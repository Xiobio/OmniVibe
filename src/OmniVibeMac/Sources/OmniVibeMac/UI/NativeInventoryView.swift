import AppKit
import SwiftUI
import OmniVibeCore

/// The original task inventory: nine fixed slots in the selected game's materials.
@MainActor
struct NativeInventoryView: View {
    @ObservedObject var localization = AppLocalization.shared
    @ObservedObject var controller: ApplicationController
    @ObservedObject var appearance: AppearanceModel
    @ObservedObject var previews: WindowPreviewService
    let onClose: () -> Void
    let onShowSettings: () -> Void
    @State private var selectedNumber = 1
    @State private var loadoutSlot: TaskSlot?
    @State private var showingRecentTasks = false
    @FocusState private var hasKeyboardFocus: Bool

    private var theme: ThemeDefinition { appearance.theme }

    var body: some View {
        ZStack {
            InventoryBackdrop(theme: theme, decorations: appearance.decorations)
            VStack(spacing: 14) {
                heading
                if let warning = controller.sessionLinkWarning {
                    Text(L10n.errorText(warning)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(3).textSelection(.enabled)
                }
                if controller.recoveryCount > 0 || controller.recoveryWarning != nil { recoveryControls }
                if controller.activationFailure != nil || controller.arrangementWarning != nil { operationDiagnostics }
                GeometryReader { geometry in
                    let rowHeight = max(138, (geometry.size.height - 24) / 3)
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                            ForEach(controller.workspace.slots.sorted { $0.number < $1.number }) { slot in
                                InventorySlotCard(slot: slot, controller: controller, appearance: appearance, previews: previews,
                                    selected: selectedNumber == slot.number, activate: { activate(slot.number) },
                                    onLoadout: { loadoutSlot = slot },
                                    onDropTask: { reorderTask($0, to: slot.number) })
                                    .frame(height: rowHeight)
                                    .onHover { if $0 { selectedNumber = slot.number } }
                            }
                        }
                    }
                }
                footer
            }
            .padding(.horizontal, 26).padding(.top, 17).padding(.bottom, 16)
        }
        .foregroundStyle(Color(nsColor: theme.text))
        .tint(Color(nsColor: theme.accent))
        .environment(\.locale, localization.locale)
        .preferredColorScheme(theme.slug == "wonderland" ? .light : .dark)
        .focusable().focused($hasKeyboardFocus)
        .onAppear { hasKeyboardFocus = true }
        .onExitCommand(perform: onClose)
        .onMoveCommand { direction in
            switch direction {
            case .left: selectedNumber = max(1, selectedNumber - 1)
            case .right: selectedNumber = min(9, selectedNumber + 1)
            case .up: selectedNumber = max(1, selectedNumber - 3)
            case .down: selectedNumber = min(9, selectedNumber + 3)
            @unknown default: break
            }
        }
        .background(keyboardActions)
        .sheet(isPresented: Binding(get: { controller.pickerSlot != nil }, set: { if !$0 { controller.pickerSlot = nil } }),
               onDismiss: controller.presentDeferredLaunchIfNeeded) {
            WindowPickerView(controller: controller, appearance: appearance)
        }
        .sheet(isPresented: Binding(get: { controller.launchSlot != nil }, set: { if !$0 && !controller.taskLaunchBusy { controller.launchSlot = nil } })) {
            if let number = controller.launchSlot, let slot = controller.workspace.slots.first(where: { $0.number == number }) {
                TaskLaunchSheet(slot: slot, initial: controller.launchConfiguration(for: number), appearance: appearance,
                    isLaunching: controller.taskLaunchBusy, operationFailure: controller.taskOperationFailure,
                    onClose: { controller.launchSlot = nil; controller.taskOperationFailure = nil },
                    onLaunch: controller.launchTask,
                    onSave: controller.isConnected(slot) ? { controller.saveLaunchConfiguration($0) } : nil)
            }
        }
        .sheet(isPresented: Binding(get: { controller.sessionDiscoverySlot != nil }, set: { if !$0 { controller.sessionDiscoverySlot = nil } })) {
            if let number = controller.sessionDiscoverySlot,
               let slot = controller.workspace.slots.first(where: { $0.number == number && $0.window != nil }) {
                SessionDiscoverySheet(slot: slot, appearance: appearance,
                    operationFailure: controller.taskOperationFailure,
                    onClose: { controller.sessionDiscoverySlot = nil; controller.taskOperationFailure = nil }, onSelect: controller.attachExistingSession)
            }
        }
        .sheet(isPresented: Binding(get: { controller.renameSlot != nil }, set: { if !$0 { controller.renameSlot = nil } })) {
            RenameTaskSheet(controller: controller, appearance: appearance)
        }
        .sheet(item: $loadoutSlot) { slot in
            LoadoutPickerView(slot: slot, appearance: appearance) { loadoutSlot = nil }
        }
        .sheet(isPresented: $showingRecentTasks, onDismiss: controller.presentRestoredRecentPickerIfNeeded) {
            RecentTasksSheet(controller: controller, appearance: appearance) { showingRecentTasks = false }
        }
        .sheet(isPresented: Binding(get: { controller.integrationSlot != nil }, set: { if !$0 { controller.integrationSlot = nil } })) {
            if let number = controller.integrationSlot,
               let slot = controller.workspace.slots.first(where: { $0.number == number && $0.window != nil }) {
                AgentIntegrationSheet(slot: slot, appearance: appearance) { controller.integrationSlot = nil }
            }
        }
        .alert(controller.taskOperationFailure != nil ? L10n.text("任务操作未完成") : L10n.text("排列未完成"),
            isPresented: Binding(get: { controller.launchSlot == nil && controller.sessionDiscoverySlot == nil && (controller.taskOperationFailure != nil || controller.arrangementFailure != nil) },
                set: { if !$0 { clearOperationFailures() } })) {
            Button(L10n.text("知道了"), action: clearOperationFailures)
        } message: { Text(L10n.errorText(controller.taskOperationFailure ?? controller.arrangementFailure ?? "")) }
    }

    private var heading: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                HStack(spacing: 13) {
                    Text(controller.isDemo ? L10n.text("OMNIVIBE / 界面演示 · 示例任务") : L10n.text("OMNIVIBE / 任务总览"))
                        .font(.system(size: 9)).foregroundStyle(Color(nsColor: theme.muted))
                    Text(L10n.text("已收纳 \(controller.occupiedCount) / 已连接 \(controller.connectedCount)"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color(nsColor: theme.accent))
                        .help(L10n.text("已连接表示当前能访问窗口；能否排列还取决于窗口是否允许移动和调整尺寸。"))
                }
                Text(theme.overviewTitle).font(.custom("STKaiti", size: 31)).tracking(5)
                if !controller.permissionGranted && !controller.isDemo {
                    Button(L10n.text("窗口控制尚未授权 · 打开权限设置")) {
                        controller.requireAccessibilityPermission(reason: L10n.text("收纳与切换窗口需要辅助功能权限"))
                    }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Color(nsColor: theme.waiting))
                } else {
                    Text(L10n.text("方向键浏览　·　Enter 进入　·　数字直达"))
                        .font(.custom("STKaiti", size: 10)).foregroundStyle(Color(nsColor: theme.muted))
                }
            }.frame(maxWidth: .infinity)
            Button(action: onClose) { Text("×").font(.system(size: 23, weight: .light)).frame(width: 32, height: 32) }
                .buttonStyle(.plain)
                .overlay(Rectangle().strokeBorder(Color(nsColor: theme.border).opacity(0.6)).allowsHitTesting(false))
                .help(L10n.text("关闭任务总览 · Esc"))
        }.frame(height: 76)
    }

    private var operationDiagnostics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                if let failure = controller.activationFailure {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.text("切换未完成")).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button(L10n.text("重试切换")) { onClose(); controller.retryLastActivation() }
                                .disabled(!controller.canControlWindows || controller.isRecordingShortcut)
                                .help(L10n.text("按失败任务的当前身份重试，不沿用排序前的编号。"))
                        }
                        Text(L10n.errorText(failure)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let warning = controller.arrangementWarning {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.text("排列提示")).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button(controller.isArranged ? L10n.text("恢复布局") : L10n.text("重试排列")) { controller.toggleArrangement() }
                                .disabled(!controller.canControlWindows || controller.isPresentingArrangement)
                        }
                        Text(L10n.errorText(warning)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
        }
        .frame(maxHeight: 116)
        .font(.system(size: 11)).buttonStyle(.borderless)
        .foregroundStyle(Color(nsColor: theme.waiting))
        .background(Color(nsColor: theme.surface).opacity(0.8))
        .overlay(Rectangle().strokeBorder(Color(nsColor: theme.waiting).opacity(0.45)).allowsHitTesting(false))
    }

    private var recoveryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("上次窗口恢复 · \(controller.recoveryCount) 条记录")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(L10n.text("恢复上次布局"), action: controller.restorePendingRecovery).disabled(controller.recoveryCount == 0)
                Button(L10n.text("保留备份并跳过"), action: controller.archiveAndSkipPendingRecovery).disabled(controller.recoveryCount == 0)
            }
            if let warning = controller.recoveryWarning {
                ScrollView { Text(L10n.errorText(warning)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 54)
            }
        }.font(.system(size: 11)).padding(11)
            .foregroundStyle(Color(nsColor: theme.waiting))
            .background(Color(nsColor: theme.surface).opacity(0.8))
            .overlay(Rectangle().strokeBorder(Color(nsColor: theme.waiting).opacity(0.45)).allowsHitTesting(false))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(L10n.errorText(footerText)).lineLimit(1).truncationMode(.middle)
                .help(L10n.errorText(footerText))
                .font(.custom("STKaiti", size: 11)).foregroundStyle(Color(nsColor: theme.muted))
            Spacer(minLength: 10)
            Picker(L10n.text("排列方式"), selection: $controller.arrangement) {
                Text(L10n.text("均衡平铺")).tag(ArrangementMode.balanced)
                Text(L10n.text("分栏")).tag(ArrangementMode.columns)
                Text(L10n.text("分行")).tag(ArrangementMode.rows)
                Text(L10n.text("主窗居左")).tag(ArrangementMode.mainLeft)
            }.labelsHidden().pickerStyle(.menu).frame(width: 94)
            if !controller.isDemo {
                if previews.enabled {
                    Button(L10n.text("关闭预览")) { previews.disable() }
                        .help(L10n.text("停止刷新并清除内存中的窗口预览，任务绑定保持原样。"))
                } else {
                    Button(L10n.text("开启窗口预览")) { previews.requestAccess() }
                        .disabled(!previews.supported || controller.connectedCount == 0)
                        .help(previews.supported
                            ? L10n.text("只预览已连接的具体窗口，需要你授予屏幕录制权限；请先收纳至少一个窗口。")
                            : L10n.text("窗口预览需要 macOS 14 或以上，收纳与切换不受影响。"))
                }
            }
            Button(controller.isArranged ? L10n.text("恢复布局") : L10n.text("排列窗口")) { controller.toggleArrangement() }
                .disabled(!controller.canControlWindows)
            Button(L10n.text("最近关闭")) { showingRecentTasks = true }
            Button(L10n.text("新任务…"), action: controller.beginNewTask).disabled(controller.isDemo || controller.taskLaunchBusy)
            Button(L10n.text("主题与设置"), action: onShowSettings)
        }
        .font(.system(size: 11)).buttonStyle(.borderless)
        .foregroundStyle(Color(nsColor: theme.accent)).frame(height: 24)
    }

    private var footerText: String {
        if let warning = controller.arrangementWarning { return warning }
        if let error = previews.errorMessage { return error }
        if let summary = controller.arrangementSummary { return summary }
        if let notice = controller.notice { return notice }
        if let warning = appearance.assetWarning { return warning }
        if !controller.permissionGranted && !controller.isDemo { return L10n.text("先在设置中开启辅助功能，再收纳你的窗口。") }
        return L10n.text("\(inventoryNumber(selectedNumber, theme: theme)) / \(controller.workspace.slots.first { $0.number == selectedNumber }?.displayName ?? L10n.text("空槽位"))　·　Esc 返回")
    }

    private var keyboardActions: some View {
        Group {
            ForEach(1...9, id: \.self) { number in
                Button("") { activate(number) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: [])
            }
            Button("") { activate(selectedNumber) }.keyboardShortcut(.return, modifiers: [])
        }.hidden().accessibilityHidden(true)
    }

    private func activate(_ number: Int) {
        guard controller.pickerSlot == nil, controller.renameSlot == nil,
              controller.integrationSlot == nil, loadoutSlot == nil,
              controller.taskOperationFailure == nil, controller.arrangementFailure == nil else { return }
        selectedNumber = number
        guard !controller.isDemo else { return }
        guard controller.canControlWindows else {
            controller.requireAccessibilityPermission(reason: L10n.text("添加与切换窗口需要辅助功能权限"))
            return
        }
        guard let slot = controller.workspace.slots.first(where: { $0.number == number }) else { return }
        if slot.window != nil {
            controller.enterSlot(number)
        } else { controller.openPicker(for: number) }
    }

    private func reorderTask(_ taskID: UUID, to number: Int) -> Bool {
        guard !controller.isDemo else { return false }
        guard let source = controller.workspace.slots.first(where: { $0.id == taskID && $0.window != nil }) else {
            controller.taskOperationFailure = "拖动的任务已被移除或替换，请重新拖动。"
            return false
        }
        guard controller.reorderSlot(from: source.number, to: number, expectedTaskID: taskID) else { return false }
        selectedNumber = number
        return true
    }

    private func clearOperationFailures() {
        controller.taskOperationFailure = nil
        controller.arrangementFailure = nil
    }
}

@MainActor
private struct InventorySlotCard: View {
    @ObservedObject var localization = AppLocalization.shared
    let slot: TaskSlot
    @ObservedObject var controller: ApplicationController
    @ObservedObject var appearance: AppearanceModel
    @ObservedObject var previews: WindowPreviewService
    let selected: Bool
    let activate: () -> Void
    let onLoadout: () -> Void
    let onDropTask: (UUID) -> Bool
    @State private var isDropTargeted = false

    private var theme: ThemeDefinition { appearance.theme }
    private var occupied: Bool { slot.window != nil }
    private var connected: Bool { controller.isConnected(slot) }
    private var stale: Bool { connected && slot.statusMayBeStaleAt(Date()) }
    private var dropTargeted: Bool { isDropTargeted && !controller.isDemo }
    private var emptySlots: [TaskSlot] { controller.workspace.slots.filter { $0.window == nil }.sorted { $0.number < $1.number } }
    private var status: String {
        if !occupied { return L10n.text("空槽位 · 等待接入") }
        if controller.isDemo { return L10n.text("示例任务 · 状态未知") }
        if !connected { return L10n.text("已断开 · 点击重连") }
        if stale { return L10n.text("状态待确认 · 较久未更新") }
        switch slot.agentState {
        case .running: return L10n.text("正在执行")
        case .waiting: return L10n.text("等待你处理")
        case .ready: return L10n.text("本轮已回复")
        case .error: return L10n.text("发生错误")
        case .unknown:
            if slot.lastAgentEventName == "SessionEnd" { return L10n.text("会话已结束") }
            return slot.integrationConnected ? L10n.text("会话已连接 · 等待任务") : L10n.text("状态未知")
        }
    }
    private var stateColor: NSColor {
        guard connected, !stale else { return theme.unknown }
        switch slot.agentState {
        case .running: return theme.running
        case .waiting: return theme.waiting
        case .ready: return theme.ready
        case .error: return theme.error
        case .unknown: return theme.unknown
        }
    }

    var body: some View {
        ZStack {
            Color(nsColor: theme.surface).opacity(0.75)
            if appearance.decorations, let frame = ThemeResources.shared.image("skins/native-v2/\(theme.slug)/frame.png") {
                Image(nsImage: frame).resizable(capInsets: EdgeInsets(top: 17, leading: 17, bottom: 17, trailing: 17))
                    .opacity(0.52).allowsHitTesting(false)
            }
            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    ZStack {
                        if let image = ThemeResources.shared.image("skins/native-v2/\(theme.slug)/core.png") {
                            Image(nsImage: image).resizable().scaledToFit()
                        } else { Circle().strokeBorder(Color(nsColor: theme.border), lineWidth: 1) }
                        Text(inventoryNumber(slot.number, theme: theme)).font(.custom("STKaiti", size: 10))
                    }.frame(width: 25, height: 25)
                    Text(status).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if controller.activeSlot == slot.number {
                        Text(L10n.text("● 当前")).font(.system(size: 8)).padding(.horizontal, 5).padding(.vertical, 3)
                            .background(Color(nsColor: theme.accent), in: Capsule())
                            .foregroundStyle(Color(nsColor: theme.background))
                    }
                    if occupied && connected && slot.unread && !controller.isDemo {
                        Text(L10n.text("未读")).font(.system(size: 8)).padding(.horizontal, 5).padding(.vertical, 3)
                            .background(Color(nsColor: theme.accent), in: Capsule())
                            .foregroundStyle(Color(nsColor: theme.background))
                    }
                    if occupied {
                        Button { _ = controller.remove(slot.number, expectedTaskID: slot.id) } label: {
                            Text("×").font(.system(size: 13)).frame(width: 24, height: 24).contentShape(Rectangle())
                        }
                            .buttonStyle(.plain).opacity(0.45).disabled(controller.isDemo).help(L10n.text("解除绑定，保留原窗口"))
                            .accessibilityLabel(L10n.format("移出%d号任务，保留原窗口", slot.number))
                    }
                }.frame(height: 25)
                ZStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: theme.background).opacity(0.62))
                        if appearance.decorations, let image = ThemeResources.shared.image(theme.artwork) {
                            GeometryReader { geometry in
                                Image(nsImage: image).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                                    .opacity(0.13)
                            }.clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        InventoryFlower(color: Color(nsColor: theme.accent).opacity(0.17))
                            .frame(width: 67, height: 67)
                        if occupied, connected, previews.enabled, !controller.isDemo, let window = slot.window {
                            WindowPreviewView(window: window, service: previews, theme: theme, showPermissionButton: false)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(alignment: .trailing) {
                                    if let image = appearance.entity(for: slot) {
                                        Image(nsImage: image).resizable().scaledToFit()
                                            .frame(width: 66).padding(7).opacity(0.7)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .allowsHitTesting(false)
                        } else if occupied {
                            HStack(spacing: 5) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(statusGlyph + " " + mainStatus)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color(nsColor: stateColor))
                                    Text(controller.isDemo ? L10n.text("界面示例") : connected ? L10n.text("点击进入窗口") : L10n.text("点击重新选择窗口"))
                                        .font(.custom("STKaiti", size: 9))
                                        .foregroundStyle(Color(nsColor: theme.muted))
                                }
                                Spacer(minLength: 0)
                                if let image = appearance.entity(for: slot) {
                                    Image(nsImage: image).resizable().scaledToFit()
                                        .frame(width: 93).padding(.vertical, 7)
                                        .opacity(controller.isDemo || connected ? 0.96 : 0.5)
                                }
                            }.padding(.horizontal, 13)
                        } else {
                            VStack(spacing: 5) {
                                Text("+").font(.system(size: 24, weight: .ultraLight))
                                Text(L10n.text("点击添加 · 保留固定编号")).font(.custom("STKaiti", size: 10))
                            }.foregroundStyle(Color(nsColor: theme.muted))
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: theme.border).opacity(0.38)))
                    .contentShape(Rectangle())
                    .allowsHitTesting(false).accessibilityHidden(true)
                    InventoryPreviewInteraction(taskID: occupied ? slot.id : nil, enabled: !controller.isDemo,
                        label: occupied ? L10n.format("第%d号任务：%@", slot.number, slot.displayName) : L10n.format("第%d号空槽，添加窗口", slot.number),
                        isDropTargeted: $isDropTargeted, activate: activate, onDropTask: onDropTask,
                        isTaskAvailable: { taskID in
                            controller.workspace.slots.contains { $0.id == taskID && $0.window != nil }
                        }, onInvalidTask: {
                            controller.taskOperationFailure = "拖动的任务已被移除或替换，请重新拖动。"
                        })
                }.frame(maxHeight: .infinity)
                Button(action: activate) {
                    VStack(spacing: 4) {
                        Text(occupied ? slot.displayName : L10n.text("槽位 \(slot.number) · 添加窗口"))
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(occupied ? "\(slot.window?.applicationName ?? "") · \(integrationLabel)" : L10n.text("收纳窗口，或点击选择已有窗口"))
                            .font(.custom("STKaiti", size: 9)).foregroundStyle(Color(nsColor: theme.muted)).lineLimit(1)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(11)
        }
        .overlay(Rectangle().strokeBorder(Color(nsColor: dropTargeted || selected ? theme.accent : theme.border)
            .opacity(dropTargeted ? 1 : selected ? 0.85 : 0.5), lineWidth: dropTargeted ? 2.5 : selected ? 1.1 : 0.7)
            .allowsHitTesting(false))
        .overlay(alignment: .bottom) {
            if dropTargeted {
                Text(L10n.text("插入到 \(slot.number) 号位置"))
                    .font(.system(size: 10, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color(nsColor: theme.accent), in: Capsule())
                    .foregroundStyle(Color(nsColor: theme.background)).padding(.bottom, 5).allowsHitTesting(false)
            }
        }
        .contextMenu {
            if occupied {
                Button(L10n.text("进入任务"), action: activate)
                Button(L10n.text("编辑任务名称")) { controller.beginRenaming(slot) }
                Button(L10n.text("更换配装…"), action: onLoadout)
                Button(L10n.text("连接自动任务状态…")) { controller.integrationSlot = slot.number }
                Button(L10n.text("关联已有 CLI 会话…")) { controller.sessionDiscoverySlot = slot.number }
                Button(controller.isConnected(slot) ? L10n.text("配置启动与续接…") : L10n.text("启动或继续任务…")) { controller.beginLaunching(slot.number) }
                    .disabled(controller.isDemo)
                Button(L10n.text("重新绑定窗口…")) { controller.openPicker(for: slot.number) }
                Menu(L10n.text("移动到空槽位")) {
                    ForEach(emptySlots) { target in
                        Button(L10n.text("\(target.number) 号空槽位")) {
                            _ = controller.moveSlot(from: slot.number, to: target.number, expectedTaskID: slot.id)
                        }
                    }
                }.disabled(controller.isDemo || emptySlots.isEmpty)
                Divider()
                Button(L10n.text("解除绑定 · 保留窗口"), role: .destructive) {
                    _ = controller.remove(slot.number, expectedTaskID: slot.id)
                }.disabled(controller.isDemo)
            } else { Button(L10n.text("添加窗口"), action: activate) }
        }
        .help(occupied ? statusHelp : L10n.text("槽位 \(slot.number) · 添加窗口"))
    }

    private var statusGlyph: String {
        if stale || !connected { return "◇" }
        switch slot.agentState {
        case .running: return "▷"
        case .waiting: return "!"
        case .ready: return "✓"
        case .error: return "×"
        case .unknown: return "◇"
        }
    }

    private var mainStatus: String {
        if controller.isDemo { return L10n.text("状态未知") }
        if !connected { return L10n.text("连接已断开") }
        return status
    }

    private var integrationLabel: String {
        if controller.isDemo { return L10n.text("示例任务") }
        if slot.stateSource == "手动标记" { return L10n.text("手动标记") }
        let provider: String
        switch slot.agentProvider {
        case "codex": provider = "Codex"
        case "claude": provider = "Claude Code"
        default: provider = "Agent"
        }
        if slot.integrationConnected { return provider + (stale ? L10n.text(" · 状态可能过期") : L10n.text(" · 状态已接入")) }
        if slot.lastAgentEventName == "SessionEnd" { return provider + L10n.text(" · 会话已结束") }
        return L10n.text("自动状态未接入")
    }

    private var statusHelp: String {
        var lines = [slot.displayName, status]
        if !slot.stateSource.isEmpty { lines.append(L10n.text("来源：") + L10n.text(slot.stateSource)) }
        if let updated = slot.updatedAt {
            lines.append(L10n.text("最近更新：") + updated.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(localization.locale)))
        }
        if stale { lines.append(L10n.text("较长时间未收到事件，长任务可能仍在运行。")) }
        if !controller.isDemo { lines.append(L10n.text("拖动预览区域调整顺序；右键可移动到空槽位。")) }
        return lines.joined(separator: "\n")
    }
}

/// Native mouse and drag handling is confined to the main preview. SwiftUI's
/// close, name, and context-menu controls keep independent hit regions.
private struct InventoryPreviewInteraction: NSViewRepresentable {
    let taskID: UUID?
    let enabled: Bool
    let label: String
    @Binding var isDropTargeted: Bool
    let activate: () -> Void
    let onDropTask: (UUID) -> Bool
    let isTaskAvailable: (UUID) -> Bool
    let onInvalidTask: () -> Void

    func makeNSView(context: Context) -> InventoryPreviewInteractionView { InventoryPreviewInteractionView(frame: .zero) }

    func updateNSView(_ view: InventoryPreviewInteractionView, context: Context) {
        view.taskID = taskID
        view.enabled = enabled
        view.onActivate = activate
        view.onDropTask = onDropTask
        view.isTaskAvailable = isTaskAvailable
        view.onInvalidTask = onInvalidTask
        view.onTargetChanged = { isDropTargeted = $0 }
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(L10n.text("点击进入或添加窗口；拖动已占用的预览区到其他槽位可插入排序。"))
        view.setAccessibilityEnabled(enabled)
        view.toolTip = taskID == nil ? L10n.text("点击添加窗口") : L10n.text("点击进入任务；拖到其他槽位预览区调整顺序")
    }
}

private final class InventoryPreviewInteractionView: NSView, NSDraggingSource {
    var taskID: UUID?
    var enabled = true
    var onActivate: (() -> Void)?
    var onDropTask: ((UUID) -> Bool)?
    var isTaskAvailable: ((UUID) -> Bool)?
    var onInvalidTask: (() -> Void)?
    var onTargetChanged: ((Bool) -> Void)?
    private var gesture: InventoryPreviewGesture?
    private var mouseDownEvent: NSEvent?
    private var incomingTaskID: UUID?
    private var highlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([TaskDragPayload.pasteboardType])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp(L10n.text("点击进入或添加窗口；拖动已占用的预览区到其他槽位可插入排序。"))
    }

    required init?(coder: NSCoder) { nil }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if enabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        gesture = InventoryPreviewGesture(taskID: taskID, origin: convert(event.locationInWindow, from: nil))
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard enabled, var gesture, let mouseDownEvent else { return }
        let draggedTaskID = gesture.move(to: convert(event.locationInWindow, from: nil))
        self.gesture = gesture
        guard let draggedTaskID else { return }
        guard draggedTaskID == taskID, isTaskAvailable?(draggedTaskID) == true else { onInvalidTask?(); return }
        let item = NSDraggingItem(pasteboardWriter: TaskDragPayload.pasteboardItem(for: draggedTaskID))
        let size = NSSize(width: min(180, max(90, bounds.width * 0.55)), height: 48)
        item.setDraggingFrame(NSRect(x: gesture.origin.x - size.width / 2, y: gesture.origin.y - size.height / 2,
                                     width: size.width, height: size.height), contents: dragImage(size: size))
        let session = beginDraggingSession(with: [item], event: mouseDownEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { gesture = nil; mouseDownEvent = nil }
        guard enabled, let gesture,
              gesture.shouldActivate(at: convert(event.locationInWindow, from: nil), bounds: bounds, currentTaskID: taskID) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }
        onActivate?()
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        gesture = nil
        mouseDownEvent = nil
        clearIncomingDrop()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateIncomingDrop(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateIncomingDrop(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearIncomingDrop() }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { updateIncomingDrop(sender) == .move }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearIncomingDrop() }
        guard enabled, sender.draggingSource != nil,
              let data = sender.draggingPasteboard.data(forType: TaskDragPayload.pasteboardType),
              let taskID = TaskDragPayload.decode(data), taskID != self.taskID else { return false }
        guard isTaskAvailable?(taskID) == true else { onInvalidTask?(); return false }
        return onDropTask?(taskID) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { clearIncomingDrop() }

    private func updateIncomingDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard enabled, sender.draggingSource != nil, sender.draggingSourceOperationMask.contains(.move),
              let data = sender.draggingPasteboard.data(forType: TaskDragPayload.pasteboardType),
              let taskID = TaskDragPayload.decode(data), taskID != self.taskID,
              isTaskAvailable?(taskID) == true else { clearIncomingDrop(); return [] }
        incomingTaskID = taskID
        setHighlighted(true)
        return .move
    }

    private func clearIncomingDrop() { incomingTaskID = nil; setHighlighted(false) }

    private func setHighlighted(_ value: Bool) {
        guard highlighted != value else { return }
        highlighted = value
        onTargetChanged?(value)
    }

    private func dragImage(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.withAlphaComponent(0.95).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            (L10n.text("移动任务") as NSString).draw(in: NSRect(x: 8, y: 14, width: rect.width - 16, height: 21),
                withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white,
                                 .paragraphStyle: paragraph])
            return true
        }
    }
}

struct InventoryBackdrop: View {
    let theme: ThemeDefinition
    let decorations: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: theme.background)
                if decorations, let illustration = ThemeResources.shared.image(theme.artwork) {
                    Image(nsImage: illustration).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.1)
                }
                if decorations, let frame = ThemeResources.shared.image("skins/native-v2/\(theme.slug)/frame.png") {
                    Image(nsImage: frame).resizable(capInsets: EdgeInsets(top: 23, leading: 23, bottom: 23, trailing: 23))
                        .opacity(0.34)
                }
                Rectangle().strokeBorder(Color(nsColor: theme.border).opacity(0.6), lineWidth: 1).padding(5)
                Rectangle().strokeBorder(Color(nsColor: theme.accent).opacity(0.22), lineWidth: 0.5).padding(8)
            }
        }.allowsHitTesting(false)
    }
}

private struct InventoryFlower: View {
    let color: Color
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Ellipse().strokeBorder(color, lineWidth: 1)
                    .frame(width: 17, height: 45).offset(y: -13)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle().fill(color).frame(width: 5, height: 5)
        }
    }
}

private func inventoryNumber(_ number: Int, theme: ThemeDefinition) -> String {
    if !["ink", "arsenal", "relic"].contains(theme.family) {
        return ["tactical", "protocol"].contains(theme.family) ? String(format: "%02d", number) : String(number)
    }
    let values = [L10n.text("壹"), L10n.text("贰"), L10n.text("叁"), L10n.text("肆"), L10n.text("伍"), L10n.text("陆"), L10n.text("柒"), L10n.text("捌"), L10n.text("玖")]
    return values.indices.contains(number - 1) ? values[number - 1] : String(number)
}
