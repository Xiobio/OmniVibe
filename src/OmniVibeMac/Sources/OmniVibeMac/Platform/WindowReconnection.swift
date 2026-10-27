import CoreGraphics
import Darwin
import Foundation
import OmniVibeCore
import Security

/// Metadata only: no screen capture, Accessibility calls or permission prompts.
struct AccessibilityWindowCandidate: Equatable, Sendable {
    let index: Int
    let processID: Int32
    let title: String
    let frame: WindowFrame
}

struct WindowServerCandidate: Equatable, Sendable {
    let number: UInt32
    let processID: Int32
    let title: String?
    let frame: WindowFrame
    let layer: Int
}

enum WindowReconnectionMatcher {
    /// Only call after the cached AX object is invalid and the saved process /
    /// session identity is verified. An unreadable CG inventory is unknown.
    static func isClosedAfterInvalidProxy(windowNumber: UInt32, processID: Int32,
                                          server: [WindowServerCandidate]?) -> Bool {
        guard let server else { return false }
        return !server.contains { $0.number == windowNumber && $0.processID == processID }
    }

    /// This establishes only the current AX-to-CG association. Geometry must
    /// uniquely identify one AX window and one ordinary CG window for this PID.
    /// A visible CG title is an additional exact check, never a fuzzy lookup.
    /// CG may redact titles without Screen Recording access; no image is read.
    static func uniqueWindowNumber(for index: Int, accessibility: [AccessibilityWindowCandidate],
                                   server: [WindowServerCandidate], tolerance: Double = 2) -> UInt32? {
        guard tolerance.isFinite, (0...2).contains(tolerance),
              accessibility.filter({ $0.index == index }).count == 1,
              let target = accessibility.first(where: { $0.index == index }),
              target.processID > 0, valid(target.frame) else { return nil }
        let peers = accessibility.filter {
            $0.processID == target.processID && valid($0.frame) && near($0.frame, target.frame, tolerance: tolerance)
        }
        guard peers.count == 1 else { return nil }
        let matches = server.filter {
            $0.number != 0 && $0.processID == target.processID && $0.layer == 0 &&
            valid($0.frame) && near($0.frame, target.frame, tolerance: tolerance)
        }
        guard matches.count == 1, let candidate = matches.first else { return nil }
        // Also require a unique reverse association around the CG bounds. Two
        // AX windows can lie on opposite sides of the permitted rounding error.
        guard accessibility.filter({
            $0.processID == candidate.processID && valid($0.frame) && near($0.frame, candidate.frame, tolerance: tolerance)
        }).count == 1 else { return nil }
        if let title = candidate.title, !title.isEmpty, title != target.title { return nil }
        return candidate.number
    }

    /// The saved CG ID is the reconnection key. Current title and geometry are
    /// used only above to prove which live AX object owns that ID. Renaming or
    /// moving the same window while OmniVibe is closed is therefore supported.
    static func alias(saved: WindowIdentity, current: WindowIdentity, sessionID: String?,
                      legacyBootSeconds: Int64? = WindowSessionIdentity.currentLegacyBootSeconds()) -> WindowIdentity? {
        guard let sessionID, !sessionID.isEmpty,
              current.platformSessionID == sessionID,
              let number = saved.platformWindowNumber, number != 0, number == current.platformWindowNumber,
              saved.processID > 0, saved.processID == current.processID,
              let started = saved.processStartedAt, started.timeIntervalSince1970.isFinite,
              started == current.processStartedAt,
              saved.bundleIdentifier == current.bundleIdentifier,
              WindowSessionIdentity.matches(saved: saved.platformSessionID, current: sessionID,
                  legacyBootSeconds: legacyBootSeconds) else { return nil }
        var restored = current
        restored.id = saved.id
        return restored
    }

    private static func valid(_ frame: WindowFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite && frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
    }

    private static func near(_ lhs: WindowFrame, _ rhs: WindowFrame, tolerance: Double) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}

enum WindowSessionIdentity {
    /// XNU initializes kern.bootsessionuuid once per boot. Unlike kern.boottime,
    /// it is independent of wall-clock corrections and sleep/wake adjustments.
    /// UID and the Security login session still prevent cross-user/logout reuse.
    /// Missing metadata disables reconnection; no time-based fallback is used.
    static func current() -> String? {
        var session: SecuritySessionId = 0
        guard SessionGetInfo(callerSecuritySession, &session, nil) == errSecSuccess,
              session != 0, session != callerSecuritySession else { return nil }
        return token(userID: geteuid(), bootUUID: bootSessionUUID(), auditSessionID: session)
    }

    static func token(userID: UInt32, bootUUID: String?, auditSessionID: UInt32) -> String? {
        guard let bootUUID, bootUUID.utf8.count == 36, let uuid = UUID(uuidString: bootUUID),
              uuid != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              auditSessionID != 0, auditSessionID != UInt32.max else { return nil }
        return "v2:\(userID):\(uuid.uuidString):\(auditSessionID)"
    }

    /// Invoke only after the owner PID, exact process start and CG window have
    /// been verified. Migration is one-way: only old tokens may omit the boot
    /// UUID, and they still need the exact current legacy boot seconds/UID/audit.
    /// The injected seconds keep migration tests independent of the host clock.
    static func matches(saved: String?, current: String?,
                        legacyBootSeconds: Int64? = WindowSessionIdentity.currentLegacyBootSeconds()) -> Bool {
        guard let saved, let current, !saved.isEmpty, !current.isEmpty else { return false }
        if let currentToken = StableToken(current) {
            if let savedToken = StableToken(saved) { return savedToken == currentToken }
            guard let legacy = LegacyToken(saved), let legacyBootSeconds, legacyBootSeconds > 0 else { return false }
            return legacy.userID == currentToken.userID && legacy.auditSessionID == currentToken.auditSessionID &&
                legacy.bootSeconds == legacyBootSeconds
        }
        // Exact opaque tokens remain compatible with older callers. A malformed
        // v2 token is never accepted, and legacy values cannot upgrade a v2 one.
        guard !saved.hasPrefix("v2:"), !current.hasPrefix("v2:") else { return false }
        return saved == current
    }

    static func currentLegacyBootSeconds() -> Int64? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var name: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&name, UInt32(name.count), &boot, &size, nil, 0) == 0,
              size == MemoryLayout<timeval>.size, boot.tv_sec > 0 else { return nil }
        return Int64(boot.tv_sec)
    }

    private static func bootSessionUUID() -> String? {
        // XNU: bsd/kern/kern_sysctl.c registers this read-only UUID string;
        // iokit/Kernel/IOPMrootDomain.cpp initializes it at boot, not at wake.
        var bytes = [CChar](repeating: 0, count: 37)
        var size = bytes.count
        let result = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname("kern.bootsessionuuid", buffer.baseAddress, &size, nil, 0)
        }
        guard result == 0, size == bytes.count, bytes.last == 0 else { return nil }
        return String(bytes: bytes.dropLast().map { UInt8(bitPattern: $0) }, encoding: .ascii)
    }

    private struct StableToken: Equatable {
        let userID: UInt32
        let bootUUID: UUID
        let auditSessionID: UInt32

        init?(_ value: String) {
            let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 4, pieces[0] == "v2",
                  let userID = WindowSessionIdentity.unsigned(pieces[1]),
                  let audit = WindowSessionIdentity.unsigned(pieces[3]),
                  WindowSessionIdentity.token(userID: userID,
                      bootUUID: String(pieces[2]), auditSessionID: audit) != nil,
                  let uuid = UUID(uuidString: String(pieces[2])) else { return nil }
            self.userID = userID; bootUUID = uuid; auditSessionID = audit
        }
    }

    private struct LegacyToken {
        let userID: UInt32
        let bootSeconds: Int64
        let auditSessionID: UInt32

        init?(_ value: String) {
            let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 4,
                  let userID = WindowSessionIdentity.unsigned(pieces[0]),
                  pieces[1].utf8.allSatisfy({ (48...57).contains($0) }),
                  let seconds = Int64(pieces[1]), seconds > 0,
                  let microseconds = WindowSessionIdentity.unsigned(pieces[2]), microseconds < 1_000_000,
                  let audit = WindowSessionIdentity.unsigned(pieces[3]), audit != 0, audit != UInt32.max else { return nil }
            self.userID = userID; bootSeconds = seconds; auditSessionID = audit
        }
    }

    private static func unsigned(_ value: Substring) -> UInt32? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return UInt32(value)
    }

    /// Reads only WindowServer metadata. This never asks for Screen Recording
    /// access and does not capture pixels, window contents or terminal output.
    static func serverWindows() -> [WindowServerCandidate]? {
        guard let records = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return records.compactMap { record in
            guard let number = record[kCGWindowNumber as String] as? NSNumber,
                  let pid = record[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = record[kCGWindowLayer as String] as? NSNumber,
                  let bounds = record[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? NSNumber, let y = bounds["Y"] as? NSNumber,
                  let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber,
                  number.uint64Value > 0, number.uint64Value <= UInt64(UInt32.max),
                  pid.int64Value > 0, pid.int64Value <= Int64(Int32.max) else { return nil }
            return WindowServerCandidate(number: number.uint32Value, processID: pid.int32Value,
                title: record[kCGWindowName as String] as? String,
                frame: WindowFrame(x: x.doubleValue, y: y.doubleValue, width: width.doubleValue, height: height.doubleValue),
                layer: layer.intValue)
        }
    }
}
