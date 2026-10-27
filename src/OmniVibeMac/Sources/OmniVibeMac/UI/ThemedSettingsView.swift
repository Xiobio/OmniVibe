import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ThemedSettingsView: View {
    @ObservedObject var localization = AppLocalization.shared
    @ObservedObject var controller: ApplicationController
    @ObservedObject var appearance: AppearanceModel
    let onClose: () -> Void
    @State private var section: SettingsSection = .appearance
    @State private var draftTheme = "relic"
    @State private var draftDecorations = true
    @State private var draftAnimate = true
    @State private var draftSoundEnabled = true
    @State private var draftSoundVolume = 0.45
    @State private var draftSignatureURL: URL?
    @State private var soundError: String?
    @State private var audition: ThemeAudio?
    @State private var editingShortcut: ShortcutAction?
    @State private var showingTerminalRecovery = false

    private var theme: ThemeDefinition { appearance.theme }
    private var preview: ThemeDefinition { appearance.availableThemes.first { $0.slug == draftTheme } ?? theme }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("OMNIVIBE / 工作台")).font(.system(size: 9)).foregroundStyle(Color(nsColor: theme.muted))
                    Text(L10n.text("设置")).font(.custom("STKaiti", size: 27))
                }
                Spacer()
                if !controller.permissionGranted && !controller.isDemo {
                    Button(L10n.text("开启窗口控制权限")) { section = .general }
                        .font(.system(size: 11)).buttonStyle(.bordered)
                }
            }.padding(.horizontal, 24).padding(.vertical, 17)
            Rectangle().fill(Color(nsColor: theme.border).opacity(0.45)).frame(height: 0.7)
            HStack(spacing: 0) {
                navigation.frame(width: 158)
                Rectangle().fill(Color(nsColor: theme.border).opacity(0.35)).frame(width: 0.7)
                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        switch section {
                        case .appearance: appearancePage
                        case .general: generalPage
                        case .shortcuts: shortcutsPage
                        case .audio: audioPage
                        }
                    }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Rectangle().fill(Color(nsColor: theme.border).opacity(0.45)).frame(height: 0.7)
            HStack(spacing: 18) {
                Text(L10n.text("外观与声音草稿保存后应用；通用与快捷键设置即时生效"))
                    .font(.custom("STKaiti", size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                Spacer()
                Button(L10n.text("恢复外观与声音默认")) {
                    draftTheme = "relic"; draftDecorations = true; draftAnimate = true
                    draftSoundEnabled = true; draftSoundVolume = 0.45
                    draftSignatureURL = nil; soundError = nil; audition?.stop()
                }
                    .buttonStyle(.borderless)
                Button(L10n.text("取消"), action: onClose).buttonStyle(.borderless)
                Button(L10n.text("保存并应用"), action: apply)
                    .buttonStyle(.borderedProminent).tint(Color(nsColor: theme.accent))
                    .foregroundStyle(Color(nsColor: theme.background))
                    .disabled(appearance.terminalThemeBusy)
            }.font(.system(size: 12)).padding(.horizontal, 24).padding(.vertical, 16)
        }
        .foregroundStyle(Color(nsColor: theme.text))
        .background(Color(nsColor: theme.background))
        .tint(Color(nsColor: theme.accent))
        .environment(\.locale, localization.locale)
        .preferredColorScheme(theme.slug == "wonderland" ? .light : .dark)
        .frame(minWidth: 860, minHeight: 620)
        .onAppear {
            draftTheme = appearance.themeSlug; draftDecorations = appearance.decorations; draftAnimate = appearance.animate
            draftSoundEnabled = appearance.soundEnabled; draftSoundVolume = appearance.soundVolume
            if controller.permissionSettingsRequested { section = .general; controller.permissionSettingsRequested = false }
        }
        .onChange(of: controller.permissionSettingsRequested) { requested in
            if requested { section = .general; controller.permissionSettingsRequested = false }
        }
        .onChange(of: draftTheme) { _ in draftSignatureURL = nil; soundError = nil; audition?.stop() }
        .onDisappear { audition?.stop(); controller.endShortcutRecording() }
        .sheet(isPresented: Binding(get: { editingShortcut != nil }, set: { if !$0 { editingShortcut = nil; controller.endShortcutRecording() } })) {
            if let action = editingShortcut {
                ShortcutEditorSheet(controller: controller, appearance: appearance, action: action) { editingShortcut = nil }
            }
        }
        .onExitCommand(perform: onClose)
        .sheet(isPresented: $showingTerminalRecovery) {
            TerminalRecoveryBaselineSheet(appearance: appearance) { showingTerminalRecovery = false }
        }
    }

    private var navigation: some View {
        VStack(spacing: 8) {
            ForEach(SettingsSection.allCases) { item in
                Button { section = item } label: {
                    HStack {
                        Text(L10n.text(item.rawValue)).font(.system(size: 13))
                        Spacer()
                    }.padding(.horizontal, 16).padding(.vertical, 13)
                    .background(section == item ? Color(nsColor: theme.elevated) : Color.clear)
                    .overlay(alignment: .leading) {
                        if section == item { Rectangle().fill(Color(nsColor: theme.accent)).frame(width: 3) }
                    }
                }.buttonStyle(.plain)
            }
            Spacer()
        }.padding(.horizontal, 10).padding(.top, 23)
            .background(Color(nsColor: theme.surface).opacity(0.42))
    }

    private var appearancePage: some View {
        Group {
            pageHeading(L10n.text("主题与换装"), L10n.text("所有主题直接陈列，先点图片选风格，再应用到任务轮盘与图录。"))
            HStack(alignment: .top, spacing: 21) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("选择主题")).font(.system(size: 15, weight: .semibold))
                    Text(L10n.text("选中后点击右侧按钮，立即应用到轮盘与图录"))
                        .font(.system(size: 10)).foregroundStyle(Color(nsColor: theme.muted))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 8) {
                        ForEach(appearance.availableThemes) { item in
                            SettingsThemeTile(theme: item, selected: item.slug == draftTheme) { draftTheme = item.slug }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 11) {
                    Text(preview.name).font(.custom("STKaiti", size: 22))
                    Text(preview.subtitle).font(.system(size: 10)).foregroundStyle(Color(nsColor: theme.muted))
                    ZStack {
                        Color(nsColor: preview.background)
                        if let illustration = ThemeResources.shared.image(preview.artwork) {
                            Image(nsImage: illustration).resizable().scaledToFill()
                                .frame(width: 270, height: 180).clipped().opacity(0.65)
                        }
                        if let identity = ThemeResources.shared.identity(themeSlug: preview.slug) {
                            Image(nsImage: identity).resizable().scaledToFit().frame(width: 112, height: 112).shadow(color: .black.opacity(0.4), radius: 12, y: 5)
                        }
                    }.frame(width: 270, height: 180)
                        .overlay(Rectangle().strokeBorder(Color(nsColor: preview.accent).opacity(0.7)))
                    Text(L10n.text("主题素材预览")).font(.custom("STKaiti", size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                    HStack(spacing: 6) {
                        ForEach([preview.accent, preview.secondary, preview.running, preview.waiting], id: \.self) { color in
                            Capsule().fill(Color(nsColor: color)).frame(width: 28, height: 3)
                        }
                    }
                    Text("\(preview.dockTitle)\n\(preview.overviewTitle)")
                        .font(.custom("STKaiti", size: 14)).lineSpacing(6).padding(.top, 7)
                    Button(draftTheme == appearance.themeSlug ? L10n.text("当前主题已应用") : L10n.text("立即应用此主题")) {
                        appearance.setTheme(draftTheme)
                    }.buttonStyle(.bordered).disabled(draftTheme == appearance.themeSlug || appearance.terminalThemeBusy)
                    Text(appearance.terminalProfileLinked ? L10n.text("完整主题联动已开启，Terminal 应用成功后同步切换外观。") : L10n.text("应用轮盘与图录外观；下方可启用 Terminal 完整主题联动。"))
                        .font(.system(size: 10)).foregroundStyle(Color(nsColor: theme.muted))
                }.frame(width: 270, alignment: .leading)
            }
            terminalThemeControls
            settingsBox(L10n.text("Claude Code 主题")) {
                Text(L10n.text("生成当前配色对应的 OmniVibe 自定义主题；保留原文件备份。首次请在 Claude Code 的 /theme 中选择 OmniVibe，之后主题切换会更新同一文件。"))
                    .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                    .fixedSize(horizontal: false, vertical: true)
                Text(appearance.claudeThemePath).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button(appearance.claudeThemeLinked ? L10n.text("更新 Claude 主题") : L10n.text("生成并联动 Claude 主题")) { appearance.enableClaudeThemeLink() }
                    Button(L10n.text("恢复 Claude 原主题文件")) { appearance.restoreClaudeTheme() }
                }.disabled(controller.isDemo || appearance.terminalThemeBusy)
                if let status = appearance.claudeThemeStatus {
                    Text(L10n.errorText(status)).font(.system(size: 11)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            settingsBox(L10n.text("界面效果")) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(L10n.text("主题装饰 · 保留插画、器物底座与边框"), isOn: $draftDecorations)
                    Toggle(L10n.text("界面动画 · 展开与选中反馈"), isOn: $draftAnimate)
                }.toggleStyle(.checkbox).font(.system(size: 12))
            }
            if let warning = appearance.assetWarning {
                Text(L10n.errorText(warning)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
            }
        }
    }

    private var terminalThemeControls: some View {
        settingsBox(L10n.text("Terminal 完整主题 · 一次导入后联动")) {
            Text(L10n.text("当前主题：") + theme.name + (appearance.decorations ? L10n.text(" · 完整装饰") : L10n.text(" · 简洁")))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(nsColor: theme.accent))
            Text(L10n.text("13 个主题各有装饰与简洁两版，包含静态背景、16 色 ANSI、文字与光标颜色及字体。首次需在 Terminal 官方“设置 → 描述文件”中手动导入 26 个 .terminal 文件；导出只会打开 Finder 目录。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Button(L10n.text("1. 导出 26 套配置")) { appearance.prepareFullTerminalThemes() }
                Button(L10n.text("2. 检查导入")) { appearance.inspectTerminalProfiles() }
                Spacer(minLength: 0)
            }.disabled(controller.isDemo || appearance.terminalThemeBusy)
            HStack(spacing: 14) {
                Button(L10n.text("自动备份原配置")) { appearance.prepareAutomaticTerminalRecoveryBaselines() }
                    .buttonStyle(.borderedProminent)
                Text(L10n.text("原生复制并保存各标签页的完整配置，成功前不切换原窗口。"))
                    .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.disabled(controller.isDemo || appearance.terminalThemeBusy)
            HStack(spacing: 14) {
                Button(appearance.terminalProfileLinked ? L10n.text("重新应用完整主题") : L10n.text("3. 应用并开启联动")) { appearance.applyFullTerminalTheme() }
                    .disabled(draftTheme != appearance.themeSlug || draftDecorations != appearance.decorations)
                Button(L10n.text("恢复原完整配置")) { appearance.restoreFullTerminalTheme() }
                Spacer(minLength: 0)
            }.disabled(controller.isDemo || appearance.terminalThemeBusy)
            Text(appearance.terminalProfileLinked ? L10n.text("联动已启用：切换主题或装饰时，先应用 Terminal，再更新 OmniVibe；失败会保留原主题。") : L10n.text("应用成功后开启联动。恢复原配置会关闭联动。操作仅作用于已打开的 Terminal 标签页，不会新建 shell。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: appearance.terminalProfileLinked ? theme.accent : theme.muted))
                .fixedSize(horizontal: false, vertical: true)
            if draftTheme != appearance.themeSlug || draftDecorations != appearance.decorations {
                Text(L10n.text("请先保存并应用外观草稿，再应用对应的 Terminal 完整主题。"))
                    .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
            }
            if appearance.terminalThemeBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("正在处理 Terminal 主题…")).font(.system(size: 11))
                }
            }
            if let status = appearance.terminalProfileStatus { terminalStatusText(L10n.errorText(status)) }
            terminalImportDetails
            Text(L10n.text("首次检查、自动备份或应用时需要 macOS 自动化授权。原配置不可独立恢复时，先点“自动备份原配置”，再应用主题；失败时原窗口和已有备份保留，可重试。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("Terminal 导出使用静态 PNG；动画背景、Windows 的着色器与自定义窗口边框不属于 Apple Terminal 的公开能力。此功能不读取终端正文或执行命令。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(L10n.text("高级：手动指定恢复基准")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("自动备份不可用时，可选择已导出的完整原文件与独立导入的恢复配置。仅在此备用流程中按你指定的配置恢复。"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.text("指定原配置备份…")) { showingTerminalRecovery = true }
                }.padding(.top, 9)
            }.disabled(controller.isDemo || appearance.terminalThemeBusy)
            DisclosureGroup(L10n.text("快速配色与旧会话备份")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("快速配色仅修改背景、普通文字、粗体文字和光标四项颜色，无需导入。准备完整主题时会先恢复此备份；完整联动期间不能混用。"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                    HStack(spacing: 14) {
                        Button(L10n.text("应用快速配色")) { appearance.applyTerminalTheme() }
                            .disabled(appearance.terminalProfileLinked || draftTheme != appearance.themeSlug)
                        Button(L10n.text("恢复快速配色")) { appearance.restoreTerminalTheme() }
                            .disabled(appearance.terminalProfileLinked)
                    }
                    if let status = appearance.terminalThemeStatus { terminalStatusText(L10n.errorText(status)) }
                    Text(L10n.text("Terminal 已重启且旧备份无法用于当前会话时，可显式归档。原文件会保留；归档不会执行恢复，也不允许归档当前会话的有效备份。"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                    HStack(spacing: 14) {
                        Button(L10n.text("归档旧快速配色备份")) { appearance.archivePreviousTerminalThemeBackup() }
                        Button(L10n.text("归档旧完整配置备份")) { appearance.archivePreviousTerminalProfileBackup() }
                    }
                }.padding(.top, 9)
            }.disabled(controller.isDemo || appearance.terminalThemeBusy)
        }
    }

    @ViewBuilder
    private var terminalImportDetails: some View {
        if let status = appearance.terminalProfileImportStatus {
            if !status.missingNames.isEmpty {
                terminalStatusText(L10n.text("尚未导入 \(status.missingNames.count) 套：") + status.missingNames.joined(separator: "、"))
            }
            if !status.ambiguousNames.isEmpty {
                terminalStatusText(L10n.text("发现同名配置，请在 Terminal 中保留每个主题唯一一份：") + status.ambiguousNames.joined(separator: "、"))
            }
            if status.temporaryOriginalCount > 0 {
                terminalStatusText(L10n.text("\(status.temporaryOriginalCount) 个标签页尚缺可恢复的原配置。请点击“自动备份原配置”；备份成功前不会切换这些窗口。"))
            }
            if status.nativeCopyCount > 0 {
                terminalStatusText(L10n.text("\(status.nativeCopyCount) 个标签页已保存原生自动备份。"))
            }
            if status.manualBaselineCount > 0 {
                terminalStatusText(L10n.text("\(status.manualBaselineCount) 个标签页使用你手动指定的恢复基准。"))
            }
            if let error = status.errorMessage { terminalStatusText(L10n.text("恢复条件待处理：") + L10n.text(error)) }
        }
    }

    private func terminalStatusText(_ text: String) -> some View {
        Text(L10n.errorText(text)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.text))
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }

    private var generalPage: some View {
        Group {
            pageHeading(L10n.text("通用"), L10n.text("保留原来的终端与工作方式，OmniVibe 只管理你收纳的窗口。"))
            settingsBox(L10n.text("辅助功能权限")) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Circle().fill(Color(nsColor: controller.permissionGranted ? theme.running : theme.waiting)).frame(width: 7, height: 7)
                        Text(controller.permissionGranted ? L10n.text("已授权，可以收纳与切换窗口") : L10n.text("尚未授权，窗口控制暂不可用"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    Text(L10n.text("用于识别、切换和排列窗口。当前不采集屏幕画面。"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                    if !controller.permissionGranted {
                        Text(L10n.text("若系统列表里开关已打开，应用仍显示未授权：关闭再打开 OmniVibe 的辅助功能开关，然后重新启动应用。"))
                            .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
                    }
                    HStack(spacing: 13) {
                        Button(L10n.text("开启权限")) { controller.requestAccess() }
                        Button(L10n.text("系统设置")) { controller.openAccessibilitySettings() }
                        Button(L10n.text("重新检查")) { controller.recheckPermissions() }
                    }
                }
            }
            settingsBox(L10n.text("当前支持")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("固定槽位收纳、具体窗口切换、排列与恢复，保持原版的任务操作规则。"))
                    Text(L10n.text("Agent 状态可从任务右键菜单连接；未连接状态时保持未知。"))
                        .foregroundStyle(Color(nsColor: theme.muted))
                    Text(L10n.text("Apple Terminal 可导入 26 套完整主题，应用后联动静态背景、16 色 ANSI、字体与配色，并保留原配置供恢复；需手动导入及自动化授权。动画背景与其他终端暂不支持联动。"))
                        .foregroundStyle(Color(nsColor: theme.muted))
                    Text(L10n.text("任务未绑定时，轮盘只显示空槽；关闭主界面后，可从菜单栏找回悬浮入口。"))
                        .foregroundStyle(Color(nsColor: theme.muted))
                }.font(.system(size: 12)).lineSpacing(5)
            }
            if let notice = controller.notice {
                Text(L10n.errorText(notice)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
            }
            WindowBehaviorSettingsView(controller: controller, appearance: appearance)
        }
    }

    private var audioPage: some View {
        Group {
            pageHeading(L10n.text("声音"), L10n.text("声音随主题切换，音量与界面动效分别调整。试听不会保存草稿。"))
            settingsBox(L10n.text("播放")) {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(L10n.text("启用窗口操作与任务提示音"), isOn: $draftSoundEnabled).toggleStyle(.checkbox)
                    HStack(spacing: 16) {
                        Text(L10n.text("音量")).frame(width: 42, alignment: .leading)
                        Slider(value: $draftSoundVolume, in: 0...1, step: 0.05)
                        Text("\(Int(draftSoundVolume * 100))%")
                            .monospacedDigit().frame(width: 42, alignment: .trailing)
                    }
                    Text(L10n.text("关闭声音或将音量调为零后，正常窗口操作保持静音。"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                }.font(.system(size: 12))
            }
            settingsBox(L10n.text("\(preview.name) · 切换标志音")) {
                VStack(alignment: .leading, spacing: 14) {
                    let available = draftSignatureURL != nil || ThemeAudio.hasSound(.switch, themeSlug: draftTheme)
                    HStack(spacing: 8) {
                        Circle().fill(Color(nsColor: available ? theme.running : theme.muted)).frame(width: 6, height: 6)
                        Text(draftSignatureURL == nil ? available ? L10n.text("可用") : L10n.text("未安装 · 切换保持静音") : L10n.text("自定义 WAV 待保存"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text(L10n.text("优先使用你导入的声音；内置经典主题有离线标志音。缺少资源时保持静音。"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                    if let draftSignatureURL {
                        Text(draftSignatureURL.lastPathComponent).font(.system(size: 11))
                    }
                    HStack(spacing: 14) {
                        Button(L10n.text("试听切换音")) { previewSound(.switch) }.disabled(!available || draftSoundVolume == 0)
                        Button(L10n.text("导入自定义 WAV…"), action: selectSignature)
                        Button(L10n.text("试听完成提示")) { previewSound(.ready) }.disabled(draftSoundVolume == 0)
                    }
                    Text(L10n.text("完成提示使用独立短音，音量为共享音量的一半。导入文件仅在保存时复制，已有自定义声音会先备份。"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                }
            }
            if let soundError {
                Text(L10n.errorText(soundError)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
            }
        }
    }

    private var shortcutsPage: some View {
        Group {
            pageHeading(L10n.text("快捷键"), L10n.text("编号、轮盘与任务总览相互配合，避免反复寻找相似的终端窗口。"))
            shortcutRuntimeStatus
            currentTaskNumbers
            settingsBox(L10n.text("操作方案 · 选择后立即生效")) {
                Picker(L10n.text("快捷键方案"), selection: Binding(get: { controller.shortcutScheme }, set: { controller.setShortcutScheme($0) })) {
                    ForEach(ShortcutScheme.allCases) { scheme in Text(L10n.text(scheme.label)).tag(scheme) }
                }.pickerStyle(.menu)
                    .disabled(controller.isDemo)
                Text(L10n.text("切换方案会恢复该方案的全部按键；下方自定义修改立即保存。"))
                    .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                Text(controller.shortcutScheme == .inventoryFirst
                    ? L10n.text("按 Option + 空格打开总览，再按 1–9 进入任务；此预设默认只注册一个全局组合，自定义后以实际注册为准。")
                    : controller.shortcutScheme == .controlOption
                        ? L10n.text("保留 Control + Option 三键组合；也可切换到 Option 双键直达或总览优先。")
                        : L10n.text("按住 Option 再按数字即可直达任务。Option 也用于输入特殊字符，需要保留这些输入时可选总览优先方案。"))
                    .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
            }
            settingsBox(L10n.text("自定义每个操作 · ") + L10n.text(controller.shortcutConfiguration.label)) {
                VStack(spacing: 0) {
                    ForEach(ShortcutConfiguration.configurableActions, id: \.self) { action in
                        HStack(spacing: 12) {
                            Text(L10n.text(action.label)).font(.system(size: 12)).frame(width: 136, alignment: .leading)
                            Text(controller.shortcutConfiguration.binding(for: action)?.label ?? L10n.text("已停用"))
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(nsColor: theme.accent))
                            Spacer()
                            Button(L10n.text("修改")) { editingShortcut = action }
                                .accessibilityLabel(L10n.format("修改“%@”快捷键", L10n.text(action.label)))
                            Menu {
                                Button(L10n.text("停用此快捷键")) { _ = controller.disableShortcut(action) }
                                Button(L10n.text("恢复方案默认值")) { controller.resetShortcut(action) }
                            } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).frame(width: 28)
                                .accessibilityLabel(L10n.format("%@的快捷键选项", L10n.text(action.label)))
                        }.padding(.vertical, 9)
                        Divider().opacity(0.35)
                    }
                    HStack {
                        Text(L10n.text("可直接录制组合，也可用修饰键与按键列表选择。"))
                            .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                        Spacer()
                        Button(L10n.text("恢复全部方案默认值")) { controller.resetAllCustomShortcuts() }
                            .disabled(!controller.shortcutConfiguration.isCustomized)
                    }.padding(.top, 13)
                }.disabled(controller.isDemo)
                if let error = controller.shortcutEditError {
                    Text(L10n.errorText(error)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
                }
            }
            settingsBox(L10n.text("任务与窗口")) {
                VStack(spacing: 0) {
                    shortcut(controller.shortcutConfiguration.slotRangeLabel, L10n.text("切换到对应任务，再按恢复原状态"))
                    if let binding = controller.shortcutConfiguration.binding(for: .aim) { shortcut(binding.label, L10n.text("按住呼出轮盘，指向任务后松开进入")) }
                    if let binding = controller.shortcutConfiguration.binding(for: .arrange) { shortcut(binding.label, L10n.text("尝试排列可调整的已收纳窗口，再按恢复布局")) }
                    if let binding = controller.shortcutConfiguration.binding(for: .toggleVisibility) { shortcut(binding.label, L10n.text("显示或隐藏悬浮入口")) }
                    if let binding = controller.shortcutConfiguration.binding(for: .inventory) { shortcut(binding.label, L10n.text("打开 / 关闭任务总览，再按数字进入")) }
                    shortcut(L10n.text("右键悬浮入口"), L10n.text("打开任务总览、主题与管理菜单"))
                    shortcut(L10n.text("按住并拖动核心"), L10n.text("移动悬浮入口位置"))
                    shortcut(L10n.text("拖动任务到槽位"), L10n.text("插入排序，名称、器物和状态一起移动"))
                    shortcut(L10n.text("任务上的 × / 拖远移出"), L10n.text("解除管理，原窗口继续运行"))
                    shortcut(L10n.text("方向键 / 数字 / Enter"), L10n.text("在任务总览中浏览和进入任务"))
                    shortcut("Esc", L10n.text("关闭任务总览或取消选择"))
                }
            }
            Text(L10n.text("⌃ Control · ⌥ Option · ⇧ Shift · ⌘ Command。Esc 保留为取消；系统保留组合与重复组合会提示原因。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
        }
    }

    private var shortcutRuntimeStatus: some View {
        settingsBox(L10n.text("快捷键当前状态")) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(controller.isDemo ? L10n.text("界面演示 · 不注册全局快捷键")
                        : controller.isRecordingShortcut ? L10n.text("正在录制 · OmniVibe 全局快捷键已暂停") : L10n.text("当前未录制 · 按以下实际注册结果检查"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: controller.isRecordingShortcut ? theme.waiting : theme.text))
                    Text(L10n.text("任务键 \(controller.registeredTaskShortcuts.count)/\(controller.shortcutConfiguration.taskBindings.count) · 入口键 \(controller.registeredWheelShortcuts.count)/\(controller.shortcutConfiguration.wheelBindings.count)"))
                        .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
                    Text(L10n.text("最近响应：") + L10n.text(controller.lastShortcut))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(nsColor: theme.accent))
                        .textSelection(.enabled)
                }
                Spacer(minLength: 10)
                Button(L10n.text("重新注册快捷键")) { controller.retryShortcuts() }
                    .disabled(controller.isDemo || controller.isRecordingShortcut)
            }
            if let warning = controller.hotKeyWarning {
                Text(L10n.errorText(warning)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if let failure = controller.activationFailure {
                Text(L10n.text("切换未完成：") + L10n.text(failure)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.waiting))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Text(L10n.text("已注册不代表按键已触发。按键后查看最近响应；切换失败时，任务总览会保留原因并提供重试。"))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
        }
    }

    private var currentTaskNumbers: some View {
        settingsBox(L10n.text("当前已收纳编号 · 排序后以此为准")) {
            HStack {
                Text(L10n.text("已收纳 \(controller.occupiedCount) / 已连接 \(controller.connectedCount)"))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(L10n.text("重新检查连接")) { controller.refreshConnections() }.disabled(controller.isDemo)
            }
            if controller.occupiedCount == 0 {
                Text(L10n.text("尚未收纳任务。先从空槽选择窗口，再查看它当前使用的编号。"))
                    .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
            } else {
                VStack(spacing: 10) {
                    ForEach(controller.workspace.slots.filter { $0.window != nil }.sorted { $0.number < $1.number }) { slot in
                        HStack(spacing: 12) {
                            Text(String(slot.number)).font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(nsColor: theme.accent)).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(slot.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    .help(slot.displayName)
                                Text((slot.window?.applicationName ?? "") + (controller.isConnected(slot) ? L10n.text(" · 已连接") : L10n.text(" · 未连接")))
                                    .font(.system(size: 10)).foregroundStyle(Color(nsColor: theme.muted))
                            }
                            Spacer(minLength: 10)
                            Text(controller.shortcutLabel(.slot(slot.number)).isEmpty
                                ? L10n.text("总览内按 \(slot.number)") : controller.shortcutLabel(.slot(slot.number)))
                                .font(.system(size: 12)).foregroundStyle(Color(nsColor: theme.accent))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(L10n.text("拖动排序后，任务会使用新位置的编号；请按当前列表选择，不沿用先前编号。已连接仅代表能访问窗口，是否可排列仍取决于窗口限制。"))
                    .font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
            }
        }
    }

    private func pageHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title)).font(.custom("STKaiti", size: 27))
            Text(L10n.text(subtitle)).font(.system(size: 11)).foregroundStyle(Color(nsColor: theme.muted))
        }
    }

    private func settingsBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(L10n.text(title)).font(.system(size: 15, weight: .semibold))
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: theme.surface).opacity(0.65))
            .overlay(Rectangle().strokeBorder(Color(nsColor: theme.border).opacity(0.5)).allowsHitTesting(false))
    }

    private func shortcut(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 22) {
            Text(L10n.text(keys)).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(nsColor: theme.accent)).frame(width: 170, alignment: .leading)
            Text(L10n.text(description)).font(.system(size: 12))
            Spacer()
        }.padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Color(nsColor: theme.border).opacity(0.2)).frame(height: 0.5) }
    }

    private func apply() {
        do {
            if let draftSignatureURL { try ThemeAudio.importSignature(from: draftSignatureURL, themeSlug: draftTheme) }
        } catch {
            soundError = error.localizedDescription
            section = .audio
            return
        }
        appearance.setThemeAndDecorations(draftTheme, decorations: draftDecorations) { succeeded in
            guard succeeded else { section = .appearance; return }
            appearance.setAnimate(draftAnimate)
            appearance.setSoundEnabled(draftSoundEnabled)
            appearance.setSoundVolume(draftSoundVolume)
            audition?.stop()
            onClose()
        }
    }

    private func selectSignature() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择当前主题的切换声音")
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { draftSignatureURL = panel.url; soundError = nil }
    }

    private func previewSound(_ cue: AudioCue) {
        if audition == nil { audition = ThemeAudio(appearance: appearance) }
        do {
            if cue == .switch, let draftSignatureURL {
                try audition?.previewFile(draftSignatureURL, volume: draftSoundVolume)
            } else {
                audition?.preview(cue, themeSlug: draftTheme, volume: draftSoundVolume)
            }
            soundError = nil
        } catch { soundError = error.localizedDescription }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance = "主题与换装"
    case shortcuts = "快捷键"
    case general = "通用"
    case audio = "声音"
    var id: Self { self }
}

@MainActor
private struct SettingsThemeTile: View {
    @ObservedObject var localization = AppLocalization.shared
    let theme: ThemeDefinition
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Color(nsColor: theme.background)
                if let illustration = ThemeResources.shared.thumbnail(theme.artwork) {
                    GeometryReader { geometry in
                        Image(nsImage: illustration).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.5)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(theme.name.components(separatedBy: " · ").first ?? theme.name)
                        .font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(theme.dockTitle).font(.custom("STKaiti", size: 9)).lineLimit(1)
                    HStack(spacing: 4) {
                        Capsule().fill(Color(nsColor: theme.accent)).frame(width: 17, height: 3)
                        Capsule().fill(Color(nsColor: theme.secondary)).frame(width: 17, height: 3)
                        Capsule().fill(Color(nsColor: theme.running)).frame(width: 17, height: 3)
                    }
                }.padding(8).background(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color(nsColor: theme.background).opacity(0.98)], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(height: 78).clipped()
            .foregroundStyle(Color(nsColor: theme.text))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: selected ? theme.accent : theme.border).opacity(selected ? 1 : 0.65), lineWidth: selected ? 1.7 : 0.7))
        }.buttonStyle(.plain).help(theme.name)
    }
}
