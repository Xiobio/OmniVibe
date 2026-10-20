using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace CodeManager;

public sealed class GettingStartedPanel : StackPanel
{
    public event Action? AddWindowRequested, ConfigureShortcutsRequested, RecoveryRequested;
    public IReadOnlyList<ShortcutBinding> Bindings { get; }
    private readonly SkinDefinition _skin = SkinCatalog.Current;
    public static bool ShouldOpenOnStartup(AppState state) => !state.Preferences.HasSeenIntroduction && state.Slots.All(s => !s.Occupied) && state.RecentTasks.Count == 0;
    public GettingStartedPanel(Preferences preferences, string warnings = "", bool shortcutsPaused = false)
    {
        Bindings = ShortcutBindings.All(preferences);
        if (shortcutsPaused) Children.Add(Text("全局快捷键已暂时暂停。鼠标点击仍可使用；在设置 → 常规中恢复后，下方按键才会生效。", 12, _skin.Waiting));
        Children.Add(Text("一个窗口，就是一个可随时找回的任务", 20, _skin.Text, true));
        Children.Add(Text("不必记窗口标题：给任务选一个角色或武器，再用点击或快捷键切换。管理的是独立窗口，同一 Terminal 窗口里的标签页共用一个槽位。", 12, _skin.Muted));
        var steps = new UniformGrid { Columns = 3, Margin = new Thickness(-5, 16, -5, 14) };
        var first = Step("01", "收纳窗口", "先照常打开终端，再点悬浮入口旁的空槽＋，选择它。也可以把窗口标题栏拖到空槽，松手收纳。");
        var captureDemo = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 12, 0, 4) };
        captureDemo.Children.Add(Pill("终端窗口")); captureDemo.Children.Add(Text(" → ", 18, _skin.Accent)); captureDemo.Children.Add(Pill("＋  1")); first.Children.Add(captureDemo);
        var second = Step("02", "找回任务", "移入悬浮入口即可展开任务。点击形象进入对应窗口；按同一个窗口快捷键两次，可以唤出再恢复。");
        var portraits = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
        foreach (int number in new[] { 1, 2 }) {
            var portrait = new StackPanel { Width = 84 }; var slot = new Slot { Number = number };
            portrait.Children.Add(new Image { Source = EquipmentCatalog.Image(slot, preferences.Skin), Width = 62, Height = 60, Stretch = Stretch.Uniform });
            portrait.Children.Add(new TextBlock { Text = ShortcutBindings.Display(preferences.TaskGesture(number)), TextAlignment = TextAlignment.Center, FontSize = 10, TextWrapping = TextWrapping.Wrap }); portraits.Children.Add(portrait);
        }
        second.Children.Add(portraits);
        var third = Step("03", "整理或移出", "拖动任务形象可调整顺序。鼠标移到已收纳的槽位，点击右上角 ×，即可移出管理，终端继续运行。");
        var removeDemo = new DockPanel { Margin = new Thickness(4, 17, 4, 8) }; var cross = Text("×", 20, _skin.Muted); DockPanel.SetDock(cross, Dock.Right); removeDemo.Children.Add(cross); removeDemo.Children.Add(Text("任务 1   ·   移出管理", 12, _skin.Text)); third.Children.Add(removeDemo);
        foreach (var step in new[] { first, second, third }) steps.Children.Add(new Border { Child = step, Background = WuxiaTheme.Brush(_skin.Surface), BorderBrush = WuxiaTheme.Brush(_skin.Border), BorderThickness = new Thickness(.5), CornerRadius = new CornerRadius(9), Padding = new Thickness(15), Margin = new Thickness(5) });
        Children.Add(steps); SizeChanged += (_, _) => steps.Columns = ActualWidth < 650 ? 1 : 3;
        var start = new WrapPanel { Margin = new Thickness(0, 0, 0, 20) };
        var add = ActionButton("选择一个已有窗口", () => AddWindowRequested?.Invoke()); add.BorderBrush = WuxiaTheme.Brush(_skin.Accent); start.Children.Add(add);
        start.Children.Add(ActionButton("恢复上次任务", () => RecoveryRequested?.Invoke())); Children.Add(start);
        var heading = new DockPanel { Margin = new Thickness(0, 0, 0, 9) }; var edit = ActionButton("修改快捷键", () => ConfigureShortcutsRequested?.Invoke()); DockPanel.SetDock(edit, Dock.Right); heading.Children.Add(edit); heading.Children.Add(Text("当前快捷键 · 按需记住", 17, _skin.Text, true)); Children.Add(heading);
        foreach (var binding in Bindings.Where(b => b.Id >= 10)) Children.Add(KeyRow(binding.Name, ShortcutBindings.Display(binding.Gesture), binding.Purpose));
        Children.Add(KeyRow("滚轮切换", preferences.WheelSwitchEnabled ? Preferences.ModifierLabel(preferences.MouseModifiers) + "+滚轮" : "未设置", "直接切换已收纳的窗口，不必打开总览"));
        var taskKeys = new StackPanel(); foreach (var binding in Bindings.Where(b => b.Id < 10)) taskKeys.Children.Add(KeyRow(binding.Name, ShortcutBindings.Display(binding.Gesture), binding.Purpose));
        Children.Add(new Expander { Header = "查看窗口 1–9 的对应按键", Content = taskKeys, Margin = new Thickness(0, 12, 0, 14) });
        if (preferences.TabTogglesInventory && preferences.InventoryGesture == "Tab") Children.Add(Text("你当前使用单独 Tab 打开总览，因此终端的 Tab 补全会被接管。可点「修改快捷键」，改成带修饰键的组合，或清除该项。", 11, _skin.Waiting));
        if (warnings.Length > 0) Children.Add(Text("以下快捷键或监听当前不可用：\n" + warnings, 12, _skin.Waiting));
        var questions = new StackPanel();
        questions.Children.Add(Text("窗口关了怎么办？", 13, _skin.Text, true)); questions.Children.Add(Text("关闭终端后槽位会腾出，任务信息留在「最近任务」。从这里恢复时，缺少项目目录或启动方式的任务需要先补充配置。", 12, _skin.Muted));
        questions.Children.Add(Text("悬浮入口不见了怎么办？", 13, _skin.Text, true)); questions.Children.Add(Text("双击系统托盘中的 OmniVibe 图标可找回入口；也可以使用上方「显示 / 隐藏入口」快捷键。长按入口可移动，设置 → 窗口与布局可恢复默认位置。", 12, _skin.Muted));
        questions.Children.Add(Text("为什么 AI 状态是未知？", 13, _skin.Text, true)); questions.Children.Add(Text("拖入窗口只完成收纳。要显示运行、等待或回复，需要右键任务 → 更多任务操作 → 连接自动任务状态，选择 Claude Code 或 Codex，按提示启动会话。未接入时显示未知是正常情况；「本轮已回复」也不代表整个任务已完成。", 12, _skin.Muted));
        Children.Add(new Expander { Header = "常见问题：窗口恢复、入口隐藏与 AI 状态", Content = questions, Margin = new Thickness(0, 10, 0, 16) });
    }
    private TextBlock Text(string value, double size, string color, bool bold = false) => new() { Text = value, FontSize = size, Foreground = WuxiaTheme.Brush(color), FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 7), VerticalAlignment = VerticalAlignment.Center };
    private StackPanel Step(string number, string title, string description) { var body = new StackPanel(); body.Children.Add(Text(number, 11, _skin.Accent, true)); body.Children.Add(Text(title, 17, _skin.Text, true)); body.Children.Add(Text(description, 12, _skin.Muted)); return body; }
    private Border Pill(string label) => new() { Child = Text(label, 12, _skin.Text), Background = WuxiaTheme.Brush(_skin.Elevated), Padding = new Thickness(10, 3, 10, 3), CornerRadius = new CornerRadius(5), VerticalAlignment = VerticalAlignment.Center };
    private Button ActionButton(string label, Action action) { var button = new Button { Content = label, Padding = new Thickness(13, 8, 13, 8), MinHeight = 34, Margin = new Thickness(0, 0, 8, 0) }; button.Click += (_, _) => action(); return button; }
    private Grid KeyRow(string action, string keys, string purpose)
    {
        var row = new Grid { Margin = new Thickness(0, 4, 0, 4) }; row.ColumnDefinitions.Add(new() { Width = new GridLength(140) }); row.ColumnDefinitions.Add(new() { Width = new GridLength(180) }); row.ColumnDefinitions.Add(new());
        row.Children.Add(Text(action, 12, _skin.Text)); var key = Pill(keys); key.Margin = new Thickness(0, 0, 15, 0); Grid.SetColumn(key, 1); row.Children.Add(key);
        var description = Text(purpose, 11, _skin.Muted); Grid.SetColumn(description, 2); row.Children.Add(description); return row;
    }
}

public sealed class GettingStartedWindow : Window
{
    public string? NextAction { get; private set; }
    public GettingStartedWindow(Preferences preferences, Native.Rect area, string warnings = "", bool shortcutsPaused = false)
    {
        Title = "OmniVibe · 快速上手"; Topmost = true; ShowInTaskbar = false;
        var screen = Native.ScreenAtCursor(); double scale = screen.Scale;
        Width = Math.Min(980, (area.Right - area.Left) / scale - 40); Height = Math.Min(800, (area.Bottom - area.Top) / scale - 40);
        MinWidth = Math.Min(640, Width); MinHeight = Math.Min(420, Height);
        Left = (area.Left + area.Right) / (2 * scale) - Width / 2; Top = (area.Top + area.Bottom) / (2 * scale) - Height / 2;
        var skin = SkinCatalog.Current; Background = WuxiaTheme.Brush(skin.Background); Foreground = WuxiaTheme.Brush(skin.Text); Resources[typeof(Button)] = SettingsWindow.SettingsButtonStyle(skin);
        SourceInitialized += (_, _) => Native.Decorate(this, noActivate: false);
        var root = new DockPanel(); Content = root;
        var close = new Button { Content = "知道了，开始使用", IsDefault = true, MinHeight = 38, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(24, 12, 24, 18) }; close.Click += (_, _) => { DialogResult = true; }; DockPanel.SetDock(close, Dock.Bottom); root.Children.Add(close);
        var guide = new GettingStartedPanel(preferences, warnings, shortcutsPaused) { Margin = new Thickness(28, 24, 28, 8) };
        guide.AddWindowRequested += () => { NextAction = "add"; DialogResult = true; };
        guide.ConfigureShortcutsRequested += () => { NextAction = "keys"; DialogResult = true; };
        guide.RecoveryRequested += () => { NextAction = "recovery"; DialogResult = true; };
        root.Children.Add(new ScrollViewer { Content = guide, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
    }
}
