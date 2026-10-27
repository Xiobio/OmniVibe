import AppKit
import Carbon
import SwiftUI

@MainActor
struct WindowBehaviorSettingsView: View {
    @ObservedObject var localization = AppLocalization.shared
    @ObservedObject var controller: ApplicationController
    @ObservedObject var appearance: AppearanceModel
    private var theme: ThemeDefinition { appearance.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("窗口与任务操作")).font(.custom("STKaiti", size: 23))
            caption(L10n.text("以下设置修改后立即生效；主题与声音草稿仍使用底部保存按钮。"))
            box(L10n.text("界面语言")) {
                Picker(L10n.text("语言"), selection: Binding(get: { localization.language }, set: { _ = localization.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }.pickerStyle(.segmented)
                caption(L10n.text("语言选择立即生效，不修改任务名称、文件路径或终端配置。"))
                if let warning = localization.warning { warningText(warning) }
            }
            box(L10n.text("收纳与唤醒")) {
                Picker(L10n.text("进入任务时"), selection: binding(\.wakeMode)) {
                    Text(L10n.text("返回上次位置")).tag(WindowBehaviorPreferences.WakeMode.lastPosition)
                    Text(L10n.text("铺满所在屏幕工作区")).tag(WindowBehaviorPreferences.WakeMode.workArea)
                }
                Toggle(L10n.text("收纳后最小化原窗口"), isOn: binding(\.minimizeOnCapture))
                caption(L10n.text("移出管理会保留原窗口；再次进入任务时按所选方式唤醒。"))
            }
            box(L10n.text("排列与界面大小")) {
                HStack {
                    Text(L10n.text("窗口间距")).frame(width: 100, alignment: .leading)
                    Slider(value: binding(\.layoutGap), in: 0...40, step: 1)
                    Text("\(Int(controller.windowBehavior.layoutGap)) pt").monospacedDigit().frame(width: 50)
                }
                Toggle(L10n.text("排列窗口时隐藏悬浮入口"), isOn: binding(\.hideLauncherOnArrange))
                Picker(L10n.text("任务总览大小"), selection: binding(\.overviewSize)) {
                    Text(L10n.text("小")).tag(WindowBehaviorPreferences.OverviewSize.small)
                    Text(L10n.text("中")).tag(WindowBehaviorPreferences.OverviewSize.medium)
                    Text(L10n.text("大")).tag(WindowBehaviorPreferences.OverviewSize.large)
                }.pickerStyle(.segmented)
                HStack {
                    Text(L10n.text("展开轮盘大小")).frame(width: 100, alignment: .leading)
                    Slider(value: binding(\.launcherExtent), in: 280...520, step: 20)
                    Text("\(Int(controller.windowBehavior.launcherExtent)) pt").monospacedDigit().frame(width: 55)
                }
            }
            box(L10n.text("快捷键与滚轮")) {
                Toggle(L10n.text("暂停全部全局快捷键与滚轮切换"), isOn: binding(\.shortcutsPaused))
                Toggle(L10n.text("按住修饰键并滚动，循环切换任务"), isOn: binding(\.wheelSwitchEnabled))
                HStack(spacing: 13) {
                    modifier("⌃ Control", UInt32(controlKey))
                    modifier("⌥ Option", UInt32(optionKey))
                    modifier("⇧ Shift", UInt32(shiftKey))
                    modifier("⌘ Command", UInt32(cmdKey))
                }
                caption(L10n.text("至少选择一个修饰键。只有匹配组合时才处理纵向滚动；暂停和录制快捷键时保持普通滚动。"))
                HStack {
                    Button(L10n.text("滚轮权限设置")) { controller.openScrollPermissionSettings() }
                    Button(L10n.text("重新注册快捷键")) { controller.retryShortcuts() }
                }
                if let warning = controller.hotKeyWarning { warningText(L10n.errorText(warning)) }
            }
            box(L10n.text("完成提醒")) {
                Toggle(L10n.text("播放任务完成提示音"), isOn: binding(\.completionSoundEnabled))
                Toggle(L10n.text("发送系统任务通知"), isOn: Binding(get: { controller.windowBehavior.systemNotificationsEnabled }, set: { enabled in
                    if enabled { controller.requestSystemNotifications() }
                    else { controller.updateWindowBehavior { $0.systemNotificationsEnabled = false } }
                })).disabled(controller.isDemo)
                caption(L10n.text("提示音沿用“声音”页面的总开关与音量。系统通知只包含任务标题与状态。"))
                if let status = controller.notificationStatus { caption(status) }
                else { caption(L10n.text("开启系统通知时才向 macOS 申请授权。")) }
                Button(L10n.text("申请或检查通知权限")) { controller.requestSystemNotifications() }.disabled(controller.isDemo)
            }
            box(L10n.text("连接与恢复")) {
                Toggle(L10n.text("启动时重新连接仍在运行的原窗口"), isOn: binding(\.autoReconnectExisting))
                Toggle(L10n.text("启动时显示待恢复记录"), isOn: binding(\.showRecoveryOnStartup))
                Toggle(L10n.text("启动时自动恢复可确认的窗口状态"), isOn: binding(\.autoRestoreRecovery))
                caption(L10n.text("只连接可确认身份的原窗口。未能恢复的记录会保留，供稍后重试。"))
                Text(L10n.text("待恢复记录：\(controller.recoveryCount)")).fontWeight(.medium)
                if let warning = controller.recoveryWarning { warningText(L10n.errorText(warning)) }
                HStack(spacing: 12) {
                    Button(L10n.text("重新连接原窗口")) { controller.reconnectExistingTasks() }.disabled(controller.isDemo)
                    Button(L10n.text("恢复待处理窗口")) { controller.restorePendingRecovery() }
                        .disabled(controller.isDemo || controller.recoveryCount == 0)
                    Button(L10n.text("归档并跳过恢复")) { controller.archiveAndSkipPendingRecovery() }
                        .disabled(controller.isDemo || controller.recoveryCount == 0)
                }
            }
            if let warning = controller.windowBehaviorWarning { warningText(L10n.errorText(warning)) }
        }.font(.system(size: 12)).toggleStyle(.checkbox)
            .environment(\.locale, localization.locale)
    }

    private func binding<Value>(_ path: WritableKeyPath<WindowBehaviorPreferences, Value>) -> Binding<Value> {
        Binding(get: { controller.windowBehavior[keyPath: path] }, set: { value in
            controller.updateWindowBehavior { $0[keyPath: path] = value }
        })
    }

    private func modifier(_ label: String, _ mask: UInt32) -> some View {
        Toggle(label, isOn: Binding(get: { controller.windowBehavior.wheelModifiers & mask != 0 }, set: { enabled in
            let current = controller.windowBehavior.wheelModifiers
            let selected = enabled ? current | mask : current & ~mask
            guard selected != 0 else { return }
            controller.updateWindowBehavior { $0.wheelModifiers = selected }
        }))
        .disabled(!controller.windowBehavior.wheelSwitchEnabled || controller.windowBehavior.wheelModifiers == mask)
    }

    private func caption(_ text: String) -> some View {
        Text(L10n.errorText(text)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func warningText(_ text: String) -> some View {
        Text(L10n.errorText(text)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }

    private func box<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(title)).font(.system(size: 15, weight: .semibold))
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: theme.surface).opacity(0.65))
            .overlay(Rectangle().strokeBorder(Color(nsColor: theme.border).opacity(0.5)).allowsHitTesting(false))
    }
}
