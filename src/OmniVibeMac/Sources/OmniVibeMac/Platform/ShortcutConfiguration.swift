import Foundation
import Carbon

/// A preset plus explicit per-action replacements or disables. Updates return
/// a validated copy, so a failed edit cannot partially change active bindings.
struct ShortcutConfiguration: Codable, Equatable, Sendable {
    enum Override: Codable, Equatable, Sendable {
        case binding(ShortcutBinding)
        case disabled
    }

    static let configurableActions: [ShortcutAction] = (1...9).map { .slot($0) }
        + [.arrange, .aim, .toggleVisibility, .inventory]

    let base: ShortcutScheme
    private(set) var overrides: [String: Override]

    init(base: ShortcutScheme) {
        self.base = base
        overrides = [:]
    }

    private init(base: ShortcutScheme, overrides: [String: Override]) {
        self.base = base
        self.overrides = overrides
    }

    var isCustomized: Bool { !overrides.isEmpty }
    var label: String { base.label + (isCustomized ? " · 自定义" : "") }
    var slotRangeLabel: String {
        overrides.keys.contains(where: { $0.hasPrefix("slot") }) ? "自定义任务快捷键" : base.slotRangeLabel
    }

    var taskBindings: [ShortcutBinding] {
        ((1...9).map { ShortcutAction.slot($0) } + [.arrange]).compactMap { binding(for: $0) }
    }

    var wheelBindings: [ShortcutBinding] {
        [ShortcutAction.aim, .toggleVisibility, .inventory].compactMap { binding(for: $0) }
    }

    func customization(for action: ShortcutAction) -> Override? { overrides[action.persistenceKey] }

    func binding(for action: ShortcutAction) -> ShortcutBinding? {
        if action == .cancelModified {
            guard let aim = binding(for: .aim) else { return nil }
            return ShortcutBinding(action: action, keyCode: kVK_Escape, modifiers: aim.modifiers,
                label: ShortcutBinding.modifierGlyphs(aim.modifiers) + "Esc")
        }
        if let override = customization(for: action) {
            switch override {
            case .binding(let binding): return binding
            case .disabled: return nil
            }
        }
        return base.binding(for: action)
    }

    func setting(_ binding: ShortcutBinding) throws -> Self {
        try Self.validateBinding(binding)
        var copy = self
        copy.overrides[binding.action.persistenceKey] = .binding(binding)
        try copy.validate()
        return copy
    }

    func disabling(_ action: ShortcutAction) throws -> Self {
        try Self.requireConfigurable(action)
        var copy = self
        copy.overrides[action.persistenceKey] = .disabled
        try copy.validate()
        return copy
    }

    func resetting(_ action: ShortcutAction) throws -> Self {
        try Self.requireConfigurable(action)
        var copy = self
        copy.overrides.removeValue(forKey: action.persistenceKey)
        try copy.validate()
        return copy
    }

    func changingBase(to scheme: ShortcutScheme, preservingOverrides: Bool = true) throws -> Self {
        let copy = Self(base: scheme, overrides: preservingOverrides ? overrides : [:])
        try copy.validate()
        return copy
    }

    func validate() throws {
        for key in overrides.keys.sorted() {
            guard let action = ShortcutAction(persistenceKey: key) else { throw ValidationError.unknownAction }
            try Self.requireConfigurable(action)
            if case .binding(let binding) = overrides[key] {
                guard binding.action == action else { throw ValidationError.actionMismatch }
                try Self.validateBinding(binding)
            }
        }
        var chords: [Chord: ShortcutBinding] = [:]
        for binding in taskBindings + wheelBindings {
            try Self.validateBinding(binding)
            let chord = Chord(keyCode: binding.keyCode, modifiers: binding.modifiers)
            if let previous = chords[chord] {
                throw ValidationError.duplicate(binding.label, previous.action.label, binding.action.label)
            }
            chords[chord] = binding
        }
    }

    fileprivate static func requireConfigurable(_ action: ShortcutAction) throws {
        guard configurableActions.contains(action) else { throw ValidationError.unknownAction }
    }

    static func validateBinding(_ binding: ShortcutBinding) throws {
        try requireConfigurable(binding.action)
        let modifiers = binding.modifiers
        let allowed = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        guard modifiers != 0 else { throw ValidationError.modifierRequired }
        guard modifiers & ~allowed == 0 else { throw ValidationError.unsupportedModifiers }
        let modifierKeys = [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option,
                            kVK_RightOption, kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function]
        guard (0...127).contains(binding.keyCode), !modifierKeys.contains(binding.keyCode) else {
            throw ValidationError.invalidKey
        }
        guard binding.keyCode != kVK_Escape else { throw ValidationError.escapeReserved }
        // Keep system quit/log-out/lock, application switching and Spotlight
        // available. Other modified letters, digits and function keys are valid.
        if modifiers & UInt32(cmdKey) != 0,
           [kVK_ANSI_Q, kVK_Tab, kVK_Space].contains(binding.keyCode) {
            throw ValidationError.systemReserved
        }
        let prefix = ShortcutBinding.modifierGlyphs(modifiers)
        guard binding.label.hasPrefix(prefix) else { throw ValidationError.invalidLabel }
        let keyName = binding.label.dropFirst(prefix.count)
        guard !keyName.isEmpty, binding.label.utf8.count <= 96,
              keyName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              !keyName.contains(where: { "⌃⌥⇧⌘".contains($0) }) else { throw ValidationError.invalidLabel }
    }

    private struct Chord: Hashable {
        let keyCode: Int
        let modifiers: UInt32
    }

    private enum CodingKeys: String, CodingKey { case base, overrides }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        base = try container.decode(ShortcutScheme.self, forKey: .base)
        overrides = try container.decodeIfPresent([String: Override].self, forKey: .overrides) ?? [:]
        try validate()
    }

    enum ValidationError: LocalizedError {
        case unknownAction, actionMismatch, modifierRequired, unsupportedModifiers, invalidKey
        case escapeReserved, systemReserved, invalidLabel
        case duplicate(String, String, String)

        var errorDescription: String? {
            let localizedSource: String? = {
                switch self {
                case .unknownAction: return "这个操作不能自定义快捷键。"
                case .actionMismatch: return "快捷键绑定的操作与配置不一致。"
                case .modifierRequired: return "请至少搭配一个修饰键：Control、Option、Shift 或 Command。"
                case .unsupportedModifiers: return "请使用 Control、Option、Shift 或 Command 修饰键。"
                case .invalidKey: return "请在修饰键之外选择一个普通键、方向键或功能键。"
                case .escapeReserved: return "Esc 保留用于取消操作，请选择其他按键。"
                case .systemReserved: return "这个组合保留给系统退出、切换应用或搜索，请选择其他组合。"
                case .invalidLabel: return "无法识别快捷键名称，请重新录制。"
                case .duplicate(let chord, let first, let second): return "“\(first)”和“\(second)”不能同时使用 \(chord)，请选择不同组合。"
                }
        }()
            return localizedSource.map { L10n.errorText($0) }
        }
    }
}
