import AppKit
import Darwin
import Foundation
import OmniVibeCore

enum TaskLaunchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case terminal, codex, claude
    var id: String { rawValue }
    var label: String { self == .terminal ? "Terminal" : self == .codex ? "Codex" : "Claude Code" }
    var provider: AgentProvider? { AgentProvider(rawValue: rawValue) }
}

struct TaskLaunchConfiguration: Codable, Equatable, Sendable {
    var mode: TaskLaunchMode
    var projectDirectory: String
    var executablePath: String
    var resumeSessionID: String

    init(mode: TaskLaunchMode = .codex, projectDirectory: String = "", executablePath: String = "", resumeSessionID: String = "") {
        self.mode = mode; self.projectDirectory = projectDirectory
        self.executablePath = executablePath; self.resumeSessionID = resumeSessionID
    }

    func validated(checkFiles: Bool = true) throws -> Self {
        guard Self.validPath(projectDirectory), Self.validPath(executablePath),
              resumeSessionID.isEmpty || UUID(uuidString: resumeSessionID) != nil,
              mode != .terminal || resumeSessionID.isEmpty else { throw TaskLaunchError.invalidConfiguration }
        if checkFiles {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: projectDirectory, isDirectory: &directory), directory.boolValue else {
                throw TaskLaunchError.missingProject
            }
            guard FileManager.default.isExecutableFile(atPath: executablePath) else { throw TaskLaunchError.missingExecutable }
        }
        return self
    }

    static func validPath(_ value: String) -> Bool {
        value.hasPrefix("/") && value.utf8.count <= 4096 &&
        value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    /// Resolution only inspects executable files; it does not run a shell, CLI,
    /// login profile, `which`, or a version command while opening settings.
    static func defaultExecutable(for mode: TaskLaunchMode, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                  environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if mode == .terminal { return "/bin/zsh" }
        let candidates = (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(mode.rawValue).path } +
            [home.appendingPathComponent(".local/bin/" + mode.rawValue).path,
             "/opt/homebrew/bin/" + mode.rawValue, "/usr/local/bin/" + mode.rawValue]
        return candidates.first { Self.validPath($0) && FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }
}

struct TaskLaunchRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var configuration: TaskLaunchConfiguration
    var updatedAt: Date
}

struct TaskLaunchRecordStore {
    let root: URL
    var fileURL: URL { root.appendingPathComponent("task-launches.json") }
    var lockURL: URL { root.appendingPathComponent(".task-launches.lock") }

    init(root: URL = WorkspaceStore().root) { self.root = root }

    func load() throws -> [TaskLaunchRecord] {
        let records: [TaskLaunchRecord] = try TaskLaunchMetadataFile.load(fileURL)
        guard records.count <= 64, Set(records.map(\.id)).count == records.count else { throw TaskLaunchError.invalidStore }
        for record in records {
            _ = try record.configuration.validated(checkFiles: false)
            guard record.updatedAt.timeIntervalSince1970.isFinite else { throw TaskLaunchError.invalidStore }
        }
        return records
    }

    func record(for taskID: UUID) throws -> TaskLaunchRecord? { try load().first { $0.id == taskID } }

    func save(_ configuration: TaskLaunchConfiguration, for taskID: UUID, at date: Date = Date()) throws {
        _ = try configuration.validated(checkFiles: false)
        guard date.timeIntervalSince1970.isFinite else { throw TaskLaunchError.invalidStore }
        try transaction { records in
            records.removeAll { $0.id == taskID }
            records.append(TaskLaunchRecord(id: taskID, configuration: configuration, updatedAt: date))
            return true
        }
    }

    func updateSession(taskID: UUID, provider: String, sessionID: String) throws {
        guard UUID(uuidString: sessionID) != nil else { return }
        try transaction { records in
            guard let index = records.firstIndex(where: { $0.id == taskID }),
                  records[index].configuration.mode.rawValue == provider else { return false }
            records[index].configuration.resumeSessionID = sessionID
            records[index].updatedAt = Date()
            return true
        }
    }

    func transfer(from oldTaskID: UUID, to newTaskID: UUID) throws {
        guard oldTaskID != newTaskID else { return }
        try transaction { records in
            guard let original = records.first(where: { $0.id == oldTaskID }) else { return false }
            records.removeAll { $0.id == newTaskID }
            records.append(TaskLaunchRecord(id: newTaskID, configuration: original.configuration, updatedAt: Date()))
            return true
        }
    }

    func remove(_ taskID: UUID) throws {
        try transaction { records in
            records.removeAll { $0.id == taskID }
            return true
        }
    }

    /// The CLI and GUI are separate processes. Atomic replacement protects
    /// readers, while this stable sidecar lock protects the entire read/modify/
    /// write transaction. Never lock the JSON inode itself: replacement would
    /// leave later writers locking a different inode.
    private func transaction(_ change: (inout [TaskLaunchRecord]) throws -> Bool) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw TaskLaunchError.invalidStore }
        defer { Darwin.close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              information.st_uid == geteuid(), information.st_mode & 0o077 == 0 else {
            throw TaskLaunchError.invalidStore
        }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw TaskLaunchError.invalidStore }
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        var records = try load()
        guard try change(&records) else { return }
        records.sort { $0.updatedAt > $1.updatedAt }
        try TaskLaunchMetadataFile.save(Array(records.prefix(64)), to: fileURL)
    }
}

/// Stores only project/executable/session metadata. A damaged or unreadable
/// existing file is never silently replaced with an empty list.
enum TaskLaunchMetadataFile {
    static func load<T: Decodable>(_ url: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 1_048_576 else { throw TaskLaunchError.invalidStore }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(TaskLaunchMetadataEnvelope<T>.self, from: Data(contentsOf: url))
        guard file.version == 1 else { throw TaskLaunchError.invalidStore }
        return file.records
    }

    static func save<T: Encodable>(_ records: [T], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw TaskLaunchError.invalidStore }
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let bytes = try encoder.encode(TaskLaunchMetadataWritableEnvelope(version: 1, records: records))
        guard bytes.count <= 1_048_576 else { throw TaskLaunchError.invalidStore }
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

}

private struct TaskLaunchMetadataEnvelope<T: Decodable>: Decodable { let version: Int; let records: [T] }
private struct TaskLaunchMetadataWritableEnvelope<T: Encodable>: Encodable { let version: Int; let records: [T] }

enum TaskLaunchError: LocalizedError {
    case invalidConfiguration, missingProject, missingExecutable, invalidStore
    case terminalAmbiguous, terminalUnavailable, terminalResponse, windowNotIdentified, expiredWindow
    case bindingNotSaved, terminalBusy, launchRequestInvalid, launchRequestUsed, wrongTerminal
    case automation(String)

    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .invalidConfiguration: return "启动配置无效。请选择绝对项目路径、可执行文件和确切的会话 UUID。"
            case .missingProject: return "项目目录不存在或不可访问，请重新选择。"
            case .missingExecutable: return "CLI 可执行文件不存在或不可执行，请重新选择。"
            case .invalidStore: return "任务启动记录无法安全读取，本次保留原文件。"
            case .terminalAmbiguous: return "发现多个 Terminal 实例，无法确认接收启动请求的实例。"
            case .terminalUnavailable: return "Terminal 未能启动或其进程身份发生变化。"
            case .terminalResponse: return "Terminal 返回了无法确认的窗口信息。"
            case .windowNotIdentified: return "已打开一个空 Terminal 窗口，但无法唯一确认其窗口身份；尚未启动 CLI，请保留窗口并手动连接。"
            case .expiredWindow: return "这个启动窗口已过期，请重新发起启动。"
            case .bindingNotSaved: return "窗口尚未安全绑定到原任务，CLI 没有启动。"
            case .terminalBusy: return "目标 Terminal 标签页正在运行其他程序，本次未发送启动命令。"
            case .launchRequestInvalid: return "启动请求无效或已过期，未启动程序。"
            case .launchRequestUsed: return "启动请求已经被使用，不能重复执行。"
            case .wrongTerminal: return "启动请求来自其他终端或任务，未启动程序。"
            case .automation(let message): return "Terminal 启动失败：" + message
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
