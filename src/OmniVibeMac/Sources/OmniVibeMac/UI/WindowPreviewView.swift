import AppKit
import SwiftUI
import OmniVibeCore

/// Displays only the image that the service positively matched to this live
/// window token. The inventory can keep its existing task button around this
/// view by disabling the embedded permission control and using one footer
/// control instead.
@MainActor
struct WindowPreviewView: View {
    @ObservedObject var localization = AppLocalization.shared
    let window: WindowIdentity
    @ObservedObject var service: WindowPreviewService
    let theme: ThemeDefinition
    var showPermissionButton = true

    var body: some View {
        ZStack {
            Color(nsColor: theme.background).opacity(0.45)
            if let image = service.images[window.id] {
                Image(nsImage: image).resizable().scaledToFit()
                    .accessibilityLabel(L10n.text("\(window.applicationName) · 指定窗口预览"))
                    .allowsHitTesting(false)
                VStack {
                    Spacer()
                    HStack {
                        Text(L10n.text("窗口预览 · 低频更新"))
                            .font(.system(size: 8)).foregroundStyle(Color(nsColor: theme.muted))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(nsColor: theme.background).opacity(0.86))
                        Spacer()
                    }
                }.allowsHitTesting(false)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 20, weight: .ultraLight))
                        .foregroundStyle(Color(nsColor: theme.muted).opacity(0.7))
                    Text(L10n.errorText(service.placeholder(for: window)))
                        .font(.system(size: 10)).multilineTextAlignment(.center)
                        .foregroundStyle(Color(nsColor: theme.muted))
                        .lineLimit(3)
                    if showPermissionButton && service.supported && !service.enabled {
                        Button(L10n.text("开启窗口预览")) { service.requestAccess() }
                            .font(.system(size: 10)).buttonStyle(.borderless)
                            .foregroundStyle(Color(nsColor: theme.accent))
                            .help(L10n.text("只预览已绑定的具体窗口，需要你在 macOS 中授予屏幕录制权限。"))
                    }
                }.padding(12)
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .environment(\.locale, localization.locale)
    }
}
