import AppKit
import Carbon

private let wheelHotKeySignature: OSType = 0x4F565748 // OVWH

private func wheelHotKeyCallback(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard result == noErr, identifier.signature == wheelHotKeySignature else { return OSStatus(eventNotHandledErr) }
    let service = Unmanaged<WheelHotKeyService>.fromOpaque(context).takeUnretainedValue()
    let kind = GetEventKind(event)
    Task { @MainActor [weak service] in service?.handle(Int(identifier.id), kind: kind) }
    return noErr
}

/// Receives only explicitly registered shortcuts. It does not monitor arbitrary
/// keyboard events or request Input Monitoring permission.
@MainActor
final class WheelHotKeyService {
    // Compatibility aliases for callers explicitly using the original scheme.
    // Dynamic UI and registration use the instance's scheme bindings below.
    static var aimShortcut: String { ShortcutScheme.controlOption.binding(for: .aim)!.label }
    static var toggleShortcut: String { ShortcutScheme.controlOption.binding(for: .toggleVisibility)!.label }

    /// Injectable Carbon operations allow conflict handling to be verified
    /// without reserving actual desktop shortcuts.
    struct RegistrationFunctions {
        var installHandler: (UnsafeMutableRawPointer, inout EventHandlerRef?) -> OSStatus
        var removeHandler: (EventHandlerRef) -> Void
        var registerKey: (Int, UInt32, UInt32) -> (OSStatus, EventHotKeyRef?)
        var unregisterKey: (EventHotKeyRef) -> Void

        static let system = RegistrationFunctions(
            installHandler: { context, handler in
                var types = [
                    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
                ]
                return InstallEventHandler(GetApplicationEventTarget(), wheelHotKeyCallback, types.count, &types,
                    context, &handler)
            },
            removeHandler: { RemoveEventHandler($0) },
            registerKey: { code, modifiers, id in
                var reference: EventHotKeyRef?
                let result = RegisterEventHotKey(UInt32(code), modifiers,
                    EventHotKeyID(signature: wheelHotKeySignature, id: id), GetApplicationEventTarget(),
                    UInt32(kEventHotKeyExclusive), &reference)
                return (result, reference)
            },
            unregisterKey: { UnregisterEventHotKey($0) }
        )
    }

    private(set) var warnings: [String] = []
    /// Permanent shortcuts that actually registered; temporary Esc captures
    /// are managed separately for the duration of a held wheel.
    private(set) var registeredShortcuts = Set<String>()
    private var registeredActions = Set<ShortcutAction>()
    var canAim: Bool { isRegistered(.aim) }
    var canToggleVisibility: Bool { isRegistered(.toggleVisibility) }
    var canOpenInventory: Bool { isRegistered(.inventory) }

    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private var escapeReferences: [EventHotKeyRef] = []
    private var escapeIdentifiers = Set<Int>()
    private var held = false
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onToggle: () -> Void
    private let onCancel: () -> Void
    private let onInventory: () -> Void
    private let registration: RegistrationFunctions
    let scheme: ShortcutScheme
    let configuration: ShortcutConfiguration

    init(configuration: ShortcutConfiguration? = nil, scheme: ShortcutScheme = .controlOption,
         onPress: @escaping () -> Void, onRelease: @escaping () -> Void,
         onToggle: @escaping () -> Void, onCancel: @escaping () -> Void,
         registration: RegistrationFunctions = .system,
         onInventory: @escaping () -> Void = {}) {
        let effective = configuration ?? ShortcutConfiguration(base: scheme)
        self.configuration = effective
        self.scheme = effective.base
        self.onPress = onPress
        self.onRelease = onRelease
        self.onToggle = onToggle
        self.onCancel = onCancel
        self.onInventory = onInventory
        self.registration = registration
    }

    func register() throws {
        guard handler == nil else { return }
        warnings.removeAll()
        try configuration.validate()
        guard !configuration.wheelBindings.isEmpty else { return }
        let result = registration.installHandler(Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr, handler != nil else {
            if let handler { registration.removeHandler(handler) }
            handler = nil
            throw WheelHotKeyError.registration("轮盘事件回调", result == noErr ? OSStatus(paramErr) : result)
        }
        for binding in configuration.wheelBindings {
            let id: UInt32
            switch binding.action {
            case .aim: id = 1
            case .toggleVisibility: id = 2
            case .inventory: id = 5
            default: continue
            }
            if let reference = registerKey(binding.keyCode, modifiers: binding.modifiers, id: id, label: binding.label) {
                references.append(reference)
                registeredShortcuts.insert(binding.label)
                registeredActions.insert(binding.action)
            }
        }
    }

    /// Esc is captured only for the duration of the held wheel. Both forms let a
    /// user cancel before or after releasing the modifier keys, without a key tap.
    func beginEscapeCapture() throws {
        guard handler != nil, canAim, escapeReferences.isEmpty,
              let cancel = configuration.binding(for: .cancelModified) else { return }
        for (modifiers, id, label) in [(cancel.modifiers, UInt32(3), cancel.label), (0, UInt32(4), "Esc")] {
            if let reference = registerKey(kVK_Escape, modifiers: modifiers, id: id, label: label) {
                escapeReferences.append(reference)
                escapeIdentifiers.insert(Int(id))
            }
        }
    }

    func endEscapeCapture() {
        for reference in escapeReferences { registration.unregisterKey(reference) }
        escapeReferences.removeAll()
        escapeIdentifiers.removeAll()
    }

    func unregister() {
        held = false
        endEscapeCapture()
        for reference in references { registration.unregisterKey(reference) }
        references.removeAll()
        registeredShortcuts.removeAll()
        registeredActions.removeAll()
        if let handler { registration.removeHandler(handler) }
        handler = nil
    }

    private func registerKey(_ code: Int, modifiers: UInt32, id: UInt32, label: String) -> EventHotKeyRef? {
        let (result, reference) = registration.registerKey(code, modifiers, id)
        guard result == noErr, let reference else {
            if let reference { registration.unregisterKey(reference) }
            let status = result == noErr ? OSStatus(paramErr) : result
            let warning = WheelHotKeyError.registration(label, status).localizedDescription
            if !warnings.contains(warning) { warnings.append(warning) }
            return nil
        }
        return reference
    }

    private func isRegistered(_ action: ShortcutAction) -> Bool {
        registeredActions.contains(action)
    }

    func handle(_ identifier: Int, kind: UInt32) {
        guard handler != nil else { return }
        if identifier == 1, canAim {
            if kind == UInt32(kEventHotKeyPressed), !held { held = true; onPress() }
            else if kind == UInt32(kEventHotKeyReleased), held { held = false; onRelease() }
        } else if identifier == 2, canToggleVisibility, kind == UInt32(kEventHotKeyPressed) {
            onToggle()
        } else if identifier == 5, canOpenInventory, kind == UInt32(kEventHotKeyPressed) {
            onInventory()
        } else if escapeIdentifiers.contains(identifier), kind == UInt32(kEventHotKeyPressed), held {
            onCancel()
        }
    }

    deinit {
        for reference in escapeReferences + references { registration.unregisterKey(reference) }
        if let handler { registration.removeHandler(handler) }
    }
}

private enum WheelHotKeyError: LocalizedError {
    case registration(String, OSStatus)
    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .registration(let label, let status):
                return "\(label) 被系统或其他程序占用（\(status)）。仍可使用悬浮入口和右键菜单。"
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
