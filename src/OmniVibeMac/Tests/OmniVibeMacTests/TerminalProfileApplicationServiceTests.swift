import AppKit
import Carbon
import Foundation
import XCTest
@testable import OmniVibeMac

final class TerminalProfileApplicationServiceTests: XCTestCase {
    private let theme = TerminalPersistentProfile(id: 30, name: "OmniVibe / 黑神话：悟空 · 灵蕴法宝匣")
    private let otherTheme = TerminalPersistentProfile(id: 31, name: "OmniVibe / 原神 · 星旅背包")
    private let baseline = TerminalPersistentProfile(id: 1, name: "My baseline")
    private let bounds = TerminalProfileWindowBounds(left: -500, top: 30, right: 300, bottom: 630)

    private func backend(twoTabs: Bool = false) -> FakeTerminalProfileApplicationBackend {
        var tabs = [TerminalProfileTabSnapshot(tab: .init(windowID: 101, tty: "/dev/ttys001"), profile: baseline, bounds: bounds)]
        if twoTabs { tabs.append(.init(tab: .init(windowID: 101, tty: "/dev/ttys002"), profile: baseline, bounds: bounds)) }
        return FakeTerminalProfileApplicationBackend(profiles: [baseline, theme, otherTheme], tabs: tabs)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeTerminalProfileTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    @MainActor
    func testConstructionDoesNotContactTerminalAndInspectionOnlyReturnsImportAndBaselineStatus() async throws {
        let fake = backend()
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        XCTAssertEqual(fake.callCount, 0)
        XCTAssertFalse(service.hasBackup)
        let missing = "OmniVibe / 朱砂藏锋"
        let status = await service.inspectImported(profileNames: [theme.name, otherTheme.name, missing])
        XCTAssertEqual(status.missingNames, [missing])
        XCTAssertEqual(status.temporaryOriginalCount, 0)
        XCTAssertNil(status.errorMessage)
        XCTAssertFalse(status.isReady)
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(fake.calledOnMainThread)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testAllTwentySixFilenameImportsResolveToTheirOfficialCanonicalNames() async throws {
        let official: [(String, String)] = [
            ("ink-jade", "墨玉机关"), ("midnight", "玄夜青金"), ("cinnabar", "朱砂藏锋"),
            ("hextech", "英雄联盟 · 海克斯枢纽"), ("tactical", "三角洲行动 · 战术终端"),
            ("protocol", "无畏契约 · 行动协议"), ("adventure", "地下城与勇士 · 冒险装备栏"),
            ("arsenal", "永劫无间 · 无间兵器匣"), ("relic", "黑神话：悟空 · 灵蕴法宝匣"),
            ("starlight", "王者荣耀 · 星曜指挥台"), ("formation", "金铲铲之战 · Agent 备战席"),
            ("astral", "原神 · 星旅背包"), ("wonderland", "梦幻西游 · 三界百宝袋")
        ]
        let imported = official.enumerated().flatMap { index, item in
            [TerminalPersistentProfile(id: 100 + index * 2, name: "OmniVibe-" + item.0),
             TerminalPersistentProfile(id: 101 + index * 2, name: "OmniVibe-" + item.0 + "-minimal")]
        }
        let expected = official.flatMap { ["OmniVibe / " + $0.1, "OmniVibe / " + $0.1 + " / 简洁"] }
        let fake = backend()
        fake.profiles = [baseline] + imported
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)

        let canonicalStatus = await service.inspectImported(profileNames: expected)
        XCTAssertTrue(canonicalStatus.isReady)
        XCTAssertTrue(canonicalStatus.missingNames.isEmpty)
        XCTAssertTrue(canonicalStatus.ambiguousNames.isEmpty)
        let filenameStatus = await service.inspectImported(profileNames: imported.map(\.name))
        XCTAssertTrue(filenameStatus.isReady)
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testFilenameImportAppliesByEitherNameAndRestoresExactOriginalProfileFromUnchangedBackup() async throws {
        let imported = TerminalPersistentProfile(id: theme.id, name: "OmniVibe-relic")
        let fake = backend()
        fake.profiles = [baseline, imported, otherTheme]
        let root = try directory()
        fake.backupURL = root.appendingPathComponent("terminal-profile-backup.json")
        let service = TerminalProfileApplicationService(root: root, backend: fake)
        let globals = fake.profiles
        let status = await service.inspectImported(profileNames: [theme.name])
        XCTAssertTrue(status.isReady)

        _ = try await service.apply(profileName: theme.name)
        XCTAssertEqual(fake.writes.last?.profile, imported)
        XCTAssertEqual(fake.tabs[0].profile.name, imported.name)
        XCTAssertTrue(fake.backupExistedBeforeEveryWrite)
        let firstOriginals = try XCTUnwrap(try document(service.backupURL)["originals"] as? [[String: Any]])
        let original = try XCTUnwrap(firstOriginals.first?["profile"] as? [String: Any])
        XCTAssertEqual(original["id"] as? Int, baseline.id)
        XCTAssertEqual(original["name"] as? String, baseline.name)

        _ = try await service.apply(profileName: imported.name)
        XCTAssertEqual(fake.writes.last?.profile, imported)
        let nextOriginals = try XCTUnwrap(try document(service.backupURL)["originals"] as? [[String: Any]])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: nextOriginals, options: .sortedKeys),
                       try JSONSerialization.data(withJSONObject: firstOriginals, options: .sortedKeys))
        XCTAssertEqual(fake.profiles, globals)

        _ = try await service.restoreLatest()
        XCTAssertEqual(fake.writes.last?.profile, baseline, "Restore uses the saved exact ID and name, without alias substitution")
        XCTAssertEqual(fake.tabs[0].profile.name, baseline.name)
        XCTAssertEqual(fake.tabs[0].bounds, bounds)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testCanonicalAndFilenameProfilesTogetherAreAmbiguousForInspectionAndApplication() async throws {
        let fake = backend()
        let filename = "OmniVibe-relic"
        fake.profiles.append(.init(id: 32, name: filename))
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)

        for requested in [theme.name, filename] {
            let status = await service.inspectImported(profileNames: [requested])
            XCTAssertFalse(status.isReady)
            XCTAssertTrue(status.missingNames.isEmpty)
            XCTAssertEqual(status.ambiguousNames, [requested])
            do { _ = try await service.apply(profileName: requested); XCTFail("Two aliases must not silently choose a profile") }
            catch TerminalProfileApplicationError.ambiguousProfile {}
            catch { XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testDuplicateFilenameProfilesAreAmbiguousEvenWhenRequestedByCanonicalName() async throws {
        let filename = "OmniVibe-relic"
        let fake = backend()
        fake.profiles = [baseline, .init(id: 30, name: filename), .init(id: 32, name: filename)]
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        let status = await service.inspectImported(profileNames: [theme.name])
        XCTAssertEqual(status.ambiguousNames, [theme.name])
        XCTAssertFalse(status.isReady)
        do { _ = try await service.apply(profileName: theme.name); XCTFail("Duplicate file imports must remain ambiguous") }
        catch TerminalProfileApplicationError.ambiguousProfile {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testOmniVibePrefixesDoNotMakeUnknownNamesTrustedThemeTargets() async throws {
        let fake = backend()
        let untrusted = ["OmniVibe / 用户配置", "OmniVibe-not-an-official-theme", "OmniVibe-relic-minimal-copy", "OmniVibe-RELIC"]
        for (offset, name) in untrusted.enumerated() { fake.profiles.append(.init(id: 60 + offset, name: name)) }
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        for name in untrusted {
            let status = await service.inspectImported(profileNames: [name])
            XCTAssertFalse(status.isReady, name)
            do { _ = try await service.apply(profileName: name); XCTFail("Untrusted profile must not be applied: \(name)") }
            catch TerminalProfileApplicationError.invalidProfileName {}
            catch { XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testOwnedFilenameCloneRenamedToCanonicalAliasIsNotSilentlyClaimed() async throws {
        let fake = backend()
        fake.profiles = [baseline, .init(id: theme.id, name: "OmniVibe-relic"), otherTheme]
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        _ = try await service.apply(profileName: theme.name)
        let cloneID = fake.tabs[0].profile.id
        let bytes = try Data(contentsOf: service.backupURL)
        fake.edit { $0[0].profile.name = theme.name }
        XCTAssertEqual(fake.tabs[0].profile.id, cloneID)
        let writes = fake.writes.count

        let status = await service.inspectImported(profileNames: [otherTheme.name])
        XCTAssertEqual(status.temporaryOriginalCount, 1)
        do { _ = try await service.apply(profileName: otherTheme.name); XCTFail("An alias-equivalent clone rename still changes its exact identity") }
        catch TerminalProfileApplicationError.needsBaselineSave(let count) { XCTAssertEqual(count, 1) }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(fake.writes.count, writes)
        XCTAssertEqual(try Data(contentsOf: service.backupURL), bytes)
    }

    @MainActor
    func testOwnedFilenameCloneWithChangedIDIsNotSilentlyClaimed() async throws {
        let fake = backend()
        fake.profiles = [baseline, .init(id: theme.id, name: "OmniVibe-relic"), otherTheme]
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        _ = try await service.apply(profileName: theme.name)
        let name = fake.tabs[0].profile.name
        let bytes = try Data(contentsOf: service.backupURL)
        fake.edit { $0[0].profile.id += 1 }
        XCTAssertEqual(fake.tabs[0].profile.name, name)
        let writes = fake.writes.count

        let status = await service.inspectImported(profileNames: [otherTheme.name])
        XCTAssertEqual(status.temporaryOriginalCount, 1)
        do { _ = try await service.apply(profileName: otherTheme.name); XCTFail("A matching filename does not prove ownership of a new clone") }
        catch TerminalProfileApplicationError.needsBaselineSave(let count) { XCTAssertEqual(count, 1) }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(fake.writes.count, writes)
        XCTAssertEqual(try Data(contentsOf: service.backupURL), bytes)
    }

    @MainActor
    func testFirstApplyRequiresActualPersistentIDMembershipRatherThanGuessingByNameOrNumber() async throws {
        let fake = backend()
        fake.edit { state in state[0].profile.id = 1000 }
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        let status = await service.inspectImported(profileNames: [theme.name])
        XCTAssertEqual(status.temporaryOriginalCount, 1)
        do { _ = try await service.apply(profileName: theme.name); XCTFail("Expected unresolved baseline rejection") }
        catch TerminalProfileApplicationError.needsBaselineSave(let count) { XCTAssertEqual(count, 1) }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(service.hasBackup)
        // A real enumerated global ID of 1000 is persistent, regardless of its value.
        fake.profiles[0].id = 1000
        _ = try await service.apply(profileName: theme.name)
        XCTAssertEqual(fake.tabs[0].profile.name, theme.name)
    }

    @MainActor
    func testApplySavesBaselineBeforeEveryWriteAndPreservesTTYWindowBoundsAndGlobalProfiles() async throws {
        let fake = backend(twoTabs: true)
        let root = try directory()
        fake.backupURL = root.appendingPathComponent("terminal-profile-backup.json")
        fake.reverseAfterNextWrite = true
        let globals = fake.profiles
        let service = TerminalProfileApplicationService(root: root, backend: fake)
        let receipt = try await service.apply(profileName: theme.name)
        XCTAssertEqual(receipt.tabCount, 2)
        XCTAssertFalse(receipt.restored)
        XCTAssertEqual(Set(fake.tabs.map { $0.tab.tty }), ["/dev/ttys001", "/dev/ttys002"])
        XCTAssertTrue(fake.tabs.allSatisfy { $0.tab.windowID == 101 && $0.profile.name == theme.name && $0.bounds == bounds })
        XCTAssertEqual(fake.profiles, globals)
        XCTAssertTrue(fake.backupExistedBeforeEveryWrite)
        XCTAssertFalse(fake.calledOnMainThread)
        XCTAssertEqual(fake.writes.map { $0.tab.tty }, ["/dev/ttys001", "/dev/ttys002"])
        XCTAssertEqual((try document(service.backupURL)["originals"] as? [Any])?.count, 2)
        XCTAssertTrue(service.hasBackup)
    }

    @MainActor
    func testRepeatedThemeSwitchAcceptsOnlyOwnedCloneAndRestoreKeepsFirstPersistentBaseline() async throws {
        let fake = backend()
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        _ = try await service.apply(profileName: theme.name)
        XCTAssertNotEqual(fake.tabs[0].profile.id, theme.id)
        let owned = await service.inspectImported(profileNames: [theme.name, otherTheme.name])
        XCTAssertTrue(owned.isReady)
        _ = try await service.apply(profileName: otherTheme.name)
        let restored = try await service.restoreLatest()
        XCTAssertTrue(restored.restored)
        XCTAssertEqual(restored.tabCount, 1)
        XCTAssertEqual(fake.tabs[0].profile.name, baseline.name)
        XCTAssertEqual(fake.tabs[0].bounds, bounds)
        XCTAssertFalse(service.hasBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.backupURL.path))
    }

    @MainActor
    func testUnownedTemporaryChangeAfterSuccessfulApplyIsNeverClaimedAsSafe() async throws {
        let fake = backend()
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        _ = try await service.apply(profileName: theme.name)
        fake.edit { $0[0].profile.name = "Unrelated temporary profile" }
        let writes = fake.writes.count
        do { _ = try await service.apply(profileName: otherTheme.name); XCTFail("Expected new baseline requirement") }
        catch TerminalProfileApplicationError.needsBaselineSave(let count) { XCTAssertEqual(count, 1) }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(fake.writes.count, writes)
        let status = await service.inspectImported(profileNames: [theme.name])
        XCTAssertEqual(status.temporaryOriginalCount, 1)
    }

    @MainActor
    func testPartialApplyFailureRollsBackEveryTTYAndWindowBounds() async throws {
        let fake = backend(twoTabs: true)
        fake.failWrites["/dev/ttys002"] = 1
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        do { _ = try await service.apply(profileName: theme.name); XCTFail("Expected partial apply failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("已回滚")) }
        XCTAssertTrue(fake.tabs.allSatisfy { $0.profile.name == baseline.name && $0.bounds == bounds })
        XCTAssertEqual(fake.writes.count, 4)
        XCTAssertEqual((try document(service.backupURL)["pendingRecovery"] as? [Any])?.count, 0)
        _ = try await service.apply(profileName: otherTheme.name)
        _ = try await service.restoreLatest()
    }

    @MainActor
    func testFailedRollbackKeepsBackupAndBlocksNewThemeUntilExplicitRestore() async throws {
        let fake = backend(twoTabs: true)
        fake.failWrites["/dev/ttys002"] = 2
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        do { _ = try await service.apply(profileName: theme.name); XCTFail("Expected rollback failure") } catch {}
        XCTAssertEqual((try document(service.backupURL)["pendingRecovery"] as? [Any])?.count, 1)
        let pending = await service.inspectImported(profileNames: [theme.name])
        XCTAssertFalse(pending.isReady)
        XCTAssertTrue(pending.errorMessage?.contains("先恢复") == true)
        let writes = fake.writes.count
        do { _ = try await service.apply(profileName: otherTheme.name); XCTFail("Expected pending recovery block") }
        catch { XCTAssertTrue(error.localizedDescription.contains("先恢复")) }
        XCTAssertEqual(fake.writes.count, writes)
        _ = try await service.restoreLatest()
        XCTAssertTrue(fake.tabs.allSatisfy { $0.profile.name == baseline.name })
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testProfileOrBoundsReadbackMismatchRollsBackWithoutClaimingSuccess() async throws {
        for wrongProfile in [true, false] {
            let fake = backend()
            fake.overrideNameAfterNextWrite = wrongProfile
            fake.ignoreBoundsWrites = wrongProfile ? 0 : 3
            let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
            do { _ = try await service.apply(profileName: theme.name); XCTFail("Expected verification failure") }
            catch { XCTAssertTrue(error.localizedDescription.contains("核验")) }
            XCTAssertEqual(fake.tabs[0].profile.name, baseline.name)
            XCTAssertEqual(fake.tabs[0].bounds, bounds)
        }
    }

    @MainActor
    func testTransientIgnoredBoundsWriteRetriesWithoutReapplyingTheProfile() async throws {
        let fake = backend()
        fake.ignoreNextBoundsWrite = true
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        _ = try await service.apply(profileName: theme.name)
        XCTAssertEqual(fake.writes.count, 1)
        XCTAssertEqual(fake.tabs[0].profile.name, theme.name)
        XCTAssertEqual(fake.tabs[0].bounds, bounds)
        _ = try await service.restoreLatest()
        XCTAssertEqual(fake.tabs[0].profile.name, baseline.name)
    }

    @MainActor
    func testRestoreNeverFollowsAMovedTTYIntoAnotherWindowAndCanRetryAfterItReturns() async throws {
        let fake = backend()
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        _ = try await service.apply(profileName: theme.name)
        fake.edit { $0[0].tab.windowID = 202 }
        let writes = fake.writes.count
        do { _ = try await service.restoreLatest(); XCTFail("Expected original window mismatch") } catch {}
        XCTAssertEqual(fake.writes.count, writes)
        XCTAssertEqual(fake.tabs[0].profile.name, theme.name)
        XCTAssertTrue(service.hasBackup)
        fake.edit { $0[0].tab.windowID = 101 }
        _ = try await service.restoreLatest()
        XCTAssertEqual(fake.tabs[0].profile.name, baseline.name)
    }

    @MainActor
    func testRestartAndMissingOriginalGlobalProfileCannotMutateTabs() async throws {
        let fake = backend()
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        _ = try await service.apply(profileName: theme.name)
        let writes = fake.writes.count
        fake.session = "new-terminal-session"
        do { _ = try await service.restoreLatest(); XCTFail("Expected session guard") }
        catch { XCTAssertTrue(error.localizedDescription.contains("重新启动")) }
        XCTAssertEqual(fake.writes.count, writes)
        fake.session = "terminal-session-1"
        fake.profiles.removeAll { $0.id == baseline.id }
        let missingOriginal = await service.inspectImported(profileNames: [theme.name])
        XCTAssertFalse(missingOriginal.isReady)
        XCTAssertTrue(missingOriginal.errorMessage?.contains("原终端配置") == true)
        do { _ = try await service.apply(profileName: otherTheme.name); XCTFail("Expected original profile guard") }
        catch { XCTAssertTrue(error.localizedDescription.contains("原终端配置")) }
        XCTAssertEqual(fake.writes.count, writes)
        XCTAssertTrue(service.hasBackup)
    }

    @MainActor
    func testMissingOrAmbiguousImportedProfileAndInvalidInputNeverWrite() async throws {
        let fake = backend()
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        for name in ["OmniVibe / Missing", "Basic", "OmniVibe / bad\nname"] {
            do { _ = try await service.apply(profileName: name); XCTFail("Expected invalid/missing profile") } catch {}
        }
        fake.profiles.append(.init(id: 32, name: theme.name))
        let status = await service.inspectImported(profileNames: [theme.name])
        XCTAssertEqual(status.ambiguousNames, [theme.name])
        XCTAssertFalse(status.isReady)
        do { _ = try await service.apply(profileName: theme.name); XCTFail("Expected ambiguous profile") } catch {}
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testInvalidBackupAndUnwritableBackupDirectoryFailBeforeFirstSwitch() async throws {
        let root = try directory()
        let blocked = root.appendingPathComponent("blocked")
        try Data("retain".utf8).write(to: blocked)
        let fake = backend()
        let service = TerminalProfileApplicationService(root: blocked, backend: fake)
        do { _ = try await service.apply(profileName: theme.name); XCTFail("Expected backup write failure") } catch {}
        XCTAssertTrue(fake.writes.isEmpty)
        let invalidRoot = try directory()
        let invalid = Data("corrupt but retained".utf8)
        try invalid.write(to: invalidRoot.appendingPathComponent("terminal-profile-backup.json"))
        let neverCalled = backend()
        let invalidService = TerminalProfileApplicationService(root: invalidRoot, backend: neverCalled)
        do { _ = try await invalidService.apply(profileName: theme.name); XCTFail("Expected invalid backup") } catch {}
        XCTAssertEqual(neverCalled.callCount, 0)
        XCTAssertEqual(try Data(contentsOf: invalidService.backupURL), invalid)
    }

    @MainActor
    func testExpiredSessionBackupCanBeArchivedWithoutAppleEventsAndNewSessionCanApply() async throws {
        let fake = backend()
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        _ = try await service.apply(profileName: theme.name)
        let bytes = try Data(contentsOf: service.backupURL)
        fake.session = "terminal-session-2"
        fake.edit { $0[0].profile = baseline }
        let calls = fake.callCount
        let writes = fake.writes.count
        let archive = try await service.archivePreviousSessionBackup()
        XCTAssertEqual(fake.callCount - calls, 1, "Archive reads only process-session metadata")
        XCTAssertEqual(fake.writes.count, writes)
        XCTAssertEqual(try Data(contentsOf: archive), bytes)
        XCTAssertTrue(archive.lastPathComponent.hasPrefix("terminal-profile-backup.archived-"))
        XCTAssertFalse(service.hasBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.backupURL.path))
        _ = try await service.apply(profileName: otherTheme.name)
        XCTAssertEqual(fake.tabs[0].profile.name, otherTheme.name)
        XCTAssertTrue(service.hasBackup)
        XCTAssertEqual(try Data(contentsOf: archive), bytes)
    }

    @MainActor
    func testCurrentSessionBackupCannotBeArchivedEvenWhenRecoveryIsPending() async throws {
        for pending in [false, true] {
            let fake = backend(twoTabs: true)
            if pending { fake.failWrites["/dev/ttys002"] = 2 }
            let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
            do { _ = try await service.apply(profileName: theme.name) }
            catch { XCTAssertTrue(pending) }
            let bytes = try Data(contentsOf: service.backupURL)
            let writes = fake.writes.count
            do { _ = try await service.archivePreviousSessionBackup(); XCTFail("Current session backup must remain recoverable") }
            catch { XCTAssertTrue(error.localizedDescription.contains("当前会话的备份不能归档")) }
            XCTAssertEqual(try Data(contentsOf: service.backupURL), bytes)
            XCTAssertEqual(fake.writes.count, writes)
            XCTAssertTrue(service.hasBackup)
        }
    }

    @MainActor
    func testCorruptBackupCannotBeSilentlyArchivedAndNeverQueriesTerminal() async throws {
        let root = try directory()
        let bytes = Data("not a valid profile backup".utf8)
        let url = root.appendingPathComponent("terminal-profile-backup.json")
        try bytes.write(to: url)
        let fake = backend()
        let service = TerminalProfileApplicationService(root: root, backend: fake)
        do { _ = try await service.archivePreviousSessionBackup(); XCTFail("Expected invalid backup rejection") } catch {}
        XCTAssertEqual(fake.callCount, 0)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [url.lastPathComponent])
    }

    @MainActor
    func testMainActorRemainsResponsiveAndConcurrentRequestsDoNotInterleave() async throws {
        let fake = backend()
        let gate = DispatchSemaphore(value: 0)
        fake.firstWriteGate = gate
        let service = TerminalProfileApplicationService(root: try directory(), backend: fake)
        let name = theme.name
        let operation = Task { try await service.apply(profileName: name) }
        for _ in 0..<500 {
            if !fake.writes.isEmpty { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(service.isBusy)
        XCTAssertTrue(Thread.isMainThread)
        do { _ = try await service.restoreLatest(); XCTFail("Expected busy rejection") } catch {}
        do { _ = try await service.archivePreviousSessionBackup(); XCTFail("Expected busy archive rejection") } catch {}
        let status = await service.inspectImported(profileNames: [name])
        XCTAssertNotNil(status.errorMessage)
        gate.signal()
        _ = try await operation.value
        XCTAssertFalse(service.isBusy)
        XCTAssertFalse(fake.calledOnMainThread)
    }

    func testScriptsUseOnlyMetadataAndTTYWindowIDsWithEscapedNames() throws {
        let key = TerminalProfileTabKey(windowID: 101, tty: "/dev/ttys001")
        let named = TerminalPersistentProfile(id: 30, name: "OmniVibe / 青 \"台\"\\path")
        let setter = try AppleScriptTerminalProfileApplicationBackend.setProfileScript(named, tab: key)
        let geometry = try AppleScriptTerminalProfileApplicationBackend.setBoundsScript(bounds, windowID: 101)
        let source = AppleScriptTerminalProfileApplicationBackend.snapshotScript + setter + geometry
        XCTAssertTrue(source.contains("repeat with savedProfile in settings sets"))
        XCTAssertTrue(source.contains("(bounds of terminalWindow) as list"))
        XCTAssertTrue(setter.contains("set requestedTTY to \"/dev/ttys001\""))
        XCTAssertTrue(setter.contains(#"set requestedProfileName to "OmniVibe / 青 \"台\"\\path""#))
        XCTAssertTrue(setter.contains("if matchingTabs is not 1 then error"))
        XCTAssertTrue(setter.contains("if matchingProfiles is not 1 then error"))
        XCTAssertGreaterThanOrEqual(setter.components(separatedBy: "tty of targetTab").count, 3)
        XCTAssertTrue(setter.contains("set current settings of targetTab to targetProfile"))
        XCTAssertTrue(geometry.contains("set bounds of targetWindow to {-500, 30, 300, 630}"))
        for forbidden in ["do script", "do shell script", "contents", "history", "make new", "open ", "import", "whose", "tab 1", "default settings", "startup settings", "activate"] {
            XCTAssertFalse(source.lowercased().contains(forbidden), forbidden)
        }
        XCTAssertThrowsError(try AppleScriptTerminalProfileApplicationBackend.setProfileScript(named, tab: .init(windowID: 0, tty: "tty")))
        XCTAssertThrowsError(try AppleScriptTerminalProfileApplicationBackend.setProfileScript(.init(id: Int.max, name: "Invalid"), tab: key))
    }

    func testMetadataDescriptorsAreTypedBoundedAndRejectDuplicateTTYOrInvalidBounds() throws {
        let profile = list([NSAppleEventDescriptor(int32: 1), NSAppleEventDescriptor(string: baseline.name)])
        let tab = list([NSAppleEventDescriptor(int32: 101), NSAppleEventDescriptor(string: "/dev/ttys001"),
                        NSAppleEventDescriptor(int32: 1), NSAppleEventDescriptor(string: baseline.name),
                        list([-500, 30, 300, 630].map { NSAppleEventDescriptor(int32: Int32($0)) })])
        let parsed = try AppleScriptTerminalProfileApplicationBackend.parseSnapshot(list([list([profile]), list([tab])]))
        XCTAssertEqual(parsed.tabs[0].bounds, bounds)
        XCTAssertEqual(parsed.tabs[0].tab.tty, "/dev/ttys001")
        XCTAssertThrowsError(try AppleScriptTerminalProfileApplicationBackend.parseSnapshot(list([list([profile]), list([tab, tab])])))
        let wrongID = list([NSAppleEventDescriptor(string: "1"), NSAppleEventDescriptor(string: baseline.name)])
        XCTAssertThrowsError(try AppleScriptTerminalProfileApplicationBackend.parseSnapshot(list([list([wrongID]), list([])])))
        XCTAssertThrowsError(try AppleScriptTerminalProfileApplicationBackend.parseSnapshot(NSAppleEventDescriptor(string: "not a list")))
        let invalid = TerminalProfileWindowBounds(left: 100, top: 100, right: 10, bottom: 10)
        XCTAssertThrowsError(try AppleScriptTerminalProfileApplicationBackend.setBoundsScript(invalid, windowID: 101))
    }

    private func list(_ elements: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (index, element) in elements.enumerated() { list.insert(element, at: index + 1) }
        return list
    }

    private func document(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}

private final class FakeTerminalProfileApplicationBackend: TerminalProfileApplicationBackend, @unchecked Sendable {
    struct Write { let tab: TerminalProfileTabKey; let profile: TerminalPersistentProfile }
    private let lock = NSLock()
    private var state: [TerminalProfileTabSnapshot]
    private var recordedWrites: [Write] = []
    private var calls = 0
    private var onMain = false
    private var backupPresent = true
    private var cloneID = 1000
    private var overrideTTY: String?
    var profiles: [TerminalPersistentProfile]
    var session = "terminal-session-1"
    var failWrites: [String: Int] = [:]
    var backupURL: URL?
    var reverseAfterNextWrite = false
    var overrideNameAfterNextWrite = false
    var ignoreNextBoundsWrite = false
    var ignoreBoundsWrites = 0
    var firstWriteGate: DispatchSemaphore?

    init(profiles: [TerminalPersistentProfile], tabs: [TerminalProfileTabSnapshot]) {
        self.profiles = profiles; state = tabs
    }
    var tabs: [TerminalProfileTabSnapshot] { locked { state } }
    var writes: [Write] { locked { recordedWrites } }
    var callCount: Int { locked { calls } }
    var calledOnMainThread: Bool { locked { onMain } }
    var backupExistedBeforeEveryWrite: Bool { locked { backupPresent } }
    func edit(_ body: (inout [TerminalProfileTabSnapshot]) -> Void) { locked { body(&state) } }

    func sessionIdentifier() throws -> String { locked { recordCall(); return session } }
    func snapshot() throws -> TerminalProfileApplicationSnapshot {
        locked {
            recordCall()
            var tabs = state
            if let tty = overrideTTY, let index = tabs.firstIndex(where: { $0.tab.tty == tty }) {
                tabs[index].profile.name = "Unexpected profile"
                overrideTTY = nil
            }
            return TerminalProfileApplicationSnapshot(profiles: profiles, tabs: tabs)
        }
    }

    func setProfile(_ profile: TerminalPersistentProfile, tab: TerminalProfileTabKey) throws {
        let gate = try locked { () throws -> DispatchSemaphore? in
            recordCall()
            guard let index = state.firstIndex(where: { $0.tab == tab }),
                  profiles.filter({ $0 == profile }).count == 1 else { throw Failure.missing }
            recordedWrites.append(.init(tab: tab, profile: profile))
            if let backupURL { backupPresent = backupPresent && FileManager.default.fileExists(atPath: backupURL.path) }
            cloneID += 1
            state[index].profile = TerminalPersistentProfile(id: cloneID, name: profile.name)
            for item in state.indices where state[item].tab.windowID == tab.windowID { state[item].bounds.right += 70 }
            if reverseAfterNextWrite { state.reverse(); reverseAfterNextWrite = false }
            if overrideNameAfterNextWrite { overrideTTY = tab.tty; overrideNameAfterNextWrite = false }
            let gate = firstWriteGate; firstWriteGate = nil
            return gate
        }
        if let gate { _ = gate.wait(timeout: .now() + 2) }
        try locked {
            if failWrites[tab.tty, default: 0] > 0 {
                failWrites[tab.tty, default: 0] -= 1
                throw Failure.write
            }
        }
    }

    func setBounds(_ bounds: TerminalProfileWindowBounds, windowID: Int) throws {
        try locked {
            recordCall()
            guard state.contains(where: { $0.tab.windowID == windowID }) else { throw Failure.missing }
            if ignoreNextBoundsWrite { ignoreNextBoundsWrite = false; return }
            if ignoreBoundsWrites > 0 { ignoreBoundsWrites -= 1; return }
            for index in state.indices where state[index].tab.windowID == windowID { state[index].bounds = bounds }
        }
    }
    private func recordCall() { calls += 1; onMain = onMain || Thread.isMainThread }
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    private enum Failure: Error { case missing, write }
}
