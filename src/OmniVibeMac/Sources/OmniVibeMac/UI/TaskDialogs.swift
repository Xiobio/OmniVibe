import AppKit
import SwiftUI
import OmniVibeCore

@MainActor
struct WindowPickerView: View {
    @ObservedObject var localization = AppLocalization.shared
    @ObservedObject var controller: ApplicationController
    @ObservedObject var appearance: AppearanceModel
    @State private var query = ""

    private var theme: ThemeDefinition { appearance.theme }
    private var filtered: [WindowIdentity] {
        controller.candidates.filter {
            query.isEmpty || ($0.applicationName + " " + $0.title).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("为第 \(controller.pickerSlot ?? 1) 槽收纳窗口"))
                        .font(.custom("STKaiti", size: 24))
                    Text(L10n.text("选择一个具体窗口；同一终端的多个窗口可分别收纳。"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                }
                Spacer()
                Button(L10n.text("刷新")) { controller.reloadCandidates() }
            }
            TextField(L10n.text("搜索应用或窗口标题"), text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "macwindow").font(.system(size: 28, weight: .light))
                            Text(L10n.text("暂无可收纳的窗口"))
                            Text(L10n.text("请先打开一个终端窗口，并为 OmniVibe 开启辅助功能权限。"))
                                .font(.system(size: 11)).multilineTextAlignment(.center)
                        }.foregroundStyle(Color(nsColor: theme.muted))
                            .frame(maxWidth: .infinity).padding(.vertical, 65)
                    }
                    ForEach(filtered) { candidate in
                        let bound = controller.candidateIsBound(candidate)
                        Button { controller.bind(candidate) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(Color(nsColor: theme.accent))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.title).font(.system(size: 13, weight: .medium))
                                        .lineLimit(1).truncationMode(.middle)
                                    Text(candidate.applicationName).font(.system(size: 10))
                                        .foregroundStyle(Color(nsColor: theme.muted))
                                }
                                Spacer()
                                Text(bound ? L10n.text("已收纳到其他槽位") : L10n.text("收纳"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(nsColor: bound ? theme.muted : theme.accent))
                            }
                            .padding(14).background(Color(nsColor: theme.surface))
                            .overlay(Rectangle().strokeBorder(Color(nsColor: theme.border).opacity(0.5)))
                        }.buttonStyle(.plain).disabled(bound)
                    }
                }
            }
            if let notice = controller.notice {
                Text(L10n.errorText(notice)).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)
            }
            HStack {
                Text(L10n.text("收纳不会结束终端或其中的任务。"))
                    .font(.system(size: 10)).foregroundStyle(Color(nsColor: theme.muted))
                Spacer()
                Button(L10n.text("新建或继续任务…"), action: controller.requestLaunchFromPicker)
                Button(L10n.text("取消")) { controller.pickerSlot = nil }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(26).frame(width: 680, height: 510)
        .foregroundStyle(Color(nsColor: theme.text))
        .background(Color(nsColor: theme.background))
        .environment(\.locale, localization.locale)
        .preferredColorScheme(appearance.themeSlug == "wonderland" ? .light : .dark)
        .tint(Color(nsColor: theme.accent))
    }
}

@MainActor
struct RenameTaskSheet: View {
    @ObservedObject var localization = AppLocalization.shared
    @ObservedObject var controller: ApplicationController
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("编辑任务名称")).font(.custom("STKaiti", size: 24))
            TextField(L10n.text("任务名称"), text: $controller.renameText)
                .textFieldStyle(.roundedBorder).onSubmit { controller.finishRenaming() }
            HStack {
                Spacer()
                Button(L10n.text("取消")) { controller.renameSlot = nil }.keyboardShortcut(.cancelAction)
                Button(L10n.text("保存")) { controller.finishRenaming() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 400)
        .foregroundStyle(Color(nsColor: appearance.theme.text))
        .background(Color(nsColor: appearance.theme.background))
        .environment(\.locale, localization.locale)
        .preferredColorScheme(appearance.themeSlug == "wonderland" ? .light : .dark)
    }
}
