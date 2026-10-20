using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace CodeManager;

/// <summary>Suite browsing is a draft; only the explicit Terminal button writes its appearance.</summary>
public sealed class SkinPicker : StackPanel
{
    private readonly ComboBox _choices = new() { FontSize = 14, MinHeight = 36 };
    private readonly SkinSuitePreview _scene = new() { Height = 340 };
    private readonly TextBlock _name = new() { FontSize = 22, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _description = new() { FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 0) };
    private readonly TextBlock _assetStatus = new() { FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 12) };
    private readonly TextBlock _feedback = new() { FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) };
    private readonly Button _terminal = new() { Content = "应用配套 Terminal 外观", HorizontalAlignment = HorizontalAlignment.Left, MinHeight = 36 };
    private readonly CheckBox _terminalAnimation = new() { Content = "Terminal 背景动画（较高资源占用）", IsChecked = false, Margin = new Thickness(0, 0, 0, 10) };
    private readonly UniformGrid _tiles = new() { Columns = 3, Margin = new Thickness(-4, 6, -4, 0) };
    private readonly Dictionary<Skin, Button> _tileButtons = new();
    private readonly Dictionary<string, Button> _tabs = new();
    private Func<bool>? _effectsEnabled, _decorationsEnabled;
    private bool _applyingTerminal;
    public Skin SelectedSkin => (_choices.SelectedItem as ComboBoxItem)?.Tag is Skin s ? s : Skin.InkJade;
    public SkinSuitePreview Scene => _scene;
    public void SelectSkin(Skin skin) => _choices.SelectedIndex = Math.Max(0, SkinCatalog.All.ToList().FindIndex(s => s.Id == skin));
    public event Action? SelectionChanged;
    public event Action? LoadoutRequested;
    public Func<bool>? EffectsEnabled { get => _effectsEnabled; set { _effectsEnabled = value; RefreshOptions(); } }
    public Func<bool>? DecorationsEnabled { get => _decorationsEnabled; set { _decorationsEnabled = value; RefreshOptions(); } }
    public SkinPicker(Skin selected)
    {
        var host = SkinCatalog.Current;
        foreach (var s in SkinCatalog.All) _choices.Items.Add(new ComboBoxItem { Content = s.Name, ToolTip = s.Subtitle, Tag = s.Id });
        _choices.SelectedIndex = Math.Max(0, SkinCatalog.All.ToList().FindIndex(s => s.Id == selected));
        AutomationProperties.SetName(_choices, "皮肤套装");
        // Selection state stays independent of the visual catalogue; no duplicate text dropdown.
        var heading = new StackPanel { Margin = new Thickness(0, 4, 0, 10) };
        _description.Foreground = WuxiaTheme.Brush(host.Muted);
        heading.Children.Add(_description); Children.Add(heading);
        var tabs = new WrapPanel { Margin = new Thickness(0, 0, 0, 10) };
        foreach (var (id, label) in new[] { ("suite", "整套效果"), ("dock", "任务圆环"), ("overview", "任务总览"), ("terminal", "Terminal"), ("states", "菜单与状态") })
        {
            var tab = new Button { Content = label, Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 0, 5, 5), MinHeight = 32, FontSize = 12, Tag = id };
            AutomationProperties.SetName(tab, "预览" + label);
            tab.Click += (_, _) => ShowPart(id); _tabs[id] = tab; tabs.Children.Add(tab);
        }
        Children.Add(tabs);
        var enlarge = new Button { Content = "放大预览 ↗", Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 0, 0, 5), MinHeight = 32, FontSize = 12 };
        enlarge.Click += (_, _) =>
        {
            var scene = new SkinSuitePreview { Mode = _scene.Mode };
            scene.SetSkin(SelectedSkin, TerminalAnimationEnabled, DecorationsEnabled?.Invoke() ?? true);
            var screen = Native.ScreenAtCursor();
            var window = new Window { Title = "主题预览 · " + SkinCatalog.Get(SelectedSkin).Name, Owner = Window.GetWindow(this), Width = Math.Min(1080, (screen.Work.Right - screen.Work.Left) / screen.Scale - 36), Height = Math.Min(640, (screen.Work.Bottom - screen.Work.Top) / screen.Scale - 36), WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = WuxiaTheme.Brush(SkinCatalog.Get(SelectedSkin).Background), Content = scene, ShowInTaskbar = false };
            window.ShowDialog();
        };
        tabs.Children.Add(enlarge);
        Children.Add(new Border { BorderBrush = WuxiaTheme.Brush(host.Border), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10), ClipToBounds = true, Child = _scene });
        _scene.AssetStatusChanged += () => _assetStatus.Text = _scene.AssetStatus;
        _assetStatus.Foreground = WuxiaTheme.Brush(host.Muted); Children.Add(_assetStatus);
        var apply = new Border { Background = WuxiaTheme.Brush(host.Surface), CornerRadius = new CornerRadius(9), Padding = new Thickness(16), Margin = new Thickness(0, 0, 0, 24) };
        var applyBody = new StackPanel();
        applyBody.Children.Add(new TextBlock { Text = "此按钮只应用 Terminal 外观，并自动备份其配置。默认使用静态插画和边框，动画需单独开启。", FontSize = 11, Foreground = WuxiaTheme.Brush(host.Muted), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 9) });
        AutomationProperties.SetName(_terminalAnimation, "Terminal 背景动画");
        _terminalAnimation.Checked += (_, _) => RefreshOptions();
        _terminalAnimation.Unchecked += (_, _) => RefreshOptions();
        applyBody.Children.Add(_terminalAnimation); applyBody.Children.Add(_terminal); applyBody.Children.Add(_feedback); apply.Child = applyBody;
        Children.Add(new Expander { Header = "配套 Terminal 外观 · 单独应用", Content = apply, Margin = new Thickness(0, 8, 0, 14) });
        foreach (var s in SkinCatalog.All.OrderBy(s => (int)s.Id >= (int)Skin.Hextech ? 0 : 1))
        {
            var tile = new Grid { Height = 78, ClipToBounds = true, Background = WuxiaTheme.Brush(s.Background) };
            var picture = Thumbnail(s);
            if (picture != null) tile.Children.Add(new Image { Source = picture, Stretch = Stretch.UniformToFill, Opacity = .88, IsHitTestVisible = false });
            tile.Children.Add(new Image { Source = EquipmentCatalog.Image(new Slot { Number = 1 }, s.Id), Width = 62, Height = 76, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Stretch = Stretch.Uniform, IsHitTestVisible = false, Margin = new Thickness(0, 1, 5, 0) });
            tile.Children.Add(new Border { Background = new LinearGradientBrush(Color.FromArgb(0, 0, 0, 0), Color.FromArgb(s.IsLight ? (byte)210 : (byte)240, s.IsLight ? (byte)245 : (byte)9, s.IsLight ? (byte)235 : (byte)14, s.IsLight ? (byte)210 : (byte)16), 90), IsHitTestVisible = false });
            var body = new StackPanel { Margin = new Thickness(8, 6, 8, 6), VerticalAlignment = VerticalAlignment.Bottom };
            string[] parts = s.Name.Split(" · ", 2);
            body.Children.Add(new TextBlock { Text = parts[0], Foreground = WuxiaTheme.Brush(s.Text), FontSize = 12, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
            body.Children.Add(new TextBlock { Text = parts.Length == 2 ? parts[1] : s.Subtitle, Foreground = WuxiaTheme.Brush(s.Muted), FontSize = 9, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 3, 0, 6) });
            var swatches = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (string color in new[] { s.Accent, s.Secondary, s.Running, s.Waiting }) swatches.Children.Add(new Border { Background = WuxiaTheme.Brush(color), Width = 14, Height = 3, CornerRadius = new CornerRadius(2), Margin = new Thickness(0, 0, 4, 0) });
            body.Children.Add(swatches); tile.Children.Add(body);
            var button = new Button { Content = tile, Padding = new Thickness(0), Margin = new Thickness(4), BorderThickness = new Thickness(1), HorizontalContentAlignment = HorizontalAlignment.Stretch, ToolTip = s.Name + "\n" + s.Subtitle, Tag = s.Id };
            AutomationProperties.SetName(button, "选择主题 " + s.Name);
            button.Click += (_, _) => { _choices.SelectedIndex = SkinCatalog.All.ToList().FindIndex(row => row.Id == s.Id); };
            _tileButtons[s.Id] = button; _tiles.Children.Add(button);
        }
        var details = new StackPanel { Margin = new Thickness(18, 0, 0, 0) };
        var detailChildren = Children.Cast<UIElement>().ToArray(); Children.Clear();
        details.Children.Add(_name);
        foreach (var child in detailChildren) details.Children.Add(child);
        var catalogue = new StackPanel();
        var catalogueHeading = new DockPanel();
        var equipment = new Button { Content = "角色与武器 →", FontSize = 11, Padding = new Thickness(8, 4, 8, 4), MinHeight = 27, Margin = new Thickness(6, 0, 0, 0) };
        equipment.Click += (_, _) => LoadoutRequested?.Invoke(); DockPanel.SetDock(equipment, Dock.Right); catalogueHeading.Children.Add(equipment);
        catalogueHeading.Children.Add(new TextBlock { Text = "选择主题", FontSize = 17, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center }); catalogue.Children.Add(catalogueHeading);
        catalogue.Children.Add(new TextBlock { Text = "直接点图片 · 预览不会修改当前外观", FontSize = 11, Foreground = WuxiaTheme.Brush(host.Muted), Margin = new Thickness(0, 6, 0, 10) });
        catalogue.Children.Add(_tiles);
        var studio = new Grid(); studio.ColumnDefinitions.Add(new()); studio.ColumnDefinitions.Add(new()); studio.RowDefinitions.Add(new() { Height = GridLength.Auto }); studio.RowDefinitions.Add(new() { Height = GridLength.Auto });
        studio.Children.Add(catalogue); Grid.SetColumn(details, 1); studio.Children.Add(details); Children.Add(studio);
        void ResizePreview() {
            bool wide = ActualWidth >= 790;
            studio.ColumnDefinitions[0].Width = new GridLength(1, GridUnitType.Star); studio.ColumnDefinitions[1].Width = wide ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
            Grid.SetColumn(details, wide ? 1 : 0); Grid.SetRow(details, wide ? 0 : 1); details.Margin = new Thickness(wide ? 18 : 0, wide ? 0 : 22, 0, 0);
            _tiles.Columns = wide ? 4 : ActualWidth < 430 ? 2 : ActualWidth < 650 ? 3 : 4;
            double width = wide ? ActualWidth / 2 - 18 : ActualWidth;
            _scene.Height = Math.Clamp(width * .61, 210, 360);
        }
        SizeChanged += (_, _) => ResizePreview(); Loaded += (_, _) => ResizePreview();
        _choices.SelectionChanged += (_, _) => RefreshPreview();
        _terminal.Click += async (_, _) =>
        {
            var skin = SkinCatalog.Get(SelectedSkin); _applyingTerminal = true; _terminal.IsEnabled = false; _feedback.Text = "正在备份并应用 " + skin.Name + "…";
            try
            {
                string script = Path.Combine(AppContext.BaseDirectory, "themes", "windows-terminal", "Apply-Skin.ps1");
                var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
                foreach (string arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script }) start.ArgumentList.Add(arg);
                foreach (string arg in TerminalAppearanceArguments()) start.ArgumentList.Add(arg);
                using var process = Process.Start(start) ?? throw new IOException("无法启动外观应用器");
                var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
                await process.WaitForExitAsync(); string result = await output; string problem = await error;
                if (process.ExitCode != 0) throw new IOException(problem.Length > 0 ? problem.Trim() : "应用失败，退出代码 " + process.ExitCode);
                using var json = JsonDocument.Parse(result); string backup = json.RootElement.GetProperty("BackupPath").GetString() ?? "";
                _feedback.Text = "Terminal 已应用「" + skin.Name + "」" + ((int)skin.Id < (int)Skin.Hextech ? "顶部配色" : "") + "；配置备份：" + backup; _feedback.ToolTip = _feedback.Text;
            }
            catch (Exception ex) { _feedback.Text = "Terminal 外观未应用：" + ex.Message; }
            finally { _applyingTerminal = false; _terminal.IsEnabled = true; }
        };
        ShowPart("suite"); RefreshPreview();
    }
    internal IReadOnlyList<string> TerminalAppearanceArguments()
    {
        var arguments = new List<string> { "-Skin", SkinCatalog.Get(SelectedSkin).Slug };
        if ((int)SelectedSkin < (int)Skin.Hextech) arguments.Add("-ChromeOnly");
        else {
            if (_terminalAnimation.IsChecked == true) arguments.Add("-EnableAnimation");
            if (DecorationsEnabled?.Invoke() == false) arguments.Add("-DisableArtwork");
        }
        return arguments;
    }
    private static BitmapSource? Thumbnail(SkinDefinition skin)
    {
        string path = Path.Combine(AppContext.BaseDirectory, skin.Artwork.Replace('/', Path.DirectorySeparatorChar));
        if (!File.Exists(path)) return null;
        try { var b = new BitmapImage(); b.BeginInit(); b.CacheOption = BitmapCacheOption.OnLoad; b.DecodePixelWidth = 360; b.UriSource = new Uri(path); b.EndInit(); b.Freeze(); return b; }
        catch (Exception ex) when (ex is IOException or NotSupportedException or FileFormatException) { return null; }
    }
    public void ShowPart(string id)
    {
        if (!_tabs.ContainsKey(id)) return;
        _scene.Mode = id; var host = SkinCatalog.Current;
        foreach (var pair in _tabs) { pair.Value.Background = WuxiaTheme.Brush(pair.Key == id ? host.Elevated : host.Surface); pair.Value.BorderBrush = WuxiaTheme.Brush(pair.Key == id ? host.Accent : host.Border); }
    }
    private bool TerminalAnimationEnabled => _terminalAnimation.IsEnabled && _terminalAnimation.IsChecked == true;
    public void RefreshOptions() => _scene.SetSkin(SelectedSkin, TerminalAnimationEnabled, DecorationsEnabled?.Invoke() ?? true);
    private void RefreshPreview()
    {
        var s = SkinCatalog.Get(SelectedSkin); _name.Text = s.Name; _description.Text = s.Subtitle + " · 圆环 / 总览 / Terminal / 菜单与状态";
        foreach (var pair in _tileButtons) { pair.Value.BorderBrush = WuxiaTheme.Brush(pair.Key == s.Id ? SkinCatalog.Current.Accent : SkinCatalog.Current.Border); pair.Value.BorderThickness = new Thickness(pair.Key == s.Id ? 2 : 1); }
        _terminal.IsEnabled = !_applyingTerminal;
        _terminal.Content = (int)s.Id >= (int)Skin.Hextech ? "应用配套 Terminal 外观" : "应用 Terminal 顶部配色";
        _terminalAnimation.IsEnabled = (int)s.Id >= (int)Skin.Hextech;
        if (!_applyingTerminal) _feedback.Text = (int)s.Id >= (int)Skin.Hextech ? "浏览主题不会自动改动 Terminal。" : "经典主题支持原生顶部配色；应用时保留当前终端背景与正文设置。";
        RefreshOptions(); SelectionChanged?.Invoke();
    }
}
