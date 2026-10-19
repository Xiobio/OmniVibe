using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;

namespace CodeManager;

/// <summary>Immediate, nonactivating task details, independent of the system tooltip delay.</summary>
internal sealed class SlotHintWindow : Window
{
    internal Slot Slot { get; }
    internal SlotHintWindow(Slot slot, bool remove = false)
    {
        Slot = slot; Width = 316; SizeToContent = SizeToContent.Height;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowActivated = false; ShowInTaskbar = false; Topmost = true;
        var skin = SkinCatalog.Current; Background = WuxiaTheme.Brush(skin.Background); Foreground = WuxiaTheme.Brush(skin.Text);
        var body = new StackPanel { Margin = new Thickness(13, 10, 13, 11) };
        var title = new TextBlock { FontSize = 13, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, MaxHeight = 42, TextTrimming = TextTrimming.CharacterEllipsis };
        var status = new TextBlock { FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0,6,0,0) };
        var project = new TextBlock { FontSize = 10, Foreground = WuxiaTheme.Brush(skin.Muted), TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0,5,0,0) };
        var action = new TextBlock { FontSize = 10, Foreground = WuxiaTheme.Brush(remove ? skin.Error : skin.Muted), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0,7,0,0) };
        body.Children.Add(title); body.Children.Add(status); body.Children.Add(project); body.Children.Add(action);
        void Refresh() {
            title.Text = slot.Number + " · " + (slot.Occupied ? slot.DisplayName : "添加窗口");
            status.Text = slot.Occupied ? slot.StateLabel : "点击＋选择已有窗口，也可以把窗口拖到这里";
            status.Foreground = WuxiaTheme.Brush(slot.Occupied ? slot.StateColor : skin.Muted);
            project.Text = slot.ProjectDirectory; project.Visibility = string.IsNullOrWhiteSpace(slot.ProjectDirectory) ? Visibility.Collapsed : Visibility.Visible;
            action.Text = slot.Occupied ? remove ? "点击×移出管理 · 终端窗口继续运行" : "左键进入 · 右上角×移出管理 · 拖动可调整顺序" : "选择窗口后即可按编号唤出";
        }
        void Changed(object? sender, PropertyChangedEventArgs e) => Refresh();
        Refresh(); slot.PropertyChanged += Changed; Closed += (_, _) => slot.PropertyChanged -= Changed;
        Content = new Border { Child = body, BorderBrush = WuxiaTheme.Brush(remove ? skin.Error : skin.Border), BorderThickness = new Thickness(1) };
        SourceInitialized += (_, _) => Native.Decorate(this, clickThrough: true);
    }
}
