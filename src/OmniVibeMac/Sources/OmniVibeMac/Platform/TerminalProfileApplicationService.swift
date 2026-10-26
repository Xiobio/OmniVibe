import AppKit
import Carbon
import Combine
import Foundation
import OmniVibeCore
import OSLog

struct TerminalPersistentProfile: Codable, Equatable, Sendable {
    var id: Int
    var name: String
}

struct TerminalProfileTabKey: Codable, Hashable, Sendable {
    var windowID: Int
    var tty: String
}

struct TerminalProfileWindowBounds: Codable, Equatable, Sendable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int

    fileprivate var valid: Bool {
        [left, top, right, bottom].allSatisfy { Int32(exactly: $0) != nil } && right > left && bottom > top
    }
    fileprivate var scriptLiteral: String { "{\(left), \(top), \(right), \(bottom)}" }
    fileprivate var frame: WindowFrame { WindowFrame(x: Double(left), y: Double(top), width: Double(right - left), height: Double(bottom - top)) }
}

struct TerminalProfileTabSnapshot: Codable, Equatable, Sendable {
    var tab: TerminalProfileTabKey
    var profile: TerminalPersistentProfile
    var bounds: TerminalProfileWindowBounds
}

struct TerminalProfileApplicationSnapshot: Equatable, Sendable {
    var profiles: [TerminalPersistentProfile]
    var tabs: [TerminalProfileTabSnapshot]

    fileprivate func validated() throws -> Self {
        guard profiles.count <= 256, tabs.count <= 256,
              Set(profiles.map(\.id)).count == profiles.count,
              Set(tabs.map(\.tab)).count == tabs.count,
              Set(tabs.map { $0.tab.tty }).count == tabs.count else { throw TerminalProfileApplicationError.invalidResponse }
        for profile in profiles { try TerminalProfileApplicationValidation.profile(profile) }
        var windowBounds: [Int: TerminalProfileWindowBounds] = [:]
        for tab in tabs {
            try TerminalProfileApplicationValidation.tab(tab)
            if let previous = windowBounds[tab.tab.windowID], previous != tab.bounds {
                throw TerminalProfileApplicationError.invalidResponse
            }
            windowBounds[tab.tab.windowID] = tab.bounds
        }
        return self
    }

    fileprivate func persistent(_ profile: TerminalPersistentProfile) -> Bool {
        profiles.filter { $0.id == profile.id && $0.name == profile.name }.count == 1
    }

    fileprivate func named(_ name: String) throws -> TerminalPersistentProfile {
        let matches = profiles.filter { $0.name == name }
        guard matches.count == 1, let profile = matches.first else {
            throw matches.isEmpty ? TerminalProfileApplicationError.profileNotImported : TerminalProfileApplicationError.ambiguousProfile
        }
        return profile
    }
}

/// Exact aliases for the 13 official slugs and their two variants. A profile is
/// never trusted merely because it has an OmniVibe prefix. Both import check
/// and application use this resolver and reject all duplicate candidates.
private struct TerminalThemeProfileResolver: Sendable {
    let definitions: [TerminalThemeProfileDefinition]

    func definition(named name: String) throws -> TerminalThemeProfileDefinition {
        let required = Set(TerminalThemeCatalog.slugs)
        guard definitions.count == required.count * 2,
              Set(definitions.filter(\.decorations).map(\.slug)) == required,
              Set(definitions.filter { !$0.decorations }.map(\.slug)) == required,
              definitions.allSatisfy({ $0.canonicalName.hasPrefix("OmniVibe / ") }),
              Set(definitions.map(\.canonicalName)).count == definitions.count else {
            throw TerminalProfileApplicationError.invalidProfileName
        }
        let matches = definitions.filter { $0.names.contains(name) }
        guard matches.count == 1, let definition = matches.first else { throw TerminalProfileApplicationError.invalidProfileName }
        do { try TerminalProfileApplicationValidation.text(name) }
        catch { throw TerminalProfileApplicationError.invalidProfileName }
        return definition
    }

    func candidates(named name: String, in snapshot: TerminalProfileApplicationSnapshot) throws -> [TerminalPersistentProfile] {
        let definition = try definition(named: name)
        return snapshot.profiles.filter { definition.names.contains($0.name) }
    }

    func resolve(_ name: String, in snapshot: TerminalProfileApplicationSnapshot) throws -> TerminalPersistentProfile {
        let matches = try candidates(named: name, in: snapshot)
        guard matches.count == 1, let profile = matches.first else {
            throw matches.isEmpty ? TerminalProfileApplicationError.profileNotImported : TerminalProfileApplicationError.ambiguousProfile
        }
        return profile
    }
}

struct TerminalProfileApplicationReceipt: Equatable, Sendable {
    let tabCount: Int
    let backupURL: URL
    let restored: Bool
    var manualBaselineCount: Int = 0
    var gridAdjustedWindowCount: Int = 0
    var nativeCopyCount: Int = 0
}

struct TerminalProfileImportStatus: Equatable, Sendable {
    var missingNames: [String] = []
    var temporaryOriginalCount: Int = 0
    var ambiguousNames: [String] = []
    var errorMessage: String?
    var manualBaselineCount: Int = 0
    var nativeCopyCount: Int = 0
    var isReady: Bool { missingNames.isEmpty && temporaryOriginalCount == 0 && ambiguousNames.isEmpty && errorMessage == nil }
}

enum TerminalProfileVerificationStep: Equatable {
    case complete, readAgain, timedOut
}

/// One metadata AppleEvent can outlast the settling interval. A first exact
/// fit still needs its confirmation read; this does not loosen frame fitting.
enum TerminalProfileVerification {
    static func step(matches: Bool, previousBounds: TerminalProfileWindowBounds?,
                     actualBounds: TerminalProfileWindowBounds, elapsed: Double,
                     readCount: Int) -> TerminalProfileVerificationStep {
        guard elapsed.isFinite, elapsed >= 0, (1...4).contains(readCount) else { return .timedOut }
        if matches, previousBounds == actualBounds { return .complete }
        guard readCount < 4 else { return .timedOut }
        if matches { return .readAgain }
        return elapsed < 0.7 ? .readAgain : .timedOut
    }
}

/// Every method runs on the service's serial worker. The protocol exposes only
/// profile and tab metadata, never terminal text, history or shell execution.
protocol TerminalProfileApplicationBackend: AnyObject {
    func sessionIdentifier() throws -> String
    func snapshot() throws -> TerminalProfileApplicationSnapshot
    func setProfile(_ profile: TerminalPersistentProfile, tab: TerminalProfileTabKey) throws
    func setBounds(_ bounds: TerminalProfileWindowBounds, windowID: Int) throws
    func appearance(profile: TerminalPersistentProfile, tab: TerminalProfileTabKey?) throws -> TerminalProfileAppearance
    func duplicateProfile(_ original: TerminalProfileTabSnapshot, named: String) throws -> TerminalPersistentProfile
}

extension TerminalProfileApplicationBackend {
    func duplicateProfile(_ original: TerminalProfileTabSnapshot, named: String) throws -> TerminalPersistentProfile {
        throw TerminalProfileApplicationError.nativeCopyUnsupported
    }

    func appearance(profile: TerminalPersistentProfile, tab: TerminalProfileTabKey?) throws -> TerminalProfileAppearance {
        throw TerminalProfileApplicationError.baselineMetadataUnavailable
    }
}

/// Requires explicit UI actions. Construction only checks the local backup;
/// even inspection can request Automation and must not be run during startup.
@MainActor
final class TerminalProfileApplicationService: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var hasBackup: Bool
    let backupURL: URL
    private let worker: Worker
    private static let queue = DispatchQueue(label: "io.github.xiobio.OmniVibe.terminal-profile", qos: .userInitiated)

    init(root: URL? = nil, backend: TerminalProfileApplicationBackend? = nil,
         profileDefinitions: [TerminalThemeProfileDefinition] = TerminalThemeCatalog.bundledProfileDefinitions,
         profilePreferences: (any TerminalProfilePreferencesReading)? = nil) {
        let folder = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OmniVibe", isDirectory: true)
        backupURL = folder.appendingPathComponent("terminal-profile-backup.json")
        worker = Worker(backupURL: backupURL, backend: backend ?? AppleScriptTerminalProfileApplicationBackend(),
            profileDefinitions: profileDefinitions, profilePreferences: profilePreferences ?? TerminalProfilePreferencesReader())
        hasBackup = FileManager.default.fileExists(atPath: backupURL.path)
    }

    func apply(profileName: String) async throws -> TerminalProfileApplicationReceipt {
        try await perform { try $0.apply(profileName: profileName) }
    }

    func restoreLatest() async throws -> TerminalProfileApplicationReceipt {
        try await perform { try $0.restore() }
    }

    /// Explicitly keeps an expired session's local backup under a unique name.
    /// This reads process metadata only; it never sends an AppleEvent.
    func archivePreviousSessionBackup() async throws -> URL {
        try await perform { try $0.archivePreviousSessionBackup() }
    }

    func inspectImported(profileNames: [String]) async -> TerminalProfileImportStatus {
        do { return try await perform { try $0.inspect(names: profileNames) } }
        catch { return TerminalProfileImportStatus(errorMessage: error.localizedDescription) }
    }

    func recoveryBaselineOptions() async throws -> TerminalRecoveryBaselineOptions {
        try await perform { try $0.recoveryBaselineOptions() }
    }

    /// Explicit user action: clone only exact original tab profiles through
    /// Terminal's native duplicate command, archive their complete persisted
    /// profile bytes, and register restoration identities. Never switches tabs.
    func prepareAutomaticRecoveryBaselines() async throws -> TerminalRecoveryBaselineReceipt {
        do { return try await perform { try $0.prepareAutomaticRecoveryBaselines() } }
        catch TerminalProfileApplicationError.invalidRecoveryBaseline { throw TerminalProfileApplicationError.nativeCopyVerificationFailed }
        catch TerminalProfileApplicationError.recoveryBaselineMismatch { throw TerminalProfileApplicationError.nativeCopyVerificationFailed }
    }

    /// The UI must explicitly describe these choices as user-selected restore
    /// profiles, not an automatic exact backup of private tab settings.
    func registerRecoveryBaselines(_ choices: [TerminalRecoveryBaselineChoice]) async throws -> TerminalRecoveryBaselineReceipt {
        try await perform { try $0.registerRecoveryBaselines(choices) }
    }

    private func perform<T: Sendable>(_ operation: @escaping (Worker) throws -> T) async throws -> T {
        guard !isBusy else { throw TerminalProfileApplicationError.busy }
        isBusy = true
        defer { isBusy = false; hasBackup = FileManager.default.fileExists(atPath: backupURL.path) }
        let worker = worker
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                continuation.resume(with: Result { try autoreleasepool { try operation(worker) } })
            }
        }
    }

    private final class Worker: @unchecked Sendable {
        private static let verificationLog = Logger(subsystem: "io.github.xiobio.OmniVibe", category: "TerminalProfileVerification")
        struct TrackedProfile: Codable {
            var tab: TerminalProfileTabKey
            var name: String
            var observedProfile: TerminalPersistentProfile? = nil
        }
        struct Backup: Codable {
            let version: Int
            let session: String
            var originals: [TerminalProfileTabSnapshot]
            var applied: [TrackedProfile]
            var pendingRecovery: [TerminalProfileTabSnapshot]
            var manualBaselines: [TerminalRecoveryBaselineEvidence]? = nil
        }
        struct NativeCopyAttempt: Codable {
            let session: String
            let tab: TerminalProfileTabKey
            let originalProfile: TerminalPersistentProfile
            let name: String
        }
        let backupURL: URL
        let backend: TerminalProfileApplicationBackend
        let baselines: TerminalRecoveryBaselineRegistry
        let resolver: TerminalThemeProfileResolver
        let profilePreferences: any TerminalProfilePreferencesReading

        init(backupURL: URL, backend: TerminalProfileApplicationBackend, profileDefinitions: [TerminalThemeProfileDefinition],
             profilePreferences: any TerminalProfilePreferencesReading) {
            self.backupURL = backupURL; self.backend = backend
            resolver = TerminalThemeProfileResolver(definitions: profileDefinitions)
            self.profilePreferences = profilePreferences
            baselines = TerminalRecoveryBaselineRegistry(root: backupURL.deletingLastPathComponent())
        }

        func recoveryBaselineOptions() throws -> TerminalRecoveryBaselineOptions {
            let backup = try loadBackup()
            guard backup?.pendingRecovery.isEmpty != false else { throw TerminalProfileApplicationError.recoveryRequired }
            let session = try backend.sessionIdentifier()
            if let backup, backup.session != session { throw TerminalProfileApplicationError.sessionChanged }
            let snapshot = try backend.snapshot().validated()
            try ensureSession(session)
            let unresolved = try snapshot.tabs.filter {
                guard !snapshot.persistent($0.profile), !owned($0, backup: backup, snapshot: snapshot) else { return false }
                return try manualBaseline($0, session: session, snapshot: snapshot) == nil
            }
            return TerminalRecoveryBaselineOptions(sessionID: session, unresolvedTabs: unresolved,
                profiles: snapshot.profiles.filter { profile in snapshot.profiles.filter { $0.name == profile.name }.count == 1 && !TerminalThemeProfileDefinition.reservedForTheme(profile.name) })
        }

        func registerRecoveryBaselines(_ choices: [TerminalRecoveryBaselineChoice]) throws -> TerminalRecoveryBaselineReceipt {
            let backup = try loadBackup()
            guard backup?.pendingRecovery.isEmpty != false else { throw TerminalProfileApplicationError.recoveryRequired }
            let session = try backend.sessionIdentifier()
            guard choices.allSatisfy({ $0.sessionID == session }) else { throw TerminalProfileApplicationError.sessionChanged }
            if let backup, backup.session != session { throw TerminalProfileApplicationError.sessionChanged }
            let snapshot = try backend.snapshot().validated()
            let receipt = try baselines.register(choices, session: session, snapshot: snapshot,
                appearance: { profile, tab in
                    try self.ensureSession(session)
                    return try self.backend.appearance(profile: profile, tab: tab)
                })
            try ensureSession(session)
            let after = try backend.snapshot().validated()
            guard choices.allSatisfy({ choice in after.tabs.contains { $0.tab == choice.tab && $0.profile == choice.observedProfile } }) else {
                throw TerminalProfileApplicationError.invalidRecoveryBaseline
            }
            return receipt
        }

        func prepareAutomaticRecoveryBaselines() throws -> TerminalRecoveryBaselineReceipt {
            let backup = try loadBackup()
            guard backup?.pendingRecovery.isEmpty != false else { throw TerminalProfileApplicationError.recoveryRequired }
            let session = try backend.sessionIdentifier()
            if let backup, backup.session != session { throw TerminalProfileApplicationError.sessionChanged }
            let initial = try backend.snapshot().validated()
            guard !initial.tabs.isEmpty else { throw TerminalProfileApplicationError.noOpenTabs }
            let unresolved = try initial.tabs.filter {
                guard !initial.persistent($0.profile), !owned($0, backup: backup, snapshot: initial) else { return false }
                return try manualBaseline($0, session: session, snapshot: initial) == nil
            }
            var count = 0
            for original in unresolved {
                try ensureSession(session)
                let before = try backend.snapshot().validated()
                guard before.tabs.contains(original) else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
                let originalAppearance = try backend.appearance(profile: original.profile, tab: original.tab)
                let attempt = try nativeCopyAttempt(original, session: session, snapshot: before)
                let name = attempt.name
                let copied = try attempt.existing ?? backend.duplicateProfile(original, named: name)
                try ensureSession(session)
                let after = try backend.snapshot().validated()
                guard copied.name == name, copied != original.profile,
                      after.profiles.filter({ $0 == copied }).count == 1,
                      after.profiles.filter({ $0.name == name }).count == 1,
                      (attempt.existing == copied || !before.profiles.contains(where: { $0.id == copied.id })),
                      after.tabs.contains(original),
                      originalAppearance.matches(try backend.appearance(profile: copied, tab: nil)),
                      originalAppearance.matches(try backend.appearance(profile: original.profile, tab: original.tab)) else {
                    throw TerminalProfileApplicationError.invalidRecoveryBaseline
                }
                let data = try profilePreferences.profileData(named: name)
                guard !data.isEmpty, data.count <= 2 * 1_048_576,
                      let fields = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      fields["name"] as? String == name, fields["type"] as? String == "Window Settings" else {
                    throw TerminalProfileApplicationError.nativeCopyNotPersisted
                }
                try ensureSession(session)
                let current = try backend.snapshot().validated()
                guard current.tabs.contains(original), current.persistent(copied),
                      current.profiles.filter({ $0.name == copied.name }).count == 1 else {
                    throw TerminalProfileApplicationError.invalidRecoveryBaseline
                }
                let staging = backupURL.deletingLastPathComponent().appendingPathComponent("TerminalRecoveryStaging", isDirectory: true)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staging.path)
                let file = staging.appendingPathComponent(UUID().uuidString + ".terminal")
                defer { try? FileManager.default.removeItem(at: file) }
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                guard try Data(contentsOf: file) == data else { throw TerminalProfileApplicationError.backupUnavailable }
                let choice = TerminalRecoveryBaselineChoice(sessionID: session, tab: original.tab,
                    observedProfile: original.profile, persistentProfile: copied, exportedProfileURL: file)
                _ = try baselines.register([choice], session: session, snapshot: current, origin: .nativeCopy,
                    appearance: { profile, tab in
                        try self.ensureSession(session)
                        return try self.backend.appearance(profile: profile, tab: tab)
                    })
                try ensureSession(session)
                guard try backend.snapshot().validated().tabs.contains(original) else {
                    throw TerminalProfileApplicationError.invalidRecoveryBaseline
                }
                count += 1
            }
            return TerminalRecoveryBaselineReceipt(registeredTabCount: count, registryURL: baselines.registryURL,
                nativeCopyCount: count, manualBaselineCount: 0)
        }

        /// Record intent before the AppleEvent. A timeout or failed post-lookup
        /// can happen after Terminal has inserted a profile; retries must not
        /// keep creating new names. An existing owned attempt is reused only
        /// after the same full identity and public appearance checks below.
        private func nativeCopyAttempt(_ original: TerminalProfileTabSnapshot, session: String,
                                       snapshot: TerminalProfileApplicationSnapshot) throws -> (name: String, existing: TerminalPersistentProfile?) {
            let folder = backupURL.deletingLastPathComponent().appendingPathComponent("TerminalRecoveryStaging", isDirectory: true)
            let url = folder.appendingPathComponent("native-copy-attempts.json")
            var attempts: [NativeCopyAttempt] = []
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 1_048_577) ?? Data()
                guard data.count <= 1_048_576 else { throw TerminalProfileApplicationError.invalidBackup }
                attempts = try JSONDecoder().decode([NativeCopyAttempt].self, from: data)
                guard attempts.count <= 256, Set(attempts.map(\.name)).count == attempts.count else {
                    throw TerminalProfileApplicationError.invalidBackup
                }
                for attempt in attempts {
                    try TerminalProfileApplicationValidation.text(attempt.session)
                    try TerminalProfileApplicationValidation.key(attempt.tab)
                    try TerminalProfileApplicationValidation.profile(attempt.originalProfile)
                    guard attempt.name.hasPrefix("OmniVibe Recovery "),
                          UUID(uuidString: String(attempt.name.dropFirst("OmniVibe Recovery ".count))) != nil else {
                        throw TerminalProfileApplicationError.invalidBackup
                    }
                }
            }
            let matchingAttempts = attempts.filter { $0.session == session && $0.tab == original.tab && $0.originalProfile == original.profile }
            guard matchingAttempts.count <= 1 else { throw TerminalProfileApplicationError.invalidBackup }
            if let attempted = matchingAttempts.first {
                let existing = snapshot.profiles.filter { $0.name == attempted.name }
                guard existing.count <= 1 else { throw TerminalProfileApplicationError.nativeCopyVerificationFailed }
                return (attempted.name, existing.first)
            }
            guard attempts.count < 256 else { throw TerminalProfileApplicationError.backupUnavailable }
            let name = "OmniVibe Recovery " + UUID().uuidString
            guard !snapshot.profiles.contains(where: { $0.name == name }) else { throw TerminalProfileApplicationError.ambiguousProfile }
            attempts.append(NativeCopyAttempt(session: session, tab: original.tab, originalProfile: original.profile, name: name))
            let data = try JSONEncoder().encode(attempts)
            guard data.count <= 1_048_576 else { throw TerminalProfileApplicationError.backupUnavailable }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            guard try Data(contentsOf: url) == data else { throw TerminalProfileApplicationError.backupUnavailable }
            return (name, nil)
        }

        func inspect(names: [String]) throws -> TerminalProfileImportStatus {
            guard names.count <= 64 else { throw TerminalProfileApplicationError.invalidProfileName }
            for name in names { _ = try resolver.definition(named: name) }
            let backup = try loadBackup()
            let session = try backend.sessionIdentifier()
            if let backup, backup.session != session { throw TerminalProfileApplicationError.sessionChanged }
            let snapshot = try backend.snapshot().validated()
            try ensureSession(session)
            var status = TerminalProfileImportStatus()
            for name in Set(names).sorted() {
                let count = try resolver.candidates(named: name, in: snapshot).count
                if count == 0 { status.missingNames.append(name) }
                if count > 1 { status.ambiguousNames.append(name) }
            }
            for tab in snapshot.tabs where !snapshot.persistent(tab.profile) && !owned(tab, backup: backup, snapshot: snapshot) {
                if let baseline = try manualBaseline(tab, session: session, snapshot: snapshot) {
                    if baseline.origin == .nativeCopy { status.nativeCopyCount += 1 }
                    else { status.manualBaselineCount += 1 }
                }
                else { status.temporaryOriginalCount += 1 }
            }
            status.manualBaselineCount += backup?.manualBaselines?.filter { $0.origin != .nativeCopy }.count ?? 0
            status.nativeCopyCount += backup?.manualBaselines?.filter { $0.origin == .nativeCopy }.count ?? 0
            if backup?.pendingRecovery.isEmpty == false {
                status.errorMessage = TerminalProfileApplicationError.recoveryRequired.localizedDescription
            } else if snapshot.tabs.contains(where: { current in
                backup?.originals.contains(where: { $0.tab.tty == current.tab.tty && $0.tab != current.tab }) == true
            }) {
                status.errorMessage = TerminalProfileApplicationError.tabMoved.localizedDescription
            } else if snapshot.tabs.contains(where: { current in
                backup?.originals.contains(where: { $0.tab == current.tab && !snapshot.persistent($0.profile) }) == true
            }) {
                status.errorMessage = TerminalProfileApplicationError.originalProfileUnavailable.localizedDescription
            } else if snapshot.tabs.isEmpty {
                status.errorMessage = TerminalProfileApplicationError.noOpenTabs.localizedDescription
            }
            return status
        }

        func apply(profileName: String) throws -> TerminalProfileApplicationReceipt {
            _ = try resolver.definition(named: profileName)
            var backup = try loadBackup()
            guard backup?.pendingRecovery.isEmpty != false else { throw TerminalProfileApplicationError.recoveryRequired }
            let session = try backend.sessionIdentifier()
            if let backup, backup.session != session { throw TerminalProfileApplicationError.sessionChanged }
            let snapshot = try backend.snapshot().validated()
            let target = try resolver.resolve(profileName, in: snapshot)
            guard !snapshot.tabs.isEmpty else { throw TerminalProfileApplicationError.noOpenTabs }
            try ensureSession(session)
            guard !snapshot.tabs.contains(where: { current in
                backup?.originals.contains(where: { $0.tab.tty == current.tab.tty && $0.tab != current.tab }) == true
            }) else { throw TerminalProfileApplicationError.tabMoved }
            var manual: [TerminalRecoveryBaselineEvidence] = []
            let temporary = try snapshot.tabs.filter {
                guard !snapshot.persistent($0.profile), !owned($0, backup: backup, snapshot: snapshot) else { return false }
                if let entry = try manualBaseline($0, session: session, snapshot: snapshot) { manual.append(entry); return false }
                return true
            }
            guard temporary.isEmpty else { throw TerminalProfileApplicationError.needsBaselineSave(temporary.count) }
            for entry in backup?.manualBaselines ?? [] {
                guard snapshot.persistent(entry.persistentProfile),
                      entry.appearance.matches(try backend.appearance(profile: entry.persistentProfile, tab: nil)) else {
                    throw TerminalProfileApplicationError.recoveryBaselineMismatch
                }
            }
            // Resolve every rollback profile before writing or switching any tab.
            let before = try snapshot.tabs.map { tab -> TerminalProfileTabSnapshot in
                var saved = tab
                if !snapshot.persistent(tab.profile) {
                    saved.profile = try manual.first(where: { $0.tab == tab.tab })?.persistentProfile ?? snapshot.named(tab.profile.name)
                }
                if let original = backup?.originals.first(where: { $0.tab == tab.tab }), !snapshot.persistent(original.profile) {
                    throw TerminalProfileApplicationError.originalProfileUnavailable
                }
                return saved
            }
            if backup == nil { backup = Backup(version: 1, session: session, originals: [], applied: [], pendingRecovery: []) }
            var state = backup!
            var manualEvidence = state.manualBaselines ?? []
            for entry in manual where !manualEvidence.contains(where: { $0.tab == entry.tab }) { manualEvidence.append(entry) }
            state.manualBaselines = manualEvidence.isEmpty ? nil : manualEvidence
            for tab in before where !state.originals.contains(where: { $0.tab == tab.tab }) {
                var original = tab
                // A window owns one rectangle, even when a later tab is added.
                if let first = state.originals.first(where: { $0.tab.windowID == tab.tab.windowID }) { original.bounds = first.bounds }
                state.originals.append(original)
            }
            state.pendingRecovery = before
            try writeBackup(state)
            do {
                var adjustedWindows = Set<Int>()
                for tab in before {
                    let actual = try change(profile: target, tab: tab.tab, bounds: tab.bounds, session: session)
                    if actual.bounds != tab.bounds { adjustedWindows.insert(tab.tab.windowID) }
                    track(actual, in: &state)
                }
                state.pendingRecovery = []
                try writeBackup(state)
                return TerminalProfileApplicationReceipt(tabCount: before.count, backupURL: backupURL, restored: false,
                    manualBaselineCount: state.manualBaselines?.filter { $0.origin != .nativeCopy }.count ?? 0,
                    gridAdjustedWindowCount: adjustedWindows.count,
                    nativeCopyCount: state.manualBaselines?.filter { $0.origin == .nativeCopy }.count ?? 0)
            } catch {
                let cause = error.localizedDescription
                var pending: [TerminalProfileTabSnapshot] = []
                for tab in before {
                    do {
                        let restored = try change(profile: tab.profile, tab: tab.tab, bounds: tab.bounds, session: session, strictBounds: true)
                        track(restored, in: &state)
                    } catch { pending.append(tab) }
                }
                state.pendingRecovery = pending
                try? writeBackup(state)
                throw TerminalProfileApplicationError.applyFailed(cause, pending.count)
            }
        }

        func restore() throws -> TerminalProfileApplicationReceipt {
            guard var backup = try loadBackup() else { throw TerminalProfileApplicationError.noBackup }
            try ensureSession(backup.session)
            for entry in backup.manualBaselines ?? [] {
                guard entry.appearance.matches(try backend.appearance(profile: entry.persistentProfile, tab: nil)) else {
                    throw TerminalProfileApplicationError.recoveryBaselineMismatch
                }
            }
            var pending: [TerminalProfileTabSnapshot] = []
            var restored: [TerminalProfileTabSnapshot] = []
            for original in backup.originals {
                do {
                    let actual = try change(profile: original.profile, tab: original.tab, bounds: original.bounds, session: backup.session, strictBounds: true)
                    restored.append(actual)
                    track(actual, in: &backup)
                } catch { pending.append(original) }
            }
            guard pending.isEmpty else {
                backup.pendingRecovery = pending
                try? writeBackup(backup)
                throw TerminalProfileApplicationError.restoreIncomplete(pending.count)
            }
            try baselines.refreshRestored(restored, session: backup.session)
            do { try FileManager.default.removeItem(at: backupURL) }
            catch { throw TerminalProfileApplicationError.backupCleanupFailed }
            return TerminalProfileApplicationReceipt(tabCount: backup.originals.count, backupURL: backupURL, restored: true,
                manualBaselineCount: backup.manualBaselines?.filter { $0.origin != .nativeCopy }.count ?? 0,
                nativeCopyCount: backup.manualBaselines?.filter { $0.origin == .nativeCopy }.count ?? 0)
        }

        func archivePreviousSessionBackup() throws -> URL {
            guard let backup = try loadBackup() else { throw TerminalProfileApplicationError.noBackup }
            let current = try backend.sessionIdentifier()
            guard !current.isEmpty, current != backup.session else { throw TerminalProfileApplicationError.currentSessionArchiveForbidden }
            let archive = backupURL.deletingLastPathComponent().appendingPathComponent(
                backupURL.deletingPathExtension().lastPathComponent + ".archived-\(UUID().uuidString).json")
            // Both URLs share a directory, so this is a rename on the same
            // filesystem, preserving the complete bytes without a copy window.
            try FileManager.default.moveItem(at: backupURL, to: archive)
            return archive
        }

        private func owned(_ tab: TerminalProfileTabSnapshot, backup: Backup?, snapshot: TerminalProfileApplicationSnapshot) -> Bool {
            guard let backup, backup.originals.contains(where: { $0.tab == tab.tab }),
                  backup.applied.contains(where: { $0.tab == tab.tab && $0.name == tab.profile.name && $0.observedProfile == tab.profile }) else { return false }
            return snapshot.profiles.filter { $0.name == tab.profile.name }.count == 1
        }

        private func manualBaseline(_ tab: TerminalProfileTabSnapshot, session: String,
                                    snapshot: TerminalProfileApplicationSnapshot) throws -> TerminalRecoveryBaselineEvidence? {
            guard let entry = try baselines.resolve(tab, session: session, profiles: snapshot.profiles) else { return nil }
            let current = try backend.appearance(profile: tab.profile, tab: tab.tab)
            let saved = try backend.appearance(profile: entry.persistentProfile, tab: nil)
            try ensureSession(session)
            guard entry.appearance.matches(current), entry.appearance.matches(saved) else {
                throw TerminalProfileApplicationError.recoveryBaselineMismatch
            }
            return entry
        }

        private func track(_ actual: TerminalProfileTabSnapshot, in backup: inout Backup) {
            backup.applied.removeAll { $0.tab == actual.tab }
            backup.applied.append(TrackedProfile(tab: actual.tab, name: actual.profile.name, observedProfile: actual.profile))
        }

        @discardableResult
        private func change(profile: TerminalPersistentProfile, tab: TerminalProfileTabKey,
                            bounds: TerminalProfileWindowBounds, session: String, strictBounds: Bool = false) throws -> TerminalProfileTabSnapshot {
            try ensureSession(session)
            try backend.setProfile(profile, tab: tab)
            try ensureSession(session)
            try backend.setBounds(bounds, windowID: tab.windowID)
            try ensureSession(session)
            let started = ProcessInfo.processInfo.systemUptime
            var stableBounds: TerminalProfileWindowBounds?
            var readCount = 0
            var retry = 0
            while true {
                let current = try backend.snapshot().validated()
                try ensureSession(session)
                readCount += 1
                guard current.persistent(profile) else {
                    Self.verificationLog.error("terminal-profile-verify stage=persistent-profile-missing")
                    throw TerminalProfileApplicationError.verificationFailed
                }
                guard let actual = current.tabs.first(where: { $0.tab == tab }) else {
                    Self.verificationLog.error("terminal-profile-verify stage=exact-tab-missing")
                    throw TerminalProfileApplicationError.verificationFailed
                }
                guard actual.profile.name == profile.name else {
                    Self.verificationLog.error("terminal-profile-verify stage=profile-name-mismatch")
                    throw TerminalProfileApplicationError.verificationFailed
                }
                let matches = strictBounds ? WindowFrameFit.restored(actual.bounds.frame, before: bounds.frame)
                                           : WindowFrameFit.accepts(actual.bounds.frame, target: bounds.frame)
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                switch TerminalProfileVerification.step(matches: matches, previousBounds: stableBounds,
                    actualBounds: actual.bounds, elapsed: elapsed, readCount: readCount) {
                case .complete: return actual
                case .readAgain: stableBounds = matches ? actual.bounds : nil
                case .timedOut:
                    let dx = actual.bounds.left - bounds.left, dy = actual.bounds.top - bounds.top
                    let dw = (actual.bounds.right - actual.bounds.left) - (bounds.right - bounds.left)
                    let dh = (actual.bounds.bottom - actual.bounds.top) - (bounds.bottom - bounds.top)
                    Self.verificationLog.error("terminal-profile-verify stage=bounds-timeout strict=\(strictBounds, privacy: .public) dx=\(dx, privacy: .public) dy=\(dy, privacy: .public) dw=\(dw, privacy: .public) dh=\(dh, privacy: .public) matched=\(matches, privacy: .public)")
                    throw TerminalProfileApplicationError.verificationFailed
                }
                // Keep both corrections inside the four-read budget, leaving
                // two reads to confirm the unchanged strict frame predicate.
                if !matches, retry < 2 {
                    try backend.setBounds(bounds, windowID: tab.windowID)
                    retry += 1
                }
                Thread.sleep(forTimeInterval: matches ? 0.02 : 0.04)
            }
        }

        private func ensureSession(_ expected: String) throws {
            guard try backend.sessionIdentifier() == expected else { throw TerminalProfileApplicationError.sessionChanged }
        }

        private func loadBackup() throws -> Backup? {
            guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
            do {
                let handle = try FileHandle(forReadingFrom: backupURL)
                defer { try? handle.close() }
                let bytes = try handle.read(upToCount: 1_048_577) ?? Data()
                guard bytes.count <= 1_048_576 else { throw TerminalProfileApplicationError.invalidBackup }
                let state = try JSONDecoder().decode(Backup.self, from: bytes)
                guard state.version == 1, !state.session.isEmpty, state.session.utf8.count <= 512,
                      !state.originals.isEmpty, state.originals.count <= 256,
                      state.pendingRecovery.count <= 256, state.applied.count <= 256 else { throw TerminalProfileApplicationError.invalidBackup }
                _ = try TerminalProfileApplicationSnapshot(profiles: [], tabs: state.originals).validated()
                _ = try TerminalProfileApplicationSnapshot(profiles: [], tabs: state.pendingRecovery).validated()
                let keys = Set(state.originals.map(\.tab))
                guard Set(state.pendingRecovery.map(\.tab)).isSubset(of: keys),
                      Set(state.applied.map(\.tab)).count == state.applied.count,
                      Set(state.applied.map(\.tab)).isSubset(of: keys) else { throw TerminalProfileApplicationError.invalidBackup }
                for tracked in state.applied {
                    try TerminalProfileApplicationValidation.text(tracked.name)
                    if let observed = tracked.observedProfile {
                        try TerminalProfileApplicationValidation.profile(observed)
                        guard observed.name == tracked.name else { throw TerminalProfileApplicationError.invalidBackup }
                    }
                }
                if let manual = state.manualBaselines {
                    guard manual.count <= 256, Set(manual.map(\.tab)).count == manual.count,
                          Set(manual.map(\.tab)).isSubset(of: keys) else { throw TerminalProfileApplicationError.invalidBackup }
                    for entry in manual { try baselines.validateArchive(entry) }
                }
                return state
            } catch { throw TerminalProfileApplicationError.invalidBackup }
        }

        private func writeBackup(_ state: Backup) throws {
            do {
                guard state.originals.count <= 256 else { throw TerminalProfileApplicationError.invalidBackup }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(state)
                guard data.count <= 1_048_576 else { throw TerminalProfileApplicationError.invalidBackup }
                try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: backupURL, options: .atomic)
            } catch { throw TerminalProfileApplicationError.backupUnavailable }
        }
    }
}

private enum TerminalProfileApplicationValidation {
    static func text(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= 512,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw TerminalProfileApplicationError.invalidResponse }
    }
    static func profile(_ profile: TerminalPersistentProfile) throws {
        guard Int32(exactly: profile.id) != nil else { throw TerminalProfileApplicationError.invalidResponse }
        try text(profile.name)
    }
    static func key(_ tab: TerminalProfileTabKey) throws {
        guard tab.windowID > 0, Int32(exactly: tab.windowID) != nil else { throw TerminalProfileApplicationError.invalidResponse }
        try text(tab.tty)
    }
    static func tab(_ tab: TerminalProfileTabSnapshot) throws {
        try key(tab.tab); try profile(tab.profile)
        guard tab.bounds.valid else { throw TerminalProfileApplicationError.invalidResponse }
    }
}

/// All lookups enumerate and require one exact match. No `whose` filter, tab
/// index, window title, terminal text, new window, open/import or shell command.
final class AppleScriptTerminalProfileApplicationBackend: TerminalProfileApplicationBackend {
    func sessionIdentifier() throws -> String {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").filter { !$0.isTerminated }
        // AppleScript addresses the bundle, so selecting an arbitrary PID when
        // several instances exist cannot establish which session receives it.
        guard applications.count <= 1 else { throw TerminalProfileApplicationError.ambiguousTerminalSession }
        guard let app = applications.first, let date = app.launchDate else { throw TerminalProfileApplicationError.terminalNotRunning }
        return "\(app.processIdentifier):\(date.timeIntervalSince1970)"
    }

    func snapshot() throws -> TerminalProfileApplicationSnapshot {
        _ = try sessionIdentifier()
        return try Self.parseSnapshot(execute(Self.snapshotScript))
    }

    func setProfile(_ profile: TerminalPersistentProfile, tab: TerminalProfileTabKey) throws {
        _ = try sessionIdentifier()
        _ = try execute(Self.setProfileScript(profile, tab: tab))
    }

    func setBounds(_ bounds: TerminalProfileWindowBounds, windowID: Int) throws {
        _ = try sessionIdentifier()
        _ = try execute(Self.setBoundsScript(bounds, windowID: windowID))
    }

    func appearance(profile: TerminalPersistentProfile, tab: TerminalProfileTabKey?) throws -> TerminalProfileAppearance {
        _ = try sessionIdentifier()
        return try Self.parseAppearance(execute(Self.appearanceScript(profile: profile, tab: tab)))
    }

    func duplicateProfile(_ original: TerminalProfileTabSnapshot, named name: String) throws -> TerminalPersistentProfile {
        _ = try sessionIdentifier()
        // execute preserves Automation denial and the numeric AppleScript
        // error. Never log the script, profile name, or preference data.
        let result = try execute(Self.duplicateProfileScript(original, named: name))
        let fields = try Self.items(result, count: 2)
        let copied = try TerminalPersistentProfile(id: Self.integer(fields[0]), name: Self.text(fields[1]))
        try TerminalProfileApplicationValidation.profile(copied)
        guard copied.name == name else { throw TerminalProfileApplicationError.invalidRecoveryBaseline }
        return copied
    }

    static func duplicateProfileScript(_ original: TerminalProfileTabSnapshot, named name: String) throws -> String {
        try TerminalProfileApplicationValidation.tab(original)
        guard name.hasPrefix("OmniVibe Recovery "), UUID(uuidString: String(name.dropFirst("OmniVibe Recovery ".count))) != nil else {
            throw TerminalProfileApplicationError.invalidRecoveryBaseline
        }
        return """
        if application id "com.apple.Terminal" is not running then error number -600
        tell application id "com.apple.Terminal"
            with timeout of 30 seconds
                \(try windowResolver(original.tab.windowID))
                set requestedTTY to \(literal(original.tab.tty))
                set originalSettings to missing value
                set matchingTabs to 0
                repeat with candidateTab in tabs of targetWindow
                    if ((tty of candidateTab) as text) is requestedTTY then
                        set originalSettings to current settings of candidateTab
                        set matchingTabs to matchingTabs + 1
                    end if
                end repeat
                if matchingTabs is not 1 then error number -1728
                if ((id of originalSettings) as integer) is not \(original.profile.id) then error number -1728
                if ((name of originalSettings) as text) is not \(literal(original.profile.name)) then error number -1728
                set recoveryName to \(literal(name))
                repeat with savedProfile in settings sets
                    if ((name of savedProfile) as text) is recoveryName then error number -1728
                end repeat
                duplicate originalSettings to end of settings sets with properties {name:recoveryName}
                set copiedID to missing value
                set matchingProfiles to 0
                repeat with savedProfile in settings sets
                    if ((name of savedProfile) as text) is recoveryName then
                        set copiedID to (id of savedProfile) as integer
                        set matchingProfiles to matchingProfiles + 1
                    end if
                end repeat
                if matchingProfiles is not 1 then error number -1728
                if ((id of originalSettings) as integer) is not \(original.profile.id) then error number -1728
                if ((name of originalSettings) as text) is not \(literal(original.profile.name)) then error number -1728
                return {copiedID, recoveryName}
            end timeout
        end tell
        """
    }

    static func appearanceScript(profile: TerminalPersistentProfile, tab: TerminalProfileTabKey?) throws -> String {
        try TerminalProfileApplicationValidation.profile(profile)
        let resolver: String
        if let tab {
            try TerminalProfileApplicationValidation.key(tab)
            resolver = """
            \(try windowResolver(tab.windowID))
            set requestedTTY to \(literal(tab.tty))
            set profileObject to missing value
            set matchingTabs to 0
            repeat with candidateTab in tabs of targetWindow
                if ((tty of candidateTab) as text) is requestedTTY then
                    set profileObject to current settings of candidateTab
                    set matchingTabs to matchingTabs + 1
                end if
            end repeat
            if matchingTabs is not 1 then error number -1728
            """
        } else {
            resolver = """
            set profileObject to missing value
            set matchingProfiles to 0
            repeat with savedProfile in settings sets
                if ((id of savedProfile) as integer) is \(profile.id) and ((name of savedProfile) as text) is \(literal(profile.name)) then
                    set profileObject to savedProfile
                    set matchingProfiles to matchingProfiles + 1
                end if
            end repeat
            if matchingProfiles is not 1 then error number -1728
            """
        }
        return """
        if application id "com.apple.Terminal" is not running then error number -600
        tell application id "com.apple.Terminal"
            with timeout of 30 seconds
                \(resolver)
                if ((id of profileObject) as integer) is not \(profile.id) then error number -1728
                if ((name of profileObject) as text) is not \(literal(profile.name)) then error number -1728
                return {{(background color of profileObject) as list, (normal text color of profileObject) as list, (bold text color of profileObject) as list, (cursor color of profileObject) as list}, (font name of profileObject) as text, (font size of profileObject) as integer}
            end timeout
        end tell
        """
    }

    static func parseAppearance(_ descriptor: NSAppleEventDescriptor) throws -> TerminalProfileAppearance {
        let fields = try items(descriptor, count: 3)
        let name = try text(fields[1])
        let size = try integer(fields[2])
        guard size > 0, size < 1000 else { throw TerminalProfileApplicationError.invalidResponse }
        return TerminalProfileAppearance(palette: try AppleScriptTerminalThemeBackend.parsePalette(fields[0]), fontName: name, fontSize: Double(size))
    }

    static let snapshotScript = """
    if application id "com.apple.Terminal" is not running then error number -600
    tell application id "com.apple.Terminal"
        with timeout of 30 seconds
            set profileRows to {}
            repeat with savedProfile in settings sets
                set end of profileRows to {(id of savedProfile) as integer, (name of savedProfile) as text}
            end repeat
            set tabRows to {}
            repeat with terminalWindow in windows
                set windowID to (id of terminalWindow) as integer
                set windowBounds to (bounds of terminalWindow) as list
                repeat with terminalTab in tabs of terminalWindow
                    set profileObject to current settings of terminalTab
                    set end of tabRows to {windowID, (tty of terminalTab) as text, (id of profileObject) as integer, (name of profileObject) as text, windowBounds}
                end repeat
            end repeat
            return {profileRows, tabRows}
        end timeout
    end tell
    """

    static func setProfileScript(_ profile: TerminalPersistentProfile, tab: TerminalProfileTabKey) throws -> String {
        try TerminalProfileApplicationValidation.profile(profile)
        try TerminalProfileApplicationValidation.key(tab)
        return """
        if application id "com.apple.Terminal" is not running then error number -600
        tell application id "com.apple.Terminal"
            with timeout of 30 seconds
                \(try windowResolver(tab.windowID))
                set requestedTTY to \(literal(tab.tty))
                set targetTab to missing value
                set matchingTabs to 0
                repeat with candidateTab in tabs of targetWindow
                    if ((tty of candidateTab) as text) is requestedTTY then
                        set targetTab to candidateTab
                        set matchingTabs to matchingTabs + 1
                    end if
                end repeat
                if matchingTabs is not 1 then error number -1728
                set requestedProfileName to \(literal(profile.name))
                set targetProfile to missing value
                set matchingProfiles to 0
                repeat with savedProfile in settings sets
                    if ((id of savedProfile) as integer) is \(profile.id) and ((name of savedProfile) as text) is requestedProfileName then
                        set targetProfile to savedProfile
                        set matchingProfiles to matchingProfiles + 1
                    end if
                end repeat
                if matchingProfiles is not 1 then error number -1728
                if ((id of targetWindow) as integer) is not \(tab.windowID) then error number -1728
                if ((tty of targetTab) as text) is not requestedTTY then error number -1728
                set current settings of targetTab to targetProfile
                if ((tty of targetTab) as text) is not requestedTTY then error number -1728
                if ((name of current settings of targetTab) as text) is not requestedProfileName then error number -1728
            end timeout
        end tell
        """
    }

    static func setBoundsScript(_ bounds: TerminalProfileWindowBounds, windowID: Int) throws -> String {
        guard bounds.valid else { throw TerminalProfileApplicationError.invalidResponse }
        return """
        if application id "com.apple.Terminal" is not running then error number -600
        tell application id "com.apple.Terminal"
            with timeout of 30 seconds
                \(try windowResolver(windowID))
                if ((id of targetWindow) as integer) is not \(windowID) then error number -1728
                set bounds of targetWindow to \(bounds.scriptLiteral)
                return (bounds of targetWindow) as list
            end timeout
        end tell
        """
    }

    private static func windowResolver(_ windowID: Int) throws -> String {
        guard windowID > 0, Int32(exactly: windowID) != nil else { throw TerminalProfileApplicationError.invalidResponse }
        return """
        set targetWindow to missing value
        set matchingWindows to 0
        repeat with candidateWindow in windows
            if ((id of candidateWindow) as integer) is \(windowID) then
                set targetWindow to candidateWindow
                set matchingWindows to matchingWindows + 1
            end if
        end repeat
        if matchingWindows is not 1 then error number -1728
        """
    }

    private static func literal(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard !Thread.isMainThread else { throw TerminalProfileApplicationError.workerRequired }
        guard let script = NSAppleScript(source: source) else { throw TerminalProfileApplicationError.scriptFailed(0) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if code == -1743 { throw TerminalProfileApplicationError.automationDenied }
            if code == -600 { throw TerminalProfileApplicationError.terminalNotRunning }
            throw TerminalProfileApplicationError.scriptFailed(code)
        }
        return result
    }

    static func parseSnapshot(_ value: NSAppleEventDescriptor) throws -> TerminalProfileApplicationSnapshot {
        let lists = try items(value, count: 2)
        let profiles = try items(lists[0], maximum: 256).map { row -> TerminalPersistentProfile in
            let fields = try items(row, count: 2)
            return TerminalPersistentProfile(id: try integer(fields[0]), name: try text(fields[1]))
        }
        let tabs = try items(lists[1], maximum: 256).map { row -> TerminalProfileTabSnapshot in
            let fields = try items(row, count: 5)
            let bounds = try items(fields[4], count: 4).map(integer)
            return TerminalProfileTabSnapshot(tab: TerminalProfileTabKey(windowID: try integer(fields[0]), tty: try text(fields[1])),
                profile: TerminalPersistentProfile(id: try integer(fields[2]), name: try text(fields[3])),
                bounds: TerminalProfileWindowBounds(left: bounds[0], top: bounds[1], right: bounds[2], bottom: bounds[3]))
        }
        return try TerminalProfileApplicationSnapshot(profiles: profiles, tabs: tabs).validated()
    }

    private static func items(_ value: NSAppleEventDescriptor, count: Int? = nil, maximum: Int = 256) throws -> [NSAppleEventDescriptor] {
        guard value.descriptorType == typeAEList, value.numberOfItems <= maximum,
              count == nil || value.numberOfItems == count else { throw TerminalProfileApplicationError.invalidResponse }
        guard value.numberOfItems > 0 else { return [] }
        return try (1...value.numberOfItems).map { index in
            guard let element = value.atIndex(index) else { throw TerminalProfileApplicationError.invalidResponse }
            return element
        }
    }

    private static func integer(_ value: NSAppleEventDescriptor) throws -> Int {
        guard [typeSInt16, typeSInt32, typeSInt64, typeUInt32].contains(value.descriptorType),
              let text = value.coerce(toDescriptorType: typeUnicodeText)?.stringValue,
              let number = Int(text), Int32(exactly: number) != nil else { throw TerminalProfileApplicationError.invalidResponse }
        return number
    }

    private static func text(_ value: NSAppleEventDescriptor) throws -> String {
        guard [typeUnicodeText, typeUTF8Text, typeChar].contains(value.descriptorType), let result = value.stringValue else {
            throw TerminalProfileApplicationError.invalidResponse
        }
        try TerminalProfileApplicationValidation.text(result)
        return result
    }
}

enum TerminalProfileApplicationError: LocalizedError {
    case busy, invalidProfileName, invalidResponse, terminalNotRunning, ambiguousTerminalSession, automationDenied, noOpenTabs
    case profileNotImported, ambiguousProfile, needsBaselineSave(Int), originalProfileUnavailable, tabMoved
    case invalidBackup, backupUnavailable, noBackup, backupCleanupFailed, sessionChanged, currentSessionArchiveForbidden
    case recoveryRequired, verificationFailed, workerRequired, scriptFailed(Int)
    case applyFailed(String, Int), restoreIncomplete(Int)
    case invalidRecoveryBaseline, recoveryBaselineMismatch, baselineMetadataUnavailable
    case nativeCopyUnsupported, nativeCopyNotPersisted, nativeCopyVerificationFailed

    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .busy: return "Terminal 配置操作正在进行，请稍候。"
            case .invalidProfileName: return "请选择已导入的 OmniVibe 终端主题配置。"
            case .invalidResponse: return "Terminal 返回的窗口、标签页或配置标识无法安全确认，本次操作已停止。"
            case .terminalNotRunning: return "请先打开 Terminal，再检查或应用终端主题。"
            case .ambiguousTerminalSession: return "检测到多个 Terminal 应用实例。请先保留一个实例后重试，以免修改错误的终端。"
            case .automationDenied: return "未获得控制 Terminal 的自动化权限，请在系统设置中允许后重试。"
            case .noOpenTabs: return "没有已打开的 Terminal 标签页可应用主题。"
            case .profileNotImported: return "尚未导入此 OmniVibe 配置，请先在 Terminal 的设置中导入主题文件。"
            case .ambiguousProfile: return "Terminal 中有同名主题配置，请先保留唯一一份，再重新检查。"
            case .needsBaselineSave(let count): return "\(count) 个标签页的原配置尚无法独立定位并恢复。请先自动备份原配置，再重新检查；自动备份不可用时，可手工导出并指定恢复基准。"
            case .invalidRecoveryBaseline: return "恢复基准无法确认。请为每个标签页选择完整导出的 .terminal 文件和已导入、名称唯一的新恢复配置；程序会按你指定的配置恢复，不会猜测临时配置。"
            case .recoveryBaselineMismatch: return "导出文件、当前标签页与所选恢复配置的公开配色或字体不同，尚未登记恢复基准。"
            case .baselineMetadataUnavailable: return "无法核对恢复配置的配色和字体，本次未登记或切换终端主题。"
            case .nativeCopyUnsupported: return "当前 Terminal 未完成原配置的原生复制，原标签页尚未切换。可稍后重试自动备份；原窗口和已有备份均保留。"
            case .nativeCopyNotPersisted: return "Terminal 的原配置副本尚未持久保存或无法完整读取，尚未切换主题。请稍后重试，原窗口和已有备份均保留。"
            case .nativeCopyVerificationFailed: return "原配置副本的身份、完整文件、配色或字体未通过核验，尚未切换主题。原窗口和已有备份均保留，可重试自动备份。"
            case .originalProfileUnavailable: return "原终端配置已改名或删除，无法保证恢复；已停止切换并保留备份。"
            case .tabMoved: return "已有备份的标签页已移到其他窗口。请先移回原窗口并恢复原配置，再重新应用主题。"
            case .invalidBackup: return "原终端配置备份无法安全读取，已保留原文件并停止修改。"
            case .backupUnavailable: return "无法安全保存原终端配置备份，尚未切换主题。"
            case .noBackup: return "没有可恢复的终端配置备份。"
            case .backupCleanupFailed: return "原配置已恢复，但备份未能清理；备份仍保留。"
            case .sessionChanged: return "Terminal 已重新启动，为避免窗口或 TTY 标识复用，已停止操作并保留备份。"
            case .currentSessionArchiveForbidden: return "备份仍属于当前 Terminal 会话，请先恢复原配置；当前会话的备份不能归档。"
            case .recoveryRequired: return "上次终端主题切换仍有待恢复项目，请先恢复原配置。"
            case .verificationFailed: return "终端主题、TTY 或窗口位置的写后核验未通过。"
            case .workerRequired: return "Terminal 配置必须在专用后台队列执行。"
            case .scriptFailed(let code): return "Terminal 配置操作失败（系统错误 \(code)）。"
            case .applyFailed(let reason, let count):
                return count == 0 ? "应用失败，已回滚本次切换并保留原配置备份：\(reason)" : "应用失败，\(count) 个标签页尚待恢复；原配置备份仍保留：\(reason)"
            case .restoreIncomplete(let count): return "\(count) 个标签页未能恢复；可能已关闭、移动或原配置不可用。备份仍保留，可稍后重试。"
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
