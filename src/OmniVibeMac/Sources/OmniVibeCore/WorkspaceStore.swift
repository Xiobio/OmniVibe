import Foundation

public struct WorkspaceLoadResult: Sendable {
    public var state: WorkspaceState
    public var warning: String?

    public init(state: WorkspaceState, warning: String? = nil) {
        self.state = state
        self.warning = warning
    }
}

public final class WorkspaceStore {
    public let root: URL
    public var stateFile: URL { root.appendingPathComponent("workspace.json") }

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OmniVibe", isDirectory: true)
    }

    public func load() throws -> WorkspaceLoadResult {
        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            return WorkspaceLoadResult(state: WorkspaceState())
        }
        // I/O failures are surfaced, not treated as corrupt data that may be overwritten.
        let data = try Data(contentsOf: stateFile)
        do {
            let state = try Self.decoder().decode(WorkspaceState.self, from: data)
            try state.validate()
            return WorkspaceLoadResult(state: state)
        } catch {
            // Preserve the original bytes before returning a writable fresh workspace.
            let backup = root.appendingPathComponent("workspace.recovery-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: stateFile, to: backup)
            return WorkspaceLoadResult(state: WorkspaceState(),
                warning: "工作区格式无效，原文件已备份到 \(backup.lastPathComponent)。")
        }
    }

    public func save(_ state: WorkspaceState) throws {
        try state.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: stateFile, options: .atomic)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}
