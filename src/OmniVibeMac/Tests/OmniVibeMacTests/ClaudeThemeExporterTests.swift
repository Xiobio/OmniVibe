import XCTest
@testable import OmniVibeMac

final class ClaudeThemeExporterTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDownWithError() throws { for root in roots { try? FileManager.default.removeItem(at: root) } }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeClaudeTheme-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        roots.append(url); return url
    }

    private func theme(background: String = "#000000", cursor: String = "#646464") -> TerminalThemeCatalog.Theme {
        .init(slug: "test", name: "Test", scheme: ["background": background, "cursorColor": cursor,
              "foreground": "#C8C8C8", "selectionBackground": "#ABCDEF"], artwork: "test.png", imageOpacity: 1,
              padding: nil, decorationWidthDip: nil)
    }

    private func fixture() throws -> (URL, URL, ClaudeThemeExporter) {
        let root = try directory(), config = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        return (root, config, ClaudeThemeExporter(root: root.appendingPathComponent("support"), configurationDirectory: config))
    }

    func testDocumentReproducesOriginalWindowsMessageBackgroundAndSelectionTokens() throws {
        let document = try ClaudeThemeExporter.document(for: theme())
        XCTAssertEqual(document.name, "OmniVibe")
        XCTAssertEqual(document.base, "dark")
        XCTAssertEqual(document.overrides, ["userMessageBackground": "#0C0C0C", "userMessageBackgroundHover": "#121212",
            "bashMessageBackgroundColor": "#141414", "memoryBackgroundColor": "#0C0C0C", "selectionBg": "#ABCDEF"])
        XCTAssertEqual(try ClaudeThemeExporter.document(for: theme(background: "#FFFFFF")).base, "light")
    }

    func testExplicitExportWritesOnlyTheCustomThemeAndExplainsInitialDirectoryRestart() throws {
        let (_, config, exporter) = try fixture()
        let settings = config.appendingPathComponent("settings.json"), contents = Data("{\"theme\":\"dark\",\"user\":\"preserve\"}".utf8)
        try contents.write(to: settings)
        let receipt = try exporter.export(theme: theme())
        XCTAssertTrue(receipt.requiresInitialRestart)
        XCTAssertTrue(exporter.hasBackup)
        XCTAssertEqual(try Data(contentsOf: settings), contents)
        let document = try JSONDecoder().decode(ClaudeThemeExporter.ThemeDocument.self, from: Data(contentsOf: receipt.themeURL))
        XCTAssertEqual(document.name, "OmniVibe")
        XCTAssertFalse(try exporter.export(theme: theme(background: "#111111")).requiresInitialRestart)
    }

    func testRepeatedThemesRetainFirstOriginalBytesAndRestoreThemExactly() throws {
        let (_, _, exporter) = try fixture()
        try FileManager.default.createDirectory(at: exporter.themeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{\n  \"name\": \"My original\", \"base\": \"light\"\n}\n".utf8)
        try original.write(to: exporter.themeURL)
        _ = try exporter.export(theme: theme())
        _ = try exporter.export(theme: theme(background: "#FFFFFF"))
        let receipt = try exporter.restoreLatest()
        XCTAssertTrue(receipt.restored)
        XCTAssertEqual(try Data(contentsOf: exporter.themeURL), original)
        XCTAssertFalse(exporter.hasBackup)
    }

    func testRestoringNewlyCreatedThemeRemovesOnlyTheUneditedGeneratedFile() throws {
        let (_, _, exporter) = try fixture()
        _ = try exporter.export(theme: theme())
        let neighbour = exporter.themeURL.deletingLastPathComponent().appendingPathComponent("my-theme.json")
        try Data("keep".utf8).write(to: neighbour)
        _ = try exporter.restoreLatest()
        XCTAssertFalse(FileManager.default.fileExists(atPath: exporter.themeURL.path))
        XCTAssertEqual(try Data(contentsOf: neighbour), Data("keep".utf8))
    }

    func testExternalEditsStopBothExportAndRestoreWithoutOverwritingTheUser() throws {
        let (_, _, exporter) = try fixture()
        _ = try exporter.export(theme: theme())
        let manual = Data("manual change".utf8)
        try manual.write(to: exporter.themeURL)
        for operation in [{ _ = try exporter.export(theme: self.theme(background: "#FFFFFF")) }, { _ = try exporter.restoreLatest() }] {
            XCTAssertThrowsError(try operation()) { guard case ClaudeThemeExportError.externalChange = $0 else { return XCTFail("Unexpected \($0)") } }
        }
        XCTAssertEqual(try Data(contentsOf: exporter.themeURL), manual)
        XCTAssertTrue(exporter.hasBackup)
    }

    func testInvalidBackupAndUnwritableBackupStopBeforeTouchingTheme() throws {
        let (root, config, exporter) = try fixture()
        try FileManager.default.createDirectory(at: exporter.backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("preserve invalid backup".utf8)
        try corrupt.write(to: exporter.backupURL)
        XCTAssertThrowsError(try exporter.export(theme: theme()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exporter.themeURL.path))
        XCTAssertEqual(try Data(contentsOf: exporter.backupURL), corrupt)
        let blocked = root.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blocked)
        let cannotBackup = ClaudeThemeExporter(root: blocked, configurationDirectory: config)
        XCTAssertThrowsError(try cannotBackup.export(theme: theme()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cannotBackup.themeURL.path))
    }

    func testThemeSymbolicLinkCannotOverwriteAnUnrelatedFile() throws {
        let (root, _, exporter) = try fixture()
        try FileManager.default.createDirectory(at: exporter.themeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let unrelated = root.appendingPathComponent("unrelated.json"), original = Data("leave alone".utf8)
        try original.write(to: unrelated)
        try FileManager.default.createSymbolicLink(at: exporter.themeURL, withDestinationURL: unrelated)
        XCTAssertThrowsError(try exporter.export(theme: theme()))
        XCTAssertEqual(try Data(contentsOf: unrelated), original)
    }

    func testConfigurationOverrideIsAbsoluteAndDoesNotDependOnWorkingDirectory() throws {
        let root = try directory(), override = root.appendingPathComponent("configured")
        let configured = ClaudeThemeExporter(root: root.appendingPathComponent("support"), environment: ["CLAUDE_CONFIG_DIR": override.path], home: root)
        XCTAssertEqual(configured.themeURL, override.appendingPathComponent("themes/omnivibe.json"))
        let relative = ClaudeThemeExporter(root: root, environment: ["CLAUDE_CONFIG_DIR": "relative"], home: root)
        XCTAssertEqual(relative.themeURL, root.appendingPathComponent(".claude/themes/omnivibe.json"))
    }

    func testMissingOrMalformedThemeColorIsRejectedBeforeCreatingFiles() throws {
        let (_, _, exporter) = try fixture()
        XCTAssertThrowsError(try exporter.export(theme: theme(cursor: "invalid")))
        XCTAssertFalse(exporter.hasBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exporter.themeURL.path))
    }

    func testAServiceForAnotherDestinationCannotReuseAndOverwriteTheOriginalBackup() throws {
        let (root, _, exporter) = try fixture()
        _ = try exporter.export(theme: theme())
        let backup = try Data(contentsOf: exporter.backupURL)
        let other = ClaudeThemeExporter(root: root.appendingPathComponent("support"), configurationDirectory: root.appendingPathComponent("other"))
        XCTAssertThrowsError(try other.export(theme: theme()))
        XCTAssertEqual(try Data(contentsOf: exporter.backupURL), backup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.themeURL.path))
    }
}
