import AppKit
import Carbon

private let omniVibeHotKeySignature: OSType = 0x4F564D43 // OVMC

private func omniVibeHotKeyCallback(
    _ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let result = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
    )
    guard result == noErr, identifier.signature == omniVibeHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let service = Unmanaged<HotKeyService>.fromOpaque(context).takeUnretainedValue()
    let number = Int(identifier.id)
    Task { @MainActor [weak service] in service?.handle(number) }
    return noErr
}

/// Registers only these explicit key combinations. It does not monitor or record
/// general keyboard input, and it does not require Input Monitoring permission.
@MainActor
final class HotKeyService {
    /// Injectable operations keep conflict tests from reserving desktop shortcuts.
    struct RegistrationFunctions {
        var installHandler: (UnsafeMutableRawPointer, inout EventHandlerRef?) -> OSStatus
        var removeHandler: (EventHandlerRef) -> Void
        var registerKey: (Int, UInt32, UInt32) -> (OSStatus, EventHotKeyRef?)
        var unregisterKey: (EventHotKeyRef) -> Void

        static let system = RegistrationFunctions(
            installHandler: { context, handler in
                var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
                return InstallEventHandler(
                    GetApplicationEventTarget(), omniVibeHotKeyCallback, 1, &eventType, context, &handler
                )
            },
            removeHandler: { RemoveEventHandler($0) },
            registerKey: { code, modifiers, id in
                var reference: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    UInt32(code), modifiers,
                    EventHotKeyID(signature: omniVibeHotKeySignature, id: id),
                    GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reference
                )
                return (status, reference)
            },
            unregisterKey: { UnregisterEventHotKey($0) }
        )
    }

    private(set) var warnings: [String] = []
    var registeredSlots: Set<Int> { Set(references.keys.filter { (1...9).contains($0) }) }
    var arrangementRegistered: Bool { references[0] != nil }

    private var handler: EventHandlerRef?
    private var references: [Int: EventHotKeyRef] = [:]
    private let onSlot: (Int) -> Void
    private let onArrange: () -> Void
    private let registration: RegistrationFunctions
    let scheme: ShortcutScheme
    let configuration: ShortcutConfiguration

    init(configuration: ShortcutConfiguration? = nil, scheme: ShortcutScheme = .controlOption,
         onSlot: @escaping (Int) -> Void, onArrange: @escaping () -> Void,
         registration: RegistrationFunctions = .system) {
        let effective = configuration ?? ShortcutConfiguration(base: scheme)
        self.configuration = effective
        self.scheme = effective.base
        self.onSlot = onSlot
        self.onArrange = onArrange
        self.registration = registration
    }

    func register() throws {
        warnings.removeAll()
        try configuration.validate()
        // Inventory-first has no global task keys and needs no Carbon handler.
        guard !configuration.taskBindings.isEmpty else { return }
        if handler == nil {
            let installed = registration.installHandler(Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard installed == noErr, handler != nil else {
                if let handler { registration.removeHandler(handler) }
                handler = nil
                throw HotKeyError.registration(label: nil, status: installed == noErr ? OSStatus(paramErr) : installed)
            }
        }

        for binding in configuration.taskBindings {
            let number: Int
            switch binding.action {
            case .slot(let slot): number = slot
            case .arrange: number = 0
            default: continue
            }
            guard references[number] == nil else { continue }
            let (registered, reference) = registration.registerKey(binding.keyCode, binding.modifiers, UInt32(number))
            guard registered == noErr, let reference else {
                if let reference { registration.unregisterKey(reference) }
                let status = registered == noErr ? OSStatus(paramErr) : registered
                warnings.append(HotKeyError.registration(label: binding.label, status: status).localizedDescription)
                continue
            }
            references[number] = reference
        }
    }

    func unregister() {
        for reference in references.values { registration.unregisterKey(reference) }
        references.removeAll()
        warnings.removeAll()
        if let handler { registration.removeHandler(handler) }
        handler = nil
    }

    func handle(_ number: Int) {
        guard handler != nil, references[number] != nil else { return }
        if number == 0 { onArrange() }
        else if (1...9).contains(number) { onSlot(number) }
    }

    deinit {
        for reference in references.values { registration.unregisterKey(reference) }
        if let handler { registration.removeHandler(handler) }
    }
}

enum HotKeyError: LocalizedError {
    case registration(label: String?, status: OSStatus)

    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .registration(let label, let status):
                if let label {
                    return "无法注册 \(label)（系统错误 \(status)）。请关闭占用该组合的快捷键后重试。"
                }
                return "无法启用全局快捷键（系统错误 \(status)）。任务按钮仍可使用。"
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
