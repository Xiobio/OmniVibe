import Foundation
import XCTest
@testable import OmniVibeCore

final class WorkspaceStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeCoreTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func testMissingWorkspaceStartsWithEmptySlotsWithoutWritingFile() throws {
        let store = WorkspaceStore(root: root)
        let result = try store.load()
        XCTAssertEqual(result.state.slots.count, 9)
        XCTAssertNil(result.warning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateFile.path))
    }

    func testWorkspaceRoundTripKeepsPreciseDatesAndLiveTokens() throws {
        var state = WorkspaceState()
        let identity = WindowIdentity(processID: 123, processStartedAt: Date(),
                                      applicationName: "Terminal", title: "测试窗口")
        try state.bind(identity, to: 9)
        try state.rename(slot: 9, to: "工作项目")
        try state.setStatus(slot: 9, state: .waiting, message: "请查看终端")
        let store = WorkspaceStore(root: root)
        try store.save(state)
        let loaded = try store.load()
        XCTAssertEqual(loaded.state, state)
        XCTAssertNil(loaded.warning)
        // Tokens remain only hints; no lookup or automatic reconnection occurs in the store.
        XCTAssertEqual(loaded.state.slots[8].window?.id, identity.id)
    }

    func testCorruptBytesAreBackedUpExactlyBeforeFreshWorkspaceIsReturned() throws {
        let store = WorkspaceStore(root: root)
        let original = Data("{ definitely not json }".utf8)
        try original.write(to: store.stateFile)
        let result = try store.load()
        XCTAssertNotNil(result.warning)
        XCTAssertTrue(result.state.slots.allSatisfy { $0.window == nil })
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("workspace.recovery-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), original)
        XCTAssertEqual(try Data(contentsOf: store.stateFile), original)
        try store.save(result.state)
        XCTAssertEqual(try Data(contentsOf: backups[0]), original)
    }

    func testUnsupportedSchemaAndInvalidSlotShapeAreRecovered() throws {
        let store = WorkspaceStore(root: root)
        let encoder = JSONEncoder()
        for invalid in [WorkspaceState(schemaVersion: 999), WorkspaceState(slots: [])] {
            try encoder.encode(invalid).write(to: store.stateFile)
            let result = try store.load()
            XCTAssertNotNil(result.warning)
            try result.state.validate()
        }
    }

    func testUnreadableStateIsNotSilentlyReplaced() throws {
        let store = WorkspaceStore(root: root)
        try FileManager.default.createDirectory(at: store.stateFile, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.load())
    }

    func testInvalidSaveKeepsPriorFileIntact() throws {
        let store = WorkspaceStore(root: root)
        try store.save(WorkspaceState())
        let before = try Data(contentsOf: store.stateFile)
        XCTAssertThrowsError(try store.save(WorkspaceState(slots: [])))
        XCTAssertEqual(try Data(contentsOf: store.stateFile), before)
    }
}
