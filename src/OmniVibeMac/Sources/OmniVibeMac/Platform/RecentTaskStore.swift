import Foundation
import OmniVibeCore

struct RecentTaskRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let task: TaskSlot
    let closedAt: Date

    init(task: TaskSlot, closedAt: Date) { id = task.id; self.task = task; self.closedAt = closedAt }
}

struct RecentTaskLoadResult: Equatable, Sendable {
    let records: [RecentTaskRecord]
    let warning: String?
}

/// Persistence only. The controller decides which observed window closures
/// qualify for automatic archival; manual removal must not call upsert.
final class RecentTaskStore {
    static let limit = 30
    let root: URL
    var stateFile: URL { root.appendingPathComponent("recent-tasks.json") }

    struct FileOperations {
        var exists: (URL) -> Bool
        var read: (URL) throws -> Data
        var createDirectory: (URL) throws -> Void
        var copy: (URL, URL) throws -> Void
        var writeAtomic: (Data, URL) throws -> Void

        static let system = FileOperations(
            exists: { FileManager.default.fileExists(atPath: $0.path) },
            read: { try Data(contentsOf: $0) },
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            copy: { try FileManager.default.copyItem(at: $0, to: $1) },
            writeAtomic: { try $0.write(to: $1, options: .atomic) })
    }

    private struct Document: Codable { let schemaVersion: Int; let records: [RecentTaskRecord] }
    private let files: FileOperations

    init(root: URL, files: FileOperations = .system) { self.root = root; self.files = files }

    func load() throws -> RecentTaskLoadResult {
        guard files.exists(stateFile) else { return RecentTaskLoadResult(records: [], warning: nil) }
        // I/O failure is not corruption, and must not authorize replacement.
        let data = try files.read(stateFile)
        do {
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.schemaVersion == 1 else { throw RecentTaskStoreError.invalidRecords }
            let records = try Self.normalized(document.records)
            return RecentTaskLoadResult(records: records, warning: nil)
        } catch {
            let backup = root.appendingPathComponent("recent-tasks.recovery-\(UUID().uuidString).json")
            // A failed backup propagates. No original or archive is overwritten.
            try files.copy(stateFile, backup)
            return RecentTaskLoadResult(records: [], warning: "最近关闭的任务记录格式无效，原文件已备份为 \(backup.lastPathComponent)。")
        }
    }

    func save(_ records: [RecentTaskRecord]) throws {
        let normalized = try Self.normalized(records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(schemaVersion: 1, records: normalized))
        try files.createDirectory(root)
        try files.writeAtomic(data, stateFile)
    }

    @discardableResult
    func upsert(task: TaskSlot, closedAt: Date) throws -> RecentTaskLoadResult {
        let loaded = try load()
        let records = try Self.normalized(loaded.records + [RecentTaskRecord(task: task, closedAt: closedAt)])
        try save(records)
        return RecentTaskLoadResult(records: records, warning: loaded.warning)
    }

    private static func normalized(_ records: [RecentTaskRecord]) throws -> [RecentTaskRecord] {
        var newest: [UUID: RecentTaskRecord] = [:]
        for record in records {
            guard record.id == record.task.id, record.task.window != nil, (1...9).contains(record.task.number),
                  record.closedAt.timeIntervalSinceReferenceDate.isFinite,
                  record.task.updatedAt?.timeIntervalSinceReferenceDate.isFinite != false,
                  record.task.window?.processStartedAt?.timeIntervalSinceReferenceDate.isFinite != false else {
                throw RecentTaskStoreError.invalidRecords
            }
            if let previous = newest[record.id], previous.closedAt > record.closedAt { continue }
            newest[record.id] = record
        }
        return Array(newest.values.sorted {
            if $0.closedAt != $1.closedAt { return $0.closedAt > $1.closedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(limit))
    }
}

enum RecentTaskStoreError: LocalizedError {
    case invalidRecords
    var errorDescription: String? {
        let localizedSource: String? = {
            "最近任务记录包含无效的任务身份、槽位、时间或空任务，未保存修改。"
        }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
