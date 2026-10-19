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
    private readonly UniformGrid _tiles = new() { Columns = 3, Margin = new Thickness(-4, 6, -4, 0) };
    private readonly Dictionary<Skin, Button> _tileButtons = new();
    private readonly Dictionary<string, Button> _tabs = new();
    private Func<bool>? _effectsEnabled, _decorationsEnabled;
    private bool _applyingTerminal;
    public Skin SelectedSkin => (_choices.SelectedItem as ComboBoxItem)?.Tag is Skin s ? s : Skin.InkJade;
    public SkinSuitePreview Scene => _scene;
    public event Action? SelectionChanged;
    public Func<bool>? EffectsEnabled { get => _effectsEnabled; set { _effectsEnabled = value; RefreshOptions(); } }
    public Func<bool>? DecorationsEnabled { get => _decorationsEnabled; set { _decorationsEnabled = value; RefreshOptions(); } }
    public SkinPicker(Skin selected)
    {
        var host = SkinCatalog.Current;
        foreach (var s in SkinCatalog.All) _choices.Items.Add(new ComboBoxItem { Content = s.Name, ToolTip = s.Subtitle, Tag = s.Id });
        _choices.SelectedIndex = Math.Max(0, SkinCatalog.All.ToList().FindIndex(s => s.Id == selected));
        AutomationProperties.SetName(_choices, "皮肤套装");
        Children.Add(_choices);
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
            scene.SetSkin(SelectedSkin, EffectsEnabled?.Invoke() ?? false, DecorationsEnabled?.Invoke() ?? true);
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
        applyBody.Children.Add(new TextBlock { Text = "两处外观，分别应用", FontSize = 13, FontWeight = FontWeights.SemiBold });
        applyBody.Children.Add(new TextBlock { Text = "OmniVibe：点击底部「保存并应用」。Terminal：使用下方按钮单独应用，会自动备份配置。", FontSize = 12, Foreground = WuxiaTheme.Brush(host.Muted), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 12) });
        applyBody.Children.Add(_terminal); applyBody.Children.Add(_feedback); apply.Child = applyBody; Children.Add(apply);
        Children.Add(new TextBlock { Text = "全部主题套装", FontSize = 17, FontWeight = FontWeights.SemiBold });
        Children.Add(new TextBlock { Text = "点击主题查看整套效果 · 十套游戏风格 + 三套经典主题", FontSize = 12, Foreground = WuxiaTheme.Brush(host.Muted), Margin = new Thickness(0, 5, 0, 6) });
        foreach (var s in SkinCatalog.All)
        {
            var tile = new Grid { Height = 103, ClipToBounds = true, Background = WuxiaTheme.Brush(s.Background) };
            var picture = Thumbnail(s);
            if (picture != null) tile.Children.Add(new Image { Source = picture, Stretch = Stretch.UniformToFill, Opacity = s.IsLight ? .17 : .24, IsHitTestVisible = false });
            var body = new StackPanel { Margin = new Thickness(12, 10, 12, 8), VerticalAlignment = VerticalAlignment.Bottom };
            string[] parts = s.Name.Split(" · ", 2);
            body.Children.Add(new TextBlock { Text = parts[0], Foreground = WuxiaTheme.Brush(s.Text), FontSize = 14, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
            body.Children.Add(new TextBlock { Text = parts.Length == 2 ? parts[1] : s.Subtitle, Foreground = WuxiaTheme.Brush(s.Muted), FontSize = 10, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 4, 0, 9) });
            var swatches = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (string color in new[] { s.Accent, s.Secondary, s.Running, s.Waiting }) swatches.Children.Add(new Border { Background = WuxiaTheme.Brush(color), Width = 20, Height = 4, CornerRadius = new CornerRadius(2), Margin = new Thickness(0, 0, 4, 0) });
            body.Children.Add(swatches); tile.Children.Add(body);
            var button = new Button { Content = tile, Padding = new Thickness(0), Margin = new Thickness(4), BorderThickness = new Thickness(1), HorizontalContentAlignment = HorizontalAlignment.Stretch, ToolTip = s.Name + "\n" + s.Subtitle, Tag = s.Id };
            AutomationProperties.SetName(button, "选择主题 " + s.Name);
            button.Click += (_, _) => { _choices.SelectedIndex = SkinCatalog.All.ToList().FindIndex(row => row.Id == s.Id); _choices.BringIntoView(); };
            _tileButtons[s.Id] = button; _tiles.Children.Add(button);
        }
        Children.Add(_tiles);
        void ResizePreview() { _tiles.Columns = ActualWidth < 520 ? 2 : ActualWidth < 800 ? 3 : 4; double height = Window.GetWindow(this)?.ActualHeight ?? 900; _scene.Height = Math.Clamp(Math.Min(ActualWidth * .51, height * .42), 220, 410); }
        SizeChanged += (_, _) => ResizePreview(); Loaded += (_, _) => ResizePreview();
        _choices.SelectionChanged += (_, _) => RefreshPreview();
        _terminal.Click += async (_, _) =>
        {
            var skin = SkinCatalog.Get(SelectedSkin); _applyingTerminal = true; _terminal.IsEnabled = false; _feedback.Text = "正在备份并应用 " + skin.Name + "…";
            try
            {
                string script = Path.Combine(AppContext.BaseDirectory, "themes", "windows-terminal", "Apply-Skin.ps1");
                var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
                foreach (string arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-Skin", skin.Slug }) start.ArgumentList.Add(arg);
                if ((int)skin.Id < (int)Skin.Hextech) start.ArgumentList.Add("-ChromeOnly");
                else
                {
                    if (EffectsEnabled?.Invoke() == false) start.ArgumentList.Add("-DisableEffects");
                    if (DecorationsEnabled?.Invoke() == false) start.ArgumentList.Add("-DisableArtwork");
                }
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
    public void RefreshOptions() => _scene.SetSkin(SelectedSkin, EffectsEnabled?.Invoke() ?? false, DecorationsEnabled?.Invoke() ?? true);
    private void RefreshPreview()
    {
        var s = SkinCatalog.Get(SelectedSkin); _name.Text = s.Name; _description.Text = s.Subtitle + " · 圆环 / 总览 / Terminal / 菜单与状态";
        foreach (var pair in _tileButtons) { pair.Value.BorderBrush = WuxiaTheme.Brush(pair.Key == s.Id ? SkinCatalog.Current.Accent : SkinCatalog.Current.Border); pair.Value.BorderThickness = new Thickness(pair.Key == s.Id ? 2 : 1); }
        _terminal.IsEnabled = !_applyingTerminal;
        _terminal.Content = (int)s.Id >= (int)Skin.Hextech ? "应用配套 Terminal 外观" : "应用 Terminal 顶部配色";
        if (!_applyingTerminal) _feedback.Text = (int)s.Id >= (int)Skin.Hextech ? "浏览主题不会自动改动 Terminal。" : "经典主题支持原生顶部配色；应用时保留当前终端背景与正文设置。";
        RefreshOptions(); SelectionChanged?.Invoke();
    }
}
