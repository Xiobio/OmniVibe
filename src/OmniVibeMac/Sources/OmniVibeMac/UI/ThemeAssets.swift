import AppKit
import Combine
import ImageIO
import OmniVibeCore

struct ThemeDefinition: Identifiable {
    let slug: String
    let name: String
    let subtitle: String
    let dockTitle: String
    let overviewTitle: String
    let family: String
    let background: NSColor
    let surface: NSColor
    let elevated: NSColor
    let text: NSColor
    let muted: NSColor
    let accent: NSColor
    let border: NSColor
    let secondary: NSColor
    let running: NSColor
    let waiting: NSColor
    let ready: NSColor
    let error: NSColor
    let unknown: NSColor
    let cardBackground: NSColor
    let cardText: NSColor
    let artwork: String
    var id: String { slug }

    fileprivate init(_ values: [String: Any]) {
        func string(_ key: String, _ fallback: String = "") -> String { values[key] as? String ?? fallback }
        func color(_ key: String, _ fallback: String = "#C1B79C") -> NSColor { NSColor(themeHex: string(key, fallback)) }
        slug = string("slug", "relic")
        name = string("name", "黑神话：悟空 · 灵蕴法宝匣")
        subtitle = string("subtitle", "玄岩石龛 · 錾金灵蕴")
        dockTitle = string("dockTitle", "灵蕴法宝匣")
        overviewTitle = string("overviewTitle", "灵蕴器物图录")
        family = string("family", "relic")
        background = color("background", "#1A1B19")
        surface = color("surface", "#2C2C27")
        elevated = color("elevated", "#414035")
        text = color("text", "#E8DDC3")
        muted = color("muted")
        accent = color("accent", "#D6B674")
        border = color("border", "#98855D")
        secondary = color("secondary", "#ADBA9A")
        running = color("running", "#B1CEAD")
        waiting = color("waiting", "#EBD08B")
        ready = color("ready", "#CADDAE")
        error = color("error", "#F3A08A")
        unknown = color("unknown", "#C2C1AF")
        cardBackground = color("cardBackground", "#292A25")
        cardText = color("cardText", "#E8DDC3")
        artwork = string("artwork", "skins/relic/illustration.png")
    }

    static let relic = ThemeDefinition([:])
}

struct EquipmentOption: Identifiable {
    let id: String
    let name: String
    let kind: String
    let imagePath: String
    var image: String { imagePath }
}

extension NSColor {
    convenience init(themeHex: String) {
        let hex = themeHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(hex, radix: 16) ?? 0xC1B79C
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

/// Reads the same catalog and alpha artwork that the Windows application uses.
/// The bounded decoded cache is separate from the untouched source resources.
@MainActor
final class ThemeResources {
    static let shared = ThemeResources()
    private(set) var themes: [ThemeDefinition] = []
    private(set) var assetWarning: String?
    let root: URL
    private var equipment: [String: [EquipmentOption]] = [:]
    private var identityFiles: [String: String] = [:]
    private let cache = NSCache<NSString, NSImage>()
    private var failedImages = Set<String>()

    private init() {
        let bundle = Bundle.main
        if bundle.bundleURL.pathExtension.lowercased() == "app" {
            root = bundle.resourceURL ?? bundle.bundleURL.appendingPathComponent("Contents/Resources")
        } else {
            // swift run / XCTest have no app Resources directory. This fixed
            // source-relative root does not conceal missing packaged resources.
            var sourceRoot = URL(fileURLWithPath: #filePath)
            for _ in 0..<6 { sourceRoot.deleteLastPathComponent() }
            root = sourceRoot
        }
        cache.countLimit = 96
        cache.totalCostLimit = 48 * 1024 * 1024
        loadCatalogs()
    }

    func theme(_ slug: String) -> ThemeDefinition {
        themes.first(where: { $0.slug == slug }) ?? themes.first(where: { $0.slug == "relic" }) ?? .relic
    }

    func equipmentItems(themeSlug: String) -> [EquipmentOption] { equipment[themeSlug] ?? [] }

    func image(_ relativePath: String) -> NSImage? { decoded(relativePath, trimAlpha: false) }

    func thumbnail(_ relativePath: String, maxEdge: Int = 320) -> NSImage? {
        decoded(relativePath, trimAlpha: false, maxEdge: min(512, max(1, maxEdge)))
    }

    func equipmentImage(_ option: EquipmentOption) -> NSImage? { decoded(option.imagePath, trimAlpha: false, maxEdge: 512) }

    func managedImage(at url: URL) -> NSImage? {
        let key = ("managed:" + url.path) as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let trimmed = Self.trim(image) ?? image
        let result = NSImage(cgImage: trimmed, size: NSSize(width: CGFloat(trimmed.width), height: CGFloat(trimmed.height)))
        cache.setObject(result, forKey: key, cost: trimmed.width * trimmed.height * 4)
        return result
    }

    func entity(for slot: TaskSlot, themeSlug: String) -> NSImage? {
        let items = equipmentItems(themeSlug: themeSlug)
        guard !items.isEmpty else { return nil }
        return equipmentImage(items[min(max(slot.number - 1, 0), items.count - 1)])
    }

    func identity(themeSlug: String) -> NSImage? {
        let file = identityFiles[themeSlug] ?? "\(themeSlug)-original-v3.png"
        return decoded("skins/identities/\(file)", trimAlpha: false, maxEdge: 512)
            ?? decoded("skins/native-v2/\(themeSlug)/core.png", trimAlpha: false, maxEdge: 512)
    }

    private func loadCatalogs() {
        var warnings: [String] = []
        do {
            let data = try Data(contentsOf: root.appendingPathComponent("skins/catalog.json"))
            guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], !entries.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let order = ["ink-jade", "midnight", "cinnabar", "hextech", "tactical", "protocol", "adventure", "arsenal", "relic", "starlight", "formation", "astral", "wonderland"]
            themes = entries.map(ThemeDefinition.init).sorted {
                (order.firstIndex(of: $0.slug) ?? 99) < (order.firstIndex(of: $1.slug) ?? 99)
            }
        } catch { themes = [.relic]; warnings.append("主题目录未能载入，已保留默认灵蕴主题。") }
        do {
            let data = try Data(contentsOf: root.appendingPathComponent("skins/loadouts/suites-v1/catalog.json"))
            let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            for pack in document?["packs"] as? [[String: Any]] ?? [] {
                guard let slug = pack["slug"] as? String, let items = pack["items"] as? [[String: Any]] else { continue }
                equipment[slug] = items.compactMap { item in
                    guard let id = item["id"] as? String, let name = item["name"] as? String,
                          let path = item["image"] as? String, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return nil }
                    return EquipmentOption(id: id, name: name, kind: item["kind"] as? String ?? "任务配装",
                                           imagePath: "skins/loadouts/suites-v1/" + path)
                }
            }
            if equipment.values.reduce(0, { $0 + $1.count }) != 117 { warnings.append("部分配装目录缺失；未能载入的实体不会以假任务替代。") }
        } catch { warnings.append("任务器物素材目录未能载入。") }
        if let data = try? Data(contentsOf: root.appendingPathComponent("skins/identities/catalog.json")),
           let catalog = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] {
            for (slug, entry) in catalog {
                if let file = entry["file"] as? String, URL(fileURLWithPath: file).lastPathComponent == file { identityFiles[slug] = file }
            }
        }
        let missing = equipment.values.flatMap { $0 }.filter { !FileManager.default.fileExists(atPath: root.appendingPathComponent($0.imagePath).path) }
        if !missing.isEmpty { warnings.append("缺少 \(missing.count) 个任务器物资源，请重新构建应用。") }
        assetWarning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    private func decoded(_ relativePath: String, trimAlpha: Bool, maxEdge: Int = 1600) -> NSImage? {
        guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else { return nil }
        let key = (relativePath + (trimAlpha ? "#alpha" : "#full") + "#\(maxEdge)") as NSString
        if let image = cache.object(forKey: key) { return image }
        guard !failedImages.contains(key as String) else { return nil }
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: trimAlpha ? min(512, maxEdge) : maxEdge,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { failedImages.insert(key as String); return nil }
        let rendered = trimAlpha ? (Self.trim(image) ?? image) : image
        let result = NSImage(cgImage: rendered, size: NSSize(width: CGFloat(rendered.width), height: CGFloat(rendered.height)))
        cache.setObject(result, forKey: key, cost: rendered.width * rendered.height * 4)
        return result
    }

    private static func trim(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { storage -> CGImage? in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = storage.bindMemory(to: UInt8.self)
            var left = width, top = height, right = -1, bottom = -1
            for y in 0..<height {
                for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 12 {
                    left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
                }
            }
            guard right >= left, bottom >= top else { return nil }
            // Retain an independent copy before the temporary pixel buffer ends.
            let data = Data(bytes: storage.baseAddress!, count: storage.count) as CFData
            guard let provider = CGDataProvider(data: data),
                  let normalized = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                           bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
            let padding = 2
            left = max(0, left - padding); top = max(0, top - padding)
            right = min(width - 1, right + padding); bottom = min(height - 1, bottom + padding)
            return normalized.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
        }
    }
}

@MainActor
final class AppearanceModel: ObservableObject {
    @Published var themeSlug = "relic"
    @Published var decorations = true
    @Published var animate = true
    @Published var soundEnabled = true
    @Published var soundVolume = 0.45
    @Published private(set) var assetWarning: String?
    @Published private(set) var terminalThemeBusy = false
    @Published private(set) var terminalThemeStatus: String?
    @Published private(set) var terminalProfileStatus: String?
    @Published private(set) var terminalProfileImportStatus: TerminalProfileImportStatus?
    @Published private(set) var terminalRecoveryOptions: TerminalRecoveryBaselineOptions?
    @Published private(set) var terminalProfileLinked = false
    @Published private(set) var claudeThemeLinked = false
    @Published private(set) var claudeThemeStatus: String?
    @Published private var selections: [String: [String: String]] = [:]
    @Published private var customImages: [String: String] = [:]
    private let demo: Bool
    private let file: URL
    private let terminalThemeService: TerminalThemeService
    private let terminalProfileService: TerminalProfileApplicationService
    private let claudeThemeExporter: ClaudeThemeExporter
    private let terminalCatalog: () throws -> TerminalThemeCatalog
    private let openTerminalProfilesDirectory: (URL) -> Void
    var availableThemes: [ThemeDefinition] { ThemeResources.shared.themes }
    var theme: ThemeDefinition { ThemeResources.shared.theme(themeSlug) }
    var equipmentOptions: [EquipmentOption] { ThemeResources.shared.equipmentItems(themeSlug: themeSlug) }

    private struct Preferences: Codable {
        var themeSlug: String
        var decorations: Bool
        var animate: Bool
        var selections: [String: [String: String]]?
        var customImages: [String: String]?
        var soundEnabled: Bool?
        var soundVolume: Double?
        var terminalProfileLinked: Bool?
        var claudeThemeLinked: Bool?
    }

    init(demo: Bool = false, root: URL? = nil,
         terminalThemeService: TerminalThemeService? = nil,
         terminalProfileService: TerminalProfileApplicationService? = nil,
         terminalCatalog: (() throws -> TerminalThemeCatalog)? = nil,
         openTerminalProfilesDirectory: ((URL) -> Void)? = nil,
         claudeThemeExporter: ClaudeThemeExporter? = nil) {
        self.demo = demo
        let folder = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OmniVibe", isDirectory: true)
        file = folder.appendingPathComponent("appearance.json")
        self.terminalThemeService = terminalThemeService ?? TerminalThemeService(root: folder)
        let catalogLoader = terminalCatalog ?? { try TerminalThemeCatalog(resourcesURL: ThemeResources.shared.root) }
        self.terminalProfileService = terminalProfileService ?? TerminalProfileApplicationService(root: folder,
            profileDefinitions: (try? catalogLoader().profileDefinitions) ?? [])
        self.claudeThemeExporter = claudeThemeExporter ?? ClaudeThemeExporter(root: folder)
        self.terminalCatalog = catalogLoader
        self.openTerminalProfilesDirectory = openTerminalProfilesDirectory ?? { NSWorkspace.shared.open($0) }
        assetWarning = ThemeResources.shared.assetWarning
        guard !demo, FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let values = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: file))
            themeSlug = availableThemes.contains(where: { $0.slug == values.themeSlug }) ? values.themeSlug : "relic"
            decorations = values.decorations; animate = values.animate
            selections = values.selections ?? [:]
            customImages = values.customImages ?? [:]
            soundEnabled = values.soundEnabled ?? true
            terminalProfileLinked = values.terminalProfileLinked ?? false
            claudeThemeLinked = values.claudeThemeLinked ?? false
            if terminalProfileLinked { terminalProfileStatus = "完整主题联动已启用；下次切换主题时会先应用 Terminal 配置。" }
            let volume = values.soundVolume ?? 0.45
            soundVolume = volume.isFinite ? min(1, max(0, volume)) : 0.45
        } catch {
            let backup = file.deletingLastPathComponent().appendingPathComponent("appearance.recovery-\(UUID().uuidString).json")
            do { try FileManager.default.copyItem(at: file, to: backup) }
            catch { assetWarning = "外观设置无法读取或备份，本次保留原文件。"; persistenceEnabled = false; return }
            assetWarning = "外观设置格式无效，原文件已备份，已恢复默认灵蕴主题。"
        }
    }

    private var persistenceEnabled = true

    func setTheme(_ slug: String) { setThemeAndDecorations(slug, decorations: decorations) }

    func setDecorations(_ enabled: Bool) { setThemeAndDecorations(themeSlug, decorations: enabled) }

    /// One transaction is important when a settings draft changes both fields.
    /// A failed Terminal apply never publishes a theme that was not applied.
    func setThemeAndDecorations(_ slug: String, decorations enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        guard availableThemes.contains(where: { $0.slug == slug }) else { completion?(false); return }
        guard slug != themeSlug || enabled != decorations else { completion?(true); return }
        guard !terminalThemeBusy else {
            terminalProfileStatus = "Terminal 操作进行中，请完成后再切换主题。"
            completion?(false); return
        }
        guard terminalProfileLinked, !demo else {
            themeSlug = slug; decorations = enabled; save()
            if claudeThemeLinked { synchronizeClaudeTheme() }
            completion?(true); return
        }
        runTerminalOperation(full: true, status: "正在应用对应的 Terminal 完整主题…", completion: completion) {
            let name = try self.fullTerminalProfileName(slug: slug, decorations: enabled)
            let receipt = try await self.terminalProfileService.apply(profileName: name)
            self.themeSlug = slug; self.decorations = enabled; self.save()
            if self.claudeThemeLinked { self.synchronizeClaudeTheme() }
            if receipt.nativeCopyCount > 0 || receipt.manualBaselineCount > 0 {
                return "已联动“\(name)”至 \(receipt.tabCount) 个 Terminal 标签页。恢复来源：\(receipt.nativeCopyCount) 个原生自动备份，\(receipt.manualBaselineCount) 个手动指定基准。"
            }
            return "已联动“\(name)”至 \(receipt.tabCount) 个 Terminal 标签页。"
        }
    }

    /// The quick four-color path remains available for users who do not import
    /// full profiles. It cannot alter a full profile's recovery baseline.
    func applyTerminalTheme() {
        guard !terminalProfileLinked, !terminalProfileService.hasBackup else {
            terminalThemeStatus = "请先恢复完整主题，再使用快速配色，以保留完整配置的恢复依据。"
            return
        }
        let selectedTheme = theme
        runTerminalOperation(full: false, status: "正在应用快速配色；首次使用请确认 macOS 自动化授权。") {
            let palette = try TerminalThemePalette(background: selectedTheme.background, normalText: selectedTheme.text,
                boldText: selectedTheme.accent, cursor: selectedTheme.accent)
            let receipt = try await self.terminalThemeService.apply(theme: palette)
            return "快速配色已同步“\(selectedTheme.name)”至 \(receipt.profileCount) 个正在使用的配置。原色已备份。"
        }
    }

    func restoreTerminalTheme() {
        guard !terminalProfileLinked, !terminalProfileService.hasBackup else {
            terminalThemeStatus = "请先恢复完整主题，再恢复快速配色。"
            return
        }
        runTerminalOperation(full: false, status: "正在恢复快速配色的原色…") {
            let receipt = try await self.terminalThemeService.restoreLatest()
            return "已恢复 \(receipt.profileCount) 个 Terminal 配置的原色。"
        }
    }

    func prepareFullTerminalThemes() {
        runTerminalOperation(full: true, status: "正在准备 26 套 Terminal 完整主题…") {
            // A modified four-color baseline must be restored before a full
            // profile can replace it. Failure stops export rather than hiding it.
            if self.terminalThemeService.hasBackup {
                _ = try await self.terminalThemeService.restoreLatest()
                self.terminalThemeStatus = "快速配色的原色已恢复，可以准备完整主题。"
            }
            let catalog = try self.terminalCatalog()
            let output = self.file.deletingLastPathComponent().appendingPathComponent("TerminalProfiles", isDirectory: true)
            let decorated = try catalog.exportProfiles(to: output, decorations: true, variantNames: true)
            let minimal = try catalog.exportProfiles(to: output, decorations: false, variantNames: true)
            let suite = TerminalProfileSuiteManifest(schemaVersion: 1, exportedAt: Date(),
                status: "exported-not-imported", imported: false, applied: false,
                profileCount: decorated.profileURLs.count + minimal.profileURLs.count,
                profileNames: catalog.profileNames(decorations: true) + catalog.profileNames(decorations: false),
                variantManifests: [decorated.manifestURL.lastPathComponent, minimal.manifestURL.lastPathComponent])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(suite).write(to: output.appendingPathComponent("suite-manifest.json"), options: .atomic)
            self.terminalProfileImportStatus = nil
            self.openTerminalProfilesDirectory(output)
            return "已导出 26 套配置并打开目录，尚未导入或应用。请在 Terminal 的“设置 → 描述文件”中导入这 26 个 .terminal 文件，再点击“检查导入”。保留此目录中的 Assets。"
        }
    }

    func inspectTerminalProfiles() {
        runTerminalOperation(full: true, status: "正在检查 Terminal 导入状态与恢复条件…") {
            let catalog = try self.terminalCatalog()
            let status = await self.terminalProfileService.inspectImported(
                profileNames: catalog.profileNames(decorations: true) + catalog.profileNames(decorations: false))
            self.terminalProfileImportStatus = status
            if status.isReady, status.nativeCopyCount > 0 || status.manualBaselineCount > 0 {
                return "26 套主题已导入，可以应用完整主题。恢复来源：\(status.nativeCopyCount) 个原生自动备份，\(status.manualBaselineCount) 个手动指定基准。"
            }
            return status.isReady ? "26 套主题已导入，当前标签页具备可恢复的原配置，可以应用完整主题。" : "检查已完成，请先处理下方列出的导入或恢复条件。"
        }
    }

    /// Only a deliberate UI action invokes native profile copying. Opening
    /// settings, selecting a language, and app construction never call this.
    func prepareAutomaticTerminalRecoveryBaselines() {
        runTerminalOperation(full: true, status: "正在原生复制并备份 Terminal 原配置…") {
            let receipt = try await self.terminalProfileService.prepareAutomaticRecoveryBaselines()
            self.terminalRecoveryOptions = nil
            let catalog = try self.terminalCatalog()
            self.terminalProfileImportStatus = await self.terminalProfileService.inspectImported(
                profileNames: catalog.profileNames(decorations: true) + catalog.profileNames(decorations: false))
            if receipt.nativeCopyCount == 0 {
                return "当前标签页已具备可恢复的配置，无需创建副本。原窗口尚未切换，可检查并应用主题。"
            }
            return "已为 \(receipt.nativeCopyCount) 个标签页创建原生配置副本并保存完整备份。原窗口尚未切换，可检查并应用主题。"
        }
    }

    func loadTerminalRecoveryBaselines() {
        terminalRecoveryOptions = nil
        runTerminalOperation(full: true, status: "正在读取原配置的恢复选项…") {
            let options = try await self.terminalProfileService.recoveryBaselineOptions()
            self.terminalRecoveryOptions = options
            return options.unresolvedTabs.isEmpty ? "当前标签页已具备可恢复的配置。" : "建议先自动备份原配置；若当前 Terminal 不支持原生复制，可在这里手动指定恢复基准。"
        }
    }

    func registerTerminalRecoveryBaselines(_ choices: [TerminalRecoveryBaselineChoice], completion: @escaping (Bool) -> Void) {
        runTerminalOperation(full: true, status: "正在保存你指定的恢复基准…", completion: completion) {
            let receipt = try await self.terminalProfileService.registerRecoveryBaselines(choices)
            self.terminalRecoveryOptions = nil
            self.terminalProfileImportStatus = nil
            return "已为 \(receipt.registeredTabCount) 个标签页保存恢复基准；还原时将使用你指定的完整配置。"
        }
    }

    func applyFullTerminalTheme() {
        let slug = themeSlug, enabled = decorations
        runTerminalOperation(full: true, status: "正在备份原配置并应用 Terminal 完整主题…") {
            if self.terminalThemeService.hasBackup {
                _ = try await self.terminalThemeService.restoreLatest()
                self.terminalThemeStatus = "快速配色的原色已恢复。"
            }
            let name = try self.fullTerminalProfileName(slug: slug, decorations: enabled)
            let receipt = try await self.terminalProfileService.apply(profileName: name)
            self.terminalProfileLinked = true; self.save()
            if receipt.nativeCopyCount > 0 || receipt.manualBaselineCount > 0 {
                return "已应用“\(name)”至 \(receipt.tabCount) 个 Terminal 标签页，完整主题联动已开启。恢复来源：\(receipt.nativeCopyCount) 个原生自动备份，\(receipt.manualBaselineCount) 个手动指定基准。"
            }
            return "已应用“\(name)”至 \(receipt.tabCount) 个 Terminal 标签页，完整主题联动已开启。后续主题与装饰切换会先确认 Terminal 应用成功。"
        }
    }

    func restoreFullTerminalTheme() {
        runTerminalOperation(full: true, status: "正在恢复 Terminal 原完整配置…") {
            let receipt = try await self.terminalProfileService.restoreLatest()
            self.terminalProfileLinked = false; self.terminalProfileImportStatus = nil; self.save()
            if receipt.nativeCopyCount > 0 {
                return "已恢复 \(receipt.tabCount) 个 Terminal 标签页的原配置，其中 \(receipt.nativeCopyCount) 个使用原生自动备份，\(receipt.manualBaselineCount) 个使用你指定的恢复基准。完整主题联动已关闭。"
            }
            return receipt.manualBaselineCount > 0
                ? "已恢复 \(receipt.tabCount) 个 Terminal 标签页的配置，其中 \(receipt.manualBaselineCount) 个使用你指定的恢复基准。完整主题联动已关闭。"
                : "已恢复 \(receipt.tabCount) 个 Terminal 标签页的原配置，完整主题联动已关闭。"
        }
    }

    func archivePreviousTerminalThemeBackup() {
        runTerminalOperation(full: false, status: "正在归档旧会话的快速配色备份…") {
            let url = try await self.terminalThemeService.archivePreviousSessionBackup()
            return "旧会话快速配色备份已保留为 \(url.lastPathComponent)。此操作不会恢复 Terminal。"
        }
    }

    func archivePreviousTerminalProfileBackup() {
        runTerminalOperation(full: true, status: "正在归档旧会话的完整配置备份…") {
            let url = try await self.terminalProfileService.archivePreviousSessionBackup()
            self.terminalProfileLinked = false; self.terminalProfileImportStatus = nil; self.save()
            return "旧会话完整配置备份已保留为 \(url.lastPathComponent)，联动已关闭。此操作不会恢复 Terminal；可重新检查并应用。"
        }
    }

    private func fullTerminalProfileName(slug: String, decorations: Bool) throws -> String {
        let catalog = try terminalCatalog()
        guard let theme = catalog.themes.first(where: { $0.slug == slug }) else {
            throw TerminalProfileExportError.invalidCatalog("当前主题不在 Terminal 完整主题目录中。")
        }
        return TerminalThemeCatalog.profileName(name: theme.name, decorations: decorations)
    }

    private func runTerminalOperation(full: Bool, status: String, completion: ((Bool) -> Void)? = nil,
                                      operation: @escaping @MainActor () async throws -> String) {
        guard !demo, !terminalThemeBusy else { completion?(false); return }
        terminalThemeBusy = true
        if full { terminalProfileStatus = status } else { terminalThemeStatus = status }
        Task {
            defer { terminalThemeBusy = false }
            do {
                let result = try await operation()
                if full { terminalProfileStatus = result } else { terminalThemeStatus = result }
                completion?(true)
            } catch {
                let result = "Terminal 操作未完成：" + error.localizedDescription
                if full { terminalProfileStatus = result } else { terminalThemeStatus = result }
                completion?(false)
            }
        }
    }
    func setAnimate(_ enabled: Bool) { animate = enabled; save() }

    var claudeThemePath: String { claudeThemeExporter.themeURL.path }

    func enableClaudeThemeLink() {
        guard !demo else { return }
        if synchronizeClaudeTheme() { claudeThemeLinked = true; save() }
    }

    @discardableResult
    func synchronizeClaudeTheme() -> Bool {
        guard !demo else { return false }
        do {
            let catalog = try terminalCatalog()
            guard let selected = catalog.themes.first(where: { $0.slug == themeSlug }) else { return false }
            let receipt = try claudeThemeExporter.export(theme: selected)
            claudeThemeStatus = receipt.requiresInitialRestart
                ? "Claude 主题已生成。请重启 Claude Code，然后通过 /theme 选择 OmniVibe；后续切换主题会自动更新文件。"
                : "Claude 主题文件已更新。请通过 /theme 选择 OmniVibe；已选用时会按 Claude 的主题监测机制更新。"
            return true
        } catch {
            claudeThemeStatus = "Claude 主题未更新：" + error.localizedDescription
            return false
        }
    }

    func restoreClaudeTheme() {
        guard !demo else { return }
        do {
            _ = try claudeThemeExporter.restoreLatest()
            claudeThemeLinked = false; save()
            claudeThemeStatus = "Claude 主题文件已恢复，自动生成已关闭。若移除了新建主题，请在 /theme 中选择其他主题。"
        } catch { claudeThemeStatus = "Claude 主题恢复未完成：" + error.localizedDescription }
    }
    func setSoundEnabled(_ enabled: Bool) { soundEnabled = enabled; save() }
    func setSoundVolume(_ volume: Double) {
        soundVolume = volume.isFinite ? min(1, max(0, volume)) : 0.45
        save()
    }
    func selectedEquipmentID(for slot: TaskSlot) -> String? {
        if let selected = selections[slot.id.uuidString]?[themeSlug], equipmentOptions.contains(where: { $0.id == selected }) { return selected }
        guard !equipmentOptions.isEmpty else { return nil }
        return equipmentOptions[min(max(slot.number - 1, 0), equipmentOptions.count - 1)].id
    }
    func equipmentID(for slot: TaskSlot) -> String? { selectedEquipmentID(for: slot) }

    /// Freeze number-derived defaults before tasks move to different slots.
    /// Build and persist one complete candidate before publishing any change.
    func preserveTaskEquipment(_ slots: [TaskSlot]) throws {
        var preserved = selections
        for slot in slots where slot.window != nil {
            let key = slot.id.uuidString
            var byTheme = preserved[key] ?? [:]
            for theme in availableThemes where byTheme[theme.slug] == nil {
                let items = ThemeResources.shared.equipmentItems(themeSlug: theme.slug)
                guard !items.isEmpty else {
                    throw NSError(domain: "OmniVibe.Appearance", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "主题器物目录未能载入，暂不能保留任务配装并排序。"])
                }
                byTheme[theme.slug] = items[min(max(slot.number - 1, 0), items.count - 1)].id
            }
            preserved[key] = byTheme
        }
        guard preserved != selections else { return }
        if !demo {
            guard persistenceEnabled else {
                throw NSError(domain: "OmniVibe.Appearance", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "外观设置未能安全读取，无法保存任务配装。"])
            }
            try writePreferences(selections: preserved)
        }
        selections = preserved
    }

    /// Explicit rebinding can replace a task UUID without losing its loadout.
    /// Keep the old identity's mappings for recovery and publish only after the
    /// complete candidate has been atomically persisted.
    func transferEquipment(from oldTaskID: UUID, to newTaskID: UUID) throws {
        guard oldTaskID != newTaskID else { return }
        let source = oldTaskID.uuidString, target = newTaskID.uuidString
        var candidateSelections = selections
        var candidateImages = customImages
        if let value = selections[source] { candidateSelections[target] = value }
        if let value = customImages[source] { candidateImages[target] = value }
        guard candidateSelections != selections || candidateImages != customImages else { return }
        if !demo {
            guard persistenceEnabled else {
                throw NSError(domain: "OmniVibe.Appearance", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "外观设置未能安全读取，无法转移任务配装。"])
            }
            try writePreferences(selections: candidateSelections, customImages: candidateImages)
        }
        selections = candidateSelections; customImages = candidateImages
    }

    func setEquipment(_ id: String, for slot: TaskSlot) {
        guard equipmentOptions.contains(where: { $0.id == id }) else { return }
        var byTheme = selections[slot.id.uuidString] ?? [:]
        byTheme[themeSlug] = id
        selections[slot.id.uuidString] = byTheme
        customImages.removeValue(forKey: slot.id.uuidString)
        save()
    }
    func customImage(for slot: TaskSlot) -> NSImage? {
        guard let name = customImages[slot.id.uuidString], name == URL(fileURLWithPath: name).lastPathComponent,
              !name.hasPrefix("."), !name.contains("/") else { return nil }
        return ThemeResources.shared.managedImage(at: file.deletingLastPathComponent().appendingPathComponent("Loadout/" + name))
    }
    func importCustomImage(_ url: URL, for slot: TaskSlot) throws {
        guard !demo else { throw NSError(domain: "OmniVibe.Appearance", code: 1, userInfo: [NSLocalizedDescriptionKey: "演示模式不保存自定义配装。"] ) }
        guard persistenceEnabled else { throw NSError(domain: "OmniVibe.Appearance", code: 2, userInfo: [NSLocalizedDescriptionKey: "外观设置未能安全读取，无法保存自定义配装。"] ) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.int64Value * height.int64Value <= 32_000_000 else {
            throw NSError(domain: "OmniVibe.Appearance", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法读取图片，或图片超过 3200 万像素。"] )
        }
        let folder = file.deletingLastPathComponent().appendingPathComponent("Loadout", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = url.pathExtension.lowercased()
        let name = UUID().uuidString + (ext.isEmpty ? ".image" : "." + ext)
        let target = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: target)
        customImages[slot.id.uuidString] = name
        save()
    }
    func entity(for slot: TaskSlot) -> NSImage? {
        if let custom = customImage(for: slot) { return custom }
        if let id = selectedEquipmentID(for: slot), let item = equipmentOptions.first(where: { $0.id == id }) {
            return ThemeResources.shared.equipmentImage(item)
        }
        return ThemeResources.shared.entity(for: slot, themeSlug: themeSlug)
    }
    private func save() {
        guard !demo, persistenceEnabled else { return }
        do { try writePreferences(selections: selections) }
        catch { assetWarning = "外观设置未能保存：\(error.localizedDescription)" }
    }

    private func writePreferences(selections candidate: [String: [String: String]], customImages candidateImages: [String: String]? = nil) throws {
        let values = Preferences(themeSlug: themeSlug, decorations: decorations, animate: animate,
                                 selections: candidate, customImages: candidateImages ?? customImages,
                                 soundEnabled: soundEnabled, soundVolume: soundVolume, terminalProfileLinked: terminalProfileLinked,
                                 claudeThemeLinked: claudeThemeLinked)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(values)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}

/// Export is a local artifact operation, independent of import and application.
struct TerminalProfileSuiteManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let status: String
    let imported: Bool
    let applied: Bool
    let profileCount: Int
    let profileNames: [String]
    let variantManifests: [String]
}
