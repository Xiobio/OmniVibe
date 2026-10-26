import AppKit
import Foundation
import XCTest
@testable import OmniVibeMac

final class AppearanceTerminalProfileTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (URL, TerminalThemeCatalog, ProfileUIBackend, TerminalProfileApplicationService) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeProfileUI-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let catalog = try TerminalThemeCatalog(resourcesURL: ThemeResources.shared.root)
        let names = catalog.profileNames(decorations: true) + catalog.profileNames(decorations: false)
        let fake = ProfileUIBackend(names: names)
        return (root, catalog, fake, TerminalProfileApplicationService(root: root, backend: fake))
    }

    @MainActor
    private func settle(_ model: AppearanceModel) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while ProcessInfo.processInfo.systemUptime < deadline {
            if !model.terminalThemeBusy { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Terminal UI operation did not finish")
    }

    @MainActor
    func testConstructionAndOldPreferencesNeverContactTerminalOrEnableLinking() throws {
        let (root, catalog, fake, service) = try fixture()
        let old = "{\"themeSlug\":\"relic\",\"decorations\":true,\"animate\":true}"
        try Data(old.utf8).write(to: root.appendingPathComponent("appearance.json"))
        let model = AppearanceModel(root: root, terminalProfileService: service, terminalCatalog: { catalog })
        XCTAssertFalse(model.terminalProfileLinked)
        XCTAssertFalse(model.terminalThemeBusy)
        XCTAssertNil(model.terminalProfileImportStatus)
        XCTAssertEqual(fake.calls, 0)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("appearance.json")), old)
    }

    @MainActor
    func testFullApplyPersistsLinkAndRestoreReturnsOriginalThenDisablesLink() async throws {
        let (root, catalog, fake, service) = try fixture()
        let model = AppearanceModel(root: root, terminalProfileService: service, terminalCatalog: { catalog })
        model.applyFullTerminalTheme()
        XCTAssertTrue(model.terminalThemeBusy)
        await settle(model)
        XCTAssertTrue(model.terminalProfileLinked)
        XCTAssertTrue(service.hasBackup)
        XCTAssertEqual(fake.current.profile.name, try name(catalog, slug: "relic", decorations: true))
        XCTAssertEqual(try preferences(root)["terminalProfileLinked"] as? Bool, true)
        let reloaded = AppearanceModel(root: root)
        XCTAssertTrue(reloaded.terminalProfileLinked)
        let callsBeforeReload = fake.calls
        XCTAssertEqual(fake.calls, callsBeforeReload)
        model.restoreFullTerminalTheme()
        await settle(model)
        XCTAssertFalse(model.terminalProfileLinked)
        XCTAssertFalse(service.hasBackup)
        XCTAssertEqual(fake.current.profile.name, "Original")
        XCTAssertEqual(try preferences(root)["terminalProfileLinked"] as? Bool, false)
    }

    @MainActor
    func testLinkedCombinedDraftAppliesOneMinimalProfileBeforePublishingBothFields() async throws {
        let (root, catalog, fake, service) = try fixture()
        let model = AppearanceModel(root: root, terminalProfileService: service, terminalCatalog: { catalog })
        model.applyFullTerminalTheme(); await settle(model)
        let previousWrites = fake.writes.count
        var result: Bool?
        model.setThemeAndDecorations("midnight", decorations: false) { result = $0 }
        XCTAssertEqual(model.themeSlug, "relic")
        XCTAssertTrue(model.decorations)
        XCTAssertNil(result)
        await settle(model)
        XCTAssertEqual(result, true)
        XCTAssertEqual(model.themeSlug, "midnight")
        XCTAssertFalse(model.decorations)
        XCTAssertEqual(fake.writes.count, previousWrites + 1)
        XCTAssertEqual(fake.current.profile.name, try name(catalog, slug: "midnight", decorations: false))
        XCTAssertEqual(try preferences(root)["themeSlug"] as? String, "midnight")
        XCTAssertEqual(try preferences(root)["decorations"] as? Bool, false)
    }

    @MainActor
    func testFailedLinkedApplyKeepsOldThemeDecorationsAndPersistedPreferences() async throws {
        let (root, catalog, fake, service) = try fixture()
        let model = AppearanceModel(root: root, terminalProfileService: service, terminalCatalog: { catalog })
        model.applyFullTerminalTheme(); await settle(model)
        let oldData = try Data(contentsOf: root.appendingPathComponent("appearance.json"))
        fake.remove(name: try name(catalog, slug: "midnight", decorations: false))
        var result: Bool?
        model.setThemeAndDecorations("midnight", decorations: false) { result = $0 }
        await settle(model)
        XCTAssertEqual(result, false)
        XCTAssertEqual(model.themeSlug, "relic")
        XCTAssertTrue(model.decorations)
        XCTAssertTrue(model.terminalProfileLinked)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("appearance.json")), oldData)
        XCTAssertTrue(model.terminalProfileStatus?.contains("未完成") == true)
    }

    @MainActor
    func testAllTerminalEntryPointsShareBusyGuardAndInspectionDoesNotWrite() async throws {
        let (root, catalog, fake, service) = try fixture()
        let model = AppearanceModel(root: root, terminalProfileService: service, terminalCatalog: { catalog })
        model.inspectTerminalProfiles()
        model.applyFullTerminalTheme(); model.restoreFullTerminalTheme(); model.prepareFullTerminalThemes()
        model.applyTerminalTheme(); model.restoreTerminalTheme(); model.archivePreviousTerminalProfileBackup()
        model.archivePreviousTerminalThemeBackup()
        model.setTheme("midnight")
        await settle(model)
        XCTAssertTrue(model.terminalProfileImportStatus?.isReady == true)
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(model.terminalProfileLinked)
        XCTAssertEqual(model.themeSlug, "relic")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("TerminalProfiles").path))
    }

    @MainActor
    func testInspectionExplainsMissingProfileAndUnresolvedOriginalWithoutApplying() async throws {
        let (root, catalog, fake, service) = try fixture()
        let missing = try name(catalog, slug: "midnight", decorations: false)
        fake.remove(name: missing)
        fake.makeOriginalTemporary()
        let model = AppearanceModel(root: root, terminalProfileService: service, terminalCatalog: { catalog })
        model.inspectTerminalProfiles(); await settle(model)
        XCTAssertEqual(model.terminalProfileImportStatus?.missingNames, [missing])
        XCTAssertEqual(model.terminalProfileImportStatus?.temporaryOriginalCount, 1)
        XCTAssertFalse(model.terminalProfileImportStatus?.isReady ?? true)
        model.applyFullTerminalTheme(); await settle(model)
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(model.terminalProfileLinked)
        XCTAssertFalse(service.hasBackup)
        XCTAssertTrue(model.terminalProfileStatus?.contains("无法独立定位并恢复") == true)
    }

    @MainActor
    func testPreparationRestoresQuickColorsThenExports26WithUnimportedSuiteAndOpensOnlyDirectory() async throws {
        let (root, catalog, fake, service) = try fixture()
        let quickFake = ProfileUIQuickBackend()
        let quick = TerminalThemeService(root: root, backend: quickFake)
        _ = try await quick.apply(theme: quickFake.changed)
        XCTAssertTrue(quick.hasBackup)
        var opened: [URL] = []
        let model = AppearanceModel(root: root, terminalThemeService: quick, terminalProfileService: service,
            terminalCatalog: { catalog }, openTerminalProfilesDirectory: { opened.append($0) })
        model.prepareFullTerminalThemes(); await settle(model)
        let directory = root.appendingPathComponent("TerminalProfiles", isDirectory: true)
        XCTAssertEqual(opened, [directory])
        XCTAssertEqual(fake.calls, 0)
        XCTAssertEqual(quickFake.current, quickFake.original)
        XCTAssertFalse(quick.hasBackup)
        let manifest = try JSONDecoder.iso8601.decode(TerminalProfileSuiteManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("suite-manifest.json")))
        XCTAssertEqual(manifest.profileCount, 26)
        XCTAssertEqual(Set(manifest.profileNames).count, 26)
        XCTAssertEqual(manifest.status, "exported-not-imported")
        XCTAssertFalse(manifest.imported); XCTAssertFalse(manifest.applied)
        XCTAssertEqual(Set(manifest.variantManifests), ["manifest-decorated.json", "manifest-minimal.json"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "terminal" }.count, 26)
        XCTAssertFalse(model.terminalProfileLinked)
    }

    @MainActor
    func testFailedQuickColorRestoreStopsPreparationAndRetainsBackup() async throws {
        let (root, catalog, fake, service) = try fixture()
        let quickFake = ProfileUIQuickBackend()
        let quick = TerminalThemeService(root: root, backend: quickFake)
        _ = try await quick.apply(theme: quickFake.changed)
        quickFake.rejectWrites = true
        var opened = false
        let model = AppearanceModel(root: root, terminalThemeService: quick, terminalProfileService: service,
            terminalCatalog: { catalog }, openTerminalProfilesDirectory: { _ in opened = true })
        model.prepareFullTerminalThemes(); await settle(model)
        XCTAssertFalse(opened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("TerminalProfiles").path))
        XCTAssertTrue(quick.hasBackup)
        XCTAssertEqual(fake.calls, 0)
        XCTAssertTrue(model.terminalProfileStatus?.contains("未完成") == true)
    }

    @MainActor
    func testClaudeLinkFollowsThemeAndRestoresTheOriginalFile() throws {
        let (root, catalog, _, service) = try fixture()
        let exporter = ClaudeThemeExporter(root: root, configurationDirectory: root.appendingPathComponent("claude"))
        try FileManager.default.createDirectory(at: exporter.themeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("existing custom theme".utf8)
        try original.write(to: exporter.themeURL)
        let model = AppearanceModel(root: root, terminalProfileService: service, terminalCatalog: { catalog }, claudeThemeExporter: exporter)
        XCTAssertFalse(model.claudeThemeLinked)
        model.enableClaudeThemeLink()
        XCTAssertTrue(model.claudeThemeLinked)
        model.setTheme("midnight")
        let generated = try JSONDecoder().decode(ClaudeThemeExporter.ThemeDocument.self, from: Data(contentsOf: exporter.themeURL))
        XCTAssertEqual(generated, try ClaudeThemeExporter.document(for: XCTUnwrap(catalog.themes.first { $0.slug == "midnight" })))
        XCTAssertEqual(try preferences(root)["claudeThemeLinked"] as? Bool, true)
        model.restoreClaudeTheme()
        XCTAssertFalse(model.claudeThemeLinked)
        XCTAssertEqual(try Data(contentsOf: exporter.themeURL), original)
    }

    @MainActor
    func testClaudeLinkPreservesAnExternalEditAndShowsAnActionableFailure() throws {
        let (root, catalog, _, service) = try fixture()
        let exporter = ClaudeThemeExporter(root: root, configurationDirectory: root.appendingPathComponent("claude"))
        let model = AppearanceModel(root: root, terminalProfileService: service, terminalCatalog: { catalog }, claudeThemeExporter: exporter)
        model.enableClaudeThemeLink()
        let external = Data("edited outside OmniVibe".utf8)
        try external.write(to: exporter.themeURL)
        model.setTheme("midnight")
        XCTAssertEqual(model.themeSlug, "midnight")
        XCTAssertEqual(try Data(contentsOf: exporter.themeURL), external)
        XCTAssertTrue(model.claudeThemeStatus?.contains("未更新") == true)
        XCTAssertTrue(exporter.hasBackup)
    }

    @MainActor
    private func name(_ catalog: TerminalThemeCatalog, slug: String, decorations: Bool) throws -> String {
        TerminalThemeCatalog.profileName(name: try XCTUnwrap(catalog.themes.first { $0.slug == slug }).name, decorations: decorations)
    }
    private func preferences(_ root: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("appearance.json"))) as? [String: Any])
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}

private final class ProfileUIBackend: TerminalProfileApplicationBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var globals: [TerminalPersistentProfile]
    private var state = TerminalProfileTabSnapshot(tab: .init(windowID: 101, tty: "/dev/ttys001"),
        profile: .init(id: 1, name: "Original"), bounds: .init(left: 30, top: 40, right: 830, bottom: 640))
    private var count = 0
    private var targets: [String] = []
    init(names: [String]) {
        globals = [.init(id: 1, name: "Original")] + names.enumerated().map { .init(id: $0.offset + 2, name: $0.element) }
    }
    var calls: Int { locked { count } }
    var current: TerminalProfileTabSnapshot { locked { state } }
    var writes: [String] { locked { targets } }
    func remove(name: String) { locked { globals.removeAll { $0.name == name } } }
    func makeOriginalTemporary() { locked { state.profile.id = 9999 } }
    func sessionIdentifier() throws -> String { locked { count += 1; return "profile-ui-session" } }
    func snapshot() throws -> TerminalProfileApplicationSnapshot { locked { count += 1; return .init(profiles: globals, tabs: [state]) } }
    func setProfile(_ profile: TerminalPersistentProfile, tab: TerminalProfileTabKey) throws {
        locked { count += 1; targets.append(profile.name); state.profile = .init(id: 1000 + count, name: profile.name) }
    }
    func setBounds(_ bounds: TerminalProfileWindowBounds, windowID: Int) throws { locked { count += 1; state.bounds = bounds } }
    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}

private final class ProfileUIQuickBackend: TerminalThemeBackend, @unchecked Sendable {
    let original: TerminalThemePalette
    let changed: TerminalThemePalette
    var current: TerminalThemePalette
    var rejectWrites = false
    init() {
        let zero = TerminalThemePalette.RGB(red: 0, green: 0, blue: 0)
        let one = TerminalThemePalette.RGB(red: 100, green: 200, blue: 300)
        original = .init(background: zero, normalText: zero, boldText: zero, cursor: zero)
        changed = .init(background: one, normalText: one, boldText: one, cursor: one)
        current = original
    }
    func sessionIdentifier() throws -> String { "quick-ui-session" }
    func usedProfiles() throws -> [TerminalProfileColors] { [.init(profileID: 1, colors: current)] }
    func colors(profileID: Int) throws -> TerminalThemePalette { current }
    func setColors(_ colors: TerminalThemePalette, profileID: Int) throws {
        if rejectWrites { throw TerminalThemeError.verificationFailed }
        current = colors
    }
}
