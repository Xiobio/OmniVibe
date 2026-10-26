import AppKit
import Combine
import CoreGraphics
import CoreVideo
import ScreenCaptureKit
import OmniVibeCore

/// A fresh, live AX description supplied by WindowService. Persisted window
/// titles alone are never enough to choose content for a preview.
struct WindowPreviewDescriptor: Equatable, Sendable {
    let window: WindowIdentity
    let frame: WindowFrame
    let title: String

    init(window: WindowIdentity, frame: WindowFrame, title: String) {
        self.window = window
        self.frame = frame
        self.title = title
    }
}

/// Plain metadata keeps matching independently testable without screen access.
struct WindowPreviewCandidate: Equatable, Sendable {
    let windowID: UInt32
    let processID: Int32
    let bundleIdentifier: String?
    let title: String?
    let frame: WindowFrame
}

enum WindowPreviewMatcher {
    static func uniqueWindowID(for descriptor: WindowPreviewDescriptor,
                               candidates: [WindowPreviewCandidate], tolerance: Double = 2) -> UInt32? {
        guard descriptor.window.processID > 0, descriptor.window.processStartedAt != nil,
              valid(descriptor.frame), tolerance.isFinite, tolerance >= 0 else { return nil }
        let title = descriptor.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let matches = candidates.filter { candidate in
            guard candidate.windowID != 0, candidate.processID == descriptor.window.processID,
                  valid(candidate.frame),
                  candidate.title?.trimmingCharacters(in: .whitespacesAndNewlines) == title else { return false }
            if let expectedBundle = descriptor.window.bundleIdentifier,
               candidate.bundleIdentifier != expectedBundle { return false }
            return abs(candidate.frame.x - descriptor.frame.x) <= tolerance &&
                abs(candidate.frame.y - descriptor.frame.y) <= tolerance &&
                abs(candidate.frame.width - descriptor.frame.width) <= tolerance &&
                abs(candidate.frame.height - descriptor.frame.height) <= tolerance
        }
        let identifiers = Set(matches.map(\.windowID))
        // Two same-title windows stacked at the same bounds remain ambiguous.
        // Showing no image is preferable to showing a different task's content.
        return identifiers.count == 1 ? identifiers.first : nil
    }

    private static func valid(_ frame: WindowFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite && frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
    }
}

/// Opt-in, in-memory snapshots of individually bound windows. Nothing is
/// captured before a deliberate opt-in, and no display or audio stream is
/// created. Image ownership ends when the inventory is no longer visible.
@MainActor
final class WindowPreviewService: ObservableObject {
    @Published private(set) var images: [UUID: NSImage] = [:]
    @Published private(set) var messages: [UUID: String] = [:]
    @Published private(set) var permissionGranted = false
    @Published private(set) var enabled = false
    @Published private(set) var errorMessage: String?

    var supported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    private var visible = false
    private var applicationActive = false
    private var descriptors: (@MainActor () -> [WindowPreviewDescriptor])?
    private var refreshTask: Task<Void, Never>?
    private var generation = UUID()
    private var captureBusy = false
    private var pixelCosts: [UUID: Int] = [:]
    private var activityObservers: [NSObjectProtocol] = []
    private let maximumPixelBytes = 50 * 1024 * 1024

    init() {
        // Preflight only reads the current grant. It never displays a prompt.
        permissionGranted = CGPreflightScreenCaptureAccess()
        applicationActive = NSApplication.shared.isActive
        activityObservers = [
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.applicationActive = true
                    self?.beginRefreshingIfAllowed()
                }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.applicationActive = false
                    self?.invalidateRefresh()
                    self?.clearImages()
                }
            }
        ]
    }

    /// Call from inventory onAppear. This stores its metadata provider but does
    /// not enable capture or request a permission on its own.
    func start(descriptors: @escaping @MainActor () -> [WindowPreviewDescriptor]) {
        self.descriptors = descriptors
        visible = true
        beginRefreshingIfAllowed()
    }

    /// Only a deliberate user control should call this method. The OS owns the
    /// permission decision; a denied grant leaves all task operations available.
    func requestAccess() {
        guard supported else {
            errorMessage = "窗口预览需要 macOS 14 或以上；窗口收纳与切换仍可使用。"
            return
        }
        permissionGranted = CGPreflightScreenCaptureAccess()
        if !permissionGranted { permissionGranted = CGRequestScreenCaptureAccess() }
        enabled = permissionGranted
        if permissionGranted {
            errorMessage = nil
            invalidateRefresh()
            beginRefreshingIfAllowed()
        } else {
            errorMessage = "尚未获得屏幕录制权限。可在系统设置中为 OmniVibe 开启，再返回重试。"
            clearImages()
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func disable() {
        enabled = false
        invalidateRefresh()
        clearImages()
        errorMessage = nil
    }

    /// Call from inventory onDisappear or its containing NSWindow close path.
    /// The user's in-session opt-in is retained; all image buffers are released.
    func stop() {
        visible = false
        descriptors = nil
        invalidateRefresh()
        clearImages()
    }

    func placeholder(for window: WindowIdentity) -> String {
        if !supported { return "窗口预览需要 macOS 14 或以上" }
        if !enabled { return permissionGranted ? "窗口预览未开启" : "开启窗口预览需屏幕录制权限" }
        return messages[window.id] ?? "正在获取指定窗口预览…"
    }

    private func beginRefreshingIfAllowed() {
        guard visible, applicationActive, enabled, supported, refreshTask == nil else { return }
        permissionGranted = CGPreflightScreenCaptureAccess()
        guard permissionGranted else {
            enabled = false
            errorMessage = "窗口预览权限已关闭，任务切换仍可使用。"
            clearImages()
            return
        }
        let ticket = generation
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.visible, self.enabled, self.generation == ticket else { return }
                if #available(macOS 14.0, *) { await self.refresh(ticket: ticket) }
                do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                catch { return }
            }
        }
    }

    private func invalidateRefresh() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func clearImages() {
        images = [:]
        pixelCosts = [:]
        messages = [:]
    }

    private func active(_ ticket: UUID) -> Bool {
        !Task.isCancelled && visible && applicationActive && enabled && generation == ticket
    }

    private func processMatches(_ descriptor: WindowPreviewDescriptor) -> Bool {
        guard let launched = descriptor.window.processStartedAt,
              let app = NSRunningApplication(processIdentifier: descriptor.window.processID),
              !app.isTerminated, app.launchDate == launched else { return false }
        if let bundle = descriptor.window.bundleIdentifier, app.bundleIdentifier != bundle { return false }
        return true
    }

    @available(macOS 14.0, *)
    private func refresh(ticket: UUID) async {
        // A cancelled SCScreenshotManager operation can finish later. Keep one
        // in-flight refresh across stop/start cycles so those cannot queue an
        // unbounded number of native screenshot operations.
        guard active(ticket), !captureBusy, let descriptors else { return }
        captureBusy = true
        defer { captureBusy = false }
        guard CGPreflightScreenCaptureAccess() else {
            permissionGranted = false
            enabled = false
            errorMessage = "窗口预览权限已关闭，任务切换仍可使用。"
            clearImages()
            return
        }
        var seen = Set<UUID>()
        let targets = Array(descriptors().filter { seen.insert($0.window.id).inserted }.prefix(9))
        let activeIDs = Set(targets.map { $0.window.id })
        images = images.filter { activeIDs.contains($0.key) }
        pixelCosts = pixelCosts.filter { activeIDs.contains($0.key) }
        messages = messages.filter { activeIDs.contains($0.key) }
        guard !targets.isEmpty else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard active(ticket) else { return }
            let candidates = content.windows.compactMap { window -> WindowPreviewCandidate? in
                guard let owner = window.owningApplication else { return nil }
                return WindowPreviewCandidate(windowID: window.windowID, processID: owner.processID,
                    bundleIdentifier: owner.bundleIdentifier.isEmpty ? nil : owner.bundleIdentifier,
                    title: window.title,
                    frame: WindowFrame(x: window.frame.minX, y: window.frame.minY,
                                       width: window.frame.width, height: window.frame.height))
            }
            var pending: [UUID: CGImage] = [:]
            var pendingCosts: [UUID: Int] = [:]
            for target in targets {
                guard active(ticket) else { return }
                guard processMatches(target),
                      let windowID = WindowPreviewMatcher.uniqueWindowID(for: target, candidates: candidates),
                      let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    removeImage(target.window.id, message: "无法唯一确认对应窗口，暂不显示预览")
                    continue
                }
                let configuration = SCStreamConfiguration()
                let scale = min(1, 512 / target.frame.width, 320 / target.frame.height)
                configuration.width = max(1, Int((target.frame.width * scale).rounded(.down)))
                configuration.height = max(1, Int((target.frame.height * scale).rounded(.down)))
                configuration.scalesToFit = true
                configuration.preservesAspectRatio = true
                configuration.showsCursor = false
                configuration.capturesAudio = false
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.ignoreShadowsSingleWindow = true
                if #available(macOS 14.2, *) { configuration.includeChildWindows = false }
                if #available(macOS 15.0, *) { configuration.captureMicrophone = false }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                do {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    guard active(ticket) else { return }
                    let cost = image.bytesPerRow * image.height
                    let retainedBytes = pixelCosts.values.reduce(0, +) + pendingCosts.values.reduce(0, +)
                    guard image.width <= 512, image.height <= 320,
                          cost > 0, cost <= maximumPixelBytes, retainedBytes <= maximumPixelBytes - cost else {
                        removeImage(target.window.id, message: "预览图像超过内存预算")
                        continue
                    }
                    pending[target.window.id] = image
                    pendingCosts[target.window.id] = cost
                } catch {
                    guard active(ticket) else { return }
                    removeImage(target.window.id, message: "暂时无法读取窗口预览，点击仍可进入任务")
                }
            }
            guard active(ticket) else { return }
            // Fetch the live AX descriptions once for this batch, rather than
            // re-reading all nine windows once per image. A rebind, title
            // change, or movement while capture was pending discards that image.
            let fresh = self.descriptors?() ?? []
            for target in targets {
                guard let image = pending[target.window.id], let cost = pendingCosts[target.window.id] else { continue }
                guard processMatches(target), fresh.first(where: { $0.window.id == target.window.id }) == target else {
                    removeImage(target.window.id, message: "窗口已变化，等待下次预览")
                    continue
                }
                images[target.window.id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                pixelCosts[target.window.id] = cost
                messages[target.window.id] = nil
            }
        } catch {
            guard active(ticket) else { return }
            images = [:]
            pixelCosts = [:]
            for target in targets { messages[target.window.id] = "暂时无法列出可预览窗口" }
        }
    }

    private func removeImage(_ identity: UUID, message: String) {
        images[identity] = nil
        pixelCosts[identity] = nil
        messages[identity] = message
    }

    deinit {
        refreshTask?.cancel()
        for observer in activityObservers { NotificationCenter.default.removeObserver(observer) }
    }
}
