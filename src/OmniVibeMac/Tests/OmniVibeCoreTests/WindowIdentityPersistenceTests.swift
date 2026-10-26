import Foundation
import XCTest
@testable import OmniVibeCore

final class WindowIdentityPersistenceTests: XCTestCase {
    private func window(number: UInt32? = 80, session: String? = "user:boot:login") -> WindowIdentity {
        WindowIdentity(processID: 120, processStartedAt: Date(timeIntervalSince1970: 10),
            bundleIdentifier: "com.example.Terminal", applicationName: "Terminal", title: "Project",
            platformWindowNumber: number, platformSessionID: session)
    }

    func testLegacyWindowJSONDecodesWithoutPlatformTokensAndNewTokensRoundTrip() throws {
        let legacy = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","processID":120,"applicationName":"Terminal","title":"Project"}
        """.utf8)
        let decoded = try JSONDecoder().decode(WindowIdentity.self, from: legacy)
        XCTAssertNil(decoded.platformWindowNumber)
        XCTAssertNil(decoded.platformSessionID)
        let current = window()
        XCTAssertEqual(try JSONDecoder().decode(WindowIdentity.self, from: JSONEncoder().encode(current)), current)
    }

    func testValidatedMetadataRefreshPreservesTaskAndAllAgentMetadata() throws {
        var state = WorkspaceState()
        let original = window()
        try state.bind(original, to: 3)
        state.slots[2].name = "My task"
        state.slots[2].agentProvider = "codex"
        state.slots[2].sessionID = "thread_123"
        state.slots[2].integrationConnected = true
        state.slots[2].agentState = .waiting
        state.slots[2].stateSource = "Codex"
        state.slots[2].unread = true
        let before = state.slots[2]
        var live = original
        live.title = "Fresh title"
        XCTAssertTrue(try state.refreshWindowMetadata(live, for: before.id))
        var expected = before
        expected.window = live
        XCTAssertEqual(state.slots[2], expected)
        XCTAssertFalse(try state.refreshWindowMetadata(live, for: before.id))
    }

    func testMetadataRefreshRejectsDifferentTaskProcessOrPlatformIdentityWithoutMutation() throws {
        var state = WorkspaceState()
        let original = window()
        try state.bind(original, to: 1)
        let before = state
        var invalids: [WindowIdentity] = []
        var value = original; value.id = UUID(); invalids.append(value)
        value = original; value.processID += 1; invalids.append(value)
        value = original; value.processStartedAt = Date(timeIntervalSince1970: 20); invalids.append(value)
        value = original; value.platformWindowNumber = 81; invalids.append(value)
        value = original; value.platformSessionID = "otherLogin"; invalids.append(value)
        for invalid in invalids {
            XCTAssertFalse(try state.refreshWindowMetadata(invalid, for: state.slots[0].id))
            XCTAssertEqual(state, before)
        }
        XCTAssertFalse(try state.refreshWindowMetadata(original, for: UUID()))
    }

    func testDuplicatePhysicalWindowCannotOccupyDifferentUUIDSlots() throws {
        var state = WorkspaceState()
        let original = window()
        try state.bind(original, to: 1)
        var alias = original; alias.id = UUID()
        let before = state
        XCTAssertThrowsError(try state.bind(alias, to: 2)) {
            XCTAssertEqual($0 as? WorkspaceError, .duplicateWindow(1))
        }
        XCTAssertEqual(state, before)
        state.slots[1].window = alias
        XCTAssertThrowsError(try state.validate())
    }

    func testAbsentTokensDoNotTreatSeparateWindowsInOneApplicationAsDuplicates() throws {
        var state = WorkspaceState()
        try state.bind(window(number: nil, session: nil), to: 1)
        try state.bind(window(number: nil, session: nil), to: 2)
        try state.validate()
    }
}
