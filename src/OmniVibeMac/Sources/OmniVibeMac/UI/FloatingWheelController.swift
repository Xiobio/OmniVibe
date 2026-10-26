import AppKit
import Combine
import OmniVibeCore

/// The core owns one screen anchor. The equipment orbit can fit inward at an
/// edge without relocating or resizing the core under the pointer.
@MainActor
final class FloatingWheelController: NSObject {
    private let controller: ApplicationController
    private let appearance: AppearanceModel
    private let onShowInventory: () -> Void
    private let onShowSettings: () -> Void
    private let onQuit: () -> Void
    private let panel: WheelPanel
    private let wheelView: NativeWheelView
    private var hotkeys: WheelHotKeyService?
    private var pointerEscape: PointerEscapeHotKeyService?
    private var scrollSwitch: TaskScrollSwitchService?
    private var scrollWarnings: [String] = []
    private var wheelRegistrationWarnings: [String] = []
    private var hotkeysSuspended = false
    private var servicesStopped = false
    private struct ScrollConfiguration: Equatable {
        let enabled: Bool
        let modifiers: UInt32
        let suspended: Bool
    }
    private var lastScrollConfiguration: ScrollConfiguration?
    private var pointerTimer: Timer?
    private var localEscapeMonitor: Any?
    private var collapseWork: Task<Void, Never>?
    private var anchor: NSPoint
    private var layout: WheelDragGeometry.Layout?
    private var expanded = false
    private var dragging = false
    private var corePressed = false
    private var slotManipulating = false
    private var coreDragStart: (pointer: NSPoint, anchor: NSPoint)?
    private var menuOpen = false
    private var suppressHoverUntilLeave = false
    private var pinnedExpansion = false
    private var subscriptions = Set<AnyCancellable>()
    private var aimReturn: (anchor: NSPoint, expanded: Bool, visible: Bool)?
    private struct ExternalDrag {
        let window: WindowIdentity
        let original: WindowFrame
        var moved = false
    }
    private var externalDrag: ExternalDrag?
    private var cachedExternalDrag: ExternalDrag?
    private var externalPressPoint: NSPoint?
    private var lastCandidateRefresh = -TimeInterval.infinity
    private var lastDragInspection = -TimeInterval.infinity
    private var wasLeftDown = false
    private(set) var isAiming = false
    private let anchorKey = "OmniVibe.FloatingAnchor.v1"

    var isVisible: Bool { panel.isVisible }
    private var displayedAnchor: NSPoint { layout?.coreScreenCenter ?? anchor }

    init(controller: ApplicationController, appearance: AppearanceModel,
         onShowInventory: @escaping () -> Void, onShowSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.controller = controller
        self.appearance = appearance
        self.onShowInventory = onShowInventory
        self.onShowSettings = onShowSettings
        self.onQuit = onQuit
        let screen = NSScreen.main ?? NSScreen.screens.first
        let work = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        if !controller.isDemo,
           let saved = UserDefaults.standard.dictionary(forKey: "OmniVibe.FloatingAnchor.v1"),
           let x = saved["x"] as? Double, let y = saved["y"] as? Double, x.isFinite, y.isFinite {
            anchor = NSPoint(x: x, y: y)
        } else { anchor = NSPoint(x: work.maxX - 190, y: work.midY) }
        panel = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: 54, height: 54),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        wheelView = NativeWheelView(controller: controller, appearance: appearance)
        super.init()
        anchor = clamped(anchor)
        panel.title = L10n.text("OmniVibe · 悬浮装备轮盘")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true
        wheelView.frame = NSRect(x: 0, y: 0, width: 54, height: 54)
        wheelView.autoresizingMask = [.width, .height]
        panel.contentView = wheelView
        connectWheel()
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if self.wheelView.isSlotManipulating {
                    self.wheelView.cancelSlotInteraction()
                    return true
                }
                guard self.isAiming else { return false }
                self.endAim(confirm: false)
                return true
            }
            return consumed ? nil : event
        }
        appearance.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.wheelView.needsDisplay = true }
        }.store(in: &subscriptions)
        controller.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.synchronizeShortcutServices() }
        }.store(in: &subscriptions)
        controller.$windowBehavior.sink { [weak self] preferences in
            guard let self else { return }
            if preferences.shortcutsPaused { self.suspendHotkeys() }
            else if !preferences.wheelSwitchEnabled || self.lastScrollConfiguration?.modifiers != preferences.wheelModifiers {
                self.scrollSwitch?.stop(); self.lastScrollConfiguration = nil
            }
        }.store(in: &subscriptions)
        controller.$isRecordingShortcut.sink { [weak self] recording in
            if recording { self?.suspendHotkeys() }
        }.store(in: &subscriptions)
        startPointerTimer()
        resumeHotkeys()
    }

    private func connectWheel() {
        wheelView.onHoverChanged = { [weak self] inside in self?.hoverChanged(inside) }
        wheelView.onCoreClick = { [weak self] in
            guard let self else { return }
            self.pinnedExpansion = false
            self.setExpanded(false)
            self.onShowInventory()
        }
        wheelView.onCorePressChanged = { [weak self] pressed in
            guard let self else { return }
            self.corePressed = pressed
            self.updateInteractionState()
        }
        wheelView.onCoreDragBegan = { [weak self] point in self?.beginCoreDrag(at: point) }
        wheelView.onCoreDragMoved = { [weak self] point in self?.moveCore(to: point) }
        wheelView.onCoreDragEnded = { [weak self] in self?.endCoreDrag() }
        wheelView.onSlotClick = { [weak self] number in self?.selectSlot(number) }
        wheelView.onSlotInteractionChanged = { [weak self] active in
            guard let self else { return }
            self.slotManipulating = active
            self.externalDrag = nil; self.externalPressPoint = nil
            self.wasLeftDown = NSEvent.pressedMouseButtons & 1 != 0
            self.collapseWork?.cancel(); self.collapseWork = nil
            self.updateInteractionState()
            if active {
                self.setExpanded(true)
                self.beginPointerEscapeCapture()
            } else {
                self.endPointerEscapeCapture()
                self.scheduleCollapse()
            }
        }
        wheelView.onSlotReorder = { [weak self] from, to, taskID in
            self?.controller.reorderSlot(from: from, to: to, expectedTaskID: taskID) ?? false
        }
        wheelView.onSlotRemove = { [weak self] number, taskID in
            _ = self?.controller.remove(number, expectedTaskID: taskID)
        }
        wheelView.onContextMenu = { [weak self] event in self?.showContextMenu(with: event) }
    }

    func show(expanded: Bool = false, keepExpanded: Bool = false) {
        pinnedExpansion = keepExpanded
        anchor = clamped(anchor)
        setExpanded(expanded)
        panel.orderFrontRegardless()
    }

    func hide() {
        wheelView.cancelSlotInteraction()
        endPointerEscapeCapture()
        if isAiming { endAim(confirm: false) }
        endCoreDrag()
        corePressed = false
        externalDrag = nil; externalPressPoint = nil
        updateInteractionState()
        collapseWork?.cancel()
        pinnedExpansion = false
        panel.orderOut(nil)
    }

    func toggleVisibility() { if panel.isVisible { hide() } else { show() } }

    func refreshPreferences() {
        panel.title = L10n.text("OmniVibe · 悬浮装备轮盘")
        synchronizeShortcutServices()
        guard !dragging, !slotManipulating, !isAiming else { return }
        anchor = clamped(anchor)
        setExpanded(expanded)
    }

    private func setExpanded(_ value: Bool) {
        guard value || !slotManipulating else { return }
        let changed = expanded != value
        collapseWork?.cancel()
        collapseWork = nil
        expanded = value
        let area = screen(containing: anchor)?.visibleFrame
            ?? NSRect(x: anchor.x - 1000, y: anchor.y - 1000, width: 2000, height: 2000)
        let next = WheelDragGeometry.layout(anchor: anchor, configured: controller.windowBehavior.launcherExtent,
                                            expanded: value, workArea: area)
        layout = next
        // Animating the host frame would translate the core during the resize.
        // Only NativeWheelView's equipment deployment has an animation.
        if panel.frame != next.frame { panel.setFrame(next.frame, display: true, animate: false) }
        wheelView.frame = NSRect(origin: .zero, size: next.frame.size)
        wheelView.bounds = NSRect(origin: .zero, size: next.logicalSize)
        wheelView.wheelLayout = next
        wheelView.needsDisplay = true
        if wheelView.expanded != value { wheelView.expanded = value }
        if changed { controller.playFeedback(value ? .expand : .collapse) }
    }

    private func hoverChanged(_ inside: Bool) {
        guard panel.isVisible, !dragging, !slotManipulating, !isAiming else { return }
        if inside {
            collapseWork?.cancel()
            if !suppressHoverUntilLeave { setExpanded(true) }
        } else { scheduleCollapse() }
    }

    private func scheduleCollapse() {
        guard !isAiming, !dragging, !slotManipulating, !menuOpen, !pinnedExpansion else { return }
        collapseWork?.cancel()
        let work = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 220_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            guard let self, !self.isAiming, !self.dragging, !self.slotManipulating, !self.menuOpen,
                  !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.setExpanded(false)
        }
        collapseWork = work
    }

    private func startPointerTimer() {
        pointerTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        pointerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkPointer() {
        guard panel.isVisible, !dragging, !slotManipulating else { return }
        let point = NSEvent.mouseLocation
        trackExternalWindowDrag(at: point)
        if isAiming { _ = wheelView.aim(at: point); return }
        if suppressHoverUntilLeave {
            if !WheelDragGeometry.coreContains(point, layout: layout, margin: 8) { suppressHoverUntilLeave = false }
            return
        }
        // AppKit may not emit mouseEntered if a transparent panel appears
        // beneath a stationary pointer. Keep hover behavior based on geometry.
        if !expanded && panel.frame.contains(point) && !menuOpen {
            setExpanded(true)
        }
        // Geometry, not alpha hit-testing, decides retraction. Passing through
        // a transparent gap between two pieces of equipment keeps it open.
        if expanded && !panel.frame.contains(point) && !menuOpen && collapseWork == nil { scheduleCollapse() }
        if panel.frame.contains(point) { collapseWork?.cancel(); collapseWork = nil }
    }

    private func beginCoreDrag(at point: NSPoint) {
        guard !isAiming, !slotManipulating else { return }
        collapseWork?.cancel()
        collapseWork = nil
        externalDrag = nil
        externalPressPoint = nil
        dragging = true
        // The panel's centre can differ from the fixed core at a screen edge.
        anchor = clamped(displayedAnchor)
        coreDragStart = (point, anchor)
        updateInteractionState()
        pinnedExpansion = false
        suppressHoverUntilLeave = true
        setExpanded(false)
    }

    private func moveCore(to point: NSPoint) {
        guard let start = coreDragStart else { return }
        anchor = clamped(WheelDragGeometry.translatedAnchor(from: start.anchor, pressPoint: start.pointer, to: point))
        setExpanded(false)
    }

    private func endCoreDrag() {
        guard coreDragStart != nil else { return }
        coreDragStart = nil
        dragging = false
        updateInteractionState()
        wasLeftDown = false
        suppressHoverUntilLeave = true
        setExpanded(false)
        if !controller.isDemo {
            UserDefaults.standard.set(["x": anchor.x, "y": anchor.y], forKey: anchorKey)
        }
    }

    private func clamped(_ point: NSPoint) -> NSPoint {
        guard let area = screen(containing: point)?.visibleFrame else { return point }
        let extent = WheelDragGeometry.physicalExtent(configured: controller.windowBehavior.launcherExtent, expanded: false)
        let frame = WheelDragGeometry.panelFrame(anchor: point, extent: min(extent, area.width, area.height), workArea: area)
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? screens.first
    }

    /// Poll button state at 30 Hz, but query AX only for a low-frequency focused
    /// candidate or the active drag. No all-application enumeration is needed.
    /// A text selection or drag within an app never moves its NSWindow frame and
    /// therefore cannot become a captured task. No global mouse/key tap is used.
    private func trackExternalWindowDrag(at point: NSPoint) {
        let leftDown = NSEvent.pressedMouseButtons & 1 != 0
        let now = ProcessInfo.processInfo.systemUptime
        defer { wasLeftDown = leftDown }
        guard !controller.isDemo, !isAiming, !dragging, !slotManipulating, !menuOpen else {
            externalDrag = nil; externalPressPoint = nil
            updateInteractionState()
            return
        }
        if !leftDown, !wasLeftDown, controller.canControlWindows,
           !panel.frame.contains(point), now - lastCandidateRefresh >= 1 {
            let candidate = externalCandidate()
            // AX can take time. A sample that finished after the button went
            // down must not overwrite the known pre-press origin.
            if NSEvent.pressedMouseButtons & 1 == 0 {
                cachedExternalDrag = candidate
                lastCandidateRefresh = ProcessInfo.processInfo.systemUptime
            }
        }
        if leftDown {
            if !wasLeftDown {
                externalDrag = nil
                externalPressPoint = panel.frame.contains(point) ? nil : point
                lastDragInspection = now
                guard externalPressPoint != nil, controller.canControlWindows else { return }
                let fresh = externalCandidate()
                let cached = now - lastCandidateRefresh <= 1.5 ? cachedExternalDrag : nil
                let original = WheelDragGeometry.initialDragOrigin(pressPoint: point, samplePoint: NSEvent.mouseLocation,
                    cached: cached.map { .init(windowID: $0.window.id, frame: $0.original) },
                    fresh: fresh.map { .init(windowID: $0.window.id, frame: $0.original) },
                    primaryTop: NSScreen.screens.first?.frame.maxY ?? 0)
                if let original,
                   let window = [fresh?.window, cached?.window].compactMap({ $0 }).first(where: { $0.id == original.windowID }) {
                    externalDrag = ExternalDrag(window: window, original: original.frame)
                }
            } else if externalPressPoint != nil, controller.canControlWindows,
                      now - lastDragInspection >= 0.1 {
                lastDragInspection = now
                if var drag = externalDrag, !drag.moved,
                   let placement = try? controller.windows.captureTrackingPlacement(drag.window) {
                    drag.moved = WheelDragGeometry.windowMoved(from: drag.original, to: placement.frame)
                    externalDrag = drag
                }
                // The initial origin is immutable. A later focused-window
                // sample may already be beside the launcher and is not a
                // restoration target for this drag.
            }
            if externalDrag?.moved == true, panel.frame.contains(point) {
                pinnedExpansion = false
                setExpanded(true)
                _ = wheelView.aim(at: point)
            }
            updateInteractionState()
        } else if wasLeftDown {
            defer {
                externalDrag = nil; externalPressPoint = nil
                cachedExternalDrag = nil; lastCandidateRefresh = -.infinity
                wheelView.clearAim()
                updateInteractionState()
            }
            guard let pressed = externalPressPoint, panel.frame.contains(point),
                  hypot(point.x - pressed.x, point.y - pressed.y) > 5 else { return }
            guard controller.canControlWindows else {
                controller.requireAccessibilityPermission(reason: "拖入窗口需要辅助功能权限。请授权后重新拖动窗口标题栏。")
                return
            }
            guard var drag = externalDrag else {
                controller.notice = "未能确认拖入前的位置，请重试，或点击空槽选择窗口。"
                return
            }
            if !drag.moved, let placement = try? controller.windows.captureTrackingPlacement(drag.window) {
                drag.moved = WheelDragGeometry.windowMoved(from: drag.original, to: placement.frame)
            }
            guard drag.moved else {
                controller.notice = "未检测到窗口位置变化。请拖动窗口标题栏，或点击空槽选择窗口。"
                return
            }
            let inCore = WheelDragGeometry.coreContains(point, layout: layout)
            if !inCore { _ = wheelView.aim(at: point) }
            let destination = WheelDragGeometry.externalDropDestination(inCore: inCore, hoveredSlot: wheelView.hoveredSlot,
                occupiedSlots: Set(controller.workspace.slots.filter { $0.window != nil }.map(\.number)))
            externalDrag = nil; externalPressPoint = nil
            updateInteractionState()
            let target: Int
            switch destination {
            case .slot(let number): target = number
            case .noEmptySlot, .occupied, .outsideSlots:
                let reason: String
                switch destination {
                case .noEmptySlot: reason = "没有空槽可收纳窗口。"
                case .occupied(let number): reason = "\(number) 号槽位已被占用，请选择空槽。"
                default: reason = "未落到可收纳的槽位，请拖到器物核心或空槽。"
                }
                if controller.restoreRejectedDrop(drag.window, originalFrame: drag.original) {
                    controller.notice = reason + " 原窗口已回位。"
                }
                return
            }
            guard controller.captureDraggedWindow(drag.window, originalFrame: drag.original, to: target) else { return }
            controller.notice = "已收纳到 \(String(format: "%02d", target)) 号槽位。"
            suppressHoverUntilLeave = true
            setExpanded(false)
        }
    }

    private func updateInteractionState() {
        controller.setWheelInteraction(corePressed || dragging || slotManipulating || externalDrag != nil)
    }

    private func externalCandidate() -> ExternalDrag? {
        guard let window = controller.windows.currentWindow(),
              let placement = try? controller.windows.captureTrackingPlacement(window), !placement.minimized else { return nil }
        return ExternalDrag(window: window, original: placement.frame)
    }

    private func selectSlot(_ number: Int) {
        pinnedExpansion = false
        guard !controller.isDemo else { onShowInventory(); return }
        guard controller.canControlWindows else {
            controller.requireAccessibilityPermission(reason: "绑定和切换窗口需要辅助功能权限。")
            return
        }
        if let slot = controller.workspace.slots.first(where: { $0.number == number }), slot.window != nil {
            controller.toggleSlot(number)
            suppressHoverUntilLeave = true
            setExpanded(false)
        } else {
            onShowInventory()
            controller.openPicker(for: number)
        }
    }

    func beginAim() {
        guard !isAiming, !dragging, !slotManipulating else { return }
        controller.rememberExternalFocus()
        aimReturn = (anchor, expanded, panel.isVisible)
        isAiming = true
        pinnedExpansion = false
        anchor = clamped(NSEvent.mouseLocation)
        setExpanded(true)
        panel.orderFrontRegardless()
        do { try hotkeys?.beginEscapeCapture() }
        catch { controller.notice = error.localizedDescription + " 可移回圆心并松键取消。" }
        _ = wheelView.aim(at: NSEvent.mouseLocation)
    }

    func endAim(confirm: Bool = true) {
        guard isAiming else { return }
        if confirm { _ = wheelView.aim(at: NSEvent.mouseLocation) }
        let selected = confirm ? wheelView.hoveredSlot : nil
        isAiming = false
        hotkeys?.endEscapeCapture()
        wheelView.clearAim()
        if let previous = aimReturn {
            anchor = previous.anchor
            setExpanded(previous.expanded)
            if !previous.visible { panel.orderOut(nil) }
        } else { setExpanded(false) }
        aimReturn = nil
        if let selected { selectSlot(selected) }
    }

    func resumeHotkeys() {
        guard !controller.isDemo, !servicesStopped else { return }
        if controller.isRecordingShortcut || controller.shortcutsPaused {
            if !hotkeysSuspended || hotkeys != nil || scrollSwitch != nil { suspendHotkeys() }
            return
        }
        hotkeysSuspended = false
        defer { refreshScrollSwitch(force: true) }
        guard hotkeys == nil else { return }
        let keys = WheelHotKeyService(configuration: controller.shortcutConfiguration, scheme: controller.shortcutScheme, onPress: { [weak self] in
                guard let self else { return }
                self.controller.recordShortcut(self.controller.shortcutLabel(.aim)); self.beginAim()
            },
            onRelease: { [weak self] in self?.endAim() },
            onToggle: { [weak self] in
                guard let self else { return }
                self.controller.recordShortcut(self.controller.shortcutLabel(.toggleVisibility)); self.toggleVisibility()
            },
            onCancel: { [weak self] in self?.controller.recordShortcut("Esc"); self?.endAim(confirm: false) },
            onInventory: { [weak self] in
                guard let self else { return }
                self.controller.recordShortcut(self.controller.shortcutLabel(.inventory))
                self.controller.toggleInventoryFromShortcut()
            })
        do {
            try keys.register()
            hotkeys = keys
            wheelRegistrationWarnings = keys.warnings
            reportWheelRegistration()
        } catch {
            wheelRegistrationWarnings = [error.localizedDescription]
            reportWheelRegistration()
        }
    }

    func retryHotkeys() {
        if isAiming { endAim(confirm: false) }
        hotkeys?.unregister()
        hotkeys = nil
        resumeHotkeys()
    }

    func suspendHotkeys() {
        hotkeysSuspended = true
        endAim(confirm: false)
        wheelView.cancelSlotInteraction()
        endPointerEscapeCapture()
        hotkeys?.unregister()
        hotkeys = nil
        scrollSwitch?.stop(); scrollSwitch = nil
        lastScrollConfiguration = nil
        scrollWarnings = []; wheelRegistrationWarnings = []
        controller.reportWheelShortcuts(registered: [], warnings: [])
    }

    private func synchronizeShortcutServices() {
        guard !servicesStopped, !controller.isDemo else { return }
        if controller.isRecordingShortcut || controller.shortcutsPaused {
            if !hotkeysSuspended { suspendHotkeys() }
        } else if hotkeysSuspended { resumeHotkeys() }
        else { refreshScrollSwitch() }
    }

    private func refreshScrollSwitch(force: Bool = false) {
        let configuration = ScrollConfiguration(enabled: controller.wheelSwitchEnabled,
            modifiers: controller.wheelModifiers,
            suspended: servicesStopped || hotkeysSuspended || controller.shortcutsPaused || controller.isRecordingShortcut)
        guard force || lastScrollConfiguration != configuration else { return }
        lastScrollConfiguration = configuration
        scrollSwitch?.stop(); scrollSwitch = nil
        scrollWarnings = []
        guard configuration.enabled, !configuration.suspended, !controller.isDemo else { reportWheelRegistration(); return }
        let service = TaskScrollSwitchService(onSwitch: { [weak self] direction in
            guard let self, !self.controller.shortcutsPaused, !self.controller.isRecordingShortcut else { return }
            self.controller.cycleTask(direction: direction)
        }, onWarning: { [weak self] message in
            guard let self else { return }
            self.scrollWarnings = [message]
            self.controller.notice = message
            self.reportWheelRegistration()
        })
        scrollWarnings = service.start(modifiers: configuration.modifiers)
        scrollSwitch = service
        reportWheelRegistration()
    }

    private func reportWheelRegistration() {
        controller.reportWheelShortcuts(registered: hotkeys?.registeredShortcuts ?? [],
            warnings: wheelRegistrationWarnings + scrollWarnings)
    }

    private func beginPointerEscapeCapture() {
        guard pointerEscape == nil, !controller.isDemo, !controller.isRecordingShortcut, !controller.shortcutsPaused else { return }
        let escape = PointerEscapeHotKeyService { [weak self] in
            self?.controller.recordShortcut("Esc")
            self?.wheelView.cancelSlotInteraction()
        }
        do {
            try escape.begin(modifiers: PointerEscapeHotKeyService.carbonModifiers(for: NSEvent.modifierFlags))
            pointerEscape = escape
            if !escape.warnings.isEmpty { controller.notice = escape.warnings.joined(separator: "\n") }
        } catch { controller.notice = error.localizedDescription }
    }

    private func endPointerEscapeCapture() {
        pointerEscape?.end()
        pointerEscape = nil
    }

    func stop() {
        servicesStopped = true
        scrollSwitch?.stop(); scrollSwitch = nil
        wheelView.cancelSlotInteraction()
        endPointerEscapeCapture()
        endAim(confirm: false)
        endCoreDrag()
        corePressed = false
        externalDrag = nil; externalPressPoint = nil
        updateInteractionState()
        collapseWork?.cancel()
        pointerTimer?.invalidate()
        pointerTimer = nil
        hotkeys?.unregister()
        hotkeys = nil
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
        localEscapeMonitor = nil
    }

    func resumeAfterCancelledQuit() { servicesStopped = false; startPointerTimer(); resumeHotkeys() }

    private func showContextMenu(with event: NSEvent) {
        collapseWork?.cancel()
        menuOpen = true
        defer { menuOpen = false; scheduleCollapse() }
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: wheelView)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "OmniVibe")
        let inventoryKey = controller.shortcutLabel(.inventory)
        add(L10n.text("打开\(appearance.theme.overviewTitle)") + (inventoryKey.isEmpty ? "" : "　" + inventoryKey), action: #selector(openInventory), to: menu)
        add(L10n.text("新建或继续任务…"), action: #selector(openNewTask), to: menu).isEnabled = !controller.isDemo && !controller.taskLaunchBusy
        add(expanded ? L10n.text("收起装备轮盘") : L10n.text("展开装备轮盘"), action: #selector(toggleExpansion), to: menu)
        let arrangeKey = controller.shortcutLabel(.arrange)
        add((controller.isArranged ? L10n.text("恢复原窗口布局") : L10n.text("排列已绑定窗口")) + (arrangeKey.isEmpty ? "" : "　" + arrangeKey), action: #selector(arrangeWindows), to: menu)
        add(L10n.text("收起全部任务"), action: #selector(parkAllTasks), to: menu).isEnabled = controller.occupiedCount > 0
        add(controller.shortcutsPaused ? L10n.text("恢复全局快捷键与滚轮") : L10n.text("暂停全局快捷键与滚轮"), action: #selector(toggleShortcutPause), to: menu)
        if let number = wheelView.hoveredSlot, let slot = controller.workspace.slots.first(where: { $0.number == number }) {
            menu.addItem(.separator())
            let title = NSMenuItem(title: L10n.text("\(number) 号槽位 · \(slot.displayName)"), action: nil, keyEquivalent: "")
            title.isEnabled = false; menu.addItem(title)
            if slot.window != nil {
                let enterKey = controller.shortcutLabel(.slot(number))
                add(L10n.text("进入任务") + (enterKey.isEmpty ? "" : "　" + enterKey), action: #selector(enterHoveredTask(_:)), tag: number, to: menu)
                add(L10n.text("编辑任务名称…"), action: #selector(editHoveredTask(_:)), tag: number, to: menu)
                if !controller.isDemo {
                    add(L10n.text("连接自动任务状态…"), action: #selector(connectHoveredTask(_:)), tag: number, to: menu)
                    add(L10n.text("关联已有 CLI 会话…"), action: #selector(discoverHoveredSession(_:)), tag: number, to: menu)
                    add(L10n.text("配置启动与续接…"), action: #selector(configureHoveredLaunch(_:)), tag: number, to: menu)
                }
                add(L10n.text("重新绑定窗口…"), action: #selector(bindHoveredTask(_:)), tag: number, to: menu)
                let removeItem = add(L10n.text("移出管理 · 保留窗口"), action: #selector(removeHoveredTask(_:)), tag: number, to: menu)
                removeItem.representedObject = slot.id.uuidString
            } else { add(L10n.text("绑定窗口…"), action: #selector(bindHoveredTask(_:)), tag: number, to: menu) }
        }
        menu.addItem(.separator())
        let themeItem = NSMenuItem(title: L10n.text("切换主题"), action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: L10n.text("切换主题"))
        for theme in appearance.availableThemes {
            let item = add(theme.name, action: #selector(selectTheme(_:)), to: themeMenu)
            item.representedObject = theme.slug
            item.state = theme.slug == appearance.themeSlug ? .on : .off
        }
        themeItem.submenu = themeMenu; menu.addItem(themeItem)
        add(L10n.text("主题装饰"), action: #selector(toggleDecorations), checked: appearance.decorations, to: menu)
        add(L10n.text("界面动效"), action: #selector(toggleMotion), checked: appearance.animate, to: menu)
        menu.addItem(.separator())
        add(L10n.text("设置与辅助功能授权…"), action: #selector(openSettings), to: menu)
        let aimKey = controller.shortcutLabel(.aim)
        let helpText = aimKey.isEmpty ? controller.shortcutLabel(.inventory) + L10n.text(" 打开总览，再按数字进入") : L10n.text("按住 \(aimKey) 指向任务，松键进入 · Esc 取消")
        let help = NSMenuItem(title: helpText, action: nil, keyEquivalent: "")
        help.isEnabled = false; menu.addItem(help)
        let toggleKey = controller.shortcutLabel(.toggleVisibility)
        add((panel.isVisible ? L10n.text("隐藏悬浮入口") : L10n.text("显示悬浮入口")) + (toggleKey.isEmpty ? "" : "　" + toggleKey), action: #selector(toggleLauncher), to: menu)
        menu.addItem(.separator())
        add(L10n.text("退出 OmniVibe"), action: #selector(quit), to: menu)
        return menu
    }

    @discardableResult
    private func add(_ title: String, action: Selector, tag: Int = 0, checked: Bool? = nil, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.tag = tag
        if let checked { item.state = checked ? .on : .off }
        menu.addItem(item)
        return item
    }

    @objc private func openInventory() { onShowInventory() }
    @objc private func openNewTask() { controller.beginNewTask() }
    @objc private func configureHoveredLaunch(_ sender: NSMenuItem) { controller.beginLaunching(sender.tag) }
    @objc private func discoverHoveredSession(_ sender: NSMenuItem) {
        controller.sessionDiscoverySlot = sender.tag
        onShowInventory()
    }
    @objc private func toggleExpansion() {
        let opening = !expanded
        pinnedExpansion = opening
        suppressHoverUntilLeave = !opening
        setExpanded(opening)
        panel.orderFrontRegardless()
    }
    @objc private func openSettings() { onShowSettings() }
    @objc private func arrangeWindows() { controller.rememberExternalFocus(); controller.toggleArrangement() }
    @objc private func parkAllTasks() { controller.parkAllTasks() }
    @objc private func toggleShortcutPause() { controller.setShortcutsPaused(!controller.shortcutsPaused) }
    @objc private func enterHoveredTask(_ sender: NSMenuItem) { selectSlot(sender.tag) }
    @objc private func selectTheme(_ sender: NSMenuItem) { if let slug = sender.representedObject as? String { appearance.setTheme(slug) } }
    @objc private func toggleDecorations() { appearance.setDecorations(!appearance.decorations) }
    @objc private func toggleMotion() { appearance.setAnimate(!appearance.animate) }
    @objc private func toggleLauncher() { toggleVisibility() }
    @objc private func quit() { onQuit() }
    @objc private func bindHoveredTask(_ sender: NSMenuItem) {
        guard controller.canControlWindows else {
            controller.requireAccessibilityPermission(reason: L10n.text("绑定窗口需要辅助功能权限。"))
            return
        }
        onShowInventory(); controller.openPicker(for: sender.tag)
    }
    @objc private func editHoveredTask(_ sender: NSMenuItem) {
        guard let slot = controller.workspace.slots.first(where: { $0.number == sender.tag }) else { return }
        onShowInventory(); controller.beginRenaming(slot)
    }
    @objc private func removeHoveredTask(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String, let taskID = UUID(uuidString: text) else { return }
        _ = controller.remove(sender.tag, expectedTaskID: taskID)
    }
    @objc private func connectHoveredTask(_ sender: NSMenuItem) {
        onShowInventory()
        controller.integrationSlot = sender.tag
    }
}

/// Coordinate math is independent of AppKit event delivery and AX permissions.
enum WheelDragGeometry {
    static let coreExtent: CGFloat = 54
    static let coreArtworkExtent: CGFloat = 116
    static let wheelLogicalExtent: CGFloat = 360
    // Includes the largest equipped item, its hover zoom and remove control.
    private static let slotEnvelopeExtent: CGFloat = 104

    struct Layout: Equatable {
        let frame: NSRect
        let coreScreenCenter: NSPoint
        let wheelScreenFrame: NSRect
        let scale: CGFloat
        let expanded: Bool

        var logicalSize: NSSize { NSSize(width: frame.width / scale, height: frame.height / scale) }
        var coreLogicalExtent: CGFloat { WheelDragGeometry.coreExtent / scale }
        var coreScreenFrame: NSRect {
            NSRect(x: coreScreenCenter.x - WheelDragGeometry.coreExtent / 2, y: coreScreenCenter.y - WheelDragGeometry.coreExtent / 2,
                   width: WheelDragGeometry.coreExtent, height: WheelDragGeometry.coreExtent)
        }
        var coreCentre: NSPoint { logicalPoint(coreScreenCenter) }
        var wheelCentre: NSPoint { logicalPoint(NSPoint(x: wheelScreenFrame.midX, y: wheelScreenFrame.midY)) }
        var logicalWheelExtent: CGFloat { expanded ? WheelDragGeometry.wheelLogicalExtent : WheelDragGeometry.coreArtworkExtent }
        var slotScreenFrames: [NSRect] {
            guard expanded else { return [] }
            return WheelDragGeometry.slotFrames(centre: NSPoint(x: wheelScreenFrame.midX, y: wheelScreenFrame.midY), scale: scale)
        }
        private func logicalPoint(_ point: NSPoint) -> NSPoint {
            // NativeWheelView is flipped; screen coordinates are not.
            NSPoint(x: (point.x - frame.minX) / scale, y: (frame.maxY - point.y) / scale)
        }
    }

    static func physicalExtent(configured: Double, expanded: Bool) -> CGFloat {
        let checked = configured.isFinite ? min(520, max(280, configured)) : 360
        return expanded ? CGFloat(checked) : coreExtent
    }

    /// A single core anchor survives every hover transition. At an edge only
    /// the equipment orbit moves inward; its full item/remove targets remain
    /// within the work area and clear of the core's fixed 54-point target.
    static func layout(anchor: NSPoint, configured: Double, expanded: Bool, workArea: NSRect) -> Layout {
        let core = NSRect(x: anchor.x - coreExtent / 2, y: anchor.y - coreExtent / 2,
                          width: coreExtent, height: coreExtent)
        guard expanded else {
            return Layout(frame: core, coreScreenCenter: anchor, wheelScreenFrame: core,
                          scale: coreExtent / coreArtworkExtent, expanded: false)
        }
        var extent = min(physicalExtent(configured: configured, expanded: true), workArea.width, workArea.height)
        var orbit = panelFrame(anchor: anchor, extent: extent, workArea: workArea)
        while extent > 0 {
            let scale = extent / wheelLogicalExtent
            let fitted = panelFrame(anchor: anchor, extent: extent, workArea: workArea)
            // This distance also offers an entirely separate inward orbit
            // when the nearest fitted orbit would cover the anchored core.
            let separation = (124.8 + slotEnvelopeExtent / 2) * scale + coreExtent / 2 + 8
            func fitX(_ x: CGFloat) -> CGFloat { min(max(x, workArea.minX + extent / 2), workArea.maxX - extent / 2) }
            func fitY(_ y: CGFloat) -> CGFloat { min(max(y, workArea.minY + extent / 2), workArea.maxY - extent / 2) }
            let xs = [fitted.midX, fitX(anchor.x - separation), fitX(anchor.x + separation),
                      workArea.minX + extent / 2, workArea.maxX - extent / 2]
            let ys = [fitted.midY, fitY(anchor.y - separation), fitY(anchor.y + separation),
                      workArea.minY + extent / 2, workArea.maxY - extent / 2]
            let protectedCore = core.insetBy(dx: -8, dy: -8)
            var best: (centre: NSPoint, distance: CGFloat)?
            for x in xs {
                for y in ys {
                    let centre = NSPoint(x: x, y: y)
                    guard slotFrames(centre: centre, scale: scale).allSatisfy({
                        workArea.contains($0) && !$0.intersects(protectedCore)
                    }) else { continue }
                    let distance = hypot(x - anchor.x, y - anchor.y)
                    if best == nil || distance < best!.distance { best = (centre, distance) }
                }
            }
            if let best {
                orbit = NSRect(x: best.centre.x - extent / 2, y: best.centre.y - extent / 2,
                               width: extent, height: extent)
                break
            }
            // Fit very small work areas without changing the stored size
            // preference. The normal 280–520-point choices remain untouched.
            extent = max(0, extent - 4)
            orbit = panelFrame(anchor: anchor, extent: max(1, extent), workArea: workArea)
        }
        let scale = max(1, orbit.width) / wheelLogicalExtent
        let host = slotFrames(centre: NSPoint(x: orbit.midX, y: orbit.midY), scale: scale)
            .reduce(orbit.union(core)) { $0.union($1) }
        return Layout(frame: host, coreScreenCenter: anchor, wheelScreenFrame: orbit,
                      scale: scale, expanded: true)
    }

    private static func slotFrames(centre: NSPoint, scale: CGFloat) -> [NSRect] {
        (1...9).map { number in
            let angle = CGFloat(number - 1) * 40 * .pi / 180
            let point = NSPoint(x: centre.x + sin(angle) * 124.8 * scale,
                                y: centre.y + cos(angle) * 124.8 * scale)
            // Even when fitting a small display, remove controls keep their
            // 22-point physical hit target plus a one-point stroke allowance.
            let side = max(slotEnvelopeExtent * scale, 2 * (35.6 * scale + 12))
            return NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        }
    }

    static func coreContains(_ point: NSPoint, layout: Layout?, margin: CGFloat = 0) -> Bool {
        guard let layout else { return false }
        return layout.coreScreenFrame.insetBy(dx: -margin, dy: -margin).contains(point)
    }

    enum ExternalDropDestination: Equatable {
        case slot(Int), noEmptySlot, occupied(Int), outsideSlots
    }

    static func externalDropDestination(inCore: Bool, hoveredSlot: Int?, occupiedSlots: Set<Int>) -> ExternalDropDestination {
        if inCore {
            return (1...9).first(where: { !occupiedSlots.contains($0) }).map(ExternalDropDestination.slot) ?? .noEmptySlot
        }
        guard let hoveredSlot, (1...9).contains(hoveredSlot) else { return .outsideSlots }
        return occupiedSlots.contains(hoveredSlot) ? .occupied(hoveredSlot) : .slot(hoveredSlot)
    }

    struct DragOrigin: Equatable {
        let windowID: UUID
        let frame: WindowFrame
    }

    /// Prefer a pre-press snapshot of the exact same AX window. A new first
    /// sample is usable only while the pointer stayed essentially stationary
    /// during that sample; samples taken later in a drag are never considered.
    static func initialDragOrigin(pressPoint: NSPoint, samplePoint: NSPoint,
                                  cached: DragOrigin?, fresh: DragOrigin?, primaryTop: CGFloat) -> DragOrigin? {
        if let cached, (fresh == nil || fresh?.windowID == cached.windowID),
           isTitleBar(pressPoint, frame: cached.frame, primaryTop: primaryTop) { return cached }
        guard let fresh, hypot(samplePoint.x - pressPoint.x, samplePoint.y - pressPoint.y) <= 3,
              isTitleBar(pressPoint, frame: fresh.frame, primaryTop: primaryTop),
              isTitleBar(samplePoint, frame: fresh.frame, primaryTop: primaryTop) else { return nil }
        return fresh
    }

    /// Fits an orbit/collapsed rectangle. A fitted orbit's midpoint is never
    /// used as the core anchor; `layout` preserves that coordinate separately.
    static func panelFrame(anchor: NSPoint, extent: CGFloat, workArea: NSRect) -> NSRect {
        let width = min(extent, workArea.width), height = min(extent, workArea.height)
        return NSRect(x: min(max(anchor.x - width / 2, workArea.minX), workArea.maxX - width),
                      y: min(max(anchor.y - height / 2, workArea.minY), workArea.maxY - height),
                      width: width, height: height)
    }

    static func translatedAnchor(from anchor: NSPoint, pressPoint: NSPoint, to point: NSPoint) -> NSPoint {
        NSPoint(x: anchor.x + point.x - pressPoint.x, y: anchor.y + point.y - pressPoint.y)
    }

    static func isTitleBar(_ point: NSPoint, frame: WindowFrame, primaryTop: CGFloat) -> Bool {
        guard valid(frame), point.x.isFinite, point.y.isFinite, primaryTop.isFinite else { return false }
        let x = Double(point.x), y = Double(primaryTop - point.y)
        return x >= frame.x && x <= frame.x + frame.width &&
            y >= frame.y && y <= frame.y + min(48, frame.height)
    }

    static func windowMoved(from original: WindowFrame, to current: WindowFrame) -> Bool {
        guard valid(original), valid(current) else { return false }
        let originMoved = abs(current.x - original.x) > 3 || abs(current.y - original.y) > 3
        let sameSize = abs(current.width - original.width) < 3 && abs(current.height - original.height) < 3
        return originMoved && sameSize
    }

    private static func valid(_ frame: WindowFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite && frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
    }
}

@MainActor
private final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
