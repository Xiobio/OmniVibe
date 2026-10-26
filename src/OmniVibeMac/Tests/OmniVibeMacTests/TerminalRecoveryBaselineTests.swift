import AppKit
import Carbon
import XCTest
@testable import OmniVibeMac

final class TerminalRecoveryBaselineTests: XCTestCase {
    private var roots: [URL] = []
    private let original = TerminalPersistentProfile(id: 1000, name: "Basic")
    private let recovery = TerminalPersistentProfile(id: 7, name: "Original Recovery - A")
    private let theme = TerminalPersistentProfile(id: 30, name: "OmniVibe / 黑神话：悟空 · 灵蕴法宝匣")
    private let key = TerminalProfileTabKey(windowID: 101, tty: "/dev/ttys001")
    private let bounds = TerminalProfileWindowBounds(left: 30, top: 40, right: 830, bottom: 640)

    override func tearDownWithError() throws { for root in roots { try? FileManager.default.removeItem(at: root) } }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeRecoveryBaseline-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        roots.append(url); return url
    }

    @MainActor
    private func fixture() throws -> (URL, URL, RecoveryBaselineBackend, TerminalProfileApplicationService) {
        let root = try directory(), exported = root.appendingPathComponent("original.terminal")
        let colors: [(String, NSColor)] = [("BackgroundColor", .black), ("TextColor", .white), ("TextBoldColor", .white), ("CursorColor", .white)]
        var profile: [String: Any] = ["name": "Basic", "type": "Window Settings", "ProfileCurrentVersion": 2.07,
            "Font": try NSKeyedArchiver.archivedData(withRootObject: NSFont(name: "Menlo-Regular", size: 13)!, requiringSecureCoding: true),
            "UnknownPreservedSetting": "complete exported file", "BackgroundImagePath": "/example/original.png"]
        for (key, color) in colors { profile[key] = try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) }
        for key in TerminalThemeCatalog.ansiProfileKeys { profile[key.profile] = profile["TextColor"] }
        try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0).write(to: exported)
        let rgb0 = TerminalThemePalette.RGB(red: 0, green: 0, blue: 0)
        let rgb1 = TerminalThemePalette.RGB(red: 65_535, green: 65_535, blue: 65_535)
        let appearance = TerminalProfileAppearance(palette: .init(background: rgb0, normalText: rgb1, boldText: rgb1, cursor: rgb1),
            fontName: "Menlo-Regular", fontSize: 13)
        let backend = RecoveryBaselineBackend(profiles: [.init(id: 1, name: "Basic"), recovery, theme],
            tab: .init(tab: key, profile: original, bounds: bounds), appearance: appearance)
        return (root, exported, backend, TerminalProfileApplicationService(root: root, backend: backend))
    }

    private func choice(_ file: URL) -> TerminalRecoveryBaselineChoice {
        .init(sessionID: "test-session-1", tab: key, observedProfile: original, persistentProfile: recovery, exportedProfileURL: file)
    }

    @MainActor
    func testExplicitFileAndUniqueProfileResolvePrivateIDWithoutChangingTerminalDuringRegistration() async throws {
        let (root, file, backend, service) = try fixture()
        let options = try await service.recoveryBaselineOptions()
        XCTAssertEqual(options.unresolvedTabs.map(\.profile), [original])
        let before = try Data(contentsOf: file)
        let receipt = try await service.registerRecoveryBaselines([choice(file)])
        XCTAssertTrue(receipt.manualBasis)
        XCTAssertEqual(receipt.registeredTabCount, 1)
        XCTAssertEqual(backend.writes, 0)
        let archives = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("TerminalRecoveryProfiles"), includingPropertiesForKeys: nil)
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try Data(contentsOf: archives[0]), before)
        let status = await service.inspectImported(profileNames: [theme.name])
        XCTAssertTrue(status.isReady)
        XCTAssertEqual(status.manualBaselineCount, 1)
        XCTAssertEqual(status.temporaryOriginalCount, 0)
    }

    @MainActor
    func testLegacyManualRegistryWithoutOriginRemainsUsable() async throws {
        let (root, file, _, service) = try fixture()
        let receipt = try await service.registerRecoveryBaselines([choice(file)])
        var document = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: receipt.registryURL)) as? [String: Any])
        var entries = try XCTUnwrap(document["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "origin")
        document["entries"] = entries
        try JSONSerialization.data(withJSONObject: document, options: .sortedKeys).write(to: receipt.registryURL, options: .atomic)
        let status = await service.inspectImported(profileNames: [theme.name])
        XCTAssertTrue(status.isReady)
        XCTAssertEqual(status.manualBaselineCount, 1)
        XCTAssertEqual(status.nativeCopyCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("TerminalRecoveryProfiles").path))
    }

    @MainActor
    func testManualRecoveryBasisIsDurableBeforeSwitchAndSurvivesRestoreAndAnotherApply() async throws {
        let (root, file, backend, service) = try fixture()
        _ = try await service.registerRecoveryBaselines([choice(file)])
        backend.backupURL = service.backupURL
        let applied = try await service.apply(profileName: theme.name)
        XCTAssertEqual(applied.manualBaselineCount, 1)
        XCTAssertTrue(backend.hadBackupBeforeAllWrites)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: service.backupURL)) as! [String: Any]
        XCTAssertEqual((raw["manualBaselines"] as? [[String: Any]])?.first?["manualBasis"] as? Bool, true)
        let restored = try await service.restoreLatest()
        XCTAssertEqual(restored.manualBaselineCount, 1)
        XCTAssertEqual(backend.tab.profile.name, recovery.name)
        XCTAssertEqual(backend.tab.bounds, bounds)
        XCTAssertFalse(service.hasBackup)
        let restarted = TerminalProfileApplicationService(root: root, backend: backend)
        _ = try await restarted.apply(profileName: theme.name)
        XCTAssertEqual(backend.tab.profile.name, theme.name)
    }

    @MainActor
    func testFilenameThemeApplicationKeepsManualRecoveryIdentityAndCompleteOriginalArchive() async throws {
        let (root, file, backend, service) = try fixture()
        let imported = TerminalPersistentProfile(id: theme.id, name: "OmniVibe-relic")
        backend.profiles.removeAll { $0.id == theme.id }
        backend.profiles.append(imported)
        let originalBytes = try Data(contentsOf: file)
        _ = try await service.registerRecoveryBaselines([choice(file)])
        let archives = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("TerminalRecoveryProfiles"), includingPropertiesForKeys: nil)
        let archive = try XCTUnwrap(archives.first)
        backend.backupURL = service.backupURL
        let status = await service.inspectImported(profileNames: [theme.name])
        XCTAssertTrue(status.isReady)
        _ = try await service.apply(profileName: theme.name)
        XCTAssertEqual(backend.lastRequestedProfile, imported)
        XCTAssertTrue(backend.hadBackupBeforeAllWrites)
        let document = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: service.backupURL)) as? [String: Any])
        let originals = try XCTUnwrap(document["originals"] as? [[String: Any]])
        let savedProfile = try XCTUnwrap(originals.first?["profile"] as? [String: Any])
        XCTAssertEqual(savedProfile["id"] as? Int, recovery.id)
        XCTAssertEqual(savedProfile["name"] as? String, recovery.name)
        XCTAssertEqual(try Data(contentsOf: archive), originalBytes)
        _ = try await service.restoreLatest()
        XCTAssertEqual(backend.lastRequestedProfile, recovery)
        XCTAssertEqual(backend.tab.profile.name, recovery.name)
        XCTAssertEqual(try Data(contentsOf: archive), originalBytes)
        XCTAssertEqual(try Data(contentsOf: file), originalBytes)
    }

    @MainActor
    func testExportNamesAndUntrustedOmniVibePrefixesCannotBecomeManualRecoveryBaselines() async throws {
        let (root, file, backend, service) = try fixture()
        let reserved = TerminalThemeCatalog.bundledProfileDefinitions.flatMap { [$0.canonicalName, $0.filenameName] } +
            ["OmniVibe-user-copy", "OmniVibe / Untrusted copy"]
        for (index, name) in reserved.enumerated() { backend.profiles.append(.init(id: 50 + index, name: name)) }
        let options = try await service.recoveryBaselineOptions()
        XCTAssertFalse(options.profiles.contains { reserved.contains($0.name) })
        XCTAssertTrue(options.profiles.contains(recovery))
        for name in reserved {
            let selected = try XCTUnwrap(backend.profiles.first { $0.name == name })
            let invalid = TerminalRecoveryBaselineChoice(sessionID: "test-session-1", tab: key, observedProfile: original,
                persistentProfile: selected, exportedProfileURL: file)
            do { _ = try await service.registerRecoveryBaselines([invalid]); XCTFail("Theme namespace must not be a recovery basis: \(name)") }
            catch TerminalProfileApplicationError.invalidRecoveryBaseline {}
        }
        XCTAssertEqual(backend.writes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("terminal-recovery-baselines.json").path))
    }

    @MainActor
    func testSameNameExistingBasicIsNotSilentlyAcceptedAsManualRecoveryProfile() async throws {
        let (_, file, backend, service) = try fixture()
        let existing = TerminalRecoveryBaselineChoice(sessionID: "test-session-1", tab: key, observedProfile: original,
            persistentProfile: .init(id: 1, name: "Basic"), exportedProfileURL: file)
        do { _ = try await service.registerRecoveryBaselines([existing]); XCTFail("Expected unique newly named recovery basis") }
        catch TerminalProfileApplicationError.invalidRecoveryBaseline {}
        XCTAssertEqual(backend.writes, 0)
        XCTAssertFalse(service.hasBackup)
    }

    @MainActor
    func testWrongFileAppearanceOrGlobalMetadataNeverRegistersOrWrites() async throws {
        let (root, file, backend, service) = try fixture()
        backend.appearanceOverride = .init(palette: backend.appearanceValue.palette, fontName: "Monaco", fontSize: 13)
        do { _ = try await service.registerRecoveryBaselines([choice(file)]); XCTFail("Expected font mismatch") }
        catch TerminalProfileApplicationError.recoveryBaselineMismatch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("terminal-recovery-baselines.json").path))
        XCTAssertEqual(backend.writes, 0)
    }

    @MainActor
    func testChangedPrivateObjectOrSessionCannotReuseTheRegistration() async throws {
        let (_, file, backend, service) = try fixture()
        _ = try await service.registerRecoveryBaselines([choice(file)])
        backend.tab.profile.id += 1
        let status = await service.inspectImported(profileNames: [theme.name])
        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.temporaryOriginalCount, 1)
        backend.tab.profile = original
        backend.session = "another-session"
        let otherSession = await service.inspectImported(profileNames: [theme.name])
        XCTAssertFalse(otherSession.isReady)
        XCTAssertEqual(backend.writes, 0)
    }

    @MainActor
    func testModifiedRegisteredArchiveOrPersistentAppearanceFailsBeforeSwitch() async throws {
        let (root, file, backend, service) = try fixture()
        _ = try await service.registerRecoveryBaselines([choice(file)])
        backend.appearanceOverride = .init(palette: backend.appearanceValue.palette, fontName: "Monaco", fontSize: 14)
        do { _ = try await service.apply(profileName: theme.name); XCTFail("Expected changed metadata guard") }
        catch TerminalProfileApplicationError.recoveryBaselineMismatch {}
        backend.appearanceOverride = nil
        let archive = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("TerminalRecoveryProfiles"), includingPropertiesForKeys: nil)[0]
        try Data("changed".utf8).write(to: archive)
        do { _ = try await service.apply(profileName: theme.name); XCTFail("Expected retained archive guard") } catch {}
        XCTAssertEqual(backend.writes, 0)
    }

    @MainActor
    func testProfileApplicationAllowsInwardCharacterGridButRestorationKeepsOriginalGeometry() async throws {
        let (_, _, backend, service) = try fixture()
        backend.tab.profile = .init(id: 1, name: "Basic")
        backend.inwardGrid = true
        let receipt = try await service.apply(profileName: theme.name)
        XCTAssertEqual(receipt.gridAdjustedWindowCount, 1)
        XCTAssertEqual(backend.tab.bounds.right, bounds.right - 8)
        _ = try await service.restoreLatest()
        XCTAssertEqual(backend.tab.bounds, bounds)
    }

    @MainActor
    func testOutwardOverflowIsNeverAcceptedAsCharacterGridFit() async throws {
        let (_, _, backend, service) = try fixture()
        backend.tab.profile = .init(id: 1, name: "Basic")
        backend.outwardOverflow = true
        do { _ = try await service.apply(profileName: theme.name); XCTFail("Expected overflowing bounds rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("回滚")) }
        XCTAssertEqual(backend.tab.profile.name, "Basic")
        XCTAssertEqual(backend.tab.bounds, bounds)
        XCTAssertTrue(service.hasBackup)
    }

    func testAppearanceScriptIsReadOnlyAndGuardsTheExactProfileAndTTY() throws {
        let source = try AppleScriptTerminalProfileApplicationBackend.appearanceScript(profile: original, tab: key)
        XCTAssertTrue(source.contains("/dev/ttys001"))
        XCTAssertTrue(source.contains("(id of profileObject) as integer) is not 1000"))
        XCTAssertTrue(source.contains("font name of profileObject"))
        for forbidden in ["do script", "history", "contents", "make new", "set current settings"] { XCTAssertFalse(source.contains(forbidden)) }
    }
}

private final class RecoveryBaselineBackend: TerminalProfileApplicationBackend, @unchecked Sendable {
    var profiles: [TerminalPersistentProfile]
    var tab: TerminalProfileTabSnapshot
    let appearanceValue: TerminalProfileAppearance
    var appearanceOverride: TerminalProfileAppearance?
    var session = "test-session-1"
    var writes = 0
    var backupURL: URL?
    var hadBackupBeforeAllWrites = true
    var inwardGrid = false
    var outwardOverflow = false
    var lastRequestedProfile: TerminalPersistentProfile?
    private var temporaryID = 2000

    init(profiles: [TerminalPersistentProfile], tab: TerminalProfileTabSnapshot, appearance: TerminalProfileAppearance) {
        self.profiles = profiles; self.tab = tab; appearanceValue = appearance
    }
    func sessionIdentifier() throws -> String { session }
    func snapshot() throws -> TerminalProfileApplicationSnapshot { .init(profiles: profiles, tabs: [tab]) }
    func appearance(profile: TerminalPersistentProfile, tab: TerminalProfileTabKey?) throws -> TerminalProfileAppearance {
        appearanceOverride ?? appearanceValue
    }
    func setProfile(_ profile: TerminalPersistentProfile, tab key: TerminalProfileTabKey) throws {
        guard tab.tab == key, profiles.contains(profile) else { throw TerminalProfileApplicationError.invalidResponse }
        if let backupURL { hadBackupBeforeAllWrites = hadBackupBeforeAllWrites && FileManager.default.fileExists(atPath: backupURL.path) }
        writes += 1; temporaryID += 1
        lastRequestedProfile = profile
        tab.profile = .init(id: temporaryID, name: profile.name)
    }
    func setBounds(_ bounds: TerminalProfileWindowBounds, windowID: Int) throws {
        guard tab.tab.windowID == windowID else { throw TerminalProfileApplicationError.invalidResponse }
        tab.bounds = bounds
        if tab.profile.name.hasPrefix("OmniVibe / ") {
            if inwardGrid { tab.bounds.right -= 8; tab.bounds.bottom -= 12 }
            if outwardOverflow { tab.bounds.right += 8 }
        }
    }
}
