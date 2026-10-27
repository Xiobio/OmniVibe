import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

struct TaskScrollSample: Equatable, Sendable {
    var deltaY: Double
    var deltaX: Double = 0
    var continuous = false
    var momentum = false
    var modifiers: UInt32
    var at: TimeInterval
}

struct ScrollSwitchAccumulator {
    enum Decision: Equatable { case pass, consume(Int?) }
    private var accumulated = 0.0
    private var lastEvent: TimeInterval?
    private var lastSwitch: TimeInterval?

    mutating func reset() { accumulated = 0; lastEvent = nil; lastSwitch = nil }

    mutating func process(_ sample: TaskScrollSample, matches: Bool, suspended: Bool) -> Decision {
        guard matches, !suspended, sample.at.isFinite, sample.deltaY.isFinite, sample.deltaX.isFinite else {
            reset(); return .pass
        }
        guard sample.deltaY != 0, abs(sample.deltaY) > abs(sample.deltaX) else {
            accumulated = 0; lastEvent = nil; return .pass
        }
        if sample.momentum { accumulated = 0; lastEvent = nil; return .consume(nil) }
        if let lastEvent, sample.at - lastEvent > 0.22 || sample.at < lastEvent { accumulated = 0 }
        lastEvent = sample.at
        if let lastSwitch, sample.at - lastSwitch < 0.24 { return .consume(nil) }
        if sample.continuous {
            if accumulated * sample.deltaY < 0 { accumulated = 0 }
            accumulated += sample.deltaY
            guard abs(accumulated) >= 24 else { return .consume(nil) }
        }
        accumulated = 0
        lastSwitch = sample.at
        return .consume(sample.deltaY > 0 ? -1 : 1)
    }
}

struct TaskScrollPermissions: Equatable, Sendable {
    let accessibility: Bool
    let listenEvents: Bool
}

protocol TaskScrollSwitchBackend: AnyObject, Sendable {
    var permissions: TaskScrollPermissions { get }
    func start(handler: @escaping @Sendable (TaskScrollSample) -> Bool, onDisabled: @escaping @Sendable () -> Void) -> Bool
    func stop()
}

private final class ScrollSwitchFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var accumulator = ScrollSwitchAccumulator()
    private var modifiers: UInt32 = 0
    private var suspended = true
    private var running = false
    private var generation: UInt64 = 0
    private var registration: UInt64 = 0

    func configure(_ modifiers: UInt32) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; registration &+= 1
        self.modifiers = modifiers; suspended = false; running = true; accumulator.reset()
        return registration
    }
    func stop() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; registration &+= 1; running = false; suspended = true; accumulator.reset()
    }
    func suspend(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        if suspended != value { generation &+= 1; accumulator.reset() }
        suspended = value
    }
    func process(_ sample: TaskScrollSample) -> (ScrollSwitchAccumulator.Decision, UInt64) {
        lock.lock(); defer { lock.unlock() }
        let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        return (accumulator.process(sample, matches: (sample.modifiers & supported) == modifiers,
                                    suspended: suspended || !running), generation)
    }
    func isCurrent(_ ticket: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == ticket && running && !suspended
    }
    func disable(_ ticket: UInt64) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        guard registration == ticket, running else { return nil }
        generation &+= 1; running = false; suspended = true; accumulator.reset()
        return generation
    }
    func isDisabled(_ ticket: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == ticket && !running
    }
}

@MainActor
final class TaskScrollSwitchService {
    private let backend: any TaskScrollSwitchBackend
    private let onSwitch: (Int) -> Void
    private let onWarning: (String) -> Void
    private let filter = ScrollSwitchFilter()
    private(set) var isRunning = false
    private(set) var warnings: [String] = []

    init(onSwitch: @escaping (Int) -> Void, onWarning: @escaping (String) -> Void = { _ in },
         backend: (any TaskScrollSwitchBackend)? = nil) {
        self.onSwitch = onSwitch; self.onWarning = onWarning
        self.backend = backend ?? CGTaskScrollSwitchBackend()
    }

    @discardableResult
    func start(modifiers: UInt32) -> [String] {
        stop()
        warnings = []
        let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let modifiers = modifiers & supported
        guard modifiers != 0 else { warnings = ["滚轮切换需要至少一个修饰键。"]; return warnings }
        let access = backend.permissions
        guard access.accessibility, access.listenEvents else {
            if !access.accessibility { warnings.append("滚轮切换未启用：请先为 OmniVibe 开启辅助功能权限。") }
            if !access.listenEvents { warnings.append("滚轮切换未启用：请在系统设置的输入监控中允许 OmniVibe，然后重新注册。") }
            return warnings
        }
        let ticket = filter.configure(modifiers)
        isRunning = backend.start(handler: { [weak self] sample in self?.handle(sample) ?? false }, onDisabled: { [weak self] in
            guard let self, let disabled = self.filter.disable(ticket) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.filter.isDisabled(disabled) else { return }
                self.isRunning = false
                let message = "滚轮切换已被系统停用，请重新检查权限并重新注册；普通滚动保持可用。"
                self.warnings = [message]
                self.onWarning(message)
            }
        })
        if !isRunning { filter.stop(); backend.stop(); warnings = ["无法注册滚轮切换，请检查辅助功能和输入监控权限后重试。"] }
        return warnings
    }

    func setSuspended(_ value: Bool) { filter.suspend(value) }

    func stop() { isRunning = false; filter.stop(); backend.stop() }

    nonisolated private func handle(_ sample: TaskScrollSample) -> Bool {
        let (decision, ticket) = filter.process(sample)
        switch decision {
        case .pass: return false
        case .consume(let direction):
            // Leave the event-tap callback before activation/AX work. Only one
            // throttled task is submitted per deliberate wheel/trackpad step.
            if let direction { Task { @MainActor [weak self] in
                guard let self, self.filter.isCurrent(ticket), self.isRunning else { return }
                self.onSwitch(direction)
            } }
            return true
        }
    }

    deinit { filter.stop(); backend.stop() }
}

private func taskScrollTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType,
                                   _ event: CGEvent, _ context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context else { return .passUnretained(event) }
    let state = Unmanaged<TaskScrollTapContext>.fromOpaque(context).takeUnretainedValue()
    guard let backend = state.backend else { return .passUnretained(event) }
    let consumed = backend.handle(type, event: event, generation: state.generation)
    return consumed ? nil : .passUnretained(event)
}

private final class TaskScrollTapContext: @unchecked Sendable {
    weak var backend: CGTaskScrollSwitchBackend?
    let generation: UInt64
    init(backend: CGTaskScrollSwitchBackend, generation: UInt64) { self.backend = backend; self.generation = generation }
}

private final class CGTaskScrollSwitchBackend: TaskScrollSwitchBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private var generation: UInt64 = 0
    private var context: TaskScrollTapContext?
    private var handler: (@Sendable (TaskScrollSample) -> Bool)?
    private var onDisabled: (@Sendable () -> Void)?
    var permissions: TaskScrollPermissions {
        TaskScrollPermissions(accessibility: AXIsProcessTrusted(), listenEvents: CGPreflightListenEventAccess())
    }

    func start(handler: @escaping @Sendable (TaskScrollSample) -> Bool, onDisabled: @escaping @Sendable () -> Void) -> Bool {
        stop()
        lock.lock()
        let ticket = generation
        lock.unlock()
        let context = TaskScrollTapContext(backend: self, generation: ticket)
        // Only scrollWheel: no key, mouse-button, text or event-posting APIs.
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: taskScrollTapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        lock.lock()
        self.tap = tap; self.source = source; self.context = context; self.handler = handler; self.onDisabled = onDisabled
        lock.unlock()
        let worker = Thread { [weak self, context] in
            withExtendedLifetime(context) {
                guard let self else { return }
                let loop = CFRunLoopGetCurrent()
                self.lock.lock()
                let valid = self.generation == ticket && self.tap != nil
                if valid { self.loop = loop }
                self.lock.unlock()
                guard valid else { return }
                CFRunLoopAddSource(loop, source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                CFRunLoopRun()
                CFRunLoopRemoveSource(loop, source, .commonModes)
                self.lock.lock()
                if self.generation == ticket { self.loop = nil }
                self.lock.unlock()
            }
        }
        worker.name = "OmniVibe scroll switch"
        worker.qualityOfService = .userInteractive
        worker.start()
        return true
    }

    func stop() {
        _ = stop(expectedGeneration: nil)
    }

    @discardableResult
    private func stop(expectedGeneration: UInt64?) -> Bool {
        lock.lock()
        if let expectedGeneration, generation != expectedGeneration { lock.unlock(); return false }
        generation &+= 1
        let tap = self.tap, source = self.source, loop = self.loop
        self.tap = nil; self.source = nil; self.loop = nil; context = nil; handler = nil; onDisabled = nil
        lock.unlock()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopSourceInvalidate(source) }
        if let loop { CFRunLoopStop(loop); CFRunLoopWakeUp(loop) }
        return true
    }

    func handle(_ type: CGEventType, event: CGEvent, generation expectedGeneration: UInt64) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let callback = generation == expectedGeneration ? onDisabled : nil
            lock.unlock()
            if stop(expectedGeneration: expectedGeneration) { callback?() }
            return false
        }
        guard type == .scrollWheel else { return false }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        var modifiers: UInt32 = 0
        if event.flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if event.flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if event.flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if event.flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        let y = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let x = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        lock.lock()
        let handler = generation == expectedGeneration ? self.handler : nil
        lock.unlock()
        return handler?(TaskScrollSample(deltaY: y, deltaX: x, continuous: continuous,
            momentum: event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0,
            modifiers: modifiers, at: ProcessInfo.processInfo.systemUptime)) ?? false
    }

    deinit { stop() }
}
