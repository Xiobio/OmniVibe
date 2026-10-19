using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace CodeManager;

/// <summary>Fixed clockwise slots. The centre and everything beyond the rim cancel.</summary>
internal static class RadialSelection
{
    public static int? Hit(Point point, Point centre, double scale = 1)
    {
        double x = (point.X - centre.X) / scale, y = (point.Y - centre.Y) / scale;
        double radius = Math.Sqrt(x * x + y * y);
        if (radius < 106 || radius > 268) return null;
        double angle = (Math.Atan2(x, -y) * 180 / Math.PI + 380) % 360;
        return (int)(angle / 40) + 1;
    }
}

/// <summary>A no-focus overlay: hold a chord, point, release. Click entry uses click to confirm.</summary>
internal sealed class RadialInventoryWindow : Window
{
    private readonly DispatcherTimer _timer;
    private readonly Func<bool>? _held;
    private Point _initialCursor;
    private bool _moved;
    private bool _finished;
    private readonly bool _animate;
    private readonly IntPtr _previousFocus;
    private readonly DateTime _started = DateTime.UtcNow;
    internal RadialInventorySurface Surface { get; }
    internal int? SelectedNumber => Surface.SelectedNumber;
    public event Action<int?>? Finish;
    public RadialInventoryWindow(IReadOnlyList<Slot> slots, Native.Rect area, double scale,
        bool animate, string gesture, Func<bool>? held = null, bool preview = false)
    {
        Left = area.Left / scale; Top = area.Top / scale;
        Width = (area.Right - area.Left) / scale; Height = (area.Bottom - area.Top) / scale;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false; ShowActivated = false; Topmost = !preview;
        AllowsTransparency = true; Background = Brushes.Transparent;
        _animate = animate && SkinCatalog.DecorationsEnabled; _held = held;
        _previousFocus = Native.GetForegroundWindow();
        Native.GetCursorPos(out var cursor); _initialCursor = new(cursor.X, cursor.Y);
        double factor = Math.Min(1, Math.Min(Width / 620, Height / 740));
        var centre = new Point(Width / 2, Height / 2 - 12 * factor);
        if (!preview && held != null)
            centre = new Point(Math.Clamp(cursor.X / scale - Left, 285 * factor, Math.Max(285 * factor, Width - 285 * factor)),
                Math.Clamp(cursor.Y / scale - Top, 340 * factor, Math.Max(340 * factor, Height - 365 * factor)));
        Surface = new RadialInventorySurface(slots, centre, factor, gesture, held != null);
        Content = Surface;
        SourceInitialized += (_, _) => Native.Decorate(this);
        MouseLeftButtonUp += (_, e) => { Surface.SelectAt(e.GetPosition(Surface)); Complete(true); e.Handled = true; };
        MouseRightButtonUp += (_, e) => { Complete(false); e.Handled = true; };
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(20) };
        _timer.Tick += Tick;
        Loaded += (_, _) =>
        {
            if (_animate) BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(110)));
            if (!preview) _timer.Start();
        };
        Closed += (_, _) => { _timer.Stop(); _timer.Tick -= Tick; _finished = true; };
    }
    private void Tick(object? sender, EventArgs e)
    {
        if (Native.GetForegroundWindow() != _previousFocus) { Complete(false); return; }
        // Polling also catches release before the opening WM_HOTKEY was dispatched.
        Native.GetCursorPos(out var cursor);
        if (Math.Abs(cursor.X - _initialCursor.X) + Math.Abs(cursor.Y - _initialCursor.Y) >= 6) _moved = true;
        if (_moved || _held == null)
            Surface.SelectAt(Surface.PointFromScreen(new Point(cursor.X, cursor.Y)));
        if (_held != null && !_held()) { Complete(true); return; }
        if (_animate) Surface.SetPhase((DateTime.UtcNow - _started).TotalSeconds);
    }
    internal void Complete(bool confirm)
    {
        if (_finished) return;
        _finished = true; _timer.Stop();
        int? selected = confirm && Surface.SelectedNumber is int n && Surface.Slots.Single(s => s.Number == n).Connected ? n : null;
        Finish?.Invoke(selected);
    }
}

internal sealed class RadialInventorySurface : FrameworkElement
{
    internal IReadOnlyList<Slot> Slots { get; }
    internal int? SelectedNumber { get; private set; }
    internal Point Centre { get; }
    internal double Factor { get; }
    private readonly SkinDefinition _skin = SkinCatalog.Current;
    private readonly string _gesture;
    private readonly bool _hold;
    private double _phase;
    private double _selectedAt;
    internal RadialInventorySurface(IReadOnlyList<Slot> slots, Point centre, double factor, string gesture, bool hold)
    {
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        Slots = slots.OrderBy(s => s.Number).ToArray(); Centre = centre; Factor = factor; _gesture = gesture; _hold = hold;
    }
    internal void SelectAt(Point point) => Select(RadialSelection.Hit(point, Centre, Factor));
    internal void Select(int? number)
    {
        if (!Slots.Any(s => s.Number == number && s.Occupied)) number = null;
        if (SelectedNumber == number) return;
        SelectedNumber = number; _selectedAt = _phase; InvalidateVisual();
    }
    internal void SetPhase(double phase)
    {
        bool moving = _phase - _selectedAt < .7;
        _phase = phase;
        if (moving) InvalidateVisual();
    }
    private static Point Polar(double radius, double degrees) => new(Math.Sin(degrees * Math.PI / 180) * radius, -Math.Cos(degrees * Math.PI / 180) * radius);
    private static Geometry Sector(double inner, double outer, double start, double end)
    {
        var geometry = new StreamGeometry();
        using (var g = geometry.Open())
        {
            g.BeginFigure(Polar(outer, start), true, true);
            g.ArcTo(Polar(outer, end), new Size(outer, outer), 0, false, SweepDirection.Clockwise, true, false);
            g.LineTo(Polar(inner, end), true, false);
            g.ArcTo(Polar(inner, start), new Size(inner, inner), 0, false, SweepDirection.Counterclockwise, true, false);
        }
        geometry.Freeze(); return geometry;
    }
    private void Text(DrawingContext dc, string value, Point centre, double size, string color, double width, bool bold = false, int lines = 1)
    {
        var text = new FormattedText(value, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Microsoft YaHei UI"), FontStyles.Normal, bold ? FontWeights.SemiBold : FontWeights.Normal, FontStretches.Normal),
            size, WuxiaTheme.Brush(color), VisualTreeHelper.GetDpi(this).PixelsPerDip)
        { MaxTextWidth = width, MaxLineCount = lines, Trimming = TextTrimming.CharacterEllipsis, TextAlignment = TextAlignment.Center };
        dc.DrawText(text, new Point(centre.X - width / 2, centre.Y - text.Height / 2));
    }
    protected override void OnRender(DrawingContext dc) => DrawLoadout(dc);
    private void DrawLoadout(DrawingContext dc)
    {
        var s = _skin;
        var background = (Color)ColorConverter.ConvertFromString(s.Background); background.A = 235;
        dc.DrawRectangle(new SolidColorBrush(background), null, new Rect(0, 0, ActualWidth, ActualHeight));
        dc.PushTransform(new TranslateTransform(Centre.X, Centre.Y)); dc.PushTransform(new ScaleTransform(Factor, Factor));
        foreach (var slot in Slots) {
            if (!slot.Occupied) continue;
            bool selected = SelectedNumber == slot.Number;
            double angle = (slot.Number - 1) * 40;
            var p = Polar(188, angle); double size = selected ? 126 : 116;
            if (SkinCatalog.DecorationsEnabled) { dc.PushOpacity(selected ? .65 : .25); EquipmentPedestal.Draw(dc, s, new Rect(p.X-size*.4, p.Y+size*.43, size*.8, 10)); dc.Pop(); }
            EquipmentCatalog.Draw(dc, slot, new Rect(p.X - size/2, p.Y - size/2, size, size), slot.Connected ? 1 : .55, s.Id);
            Text(dc, slot.Number.ToString(), new Point(p.X - 37, p.Y + 49), 12, selected ? s.Accent : s.Text, 20, true);
            if (slot.Connected && slot.State is AgentState.Waiting or AgentState.Error or AgentState.Ready)
                Text(dc, slot.State == AgentState.Ready ? "✓" : "!", new Point(p.X + 37, p.Y + 49), 12, slot.StateColor, 20, true);
        }
        var chosen = Slots.FirstOrDefault(x => x.Number == SelectedNumber) ?? Slots.FirstOrDefault(x => x.IsActive) ?? Slots.First();
        if (chosen.Occupied) EquipmentCatalog.Draw(dc, chosen, new Rect(-80, -80, 160, 160), skin: s.Id);
        Text(dc, chosen.Occupied ? EquipmentCatalog.Name(chosen, s.Id) : "添加任务", new Point(0, 91), 13, s.Text, 180, true);
        Text(dc, "永劫无间 / 角色配装", new Point(0, -320), 17, s.Text, 450, true);
        Text(dc, chosen.Occupied ? chosen.DisplayName + " · " + chosen.StateLabel : "空槽位 · 拖入窗口绑定这件武器", new Point(0, 292), 12, s.Text, 560);
        Text(dc, _hold ? "按住 " + _gesture + "  ·  指向角色  ·  松键进入任务" : "点击角色进入任务", new Point(0, 321), 11, s.Muted, 560);
        Text(dc, "中央松键 / Esc / 右键取消", new Point(0, 346), 10, s.Muted, 500);
        dc.Pop(); dc.Pop();
    }
}

/// <summary>Original vector signals; no game artwork, fonts or sound samples.</summary>
internal static class HexSignal
{
    internal static string Label(Slot slot) => !slot.Connected ? "离线" : slot.State switch
    { AgentState.Waiting => "需要处理", AgentState.Error => "错误警报", AgentState.Ready => "本轮已回复", AgentState.Running => "正在执行", _ => "状态未知" };
    internal static void Draw(DrawingContext dc, Point centre, double radius, Slot slot, SkinDefinition skin, double phase)
    {
        string color = slot.Connected ? SkinUi.StateColor(slot, skin) : skin.Unknown;
        var brush = WuxiaTheme.Brush(color);
        dc.PushTransform(new TranslateTransform(centre.X, centre.Y));
        if (phase < 1)
        {
            dc.PushOpacity((1 - phase) * .65);
            dc.DrawEllipse(null, new Pen(brush, 1.8), new Point(), radius * (1.1 + phase * 1.5), radius * (1.1 + phase * 1.5));
            dc.Pop();
        }
        dc.PushTransform(new RotateTransform(45));
        dc.DrawRectangle(WuxiaTheme.Brush(skin.Background), new Pen(brush, 1.6), new Rect(-radius * .69, -radius * .69, radius * 1.38, radius * 1.38));
        dc.DrawRectangle(null, new Pen(WuxiaTheme.Brush(skin.Accent), .55), new Rect(-radius * .88, -radius * .88, radius * 1.76, radius * 1.76));
        dc.Pop();
        var pen = new Pen(brush, 2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        double q = radius * .4;
        if (!slot.Occupied) { dc.DrawLine(pen, new Point(-q, 0), new Point(q, 0)); dc.DrawLine(pen, new Point(0, -q), new Point(0, q)); }
        else if (slot.Connected && slot.State == AgentState.Ready)
        { dc.DrawLine(pen, new Point(-q, 0), new Point(-q * .2, q * .6)); dc.DrawLine(pen, new Point(-q * .2, q * .6), new Point(q, -q * .65)); }
        else if (slot.Connected && slot.State == AgentState.Running)
        { dc.DrawLine(pen, new Point(-q * .55, -q), new Point(q * .6, 0)); dc.DrawLine(pen, new Point(q * .6, 0), new Point(-q * .55, q)); }
        else if (slot.Connected && slot.State is AgentState.Waiting or AgentState.Error)
        { dc.DrawLine(pen, new Point(0, -q), new Point(0, q * .25)); dc.DrawEllipse(brush, null, new Point(0, q), 1.4, 1.4); }
        else dc.DrawEllipse(null, pen, new Point(), q * .55, q * .55);
        dc.Pop();
    }
}

internal sealed class HexEquipSignalSurface : FrameworkElement
{
    private readonly Slot _slot;
    private readonly SkinDefinition _skin = SkinCatalog.Current;
    internal HexEquipSignalSurface(Slot slot)
    {
        _slot = slot;
    }
    protected override void OnRender(DrawingContext dc)
    {
        var s = _skin;
        dc.DrawGeometry(WuxiaTheme.Brush(s.Background), new Pen(WuxiaTheme.Brush(s.Accent), .8), Geometry.Parse("M1,10 H230 L249,29 V91 H20 L1,72 Z"));
        EquipmentCatalog.Draw(dc, _slot, new Rect(14, 16, 64, 76), skin: s.Id);
        void Text(string value, double y, double size, string color)
        {
            var text = new FormattedText(value, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface("Microsoft YaHei UI"), size, WuxiaTheme.Brush(color), VisualTreeHelper.GetDpi(this).PixelsPerDip)
            { MaxTextWidth = 155, MaxLineCount = 1, Trimming = TextTrimming.CharacterEllipsis };
            dc.DrawText(text, new Point(83, y));
        }
        Text("EQUIPPED / " + _slot.Number.ToString("D2"), 19, 9, s.Accent);
        Text(EquipmentCatalog.Name(_slot, s.Id), 37, 13, s.Text);
        Text(_slot.DisplayName, 62, 10, s.Muted);
    }
}
