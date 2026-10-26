import AppKit
import SwiftUI
import OmniVibeCore

@MainActor
struct AgentIntegrationSheet: View {
    @ObservedObject var localization = AppLocalization.shared
    let slot: TaskSlot
    @ObservedObject var appearance: AppearanceModel
    var onClose: () -> Void
    @State private var provider = AgentProvider.codex
    @State private var directory = ""
    @State private var resume = false
    @State private var copied = false

    private var command: String {
        AgentIntegration.connectionCommand(executable: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]),
            taskID: slot.id, provider: provider, root: WorkspaceStore().root,
            directory: directory, resume: resume ? slot.sessionID : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("第 \(slot.number) 槽 · 连接自动任务状态")).font(.custom("STKaiti", size: 25))
            Text(slot.displayName).font(.system(size: 12)).foregroundStyle(Color(nsColor: appearance.theme.muted))
            Picker("CLI", selection: $provider) {
                ForEach(AgentProvider.allCases) { item in Text(L10n.text(item.label)).tag(item) }
            }.pickerStyle(.segmented)
            Text(L10n.text("在对应终端中运行以下命令，继续使用原来的 CLI 工作方式。收到真实事件后，轮盘与图录会显示运行、等待或本轮已回复。"))
                .font(.system(size: 12)).lineSpacing(4)
            HStack {
                TextField(L10n.text("项目目录（留空沿用终端当前目录）"), text: $directory).textFieldStyle(.roundedBorder)
                Button(L10n.text("选择…")) { chooseDirectory() }
            }
            if !slot.sessionID.isEmpty && provider.rawValue == slot.agentProvider {
                Toggle(L10n.text("继续已关联的会话"), isOn: $resume).toggleStyle(.checkbox)
            }
            ScrollView {
                Text(command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(13)
            }.frame(height: 130).background(Color(nsColor: appearance.theme.surface))
                .overlay(Rectangle().strokeBorder(Color(nsColor: appearance.theme.border).opacity(0.5)))
            if provider == .codex {
                Text(L10n.text("Codex 首次运行后，用 /hooks 查看并信任本地状态观察器；此连接命令不会绕过 CLI 的授权设置。"))
                    .font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.muted))
            }
            Text(L10n.text("观察器只记录状态事件，不批准工具操作，也不保存提示词正文。重新绑定槽位后，请复制新的连接命令。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.muted))
            HStack {
                Text(slot.integrationConnected ? L10n.text("已收到该任务的状态事件") : L10n.text("尚未收到状态事件"))
                    .font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.muted))
                Spacer()
                Button(L10n.text("关闭"), action: onClose).keyboardShortcut(.cancelAction)
                Button(copied ? L10n.text("已复制") : L10n.text("复制连接命令")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 690)
            .foregroundStyle(Color(nsColor: appearance.theme.text))
            .background(Color(nsColor: appearance.theme.background))
            .environment(\.locale, localization.locale)
        .preferredColorScheme(appearance.themeSlug == "wonderland" ? .light : .dark)
            .onAppear { provider = AgentProvider(rawValue: slot.agentProvider) ?? .codex }
            .onChange(of: provider) { _ in copied = false; resume = false }
            .onChange(of: directory) { _ in copied = false }
            .onChange(of: resume) { _ in copied = false }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { directory = panel.url?.path ?? "" }
    }
}
