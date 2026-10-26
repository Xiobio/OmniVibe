import AppKit
import CryptoKit
import Foundation

struct TerminalProfileAppearance: Codable, Equatable, Sendable {
    let palette: TerminalThemePalette
    let fontName: String
    let fontSize: Double

    func matches(_ other: Self) -> Bool {
        func close(_ a: TerminalThemePalette.RGB, _ b: TerminalThemePalette.RGB) -> Bool {
            abs(Int(a.red) - Int(b.red)) <= 512 && abs(Int(a.green) - Int(b.green)) <= 512 && abs(Int(a.blue) - Int(b.blue)) <= 512
        }
        return fontName == other.fontName && abs(fontSize - other.fontSize) <= 0.05 &&
            close(palette.background, other.palette.background) && close(palette.normalText, other.palette.normalText) &&
            close(palette.boldText, other.palette.boldText) && close(palette.cursor, other.palette.cursor)
    }
}

struct TerminalRecoveryBaselineOptions: Sendable {
    let sessionID: String
    let unresolvedTabs: [TerminalProfileTabSnapshot]
    let profiles: [TerminalPersistentProfile]
}

/// The user chooses a complete exported file and the unique imported profile
/// that should be used for restoration. This is an explicit recovery basis,
/// never an inferred equivalence between a private tab copy and a same-name set.
struct TerminalRecoveryBaselineChoice: Sendable {
    let sessionID: String
    let tab: TerminalProfileTabKey
    let observedProfile: TerminalPersistentProfile
    let persistentProfile: TerminalPersistentProfile
    let exportedProfileURL: URL
}

struct TerminalRecoveryBaselineReceipt: Sendable {
    let registeredTabCount: Int
    let registryURL: URL
    var nativeCopyCount: Int = 0
    var manualBaselineCount: Int = 0
    var manualBasis: Bool { nativeCopyCount == 0 }
}

enum TerminalRecoveryBaselineOrigin: String, Codable, Sendable {
    case manual, nativeCopy
}

struct TerminalRecoveryBaselineEvidence: Codable, Equatable, Sendable {
    let tab: TerminalProfileTabKey
    var observedProfile: TerminalPersistentProfile
    let persistentProfile: TerminalPersistentProfile
    let exportedName: String
    let filename: String
    let sha256: String
    let appearance: TerminalProfileAppearance
    let manualBasis: Bool
    var origin: TerminalRecoveryBaselineOrigin? = nil

    var validBasis: Bool { origin == .nativeCopy ? !manualBasis : manualBasis }
}

/// This store retains complete user-selected profile bytes, including settings
/// AppleScript does not expose (ANSI colors and background artwork). Public
/// color/font metadata is compared as an additional safeguard. It cannot prove
/// unseen fields of an imported profile; the UI must state the user's selection
/// is the restoration basis rather than promise an automatic private-copy backup.
final class TerminalRecoveryBaselineRegistry {
    struct Document: Codable {
        let version: Int
        let session: String
        var entries: [TerminalRecoveryBaselineEvidence]
    }
    let root: URL
    let registryURL: URL
    private let files = FileManager.default

    init(root: URL) {
        self.root = root
        registryURL = root.appendingPathComponent("terminal-recovery-baselines.json")
    }

    func entries(session: String) throws -> [TerminalRecoveryBaselineEvidence] {
        guard let document = try load(), document.session == session else { return [] }
        return document.entries
    }

    func resolve(_ tab: TerminalProfileTabSnapshot, session: String,
                 profiles: [TerminalPersistentProfile]) throws -> TerminalRecoveryBaselineEvidence? {
        guard let entry = try entries(session: session).first(where: { $0.tab == tab.tab && $0.observedProfile == tab.profile }) else { return nil }
        guard profiles.filter({ $0 == entry.persistentProfile }).count == 1,
              profiles.filter({ $0.name == entry.persistentProfile.name }).count == 1 else {
            throw TerminalProfileApplicationError.originalProfileUnavailable
        }
        try validateArchive(entry)
        return entry
    }

    func register(_ choices: [TerminalRecoveryBaselineChoice], session: String,
                  snapshot: TerminalProfileApplicationSnapshot,
                  origin: TerminalRecoveryBaselineOrigin = .manual,
                  appearance: (TerminalPersistentProfile, TerminalProfileTabKey?) throws -> TerminalProfileAppearance) throws -> TerminalRecoveryBaselineReceipt {
        guard !choices.isEmpty, choices.count <= 256, choices.allSatisfy({ $0.sessionID == session }),
              Set(choices.map(\.tab)).count == choices.count else {
            throw TerminalProfileApplicationError.invalidRecoveryBaseline
        }
        var prepared: [(TerminalRecoveryBaselineEvidence, Data)] = []
        for choice in choices {
            guard let current = snapshot.tabs.first(where: { $0.tab == choice.tab }), current.profile == choice.observedProfile,
                  snapshot.profiles.filter({ $0 == choice.persistentProfile }).count == 1,
                  snapshot.profiles.filter({ $0.name == choice.persistentProfile.name }).count == 1,
                  choice.persistentProfile.name != choice.observedProfile.name,
                  !TerminalThemeProfileDefinition.reservedForTheme(choice.persistentProfile.name) else {
                throw TerminalProfileApplicationError.invalidRecoveryBaseline
            }
            let currentAppearance = try appearance(choice.observedProfile, choice.tab)
            let savedAppearance = try appearance(choice.persistentProfile, nil)
            guard currentAppearance.matches(savedAppearance) else { throw TerminalProfileApplicationError.recoveryBaselineMismatch }
            let exported = try Self.exportedProfile(choice.exportedProfileURL,
                inheritedAppearance: origin == .nativeCopy ? currentAppearance : nil)
            guard origin != .nativeCopy || exported.name == choice.persistentProfile.name else {
                throw TerminalProfileApplicationError.invalidRecoveryBaseline
            }
            guard exported.appearance.matches(currentAppearance), exported.appearance.matches(savedAppearance) else {
                throw TerminalProfileApplicationError.recoveryBaselineMismatch
            }
            let filename = UUID().uuidString + ".terminal"
            let entry = TerminalRecoveryBaselineEvidence(tab: choice.tab, observedProfile: choice.observedProfile,
                persistentProfile: choice.persistentProfile, exportedName: exported.name, filename: filename,
                sha256: Self.digest(exported.data), appearance: exported.appearance, manualBasis: origin == .manual,
                origin: origin)
            prepared.append((entry, exported.data))
        }
        let previous = try load()
        var entries = previous?.session == session ? previous!.entries : []
        for (entry, _) in prepared {
            entries.removeAll { $0.tab == entry.tab }
            entries.append(entry)
        }
        guard entries.count <= 256 else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
        let archiveRoot = root.appendingPathComponent("TerminalRecoveryProfiles", isDirectory: true)
        try files.createDirectory(at: archiveRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: archiveRoot.path)
        for (entry, data) in prepared {
            let destination = archiveRoot.appendingPathComponent(entry.filename)
            guard !files.fileExists(atPath: destination.path) else { throw TerminalProfileApplicationError.backupUnavailable }
            try data.write(to: destination, options: .atomic)
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            try validateArchive(entry)
        }
        if let previous, previous.session != session {
            let backup = root.appendingPathComponent("terminal-recovery-baselines.archived-\(UUID()).json")
            try files.copyItem(at: registryURL, to: backup)
        }
        try save(Document(version: 1, session: session, entries: entries))
        return TerminalRecoveryBaselineReceipt(registeredTabCount: prepared.count, registryURL: registryURL,
            nativeCopyCount: origin == .nativeCopy ? prepared.count : 0,
            manualBaselineCount: origin == .manual ? prepared.count : 0)
    }

    func refreshRestored(_ restored: [TerminalProfileTabSnapshot], session: String) throws {
        guard var document = try load(), document.session == session else { return }
        for restored in restored {
            guard let index = document.entries.firstIndex(where: { $0.tab == restored.tab && $0.persistentProfile.name == restored.profile.name }) else { continue }
            document.entries[index].observedProfile = restored.profile
        }
        try save(document)
    }

    func validateArchive(_ entry: TerminalRecoveryBaselineEvidence) throws {
        guard entry.validBasis, UUID(uuidString: URL(fileURLWithPath: entry.filename).deletingPathExtension().lastPathComponent) != nil,
              entry.filename == URL(fileURLWithPath: entry.filename).lastPathComponent,
              entry.filename.hasSuffix(".terminal"), entry.sha256.count == 64 else {
            throw TerminalProfileApplicationError.invalidRecoveryBaseline
        }
        let url = root.appendingPathComponent("TerminalRecoveryProfiles", isDirectory: true).appendingPathComponent(entry.filename)
        let source = try Self.exportedProfile(url, inheritedAppearance: entry.origin == .nativeCopy ? entry.appearance : nil)
        guard Self.digest(source.data) == entry.sha256, source.name == entry.exportedName,
              entry.origin != .nativeCopy || source.name == entry.persistentProfile.name,
              source.appearance == entry.appearance else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
    }

    private func load() throws -> Document? {
        guard files.fileExists(atPath: registryURL.path) else { return nil }
        do {
            let data = try Self.boundedFile(registryURL, maximum: 2 * 1_048_576)
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1, !document.session.isEmpty, document.session.utf8.count <= 512,
                  document.entries.count <= 256, Set(document.entries.map(\.tab)).count == document.entries.count else {
                throw TerminalProfileApplicationError.invalidRecoveryBaseline
            }
            for entry in document.entries {
                guard entry.validBasis, entry.tab.windowID > 0, !entry.tab.tty.isEmpty,
                      !entry.observedProfile.name.isEmpty, !entry.persistentProfile.name.isEmpty,
                      !TerminalThemeProfileDefinition.reservedForTheme(entry.persistentProfile.name) else {
                    throw TerminalProfileApplicationError.invalidRecoveryBaseline
                }
                try validateArchive(entry)
            }
            return document
        } catch { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
    }

    private func save(_ document: Document) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 2 * 1_048_576 else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: registryURL, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
        guard try Data(contentsOf: registryURL) == data else { throw TerminalProfileApplicationError.backupUnavailable }
    }

    private static func boundedFile(_ url: URL, maximum: Int) throws -> Data {
        guard url.isFileURL else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximum else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximum else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
        return data
    }

    private static func exportedProfile(_ url: URL, inheritedAppearance: TerminalProfileAppearance? = nil) throws -> (name: String, appearance: TerminalProfileAppearance, data: Data) {
        do {
            guard url.pathExtension.lowercased() == "terminal" else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
            let data = try boundedFile(url, maximum: 2 * 1_048_576)
            guard let profile = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  profile["type"] as? String == "Window Settings", let name = profile["name"] as? String,
                  !name.isEmpty, name.utf8.count <= 512,
                  name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                throw TerminalProfileApplicationError.invalidRecoveryBaseline
            }
            let fontName: String, fontSize: Double
            if profile["Font"] != nil {
                guard let fontData = profile["Font"] as? Data,
                      let font = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: fontData) else {
                    throw TerminalProfileApplicationError.invalidRecoveryBaseline
                }
                fontName = font.fontName; fontSize = font.pointSize
            } else if let inheritedAppearance {
                fontName = inheritedAppearance.fontName; fontSize = inheritedAppearance.fontSize
            } else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
            guard !fontName.isEmpty, fontName.utf8.count <= 512,
                  fontName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                  fontSize.isFinite, fontSize > 0, fontSize < 1000 else {
                throw TerminalProfileApplicationError.invalidRecoveryBaseline
            }
            // Native copies use Terminal's inheritance semantics. Missing public
            // fields are interpreted from the verified copy, never synthesized
            // into the archived bytes. Explicit malformed fields still fail.
            func color(_ key: String, inherited: TerminalThemePalette.RGB?) throws -> TerminalThemePalette.RGB {
                if profile[key] == nil, let inherited { return inherited }
                guard let archive = profile[key] as? Data,
                      let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: archive),
                      let color = decoded.usingColorSpace(.sRGB) else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                guard channels.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
                let values = channels.map { UInt16(($0 * 65_535).rounded()) }
                return .init(red: values[0], green: values[1], blue: values[2])
            }
            let palette = try TerminalThemePalette(
                background: color("BackgroundColor", inherited: inheritedAppearance?.palette.background),
                normalText: color("TextColor", inherited: inheritedAppearance?.palette.normalText),
                boldText: color("TextBoldColor", inherited: inheritedAppearance?.palette.boldText),
                cursor: color("CursorColor", inherited: inheritedAppearance?.palette.cursor))
            return (name, TerminalProfileAppearance(palette: palette, fontName: fontName, fontSize: fontSize), data)
        } catch { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
