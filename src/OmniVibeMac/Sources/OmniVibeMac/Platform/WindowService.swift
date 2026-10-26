import AppKit
import ApplicationServices
import Darwin
import OmniVibeCore
import OSLog

/// Uses public Accessibility and WindowServer metadata APIs. A saved title is
/// never enough to reconnect: a complete session/process/CG identity is required.
@MainActor
final class WindowService {
    private struct Entry {
        var identity: WindowIdentity
        let element: AXUIElement
        var lastPlatformAttempt: TimeInterval = 0
    }

    private var entries: [UUID: Entry] = [:]
    private let messagingTimeout: Float = 0.25
    private var explicitOperationDepth: [UUID: Int] = [:]
    private var platformSessionID: String? { WindowSessionIdentity.current() }
    private var reconnectionReadDeadline: TimeInterval?
    private var reconnectionWindowHints: [AXUIElement] = []
    private let activationLogger = Logger(subsystem: "com.xiobio.omnivibe", category: "WindowReconnection")

    init() {}

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func windows() -> [WindowIdentity] {
        guard isTrusted else { return [] }
        return windows(in: NSWorkspace.shared.runningApplications)
    }

    /// A known helper PID needs no Accessibility queries to unrelated apps.
    /// Token verification still uses the same WindowServer metadata checks.
    func windows(for processID: pid_t) -> [WindowIdentity] {
        guard isTrusted, processID > 0,
              let app = NSRunningApplication(processIdentifier: processID) else { return [] }
        return windows(in: [app], refreshPlatformIdentity: true)
    }

    private func windows(in applications: [NSRunningApplication], refreshPlatformIdentity: Bool = false) -> [WindowIdentity] {
        var result: [WindowIdentity] = []
        for app in applications where
            app.activationPolicy == .regular &&
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
            !app.isTerminated {
            // A launch date is needed to protect against a reused process ID.
            guard app.launchDate != nil else { continue }
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, messagingTimeout)
            let elements = observedWindows(application)
            for element in elements {
                if let identity = remember(element, application: app, refreshPlatformIdentity: refreshPlatformIdentity) { result.append(identity) }
            }
        }
        entries = entries.filter { _, entry in
            guard let app = NSRunningApplication(processIdentifier: entry.identity.processID) else { return false }
            return !app.isTerminated && app.launchDate == entry.identity.processStartedAt
        }
        return result.sorted {
            let applicationComparison = $0.applicationName.localizedStandardCompare($1.applicationName)
            if applicationComparison != .orderedSame { return applicationComparison == .orderedAscending }
            let titleComparison = $0.title.localizedStandardCompare($1.title)
            if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func isAvailable(_ window: WindowIdentity) -> Bool {
        guard isTrusted, let entry = validEntry(window) else { return false }
        return (attribute(entry.element, kAXRoleAttribute) as? String) == (kAXWindowRole as String)
    }

    /// Rebuilds only the verified live AX reference, preserving the saved UUID.
    /// Legacy workspaces without platform tokens require explicit confirmation.
    /// No window is activated, moved, resized or captured by this operation.
    func reconnect(_ saved: WindowIdentity) -> WindowIdentity? {
        if let deadline = reconnectionReadDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
            traceExplicitReconnection("reconnect-deadline-expired")
            return nil
        }
        guard isTrusted, let session = platformSessionID,
              WindowSessionIdentity.matches(saved: saved.platformSessionID, current: session),
              let number = saved.platformWindowNumber, number != 0,
              let started = saved.processStartedAt,
              let app = NSRunningApplication(processIdentifier: saved.processID), !app.isTerminated,
              app.launchDate == started, app.bundleIdentifier == saved.bundleIdentifier else {
            traceExplicitReconnection("reconnect-owner-guard-failed")
            return nil
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        let elements = observedWindows(application)
        if elements.isEmpty { traceExplicitReconnection("reconnect-observed-windows-empty") }
        var matches: [Entry] = []
        for element in elements {
            guard let current = remember(element, application: app, refreshPlatformIdentity: true) else { continue }
            guard let alias = WindowReconnectionMatcher.alias(saved: saved, current: current, sessionID: session) else {
                traceExplicitReconnection("reconnect-alias-failed")
                continue
            }
            guard let live = entries[current.id] else {
                traceExplicitReconnection("reconnect-entry-missing")
                continue
            }
            matches.append(Entry(identity: alias, element: live.element))
        }
        guard matches.count == 1, let restored = matches.first else {
            traceExplicitReconnection("reconnect-match-count-invalid")
            return nil
        }
        // One physical AX object must have one cache UUID. Do not leave the
        // newly discovered temporary UUID available as a second live target.
        let duplicates = entries.filter {
            $0.key != saved.id && $0.value.identity.processID == saved.processID && CFEqual($0.value.element, restored.element)
        }.map(\.key)
        for id in duplicates { entries.removeValue(forKey: id) }
        entries[saved.id] = restored
        return restored.identity
    }

    /// Some apps expose no AX windows until they enter the foreground. Waking
    /// is reserved for an explicit user activation and never creates an app or
    /// substitutes its main window for the saved WindowServer identity.
    func reconnectForActivation(_ saved: WindowIdentity) async throws -> WindowIdentity? {
        try Task.checkCancellation()
        guard isTrusted else { throw WindowServiceError.permission }
        if let live = reconnect(saved) {
            try Task.checkCancellation()
            activationLogger.debug("stage=direct-reconnected")
            return live
        }
        activationLogger.debug("stage=direct-unavailable")
        guard let app = activationApplication(for: saved) else {
            activationLogger.debug("stage=owner-guard-rejected")
            return nil
        }
        try Task.checkCancellation()
        let deadline = ProcessInfo.processInfo.systemUptime + 2.5
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        do { try requestForeground(app, application: application) }
        catch { activationLogger.debug("stage=foreground-request-failed"); throw error }
        activationLogger.debug("stage=foreground-requested")
        var observedForeground = false
        var primedAccessibility = false
        var windowHints: [AXUIElement] = []
        defer {
            windowHints.removeAll()
            if !observedForeground { activationLogger.debug("stage=foreground-not-observed") }
        }
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            if !observedForeground,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                observedForeground = true
                activationLogger.debug("stage=foreground-observed")
            }
            guard isTrusted else { throw WindowServiceError.permission }
            guard activationApplication(for: saved) != nil else {
                activationLogger.debug("stage=identity-changed")
                return nil
            }
            if observedForeground && !primedAccessibility {
                primedAccessibility = true
                windowHints = try primeAccessibilityForActivation(saved, application: application, deadline: deadline)
            }
            let previousDeadline = reconnectionReadDeadline
            let previousHints = reconnectionWindowHints
            reconnectionReadDeadline = deadline
            reconnectionWindowHints = windowHints
            let live: WindowIdentity?
            do {
                defer {
                    reconnectionWindowHints = previousHints
                    reconnectionReadDeadline = previousDeadline
                }
                live = reconnect(saved)
            }
            try Task.checkCancellation()
            if let live {
                guard activationApplication(for: saved) != nil else {
                    activationLogger.debug("stage=identity-changed")
                    return nil
                }
                activationLogger.debug("stage=foreground-reconnected")
                return live
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { break }
            try await Task.sleep(nanoseconds: UInt64(min(0.1, remaining) * 1_000_000_000))
        }
        activationLogger.debug("stage=foreground-timeout")
        return nil
    }

    /// Certain accessibility bridges initialize in response to a public hit
    /// test. Only explicit activation reaches this path. Window relationships
    /// provide temporary candidates, never bindings or confirmed focus.
    private func primeAccessibilityForActivation(_ saved: WindowIdentity, application: AXUIElement,
                                                deadline: TimeInterval) throws -> [AXUIElement] {
        var hints: [AXUIElement] = []
        defer {
            if hints.isEmpty { activationLogger.debug("stage=hint-no-window") }
            else { activationLogger.debug("stage=hint-obtained") }
        }
        try Task.checkCancellation()
        guard ProcessInfo.processInfo.systemUptime < deadline,
              activationApplication(for: saved) != nil,
              let number = saved.platformWindowNumber,
              let server = WindowSessionIdentity.serverWindows() else {
            activationLogger.debug("stage=hit-test-no-value")
            return []
        }
        let matches = server.filter { $0.number == number }
        guard matches.count == 1, let window = matches.first,
              window.processID == saved.processID, window.layer == 0 else {
            activationLogger.debug("stage=hit-test-no-value")
            return []
        }
        let frame = window.frame
        guard frame.x.isFinite, frame.y.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else {
            activationLogger.debug("stage=hit-test-no-value")
            return []
        }
        let centerX = Float(frame.x + frame.width / 2)
        let titleY = Float(frame.y + min(12, frame.height / 4))
        let centerY = Float(frame.y + frame.height / 2)
        guard centerX.isFinite, titleY.isFinite, centerY.isFinite else {
            activationLogger.debug("stage=hit-test-no-value")
            return []
        }
        var receivedElement = false
        for y in [titleY, centerY] {
            try Task.checkCancellation()
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { break }
            AXUIElementSetMessagingTimeout(application, Float(min(0.20, remaining)))
            var opaqueElement: AXUIElement?
            let result = AXUIElementCopyElementAtPosition(application, centerX, y, &opaqueElement)
            if result == .success, let element = opaqueElement {
                receivedElement = true
                var owner: pid_t = 0
                if AXUIElementGetPid(element, &owner) == .success, owner == saved.processID {
                    let previousDeadline = reconnectionReadDeadline
                    reconnectionReadDeadline = deadline
                    let isWindow = (attribute(element, kAXRoleAttribute) as? String) == (kAXWindowRole as String)
                    reconnectionReadDeadline = previousDeadline
                    if isWindow { activationLogger.debug("stage=app-hit-role-window") }
                    else { activationLogger.debug("stage=app-hit-role-other") }
                    if let hint = try explicitWindowHint(from: element, processID: saved.processID, deadline: deadline),
                       !hints.contains(where: { CFEqual($0, hint) }) { hints.append(hint) }
                } else { activationLogger.debug("stage=app-hit-role-other") }
            } else { activationLogger.debug("stage=app-hit-no-value") }
            opaqueElement = nil
        }
        if hints.isEmpty {
            let systemWide = AXUIElementCreateSystemWide()
            defer { AXUIElementSetMessagingTimeout(systemWide, messagingTimeout) }
            for y in [titleY, centerY] {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == saved.processID,
                      activationApplication(for: saved) != nil else {
                    activationLogger.debug("stage=system-hit-no-value")
                    break
                }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { break }
                AXUIElementSetMessagingTimeout(systemWide, Float(min(0.20, remaining)))
                var opaqueElement: AXUIElement?
                let result = AXUIElementCopyElementAtPosition(systemWide, centerX, y, &opaqueElement)
                if result == .success, let element = opaqueElement {
                    receivedElement = true
                    var owner: pid_t = 0
                    // Ownership is checked before any attribute is read. A
                    // window covering the point must never expose another
                    // app's role, window relationship or accessibility tree.
                    if AXUIElementGetPid(element, &owner) == .success, owner == saved.processID {
                        activationLogger.debug("stage=system-hit-target")
                        if let hint = try explicitWindowHint(from: element, processID: saved.processID, deadline: deadline),
                           !hints.contains(where: { CFEqual($0, hint) }) { hints.append(hint) }
                    } else { activationLogger.debug("stage=system-hit-foreign") }
                } else { activationLogger.debug("stage=system-hit-no-value") }
                opaqueElement = nil
            }
        }
        if receivedElement { activationLogger.debug("stage=hit-test-completed") }
        else { activationLogger.debug("stage=hit-test-no-value") }
        return hints
    }

    /// Follow only Role, AXWindow and at most six AXParent relationships.
    /// Text, values, child trees and accessible names are never requested.
    private func explicitWindowHint(from element: AXUIElement, processID: pid_t,
                                    deadline: TimeInterval) throws -> AXUIElement? {
        let previousDeadline = reconnectionReadDeadline
        reconnectionReadDeadline = deadline
        defer { reconnectionReadDeadline = previousDeadline }
        var current = element
        var visited: [AXUIElement] = []
        for depth in 0...6 {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  !visited.contains(where: { CFEqual($0, current) }) else { return nil }
            visited.append(current)
            var owner: pid_t = 0
            guard AXUIElementGetPid(current, &owner) == .success, owner == processID else { return nil }
            if (attribute(current, kAXRoleAttribute) as? String) == (kAXWindowRole as String) { return current }
            if let value = attribute(current, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let window = unsafeBitCast(value, to: AXUIElement.self)
                var windowOwner: pid_t = 0
                if AXUIElementGetPid(window, &windowOwner) == .success, windowOwner == processID,
                   (attribute(window, kAXRoleAttribute) as? String) == (kAXWindowRole as String) { return window }
            }
            guard depth < 6, let parent = attribute(current, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            current = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return nil
    }

    private func activationApplication(for saved: WindowIdentity) -> NSRunningApplication? {
        guard isTrusted, saved.processID != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: saved.processID) else { return nil }
        let process = WindowActivationProcess(processID: app.processIdentifier, startedAt: app.launchDate,
            bundleIdentifier: app.bundleIdentifier, userID: processEffectiveUserID(app.processIdentifier), terminated: app.isTerminated)
        guard WindowActivationReconnectionGuard.permits(saved, process: process, currentSession: platformSessionID,
            currentUserID: geteuid(), serverWindows: WindowSessionIdentity.serverWindows()) else { return nil }
        return app
    }

    private func processEffectiveUserID(_ pid: pid_t) -> UInt32? {
        guard pid > 0 else { return nil }
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &process, &size, nil, 0) == 0,
              size == MemoryLayout<kinfo_proc>.size, process.kp_proc.p_pid == pid else { return nil }
        return process.kp_eproc.e_ucred.cr_uid
    }

    /// Unavailability is not proof of destruction: an AX timeout, revoked
    /// permission, or a previous session's uncached token must retain recovery
    /// snapshots. Only an observed process exit/reuse or invalid AX object is
    /// conclusive enough to discard them.
    func isDefinitelyClosed(_ window: WindowIdentity) -> Bool {
        guard isTrusted, window.processID > 0 else { return false }
        if kill(window.processID, 0) != 0, errno == ESRCH { return true }
        if let app = NSRunningApplication(processIdentifier: window.processID) {
            if app.isTerminated { return true }
            if let expected = window.processStartedAt, let actual = app.launchDate, expected != actual { return true }
        }
        guard let entry = entries[window.id],
              entry.identity.processID == window.processID,
              entry.identity.processStartedAt == window.processStartedAt,
              entry.identity.bundleIdentifier == window.bundleIdentifier else { return false }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(entry.element, kAXRoleAttribute as CFString, &role) == .invalidUIElement else { return false }
        if let number = window.platformWindowNumber,
           WindowSessionIdentity.matches(saved: window.platformSessionID, current: platformSessionID),
           WindowSessionIdentity.serverWindows()?.contains(where: { $0.number == number && $0.processID == window.processID }) == true {
            // The AX proxy was rebuilt, while the original WindowServer window
            // is still alive. Keep the task available for verified reconnect.
            return false
        }
        return true
    }

    func currentWindow() -> WindowIdentity? {
        guard isTrusted,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.launchDate != nil else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        guard let value = attribute(application, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        return remember(element, application: app)
    }

    func activate(_ window: WindowIdentity) throws {
        try withExplicitOperationTimeout(for: window) {
            try activateWindow(window)
        }
    }

    private func activateWindow(_ window: WindowIdentity) throws {
        let entry = try requiredEntry(window)
        try rejectFullScreen(entry.element)
        guard let app = NSRunningApplication(processIdentifier: window.processID) else { throw WindowServiceError.disconnected }
        let wasMinimized = try minimizedState(of: entry.element)
        if wasMinimized {
            try activationRequest(AXUIElementSetAttributeValue(entry.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse), operation: "还原目标窗口")
        }

        do {
            // Select the exact AX window before activating the application. In
            // particular, do not use activateAllWindows or merely activate app.
            if isSettable(entry.element, kAXMainAttribute) {
                try activationRequest(AXUIElementSetAttributeValue(entry.element, kAXMainAttribute as CFString, kCFBooleanTrue), operation: "选择目标窗口")
            }
            try activationRequest(AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString), operation: "置前目标窗口")
            let application = AXUIElementCreateApplication(window.processID)
            AXUIElementSetMessagingTimeout(application, 1)
            try requestForeground(app, application: application)
            // The application's activation may initially raise its previous key
            // window; repeat the exact-window raise after activation.
            try activationRequest(AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString), operation: "激活目标窗口")
        } catch {
            if wasMinimized { _ = AXUIElementSetAttributeValue(entry.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
            throw error
        }
    }

    /// Activation requests may complete asynchronously. The UI must await this
    /// exact-window result before presenting a slot as active.
    func confirmActivation(_ window: WindowIdentity) async throws {
        guard isTrusted else { throw WindowServiceError.permission }
        // A window can temporarily stop answering AXRole while its minimize or
        // unminimize animation runs. Validate the cached session/process first;
        // the asynchronous loop below verifies the actual AX focus result.
        guard let entry = cachedProcessEntry(window) else { throw WindowServiceError.disconnected }
        let application = AXUIElementCreateApplication(window.processID)
        AXUIElementSetMessagingTimeout(application, 0.08)
        AXUIElementSetMessagingTimeout(entry.element, 0.10)
        defer { AXUIElementSetMessagingTimeout(entry.element, messagingTimeout) }
        let deadline = Date().addingTimeInterval(2)
        var attempt = 0
        while Date() < deadline {
            try Task.checkCancellation()
            guard isTrusted else { throw WindowServiceError.permission }
            guard let app = NSRunningApplication(processIdentifier: window.processID), !app.isTerminated,
                  app.launchDate == window.processStartedAt else { throw WindowServiceError.disconnected }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == window.processID {
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
                if result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID(),
                   CFEqual(value, entry.element) { return }
                if result == .invalidUIElement { throw WindowServiceError.disconnected }
                if result == .apiDisabled { throw WindowServiceError.permission }
            }
            if attempt > 0 && attempt % 3 == 0 {
                // An earlier request may have timed out while AppKit animated
                // the window. Retry after yielding to its run loop; never treat
                // the timeout itself as confirmed success or destruction.
                if isSettable(entry.element, kAXMainAttribute) {
                    try activationRequest(AXUIElementSetAttributeValue(entry.element, kAXMainAttribute as CFString, kCFBooleanTrue), operation: "确认目标窗口选择")
                }
                try activationRequest(AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString), operation: "确认目标窗口焦点")
                try requestForeground(app, application: application)
            }
            attempt += 1
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            try await Task.sleep(nanoseconds: UInt64(min(0.12, remaining) * 1_000_000_000))
        }
        throw WindowServiceError.operation("未能确认目标窗口获得焦点，请检查当前桌面与目标应用后重试。")
    }

    func capturePlacement(_ window: WindowIdentity) throws -> WindowPlacement {
        try withExplicitOperationTimeout(for: window) {
            try captureTrackingPlacement(window)
        }
    }

    func captureTrackingPlacement(_ window: WindowIdentity) throws -> WindowPlacement {
        let entry = try requiredEntry(window)
        return WindowPlacement(frame: try frame(of: entry.element), minimized: try minimizedState(of: entry.element))
    }

    func captureArrangementPlacement(_ window: WindowIdentity) throws -> WindowPlacement {
        try capturePlacement(window)
    }

    func previewDescriptor(_ window: WindowIdentity) -> WindowPreviewDescriptor? {
        guard let entry = try? requiredEntry(window),
              let placement = try? captureTrackingPlacement(window), !placement.minimized,
              let title = attribute(entry.element, kAXTitleAttribute) as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return WindowPreviewDescriptor(window: window, frame: placement.frame, title: title)
    }

    func restore(_ window: WindowIdentity, to placement: WindowPlacement) throws {
        try withExplicitOperationTimeout(for: window) {
            try restoreWindow(window, to: placement)
        }
    }

    private func restoreWindow(_ window: WindowIdentity, to placement: WindowPlacement) throws {
        let entry = try requiredEntry(window)
        try rejectFullScreen(entry.element)
        let before = WindowPlacement(frame: try frame(of: entry.element), minimized: try minimizedState(of: entry.element))
        do {
            if !sameGeometry(before.frame, placement.frame) {
                try setWindowFrame(placement.frame, for: window, strict: true)
            }
            let restoredFrame = try frame(of: entry.element)
            guard WindowFrameFit.restored(restoredFrame, before: placement.frame) else {
                throw WindowFrameConstraintError(requested: placement.frame, actual: restoredFrame)
            }
            let currentMinimized = try minimizedState(of: entry.element)
            if currentMinimized != placement.minimized {
                try setMinimizedAndSettle(placement.minimized, element: entry.element)
            }
        } catch {
            let originalError = error
            do {
                if boolAttribute(entry.element, kAXMinimizedAttribute) == true {
                    try setMinimizedAndSettle(false, element: entry.element)
                }
                let rolledBack = try applyAndSettle(before.frame, to: entry.element, strict: true)
                guard WindowFrameFit.restored(rolledBack, before: before.frame) else {
                    throw WindowServiceError.operation("无法确认恢复尝试之前的窗口状态。")
                }
                if before.minimized { try setMinimizedAndSettle(true, element: entry.element) }
            } catch {
                if var constraint = originalError as? WindowFrameConstraintError {
                    constraint.recoveryFailure = error.localizedDescription
                    throw constraint
                }
                throw WindowServiceError.operation("\(originalError.localizedDescription) 原窗口状态未能完整恢复，请手动检查。")
            }
            throw originalError
        }
    }

    func setFrame(_ target: WindowFrame, for window: WindowIdentity) throws {
        try withExplicitOperationTimeout(for: window) {
            try setWindowFrame(target, for: window)
        }
    }

    private func setWindowFrame(_ target: WindowFrame, for window: WindowIdentity, strict: Bool = false) throws {
        guard target.x.isFinite, target.y.isFinite, target.width.isFinite, target.height.isFinite,
              target.width > 0, target.height > 0 else { throw WindowServiceError.operation("窗口位置或尺寸无效。") }
        let entry = try requiredEntry(window)
        try rejectFullScreen(entry.element)
        let before = WindowPlacement(frame: try frame(of: entry.element), minimized: try minimizedState(of: entry.element))
        do {
            if before.minimized { try setMinimizedAndSettle(false, element: entry.element) }
            let actual = try applyAndSettle(target, to: entry.element, strict: strict)
            let accepted = strict ? WindowFrameFit.restored(actual, before: target) : WindowFrameFit.accepts(actual, target: target)
            if !accepted { throw WindowFrameConstraintError(requested: target, actual: actual) }
        } catch {
            let originalError = error
            do {
                if try minimizedState(of: entry.element) {
                    try setMinimizedAndSettle(false, element: entry.element)
                }
                let rolledBack = try applyAndSettle(before.frame, to: entry.element, strict: true)
                guard WindowFrameFit.restored(rolledBack, before: before.frame) else {
                    throw WindowServiceError.operation("无法确认原窗口位置已恢复。")
                }
                if try minimizedState(of: entry.element) != before.minimized {
                    try setMinimizedAndSettle(before.minimized, element: entry.element)
                }
            } catch {
                if var constraint = originalError as? WindowFrameConstraintError {
                    constraint.recoveryFailure = error.localizedDescription
                    throw constraint
                }
                throw WindowServiceError.operation("\(originalError.localizedDescription) 原窗口位置未能完整恢复，请手动检查。")
            }
            throw originalError
        }
    }

    /// Preflight only: the controller can exclude these windows before it
    /// divides a display into cells. This never changes focus, size or state.
    func arrangementBlockReason(_ window: WindowIdentity) -> String? {
        do {
            return try withExplicitOperationTimeout(for: window) { () throws -> String? in
                let entry = try requiredEntry(window)
                try rejectFullScreen(entry.element)
                var movable = DarwinBoolean(false)
                try check(AXUIElementIsAttributeSettable(entry.element, kAXPositionAttribute as CFString, &movable),
                          operation: "检查窗口移动能力")
                guard movable.boolValue else {
                    return "这个窗口不允许调整位置，请改选普通窗口。"
                }
                var resizable = DarwinBoolean(false)
                try check(AXUIElementIsAttributeSettable(entry.element, kAXSizeAttribute as CFString, &resizable),
                          operation: "检查窗口缩放能力")
                guard resizable.boolValue else {
                    return "这个窗口不允许调整尺寸；请改选普通可缩放窗口。"
                }
                return nil
            }
        } catch {
            return error.localizedDescription
        }
    }

    func workArea(for window: WindowIdentity?) -> WindowFrame {
        arrangementDisplaySnapshot(for: window).workArea
    }

    func arrangementDisplay(for window: WindowIdentity) -> ArrangementDisplay {
        arrangementDisplaySnapshot(for: window)
    }

    /// Identity comes from the display, not its changing Dock/menu-bar work
    /// area. Both callers share one scoped AX read and one visibleFrame sample.
    private func arrangementDisplaySnapshot(for window: WindowIdentity?) -> ArrangementDisplay {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            return ArrangementDisplay(id: "display:unavailable", workArea: WindowFrame(x: 0, y: 0, width: 1280, height: 800))
        }
        let windowFrame: WindowFrame?
        if let window {
            windowFrame = try? withExplicitOperationTimeout(for: window) {
                let entry = try requiredEntry(window)
                return try frame(of: entry.element)
            }
        } else { windowFrame = nil }
        let selected: NSScreen
        if let windowFrame {
            let rect = cgRect(windowFrame)
            selected = screens.max { a, b in
                intersectionArea(rect, axRect(a.frame, primaryTop: first.frame.maxY)) <
                intersectionArea(rect, axRect(b.frame, primaryTop: first.frame.maxY))
            } ?? first
        } else {
            selected = NSScreen.main ?? first
        }
        let id: String
        if let number = selected.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            id = "display:\(number.uint32Value)"
        } else {
            // A defensive fallback still avoids the dynamic visibleFrame.
            let full = selected.frame
            id = "display-frame:\(full.minX):\(full.minY):\(full.width):\(full.height)"
        }
        let visible = axRect(selected.visibleFrame, primaryTop: first.frame.maxY)
        return ArrangementDisplay(id: id,
            workArea: WindowFrame(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height))
    }

    private func remember(_ element: AXUIElement, application app: NSRunningApplication,
                          refreshPlatformIdentity: Bool = false) -> WindowIdentity? {
        let readTimeout: Float = refreshPlatformIdentity ? 1 : messagingTimeout
        AXUIElementSetMessagingTimeout(element, readTimeout)
        defer { AXUIElementSetMessagingTimeout(element, messagingTimeout) }
        guard (attribute(element, kAXRoleAttribute) as? String) == (kAXWindowRole as String) else {
            traceExplicitReconnection("remember-role-failed")
            return nil
        }
        guard let rawTitle = attribute(element, kAXTitleAttribute) as? String else {
            traceExplicitReconnection("remember-title-unreadable")
            return nil
        }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            traceExplicitReconnection("remember-title-empty")
            return nil
        }
        guard let bounds = try? frame(of: element), bounds.width > 0, bounds.height > 0 else {
            traceExplicitReconnection("remember-frame-failed")
            return nil
        }
        if let previous = entries.values.first(where: {
            $0.identity.processID == app.processIdentifier &&
            $0.identity.processStartedAt == app.launchDate && CFEqual($0.element, element)
        }) {
            var updated = previous
            updated.identity.title = title
            let now = ProcessInfo.processInfo.systemUptime
            if refreshPlatformIdentity || (updated.identity.platformWindowNumber == nil && now - updated.lastPlatformAttempt >= 10) {
                updated.lastPlatformAttempt = now
                let token = platformToken(for: element, application: app, timeout: refreshPlatformIdentity ? 1 : messagingTimeout)
                updated.identity.platformWindowNumber = token?.number
                updated.identity.platformSessionID = token?.session
            }
            entries[updated.identity.id] = updated
            return updated.identity
        }
        let token = platformToken(for: element, application: app, timeout: readTimeout)
        let identity = WindowIdentity(
            id: UUID(), processID: app.processIdentifier, processStartedAt: app.launchDate,
            bundleIdentifier: app.bundleIdentifier, applicationName: app.localizedName ?? "应用", title: title,
            platformWindowNumber: token?.number, platformSessionID: token?.session
        )
        entries[identity.id] = Entry(identity: identity, element: element, lastPlatformAttempt: ProcessInfo.processInfo.systemUptime)
        return identity
    }

    private func platformToken(for element: AXUIElement, application app: NSRunningApplication, timeout: Float? = nil) -> (number: UInt32, session: String)? {
        guard let session = platformSessionID else {
            traceExplicitReconnection("token-session-unavailable")
            return nil
        }
        guard let server = WindowSessionIdentity.serverWindows() else {
            traceExplicitReconnection("token-server-unavailable")
            return nil
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, timeout ?? messagingTimeout)
        guard let listed = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else {
            traceExplicitReconnection("token-window-list-unreadable")
            return nil
        }
        // A successful, empty AXWindows list may still expose exact window
        // objects in the application's immediate children or focused/main
        // attributes. A failed AXWindows read remains unknown and is refused.
        let elements = listed.isEmpty ? supplementalWindows(application, includeChildren: true) : listed
        var candidates: [AccessibilityWindowCandidate] = []
        var targetIndices: [Int] = []
        for (index, candidate) in elements.enumerated() {
            AXUIElementSetMessagingTimeout(candidate, timeout ?? messagingTimeout)
            defer { AXUIElementSetMessagingTimeout(candidate, messagingTimeout) }
            var owner: pid_t = 0
            guard AXUIElementGetPid(candidate, &owner) == .success, owner == app.processIdentifier else {
                traceExplicitReconnection("token-peer-pid-failed")
                return nil
            }
            guard let role = attribute(candidate, kAXRoleAttribute) as? String else {
                traceExplicitReconnection("token-peer-role-unreadable")
                return nil
            }
            guard role == (kAXWindowRole as String) else {
                traceExplicitReconnection("token-peer-role-skipped")
                continue
            }
            // An unreadable peer cannot be ignored when establishing uniqueness.
            guard let bounds = try? frame(of: candidate), bounds.width > 0, bounds.height > 0 else {
                traceExplicitReconnection("token-peer-frame-failed")
                return nil
            }
            candidates.append(AccessibilityWindowCandidate(index: index, processID: app.processIdentifier,
                title: attribute(candidate, kAXTitleAttribute) as? String ?? "", frame: bounds))
            if CFEqual(candidate, element) { targetIndices.append(index) }
        }
        guard targetIndices.count == 1, let index = targetIndices.first else {
            if targetIndices.isEmpty { traceExplicitReconnection("token-target-index-absent") }
            else { traceExplicitReconnection("token-target-index-ambiguous") }
            return nil
        }
        guard let number = WindowReconnectionMatcher.uniqueWindowNumber(for: index, accessibility: candidates, server: server) else {
            traceExplicitReconnection("token-cg-unique-match-failed")
            return nil
        }
        return (number, session)
    }

    private func observedWindows(_ application: AXUIElement) -> [AXUIElement] {
        let listed = attribute(application, kAXWindowsAttribute) as? [AXUIElement]
        var result = listed ?? []
        // Some applications time out on AXWindows while their focused or main
        // window remains accessible. These are explicit AX objects, not title
        // guesses; platform-token matching still requires a successful list
        // read and a unique association among observed AX and all CG windows.
        for window in supplementalWindows(application, includeChildren: listed?.isEmpty == true) {
            if !result.contains(where: { CFEqual($0, window) }) { result.append(window) }
        }
        return result
    }

    /// Reads explicit window relationships and immediate application children,
    /// never element values or descendants. Every admitted object must
    /// explicitly identify itself as an AXWindow owned by this application.
    private func supplementalWindows(_ application: AXUIElement, includeChildren: Bool) -> [AXUIElement] {
        var applicationPID: pid_t = 0
        guard AXUIElementGetPid(application, &applicationPID) == .success, applicationPID > 0 else { return [] }
        var candidates: [AXUIElement] = []
        for name in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard let value = attribute(application, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            candidates.append(unsafeBitCast(value, to: AXUIElement.self))
        }
        if includeChildren, let children = attribute(application, kAXChildrenAttribute) as? [AXUIElement] {
            candidates.append(contentsOf: children)
        }
        if includeChildren && reconnectionReadDeadline != nil {
            candidates.append(contentsOf: reconnectionWindowHints)
        }
        if includeChildren,
           let focusedValue = attribute(application, kAXFocusedUIElementAttribute),
           CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(focused, messagingTimeout)
            var focusedOwner: pid_t = 0
            // AXWindow is a direct metadata relationship. Do not inspect the
            // focused element's value, contents or accessibility descendants.
            if AXUIElementGetPid(focused, &focusedOwner) == .success, focusedOwner == applicationPID,
               let windowValue = attribute(focused, kAXWindowAttribute),
               CFGetTypeID(windowValue) == AXUIElementGetTypeID() {
                candidates.append(unsafeBitCast(windowValue, to: AXUIElement.self))
            }
        }
        var result: [AXUIElement] = []
        for candidate in candidates {
            if let deadline = reconnectionReadDeadline, ProcessInfo.processInfo.systemUptime >= deadline { break }
            AXUIElementSetMessagingTimeout(candidate, messagingTimeout)
            var owner: pid_t = 0
            guard AXUIElementGetPid(candidate, &owner) == .success, owner == applicationPID,
                  (attribute(candidate, kAXRoleAttribute) as? String) == (kAXWindowRole as String) else { continue }
            if !result.contains(where: { CFEqual($0, candidate) }) { result.append(candidate) }
        }
        return result
    }

    private func validEntry(_ window: WindowIdentity) -> Entry? {
        guard let entry = cachedProcessEntry(window) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(entry.element, &pid) == .success, pid == window.processID else { return nil }
        return entry
    }

    private func cachedProcessEntry(_ window: WindowIdentity) -> Entry? {
        guard let entry = entries[window.id], entry.identity.processID == window.processID,
              entry.identity.processStartedAt == window.processStartedAt,
              entry.identity.bundleIdentifier == window.bundleIdentifier,
              window.processStartedAt != nil,
              let app = NSRunningApplication(processIdentifier: window.processID), !app.isTerminated,
              app.launchDate == window.processStartedAt else { return nil }
        return entry
    }

    private func requiredEntry(_ window: WindowIdentity) throws -> Entry {
        guard isTrusted else { throw WindowServiceError.permission }
        guard let entry = entries[window.id], entry.identity.processID == window.processID,
              entry.identity.processStartedAt == window.processStartedAt,
              entry.identity.bundleIdentifier == window.bundleIdentifier,
              window.processStartedAt != nil,
              let app = NSRunningApplication(processIdentifier: window.processID), !app.isTerminated,
              app.launchDate == window.processStartedAt else {
            throw WindowServiceError.disconnected
        }
        var pid: pid_t = 0
        try check(AXUIElementGetPid(entry.element, &pid), operation: "验证目标窗口")
        guard pid == window.processID else { throw WindowServiceError.disconnected }
        var role: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(entry.element, kAXRoleAttribute as CFString, &role), operation: "读取目标窗口")
        guard (role as? String) == (kAXWindowRole as String) else {
            throw WindowServiceError.operation("目标对象不是可管理的窗口。")
        }
        return entry
    }

    /// Explicit user operations get a longer AX response budget, including
    /// requiredEntry's initial role read. Background probes keep their short
    /// timeout; nested restore -> setFrame must not reset the outer budget.
    private func withExplicitOperationTimeout<T>(for window: WindowIdentity, _ body: () throws -> T) throws -> T {
        guard isTrusted else { throw WindowServiceError.permission }
        guard let entry = cachedProcessEntry(window) else { throw WindowServiceError.disconnected }
        let depth = explicitOperationDepth[window.id, default: 0]
        if depth == 0 {
            try check(AXUIElementSetMessagingTimeout(entry.element, 1), operation: "设置窗口操作等待时间")
        }
        explicitOperationDepth[window.id] = depth + 1
        defer {
            if depth == 0 {
                explicitOperationDepth.removeValue(forKey: window.id)
                _ = AXUIElementSetMessagingTimeout(entry.element, messagingTimeout)
            } else {
                explicitOperationDepth[window.id] = depth
            }
        }
        return try body()
    }

    private func rejectFullScreen(_ element: AXUIElement) throws {
        // AX attribute inspection leaves the window's full-screen state alone.
        // A missing attribute is not treated as proof of full screen, and a
        // maximized ordinary window is not rejected based on its geometry.
        if boolAttribute(element, "AXFullScreen") == true {
            throw WindowServiceError.operation("预览版暂不操作全屏窗口，请先手动退出全屏。")
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        if let deadline = reconnectionReadDeadline {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            // The scoped deadline is set only during a synchronous explicit
            // reconnect attempt; no async suspension exposes it to monitoring.
            AXUIElementSetMessagingTimeout(element, Float(min(0.20, remaining)))
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func traceExplicitReconnection(_ stage: StaticString) {
        guard reconnectionReadDeadline != nil else { return }
        activationLogger.debug("stage=\(String(describing: stage), privacy: .public)")
    }

    private func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        guard let value = attribute(element, name), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
    }

    private func minimizedState(of element: AXUIElement) throws -> Bool {
        guard let value = boolAttribute(element, kAXMinimizedAttribute) else {
            throw WindowServiceError.operation("无法确认窗口最小化状态，请检查目标窗口。")
        }
        return value
    }

    private func frame(of element: AXUIElement) throws -> WindowFrame {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw WindowServiceError.operation("无法读取窗口位置或尺寸。")
        }
        let positionAX = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAX = unsafeBitCast(sizeValue, to: AXValue.self)
        guard AXValueGetType(positionAX) == .cgPoint, AXValueGetType(sizeAX) == .cgSize else {
            throw WindowServiceError.operation("目标应用返回了不支持的窗口坐标。")
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position), AXValueGetValue(sizeAX, .cgSize, &size),
              position.x.isFinite, position.y.isFinite, size.width.isFinite, size.height.isFinite else {
            throw WindowServiceError.operation("无法读取有效的窗口坐标。")
        }
        return WindowFrame(x: position.x, y: position.y, width: size.width, height: size.height)
    }

    private func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var result: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
    }

    private func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) throws {
        try check(AXUIElementSetAttributeValue(element, name as CFString, value), operation: "更新窗口状态")
    }

    private func activationRequest(_ result: AXError, operation: String) throws {
        // cannotComplete can mean the recipient is inside its system animation
        // and has not replied yet. Only confirmActivation can establish success.
        guard result != .cannotComplete else { return }
        try check(result, operation: operation)
    }

    private func requestForeground(_ app: NSRunningApplication, application: AXUIElement) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier else { return }
        // AppKit documents activation as a request, not its result. A false
        // request return is not proof that foreground activation has failed.
        if #available(macOS 14.0, *), NSApp.isActive {
            NSApp.yieldActivation(to: app)
            _ = app.activate(from: NSRunningApplication.current, options: [])
        } else {
            _ = app.activate(options: [])
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier,
           isSettable(application, kAXFrontmostAttribute) {
            try activationRequest(AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue), operation: "激活目标应用")
        }
    }

    private func applyAndSettle(_ rect: WindowFrame, to element: AXUIElement, strict: Bool) throws -> WindowFrame {
        var owner: pid_t = 0
        try check(AXUIElementGetPid(element, &owner), operation: "验证目标窗口")
        guard owner > 0 else { throw WindowServiceError.disconnected }
        let application = AXUIElementCreateApplication(owner)
        AXUIElementSetMessagingTimeout(application, 1)
        let enhancedAttribute = "AXEnhancedUserInterface"
        return try WindowEnhancedUIAdjustment.perform(
            read: { self.boolAttribute(application, enhancedAttribute) },
            isSettable: { self.isSettable(application, enhancedAttribute) },
            write: { enabled in
                try self.set(application, enhancedAttribute, enabled ? kCFBooleanTrue : kCFBooleanFalse)
                guard self.boolAttribute(application, enhancedAttribute) == enabled else {
                    throw WindowServiceError.operation("目标应用未确认窗口辅助功能状态，请稍后重试。")
                }
                if enabled { self.activationLogger.debug("stage=enhanced-ui-restored") }
                else { self.activationLogger.debug("stage=enhanced-ui-suspended") }
            },
            adjustment: { try self.applyAndSettleGeometry(rect, to: element, strict: strict) },
            verifyRestored: { _ in
                // Re-enabling an existing accessibility mode can itself make
                // an app change geometry. Confirm again after restoring it,
                // without sending any more position/size writes in that mode.
                try self.check(AXUIElementSetMessagingTimeout(element, 0.10), operation: "设置窗口确认等待时间")
                defer { _ = AXUIElementSetMessagingTimeout(element, 1) }
                let actual = try WindowFrameSettlement.settledFrame(target: rect, strict: strict,
                    read: { try self.frame(of: element) }, retryPosition: {})
                let accepted = strict ? WindowFrameFit.restored(actual, before: rect) : WindowFrameFit.accepts(actual, target: rect)
                guard accepted else { throw WindowFrameConstraintError(requested: rect, actual: actual) }
                return actual
            })
    }

    private func applyAndSettleGeometry(_ rect: WindowFrame, to element: AXUIElement, strict: Bool) throws -> WindowFrame {
        let current = try frame(of: element)
        let move = abs(current.x - rect.x) > 0.5 || abs(current.y - rect.y) > 0.5
        let resize = abs(current.width - rect.width) > 0.5 || abs(current.height - rect.height) > 0.5
        guard move || resize else { return current }
        if move && !isSettable(element, kAXPositionAttribute) {
            throw WindowServiceError.operation("这个窗口不允许调整位置，请改选普通窗口。")
        }
        if resize && !isSettable(element, kAXSizeAttribute) {
            throw WindowServiceError.operation("这个窗口不允许调整尺寸；请改选普通可缩放窗口。")
        }
        var point = CGPoint(x: rect.x, y: rect.y)
        var size = CGSize(width: rect.width, height: rect.height)
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else {
            throw WindowServiceError.operation("无法创建窗口坐标。")
        }
        func settle(normalize: (WindowFrame) -> WindowFrame, retry: () throws -> Void) throws -> WindowFrame {
            try check(AXUIElementSetMessagingTimeout(element, 0.10), operation: "设置窗口确认等待时间")
            defer { _ = AXUIElementSetMessagingTimeout(element, 1) }
            return try WindowFrameSettlement.settledFrame(target: rect, strict: strict,
                read: { (try? self.frame(of: element)).map(normalize) }, retryPosition: retry)
        }
        func moveToTarget() throws {
            guard isSettable(element, kAXPositionAttribute) else {
                throw WindowServiceError.operation("这个窗口不允许调整位置。")
            }
            try set(element, kAXPositionAttribute, position)
        }
        func dimensionsOnly(_ actual: WindowFrame) -> WindowFrame {
            WindowFrame(x: rect.x, y: rect.y, width: actual.width, height: actual.height)
        }

        // Qt can acknowledge AX writes before applying them. Interleaving a
        // size and position request then lets each handler overwrite the other
        // with its previous frame. Confirm one attribute before sending the next.
        if resize {
            try set(element, kAXSizeAttribute, dimensions)
            _ = try settle(normalize: dimensionsOnly, retry: {})
        }
        if isSettable(element, kAXPositionAttribute) {
            try moveToTarget()
            _ = try settle(normalize: { actual in
                WindowFrame(x: actual.x, y: actual.y, width: rect.width, height: rect.height)
            }, retry: moveToTarget)
        }
        var afterMove = try frame(of: element)
        var lastSizeRequest = rect
        // A target on another display can require moving before its final size
        // becomes legal. This request follows confirmed placement, never races it.
        for attempt in 0..<3 {
            let sizeFits = strict ? WindowFrameFit.restored(dimensionsOnly(afterMove), before: rect)
                                  : WindowFrameFit.accepts(dimensionsOnly(afterMove), target: rect)
            if sizeFits { break }
            guard isSettable(element, kAXSizeAttribute) else {
                throw WindowServiceError.operation("这个窗口不允许调整尺寸。")
            }
            // Some accessibility implementations treat AXSize as their content
            // rectangle but report the outer frame. Correct only a small,
            // observed discrepancy; success still requires the actual frame to
            // fit the original target, including strict rollback geometry.
            let correction = WindowFrameFit.correctedSizeRequest(target: rect, actual: afterMove, lastRequested: lastSizeRequest)
            // A large first discrepancy may be a screen-edge clamp from the
            // old position. Retry the original size once after moving; later
            // feedback is permitted only for a small observed discrepancy.
            guard correction != nil || attempt == 0 else { break }
            let request = correction ?? rect
            lastSizeRequest = request
            var adjustedSize = CGSize(width: request.width, height: request.height)
            guard let adjustedDimensions = AXValueCreate(.cgSize, &adjustedSize) else {
                throw WindowServiceError.operation("无法创建窗口尺寸。")
            }
            try set(element, kAXSizeAttribute, adjustedDimensions)
            _ = try settle(normalize: dimensionsOnly, retry: {})
            if isSettable(element, kAXPositionAttribute) {
                try moveToTarget()
                _ = try settle(normalize: { actual in
                    WindowFrame(x: actual.x, y: actual.y, width: rect.width, height: rect.height)
                }, retry: moveToTarget)
            }
            afterMove = try frame(of: element)
        }
        let final = try settle(normalize: { $0 }, retry: moveToTarget)
        return final
    }

    private func setMinimizedAndSettle(_ target: Bool, element: AXUIElement) throws {
        try set(element, kAXMinimizedAttribute, target ? kCFBooleanTrue : kCFBooleanFalse)
        try check(AXUIElementSetMessagingTimeout(element, 0.10), operation: "设置窗口确认等待时间")
        defer { _ = AXUIElementSetMessagingTimeout(element, 1) }
        guard try WindowFrameSettlement.settledMinimized(target: target,
            read: { self.boolAttribute(element, kAXMinimizedAttribute) }) else {
            throw WindowServiceError.operation("窗口最小化状态尚未确认，请稍后重试。")
        }
    }

    private func sameGeometry(_ first: WindowFrame, _ second: WindowFrame) -> Bool {
        abs(first.x - second.x) <= 0.5 && abs(first.y - second.y) <= 0.5 &&
        abs(first.width - second.width) <= 0.5 && abs(first.height - second.height) <= 0.5
    }

    private func check(_ result: AXError, operation: String) throws {
        guard result == .success else {
            switch result {
            case .apiDisabled: throw WindowServiceError.permission
            case .invalidUIElement: throw WindowServiceError.disconnected
            case .cannotComplete: throw WindowServiceError.operation("\(operation)超时或目标应用未响应，请稍后重试。")
            case .attributeUnsupported, .actionUnsupported, .notImplemented:
                throw WindowServiceError.operation("目标应用不支持此窗口操作（\(operation)）。")
            default: throw WindowServiceError.operation("\(operation)失败（系统错误 \(result.rawValue)）。")
            }
        }
    }

    private func axRect(_ rect: NSRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    private func cgRect(_ frame: WindowFrame) -> CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

/// A temporary change applies only to a mode that was already enabled. Always
/// restore that state, including for active assistive technology and failures.
/// Geometry confirmation runs after restoration, never while the mode is off.
enum WindowEnhancedUIAdjustment {
    static func perform<Value>(read: () -> Bool?, isSettable: () -> Bool,
                               write: (Bool) throws -> Void,
                               adjustment: () throws -> Value,
                               verifyRestored: (Value) throws -> Value) throws -> Value {
        guard read() == true, isSettable() else { return try adjustment() }
        var restorationError: Error?
        let outcome: Result<Value, Error> = {
            defer {
                do { try write(true) }
                catch { restorationError = error }
            }
            return Result {
                try write(false)
                return try adjustment()
            }
        }()
        if let restorationError {
            let adjustmentError: Error?
            switch outcome {
            case .success: adjustmentError = nil
            case .failure(let error): adjustmentError = error
            }
            throw RestorationFailure(adjustmentError: adjustmentError, restorationError: restorationError)
        }
        return try verifyRestored(outcome.get())
    }

    struct RestorationFailure: LocalizedError {
        let adjustmentError: Error?
        let restorationError: Error

        var errorDescription: String? {
            let errors: [Error?] = [adjustmentError, restorationError]
            return errors.compactMap { $0?.localizedDescription }.joined(separator: "\n")
        }
    }
}

enum WindowServiceError: LocalizedError {
    case permission
    case disconnected
    case operation(String)

    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .permission: return "请先在系统设置中允许 OmniVibe 使用辅助功能，然后重新检查权限。"
            case .disconnected: return "窗口已关闭或属于上一次运行，请重新绑定具体窗口。"
            case .operation(let message): return message
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
