import AppKit
import Foundation

/// A process-local task reference shared by the inventory and floating wheel.
/// Numbers and window metadata are deliberately resolved only at drop time.
enum TaskDragPayload {
    static let typeIdentifier = "com.xiobio.omnivibe.task-reference"
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)

    static func encode(_ taskID: UUID) -> Data { Data(taskID.uuidString.utf8) }

    static func decode(_ data: Data) -> UUID? {
        guard data.count == 36, let value = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: value)
    }

    static func provider(for taskID: UUID) -> NSItemProvider {
        let data = encode(taskID)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) { completion in
            // Export synchronously on the provider's calling queue. Dispatching
            // item exports to the main actor can deadlock a native drag session.
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// NSDraggingItem requires NSPasteboardWriting rather than NSItemProvider.
    /// The native source permits only within-application moves, and native
    /// destinations additionally reject sessions without a local source.
    static func pasteboardItem(for taskID: UUID) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(encode(taskID), forType: pasteboardType)
        return item
    }
}

/// One press has exactly one outcome: click, drag, or cancellation. A drag
/// must never turn back into a click when the pointer returns to its origin.
struct InventoryPreviewGesture {
    let taskID: UUID?
    let origin: NSPoint
    private(set) var crossedDragThreshold = false

    mutating func move(to point: NSPoint) -> UUID? {
        guard !crossedDragThreshold, hypot(point.x - origin.x, point.y - origin.y) >= 9 else { return nil }
        crossedDragThreshold = true
        return taskID
    }

    func shouldActivate(at point: NSPoint, bounds: NSRect, currentTaskID: UUID?) -> Bool {
        !crossedDragThreshold && taskID == currentTaskID && bounds.contains(point)
    }
}
