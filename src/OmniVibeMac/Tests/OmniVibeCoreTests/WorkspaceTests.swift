import Foundation
import XCTest
@testable import OmniVibeCore

final class WorkspaceTests: XCTestCase {
    private func window(id: UUID = UUID(), pid: Int32 = 42, started: Date? = Date(timeIntervalSince1970: 100),
                        title: String = "Project") -> WindowIdentity {
        WindowIdentity(id: id, processID: pid, processStartedAt: started,
                       bundleIdentifier: "com.example.terminal", applicationName: "Terminal", title: title)
    }

    func testNineSlotsHaveStableNumbersAndDistinctIdentities() throws {
        let state = WorkspaceState()
        XCTAssertEqual(state.slots.map(\.number), Array(1...9))
        XCTAssertEqual(Set(state.slots.map(\.id)).count, 9)
        XCTAssertTrue(state.slots.allSatisfy { $0.window == nil })
        try state.validate()
    }

    func testBindRejectsOverwriteAndDuplicateWindowWithoutMutation() throws {
        var state = WorkspaceState()
        let first = window()
        try state.bind(first, to: 3)
        let bound = state
        XCTAssertThrowsError(try state.bind(window(), to: 3)) {
            XCTAssertEqual($0 as? WorkspaceError, .occupiedSlot(3))
        }
        XCTAssertThrowsError(try state.bind(first, to: 7)) {
            XCTAssertEqual($0 as? WorkspaceError, .duplicateWindow(3))
        }
        XCTAssertEqual(state, bound)
    }

    func testDifferentWindowsInSameApplicationMayUseSeparateSlots() throws {
        var state = WorkspaceState()
        let first = window(title: "Same title")
        let second = window(title: "Same title")
        try state.bind(first, to: 1)
        try state.bind(second, to: 2)
        XCTAssertNotEqual(state.slots[0].window?.id, state.slots[1].window?.id)
    }

    func testUnbindingPreservesEveryOtherSlotAndChangesTaskIdentity() throws {
        var state = WorkspaceState()
        try state.bind(window(), to: 2)
        try state.bind(window(), to: 8)
        try state.rename(slot: 8, to: "Backend")
        let before = state
        try state.remove(slot: 2)
        XCTAssertNil(state.slots[1].window)
        XCTAssertNotEqual(state.slots[1].id, before.slots[1].id)
        for number in (1...9) where number != 2 {
            XCTAssertEqual(state.slots[number - 1], before.slots[number - 1])
        }
    }

    func testReplacementDoesNotInheritAgentStatusOrTaskName() throws {
        var state = WorkspaceState()
        try state.bind(window(), to: 4)
        try state.rename(slot: 4, to: "Old task")
        try state.setStatus(slot: 4, state: .ready, message: "Old result")
        let priorTaskID = state.slots[3].id
        try state.remove(slot: 4)
        try state.bind(window(), to: 4)
        XCTAssertNotEqual(state.slots[3].id, priorTaskID)
        XCTAssertEqual(state.slots[3].name, "")
        XCTAssertEqual(state.slots[3].agentState, .unknown)
        XCTAssertFalse(state.slots[3].unread)
        XCTAssertEqual(state.slots[3].message, "")
        XCTAssertNil(state.slots[3].updatedAt)
    }

    func testMetadataRefreshPreservesTaskButReusedProcessDoesNot() throws {
        var state = WorkspaceState()
        var identity = window()
        try state.bind(identity, to: 1)
        try state.setStatus(slot: 1, state: .waiting, message: "Approval")
        let oldTask = state.slots[0]
        identity.title = "Renamed terminal"
        try state.bind(identity, to: 1)
        XCTAssertEqual(state.slots[0].id, oldTask.id)
        XCTAssertEqual(state.slots[0].agentState, .waiting)
        identity.processStartedAt = Date(timeIntervalSince1970: 200)
        try state.bind(identity, to: 1)
        XCTAssertNotEqual(state.slots[0].id, oldTask.id)
        XCTAssertEqual(state.slots[0].agentState, .unknown)
        XCTAssertFalse(state.slots[0].unread)
    }

    func testStatusRequiresOccupiedSlotAndDoesNotClaimWindowConnectivity() throws {
        var state = WorkspaceState()
        XCTAssertThrowsError(try state.setStatus(slot: 1, state: .running, message: ""))
        try state.bind(window(), to: 1)
        try state.setStatus(slot: 1, state: .ready, message: "Reply available")
        XCTAssertTrue(state.slots[0].unread)
        XCTAssertNotNil(state.slots[0].updatedAt)
        XCTAssertEqual(state.slots[0].agentState, .ready)
        try state.setStatus(slot: 1, state: .running, message: "Next turn")
        XCTAssertFalse(state.slots[0].unread)
    }

    func testInvalidSlotNumbersAreRejected() {
        var state = WorkspaceState()
        for number in [0, 10, -1] {
            XCTAssertThrowsError(try state.bind(window(), to: number))
            XCTAssertThrowsError(try state.remove(slot: number))
            XCTAssertThrowsError(try state.rename(slot: number, to: "x"))
        }
    }

    func testValidationRejectsMalformedSlotSetsAndDuplicateBindings() {
        var state = WorkspaceState()
        state.slots[1].number = 1
        XCTAssertThrowsError(try state.validate())
        state = WorkspaceState()
        state.slots[1].id = state.slots[0].id
        XCTAssertThrowsError(try state.validate())
        state = WorkspaceState()
        let identity = window()
        state.slots[0].window = identity
        state.slots[1].window = identity
        XCTAssertThrowsError(try state.validate())
        state = WorkspaceState(schemaVersion: 2)
        XCTAssertThrowsError(try state.validate())
    }
}
