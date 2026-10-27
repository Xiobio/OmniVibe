import AppKit
import SwiftUI
import Combine
import Darwin
import OmniVibeCore

@main
@MainActor
enum OmniVibeApp {
    static func main() {
        if let code = TaskLaunchCommandLine.runIfRequested(arguments: CommandLine.arguments) { exit(code) }
        if let code = AgentCommandLine.runIfRequested(arguments: CommandLine.arguments) { exit(code) }
        let application = NSApplication.shared
        let delegate = OmniVibeDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class OmniVibeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controller: ApplicationController?
    private var appearance: AppearanceModel?
    private var audio: ThemeAudio?
    private var previews: WindowPreviewService?
    private var taskNotifications: TaskNotificationService?
    private var floatingWheel: FloatingWheelController?
    private var inventoryWindow: FocusCapturingWindow?
    private var settingsWindow: FocusCapturingWindow?
    private var statusItem: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()
    private var lastExternalFocus: WindowIdentity?
    private var inventoryReturnFocus: WindowIdentity?
    private var settingsReturnFocus: WindowIdentity?
    private var quitting = false
    private var launcherVisibleBeforeArrangement: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--validate-arrangement"), arguments.indices.contains(index + 1) {
            Task { let code = await ArrangementValidationRunner.run(outputPath: arguments[index + 1]); exit(code) }
            return
        }
        if let index = arguments.firstIndex(of: "--smoke-test"), arguments.indices.contains(index + 1) {
            let path = arguments[index + 1]
            Task { let code = await NativeSmokeRunner.run(outputPath: path); exit(code) }
            return
        }
        if let index = arguments.firstIndex(of: "--validate-appearance"), arguments.indices.contains(index + 1) {
            exit(AppearanceValidationRunner.run(outputPath: arguments[index + 1]))
        }
        NSApp.setActivationPolicy(.accessory)
        _ = AppLocalization.shared
        let model = ApplicationController(demo: arguments.contains("--demo"))
        let visuals = AppearanceModel(demo: model.isDemo)
        controller = model
        appearance = visuals
        model.onRequestInventory = { [weak self] in self?.showInventory() }
        model.onRequestPermission = { [weak self] in self?.showSettings() }
        model.onPrepareSlotOrdering = { [weak visuals] slots in
            guard let visuals else { throw IntegrationError("外观配置尚未就绪，请重新打开任务总览。") }
            try visuals.preserveTaskEquipment(slots)
        }
        model.onTaskIdentityReplaced = { [weak visuals] oldID, newID in
            guard let visuals else { throw IntegrationError("外观配置尚未就绪。") }
            try visuals.transferEquipment(from: oldID, to: newID)
        }
        model.onSuspendWheelShortcuts = { [weak self] in self?.floatingWheel?.suspendHotkeys() }
        model.onToggleInventory = { [weak self] in
            guard let self else { return }
            if self.inventoryWindow?.isKeyWindow == true && NSApp.isActive { self.closeInventory() }
            else { self.showInventory() }
        }
        model.onBeforeArrangement = { [weak self, weak model] in
            guard let self, let model else { return }
            self.inventoryReturnFocus = nil
            self.settingsReturnFocus = nil
            self.inventoryWindow?.close()
            self.settingsWindow?.close()
            self.launcherVisibleBeforeArrangement = self.floatingWheel?.isVisible
            if model.windowBehavior.hideLauncherOnArrange { self.floatingWheel?.hide() }
        }
        model.onArrangementRestored = { [weak self] in
            guard let self else { return }
            if self.launcherVisibleBeforeArrangement == true && !self.quitting { self.floatingWheel?.show() }
            self.launcherVisibleBeforeArrangement = nil
        }
        model.onBeforeTaskActivation = { [weak self] in
            guard let self else { return }
            self.inventoryReturnFocus = nil
            self.settingsReturnFocus = nil
            self.inventoryWindow?.close()
            self.settingsWindow?.close()
        }
        model.managementWindowIsActive = { [weak self] in
            guard let self, NSApp.isActive else { return false }
            return self.inventoryWindow?.isKeyWindow == true || self.settingsWindow?.isKeyWindow == true
        }
        let sound = ThemeAudio(appearance: visuals)
        audio = sound
        model.onFeedback = { [weak sound, weak model] cue in
            if [.waiting, .ready, .error].contains(cue), model?.windowBehavior.completionSoundEnabled == false { return }
            sound?.play(cue)
        }
        let notifications = TaskNotificationService { [weak model] taskID in model?.openTaskFromNotification(taskID) }
        taskNotifications = notifications
        model.onRequestSystemNotifications = { [weak model, weak notifications] in
            Task { @MainActor in
                guard let model, let notifications else { return }
                do {
                    let status = try await notifications.requestAuthorization()
                    model.notificationStatus = status.label
                    model.updateWindowBehavior { $0.systemNotificationsEnabled = status.canDeliver }
                } catch { model.notificationStatus = error.localizedDescription }
            }
        }
        model.onTaskReady = { [weak model, weak notifications] taskID, title in
            guard model?.windowBehavior.systemNotificationsEnabled == true else { return }
            Task { @MainActor in
                guard let model, let notifications else { return }
                switch await notifications.notify(taskID: taskID, title: title) {
                case .sent: model.notificationStatus = "通知已提交系统。"
                case .notAuthorized(let status): model.notificationStatus = status.label + "；请在系统设置 → 通知 → OmniVibe 中允许。"
                case .failed(let message): model.notificationStatus = message
                }
            }
        }
        Task { @MainActor [weak model, weak notifications] in
            guard let model, let notifications else { return }
            model.notificationStatus = await notifications.authorizationStatus().label
        }
        previews = WindowPreviewService()
        installMainMenu()
        floatingWheel = FloatingWheelController(controller: model, appearance: visuals,
            onShowInventory: { [weak self] in self?.showInventory() },
            onShowSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) })
        model.onRetryWheelShortcuts = { [weak self] in self?.floatingWheel?.retryHotkeys() }
        model.onWindowBehaviorChanged = { [weak self] in self?.applyWindowBehavior() }
        installStatusItem()
        visuals.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.refreshWindowTheme() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .omniVibeLanguageDidChange).sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.installMainMenu()
                self.refreshWindowTheme()
                self.floatingWheel?.refreshPreferences()
                self.statusItem?.button?.toolTip = L10n.text("OmniVibe · 左键显示/隐藏悬浮入口，右键管理")
            }
        }.store(in: &subscriptions)
        floatingWheel?.show(expanded: arguments.contains("--wheel-expanded"), keepExpanded: arguments.contains("--wheel-expanded"))
        if arguments.contains("--show-inventory") { showInventory() }
        if arguments.contains("--show-settings") || arguments.contains("--request-access") { showSettings() }
        if arguments.contains("--request-access") { model.requestAccess() }
        if model.recoveryCount > 0 {
            if model.windowBehavior.autoRestoreRecovery { model.restorePendingRecovery() }
            if model.recoveryCount > 0 && model.windowBehavior.showRecoveryOnStartup { showInventory() }
        }
    }

    private func rememberExternalFocus() -> WindowIdentity? {
        controller?.rememberExternalFocus()
        if let current = controller?.windows.currentWindow() { lastExternalFocus = current }
        return lastExternalFocus
    }

    @objc func showInventory() {
        guard let controller, let appearance, let previews else { return }
        controller.endShortcutRecording()
        controller.cancelArrangementPresentation()
        let openingFresh = inventoryWindow?.isVisible != true
        if openingFresh { inventoryReturnFocus = rememberExternalFocus() }
        controller.recheckPermissions()
        if inventoryWindow == nil {
            let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 900)
            let size = inventorySize(in: area, preference: controller.windowBehavior.overviewSize)
            let window = FocusCapturingWindow(contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            window.minSize = NSSize(width: 820, height: 620)
            window.isReleasedWhenClosed = false
            window.backgroundColor = appearance.theme.background
            window.appearance = NSAppearance(named: .darkAqua)
            window.onBeforeBecomingKey = { [weak self] in _ = self?.rememberExternalFocus() }
            window.contentView = NSHostingView(rootView: NativeInventoryView(controller: controller, appearance: appearance, previews: previews,
                onClose: { [weak self] in self?.closeInventory() },
                onShowSettings: { [weak self] in self?.showSettings() }))
            window.delegate = self
            window.center()
            inventoryWindow = window
        }
        refreshWindowTheme()
        inventoryWindow?.makeKeyAndOrderFront(nil)
        activateApplication()
        if !controller.isDemo {
            previews.start { [weak controller] in
                guard let controller else { return [] }
                return controller.workspace.slots.compactMap(\.window).compactMap { controller.windows.previewDescriptor($0) }
            }
        }
        if openingFresh { controller.playFeedback(.inventoryOpen) }
    }

    private func closeInventory() { inventoryWindow?.close() }

    @objc func showSettings() {
        guard let controller, let appearance else { return }
        controller.cancelArrangementPresentation()
        let openingFresh = settingsWindow?.isVisible != true
        if openingFresh { settingsReturnFocus = rememberExternalFocus() }
        controller.recheckPermissions()
        if settingsWindow == nil {
            let window = FocusCapturingWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 690),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.minSize = NSSize(width: 760, height: 580)
            window.isReleasedWhenClosed = false
            window.backgroundColor = appearance.theme.background
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.onBeforeBecomingKey = { [weak self] in _ = self?.rememberExternalFocus() }
            window.contentView = NSHostingView(rootView: ThemedSettingsView(controller: controller, appearance: appearance,
                onClose: { [weak self] in self?.settingsWindow?.close() }))
            window.delegate = self
            window.center()
            settingsWindow = window
        } else if openingFresh {
            // A retained NSWindow also retains SwiftUI @State. Recreate the
            // draft so Cancel/closing cannot carry an unapplied theme forward.
            settingsWindow?.contentView = NSHostingView(rootView: ThemedSettingsView(controller: controller, appearance: appearance,
                onClose: { [weak self] in self?.settingsWindow?.close() }))
        }
        refreshWindowTheme()
        settingsWindow?.makeKeyAndOrderFront(nil)
        activateApplication()
    }

    private func activateApplication() {
        if #available(macOS 14.0, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
    }

    private func inventorySize(in area: NSRect, preference: WindowBehaviorPreferences.OverviewSize) -> NSSize {
        let requested: NSSize
        switch preference {
        case .small: requested = NSSize(width: 820, height: 620)
        case .medium: requested = NSSize(width: 1040, height: 780)
        case .large: requested = NSSize(width: 1280, height: 920)
        }
        return NSSize(width: min(requested.width, max(820, area.width - 80)), height: min(requested.height, max(620, area.height - 80)))
    }

    private func applyWindowBehavior() {
        guard let controller else { return }
        floatingWheel?.refreshPreferences()
        if let window = inventoryWindow {
            let area = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            window.setContentSize(inventorySize(in: area, preference: controller.windowBehavior.overviewSize))
        }
    }

    private func refreshWindowTheme() {
        guard let appearance else { return }
        let demo = controller?.isDemo == true ? L10n.text(" · 示例任务") : ""
        inventoryWindow?.title = "OmniVibe · \(appearance.theme.overviewTitle)\(demo)"
        settingsWindow?.title = L10n.text("OmniVibe · 设置与配装")
        inventoryWindow?.backgroundColor = appearance.theme.background
        settingsWindow?.backgroundColor = appearance.theme.background
        let style: NSAppearance.Name = appearance.themeSlug == "wonderland" ? .aqua : .darkAqua
        inventoryWindow?.appearance = NSAppearance(named: style)
        settingsWindow?.appearance = NSAppearance(named: style)
    }

    private func restoreFocus(_ identity: WindowIdentity?) {
        guard let identity, let controller, !quitting, !controller.isDemo,
              !controller.windows.isDefinitelyClosed(identity) else { return }
        // No delayed re-raise: the inventory activates a selected task directly
        // after onClose, and that task must retain the final keyboard focus.
        do { try controller.windows.activate(identity) }
        catch { controller.notice = "总览已关闭，但未能返回先前窗口：\(error.localizedDescription)" }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === inventoryWindow {
            previews?.stop()
            controller?.playFeedback(.inventoryClose)
            let prior = inventoryReturnFocus
            inventoryReturnFocus = nil
            restoreFocus(prior)
        } else if let window = notification.object as? NSWindow, window === settingsWindow {
            controller?.endShortcutRecording()
            let prior = settingsReturnFocus
            settingsReturnFocus = nil
            restoreFocus(prior)
        }
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let inventory = applicationMenu.addItem(withTitle: L10n.text("打开任务总览"), action: #selector(showInventory), keyEquivalent: "0")
        inventory.target = self
        let create = applicationMenu.addItem(withTitle: L10n.text("新建或继续任务…"), action: #selector(openNewTask), keyEquivalent: "n")
        create.target = self
        let settings = applicationMenu.addItem(withTitle: L10n.text("设置与配装…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: L10n.text("退出 OmniVibe"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu; menu.addItem(applicationItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.text("编辑"))
        editMenu.addItem(withTitle: L10n.text("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.text("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.text("拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.text("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.text("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    @objc private func openNewTask() { controller?.beginNewTask() }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let url = Bundle.main.resourceURL?.appendingPathComponent("omnivibe-128.png"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 19, height: 19)
            item.button?.image = image
        } else { item.button?.title = "OV" }
        item.button?.toolTip = L10n.text("OmniVibe · 左键显示/隐藏悬浮入口，右键管理")
        item.button?.target = self
        item.button?.action = #selector(statusClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp, let menu = floatingWheel?.makeMenu() {
            NSMenu.popUpContextMenu(menu, with: event, for: sender)
        } else { floatingWheel?.toggleVisibility() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        floatingWheel?.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidResignActive(_ notification: Notification) { controller?.endShortcutRecording() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        quitting = true
        floatingWheel?.stop()
        previews?.stop()
        audio?.stop()
        let failures = controller.prepareToQuit()
        if failures.isEmpty { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L10n.text("部分窗口未能恢复原布局")
        alert.informativeText = failures.map { L10n.errorText($0) }.joined(separator: "\n")
        alert.addButton(withTitle: L10n.text("返回并重试"))
        alert.addButton(withTitle: L10n.text("仍然退出"))
        if alert.runModal() == .alertSecondButtonReturn { return .terminateNow }
        quitting = false
        controller.resumeAfterCancelledQuit()
        floatingWheel?.resumeAfterCancelledQuit()
        floatingWheel?.show()
        return .terminateCancel
    }
}

@MainActor
final class FocusCapturingWindow: NSWindow {
    var onBeforeBecomingKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func becomeKey() { onBeforeBecomingKey?(); super.becomeKey() }
}
