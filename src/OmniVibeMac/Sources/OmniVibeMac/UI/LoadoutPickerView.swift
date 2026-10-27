import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OmniVibeCore

@MainActor
struct LoadoutPickerView: View {
    @ObservedObject var localization = AppLocalization.shared
    let slot: TaskSlot
    @ObservedObject var appearance: AppearanceModel
    var onClose: () -> Void
    @State private var selectedID: String?
    @State private var customURL: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("第 \(slot.number) 槽 · 配装"))
                        .font(.custom("STKaiti", size: 27))
                    Text(slot.displayName).font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: appearance.theme.muted))
                }
                Spacer()
                Button(L10n.text("导入自己的图片…")) { chooseImage() }
            }
            Text(L10n.text("\(appearance.theme.name) · 配装随主题独立保存，任务和窗口绑定保持原样。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.theme.muted))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(appearance.equipmentOptions) { option in
                    Button {
                        selectedID = option.id
                        customURL = nil
                    } label: {
                        VStack(spacing: 8) {
                            if let image = ThemeResources.shared.equipmentImage(option) {
                                Image(nsImage: image).resizable().scaledToFit().frame(height: 82)
                            }
                            Text(option.name).font(.system(size: 11)).lineLimit(1)
                        }
                        .padding(10).frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color(nsColor: appearance.theme.surface).opacity(0.65))
                        .overlay(Rectangle().strokeBorder(Color(nsColor: selectedID == option.id && customURL == nil
                            ? appearance.theme.accent : appearance.theme.border).opacity(selectedID == option.id && customURL == nil ? 1 : 0.35),
                                                          lineWidth: selectedID == option.id && customURL == nil ? 1.5 : 0.6))
                    }.buttonStyle(.plain)
                }
            }
            if let customURL {
                HStack(spacing: 12) {
                    if let image = NSImage(contentsOf: customURL) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 55, height: 45)
                    }
                    Text(L10n.text("待保存：\(customURL.lastPathComponent)")).font(.system(size: 11))
                }
            }
            if let error { Text(L10n.errorText(error)).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Text(L10n.text("取消不会修改配装。"))
                    .font(.system(size: 10)).foregroundStyle(Color(nsColor: appearance.theme.muted))
                Spacer()
                Button(L10n.text("取消"), action: onClose).keyboardShortcut(.cancelAction)
                Button(L10n.text("保存")) { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 670)
        .foregroundStyle(Color(nsColor: appearance.theme.text))
        .background(Color(nsColor: appearance.theme.background))
        .environment(\.locale, localization.locale)
        .preferredColorScheme(appearance.themeSlug == "wonderland" ? .light : .dark)
        .onAppear { selectedID = appearance.selectedEquipmentID(for: slot) }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择任务配装图片")
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { customURL = panel.url }
    }

    private func save() {
        do {
            if let customURL { try appearance.importCustomImage(customURL, for: slot) }
            else if let selectedID { appearance.setEquipment(selectedID, for: slot) }
            onClose()
        } catch { self.error = error.localizedDescription }
    }
}
