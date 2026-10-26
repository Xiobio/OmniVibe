import AppKit
import Carbon
import Foundation
import XCTest
@testable import OmniVibeMac

final class TerminalThemeServiceTests: XCTestCase {
    @MainActor
    func testConstructionNeverContactsTerminalAndApplyBacksUpBeforeChangingOnlyUsedProfiles() async throws {
        let root = try temporaryDirectory()
        let original = colors(10)
        let unused = colors(90)
        let backend = FakeTerminalThemeBackend(values: [1: original, 99: unused], used: [1, 1])
        backend.backupURL = root.appendingPathComponent("terminal-theme-backup.json")
        let service = TerminalThemeService(root: root, backend: backend)
        XCTAssertEqual(backend.callCount, 0)
        XCTAssertFalse(service.hasBackup)
        let palette = colors(100)
        let receipt = try await service.apply(theme: palette)
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(receipt.profileCount, 1)
        XCTAssertFalse(receipt.restored)
        XCTAssertTrue(service.hasBackup)
        XCTAssertFalse(service.isBusy)
        XCTAssertEqual(backend.snapshot, [1: palette, 99: unused])
        XCTAssertEqual(backend.writes.map(\.id), [1])
        XCTAssertTrue(backend.backupExistedBeforeEveryWrite)
        XCTAssertFalse(backend.calledOnMainThread)
        let backup = try backupDocument(receipt.backupURL)
        XCTAssertEqual((backup["originals"] as? [[String: Any]])?.count, 1)
    }

    @MainActor
    func testRepeatedSyncKeepsEarliestColorsAndRestoreAlsoUndoesPreviouslyUsedProfiles() async throws {
        let root = try temporaryDirectory()
        let original = [1: colors(10), 2: colors(20), 99: colors(90)]
        let backend = FakeTerminalThemeBackend(values: original, used: [1, 2])
        let service = TerminalThemeService(root: root, backend: backend)
        _ = try await service.apply(theme: colors(100))
        XCTAssertEqual(backend.snapshot[99], original[99])
        backend.used = [1, 99]
        _ = try await service.apply(theme: colors(200))
        XCTAssertEqual(backend.snapshot[2], colors(100))
        let reloaded = TerminalThemeService(root: root, backend: backend)
        XCTAssertTrue(reloaded.hasBackup)
        let receipt = try await reloaded.restoreLatest()
        XCTAssertTrue(receipt.restored)
        XCTAssertEqual(receipt.profileCount, 3)
        XCTAssertEqual(backend.snapshot, original)
        XCTAssertFalse(reloaded.hasBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.backupURL.path))
    }

    @MainActor
    func testPartialWriteFailureRollsBackEveryTargetAndKeepsOriginalBackup() async throws {
        let root = try temporaryDirectory()
        let original = [1: colors(10), 2: colors(20), 99: colors(90)]
        let backend = FakeTerminalThemeBackend(values: original, used: [1, 2])
        backend.failWrites[2] = 1
        backend.mutateBeforeFailure = true
        let service = TerminalThemeService(root: root, backend: backend)
        do { _ = try await service.apply(theme: colors(100)); XCTFail("Expected write failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("已回滚")) }
        XCTAssertEqual(backend.snapshot, original)
        XCTAssertEqual(backend.writes.map(\.id), [1, 2, 1, 2])
        XCTAssertTrue(service.hasBackup)
        XCTAssertEqual((try backupDocument(service.backupURL)["pendingRecovery"] as? [Any])?.count, 0)
    }

    @MainActor
    func testReadBackMismatchAlsoRollsBackAllFourColors() async throws {
        let root = try temporaryDirectory()
        let original = colors(10)
        let backend = FakeTerminalThemeBackend(values: [1: original], used: [1])
        backend.nextReadOverrides[1] = colors(999)
        let service = TerminalThemeService(root: root, backend: backend)
        do { _ = try await service.apply(theme: colors(100)); XCTFail("Expected verification failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("核验")) }
        XCTAssertEqual(backend.snapshot[1], original)
        XCTAssertTrue(service.hasBackup)
    }

    @MainActor
    func testFailedRollbackRetainsRecoveryAndBlocksAnotherSyncUntilExplicitRestore() async throws {
        let root = try temporaryDirectory()
        let original = [1: colors(10), 2: colors(20)]
        let backend = FakeTerminalThemeBackend(values: original, used: [1, 2])
        backend.failWrites[2] = 2
        let service = TerminalThemeService(root: root, backend: backend)
        do { _ = try await service.apply(theme: colors(100)); XCTFail("Expected failure") } catch {}
        XCTAssertTrue(service.hasBackup)
        XCTAssertEqual((try backupDocument(service.backupURL)["pendingRecovery"] as? [Any])?.count, 1)
        let writes = backend.writes.count
        do { _ = try await service.apply(theme: colors(200)); XCTFail("Expected pending recovery rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("先恢复")) }
        XCTAssertEqual(backend.writes.count, writes)
        _ = try await service.restoreLatest()
        XCTAssertEqual(backend.snapshot, original)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testRestoreFailureRetainsBackupAndRetryCompletes() async throws {
        let root = try temporaryDirectory()
        let original = [1: colors(10), 2: colors(20)]
        let backend = FakeTerminalThemeBackend(values: original, used: [1, 2])
        let service = TerminalThemeService(root: root, backend: backend)
        _ = try await service.apply(theme: colors(100))
        backend.failWrites[2] = 1
        do { _ = try await service.restoreLatest(); XCTFail("Expected partial restoration") } catch {}
        XCTAssertTrue(service.hasBackup)
        XCTAssertEqual(backend.snapshot[1], original[1])
        _ = try await service.restoreLatest()
        XCTAssertEqual(backend.snapshot, original)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testBackupWriteFailureOrMalformedBackupNeverChangesProfiles() async throws {
        let folder = try temporaryDirectory()
        let blocked = folder.appendingPathComponent("blocked-root")
        try Data("retain".utf8).write(to: blocked)
        let original = [1: colors(10)]
        let backend = FakeTerminalThemeBackend(values: original, used: [1])
        let blockedService = TerminalThemeService(root: blocked, backend: backend)
        do { _ = try await blockedService.apply(theme: colors(100)); XCTFail("Expected backup failure") } catch {}
        XCTAssertTrue(backend.writes.isEmpty)
        XCTAssertEqual(backend.snapshot, original)

        let invalidRoot = try temporaryDirectory()
        let invalid = Data("not-json".utf8)
        let backup = invalidRoot.appendingPathComponent("terminal-theme-backup.json")
        try invalid.write(to: backup)
        let neverCalled = FakeTerminalThemeBackend(values: original, used: [1])
        let invalidService = TerminalThemeService(root: invalidRoot, backend: neverCalled)
        do { _ = try await invalidService.apply(theme: colors(100)); XCTFail("Expected invalid backup") } catch {}
        XCTAssertEqual(neverCalled.callCount, 0)
        XCTAssertEqual(try Data(contentsOf: backup), invalid)
    }

    @MainActor
    func testTerminalRestartCannotRestoreAReusedProfileIdentifier() async throws {
        let root = try temporaryDirectory()
        let backend = FakeTerminalThemeBackend(values: [1: colors(10)], used: [1])
        let service = TerminalThemeService(root: root, backend: backend)
        _ = try await service.apply(theme: colors(100))
        backend.session = "different-terminal-process"
        let writes = backend.writes.count
        do { _ = try await service.restoreLatest(); XCTFail("Expected session mismatch") }
        catch { XCTAssertTrue(error.localizedDescription.contains("重新启动")) }
        XCTAssertEqual(backend.writes.count, writes)
        XCTAssertTrue(service.hasBackup)
    }

    @MainActor
    func testNoOpenWindowsAndDeniedAutomationDoNotCreateBackupOrWriteColors() async throws {
        let root = try temporaryDirectory()
        let backend = FakeTerminalThemeBackend(values: [1: colors(10)], used: [])
        let service = TerminalThemeService(root: root, backend: backend)
        do { _ = try await service.apply(theme: colors(100)); XCTFail("Expected no open windows") } catch {}
        XCTAssertTrue(backend.writes.isEmpty)
        XCTAssertFalse(service.hasBackup)
        backend.used = [1]
        backend.readFailure = TerminalThemeError.automationDenied
        do { _ = try await service.apply(theme: colors(100)); XCTFail("Expected denied Automation") }
        catch { XCTAssertTrue(error.localizedDescription.contains("自动化权限")) }
        XCTAssertTrue(backend.writes.isEmpty)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testExpiredSessionBackupCanBeArchivedLocallyAndNewSessionCanApply() async throws {
        let root = try temporaryDirectory()
        let backend = FakeTerminalThemeBackend(values: [1: colors(10)], used: [1])
        let service = TerminalThemeService(root: root, backend: backend)
        _ = try await service.apply(theme: colors(100))
        let bytes = try Data(contentsOf: service.backupURL)
        backend.session = "terminal-process-2"
        let calls = backend.callCount
        let writes = backend.writes.count
        let archive = try await service.archivePreviousSessionBackup()
        XCTAssertEqual(backend.callCount - calls, 1, "Only process metadata may be read")
        XCTAssertEqual(backend.writes.count, writes)
        XCTAssertEqual(try Data(contentsOf: archive), bytes)
        XCTAssertTrue(archive.lastPathComponent.hasPrefix("terminal-theme-backup.archived-"))
        XCTAssertFalse(service.hasBackup)
        _ = try await service.apply(theme: colors(200))
        XCTAssertEqual(backend.snapshot[1], colors(200))
        XCTAssertTrue(service.hasBackup)
        XCTAssertEqual(try Data(contentsOf: archive), bytes)
    }

    @MainActor
    func testCurrentSessionCannotArchiveRecoverableBackupEvenWithPendingRecovery() async throws {
        for pending in [false, true] {
            let backend = FakeTerminalThemeBackend(values: [1: colors(10), 2: colors(20)], used: [1, 2])
            if pending { backend.failWrites[2] = 2 }
            let service = TerminalThemeService(root: try temporaryDirectory(), backend: backend)
            do { _ = try await service.apply(theme: colors(100)) }
            catch { XCTAssertTrue(pending) }
            let bytes = try Data(contentsOf: service.backupURL)
            let writes = backend.writes.count
            do { _ = try await service.archivePreviousSessionBackup(); XCTFail("Must preserve current recovery") }
            catch { XCTAssertTrue(error.localizedDescription.contains("当前会话的备份不能归档")) }
            XCTAssertEqual(try Data(contentsOf: service.backupURL), bytes)
            XCTAssertEqual(backend.writes.count, writes)
            XCTAssertTrue(service.hasBackup)
        }
    }

    @MainActor
    func testMalformedBackupCannotBeSilentlyArchivedOrContactTerminal() async throws {
        let root = try temporaryDirectory()
        let bytes = Data("not a valid color backup".utf8)
        let url = root.appendingPathComponent("terminal-theme-backup.json")
        try bytes.write(to: url)
        let backend = FakeTerminalThemeBackend(values: [1: colors(10)], used: [1])
        let service = TerminalThemeService(root: root, backend: backend)
        do { _ = try await service.archivePreviousSessionBackup(); XCTFail("Expected invalid backup") } catch {}
        XCTAssertEqual(backend.callCount, 0)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [url.lastPathComponent])
    }

    @MainActor
    func testMainActorStaysResponsiveAndConcurrentRequestFailsWithoutInterleaving() async throws {
        let root = try temporaryDirectory()
        let backend = FakeTerminalThemeBackend(values: [1: colors(10)], used: [1])
        let gate = DispatchSemaphore(value: 0)
        backend.firstWriteGate = gate
        let service = TerminalThemeService(root: root, backend: backend)
        let palette = colors(100)
        let operation = Task { try await service.apply(theme: palette) }
        for _ in 0..<500 {
            if !backend.writes.isEmpty { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(service.isBusy)
        XCTAssertFalse(backend.writes.isEmpty)
        XCTAssertTrue(Thread.isMainThread)
        do { _ = try await service.restoreLatest(); XCTFail("Expected busy rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("正在进行")) }
        do { _ = try await service.archivePreviousSessionBackup(); XCTFail("Expected busy archive rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("正在进行")) }
        gate.signal()
        _ = try await operation.value
        XCTAssertFalse(service.isBusy)
        XCTAssertFalse(backend.calledOnMainThread)
    }

    @MainActor
    func testNSColorsConvertToBoundedSixteenBitCalibratedRGBForAppleScript() throws {
        let color = NSColor(calibratedRed: 0.25, green: 0.5, blue: 1, alpha: 1)
        let palette = try TerminalThemePalette(background: color, normalText: color, boldText: color, cursor: color)
        XCTAssertEqual(palette.background, .init(red: 16_384, green: 32_768, blue: 65_535))
        let midGray = try TerminalThemePalette.RGB(NSColor(calibratedWhite: 0.5, alpha: 1))
        XCTAssertEqual(midGray, .init(red: 32_768, green: 32_768, blue: 32_768))
        XCTAssertEqual(try JSONDecoder().decode(TerminalThemePalette.self, from: JSONEncoder().encode(palette)), palette)
    }

    func testScriptsOnlyReadUsedProfilesAndCoerceFourColorsWithoutAnyTerminalInputOrFontChanges() throws {
        let palette = colors(100)
        let source = AppleScriptTerminalThemeBackend.usedProfilesScript
        let read = try AppleScriptTerminalThemeBackend.colorsScript(profileID: 123)
        let write = try AppleScriptTerminalThemeBackend.setColorsScript(palette, profileID: 123)
        XCTAssertTrue(source.contains("current settings of terminalTab"))
        XCTAssertTrue(source.contains("(id of profileObject) as integer"))
        for property in ["background color", "normal text color", "bold text color", "cursor color"] {
            XCTAssertTrue(source.contains("(\(property) of profileObject) as list"))
            XCTAssertTrue(read.contains("(\(property) of profileObject) as list"))
            XCTAssertTrue(write.contains("set \(property) of profileObject to {"))
        }
        for forbidden in ["do script", "do shell script", "contents", "history", "font", "default settings", "startup settings", "activate", "import"] {
            XCTAssertFalse((source + read + write).lowercased().contains(forbidden), forbidden)
        }
        XCTAssertThrowsError(try AppleScriptTerminalThemeBackend.colorsScript(profileID: Int.max))
        XCTAssertThrowsError(try AppleScriptTerminalThemeBackend.setColorsScript(palette, profileID: Int.min))
    }

    func testReadAndWriteResolveTransientCurrentSettingsBeforeSavedProfiles() throws {
        for script in [try AppleScriptTerminalThemeBackend.colorsScript(profileID: 1000),
                       try AppleScriptTerminalThemeBackend.setColorsScript(colors(100), profileID: 1000)] {
            XCTAssertTrue(script.contains("set requestedProfileID to 1000"))
            XCTAssertTrue(script.contains("set candidateProfile to current settings of terminalTab"))
            XCTAssertTrue(script.contains("((id of candidateProfile) as integer) is requestedProfileID"))
            XCTAssertTrue(script.contains("set profileObject to candidateProfile"))
            let live = try XCTUnwrap(script.range(of: "repeat with terminalWindow in windows"))
            let saved = try XCTUnwrap(script.range(of: "repeat with candidateProfile in settings sets"))
            XCTAssertLessThan(live.lowerBound, saved.lowerBound)
            XCTAssertTrue(script.contains("if profileObject is missing value then error number -1728"))
            XCTAssertFalse(script.contains("first settings set"))
            XCTAssertFalse(script.contains("whose id"))
        }
    }

    func testDescriptorParsingAcceptsOnlyBoundedIntegerColorTriples() throws {
        let palette = colors(10)
        let value = descriptor(palette)
        XCTAssertEqual(try AppleScriptTerminalThemeBackend.parsePalette(value), palette)
        let row = NSAppleEventDescriptor.list()
        row.insert(NSAppleEventDescriptor(int32: 7), at: 1)
        for position in 1...4 { row.insert(try XCTUnwrap(value.atIndex(position)), at: position + 1) }
        let profiles = NSAppleEventDescriptor.list(); profiles.insert(row, at: 1)
        XCTAssertEqual(try AppleScriptTerminalThemeBackend.parseProfiles(profiles), [.init(profileID: 7, colors: palette)])
        for bad in [NSAppleEventDescriptor(int32: -1), NSAppleEventDescriptor(int32: 65_536), NSAppleEventDescriptor(string: "42")] {
            let malformedRGB = NSAppleEventDescriptor.list()
            malformedRGB.insert(bad, at: 1)
            malformedRGB.insert(NSAppleEventDescriptor(int32: 0), at: 2)
            malformedRGB.insert(NSAppleEventDescriptor(int32: 0), at: 3)
            let invalid = NSAppleEventDescriptor.list()
            invalid.insert(malformedRGB, at: 1)
            for position in 2...4 { invalid.insert(try XCTUnwrap(value.atIndex(position)), at: position) }
            XCTAssertThrowsError(try AppleScriptTerminalThemeBackend.parsePalette(invalid))
        }
        XCTAssertThrowsError(try AppleScriptTerminalThemeBackend.parseProfiles(NSAppleEventDescriptor(string: "not a list")))
    }

    private func colors(_ start: UInt16) -> TerminalThemePalette {
        let rgb = TerminalThemePalette.RGB(red: start, green: start + 1, blue: start + 2)
        return TerminalThemePalette(background: rgb, normalText: rgb, boldText: rgb, cursor: rgb)
    }

    private func descriptor(_ palette: TerminalThemePalette) -> NSAppleEventDescriptor {
        let result = NSAppleEventDescriptor.list()
        for (position, color) in [palette.background, palette.normalText, palette.boldText, palette.cursor].enumerated() {
            let rgb = NSAppleEventDescriptor.list()
            for (channel, value) in [color.red, color.green, color.blue].enumerated() {
                rgb.insert(NSAppleEventDescriptor(int32: Int32(value)), at: channel + 1)
            }
            result.insert(rgb, at: position + 1)
        }
        return result
    }

    private func backupDocument(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omnivibe-terminal-theme-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}

private final class FakeTerminalThemeBackend: TerminalThemeBackend, @unchecked Sendable {
    struct Write { let id: Int; let colors: TerminalThemePalette }
    private let lock = NSLock()
    private var values: [Int: TerminalThemePalette]
    private var recordedWrites: [Write] = []
    private var calls = 0
    private var anyMainThreadCall = false
    private var backupPresent = true
    var used: [Int]
    var session = "terminal-process-1"
    var failWrites: [Int: Int] = [:]
    var mutateBeforeFailure = false
    var nextReadOverrides: [Int: TerminalThemePalette] = [:]
    var readFailure: Error?
    var backupURL: URL?
    var firstWriteGate: DispatchSemaphore?

    init(values: [Int: TerminalThemePalette], used: [Int]) { self.values = values; self.used = used }
    var snapshot: [Int: TerminalThemePalette] { locked { values } }
    var writes: [Write] { locked { recordedWrites } }
    var callCount: Int { locked { calls } }
    var calledOnMainThread: Bool { locked { anyMainThreadCall } }
    var backupExistedBeforeEveryWrite: Bool { locked { backupPresent } }

    func sessionIdentifier() throws -> String { locked { recordCall(); return session } }
    func usedProfiles() throws -> [TerminalProfileColors] {
        try locked {
            recordCall()
            if let readFailure { throw readFailure }
            return used.compactMap { id in values[id].map { TerminalProfileColors(profileID: id, colors: $0) } }
        }
    }
    func colors(profileID: Int) throws -> TerminalThemePalette {
        try locked {
            recordCall()
            if let override = nextReadOverrides.removeValue(forKey: profileID) { return override }
            guard let colors = values[profileID] else { throw Failure.missingProfile }
            return colors
        }
    }
    func setColors(_ colors: TerminalThemePalette, profileID: Int) throws {
        let gate = locked { () -> DispatchSemaphore? in
            recordCall()
            recordedWrites.append(Write(id: profileID, colors: colors))
            if let backupURL { backupPresent = backupPresent && FileManager.default.fileExists(atPath: backupURL.path) }
            let gate = firstWriteGate; firstWriteGate = nil
            return gate
        }
        if let gate { _ = gate.wait(timeout: .now() + 2) }
        try locked {
            guard values[profileID] != nil else { throw Failure.missingProfile }
            if (failWrites[profileID] ?? 0) > 0 {
                failWrites[profileID, default: 0] -= 1
                if mutateBeforeFailure { values[profileID] = colors }
                throw Failure.write
            }
            values[profileID] = colors
        }
    }
    private func recordCall() { calls += 1; anyMainThreadCall = anyMainThreadCall || Thread.isMainThread }
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    private enum Failure: Error { case write, missingProfile }
}
