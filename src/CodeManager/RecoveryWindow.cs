using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;

namespace CodeManager;

public sealed class RecoveryWindow : Window
{
    public RecoveryWindow(Manager manager, Native.Rect area) : this(manager.State.Slots, area, manager.RestoreTask, manager.Rename, manager.PickWindow, manager.RestoreAllTasks, manager.ReconnectExisting, manager.ActivateSlot) { }
    internal RecoveryWindow(System.Collections.Generic.IEnumerable<Slot> slots, Native.Rect area, Func<Slot, string>? restore = null, Action<Slot>? configure = null, Action<Slot>? pick = null, Func<string>? restoreAll = null, Func<int>? reconnect = null, Action<int>? activate = null)
    {
        Title = "OmniVibe · 恢复工作现场"; Width = 920; Height = 760; MinWidth = 640; MinHeight = 420;
        Background = WuxiaTheme.Ink; Foreground = WuxiaTheme.Ivory; Topmost = true; ShowInTaskbar = false;
        SourceInitialized += (_, _) => Native.Decorate(this, noActivate: false);
        double scale = Native.ScreenAtCursor().Scale;
        Width = Math.Min(920, (area.Right - area.Left) / scale - 40); Height = Math.Min(760, (area.Bottom - area.Top) / scale - 40);
        Left = (area.Left + area.Right) / (2d * scale) - Width / 2; Top = (area.Top + area.Bottom) / (2d * scale) - Height / 2;
        var root = new DockPanel { Margin = new Thickness(24) };
        var header = new StackPanel(); DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);
        header.Children.Add(new TextBlock { Text = "恢复工作现场", FontFamily = SkinCatalog.Current.TitleFont, FontSize = 29 });
        header.Children.Add(new TextBlock { Text = "上次开的窗口、项目与任务都留在这里。先重连已有窗口，再恢复尚未打开的任务。", TextWrapping = TextWrapping.Wrap, FontSize = 13, Margin = new Thickness(0, 12, 0, 14) });
        var actions = new WrapPanel { Margin = new Thickness(0, 0, 0, 14) };
        var all = new Button { Content = "一键恢复已配置任务", Margin = new Thickness(0, 0, 10, 6), Background = WuxiaTheme.Brush(SkinCatalog.Current.Elevated) };
        var match = new Button { Content = "匹配已有窗口", Margin = new Thickness(0, 0, 10, 6) };
        actions.Children.Add(all); actions.Children.Add(match); header.Children.Add(actions);
        var feedback = new TextBlock { Text = "未配置的旧任务不会凭标题猜测启动命令。点击“配置恢复”补充一次，之后即可恢复。", TextWrapping = TextWrapping.Wrap, Foreground = WuxiaTheme.Gold, Margin = new Thickness(0, 0, 0, 14), FontSize = 12 }; header.Children.Add(feedback);
        all.Click += (_, _) => feedback.Text = restoreAll?.Invoke() ?? "示例预览";
        match.Click += (_, _) => feedback.Text = "已重连 " + (reconnect?.Invoke() ?? 0) + " 个可唯一确认的窗口";
        var footer = new DockPanel { Margin = new Thickness(0, 14, 0, 0) }; DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        var close = new Button { Content = "稍后继续 / 关闭", IsCancel = true, HorizontalAlignment = HorizontalAlignment.Right }; close.Click += (_, _) => Close(); DockPanel.SetDock(close, Dock.Right); footer.Children.Add(close);
        footer.Children.Add(new TextBlock { Text = "任务记录持续保存在本机 · 启动行为可在设置中调整", TextWrapping = TextWrapping.Wrap, FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 15, 0) });
        var list = new StackPanel();
        var tasks = slots.Where(s => s.Occupied).ToArray();
        if (tasks.Length == 0) list.Children.Add(new TextBlock { Text = "还没有保存的任务，先把终端拖进侧栏。", Margin = new Thickness(0, 30, 0, 0) });
        foreach (var slot in tasks)
        {
            var card = new Border { Background = WuxiaTheme.Wood, BorderBrush = WuxiaTheme.Bronze, BorderThickness = new Thickness(1), Padding = new Thickness(14), Margin = new Thickness(0, 0, 10, 12), DataContext = slot };
            var body = new StackPanel();
            var title = new TextBlock { FontSize = 17, TextTrimming = TextTrimming.CharacterEllipsis }; title.SetBinding(TextBlock.TextProperty, new Binding(nameof(Slot.DisplayName)) { StringFormat = slot.Number + " · {0}" }); body.Children.Add(title);
            var details = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = WuxiaTheme.Ivory, FontSize = 12, Margin = new Thickness(0, 8, 0, 8) }; details.SetBinding(TextBlock.TextProperty, nameof(Slot.RecoveryDetails)); body.Children.Add(details);
            var status = new TextBlock { Foreground = WuxiaTheme.Gold, TextWrapping = TextWrapping.Wrap, FontSize = 13 }; status.SetBinding(TextBlock.TextProperty, nameof(Slot.RecoveryLabel)); body.Children.Add(status);
            var row = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
            var open = new Button { Content = "恢复 / 唤出", Margin = new Thickness(0, 0, 8, 0) };
            var edit = new Button { Content = "配置恢复", Margin = new Thickness(0, 0, 8, 0) };
            var select = new Button { Content = "选择已有窗口" };
            open.Click += (_, _) => { if (slot.Connected) { Close(); activate?.Invoke(slot.Number); } else feedback.Text = restore?.Invoke(slot) ?? "示例预览"; };
            edit.Click += (_, _) => { configure?.Invoke(slot); slot.Refresh(); };
            select.Click += (_, _) => { pick?.Invoke(slot); slot.Refresh(); };
            row.Children.Add(open); row.Children.Add(edit); row.Children.Add(select); body.Children.Add(row); card.Child = body; list.Children.Add(card);
        }
        root.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }); Content = root;
    }
}
