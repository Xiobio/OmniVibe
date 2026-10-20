using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace CodeManager;

public static class Dialogs
{
    private static Window Shell(string title, double height, Native.Rect area)
    {
        var window = new Window { Title = title, Width = 520, Height = height, ResizeMode = ResizeMode.NoResize, Background = WuxiaTheme.Ink, WindowStartupLocation = WindowStartupLocation.Manual, Topmost = true, ShowInTaskbar = false };
        window.SourceInitialized += (_, _) => Native.Decorate(window, noActivate: false);
        double scale = Native.ScreenAtCursor().Scale;
        window.Left = (area.Left + (area.Right - area.Left) / 2d) / scale - window.Width / 2;
        window.Top = (area.Top + (area.Bottom - area.Top) / 2d) / scale - height / 2;
        window.PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) window.DialogResult = false; };
        return window;
    }
    public static string? Rename(string current, Native.Rect area)
    {
        var window = Shell(L.T("重命名任务"), 215, area);
        var panel = new StackPanel { Margin = new Thickness(22) };
        panel.Children.Add(new TextBlock { Text = L.T("用任务名称辨认窗口"), FontSize = 16, Margin = new Thickness(0, 0, 0, 14) });
        var text = new TextBox { Text = current, MaxLength = 80 }; panel.Children.Add(text);
        var button = new Button { Content = L.T("保存名称"), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 15, 0, 0), IsDefault = true };
        button.Click += (_, _) => { if (!string.IsNullOrWhiteSpace(text.Text)) window.DialogResult = true; };
        panel.Children.Add(button); window.Content = panel;
        window.Loaded += (_, _) => { text.Focus(); text.SelectAll(); };
        return window.ShowDialog() == true ? text.Text.Trim() : null;
    }
    public static WindowIdentity? Pick(int number, Native.Rect area, Slot? reconnect = null, System.Collections.Generic.IEnumerable<Slot>? slots = null)
    {
        var window = Shell(L.T("绑定窗口到槽位 ") + number, 440, area);
        var panel = new DockPanel { Margin = new Thickness(18) };
        var title = new TextBlock { Text = reconnect?.Occupied == true ? L.T("重新连接窗口 · 保留任务名与颜色") : L.T("选择一个窗口，或拖动标题栏到槽位"), FontSize = 14, Margin = new Thickness(0, 0, 0, 14) };
        DockPanel.SetDock(title, Dock.Top); panel.Children.Add(title);
        var search = new TextBox { Margin = new Thickness(0, 0, 0, 10), ToolTip = L.T("按标题或进程名筛选") };
        DockPanel.SetDock(search, Dock.Top); panel.Children.Add(search);
        var confirm = new Button { Content = L.T("绑定选中的窗口"), Margin = new Thickness(0, 12, 0, 0), HorizontalAlignment = HorizontalAlignment.Right, IsDefault = true };
        DockPanel.SetDock(confirm, Dock.Bottom); panel.Children.Add(confirm);
        var occupied = (slots ?? Array.Empty<Slot>()).Where(s => s.Number != number && Native.Matches(s.Window)).Select(s => s.Window!.Handle).ToHashSet();
        int Score(WindowIdentity window) => (window.ProcessName == reconnect?.Window?.ProcessName ? 10 : 0) + (window.Title == reconnect?.Window?.Title ? 50 : 0) + (reconnect?.ProjectLabel.Length > 0 && window.Title.Contains(reconnect.ProjectLabel, StringComparison.OrdinalIgnoreCase) ? 30 : 0) + (window.ProcessName.ToLowerInvariant() is "windowsterminal" or "powershell" or "pwsh" or "cmd" or "conhost" ? 5 : 0);
        var candidates = Native.Windows().Where(w => !occupied.Contains(w.Handle)).OrderByDescending(Score).ToList();
        var list = new ListBox { Background = WuxiaTheme.Wood, Foreground = WuxiaTheme.Ivory, BorderThickness = new Thickness(0), DisplayMemberPath = "Title", Padding = new Thickness(5), ItemsSource = candidates };
        panel.Children.Add(list);
        search.TextChanged += (_, _) => list.ItemsSource = candidates.Where(w => (w.Title + " " + w.ProcessName).Contains(search.Text, StringComparison.OrdinalIgnoreCase)).ToList();
        confirm.Click += (_, _) => { if (list.SelectedItem != null) window.DialogResult = true; };
        list.MouseDoubleClick += (_, _) => { if (list.SelectedItem != null) window.DialogResult = true; };
        window.Content = panel;
        window.Loaded += (_, _) => search.Focus();
        return window.ShowDialog() == true ? list.SelectedItem as WindowIdentity : null;
    }
}
