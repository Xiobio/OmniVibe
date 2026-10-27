import Foundation
import OmniVibeCore

/// Bounded observation after the caller's initial AX write. Callbacks must use
/// short AX messaging timeouts: a synchronous callback cannot be preempted by
/// this scheduler. No run-loop pumping or asynchronous controller reentry occurs.
@MainActor
enum WindowFrameSettlement {
    private static let maximumDuration: TimeInterval = 0.6
    private static let maximumMinimizedDuration: TimeInterval = 2
    private static let stabilityInterval: TimeInterval = 0.02
    private static let pollInterval: TimeInterval = 0.04
    private static let retryMoments: [TimeInterval] = [0.12, 0.32]
    private static let maximumSamples = 64
    private static let maximumMinimizedSamples = 128
    private static let epsilon: TimeInterval = 0.000_000_001

    static func settledFrame(target: WindowFrame, strict: Bool,
                             read: () throws -> WindowFrame?,
                             retryPosition: () throws -> Void,
                             now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                             pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) throws -> WindowFrame {
        var latest = try read()
        var budget = Budget(started: now())
        var candidate: (frame: WindowFrame, since: TimeInterval)?
        var retryIndex = 0

        func matches(_ frame: WindowFrame?) -> Bool {
            guard let frame else { return false }
            return strict ? WindowFrameFit.restored(frame, before: target) : WindowFrameFit.accepts(frame, target: target)
        }

        for _ in 0..<maximumSamples {
            let elapsed = budget.elapsed(at: now())
            let matched = matches(latest)
            if let observed = latest, matched {
                if let previous = candidate, WindowFrameFit.restored(observed, before: previous.frame) {
                    if elapsed - previous.since + epsilon >= stabilityInterval { return observed }
                } else { candidate = (observed, elapsed) }
            } else { candidate = nil }
            if elapsed + epsilon >= maximumDuration { break }

            // Only position is resent. Delayed size changes are observed, while
            // genuine minimum-size constraints retain the original fit rules.
            if !matched, retryIndex < retryMoments.count, elapsed + epsilon >= retryMoments[retryIndex] {
                try retryPosition()
                retryIndex += 1
                latest = try read()
                continue
            }
            var delay = min(matched ? stabilityInterval : pollInterval, maximumDuration - elapsed)
            if !matched, retryIndex < retryMoments.count {
                delay = min(delay, max(0, retryMoments[retryIndex] - elapsed))
            }
            guard delay > epsilon else { break }
            pause(delay)
            budget.paused += delay
            latest = try read()
        }
        // Returning a newly matching but unconfirmed frame would let the caller
        // declare success without the required second stable observation.
        guard let latest else { throw SettlementError.unreadableFrame }
        if matches(latest) { throw SettlementError.unstableFrame }
        return latest
    }

    /// The return value reports confirmation, not the observed flag. A settled
    /// target=false also returns true. An unavailable flag is unknown and resets
    /// confirmation. Failure to settle returns false so the caller can throw and
    /// retain its recovery journal; actual callback errors still propagate.
    static func settledMinimized(target: Bool, read: () throws -> Bool?,
                                 now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                                 pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) throws -> Bool {
        var latest = try read()
        var budget = Budget(started: now())
        var matchedSince: TimeInterval?
        for _ in 0..<maximumMinimizedSamples {
            let elapsed = budget.elapsed(at: now())
            if let latest, latest == target {
                if let since = matchedSince {
                    if elapsed - since + epsilon >= stabilityInterval { return true }
                } else { matchedSince = elapsed }
            } else { matchedSince = nil }
            if elapsed + epsilon >= maximumMinimizedDuration { return false }
            let delay = min(latest == target ? stabilityInterval : pollInterval, maximumMinimizedDuration - elapsed)
            guard delay > epsilon else { return false }
            pause(delay)
            budget.paused += delay
            latest = try read()
        }
        return false
    }

    private struct Budget {
        let started: TimeInterval
        var paused: TimeInterval = 0

        func elapsed(at observed: TimeInterval) -> TimeInterval {
            let clockDelta = observed - started
            let wall = clockDelta.isFinite ? max(0, clockDelta) : 0
            // A frozen/backward injected clock must not create an infinite
            // loop. Real uptime normally advances by at least each pause.
            return max(wall, paused)
        }
    }

    enum SettlementError: LocalizedError {
        case unstableFrame, unreadableFrame
        var errorDescription: String? {
            let localizedSource: String? = {
                switch self {
                case .unstableFrame: return "窗口位置或尺寸仍在变化，未能确认已经稳定，请稍后重试。"
                case .unreadableFrame: return "窗口位置或尺寸暂时无法读取，未能确认操作完成，请稍后重试。"
                }
        }()
            return localizedSource.map { L10n.errorText($0) }
        }
    }
}
