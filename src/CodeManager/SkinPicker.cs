using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace CodeManager;

/// <summary>Previews are local; saving settings applies the skin without changing task data.</summary>
public sealed class SkinPicker : StackPanel
{
    private readonly ComboBox _choices = new() { FontSize = 14 };
    private readonly Border _preview = new() { Height = 205, Margin = new Thickness(0, 12, 0, 8), ClipToBounds = true };
    private readonly TextBlock _description = new() { TextWrapping = TextWrapping.Wrap, FontSize = 12, Margin = new Thickness(0, 3, 0, 10) };
    private readonly Button _terminal = new() { Content = "应用配套 Terminal 外观", HorizontalAlignment = HorizontalAlignment.Left };
    private readonly TextBlock _feedback = new() { TextWrapping = TextWrapping.Wrap, FontSize = 12, Margin = new Thickness(0, 8, 0, 0) };
    public Skin SelectedSkin => (_choices.SelectedItem as ComboBoxItem)?.Tag is Skin s ? s : Skin.InkJade;
    public Func<bool>? EffectsEnabled { get; set; }
    public Func<bool>? DecorationsEnabled { get; set; }
    public SkinPicker(Skin selected)
    {
        foreach (var skin in SkinCatalog.All) _choices.Items.Add(new ComboBoxItem { Content = skin.Name + "  ·  " + skin.Subtitle, Tag = skin.Id });
        _choices.SelectedIndex = SkinCatalog.All.ToList().FindIndex(s => s.Id == selected);
        AutomationProperties.SetName(_choices, "皮肤套装");
        Children.Add(_choices); Children.Add(_preview); Children.Add(_description); Children.Add(_terminal); Children.Add(_feedback);
        _choices.SelectionChanged += (_, _) => RefreshPreview();
        _terminal.Click += async (_, _) =>
        {
            var skin = SkinCatalog.Get(SelectedSkin);
            _terminal.IsEnabled = false; _feedback.Text = "正在备份配置并应用 " + skin.Name + "…";
            try
            {
                string script = Path.Combine(AppContext.BaseDirectory, "themes", "windows-terminal", "Apply-Skin.ps1");
                var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
                foreach (string arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-Skin", skin.Slug }) start.ArgumentList.Add(arg);
                if (EffectsEnabled?.Invoke() == false || DecorationsEnabled?.Invoke() == false) start.ArgumentList.Add("-DisableEffects");
                if (DecorationsEnabled?.Invoke() == false) start.ArgumentList.Add("-DisableArtwork");
                using var process = Process.Start(start) ?? throw new IOException("无法启动外观应用器");
                var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
                await process.WaitForExitAsync(); string result = await output; string problem = await error;
                if (process.ExitCode != 0) throw new IOException(problem.Length > 0 ? problem.Trim() : "应用失败，退出代码 " + process.ExitCode);
                using var json = JsonDocument.Parse(result);
                string backup = json.RootElement.GetProperty("BackupPath").GetString() ?? "";
                _feedback.Text = "已应用 " + skin.Name + "。Terminal 会自动载入外观；备份：\n" + backup;
                _feedback.ToolTip = _feedback.Text;
            }
            catch (Exception ex) { _feedback.Text = "Terminal 外观未应用：" + ex.Message; }
            finally { _terminal.IsEnabled = true; }
        };
        RefreshPreview();
    }
    private void RefreshPreview()
    {
        var s = SkinCatalog.Get(SelectedSkin);
        _preview.Background = WuxiaTheme.Brush(s.Background); _preview.BorderBrush = WuxiaTheme.Brush(s.Border);
        _preview.BorderThickness = new Thickness(1); _preview.CornerRadius = new CornerRadius(s.CornerRadius);
        var grid = new Grid();
        string art = Path.Combine(AppContext.BaseDirectory, s.Artwork.Replace('/', Path.DirectorySeparatorChar));
        if (File.Exists(art))
        {
            try
            {
                var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.UriSource = new Uri(art); bitmap.DecodePixelWidth = 900; bitmap.EndInit(); bitmap.Freeze();
                grid.Children.Add(new Image { Source = bitmap, Stretch = Stretch.UniformToFill, Opacity = s.IsLight ? .66 : .45, IsHitTestVisible = false });
            }
            catch (Exception ex) when (ex is IOException or NotSupportedException or FileFormatException) { }
        }
        var text = new StackPanel { Margin = new Thickness(18, 15, 18, 12), HorizontalAlignment = HorizontalAlignment.Left };
        text.Children.Add(new TextBlock { Text = s.Name, Foreground = WuxiaTheme.Brush(s.Text), FontFamily = s.TitleFont, FontSize = 25 });
        text.Children.Add(new TextBlock { Text = s.Subtitle, Foreground = WuxiaTheme.Brush(s.Muted), FontSize = 11, Margin = new Thickness(0, 5, 0, 15) });
        var states = new WrapPanel { MaxWidth = 320 };
        foreach (var (label, color) in new[] { ("▶ 执行", s.Running), ("Ⅱ 等待", s.Waiting), ("✓ 已回复", s.Ready), ("! 错误", s.Error), ("? 未知", s.Unknown) })
            states.Children.Add(new Border { Background = WuxiaTheme.Brush(s.Surface), CornerRadius = new CornerRadius(3), Padding = new Thickness(7, 5, 7, 5), Margin = new Thickness(0, 0, 6, 6), Child = new TextBlock { Text = label, Foreground = WuxiaTheme.Brush(color), FontSize = 12 } });
        text.Children.Add(states); grid.Children.Add(text); _preview.Child = grid;
        _description.Text = "覆盖侧栏、九槽总览、任务状态、菜单与设置。保存后应用，任务与窗口位置保持不变。";
        bool terminal = (int)s.Id >= (int)Skin.Hextech;
        _terminal.Visibility = terminal ? Visibility.Visible : Visibility.Collapsed;
        _feedback.Text = terminal ? "配套 Terminal 单独应用；会先备份配置，保留命令、快捷键及 Profile 自定义。" : "经典皮肤；Terminal 可使用仓库中的 InkJade 套装。";
    }
}
