import AppKit
import XCTest
@testable import OmniVibeMac

final class WheelSlotGestureTests: XCTestCase {
    private let taskID = UUID()

    func testOccupiedClickActivatesOnlyThePressedSlot() {
        let gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero)
        XCTAssertEqual(gesture.release(hitSlot: 2, removeSlot: nil, outside: false), .activate(2))
        XCTAssertEqual(gesture.release(hitSlot: 3, removeSlot: nil, outside: false), .none)
    }

    func testEmptyClickCanOpenPicker() {
        let gesture = WheelSlotGesture(source: 4, taskID: nil, origin: .zero)
        XCTAssertEqual(gesture.release(hitSlot: 4, removeSlot: nil, outside: false), .activate(4))
    }

    func testMovementBelowNinePointsRemainsAClick() {
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero)
        gesture.move(to: NSPoint(x: 8.99, y: 0))
        XCTAssertFalse(gesture.sorting)
        XCTAssertEqual(gesture.release(hitSlot: 2, removeSlot: nil, outside: false), .activate(2))
    }

    func testNinePointThresholdStartsSorting() {
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero)
        gesture.move(to: NSPoint(x: 9, y: 0))
        XCTAssertTrue(gesture.sorting)
    }

    func testThresholdUsesBothAxes() {
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: NSPoint(x: 100, y: 100))
        gesture.move(to: NSPoint(x: 106, y: 107))
        XCTAssertTrue(gesture.sorting)
    }

    func testSortPassesTheOriginalTaskIdentityToLaterSlot() {
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero)
        gesture.move(to: NSPoint(x: 20, y: 0))
        XCTAssertEqual(gesture.release(hitSlot: 7, removeSlot: nil, outside: false), .reorder(2, 7, taskID))
    }

    func testSortCanMoveTowardEarlierSlot() {
        var gesture = WheelSlotGesture(source: 7, taskID: taskID, origin: .zero)
        gesture.move(to: NSPoint(x: -20, y: 0))
        XCTAssertEqual(gesture.release(hitSlot: 1, removeSlot: nil, outside: false), .reorder(7, 1, taskID))
    }

    func testSameSlotSortCancelsInsteadOfActivating() {
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero)
        gesture.move(to: NSPoint(x: 20, y: 0))
        XCTAssertEqual(gesture.release(hitSlot: 2, removeSlot: nil, outside: false), .none)
    }

    func testReturningToPressPointCannotTurnASortIntoAClick() {
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero)
        gesture.move(to: NSPoint(x: 20, y: 0))
        gesture.move(to: .zero)
        XCTAssertTrue(gesture.sorting)
        XCTAssertEqual(gesture.release(hitSlot: 2, removeSlot: nil, outside: false), .none)
    }

    func testFarOutsideDropRemovesOnlyTheOriginalTask() {
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero)
        gesture.move(to: NSPoint(x: 20, y: 0))
        XCTAssertEqual(gesture.release(hitSlot: nil, removeSlot: nil, outside: true), .remove(2, taskID))
    }

    func testNoTargetNearTheWheelCancels() {
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero)
        gesture.move(to: NSPoint(x: 20, y: 0))
        XCTAssertEqual(gesture.release(hitSlot: nil, removeSlot: nil, outside: false), .none)
    }

    func testRemovalRequiresMoreThanTwentyEightPointsOutsideEachEdge() {
        let bounds = NSRect(x: 0, y: 0, width: 360, height: 360)
        for point in [NSPoint(x: -28, y: 180), NSPoint(x: 388, y: 180),
                      NSPoint(x: 180, y: -28), NSPoint(x: 180, y: 388)] {
            XCTAssertFalse(WheelSlotGesture.isRemovalDrop(point, bounds: bounds))
        }
        for point in [NSPoint(x: -28.1, y: 180), NSPoint(x: 388.1, y: 180),
                      NSPoint(x: 180, y: -28.1), NSPoint(x: 180, y: 388.1)] {
            XCTAssertTrue(WheelSlotGesture.isRemovalDrop(point, bounds: bounds))
        }
    }

    func testRemoveButtonHasATwentyTwoPointCircularHitArea() {
        let centre = NSPoint(x: 100, y: 100)
        XCTAssertTrue(WheelSlotGesture.hitsRemove(NSPoint(x: 111, y: 100), centre: centre))
        XCTAssertTrue(WheelSlotGesture.hitsRemove(NSPoint(x: 100, y: 89), centre: centre))
        XCTAssertFalse(WheelSlotGesture.hitsRemove(NSPoint(x: 111.1, y: 100), centre: centre))
    }

    func testRemovePressMustReleaseOnTheSameRemoveButton() {
        let gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero, removal: true)
        XCTAssertEqual(gesture.release(hitSlot: 2, removeSlot: 2, outside: false), .remove(2, taskID))
        XCTAssertEqual(gesture.release(hitSlot: 2, removeSlot: nil, outside: false), .none)
        XCTAssertEqual(gesture.release(hitSlot: 3, removeSlot: 3, outside: false), .none)
    }

    func testRemovePressCannotBecomeSortingOrActivation() {
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero, removal: true)
        gesture.move(to: NSPoint(x: 30, y: 0))
        XCTAssertFalse(gesture.sorting)
        XCTAssertEqual(gesture.release(hitSlot: 3, removeSlot: nil, outside: false), .none)
    }

    func testEmptySlotCannotBecomeASortOrOutsideRemoval() {
        var gesture = WheelSlotGesture(source: 2, taskID: nil, origin: .zero)
        gesture.move(to: NSPoint(x: 30, y: 0))
        XCTAssertFalse(gesture.sorting)
        XCTAssertEqual(gesture.release(hitSlot: 3, removeSlot: nil, outside: false), .none)
        XCTAssertEqual(gesture.release(hitSlot: nil, removeSlot: nil, outside: true), .none)
    }

    func testInvalidSlotNumbersCannotOperateOnTasks() {
        var invalidSource = WheelSlotGesture(source: 0, taskID: taskID, origin: .zero)
        invalidSource.move(to: NSPoint(x: 20, y: 0))
        XCTAssertEqual(invalidSource.release(hitSlot: 2, removeSlot: nil, outside: false), .none)
        var gesture = WheelSlotGesture(source: 2, taskID: taskID, origin: .zero)
        gesture.move(to: NSPoint(x: 20, y: 0))
        XCTAssertEqual(gesture.release(hitSlot: 10, removeSlot: nil, outside: false), .none)
    }
}
