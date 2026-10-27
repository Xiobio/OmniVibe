import SwiftUI

@MainActor
struct RecentTasksSheet: View {
    @ObservedObject var localization = AppLocalization.shared
    @ObservedObject var controller: ApplicationController
    @ObservedObject var appearance: AppearanceModel
    let onClose: () -> Void
    private var theme: ThemeDefinition { appearance.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("最近关闭的任务")).font(.custom("STKaiti", size: 26))
                    Text(L10n.text("自动归档最近 30 个关闭的任务；手动移出管理不会归档。"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                }
                Spacer()
                Button(L10n.text("关闭"), action: onClose).buttonStyle(.borderless)
            }
            Text(L10n.text("恢复任务可重新选择现有窗口；启动／继续会按项目配置创建新的 Terminal 任务，并可续接原会话。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                .fixedSize(horizontal: false, vertical: true)
            if let warning = controller.recentTasksWarning {
                Text(L10n.errorText(warning)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if let failure = controller.taskOperationFailure {
                Text(L10n.errorText(failure)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if controller.recentTasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 25, weight: .light))
                    Text(L10n.text("还没有自动归档的任务")).font(.system(size: 13))
                }.foregroundStyle(Color(nsColor: theme.muted))
                    .frame(maxWidth: .infinity, minHeight: 170)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(controller.recentTasks) { record in
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.task.displayName).font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1).help(record.task.displayName)
                                    Text((record.task.window?.applicationName ?? L10n.text("原应用")) + L10n.text(" · 原 \(record.task.number) 号槽位"))
                                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                                    Text(L10n.text("关闭于 ") + record.closedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(localization.locale)))
                                        .font(.system(size: 10)).foregroundStyle(Color(nsColor: theme.muted))
                                }
                                Spacer(minLength: 12)
                                Button(L10n.text("恢复任务")) {
                                    if controller.restoreRecentTask(record.id) { onClose() }
                                }.disabled(controller.isDemo)
                                if controller.canLaunchRecentTask(record.id) {
                                    Button(L10n.text("启动／继续…")) {
                                        if controller.requestLaunchRecentTask(record.id) { onClose() }
                                    }.disabled(controller.isDemo || controller.taskLaunchBusy)
                                }
                            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: theme.surface).opacity(0.75))
                                .overlay(Rectangle().strokeBorder(Color(nsColor: theme.border).opacity(0.45)).allowsHitTesting(false))
                        }
                    }
                }.frame(maxHeight: 390)
            }
        }.padding(25).frame(width: 670)
            .foregroundStyle(Color(nsColor: theme.text))
            .background(Color(nsColor: theme.background))
            .tint(Color(nsColor: theme.accent))
            .environment(\.locale, localization.locale)
            .preferredColorScheme(theme.slug == "wonderland" ? .light : .dark)
            .onExitCommand(perform: onClose)
    }
}
