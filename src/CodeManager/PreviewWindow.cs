using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

namespace CodeManager;

public sealed class PreviewWindow : Window
{
    private readonly Slot _slot;
    private IntPtr _thumbnail;
    public PreviewWindow(Slot slot)
    {
        _slot = slot;
        Width = 350; Height = 260; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowActivated = false; ShowInTaskbar = false; Topmost = true;
        Background = WuxiaTheme.Ink;
        var panel = new Grid { Margin = new Thickness(14) };
        panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        panel.RowDefinitions.Add(new RowDefinition());
        panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var header = new StackPanel();
        header.Children.Add(new TextBlock { Text = slot.DisplayName, FontSize = 14, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
        header.Children.Add(new TextBlock { Text = slot.StateLabel + " · " + (slot.StateSource == "" ? "未接入状态事件" : slot.StateSource), FontSize = 10, Foreground = WuxiaTheme.Brush("#B9A783"), Margin = new Thickness(0, 6, 0, 0) });
        panel.Children.Add(header);
        var footer = new TextBlock { Text = string.IsNullOrWhiteSpace(slot.Message) ? "最小化时预览可能暂停更新" : slot.Message, TextTrimming = TextTrimming.CharacterEllipsis, ToolTip = slot.Message, FontSize = 9, Foreground = WuxiaTheme.Bronze };
        Grid.SetRow(footer, 2); panel.Children.Add(footer); Content = panel;
        SourceInitialized += (_, _) => Native.Decorate(this);
        Closed += (_, _) => { if (_thumbnail != IntPtr.Zero) Native.DwmUnregisterThumbnail(_thumbnail); };
    }
    public void UpdateThumbnail()
    {
        if (_thumbnail != IntPtr.Zero) Native.DwmUnregisterThumbnail(_thumbnail);
        var scale = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformToDevice.M11 ?? 1;
        _thumbnail = Native.Thumbnail(new WindowInteropHelper(this).Handle, new(_slot.Window!.Handle), new((int)(14 * scale), (int)(60 * scale), (int)(336 * scale), (int)(226 * scale)));
    }
}
