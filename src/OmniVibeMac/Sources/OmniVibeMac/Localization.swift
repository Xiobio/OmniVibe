import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return L10n.text("跟随系统")
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    func resolved(preferredLanguages: [String]) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            let primary = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if primary == "zh" || primary.hasPrefix("zh-") { return .zhHans }
            if primary == "en" || primary.hasPrefix("en-") { return .en }
        }
        return .en
    }

    var locale: Locale { Locale(identifier: self == .zhHans ? "zh_Hans_CN" : "en_US") }
}

extension Notification.Name {
    static let omniVibeLanguageDidChange = Notification.Name("OmniVibe.LanguageDidChange.v1")
}

/// Source keys remain Chinese. Translation happens explicitly at presentation
/// boundaries; task titles, paths, session identifiers and protocol data must
/// be passed verbatim rather than through this API.
enum L10n {
    static func text(_ source: String) -> String {
        let snapshot = LocalizationRuntime.shared.snapshot()
        return snapshot.catalog.text(source, language: snapshot.language)
    }

    static func format(_ source: String, _ arguments: CVarArg...) -> String {
        let snapshot = LocalizationRuntime.shared.snapshot()
        return snapshot.catalog.format(source, arguments: arguments, language: snapshot.language)
    }

    static func errorText(_ source: String) -> String {
        let snapshot = LocalizationRuntime.shared.snapshot()
        return snapshot.catalog.errorText(source, language: snapshot.language)
    }

    static func errorDescription(_ error: Error) -> String { errorText(error.localizedDescription) }

    static var locale: Locale { LocalizationRuntime.shared.snapshot().language.locale }
}

/// Observe this object in SwiftUI roots and native views. Changes also emit a
/// notification for AppKit menus, window titles and accessibility labels.
/// Selecting a language never rewrites task data or terminal profile names.
@MainActor
final class AppLocalization: NSObject, ObservableObject {
    nonisolated static let preferenceKey = "OmniVibe.AppLanguage.v1"
    static let shared = AppLocalization(appliesToRuntime: true)

    @Published private(set) var language: AppLanguage
    @Published private(set) var resolvedLanguage: AppLanguage
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var warning: String?
    private let preferences: UserDefaults
    private let preferredLanguages: () -> [String]
    private let catalog: LocalizationCatalog
    private let appliesToRuntime: Bool
    private var localeObservation: NSObjectProtocol?

    var locale: Locale { resolvedLanguage.locale }

    init(preferences: UserDefaults = .standard,
         preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
         catalog: LocalizationCatalog? = nil, appliesToRuntime: Bool = false) {
        self.preferences = preferences
        self.preferredLanguages = preferredLanguages
        self.appliesToRuntime = appliesToRuntime
        let stored = preferences.object(forKey: Self.preferenceKey)
        let selected = (stored as? String).flatMap(AppLanguage.init(rawValue:)) ?? .system
        language = selected
        resolvedLanguage = selected.resolved(preferredLanguages: preferredLanguages())
        if stored != nil && (stored as? String).flatMap(AppLanguage.init(rawValue:)) == nil {
            warning = "语言设置无法读取，已暂时跟随系统；原配置保留到你明确选择语言。"
        }
        if let catalog { self.catalog = catalog }
        else {
            do { self.catalog = try LocalizationCatalog.bundled() }
            catch {
                self.catalog = .empty
                warning = "语言资源未能载入，请重新构建完整应用。"
            }
        }
        super.init()
        if appliesToRuntime {
            LocalizationRuntime.shared.install(catalog: self.catalog, language: resolvedLanguage)
            localeObservation = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification,
                object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refreshSystemLanguage() }
                }
        }
    }

    /// Runtime state changes only after the requested preference reads back.
    /// UserDefaults writes asynchronously; this does not claim a disk fsync.
    @discardableResult
    func setLanguage(_ selected: AppLanguage) -> Bool {
        preferences.set(selected.rawValue, forKey: Self.preferenceKey)
        guard preferences.string(forKey: Self.preferenceKey) == selected.rawValue else {
            warning = "语言设置未能保存，当前语言保持不变。"
            return false
        }
        let resolved = selected.resolved(preferredLanguages: preferredLanguages())
        let changed = selected != language || resolved != resolvedLanguage
        language = selected
        resolvedLanguage = resolved
        warning = nil
        if changed { publishChange() }
        return true
    }

    func refreshSystemLanguage() {
        guard language == .system else { return }
        let resolved = language.resolved(preferredLanguages: preferredLanguages())
        guard resolved != resolvedLanguage else { return }
        resolvedLanguage = resolved
        publishChange()
    }

    func text(_ source: String) -> String { catalog.text(source, language: resolvedLanguage) }

    func format(_ source: String, _ arguments: CVarArg...) -> String {
        catalog.format(source, arguments: arguments, language: resolvedLanguage)
    }

    private func publishChange() {
        if appliesToRuntime { LocalizationRuntime.shared.install(catalog: catalog, language: resolvedLanguage) }
        revision &+= 1
        NotificationCenter.default.post(name: .omniVibeLanguageDidChange, object: self)
    }

    deinit { if let localeObservation { NotificationCenter.default.removeObserver(localeObservation) } }
}

/// Immutable catalogues and snapshots can also be read by background error
/// producers. The main-actor preference model is the only runtime writer.
private final class LocalizationResourceAnchor: NSObject {}

private final class LocalizationRuntime: @unchecked Sendable {
    struct Snapshot {
        let catalog: LocalizationCatalog
        let language: AppLanguage
    }
    static let shared = LocalizationRuntime()
    private let lock = NSLock()
    private var value: Snapshot

    private init() {
        let selected = UserDefaults.standard.string(forKey: AppLocalization.preferenceKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        value = Snapshot(catalog: (try? LocalizationCatalog.bundled()) ?? .empty,
                         language: selected.resolved(preferredLanguages: Locale.preferredLanguages))
    }

    func snapshot() -> Snapshot { lock.lock(); defer { lock.unlock() }; return value }
    func install(catalog: LocalizationCatalog, language: AppLanguage) {
        lock.lock(); defer { lock.unlock() }
        value = Snapshot(catalog: catalog, language: language)
    }
}

/// The catalogue contains fixed UI strings, not user data. Registered composed
/// templates let previously created status messages change language while each
/// captured task name, file path or identifier remains byte-for-byte intact.
struct LocalizationCatalog: @unchecked Sendable {
    private struct File: Decodable {
        let schemaVersion: Int
        let translations: [String: String]
        let verbatimKeys: [String]?
        let nestedErrorArguments: [String: [Int]]?
    }
    let translations: [String: String]
    let verbatimKeys: Set<String>
    private let toEnglish: [ComposedTemplate]
    private let toChinese: [ComposedTemplate]
    private let reverse: [String: String]
    private let nestedErrorArguments: [String: Set<Int>]
    static let empty = try! LocalizationCatalog(translations: [:])

    init(translations: [String: String], verbatimKeys: Set<String> = [], nestedErrorArguments: [String: Set<Int>] = [:]) throws {
        guard translations.count <= 5_000,
              translations.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty && $0.key.utf8.count <= 32_768 && $0.value.utf8.count <= 32_768 }),
              verbatimKeys.isSubset(of: Set(translations.keys)) else { throw CatalogError.invalidCatalog }
        for (source, translation) in translations {
            guard PrintfTemplate(source).signature == PrintfTemplate(translation).signature else {
                throw CatalogError.placeholderMismatch(source)
            }
            guard !verbatimKeys.contains(source) || source == translation else { throw CatalogError.invalidCatalog }
        }
        for (source, positions) in nestedErrorArguments {
            guard translations[source] != nil, !positions.isEmpty,
                  positions.allSatisfy({ PrintfTemplate(source).signature[$0] == .object }) else {
                throw CatalogError.invalidCatalog
            }
        }
        self.translations = translations
        self.verbatimKeys = verbatimKeys
        self.nestedErrorArguments = nestedErrorArguments
        let grouped = Dictionary(grouping: translations.keys, by: { translations[$0]! })
        reverse = grouped.compactMapValues { $0.count == 1 ? $0[0] : nil }
        toEnglish = translations.compactMap {
            ComposedTemplate(source: $0.key, translation: $0.value, nestedErrors: nestedErrorArguments[$0.key] ?? [])
        }
            .sorted { $0.specificity > $1.specificity }
        toChinese = grouped.compactMap { english, sources in
            sources.count == 1 ? ComposedTemplate(source: english, translation: sources[0], nestedErrors: nestedErrorArguments[sources[0]] ?? []) : nil
        }.sorted { $0.specificity > $1.specificity }
    }

    static func load(_ url: URL) throws -> LocalizationCatalog {
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 2_097_152 else { throw CatalogError.invalidCatalog }
        let file = try JSONDecoder().decode(File.self, from: bytes)
        guard file.schemaVersion == 1 else { throw CatalogError.invalidCatalog }
        return try LocalizationCatalog(translations: file.translations, verbatimKeys: Set(file.verbatimKeys ?? []),
            nestedErrorArguments: (file.nestedErrorArguments ?? [:]).mapValues(Set.init))
    }

    static func bundled() throws -> LocalizationCatalog {
        let resourceBundle = "OmniVibeMac_OmniVibeMac.bundle"
        // An installed .app owns its catalogue directly. Darwin XCTest's
        // Bundle.main belongs to the Xcode runner, so also inspect the bundle
        // containing this module and the other loaded bundles for SwiftPM's
        // adjacent resource bundle. Never use Bundle.module's fatal fallback.
        let bundles = [Bundle.main, Bundle(for: LocalizationResourceAnchor.self)] + Bundle.allBundles
        var candidates = [URL]()
        for bundle in bundles {
            candidates.append(contentsOf: [
                bundle.resourceURL?.appendingPathComponent("Localization/en.json"),
                bundle.resourceURL?.appendingPathComponent(resourceBundle + "/Localization/en.json"),
                bundle.bundleURL.appendingPathComponent(resourceBundle + "/Localization/en.json"),
                bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(resourceBundle + "/Localization/en.json"),
                bundle.executableURL?.deletingLastPathComponent().appendingPathComponent(resourceBundle + "/Localization/en.json")
            ].compactMap { $0 })
        }
        guard let url = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw CatalogError.missingResource
        }
        return try load(url)
    }

    func text(_ source: String, language: AppLanguage) -> String {
        translate(source, language: language, depth: 0, errorContext: false)
    }

    /// Only errors and warnings should use this entry point. Registered nested
    /// error positions are localized; every unmarked captured task name/path
    /// stays verbatim, even when its value happens to equal another UI key.
    func errorText(_ source: String, language: AppLanguage) -> String {
        translate(source, language: language, depth: 0, errorContext: true)
    }

    private func translate(_ source: String, language: AppLanguage, depth: Int, errorContext: Bool) -> String {
        guard !source.isEmpty else { return source }
        guard source.utf8.count <= 65_536 else { return source }
        let chinese = language == .zhHans
        if chinese {
            if translations[source] != nil { return source }
            if let translated = reverse[source] { return translated }
        } else {
            if let translated = translations[source] { return translated }
        }
        guard depth < 4 else { return source }
        let templates = chinese ? toChinese : toEnglish
        for template in templates {
            if let translated = template.translate(source, localizeError: {
                self.translate($0, language: language, depth: depth + 1, errorContext: true)
            }) { return translated }
        }
        if errorContext {
            // Controller diagnostics can join independent per-window errors.
            // Preserve the exact lines, application names and unrecognized data.
            if source.contains("\n") {
                let pieces = source.components(separatedBy: "\n")
                if pieces.count <= 64 {
                    return pieces.map { translate($0, language: language, depth: depth + 1, errorContext: true) }.joined(separator: "\n")
                }
            }
            // An app name is opaque data. Translate a known error after its
            // separator only when the suffix genuinely matches the catalogue.
            // Inspect at most eight separators and never scan arbitrary text.
            let value = source as NSString
            var search = NSRange(location: 0, length: value.length)
            for _ in 0..<8 {
                let fullWidth = value.range(of: "：", options: .backwards, range: search)
                let ascii = value.range(of: ":", options: .backwards, range: search)
                let range: NSRange
                if fullWidth.location == NSNotFound { range = ascii }
                else if ascii.location == NSNotFound { range = fullWidth }
                else { range = fullWidth.location > ascii.location ? fullWidth : ascii }
                guard range.location != NSNotFound else { break }
                let tail = value.substring(from: range.location + range.length)
                let whitespace = String(tail.prefix(while: { $0.isWhitespace }))
                let message = String(tail.dropFirst(whitespace.count))
                let localized = translate(message, language: language, depth: depth + 1, errorContext: true)
                if localized != message {
                    return value.substring(to: range.location) + (chinese ? "：" : ": ") + localized
                }
                search = NSRange(location: 0, length: range.location)
            }
        }
        return source
    }

    func format(_ source: String, arguments: [CVarArg], language: AppLanguage) -> String {
        let translated = text(source, language: language)
        let original = PrintfTemplate(source)
        let destination = PrintfTemplate(translated)
        guard original.isSafeFormat, destination.isSafeFormat, original.signature == destination.signature,
              destination.accepts(arguments) else { return source }
        var localizedArguments = arguments
        let sourceKey = translations[source] != nil ? source : reverse[source] ?? source
        for index in nestedErrorArguments[sourceKey] ?? [] {
            if let message = arguments[index] as? String {
                localizedArguments[index] = errorText(message, language: language)
            } else if let message = arguments[index] as? NSString {
                localizedArguments[index] = errorText(message as String, language: language)
            }
        }
        return String(format: translated, locale: language.locale, arguments: localizedArguments)
    }

    enum CatalogError: LocalizedError {
        case missingResource, invalidCatalog, placeholderMismatch(String)
        var errorDescription: String? {
            switch self {
            case .missingResource: return "The bundled English localization catalogue is missing."
            case .invalidCatalog: return "The localization catalogue is invalid."
            case .placeholderMismatch(let key): return "Localization placeholders do not match: " + key
            }
        }
    }
}

private struct PrintfTemplate {
    enum Kind: String { case object, integer, unsigned, floating, character, pointer }
    enum Part { case literal(String), argument(Int, Kind) }
    let parts: [Part]
    let signature: [Int: Kind]
    let isSafeFormat: Bool
    private static let expression = try! NSRegularExpression(pattern: #"%([1-9][0-9]*\$)?[-+ #0]*(?:[0-9]+)?(?:\.[0-9]+)?(?:hh|ll|h|l|j|z|t|L)?[@diuoxXfFeEgGaAcCsSp]"#)

    init(_ source: String) {
        let expression = Self.expression
        let text = source as NSString
        var offset = 0, sequential = 0
        var output: [Part] = [], signature: [Int: Kind] = [:]
        var safe = true, positional: Bool?
        while offset < text.length {
            let range = text.range(of: "%", options: [], range: NSRange(location: offset, length: text.length - offset))
            if range.location == NSNotFound { output.append(.literal(text.substring(from: offset))); break }
            if range.location > offset { output.append(.literal(text.substring(with: NSRange(location: offset, length: range.location - offset)))) }
            if range.location + 1 < text.length, text.substring(with: NSRange(location: range.location, length: 2)) == "%%" {
                output.append(.literal("%")); offset = range.location + 2; continue
            }
            guard let match = expression.firstMatch(in: source, options: [.anchored],
                range: NSRange(location: range.location, length: text.length - range.location)) else {
                output.append(.literal("%")); offset = range.location + 1; safe = false; continue
            }
            let hasPosition = match.range(at: 1).location != NSNotFound
            if let previous = positional, previous != hasPosition { safe = false }
            positional = hasPosition
            let index: Int
            if hasPosition {
                let token = text.substring(with: match.range(at: 1)).dropLast()
                index = (Int(token) ?? 0) - 1
            } else { index = sequential; sequential += 1 }
            let token = text.substring(with: match.range)
            let kind: Kind
            switch token.last! {
            case "@": kind = .object
            case "d", "i": kind = .integer
            case "u", "o", "x", "X": kind = .unsigned
            case "f", "F", "e", "E", "g", "G", "a", "A": kind = .floating
            case "c", "C": kind = .character
            case "p": kind = .pointer
            default: kind = .object; safe = false
            }
            if index < 0 || index > 63 { safe = false }
            if let previous = signature[index], previous != kind { safe = false }
            signature[index] = kind
            output.append(.argument(index, kind)); offset = match.range.location + match.range.length
        }
        if !signature.isEmpty, Set(signature.keys) != Set(0...signature.keys.max()!) { safe = false }
        parts = output; self.signature = signature; isSafeFormat = safe
    }

    func accepts(_ arguments: [CVarArg]) -> Bool {
        guard isSafeFormat, arguments.count == signature.count else { return false }
        for (index, kind) in signature {
            let value = arguments[index]
            switch kind {
            case .object: if !(value is String || value is NSString) { return false }
            case .floating: if !(value is Double || value is Float || value is CGFloat) { return false }
            case .integer, .unsigned, .character:
                if !(value is Int || value is Int8 || value is Int16 || value is Int32 || value is Int64 ||
                     value is UInt || value is UInt8 || value is UInt16 || value is UInt32 || value is UInt64) { return false }
            case .pointer: return false
            }
        }
        return true
    }
}

private struct ComposedTemplate {
    let expression: NSRegularExpression
    let output: [PrintfTemplate.Part]
    let capturedPositions: [Int]
    let prefix: String
    let suffix: String
    let specificity: Int
    let nestedErrors: Set<Int>

    init?(source: String, translation: String, nestedErrors: Set<Int> = []) {
        let original = PrintfTemplate(source), translated = PrintfTemplate(translation)
        guard !original.signature.isEmpty, original.signature == translated.signature,
              original.isSafeFormat, translated.isSafeFormat else { return nil }
        var pattern = "\\A", positions: [Int] = [], literalCount = 0
        for part in original.parts {
            switch part {
            case .literal(let literal): pattern += NSRegularExpression.escapedPattern(for: literal); literalCount += literal.count
            case .argument(let position, _): pattern += "([\\s\\S]*?)"; positions.append(position)
            }
        }
        pattern += "\\z"
        guard literalCount >= 2, let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        self.expression = expression; capturedPositions = positions; output = translated.parts
        if case .literal(let first) = original.parts.first { prefix = first } else { prefix = "" }
        if case .literal(let last) = original.parts.last { suffix = last } else { suffix = "" }
        specificity = literalCount
        self.nestedErrors = nestedErrors
    }

    func translate(_ source: String, localizeError: (String) -> String) -> String? {
        guard source.hasPrefix(prefix), source.hasSuffix(suffix), source.utf8.count <= 65_536 else { return nil }
        let text = source as NSString
        guard let match = expression.firstMatch(in: source, range: NSRange(location: 0, length: text.length)) else { return nil }
        var values: [Int: String] = [:]
        for (index, position) in capturedPositions.enumerated() {
            let value = text.substring(with: match.range(at: index + 1))
            if let previous = values[position], previous != value { return nil }
            values[position] = value
        }
        var result = ""
        for part in output {
            switch part {
            case .literal(let literal): result += literal
            case .argument(let position, _):
                guard let value = values[position] else { return nil }
                result += nestedErrors.contains(position) ? localizeError(value) : value
            }
        }
        return result
    }
}
