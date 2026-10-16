using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace CodeManager;

public sealed class InventoryWindow : Window
{
    private readonly IReadOnlyList<Slot> _slots;
    private readonly Dictionary<int, SkinTaskCard> _cards = new();
    private readonly Dictionary<int, IntPtr> _thumbnails = new();
    private readonly Dictionary<int, string> _visualStates = new();
    private readonly WheelSelection _wheel = new();
    private readonly TextBlock _hint;
    private readonly DispatcherTimer _motion;
    private readonly ScrollViewer? _viewport;
    private Window? _mask;
    private bool _closed;
    public int? SelectedNumber { get; private set; }
    internal int ThumbnailCount => _thumbnails.Count;
    public event Action<int>? Choose;
    public event Action? Dismiss;

    public InventoryWindow(IReadOnlyList<Slot> slots, Native.Rect area, double scale, int? selected, bool animate, bool duringDrag = false, bool presentationPreview = false)
    {
        _slots = slots.OrderBy(s => s.Number).ToList();
        var skin = SkinCatalog.Current;
        SelectedNumber = _slots.FirstOrDefault(s => s.Number == selected && s.Occupied)?.Number ?? _slots.FirstOrDefault(s => s.Connected)?.Number ?? 1;
        Title = "OmniVibe · " + skin.OverviewTitle; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false; Topmost = true; Background = WuxiaTheme.Brush(skin.Background); ShowActivated = !duringDrag;
        Width = Math.Max(1, Math.Min(1280, (area.Right - area.Left) / scale - 56));
        Height = Math.Max(1, Math.Min(960, (area.Bottom - area.Top) / scale - 48));
        bool scrollingLayout = Height < 420;
        Left = (area.Left + (area.Right - area.Left) / 2d) / scale - Width / 2;
        Top = (area.Top + (area.Bottom - area.Top) / 2d) / scale - Height / 2;
        var layers = new Grid { ClipToBounds = true };
        layers.Children.Add(new SkinBackdrop { IsHitTestVisible = false });
        var root = new Grid { Margin = scrollingLayout ? new Thickness(12) : new Thickness(Width < 800 ? 18 : 32, 19, Width < 800 ? 18 : 32, 18) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); root.RowDefinitions.Add(new RowDefinition()); root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var header = new Grid { Margin = new Thickness(0, 0, 0, scrollingLayout ? 9 : 15) };
        header.ColumnDefinitions.Add(new ColumnDefinition()); header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bool centered = skin.Family is "ink" or "relic" or "astral" or "wonderland";
        var title = new StackPanel { HorizontalAlignment = centered ? HorizontalAlignment.Center : HorizontalAlignment.Left, Margin = centered ? new Thickness(65, 0, 0, 0) : new Thickness(0) };
        title.Children.Add(new TextBlock { Text = presentationPreview ? "OMNIVIBE / 皮肤预览 · 示例任务" : "OMNIVIBE / " + skin.Subtitle, FontSize = 10, Foreground = WuxiaTheme.Brush(skin.Muted) });
        title.Children.Add(new TextBlock { Text = skin.OverviewTitle, FontSize = scrollingLayout ? 24 : Height < 700 ? 27 : skin.Family == "ink" ? 39 : 33, FontFamily = skin.TitleFont, FontWeight = FontWeights.SemiBold, Foreground = WuxiaTheme.Brush(skin.Text), Margin = new Thickness(0, scrollingLayout ? 3 : 5, 0, scrollingLayout ? 2 : 5) });
        if (!scrollingLayout) title.Children.Add(new TextBlock { Text = "滚轮 / 方向键浏览     ·     Enter 进入     ·     数字直达", FontSize = 10, Foreground = WuxiaTheme.Brush(skin.Muted) });
        header.Children.Add(title);
        var close = new Button { Content = "关闭 ×", ToolTip = "Tab / Esc 关闭", VerticalAlignment = VerticalAlignment.Top, Padding = new Thickness(10, 7, 10, 7), Margin = new Thickness(8, 0, 0, 0) };
        close.Click += (_, _) => Dismiss?.Invoke(); Grid.SetColumn(close, 1); header.Children.Add(close); root.Children.Add(header);
        var grid = new UniformGrid { Columns = 3, Rows = 3, Margin = new Thickness(-7, 0, -7, 0) };
        foreach (var slot in _slots)
        {
            var card = new SkinTaskCard(slot, animate); _cards[slot.Number] = card;
            if (!presentationPreview) card.MouseEnter += (_, _) => { _wheel.Reset(); SelectedNumber = slot.Number; RefreshSelection(); };
            card.MouseLeftButtonUp += (_, e) => { Choose?.Invoke(slot.Number); e.Handled = true; };
            grid.Children.Add(card);
        }
        if (scrollingLayout)
        {
            grid.MinHeight = Math.Clamp((Height - 110) * 3, 360, 540);
            _viewport = new ScrollViewer { Content = grid, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, CanContentScroll = false, ClipToBounds = true, Padding = new Thickness(0, 0, 4, 0) };
            _viewport.ScrollChanged += (_, _) => { if (IsLoaded && !_closed) UpdateThumbnails(); };
            Grid.SetRow(_viewport, 1); root.Children.Add(_viewport);
        }
        else { Grid.SetRow(grid, 1); root.Children.Add(grid); }
        _hint = new TextBlock { FontSize = 10, Foreground = WuxiaTheme.Brush(skin.Muted), Margin = new Thickness(0, 12, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis, HorizontalAlignment = HorizontalAlignment.Center };
        Grid.SetRow(_hint, 2); root.Children.Add(_hint); layers.Children.Add(root); Content = layers;
        SourceInitialized += (_, _) => Native.Decorate(this, noActivate: duringDrag);
        _motion = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
        _motion.Tick += (_, _) => PositionThumbnails();
        Loaded += (_, _) =>
        {
            if (!presentationPreview)
            {
                _mask = new Window { WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, AllowsTransparency = true, Background = Brushes.Transparent, ShowActivated = false, ShowInTaskbar = false, Topmost = true, IsHitTestVisible = false, Left = area.Left / scale, Top = area.Top / scale, Width = (area.Right - area.Left) / scale, Height = (area.Bottom - area.Top) / scale, Content = new SkinBackdrop { Translucent = true } };
                _mask.SourceInitialized += (_, _) => Native.Decorate(_mask, clickThrough: true); _mask.Show();
            }
            Native.SetWindowPos(new WindowInteropHelper(this).Handle, new IntPtr(-1), 0, 0, 0, 0, 0x13);
            UpdateLayout(); BringSelectedIntoView(); UpdateThumbnails(); if (!duringDrag && !presentationPreview) Focus();
            if (animate)
            {
                BeginAnimation(OpacityProperty, new DoubleAnimation(.25, 1, TimeSpan.FromMilliseconds(160)) { FillBehavior = FillBehavior.Stop });
                _mask?.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)) { FillBehavior = FillBehavior.Stop });
                _motion.Start();
            }
        };
        SizeChanged += (_, _) => { if (IsLoaded) PositionThumbnails(); };
        Closed += (_, _) =>
        {
            _closed = true; _motion.Stop(); ClearThumbnails(); _mask?.Close(); _mask = null;
            foreach (var card in _cards.Values) card.StopAnimations();
            foreach (var s in _slots) s.PropertyChanged -= SlotChanged;
        };
        PreviewMouseWheel += (_, e) => { Browse(e.Delta); e.Handled = true; }; PreviewKeyDown += OnKey;
        foreach (var s in _slots) s.PropertyChanged += SlotChanged;
        RefreshSelection();
    }
    private void SlotChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_closed) return;
        bool changed = sender is Slot s && _visualStates.GetValueOrDefault(s.Number) != VisualKey(s);
        RefreshSelection(); if (changed && IsLoaded) UpdateThumbnails();
    }
    private static string VisualKey(Slot slot) => slot.State + ":" + slot.Connected + ":" + slot.Occupied + ":" + slot.Window?.Handle;
    private void RefreshSelection()
    {
        foreach (var slot in _slots) { _cards[slot.Number].Update(slot.Number == SelectedNumber); _visualStates[slot.Number] = VisualKey(slot); }
        var selected = _slots.FirstOrDefault(s => s.Number == SelectedNumber);
        _hint.Text = selected == null ? "所有任务，一个工作现场" : SkinCatalog.Current.SlotNumber(selected.Number) + "  /  " + (selected.Occupied ? selected.DisplayName + "    ·    Enter 进入 · Tab / Esc 关闭" : "空槽位    ·    点击或 Enter 选择已有窗口");
        if (_viewport != null) { _hint.Text = "滚动总览 · 部分预览收起 · 方向键可浏览全部任务"; _hint.ToolTip = "屏幕工作区较短时，任务保持可读尺寸。只有完整显示在视口内的窗口预览实时更新；滚动到任务后恢复预览。"; }
    }
    internal void Browse(int delta) { var next = _wheel.Move(delta, _slots.Where(s => _viewport != null || s.Connected).Select(s => s.Number).ToArray(), SelectedNumber); if (next.HasValue) Select(next.Value); }
    internal void Select(int n) { if (!_cards.ContainsKey(n)) return; SelectedNumber = n; RefreshSelection(); BringSelectedIntoView(); }
    private void BringSelectedIntoView() { if (_viewport != null && SelectedNumber.HasValue && _cards.TryGetValue(SelectedNumber.Value, out var card)) card.BringIntoView(); }
    internal void Enter() { if (SelectedNumber.HasValue) Choose?.Invoke(SelectedNumber.Value); }
    public Slot? HitSlot(Native.Point cursor)
    {
        if (!IsVisible) return null; var p = PointFromScreen(new Point(cursor.X, cursor.Y));
        if (_viewport != null && !ViewportBounds().Contains(p)) return null;
        foreach (var slot in _slots) { var card = _cards[slot.Number]; var q = card.TranslatePoint(new Point(), this); if (p.X >= q.X && p.Y >= q.Y && p.X <= q.X + card.ActualWidth && p.Y <= q.Y + card.ActualHeight) return slot; } return null;
    }
    private void OnKey(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers != ModifierKeys.None) return;
        if (e.Key is Key.Escape or Key.Tab) { if (!e.IsRepeat) Dismiss?.Invoke(); e.Handled = true; return; }
        if (e.Key == Key.Enter) { if (!e.IsRepeat) Enter(); e.Handled = true; return; }
        int digit = e.Key is >= Key.D1 and <= Key.D9 ? e.Key - Key.D0 : e.Key is >= Key.NumPad1 and <= Key.NumPad9 ? e.Key - Key.NumPad0 : 0;
        if (digit != 0) { if (!e.IsRepeat && _cards.ContainsKey(digit)) Choose?.Invoke(digit); e.Handled = true; return; }
        int step = e.Key switch { Key.Left => -1, Key.Right => 1, Key.Up => -3, Key.Down => 3, _ => 0 }; if (step == 0) return;
        _wheel.Reset(); int index = _slots.ToList().FindIndex(s => s.Number == SelectedNumber); Select(_slots[((index + step) % _slots.Count + _slots.Count) % _slots.Count].Number); e.Handled = true;
    }
    public void UpdateThumbnails()
    {
        ClearThumbnails();
        foreach (var s in _slots.Where(s => s.Connected && Native.Matches(s.Window) && PreviewFullyVisible(s.Number)))
        {
            // Status, name, unread and selection labels live outside this rectangle.
            var thumb = Native.Thumbnail(new WindowInteropHelper(this).Handle, new(s.Window!.Handle), ImageRect(s.Number), 245);
            if (thumb != IntPtr.Zero) _thumbnails[s.Number] = thumb;
        }
    }
    private Native.Rect ImageRect(int number)
    {
        double scale = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformToDevice.M11 ?? 1; var image = _cards[number].PreviewRegion;
        var r = image.TransformToAncestor(this).TransformBounds(new Rect(2, 2, Math.Max(1, image.ActualWidth - 4), Math.Max(1, image.ActualHeight - 4)));
        return new((int)(r.Left * scale), (int)(r.Top * scale), (int)(r.Right * scale), (int)(r.Bottom * scale));
    }
    private bool PreviewFullyVisible(int number)
    {
        if (_viewport == null) return true;
        var image = _cards[number].PreviewRegion;
        var bounds = image.TransformToAncestor(this).TransformBounds(new Rect(image.RenderSize));
        var viewport = ViewportBounds();
        return bounds.Height > 1 && bounds.Left >= viewport.Left - 1 && bounds.Right <= viewport.Right + 1 && bounds.Top >= viewport.Top - 1 && bounds.Bottom <= viewport.Bottom + 1;
    }
    private Rect ViewportBounds()
    {
        FrameworkElement clip = _viewport!.Template.FindName("PART_ScrollContentPresenter", _viewport) as FrameworkElement ?? _viewport;
        return clip.TransformToAncestor(this).TransformBounds(new Rect(clip.RenderSize));
    }
    private void PositionThumbnails()
    {
        // Entrance transforms can briefly move a preview across the viewport edge.
        if (_viewport != null && (_thumbnails.Keys.Any(n => !PreviewFullyVisible(n)) || _slots.Any(s => s.Connected && !_thumbnails.ContainsKey(s.Number) && PreviewFullyVisible(s.Number) && Native.Matches(s.Window)))) UpdateThumbnails();
        foreach (var p in _thumbnails) Native.MoveThumbnail(p.Value, ImageRect(p.Key));
    }
    private void ClearThumbnails() { foreach (var t in _thumbnails.Values) Native.DwmUnregisterThumbnail(t); _thumbnails.Clear(); }
}
