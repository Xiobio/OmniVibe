import Foundation
import XCTest
@testable import OmniVibeCore

final class SessionIdentityTests: XCTestCase {
    private func workspace() throws -> WorkspaceState {
        var state = WorkspaceState()
        for number in 1...2 {
            try state.bind(WindowIdentity(processID: Int32(number), processStartedAt: Date(timeIntervalSince1970: 1),
                bundleIdentifier: "fixture", applicationName: "Fixture", title: "Window"), to: number)
        }
        return state
    }

    func testUUIDCaseDoesNotRejectTheSelectedTranscriptOrAllowDuplicateAssociation() throws {
        var state = try workspace()
        let session = UUID().uuidString
        state.slots[0].agentProvider = "codex"; state.slots[0].sessionID = session.uppercased()
        let date = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(try state.apply(.init(taskID: state.slots[0].id, state: .running, at: date,
            provider: "codex", sessionID: session.lowercased(), eventName: "Transcript"), now: date))
        XCTAssertFalse(try state.apply(.init(taskID: state.slots[1].id, state: .unknown, at: date,
            provider: "codex", sessionID: session.uppercased(), eventName: "SessionStart"), now: date))
    }

    func testLateTranscriptCannotBypassHookPriorityByChangingUUIDCase() throws {
        var state = try workspace()
        let session = UUID().uuidString, date = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(try state.apply(.init(taskID: state.slots[0].id, state: .unknown, at: date,
            provider: "codex", sessionID: session.uppercased(), eventName: "SessionStart"), now: date))
        XCTAssertFalse(try state.apply(.init(taskID: state.slots[0].id, state: .ready, at: date.addingTimeInterval(1),
            provider: "codex", sessionID: session.lowercased(), eventName: "Transcript"), now: date.addingTimeInterval(1)))
        XCTAssertEqual(state.slots[0].stateSource, "Codex hooks")
    }

    func testOpaqueSessionIdentifiersRemainCaseSensitive() throws {
        var state = try workspace()
        state.slots[0].agentProvider = "claude"; state.slots[0].sessionID = "SESSION-A"
        let date = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(try state.apply(.init(taskID: state.slots[0].id, state: .ready, at: date,
            provider: "claude", sessionID: "session-a", eventName: "Transcript"), now: date))
    }
}
