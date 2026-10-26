import AppKit
import CryptoKit
import Foundation
import ImageIO

/// The two names Terminal may use for one exported, official theme variant.
/// Aliases are generated from a validated catalog, never from a profile's name.
struct TerminalThemeProfileDefinition: Equatable, Sendable {
    let slug: String
    let decorations: Bool
    let canonicalName: String

    var filenameName: String { "OmniVibe-" + slug + (decorations ? "" : "-minimal") }
    var names: Set<String> { [canonicalName, filenameName] }

    /// Recovery profiles must be independently named outside our export namespace.
    static func reservedForTheme(_ name: String) -> Bool {
        name.hasPrefix("OmniVibe / ") || name.hasPrefix("OmniVibe-")
    }
}

/// Complete terminal palettes use the same calibrated source as Windows.
/// Exporting a profile never imports it, opens Terminal, or edits preferences.
struct TerminalThemeCatalog {
    static let slugs = ["ink-jade", "midnight", "cinnabar", "hextech", "tactical", "protocol", "adventure",
                        "arsenal", "relic", "starlight", "formation", "astral", "wonderland"]
    static let manifestResource = "themes/windows-terminal/skins.json"
    static let assetDirectory = "themes/windows-terminal/assets/refined-v1"
    static let ansiProfileKeys: [(source: String, profile: String)] = [
        ("black", "ANSIBlackColor"), ("red", "ANSIRedColor"), ("green", "ANSIGreenColor"),
        ("yellow", "ANSIYellowColor"), ("blue", "ANSIBlueColor"), ("purple", "ANSIMagentaColor"),
        ("cyan", "ANSICyanColor"), ("white", "ANSIWhiteColor"),
        ("brightBlack", "ANSIBrightBlackColor"), ("brightRed", "ANSIBrightRedColor"),
        ("brightGreen", "ANSIBrightGreenColor"), ("brightYellow", "ANSIBrightYellowColor"),
        ("brightBlue", "ANSIBrightBlueColor"), ("brightPurple", "ANSIBrightMagentaColor"),
        ("brightCyan", "ANSIBrightCyanColor"), ("brightWhite", "ANSIBrightWhiteColor")
    ]
    static let colorKeys = ansiProfileKeys.map(\.source) + ["foreground", "background", "cursorColor", "selectionBackground"]

    /// Resource-free fallback for direct service clients. The application passes
    /// definitions from the validated bundled catalog so its exported names agree.
    static let bundledProfileDefinitions: [TerminalThemeProfileDefinition] = {
        let names = ["墨玉机关", "玄夜青金", "朱砂藏锋", "英雄联盟 · 海克斯枢纽",
                     "三角洲行动 · 战术终端", "无畏契约 · 行动协议", "地下城与勇士 · 冒险装备栏",
                     "永劫无间 · 无间兵器匣", "黑神话：悟空 · 灵蕴法宝匣", "王者荣耀 · 星曜指挥台",
                     "金铲铲之战 · Agent 备战席", "原神 · 星旅背包", "梦幻西游 · 三界百宝袋"]
        return [true, false].flatMap { decorations in
            zip(slugs, names).map { slug, name in
                TerminalThemeProfileDefinition(slug: slug, decorations: decorations,
                    canonicalName: profileName(name: name, decorations: decorations))
            }
        }
    }()

    struct Theme: Decodable, Equatable, Sendable {
        let slug: String
        let name: String
        let scheme: [String: String]
        let artwork: String
        let imageOpacity: Double
        let padding: String?
        let decorationWidthDip: Double?

        func resource(decorations: Bool, animated: Bool = false) -> String {
            TerminalThemeCatalog.assetDirectory + "/" + slug + (decorations ? "-c-v1" : "-frame-only-v1") + (animated ? ".gif" : ".png")
        }
    }

    private struct Document: Decodable {
        let version: Int
        let skins: [Theme]
    }

    let resourcesURL: URL
    let themes: [Theme]

    init(resourcesURL: URL) throws {
        self.resourcesURL = resourcesURL.standardizedFileURL.resolvingSymlinksInPath()
        let manifest = try Self.resourceURL(Self.manifestResource, in: self.resourcesURL)
        guard FileManager.default.fileExists(atPath: manifest.path) else { throw TerminalProfileExportError.missingResource(Self.manifestResource) }
        let data = try Data(contentsOf: manifest)
        guard data.count <= 1_048_576 else { throw TerminalProfileExportError.invalidCatalog("主题目录过大。") }
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw TerminalProfileExportError.invalidCatalog("无法读取终端主题目录：\(error.localizedDescription)") }
        guard document.version == 1, document.skins.count == Self.slugs.count,
              Set(document.skins.map(\.slug)) == Set(Self.slugs) else {
            throw TerminalProfileExportError.invalidCatalog("终端主题目录必须包含 13 个不同的正式主题。")
        }
        for theme in document.skins {
            guard !theme.name.isEmpty, theme.imageOpacity.isFinite, (0...1).contains(theme.imageOpacity),
                  Self.colorKeys.allSatisfy({ Self.isHexColor(theme.scheme[$0]) }) else {
                throw TerminalProfileExportError.invalidCatalog("\(theme.slug) 缺少完整的 20 色配色或包含无效颜色。")
            }
            _ = try Self.resourceURL(theme.artwork, in: self.resourcesURL)
        }
        themes = Self.slugs.compactMap { slug in document.skins.first { $0.slug == slug } }
    }

    static func bundled(in bundle: Bundle = .main) throws -> Self {
        guard let resources = bundle.resourceURL else { throw TerminalProfileExportError.missingResource(manifestResource) }
        return try Self(resourcesURL: resources)
    }

    static func profileName(name: String, decorations: Bool) -> String {
        "OmniVibe / " + name + (decorations ? "" : " / 简洁")
    }

    /// Names emitted by exportProfiles(..., variantNames: true).
    func profileNames(decorations: Bool) -> [String] {
        themes.map { Self.profileName(name: $0.name, decorations: decorations) }
    }

    var profileDefinitions: [TerminalThemeProfileDefinition] {
        [true, false].flatMap { decorations in
            themes.map { TerminalThemeProfileDefinition(slug: $0.slug, decorations: decorations,
                canonicalName: Self.profileName(name: $0.name, decorations: decorations)) }
        }
    }

    /// Creates thirteen importable files plus a receipt manifest. Images are
    /// copied to content-addressed, stable paths before bookmarks are generated.
    /// The optional destination keeps tests entirely outside Application Support.
    @MainActor
    func exportProfiles(to directory: URL? = nil, decorations: Bool = true, variantNames: Bool = false) throws -> TerminalProfileExportReceipt {
        let output: URL
        if let directory { output = directory.standardizedFileURL }
        else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            output = support.appendingPathComponent("OmniVibe/TerminalProfiles", isDirectory: true)
        } else { throw TerminalProfileExportError.outputUnavailable }
        let assets = output.appendingPathComponent("Assets", isDirectory: true)
        let font = NSFont(name: "Menlo-Regular", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let fontData = try NSKeyedArchiver.archivedData(withRootObject: font, requiringSecureCoding: true)

        // Verify all dependencies before creating any output. Windows' .12
        // source calibration opacity must not be applied to precomposed images.
        let sources = try themes.map { theme -> PreparedAsset in
            let relative = theme.resource(decorations: decorations)
            let url = try Self.resourceURL(relative, in: resourcesURL)
            guard FileManager.default.fileExists(atPath: url.path) else { throw TerminalProfileExportError.missingResource(relative) }
            let data = try Data(contentsOf: url)
            guard data.count <= 32 * 1_048_576, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 1280,
                  (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 754,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw TerminalProfileExportError.invalidImage(relative)
            }
            let digest = Self.sha256(data)
            let filename = theme.slug + (decorations ? "-c-v1-" : "-frame-only-v1-") + digest + ".png"
            return PreparedAsset(data: data, source: relative, filename: filename, sha256: digest)
        }

        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        for asset in sources {
            let target = assets.appendingPathComponent(asset.filename)
            if let existing = try? Data(contentsOf: target), Self.sha256(existing) == asset.sha256 { continue }
            try asset.data.write(to: target, options: .atomic)
        }

        var profileFiles: [(url: URL, data: Data)] = []
        var records: [TerminalProfileExportRecord] = []
        for (theme, asset) in zip(themes, sources) {
            let image = assets.appendingPathComponent(asset.filename)
            let bookmark = try image.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            // Apple's built-in Solid Colors.terminal uses an archived NSData
            // bookmark, rather than a path string, for BackgroundImageBookmark.
            let archivedBookmark = try NSKeyedArchiver.archivedData(withRootObject: bookmark as NSData, requiringSecureCoding: true)
            var profile: [String: Any] = [
                "name": variantNames ? Self.profileName(name: theme.name, decorations: decorations) : "OmniVibe / " + theme.name,
                "type": "Window Settings",
                "Font": fontData,
                "FontAntialias": true,
                "DynamicANSIForegroundColors": false,
                "BackgroundImageBookmark": archivedBookmark,
                "BackgroundSettingsForInactiveWindows": false,
                "BackgroundAlphaInactive": 1.0,
                "BackgroundBlur": 0.0,
                "BackgroundBlurInactive": 0.0
            ]
            for mapping in Self.ansiProfileKeys { profile[mapping.profile] = try Self.archivedColor(theme.scheme[mapping.source]!) }
            for (source, key) in [("foreground", "TextColor"), ("foreground", "TextBoldColor"),
                                  ("background", "BackgroundColor"), ("cursorColor", "CursorColor"),
                                  ("selectionBackground", "SelectionColor")] {
                profile[key] = try Self.archivedColor(theme.scheme[source]!)
            }
            let filename = "OmniVibe-" + theme.slug + (!decorations && variantNames ? "-minimal" : "") + ".terminal"
            let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
            profileFiles.append((output.appendingPathComponent(filename), data))
            let animated = theme.resource(decorations: decorations, animated: true)
            records.append(TerminalProfileExportRecord(slug: theme.slug, name: theme.name, profileFilename: filename,
                profileSHA256: Self.sha256(data), imageFilename: "Assets/" + asset.filename, imageSHA256: asset.sha256,
                sourceImageResource: asset.source, sourceArtwork: theme.artwork,
                sourceImageOpacity: theme.imageOpacity, appliedImageOpacity: 1,
                colors: theme.scheme.filter { Self.colorKeys.contains($0.key) },
                animationResource: animated, animationResourceBundled: FileManager.default.fileExists(atPath: try Self.resourceURL(animated, in: resourcesURL).path)))
        }
        for file in profileFiles { try file.data.write(to: file.url, options: .atomic) }
        let capabilities = TerminalProfileExportCapabilities(
            status: "exported-not-imported", imported: false, applied: false,
            ansiColors: 16, fontName: font.fontName, fontSizePoints: font.pointSize, windowOpacity: 1,
            boldTextPolicy: "matches-foreground", imageMode: decorations ? "precomposed-artwork" : "precomposed-frame-only",
            nativeGIFPlaybackVerified: false, animationNote: "GIF resources are retained for preview and future compatibility checks; exported Terminal profiles use static PNG only.",
            compatibilityNote: "Generated from Apple's built-in .terminal profile field format. User import and target macOS rendering remain separate validation steps; Windows padding, chrome and shader behavior are not implied.")
        let manifestFilename = variantNames ? (decorations ? "manifest-decorated.json" : "manifest-minimal.json") : "manifest.json"
        let manifestURL = output.appendingPathComponent(manifestFilename)
        let manifest = TerminalProfileExportManifest(schemaVersion: 1, exportedAt: Date(), decorations: decorations,
                                                     capabilities: capabilities, profiles: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return TerminalProfileExportReceipt(directoryURL: output, profileURLs: profileFiles.map(\.url),
            assetURLs: sources.map { assets.appendingPathComponent($0.filename) }, manifestURL: manifestURL, capabilities: capabilities)
    }

    private struct PreparedAsset {
        let data: Data
        let source: String
        let filename: String
        let sha256: String
    }

    private static func isHexColor(_ value: String?) -> Bool {
        guard let value, value.utf8.count == 7, value.first == "#" else { return false }
        return value.dropFirst().unicodeScalars.allSatisfy { (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value) }
    }

    private static func resourceURL(_ relative: String, in root: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\"),
              !relative.split(separator: "/").contains("..") else { throw TerminalProfileExportError.invalidResourcePath(relative) }
        let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/") else {
            throw TerminalProfileExportError.invalidResourcePath(relative)
        }
        return url
    }

    private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    @MainActor
    private static func archivedColor(_ hex: String) throws -> Data {
        guard let value = UInt32(hex.dropFirst(), radix: 16) else { throw TerminalProfileExportError.invalidCatalog("无效颜色：\(hex)") }
        let color = NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                            blue: CGFloat(value & 255) / 255, alpha: 1)
        return try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
    }
}

struct TerminalProfileExportCapabilities: Codable, Equatable, Sendable {
    let status: String
    let imported: Bool
    let applied: Bool
    let ansiColors: Int
    let fontName: String
    let fontSizePoints: Double
    let windowOpacity: Double
    let boldTextPolicy: String
    let imageMode: String
    let nativeGIFPlaybackVerified: Bool
    let animationNote: String
    let compatibilityNote: String
}

struct TerminalProfileExportRecord: Codable, Equatable, Sendable {
    let slug: String
    let name: String
    let profileFilename: String
    let profileSHA256: String
    let imageFilename: String
    let imageSHA256: String
    let sourceImageResource: String
    let sourceArtwork: String
    let sourceImageOpacity: Double
    let appliedImageOpacity: Double
    let colors: [String: String]
    let animationResource: String
    let animationResourceBundled: Bool
}

struct TerminalProfileExportManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let decorations: Bool
    let capabilities: TerminalProfileExportCapabilities
    let profiles: [TerminalProfileExportRecord]
}

struct TerminalProfileExportReceipt: Equatable, Sendable {
    let directoryURL: URL
    let profileURLs: [URL]
    let assetURLs: [URL]
    let manifestURL: URL
    let capabilities: TerminalProfileExportCapabilities
}

enum TerminalProfileExportError: LocalizedError {
    case missingResource(String), invalidCatalog(String), invalidResourcePath(String), invalidImage(String), outputUnavailable

    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .missingResource(let path): return "终端主题资源缺失：\(path)。请重新构建完整应用。"
            case .invalidCatalog(let detail): return detail
            case .invalidResourcePath(let path): return "终端主题资源路径无效：\(path)"
            case .invalidImage(let path): return "终端静态背景无法解码或尺寸不是 1280 × 754：\(path)"
            case .outputUnavailable: return "无法确定终端主题导出目录。"
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
