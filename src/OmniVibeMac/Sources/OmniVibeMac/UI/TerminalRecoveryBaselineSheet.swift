import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct TerminalRecoveryBaselineSheet: View {
    @ObservedObject var appearance: AppearanceModel
    @ObservedObject private var localization = AppLocalization.shared
    let onClose: () -> Void
    @State private var selectedProfiles: [TerminalProfileTabKey: Int] = [:]
    @State private var exportedFiles: [TerminalProfileTabKey: URL] = [:]
    @State private var confirmed = false

    private var theme: ThemeDefinition { appearance.theme }
    private var options: TerminalRecoveryBaselineOptions? { appearance.terminalRecoveryOptions }
    private var canRegister: Bool {
        guard confirmed, let options, !options.unresolvedTabs.isEmpty else { return false }
        return options.unresolvedTabs.allSatisfy { tab in
            exportedFiles[tab.tab] != nil && options.profiles.contains {
                $0.id == selectedProfiles[tab.tab] && $0.name != tab.profile.name
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("指定 Terminal 恢复配置")).font(.system(size: 23, weight: .semibold))
            Text(L10n.text("Terminal 的部分标签页使用独立配置副本，无法自动定位原配置。请先导出各标签页的完整设置，再导入为独立且名称唯一的备份配置。这里登记你明确选择的恢复基准。"))
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("1. 选中原标签页，使用 Shell → 导出设置保存 .terminal 文件。\n2. 在设置 → 描述文件中导入该文件，将导入项重命名为唯一名称，例如“原配置备份 1”。\n3. 在下方选择对应的导出文件和已导入的备份配置。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let options {
                        if options.unresolvedTabs.isEmpty { Text(L10n.text("当前标签页无需手动登记恢复配置。")) }
                        ForEach(options.unresolvedTabs, id: \.tab) { tab in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.format("窗口 %d · %@", tab.tab.windowID, tab.tab.tty)).fontWeight(.semibold)
                                Text(L10n.format("当前配置：%@", tab.profile.name)).foregroundStyle(Color(nsColor: theme.muted))
                                Picker(L10n.text("恢复时使用"), selection: Binding<Int?>(get: { selectedProfiles[tab.tab] }, set: { selectedProfiles[tab.tab] = $0 })) {
                                    Text(L10n.text("选择名称唯一的已导入备份")).tag(Optional<Int>.none)
                                    ForEach(options.profiles.filter { $0.name != tab.profile.name }, id: \.id) { profile in
                                        Text(profile.name).tag(Optional(profile.id))
                                    }
                                }
                                HStack {
                                    Button(L10n.text("选择原导出文件…")) { chooseExport(for: tab.tab) }
                                    Text(exportedFiles[tab.tab]?.lastPathComponent ?? L10n.text("尚未选择文件"))
                                        .lineLimit(1).truncationMode(.middle)
                                }
                            }.font(.system(size: 12)).padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: theme.surface))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let status = appearance.terminalProfileStatus {
                Text(L10n.errorText(status)).font(.system(size: 11)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(L10n.text("我已导入所选完整文件，并同意按指定配置作为恢复基准"), isOn: $confirmed)
                .toggleStyle(.checkbox).font(.system(size: 11))
            HStack {
                Button(L10n.text("重新读取配置")) { appearance.loadTerminalRecoveryBaselines() }
                Spacer()
                Button(L10n.text("关闭"), action: onClose).keyboardShortcut(.cancelAction)
                Button(L10n.text("保存恢复基准"), action: register).buttonStyle(.borderedProminent)
                    .disabled(!canRegister)
            }.disabled(appearance.terminalThemeBusy)
        }.padding(24).frame(width: 710, height: 650)
            .foregroundStyle(Color(nsColor: theme.text))
            .background(Color(nsColor: theme.background))
            .tint(Color(nsColor: theme.accent))
            .environment(\.locale, localization.locale)
            .onAppear { appearance.loadTerminalRecoveryBaselines() }
    }

    private func chooseExport(for tab: TerminalProfileTabKey) {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择对应标签页导出的完整配置")
        panel.allowedContentTypes = [UTType(filenameExtension: "terminal") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { exportedFiles[tab] = url }
    }

    private func register() {
        guard canRegister, let options else { return }
        let choices = options.unresolvedTabs.compactMap { tab -> TerminalRecoveryBaselineChoice? in
            guard let file = exportedFiles[tab.tab],
                  let profile = options.profiles.first(where: { $0.id == selectedProfiles[tab.tab] }) else { return nil }
            return TerminalRecoveryBaselineChoice(sessionID: options.sessionID, tab: tab.tab, observedProfile: tab.profile,
                persistentProfile: profile, exportedProfileURL: file)
        }
        appearance.registerTerminalRecoveryBaselines(choices) { success in if success { onClose() } }
    }
}
