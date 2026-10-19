using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace CodeManager;

/// <summary>Optional feedback follows the palette and never delays task activation.</summary>
public static class InkEffects
{
    private static readonly List<VisualLease> Visuals = new();
    public static int ActiveVisualCount => Visuals.Count;
    public static void Detent(bool enabled)
    {
        GameAudio.Play(WuxiaTheme.CurrentSkin, AudioCue.Detent, enabled, immersive: true);
    }
    public static void Sound(bool enabled, bool capture = false)
    {
        GameAudio.Play(WuxiaTheme.CurrentSkin, capture ? AudioCue.Capture : AudioCue.Switch, enabled);
    }

    /// <summary>Legacy deterministic PCM export for the original validation harness. Runtime playback uses GameAudio.</summary>
    public static byte[] CreateSound(Skin skin, bool capture = false)
    {
        const int rate = 22050;
        double duration = capture ? .17 : .105;
        int count = (int)(rate * duration);
        var random = new Random(1709 + (int)skin * 137 + (capture ? 5 : 0));
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream, System.Text.Encoding.ASCII, true);
        writer.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + count * 2);
        writer.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt ")); writer.Write(16); writer.Write((short)1); writer.Write((short)1);
        writer.Write(rate); writer.Write(rate * 2); writer.Write((short)2); writer.Write((short)16);
        writer.Write(System.Text.Encoding.ASCII.GetBytes("data")); writer.Write(count * 2);
        double previous = 0, ratio = capture ? .74 : 1;
        for (int i = 0; i < count; i++)
        {
            double t = i / (double)rate, u = t / duration, n = random.NextDouble() * 2 - 1;
            double brightNoise = (n - previous) * .5; previous = n;
            double Tone(double f) => Math.Sin(2 * Math.PI * f * ratio * t);
            // Crystal gear, radio latch, protocol chirp, forged clasp, blade air,
            // stone bowl, skill chime, board token, celestial glass, bamboo.
            double wave = skin switch
            {
                Skin.Hextech => .48 * Tone(980) + .22 * Tone(1470) * Math.Exp(-t * 18) + .16 * Tone(2473),
                Skin.Tactical => (.48 * Tone(490) + .24 * brightNoise) * (Math.Exp(-t * 85) + .65 * Math.Exp(-Math.Pow((t - .036) / .009, 2))),
                Skin.Protocol => .52 * Math.Sin(2 * Math.PI * ratio * (1160 * t - 1650 * t * t)) + .16 * Tone(1740),
                Skin.Adventure => .45 * Tone(195) + .22 * Tone(1187) * Math.Exp(-t * 30) + .17 * brightNoise,
                Skin.Arsenal => .49 * brightNoise * Math.Sin(Math.PI * u) + .28 * Tone(470) + .13 * Tone(1840),
                Skin.Relic => .46 * Tone(330) + .25 * Tone(733) + .13 * Tone(1231) * Math.Exp(-t * 22),
                Skin.Starlight => .42 * Tone(880) + .23 * Tone(1320) + .17 * Tone(1760) * Math.Exp(-t * 13),
                Skin.Formation => .43 * Tone(392) + .22 * Tone(587.33) + .13 * Tone(783.99) + .05 * n,
                Skin.Astral => .44 * Tone(1046.5) + .23 * Tone(1567.98) + .12 * Tone(2638),
                Skin.Wonderland => .49 * Tone(659.25) + .20 * Tone(1318.5) * Math.Exp(-t * 26) + .10 * n * Math.Exp(-t * 45),
                Skin.Midnight => .43 * Tone(740) + .20 * Tone(1108) + .16 * brightNoise,
                Skin.Cinnabar => .45 * Tone(415) + .24 * Tone(830) + .18 * brightNoise,
                _ => .39 * brightNoise + .36 * Tone(capture ? 910 : 2200)
            };
            double envelope = Math.Sin(Math.PI * u) * Math.Exp(-t * (capture ? 13 : 18));
            writer.Write((short)Math.Clamp(Math.Round(wave * envelope * 5700), short.MinValue, short.MaxValue));
        }
        writer.Flush(); return stream.ToArray();
    }

    public static void Sweep(Native.Rect area, double scale, bool enabled, bool capture = false)
    {
        if (!enabled || !SkinCatalog.DecorationsEnabled || !CanShow || !double.IsFinite(scale) || scale <= 0 || area.Right <= area.Left || area.Bottom <= area.Top) return;
        var skin = SkinCatalog.Current;
        double width = (area.Right - area.Left) / scale, height = (area.Bottom - area.Top) / scale;
        var window = Overlay(area.Left / scale, area.Top / scale, width, height);
        var canvas = new Canvas { ClipToBounds = true, IsHitTestVisible = false };
        double bandWidth = skin.Family is "tactical" or "protocol" ? 100 : Math.Min(360, width * .24);
        var group = new Grid { Width = bandWidth, Height = height, Opacity = skin.IsLight ? .19 : .23 };
        var accent = (Color)ColorConverter.ConvertFromString(skin.Secondary);
        group.Background = new LinearGradientBrush(new GradientStopCollection { new(Colors.Transparent, 0), new(Color.FromArgb(30, accent.R, accent.G, accent.B), .42), new(accent, .52), new(Colors.Transparent, 1) }, 0);
        foreach (double y in new[] { .23, .5, .77 })
            group.Children.Add(new FeedbackGlyph(skin) { Width = 58, Height = 58, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, Math.Max(0, height * y - 29), 0, 0) });
        var move = new TranslateTransform(-bandWidth, 0); group.RenderTransform = move;
        canvas.Children.Add(group); window.Content = canvas;
        var duration = TimeSpan.FromMilliseconds(capture ? 210 : 145);
        ShowTransient(window, duration + TimeSpan.FromMilliseconds(25), () =>
        {
            move.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-bandWidth, width, duration) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
            group.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(group.Opacity, 0, duration));
        });
    }

    public static void Ripple(FrameworkElement target)
    {
        if (!SkinCatalog.DecorationsEnabled || !CanShow || !target.IsVisible || target.ActualWidth < 1 || target.ActualHeight < 1) return;
        try
        {
            var scale = PresentationSource.FromVisual(target)?.CompositionTarget?.TransformToDevice.M11 ?? 1;
            var center = target.PointToScreen(new Point(target.ActualWidth / 2, target.ActualHeight / 2));
            var window = Overlay(center.X / scale - 78, center.Y / scale - 78, 156, 156);
            var glyph = new FeedbackGlyph(SkinCatalog.Current) { Width = 112, Height = 112, Opacity = .70, RenderTransformOrigin = new Point(.5, .5) };
            var zoom = new ScaleTransform(.45, .45); glyph.RenderTransform = zoom; window.Content = glyph;
            ShowTransient(window, TimeSpan.FromMilliseconds(345), () =>
            {
                var pulse = new DoubleAnimation(.45, 1.22, TimeSpan.FromMilliseconds(320)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
                zoom.BeginAnimation(ScaleTransform.ScaleXProperty, pulse); zoom.BeginAnimation(ScaleTransform.ScaleYProperty, pulse);
                glyph.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(.70, 0, TimeSpan.FromMilliseconds(320)));
            });
        }
        catch (InvalidOperationException) { /* Target detached during the action. */ }
    }

    private static bool CanShow => Application.Current is { Dispatcher: { } dispatcher } && dispatcher.CheckAccess() && !dispatcher.HasShutdownStarted;
    public static void CancelVisuals()
    {
        if (!CanShow) return;
        foreach (var lease in Visuals.ToArray()) lease.Close();
    }
    private static Window Overlay(double left, double top, double width, double height) => new()
    {
        WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, AllowsTransparency = true,
        Background = Brushes.Transparent, ShowActivated = false, ShowInTaskbar = false,
        Topmost = true, IsHitTestVisible = false, Focusable = false,
        Left = left, Top = top, Width = width, Height = height
    };
    private static void ShowTransient(Window window, TimeSpan lifetime, Action animate)
    {
        while (Visuals.Count >= 3) Visuals[0].Close();
        var lease = new VisualLease(window, lifetime); Visuals.Add(lease);
        try { window.Show(); animate(); lease.Start(); }
        catch (Exception) { lease.Close(); }
    }
    private sealed class VisualLease
    {
        private readonly Window _window;
        private readonly DispatcherTimer _timer;
        private bool _disposed;
        public VisualLease(Window window, TimeSpan duration)
        {
            _window = window; _timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = duration };
            _timer.Tick += Tick; window.Closed += Closed; window.SourceInitialized += Initialized;
        }
        private void Initialized(object? sender, EventArgs e) => Native.Decorate(_window, clickThrough: true);
        private void Tick(object? sender, EventArgs e) => Close();
        private void Closed(object? sender, EventArgs e) => Dispose();
        public void Start() { if (!_disposed) _timer.Start(); }
        public void Close()
        {
            if (_disposed) return;
            try { _window.Close(); } catch (InvalidOperationException) { }
            finally { Dispose(); }
        }
        private void Dispose()
        {
            if (_disposed) return; _disposed = true;
            _timer.Stop(); _timer.Tick -= Tick; _window.Closed -= Closed; _window.SourceInitialized -= Initialized;
            _window.Content = null; Visuals.Remove(this);
        }
    }

    private sealed class FeedbackGlyph(SkinDefinition skin) : FrameworkElement
    {
        protected override void OnRender(DrawingContext dc)
        {
            double unit = Math.Min(ActualWidth, ActualHeight) / 100;
            dc.PushTransform(new ScaleTransform(unit, unit));
            var pen = new Pen(WuxiaTheme.Brush(skin.Accent), 1.25);
            var light = new Pen(WuxiaTheme.Brush(skin.Secondary), 1.6);
            var center = new Point(50, 50);
            void L(double x, double y, double a, double b, bool glow = false) => dc.DrawLine(glow ? light : pen, new Point(x, y), new Point(a, b));
            void Poly(int sides, double radius, double start = 0, Pen? outline = null)
            {
                var shape = new StreamGeometry(); using (var g = shape.Open())
                    for (int i = 0; i < sides; i++) { double a = start + 2 * Math.PI * i / sides; var p = new Point(50 + Math.Cos(a) * radius, 50 + Math.Sin(a) * radius); if (i == 0) g.BeginFigure(p, false, true); else g.LineTo(p, true, false); }
                dc.DrawGeometry(null, outline ?? pen, shape);
            }
            switch (skin.Family)
            {
                case "mechanical": Poly(6, 34); Poly(6, 24, Math.PI / 6, light); dc.DrawEllipse(null, pen, center, 12, 12); break;
                case "tactical":
                    for (int i = 0; i < 4; i++) { dc.PushTransform(new RotateTransform(i * 90, 50, 50)); L(20,38,20,20); L(20,20,38,20); L(17,48,23,48,true); dc.Pop(); } L(38,50,62,50,true); L(50,38,50,62,true); break;
                case "protocol": Poly(4,37,Math.PI/4); L(25,65,65,25,true); L(35,75,75,35,true); break;
                case "equipment":
                    dc.DrawRoundedRectangle(null,pen,new Rect(19,19,62,62),3,3); dc.DrawRoundedRectangle(null,light,new Rect(25,25,50,50),2,2); foreach(var p in new[]{new Point(22,22),new Point(78,22),new Point(22,78),new Point(78,78)}) dc.DrawEllipse(pen.Brush,null,p,2,2); break;
                case "arsenal": Poly(4,34); L(25,77,74,24,true); L(23,26,75,77,true); L(22,65,35,78); L(65,78,79,64); break;
                case "relic": dc.DrawRoundedRectangle(null,pen,new Rect(21,13,58,74),17,17); dc.DrawEllipse(null,light,center,16,21); L(42,50,58,50,true); L(50,39,50,61,true); break;
                case "fantasy": dc.DrawEllipse(null,pen,center,34,34); Poly(4,24,0,light); Poly(4,12,Math.PI/4); break;
                case "formation": dc.DrawRoundedRectangle(null,pen,new Rect(18,18,64,64),14,14); for(int i=0;i<3;i++) for(int j=0;j<3;j++) dc.DrawEllipse(i==j?light.Brush:pen.Brush,null,new Point(33+i*17,33+j*17),2.1,2.1); break;
                case "astral": L(20,66,44,28); L(44,28,75,40); L(44,28,60,76); foreach(var p in new[]{new Point(20,66),new Point(44,28),new Point(75,40),new Point(60,76)}) dc.DrawEllipse(light.Brush,null,p,2.8,2.8); break;
                case "wonderland": dc.DrawEllipse(null,pen,new Point(33,51),18,17); dc.DrawEllipse(null,light,new Point(51,41),17,19); dc.DrawEllipse(null,pen,new Point(68,54),15,14); L(27,70,75,70,true); break;
                default: dc.DrawEllipse(null,pen,center,34,34); dc.DrawEllipse(null,light,center,26,26); Poly(8,40); break;
            }
            dc.Pop();
        }
    }
}
