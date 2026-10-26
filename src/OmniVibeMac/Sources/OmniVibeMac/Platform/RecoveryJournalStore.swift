import Foundation
import OmniVibeCore

struct WindowRecoveryRecord: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case toggle, layout, parked }
    var kind: Kind
    var taskID: UUID?
    var window: WindowIdentity
    var frame: WindowFrame
    var minimized: Bool
    var previousFocus: WindowIdentity?

    init(kind: Kind, taskID: UUID? = nil, window: WindowIdentity, frame: WindowFrame,
         minimized: Bool, previousFocus: WindowIdentity? = nil) {
        self.kind = kind; self.taskID = taskID; self.window = window
        self.frame = frame; self.minimized = minimized; self.previousFocus = previousFocus
    }
}

struct RecoveryJournalLoadResult: Sendable {
    let records: [WindowRecoveryRecord]
    var warning: String?
}

struct RecoveryJournalStore: Sendable {
    static let maximumRecords = 32
    static let maximumBytes = 1_048_576
    let root: URL
    var journalURL: URL { root.appendingPathComponent("window-recovery.json") }

    init(root: URL) { self.root = root }

    private struct Document: Codable {
        let version: Int
        let records: [WindowRecoveryRecord]
    }

    func load() throws -> RecoveryJournalLoadResult {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return RecoveryJournalLoadResult(records: []) }
        try requireRegularJournal()
        do {
            let handle = try FileHandle(forReadingFrom: journalURL)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            guard bytes.count <= Self.maximumBytes else { throw JournalError.tooLarge }
            let document = try JSONDecoder().decode(Document.self, from: bytes)
            guard document.version == 1 else { throw JournalError.invalidVersion }
            try validate(document.records)
            return RecoveryJournalLoadResult(records: document.records)
        } catch {
            // Copy into a private staging name, then rename the complete backup
            // beside the journal. The original remains untouched if either step
            // fails; callers must not silently continue past a backup failure.
            let backup = try preserveRejectedJournal()
            return RecoveryJournalLoadResult(records: [], warning: "窗口恢复记录无法读取，原文件已备份为 \(backup.lastPathComponent)。请检查备份后手动恢复窗口。")
        }
    }

    /// Call before mutating windows. A failed write leaves the previous journal
    /// intact. Empty records delete only this app's fixed regular journal file.
    func save(records: [WindowRecoveryRecord]) throws {
        try validate(records)
        if records.isEmpty {
            if FileManager.default.fileExists(atPath: journalURL.path) {
                try requireRegularJournal()
                try FileManager.default.removeItem(at: journalURL)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(Document(version: 1, records: records))
        guard bytes.count <= Self.maximumBytes else { throw JournalError.tooLarge }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: journalURL.path) { try requireRegularJournal() }
        try bytes.write(to: journalURL, options: .atomic)
    }

    private func validate(_ records: [WindowRecoveryRecord]) throws {
        guard records.count <= Self.maximumRecords else { throw JournalError.tooManyRecords }
        for (index, record) in records.enumerated() {
            let frame = record.frame
            guard frame.x.isFinite, frame.y.isFinite, frame.width.isFinite, frame.height.isFinite,
                  frame.width > 0, frame.height > 0,
                  (frame.x + frame.width).isFinite, (frame.y + frame.height).isFinite else { throw JournalError.invalidFrame }
            guard record.window.processID > 0 else { throw JournalError.invalidWindow }
            for previous in records.prefix(index) where previous.kind == record.kind {
                // Different layers (toggle atop layout) are intentional and
                // restore in that order. Duplicates within one layer are not.
                guard previous.window.id != record.window.id,
                      !previous.window.refersToSamePlatformWindow(as: record.window),
                      previous.taskID == nil || record.taskID == nil || previous.taskID != record.taskID else { throw JournalError.duplicateRecord }
            }
        }
    }

    private func requireRegularJournal() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: journalURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw JournalError.invalidFile }
    }

    private func preserveRejectedJournal() throws -> URL {
        let identifier = UUID().uuidString
        let staging = root.appendingPathComponent(".window-recovery-backup-\(identifier).tmp")
        let backup = root.appendingPathComponent("window-recovery.rejected-\(identifier).json")
        do {
            try FileManager.default.copyItem(at: journalURL, to: staging)
            try FileManager.default.moveItem(at: staging, to: backup)
            return backup
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    enum JournalError: LocalizedError {
        case tooManyRecords, tooLarge, invalidFrame, invalidWindow, duplicateRecord, invalidVersion, invalidFile
        var errorDescription: String? {
            let localizedSource: String? = {
                switch self {
                case .tooManyRecords: return "窗口恢复记录超过 32 项，尚未修改窗口。"
                case .tooLarge: return "窗口恢复记录超过 1 MiB，尚未修改窗口。"
                case .invalidFrame: return "窗口恢复位置或尺寸无效，尚未修改窗口。"
                case .invalidWindow: return "窗口恢复记录的目标进程无效。"
                case .duplicateRecord: return "同一恢复层包含重复窗口或任务，尚未修改窗口。"
                case .invalidVersion: return "窗口恢复记录的版本不受支持。"
                case .invalidFile: return "窗口恢复记录不是普通文件，已保留原路径。"
                }
        }()
            return localizedSource.map { L10n.errorText($0) }
        }
    }
}
