import Foundation
import Carbon

enum ShortcutAction: Hashable, Codable, Sendable {
    case slot(Int)
    case arrange
    case aim
    case toggleVisibility
    case inventory
    case cancelModified

    var persistenceKey: String {
        switch self {
        case .slot(let number): return "slot\(number)"
        case .arrange: return "arrange"
        case .aim: return "aim"
        case .toggleVisibility: return "toggleVisibility"
        case .inventory: return "inventory"
        case .cancelModified: return "cancelModified"
        }
    }

    var label: String {
        switch self {
        case .slot(let number): return "任务 \(number)"
        case .arrange: return "排列 / 恢复窗口"
        case .aim: return "按住呼出轮盘"
        case .toggleVisibility: return "显示 / 隐藏悬浮入口"
        case .inventory: return "打开 / 关闭任务总览"
        case .cancelModified: return "取消轮盘"
        }
    }

    init?(persistenceKey: String) {
        if persistenceKey.hasPrefix("slot"), let number = Int(persistenceKey.dropFirst(4)),
           (1...9).contains(number), persistenceKey == "slot\(number)" {
            self = .slot(number)
            return
        }
        switch persistenceKey {
        case "arrange": self = .arrange
        case "aim": self = .aim
        case "toggleVisibility": self = .toggleVisibility
        case "inventory": self = .inventory
        case "cancelModified": self = .cancelModified
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let key = try container.decode(String.self)
        guard let action = Self(persistenceKey: key) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown shortcut action")
        }
        self = action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(persistenceKey)
    }
}

struct ShortcutBinding: Codable, Equatable, Sendable {
    let action: ShortcutAction
    let keyCode: Int
    /// Carbon modifier bits, rather than NSEvent.ModifierFlags raw values.
    let modifiers: UInt32
    let label: String

    /// Recording supplies an unmodified key name; modifier glyphs are generated
    /// from the same Carbon bits that are registered with the operating system.
    static func recorded(action: ShortcutAction, physicalKeyCode: Int, modifiers: UInt32,
                         keyLabel: String) throws -> ShortcutBinding {
        let specialNames = [kVK_Space: "Space", kVK_Tab: "Tab", kVK_Return: "Return",
                            kVK_Delete: "Delete", kVK_ForwardDelete: "Forward Delete",
                            kVK_Escape: "Esc", kVK_LeftArrow: "←", kVK_RightArrow: "→",
                            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ANSI_Grave: "`"]
        let key = specialNames[physicalKeyCode] ?? keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let binding = ShortcutBinding(action: action, keyCode: physicalKeyCode, modifiers: modifiers,
            label: modifierGlyphs(modifiers) + key)
        try ShortcutConfiguration.validateBinding(binding)
        return binding
    }

    static func modifierGlyphs(_ modifiers: UInt32) -> String {
        [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined()
    }
}

/// The single source of bindings and display labels for registration and UI.
/// Persistence is owned by the application, using the stable raw value.
enum ShortcutScheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case optionNumbers
    case inventoryFirst
    case controlOption

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionNumbers: return "Option 双键直达"
        case .inventoryFirst: return "Option Space 总览优先"
        case .controlOption: return "Control Option 原组合"
        }
    }

    var modifiers: UInt32 {
        self == .controlOption ? UInt32(controlKey | optionKey) : UInt32(optionKey)
    }

    var modifierLabel: String { self == .controlOption ? "⌃⌥" : "⌥" }

    var slotRangeLabel: String {
        self == .inventoryFirst ? "1–9（总览内）" : modifierLabel + "1–9"
    }

    var taskBindings: [ShortcutBinding] {
        guard self != .inventoryFirst else { return [] }
        return ((1...9).map { ShortcutAction.slot($0) } + [.arrange]).compactMap { binding(for: $0) }
    }

    var wheelBindings: [ShortcutBinding] {
        let actions: [ShortcutAction] = self == .inventoryFirst ? [.inventory] : [.aim, .toggleVisibility]
        return actions.compactMap { binding(for: $0) }
    }

    func binding(for action: ShortcutAction) -> ShortcutBinding? {
        if self == .inventoryFirst {
            guard action == .inventory else { return nil }
            return ShortcutBinding(action: action, keyCode: kVK_Space, modifiers: modifiers, label: "⌥Space")
        }
        let keyCode: Int
        let keyLabel: String
        switch action {
        case .slot(let number):
            let codes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                         kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
            guard (1...9).contains(number) else { return nil }
            keyCode = codes[number - 1]
            keyLabel = String(number)
        case .arrange:
            keyCode = self == .optionNumbers ? kVK_ANSI_Grave : kVK_ANSI_0
            keyLabel = self == .optionNumbers ? "`" : "0"
        case .aim: keyCode = kVK_ANSI_Q; keyLabel = "Q"
        case .toggleVisibility: keyCode = kVK_ANSI_H; keyLabel = "H"
        case .cancelModified: keyCode = kVK_Escape; keyLabel = "Esc"
        case .inventory: return nil
        }
        return ShortcutBinding(action: action, keyCode: keyCode, modifiers: modifiers, label: modifierLabel + keyLabel)
    }
}
