using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace CodeManager;

internal static class TaskEmblem
{
    private static readonly string[] Colors = { "#72CCD9", "#BEA2E5", "#E6B77D", "#99CBA5", "#88B9EC", "#DEA5BC", "#CED28B", "#83CEBC", "#C3B09B" };
    internal static uint Seed(Slot slot)
    {
        uint hash = 2166136261;
        foreach (char c in slot.Id) hash = (hash ^ c) * 16777619;
        return hash;
    }
    internal static string Color(Slot slot) => Colors[Seed(slot) % 9];
    internal static string Name(Slot slot) => slot.DisplayName;
    internal static string Project(Slot slot)
    {
        string name = Name(slot); int divider = name.LastIndexOf('|');
        return divider >= 0 && name[(divider + 1)..].Trim().Length is > 0 and <= 28 ? name[(divider + 1)..].Trim() : slot.ProjectLabel;
    }
    internal static string Role(Slot slot)
    {
        string name = Name(slot); int divider = name.LastIndexOf('|');
        return divider >= 0 && Project(slot) != "" ? name[..divider].Trim() : name;
    }
    internal static string CardName(Slot slot) => Project(slot) is string project && project != "" && project != Role(slot) ? project + "\n" + Role(slot) : Name(slot);
    internal static string Initial(Slot slot)
    {
        string name = Name(slot).Trim();
        return name.Length == 0 ? ">_" : char.IsAsciiLetter(name[0]) ? new string(name.Where(char.IsAsciiLetterOrDigit).Take(2).ToArray()).ToUpperInvariant() : StringInfo.GetNextTextElement(name);
    }
}

/// <summary>A persistent equipment core with a deployable, fixed-position task constellation.</summary>
public sealed class DockWeaponWheel : FrameworkElement
{
    internal bool MeasureDrawing { get; set; }
    internal List<double> DrawTimes { get; } = new();
    internal List<long> DrawAllocations { get; } = new();
    private readonly record struct TextKey(string Value, double Size, string Color, double Width, bool Bold, int Lines, double Dpi, string Culture);
    private readonly Dictionary<TextKey, DrawingGroup> _textCache = new();
    private static readonly Dictionary<string, SolidColorBrush> BrushesByColor = new();
    private static readonly Dictionary<(string From, string To, double Angle, bool Fade), LinearGradientBrush> Gradients = new();
    private static readonly Dictionary<(double W, double H), Geometry> Plates = new();
    private static readonly Typeface NormalTypeface = new(new FontFamily("Microsoft YaHei UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
    private static readonly Typeface BoldTypeface = new(new FontFamily("Microsoft YaHei UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
    internal int TextBuilds { get; private set; }
    internal int DeploymentTransitions { get; private set; }
    private IReadOnlyList<Slot> _slots = Array.Empty<Slot>();
    private int? _hover, _pulseNumber;
    private string? _lastEquippedId;
    private bool _subscribed, _motionEnabled;
    private bool _warming, _warmScheduled;
    internal bool Aiming { get; private set; }
    internal bool IsDeployed { get; private set; }
    private bool _captureTargetsVisible;
    internal bool CaptureTargetsVisible { get => _captureTargetsVisible; set { if (_captureTargetsVisible == value) return; _captureTargetsVisible = value; InvalidateVisual(); } }
    private bool _removeHovered;
    internal bool RemoveHovered { get => _removeHovered; set { if (_removeHovered == value) return; _removeHovered = value; InvalidateVisual(); } }
    internal bool DeploymentInMotion => Math.Abs(Deployment - (IsDeployed ? 1 : 0)) > .001;
    internal event Action? DeploymentSettled;
    internal IReadOnlyList<Slot> Slots => _slots;
    private static DependencyProperty Animated(string name, double initial) => DependencyProperty.Register(name, typeof(double), typeof(DockWeaponWheel), new FrameworkPropertyMetadata(initial, FrameworkPropertyMetadataOptions.AffectsRender));
    private static readonly DependencyProperty PhaseProperty = Animated(nameof(Phase), 1);
    private static readonly DependencyProperty DeploymentProperty = Animated(nameof(Deployment), 0);
    private static readonly DependencyProperty LiftProperty = Animated(nameof(Lift), 1);
    private static readonly DependencyProperty FlowProperty = Animated(nameof(Flow), 0);
    private static readonly DependencyProperty[] HoverWeights = Enumerable.Range(1, 9).Select(n => Animated("HoverWeight" + n, 0)).ToArray();
    public double Phase { get => (double)GetValue(PhaseProperty); set => SetValue(PhaseProperty, value); }
    public double Deployment { get => (double)GetValue(DeploymentProperty); set => SetValue(DeploymentProperty, value); }
    public double Lift { get => (double)GetValue(LiftProperty); set => SetValue(LiftProperty, value); }
    public double Flow { get => (double)GetValue(FlowProperty); set => SetValue(FlowProperty, value); }
    internal bool MotionEnabled { get => _motionEnabled; set { _motionEnabled = value; UpdateFlow(); } }
    internal Slot? CurrentSlot => _slots.FirstOrDefault(s => s.IsActive) ?? _slots.FirstOrDefault(s => s.Id == _lastEquippedId && s.Connected) ?? _slots.FirstOrDefault(s => s.Connected) ?? _slots.FirstOrDefault(s => s.Occupied);
    // Empty hover is intentionally excluded from the central work context.
    internal Slot? FocusedSlot => _slots.FirstOrDefault(s => s.IsDropTarget) ?? _slots.FirstOrDefault(s => s.Number == _hover && s.Occupied) ?? CurrentSlot;
    internal int? AimCandidate => Aiming && _slots.FirstOrDefault(s => s.Number == _hover)?.Connected == true ? _hover : null;
    internal Point Centre => new(ActualWidth / 2, ActualHeight / 2);
    internal double Radius => Math.Max(1, Math.Min(ActualWidth, ActualHeight) / 2 - 24);
    internal bool InCore(Point point) => Math.Abs(point.X - Centre.X) <= 56 && Math.Abs(point.Y - Centre.Y) <= 56;
    public DockWeaponWheel()
    {
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        NativeSkinArt.Warm(SkinCatalog.Current);
        ThemeIdentityArt.Image(SkinCatalog.Current.Id);
        Loaded += (_, _) => { Subscribe(); UpdateFlow(); ScheduleWarmup(); };
        SizeChanged += (_, _) => ScheduleWarmup();
        Unloaded += (_, _) => { Unsubscribe(); foreach (var dp in new[] { PhaseProperty, DeploymentProperty, LiftProperty, FlowProperty }.Concat(HoverWeights)) BeginAnimation(dp, null); };
    }
    internal void SetSlots(IEnumerable<Slot> slots)
    {
        Unsubscribe(); _slots = slots.OrderBy(s => s.Number).ToArray();
        ThemeIdentityArt.Image(SkinCatalog.Current.Id);
        if (IsLoaded) Subscribe(); UpdateFlow(); InvalidateVisual(); ScheduleWarmup();
    }
    private void ScheduleWarmup()
    {
        if (!IsLoaded || _warmScheduled) return;
        _warmScheduled = true;
        Dispatcher.BeginInvoke(() =>
        {
            _warmScheduled = false;
            if (!IsLoaded || Aiming || ActualWidth < 20 || ActualHeight < 20) return;
            _warming = true;
            try { var drawing = new DrawingGroup(); using var context = drawing.Open(); DrawFrame(context); }
            finally { _warming = false; }
        }, DispatcherPriority.ContextIdle);
    }
    private void Subscribe() { if (_subscribed) return; foreach (var slot in _slots) slot.PropertyChanged += Changed; _subscribed = true; }
    private void Unsubscribe() { if (!_subscribed) return; foreach (var slot in _slots) slot.PropertyChanged -= Changed; _subscribed = false; }
    private void Changed(object? sender, PropertyChangedEventArgs e) { UpdateFlow(); InvalidateVisual(); }
    private bool _flowing;
    private void UpdateFlow()
    {
        bool run = IsLoaded && _motionEnabled && SkinCatalog.Current.Id != Skin.Arsenal && SkinCatalog.DecorationsEnabled && _slots.Any(s => s.Connected && s.State is AgentState.Running or AgentState.Waiting);
        if (_flowing == run) return;
        _flowing = run;
        if (!run) { BeginAnimation(FlowProperty, null); return; }
        var flow = new DoubleAnimation(0, 1, TimeSpan.FromSeconds(7)) { RepeatBehavior = RepeatBehavior.Forever };
        Timeline.SetDesiredFrameRate(flow, 24); BeginAnimation(FlowProperty, flow);
    }
    internal void Deploy(bool expanded, bool animate)
    {
        bool useMotion = animate && SkinCatalog.DecorationsEnabled;
        if (IsDeployed == expanded)
        {
            if (!useMotion) { BeginAnimation(DeploymentProperty, null); Deployment = expanded ? 1 : 0; }
            return;
        }
        DeploymentTransitions++;
        IsDeployed = expanded;
        if (!expanded) { Aiming = false; Hover(null); }
        double from = Deployment; BeginAnimation(DeploymentProperty, null); Deployment = expanded ? 1 : 0;
        if (useMotion)
        {
            var animation = new DoubleAnimation(from, Deployment, TimeSpan.FromMilliseconds((expanded ? 115 : 95) * Math.Max(.3, Math.Abs(Deployment - from)))) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
            animation.Completed += (_, _) => { if (IsDeployed == expanded) DeploymentSettled?.Invoke(); };
            Timeline.SetDesiredFrameRate(animation, 120); BeginAnimation(DeploymentProperty, animation);
        }
        InvalidateVisual();
    }
    internal void BeginAim(bool animate) { Aiming = true; Hover(null); Deploy(true, animate); }
    internal int? EndAim(bool confirm)
    {
        int? selected = confirm ? AimCandidate : null; Aiming = false; Hover(null); return selected;
    }
    internal bool Hover(Slot? slot)
    {
        // A few degrees of hysteresis stop tremor at angular boundaries during a gesture.
        if (_hover == slot?.Number) return false;
        RemoveHovered = false;
        int? previous = _hover;
        _hover = slot?.Number;
        void Weight(int? number, double target)
        {
            if (number is not (>= 1 and <= 9)) return;
            var property = HoverWeights[number.Value - 1]; double from = (double)GetValue(property);
            BeginAnimation(property, null); SetValue(property, target);
            if (_motionEnabled && SkinCatalog.DecorationsEnabled)
            {
                var animation = new DoubleAnimation(from, target, TimeSpan.FromMilliseconds(90)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
                Timeline.SetDesiredFrameRate(animation, 120); BeginAnimation(property, animation);
            }
        }
        Weight(previous, 0); Weight(_hover, 1);
        InvalidateVisual(); return slot?.Connected == true;
    }
    internal Slot? AimAt(Point point)
    {
        var v = point - Centre; double radius = v.Length;
        if (radius < 92 || radius > Radius + 90) { Hover(null); return null; }
        double angle = (Math.Atan2(v.X, -v.Y) * 180 / Math.PI + 360) % 360;
        if (_hover is int old)
        {
            double distance = Math.Abs(((angle - (old - 1) * 40 + 540) % 360) - 180);
            if (distance < 23) return _slots.FirstOrDefault(s => s.Number == old);
        }
        int number = (int)((angle + 20) % 360 / 40) + 1;
        var slot = _slots.FirstOrDefault(s => s.Number == number); Hover(slot); return slot;
    }
    internal Slot? HitSlot(Point point, bool duringCapture = false)
    {
        if (duringCapture && InCore(point)) return _slots.FirstOrDefault(s => !s.Occupied);
        if (!IsDeployed) return null;
        if (HitRemove(point) is Slot remove) return remove;
        foreach (var slot in _slots)
        {
            Point p = SlotPoint(slot.Number);
            if (EquipmentCatalog.All.Count == 9) {
                double weaponFactor = Math.Clamp(Radius / 202, .5, 1.12);
                if (Math.Abs(point.X - p.X) <= 44 * weaponFactor + 3 && Math.Abs(point.Y - p.Y) <= 39 * weaponFactor + 3) return slot;
                continue;
            }
            double factor = Math.Clamp(Radius / 202, .82, 1.12);
            if (Math.Abs(point.X - p.X) <= 54 * factor && Math.Abs(point.Y - p.Y) <= 44 * factor) return slot;
        }
        return null;
    }
    internal Point SlotPoint(int number)
    {
        var p = Polar(Radius * .80, (number - 1) * 40); return new Point(Centre.X + p.X, Centre.Y + p.Y);
    }
    internal Point RemovePoint(Slot slot)
    {
        var p = SlotPoint(slot.Number); double f = Math.Clamp(Radius / 202, .5, 1.12);
        return new Point(p.X + 46*f, p.Y - 39*f);
    }
    internal Slot? HitRemove(Point point) => IsDeployed && Deployment > .9 && _slots.FirstOrDefault(s => s.Occupied && s.Number == _hover && (point - RemovePoint(s)).Length <= 11) is Slot slot ? slot : null;
    internal void Pulse(Slot slot, bool animate)
    {
        _lastEquippedId = slot.Id; _pulseNumber = slot.Number;
        BeginAnimation(PhaseProperty, null); Phase = 1;
        if (animate && SkinCatalog.DecorationsEnabled) BeginAnimation(PhaseProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(560)));
        InvalidateVisual();
    }
    private static Point Polar(double radius, double angle) => new(Math.Sin(angle * Math.PI / 180) * radius, -Math.Cos(angle * Math.PI / 180) * radius);
    private static SolidColorBrush B(string color)
    {
        if (BrushesByColor.TryGetValue(color, out var cached)) return cached;
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color)); brush.Freeze();
        if (BrushesByColor.Count > 256) BrushesByColor.Clear(); BrushesByColor[color] = brush; return brush;
    }
    private static Color C(string color) => B(color).Color;
    private static LinearGradientBrush Gradient(string from, string to, double angle, bool fade = false)
    {
        var key = (from, to, angle, fade);
        if (Gradients.TryGetValue(key, out var cached)) return cached;
        Color end = C(to); if (fade) end.A = 0;
        var brush = new LinearGradientBrush(C(from), end, angle); brush.Freeze();
        if (Gradients.Count > 128) Gradients.Clear(); Gradients[key] = brush; return brush;
    }
    private void Text(DrawingContext dc, string value, double x, double y, double size, string color, double width, bool bold = false, int lines = 1)
    {
        var key = new TextKey(value, size, color, width, bold, lines, VisualTreeHelper.GetDpi(this).PixelsPerDip, CultureInfo.CurrentUICulture.Name);
        if (!_textCache.TryGetValue(key, out var drawing))
        {
            var text = new FormattedText(value, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, bold ? BoldTypeface : NormalTypeface, size, B(color), key.Dpi)
            { MaxTextWidth = Math.Max(1, width), MaxLineCount = lines, Trimming = TextTrimming.CharacterEllipsis, TextAlignment = TextAlignment.Center };
            drawing = new DrawingGroup(); using (var context = drawing.Open()) context.DrawText(text, new Point(-width / 2, -text.Height / 2)); drawing.Freeze();
            if (_textCache.Count > 512) _textCache.Clear(); _textCache[key] = drawing; TextBuilds++;
        }
        dc.PushTransform(new TranslateTransform(x, y)); dc.DrawDrawing(drawing); dc.Pop();
    }
    private static Geometry Arc(double radius, double start, double end)
    {
        var g = new StreamGeometry(); using (var p = g.Open()) { p.BeginFigure(Polar(radius, start), false, false); p.ArcTo(Polar(radius, end), new Size(radius, radius), 0, end - start > 180, SweepDirection.Clockwise, true, false); } g.Freeze(); return g;
    }
    private static Geometry Plate(double w, double h)
    {
        if (Plates.TryGetValue((w, h), out var cached)) return cached;
        var geometry = Geometry.Parse(FormattableString.Invariant($"M{-w/2+9},{-h/2} H{w/2-9} L{w/2},{-h/2+9} V{h/2-9} L{w/2-9},{h/2} H{-w/2+9} L{-w/2},{h/2-9} V{-h/2+9} Z")); geometry.Freeze();
        if (Plates.Count > 128) Plates.Clear(); Plates[(w, h)] = geometry; return geometry;
    }
    protected override void OnRender(DrawingContext dc)
    {
        if (!MeasureDrawing) { DrawFrame(dc); DrawRemove(dc); return; }
        long allocated = GC.GetAllocatedBytesForCurrentThread(), started = Stopwatch.GetTimestamp();
        DrawFrame(dc);
        DrawRemove(dc);
        DrawTimes.Add(Stopwatch.GetElapsedTime(started).TotalMilliseconds);
        DrawAllocations.Add(GC.GetAllocatedBytesForCurrentThread() - allocated);
    }
    private void DrawFrame(DrawingContext dc)
    {
        if (_slots.Count == 0 || ActualWidth < 20 || ActualHeight < 20) return;
        DrawWeaponLoadout(dc);
    }
    private void DrawWeaponLoadout(DrawingContext dc)
    {
        var skin = SkinCatalog.Current;
        double d = _warming ? 1 : Math.Clamp(Deployment, 0, 1), f = Math.Clamp(Radius / 202, .5, 1.12);
        dc.PushTransform(new TranslateTransform(Centre.X, Centre.Y));
        if (d > .001) {
            dc.PushOpacity(d);
            foreach (var slot in _slots) {
                double angle = (slot.Number - 1) * 40;
                var p = Polar(60 + (Radius * .8 - 60) * d, angle);
                bool selected = _hover == slot.Number || slot.IsDropTarget, active = slot.IsActive;
                double w = 88 * f, h = 78 * f;
                dc.PushTransform(new TranslateTransform(p.X, p.Y));
                if (!slot.Occupied) {
                    DrawEmptyTarget(dc, slot, selected, f);
                    dc.Pop(); continue;
                }
                double zoom = 1 + .07 * (double)GetValue(HoverWeights[slot.Number - 1]);
                if (SkinCatalog.DecorationsEnabled && skin.Id != Skin.Arsenal) {
                    dc.PushOpacity(selected || active ? .56 : .24);
                    EquipmentPedestal.Draw(dc, skin, new Rect(-w*.4, h/2-3, w*.8, 8));
                    dc.Pop();
                }
                if (SkinCatalog.DecorationsEnabled && slot.Connected && slot.State is AgentState.Running or AgentState.Waiting) {
                    double gleam = .35 + Math.Sin(Flow * Math.PI * 2 + slot.Number) * .18;
                    dc.PushOpacity(gleam);
                    dc.DrawLine(new Pen(B(slot.StateColor), 1), new Point(-w*.16, h/2+2), new Point(w*.16, h/2+2));
                    dc.Pop();
                }
                if (selected || active) {
                    dc.PushOpacity(selected ? .8 : .45);
                    dc.DrawLine(new Pen(B(skin.Accent), 1.2), new Point(-w*.24, h/2+3), new Point(w*.24, h/2+3));
                    dc.Pop();
                }
                EquipmentCatalog.Draw(dc, slot, new Rect(-w*zoom/2, -h*zoom/2, w*zoom, h*zoom), slot.Connected ? selected || active ? 1 : .94 : .55);
                Text(dc, slot.Number.ToString(), -w/2 + 5, h/2 - 3, 11, selected || active ? skin.Accent : skin.Text, 18, true);
                if (slot.Connected && slot.State is AgentState.Waiting or AgentState.Error or AgentState.Ready)
                    Text(dc, slot.State == AgentState.Ready ? "✓" : "!", w/2 - 5, h/2 - 3, 11, slot.StateColor, 16, true);
                dc.Pop();
            }
            dc.Pop();
        }
        // The desktop sees only the character's alpha silhouette, without a badge or backdrop.
        var current = CurrentSlot;
        if (current != null) {
            if (d > .9 && skin.Id != Skin.Arsenal && SkinCatalog.DecorationsEnabled) {
                dc.PushOpacity(.8);
                EquipmentPedestal.Draw(dc, skin, new Rect(-43, 46, 86, 8));
                dc.Pop();
            }
            EquipmentCatalog.Draw(dc, current, new Rect(-55, -55, 110, 110));
            if (current.Connected && current.State is AgentState.Waiting or AgentState.Error or AgentState.Ready) {
                dc.DrawEllipse(B(skin.Background), null, new Point(40, 43), 8, 8);
                Text(dc, current.State == AgentState.Ready ? "✓" : "!", 40, 43, 11, current.StateColor, 14, true);
            }
        }
        else DrawEmptyCore(dc, d);
        dc.Pop();
    }
    private void DrawEmptyCore(DrawingContext dc, double deployment)
    {
        var skin = SkinCatalog.Current;
        // The idle core identifies the game, independently of any empty slot's saved equipment.
        var bounds = deployment > .9 ? new Rect(-55, -64, 110, 100) : new Rect(-55, -55, 110, 110);
        if (!ThemeIdentityArt.DrawCached(dc, skin.Id, bounds))
            NativeSkinArt.Core(dc, skin, new Point(0, -8), 84);
        dc.DrawRoundedRectangle(B(skin.Background), new Pen(B(skin.Border), .7), new Rect(30, 16, 18, 18), 5, 5);
        var plus = new Pen(B(skin.Accent), 1.2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        dc.DrawLine(plus, new Point(35, 25), new Point(43, 25));
        dc.DrawLine(plus, new Point(39, 21), new Point(39, 29));
        if (deployment > .9) Text(dc, "点击空槽添加", 0, 44, 10, skin.Text, 108);
    }
    private void DrawEmptyTarget(DrawingContext dc, Slot slot, bool selected, double f)
    {
        var skin = SkinCatalog.Current; double side = Math.Max(34, 42*f);
        double emphasis = selected ? 1 : CaptureTargetsVisible ? .6 : 0;
        // Retain a filled alpha hit surface without the heavy, opaque tile.
        dc.PushOpacity(.22 + emphasis * .32);
        dc.DrawRoundedRectangle(B(skin.Surface), null, new Rect(-side/2,-side/2,side,side), 10,10);
        dc.Pop();
        dc.PushOpacity(.24 + emphasis * .48);
        dc.DrawRoundedRectangle(null, new Pen(B(emphasis > 0 ? skin.Accent : skin.Muted), .7), new Rect(-side/2,-side/2,side,side), 10,10);
        dc.Pop();
        dc.PushOpacity(.58 + emphasis * .42);
        var plus = new Pen(B(selected ? skin.Accent : skin.Text), 1.1) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        dc.DrawLine(plus, new Point(-5, 0), new Point(5, 0));
        dc.DrawLine(plus, new Point(0, -5), new Point(0, 5));
        Text(dc, slot.Number.ToString(), -side/2+6, -side/2+6, 8, skin.Muted, 12);
        dc.Pop();
    }
    private void DrawRemove(DrawingContext dc)
    {
        if (!IsDeployed || Deployment < .9) return;
        var slot = _slots.FirstOrDefault(s => s.Number == _hover && s.Occupied); if (slot == null) return;
        var p = RemovePoint(slot); var skin = SkinCatalog.Current;
        dc.PushOpacity(RemoveHovered ? .9 : .38);
        dc.DrawEllipse(B(skin.Background), null, p, 10,10);
        dc.Pop();
        dc.PushOpacity(RemoveHovered ? 1 : .6);
        var cross = new Pen(B(RemoveHovered ? skin.Error : skin.Text), 1.1) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        dc.DrawLine(cross, new Point(p.X-3,p.Y-3), new Point(p.X+3,p.Y+3));
        dc.DrawLine(cross, new Point(p.X+3,p.Y-3), new Point(p.X-3,p.Y+3));
        dc.Pop();
    }
}
