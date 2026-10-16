using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Windows.Data;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace CodeManager;

public sealed class InventoryWindow : Window
{
    private readonly IReadOnlyList<Slot> _slots;
    private readonly Dictionary<int, Border> _cards = new();
    private readonly Dictionary<int, FrameworkElement> _images = new();
    private readonly Dictionary<int, TextBlock> _states = new(), _seals = new(), _messages = new();
    private readonly Dictionary<int, Border> _sealFrames = new();
    private readonly Dictionary<int, InkSplash> _splashes = new();
    private readonly Dictionary<int, IntPtr> _thumbnails = new();
    private readonly Dictionary<int, string> _visualStates = new();
    private readonly WheelSelection _wheel = new();
    private readonly TextBlock _hint;
    private readonly bool _animate;
    private readonly DispatcherTimer _motion;
    private Window? _mask;
    public int? SelectedNumber { get; private set; }
    internal int ThumbnailCount => _thumbnails.Count;
    public event Action<int>? Choose;
    public event Action? Dismiss;

    public InventoryWindow(IReadOnlyList<Slot> slots, Native.Rect area, double scale, int? selected, bool animate, bool duringDrag = false, bool presentationPreview = false)
    {
        _slots = slots.OrderBy(s => s.Number).ToList(); _animate = animate;
        SelectedNumber = _slots.FirstOrDefault(s => s.Number == selected && s.Occupied)?.Number ?? _slots.FirstOrDefault(s => s.Connected)?.Number ?? 1;
        Title = "CodeManager · 九宫百宝囊"; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false; Topmost = true; Background = WuxiaTheme.Ink; ShowActivated = !duringDrag;
        Width = Math.Min(1280, (area.Right - area.Left) / scale - 64);
        Height = Math.Min(960, (area.Bottom - area.Top) / scale - 52);
        Left = (area.Left + (area.Right - area.Left) / 2d) / scale - Width / 2;
        Top = (area.Top + (area.Bottom - area.Top) / 2d) / scale - Height / 2;
        var layers = new Grid { ClipToBounds = true };
        layers.Children.Add(new InkScenery { IsHitTestVisible = false });
        layers.Children.Add(new BaguaGlyph(animate) { Width = 690, Height = 690, Opacity = .045, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        layers.Children.Add(new QiParticles(animate) { IsHitTestVisible = false });
        var root = new Grid { Margin = new Thickness(34, 22, 34, 22) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition());
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var header = new Grid { Margin = new Thickness(0, 0, 0, 22) };
        var title = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        title.Children.Add(new TextBlock { Text = presentationPreview ? "视觉预览 · 示例任务" : "藏 经 阁  ·  万 象 归 藏", FontSize = 10, Foreground = WuxiaTheme.Bronze, HorizontalAlignment = HorizontalAlignment.Center });
        title.Children.Add(new TextBlock { Text = "九 宫 百 宝 囊", FontSize = 43, FontFamily = WuxiaTheme.Calligraphy, Foreground = WuxiaTheme.Ivory, Margin = new Thickness(0, 7, 0, 6), HorizontalAlignment = HorizontalAlignment.Center });
        title.Children.Add(new TextBlock { Text = "滚轮 / 方向键浏览    ·    Enter 进入    ·    数字直达", FontSize = 11, Foreground = WuxiaTheme.Brush("#A6987C"), HorizontalAlignment = HorizontalAlignment.Center });
        header.Children.Add(title);
        var close = new Button { Content = "合卷  ×", ToolTip = "Tab / Esc 关闭", HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Padding = new Thickness(12, 7, 12, 7) };
        close.Click += (_, _) => Dismiss?.Invoke(); header.Children.Add(close); root.Children.Add(header);
        var grid = new UniformGrid { Columns = 3, Rows = 3, Margin = new Thickness(-7) };
        foreach (var slot in _slots) grid.Children.Add(Scroll(slot));
        Grid.SetRow(grid, 1); root.Children.Add(grid);
        _hint = new TextBlock { FontSize = 11, Foreground = WuxiaTheme.Brush("#B9AA8C"), Margin = new Thickness(0, 18, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis, HorizontalAlignment = HorizontalAlignment.Center };
        Grid.SetRow(_hint, 2); root.Children.Add(_hint); layers.Children.Add(root); Content = layers;
        SourceInitialized += (_, _) => Native.Decorate(this, noActivate: duringDrag);
        _motion = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(32) };
        _motion.Tick += (_, _) => PositionThumbnails();
        Loaded += (_, _) =>
        {
            if (!presentationPreview)
            {
            _mask = new Window { WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, AllowsTransparency = true, Background = Brushes.Transparent, ShowActivated = false, ShowInTaskbar = false, Topmost = true, IsHitTestVisible = false, Left = area.Left / scale, Top = area.Top / scale, Width = (area.Right - area.Left) / scale, Height = (area.Bottom - area.Top) / scale };
            var backdrop = new Grid(); backdrop.Children.Add(new InkScenery { Translucent = true });
            backdrop.Children.Add(new BaguaGlyph(animate) { Width = 1050, Height = 1050, Opacity = .07, HorizontalAlignment = HorizontalAlignment.Center });
            _mask.Content = backdrop; _mask.SourceInitialized += (_, _) => Native.Decorate(_mask, clickThrough: true);
            _mask.Show();
            }
            Native.SetWindowPos(new WindowInteropHelper(this).Handle, new IntPtr(-1), 0, 0, 0, 0, 0x13);
            UpdateLayout(); UpdateThumbnails(); if (!duringDrag && !presentationPreview) Focus();
            if (animate) { BeginAnimation(OpacityProperty, new DoubleAnimation(.1, 1, TimeSpan.FromMilliseconds(170))); _mask?.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(170))); _motion.Start(); }
        };
        SizeChanged += (_, _) => { if (IsLoaded) PositionThumbnails(); };
        Closed += (_, _) => { _motion.Stop(); ClearThumbnails(); _mask?.Close(); _mask = null; foreach (var s in _slots) s.PropertyChanged -= SlotChanged; };
        PreviewMouseWheel += (_, e) => { Browse(e.Delta); e.Handled = true; };
        PreviewKeyDown += OnKey;
        foreach (var s in _slots) s.PropertyChanged += SlotChanged;
        RefreshSelection();
    }

    private FrameworkElement Scroll(Slot slot)
    {
        var shell = new Grid { Margin = new Thickness(10, 6, 10, 9), Cursor = Cursors.Hand, DataContext = slot, ToolTip = slot.Tooltip, RenderTransformOrigin = new Point(.5, .5) };
        shell.RowDefinitions.Add(new RowDefinition { Height = new GridLength(10) }); shell.RowDefinitions.Add(new RowDefinition()); shell.RowDefinitions.Add(new RowDefinition { Height = new GridLength(10) });
        var card = new Border { Background = slot.Occupied ? WuxiaTheme.Paper : WuxiaTheme.Brush("#18201B"), BorderBrush = WuxiaTheme.Bronze, BorderThickness = new Thickness(1), Padding = new Thickness(15, 10, 15, 9), CornerRadius = new CornerRadius(1), Margin = new Thickness(5, 0, 5, 0) };
        Grid.SetRow(card, 1); shell.Children.Add(card); _cards[slot.Number] = card;
        if (!slot.Occupied)
        {
            var outline = new System.Windows.Shapes.Rectangle { Stroke = WuxiaTheme.Bronze, StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 5, 5 }, Opacity = .65, Margin = new Thickness(7, 1, 7, 1), IsHitTestVisible = false };
            Grid.SetRow(outline, 1); shell.Children.Add(outline);
        }
        for (int row = 0; row < 3; row += 2)
        {
            var rod = new Border { Background = WuxiaTheme.Wood, BorderBrush = WuxiaTheme.Bronze, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(3), Height = 10 };
            var fittings = new Grid(); fittings.Children.Add(new Border { Width = 12, Background = WuxiaTheme.Bronze, Opacity = .6, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(9, 0, 0, 0) }); fittings.Children.Add(new Border { Width = 12, Background = WuxiaTheme.Bronze, Opacity = .6, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 9, 0) }); rod.Child = fittings;
            Grid.SetRow(rod, row); shell.Children.Add(rod);
        }
        var body = new Grid(); body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); body.RowDefinitions.Add(new RowDefinition()); body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var splash = new InkSplash { Width = 110, Height = 110, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, IsHitTestVisible = false };
        Grid.SetRowSpan(splash, 3); body.Children.Add(splash); _splashes[slot.Number] = splash;
        var top = new DockPanel();
        var number = new TextBlock { Text = WuxiaTheme.Numeral(slot.Number), FontFamily = WuxiaTheme.Calligraphy, FontSize = 23, Foreground = WuxiaTheme.Brush(slot.Occupied ? "#574829" : "#776344"), Margin = new Thickness(0, 0, 10, 0) }; top.Children.Add(number);
        var state = new TextBlock { FontSize = 12, FontFamily = WuxiaTheme.Calligraphy, VerticalAlignment = VerticalAlignment.Center }; top.Children.Add(state); _states[slot.Number] = state;
        body.Children.Add(top);
        var image = new Border { Background = WuxiaTheme.Brush(slot.Occupied ? "#17211B" : "#141C17"), Margin = new Thickness(0, 7, 0, 7), BorderBrush = WuxiaTheme.Brush("#776E50"), BorderThickness = new Thickness(.5), ClipToBounds = true };
        var picture = new Grid(); picture.Children.Add(new BaguaGlyph(_animate && (!slot.Occupied || slot.State == AgentState.Running)) { Opacity = slot.Occupied ? .18 : .22, Margin = new Thickness(8) });
        var caption = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        var seal = new TextBlock { FontFamily = WuxiaTheme.Calligraphy, FontSize = 32, TextAlignment = TextAlignment.Center, VerticalAlignment = VerticalAlignment.Center }; _seals[slot.Number] = seal;
        var stamp = new Border { BorderThickness = new Thickness(2), Padding = new Thickness(4), HorizontalAlignment = HorizontalAlignment.Center, Child = seal }; _sealFrames[slot.Number] = stamp; caption.Children.Add(stamp);
        var message = new TextBlock { FontSize = 10, TextAlignment = TextAlignment.Center, Margin = new Thickness(3, 5, 3, 0) }; _messages[slot.Number] = message; caption.Children.Add(message);
        picture.Children.Add(caption); image.Child = picture; Grid.SetRow(image, 1); body.Children.Add(image); _images[slot.Number] = image;
        var name = new TextBlock { Text = slot.Occupied ? slot.DisplayName : "空 阵 眼 · 点击收纳", FontFamily = WuxiaTheme.Calligraphy, FontSize = 15, TextTrimming = TextTrimming.CharacterEllipsis, Foreground = WuxiaTheme.Brush(slot.Occupied ? "#342D22" : "#958362"), TextAlignment = TextAlignment.Center, ToolTip = slot.DisplayName };
        if (slot.Occupied) name.SetBinding(TextBlock.TextProperty, new Binding(nameof(Slot.DisplayName)));
        Grid.SetRow(name, 2); body.Children.Add(name); card.Child = body;
        var translate = new TranslateTransform(); var scale = new ScaleTransform(1, 1); var skew = new SkewTransform(slot.Number % 3 == 1 ? -1.2 : slot.Number % 3 == 0 ? 1.2 : 0, 0);
        var transforms = new TransformGroup(); transforms.Children.Add(scale); transforms.Children.Add(skew); transforms.Children.Add(translate); shell.RenderTransform = transforms;
        if (_animate)
        {
            shell.Loaded += (_, _) =>
            {
                var delay = TimeSpan.FromMilliseconds((slot.Number - 1) * 35);
                shell.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(330)) { BeginTime = delay });
                scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(.12, 1, TimeSpan.FromMilliseconds(480)) { BeginTime = delay, EasingFunction = new BackEase { Amplitude = .2, EasingMode = EasingMode.EaseOut } });
                translate.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation((slot.Number % 3 - 1) * 65, 0, TimeSpan.FromMilliseconds(450)) { BeginTime = delay, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
            };
            if (slot.Occupied) translate.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-4, 4, TimeSpan.FromSeconds(2.4 + slot.Number * .12)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase() });
            var orbit = new System.Windows.Shapes.Rectangle { Stroke = slot.State == AgentState.Error ? WuxiaTheme.Cinnabar : slot.State == AgentState.Waiting ? WuxiaTheme.Gold : WuxiaTheme.Jade, StrokeThickness = 1.8, StrokeDashArray = new DoubleCollection { 16, 65, 3, 35 }, Opacity = slot.Occupied ? .8 : .18, Margin = new Thickness(5, 0, 5, 0), IsHitTestVisible = false };
            Grid.SetRow(orbit, 1); shell.Children.Add(orbit);
            orbit.BeginAnimation(System.Windows.Shapes.Shape.StrokeDashOffsetProperty, new DoubleAnimation(0, -119, TimeSpan.FromSeconds(3.2)) { RepeatBehavior = RepeatBehavior.Forever });
        }
        shell.MouseEnter += (_, _) => { _wheel.Reset(); Select(slot.Number); Panel.SetZIndex(shell, 10); if (_animate) { scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(scale.ScaleX, 1.045, TimeSpan.FromMilliseconds(190)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = .3 } }); scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(scale.ScaleY, 1.045, TimeSpan.FromMilliseconds(190))); skew.BeginAnimation(SkewTransform.AngleXProperty, new DoubleAnimation(skew.AngleX, 0, TimeSpan.FromMilliseconds(190))); } };
        shell.MouseLeave += (_, _) => { if (_animate) { scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(scale.ScaleX, 1, TimeSpan.FromMilliseconds(160))); scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(scale.ScaleY, 1, TimeSpan.FromMilliseconds(160))); } };
        shell.MouseLeftButtonUp += (_, e) => { Choose?.Invoke(slot.Number); e.Handled = true; };
        return shell;
    }

    private void SlotChanged(object? sender, PropertyChangedEventArgs e)
    {
        bool changed = sender is Slot before && _visualStates.GetValueOrDefault(before.Number) != before.State + ":" + before.Connected + ":" + before.Occupied;
        RefreshSelection();
        if (changed && IsLoaded) UpdateThumbnails();
    }
    private void RefreshSelection()
    {
        foreach (var slot in _slots)
        {
            var color = slot.Connected ? slot.StateColor : "#827352"; var accent = WuxiaTheme.Brush(color);
            var card = _cards[slot.Number];
            _splashes[slot.Number].Visibility = slot.Connected && slot.State == AgentState.Error ? Visibility.Visible : Visibility.Collapsed;
            card.BorderBrush = slot.IsDropTarget ? (slot.Occupied ? WuxiaTheme.Gold : WuxiaTheme.Jade) : slot.Number == SelectedNumber ? WuxiaTheme.Gold : WuxiaTheme.Bronze;
            card.BorderThickness = new Thickness(slot.Number == SelectedNumber || slot.IsDropTarget ? 2 : 1);
            card.Background = !slot.Occupied ? WuxiaTheme.Brush("#18201B") : slot.Connected && slot.State == AgentState.Waiting ? WuxiaTheme.GoldPaper : slot.Connected && slot.State == AgentState.Error ? WuxiaTheme.RedPaper : WuxiaTheme.Paper;
            var glow = card.Effect as DropShadowEffect ?? new DropShadowEffect { ShadowDepth = 0 };
            glow.Color = (Color)ColorConverter.ConvertFromString(slot.Number == SelectedNumber ? "#D8B56B" : color); glow.BlurRadius = slot.Number == SelectedNumber || slot.State == AgentState.Error ? 20 : 12; glow.Opacity = slot.Number == SelectedNumber || slot.State == AgentState.Error ? .45 : .26;
            card.Effect = slot.Occupied ? glow : null;
            _states[slot.Number].Text = slot.Occupied ? slot.WuxiaStateLabel : "虚位以待";
            _states[slot.Number].Foreground = WuxiaTheme.Brush(slot.Occupied ? slot.State == AgentState.Error ? "#8F3E32" : slot.State == AgentState.Waiting ? "#84601F" : "#375849" : "#897954");
            _seals[slot.Number].Text = !slot.Occupied ? WuxiaTheme.Numeral(slot.Number) : !slot.Connected ? "待 重 连" : slot.State == AgentState.Waiting ? "敕" : slot.State == AgentState.Error ? "阵法\n崩坏" : slot.State == AgentState.Running ? "生 生 不 息" : slot.State == AgentState.Ready ? "卷 成" : "静 候 起 阵";
            bool stamped = slot.Connected && slot.State is AgentState.Waiting or AgentState.Error;
            _sealFrames[slot.Number].BorderBrush = stamped ? accent : Brushes.Transparent;
            _sealFrames[slot.Number].Width = stamped ? 76 : double.NaN; _sealFrames[slot.Number].Height = stamped ? 76 : double.NaN;
            _sealFrames[slot.Number].RenderTransformOrigin = new Point(.5, .5); _sealFrames[slot.Number].RenderTransform = new RotateTransform(stamped ? -5 : 0);
            _seals[slot.Number].FontSize = stamped ? slot.State == AgentState.Waiting ? 49 : 28 : 29;
            _seals[slot.Number].Foreground = accent;
            _messages[slot.Number].Text = !slot.Occupied ? "拖入剑匣 · 或点击收纳" : !slot.Connected ? "窗口已断开 · 点击重新连接" : slot.State == AgentState.Waiting ? "阵法凝滞 · 候君决断" : slot.State == AgentState.Error ? "气血逆行 · 进入终端查看" : slot.ProjectLabel == "" ? slot.ToolName : slot.ProjectLabel;
            _messages[slot.Number].Foreground = WuxiaTheme.Brush("#B6AA89");
            string visual = slot.State + ":" + slot.Connected + ":" + slot.Occupied;
            if (_visualStates.GetValueOrDefault(slot.Number) != visual)
            {
                if (_animate && slot.Occupied && slot.State == AgentState.Waiting) _seals[slot.Number].BeginAnimation(OpacityProperty, new DoubleAnimation(.35, 1, TimeSpan.FromSeconds(1.1)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
                else _seals[slot.Number].BeginAnimation(OpacityProperty, null);
                if (_animate && slot.Connected && slot.State == AgentState.Waiting) glow.BeginAnimation(DropShadowEffect.OpacityProperty, new DoubleAnimation(.15, .6, TimeSpan.FromSeconds(1.3)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
                else glow.BeginAnimation(DropShadowEffect.OpacityProperty, null);
                if (_animate && slot.State == AgentState.Error)
                {
                    var shake = new TranslateTransform(); card.RenderTransform = shake;
                    var animation = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(430), FillBehavior = FillBehavior.Stop };
                    foreach (var p in new[] { (0, 0d), (45, -3d), (80, 2d), (140, -2d), (205, 1d), (285, -1d), (430, 0d) }) animation.KeyFrames.Add(new LinearDoubleKeyFrame(p.Item2, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(p.Item1))));
                    shake.BeginAnimation(TranslateTransform.XProperty, animation);
                }
                _visualStates[slot.Number] = visual;
            }
        }
        var selected = _slots.FirstOrDefault(s => s.Number == SelectedNumber);
        _hint.Text = selected == null ? "万象归藏 · 诸事有序" : WuxiaTheme.Numeral(selected.Number) + "  ·  " + (selected.Occupied ? selected.DisplayName + "    —    Enter 进入 · Tab / Esc 合卷" : "空阵眼    —    点击或 Enter 收纳已有窗口");
    }
    internal void Browse(int delta) { var next = _wheel.Move(delta, _slots.Where(s => s.Connected).Select(s => s.Number).ToArray(), SelectedNumber); if (next.HasValue) Select(next.Value); }
    internal void Select(int n) { if (!_cards.ContainsKey(n)) return; SelectedNumber = n; RefreshSelection(); }
    internal void Enter() { if (SelectedNumber.HasValue) Choose?.Invoke(SelectedNumber.Value); }
    public Slot? HitSlot(Native.Point cursor)
    {
        if (!IsVisible) return null;
        var p = PointFromScreen(new Point(cursor.X, cursor.Y));
        foreach (var slot in _slots) { var card = _cards[slot.Number]; var q = card.TranslatePoint(new Point(), this); if (p.X >= q.X && p.Y >= q.Y && p.X <= q.X + card.ActualWidth && p.Y <= q.Y + card.ActualHeight) return slot; }
        return null;
    }
    private void OnKey(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers != ModifierKeys.None) return;
        if (e.Key is Key.Escape or Key.Tab) { if (!e.IsRepeat) Dismiss?.Invoke(); e.Handled = true; return; }
        if (e.Key == Key.Enter) { if (!e.IsRepeat) Enter(); e.Handled = true; return; }
        int digit = e.Key is >= Key.D1 and <= Key.D9 ? e.Key - Key.D0 : e.Key is >= Key.NumPad1 and <= Key.NumPad9 ? e.Key - Key.NumPad0 : 0;
        if (digit != 0) { if (!e.IsRepeat && _cards.ContainsKey(digit)) Choose?.Invoke(digit); e.Handled = true; return; }
        int step = e.Key switch { Key.Left => -1, Key.Right => 1, Key.Up => -3, Key.Down => 3, _ => 0 };
        if (step == 0) return;
        _wheel.Reset(); int index = _slots.ToList().FindIndex(s => s.Number == SelectedNumber);
        Select(_slots[((index + step) % _slots.Count + _slots.Count) % _slots.Count].Number); e.Handled = true;
    }
    public void UpdateThumbnails()
    {
        ClearThumbnails();
        foreach (var s in _slots.Where(s => Native.Matches(s.Window)))
        {
            byte opacity = s.State == AgentState.Waiting ? (byte)82 : s.State == AgentState.Error ? (byte)65 : (byte)226;
            var thumb = Native.Thumbnail(new WindowInteropHelper(this).Handle, new(s.Window!.Handle), ImageRect(s.Number), opacity);
            if (thumb != IntPtr.Zero) _thumbnails[s.Number] = thumb;
        }
    }
    private Native.Rect ImageRect(int number)
    {
        double scale = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformToDevice.M11 ?? 1; var image = _images[number]; var r = image.TransformToAncestor(this).TransformBounds(new Rect(0, 0, image.ActualWidth, image.ActualHeight));
        return new((int)(r.Left * scale), (int)(r.Top * scale), (int)(r.Right * scale), (int)(r.Bottom * scale));
    }
    private void PositionThumbnails() { foreach (var p in _thumbnails) Native.MoveThumbnail(p.Value, ImageRect(p.Key)); }
    private void ClearThumbnails() { foreach (var t in _thumbnails.Values) Native.DwmUnregisterThumbnail(t); _thumbnails.Clear(); }
}
