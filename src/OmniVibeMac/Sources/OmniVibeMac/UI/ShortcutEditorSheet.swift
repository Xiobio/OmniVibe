import AppKit
import Carbon
import SwiftUI

@MainActor
struct ShortcutEditorSheet: View {
    @ObservedObject var localization = AppLocalization.shared
    @ObservedObject var controller: ApplicationController
    @ObservedObject var appearance: AppearanceModel
    let action: ShortcutAction
    let onClose: () -> Void
    @State private var keyCode: Int
    @State private var modifiers: UInt32
    @State private var capturedKeyName: String
    @State private var error: String?

    init(controller: ApplicationController, appearance: AppearanceModel, action: ShortcutAction, onClose: @escaping () -> Void) {
        self.controller = controller; self.appearance = appearance; self.action = action; self.onClose = onClose
        let binding = controller.shortcutConfiguration.binding(for: action)
        _keyCode = State(initialValue: binding?.keyCode ?? kVK_Space)
        _modifiers = State(initialValue: binding?.modifiers ?? UInt32(optionKey))
        _capturedKeyName = State(initialValue: ShortcutKeyChoice.name(for: binding?.keyCode ?? kVK_Space))
    }

    private var proposed: ShortcutBinding? {
        try? ShortcutBinding.recorded(action: action, physicalKeyCode: keyCode, modifiers: modifiers, keyLabel: capturedKeyName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("自定义 · ") + L10n.text(action.label)).font(.custom("STKaiti", size: 24))
            Text(L10n.text("点击录制区后按下组合，或在下面选择修饰键和按键。编辑期间暂停 OmniVibe 的全局快捷键，避免触发原操作。"))
                .font(.system(size: 12)).foregroundStyle(Color(nsColor: appearance.theme.muted))
            ShortcutRecorder(display: proposed?.label ?? L10n.text("点击这里，再按新组合"), onFocus: controller.beginShortcutRecording,
                onBlur: controller.endShortcutRecording,
                onKey: { code, flags, name in
                    keyCode = code; modifiers = flags; capturedKeyName = name; error = nil
                }, onCancel: close)
                .frame(height: 66)
            HStack(spacing: 16) {
                Toggle("⌃ Control", isOn: modifier(UInt32(controlKey)))
                Toggle("⌥ Option", isOn: modifier(UInt32(optionKey)))
                Toggle("⇧ Shift", isOn: modifier(UInt32(shiftKey)))
                Toggle("⌘ Command", isOn: modifier(UInt32(cmdKey)))
            }.toggleStyle(.checkbox).font(.system(size: 11))
            Picker(L10n.text("按键"), selection: $keyCode) {
                ForEach(ShortcutKeyChoice.all) { item in Text(item.name).tag(item.code) }
                if !ShortcutKeyChoice.all.contains(where: { $0.code == keyCode }) {
                    Text(capturedKeyName).tag(keyCode)
                }
            }.pickerStyle(.menu).frame(maxWidth: 300, alignment: .leading)
                .onChange(of: keyCode) { code in capturedKeyName = ShortcutKeyChoice.name(for: code); error = nil }
            Text(L10n.text("这是全局组合，至少搭配一个修饰键；Esc 用于取消。与其他操作重复的组合不会覆盖原设置。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.muted))
            if let error {
                Text(L10n.errorText(error)).font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.waiting))
            }
            HStack {
                Spacer()
                Button(L10n.text("取消"), action: close)
                Button(L10n.text("保存快捷键"), action: save).buttonStyle(.borderedProminent)
            }
        }.padding(26).frame(width: 620)
            .foregroundStyle(Color(nsColor: appearance.theme.text))
            .background(Color(nsColor: appearance.theme.background))
            .tint(Color(nsColor: appearance.theme.accent))
            .environment(\.locale, localization.locale)
        .preferredColorScheme(appearance.themeSlug == "wonderland" ? .light : .dark)
            .onAppear { controller.beginShortcutRecording() }
            .onDisappear { controller.endShortcutRecording() }
    }

    private func modifier(_ flag: UInt32) -> Binding<Bool> {
        Binding(get: { modifiers & flag != 0 }, set: { enabled in
            if enabled { modifiers |= flag } else { modifiers &= ~flag }
            error = nil
        })
    }

    private func save() {
        do {
            let binding = try ShortcutBinding.recorded(action: action, physicalKeyCode: keyCode, modifiers: modifiers, keyLabel: capturedKeyName)
            if controller.setCustomShortcut(binding) { close() }
            else { error = controller.shortcutEditError }
        } catch { self.error = error.localizedDescription }
    }

    private func close() { controller.endShortcutRecording(); onClose() }
}

private struct ShortcutKeyChoice: Identifiable {
    let code: Int
    let name: String
    var id: Int { code }
    static let all: [ShortcutKeyChoice] = {
        let letters: [(Int, String)] = [(kVK_ANSI_A,"A"),(kVK_ANSI_B,"B"),(kVK_ANSI_C,"C"),(kVK_ANSI_D,"D"),
            (kVK_ANSI_E,"E"),(kVK_ANSI_F,"F"),(kVK_ANSI_G,"G"),(kVK_ANSI_H,"H"),(kVK_ANSI_I,"I"),(kVK_ANSI_J,"J"),
            (kVK_ANSI_K,"K"),(kVK_ANSI_L,"L"),(kVK_ANSI_M,"M"),(kVK_ANSI_N,"N"),(kVK_ANSI_O,"O"),(kVK_ANSI_P,"P"),
            (kVK_ANSI_Q,"Q"),(kVK_ANSI_R,"R"),(kVK_ANSI_S,"S"),(kVK_ANSI_T,"T"),(kVK_ANSI_U,"U"),(kVK_ANSI_V,"V"),
            (kVK_ANSI_W,"W"),(kVK_ANSI_X,"X"),(kVK_ANSI_Y,"Y"),(kVK_ANSI_Z,"Z")]
        let digits = [kVK_ANSI_0,kVK_ANSI_1,kVK_ANSI_2,kVK_ANSI_3,kVK_ANSI_4,kVK_ANSI_5,kVK_ANSI_6,kVK_ANSI_7,kVK_ANSI_8,kVK_ANSI_9]
            .enumerated().map { ($0.element, String($0.offset)) }
        let special: [(Int,String)] = [(kVK_ANSI_Grave,"`"),(kVK_Space,"Space"),(kVK_Tab,"Tab"),(kVK_Return,"Return"),
            (kVK_Delete,"Delete"),(kVK_ForwardDelete,"Forward Delete"),(kVK_LeftArrow,"←"),(kVK_RightArrow,"→"),
            (kVK_UpArrow,"↑"),(kVK_DownArrow,"↓"),(kVK_Home,"Home"),(kVK_End,"End"),(kVK_PageUp,"Page Up"),(kVK_PageDown,"Page Down"),
            (kVK_ANSI_Minus,"-"),(kVK_ANSI_Equal,"="),(kVK_ANSI_LeftBracket,"["),(kVK_ANSI_RightBracket,"]"),
            (kVK_ANSI_Backslash,"\\"),(kVK_ANSI_Semicolon,";"),(kVK_ANSI_Quote,"'"),(kVK_ANSI_Comma,","),(kVK_ANSI_Period,"."),(kVK_ANSI_Slash,"/")]
        let functions = [kVK_F1,kVK_F2,kVK_F3,kVK_F4,kVK_F5,kVK_F6,kVK_F7,kVK_F8,kVK_F9,kVK_F10,kVK_F11,kVK_F12,kVK_F13,kVK_F14,kVK_F15,kVK_F16,kVK_F17,kVK_F18,kVK_F19,kVK_F20]
            .enumerated().map { ($0.element, "F\($0.offset + 1)") }
        return (letters + digits + special + functions).map { ShortcutKeyChoice(code: $0.0, name: $0.1) }
    }()
    static func name(for code: Int) -> String { all.first { $0.code == code }?.name ?? "Key \(code)" }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let display: String
    let onFocus: () -> Void
    let onBlur: () -> Void
    let onKey: (Int, UInt32, String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView { KeyCaptureView() }
    func updateNSView(_ view: KeyCaptureView, context: Context) {
        view.display = display; view.onFocus = onFocus; view.onBlur = onBlur; view.onKey = onKey; view.onCancel = onCancel
        view.setAccessibilityLabel(L10n.text("快捷键录制区域"))
        view.needsDisplay = true
    }
}

private final class KeyCaptureView: NSView {
    var display = L10n.text("按下快捷键")
    var onFocus: (() -> Void)?
    var onBlur: (() -> Void)?
    var onKey: ((Int, UInt32, String) -> Void)?
    var onCancel: (() -> Void)?
    private var windowObservers: [NSObjectProtocol] = []
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateRecordingFocus() }
                })
            }
            windowObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateRecordingFocus() }
            })
        } else { onBlur?() }
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityLabel(L10n.text("快捷键录制区域"))
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            self.updateRecordingFocus()
        }
    }
    private func updateRecordingFocus() {
        if window?.isKeyWindow == true && NSApp.isActive { onFocus?() }
        else { onBlur?() }
    }
    override func becomeFirstResponder() -> Bool { updateRecordingFocus(); needsDisplay = true; return true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        capture(event); return true
    }
    override func keyDown(with event: NSEvent) { capture(event) }

    private func capture(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if Int(event.keyCode) == kVK_Escape { onCancel?(); return }
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        let code = Int(event.keyCode)
        onKey?(code, carbon, ShortcutKeyChoice.name(for: code))
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        NSColor.controlBackgroundColor.setFill(); path.fill()
        NSColor.keyboardFocusIndicatorColor.setStroke(); path.lineWidth = 1.5; path.stroke()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let font = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
        (L10n.text(display) as NSString).draw(in: NSRect(x: 8, y: (bounds.height - 26) / 2, width: bounds.width - 16, height: 26),
            withAttributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        setAccessibilityValue(L10n.text(display))
    }

    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }
}
