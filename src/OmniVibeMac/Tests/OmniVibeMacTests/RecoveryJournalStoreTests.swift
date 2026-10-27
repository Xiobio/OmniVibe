import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class RecoveryJournalStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeRecoveryJournalTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func record(kind: WindowRecoveryRecord.Kind = .layout, taskID: UUID? = UUID(),
                        number: UInt32 = 80) -> WindowRecoveryRecord {
        let window = WindowIdentity(processID: 120, processStartedAt: Date(timeIntervalSince1970: 10),
            bundleIdentifier: "com.example.Terminal", applicationName: "Terminal", title: "Project",
            platformWindowNumber: number, platformSessionID: "user:boot:login")
        return WindowRecoveryRecord(kind: kind, taskID: taskID, window: window,
            frame: WindowFrame(x: -800, y: 40, width: 720, height: 480), minimized: true)
    }

    func testAbsentJournalAndRoundTripPreserveExactTaskPlatformPlacementAndFocusMetadata() throws {
        let store = RecoveryJournalStore(root: try directory())
        XCTAssertTrue(try store.load().records.isEmpty)
        XCTAssertNil(try store.load().warning)
        var first = record(kind: .toggle)
        first.previousFocus = record(number: 90).window
        let second = record(kind: .parked, taskID: nil, number: 81)
        try store.save(records: [first, second])
        let loaded = try store.load()
        XCTAssertNil(loaded.warning)
        XCTAssertEqual(loaded.records, [first, second])
    }

    func testNestedToggleAndLayoutForSameWindowAreValidButDuplicateLayerIsRejected() throws {
        let store = RecoveryJournalStore(root: try directory())
        let layout = record()
        var toggle = layout; toggle.kind = .toggle
        toggle.frame.width = 900
        try store.save(records: [toggle, layout])
        let original = try Data(contentsOf: store.journalURL)
        XCTAssertThrowsError(try store.save(records: [layout, layout]))
        var physicalAlias = layout; physicalAlias.window.id = UUID(); physicalAlias.taskID = UUID()
        XCTAssertThrowsError(try store.save(records: [layout, physicalAlias]))
        var sameTask = record(number: 81); sameTask.taskID = layout.taskID
        XCTAssertThrowsError(try store.save(records: [layout, sameTask]))
        XCTAssertEqual(try Data(contentsOf: store.journalURL), original)
    }

    func testInvalidFramesAndTooManyRecordsLeaveExistingJournalIntact() throws {
        let store = RecoveryJournalStore(root: try directory())
        let valid = record()
        try store.save(records: [valid])
        let original = try Data(contentsOf: store.journalURL)
        for frame in [WindowFrame(x: .nan, y: 0, width: 10, height: 10),
                      WindowFrame(x: 0, y: .infinity, width: 10, height: 10),
                      WindowFrame(x: 0, y: 0, width: 0, height: 10),
                      WindowFrame(x: 0, y: 0, width: 10, height: -1),
                      WindowFrame(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 1)] {
            var invalid = valid; invalid.frame = frame
            XCTAssertThrowsError(try store.save(records: [invalid]))
        }
        XCTAssertThrowsError(try store.save(records: (1...33).map { record(number: UInt32($0)) }))
        XCTAssertEqual(try Data(contentsOf: store.journalURL), original)
        XCTAssertEqual(try store.load().records, [valid])
    }

    func testCorruptFileIsBackedUpCompletelyBeforeWarningAndOriginalBytesRemain() throws {
        let root = try directory()
        let store = RecoveryJournalStore(root: root)
        let original = Data("{broken journal \"do not erase\"".utf8)
        try original.write(to: store.journalURL)
        let loaded = try store.load()
        XCTAssertTrue(loaded.records.isEmpty)
        XCTAssertNotNil(loaded.warning)
        XCTAssertEqual(try Data(contentsOf: store.journalURL), original)
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("window-recovery.rejected-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".window-recovery-backup-") })
    }

    func testOversizedSaveDoesNotOverwriteAndOversizedReadCreatesExactBackup() throws {
        let root = try directory()
        let store = RecoveryJournalStore(root: root)
        let valid = record()
        try store.save(records: [valid])
        let before = try Data(contentsOf: store.journalURL)
        var huge = valid; huge.window.title = String(repeating: "x", count: RecoveryJournalStore.maximumBytes)
        XCTAssertThrowsError(try store.save(records: [huge]))
        XCTAssertEqual(try Data(contentsOf: store.journalURL), before)
        let oversized = Data(repeating: 65, count: RecoveryJournalStore.maximumBytes + 100)
        try oversized.write(to: store.journalURL)
        XCTAssertNotNil(try store.load().warning)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("window-recovery.rejected-") })
        XCTAssertEqual(try Data(contentsOf: backup), oversized)
    }

    func testInvalidDocumentVersionOrDuplicateLoadedRecordsAreRejectedWithWarning() throws {
        let store = RecoveryJournalStore(root: try directory())
        let valid = record()
        try store.save(records: [valid])
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.journalURL)) as? [String: Any])
        document["version"] = 2
        try JSONSerialization.data(withJSONObject: document).write(to: store.journalURL)
        XCTAssertNotNil(try store.load().warning)
        document["version"] = 1
        let records = try XCTUnwrap(document["records"] as? [[String: Any]])
        document["records"] = records + records
        try JSONSerialization.data(withJSONObject: document).write(to: store.journalURL)
        XCTAssertNotNil(try store.load().warning)
    }

    func testEmptySaveDeletesOnlyFixedJournalAndNeverRemovesDirectoriesOrOtherFiles() throws {
        let root = try directory()
        let store = RecoveryJournalStore(root: root)
        let other = root.appendingPathComponent("workspace.json")
        try Data("untouched".utf8).write(to: other)
        try store.save(records: [record()])
        try store.save(records: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.journalURL.path))
        XCTAssertEqual(try String(contentsOf: other), "untouched")
        try FileManager.default.createDirectory(at: store.journalURL, withIntermediateDirectories: false)
        let nested = store.journalURL.appendingPathComponent("untouched.json")
        try Data("keep".utf8).write(to: nested)
        XCTAssertThrowsError(try store.save(records: []))
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: nested), "keep")
    }

    func testUnavailableParentFailsWithoutCreatingOrReplacingRecoveryData() throws {
        let root = try directory()
        let blocked = root.appendingPathComponent("not-a-folder")
        try Data("original".utf8).write(to: blocked)
        let store = RecoveryJournalStore(root: blocked)
        XCTAssertThrowsError(try store.save(records: [record()]))
        XCTAssertEqual(try String(contentsOf: blocked), "original")
    }
}
