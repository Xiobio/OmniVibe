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
    private readonly Button _remove;
    public event Action? RemoveRequested;
    private Image? _weaponImage;
    private readonly Image _previewEntity;
    private readonly StackPanel _previewMessage;
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
        {
            var emblem = new StackPanel { Orientation = Orientation.Horizontal };
            top.Children.Remove(number); emblem.Children.Add(number);
            _weaponImage = new Image { Source = slot.Occupied ? EquipmentCatalog.Image(slot, _skin.Id) : ThemeIdentityArt.Image(_skin.Id), Width = 27, Height = 28, Stretch = Stretch.Uniform, Margin = new Thickness(7, 0, 1, 0), ToolTip = slot.Occupied ? EquipmentCatalog.Name(slot, _skin.Id) : ThemeIdentityArt.Name(_skin.Id) };
            emblem.Children.Add(_weaponImage); top.Children.Add(emblem);
        }
        var stateGroup = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(9, 0, 4, 0) };
        if (_skin.Family is "tactical" or "protocol") stateGroup.Children.Add(new TextBlock { Text = _skin.Family == "tactical" ? "DEVICE // " + slot.Number.ToString("00") : "AGENT / " + slot.Number.ToString("00"), FontSize = 8, Foreground = WuxiaTheme.Brush(_skin.Muted) });
        _state = new TextBlock { FontFamily = WuxiaTheme.BodyFont, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis, FontWeight = FontWeights.SemiBold };
        stateGroup.Children.Add(_state); Grid.SetColumn(stateGroup, 1); top.Children.Add(stateGroup);
        _badge = new TextBlock { FontSize = 8.5, FontWeight = FontWeights.Bold, TextAlignment = TextAlignment.Center };
        _badgeFrame = new Border { Padding = new Thickness(5, 3, 5, 3), CornerRadius = new CornerRadius(Math.Min(8, _skin.CornerRadius)), Child = _badge, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(_badgeFrame, 2); top.Children.Add(_badgeFrame); body.Children.Add(top);
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _remove = new Button { Width = 22, Height = 22, MinWidth = 0, MinHeight = 0, Padding = new Thickness(0), Margin = new Thickness(5, 0, 0, 0), ToolTip = L.T("移出管理，保留终端窗口"), Foreground = WuxiaTheme.Brush(_skin.CardText), VerticalAlignment = VerticalAlignment.Center };
        _remove.Template = (ControlTemplate)System.Windows.Markup.XamlReader.Parse("""
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:local="clr-namespace:CodeManager;assembly=CodeManager" TargetType="Button">
  <Grid Background="Transparent">
    <Border x:Name="Wash" Background="{TemplateBinding Foreground}" CornerRadius="11" Opacity="0"/>
    <Path x:Name="Mark" Data="M 8,8 L 14,14 M 14,8 L 8,14" Stroke="{TemplateBinding Foreground}" StrokeThickness="1.1" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Opacity="0.28"/>
  </Grid>
  <ControlTemplate.Triggers>
    <DataTrigger Binding="{Binding IsMouseOver, RelativeSource={RelativeSource AncestorType={x:Type local:SkinTaskCard}}}" Value="True">
      <Setter TargetName="Mark" Property="Opacity" Value="0.65"/>
    </DataTrigger>
    <Trigger Property="IsMouseOver" Value="True">
      <Setter TargetName="Mark" Property="Opacity" Value="1"/>
      <Setter TargetName="Wash" Property="Opacity" Value="0.10"/>
    </Trigger>
    <Trigger Property="IsKeyboardFocused" Value="True">
      <Setter TargetName="Mark" Property="Opacity" Value="1"/>
      <Setter TargetName="Wash" Property="Opacity" Value="0.14"/>
    </Trigger>
    <Trigger Property="IsPressed" Value="True">
      <Setter TargetName="Wash" Property="Opacity" Value="0.20"/>
    </Trigger>
  </ControlTemplate.Triggers>
</ControlTemplate>
""");
        Grid.SetColumn(_remove, 3); top.Children.Add(_remove);
        _remove.Click += (_, e) => { e.Handled = true; RemoveRequested?.Invoke(); };

        var preview = new Border { Background = WuxiaTheme.Brush(_skin.Background), BorderBrush = WuxiaTheme.Brush(_skin.Border), BorderThickness = new Thickness(.5), Margin = new Thickness(0, 9, 0, 8), ClipToBounds = true, CornerRadius = new CornerRadius(Math.Min(_skin.CornerRadius, 6)) };
        var placeholder = new Grid { ClipToBounds = true };
        placeholder.Children.Add(new NativeCardScene(_skin));
        if (SkinCatalog.DecorationsEnabled) placeholder.Children.Add(new SkinGlyph(animate) { Width = 90, Height = 90, Opacity = .22, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        _previewEntity = new Image { Stretch = Stretch.Uniform, Opacity = .72, IsHitTestVisible = false };
        // An overlay must not contribute a desired height inside the short-screen ScrollViewer.
        // Deriving a normal Grid child's height from its parent's actual height creates layout feedback.
        var entityLayer = new Canvas { IsHitTestVisible = false, ClipToBounds = true };
        entityLayer.Children.Add(_previewEntity); placeholder.Children.Add(entityLayer);
        var message = _previewMessage = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8) };
        _placeholder = new TextBlock { FontSize = 17, FontFamily = WuxiaTheme.BodyFont, FontWeight = FontWeights.SemiBold, TextAlignment = TextAlignment.Center, Foreground = WuxiaTheme.Brush(_skin.Accent) };
        _previewHint = new TextBlock { FontSize = 10, TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 5, 0, 0), Foreground = WuxiaTheme.Brush(_skin.Muted) };
        message.Children.Add(_placeholder); message.Children.Add(_previewHint); placeholder.Children.Add(message); preview.Child = placeholder;
        PreviewRegion = preview; Grid.SetRow(preview, 1); body.Children.Add(preview);
        preview.SizeChanged += (_, e) =>
        {
            UpdatePreviewEntity(e.NewSize.Width, e.NewSize.Height);
            _placeholder.FontSize = e.NewSize.Height < 60 ? 12 : e.NewSize.Width < 180 ? 14 : 17;
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
            if (_weaponImage != null) { ((Panel)_weaponImage.Parent).Children.Remove(_weaponImage); _weaponImage.Margin = new Thickness(0, 5, 0, 0); rail.Children.Add(_weaponImage); }
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
            if (_weaponImage != null) _weaponImage.Height = tight ? 22 : 28;
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
        _remove.Visibility = _slot.Occupied ? Visibility.Visible : Visibility.Collapsed;
        _previewEntity.Source = _slot.Occupied ? EquipmentCatalog.Image(_slot, _skin.Id) : ThemeIdentityArt.Image(_skin.Id);
        UpdatePreviewEntity(PreviewRegion.ActualWidth, PreviewRegion.ActualHeight);
        if (_weaponImage != null) { _weaponImage.Source = _slot.Occupied ? EquipmentCatalog.Image(_slot, _skin.Id) : ThemeIdentityArt.Image(_skin.Id); _weaponImage.ToolTip = _slot.Occupied ? EquipmentCatalog.Name(_slot, _skin.Id) : ThemeIdentityArt.Name(_skin.Id); _weaponImage.Visibility = Visibility.Visible; ToolTip = _slot.Occupied ? EquipmentCatalog.Detail(_slot) : ThemeIdentityArt.Name(_skin.Id) + L.T(" · 空槽位\n拖入窗口，或点击选择已有窗口"); }
        string statusColor = SkinUi.StateColor(_slot, _skin);
        var status = WuxiaTheme.Brush(statusColor);
        _state.Text = SkinUi.StateSymbol(_slot) + "  " + (_slot.Occupied ? _slot.StateLabel : L.T("空槽位 · 等待接入"));
        // Pale cards use their own dark text; status color remains visible as an adjacent line and icon.
        _state.Foreground = WuxiaTheme.Brush(_skin.CardText);
        _frame.BorderBrush = WuxiaTheme.Brush(selected || _slot.IsDropTarget ? _skin.Accent : _slot.Connected ? statusColor : _skin.Border);
        _frame.BorderThickness = new Thickness(selected || _slot.IsDropTarget ? 2 : 1);
        _frame.Background = _cardSurface;
        _name.Text = _slot.Occupied ? _slot.DisplayName : L.T("槽位 ") + _slot.Number + L.T(" · 添加窗口");
        _metadata.Text = !_slot.Occupied ? L.T("拖入窗口，或点击选择已有窗口") : !_slot.Connected ? L.T("上次：") + SkinUi.ExecutionLabel(_slot.State) + L.T(" · 点击重连") : _slot.State == AgentState.Waiting ? L.T("需要你处理 · 进入终端查看") : _slot.State == AgentState.Ready ? L.T("仅本轮回复完成 · 任务可继续") : (_slot.ProjectLabel == "" ? _slot.ToolName : _slot.ProjectLabel) + (_slot.IntegrationConnected ? L.T(" · 状态已接入") : L.T(" · 自动状态未接入"));
        var flags = new System.Collections.Generic.List<string>();
        if (selected) flags.Add(L.T("◆ 已选")); if (_slot.IsActive) flags.Add(L.T("● 当前")); if (_slot.Unread) flags.Add(L.T("✉ 未读"));
        string tag = string.Join("\n", flags);
        _badge.Text = tag; _badge.Foreground = WuxiaTheme.Brush(_skin.Background); _badgeFrame.Background = WuxiaTheme.Brush(_skin.Accent); _badgeFrame.Visibility = tag == "" ? Visibility.Collapsed : Visibility.Visible;
        _placeholder.Text = !_slot.Occupied ? "+" : !_slot.Connected ? L.T("⌁ 连接已断开") : _slot.State switch { AgentState.Waiting => L.T("! 等待你处理"), AgentState.Ready => L.T("✓ 本轮已回复"), AgentState.Error => L.T("× 发生错误"), AgentState.Running => L.T("▷ 正在执行"), _ => L.T("○ 状态未知") };
        _placeholder.Foreground = status;
        _previewHint.Text = !_slot.Occupied ? L.T("点击添加 · 保留固定编号") : !_slot.Connected ? L.T("点击重新连接窗口") : L.T("实时窗口预览");
        _ornament.StateColor = statusColor; _ornament.Selected = selected; _ornament.IsEmpty = !_slot.Occupied; _ornament.InvalidateVisual();
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
    private void UpdatePreviewEntity(double width, double height)
    {
        if (!_slot.Occupied && _previewEntity.Source != null) {
            _previewEntity.Visibility = height >= 30 && width >= 50 ? Visibility.Visible : Visibility.Collapsed;
            _previewEntity.Width = Math.Max(1, Math.Min(320, width - 20)); _previewEntity.Height = Math.Max(1, height - 12);
            Canvas.SetLeft(_previewEntity, (width - _previewEntity.Width) / 2); Canvas.SetTop(_previewEntity, 6);
            _previewEntity.Opacity = 1; _previewMessage.Visibility = Visibility.Collapsed;
            return;
        }
        _previewEntity.Opacity = .72; _previewMessage.Visibility = Visibility.Visible;
        bool visible = _slot.Occupied && height >= 80 && width >= 180;
        _previewEntity.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        _previewEntity.Width = Math.Max(1, width * .35); _previewEntity.Height = Math.Max(1, height - 8);
        Canvas.SetLeft(_previewEntity, Math.Max(0, width * .65 - 4)); Canvas.SetTop(_previewEntity, 4);
        _previewMessage.HorizontalAlignment = visible ? HorizontalAlignment.Left : HorizontalAlignment.Center;
        double messageWidth = Math.Max(40, width * (visible ? .6 : 1) - 16);
        _placeholder.MaxWidth = messageWidth; _previewHint.MaxWidth = messageWidth;
    }
    internal static FrameworkElement NumberPlaque(int n, SkinDefinition skin, double size)
    {
        if (NativeSkinArt.Available(skin)) return new NativeNumberPlaque(n, skin) { Width = size + 6, Height = size + 6, VerticalAlignment = VerticalAlignment.Center };
        double radius = skin.Family switch { "fantasy" or "mechanical" => size / 2, "formation" or "wonderland" => 9, _ => 1 };
        var border = new Border { Width = size + (skin.Family == "tactical" ? 8 : 0), Height = size, BorderBrush = WuxiaTheme.Brush(skin.Accent), Background = WuxiaTheme.Brush(skin.Background), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(radius) };
        border.Child = new TextBlock { Text = skin.SlotNumber(n), FontFamily = skin.TitleFont, FontSize = size * .51, FontWeight = FontWeights.SemiBold, Foreground = WuxiaTheme.Brush(skin.Accent), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        if (skin.Family == "protocol") border.BorderThickness = new Thickness(3, 0, 0, 0);
        return border;
    }
}

internal static class SkinUi
{
    internal static string ExecutionLabel(AgentState state) => state switch { AgentState.Running => L.T("正在执行"), AgentState.Waiting => L.T("等待你处理"), AgentState.Ready => L.T("本轮已回复"), AgentState.Error => L.T("发生错误"), _ => L.T("状态未知") };
    internal static string StateColor(Slot slot, SkinDefinition skin) => !slot.Connected || slot.StatusMayBeStale ? skin.Unknown : slot.State switch { AgentState.Running => skin.Running, AgentState.Waiting => skin.Waiting, AgentState.Ready => skin.Ready, AgentState.Error => skin.Error, _ => skin.Unknown };
    internal static string StateSymbol(Slot slot) => !slot.Occupied ? "+" : !slot.Connected ? "⌁" : slot.State switch { AgentState.Running => "▷", AgentState.Waiting => "!", AgentState.Ready => "✓", AgentState.Error => "×", _ => "○" };
}

/// <summary>Procedural, original structural ornaments. No game artwork or copied symbols.</summary>
internal sealed class SkinCardOrnament : FrameworkElement
{
    private readonly SkinDefinition _skin;
    private readonly bool _compact;
    public string StateColor { get; set; }
    public bool Selected { get; set; }
    public bool IsEmpty { get; set; }
    public SkinCardOrnament(SkinDefinition skin, bool compact) { _skin = skin; _compact = compact; StateColor = skin.Accent; IsHitTestVisible = false; NativeSkinArt.Warm(skin); }
    protected override void OnRender(DrawingContext dc)
    {
        double w = ActualWidth, h = ActualHeight; if (w < 20 || h < 20) return;
        var accent = WuxiaTheme.Brush(Selected ? _skin.Accent : StateColor); var edge = new Pen(WuxiaTheme.Brush(_skin.Border), 1); var line = new Pen(accent, 1.4);
        if (SkinCatalog.DecorationsEnabled && NativeSkinArt.Available(_skin))
        {
            if (IsEmpty) dc.PushOpacity(.38);
            NativeSkinArt.Frame(dc, _skin, new Rect(0, 0, w, h), h < 135 ? 12 : h < 205 ? 20 : 26);
            if (IsEmpty) dc.Pop();
            if (!IsEmpty) dc.DrawRoundedRectangle(accent, null, new Rect(2, 16, 2, Math.Max(1, h - 32)), 1, 1);
            return;
        }
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
