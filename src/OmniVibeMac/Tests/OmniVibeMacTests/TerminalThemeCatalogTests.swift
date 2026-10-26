import AppKit
import Foundation
import ImageIO
import XCTest
@testable import OmniVibeMac

final class TerminalThemeCatalogTests: XCTestCase {
    @MainActor
    func testCatalogLoadsAllThirteenCompleteSourcePalettesInStableOrder() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        XCTAssertEqual(catalog.themes.map(\.slug), TerminalThemeCatalog.slugs)
        XCTAssertEqual(catalog.themes.count, 13)
        for theme in catalog.themes {
            XCTAssertEqual(Set(theme.scheme.keys).subtracting(["name"]), Set(TerminalThemeCatalog.colorKeys))
            XCTAssertEqual(theme.imageOpacity, 0.12)
            XCTAssertEqual(theme.padding, "36, 32, 36, 32")
        }
    }

    @MainActor
    func testMissingInvalidAndDuplicateSourceColorsOrThemesAreRejected() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let valid = fixture.rows
        fixture.rows[0]["scheme"] = ["foreground": "#112233"]
        try fixture.writeManifest()
        XCTAssertThrowsError(try TerminalThemeCatalog(resourcesURL: fixture.resources))
        fixture.rows = valid
        var scheme = fixture.rows[0]["scheme"] as! [String: String]
        scheme["brightPurple"] = "not-a-color"
        fixture.rows[0]["scheme"] = scheme
        try fixture.writeManifest()
        XCTAssertThrowsError(try TerminalThemeCatalog(resourcesURL: fixture.resources))
        fixture.rows = valid
        fixture.rows[0]["slug"] = fixture.rows[1]["slug"]
        try fixture.writeManifest()
        XCTAssertThrowsError(try TerminalThemeCatalog(resourcesURL: fixture.resources))
        fixture.rows = Array(valid.dropLast())
        try fixture.writeManifest()
        XCTAssertThrowsError(try TerminalThemeCatalog(resourcesURL: fixture.resources))
    }

    @MainActor
    func testTraversalArtworkAndEscapingAssetSymlinkAreRejected() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        fixture.rows[0]["artwork"] = "../../outside.png"
        try fixture.writeManifest()
        XCTAssertThrowsError(try TerminalThemeCatalog(resourcesURL: fixture.resources))
        fixture.rows[0]["artwork"] = "skins/ink-jade/illustration.png"
        try fixture.writeManifest()
        let asset = fixture.resource("ink-jade", decorations: true)
        try FileManager.default.removeItem(at: asset)
        let outside = fixture.root.appendingPathComponent("outside.png")
        try fixture.decoratedData.write(to: outside)
        try FileManager.default.createSymbolicLink(at: asset, withDestinationURL: outside)
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        XCTAssertThrowsError(try catalog.exportProfiles(to: fixture.output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.output.path))
    }

    @MainActor
    func testExportsThirteenNativeProfilesWithExactANSIAndAppearanceFields() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        let receipt = try catalog.exportProfiles(to: fixture.output)
        XCTAssertEqual(receipt.profileURLs.count, 13)
        XCTAssertEqual(receipt.assetURLs.count, 13)
        for (theme, url) in zip(catalog.themes, receipt.profileURLs) {
            let profile = try fixture.profile(at: url)
            XCTAssertEqual(profile["type"] as? String, "Window Settings")
            XCTAssertEqual(profile["name"] as? String, "OmniVibe / " + theme.name)
            for mapping in TerminalThemeCatalog.ansiProfileKeys {
                try assertColor(profile[mapping.profile], equals: theme.scheme[mapping.source]!)
            }
            try assertColor(profile["TextColor"], equals: theme.scheme["foreground"]!)
            try assertColor(profile["TextBoldColor"], equals: theme.scheme["foreground"]!)
            try assertColor(profile["BackgroundColor"], equals: theme.scheme["background"]!)
            try assertColor(profile["CursorColor"], equals: theme.scheme["cursorColor"]!)
            try assertColor(profile["SelectionColor"], equals: theme.scheme["selectionBackground"]!)
            let fontData = try XCTUnwrap(profile["Font"] as? Data)
            let font = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: fontData))
            XCTAssertEqual(font.pointSize, 13)
            XCTAssertTrue(font.isFixedPitch)
            XCTAssertEqual(profile["FontAntialias"] as? Bool, true)
            XCTAssertEqual(profile["DynamicANSIForegroundColors"] as? Bool, false)
            XCTAssertEqual(profile["BackgroundSettingsForInactiveWindows"] as? Bool, false)
            XCTAssertEqual(profile["BackgroundAlphaInactive"] as? Double, 1)
            XCTAssertEqual(profile["BackgroundBlur"] as? Double, 0)
            XCTAssertNil(profile["CommandString"])
            XCTAssertNil(profile["RunCommandAsShell"])
            XCTAssertNil(profile["ShellExitAction"])
        }
    }

    @MainActor
    func testNativeBackgroundBookmarksResolveToStableCopiedPNGFiles() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        let first = try catalog.exportProfiles(to: fixture.output)
        for (url, asset) in zip(first.profileURLs, first.assetURLs) {
            let profile = try fixture.profile(at: url)
            let archived = try XCTUnwrap(profile["BackgroundImageBookmark"] as? Data)
            let bookmark = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSData.self, from: archived))
            var stale = false
            let resolved = try URL(resolvingBookmarkData: bookmark as Data, options: [.withoutUI, .withoutMounting],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
            XCTAssertEqual(resolved.standardizedFileURL, asset.standardizedFileURL)
            XCTAssertFalse(stale)
            XCTAssertEqual(try Data(contentsOf: asset), fixture.decoratedData)
            XCTAssertEqual(asset.deletingLastPathComponent(), fixture.output.appendingPathComponent("Assets"))
        }
        let second = try catalog.exportProfiles(to: fixture.output)
        XCTAssertEqual(first.assetURLs, second.assetURLs)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.output.appendingPathComponent("Assets").path).count, 13)
    }

    @MainActor
    func testDecorationsOffUsesPureFrameAssetsAndDoesNotApplySourcePointTwelveOpacity() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        let receipt = try catalog.exportProfiles(to: fixture.output, decorations: false)
        XCTAssertEqual(receipt.manifestURL.lastPathComponent, "manifest.json")
        XCTAssertTrue(receipt.profileURLs.allSatisfy { !$0.lastPathComponent.contains("-minimal") })
        XCTAssertEqual(try fixture.profile(at: receipt.profileURLs[0])["name"] as? String, "OmniVibe / " + catalog.themes[0].name)
        XCTAssertEqual(receipt.capabilities.windowOpacity, 1)
        XCTAssertEqual(receipt.capabilities.imageMode, "precomposed-frame-only")
        for asset in receipt.assetURLs {
            XCTAssertTrue(asset.lastPathComponent.contains("-frame-only-v1-"))
            XCTAssertEqual(try Data(contentsOf: asset), fixture.frameData)
        }
        let manifest = try fixture.manifest(at: receipt.manifestURL)
        for record in manifest.profiles {
            XCTAssertEqual(record.sourceImageOpacity, 0.12)
            XCTAssertEqual(record.appliedImageOpacity, 1)
            XCTAssertTrue(record.sourceImageResource.hasSuffix("-frame-only-v1.png"))
            XCTAssertTrue(record.animationResource.hasSuffix("-frame-only-v1.gif"))
        }
        try assertColor(fixture.profile(at: receipt.profileURLs[0])["BackgroundColor"],
                        equals: catalog.themes[0].scheme["background"]!)
    }

    @MainActor
    func testNamedDecoratedAndMinimalVariantsCoexistWithoutOverwritingProfilesOrManifests() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        let decorated = try catalog.exportProfiles(to: fixture.output, decorations: true, variantNames: true)
        let originalBytes = try decorated.profileURLs.map { try Data(contentsOf: $0) }
        let decoratedManifest = try Data(contentsOf: decorated.manifestURL)
        let minimal = try catalog.exportProfiles(to: fixture.output, decorations: false, variantNames: true)

        XCTAssertTrue(Set(decorated.profileURLs).isDisjoint(with: Set(minimal.profileURLs)))
        XCTAssertEqual(decorated.manifestURL.lastPathComponent, "manifest-decorated.json")
        XCTAssertEqual(minimal.manifestURL.lastPathComponent, "manifest-minimal.json")
        XCTAssertEqual(try Data(contentsOf: decorated.manifestURL), decoratedManifest)
        XCTAssertEqual(try decorated.profileURLs.map { try Data(contentsOf: $0) }, originalBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.output.path).filter { $0.hasSuffix(".terminal") }.count, 26)
        for (index, theme) in catalog.themes.enumerated() {
            XCTAssertEqual(try fixture.profile(at: decorated.profileURLs[index])["name"] as? String,
                           TerminalThemeCatalog.profileName(name: theme.name, decorations: true))
            XCTAssertEqual(try fixture.profile(at: minimal.profileURLs[index])["name"] as? String,
                           TerminalThemeCatalog.profileName(name: theme.name, decorations: false))
            XCTAssertEqual(minimal.profileURLs[index].lastPathComponent, "OmniVibe-\(theme.slug)-minimal.terminal")
        }
        XCTAssertTrue(try fixture.manifest(at: decorated.manifestURL).decorations)
        XCTAssertFalse(try fixture.manifest(at: minimal.manifestURL).decorations)
    }

    @MainActor
    func testVariantProfileNamesProvideExactApplyTargetsInCatalogOrder() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        XCTAssertEqual(catalog.profileNames(decorations: true), catalog.themes.map { "OmniVibe / " + $0.name })
        XCTAssertEqual(catalog.profileNames(decorations: false), catalog.themes.map { "OmniVibe / " + $0.name + " / 简洁" })
        XCTAssertEqual(TerminalThemeCatalog.profileName(name: "Relic", decorations: false), "OmniVibe / Relic / 简洁")
    }

    @MainActor
    func testTrustedAliasesMatchAllExportedFilenameAndPlistNames() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        let exports = try [true, false].flatMap { decorations in
            try catalog.exportProfiles(to: fixture.output, decorations: decorations, variantNames: true).profileURLs
        }
        XCTAssertEqual(exports.count, 26)
        XCTAssertEqual(Set(catalog.profileDefinitions.map(\.filenameName)).count, 26)
        for url in exports {
            let filename = url.deletingPathExtension().lastPathComponent
            let definition = try XCTUnwrap(catalog.profileDefinitions.first { $0.filenameName == filename })
            XCTAssertEqual(try fixture.profile(at: url)["name"] as? String, definition.canonicalName)
            XCTAssertTrue(TerminalThemeCatalog.slugs.contains(definition.slug))
            XCTAssertEqual(definition.names, [definition.canonicalName, filename])
        }
    }

    @MainActor
    func testResourceFreeOfficialDefinitionsStayAlignedWithBundledCatalog() throws {
        let catalog = try TerminalThemeCatalog(resourcesURL: ThemeResources.shared.root)
        XCTAssertEqual(TerminalThemeCatalog.bundledProfileDefinitions, catalog.profileDefinitions)
    }

    @MainActor
    func testReceiptDistinguishesExportFromImportApplicationAndNativeAnimation() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        let receipt = try catalog.exportProfiles(to: fixture.output)
        let manifest = try fixture.manifest(at: receipt.manifestURL)
        XCTAssertEqual(manifest.profiles.count, 13)
        XCTAssertEqual(manifest.capabilities.status, "exported-not-imported")
        XCTAssertFalse(manifest.capabilities.imported)
        XCTAssertFalse(manifest.capabilities.applied)
        XCTAssertFalse(manifest.capabilities.nativeGIFPlaybackVerified)
        XCTAssertEqual(manifest.capabilities.ansiColors, 16)
        XCTAssertTrue(manifest.profiles.allSatisfy(\.animationResourceBundled))
        XCTAssertTrue(manifest.profiles.allSatisfy { $0.colors.count == 20 && $0.profileSHA256.count == 64 && $0.imageSHA256.count == 64 })
    }

    @MainActor
    func testMissingOrInvalidLastAssetFailsBeforeAnyExportIsCreated() throws {
        let fixture = try TerminalCatalogFixture()
        defer { fixture.cleanup() }
        let asset = fixture.resource("wonderland", decorations: true)
        try FileManager.default.removeItem(at: asset)
        let catalog = try TerminalThemeCatalog(resourcesURL: fixture.resources)
        XCTAssertThrowsError(try catalog.exportProfiles(to: fixture.output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.output.path))
        try Data("not a PNG".utf8).write(to: asset)
        XCTAssertThrowsError(try catalog.exportProfiles(to: fixture.output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.output.path))
    }

    @MainActor
    private func assertColor(_ value: Any?, equals hex: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try XCTUnwrap(value as? Data, file: file, line: line)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data), file: file, line: line)
        let color = try XCTUnwrap(decoded.usingColorSpace(.sRGB), file: file, line: line)
        let expected = UInt32(hex.dropFirst(), radix: 16)!
        XCTAssertEqual(color.redComponent, CGFloat((expected >> 16) & 255) / 255, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(color.greenComponent, CGFloat((expected >> 8) & 255) / 255, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(color.blueComponent, CGFloat(expected & 255) / 255, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.0001, file: file, line: line)
    }
}

@MainActor
private final class TerminalCatalogFixture {
    let root: URL
    let resources: URL
    let output: URL
    let decoratedData: Data
    let frameData: Data
    var rows: [[String: Any]]

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeTerminalCatalogTests-\(UUID())", isDirectory: true)
        resources = root.appendingPathComponent("Resources", isDirectory: true)
        output = root.appendingPathComponent("ExportedProfiles", isDirectory: true)
        decoratedData = try Self.imageData(red: 0.1, type: "public.png")
        frameData = try Self.imageData(red: 0.4, type: "public.png")
        rows = TerminalThemeCatalog.slugs.reversed().map { slug in
            var scheme = Dictionary(uniqueKeysWithValues: TerminalThemeCatalog.colorKeys.enumerated().map { index, key in
                (key, String(format: "#%06X", 0x102030 + index * 0x030201))
            })
            scheme["name"] = "Scheme-" + slug
            return ["slug": slug, "name": "Theme-" + slug, "scheme": scheme,
                    "artwork": "skins/\(slug)/illustration.png", "imageOpacity": 0.12,
                    "padding": "36, 32, 36, 32", "decorationWidthDip": 24] as [String: Any]
        }
        let assetFolder = resources.appendingPathComponent(TerminalThemeCatalog.assetDirectory)
        try FileManager.default.createDirectory(at: assetFolder, withIntermediateDirectories: true)
        let gif = try Self.imageData(red: 0.2, type: "com.compuserve.gif")
        for slug in TerminalThemeCatalog.slugs {
            try decoratedData.write(to: resource(slug, decorations: true))
            try frameData.write(to: resource(slug, decorations: false))
            for decorated in [false, true] {
                try gif.write(to: resource(slug, decorations: decorated).deletingPathExtension().appendingPathExtension("gif"))
            }
        }
        try writeManifest()
    }

    func resource(_ slug: String, decorations: Bool) -> URL {
        resources.appendingPathComponent(TerminalThemeCatalog.assetDirectory)
            .appendingPathComponent(slug + (decorations ? "-c-v1.png" : "-frame-only-v1.png"))
    }

    func writeManifest() throws {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "skins": rows])
        try data.write(to: resources.appendingPathComponent(TerminalThemeCatalog.manifestResource))
    }

    func profile(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    }

    func manifest(at url: URL) throws -> TerminalProfileExportManifest {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TerminalProfileExportManifest.self, from: Data(contentsOf: url))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    private static func imageData(red: CGFloat, type: String) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1280, height: 754, bitsPerComponent: 8, bytesPerRow: 1280 * 4,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1280, height: 754))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
