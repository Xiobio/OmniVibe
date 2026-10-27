import CryptoKit
import Foundation

struct ClaudeThemeExportReceipt: Equatable, Sendable {
    let themeURL: URL
    let backupURL: URL
    let requiresInitialRestart: Bool
    let restored: Bool
}

/// Writes only the documented custom theme file. It never reads conversations,
/// changes Claude's selected theme/settings, or launches Claude Code.
final class ClaudeThemeExporter: @unchecked Sendable {
    struct ThemeDocument: Codable, Equatable, Sendable {
        let name: String
        let base: String
        let overrides: [String: String]
    }

    private struct Backup: Codable {
        let version: Int
        let destination: URL
        let original: Data?
        var allowedHashes: [String]
        var allowsMissing: Bool
    }
    let themeURL: URL
    let backupURL: URL
    private let files = FileManager.default
    private let operationLock = NSLock()

    init(root: URL? = nil, configurationDirectory: URL? = nil,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let support = root ?? files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OmniVibe", isDirectory: true)
        backupURL = support.appendingPathComponent("claude-theme-backup.json")
        let directory: URL
        if let configurationDirectory { directory = configurationDirectory }
        else if let value = environment["CLAUDE_CONFIG_DIR"], !value.isEmpty, value.hasPrefix("/") {
            directory = URL(fileURLWithPath: value, isDirectory: true)
        } else { directory = home.appendingPathComponent(".claude", isDirectory: true) }
        themeURL = directory.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent("themes/omnivibe.json")
    }

    var hasBackup: Bool { files.fileExists(atPath: backupURL.path) }

    static func document(for theme: TerminalThemeCatalog.Theme) throws -> ThemeDocument {
        func rgb(_ key: String) throws -> [Int] {
            guard let color = theme.scheme[key], color.count == 7, color.first == "#",
                  let number = UInt32(color.dropFirst(), radix: 16) else { throw ClaudeThemeExportError.invalidTheme }
            return [Int((number >> 16) & 255), Int((number >> 8) & 255), Int(number & 255)]
        }
        let background = try rgb("background"), cursor = try rgb("cursorColor"), foreground = try rgb("foreground")
        _ = try rgb("selectionBackground")
        func mix(_ tint: [Int], _ amount: Double) -> String {
            "#" + zip(background, tint).map { base, color in
                String(format: "%02X", Int((Double(base) + Double(color - base) * amount).rounded(.toNearestOrEven)))
            }.joined()
        }
        let luminance = (0.2126 * Double(background[0]) + 0.7152 * Double(background[1]) + 0.0722 * Double(background[2])) / 255
        return ThemeDocument(name: "OmniVibe", base: luminance < 0.5 ? "dark" : "light", overrides: [
            "userMessageBackground": mix(cursor, 0.12),
            "userMessageBackgroundHover": mix(cursor, 0.18),
            "bashMessageBackgroundColor": mix(foreground, 0.10),
            "memoryBackgroundColor": mix(cursor, 0.12),
            "selectionBg": theme.scheme["selectionBackground"]!.uppercased()
        ])
    }

    /// An explicit UI action opts into this path. Repeated theme changes retain
    /// the first original and stop if a user has edited the generated file.
    func export(theme: TerminalThemeCatalog.Theme) throws -> ClaudeThemeExportReceipt {
        operationLock.lock(); defer { operationLock.unlock() }
        let document = try Self.document(for: theme)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = try encoder.encode(document)
        let current = try readOptional(themeURL)
        var state = try loadBackup() ?? Backup(version: 1, destination: themeURL, original: current,
            allowedHashes: current.map { [Self.digest($0)] } ?? [], allowsMissing: current == nil)
        try validateCurrent(state, data: current)
        let existedDirectory = files.fileExists(atPath: themeURL.deletingLastPathComponent().path)
        state.allowedHashes = Array(Set(state.allowedHashes + [Self.digest(output)]))
        try writeBackup(state)
        try validateCurrent(state, data: readOptional(themeURL))
        try files.createDirectory(at: themeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rejectSymbolicLink(themeURL)
        try output.write(to: themeURL, options: .atomic)
        guard try readOptional(themeURL) == output else { throw ClaudeThemeExportError.verificationFailed }
        state.allowedHashes = [Self.digest(output)]; state.allowsMissing = false
        try writeBackup(state)
        return ClaudeThemeExportReceipt(themeURL: themeURL, backupURL: backupURL,
            requiresInitialRestart: !existedDirectory, restored: false)
    }

    func restoreLatest() throws -> ClaudeThemeExportReceipt {
        operationLock.lock(); defer { operationLock.unlock() }
        guard var state = try loadBackup() else { throw ClaudeThemeExportError.noBackup }
        try validateCurrent(state, data: readOptional(themeURL))
        if let original = state.original { state.allowedHashes = Array(Set(state.allowedHashes + [Self.digest(original)])) }
        else { state.allowsMissing = true }
        try writeBackup(state)
        try validateCurrent(state, data: readOptional(themeURL))
        if let original = state.original {
            try rejectSymbolicLink(themeURL)
            try original.write(to: themeURL, options: .atomic)
        } else if files.fileExists(atPath: themeURL.path) { try files.removeItem(at: themeURL) }
        guard try readOptional(themeURL) == state.original else { throw ClaudeThemeExportError.verificationFailed }
        do { try files.removeItem(at: backupURL) }
        catch { throw ClaudeThemeExportError.backupCleanupFailed }
        return ClaudeThemeExportReceipt(themeURL: themeURL, backupURL: backupURL, requiresInitialRestart: false, restored: true)
    }

    private func loadBackup() throws -> Backup? {
        guard let data = try readOptional(backupURL, maximum: 2 * 1_048_576) else { return nil }
        do {
            let state = try JSONDecoder().decode(Backup.self, from: data)
            guard state.version == 1, state.destination == themeURL, (state.original?.count ?? 0) <= 1_048_576,
                  state.allowedHashes.count <= 256, state.allowedHashes.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else {
                throw ClaudeThemeExportError.invalidBackup
            }
            return state
        } catch { throw ClaudeThemeExportError.invalidBackup }
    }

    private func writeBackup(_ state: Backup) throws {
        do {
            try files.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try rejectSymbolicLink(backupURL)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: backupURL, options: .atomic)
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            guard try readOptional(backupURL, maximum: 2 * 1_048_576) == data else { throw ClaudeThemeExportError.backupUnavailable }
        } catch { throw ClaudeThemeExportError.backupUnavailable }
    }

    private func validateCurrent(_ state: Backup, data: Data?) throws {
        if let data {
            guard state.allowedHashes.contains(Self.digest(data)) else { throw ClaudeThemeExportError.externalChange }
        } else if !state.allowsMissing { throw ClaudeThemeExportError.externalChange }
    }

    private func readOptional(_ url: URL, maximum: Int = 1_048_576) throws -> Data? {
        try rejectSymbolicLink(url)
        guard files.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= maximum else { throw ClaudeThemeExportError.invalidFile }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw ClaudeThemeExportError.invalidFile }
        return data
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        if let value = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), value.isSymbolicLink == true { throw ClaudeThemeExportError.invalidFile }
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

enum ClaudeThemeExportError: LocalizedError {
    case invalidTheme, invalidFile, invalidBackup, backupUnavailable, noBackup, externalChange, verificationFailed, backupCleanupFailed
    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .invalidTheme: return "当前主题缺少有效的 Claude 配色，尚未写入文件。"
            case .invalidFile: return "Claude 主题目标不是可安全处理的普通文件，已停止写入。"
            case .invalidBackup: return "Claude 主题备份无法安全读取，原文件已保留。"
            case .backupUnavailable: return "无法安全保存 Claude 原主题备份，已停止写入。"
            case .noBackup: return "没有可恢复的 Claude 主题备份。"
            case .externalChange: return "Claude 主题文件已被其他程序或用户修改。为保留修改，本次不会覆盖。"
            case .verificationFailed: return "Claude 主题写后核验未通过，恢复备份仍保留。"
            case .backupCleanupFailed: return "Claude 原主题已恢复，但备份未能清理，文件仍保留。"
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
