import AppKit
import CryptoKit
import Foundation
import XCTest
@testable import OmniVibeMac

final class TerminalAutomaticRecoveryTests: XCTestCase {
    private let themeName = "OmniVibe / 黑神话：悟空 · 灵蕴法宝匣"

    func testNativeDuplicateScriptTargetsExactMetadataAndNeverExportsTerminalTextOrSwitchesProfiles() throws {
        let original = TerminalProfileTabSnapshot(tab: .init(windowID: 123, tty: "/dev/ttys009"),
            profile: .init(id: 1007, name: "Basic"), bounds: .init(left: 30, top: 40, right: 830, bottom: 640))
        let unique = "OmniVibe Recovery " + UUID().uuidString
        let script = try AppleScriptTerminalProfileApplicationBackend.duplicateProfileScript(original, named: unique)
        XCTAssertTrue(script.contains("/dev/ttys009"))
        XCTAssertTrue(script.contains("is not 1007"))
        XCTAssertTrue(script.contains("123"))
        XCTAssertTrue(script.contains("duplicate originalSettings to end of settings sets with properties"))
        XCTAssertTrue(script.contains(unique))
        for forbidden in ["contents", "history", "do script", "make new", "set current settings", "save ", "System Events"] {
            XCTAssertFalse(script.contains(forbidden), forbidden)
        }
        XCTAssertThrowsError(try AppleScriptTerminalProfileApplicationBackend.duplicateProfileScript(original, named: "Basic"))
    }

    @MainActor
    private func fixture(twoTabs: Bool = false, cursorColor: NSColor = .white) throws -> AutomaticRecoveryFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeAutomaticRecovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let zero = TerminalThemePalette.RGB(red: 0, green: 0, blue: 0)
        let full = TerminalThemePalette.RGB(red: 65_535, green: 65_535, blue: 65_535)
        let genericCursor = try XCTUnwrap(cursorColor.usingColorSpace(.genericRGB))
        let cursorValues = [genericCursor.redComponent, genericCursor.greenComponent, genericCursor.blueComponent]
            .map { UInt16(($0 * 65_535).rounded()) }
        let cursor = TerminalThemePalette.RGB(red: cursorValues[0], green: cursorValues[1], blue: cursorValues[2])
        let appearance = TerminalProfileAppearance(palette: .init(background: zero, normalText: full, boldText: full, cursor: cursor),
            fontName: "Menlo-Regular", fontSize: 13)
        let bounds = TerminalProfileWindowBounds(left: 30, top: 40, right: 830, bottom: 640)
        var tabs = [TerminalProfileTabSnapshot(tab: .init(windowID: 101, tty: "/dev/ttys001"),
            profile: .init(id: 1000, name: "Basic"), bounds: bounds)]
        if twoTabs {
            tabs.append(.init(tab: .init(windowID: 102, tty: "/dev/ttys002"),
                profile: .init(id: 1001, name: "Basic"), bounds: bounds))
        }
        let backend = AutomaticRecoveryBackend(profiles: [.init(id: 1, name: "Basic"), .init(id: 30, name: "OmniVibe-relic")],
            tabs: tabs, appearance: appearance)
        let preferences = try AutomaticRecoveryPreferences(backend: backend, cursorColor: cursorColor)
        let service = TerminalProfileApplicationService(root: root, backend: backend, profilePreferences: preferences)
        return AutomaticRecoveryFixture(root: root, backend: backend, preferences: preferences, service: service)
    }

    @MainActor
    func testNativeCopyRegistersCompletePrivateArchiveWithoutSwitchingOriginalTab() async throws {
        let context = try fixture()
        let originalTabs = context.backend.tabs
        let originalGlobals = context.backend.profiles
        let receipt = try await context.service.prepareAutomaticRecoveryBaselines()

        XCTAssertEqual(receipt.registeredTabCount, 1)
        XCTAssertEqual(receipt.nativeCopyCount, 1)
        XCTAssertEqual(receipt.manualBaselineCount, 0)
        XCTAssertFalse(receipt.manualBasis)
        XCTAssertEqual(context.backend.tabs, originalTabs)
        XCTAssertEqual(context.backend.profiles.prefix(originalGlobals.count), originalGlobals[...])
        XCTAssertEqual(context.backend.duplicates.count, 1)
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
        XCTAssertEqual(context.backend.boundsWrites, 0)
        XCTAssertFalse(context.service.hasBackup)
        let copy = try XCTUnwrap(context.backend.duplicates.first?.profile)
        XCTAssertNotEqual(copy.name, originalTabs[0].profile.name)
        XCTAssertEqual(context.backend.profiles.filter { $0.name == copy.name }, [copy])
        let entries = try registryEntries(context.root)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry["origin"] as? String, "nativeCopy")
        let persistent = try XCTUnwrap(entry["persistentProfile"] as? [String: Any])
        XCTAssertEqual(persistent["id"] as? Int, copy.id)
        XCTAssertEqual(persistent["name"] as? String, copy.name)
        let observed = try XCTUnwrap(entry["observedProfile"] as? [String: Any])
        XCTAssertEqual(observed["id"] as? Int, originalTabs[0].profile.id)
        let filename = try XCTUnwrap(entry["filename"] as? String)
        let archive = context.root.appendingPathComponent("TerminalRecoveryProfiles").appendingPathComponent(filename)
        let archived = try Data(contentsOf: archive)
        XCTAssertEqual(archived, context.preferences.generatedByName[copy.name])
        XCTAssertEqual(entry["sha256"] as? String, SHA256.hash(data: archived).map { String(format: "%02x", $0) }.joined())
        let profile = try XCTUnwrap(try PropertyListSerialization.propertyList(from: archived, format: nil) as? [String: Any])
        XCTAssertEqual(profile["UnknownPreservedSetting"] as? String, "private copy complete data")
        XCTAssertEqual(profile["BackgroundImagePath"] as? String, "/example/original-background.png")
        for mapping in TerminalThemeCatalog.ansiProfileKeys { XCTAssertNotNil(profile[mapping.profile] as? Data) }
        XCTAssertEqual(try permissions(archive), 0o600)
        XCTAssertEqual(try permissions(receipt.registryURL), 0o600)
        XCTAssertEqual(try permissions(archive.deletingLastPathComponent()), 0o700)
        let status = await context.service.inspectImported(profileNames: [themeName])
        XCTAssertTrue(status.isReady)
        XCTAssertEqual(status.temporaryOriginalCount, 0)
    }

    @MainActor
    func testNativeCopyBecomesDurableExactRestoreProfileBeforeApplyingTheme() async throws {
        let context = try fixture()
        let original = context.backend.tabs[0]
        _ = try await context.service.prepareAutomaticRecoveryBaselines()
        let recovery = try XCTUnwrap(context.backend.duplicates.first?.profile)
        let archive = try XCTUnwrap(try FileManager.default.contentsOfDirectory(
            at: context.root.appendingPathComponent("TerminalRecoveryProfiles"), includingPropertiesForKeys: nil).first)
        let archiveBytes = try Data(contentsOf: archive)
        context.backend.backupURL = context.service.backupURL

        _ = try await context.service.apply(profileName: themeName)
        XCTAssertTrue(context.backend.hadBackupBeforeAllWrites)
        let document = try json(context.service.backupURL)
        let saved = try XCTUnwrap((document["originals"] as? [[String: Any]])?.first)
        let profile = try XCTUnwrap(saved["profile"] as? [String: Any])
        XCTAssertEqual(profile["id"] as? Int, recovery.id)
        XCTAssertEqual(profile["name"] as? String, recovery.name)
        XCTAssertEqual(context.backend.profileWrites.last?.name, "OmniVibe-relic")
        let restored = try await context.service.restoreLatest()
        XCTAssertTrue(restored.restored)
        XCTAssertEqual(context.backend.profileWrites.last, recovery)
        XCTAssertEqual(context.backend.tabs[0].profile.name, recovery.name)
        XCTAssertEqual(context.backend.tabs[0].tab, original.tab)
        XCTAssertEqual(context.backend.tabs[0].bounds, original.bounds)
        XCTAssertEqual(try Data(contentsOf: archive), archiveBytes)
        XCTAssertFalse(context.service.hasBackup)
    }

    @MainActor
    func testSparseNativeProfileArchiveKeepsRawBytesAndRestoresUsingVerifiedAppearance() async throws {
        let context = try fixture()
        let original = context.backend.tabs[0]
        context.preferences.omitFont = true
        context.preferences.omitColors = true
        let receipt = try await context.service.prepareAutomaticRecoveryBaselines()
        XCTAssertEqual(receipt.nativeCopyCount, 1)
        XCTAssertEqual(context.backend.tabs, [original])
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
        let copied = try XCTUnwrap(context.backend.duplicates.first?.profile)
        let raw = try XCTUnwrap(context.preferences.generatedByName[copied.name])
        let fields = try XCTUnwrap(try PropertyListSerialization.propertyList(from: raw, format: nil) as? [String: Any])
        XCTAssertNil(fields["Font"])
        for key in ["BackgroundColor", "TextColor", "TextBoldColor", "CursorColor"] { XCTAssertNil(fields[key]) }
        let evidence = try XCTUnwrap(try registryEntries(context.root).first)
        let archive = context.root.appendingPathComponent("TerminalRecoveryProfiles")
            .appendingPathComponent(try XCTUnwrap(evidence["filename"] as? String))
        let digest = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(try Data(contentsOf: archive), raw, "Missing defaults must never be synthesized into the retained file")
        XCTAssertEqual(evidence["sha256"] as? String, digest)

        context.backend.backupURL = context.service.backupURL
        _ = try await context.service.apply(profileName: themeName)
        XCTAssertTrue(context.backend.hadBackupBeforeAllWrites)
        _ = try await context.service.restoreLatest()
        XCTAssertEqual(context.backend.profileWrites.last, copied)
        XCTAssertEqual(context.backend.tabs[0].tab, original.tab)
        XCTAssertEqual(context.backend.tabs[0].bounds, original.bounds)
        XCTAssertEqual(try Data(contentsOf: archive), raw)
        let restoredEvidence = try XCTUnwrap(try registryEntries(context.root).first)
        XCTAssertEqual(restoredEvidence["sha256"] as? String, digest)
    }

    @MainActor
    func testCalibratedGrayAndColoredProfileArchivesUseTerminalsGenericRGBComponents() async throws {
        for color in [NSColor(calibratedWhite: 0.5, alpha: 1),
                      NSColor(calibratedRed: 0.25, green: 0.45, blue: 0.65, alpha: 1)] {
            let context = try fixture(cursorColor: color)
            let srgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
            let srgbValues = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
                .map { Int(($0 * 65_535).rounded()) }
            let expected = context.backend.publicAppearance.palette.cursor
            XCTAssertGreaterThan(zip(srgbValues, [Int(expected.red), Int(expected.green), Int(expected.blue)])
                .map { abs($0 - $1) }.max() ?? 0, 512, "The fixture must detect an incorrect sRGB conversion")

            let receipt = try await context.service.prepareAutomaticRecoveryBaselines()
            XCTAssertEqual(receipt.nativeCopyCount, 1)
            XCTAssertTrue(context.backend.profileWrites.isEmpty)
            let copied = try XCTUnwrap(context.backend.duplicates.first?.profile)
            let raw = try XCTUnwrap(context.preferences.generatedByName[copied.name])
            let evidence = try XCTUnwrap(try registryEntries(context.root).first)
            let archive = context.root.appendingPathComponent("TerminalRecoveryProfiles")
                .appendingPathComponent(try XCTUnwrap(evidence["filename"] as? String))
            let digest = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(try Data(contentsOf: archive), raw)
            XCTAssertEqual(evidence["sha256"] as? String, digest)
            let savedAppearance = try JSONDecoder().decode(TerminalProfileAppearance.self,
                from: JSONSerialization.data(withJSONObject: try XCTUnwrap(evidence["appearance"])))
            XCTAssertTrue(savedAppearance.matches(context.backend.publicAppearance))

            _ = try await context.service.apply(profileName: themeName)
            _ = try await context.service.restoreLatest()
            XCTAssertEqual(context.backend.profileWrites.last, copied)
            XCTAssertEqual(try Data(contentsOf: archive), raw)
            XCTAssertEqual((try registryEntries(context.root).first)?["sha256"] as? String, digest)
        }
    }

    @MainActor
    func testSparseExportIsNotAcceptedAsAnExplicitManualRecoveryBaseline() async throws {
        let context = try fixture()
        let original = context.backend.tabs[0]
        let manualProfile = TerminalPersistentProfile(id: 77, name: "Independent manual recovery")
        context.backend.profiles.append(manualProfile)
        context.preferences.omitFont = true
        context.preferences.omitColors = true
        let sparseFile = context.root.appendingPathComponent("manual-original.terminal")
        let raw = try context.preferences.profileData(named: manualProfile.name)
        try raw.write(to: sparseFile)
        let choice = TerminalRecoveryBaselineChoice(sessionID: context.backend.session, tab: original.tab,
            observedProfile: original.profile, persistentProfile: manualProfile, exportedProfileURL: sparseFile)

        do { _ = try await context.service.registerRecoveryBaselines([choice]); XCTFail("Only a verified native copy may use public appearance for absent defaults") }
        catch TerminalProfileApplicationError.invalidRecoveryBaseline {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(context.backend.tabs, [original])
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
        XCTAssertEqual(context.backend.boundsWrites, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.registryURL.path))
        XCTAssertEqual(try Data(contentsOf: sparseFile), raw)
    }

    @MainActor
    func testPreferencesReadFailureRetryReusesExactNativeCopyBeforeArchivingSparseData() async throws {
        let context = try fixture()
        let original = context.backend.tabs[0]
        context.preferences.failure = .missingData
        do { _ = try await context.service.prepareAutomaticRecoveryBaselines(); XCTFail("First preferences read should fail") }
        catch {}
        let copied = try XCTUnwrap(context.backend.duplicates.first?.profile)
        XCTAssertEqual(context.backend.duplicates.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.registryURL.path))
        XCTAssertEqual(context.backend.tabs, [original])

        context.preferences.failure = nil
        context.preferences.omitFont = true
        context.preferences.omitColors = true
        let receipt = try await context.service.prepareAutomaticRecoveryBaselines()
        XCTAssertEqual(receipt.nativeCopyCount, 1)
        XCTAssertEqual(context.backend.duplicates.count, 1, "A verified same-session attempt must not duplicate the private profile again")
        XCTAssertEqual(context.backend.profiles.filter { $0.name == copied.name }, [copied])
        XCTAssertTrue(context.preferences.requests.allSatisfy { $0 == copied.name })
        let evidence = try XCTUnwrap(try registryEntries(context.root).first)
        let savedProfile = try XCTUnwrap(evidence["persistentProfile"] as? [String: Any])
        XCTAssertEqual(savedProfile["id"] as? Int, copied.id)
        XCTAssertEqual(savedProfile["name"] as? String, copied.name)
        let archive = context.root.appendingPathComponent("TerminalRecoveryProfiles")
            .appendingPathComponent(try XCTUnwrap(evidence["filename"] as? String))
        XCTAssertEqual(try Data(contentsOf: archive), context.preferences.generatedByName[copied.name])
        XCTAssertEqual(context.backend.tabs, [original])
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
        XCTAssertEqual(context.backend.boundsWrites, 0)
    }

    @MainActor
    func testUnsupportedNativeCopyStopsWithoutSwitchingOrRegistering() async throws {
        let context = try fixture()
        let originals = context.backend.tabs
        context.backend.unsupported = true
        do { _ = try await context.service.prepareAutomaticRecoveryBaselines(); XCTFail("Unsupported copying cannot produce a recovery claim") }
        catch {}
        XCTAssertEqual(context.backend.tabs, originals)
        XCTAssertTrue(context.backend.duplicates.isEmpty)
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
        XCTAssertEqual(context.backend.boundsWrites, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.registryURL.path))
    }

    @MainActor
    func testReturnedCopyMustBeTheExactNewPersistentProfileBeforeRegistration() async throws {
        let context = try fixture()
        let originals = context.backend.tabs
        context.backend.wrongReturnedProfile = true
        do { _ = try await context.service.prepareAutomaticRecoveryBaselines(); XCTFail("A different returned profile cannot be registered") }
        catch {}
        XCTAssertEqual(context.backend.tabs, originals)
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
        XCTAssertEqual(context.backend.boundsWrites, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.registryURL.path))
    }

    @MainActor
    func testOriginalPrivateObjectAndTerminalSessionAreRecheckedAfterNativeCopy() async throws {
        for changeSession in [false, true] {
            let context = try fixture()
            context.backend.changeOriginalDuringDuplicate = !changeSession
            context.backend.changeSessionDuringDuplicate = changeSession
            do { _ = try await context.service.prepareAutomaticRecoveryBaselines(); XCTFail("Changed original identity or session cannot be registered") }
            catch {}
            XCTAssertTrue(context.backend.profileWrites.isEmpty)
            XCTAssertEqual(context.backend.boundsWrites, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: context.registryURL.path))
        }
    }

    @MainActor
    func testMissingPersistentDataWrongExportNameAndWrongColorsNeverRegisterOrSwitch() async throws {
        for failure in AutomaticRecoveryPreferences.FailureMode.allCases {
            let context = try fixture()
            let originals = context.backend.tabs
            context.preferences.failure = failure
            do { _ = try await context.service.prepareAutomaticRecoveryBaselines(); XCTFail("Unverified persistent data must not become recovery evidence: \(failure)") }
            catch {}
            XCTAssertEqual(context.backend.tabs, originals)
            XCTAssertTrue(context.backend.profileWrites.isEmpty)
            XCTAssertEqual(context.backend.boundsWrites, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: context.registryURL.path))
        }
    }

    @MainActor
    func testPartialFailureRetainsFirstRegistrationAndRetryCopiesOnlyRemainingTab() async throws {
        let context = try fixture(twoTabs: true)
        let originals = context.backend.tabs
        let secondTTY = originals[1].tab.tty
        context.backend.failTTY = secondTTY
        do { _ = try await context.service.prepareAutomaticRecoveryBaselines(); XCTFail("Second copy should fail") }
        catch {}
        let firstEntries = try registryEntries(context.root)
        XCTAssertEqual(firstEntries.count, 1)
        let firstCopy = try XCTUnwrap(context.backend.duplicates.first?.profile)
        XCTAssertEqual(context.backend.duplicates.map(\.original.tab.tty), [originals[0].tab.tty])
        XCTAssertEqual(context.backend.tabs, originals)
        XCTAssertTrue(context.backend.profileWrites.isEmpty)

        context.backend.failTTY = nil
        let receipt = try await context.service.prepareAutomaticRecoveryBaselines()
        XCTAssertEqual(receipt.registeredTabCount, 1)
        XCTAssertEqual(receipt.nativeCopyCount, 1)
        XCTAssertEqual(receipt.manualBaselineCount, 0)
        XCTAssertEqual(context.backend.duplicates.map(\.original.tab.tty), originals.map(\.tab.tty))
        let completed = try registryEntries(context.root)
        XCTAssertEqual(completed.count, 2)
        XCTAssertEqual(completed.filter { ($0["persistentProfile"] as? [String: Any])?["id"] as? Int == firstCopy.id }.count, 1)
        XCTAssertEqual(context.backend.tabs, originals)
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
        XCTAssertEqual(context.backend.boundsWrites, 0)
        let status = await context.service.inspectImported(profileNames: [themeName])
        XCTAssertTrue(status.isReady)
    }

    @MainActor
    func testAlreadyPersistentOriginalNeedsNoNativeCopiesOrRegistration() async throws {
        let context = try fixture()
        context.backend.tabs[0].profile = .init(id: 1, name: "Basic")
        let receipt = try await context.service.prepareAutomaticRecoveryBaselines()
        XCTAssertEqual(receipt.registeredTabCount, 0)
        XCTAssertEqual(receipt.nativeCopyCount, 0)
        XCTAssertEqual(receipt.manualBaselineCount, 0)
        XCTAssertTrue(context.backend.duplicates.isEmpty)
        XCTAssertTrue(context.preferences.requests.isEmpty)
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
        XCTAssertEqual(context.backend.boundsWrites, 0)
    }

    @MainActor
    func testAppearanceModelOnlyCopiesAfterExplicitAutomaticBackupAction() async throws {
        let context = try fixture()
        let model = AppearanceModel(root: context.root, terminalProfileService: context.service)
        XCTAssertTrue(context.backend.duplicates.isEmpty)
        XCTAssertTrue(context.preferences.requests.isEmpty)
        model.prepareAutomaticTerminalRecoveryBaselines()
        XCTAssertTrue(model.terminalThemeBusy)
        await settle(model)
        XCTAssertEqual(context.backend.duplicates.count, 1)
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
        XCTAssertEqual(context.backend.boundsWrites, 0)
        XCTAssertFalse(model.terminalProfileLinked)
        XCTAssertEqual(model.terminalProfileImportStatus?.nativeCopyCount, 1)
        XCTAssertEqual(model.terminalProfileImportStatus?.manualBaselineCount, 0)
        XCTAssertTrue(model.terminalProfileStatus?.contains("1 个标签页创建原生配置副本") == true)
    }

    @MainActor
    func testAppearanceApplyAndRestoreReportNativeCopiesSeparatelyFromManualBaselines() async throws {
        let context = try fixture()
        _ = try await context.service.prepareAutomaticRecoveryBaselines()
        let model = AppearanceModel(root: context.root, terminalProfileService: context.service)
        model.applyFullTerminalTheme()
        await settle(model)
        XCTAssertTrue(model.terminalProfileLinked)
        XCTAssertTrue(model.terminalProfileStatus?.contains("1 个原生自动备份，0 个手动指定基准") == true)
        model.restoreFullTerminalTheme()
        await settle(model)
        XCTAssertFalse(model.terminalProfileLinked)
        XCTAssertTrue(model.terminalProfileStatus?.contains("1 个使用原生自动备份，0 个使用你指定的恢复基准") == true)
    }

    @MainActor
    func testDemoAutomaticBackupActionNeverContactsTerminalOrPreferences() throws {
        let context = try fixture()
        let model = AppearanceModel(demo: true, root: context.root, terminalProfileService: context.service)
        model.prepareAutomaticTerminalRecoveryBaselines()
        XCTAssertFalse(model.terminalThemeBusy)
        XCTAssertTrue(context.backend.duplicates.isEmpty)
        XCTAssertTrue(context.preferences.requests.isEmpty)
        XCTAssertTrue(context.backend.profileWrites.isEmpty)
    }

    @MainActor
    private func settle(_ model: AppearanceModel) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while model.terminalThemeBusy, ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(model.terminalThemeBusy)
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func registryEntries(_ root: URL) throws -> [[String: Any]] {
        try XCTUnwrap(try json(root.appendingPathComponent("terminal-recovery-baselines.json"))["entries"] as? [[String: Any]])
    }

    private func permissions(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber).intValue & 0o777
    }
}

private struct AutomaticRecoveryFixture {
    let root: URL
    let backend: AutomaticRecoveryBackend
    let preferences: AutomaticRecoveryPreferences
    let service: TerminalProfileApplicationService
    var registryURL: URL { root.appendingPathComponent("terminal-recovery-baselines.json") }
}

private enum AutomaticRecoveryTestError: Error { case unsupported, missingData, cannotCopy }

private final class AutomaticRecoveryBackend: TerminalProfileApplicationBackend, @unchecked Sendable {
    struct Duplicate { let original: TerminalProfileTabSnapshot; let profile: TerminalPersistentProfile }
    var profiles: [TerminalPersistentProfile]
    var tabs: [TerminalProfileTabSnapshot]
    let publicAppearance: TerminalProfileAppearance
    var session = "automatic-test-session"
    var duplicates: [Duplicate] = []
    var profileWrites: [TerminalPersistentProfile] = []
    var boundsWrites = 0
    var unsupported = false
    var wrongReturnedProfile = false
    var changeOriginalDuringDuplicate = false
    var changeSessionDuringDuplicate = false
    var failTTY: String?
    var backupURL: URL?
    var hadBackupBeforeAllWrites = true
    private var nextID = 7000

    init(profiles: [TerminalPersistentProfile], tabs: [TerminalProfileTabSnapshot], appearance: TerminalProfileAppearance) {
        self.profiles = profiles; self.tabs = tabs; publicAppearance = appearance
    }
    func sessionIdentifier() throws -> String { session }
    func snapshot() throws -> TerminalProfileApplicationSnapshot { .init(profiles: profiles, tabs: tabs) }
    func appearance(profile: TerminalPersistentProfile, tab: TerminalProfileTabKey?) throws -> TerminalProfileAppearance { publicAppearance }
    func duplicateProfile(_ original: TerminalProfileTabSnapshot, named: String) throws -> TerminalPersistentProfile {
        if unsupported { throw AutomaticRecoveryTestError.unsupported }
        guard failTTY != original.tab.tty, tabs.contains(original) else { throw AutomaticRecoveryTestError.cannotCopy }
        nextID += 1
        let copy = TerminalPersistentProfile(id: nextID, name: named)
        profiles.append(copy)
        duplicates.append(.init(original: original, profile: copy))
        if changeOriginalDuringDuplicate, let index = tabs.firstIndex(where: { $0.tab == original.tab }) { tabs[index].profile.id += 500 }
        if changeSessionDuringDuplicate { session = "another-terminal-session" }
        return wrongReturnedProfile ? .init(id: copy.id, name: copy.name + "-unexpected") : copy
    }
    func setProfile(_ profile: TerminalPersistentProfile, tab: TerminalProfileTabKey) throws {
        guard let index = tabs.firstIndex(where: { $0.tab == tab }), profiles.contains(profile) else { throw AutomaticRecoveryTestError.cannotCopy }
        if let backupURL { hadBackupBeforeAllWrites = hadBackupBeforeAllWrites && FileManager.default.fileExists(atPath: backupURL.path) }
        profileWrites.append(profile)
        nextID += 1
        tabs[index].profile = .init(id: nextID, name: profile.name)
    }
    func setBounds(_ bounds: TerminalProfileWindowBounds, windowID: Int) throws {
        boundsWrites += 1
        for index in tabs.indices where tabs[index].tab.windowID == windowID { tabs[index].bounds = bounds }
    }
}

private final class AutomaticRecoveryPreferences: TerminalProfilePreferencesReading, @unchecked Sendable {
    enum FailureMode: CaseIterable { case missingData, wrongName, wrongColor, wrongFont }
    let backend: AutomaticRecoveryBackend
    private let template: [String: Any]
    private let whiteArchive: Data
    private let wrongFontArchive: Data
    var failure: FailureMode?
    var omitFont = false
    var omitColors = false
    var requests: [String] = []
    var generatedByName: [String: Data] = [:]

    @MainActor
    init(backend: AutomaticRecoveryBackend, cursorColor: NSColor = .white) throws {
        self.backend = backend
        let black = try NSKeyedArchiver.archivedData(withRootObject: NSColor.black, requiringSecureCoding: true)
        whiteArchive = try NSKeyedArchiver.archivedData(withRootObject: NSColor.white, requiringSecureCoding: true)
        wrongFontArchive = try NSKeyedArchiver.archivedData(withRootObject: NSFont(name: "Menlo-Regular", size: 20)!, requiringSecureCoding: true)
        var values: [String: Any] = ["type": "Window Settings", "ProfileCurrentVersion": 2.07,
            "Font": try NSKeyedArchiver.archivedData(withRootObject: NSFont(name: "Menlo-Regular", size: 13)!, requiringSecureCoding: true),
            "BackgroundColor": black, "TextColor": whiteArchive, "TextBoldColor": whiteArchive,
            "CursorColor": try NSKeyedArchiver.archivedData(withRootObject: cursorColor, requiringSecureCoding: true),
            "UnknownPreservedSetting": "private copy complete data", "BackgroundImagePath": "/example/original-background.png"]
        for key in TerminalThemeCatalog.ansiProfileKeys { values[key.profile] = whiteArchive }
        template = values
    }
    func profileData(named: String) throws -> Data {
        requests.append(named)
        guard failure != .missingData, backend.profiles.filter({ $0.name == named }).count == 1 else {
            throw AutomaticRecoveryTestError.missingData
        }
        var profile = template
        profile["name"] = failure == .wrongName ? "Unrelated exported profile" : named
        if failure == .wrongColor { profile["BackgroundColor"] = whiteArchive }
        if failure == .wrongFont { profile["Font"] = wrongFontArchive }
        if omitFont { profile.removeValue(forKey: "Font") }
        if omitColors {
            for key in ["BackgroundColor", "TextColor", "TextBoldColor", "CursorColor"] { profile.removeValue(forKey: key) }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        generatedByName[named] = data
        return data
    }
}
