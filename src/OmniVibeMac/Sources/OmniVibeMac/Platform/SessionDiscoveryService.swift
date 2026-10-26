import Foundation
import OmniVibeCore
import SQLite3

struct DiscoveredAgentSession: Codable, Equatable, Identifiable, Sendable {
    var provider: String
    var sessionID: String
    var projectDirectory: String
    var title: String
    var transcriptPath: String
    var modifiedAt: Date
    var id: String { provider + ":" + sessionID.lowercased() }
    var providerLabel: String { provider == "codex" ? "Codex" : "Claude Code" }

    func validated() throws -> Self {
        guard AgentProvider(rawValue: provider) != nil, UUID(uuidString: sessionID) != nil,
              TaskLaunchConfiguration.validPath(projectDirectory), TaskLaunchConfiguration.validPath(transcriptPath),
              transcriptPath.hasSuffix(".jsonl"), title.utf8.count <= 2048,
              title.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              modifiedAt.timeIntervalSince1970.isFinite else { throw TaskLaunchError.invalidStore }
        return self
    }
}

struct SessionDiscoveryResult: Sendable {
    var sessions: [DiscoveredAgentSession]
    var warnings: [String]
}

struct SessionDiscoveryRoots: Sendable {
    let codex: URL
    let claude: URL
    var codexSessions: URL { codex.appendingPathComponent("sessions", isDirectory: true) }
    var claudeProjects: URL { claude.appendingPathComponent("projects", isDirectory: true) }

    init(codex: URL? = nil, claude: URL? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.codex = (codex ?? environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ??
            home.appendingPathComponent(".codex", isDirectory: true)).standardizedFileURL.resolvingSymlinksInPath()
        self.claude = (claude ?? environment["CLAUDE_CONFIG_DIR"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ??
            home.appendingPathComponent(".claude", isDirectory: true)).standardizedFileURL.resolvingSymlinksInPath()
    }

    func allows(_ file: URL, provider: String) -> Bool {
        guard provider == "codex" || provider == "claude" else { return false }
        let root = provider == "codex" ? codexSessions : claudeProjects
        let path = file.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") && file.pathExtension == "jsonl"
    }
}

/// Reads only the Codex threads metadata table, Claude's metadata index, and
/// whitelisted JSON fields. Message/prompt/tool-output strings are never decoded,
/// displayed, persisted, or used to infer a window association.
final class SessionDiscoveryService: @unchecked Sendable {
    private let roots: SessionDiscoveryRoots
    private static let queue = DispatchQueue(label: "io.github.xiobio.OmniVibe.session-discovery", qos: .utility)
    init(roots: SessionDiscoveryRoots = SessionDiscoveryRoots()) { self.roots = roots }

    func discover() async -> SessionDiscoveryResult {
        let roots = roots
        return await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: Self.discover(roots: roots)) }
        }
    }

    static func discover(roots: SessionDiscoveryRoots) -> SessionDiscoveryResult {
        var sessions: [DiscoveredAgentSession] = []
        var warnings: [String] = []
        do { sessions += try codexDatabase(roots: roots) }
        catch { warnings.append("Codex 会话索引暂不可读，将检查有限数量的本地元数据。") }
        let fileManager = FileManager.default
        let claudeDirectories = ((try? fileManager.contentsOfDirectory(at: roots.claudeProjects,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []).prefix(128)
        var files: [(URL, String)] = []
        for directory in claudeDirectories {
            guard let info = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  info.isDirectory == true, info.isSymbolicLink != true else { continue }
            let index = directory.appendingPathComponent("sessions-index.json")
            if let bytes = try? boundedData(index, limit: 1_048_576),
               let rows = try? SessionMetadataProjection.indexRows(bytes) {
                for fields in rows.prefix(256) {
                    guard fields["isSidechain"] != "true", let id = fields["sessionId"],
                          let cwd = fields["projectPath"], let path = fields["fullPath"] else { continue }
                    let file = URL(fileURLWithPath: path)
                    guard roots.allows(file, provider: "claude"), let modified = fileDate(file) else { continue }
                    if let value = make(provider: "claude", id: id, cwd: cwd,
                        title: fields["customTitle"] ?? "", file: file, modified: modified) { sessions.append(value) }
                }
            }
            let local = (try? fileManager.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])) ?? []
            files += local.filter { $0.pathExtension == "jsonl" }.prefix(256).map { ($0, "claude") }
            if files.count >= 2048 { break }
        }
        // The stable SQLite metadata covers older Codex sessions too. A bounded
        // 14-day fallback recognizes old CLI layouts without scanning all history.
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy/MM/dd"
        for days in 0..<14 {
            let day = roots.codexSessions.appendingPathComponent(formatter.string(from: Date().addingTimeInterval(-Double(days) * 86400)))
            let local = (try? fileManager.contentsOfDirectory(at: day,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])) ?? []
            files += local.filter { $0.pathExtension == "jsonl" }.prefix(128).map { ($0, "codex") }
            if files.count >= 3072 { break }
        }
        let knownPaths = Set(sessions.map(\.transcriptPath))
        let newest = files.filter { !knownPaths.contains($0.0.path) }.compactMap { file, provider -> (URL, String, Date)? in
            guard roots.allows(file, provider: provider), let date = fileDate(file) else { return nil }
            return (file, provider, date)
        }.sorted { $0.2 > $1.2 }.prefix(128)
        for (file, provider, modified) in newest {
            if let session = inspectHeader(file, provider: provider, modified: modified) { sessions.append(session) }
        }
        var unique: [DiscoveredAgentSession] = []
        for values in Dictionary(grouping: sessions, by: \.id).values {
            let identities = Set(values.map { $0.projectDirectory + "\u{0}" + $0.transcriptPath })
            guard identities.count == 1 else {
                warnings.append("同一会话 ID 存在多个项目或记录文件，已跳过，避免误关联。")
                continue
            }
            if let value = values.max(by: { $0.modifiedAt < $1.modifiedAt }) { unique.append(value) }
        }
        return SessionDiscoveryResult(sessions: Array(unique.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(256)),
            warnings: Array(Set(warnings)).sorted())
    }

    static func inspectHeader(_ file: URL, provider: String, modified: Date) -> DiscoveredAgentSession? {
        guard let bytes = try? boundedPrefix(file, limit: 262_144) else { return nil }
        var id = "", cwd = "", title = ""
        for line in bytes.split(separator: 10).prefix(24) {
            guard let fields = try? SessionMetadataProjection.fields(Data(line)) else { continue }
            if provider == "codex" {
                if fields["type"] == "session_meta" {
                    guard fields["payload.source"] != "<object>" else { return nil }
                    id = fields["payload.id"] ?? ""; cwd = fields["payload.cwd"] ?? ""; title = fields["payload.title"] ?? ""
                    break
                }
            } else {
                if fields["isSidechain"] == "true" { return nil }
                if id.isEmpty { id = fields["sessionId"] ?? "" }
                if cwd.isEmpty { cwd = fields["cwd"] ?? "" }
                if title.isEmpty { title = fields["customTitle"] ?? fields["aiTitle"] ?? "" }
                if !id.isEmpty && !cwd.isEmpty { break }
            }
        }
        guard UUID(uuidString: id) != nil,
              let filenameID = UUID(uuidString: String(file.deletingPathExtension().lastPathComponent.suffix(36))),
              filenameID == UUID(uuidString: id) else { return nil }
        return make(provider: provider, id: id, cwd: cwd, title: title, file: file, modified: modified)
    }

    static func fileDate(_ file: URL) -> Date? {
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return values.contentModificationDate
    }

    private static func make(provider: String, id: String, cwd: String, title: String, file: URL, modified: Date) -> DiscoveredAgentSession? {
        let cleanTitle = String(title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(160))
        let fallback = URL(fileURLWithPath: cwd).lastPathComponent + " · " + String(id.prefix(8))
        let value = DiscoveredAgentSession(provider: provider, sessionID: id, projectDirectory: cwd,
            title: cleanTitle.isEmpty ? fallback : cleanTitle, transcriptPath: file.standardizedFileURL.path, modifiedAt: modified)
        return try? value.validated()
    }

    private static func boundedData(_ file: URL, limit: Int) throws -> Data {
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= limit else {
            throw TaskLaunchError.invalidStore
        }
        return try Data(contentsOf: file)
    }

    private static func boundedPrefix(_ file: URL, limit: Int) throws -> Data {
        guard fileDate(file) != nil else { throw TaskLaunchError.invalidStore }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        return try handle.read(upToCount: limit) ?? Data()
    }

    private static func codexDatabase(roots: SessionDiscoveryRoots) throws -> [DiscoveredAgentSession] {
        let paths = try FileManager.default.contentsOfDirectory(at: roots.codex,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" && fileDate($0) != nil }
            .sorted { (fileDate($0) ?? .distantPast) > (fileDate($1) ?? .distantPast) }.prefix(3)
        var result: [DiscoveredAgentSession] = []
        for path in paths {
            var db: OpaquePointer?
            guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db else {
                if let db { sqlite3_close(db) }; continue
            }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 100)
            sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 65_536)
            sqlite3_exec(db, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", nil, nil, nil)
            var schema: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &schema, nil) == SQLITE_OK else { continue }
            var columns = Set<String>()
            while sqlite3_step(schema) == SQLITE_ROW {
                if let value = sqlite3_column_text(schema, 1) { columns.insert(String(cString: value)) }
            }
            sqlite3_finalize(schema)
            guard ["id", "cwd", "rollout_path"].allSatisfy(columns.contains) else { continue }
            let titleColumn = columns.contains("title") ? "title" : "''"
            let sourceColumn = columns.contains("source") ? "source" : "''"
            let updatedColumn = columns.contains("updated_at") ? "updated_at" : "0"
            let filter = columns.contains("archived") ? "WHERE archived=0" : ""
            var statement: OpaquePointer?
            let sql = "SELECT id,cwd,rollout_path,\(titleColumn),\(sourceColumn) FROM threads \(filter) ORDER BY \(updatedColumn) DESC LIMIT 512"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            let budget = SessionDiscoverySQLiteBudget()
            sqlite3_progress_handler(db, 1000, { pointer in
                guard let pointer else { return 1 }
                return Unmanaged<SessionDiscoverySQLiteBudget>.fromOpaque(pointer).takeUnretainedValue().expired ? 1 : 0
            }, Unmanaged.passUnretained(budget).toOpaque())
            defer { sqlite3_progress_handler(db, 0, nil, nil) }
            while sqlite3_step(statement) == SQLITE_ROW {
                func string(_ index: Int32) -> String { sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" }
                let id = string(0), cwd = string(1), file = URL(fileURLWithPath: string(2))
                let source = string(4).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.hasPrefix("{"), source != "subagent" else { continue }
                guard roots.allows(file, provider: "codex"), let modified = fileDate(file) else { continue }
                if let value = make(provider: "codex", id: id, cwd: cwd, title: string(3), file: file, modified: modified) { result.append(value) }
            }
            if !result.isEmpty { break }
        }
        return result
    }
}

private final class SessionDiscoverySQLiteBudget {
    let started = ProcessInfo.processInfo.systemUptime
    var expired: Bool { ProcessInfo.processInfo.systemUptime - started > 0.3 }
}

struct SessionDiscoveryAssociation: Codable, Equatable, Identifiable, Sendable {
    var taskID: UUID
    var windowID: UUID
    var session: DiscoveredAgentSession
    var linkedAt: Date
    var id: UUID { taskID }
}

struct SessionDiscoveryAssociationStore {
    let root: URL
    var fileURL: URL { root.appendingPathComponent("session-associations.json") }
    init(root: URL = WorkspaceStore().root) { self.root = root }

    func load() throws -> [SessionDiscoveryAssociation] {
        let values: [SessionDiscoveryAssociation] = try TaskLaunchMetadataFile.load(fileURL)
        guard values.count <= 64, Set(values.map(\.taskID)).count == values.count,
              Set(values.map { $0.session.id }).count == values.count else { throw TaskLaunchError.invalidStore }
        for value in values { _ = try value.session.validated(); guard value.linkedAt.timeIntervalSince1970.isFinite else { throw TaskLaunchError.invalidStore } }
        return values
    }

    func bind(taskID: UUID, windowID: UUID, session: DiscoveredAgentSession) throws {
        _ = try session.validated()
        var values = try load().filter { $0.taskID != taskID }
        guard !values.contains(where: { $0.session.id == session.id }) else {
            throw IntegrationError("这个 CLI 会话已关联到其他任务，请先解除原关联。")
        }
        values.append(SessionDiscoveryAssociation(taskID: taskID, windowID: windowID, session: session, linkedAt: Date()))
        guard values.count <= 64 else { throw TaskLaunchError.invalidStore }
        try TaskLaunchMetadataFile.save(values, to: fileURL)
    }
    func remove(_ taskID: UUID) throws { try TaskLaunchMetadataFile.save(load().filter { $0.taskID != taskID }, to: fileURL) }
    func transfer(from oldID: UUID, to newID: UUID, windowID: UUID) throws {
        guard oldID != newID, let value = try load().first(where: { $0.taskID == oldID }) else { return }
        var values = try load().filter { $0.taskID != oldID && $0.taskID != newID }
        values.append(SessionDiscoveryAssociation(taskID: newID, windowID: windowID, session: value.session, linkedAt: Date()))
        try TaskLaunchMetadataFile.save(values, to: fileURL)
    }
}

struct SessionDiscoveryUpdate: Sendable {
    let taskID: UUID
    let windowID: UUID
    let event: AgentStatusEvent
}

final class SessionDiscoveryObserver: @unchecked Sendable {
    private let roots: SessionDiscoveryRoots
    private let queue = DispatchQueue(label: "io.github.xiobio.OmniVibe.session-observer", qos: .utility)
    private var cursors: [String: Cursor] = [:]
    private struct Cursor { var identity: String; var offset: UInt64; var skippingLongLine: Bool; var modifiedAt: Date }
    init(roots: SessionDiscoveryRoots = SessionDiscoveryRoots()) { self.roots = roots }

    func poll(_ associations: [SessionDiscoveryAssociation]) async -> [SessionDiscoveryUpdate] {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.read(associations)) }
        }
    }

    private func read(_ associations: [SessionDiscoveryAssociation]) -> [SessionDiscoveryUpdate] {
        var updates: [SessionDiscoveryUpdate] = []
        var active = Set<String>()
        for association in associations.prefix(9) {
            let session = association.session
            let file = URL(fileURLWithPath: session.transcriptPath)
            let key = association.taskID.uuidString + ":" + association.windowID.uuidString + ":" + session.id + ":" + file.path
            active.insert(key)
            guard roots.allows(file, provider: session.provider), let modified = SessionDiscoveryService.fileDate(file),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let size = (attributes[.size] as? NSNumber)?.uint64Value,
                  let inode = attributes[.systemFileNumber] as? NSNumber,
                  let device = attributes[.systemNumber] as? NSNumber else { continue }
            let identity = device.stringValue + ":" + inode.stringValue
            let cursor = cursors[key]
            if cursor == nil || cursor?.identity != identity || (cursor?.offset ?? 0) > size ||
                (cursor?.offset == size && cursor?.modifiedAt != modified) {
                // Explicitly validate the selected exact ID/file again. The
                // first observation anchors EOF, never replays an old reply.
                guard let header = SessionDiscoveryService.inspectHeader(file, provider: session.provider, modified: modified),
                      header.sessionID.caseInsensitiveCompare(session.sessionID) == .orderedSame,
                      header.projectDirectory == session.projectDirectory else { cursors.removeValue(forKey: key); continue }
                cursors[key] = Cursor(identity: identity, offset: size, skippingLongLine: false, modifiedAt: modified)
                continue
            }
            guard var current = cursor, current.offset < size,
                  let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: current.offset)
                let bytes = try handle.read(upToCount: 131_072) ?? Data()
                var start = bytes.startIndex
                if current.skippingLongLine {
                    if let end = bytes.firstIndex(of: 10) { start = bytes.index(after: end); current.skippingLongLine = false }
                    else { current.offset += UInt64(bytes.count); current.modifiedAt = modified; cursors[key] = current; continue }
                }
                var consumed = start
                var latest: AgentStatusEvent?
                while start < bytes.endIndex, let end = bytes[start...].firstIndex(of: 10) {
                    if let event = Self.parse(provider: session.provider, taskID: association.taskID, sessionID: session.sessionID,
                        data: Data(bytes[start..<end])), latest == nil || event.at > latest!.at { latest = event }
                    start = bytes.index(after: end); consumed = start
                }
                if consumed == bytes.startIndex && bytes.count == 131_072 {
                    // Skip oversized records without retaining prompt/tool text
                    // across polls. Continue at its next newline on a later poll.
                    current.offset += UInt64(bytes.count); current.skippingLongLine = true
                } else { current.offset += UInt64(consumed - bytes.startIndex) }
                current.modifiedAt = modified; cursors[key] = current
                if let latest { updates.append(SessionDiscoveryUpdate(taskID: association.taskID, windowID: association.windowID, event: latest)) }
            } catch { continue }
        }
        cursors = cursors.filter { active.contains($0.key) }
        return updates
    }

    static func parse(provider: String, taskID: UUID, sessionID: String, data: Data) -> AgentStatusEvent? {
        guard let fields = try? SessionMetadataProjection.fields(data), fields["isSidechain"] != "true",
              let timestamp = fields["timestamp"], let date = SessionDiscoveryDate.parse(timestamp) else { return nil }
        if let declared = fields["sessionId"], !declared.isEmpty,
           declared.caseInsensitiveCompare(sessionID) != .orderedSame { return nil }
        let type = fields["type"] ?? ""
        let state: AgentState?
        if provider == "codex" {
            let event = fields["payload.type"] ?? ""
            if type == "event_msg" {
                switch event {
                case "task_started": state = .running
                case "task_complete", "turn_complete": state = .ready
                case "task_failed": state = .error
                case "turn_aborted": state = .unknown
                default: state = nil
                }
            } else { state = type == "response_item" && ["function_call_output", "custom_tool_call_output"].contains(event) ? .running : nil }
        } else if provider == "claude" {
            if fields["isApiErrorMessage"] == "true" { state = .error }
            else if type == "system" && fields["subtype"] == "turn_duration" { state = .ready }
            else if type == "assistant" {
                if (fields["message.content.*.name"] ?? "").split(separator: "\u{1F}").contains("AskUserQuestion") { state = .waiting }
                else if ["end_turn", "max_tokens"].contains(fields["message.stop_reason"] ?? "") { state = .ready }
                else { state = fields["message.stop_reason"] == "tool_use" ? .running : nil }
            } else { state = nil }
        } else { state = nil }
        guard let state else { return nil }
        let message: String
        switch state {
        case .running: message = "AI 正在执行"
        case .ready: message = "本轮回复已结束，请查看结果"
        case .waiting: message = "需要你的输入"
        case .error: message = "本轮执行发生错误，请查看终端"
        case .unknown: message = "本轮已中断"
        }
        return AgentStatusEvent(taskID: taskID, state: state, message: message, at: date,
            provider: provider, sessionID: sessionID, eventName: "Transcript")
    }
}

enum SessionDiscoveryDate {
    static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// A bounded, field-projecting JSON scanner. Unknown values are skipped as
/// bytes; string contents in message, prompt, tool arguments/results, history,
/// firstPrompt and summary are not decoded into Strings.
enum SessionMetadataProjection {
    private static let wanted: Set<String> = ["type", "timestamp", "sessionId", "cwd", "isSidechain", "isMeta",
        "isApiErrorMessage", "customTitle", "aiTitle", "subtype", "payload.id", "payload.cwd", "payload.title",
        "payload.type", "payload.source", "message.stop_reason", "message.content.*.type", "message.content.*.name"]
    private static let indexWanted: Set<String> = ["sessionId", "projectPath", "fullPath", "customTitle", "isSidechain"]

    static func fields(_ bytes: Data) throws -> [String: String] {
        var scanner = Scanner(bytes: Array(bytes), wanted: wanted)
        guard bytes.count <= 262_144 else { throw TaskLaunchError.invalidStore }
        try scanner.object(path: "", depth: 0)
        scanner.space(); guard scanner.position == scanner.bytes.count else { throw TaskLaunchError.invalidStore }
        return scanner.values
    }
    static func indexRows(_ bytes: Data) throws -> [[String: String]] {
        guard bytes.count <= 1_048_576 else { throw TaskLaunchError.invalidStore }
        var scanner = Scanner(bytes: Array(bytes), wanted: indexWanted)
        return try scanner.index()
    }

    private struct Scanner {
        let bytes: [UInt8]
        let wanted: Set<String>
        var position = 0
        var values: [String: String] = [:]
        var captured = 0
        mutating func space() { while position < bytes.count && [9, 10, 13, 32].contains(bytes[position]) { position += 1 } }
        mutating func take(_ byte: UInt8) throws { space(); guard position < bytes.count, bytes[position] == byte else { throw TaskLaunchError.invalidStore }; position += 1 }
        mutating func string(decode: Bool) throws -> String? {
            space(); let start = position
            guard position < bytes.count, bytes[position] == 34 else { throw TaskLaunchError.invalidStore }; position += 1
            while position < bytes.count {
                let value = bytes[position]; position += 1
                if value == 34 {
                    if !decode { return nil }
                    guard position - start <= 8192 else { throw TaskLaunchError.invalidStore }
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<position]))
                }
                guard value >= 32 else { throw TaskLaunchError.invalidStore }
                if value == 92 {
                    guard position < bytes.count else { throw TaskLaunchError.invalidStore }
                    let escape = bytes[position]; position += 1
                    if escape == 117 {
                        for _ in 0..<4 {
                            guard position < bytes.count, (48...57).contains(bytes[position]) || (65...70).contains(bytes[position]) || (97...102).contains(bytes[position]) else { throw TaskLaunchError.invalidStore }
                            position += 1
                        }
                    } else if ![34, 47, 92, 98, 102, 110, 114, 116].contains(escape) { throw TaskLaunchError.invalidStore }
                }
            }
            throw TaskLaunchError.invalidStore
        }
        mutating func object(path: String, depth: Int) throws {
            guard depth <= 48 else { throw TaskLaunchError.invalidStore }
            try take(123); space()
            if position < bytes.count, bytes[position] == 125 { position += 1; return }
            while true {
                guard let key = try string(decode: true), key.utf8.count <= 128 else { throw TaskLaunchError.invalidStore }
                try take(58)
                let next = path.isEmpty ? key : path + "." + key
                let relevant = wanted.contains(next) || wanted.contains(where: { $0.hasPrefix(next + ".") })
                try value(path: next, relevant: relevant, depth: depth + 1)
                space(); guard position < bytes.count else { throw TaskLaunchError.invalidStore }
                if bytes[position] == 125 { position += 1; return }
                try take(44)
            }
        }
        mutating func value(path: String, relevant: Bool, depth: Int) throws {
            guard depth <= 48 else { throw TaskLaunchError.invalidStore }
            space(); guard position < bytes.count else { throw TaskLaunchError.invalidStore }
            if bytes[position] == 34 {
                if let text = try string(decode: relevant && wanted.contains(path)) { capture(text, path: path) }
            } else if bytes[position] == 123 {
                if relevant {
                    if wanted.contains(path) { capture("<object>", path: path) }
                    try object(path: path, depth: depth)
                } else { try skip(depth: depth) }
            } else if bytes[position] == 91 {
                if relevant {
                    try take(91); space()
                    if position < bytes.count, bytes[position] == 93 { position += 1; return }
                    while true {
                        try value(path: path + ".*", relevant: true, depth: depth + 1)
                        space(); guard position < bytes.count else { throw TaskLaunchError.invalidStore }
                        if bytes[position] == 93 { position += 1; break }; try take(44)
                    }
                } else { try skip(depth: depth) }
            } else {
                let start = position; try primitive()
                if relevant && wanted.contains(path) {
                    let scalar = String(decoding: bytes[start..<position], as: UTF8.self)
                    if scalar == "true" || scalar == "false" { capture(scalar, path: path) }
                }
            }
        }
        mutating func capture(_ value: String, path: String) {
            guard captured < 256, value.utf8.count <= 4096 else { return }
            captured += 1
            if path.contains(".*."), let previous = values[path] { values[path] = previous + "\u{1F}" + value }
            else { values[path] = value }
        }
        mutating func skip(depth: Int) throws {
            guard depth <= 48 else { throw TaskLaunchError.invalidStore }
            space(); guard position < bytes.count else { throw TaskLaunchError.invalidStore }
            switch bytes[position] {
            case 34: _ = try string(decode: false)
            case 123:
                try take(123); space(); if position < bytes.count, bytes[position] == 125 { position += 1; return }
                while true {
                    _ = try string(decode: false); try take(58); try skip(depth: depth + 1)
                    space(); guard position < bytes.count else { throw TaskLaunchError.invalidStore }
                    if bytes[position] == 125 { position += 1; return }; try take(44)
                }
            case 91:
                try take(91); space(); if position < bytes.count, bytes[position] == 93 { position += 1; return }
                while true {
                    try skip(depth: depth + 1); space(); guard position < bytes.count else { throw TaskLaunchError.invalidStore }
                    if bytes[position] == 93 { position += 1; return }; try take(44)
                }
            default: try primitive()
            }
        }
        mutating func primitive() throws {
            let start = position
            while position < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[position]) { position += 1 }
            guard position > start else { throw TaskLaunchError.invalidStore }
            let token = bytes[start..<position]
            if token.elementsEqual(Array("true".utf8)) || token.elementsEqual(Array("false".utf8)) || token.elementsEqual(Array("null".utf8)) { return }
            guard token.count <= 128, (try? JSONDecoder().decode(Double.self, from: Data(token))) != nil else { throw TaskLaunchError.invalidStore }
        }
        mutating func index() throws -> [[String: String]] {
            try take(123); var rows: [[String: String]] = []; space()
            if position < bytes.count, bytes[position] == 125 {
                position += 1; space(); guard position == bytes.count else { throw TaskLaunchError.invalidStore }; return []
            }
            while true {
                let key = try string(decode: true); try take(58)
                if key == "entries" {
                    try take(91); space()
                    if position < bytes.count, bytes[position] == 93 { position += 1 }
                    else {
                        while true {
                            values = [:]; captured = 0; try object(path: "", depth: 1)
                            if rows.count < 512 { rows.append(values) }
                            space(); guard position < bytes.count else { throw TaskLaunchError.invalidStore }
                            if bytes[position] == 93 { position += 1; break }; try take(44)
                        }
                    }
                } else { try skip(depth: 1) }
                space(); guard position < bytes.count else { throw TaskLaunchError.invalidStore }
                if bytes[position] == 125 { position += 1; break }; try take(44)
            }
            space(); guard position == bytes.count else { throw TaskLaunchError.invalidStore }
            return rows
        }
    }
}
