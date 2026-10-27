import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class RecentTaskStoreTests: XCTestCase {
    func testMissingStoreReturnsEmptyWithoutCreatingAnything() throws {
        let files = FakeRecentTaskFiles()
        let store = RecentTaskStore(root: files.root, files: files.operations)
        let result = try store.load()
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertNil(result.warning)
        XCTAssertEqual(files.writes, 0)
        XCTAssertEqual(files.directoriesCreated, 0)
    }

    func testSaveAndLoadPreserveCompleteTaskIdentityAndAgentMetadata() throws {
        let files = FakeRecentTaskFiles()
        let store = RecentTaskStore(root: files.root, files: files.operations)
        let record = RecentTaskRecord(task: task(number: 4), closedAt: Date(timeIntervalSinceReferenceDate: 12345.123456789))
        try store.save([record])
        let loaded = try store.load()
        XCTAssertEqual(loaded.records, [record])
        XCTAssertEqual(loaded.records[0].id, record.task.id)
        XCTAssertEqual(loaded.records[0].task.sessionID, "session-4")
        XCTAssertTrue(loaded.records[0].task.unread)
        XCTAssertNil(loaded.warning)
    }

    func testNewestUniqueThirtyAreKeptAndOlderDuplicateCannotReplaceNewerTask() throws {
        let files = FakeRecentTaskFiles()
        let store = RecentTaskStore(root: files.root, files: files.operations)
        let records = (0..<35).map { index in
            RecentTaskRecord(task: task(number: index % 9 + 1), closedAt: Date(timeIntervalSince1970: Double(index)))
        }
        var olderDuplicate = records[34].task
        olderDuplicate.name = "An older snapshot"
        try store.save(records + [RecentTaskRecord(task: olderDuplicate, closedAt: Date(timeIntervalSince1970: 1))])
        let result = try store.load()
        XCTAssertEqual(result.records.count, 30)
        XCTAssertEqual(result.records.first, records[34])
        XCTAssertEqual(result.records.last, records[5])
        XCTAssertEqual(Set(result.records.map(\.id)).count, 30)
    }

    func testUpsertRefreshesOneTaskAndReturnsCorruptionRecoveryWarning() throws {
        let files = FakeRecentTaskFiles()
        let store = RecentTaskStore(root: files.root, files: files.operations)
        let broken = Data("{ damaged archive".utf8)
        files.storage[store.stateFile] = broken
        let original = task(number: 2)
        let first = try store.upsert(task: original, closedAt: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(first.records.count, 1)
        XCTAssertNotNil(first.warning)
        XCTAssertEqual(files.backups.count, 1)
        XCTAssertEqual(files.storage[files.backups[0]], broken)
        var updated = original
        updated.name = "Updated task title"
        let second = try store.upsert(task: updated, closedAt: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(second.records.count, 1)
        XCTAssertEqual(second.records[0].task, updated)
        XCTAssertEqual(second.records[0].id, original.id)
        XCTAssertNil(second.warning)
        XCTAssertEqual(try store.load().records, second.records)
    }

    func testMalformedJSONAndMismatchedTaskIdentityAreBackedUpByteForByteWithoutOverwriting() throws {
        let files = FakeRecentTaskFiles()
        let store = RecentTaskStore(root: files.root, files: files.operations)
        try store.save([RecentTaskRecord(task: task(number: 1), closedAt: Date())])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: files.storage[store.stateFile]!) as? [String: Any])
        var records = try XCTUnwrap(object["records"] as? [[String: Any]])
        records[0]["id"] = UUID().uuidString
        object["records"] = records
        let malformed = try JSONSerialization.data(withJSONObject: object)
        files.storage[store.stateFile] = malformed
        let writesBefore = files.writes

        let result = try store.load()

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertNotNil(result.warning)
        XCTAssertEqual(files.storage[store.stateFile], malformed)
        XCTAssertEqual(files.storage[files.backups[0]], malformed)
        XCTAssertEqual(files.writes, writesBefore)
    }

    func testReadAndBackupFailuresNeverAuthorizeReplacementOrDestroyOriginal() throws {
        let files = FakeRecentTaskFiles()
        let store = RecentTaskStore(root: files.root, files: files.operations)
        let original = Data("broken".utf8)
        files.storage[store.stateFile] = original
        files.readFailure = true
        XCTAssertThrowsError(try store.load())
        XCTAssertTrue(files.backups.isEmpty)
        files.readFailure = false
        files.backupFailure = true
        XCTAssertThrowsError(try store.upsert(task: task(number: 3), closedAt: Date()))
        XCTAssertEqual(files.storage[store.stateFile], original)
        XCTAssertEqual(files.writes, 0)
    }

    func testInvalidEmptyTaskOrTimeAndAtomicWriteFailureKeepPreviousBytes() throws {
        let files = FakeRecentTaskFiles()
        let store = RecentTaskStore(root: files.root, files: files.operations)
        try store.save([RecentTaskRecord(task: task(number: 5), closedAt: Date())])
        let original = files.storage[store.stateFile]
        XCTAssertThrowsError(try store.save([RecentTaskRecord(task: TaskSlot(number: 1), closedAt: Date())]))
        XCTAssertThrowsError(try store.save([RecentTaskRecord(task: task(number: 1), closedAt: Date(timeIntervalSinceReferenceDate: .infinity))]))
        var invalidSlot = task(number: 1)
        invalidSlot.number = 10
        XCTAssertThrowsError(try store.save([RecentTaskRecord(task: invalidSlot, closedAt: Date())]))
        XCTAssertEqual(files.storage[store.stateFile], original)
        files.writeFailure = true
        XCTAssertThrowsError(try store.upsert(task: task(number: 2), closedAt: Date()))
        XCTAssertEqual(files.storage[store.stateFile], original)
    }

    func testSystemAtomicFileRoundTripUsesOnlyIsolatedDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeRecentTaskTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecentTaskStore(root: root)
        let record = RecentTaskRecord(task: task(number: 9), closedAt: Date(timeIntervalSinceReferenceDate: 22222.987654321))
        try store.save([record])
        XCTAssertEqual(try store.load().records, [record])
        let original = try Data(contentsOf: store.stateFile)
        XCTAssertThrowsError(try store.save([RecentTaskRecord(task: TaskSlot(number: 1), closedAt: Date())]))
        XCTAssertEqual(try Data(contentsOf: store.stateFile), original)
    }

    private func task(number: Int) -> TaskSlot {
        let window = WindowIdentity(processID: Int32(100 + number), processStartedAt: Date(timeIntervalSinceReferenceDate: 123.123456789),
                                    bundleIdentifier: "com.example.Terminal", applicationName: "Terminal", title: "Project \(number)")
        return TaskSlot(number: number, name: "Named task \(number)", window: window,
                        agentState: .waiting, unread: true, message: "Fixed status hint", updatedAt: Date(timeIntervalSinceReferenceDate: 234.987654321),
                        agentProvider: "claude", sessionID: "session-\(number)", integrationConnected: true,
                        stateSource: "Claude Code hooks", lastAgentTurnID: "turn-\(number)", lastAgentEventName: "PermissionRequest")
    }
}

private enum RecentTaskFixtureError: Error { case failed, missing }

private final class FakeRecentTaskFiles {
    let root = URL(fileURLWithPath: "/fixture/OmniVibe")
    var storage: [URL: Data] = [:]
    var backups: [URL] = []
    var writes = 0
    var directoriesCreated = 0
    var readFailure = false
    var backupFailure = false
    var writeFailure = false

    var operations: RecentTaskStore.FileOperations {
        .init(exists: { self.storage[$0] != nil }, read: { url in
            if self.readFailure { throw RecentTaskFixtureError.failed }
            guard let value = self.storage[url] else { throw RecentTaskFixtureError.missing }
            return value
        }, createDirectory: { _ in self.directoriesCreated += 1 }, copy: { source, target in
            if self.backupFailure { throw RecentTaskFixtureError.failed }
            guard let data = self.storage[source] else { throw RecentTaskFixtureError.missing }
            self.storage[target] = data
            self.backups.append(target)
        }, writeAtomic: { data, url in
            if self.writeFailure { throw RecentTaskFixtureError.failed }
            self.storage[url] = data
            self.writes += 1
        })
    }
}
