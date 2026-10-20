using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
namespace CodeManager;
public sealed class SettingsWindow : Window
{
    public Preferences Result { get; private set; }
    public bool AutoHide { get; private set; }
    public bool MinimizeOnCapture { get; private set; }
    public event Action? LoadoutRequested;
    public Skin LoadoutSkin { get; private set; }
    public event Action? AddWindowRequested, RecoveryRequested, DataDirectoryRequested;
    public bool PauseShortcuts { get; private set; }
    public bool ResetDockPositionRequested { get; private set; }
    public Func<Preferences, string?>? ShortcutAvailabilityCheck { get; set; }
    public Func<Preferences, Task<TerminalThemeReceipt>>? ApplyThemeAsync { get; set; }
    public string TerminalApplyMessage { get; private set; } = "";
    public SettingsWindow(Preferences source, Native.Rect workArea, string warnings, bool autoHide = false, bool minimize = true, int page = 2, bool shortcutsPaused = false)
    {
        Result = source.Copy(); AutoHide = autoHide; MinimizeOnCapture = minimize;
        LoadoutSkin = source.Skin;
        Title = "OmniVibe · 设置"; Width = 1180; Height = 900; MinWidth = 700; MinHeight = 470;
        Background = WuxiaTheme.Ink; Foreground = WuxiaTheme.Ivory; Topmost = true; ShowInTaskbar = false;
        SourceInitialized += (_, _) => Native.Decorate(this, noActivate: false);
        double scale = Native.ScreenAtCursor().Scale;
        double availableWidth = Math.Max(360, (workArea.Right - workArea.Left) / scale - 40), availableHeight = Math.Max(340, (workArea.Bottom - workArea.Top) / scale - 40);
        MinWidth = Math.Min(700, availableWidth); MinHeight = Math.Min(470, availableHeight);
        Width = Math.Min(1180, availableWidth); Height = Math.Min(900, availableHeight);
        Left = (workArea.Left + workArea.Right) / (2 * scale) - Width / 2; Top = (workArea.Top + workArea.Bottom) / (2 * scale) - Height / 2;
        var host = SkinCatalog.Current;
        Resources[typeof(Button)] = SettingsButtonStyle(host);
        var root = new DockPanel();
        var title = new StackPanel { Margin = new Thickness(24, 10, 24, 9) };
        title.Children.Add(new TextBlock { Text = "OMNIVIBE / 工作台", FontSize = 10, Foreground = WuxiaTheme.Brush(host.Muted), Margin = new Thickness(0, 0, 0, 6) });
        title.Children.Add(new TextBlock { Text = "设置", FontSize = 22, FontWeight = FontWeights.SemiBold });
        var header = new Border { Child = title, BorderBrush = WuxiaTheme.Brush(host.Border), BorderThickness = new Thickness(0, 0, 0, .5) }; DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);
        var bottom = new StackPanel { Margin = new Thickness(24, 8, 24, 16) }; var footer = new Border { Child = bottom, Background = WuxiaTheme.Brush(host.Surface), BorderBrush = WuxiaTheme.Brush(host.Border), BorderThickness = new Thickness(0, .5, 0, 0) }; DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        var error = new TextBlock { Foreground = WuxiaTheme.Cinnabar, TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed, Margin = new Thickness(0, 8, 0, 8) }; bottom.Children.Add(error);
        void Fail(string message) { error.Text = message; error.Visibility = Visibility.Visible; }
        var actionRow = new DockPanel(); var draft = new TextBlock { Text = "保存后同步 Terminal 与 OmniVibe 整套外观", Foreground = WuxiaTheme.Brush(host.Muted), FontSize = 11, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap, MaxWidth = 330 }; DockPanel.SetDock(draft, Dock.Left); actionRow.Children.Add(draft);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var reset = new Button { Content = "恢复默认", Margin = new Thickness(0, 0, 16, 0) }; var cancel = new Button { Content = "取消", IsCancel = true, Margin = new Thickness(0, 0, 10, 0) }; var save = new Button { Content = "保存并应用", IsDefault = true, Background = WuxiaTheme.Brush("#354730") };
        save.Background = WuxiaTheme.Brush(host.Accent); save.Foreground = WuxiaTheme.Brush(host.Background); save.FontWeight = FontWeights.SemiBold;
        var saveCaption = new FrameworkElementFactory(typeof(TextBlock)); saveCaption.SetBinding(TextBlock.TextProperty, new Binding()); saveCaption.SetValue(TextBlock.ForegroundProperty, WuxiaTheme.Brush(host.Background)); saveCaption.SetValue(TextBlock.FontWeightProperty, FontWeights.SemiBold); save.ContentTemplate = new DataTemplate { VisualTree = saveCaption };
        foreach (var button in new[] { reset, cancel, save }) { button.MinHeight = 38; button.Padding = new Thickness(17, 8, 17, 8); button.FontSize = 12; }
        actions.Children.Add(reset); actions.Children.Add(cancel); actions.Children.Add(save); actionRow.Children.Add(actions); bottom.Children.Add(actionRow);
        var nav = new StackPanel { Margin = new Thickness(12, 22, 12, 12) };
        var sidebar = new Border { Width = 184, Background = WuxiaTheme.Brush(host.Surface), BorderBrush = WuxiaTheme.Brush(host.Border), BorderThickness = new Thickness(0, 0, .5, 0), Child = nav }; DockPanel.SetDock(sidebar, Dock.Left); root.Children.Add(sidebar);
        var pages = new Grid { Margin = new Thickness(26, 20, 16, 0) }; root.Children.Add(pages);
        var navButtons = new List<Button>();
        StackPanel Page(string name, string description)
        {
            var panel = new StackPanel { Margin = new Thickness(0, 0, 12, 12) }; var scroll = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Visibility = pages.Children.Count == 0 ? Visibility.Visible : Visibility.Collapsed }; pages.Children.Add(scroll);
            panel.Children.Add(new TextBlock { Text = name, FontSize = 25, FontWeight = FontWeights.SemiBold });
            panel.Children.Add(new TextBlock { Text = description, FontSize = 12, Foreground = WuxiaTheme.Brush(host.Muted), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 14) });
            var b = new Button { Content = name, HorizontalContentAlignment = HorizontalAlignment.Left, Padding = new Thickness(14, 13, 8, 13), FontSize = 13, BorderThickness = new Thickness(3, 0, 0, 0), Margin = new Thickness(0, 0, 0, 7) };
            b.Click += (_, _) => { foreach (UIElement item in pages.Children) item.Visibility = item == scroll ? Visibility.Visible : Visibility.Collapsed; foreach (Button button in navButtons) { button.Background = WuxiaTheme.Brush(button == b ? host.Elevated : host.Surface); button.BorderBrush = WuxiaTheme.Brush(button == b ? host.Accent : host.Surface); } };
            nav.Children.Add(b); navButtons.Add(b); return panel;
        }
        var guidePage = Page("快速上手", "把窗口收进来，用形象认任务，用快捷键找回窗口。");
        var guide = new GettingStartedPanel(source, warnings, shortcutsPaused);
        guide.AddWindowRequested += () => AddWindowRequested?.Invoke();
        guide.ConfigureShortcutsRequested += () => navButtons[2].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        guide.RecoveryRequested += () => RecoveryRequested?.Invoke();
        guidePage.Children.Add(guide);

        var appearance = Page("主题与换装", "所有主题直接陈列。先点图片选风格，再调整这套主题的角色和武器。");
        var skin = new SkinPicker(source.Skin, source.TerminalAnimation); appearance.Children.Add(skin);
        skin.SelectionChanged += () => { LoadoutSkin = skin.SelectedSkin; draft.Text = "保存后同步 Terminal 与 OmniVibe 整套外观"; };
        skin.LoadoutRequested += () => LoadoutRequested?.Invoke();
        var qualitySection = Section(appearance, "界面效果", "插画与装饰随整套主题应用；Terminal 动画使用上方独立开关。");
        var quality = Options(new[] { "完整效果 · 插画、装饰与动画", "静态外观 · 保留插画和装饰", "简洁外观 · 保留任务与状态" }, source.DecorationsEnabled ? source.Animate ? 0 : 1 : 2);
        qualitySection.Children.Add(quality);
        skin.EffectsEnabled = () => quality.SelectedIndex == 0;
        skin.DecorationsEnabled = () => quality.SelectedIndex != 2;
        quality.SelectionChanged += (_, _) => skin.RefreshOptions();

        var keyPage = Page("快捷键", "点击右侧按键后直接录入，保存后全局生效。× 清除，↺ 恢复默认，Esc 取消录入。Windows 保留组合无法接管。");
        var recorders = new Dictionary<int, ShortcutRecorder>();
        var defaults = new Preferences();
        var wheelEditor = new ShortcutRecorder("滚轮切换", source.WheelSwitchEnabled ? Preferences.ModifierLabel(source.MouseModifiers) + "+Wheel" : "", "Alt+Wheel", wheel: true);
        var keyNotice = new TextBlock { FontSize = 11, TextWrapping = TextWrapping.Wrap, Foreground = WuxiaTheme.Brush(host.Waiting), Margin = new Thickness(0, 0, 0, 12) }; keyPage.Children.Add(keyNotice);
        void KeyRow(Panel parent, ShortcutBinding binding)
        {
            var row = new Grid { Margin = new Thickness(0, 6, 0, 9) };
            row.ColumnDefinitions.Add(new()); row.ColumnDefinitions.Add(new() { Width = new GridLength(238) });
            var info = new StackPanel { Margin = new Thickness(0, 2, 14, 0), VerticalAlignment = VerticalAlignment.Center };
            info.Children.Add(new TextBlock { Text = binding.Name, FontSize = 13, FontWeight = FontWeights.SemiBold });
            info.Children.Add(new TextBlock { Text = binding.Purpose, FontSize = 11, TextWrapping = TextWrapping.Wrap, Foreground = WuxiaTheme.Brush(host.Muted), Margin = new Thickness(0, 4, 0, 0) }); row.Children.Add(info);
            var editor = new ShortcutRecorder(binding.Name, binding.Gesture, ShortcutBindings.All(defaults).First(b => b.Id == binding.Id).Gesture);
            editor.Changed += () => UpdateKeyNotice(); recorders[binding.Id] = editor; Grid.SetColumn(editor, 1); row.Children.Add(editor); parent.Children.Add(row);
        }
        var commonKeys = Section(keyPage, "常用操作", "总览看全部任务，轮盘用指向选择；选你顺手的一种即可。");
        foreach (var binding in ShortcutBindings.All(source).Where(b => b.Id >= 10)) KeyRow(commonKeys, binding);
        var wheelSection = Section(keyPage, "滚轮切换", "不用打开总览，按住修饰键并滚动即可切换已收纳的窗口。");
        wheelEditor.Changed += () => UpdateKeyNotice(); wheelSection.Children.Add(wheelEditor);
        var slotsBody = new StackPanel();
        foreach (var binding in ShortcutBindings.All(source).Where(b => b.Id < 10)) KeyRow(slotsBody, binding);
        var taskKeys = new Expander { Header = "窗口 1–9 · 展开后逐个自定义", Content = slotsBody, Margin = new Thickness(0, 4, 0, 16), IsExpanded = true }; keyPage.Children.Add(taskKeys);
        Preferences KeyDraft()
        {
            var candidate = Result.Copy();
            candidate.TaskGestures = recorders.Where(x => x.Key < 10).ToDictionary(x => x.Key, x => x.Value.Gesture);
            candidate.InventoryGesture = recorders[11].Gesture; candidate.TabTogglesInventory = candidate.InventoryGesture.Length > 0;
            candidate.RadialGesture = recorders[13].Gesture; candidate.ArrangeGesture = recorders[12].Gesture; candidate.ToggleGesture = recorders[10].Gesture;
            candidate.WheelSwitchEnabled = wheelEditor.Gesture.Length > 0;
            if (candidate.WheelSwitchEnabled && InputService.TryParseGesture(wheelEditor.Gesture.Replace("Wheel", "F24"), out uint mods, out uint key)) candidate.MouseModifiers = (ShortcutModifiers)mods;
            return candidate;
        }
        void UpdateKeyNotice()
        {
            if (recorders.Count != 13) return;
            var candidate = KeyDraft();
            keyNotice.Text = !ShortcutBindings.Validate(candidate, out string problem) ? problem : string.Join("、", ShortcutBindings.All(candidate).Where(b => ShortcutBindings.IsTypingKey(b.Gesture)).Select(b => b.Name + "（" + ShortcutBindings.Display(b.Gesture) + "）")) is string typing && typing.Length > 0 ? typing + " 会全局接管原应用的这个键；清除或加修饰键即可交还。" : "";
        }
        UpdateKeyNotice();

        var layoutPage = Page("窗口与布局", "调整多个窗口怎么排、单个窗口怎么唤出，以及桌面入口的位置。");
        var overview = Section(layoutPage, "任务总览大小", "按总览快捷键查看任务。档位越大，终端预览越清楚；会按屏幕大小自动限制，并保留桌面边距。");
        var overviewSize = Options(OverviewSizing.Labels, (int)OverviewSizing.Normalize(source.OverviewSize));
        overviewSize.Name = "OverviewSizePicker"; overview.Children.Add(overviewSize);
        var layout = Section(layoutPage, "全部排列", "按「排列 / 恢复」快捷键铺开窗口，再按一次恢复。");
        var arrangement = Options(new[] { "均衡网格 · 铺满屏幕", "纵向分栏", "横向分行", "主窗居左 · 其余居右" }, (int)source.Arrangement); layout.Children.Add(arrangement);
        Label(layout, "窗口间距"); var gap = Slider(0, 32, source.LayoutGap, layout);
        layout = Section(layoutPage, "切换窗口", "同一个窗口的快捷键再按一次，会恢复唤出之前的样子。");
        var wake = Options(new[] { "保留窗口最近的大小和位置", "唤出时铺满当前屏幕工作区" }, (int)source.WakeMode); layout.Children.Add(wake);
        var mini = Check("收纳后最小化原窗口", minimize); layout.Children.Add(mini);
        var ring = Section(layoutPage, "悬浮入口", "鼠标移入展开任务，移开收回；长按入口可直接拖动位置。");
        Label(ring, "展开范围"); var width = Slider(320, 480, source.DockWidth, ring);
        var resetPosition = new Button { Content = "恢复右侧默认位置", HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 8, 0, 0) };
        resetPosition.Click += (_, _) => { ResetDockPositionRequested = true; resetPosition.Content = "保存后恢复右侧位置"; }; ring.Children.Add(resetPosition);

        var generalPage = Page("常规", "管理启动恢复和声音。少用的维护工具收在页面底部。");
        var general = Section(generalPage, "启动与输入", "选择打开 OmniVibe 后如何继续上次的工作。");
        var startup = Options(new[] { "只显示悬浮入口", "重连仍在运行的窗口", "重连窗口，并显示待恢复任务", "重连窗口，并自动打开已配置任务" }, source.AutoRestoreOnStartup ? 3 : source.ShowRecoveryOnStartup ? 2 : source.AutoReconnectExisting ? 1 : 0); general.Children.Add(startup);
        var pause = Check("本次运行暂停全局快捷键（鼠标仍可用）", shortcutsPaused); general.Children.Add(pause);
        var audio = new AudioSettingsPanel(source, () => skin.SelectedSkin); generalPage.Children.Add(audio);
        var maintenance = new StackPanel();
        var history = new Button { Content = "查看最近任务 / 恢复工作现场", HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 6, 0, 6) }; history.Click += (_, _) => RecoveryRequested?.Invoke(); maintenance.Children.Add(history);
        var data = new Button { Content = "打开配置目录", HorizontalAlignment = HorizontalAlignment.Left }; data.Click += (_, _) => DataDirectoryRequested?.Invoke(); maintenance.Children.Add(data);
        if (warnings != "") Label(maintenance, "当前快捷键 / 监听提示\n" + warnings, 12);
        generalPage.Children.Add(new Expander { Header = "维护与诊断", Content = maintenance, Margin = new Thickness(0, 10, 0, 16) });
        bool applying = false;
        Closing += (_, e) => { if (applying) e.Cancel = true; };
        async Task CommitAsync(Preferences candidate, bool minimizeAfter, bool pausedAfter, bool resetDefaults = false)
        {
            if (applying) return;
            applying = true; root.IsEnabled = false; save.Content = "正在应用整套主题…";
            try {
                if (ApplyThemeAsync != null) TerminalApplyMessage = (await ApplyThemeAsync(candidate)).Message;
                Result = candidate; MinimizeOnCapture = minimizeAfter; PauseShortcuts = pausedAfter;
                if (resetDefaults) AutoHide = false;
                applying = false; DialogResult = true;
            }
            catch (Exception ex) { Fail("整套主题尚未应用：" + ex.Message); }
            finally { applying = false; root.IsEnabled = true; save.Content = "保存并应用"; }
        }
        reset.Click += async (_, _) => await CommitAsync(new(), true, false, resetDefaults:true);
        save.Click += async (_, _) =>
        {
            error.Visibility = Visibility.Collapsed;
            if (recorders.Values.Any(r => r.IsCapturing) || wheelEditor.IsCapturing) { Fail("请先完成按键录入，或按 Esc 取消本次录入。"); return; }
            var candidate = KeyDraft();
            if (!ShortcutBindings.Validate(candidate, out string problem)) { Fail(problem); navButtons[2].RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); return; }
            if (ShortcutAvailabilityCheck?.Invoke(candidate) is string occupied) { Fail(occupied); navButtons[2].RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); return; }
            candidate.Arrangement = (ArrangementMode)arrangement.SelectedIndex; candidate.LayoutGap = (int)gap.Value; candidate.HideDockOnArrange = false; candidate.WakeMode = (WakeMode)wake.SelectedIndex;
            candidate.OverviewSize = (OverviewSize)overviewSize.SelectedIndex;
            candidate.Skin = skin.SelectedSkin; candidate.DockWidth = width.Value; candidate.DockHeight = 0;
            candidate.TerminalAnimation = skin.TerminalAnimationEnabled;
            candidate.Animate = quality.SelectedIndex == 0; candidate.DecorationsEnabled = quality.SelectedIndex != 2;
            candidate.ShowRecoveryOnStartup = startup.SelectedIndex >= 2; candidate.AutoReconnectExisting = startup.SelectedIndex >= 1; candidate.AutoRestoreOnStartup = startup.SelectedIndex == 3;
            if (!audio.TryCommit(candidate, out string audioError)) { Fail(audioError); return; }
            await CommitAsync(candidate, mini.IsChecked == true, pause.IsChecked == true);
        };
        Content = root;
        SizeChanged += (_, _) => { sidebar.Width = ActualWidth < 880 ? 144 : 184; pages.Margin = new Thickness(ActualWidth < 880 ? 16 : 26, 20, 12, 0); draft.Visibility = ActualWidth < 820 ? Visibility.Collapsed : Visibility.Visible; };
        int initial = page switch { 0 => 2, 1 => 3, 2 => 1, 3 or 5 => 4, _ => 0 };
        navButtons[initial].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    }
    private static StackPanel Section(Panel parent, string title, string description)
    {
        var skin = SkinCatalog.Current; var panel = new StackPanel();
        panel.Children.Add(new TextBlock { Text = title, FontSize = 17, FontWeight = FontWeights.SemiBold });
        panel.Children.Add(new TextBlock { Text = description, FontSize = 12, Foreground = WuxiaTheme.Brush(skin.Muted), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 7, 0, 8) });
        parent.Children.Add(new Border { Background = WuxiaTheme.Brush(skin.Surface), BorderBrush = WuxiaTheme.Brush(skin.Border), BorderThickness = new Thickness(.5), CornerRadius = new CornerRadius(10), Padding = new Thickness(19), Margin = new Thickness(0, 0, 0, 17), Child = panel });
        return panel;
    }
    internal static Style SettingsButtonStyle(SkinDefinition skin)
    {
        var style = new Style(typeof(Button));
        // The global TextBlock style sets its own foreground. Button captions
        // inherit the button's foreground so the accent save button stays readable.
        style.Resources[typeof(TextBlock)] = new Style(typeof(TextBlock));
        style.Setters.Add(new Setter(Control.BackgroundProperty, WuxiaTheme.Brush(skin.Surface)));
        style.Setters.Add(new Setter(Control.ForegroundProperty, WuxiaTheme.Brush(skin.Text)));
        style.Setters.Add(new Setter(Control.BorderBrushProperty, Brushes.Transparent));
        style.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(1)));
        style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(12, 8, 12, 8)));
        style.Setters.Add(new Setter(Control.FontFamilyProperty, WuxiaTheme.BodyFont));
        var border = new FrameworkElementFactory(typeof(Border)); border.Name = "Chrome";
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
        foreach (var (property, path) in new[] { (Border.BackgroundProperty, "Background"), (Border.BorderBrushProperty, "BorderBrush"), (Border.BorderThicknessProperty, "BorderThickness"), (Border.PaddingProperty, "Padding") }) border.SetBinding(property, new Binding(path) { RelativeSource = RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter)); content.SetValue(ContentPresenter.ContentSourceProperty, "Content");
        content.SetBinding(FrameworkElement.HorizontalAlignmentProperty, new Binding("HorizontalContentAlignment") { RelativeSource = RelativeSource.TemplatedParent });
        content.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center); border.AppendChild(content);
        var template = new ControlTemplate(typeof(Button)) { VisualTree = border };
        var hover = new Trigger { Property = IsMouseOverProperty, Value = true }; hover.Setters.Add(new Setter(Border.BorderBrushProperty, WuxiaTheme.Brush(skin.Accent), "Chrome")); template.Triggers.Add(hover);
        var focus = new Trigger { Property = IsKeyboardFocusedProperty, Value = true }; focus.Setters.Add(new Setter(Border.BorderBrushProperty, WuxiaTheme.Brush(skin.Accent), "Chrome")); template.Triggers.Add(focus);
        var disabled = new Trigger { Property = IsEnabledProperty, Value = false }; disabled.Setters.Add(new Setter(OpacityProperty, .45)); template.Triggers.Add(disabled);
        style.Setters.Add(new Setter(Control.TemplateProperty, template)); return style;
    }
    private static void Label(Panel p, string text, double size = 13) => p.Children.Add(new TextBlock { Text = text, FontSize = size, Foreground = WuxiaTheme.Brush(size <= 12 ? SkinCatalog.Current.Muted : SkinCatalog.Current.Text), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 8) });
    private static CheckBox Check(string text, bool value) => new() { Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap }, IsChecked = value, Foreground = WuxiaTheme.Ivory, Margin = new Thickness(0, 10, 0, 8) };
    private static ComboBox Options(string[] choices, int selected) { var c = new ComboBox { FontSize = 14, MinHeight = 36 }; foreach (string s in choices) c.Items.Add(new ComboBoxItem { Content = s }); c.SelectedIndex = Math.Clamp(selected, 0, choices.Length - 1); return c; }
    private static Slider Slider(double min, double max, double value, Panel panel)
    {
        var row = new DockPanel(); var label = new TextBlock { Width = 48, TextAlignment = TextAlignment.Right }; DockPanel.SetDock(label, Dock.Right); row.Children.Add(label);
        var slider = new Slider { Minimum = min, Maximum = max, Value = Math.Clamp(value, min, max), IsSnapToTickEnabled = true, TickFrequency = 1, VerticalAlignment = VerticalAlignment.Center };
        void Update() => label.Text = Math.Round(slider.Value).ToString(); slider.ValueChanged += (_, _) => Update(); Update(); row.Children.Add(slider); panel.Children.Add(row); return slider;
    }
}
