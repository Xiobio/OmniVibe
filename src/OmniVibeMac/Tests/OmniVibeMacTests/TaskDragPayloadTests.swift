import AppKit
import XCTest
@testable import OmniVibeMac

final class TaskDragPayloadTests: XCTestCase {
    func testPayloadPreservesTaskIdentityWithoutSlotNumberOrWindowMetadata() {
        let taskID = UUID()
        let data = TaskDragPayload.encode(taskID)
        XCTAssertEqual(TaskDragPayload.decode(data), taskID)
        XCTAssertEqual(String(data: data, encoding: .utf8), taskID.uuidString)
    }

    func testMalformedOrAdditionalPayloadDataCannotSelectATask() {
        let valid = TaskDragPayload.encode(UUID())
        for data in [Data(), Data("3".utf8), Data(repeating: 0xFF, count: 36),
                     Data(repeating: 0x41, count: 36), valid + Data("\n".utf8), Data("prefix:".utf8) + valid] {
            XCTAssertNil(TaskDragPayload.decode(data))
        }
    }

    func testProviderExportsOnlyThePrivateTaskReferenceAndLoadsWithoutMainQueueDispatch() async {
        let taskID = UUID()
        let provider = TaskDragPayload.provider(for: taskID)
        XCTAssertEqual(provider.registeredTypeIdentifiers, [TaskDragPayload.typeIdentifier])
        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier("public.text"))
        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier("public.file-url"))
        let loaded = expectation(description: "Load process-local task reference")
        provider.loadDataRepresentation(forTypeIdentifier: TaskDragPayload.typeIdentifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data.flatMap(TaskDragPayload.decode), taskID)
            loaded.fulfill()
        }
        await fulfillment(of: [loaded], timeout: 2)
    }

    func testNativePasteboardItemUsesTheSamePrivateUUIDRepresentation() {
        let taskID = UUID()
        let item = TaskDragPayload.pasteboardItem(for: taskID)
        XCTAssertEqual(item.types, [TaskDragPayload.pasteboardType])
        XCTAssertEqual(item.data(forType: TaskDragPayload.pasteboardType).flatMap(TaskDragPayload.decode), taskID)
        XCTAssertNil(item.string(forType: .string))
    }

    func testPreviewPressBelowThresholdCanActivateWithoutStartingDrag() {
        let taskID = UUID()
        var gesture = InventoryPreviewGesture(taskID: taskID, origin: .zero)
        XCTAssertNil(gesture.move(to: NSPoint(x: 8, y: 0)))
        XCTAssertFalse(gesture.crossedDragThreshold)
        XCTAssertTrue(gesture.shouldActivate(at: NSPoint(x: 8, y: 0),
                                             bounds: NSRect(x: -20, y: -20, width: 100, height: 100), currentTaskID: taskID))
    }

    func testNinePointDragStartsOnceAndNeverTurnsIntoActivation() {
        let taskID = UUID()
        var gesture = InventoryPreviewGesture(taskID: taskID, origin: .zero)
        XCTAssertEqual(gesture.move(to: NSPoint(x: 9, y: 0)), taskID)
        XCTAssertTrue(gesture.crossedDragThreshold)
        XCTAssertNil(gesture.move(to: NSPoint(x: 20, y: 0)), "A single press must create at most one native drag session.")
        XCTAssertNil(gesture.move(to: .zero))
        XCTAssertFalse(gesture.shouldActivate(at: .zero, bounds: NSRect(x: -20, y: -20, width: 100, height: 100), currentTaskID: taskID),
                       "Returning to the source or cancelling a drag must not activate its window.")
    }

    func testEmptyPreviewDragDoesNotExportOrActivateAnEmptySlot() {
        var gesture = InventoryPreviewGesture(taskID: nil, origin: .zero)
        XCTAssertNil(gesture.move(to: NSPoint(x: 9, y: 0)))
        XCTAssertTrue(gesture.crossedDragThreshold)
        XCTAssertFalse(gesture.shouldActivate(at: .zero, bounds: NSRect(x: -20, y: -20, width: 100, height: 100), currentTaskID: nil))
    }

    func testReplacedTaskAndReleaseOutsidePreviewCannotActivate() {
        let taskID = UUID()
        let gesture = InventoryPreviewGesture(taskID: taskID, origin: .zero)
        let bounds = NSRect(x: -20, y: -20, width: 100, height: 100)
        XCTAssertFalse(gesture.shouldActivate(at: .zero, bounds: bounds, currentTaskID: UUID()))
        XCTAssertFalse(gesture.shouldActivate(at: NSPoint(x: 100, y: 0), bounds: bounds, currentTaskID: taskID))
    }
}
