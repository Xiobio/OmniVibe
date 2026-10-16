using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
namespace CodeManager;
public sealed class SettingsWindow : Window
{
    public Preferences Result { get; private set; }
    public bool AutoHide { get; private set; }
    public bool MinimizeOnCapture { get; private set; }
    public SettingsWindow(Preferences source, Native.Rect workArea, string warnings, bool autoHide = false, bool minimize = true, int page = 0)
    {
        Result = source.Copy(); AutoHide = autoHide; MinimizeOnCapture = minimize;
        Title = "CodeManager · 设置"; Width = 780; Height = 700; MinWidth = 620; MinHeight = 430;
        Background = WuxiaTheme.Ink; Foreground = WuxiaTheme.Ivory; Topmost = true; ShowInTaskbar = false;
        SourceInitialized += (_, _) => Native.Decorate(this, noActivate: false);
        double scale = Native.ScreenAtCursor().Scale;
        Width = Math.Min(780, (workArea.Right - workArea.Left) / scale - 40); Height = Math.Min(700, (workArea.Bottom - workArea.Top) / scale - 40);
        Left = (workArea.Left + workArea.Right) / (2 * scale) - Width / 2; Top = (workArea.Top + workArea.Bottom) / (2 * scale) - Height / 2;
        var root = new DockPanel { Margin = new Thickness(22) };
        var title = new TextBlock { Text = "机 枢 设 定", FontFamily = WuxiaTheme.Calligraphy, FontSize = 30, Margin = new Thickness(0, 0, 0, 18) }; DockPanel.SetDock(title, Dock.Top); root.Children.Add(title);
        var bottom = new StackPanel(); DockPanel.SetDock(bottom, Dock.Bottom); root.Children.Add(bottom);
        var error = new TextBlock { Foreground = WuxiaTheme.Cinnabar, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 8) }; bottom.Children.Add(error);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var reset = new Button { Content = "恢复默认", Margin = new Thickness(0, 0, 16, 0) }; var cancel = new Button { Content = "取消", IsCancel = true, Margin = new Thickness(0, 0, 10, 0) }; var save = new Button { Content = "保存并应用", IsDefault = true, Background = WuxiaTheme.Brush("#354730") };
        actions.Children.Add(reset); actions.Children.Add(cancel); actions.Children.Add(save); bottom.Children.Add(actions);
        var nav = new StackPanel { Width = 128, Margin = new Thickness(0, 0, 24, 0) }; DockPanel.SetDock(nav, Dock.Left); root.Children.Add(nav);
        var pages = new Grid(); root.Children.Add(pages);
        StackPanel Page(string name)
        {
            var panel = new StackPanel { Margin = new Thickness(0, 0, 12, 12) }; var scroll = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Visibility = pages.Children.Count == 0 ? Visibility.Visible : Visibility.Collapsed }; pages.Children.Add(scroll);
            var b = new Button { Content = name, HorizontalContentAlignment = HorizontalAlignment.Left, Padding = new Thickness(12, 11, 12, 11), Margin = new Thickness(0, 0, 0, 8) };
            b.Click += (_, _) => { foreach (UIElement page in pages.Children) page.Visibility = page == scroll ? Visibility.Visible : Visibility.Collapsed; foreach (Button button in nav.Children) button.Background = button == b ? WuxiaTheme.Brush("#3B4C3A") : WuxiaTheme.Brush("#2B261D"); }; nav.Children.Add(b); return panel;
        }
        var keys = Page("快捷键"); Label(keys, "快捷唤出", 20); Label(keys, "数字键修饰键（1–9 对应当前排序）"); var number = Modifiers(source.TaskModifiers); keys.Children.Add(number);
        Label(keys, "滚轮切换修饰键"); var mouse = Modifiers(source.MouseModifiers); keys.Children.Add(mouse);
        var inventoryEnabled = Check("启用任务总览快捷键", source.TabTogglesInventory); keys.Children.Add(inventoryEnabled);
        Label(keys, "任务总览（单独 Tab 或组合键）"); var inventory = Gesture(source.InventoryGesture, true); keys.Children.Add(inventory);
        Label(keys, "全部排列 / 再按恢复"); var arrange = Gesture(source.ArrangeGesture); keys.Children.Add(arrange);
        Label(keys, "显示 / 隐藏侧栏"); var toggle = Gesture(source.ToggleGesture); keys.Children.Add(toggle);
        Label(keys, "点击输入框后按新组合键。单独 Tab 会接管终端补全；本工具对话框中自动停用。", 12);
        var layout = Page("唤出与排列"); Label(layout, "排列偏好", 20);
        var arrangement = Options(new[] { "均衡网格 · 铺满屏幕", "纵向分栏", "横向分行", "主窗居左 · 其余居右" }, (int)source.Arrangement); layout.Children.Add(arrangement);
        Label(layout, "窗口间距（0 为无缝铺满）"); var gap = Slider(0, 32, source.LayoutGap, layout);
        var hide = Check("全部排列时隐藏侧栏", source.HideDockOnArrange); layout.Children.Add(hide);
        Label(layout, "单个窗口唤出方式", 18); var wake = Options(new[] { "恢复最近使用的大小与位置", "铺满侧栏所在屏幕工作区" }, (int)source.WakeMode); layout.Children.Add(wake);
        Label(layout, "排列中，Alt+数字临时放大任务，再按返回原格子。偏好在下次排列时使用。", 12);
        var appearance = Page("皮肤与侧栏"); Label(appearance, "机关外观", 20);
        var skin = Options(new[] { "墨玉 · 青竹真气", "夜阑 · 深蓝玄铁", "朱砂 · 赤木剑匣" }, (int)source.Skin); appearance.Children.Add(skin);
        Label(appearance, "皮肤应用于剑匣、卷轴木轴和窗口底色，保存后切换。", 12);
        Label(appearance, "侧栏宽度"); var width = Slider(210, 520, source.DockWidth, appearance);
        Label(appearance, "侧栏高度（0 为随任务数量自动调整）"); var height = Slider(0, Math.Max(260, (workArea.Bottom - workArea.Top) / scale - 32), source.DockHeight, appearance);
        var position = Check("恢复右侧贴边位置", !source.FreeDockPosition); appearance.Children.Add(position);
        Label(appearance, "拖动侧栏标题移动，拖右下角 ◢ 调整宽高。位置与尺寸自动保存。", 12);
        var general = Page("常规与状态"); Label(general, "日常行为", 20);
        var compact = Check("紧凑列表（拖入时展开空槽）", source.Compact); general.Children.Add(compact);
        var auto = Check("鼠标离开后收起侧栏", autoHide); general.Children.Add(auto);
        var mini = Check("收纳窗口后最小化原窗口", minimize); general.Children.Add(mini);
        var animate = Check("启用动态法阵、卷轴入场与切换反馈", source.Animate); general.Children.Add(animate);
        var sound = Check("启用出鞘 / 机关音效", source.SoundEffects); general.Children.Add(sound);
        Label(general, "启动与工作现场", 20);
        var recoveryPage = Check("启动时显示未恢复的任务清单", source.ShowRecoveryOnStartup); general.Children.Add(recoveryPage);
        var reconnect = Check("启动时自动重连可唯一确认的已有窗口", source.AutoReconnectExisting); general.Children.Add(reconnect);
        var restore = Check("启动时自动打开已配置的断开任务", source.AutoRestoreOnStartup); general.Children.Add(restore);
        Label(general, "自动打开仅使用任务中保存的项目、启动方式与会话 ID；缺少信息的任务仍需配置。", 12);
        Label(general, "AI 工作状态", 20);
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
            string toggleKey = (string)toggle.Tag, arrangeKey = (string)arrange.Tag, inventoryKey = (string)inventory.Tag;
            if (!Validate(toggleKey, false) || !Validate(arrangeKey, false) || inventoryEnabled.IsChecked == true && !Validate(inventoryKey, true)) return;
            Result.TaskModifiers = taskMods; Result.MouseModifiers = Enum.GetValues<ShortcutModifiers>()[mouse.SelectedIndex]; Result.ToggleGesture = toggleKey; Result.ArrangeGesture = arrangeKey; Result.InventoryGesture = inventoryKey; Result.TabTogglesInventory = inventoryEnabled.IsChecked == true;
            Result.Arrangement = (ArrangementMode)arrangement.SelectedIndex; Result.LayoutGap = (int)gap.Value; Result.HideDockOnArrange = hide.IsChecked == true; Result.WakeMode = (WakeMode)wake.SelectedIndex;
            Result.Skin = (Skin)skin.SelectedIndex; Result.DockWidth = width.Value; Result.DockHeight = height.Value < 260 ? 0 : height.Value; if (position.IsChecked == true) Result.FreeDockPosition = false;
            Result.Compact = compact.IsChecked == true; Result.Animate = animate.IsChecked == true; Result.SoundEffects = sound.IsChecked == true; AutoHide = auto.IsChecked == true; MinimizeOnCapture = mini.IsChecked == true;
            Result.ShowRecoveryOnStartup = recoveryPage.IsChecked == true; Result.AutoReconnectExisting = reconnect.IsChecked == true; Result.AutoRestoreOnStartup = restore.IsChecked == true; DialogResult = true;
        };
        Content = root;
        ((Button)nav.Children[Math.Clamp(page, 0, nav.Children.Count - 1)]).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    }
    private static void Label(Panel p, string text, double size = 13) => p.Children.Add(new TextBlock { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 8) });
    private static CheckBox Check(string text, bool value) => new() { Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap }, IsChecked = value, Foreground = WuxiaTheme.Ivory, Margin = new Thickness(0, 10, 0, 8) };
    private static ComboBox Options(string[] choices, int selected) { var c = new ComboBox { FontSize = 14 }; foreach (string s in choices) c.Items.Add(new ComboBoxItem { Content = s }); c.SelectedIndex = Math.Clamp(selected, 0, choices.Length - 1); return c; }
    private static ComboBox Modifiers(ShortcutModifiers m) => Options(Enum.GetValues<ShortcutModifiers>().Select(Preferences.ModifierLabel).ToArray(), Array.IndexOf(Enum.GetValues<ShortcutModifiers>(), m));
    private static Slider Slider(double min, double max, double value, Panel panel)
    {
        var row = new DockPanel(); var label = new TextBlock { Width = 48, TextAlignment = TextAlignment.Right }; DockPanel.SetDock(label, Dock.Right); row.Children.Add(label);
        var s = new Slider { Minimum = min, Maximum = max, Value = Math.Clamp(value, min, max), IsSnapToTickEnabled = true, TickFrequency = 1, VerticalAlignment = VerticalAlignment.Center }; void Update() => label.Text = Math.Round(s.Value).ToString(); s.ValueChanged += (_, _) => Update(); Update(); row.Children.Add(s); panel.Children.Add(row); return s;
    }
    private static TextBox Gesture(string value, bool allowTab = false)
    {
        var box = new TextBox { Text = value.Replace("Oem3", "反引号"), Tag = value, IsReadOnly = true, ToolTip = "点击后按快捷键" };
        box.PreviewKeyDown += (_, e) => { Key key = e.Key == Key.System ? e.SystemKey : e.Key; if (key == Key.Escape) return; e.Handled = true;
            if (allowTab && key == Key.Tab && Keyboard.Modifiers == ModifierKeys.None) { box.Tag = box.Text = "Tab"; return; }
            if (key is Key.LeftAlt or Key.RightAlt or Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin || Keyboard.Modifiers == ModifierKeys.None) return;
            try { string gesture = new KeyGestureConverter().ConvertToInvariantString(new KeyGesture(key, Keyboard.Modifiers))!; box.Tag = gesture; box.Text = gesture.Replace("Oem3", "反引号"); } catch (ArgumentException) { } };
        return box;
    }
}
