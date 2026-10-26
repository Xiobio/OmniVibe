import AppKit
import Carbon
import Combine
import Foundation

struct TerminalThemePalette: Codable, Equatable, Sendable {
    struct RGB: Codable, Equatable, Sendable {
        let red: UInt16
        let green: UInt16
        let blue: UInt16

        init(red: UInt16, green: UInt16, blue: UInt16) {
            self.red = red; self.green = green; self.blue = blue
        }

        @MainActor
        init(_ color: NSColor) throws {
            // Terminal's AppleScript RGB lists use calibrated RGB components.
            guard let color = color.usingColorSpace(.genericRGB) else { throw TerminalThemeError.invalidColor }
            let values = [color.redComponent, color.greenComponent, color.blueComponent]
            guard values.allSatisfy(\.isFinite) else { throw TerminalThemeError.invalidColor }
            let channels = values.map { UInt16((min(1, max(0, $0)) * 65_535).rounded()) }
            self.init(red: channels[0], green: channels[1], blue: channels[2])
        }

        fileprivate var scriptLiteral: String { "{\(red), \(green), \(blue)}" }
    }

    let background: RGB
    let normalText: RGB
    let boldText: RGB
    let cursor: RGB

    init(background: RGB, normalText: RGB, boldText: RGB, cursor: RGB) {
        self.background = background; self.normalText = normalText; self.boldText = boldText; self.cursor = cursor
    }

    @MainActor
    init(background: NSColor, normalText: NSColor, boldText: NSColor, cursor: NSColor) throws {
        self.init(background: try RGB(background), normalText: try RGB(normalText),
                  boldText: try RGB(boldText), cursor: try RGB(cursor))
    }
}

struct TerminalProfileColors: Codable, Equatable, Sendable {
    let profileID: Int
    let colors: TerminalThemePalette
}

struct TerminalThemeReceipt: Equatable, Sendable {
    let profileCount: Int
    let backupURL: URL
    let restored: Bool
}

/// All backend methods run exclusively on the service's serial worker. This
/// interface also keeps tests from sending AppleEvents or requesting consent.
protocol TerminalThemeBackend: AnyObject {
    func sessionIdentifier() throws -> String
    func usedProfiles() throws -> [TerminalProfileColors]
    func colors(profileID: Int) throws -> TerminalThemePalette
    func setColors(_ colors: TerminalThemePalette, profileID: Int) throws
}

/// Construction reads only whether a local backup exists. Only an explicit
/// apply/restore call can contact Terminal and cause an Automation prompt.
@MainActor
final class TerminalThemeService: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var hasBackup: Bool
    let backupURL: URL
    private let worker: Worker
    private static let queue = DispatchQueue(label: "io.github.xiobio.OmniVibe.terminal-theme", qos: .userInitiated)

    init(root: URL? = nil, backend: TerminalThemeBackend? = nil) {
        let folder = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OmniVibe", isDirectory: true)
        backupURL = folder.appendingPathComponent("terminal-theme-backup.json")
        worker = Worker(backupURL: backupURL, backend: backend ?? AppleScriptTerminalThemeBackend())
        hasBackup = FileManager.default.fileExists(atPath: backupURL.path)
    }

    func apply(theme: TerminalThemePalette) async throws -> TerminalThemeReceipt {
        try await perform { try $0.apply(theme) }
    }

    func restoreLatest() async throws -> TerminalThemeReceipt {
        try await perform { try $0.restore() }
    }

    /// An explicit local archive is allowed only after Terminal starts a new
    /// process session. Process metadata inspection sends no AppleEvents.
    func archivePreviousSessionBackup() async throws -> URL {
        try await perform { try $0.archivePreviousSessionBackup() }
    }

    private func perform<T: Sendable>(_ operation: @escaping (Worker) throws -> T) async throws -> T {
        guard !isBusy else { throw TerminalThemeError.busy }
        isBusy = true
        defer {
            isBusy = false
            hasBackup = FileManager.default.fileExists(atPath: backupURL.path)
        }
        let worker = worker
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                let result = Result { try autoreleasepool { try operation(worker) } }
                continuation.resume(with: result)
            }
        }
    }

    private final class Worker: @unchecked Sendable {
        let backupURL: URL
        let backend: TerminalThemeBackend

        struct Backup: Codable {
            let version: Int
            let session: String
            var originals: [TerminalProfileColors]
            var pendingRecovery: [TerminalProfileColors]
        }

        init(backupURL: URL, backend: TerminalThemeBackend) {
            self.backupURL = backupURL; self.backend = backend
        }

        func apply(_ palette: TerminalThemePalette) throws -> TerminalThemeReceipt {
            var previous = try loadBackup()
            guard previous?.pendingRecovery.isEmpty != false else { throw TerminalThemeError.recoveryRequired }
            let session = try backend.sessionIdentifier()
            if let previous, previous.session != session { throw TerminalThemeError.sessionChanged }
            let before = try normalized(backend.usedProfiles())
            guard !before.isEmpty else { throw TerminalThemeError.noOpenWindows }
            try ensureSession(session)
            if previous == nil { previous = Backup(version: 1, session: session, originals: [], pendingRecovery: []) }
            var backup = previous!
            let known = Set(backup.originals.map(\.profileID))
            backup.originals += before.filter { !known.contains($0.profileID) }
            guard backup.originals.count <= 256 else { throw TerminalThemeError.invalidResponse }
            backup.originals.sort { $0.profileID < $1.profileID }
            backup.pendingRecovery = before
            try writeBackup(backup) // No Terminal mutation is permitted before this succeeds.
            do {
                for profile in before {
                    try ensureSession(session)
                    try backend.setColors(palette, profileID: profile.profileID)
                    try verify(palette, profileID: profile.profileID, session: session)
                }
                backup.pendingRecovery = []
                try writeBackup(backup)
                return TerminalThemeReceipt(profileCount: before.count, backupURL: backupURL, restored: false)
            } catch {
                let cause = error.localizedDescription
                var pending: [TerminalProfileColors] = []
                for profile in before {
                    do {
                        try ensureSession(session)
                        try backend.setColors(profile.colors, profileID: profile.profileID)
                        try verify(profile.colors, profileID: profile.profileID, session: session)
                    } catch { pending.append(profile) }
                }
                backup.pendingRecovery = pending
                // If updating recovery metadata also fails, the earlier atomic
                // backup still contains every before-operation color snapshot.
                try? writeBackup(backup)
                throw TerminalThemeError.applyFailed(cause, pending.count)
            }
        }

        func restore() throws -> TerminalThemeReceipt {
            guard var backup = try loadBackup() else { throw TerminalThemeError.noBackup }
            try ensureSession(backup.session)
            var pending: [TerminalProfileColors] = []
            for profile in backup.originals {
                do {
                    try ensureSession(backup.session)
                    try backend.setColors(profile.colors, profileID: profile.profileID)
                    try verify(profile.colors, profileID: profile.profileID, session: backup.session)
                } catch { pending.append(profile) }
            }
            guard pending.isEmpty else {
                backup.pendingRecovery = pending
                try? writeBackup(backup)
                throw TerminalThemeError.restoreIncomplete(pending.count)
            }
            do { try FileManager.default.removeItem(at: backupURL) }
            catch { throw TerminalThemeError.backupCleanupFailed }
            return TerminalThemeReceipt(profileCount: backup.originals.count, backupURL: backupURL, restored: true)
        }

        func archivePreviousSessionBackup() throws -> URL {
            guard let backup = try loadBackup() else { throw TerminalThemeError.noBackup }
            let current = try backend.sessionIdentifier()
            guard !current.isEmpty, current != backup.session else { throw TerminalThemeError.currentSessionArchiveForbidden }
            let archive = backupURL.deletingLastPathComponent().appendingPathComponent(
                backupURL.deletingPathExtension().lastPathComponent + ".archived-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: backupURL, to: archive)
            return archive
        }

        private func ensureSession(_ expected: String) throws {
            guard try backend.sessionIdentifier() == expected else { throw TerminalThemeError.sessionChanged }
        }

        private func verify(_ expected: TerminalThemePalette, profileID: Int, session: String) throws {
            try ensureSession(session)
            guard try backend.colors(profileID: profileID) == expected else { throw TerminalThemeError.verificationFailed }
        }

        private func normalized(_ values: [TerminalProfileColors]) throws -> [TerminalProfileColors] {
            guard values.count <= 256 else { throw TerminalThemeError.invalidResponse }
            var profiles: [Int: TerminalProfileColors] = [:]
            for profile in values {
                guard Int32(exactly: profile.profileID) != nil else { throw TerminalThemeError.invalidResponse }
                if let old = profiles[profile.profileID], old != profile { throw TerminalThemeError.invalidResponse }
                profiles[profile.profileID] = profile
            }
            return profiles.values.sorted { $0.profileID < $1.profileID }
        }

        private func loadBackup() throws -> Backup? {
            guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
            do {
                let size = try backupURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 1_048_576 else { throw TerminalThemeError.invalidBackup }
                let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: backupURL))
                guard backup.version == 1, !backup.session.isEmpty, !backup.originals.isEmpty,
                      try normalized(backup.originals).count == backup.originals.count,
                      try normalized(backup.pendingRecovery).count == backup.pendingRecovery.count,
                      Set(backup.pendingRecovery.map(\.profileID)).isSubset(of: Set(backup.originals.map(\.profileID))) else {
                    throw TerminalThemeError.invalidBackup
                }
                return backup
            } catch { throw TerminalThemeError.invalidBackup }
        }

        private func writeBackup(_ backup: Backup) throws {
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(backup)
                guard data.count <= 1_048_576 else { throw TerminalThemeError.invalidBackup }
                try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: backupURL, options: .atomic)
            } catch { throw TerminalThemeError.backupUnavailable }
        }
    }
}

/// Uses only properties published by Terminal.sdef. No profile names, tab
/// titles, contents, history, shell commands or terminal input are requested.
final class AppleScriptTerminalThemeBackend: TerminalThemeBackend {
    func sessionIdentifier() throws -> String {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").filter { !$0.isTerminated }
        guard applications.count <= 1 else { throw TerminalThemeError.ambiguousTerminalSession }
        guard let app = applications.first, let started = app.launchDate else {
            throw TerminalThemeError.terminalNotRunning
        }
        return "\(app.processIdentifier):\(started.timeIntervalSince1970)"
    }

    func usedProfiles() throws -> [TerminalProfileColors] {
        _ = try sessionIdentifier()
        return try Self.parseProfiles(execute(Self.usedProfilesScript))
    }

    func colors(profileID: Int) throws -> TerminalThemePalette {
        _ = try sessionIdentifier()
        return try Self.parsePalette(execute(Self.colorsScript(profileID: profileID)))
    }

    func setColors(_ colors: TerminalThemePalette, profileID: Int) throws {
        _ = try sessionIdentifier()
        _ = try execute(Self.setColorsScript(colors, profileID: profileID))
    }

    static let usedProfilesScript = """
    if application id "com.apple.Terminal" is not running then error number -600
    tell application id "com.apple.Terminal"
        with timeout of 30 seconds
            set profileIDs to {}
            set savedColors to {}
            repeat with terminalWindow in windows
                repeat with terminalTab in tabs of terminalWindow
                    set profileObject to current settings of terminalTab
                    set profileID to (id of profileObject) as integer
                    if profileID is not in profileIDs then
                        set end of profileIDs to profileID
                        set end of savedColors to {profileID, (background color of profileObject) as list, (normal text color of profileObject) as list, (bold text color of profileObject) as list, (cursor color of profileObject) as list}
                    end if
                end repeat
            end repeat
            return savedColors
        end timeout
    end tell
    """

    static func colorsScript(profileID: Int) throws -> String {
        let resolution = try profileResolutionScript(profileID: profileID)
        return """
        if application id "com.apple.Terminal" is not running then error number -600
        tell application id "com.apple.Terminal"
            with timeout of 30 seconds
                \(resolution)
                return {(background color of profileObject) as list, (normal text color of profileObject) as list, (bold text color of profileObject) as list, (cursor color of profileObject) as list}
            end timeout
        end tell
        """
    }

    static func setColorsScript(_ colors: TerminalThemePalette, profileID: Int) throws -> String {
        let resolution = try profileResolutionScript(profileID: profileID)
        return """
        if application id "com.apple.Terminal" is not running then error number -600
        tell application id "com.apple.Terminal"
            with timeout of 30 seconds
                \(resolution)
                set background color of profileObject to \(colors.background.scriptLiteral)
                set normal text color of profileObject to \(colors.normalText.scriptLiteral)
                set bold text color of profileObject to \(colors.boldText.scriptLiteral)
                set cursor color of profileObject to \(colors.cursor.scriptLiteral)
            end timeout
        end tell
        """
    }

    /// A tab can use a transient settings set that is absent from Terminal's
    /// global settings-set collection. Resolve live tab profiles first, using
    /// only numeric IDs, and consult saved profiles only as a fallback.
    private static func profileResolutionScript(profileID: Int) throws -> String {
        let identifier = try validatedID(profileID)
        return """
        set requestedProfileID to \(identifier)
        set profileObject to missing value
        repeat with terminalWindow in windows
            repeat with terminalTab in tabs of terminalWindow
                try
                    set candidateProfile to current settings of terminalTab
                    if ((id of candidateProfile) as integer) is requestedProfileID then
                        set profileObject to candidateProfile
                        exit repeat
                    end if
                end try
            end repeat
            if profileObject is not missing value then exit repeat
        end repeat
        if profileObject is missing value then
            repeat with candidateProfile in settings sets
                if ((id of candidateProfile) as integer) is requestedProfileID then
                    set profileObject to candidateProfile
                    exit repeat
                end if
            end repeat
        end if
        if profileObject is missing value then error number -1728
        """
    }

    private static func validatedID(_ profileID: Int) throws -> String {
        guard Int32(exactly: profileID) != nil else { throw TerminalThemeError.invalidResponse }
        return String(profileID)
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard !Thread.isMainThread else { throw TerminalThemeError.workerRequired }
        guard let script = NSAppleScript(source: source) else { throw TerminalThemeError.scriptFailed(0) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if code == -1743 { throw TerminalThemeError.automationDenied }
            if code == -600 { throw TerminalThemeError.terminalNotRunning }
            throw TerminalThemeError.scriptFailed(code)
        }
        return result
    }

    static func parseProfiles(_ descriptor: NSAppleEventDescriptor) throws -> [TerminalProfileColors] {
        guard descriptor.descriptorType == typeAEList, descriptor.numberOfItems <= 256 else {
            throw TerminalThemeError.invalidResponse
        }
        guard descriptor.numberOfItems > 0 else { return [] }
        return try (1...descriptor.numberOfItems).map { index in
            guard let row = descriptor.atIndex(index), row.descriptorType == typeAEList, row.numberOfItems == 5,
                  let id = row.atIndex(1) else { throw TerminalThemeError.invalidResponse }
            let profileID = try integer(id)
            let list = NSAppleEventDescriptor.list()
            for color in 1...4 {
                guard let value = row.atIndex(color + 1) else { throw TerminalThemeError.invalidResponse }
                list.insert(value, at: color)
            }
            return TerminalProfileColors(profileID: profileID, colors: try parsePalette(list))
        }
    }

    static func parsePalette(_ descriptor: NSAppleEventDescriptor) throws -> TerminalThemePalette {
        guard descriptor.descriptorType == typeAEList, descriptor.numberOfItems == 4 else {
            throw TerminalThemeError.invalidResponse
        }
        let colors = try (1...4).map { index -> TerminalThemePalette.RGB in
            guard let color = descriptor.atIndex(index), color.descriptorType == typeAEList,
                  color.numberOfItems == 3 else { throw TerminalThemeError.invalidResponse }
            let channels = try (1...3).map { position -> UInt16 in
                guard let component = color.atIndex(position), let value = UInt16(exactly: try integer(component)) else {
                    throw TerminalThemeError.invalidResponse
                }
                return value
            }
            return .init(red: channels[0], green: channels[1], blue: channels[2])
        }
        return TerminalThemePalette(background: colors[0], normalText: colors[1], boldText: colors[2], cursor: colors[3])
    }

    private static func integer(_ descriptor: NSAppleEventDescriptor) throws -> Int {
        guard [typeSInt16, typeSInt32, typeSInt64, typeUInt32].contains(descriptor.descriptorType),
              let text = descriptor.coerce(toDescriptorType: typeUnicodeText)?.stringValue,
              let value = Int(text), Int32(exactly: value) != nil else { throw TerminalThemeError.invalidResponse }
        return value
    }
}

enum TerminalThemeError: LocalizedError {
    case busy, invalidColor, terminalNotRunning, ambiguousTerminalSession, noOpenWindows, automationDenied, invalidResponse
    case invalidBackup, backupUnavailable, noBackup, sessionChanged, currentSessionArchiveForbidden, recoveryRequired, verificationFailed
    case workerRequired, backupCleanupFailed
    case scriptFailed(Int), applyFailed(String, Int), restoreIncomplete(Int)

    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .busy: return "Terminal 配色操作正在进行，请稍候。"
            case .invalidColor: return "主题颜色无法转换为 Terminal 支持的 RGB 颜色。"
            case .terminalNotRunning: return "请先打开 Terminal 窗口，再同步配色。"
            case .ambiguousTerminalSession: return "检测到多个 Terminal 应用实例。请先保留一个实例后重试，以免修改错误的终端。"
            case .noOpenWindows: return "没有已打开的 Terminal 窗口可同步。"
            case .automationDenied: return "未获得控制 Terminal 的自动化权限，请在系统设置中允许后重试。"
            case .invalidResponse: return "Terminal 返回的配色或配置标识无效，本次操作已停止。"
            case .invalidBackup: return "Terminal 原配色备份无法安全读取，已保留备份并停止修改。"
            case .backupUnavailable: return "无法安全保存 Terminal 原配色备份，本次操作已停止。"
            case .noBackup: return "没有可恢复的 Terminal 配色备份。"
            case .sessionChanged: return "Terminal 已重新启动，为避免配置标识复用，本次操作已停止并保留原备份。"
            case .currentSessionArchiveForbidden: return "备份仍属于当前 Terminal 会话，请先恢复原配色；当前会话的备份不能归档。"
            case .recoveryRequired: return "上次配色操作尚有待恢复项目，请先恢复原配色。"
            case .verificationFailed: return "Terminal 配色写入后的核验未通过。"
            case .workerRequired: return "Terminal 配色必须在专用后台队列执行。"
            case .backupCleanupFailed: return "原配色已恢复，但未能清理备份；备份仍保留。"
            case .scriptFailed(let code): return "Terminal 配色操作失败（系统错误 \(code)）。"
            case .applyFailed(let reason, let count):
                return count == 0 ? "同步失败，已回滚本次改动并保留原配色备份：\(reason)"
                    : "同步失败，\(count) 个配置尚待恢复；原配色备份仍保留：\(reason)"
            case .restoreIncomplete(let count): return "\(count) 个配置尚未恢复，备份仍保留，请稍后重试。"
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
