import Foundation
import XCTest
@testable import OmniVibeCore

final class SlotOrderingTests: XCTestCase {
    func testMoveIntoEmptySlotPreservesWholeTaskAndLeavesOtherSlotsUntouched() throws {
        var state = WorkspaceState()
        state.slots[1] = task(number: 2)
        state.slots[7] = task(number: 8)
        let before = state
        let equipmentByTask = [before.slots[1].id: "custom-equipment.png"]

        try state.move(from: 2, to: 6)

        assertTask(state.slots[5], equals: before.slots[1], at: 6)
        XCTAssertEqual(equipmentByTask[state.slots[5].id], "custom-equipment.png")
        XCTAssertNil(state.slots[1].window)
        XCTAssertNotEqual(state.slots[1].id, before.slots[1].id)
        XCTAssertNotEqual(state.slots[1].id, before.slots[5].id)
        XCTAssertEqual(state.slots[1], TaskSlot(id: state.slots[1].id, number: 2))
        for number in 1...9 where number != 2 && number != 6 {
            XCTAssertEqual(state.slots[number - 1], before.slots[number - 1])
        }
        try assertValidNumbers(state)
    }

    func testMoveRejectsOccupiedTargetWithoutSwappingOrMutating() throws {
        var state = fullWorkspace()
        let before = state
        XCTAssertThrowsError(try state.move(from: 2, to: 6)) {
            XCTAssertEqual($0 as? WorkspaceError, .occupiedSlot(6))
        }
        XCTAssertEqual(state, before)
    }

    func testReorderForwardInsertsAtTargetAndShiftsEveryInterveningTask() throws {
        var state = fullWorkspace()
        let before = state
        let equipmentByTask = Dictionary(uniqueKeysWithValues: before.slots.map { ($0.id, "art-\($0.number).png") })

        try state.reorder(from: 2, to: 6)

        let oldNumbers = [1, 3, 4, 5, 6, 2, 7, 8, 9]
        for (index, oldNumber) in oldNumbers.enumerated() {
            assertTask(state.slots[index], equals: before.slots[oldNumber - 1], at: index + 1)
            XCTAssertEqual(equipmentByTask[state.slots[index].id], "art-\(oldNumber).png")
        }
        try assertValidNumbers(state)
    }

    func testReorderBackwardInsertsBeforeTargetAndPreservesEmptySlotIdentities() throws {
        var state = fullWorkspace()
        state.slots[3] = TaskSlot(number: 4)
        let before = state

        try state.reorder(from: 7, to: 3)

        let oldNumbers = [1, 2, 7, 3, 4, 5, 6, 8, 9]
        for (index, oldNumber) in oldNumbers.enumerated() {
            assertTask(state.slots[index], equals: before.slots[oldNumber - 1], at: index + 1)
        }
        XCTAssertNil(state.slots[4].window)
        XCTAssertEqual(Set(state.slots.map(\.id)), Set(before.slots.map(\.id)))
        try assertValidNumbers(state)
    }

    func testReorderIntoEmptyTargetShiftsSlotsInsteadOfUsingMoveSemantics() throws {
        var state = WorkspaceState()
        state.slots[0] = task(number: 1)
        state.slots[2] = task(number: 3)
        let before = state

        try state.reorder(from: 1, to: 4)

        let oldNumbers = [2, 3, 4, 1, 5, 6, 7, 8, 9]
        for (index, oldNumber) in oldNumbers.enumerated() {
            assertTask(state.slots[index], equals: before.slots[oldNumber - 1], at: index + 1)
        }
        XCTAssertEqual(Set(state.slots.map(\.id)), Set(before.slots.map(\.id)))
        try assertValidNumbers(state)
    }

    func testSameSlotIsNoOpForOccupiedAndEmptySlots() throws {
        var state = WorkspaceState()
        state.slots[1] = task(number: 2)
        let before = state
        try state.move(from: 2, to: 2)
        try state.reorder(from: 2, to: 2)
        try state.move(from: 5, to: 5)
        try state.reorder(from: 5, to: 5)
        XCTAssertEqual(state, before)
    }

    func testInvalidNumbersAndEmptySourcesFailWithoutMutation() throws {
        var state = WorkspaceState()
        state.slots[1] = task(number: 2)
        let before = state
        for number in [-1, 0, 10] {
            XCTAssertThrowsError(try state.move(from: number, to: 2)) {
                XCTAssertEqual($0 as? WorkspaceError, .invalidSlot(number))
            }
            XCTAssertThrowsError(try state.move(from: 2, to: number)) {
                XCTAssertEqual($0 as? WorkspaceError, .invalidSlot(number))
            }
            XCTAssertThrowsError(try state.reorder(from: number, to: 2)) {
                XCTAssertEqual($0 as? WorkspaceError, .invalidSlot(number))
            }
            XCTAssertThrowsError(try state.reorder(from: 2, to: number)) {
                XCTAssertEqual($0 as? WorkspaceError, .invalidSlot(number))
            }
            XCTAssertEqual(state, before)
        }
        XCTAssertThrowsError(try state.move(from: 3, to: 4)) {
            XCTAssertEqual($0 as? WorkspaceError, .emptySlot(3))
        }
        XCTAssertThrowsError(try state.reorder(from: 3, to: 2)) {
            XCTAssertEqual($0 as? WorkspaceError, .emptySlot(3))
        }
        XCTAssertEqual(state, before)
    }

    func testExistingHookFollowsMovedTaskAndDoesNotUpdateReplacementAtOldNumber() throws {
        var state = WorkspaceState()
        state.slots[1] = task(number: 2)
        let originalTask = state.slots[1]
        try state.move(from: 2, to: 6)
        try state.bind(window(number: 20), to: 2)
        let replacement = state.slots[1]
        let time = Date(timeIntervalSince1970: 4000)
        let event = AgentStatusEvent(taskID: originalTask.id, state: .ready, message: "Original task completed",
                                     at: time, provider: "claude", sessionID: originalTask.sessionID,
                                     eventName: "Stop", turnID: originalTask.lastAgentTurnID)

        XCTAssertTrue(try state.apply(event, now: time))

        XCTAssertEqual(state.slots[5].id, originalTask.id)
        XCTAssertEqual(state.slots[5].agentState, .ready)
        XCTAssertEqual(state.slots[5].message, event.message)
        XCTAssertTrue(state.slots[5].unread)
        XCTAssertEqual(state.slots[5].sessionID, originalTask.sessionID)
        XCTAssertEqual(state.slots[1], replacement)
    }

    func testExistingHooksFollowReorderedTasksAfterPersistenceRoundTrip() throws {
        var state = fullWorkspace()
        let moved = state.slots[1]
        let shifted = state.slots[4]
        try state.reorder(from: 2, to: 6)
        state = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        let time = Date(timeIntervalSince1970: 4000)
        for slot in [moved, shifted] {
            let event = AgentStatusEvent(taskID: slot.id, state: .waiting, message: "Approval for \(slot.id)",
                                         at: time, provider: "claude", sessionID: slot.sessionID,
                                         eventName: "PermissionRequest", turnID: slot.lastAgentTurnID)
            XCTAssertTrue(try state.apply(event, now: time))
        }

        XCTAssertEqual(state.slots[5].id, moved.id)
        XCTAssertEqual(state.slots[3].id, shifted.id)
        XCTAssertEqual(state.slots[5].agentState, .waiting)
        XCTAssertEqual(state.slots[3].agentState, .waiting)
        XCTAssertTrue(state.slots[5].unread)
        XCTAssertTrue(state.slots[3].unread)
        XCTAssertEqual(state.slots[5].sessionID, moved.sessionID)
        XCTAssertEqual(state.slots[3].sessionID, shifted.sessionID)
        try assertValidNumbers(state)
    }

    func testReorderUsesFixedNumbersEvenWhenDecodedArrayOrderIsDifferent() throws {
        var state = fullWorkspace()
        let before = state
        state.slots.reverse()
        try state.validate()

        try state.reorder(from: 2, to: 6)

        let oldNumbers = [1, 3, 4, 5, 6, 2, 7, 8, 9]
        for (index, oldNumber) in oldNumbers.enumerated() {
            assertTask(state.slots[index], equals: before.slots[oldNumber - 1], at: index + 1)
        }
        try assertValidNumbers(state)
    }

    private func fullWorkspace() -> WorkspaceState {
        WorkspaceState(slots: (1...9).map(task))
    }

    private func task(number: Int) -> TaskSlot {
        TaskSlot(number: number, name: "Named task \(number)", window: window(number: number),
                 agentState: number.isMultiple(of: 2) ? .waiting : .running,
                 unread: number.isMultiple(of: 2), message: "Message \(number)",
                 updatedAt: Date(timeIntervalSince1970: Double(2000 + number)),
                 agentProvider: "claude", sessionID: "session-\(number)", integrationConnected: true,
                 stateSource: "Claude Code hooks", lastAgentTurnID: "turn-\(number)", lastAgentEventName: "PreToolUse")
    }

    private func window(number: Int) -> WindowIdentity {
        WindowIdentity(processID: Int32(100 + number), processStartedAt: Date(timeIntervalSince1970: Double(1000 + number)),
                       bundleIdentifier: "com.example.Terminal", applicationName: "Terminal", title: "Session \(number)")
    }

    private func assertTask(_ actual: TaskSlot, equals original: TaskSlot, at number: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
        var expected = original
        expected.number = number
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func assertValidNumbers(_ state: WorkspaceState, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(state.slots.map(\.number), Array(1...9), file: file, line: line)
        XCTAssertEqual(Set(state.slots.map(\.id)).count, 9, file: file, line: line)
        try state.validate()
    }
}
