import AppKit
import Combine
import OmniVibeCore

/// The native desktop entry keeps the Windows wheel's open alpha silhouette,
/// equipment sizes and fixed clockwise numbering. It never owns a window.
@MainActor
final class NativeWheelView: NSView {
    let controller: ApplicationController
    let appearanceModel: AppearanceModel
    var onHoverChanged: ((Bool) -> Void)?
    var onCoreClick: (() -> Void)?
    var onCorePressChanged: ((Bool) -> Void)?
    var onCoreDragBegan: ((NSPoint) -> Void)?
    var onCoreDragMoved: ((NSPoint) -> Void)?
    var onCoreDragEnded: (() -> Void)?
    var onSlotClick: ((Int) -> Void)?
    var onSlotInteractionChanged: ((Bool) -> Void)?
    var onSlotReorder: ((Int, Int, UUID) -> Bool)?
    var onSlotRemove: ((Int, UUID) -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    var wheelLayout: WheelDragGeometry.Layout? {
        didSet { updateTrackingAreas(); needsDisplay = true }
    }
    private(set) var hoveredSlot: Int?
    var expanded = false {
        didSet {
            guard expanded != oldValue else { return }
            if !expanded { cancelSlotInteraction() }
            clearAim()
            revealTimer?.invalidate()
            if expanded && appearanceModel.animate {
                deployment = 0
                let start = Date()
                let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
                    MainActor.assumeIsolated {
                        guard let self else { timer.invalidate(); return }
                        let progress = min(1, Date().timeIntervalSince(start) / 0.115)
                        self.deployment = 1 - pow(1 - progress, 3)
                        self.needsDisplay = true
                        if progress >= 1 { timer.invalidate(); self.revealTimer = nil }
                    }
                }
                revealTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            } else { deployment = expanded ? 1 : 0 }
            needsDisplay = true
            updateTrackingAreas()
        }
    }

    private var tracking: NSTrackingArea?
    private var subscriptions = Set<AnyCancellable>()
    private var deployment: Double = 0
    private var revealTimer: Timer?
    private var downPoint = NSPoint.zero
    private var downScreenPoint = NSPoint.zero
    private var slotGesture: WheelSlotGesture?
    private var incomingTaskID: UUID?
    private var dropSlot: Int?
    private var removeHovered = false
    private var slotDragPoint: NSPoint?
    private var pressedCore = false
    private var didDragCore = false
    private var lastEquippedTaskID: UUID?
    var isSlotManipulating: Bool { slotGesture != nil || incomingTaskID != nil }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    init(controller: ApplicationController, appearance: AppearanceModel) {
        self.controller = controller
        self.appearanceModel = appearance
        super.init(frame: NSRect(x: 0, y: 0, width: 116, height: 116))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([TaskDragPayload.pasteboardType])
        controller.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refreshContent() }
        }.store(in: &subscriptions)
        appearanceModel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refreshContent() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .omniVibeLanguageDidChange).sink { [weak self] _ in
            Task { @MainActor in self?.refreshContent() }
        }.store(in: &subscriptions)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        refreshContent()
    }

    required init?(coder: NSCoder) { nil }

    private func refreshContent() {
        if let number = controller.activeSlot,
           let slot = controller.workspace.slots.first(where: { $0.number == number && $0.window != nil }) {
            lastEquippedTaskID = slot.id
        }
        if let gesture = slotGesture, let taskID = gesture.taskID,
           !controller.workspace.slots.contains(where: { $0.number == gesture.source && $0.id == taskID && $0.window != nil }) {
            cancelSlotInteraction()
        }
        if let incomingTaskID, !controller.workspace.slots.contains(where: { $0.id == incomingTaskID && $0.window != nil }) {
            cancelSlotInteraction()
        }
        _ = ThemeResources.shared.identity(themeSlug: appearanceModel.themeSlug)
        for slot in controller.workspace.slots where slot.window != nil { _ = appearanceModel.entity(for: slot) }
        setAccessibilityLabel("OmniVibe · " + appearanceModel.theme.dockTitle + (controller.isDemo ? L10n.text(" · 界面演示") : ""))
        setAccessibilityHelp(expanded ? L10n.text("点击器物进入窗口；拖到其他槽位按插入顺序排序；悬停后点击叉号移出管理，保留原窗口。") : L10n.text("悬停展开装备轮盘；拖动核心移动入口；右键打开任务总览与设置。"))
        updateTooltip()
        needsDisplay = true
    }

    private var centre: NSPoint { wheelLayout?.wheelCentre ?? NSPoint(x: bounds.midX, y: bounds.midY) }
    private var coreCentre: NSPoint { wheelLayout?.coreCentre ?? centre }
    private var coreExtent: CGFloat { wheelLayout?.coreLogicalExtent ?? 116 }
    private var radius: CGFloat { max(1, (wheelLayout?.logicalWheelExtent ?? min(bounds.width, bounds.height)) / 2 - 24) }
    private var factor: CGFloat { min(1.12, max(0.5, radius / 202)) }
    private var currentSlot: TaskSlot? {
        let occupied = controller.workspace.slots.filter { $0.window != nil }
        if let number = controller.activeSlot, let slot = occupied.first(where: { $0.number == number }) { return slot }
        if let taskID = lastEquippedTaskID, let slot = occupied.first(where: { $0.id == taskID && controller.isConnected($0) }) { return slot }
        return occupied.first(where: { controller.isConnected($0) }) ?? occupied.first
    }

    private func slotPoint(_ number: Int, deployment: CGFloat = 1) -> NSPoint {
        let angle = CGFloat(number - 1) * 40 * .pi / 180
        let distance = 60 + (radius * 0.8 - 60) * deployment
        return NSPoint(x: centre.x + sin(angle) * distance, y: centre.y - cos(angle) * distance)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.imageInterpolation = .high
        let theme = appearanceModel.theme
        if expanded && deployment > 0 {
            drawConnector(theme)
            for slot in controller.workspace.slots.sorted(by: { $0.number < $1.number }) {
                let point = slotPoint(slot.number, deployment: CGFloat(deployment))
                if slot.window == nil { drawEmpty(slot, at: point, theme: theme) }
                else { drawOccupied(slot, at: point, theme: theme) }
            }
            drawRemove(theme)
        }
        drawCore(theme)
        if let gesture = slotGesture, gesture.sorting, let point = slotDragPoint,
           let source = controller.workspace.slots.first(where: { $0.id == gesture.taskID }) {
            drawImage(appearanceModel.entity(for: source),
                      in: NSRect(x: point.x - 32, y: point.y - 32, width: 64, height: 64), alpha: 0.85)
        }
    }

    private func drawConnector(_ theme: ThemeDefinition) {
        let distance = hypot(coreCentre.x - centre.x, coreCentre.y - centre.y)
        guard distance > 2 else { return }
        let dx = (centre.x - coreCentre.x) / distance, dy = (centre.y - coreCentre.y) / distance
        let inset = coreExtent / 2 + 5 / (wheelLayout?.scale ?? 1)
        let start = NSPoint(x: coreCentre.x + dx * inset, y: coreCentre.y + dy * inset)
        drawLine(from: start, to: centre, color: theme.accent.withAlphaComponent(0.32 * deployment), width: 1)
        theme.accent.withAlphaComponent(0.45 * deployment).setStroke()
        NSBezierPath(ovalIn: NSRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)).stroke()
    }

    private func drawCore(_ theme: ThemeDefinition) {
        // Keep the complete original artwork and status composition. Its
        // independent transform has the same 54-point footprint in both modes.
        let centre = coreCentre
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: centre.x, yBy: centre.y)
        transform.scale(by: coreExtent / 116)
        transform.translateX(by: -centre.x, yBy: -centre.y)
        transform.concat()
        if let current = currentSlot {
            if expanded && appearanceModel.decorations && appearanceModel.themeSlug != "arsenal" {
                drawPedestal(in: NSRect(x: centre.x - 43, y: centre.y + 46, width: 86, height: 8), theme: theme, opacity: 0.8)
            }
            drawImage(appearanceModel.entity(for: current), in: NSRect(x: centre.x - 55, y: centre.y - 55, width: 110, height: 110), alpha: 1)
            drawCoreStatus(theme)
        } else {
            drawImage(ThemeResources.shared.identity(themeSlug: appearanceModel.themeSlug),
                      in: NSRect(x: centre.x - 55, y: centre.y - 57, width: 110, height: 92), alpha: 1)
            let cue = NSRect(x: centre.x - 45, y: centre.y + 33, width: 90, height: 21)
            theme.background.withAlphaComponent(0.86).setFill()
            let plate = NSBezierPath(roundedRect: cue, xRadius: 10, yRadius: 10)
            plate.fill()
            theme.border.withAlphaComponent(0.5).setStroke(); plate.lineWidth = 0.6; plate.stroke()
            drawArrow(at: NSPoint(x: centre.x - 30, y: centre.y + 43), color: theme.accent)
            drawText(L10n.text("拖入窗口"), at: NSPoint(x: centre.x + 8, y: centre.y + 43), size: 10, color: theme.text, width: 65)
        }
    }

    private func drawEmpty(_ slot: TaskSlot, at point: NSPoint, theme: ThemeDefinition) {
        let side = max(34, 42 * factor)
        let selected = hoveredSlot == slot.number
        let rect = NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        let plate = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        theme.surface.withAlphaComponent((selected ? 0.54 : 0.22) * deployment).setFill(); plate.fill()
        (selected ? theme.accent : theme.muted).withAlphaComponent((selected ? 0.72 : 0.24) * deployment).setStroke()
        plate.lineWidth = 0.7; plate.stroke()
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: point.x - 5, y: point.y)); plus.line(to: NSPoint(x: point.x + 5, y: point.y))
        plus.move(to: NSPoint(x: point.x, y: point.y - 5)); plus.line(to: NSPoint(x: point.x, y: point.y + 5))
        plus.lineWidth = 1.1; plus.lineCapStyle = .round
        (selected ? theme.accent : theme.text).withAlphaComponent((selected ? 1 : 0.58) * deployment).setStroke(); plus.stroke()
        drawText(String(slot.number), at: NSPoint(x: rect.minX + 7, y: rect.minY + 7), size: 8,
                 color: theme.muted.withAlphaComponent(deployment), width: 12)
        if dropSlot == slot.number { drawDropMark(rect.insetBy(dx: -5, dy: -5), theme: theme) }
    }

    private func drawOccupied(_ slot: TaskSlot, at point: NSPoint, theme: ThemeDefinition) {
        let selected = hoveredSlot == slot.number
        let active = controller.activeSlot == slot.number
        let connected = controller.isDemo || controller.isConnected(slot)
        let width = 88 * factor, height = 78 * factor
        let zoom: CGFloat = selected ? 1.07 : 1
        if appearanceModel.decorations && appearanceModel.themeSlug != "arsenal" {
            drawPedestal(in: NSRect(x: point.x - width * 0.4, y: point.y + height / 2 - 3,
                                   width: width * 0.8, height: 8), theme: theme, opacity: (selected || active ? 0.56 : 0.24) * deployment)
        }
        if selected || active {
            drawLine(from: NSPoint(x: point.x - width * 0.24, y: point.y + height / 2 + 3),
                     to: NSPoint(x: point.x + width * 0.24, y: point.y + height / 2 + 3),
                     color: theme.accent.withAlphaComponent(selected ? 0.8 : 0.45), width: 1.2)
        }
        drawImage(appearanceModel.entity(for: slot),
                  in: NSRect(x: point.x - width * zoom / 2, y: point.y - height * zoom / 2, width: width * zoom, height: height * zoom),
                  alpha: (slotGesture?.sorting == true && slotGesture?.source == slot.number ? 0.3 : connected ? selected || active ? 1 : 0.94 : 0.55) * deployment)
        drawText(String(slot.number), at: NSPoint(x: point.x - width / 2 + 5, y: point.y + height / 2 - 3),
                 size: 11, color: selected || active ? theme.accent : theme.text, width: 18, bold: true)
        drawStateGlyph(slot.statusMayBeStale ? .unknown : slot.agentState, at: NSPoint(x: point.x - width / 2 + 22, y: point.y + height / 2 - 3),
                       theme: theme, connected: connected)
        if dropSlot == slot.number {
            drawDropMark(NSRect(x: point.x - width / 2 - 5, y: point.y - height / 2 - 5,
                                width: width + 10, height: height + 10), theme: theme)
        }
    }

    private func drawDropMark(_ rect: NSRect, theme: ThemeDefinition) {
        let mark = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        theme.accent.withAlphaComponent(0.12).setFill(); mark.fill()
        theme.accent.setStroke(); mark.lineWidth = 2; mark.stroke()
    }

    private func removePoint(_ number: Int) -> NSPoint {
        let point = slotPoint(number)
        return NSPoint(x: point.x + 46 * factor, y: point.y - 39 * factor)
    }

    // The host frame is measured in AppKit points, while the wheel keeps its
    // 360-point logical bounds. Preserve a real 22-point target when shrinking.
    private var removeTargetSize: NSSize {
        WheelSlotGesture.removeTargetSize(physicalSize: frame.size, logicalSize: bounds.size)
    }

    private func hitRemove(_ point: NSPoint) -> Int? {
        guard expanded, deployment > 0.9, slotGesture?.sorting != true, let number = hoveredSlot,
              controller.workspace.slots.contains(where: { $0.number == number && $0.window != nil }),
              WheelSlotGesture.hitsRemove(point, centre: removePoint(number), targetSize: removeTargetSize) else { return nil }
        return number
    }

    private func drawRemove(_ theme: ThemeDefinition) {
        guard expanded, deployment > 0.9, slotGesture?.sorting != true, let number = hoveredSlot,
              controller.workspace.slots.contains(where: { $0.number == number && $0.window != nil }) else { return }
        let point = removePoint(number)
        let target = removeTargetSize
        let circle = NSBezierPath(ovalIn: NSRect(x: point.x - target.width / 2, y: point.y - target.height / 2,
                                                width: target.width, height: target.height))
        theme.background.withAlphaComponent(removeHovered ? 0.98 : 0.9).setFill(); circle.fill()
        (removeHovered ? theme.error : theme.border).withAlphaComponent(0.9).setStroke(); circle.lineWidth = 0.8; circle.stroke()
        let color = removeHovered ? theme.error : theme.text
        drawLine(from: NSPoint(x: point.x - 3.5, y: point.y - 3.5), to: NSPoint(x: point.x + 3.5, y: point.y + 3.5), color: color, width: 1.4)
        drawLine(from: NSPoint(x: point.x - 3.5, y: point.y + 3.5), to: NSPoint(x: point.x + 3.5, y: point.y - 3.5), color: color, width: 1.4)
    }

    private func drawCoreStatus(_ theme: ThemeDefinition) {
        let occupied = controller.workspace.slots.filter { $0.window != nil && (controller.isDemo || controller.isConnected($0)) }
        guard !occupied.isEmpty else { return }
        let attention = occupied.filter { !$0.statusMayBeStale && $0.unread && [.waiting, .ready, .error].contains($0.agentState) }
        let running = occupied.filter { !$0.statusMayBeStale && $0.agentState == .running }
        let state: AgentState = attention.contains(where: { $0.agentState == .error }) ? .error
            : attention.contains(where: { $0.agentState == .waiting }) ? .waiting
            : !attention.isEmpty ? .ready : !running.isEmpty ? .running : .unknown
        let count = attention.isEmpty ? running.count : attention.count
        let width: CGFloat = count > 0 ? 32 : 19
        let point = NSPoint(x: coreCentre.x + 36, y: coreCentre.y + 43)
        let rect = NSRect(x: point.x - width / 2, y: point.y - 9, width: width, height: 18)
        let plate = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        theme.background.withAlphaComponent(0.94).setFill(); plate.fill()
        theme.border.withAlphaComponent(0.32).setStroke(); plate.lineWidth = 0.6; plate.stroke()
        drawStateGlyph(state, at: NSPoint(x: point.x + (count > 0 ? -6 : 0), y: point.y), theme: theme, connected: true)
        if count > 0 { drawText(String(count), at: NSPoint(x: point.x + 7.5, y: point.y), size: 10, color: theme.text, width: 14, bold: true) }
    }

    private func drawStateGlyph(_ state: AgentState, at point: NSPoint, theme: ThemeDefinition, connected: Bool) {
        let actual: AgentState = connected ? state : .unknown
        let color: NSColor
        switch actual { case .running: color = theme.running; case .waiting: color = theme.waiting; case .ready: color = theme.ready; case .error: color = theme.error; case .unknown: color = theme.unknown }
        switch actual {
        case .running:
            for x in [-3.5, 0, 3.5] { color.withAlphaComponent(0.65).setFill(); NSBezierPath(ovalIn: NSRect(x: point.x + x - 1, y: point.y - 1, width: 2, height: 2)).fill() }
        case .waiting:
            drawLine(from: NSPoint(x: point.x - 2, y: point.y - 3), to: NSPoint(x: point.x - 2, y: point.y + 3), color: color, width: 1.5)
            drawLine(from: NSPoint(x: point.x + 2, y: point.y - 3), to: NSPoint(x: point.x + 2, y: point.y + 3), color: color, width: 1.5)
        case .ready:
            drawLine(from: NSPoint(x: point.x - 3.6, y: point.y), to: NSPoint(x: point.x - 1.1, y: point.y + 2.5), color: color, width: 1.55)
            drawLine(from: NSPoint(x: point.x - 1.1, y: point.y + 2.5), to: NSPoint(x: point.x + 3.7, y: point.y - 3), color: color, width: 1.55)
        case .error:
            drawLine(from: NSPoint(x: point.x, y: point.y - 3.7), to: NSPoint(x: point.x, y: point.y + 0.6), color: color, width: 1.6)
            color.setFill(); NSBezierPath(ovalIn: NSRect(x: point.x - 0.9, y: point.y + 2.4, width: 1.8, height: 1.8)).fill()
        case .unknown:
            let diamond = NSBezierPath()
            diamond.move(to: NSPoint(x: point.x - 3, y: point.y)); diamond.line(to: NSPoint(x: point.x, y: point.y - 3))
            diamond.line(to: NSPoint(x: point.x + 3, y: point.y)); diamond.line(to: NSPoint(x: point.x, y: point.y + 3)); diamond.close()
            color.withAlphaComponent(0.65).setStroke(); diamond.lineWidth = 1; diamond.stroke()
        }
    }

    private func drawPedestal(in rect: NSRect, theme: ThemeDefinition, opacity: Double) {
        let mid = rect.midY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: mid - 1)); path.line(to: NSPoint(x: rect.minX + 3, y: mid - 1))
        path.line(to: NSPoint(x: rect.minX + 3, y: mid + 1)); path.line(to: NSPoint(x: rect.minX + 7, y: mid + 1))
        path.line(to: NSPoint(x: rect.minX + 9, y: mid + 3)); path.line(to: NSPoint(x: rect.maxX - 9, y: mid + 3))
        path.line(to: NSPoint(x: rect.maxX - 7, y: mid + 1)); path.line(to: NSPoint(x: rect.maxX - 3, y: mid + 1))
        path.line(to: NSPoint(x: rect.maxX - 3, y: mid - 1)); path.line(to: NSPoint(x: rect.maxX, y: mid - 1))
        theme.accent.withAlphaComponent(opacity).setStroke(); path.lineWidth = 0.9; path.stroke()
    }

    private func drawArrow(at point: NSPoint, color: NSColor) {
        drawLine(from: NSPoint(x: point.x, y: point.y - 5), to: NSPoint(x: point.x, y: point.y + 3), color: color, width: 1.1)
        drawLine(from: NSPoint(x: point.x - 4, y: point.y), to: NSPoint(x: point.x, y: point.y + 4), color: color, width: 1.1)
        drawLine(from: NSPoint(x: point.x, y: point.y + 4), to: NSPoint(x: point.x + 4, y: point.y), color: color, width: 1.1)
    }

    private func drawImage(_ image: NSImage?, in rect: NSRect, alpha: Double) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let fit = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = NSSize(width: image.size.width * fit, height: image.size.height * fit)
        let fitted = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    private func drawText(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor, width: CGFloat, bold: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let height = ceil(font.ascender - font.descender + font.leading + 2)
        (L10n.text(text) as NSString).draw(in: NSRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
                               withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func drawLine(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat) {
        let path = NSBezierPath(); path.move(to: start); path.line(to: end)
        path.lineWidth = width; path.lineCapStyle = .round; color.setStroke(); path.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true); updateHover(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) {
        setHover(nil); removeHovered = false; dropSlot = nil
        needsDisplay = true
        onHoverChanged?(false)
    }
    override func mouseMoved(with event: NSEvent) { updateHover(convert(event.locationInWindow, from: nil)) }

    private func isCore(_ point: NSPoint) -> Bool {
        abs(point.x - coreCentre.x) <= coreExtent / 2 && abs(point.y - coreCentre.y) <= coreExtent / 2
    }

    private func hitSlot(_ point: NSPoint) -> Int? {
        guard expanded else { return nil }
        for slot in controller.workspace.slots {
            let p = slotPoint(slot.number)
            let side: CGFloat = slot.window == nil ? max(34, 42 * factor) : 88 * factor
            let height: CGFloat = slot.window == nil ? side : 78 * factor
            if abs(point.x - p.x) <= side / 2 + 3 && abs(point.y - p.y) <= height / 2 + 3 { return slot.number }
        }
        return nil
    }

    private func updateHover(_ point: NSPoint) {
        let removal = hitRemove(point)
        let oldRemoval = removeHovered
        removeHovered = removal != nil
        setHover(removal ?? hitSlot(point))
        if removeHovered != oldRemoval { updateTooltip(); needsDisplay = true }
    }
    private func setHover(_ number: Int?) { if number != hoveredSlot { hoveredSlot = number; updateTooltip(); needsDisplay = true } }

    private func updateTooltip() {
        if let number = hoveredSlot, let slot = controller.workspace.slots.first(where: { $0.number == number }) {
            if removeHovered { toolTip = L10n.text("移出管理 · 保留原窗口"); return }
            let status = slot.statusMayBeStale ? L10n.text("状态较久未更新，请查看终端") : statusLabel(slot.agentState)
            toolTip = slot.window == nil ? L10n.text("\(number) 号槽位 · 点击添加窗口") : L10n.text("\(number) · \(slot.displayName)\n\(controller.isDemo ? L10n.text("示例任务，不连接真实窗口") : controller.isConnected(slot) ? L10n.text("窗口已连接") : L10n.text("窗口已断开")) · \(status)\n拖到其他槽位排序 · 拖出轮盘移出管理")
        } else {
            toolTip = appearanceModel.theme.dockTitle + L10n.text("\n悬停展开 · 长按拖动 · 右键管理")
        }
    }

    private func statusLabel(_ state: AgentState) -> String {
        switch state { case .unknown: return L10n.text("状态未知"); case .running: return L10n.text("正在执行"); case .waiting: return L10n.text("等待处理"); case .ready: return L10n.text("本轮已回复"); case .error: return L10n.text("发生错误") }
    }

    func aim(at screenPoint: NSPoint) -> Int? {
        guard expanded, let window else { return nil }
        let point = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        // The core is the cancellation target even when its equipment orbit
        // has fitted inward and now has a different centre.
        guard !isCore(point) else { setHover(nil); return nil }
        let dx = point.x - centre.x, dy = point.y - centre.y
        let distance = hypot(dx, dy)
        guard distance >= 92, distance <= radius + 90 else { setHover(nil); return nil }
        let angle = (atan2(dx, -dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        var number = Int(((angle + 20).truncatingRemainder(dividingBy: 360)) / 40) + 1
        if let old = hoveredSlot {
            let delta = abs((angle - CGFloat(old - 1) * 40 + 540).truncatingRemainder(dividingBy: 360) - 180)
            if delta < 23 { number = old }
        }
        setHover(number)
        guard let slot = controller.workspace.slots.first(where: { $0.number == number }), slot.window != nil,
              controller.isDemo || controller.isConnected(slot) else { return nil }
        return number
    }

    func clearAim() { setHover(nil) }

    override func mouseDown(with event: NSEvent) {
        cancelSlotInteraction()
        downPoint = convert(event.locationInWindow, from: nil)
        downScreenPoint = screenPoint(for: event)
        let removal = hitRemove(downPoint)
        pressedCore = removal == nil && isCore(downPoint)
        if pressedCore { onCorePressChanged?(true) }
        didDragCore = false
        if let number = removal,
           let slot = controller.workspace.slots.first(where: { $0.number == number && $0.window != nil }) {
            slotGesture = WheelSlotGesture(source: number, taskID: slot.id, origin: downPoint, removal: true)
        } else if !pressedCore, let number = hitSlot(downPoint),
                  let slot = controller.workspace.slots.first(where: { $0.number == number }) {
            slotGesture = WheelSlotGesture(source: number, taskID: slot.window == nil ? nil : slot.id, origin: downPoint)
        }
        if slotGesture != nil { onSlotInteractionChanged?(true) }
    }

    override func mouseDragged(with event: NSEvent) {
        if var gesture = slotGesture {
            let point = convert(event.locationInWindow, from: nil)
            gesture.move(to: point)
            slotGesture = gesture
            if gesture.sorting {
                slotDragPoint = point
                let target = hitSlot(point)
                dropSlot = target == gesture.source ? nil : target
                setHover(dropSlot)
                removeHovered = false
            } else { updateHover(point) }
            needsDisplay = true
            return
        }
        guard pressedCore else { updateHover(convert(event.locationInWindow, from: nil)); return }
        let point = screenPoint(for: event)
        if !didDragCore, hypot(point.x - downScreenPoint.x, point.y - downScreenPoint.y) > 4 {
            didDragCore = true
            onCoreDragBegan?(downScreenPoint)
        }
        if didDragCore { onCoreDragMoved?(point) }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            if pressedCore { onCorePressChanged?(false) }
            pressedCore = false; didDragCore = false
        }
        if didDragCore { onCoreDragEnded?(); return }
        let point = convert(event.locationInWindow, from: nil)
        if let gesture = slotGesture {
            let action = gesture.release(hitSlot: hitSlot(point), removeSlot: hitRemove(point),
                                         outside: WheelSlotGesture.isRemovalDrop(point, bounds: bounds))
            cancelSlotInteraction()
            if let taskID = gesture.taskID,
               !controller.workspace.slots.contains(where: { $0.number == gesture.source && $0.id == taskID && $0.window != nil }) { return }
            switch action {
            case .none: break
            case .activate(let number):
                if let taskID = gesture.taskID { lastEquippedTaskID = taskID }
                onSlotClick?(number)
            case .reorder(let from, let to, let taskID): _ = onSlotReorder?(from, to, taskID)
            case .remove(let number, let taskID): onSlotRemove?(number, taskID)
            }
        } else if pressedCore && isCore(point) { onCoreClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelSlotInteraction()
        updateHover(convert(event.locationInWindow, from: nil))
        onContextMenu?(event)
    }

    func cancelSlotInteraction() {
        let wasActive = isSlotManipulating
        slotGesture = nil; incomingTaskID = nil; dropSlot = nil; slotDragPoint = nil; removeHovered = false
        needsDisplay = true
        if wasActive { onSlotInteractionChanged?(false) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let data = sender.draggingPasteboard.data(forType: TaskDragPayload.pasteboardType),
              let taskID = TaskDragPayload.decode(data),
              controller.workspace.slots.contains(where: { $0.id == taskID && $0.window != nil }) else { return [] }
        cancelSlotInteraction()
        incomingTaskID = taskID
        onSlotInteractionChanged?(true)
        return updateIncomingDrop(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateIncomingDrop(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) { cancelSlotInteraction(); setHover(nil) }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        updateIncomingDrop(sender) == .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let taskID = incomingTaskID,
              let source = controller.workspace.slots.first(where: { $0.id == taskID && $0.window != nil }),
              let target = incomingDropTarget(sender), target != source.number else {
            cancelSlotInteraction()
            return false
        }
        cancelSlotInteraction()
        return onSlotReorder?(source.number, target, taskID) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { cancelSlotInteraction() }

    private func incomingDropTarget(_ sender: NSDraggingInfo) -> Int? {
        // The panel may expand during draggingEntered, changing window-local
        // coordinates. The live screen point remains stable across that resize.
        guard let window else { return nil }
        return hitSlot(convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }

    private func updateIncomingDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let taskID = incomingTaskID,
              let source = controller.workspace.slots.first(where: { $0.id == taskID && $0.window != nil }) else { return [] }
        let target = incomingDropTarget(sender)
        dropSlot = target == source.number ? nil : target
        setHover(dropSlot)
        needsDisplay = true
        return dropSlot == nil ? [] : .move
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    deinit { revealTimer?.invalidate() }
}

/// A slot press never shares state with the core/window drag. The threshold is
/// the original Windows 9-point sorting gesture; once crossed it cannot click.
struct WheelSlotGesture {
    enum Action: Equatable {
        case none
        case activate(Int)
        case reorder(Int, Int, UUID)
        case remove(Int, UUID)
    }

    let source: Int
    let taskID: UUID?
    let origin: NSPoint
    let removal: Bool
    private(set) var sorting = false

    init(source: Int, taskID: UUID?, origin: NSPoint, removal: Bool = false) {
        self.source = source; self.taskID = taskID; self.origin = origin; self.removal = removal
    }

    mutating func move(to point: NSPoint) {
        if !removal, taskID != nil, hypot(point.x - origin.x, point.y - origin.y) >= 9 { sorting = true }
    }

    func release(hitSlot: Int?, removeSlot: Int?, outside: Bool) -> Action {
        guard (1...9).contains(source) else { return .none }
        if removal {
            guard removeSlot == source, let taskID else { return .none }
            return .remove(source, taskID)
        }
        if sorting, let taskID {
            if let target = hitSlot, (1...9).contains(target) {
                return target == source ? .none : .reorder(source, target, taskID)
            }
            return outside ? .remove(source, taskID) : .none
        }
        return hitSlot == source ? .activate(source) : .none
    }

    static func isRemovalDrop(_ point: NSPoint, bounds: NSRect) -> Bool {
        point.x < bounds.minX - 28 || point.x > bounds.maxX + 28 ||
            point.y < bounds.minY - 28 || point.y > bounds.maxY + 28
    }

    static func removeTargetSize(physicalSize: NSSize, logicalSize: NSSize) -> NSSize {
        func side(physical: CGFloat, logical: CGFloat) -> CGFloat {
            guard physical.isFinite, logical.isFinite, physical > 0, logical > 0 else { return 22 }
            return max(22, 22 * (logical / physical))
        }
        return NSSize(width: side(physical: physicalSize.width, logical: logicalSize.width),
                      height: side(physical: physicalSize.height, logical: logicalSize.height))
    }

    static func hitsRemove(_ point: NSPoint, centre: NSPoint, targetSize: NSSize = NSSize(width: 22, height: 22)) -> Bool {
        guard point.x.isFinite, point.y.isFinite, centre.x.isFinite, centre.y.isFinite,
              targetSize.width.isFinite, targetSize.height.isFinite, targetSize.width > 0, targetSize.height > 0 else { return false }
        return hypot((point.x - centre.x) / (targetSize.width / 2),
                     (point.y - centre.y) / (targetSize.height / 2)) <= 1
    }
}
