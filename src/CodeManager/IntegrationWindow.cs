using System;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace CodeManager;

public sealed class IntegrationWindow : Window
{
    public static string Command(Slot slot, string provider, string root)
    {
        string script = Path.Combine(AppContext.BaseDirectory, "scripts", "Start-TrackedSession.ps1");
        string Quote(string text) => "'" + text.Replace("'", "''") + "'";
        string command = "& " + Quote(script) + " -TaskId " + Quote(slot.Id) + " -Provider " + Quote(provider) + " -DataRoot " + Quote(root);
        if (slot.ProjectDirectory != "") command += " -ProjectDirectory " + Quote(slot.ProjectDirectory);
        return "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
    }
    public IntegrationWindow(Slot slot, string provider, string root, Native.Rect area)
    {
        Title = "连接 " + (provider == "claude" ? "Claude Code" : "Codex") + " 状态";
        Width = 590; Height = 510; ResizeMode = ResizeMode.NoResize; Topmost = true; ShowInTaskbar = false;
        Background = WuxiaTheme.Ink;
        SourceInitialized += (_, _) => Native.Decorate(this, noActivate: false);
        double scale = Native.ScreenAtCursor().Scale;
        Height = Math.Min(510, (area.Bottom - area.Top) / scale - 40);
        Left = (area.Left + (area.Right - area.Left) / 2d) / scale - Width / 2; Top = (area.Top + (area.Bottom - area.Top) / 2d) / scale - Height / 2;
        var rootPanel = new DockPanel { Margin = new Thickness(24) };
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock { Text = slot.Number + " · " + slot.DisplayName, FontSize = 19, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 0, 0, 16) });
        var connection = new TextBlock { DataContext = slot, Foreground = WuxiaTheme.Jade, FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 14) }; connection.SetBinding(TextBlock.TextProperty, nameof(Slot.IntegrationLabel)); panel.Children.Add(connection);
        panel.Children.Add(new TextBlock { Text = "在这个任务对应的 terminal 里执行下方命令。若 CLI 正在运行，请先正常退出 CLI，再执行接入命令。", TextWrapping = TextWrapping.Wrap, FontSize = 13, Margin = new Thickness(0, 0, 0, 14) });
        panel.Children.Add(new TextBlock { Text = "接入后会自动显示：正在执行、等待确认、本轮已回复。事件只关联本任务，不会按项目名称猜测窗口。", TextWrapping = TextWrapping.Wrap, FontSize = 12, Foreground = WuxiaTheme.Brush("#B9A783"), Margin = new Thickness(0, 0, 0, 14) });
        var command = new TextBox { Text = Command(slot, provider, root), IsReadOnly = true, TextWrapping = TextWrapping.Wrap, MaxHeight = 100, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, FontSize = 10 }; panel.Children.Add(command);
        if (provider == "codex") panel.Children.Add(new TextBlock { Text = "Codex 首次提示 hooks 待审核时，输入 /hooks 查看并信任 CodeManager 的观察脚本，状态接入才会生效。", TextWrapping = TextWrapping.Wrap, Foreground = WuxiaTheme.Gold, FontSize = 12, Margin = new Thickness(0, 12, 0, 0) });
        panel.Children.Add(new TextBlock { Text = "仅为此会话添加观察 hooks；不会修改全局 CLI 配置，也不会替你批准任何操作。", TextWrapping = TextWrapping.Wrap, FontSize = 11, Foreground = WuxiaTheme.Brush("#B9A783"), Margin = new Thickness(0, 12, 0, 0) });
        var copy = new Button { Content = "复制接入命令", HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) };
        copy.Click += (_, _) => { Clipboard.SetText(command.Text); copy.Content = "已复制，在对应终端执行"; };
        DockPanel.SetDock(copy, Dock.Bottom); rootPanel.Children.Add(copy);
        rootPanel.Children.Add(new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }); Content = rootPanel;
        PreviewKeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Escape) Close(); };
    }
}
