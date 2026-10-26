import Foundation
import OmniVibeCore

struct ArrangementDisplay: Equatable, Sendable {
    let id: String
    let workArea: WindowFrame
}

/// Metadata required before an explicit task switch may wake an existing app.
/// This does not establish an AX binding or confirm which window has focus.
struct WindowActivationProcess: Equatable, Sendable {
    let processID: Int32
    let startedAt: Date?
    let bundleIdentifier: String?
    let userID: UInt32?
    let terminated: Bool
}

enum WindowActivationReconnectionGuard {
    static func permits(_ saved: WindowIdentity, process: WindowActivationProcess,
                        currentSession: String?, currentUserID: UInt32,
                        serverWindows: [WindowServerCandidate]?,
                        legacyBootSeconds: Int64? = WindowSessionIdentity.currentLegacyBootSeconds()) -> Bool {
        guard saved.processID > 0, saved.processID == process.processID, !process.terminated,
              let started = saved.processStartedAt, started.timeIntervalSince1970.isFinite,
              started == process.startedAt,
              let bundle = saved.bundleIdentifier, !bundle.isEmpty, bundle == process.bundleIdentifier,
              process.userID == currentUserID,
              let currentSession else { return false }
        let pieces = currentSession.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 4, pieces[0] == "v2", UInt32(pieces[1]) == currentUserID,
              let audit = UInt32(pieces[3]),
              WindowSessionIdentity.token(userID: currentUserID, bootUUID: String(pieces[2]), auditSessionID: audit) == currentSession,
              WindowSessionIdentity.matches(saved: saved.platformSessionID, current: currentSession,
                  legacyBootSeconds: legacyBootSeconds),
              let number = saved.platformWindowNumber, number != 0, let serverWindows else { return false }
        let matches = serverWindows.filter { $0.number == number }
        return matches.count == 1 && matches[0].processID == saved.processID && matches[0].layer == 0
    }
}

/// The observed application result is retained after a failed resize so a
/// coordinator can revise its layout without treating an oversized cell as a
/// success. A recoveryFailure must be resolved before retrying a new layout.
struct WindowFrameConstraintError: LocalizedError, Equatable, Sendable {
    let requested: WindowFrame
    let actual: WindowFrame
    var recoveryFailure: String?

    init(requested: WindowFrame, actual: WindowFrame, recoveryFailure: String? = nil) {
        self.requested = requested; self.actual = actual; self.recoveryFailure = recoveryFailure
    }

    var errorDescription: String? {
        let localizedSource: String? = {
            let reason = WindowFrameFit.restrictionDescription(target: requested, actual: actual)
            guard let recoveryFailure else { return reason }
            return L10n.format("%@ 原窗口状态未能完整恢复：%@", reason, recoveryFailure)
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}

/// Keeps coordinator recovery behavior testable without controlling the user's desktop.
@MainActor
protocol WindowControlling: AnyObject {
    var isTrusted: Bool { get }
    func requestAccess()
    func openAccessibilitySettings()
    func windows() -> [WindowIdentity]
    /// Reuses a saved AX UUID only after a complete platform identity check.
    func reconnect(_ saved: WindowIdentity) -> WindowIdentity?
    /// Only an explicit task activation may wake the verified existing owner.
    /// A returned alias still needs exact-window activation and confirmation.
    func reconnectForActivation(_ saved: WindowIdentity) async throws -> WindowIdentity?
    func isAvailable(_ window: WindowIdentity) -> Bool
    /// Unlike a failed availability query, this must positively establish destruction.
    func isDefinitelyClosed(_ window: WindowIdentity) -> Bool
    func currentWindow() -> WindowIdentity?
    func activate(_ window: WindowIdentity) throws
    func confirmActivation(_ window: WindowIdentity) async throws
    func capturePlacement(_ window: WindowIdentity) throws -> WindowPlacement
    func captureTrackingPlacement(_ window: WindowIdentity) throws -> WindowPlacement
    func restore(_ window: WindowIdentity, to placement: WindowPlacement) throws
    func setFrame(_ target: WindowFrame, for window: WindowIdentity) throws
    func workArea(for window: WindowIdentity?) -> WindowFrame
    func previewDescriptor(_ window: WindowIdentity) -> WindowPreviewDescriptor?
    func arrangementBlockReason(_ window: WindowIdentity) -> String?
    func captureArrangementPlacement(_ window: WindowIdentity) throws -> WindowPlacement
    func arrangementDisplay(for window: WindowIdentity) -> ArrangementDisplay
}

extension WindowControlling {
    func reconnect(_ saved: WindowIdentity) -> WindowIdentity? { nil }
    func reconnectForActivation(_ saved: WindowIdentity) async throws -> WindowIdentity? {
        try Task.checkCancellation()
        return reconnect(saved)
    }
    func captureTrackingPlacement(_ window: WindowIdentity) throws -> WindowPlacement { try capturePlacement(window) }
    func previewDescriptor(_ window: WindowIdentity) -> WindowPreviewDescriptor? { nil }
    func arrangementBlockReason(_ window: WindowIdentity) -> String? { nil }
    func captureArrangementPlacement(_ window: WindowIdentity) throws -> WindowPlacement { try capturePlacement(window) }
    func arrangementDisplay(for window: WindowIdentity) -> ArrangementDisplay {
        let area = workArea(for: window)
        return ArrangementDisplay(id: "\(area.x):\(area.y):\(area.width):\(area.height)", workArea: area)
    }
}

extension WindowService: WindowControlling {}
