using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace CodeManager;

/// <summary>Skin geometry is separate from task state; the preview never covers task information.</summary>
public sealed class SkinTaskCard : Grid
{
    private readonly Slot _slot;
    private readonly SkinDefinition _skin;
    private readonly bool _animate;
    private readonly Border _frame;
    private readonly TextBlock _state, _name, _metadata, _badge, _placeholder, _previewHint;
    private readonly Border _badgeFrame;
    private Border? _unitBanner;
    private readonly SkinCardOrnament _ornament;
    private readonly Brush _cardSurface;
    private readonly ScaleTransform _scale = new(1, 1);
    private readonly TranslateTransform _translation = new();
    private string _lastState = "";
    public FrameworkElement PreviewRegion { get; }

    public SkinTaskCard(Slot slot, bool animate)
    {
        _slot = slot; _skin = SkinCatalog.Current; _animate = animate;
        DataContext = slot; Margin = new Thickness(7, 6, 7, 8); Cursor = System.Windows.Input.Cursors.Hand;
        SetBinding(ToolTipProperty, new Binding(nameof(Slot.Tooltip)));
        RenderTransformOrigin = new Point(.5, .5);
        var transforms = new TransformGroup(); transforms.Children.Add(_scale); transforms.Children.Add(_translation); RenderTransform = transforms;
        bool ink = _skin.Family == "ink";
        _cardSurface = SkinCatalog.DecorationsEnabled ? ink ? WuxiaTheme.Paper : SkinMaterials.Create(_skin, true) : WuxiaTheme.Brush(_skin.CardBackground);
        _frame = new Border { BorderThickness = new Thickness(1), Padding = new Thickness(ink ? 16 : 13, 11, ink ? 16 : 13, 10), CornerRadius = new CornerRadius(_skin.CornerRadius), Background = _cardSurface };
        Children.Add(_frame);
        _ornament = new SkinCardOrnament(_skin, compact: false) { IsHitTestVisible = false };
        Children.Add(_ornament);
        var body = new Grid(); body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); body.RowDefinitions.Add(new RowDefinition()); body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _frame.Child = body;
        var top = new Grid(); top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); top.ColumnDefinitions.Add(new ColumnDefinition()); top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var number = NumberPlaque(slot.Number, _skin, 28);
        top.Children.Add(number);
        var stateGroup = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(9, 0, 4, 0) };
        if (_skin.Family is "tactical" or "protocol") stateGroup.Children.Add(new TextBlock { Text = _skin.Family == "tactical" ? "DEVICE // " + slot.Number.ToString("00") : "AGENT / " + slot.Number.ToString("00"), FontSize = 8, Foreground = WuxiaTheme.Brush(_skin.Muted) });
        _state = new TextBlock { FontFamily = WuxiaTheme.BodyFont, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis, FontWeight = FontWeights.SemiBold };
        stateGroup.Children.Add(_state); Grid.SetColumn(stateGroup, 1); top.Children.Add(stateGroup);
        _badge = new TextBlock { FontSize = 8.5, FontWeight = FontWeights.Bold, TextAlignment = TextAlignment.Center };
        _badgeFrame = new Border { Padding = new Thickness(5, 3, 5, 3), CornerRadius = new CornerRadius(Math.Min(8, _skin.CornerRadius)), Child = _badge, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(_badgeFrame, 2); top.Children.Add(_badgeFrame); body.Children.Add(top);

        var preview = new Border { Background = WuxiaTheme.Brush(_skin.Background), BorderBrush = WuxiaTheme.Brush(_skin.Border), BorderThickness = new Thickness(.5), Margin = new Thickness(0, 9, 0, 8), ClipToBounds = true, CornerRadius = new CornerRadius(Math.Min(_skin.CornerRadius, 6)) };
        var placeholder = new Grid { ClipToBounds = true };
        if (SkinCatalog.DecorationsEnabled) placeholder.Children.Add(new SkinGlyph(animate) { Width = 90, Height = 90, Opacity = .22, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        var message = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8) };
        _placeholder = new TextBlock { FontSize = 21, FontFamily = _skin.TitleFont, TextAlignment = TextAlignment.Center, Foreground = WuxiaTheme.Brush(_skin.Accent) };
        _previewHint = new TextBlock { FontSize = 10, TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 5, 0, 0), Foreground = WuxiaTheme.Brush(_skin.Muted) };
        message.Children.Add(_placeholder); message.Children.Add(_previewHint); placeholder.Children.Add(message); preview.Child = placeholder;
        PreviewRegion = preview; Grid.SetRow(preview, 1); body.Children.Add(preview);
        preview.SizeChanged += (_, e) =>
        {
            _placeholder.MaxWidth = Math.Max(40, e.NewSize.Width - 16); _previewHint.MaxWidth = Math.Max(40, e.NewSize.Width - 16);
            _placeholder.FontSize = e.NewSize.Height < 60 ? 14 : e.NewSize.Width < 180 ? 16 : 21;
            _previewHint.Visibility = e.NewSize.Height < 75 ? Visibility.Collapsed : Visibility.Visible;
        };
        var foot = new StackPanel();
        _name = new TextBlock { FontSize = _skin.Family == "ink" ? 16 : 14, FontFamily = _skin.Family == "ink" ? _skin.TitleFont : WuxiaTheme.BodyFont, FontWeight = FontWeights.SemiBold, Foreground = WuxiaTheme.Brush(_skin.CardText), TextTrimming = TextTrimming.CharacterEllipsis };
        _metadata = new TextBlock { FontSize = 10, Foreground = WuxiaTheme.Brush(_skin.CardText), Opacity = .8, Margin = new Thickness(0, 4, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis };
        foot.Children.Add(_name); foot.Children.Add(_metadata); Grid.SetRow(foot, 2); body.Children.Add(foot);
        // The different families use different chassis, rather than recoloring a scroll.
        if (_skin.Family == "protocol")
        {
            top.Children.Remove(number); top.ColumnDefinitions[0].Width = new GridLength(0);
            var actionRail = new Grid(); actionRail.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(39) }); actionRail.ColumnDefinitions.Add(new ColumnDefinition());
            var rail = new StackPanel { Margin = new Thickness(0, 1, 9, 0) };
            rail.Children.Add(new TextBlock { Text = slot.Number.ToString("00"), FontFamily = _skin.TitleFont, FontSize = 27, FontWeight = FontWeights.Bold, Foreground = WuxiaTheme.Brush(_skin.Accent) });
            rail.Children.Add(new Border { Height = 3, Margin = new Thickness(0, 7, 0, 7), Background = WuxiaTheme.Brush(_skin.Accent) });
            rail.Children.Add(new TextBlock { Text = "OPS", FontSize = 8, FontWeight = FontWeights.Bold, Foreground = WuxiaTheme.Brush(_skin.Muted) });
            actionRail.Children.Add(rail); _frame.Child = null; Grid.SetColumn(body, 1); actionRail.Children.Add(body); _frame.Child = actionRail;
        }
        if (_skin.Family == "formation")
        {
            preview.CornerRadius = new CornerRadius(12); preview.BorderThickness = new Thickness(2);
            body.Children.Remove(foot);
            var banner = new Border { CornerRadius = new CornerRadius(7), Background = WuxiaTheme.Brush(_skin.Elevated), Padding = new Thickness(8, 6, 8, 6), Child = foot };
            _unitBanner = banner;
            Grid.SetRow(banner, 2); body.Children.Add(banner);
            _name.FontSize = 13; _metadata.Margin = new Thickness(0, 3, 0, 0);
        }
        if (_skin.Family == "fantasy")
        {
            preview.CornerRadius = new CornerRadius(12); preview.BorderThickness = new Thickness(1.5);
            _name.TextAlignment = TextAlignment.Center; _metadata.TextAlignment = TextAlignment.Center;
        }
        if (_skin.Family == "equipment")
        {
            preview.BorderThickness = new Thickness(3); preview.Margin = new Thickness(2, 10, 2, 8);
            _name.FontFamily = _skin.TitleFont;
        }
        if (_skin.Family == "astral")
        {
            _name.TextAlignment = TextAlignment.Center; _metadata.TextAlignment = TextAlignment.Center;
            preview.Margin = new Thickness(5, 10, 5, 8);
        }
        if (_skin.Family == "wonderland")
        {
            preview.CornerRadius = new CornerRadius(16); preview.BorderThickness = new Thickness(2);
            _name.FontFamily = _skin.TitleFont; _name.FontSize = 16; _name.TextAlignment = TextAlignment.Center;
        }
        if (_skin.Family is "relic" or "arsenal")
        {
            _frame.Padding = new Thickness(18, _skin.Family == "relic" ? 21 : 13, 18, 14);
            _name.TextAlignment = TextAlignment.Center; _metadata.TextAlignment = TextAlignment.Center;
        }
        if (_skin.Family is "formation" or "wonderland") _frame.Padding = new Thickness(15, 13, 15, 13);
        if (ink)
        {
            _frame.Margin = new Thickness(4, 7, 4, 7);
            foreach (var alignment in new[] { VerticalAlignment.Top, VerticalAlignment.Bottom })
                Children.Add(new Border { Height = 9, VerticalAlignment = alignment, Background = WuxiaTheme.Wood, BorderBrush = WuxiaTheme.Brush(_skin.Border), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(3), IsHitTestVisible = false });
        }
        var normalPadding = _frame.Padding; var normalPreviewMargin = preview.Margin; var normalFrameMargin = _frame.Margin; double normalNameSize = _name.FontSize;
        SizeChanged += (_, _) =>
        {
            bool dense = ActualHeight < 205;
            bool tight = ActualHeight < 135;
            _frame.Padding = tight ? new Thickness(7, 5, 7, 5) : dense ? new Thickness(10, _skin.Family == "relic" ? 15 : 8, 10, _skin.Family == "relic" ? 15 : 8) : normalPadding;
            _frame.Margin = tight && ink ? new Thickness(4, 3, 4, 3) : normalFrameMargin;
            preview.Margin = tight ? new Thickness(0, 4, 0, 4) : dense ? new Thickness(0, 6, 0, 6) : normalPreviewMargin;
            number.Height = tight ? 22 : 28;
            _name.FontSize = tight ? 11 : dense ? 12 : normalNameSize; _metadata.FontSize = dense ? 9 : 10;
            _metadata.Visibility = tight ? Visibility.Collapsed : Visibility.Visible;
            _metadata.Margin = new Thickness(0, dense ? 2 : 4, 0, 0);
            if (_unitBanner != null) _unitBanner.Padding = dense ? new Thickness(6, 4, 6, 4) : new Thickness(8, 6, 8, 6);
            UpdateClip();
        };
        if (animate)
        {
            Loaded += (_, _) =>
            {
                var delay = TimeSpan.FromMilliseconds((slot.Number - 1) * 28);
                BeginAnimation(OpacityProperty, new DoubleAnimation(.15, 1, TimeSpan.FromMilliseconds(260)) { BeginTime = delay, FillBehavior = FillBehavior.Stop });
                _translation.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(_skin.Family == "tactical" ? 10 : 23, 0, TimeSpan.FromMilliseconds(340)) { BeginTime = delay, FillBehavior = FillBehavior.Stop, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
            };
        }
        MouseEnter += (_, _) => Hover(true); MouseLeave += (_, _) => Hover(false);
        Unloaded += (_, _) => StopAnimations();
    }
    private void UpdateClip()
    {
        if (_skin.Family != "protocol") return;
        double w = ActualWidth, h = ActualHeight, cut = Math.Min(18, h / 6);
        if (w <= 1 || h <= 1) return;
        _frame.Clip = Geometry.Parse(FormattableString.Invariant($"M0,0 L{w-cut},0 L{w},{cut} L{w},{h} L{cut},{h} L0,{h-cut} Z"));
    }
    private void Hover(bool over)
    {
        Panel.SetZIndex(this, over ? 10 : 0);
        if (!_animate) return;
        double target = over ? 1.025 : 1;
        foreach (var property in new[] { ScaleTransform.ScaleXProperty, ScaleTransform.ScaleYProperty }) _scale.BeginAnimation(property, new DoubleAnimation(target, TimeSpan.FromMilliseconds(150)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
    }
    public void Update(bool selected)
    {
        string statusColor = SkinUi.StateColor(_slot, _skin);
        var status = WuxiaTheme.Brush(statusColor);
        _state.Text = SkinUi.StateSymbol(_slot) + "  " + (_slot.Occupied ? _slot.StateLabel : "空槽位 · 等待接入");
        // Pale cards use their own dark text; status color remains visible as an adjacent line and icon.
        _state.Foreground = WuxiaTheme.Brush(_skin.CardText);
        _frame.BorderBrush = WuxiaTheme.Brush(selected || _slot.IsDropTarget ? _skin.Accent : _slot.Connected ? statusColor : _skin.Border);
        _frame.BorderThickness = new Thickness(selected || _slot.IsDropTarget ? 2 : 1);
        _frame.Background = _cardSurface;
        _name.Text = _slot.Occupied ? _slot.DisplayName : "槽位 " + _slot.Number + " · 添加窗口";
        _metadata.Text = !_slot.Occupied ? "拖入窗口，或点击选择已有窗口" : !_slot.Connected ? "上次：" + SkinUi.ExecutionLabel(_slot.State) + " · 点击重连" : _slot.State == AgentState.Waiting ? "需要你处理 · 进入终端查看" : _slot.State == AgentState.Ready ? "仅本轮回复完成 · 任务可继续" : (_slot.ProjectLabel == "" ? _slot.ToolName : _slot.ProjectLabel) + (_slot.IntegrationConnected ? " · 状态已接入" : " · 自动状态未接入");
        var flags = new System.Collections.Generic.List<string>();
        if (selected) flags.Add("◆ 已选"); if (_slot.IsActive) flags.Add("● 当前"); if (_slot.Unread) flags.Add("✉ 未读");
        string tag = string.Join("\n", flags);
        _badge.Text = tag; _badge.Foreground = WuxiaTheme.Brush(_skin.Background); _badgeFrame.Background = WuxiaTheme.Brush(_skin.Accent); _badgeFrame.Visibility = tag == "" ? Visibility.Collapsed : Visibility.Visible;
        _placeholder.Text = !_slot.Occupied ? "+" : !_slot.Connected ? "⌁ 连接已断开" : _slot.State switch { AgentState.Waiting => "! 等待你处理", AgentState.Ready => "✓ 本轮已回复", AgentState.Error => "× 发生错误", AgentState.Running => "▷ 正在执行", _ => "○ 状态未知" };
        _placeholder.Foreground = status;
        _previewHint.Text = !_slot.Occupied ? "点击添加 · 保留固定编号" : !_slot.Connected ? "点击重新连接窗口" : "实时窗口预览";
        _ornament.StateColor = statusColor; _ornament.Selected = selected; _ornament.InvalidateVisual();
        var key = _slot.State + ":" + _slot.Connected + ":" + _slot.Occupied;
        if (key == _lastState) return;
        _lastState = key;
        _frame.BeginAnimation(OpacityProperty, null);
        if (_animate && _slot.Connected && _slot.State == AgentState.Waiting)
        {
            _badgeFrame.BeginAnimation(OpacityProperty, new DoubleAnimation(.58, 1, TimeSpan.FromSeconds(.8)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
            _ornament.BeginAnimation(OpacityProperty, new DoubleAnimation(.45, 1, TimeSpan.FromSeconds(.8)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
        }
        else { _badgeFrame.BeginAnimation(OpacityProperty, null); _ornament.BeginAnimation(OpacityProperty, null); }
        if (_animate && _slot.Connected && _slot.State == AgentState.Error)
        {
            var shake = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(300), FillBehavior = FillBehavior.Stop };
            foreach (var frame in new[] { (0, 0d), (40, -3d), (85, 2d), (140, -1d), (230, 1d), (300, 0d) }) shake.KeyFrames.Add(new LinearDoubleKeyFrame(frame.Item2, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(frame.Item1))));
            _translation.BeginAnimation(TranslateTransform.XProperty, shake);
        }
    }
    public void StopAnimations()
    {
        BeginAnimation(OpacityProperty, null); _badgeFrame.BeginAnimation(OpacityProperty, null); _frame.BeginAnimation(OpacityProperty, null); _ornament.BeginAnimation(OpacityProperty, null);
        _scale.BeginAnimation(ScaleTransform.ScaleXProperty, null); _scale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
        _translation.BeginAnimation(TranslateTransform.XProperty, null); _translation.BeginAnimation(TranslateTransform.YProperty, null);
    }
    internal static FrameworkElement NumberPlaque(int n, SkinDefinition skin, double size)
    {
        double radius = skin.Family switch { "fantasy" or "mechanical" => size / 2, "formation" or "wonderland" => 9, _ => 1 };
        var border = new Border { Width = size + (skin.Family == "tactical" ? 8 : 0), Height = size, BorderBrush = WuxiaTheme.Brush(skin.Accent), Background = WuxiaTheme.Brush(skin.Background), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(radius) };
        border.Child = new TextBlock { Text = skin.SlotNumber(n), FontFamily = skin.TitleFont, FontSize = size * .51, FontWeight = FontWeights.SemiBold, Foreground = WuxiaTheme.Brush(skin.Accent), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        if (skin.Family == "protocol") border.BorderThickness = new Thickness(3, 0, 0, 0);
        return border;
    }
}

internal static class SkinUi
{
    internal static string ExecutionLabel(AgentState state) => state switch { AgentState.Running => "正在执行", AgentState.Waiting => "等待你处理", AgentState.Ready => "本轮已回复", AgentState.Error => "发生错误", _ => "状态未知" };
    internal static string StateColor(Slot slot, SkinDefinition skin) => !slot.Connected ? skin.Unknown : slot.State switch { AgentState.Running => skin.Running, AgentState.Waiting => skin.Waiting, AgentState.Ready => skin.Ready, AgentState.Error => skin.Error, _ => skin.Unknown };
    internal static string StateSymbol(Slot slot) => !slot.Occupied ? "+" : !slot.Connected ? "⌁" : slot.State switch { AgentState.Running => "▷", AgentState.Waiting => "!", AgentState.Ready => "✓", AgentState.Error => "×", _ => "○" };
}

/// <summary>Procedural, original structural ornaments. No game artwork or copied symbols.</summary>
internal sealed class SkinCardOrnament : FrameworkElement
{
    private readonly SkinDefinition _skin;
    private readonly bool _compact;
    public string StateColor { get; set; }
    public bool Selected { get; set; }
    public SkinCardOrnament(SkinDefinition skin, bool compact) { _skin = skin; _compact = compact; StateColor = skin.Accent; IsHitTestVisible = false; }
    protected override void OnRender(DrawingContext dc)
    {
        double w = ActualWidth, h = ActualHeight; if (w < 20 || h < 20) return;
        var accent = WuxiaTheme.Brush(Selected ? _skin.Accent : StateColor); var edge = new Pen(WuxiaTheme.Brush(_skin.Border), 1); var line = new Pen(accent, 1.4);
        // A persistent status rail remains when decorative content is disabled.
        dc.DrawRoundedRectangle(accent, null, new Rect(1, 12, 3, Math.Max(1, h - 24)), 1, 1);
        if (!SkinCatalog.DecorationsEnabled || (!_compact && h < 135)) return;
        switch (_skin.Family)
        {
            case "tactical":
                for (int i = 0; i < (_compact ? 5 : 12); i++) { double x = w - 12 - i * 5; dc.DrawLine(edge, new Point(x, 3), new Point(x, i % 3 == 0 ? 9 : 6)); }
                foreach (var p in new[] { new Point(6, 6), new Point(w - 6, h - 6) }) { dc.DrawLine(line, p, new Point(p.X + (p.X < w / 2 ? 12 : -12), p.Y)); dc.DrawLine(line, p, new Point(p.X, p.Y + (p.Y < h / 2 ? 12 : -12))); }
                break;
            case "protocol":
                dc.DrawGeometry(accent, null, Geometry.Parse(FormattableString.Invariant($"M{w-22},0 L{w},22 L{w},0 Z")));
                dc.DrawLine(line, new Point(10, h - 5), new Point(Math.Min(72, w - 10), h - 5)); break;
            case "equipment":
                foreach (double x in new[] { 5d, w - 5 }) foreach (double y in new[] { 7d, h - 7 }) { dc.DrawEllipse(WuxiaTheme.Brush(_skin.Border), new Pen(WuxiaTheme.Brush(_skin.Secondary), .7), new Point(x, y), 2.4, 2.4); }
                dc.DrawLine(edge, new Point(10, h - 5), new Point(w - 10, h - 5)); break;
            case "arsenal":
                foreach (double y in new[] { 4d, h - 4 }) { dc.DrawRectangle(WuxiaTheme.Brush(_skin.Border), null, new Rect(7, y, w - 14, 2)); dc.DrawRectangle(accent, null, new Rect(w / 2 - 11, y - 2, 22, 5)); }
                dc.DrawLine(new Pen(accent, .7), new Point(w - 7, 18), new Point(w - 7, h - 18)); break;
            case "relic":
                var arch = new StreamGeometry(); using (var p = arch.Open()) { p.BeginFigure(new Point(7, 25), false, false); p.BezierTo(new Point(7, 2), new Point(w - 7, 2), new Point(w - 7, 25), true, false); } dc.DrawGeometry(null, edge, arch);
                for (int i = 0; i < 3; i++) dc.DrawLine(edge, new Point(5 + i * 3, h - 5 - i * 3), new Point(w - 5 - i * 3, h - 5 - i * 3)); break;
            case "fantasy":
                foreach (double x in new[] { 6d, w - 6 }) { var diamond = new StreamGeometry(); using (var p = diamond.Open()) { p.BeginFigure(new Point(x, h / 2 - 8), true, true); p.PolyLineTo(new[] { new Point(x + 4, h / 2), new Point(x, h / 2 + 8), new Point(x - 4, h / 2) }, true, false); } dc.DrawGeometry(accent, null, diamond); }
                dc.DrawLine(edge, new Point(w / 2 - 20, h - 4), new Point(w / 2 + 20, h - 4)); break;
            case "formation":
                for (int i = 0; i < 3; i++) dc.DrawEllipse(i == 1 ? accent : WuxiaTheme.Brush(_skin.Border), null, new Point(w / 2 - 8 + i * 8, h - 4), 1.8, 1.8);
                break;
            case "astral":
                foreach (var p in new[] { new Point(6, 9), new Point(w - 6, h - 9) }) { dc.DrawLine(line, new Point(p.X - 3, p.Y), new Point(p.X + 3, p.Y)); dc.DrawLine(line, new Point(p.X, p.Y - 3), new Point(p.X, p.Y + 3)); }
                dc.DrawLine(new Pen(accent, .6), new Point(w - 7, 22), new Point(w - 7, h - 22)); break;
            case "wonderland":
                foreach (double x in new[] { 10d, w - 10 }) { dc.DrawEllipse(WuxiaTheme.Brush(_skin.Secondary), null, new Point(x, 6), 5, 3); dc.DrawEllipse(accent, null, new Point(x + 4, 5), 4, 3); }
                break;
            case "mechanical":
                foreach (double x in new[] { 7d, w - 7 }) foreach (double y in new[] { 7d, h - 7 }) dc.DrawEllipse(WuxiaTheme.Brush(_skin.Background), line, new Point(x, y), 3, 3);
                dc.DrawLine(edge, new Point(15, 4), new Point(w - 15, 4)); break;
        }
    }
}

/// <summary>Dock text is rebuilt on theme changes, and unsubscribes whenever recycled.</summary>
public sealed class SkinDockContent : ContentControl
{
    private Slot? _slot;
    private readonly SkinDefinition _skin;
    private readonly TextBlock _name, _detail, _activity;
    private readonly SkinCardOrnament _ornament;
    private readonly Grid _root;
    private Border? _tagMarker;
    public SkinDockContent()
    {
        _skin = SkinCatalog.Current; IsHitTestVisible = false;
        _root = new Grid(); _root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); _root.ColumnDefinitions.Add(new ColumnDefinition());
        _ornament = new SkinCardOrnament(_skin, compact: true) { Margin = new Thickness(-7, -6, -6, -6) }; Grid.SetColumnSpan(_ornament, 2); _root.Children.Add(_ornament);
        var text = new StackPanel { Margin = new Thickness(8, 0, 2, 0), VerticalAlignment = VerticalAlignment.Center };
        _name = new TextBlock { FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = WuxiaTheme.Brush(_skin.Text), TextTrimming = TextTrimming.CharacterEllipsis };
        _detail = new TextBlock { FontSize = 10, Margin = new Thickness(0, 4, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis };
        _activity = new TextBlock { FontSize = 9, Margin = new Thickness(0, 3, 0, 0), Foreground = WuxiaTheme.Brush(_skin.Accent), TextTrimming = TextTrimming.CharacterEllipsis };
        text.Children.Add(_name); text.Children.Add(_detail); text.Children.Add(_activity); Grid.SetColumn(text, 1); _root.Children.Add(text); Content = _root;
        Loaded += (_, _) => Attach(); Unloaded += (_, _) => Detach(); DataContextChanged += (_, _) => { if (IsLoaded) Attach(); };
    }
    private void Attach()
    {
        Detach(); _slot = DataContext as Slot; if (_slot == null) return;
        // The host retains its original drag/click events; only its geometry changes.
        DependencyObject? parent = VisualTreeHelper.GetParent(this);
        while (parent != null && parent is not Border) parent = VisualTreeHelper.GetParent(parent);
        if (parent is Border frame) frame.CornerRadius = new CornerRadius(_skin.CornerRadius);
        var numberHost = new Grid { Width = _skin.Family == "tactical" ? 33 : 26 };
        numberHost.Children.Add(SkinTaskCard.NumberPlaque(_slot.Number, _skin, 25));
        _tagMarker = new Border { Height = 2, Width = 17, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, -3), CornerRadius = new CornerRadius(1) };
        numberHost.Children.Add(_tagMarker); _root.Children.Add(numberHost); _slot.PropertyChanged += Changed; Update();
    }
    private void Detach() { if (_slot != null) _slot.PropertyChanged -= Changed; _slot = null; _tagMarker = null; if (_root.Children.Count > 2) _root.Children.RemoveAt(_root.Children.Count - 1); }
    private void Changed(object? sender, PropertyChangedEventArgs e) => Update();
    private void Update()
    {
        if (_slot == null) return;
        _name.Text = _slot.DisplayName;
        if (_tagMarker != null)
        {
            try { _tagMarker.Background = WuxiaTheme.Brush(string.IsNullOrWhiteSpace(_slot.TagColor) ? _skin.Muted : _slot.TagColor); }
            catch (Exception ex) when (ex is FormatException or NotSupportedException) { _tagMarker.Background = WuxiaTheme.Brush(_skin.Muted); }
            _tagMarker.Visibility = _slot.Occupied ? Visibility.Visible : Visibility.Collapsed;
        }
        _detail.Text = SkinUi.StateSymbol(_slot) + " " + _slot.StateLabel;
        _detail.Foreground = WuxiaTheme.Brush(SkinUi.StateColor(_slot, _skin));
        _activity.Text = (_slot.IsSelected ? "◆ 已选择  " : _slot.IsActive ? "● 当前窗口  " : "") + (_slot.Unread ? "✉ 未读" : "");
        _activity.Visibility = _activity.Text == "" ? Visibility.Collapsed : Visibility.Visible;
        _ornament.StateColor = SkinUi.StateColor(_slot, _skin); _ornament.Selected = _slot.IsSelected; _ornament.InvalidateVisual();
    }
}
