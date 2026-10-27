import Foundation

public struct PendingStatusEvent: Sendable {
    public let url: URL
    public let event: AgentStatusEvent
    let receivedBytes: Data
}

public enum StatusEventInboxError: Error, LocalizedError {
    case invalidEvent, oversizedEvent, invalidAcknowledgement
    public var errorDescription: String? {
        switch self {
        case .invalidEvent: return "任务状态事件无效。"
        case .oversizedEvent: return "任务状态事件超过大小限制。"
        case .invalidAcknowledgement: return "无法确认事件目录以外的文件。"
        }
    }
}

/// Disk-only inbox. Reading never acknowledges an event; the application saves
/// its workspace successfully before asking this actor to remove the batch.
public actor StatusEventInbox {
    public static let batchSize = 24
    public static let maximumEventBytes = 32_768
    public nonisolated let eventsDirectory: URL

    public init(root: URL) { eventsDirectory = root.appendingPathComponent("events", isDirectory: true).standardizedFileURL }

    @discardableResult
    public nonisolated static func publish(_ event: AgentStatusEvent, root: URL) throws -> URL {
        guard event.isValid() else { throw StatusEventInboxError.invalidEvent }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(event)
        guard bytes.count <= maximumEventBytes else { throw StatusEventInboxError.oversizedEvent }
        let folder = root.appendingPathComponent("events", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(UUID().uuidString + ".json")
        try bytes.write(to: output, options: .atomic)
        return output
    }

    public func read(now: Date = Date()) throws -> [PendingStatusEvent] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: eventsDirectory.path) else { return [] }
        var enumerationError: Error?
        guard let enumerator = manager.enumerator(at: eventsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            return []
        }
        var oldest: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            guard let properties = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { continue }
            if properties.isSymbolicLink == true { reject(url); continue }
            guard properties.isRegularFile == true else { continue }
            oldest.append((url, properties.contentModificationDate ?? .distantPast))
            oldest.sort { first, second in first.modified == second.modified ? first.url.lastPathComponent < second.url.lastPathComponent : first.modified < second.modified }
            if oldest.count > Self.batchSize { oldest.removeLast() }
        }
        if let enumerationError { throw enumerationError }
        var pending: [PendingStatusEvent] = []
        for candidate in oldest {
            do {
                let handle = try FileHandle(forReadingFrom: candidate.url)
                defer { try? handle.close() }
                let bytes = try handle.read(upToCount: Self.maximumEventBytes + 1) ?? Data()
                guard bytes.count <= Self.maximumEventBytes,
                      let event = try? JSONDecoder().decode(AgentStatusEvent.self, from: bytes),
                      event.isValid(at: now) else { reject(candidate.url); continue }
                pending.append(PendingStatusEvent(url: candidate.url, event: event, receivedBytes: bytes))
            } catch {
                // Locked/inaccessible/transiently unreadable files remain for a
                // later poll and do not starve the other events in this batch.
                continue
            }
        }
        return pending.sorted { first, second in
            first.event.at == second.event.at ? first.url.lastPathComponent < second.url.lastPathComponent : first.event.at < second.event.at
        }
    }

    public func acknowledge(_ batch: [PendingStatusEvent]) throws {
        for item in batch {
            guard item.url.standardizedFileURL.deletingLastPathComponent() == eventsDirectory,
                  item.url.pathExtension.lowercased() == "json" else { throw StatusEventInboxError.invalidAcknowledgement }
            guard FileManager.default.fileExists(atPath: item.url.path) else { continue }
            // A producer replacing a filename after a read must not lose its
            // new event when the prior contents are acknowledged.
            guard try Data(contentsOf: item.url) == item.receivedBytes else { continue }
            try FileManager.default.removeItem(at: item.url)
        }
    }

    private func reject(_ url: URL) {
        let destination = url.appendingPathExtension(UUID().uuidString + ".rejected")
        try? FileManager.default.moveItem(at: url, to: destination)
    }
}
