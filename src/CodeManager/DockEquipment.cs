using System;
using System.ComponentModel;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace CodeManager;

/// <summary>Fixed equipment holsters: the active task gains emphasis without moving its slot.</summary>
public sealed class SkinDockContent : Grid
{
    private Slot? _slot;
    private readonly SkinDefinition _skin = SkinCatalog.Current;
    private readonly DockEquipmentSurface _surface;
    private readonly TextBlock _number, _provider, _name, _state, _badge, _binding;
    private readonly Image _equipment;
    private readonly StackPanel _body;
    private readonly Grid _layout;
    private Window? _owner;

    public SkinDockContent()
    {
        IsHitTestVisible = false;
        MinHeight = 64;
        _surface = new DockEquipmentSurface(_skin);
        Children.Add(_surface);
        var layout = _layout = new Grid { Margin = new Thickness(12, 10, 14, 10) };
        layout.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(44) });
        layout.ColumnDefinitions.Add(new ColumnDefinition());
        _equipment = new Image { Width = 43, Height = 62, Stretch = Stretch.Uniform, VerticalAlignment = VerticalAlignment.Center };
        layout.Children.Add(_equipment);
        _number = Label("01", 31, _skin.Muted);
        _number.FontFamily = new FontFamily("Bahnschrift, Consolas");
        _number.FontWeight = FontWeights.SemiBold;
        _number.VerticalAlignment = VerticalAlignment.Top;
        layout.Children.Add(_number);
        _binding = Label("ALT", 7, _skin.Muted);
        _binding.VerticalAlignment = VerticalAlignment.Bottom;
        _binding.Margin = new Thickness(1, 0, 0, -2);
        layout.Children.Add(_binding);
        _body = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0) };
        Grid.SetColumn(_body, 1);
        var meta = new Grid();
        meta.ColumnDefinitions.Add(new ColumnDefinition());
        meta.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _provider = Label("TERMINAL", 8, _skin.Muted);
        _badge = Label("", 8, _skin.Accent);
        _badge.FontWeight = FontWeights.SemiBold;
        Grid.SetColumn(_badge, 1);
        meta.Children.Add(_provider); meta.Children.Add(_badge);
        _name = Label("", 12, _skin.Text);
        _name.FontFamily = new FontFamily("Microsoft YaHei UI, Segoe UI");
        _name.FontWeight = FontWeights.SemiBold;
        _name.Margin = new Thickness(0, 5, 0, 0);
        _state = Label("", 9, _skin.Muted);
        _state.Margin = new Thickness(0, 5, 0, 0);
        _body.Children.Add(meta); _body.Children.Add(_name); _body.Children.Add(_state);
        layout.Children.Add(_body); Children.Add(layout);
        Loaded += (_, _) => Attach();
        Unloaded += (_, _) => Detach();
        DataContextChanged += (_, _) => { if (IsLoaded) Attach(); };
    }

    private static TextBlock Label(string text, double size, string color) => new()
    {
        Text = text, FontSize = size, Foreground = WuxiaTheme.Brush(color),
        TextTrimming = TextTrimming.CharacterEllipsis,
        FontFamily = new FontFamily("Bahnschrift, Microsoft YaHei UI, Segoe UI")
    };

    private void Attach()
    {
        Detach(); _slot = DataContext as Slot;
        if (_slot == null) return;
        _slot.PropertyChanged += Changed;
        _owner = Window.GetWindow(this);
        if (_owner != null) _owner.SizeChanged += OwnerSizeChanged;
        Update();
    }
    private void Detach() { if (_slot != null) _slot.PropertyChanged -= Changed; if (_owner != null) _owner.SizeChanged -= OwnerSizeChanged; _owner = null; _slot = null; }
    private void OwnerSizeChanged(object sender, SizeChangedEventArgs e) { if (e.HeightChanged) Update(); }
    private void Changed(object? sender, PropertyChangedEventArgs e) => Update();
    private void Update()
    {
        if (_slot == null) return;
        bool equipped = _slot.Occupied && (_slot.IsActive || _slot.IsSelected);
        bool dense = _owner is DockWindow { ActualHeight: > 0 and < 460 };
        MinHeight = !_slot.Occupied ? (dense ? 42 : 46) : equipped ? (dense ? 90 : 106) : dense ? 64 : 76;
        _layout.Margin = new Thickness(12, dense ? 8 : 10, 14, dense ? 8 : 10);
        _number.Text = _slot.Number.ToString("D2", CultureInfo.InvariantCulture);
        _number.FontSize = 9;
        _equipment.Source = _slot.Occupied ? EquipmentCatalog.Image(_slot, _skin.Id) : null;
        _equipment.Visibility = _slot.Occupied ? Visibility.Visible : Visibility.Collapsed;
        _number.Foreground = WuxiaTheme.Brush(equipped ? _skin.Accent : _slot.Occupied ? _skin.Text : _skin.Muted);
        _binding.Text = _slot.Occupied ? "SLOT" : "+";
        _provider.Text = !_slot.Occupied ? "EMPTY SLOT" : _slot.AgentProvider == "claude" ? "CLAUDE CODE" : _slot.AgentProvider == "codex" ? "CODEX" : _slot.ToolName.ToUpperInvariant();
        _badge.Text = _slot.IsDropTarget ? "接入" : _slot.IsSelected ? "切换中" : _slot.IsActive ? "已装备" : _slot.Unread ? "新消息" : "";
        _badge.Margin = new Thickness(4, 0, _slot.Occupied ? 10 : 0, 0);
        _name.Text = _slot.Occupied ? EquipmentCatalog.Name(_slot, _skin.Id) : "拖入窗口，装备任务";
        _name.FontSize = equipped ? (dense ? 13 : 14) : _slot.Occupied ? 12 : 10;
        _name.TextWrapping = equipped ? TextWrapping.Wrap : TextWrapping.NoWrap;
        _name.MaxHeight = equipped ? (dense ? 36 : 42) : 22;
        _name.Margin = new Thickness(0, _slot.Occupied ? 5 : 3, 0, 0);
        _state.Text = SkinUi.StateSymbol(_slot) + "  " + _slot.StateLabel;
        _state.Foreground = WuxiaTheme.Brush(SkinUi.StateColor(_slot, _skin));
        _state.Visibility = _slot.Occupied ? Visibility.Visible : Visibility.Collapsed;
        _body.Margin = new Thickness(4, 0, 0, 0);
        ToolTip = EquipmentCatalog.Detail(_slot);
        _surface.Slot = _slot; _surface.InvalidateVisual();
    }
}

/// <summary>Quiet rack architecture leaves headers, shortcuts and labels unobstructed.</summary>
public sealed class DockEquipmentBackdrop : FrameworkElement
{
    private readonly SkinDefinition _skin = SkinCatalog.Current;
    protected override void OnRender(DrawingContext dc)
    {
        double w = ActualWidth, h = ActualHeight;
        if (w < 10 || h < 10 || !SkinCatalog.DecorationsEnabled) return;
        var s = _skin;
        var shade = new LinearGradientBrush((Color)ColorConverter.ConvertFromString(s.Surface), Colors.Transparent, 90) { Opacity = .45 };
        dc.DrawRectangle(shade, null, new Rect(0, 0, w, Math.Min(130, h)));
        dc.PushOpacity(.16);
        var thin = new Pen(WuxiaTheme.Brush(s.Border), .5);
        dc.DrawLine(thin, new Point(w - 6, 0), new Point(w - 6, h));
        for (double y = 120; y < h - 12; y += 7)
            dc.DrawLine(thin, new Point(w - 9, y), new Point(w - 6, y));
        dc.Pop();
        dc.DrawLine(new Pen(WuxiaTheme.Brush(s.Accent), 1), new Point(0, 0), new Point(26, 0));
        dc.DrawLine(new Pen(WuxiaTheme.Brush(s.Border), .7), new Point(31, 0), new Point(51, 0));
    }
}

/// <summary>A short, click-through equip confirmation; the target window is already active.</summary>
internal sealed class EquipmentSwitchCue : Window
{
    private readonly DispatcherTimer _lifetime;
    public EquipmentSwitchCue(Slot slot, double left, double top)
    {
        Width = 250; Height = 112; Left = left; Top = top;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowActivated = false; ShowInTaskbar = false; Topmost = true;
        AllowsTransparency = true; Background = Brushes.Transparent; IsHitTestVisible = false;
        FrameworkElement content = SkinCatalog.Current.Id == Skin.Hextech ? new HexEquipSignalSurface(slot) : new SkinDockContent { DataContext = slot, MinHeight = 98 };
        Content = content;
        SourceInitialized += (_, _) => Native.Decorate(this, clickThrough: true);
        _lifetime = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(680) };
        _lifetime.Tick += Expire;
        Loaded += (_, _) =>
        {
            var slide = new TranslateTransform(16, 0); content.RenderTransform = slide;
            slide.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(16, 0, TimeSpan.FromMilliseconds(150)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
            BeginAnimation(OpacityProperty, new DoubleAnimationUsingKeyFrames
            {
                KeyFrames = new DoubleKeyFrameCollection
                {
                    new LinearDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.Zero)),
                    new LinearDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(90))),
                    new LinearDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(390))),
                    new LinearDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(650)))
                }
            });
            _lifetime.Start();
        };
        Closed += (_, _) => { _lifetime.Stop(); _lifetime.Tick -= Expire; Content = null; };
    }
    private void Expire(object? sender, EventArgs e) { _lifetime.Stop(); Close(); }
}

/// <summary>Bevels, cut corners and a lit mounting rail replace ordinary bordered list cards.</summary>
internal sealed class DockEquipmentSurface : FrameworkElement
{
    private static readonly Dictionary<string, ImageSource?> ArtworkCache = new();
    private readonly SkinDefinition _skin;
    private readonly ImageSource? _art;
    public Slot? Slot { get; set; }
    public DockEquipmentSurface(SkinDefinition skin)
    {
        _skin = skin; IsHitTestVisible = false;
        NativeSkinArt.Warm(skin);
        string file = Path.Combine(AppContext.BaseDirectory, skin.Artwork);
        if (ArtworkCache.TryGetValue(file, out var cached)) { _art = cached; return; }
        try
        {
            if (File.Exists(file))
            {
                var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.UriSource = new Uri(file); bitmap.DecodePixelWidth = 650; bitmap.EndInit(); bitmap.Freeze(); _art = bitmap;
            }
        }
        catch (Exception ex) when (ex is IOException or NotSupportedException or FileFormatException or ArgumentException) { }
        ArtworkCache[file] = _art;
    }
    protected override void OnRender(DrawingContext dc)
    {
        double w = ActualWidth, h = ActualHeight;
        if (w < 50 || h < 20 || Slot == null) return;
        var s = _skin; var slot = Slot;
        bool active = slot.Occupied && (slot.IsActive || slot.IsSelected);
        var accent = WuxiaTheme.Brush(s.Accent);
        var status = WuxiaTheme.Brush(SkinUi.StateColor(slot, s));
        var edge = WuxiaTheme.Brush(active || slot.IsDropTarget ? s.Accent : s.Border);
        double cut = SkinCatalog.DecorationsEnabled ? 10 : 0;
        var shape = Geometry.Parse(FormattableString.Invariant($"M1,1 H{w-cut-1} L{w-1},{cut+1} V{h-1} H{cut+1} L1,{h-cut-1} Z"));
        var background = new LinearGradientBrush((Color)ColorConverter.ConvertFromString(active ? s.Elevated : s.Surface), (Color)ColorConverter.ConvertFromString(s.Background), 20);
        dc.DrawGeometry(background, new Pen(edge, active ? 1.3 : .7), shape);
        dc.PushClip(shape);
        if (active)
        {
            var glow = new LinearGradientBrush((Color)ColorConverter.ConvertFromString(s.Accent), Colors.Transparent, 0) { Opacity = s.IsLight ? .12 : .15 };
            dc.DrawRectangle(glow, null, new Rect(0, 0, w, h));
            if (SkinCatalog.DecorationsEnabled && _art != null)
            {
                dc.PushOpacity(s.IsLight ? .10 : .18);
                dc.DrawRectangle(new ImageBrush(_art) { Stretch = Stretch.UniformToFill, AlignmentX = AlignmentX.Right }, null, new Rect(w * .45, 0, w * .55, h));
                dc.Pop();
            }
        }
        dc.Pop();
        if (SkinCatalog.DecorationsEnabled) NativeSkinArt.Frame(dc, s, new Rect(0, 0, w, h), 24);
        dc.DrawRectangle(active || slot.IsDropTarget ? accent : status, null, new Rect(0, active ? 14 : 16, active ? 4 : 2, Math.Max(1, h - (active ? 28 : 32))));
        dc.DrawLine(new Pen(WuxiaTheme.Brush(s.Border), .6), new Point(55, 13), new Point(55, h - 13));
        if (!SkinCatalog.DecorationsEnabled) return;
        dc.PushOpacity(active ? .9 : .3);
        dc.DrawLine(new Pen(accent, 1), new Point(10, 1), new Point(active ? w * .65 : 32, 1));
        dc.DrawLine(new Pen(accent, 1), new Point(w - 28, h - 1), new Point(w - 11, h - 1));
        for (int i = 0; i < 3; i++) dc.DrawLine(new Pen(accent, .8), new Point(w - 12 - i * 4, h - 8), new Point(w - 9 - i * 4, h - 12));
        if (active)
        {
            dc.DrawGeometry(accent, null, Geometry.Parse(FormattableString.Invariant($"M{w-29},0 H{w-12} L{w-19},7 H{w-36} Z")));
            dc.DrawEllipse(accent, null, new Point(18, h - 9), 1.6, 1.6);
            dc.DrawLine(new Pen(accent, 1), new Point(24, h - 9), new Point(42, h - 9));
        }
        dc.Pop();
    }
}
