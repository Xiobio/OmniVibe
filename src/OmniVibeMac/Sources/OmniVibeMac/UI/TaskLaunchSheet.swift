import AppKit
import SwiftUI
import OmniVibeCore

@MainActor
struct TaskLaunchSheet: View {
    let slot: TaskSlot
    @ObservedObject var appearance: AppearanceModel
    @ObservedObject private var localization = AppLocalization.shared
    var isLaunching: Bool
    var operationFailure: String?
    var onClose: () -> Void
    var onLaunch: (TaskLaunchConfiguration) -> Void
    var onSave: ((TaskLaunchConfiguration) -> Void)?
    @State private var configuration: TaskLaunchConfiguration
    @State private var selectingSession = false
    @State private var validationMessage: String?

    init(slot: TaskSlot, initial: TaskLaunchConfiguration? = nil, appearance: AppearanceModel,
         isLaunching: Bool = false, operationFailure: String? = nil, onClose: @escaping () -> Void,
         onLaunch: @escaping (TaskLaunchConfiguration) -> Void,
         onSave: ((TaskLaunchConfiguration) -> Void)? = nil) {
        self.slot = slot; self.appearance = appearance; self.isLaunching = isLaunching; self.operationFailure = operationFailure
        self.onClose = onClose; self.onLaunch = onLaunch
        self.onSave = onSave
        _configuration = State(initialValue: initial ?? TaskLaunchConfiguration(executablePath: TaskLaunchConfiguration.defaultExecutable(for: .codex)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.format("第 %d 槽 · 启动或继续任务", slot.number)).font(.custom("STKaiti", size: 24))
            if slot.window != nil { Text(slot.displayName).font(.system(size: 12)).foregroundStyle(Color(nsColor: appearance.theme.muted)) }
            Text(L10n.text("选择项目和程序。点击启动后会新建一个 Terminal 窗口，确认并保存窗口绑定后再启动程序。"))
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Picker(L10n.text("启动方式"), selection: $configuration.mode) {
                ForEach(TaskLaunchMode.allCases) { mode in Text(mode.label).tag(mode) }
            }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("项目目录")).font(.system(size: 12, weight: .medium))
                HStack {
                    TextField(L10n.text("选择项目目录"), text: $configuration.projectDirectory).textFieldStyle(.roundedBorder)
                    Button(L10n.text("选择…")) { chooseDirectory() }
                }
                Text(L10n.text(configuration.mode == .terminal ? "Shell 可执行文件" : "CLI 可执行文件"))
                    .font(.system(size: 12, weight: .medium)).padding(.top, 3)
                HStack {
                    TextField(L10n.text("选择可执行文件的绝对路径"), text: $configuration.executablePath).textFieldStyle(.roundedBorder)
                    Button(L10n.text("选择…")) { chooseExecutable() }
                }
                if configuration.mode != .terminal {
                    Text(L10n.text("继续已有会话（可选）")).font(.system(size: 12, weight: .medium)).padding(.top, 3)
                    HStack {
                        TextField(L10n.text("留空新建，或填写确切会话 UUID"), text: $configuration.resumeSessionID)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                        Button(L10n.text("发现本地会话…")) { selectingSession = true }
                    }
                }
            }.disabled(isLaunching)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("将执行")).font(.system(size: 12, weight: .medium))
                Text(preview).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Text(configuration.projectDirectory).font(.system(size: 11)).textSelection(.enabled)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: appearance.theme.surface))
            Text(L10n.text("会话启动沿用 CLI 自身的授权与信任提示，不会自动提交提示词或绕过权限。已保存的配置可用于窗口关闭后的再次启动。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.muted))
                .fixedSize(horizontal: false, vertical: true)
            if let validationMessage {
                Text(L10n.errorText(validationMessage)).font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.waiting))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let operationFailure {
                Text(L10n.errorText(operationFailure)).font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.waiting))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack {
                if isLaunching { ProgressView().controlSize(.small); Text(L10n.text("正在确认新窗口…")).font(.system(size: 11)) }
                Spacer()
                Button(L10n.text("取消"), action: onClose).keyboardShortcut(.cancelAction).disabled(isLaunching)
                if let onSave {
                    Button(L10n.text("保存启动配置")) {
                        do { _ = try configuration.validated(); validationMessage = nil; onSave(configuration) }
                        catch { validationMessage = error.localizedDescription }
                    }.keyboardShortcut(.defaultAction).disabled(isLaunching)
                } else {
                    Button(L10n.text(configuration.resumeSessionID.isEmpty ? "启动任务" : "继续所选会话")) {
                        do { _ = try configuration.validated(); validationMessage = nil; onLaunch(configuration) }
                        catch { validationMessage = error.localizedDescription }
                    }.keyboardShortcut(.defaultAction).disabled(isLaunching)
                }
            }
        }.padding(26).frame(width: 700)
            .foregroundStyle(Color(nsColor: appearance.theme.text)).background(Color(nsColor: appearance.theme.background))
            .environment(\.locale, localization.locale)
            .preferredColorScheme(appearance.themeSlug == "wonderland" ? .light : .dark)
            .onChange(of: configuration.mode) { mode in
                configuration.executablePath = TaskLaunchConfiguration.defaultExecutable(for: mode)
                configuration.resumeSessionID = ""; validationMessage = nil
            }
            .sheet(isPresented: $selectingSession) {
                SessionDiscoverySheet(slot: slot, appearance: appearance, providerFilter: configuration.mode.rawValue,
                    onClose: { selectingSession = false }, onSelect: { session in
                        configuration.projectDirectory = session.projectDirectory
                        configuration.resumeSessionID = session.sessionID
                        selectingSession = false
                    })
            }
    }

    private var preview: String {
        var arguments = [configuration.executablePath]
        if !configuration.resumeSessionID.isEmpty {
            arguments += configuration.mode == .codex ? ["resume", configuration.resumeSessionID] : ["--resume", configuration.resumeSessionID]
        }
        return arguments.map(AgentIntegration.quote).joined(separator: " ")
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = L10n.text("选择任务的项目目录")
        if panel.runModal() == .OK, let url = panel.url { configuration.projectDirectory = url.path; validationMessage = nil }
    }
    private func chooseExecutable() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = L10n.text("选择要运行的 CLI 或 Shell 可执行文件")
        if panel.runModal() == .OK, let url = panel.url { configuration.executablePath = url.path; validationMessage = nil }
    }
}
