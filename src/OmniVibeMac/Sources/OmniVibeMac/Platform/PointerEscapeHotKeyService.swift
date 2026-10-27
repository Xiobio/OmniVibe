import AppKit
import Carbon

private let pointerEscapeSignature: OSType = 0x4F565045 // OVPE

private func pointerEscapeCallback(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard result == noErr, identifier.signature == pointerEscapeSignature else { return OSStatus(eventNotHandledErr) }
    let service = Unmanaged<PointerEscapeHotKeyService>.fromOpaque(context).takeUnretainedValue()
    let kind = GetEventKind(event)
    // Application event-target handlers run on the main event loop. Cancel in
    // this event, before a following mouse-up can commit an outside removal.
    MainActor.assumeIsolated { service.handle(Int(identifier.id), kind: kind) }
    return noErr
}

/// Temporary, explicitly registered Escape combinations for a pointer gesture.
/// No event tap, arbitrary key observer, or Input Monitoring permission is used.
@MainActor
final class PointerEscapeHotKeyService {
    struct RegistrationFunctions {
        var installHandler: (UnsafeMutableRawPointer, inout EventHandlerRef?) -> OSStatus
        var removeHandler: (EventHandlerRef) -> Void
        var registerKey: (Int, UInt32, UInt32) -> (OSStatus, EventHotKeyRef?)
        var unregisterKey: (EventHotKeyRef) -> Void

        static let system = RegistrationFunctions(
            installHandler: { context, handler in
                var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
                return InstallEventHandler(GetApplicationEventTarget(), pointerEscapeCallback, 1, &type, context, &handler)
            },
            removeHandler: { RemoveEventHandler($0) },
            registerKey: { code, modifiers, id in
                var reference: EventHotKeyRef?
                let result = RegisterEventHotKey(UInt32(code), modifiers,
                    EventHotKeyID(signature: pointerEscapeSignature, id: id), GetApplicationEventTarget(),
                    UInt32(kEventHotKeyExclusive), &reference)
                return (result, reference)
            },
            unregisterKey: { UnregisterEventHotKey($0) }
        )
    }

    private(set) var warnings: [String] = []
    private(set) var registeredModifiers = Set<UInt32>()
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private var identifiers = Set<UInt32>()
    private static var nextIdentifier: UInt32 = 1
    private var cancelled = false
    private let onCancel: () -> Void
    private let registration: RegistrationFunctions

    init(onCancel: @escaping () -> Void, registration: RegistrationFunctions = .system) {
        self.onCancel = onCancel
        self.registration = registration
    }

    func begin(modifiers: UInt32 = 0) throws {
        guard handler == nil else { return }
        warnings.removeAll()
        cancelled = false
        let result = registration.installHandler(Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr, handler != nil else {
            if let handler { registration.removeHandler(handler) }
            handler = nil
            throw PointerEscapeError.registration("Esc 取消回调", result == noErr ? OSStatus(paramErr) : result)
        }
        let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let current = modifiers & supported
        for combination in current == 0 ? [UInt32(0)] : [UInt32(0), current] {
            let id = Self.nextIdentifier
            Self.nextIdentifier &+= 1
            if Self.nextIdentifier == 0 { Self.nextIdentifier = 1 }
            let (status, reference) = registration.registerKey(kVK_Escape, combination, id)
            guard status == noErr, let reference else {
                if let reference { registration.unregisterKey(reference) }
                warnings.append(PointerEscapeError.registration(Self.label(combination),
                    status == noErr ? OSStatus(paramErr) : status).localizedDescription)
                continue
            }
            references.append(reference)
            identifiers.insert(id)
            registeredModifiers.insert(combination)
        }
    }

    func end() {
        identifiers.removeAll()
        registeredModifiers.removeAll()
        cancelled = true
        for reference in references { registration.unregisterKey(reference) }
        references.removeAll()
        if let handler { registration.removeHandler(handler) }
        handler = nil
    }

    func handle(_ identifier: Int, kind: UInt32) {
        guard handler != nil, !cancelled, kind == UInt32(kEventHotKeyPressed),
              let id = UInt32(exactly: identifier), identifiers.contains(id) else { return }
        cancelled = true
        onCancel()
    }

    static func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    private static func label(_ modifiers: UInt32) -> String {
        var label = ""
        if modifiers & UInt32(controlKey) != 0 { label += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { label += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { label += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { label += "⌘" }
        return label + "Esc"
    }

    deinit {
        for reference in references { registration.unregisterKey(reference) }
        if let handler { registration.removeHandler(handler) }
    }
}

private enum PointerEscapeError: LocalizedError {
    case registration(String, OSStatus)

    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .registration(let key, let status):
                return "\(key) 暂不可用于取消拖动（系统错误 \(status)）。可移回原槽松开以取消。"
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}
