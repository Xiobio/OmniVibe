using System;
using System.Collections.Generic;
using System.Linq;
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
    public SettingsWindow(Preferences source, Native.Rect workArea, string warnings, bool autoHide = false, bool minimize = true, int page = 2)
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
        var title = new StackPanel { Margin = new Thickness(26, 19, 26, 17) };
        title.Children.Add(new TextBlock { Text = "OMNIVIBE / 工作台", FontSize = 10, Foreground = WuxiaTheme.Brush(host.Muted), Margin = new Thickness(0, 0, 0, 6) });
        title.Children.Add(new TextBlock { Text = "设置", FontSize = 26, FontWeight = FontWeights.SemiBold });
        var header = new Border { Child = title, BorderBrush = WuxiaTheme.Brush(host.Border), BorderThickness = new Thickness(0, 0, 0, .5) }; DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);
        var bottom = new StackPanel { Margin = new Thickness(24, 8, 24, 16) }; var footer = new Border { Child = bottom, Background = WuxiaTheme.Brush(host.Surface), BorderBrush = WuxiaTheme.Brush(host.Border), BorderThickness = new Thickness(0, .5, 0, 0) }; DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        var error = new TextBlock { Foreground = WuxiaTheme.Cinnabar, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 8) }; bottom.Children.Add(error);
        var actionRow = new DockPanel(); var draft = new TextBlock { Text = "保存后应用 · Terminal 外观单独应用", Foreground = WuxiaTheme.Brush(host.Muted), FontSize = 11, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap, MaxWidth = 330 }; DockPanel.SetDock(draft, Dock.Left); actionRow.Children.Add(draft);
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
            panel.Children.Add(new TextBlock { Text = description, FontSize = 12, Foreground = WuxiaTheme.Brush(host.Muted), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 22) });
            var b = new Button { Content = name, HorizontalContentAlignment = HorizontalAlignment.Left, Padding = new Thickness(14, 13, 8, 13), FontSize = 13, BorderThickness = new Thickness(3, 0, 0, 0), Margin = new Thickness(0, 0, 0, 7) };
            b.Click += (_, _) => { foreach (UIElement item in pages.Children) item.Visibility = item == scroll ? Visibility.Visible : Visibility.Collapsed; foreach (Button button in navButtons) { button.Background = WuxiaTheme.Brush(button == b ? host.Elevated : host.Surface); button.BorderBrush = WuxiaTheme.Brush(button == b ? host.Accent : host.Surface); } };
            nav.Children.Add(b); navButtons.Add(b); return panel;
        }
        var keyPage = Page("快捷键", "把常用操作放到顺手的位置。点击快捷键输入框后，按下新的组合键。");
        var keys = Section(keyPage, "快速唤出", "数字键 1–9 始终对应当前任务排序。"); Label(keys, "数字键修饰键"); var number = Modifiers(source.TaskModifiers); keys.Children.Add(number);
        Label(keys, "滚轮切换修饰键"); var mouse = Modifiers(source.MouseModifiers); keys.Children.Add(mouse);
        keys = Section(keyPage, "总览与轮盘", "总览用于查看任务；轮盘用于快速选择。");
        var inventoryEnabled = Check("启用任务总览快捷键", source.TabTogglesInventory); keys.Children.Add(inventoryEnabled);
        Label(keys, "任务总览（单独 Tab 或组合键）"); var inventory = Gesture(source.InventoryGesture, true); keys.Children.Add(inventory);
        Label(keys, "任务轮盘（按住 → 指向 → 松键切换）"); var radial = Gesture(source.RadialGesture); keys.Children.Add(radial);
        keys = Section(keyPage, "窗口与圆环", "排列、恢复与显示状态均支持独立快捷键。");
        Label(keys, "全部排列 / 再按恢复"); var arrange = Gesture(source.ArrangeGesture); keys.Children.Add(arrange);
        Label(keys, "显示 / 隐藏圆环"); var toggle = Gesture(source.ToggleGesture); keys.Children.Add(toggle);
        Label(keys, "点击输入框后按新组合键。单独 Tab 会接管终端补全；本工具对话框中自动停用。", 12);
        var layoutPage = Page("窗口与排列", "选择任务唤出方式，以及多个窗口同时展示时的布局。");
        var layout = Section(layoutPage, "全部排列", "按排列快捷键铺开窗口，再按一次恢复。");
        var arrangement = Options(new[] { "均衡网格 · 铺满屏幕", "纵向分栏", "横向分行", "主窗居左 · 其余居右" }, (int)source.Arrangement); layout.Children.Add(arrangement);
        Label(layout, "窗口间距（0 为无缝铺满）"); var gap = Slider(0, 32, source.LayoutGap, layout);
        Label(layout, "全部排列和恢复布局时，悬浮入口始终保留；仅主动隐藏时关闭。", 12);
        layout = Section(layoutPage, "单个窗口唤出", "选择切换到某个任务时的窗口大小。"); var wake = Options(new[] { "恢复最近使用的大小与位置", "铺满侧栏所在屏幕工作区" }, (int)source.WakeMode); layout.Children.Add(wake);
        Label(layout, "排列中，Alt+数字临时放大任务，再按返回原格子。偏好在下次排列时使用。", 12);
        var appearance = Page("主题套装", "先看整套效果，再决定应用。每套包含圆环、任务总览、菜单与配套 Terminal 外观。");
        var skin = new SkinPicker(source.Skin); appearance.Children.Add(skin);
        skin.SelectionChanged += () => { LoadoutSkin = skin.SelectedSkin; draft.Text = skin.SelectedSkin == source.Skin ? "保存后应用 · Terminal 外观单独应用" : "正在预览新主题 · 保存后应用"; };
        var generalPage = Page("常规与状态", "安排日常行为、工作现场恢复与 AI 任务状态接入。");
        var ringPage = Page("圆环与位置", "圆环悬停展开，离开操作范围后收回；左键长按可拖动，右键打开管理菜单。");
        var ring = Section(ringPage, "展开范围", "调整展开后的装备范围，核心位置保持不动。");
        Label(ring, "宽度"); var width = Slider(320, 480, source.DockWidth, ring);
        Label(ring, "常驻圆环为 116×116；上面的尺寸只影响悬停展开后的任务范围。", 12);
        ring = Section(ringPage, "屏幕位置", "也可以直接长按圆环拖动，松手后自动保存位置。");
        var position = Check("恢复右侧贴边位置", !source.FreeDockPosition); ring.Children.Add(position);
        var loadout = Section(appearance, "主题配装", "内置藏品按上方主题分别记忆；导入图片随任务跨主题保留。配装单独保存。");
        var equipment = new Button { Content = "配置这套主题的角色与藏品…", HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(14, 9, 14, 9) };
        equipment.Click += (_, _) => LoadoutRequested?.Invoke(); loadout.Children.Add(equipment);
        var feedback = Section(appearance, "视听反馈", "预览会跟随动效与材质开关。音效在实际任务操作中播放。");
        var animate = Check("启用皮肤动效、任务入场与切换反馈", source.Animate); feedback.Children.Add(animate);
        var decorations = Check("启用材质、插画与装饰（关闭后保留状态和操作）", source.DecorationsEnabled); feedback.Children.Add(decorations);
        Label(feedback, "窗口切换标志音、声音主题与音量可在「声音与反馈」中试听和设置。", 12);
        var audioPage = Page("声音与反馈", "每套游戏保留一个窗口切换标志音。声音主题可跟随界面或单独选择，保存后应用。");
        var audio = new AudioSettingsPanel(source, () => skin.SelectedSkin); audioPage.Children.Add(audio);
        skin.EffectsEnabled = () => animate.IsChecked == true;
        skin.DecorationsEnabled = () => decorations.IsChecked == true;
        animate.Click += (_, _) => skin.RefreshOptions(); decorations.Click += (_, _) => skin.RefreshOptions();
        var general = Section(generalPage, "日常行为", "收纳窗口后仍保留任务与项目的绑定。");
        var mini = Check("收纳窗口后最小化原窗口", minimize); general.Children.Add(mini);
        general = Section(generalPage, "启动与工作现场", "继续上次的工作，减少重复寻找窗口。");
        var recoveryPage = Check("启动时显示未恢复的任务清单", source.ShowRecoveryOnStartup); general.Children.Add(recoveryPage);
        var reconnect = Check("启动时自动重连可唯一确认的已有窗口", source.AutoReconnectExisting); general.Children.Add(reconnect);
        var restore = Check("启动时自动打开已配置的断开任务", source.AutoRestoreOnStartup); general.Children.Add(restore);
        Label(general, "自动打开仅使用任务中保存的项目、启动方式与会话 ID；缺少信息的任务仍需配置。", 12);
        general = Section(generalPage, "AI 工作状态", "接入真实事件后显示运行、等待处理、本轮回复与错误。");
        Label(general, "Claude Code / Codex 可通过真实 hooks 事件更新运行、等待处理、本轮回复和错误。右键任务 → 连接自动任务状态，复制该任务的启动命令。已运行的 CLI 需要用接入命令重新启动。", 13);
        Label(general, "仅拖入终端不能判断内部 AI 状态，未接入时显示未知。建议一个窗口对应一个 AI 会话；本轮回复不等于整个任务完成。", 13);
        if (warnings != "") Label(general, "当前监听提示\n" + warnings, 12);
        reset.Click += (_, _) => { Result = new(); AutoHide = false; MinimizeOnCapture = true; DialogResult = true; };
        save.Click += (_, _) =>
        {
            var chords = new HashSet<string>(); var taskMods = Enum.GetValues<ShortcutModifiers>()[number.SelectedIndex];
            bool Validate(string text, bool tabAllowed)
            {
                uint mods = 0, key = 9;
                if (!(tabAllowed && text == "Tab") && !InputService.TryParseGesture(text, out mods, out key)) { error.Text = "请选择有效组合键；仅总览允许单独 Tab。"; return false; }
                if (mods == (uint)taskMods && key is >= 0x31 and <= 0x39 || !chords.Add(mods + ":" + key)) { error.Text = "快捷键重复，请使用不同组合。"; return false; }
                return true;
            }
            string toggleKey = (string)toggle.Tag, arrangeKey = (string)arrange.Tag, inventoryKey = (string)inventory.Tag, radialKey = (string)radial.Tag;
            if (!Validate(toggleKey, false) || !Validate(arrangeKey, false) || !Validate(radialKey, false) || inventoryEnabled.IsChecked == true && !Validate(inventoryKey, true)) return;
            Result.RadialGesture = radialKey;
            Result.TaskModifiers = taskMods; Result.MouseModifiers = Enum.GetValues<ShortcutModifiers>()[mouse.SelectedIndex]; Result.ToggleGesture = toggleKey; Result.ArrangeGesture = arrangeKey; Result.InventoryGesture = inventoryKey; Result.TabTogglesInventory = inventoryEnabled.IsChecked == true;
            Result.Arrangement = (ArrangementMode)arrangement.SelectedIndex; Result.LayoutGap = (int)gap.Value; Result.HideDockOnArrange = false; Result.WakeMode = (WakeMode)wake.SelectedIndex;
            Result.Skin = skin.SelectedSkin; Result.DockWidth = width.Value; Result.DockHeight = 0; if (position.IsChecked == true) Result.FreeDockPosition = false;
            Result.Animate = animate.IsChecked == true; Result.DecorationsEnabled = decorations.IsChecked == true; MinimizeOnCapture = mini.IsChecked == true;
            if (!audio.TryCommit(Result, out string audioError)) { error.Text = audioError; return; }
            Result.ShowRecoveryOnStartup = recoveryPage.IsChecked == true; Result.AutoReconnectExisting = reconnect.IsChecked == true; Result.AutoRestoreOnStartup = restore.IsChecked == true; DialogResult = true;
        };
        Content = root;
        nav.Children.Clear(); foreach (int index in new[] { 2, 5, 4, 1, 0, 3 }) nav.Children.Add(navButtons[index]);
        SizeChanged += (_, _) => { sidebar.Width = ActualWidth < 880 ? 144 : 184; pages.Margin = new Thickness(ActualWidth < 880 ? 16 : 26, 20, 12, 0); draft.Visibility = ActualWidth < 820 ? Visibility.Collapsed : Visibility.Visible; };
        navButtons[Math.Clamp(page, 0, navButtons.Count - 1)].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
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
    private static ComboBox Modifiers(ShortcutModifiers m) => Options(Enum.GetValues<ShortcutModifiers>().Select(Preferences.ModifierLabel).ToArray(), Array.IndexOf(Enum.GetValues<ShortcutModifiers>(), m));
    private static Slider Slider(double min, double max, double value, Panel panel)
    {
        var row = new DockPanel(); var label = new TextBlock { Width = 48, TextAlignment = TextAlignment.Right }; DockPanel.SetDock(label, Dock.Right); row.Children.Add(label);
        var s = new Slider { Minimum = min, Maximum = max, Value = Math.Clamp(value, min, max), IsSnapToTickEnabled = true, TickFrequency = 1, VerticalAlignment = VerticalAlignment.Center }; void Update() => label.Text = Math.Round(s.Value).ToString(); s.ValueChanged += (_, _) => Update(); Update(); row.Children.Add(s); panel.Children.Add(row); return s;
    }
    private static TextBox Gesture(string value, bool allowTab = false)
    {
        var box = new TextBox { Text = value.Replace("Oem3", "反引号"), Tag = value, IsReadOnly = true, ToolTip = "点击后按快捷键", MinHeight = 36, VerticalContentAlignment = VerticalAlignment.Center, Padding = new Thickness(10, 6, 10, 6) };
        box.PreviewKeyDown += (_, e) => { Key key = e.Key == Key.System ? e.SystemKey : e.Key; if (key == Key.Escape) return; e.Handled = true;
            if (allowTab && key == Key.Tab && Keyboard.Modifiers == ModifierKeys.None) { box.Tag = box.Text = "Tab"; return; }
            if (key is Key.LeftAlt or Key.RightAlt or Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin || Keyboard.Modifiers == ModifierKeys.None) return;
            try { string gesture = new KeyGestureConverter().ConvertToInvariantString(new KeyGesture(key, Keyboard.Modifiers))!; box.Tag = gesture; box.Text = gesture.Replace("Oem3", "反引号"); } catch (ArgumentException) { } };
        return box;
    }
}
