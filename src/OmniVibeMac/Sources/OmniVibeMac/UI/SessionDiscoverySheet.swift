import SwiftUI
import OmniVibeCore

@MainActor
struct SessionDiscoverySheet: View {
    let slot: TaskSlot
    @ObservedObject var appearance: AppearanceModel
    @ObservedObject private var localization = AppLocalization.shared
    var providerFilter: String? = nil
    var operationFailure: String? = nil
    var onClose: () -> Void
    var onSelect: (DiscoveredAgentSession) -> Void
    @State private var sessions: [DiscoveredAgentSession] = []
    @State private var warnings: [String] = []
    @State private var selectedID: String?
    @State private var search = ""
    @State private var isLoading = false
    private var filtered: [DiscoveredAgentSession] {
        sessions.filter { session in
            (providerFilter == nil || session.provider == providerFilter) &&
            (search.isEmpty || [session.title, session.projectDirectory, session.sessionID, session.providerLabel]
                .contains(where: { $0.localizedCaseInsensitiveContains(search) }))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text("选择本地 CLI 会话")).font(.custom("STKaiti", size: 24))
                Spacer()
                Button(L10n.text("刷新")) { Task { await refresh() } }.disabled(isLoading)
            }
            Text(L10n.format("第 %d 槽 · 请明确选择这个任务对应的会话", slot.number)).font(.system(size: 12))
            Text(L10n.text("仅显示会话 ID、项目、名称和时间，不显示或保存会话正文。关联时从当前记录末尾开始，之后跟踪新状态；不会因标题相似自动认领。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.muted))
                .fixedSize(horizontal: false, vertical: true)
            TextField(L10n.text("搜索项目、会话名称或 ID"), text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if isLoading && sessions.isEmpty { ProgressView().padding(35) }
                    else if filtered.isEmpty {
                        Text(L10n.text("尚未发现符合条件的本地会话。可先启动 CLI，或在启动配置中填写确切会话 UUID。"))
                            .font(.system(size: 12)).foregroundStyle(Color(nsColor: appearance.theme.muted)).padding(20)
                    }
                    ForEach(filtered) { session in
                        Button {
                            selectedID = session.id
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selectedID == session.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color(nsColor: selectedID == session.id ? appearance.theme.accent : appearance.theme.muted))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(session.providerLabel + " · " + session.title).font(.system(size: 13, weight: .medium))
                                    Text(session.projectDirectory).font(.system(size: 11)).lineLimit(2)
                                    HStack {
                                        Text(session.sessionID).font(.system(size: 10, design: .monospaced))
                                        Spacer()
                                        Text(session.modifiedAt, style: .date).font(.system(size: 10))
                                    }.foregroundStyle(Color(nsColor: appearance.theme.muted))
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: appearance.theme.surface).opacity(selectedID == session.id ? 1 : 0.6))
                                .overlay(Rectangle().strokeBorder(Color(nsColor: selectedID == session.id ? appearance.theme.accent : appearance.theme.border).opacity(0.5)))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(minHeight: 270, maxHeight: 380)
            ForEach(warnings, id: \.self) { warning in Text(L10n.errorText(warning)).font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.waiting)) }
            if let operationFailure {
                Text(L10n.errorText(operationFailure)).font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.waiting))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack {
                Text(L10n.format("%d 个本地会话", filtered.count)).font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.muted))
                Spacer()
                Button(L10n.text("取消"), action: onClose).keyboardShortcut(.cancelAction)
                Button(L10n.text("使用所选会话")) {
                    if let selected = filtered.first(where: { $0.id == selectedID }) { onSelect(selected) }
                }.keyboardShortcut(.defaultAction).disabled(!filtered.contains(where: { $0.id == selectedID }))
            }
        }.padding(25).frame(width: 740)
            .foregroundStyle(Color(nsColor: appearance.theme.text)).background(Color(nsColor: appearance.theme.background))
            .environment(\.locale, localization.locale)
            .preferredColorScheme(appearance.themeSlug == "wonderland" ? .light : .dark)
            .task { await refresh() }
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        let result = await SessionDiscoveryService().discover()
        sessions = result.sessions; warnings = result.warnings
        if !sessions.contains(where: { $0.id == selectedID }) { selectedID = nil }
    }
}
