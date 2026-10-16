using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;

namespace CodeManager;

/// <summary>Vector materials remain crisp at mixed monitor DPI and work without illustration files.</summary>
public static class SkinMaterials
{
    public static DrawingBrush Create(SkinDefinition s, bool card)
    {
        var drawing = new DrawingGroup { ClipGeometry = new RectangleGeometry(new Rect(0, 0, 256, 256)) };
        var random = new Random(30 + (int)s.Id);
        using (var dc = drawing.Open())
        {
            dc.DrawRectangle(WuxiaTheme.Brush(card ? s.CardBackground : s.Surface), null, new Rect(0, 0, 256, 256));
            var pen = new Pen(WuxiaTheme.Brush(s.Border), .5);
            switch (s.Family)
            {
                case "mechanical":
                    dc.PushOpacity(.15);
                    for (int y = -24; y < 280; y += 48)
                        for (int x = -24; x < 280; x += 42) dc.DrawGeometry(null, pen, Polygon(new Point(x, y + (x % 84 == 18 ? 24 : 0)), 27, 6, 30));
                    dc.Pop(); break;
                case "tactical":
                    dc.PushOpacity(.15);
                    for (int i = 0; i <= 256; i += 16) { dc.DrawLine(pen, new Point(i, 0), new Point(i, 256)); dc.DrawLine(pen, new Point(0, i), new Point(256, i)); }
                    for (int i = 0; i < 80; i++) dc.DrawRectangle(WuxiaTheme.Brush(s.Secondary), null, new Rect(random.Next(256), random.Next(256), 1, 1));
                    dc.Pop(); break;
                case "protocol":
                    dc.PushOpacity(.065);
                    for (int i = -256; i < 512; i += 48) dc.DrawLine(new Pen(WuxiaTheme.Brush(s.Text), 2), new Point(i, 0), new Point(i - 256, 256));
                    dc.Pop(); break;
                case "equipment":
                    dc.PushOpacity(.1);
                    for (int i = 0; i < 700; i++) dc.DrawEllipse(WuxiaTheme.Brush(s.Accent), null, new Point(random.Next(256), random.Next(256)), .6, .6);
                    dc.DrawRectangle(null, new Pen(WuxiaTheme.Brush(s.Accent), 1) { DashStyle = new DashStyle(new[] { 2d, 4d }, 0) }, new Rect(9, 9, 238, 238));
                    dc.Pop(); break;
                case "arsenal":
                    dc.PushOpacity(.13);
                    for (int i = -256; i < 512; i += 11) dc.DrawLine(pen, new Point(i, 0), new Point(i + 128, 256));
                    dc.DrawLine(new Pen(WuxiaTheme.Brush(s.Secondary), 3), new Point(0, 240), new Point(256, 240)); dc.Pop(); break;
                case "relic":
                    dc.PushOpacity(.14);
                    for (int i = 0; i < 400; i++) dc.DrawEllipse(WuxiaTheme.Brush(i % 2 == 0 ? s.Accent : s.Background), null, new Point(random.Next(256), random.Next(256)), random.NextDouble() * 1.5 + .2, .5);
                    for (int i = 0; i < 6; i++) dc.DrawGeometry(null, pen, Geometry.Parse($"M {i * 52},0 l -8,40 14,12 -3,31 8,19"));
                    dc.Pop(); break;
                case "formation":
                    dc.PushOpacity(.13);
                    for (int y = 0; y < 256; y += 64) for (int x = 0; x < 256; x += 64)
                        if ((x + y) % 128 == 0) dc.DrawRectangle(WuxiaTheme.Brush(s.Secondary), null, new Rect(x, y, 64, 64));
                    dc.Pop(); break;
                case "astral":
                    dc.PushOpacity(.16);
                    for (int i = 0; i < 22; i++) dc.DrawEllipse(WuxiaTheme.Brush(s.Accent), null, new Point(random.Next(256), random.Next(256)), .65, .65);
                    dc.Pop(); break;
                case "fantasy":
                    dc.PushOpacity(.09);
                    for (int i = -128; i < 512; i += 64) dc.DrawGeometry(null, pen, Geometry.Parse($"M{i},0 Q{i + 128},128 {i},256"));
                    dc.Pop(); break;
                case "wonderland":
                    dc.PushOpacity(.09);
                    for (int y = 15; y < 300; y += 70) for (int x = -10; x < 300; x += 90)
                        dc.DrawGeometry(null, new Pen(WuxiaTheme.Brush(s.Secondary), 1.4), Geometry.Parse($"M{x},{y} c-12,-8 -6,-19 5,-15 c1,-16 24,-17 29,-3 c17,-4 22,14 8,19 h-27"));
                    dc.Pop(); break;
                default:
                    dc.PushOpacity(.11);
                    for (int i = 0; i < 100; i++) { double x = random.Next(256), y = random.Next(256); dc.DrawLine(pen, new Point(x, y), new Point(x + Math.Sin(y) * 4, y + 50)); }
                    dc.Pop(); break;
            }
            var gloss = new LinearGradientBrush(); gloss.GradientStops.Add(new GradientStop(Color.FromArgb(s.IsLight ? (byte)40 : (byte)8, 255, 255, 255), 0)); gloss.GradientStops.Add(new GradientStop(Colors.Transparent, .4));
            dc.DrawRectangle(gloss, null, new Rect(0, 0, 256, 256));
        }
        var brush = new DrawingBrush(drawing) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 256, 256), ViewportUnits = BrushMappingMode.Absolute, Viewbox = new Rect(0, 0, 256, 256), ViewboxUnits = BrushMappingMode.Absolute, Stretch = Stretch.Fill };
        brush.Freeze(); return brush;
    }

    internal static Geometry Polygon(Point center, double radius, int sides, double phase = -90)
    {
        var geometry = new StreamGeometry();
        using (var ctx = geometry.Open())
            for (int i = 0; i < sides; i++)
            {
                double angle = (phase + i * 360d / sides) * Math.PI / 180;
                var p = new Point(center.X + Math.Cos(angle) * radius, center.Y + Math.Sin(angle) * radius);
                if (i == 0) ctx.BeginFigure(p, true, true); else ctx.LineTo(p, true, false);
            }
        geometry.Freeze(); return geometry;
    }
}

/// <summary>Family-specific architecture and optional edge artwork; no artwork under readable UI text.</summary>
public sealed class SkinBackdrop : FrameworkElement
{
    private readonly SkinDefinition _skin = SkinCatalog.Current;
    private static readonly Dictionary<string, BitmapSource?> ArtworkCache = new();
    public bool Translucent { get; set; }
    public SkinBackdrop() { IsHitTestVisible = false; ClipToBounds = true; }
    protected override void OnRender(DrawingContext dc)
    {
        double w = ActualWidth, h = ActualHeight; if (w < 1 || h < 1) return;
        var s = _skin; var area = new Rect(0, 0, w, h);
        var bg = WuxiaTheme.Brush(s.Background).Clone(); bg.Opacity = Translucent ? .93 : 1;
        dc.DrawRectangle(bg, null, area);
        if (!SkinCatalog.DecorationsEnabled) return;
        dc.PushOpacity(.5); dc.DrawRectangle(SkinMaterials.Create(s, false), null, area); dc.Pop();
        var image = Artwork(s);
        if (image != null)
        {
            dc.PushOpacity(s.IsLight ? .32 : .4);
            var imageBrush = new ImageBrush(image) { Stretch = Stretch.UniformToFill, AlignmentX = AlignmentX.Right, AlignmentY = AlignmentY.Center };
            dc.DrawRectangle(imageBrush, null, area); dc.Pop();
            var clearCenter = new RadialGradientBrush { Center = new Point(.5, .5), GradientOrigin = new Point(.5, .5), RadiusX = .7, RadiusY = .7 };
            var dark = (Color)ColorConverter.ConvertFromString(s.Background); dark.A = 245;
            clearCenter.GradientStops.Add(new GradientStop(dark, 0)); dark.A = 220; clearCenter.GradientStops.Add(new GradientStop(dark, .55)); dark.A = 30; clearCenter.GradientStops.Add(new GradientStop(dark, 1));
            dc.DrawRectangle(clearCenter, null, area);
        }
        var pen = new Pen(WuxiaTheme.Brush(s.Border), 1); var accent = new Pen(WuxiaTheme.Brush(s.Accent), 1.5);
        dc.PushOpacity(.66);
        switch (s.Family)
        {
            case "mechanical":
                DrawGear(dc, new Point(w - 28, h * .72), Math.Min(w, h) * .29, 18, pen);
                DrawGear(dc, new Point(22, h * .24), Math.Min(w, h) * .16, 12, pen);
                foreach (double x in new[] { 18d, w - 18 }) { dc.DrawLine(accent, new Point(x, 48), new Point(x, h - 48)); for (int y = 64; y < h - 48; y += 36) dc.DrawEllipse(WuxiaTheme.Brush(s.Secondary), null, new Point(x, y), 2, 2); }
                break;
            case "tactical":
                for (int i = 24; i < w - 24; i += 12) { double len = i % 60 == 24 ? 10 : 4; dc.DrawLine(pen, new Point(i, 15), new Point(i, 15 + len)); dc.DrawLine(pen, new Point(i, h - 15), new Point(i, h - 15 - len)); }
                for (int i = 48; i < h - 30; i += 16) { dc.DrawLine(pen, new Point(15, i), new Point(i % 64 == 48 ? 24 : 19, i)); dc.DrawLine(pen, new Point(w - 15, i), new Point(w - 20, i)); }
                DrawCrosshair(dc, new Point(w - 54, h - 55), 20, accent); DrawText(dc, "SYS / PARALLEL\nLINK • 09", new Point(30, h - 62), s, 9);
                break;
            case "protocol":
                dc.DrawGeometry(WuxiaTheme.Brush(s.Accent), null, Geometry.Parse($"M0,0 H{w * .2} L{w * .2 - 24},10 H0 Z"));
                dc.DrawGeometry(WuxiaTheme.Brush(s.Accent), null, Geometry.Parse($"M{w},{h} H{w * .78} L{w * .78 + 24},{h - 10} H{w} Z"));
                dc.DrawGeometry(null, accent, Geometry.Parse($"M18,70 V18 H{w * .3} M{w - 18},{h - 70} V{h - 18} H{w * .7}"));
                for (int i = 0; i < 7; i++) dc.DrawLine(new Pen(WuxiaTheme.Brush(s.Accent), 2), new Point(w - 54 + i * 6, 35), new Point(w - 65 + i * 6, 49));
                break;
            case "equipment":
                dc.DrawRoundedRectangle(null, new Pen(WuxiaTheme.Brush(s.Border), 4), new Rect(12, 12, Math.Max(0, w - 24), Math.Max(0, h - 24)), 5, 5);
                var stitch = new Pen(WuxiaTheme.Brush(s.Accent), 1) { DashStyle = new DashStyle(new[] { 2d, 5d }, 0) };
                dc.DrawRoundedRectangle(null, stitch, new Rect(20, 20, Math.Max(0, w - 40), Math.Max(0, h - 40)), 2, 2);
                foreach (var p in Corners(w, h, 19)) { dc.DrawEllipse(WuxiaTheme.Brush(s.Border), new Pen(WuxiaTheme.Brush(s.Accent), .7), p, 5, 5); dc.DrawLine(pen, new Point(p.X - 2, p.Y), new Point(p.X + 2, p.Y)); }
                break;
            case "arsenal":
                foreach (double x in new[] { 17d, w - 17 }) { dc.DrawLine(new Pen(WuxiaTheme.Brush(s.Border), 5), new Point(x, 30), new Point(x, h - 30)); dc.DrawLine(new Pen(WuxiaTheme.Brush(s.Secondary), 1), new Point(x + 4, 35), new Point(x + 4, h - 35)); }
                for (int i = 0; i < 5; i++) { double x = w / 2 + (i - 2) * 22; dc.DrawGeometry(null, accent, Geometry.Parse($"M{x},9 l-6,9 6,8 6,-8 Z")); }
                break;
            case "relic":
                dc.DrawRoundedRectangle(null, new Pen(WuxiaTheme.Brush(s.Border), 3), new Rect(12, 12, Math.Max(0, w - 24), Math.Max(0, h - 24)), 16, 16);
                for (int i = 0; i < 6; i++)
                {
                    double x = 24 + i * (w - 48) / 5;
                    dc.DrawGeometry(null, pen, Geometry.Parse($"M{x - 8},22 h16 v7 h-9 v7 h16 M{x - 8},{h - 22} h16 v-7 h-9 v-7 h16"));
                }
                break;
            case "fantasy":
                dc.DrawGeometry(null, accent, Geometry.Parse($"M18,80 Q18,18 80,18 H{w - 80} Q{w - 18},18 {w - 18},80 M18,{h - 80} Q18,{h - 18} 80,{h - 18} H{w - 80} Q{w - 18},{h - 18} {w - 18},{h - 80}"));
                foreach (var p in Corners(w, h, 25)) dc.DrawGeometry(WuxiaTheme.Brush(s.Secondary), pen, SkinMaterials.Polygon(p, 7, 4));
                break;
            case "formation":
                for (int i = 0; i < 9; i++) { double x = w * .5 + (i - 4) * 28; dc.DrawRoundedRectangle(i == 4 ? WuxiaTheme.Brush(s.Accent) : null, pen, new Rect(x - 8, h - 24, 16, 7), 3, 3); }
                dc.DrawRoundedRectangle(null, pen, new Rect(14, 14, Math.Max(0, w - 28), Math.Max(0, h - 28)), 22, 22);
                break;
            case "astral":
                var center = new Point(w - 35, h * .65);
                for (int i = 0; i < 4; i++) dc.DrawEllipse(null, new Pen(WuxiaTheme.Brush(s.Border), .6), center, 75 + i * 38, 75 + i * 38);
                for (int i = 0; i < 10; i++) { double a = i * 2.39996, r = 60 + i * 18; var p = new Point(center.X + Math.Cos(a) * r, center.Y + Math.Sin(a) * r); dc.DrawGeometry(WuxiaTheme.Brush(s.Accent), null, SkinMaterials.Polygon(p, i % 3 == 0 ? 4 : 2, 4)); }
                dc.DrawRoundedRectangle(null, pen, new Rect(16, 16, Math.Max(0, w - 32), Math.Max(0, h - 32)), 8, 8);
                break;
            case "wonderland":
                dc.DrawRoundedRectangle(null, new Pen(WuxiaTheme.Brush(s.Secondary), 3), new Rect(13, 13, Math.Max(0, w - 26), Math.Max(0, h - 26)), 23, 23);
                dc.DrawRoundedRectangle(null, accent, new Rect(19, 19, Math.Max(0, w - 38), Math.Max(0, h - 38)), 18, 18);
                foreach (var p in Corners(w, h, 24)) { dc.DrawEllipse(WuxiaTheme.Brush(s.Accent), null, p, 4, 4); dc.DrawEllipse(WuxiaTheme.Brush(s.Background), null, p, 2, 2); }
                break;
            default:
                dc.DrawRectangle(null, pen, new Rect(13, 13, Math.Max(0, w - 26), Math.Max(0, h - 26)));
                break;
        }
        dc.Pop();
    }

    private static BitmapSource? Artwork(SkinDefinition s)
    {
        if (ArtworkCache.TryGetValue(s.Slug, out var cached)) return cached;
        string path = Path.Combine(AppContext.BaseDirectory, "skins", s.Slug, "illustration.png");
        BitmapSource? result = null;
        try { if (File.Exists(path)) { var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad; image.UriSource = new Uri(path); image.DecodePixelWidth = 1600; image.EndInit(); image.Freeze(); result = image; } }
        catch (Exception ex) when (ex is IOException or NotSupportedException or FileFormatException or ArgumentException) { }
        ArtworkCache[s.Slug] = result; return result;
    }
    private static Point[] Corners(double w, double h, double n) => new[] { new Point(n, n), new Point(w - n, n), new Point(w - n, h - n), new Point(n, h - n) };
    private static void DrawText(DrawingContext dc, string text, Point p, SkinDefinition s, double size) => dc.DrawText(new FormattedText(text, System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Consolas"), size, WuxiaTheme.Brush(s.Muted), 1), p);
    internal static void DrawCrosshair(DrawingContext dc, Point c, double r, Pen p)
    {
        dc.DrawEllipse(null, p, c, r * .6, r * .6);
        dc.DrawLine(p, new Point(c.X - r, c.Y), new Point(c.X - r * .35, c.Y)); dc.DrawLine(p, new Point(c.X + r * .35, c.Y), new Point(c.X + r, c.Y));
        dc.DrawLine(p, new Point(c.X, c.Y - r), new Point(c.X, c.Y - r * .35)); dc.DrawLine(p, new Point(c.X, c.Y + r * .35), new Point(c.X, c.Y + r));
    }
    internal static void DrawGear(DrawingContext dc, Point c, double r, int count, Pen pen)
    {
        dc.DrawEllipse(null, pen, c, r * .72, r * .72); dc.DrawEllipse(null, pen, c, r * .86, r * .86);
        for (int i = 0; i < count; i++) { dc.PushTransform(new RotateTransform(i * 360d / count, c.X, c.Y)); dc.DrawRectangle(null, pen, new Rect(c.X - r * .055, c.Y - r, r * .11, r * .18)); dc.Pop(); }
    }
}

/// <summary>Original family emblems. Geometry differs per skin, independently of color.</summary>
public sealed class SkinGlyph : FrameworkElement
{
    private readonly SkinDefinition _skin = SkinCatalog.Current;
    public SkinGlyph() : this(false) { }
    public SkinGlyph(bool animate)
    {
        IsHitTestVisible = false; RenderTransformOrigin = new Point(.5, .5);
        if (animate && SkinCatalog.DecorationsEnabled)
        {
            if (_skin.Family is "mechanical" or "tactical" or "astral" or "ink")
            {
                var t = new RotateTransform(); RenderTransform = t;
                double seconds = _skin.Family is "tactical" or "mechanical" ? 45 : 140;
                t.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(seconds)) { RepeatBehavior = RepeatBehavior.Forever });
                Unloaded += (_, _) => t.BeginAnimation(RotateTransform.AngleProperty, null);
            }
            else if (_skin.Family is "formation" or "fantasy")
            {
                var t = new ScaleTransform(); RenderTransform = t;
                var breath = new DoubleAnimation(.96, 1.035, TimeSpan.FromSeconds(3)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase() };
                t.BeginAnimation(ScaleTransform.ScaleXProperty, breath); t.BeginAnimation(ScaleTransform.ScaleYProperty, breath);
                Unloaded += (_, _) => { t.BeginAnimation(ScaleTransform.ScaleXProperty, null); t.BeginAnimation(ScaleTransform.ScaleYProperty, null); };
            }
            else if (_skin.Family is "equipment" or "arsenal" or "wonderland")
            {
                var t = new TranslateTransform(); RenderTransform = t;
                t.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-1.3, 1.3, TimeSpan.FromSeconds(2.2)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase() });
                Unloaded += (_, _) => t.BeginAnimation(TranslateTransform.YProperty, null);
            }
            else
            {
                BeginAnimation(OpacityProperty, new DoubleAnimation(.65, 1, TimeSpan.FromSeconds(_skin.Family == "protocol" ? 1.4 : 3)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
                Unloaded += (_, _) => BeginAnimation(OpacityProperty, null);
            }
        }
    }
    protected override void OnRender(DrawingContext dc)
    {
        if (!SkinCatalog.DecorationsEnabled) return;
        double side = Math.Min(ActualWidth, ActualHeight); if (side <= 0) return;
        var s = _skin; var pen = new Pen(WuxiaTheme.Brush(s.Accent), 1.1);
        var secondary = new Pen(WuxiaTheme.Brush(s.Secondary), 1.2);
        dc.PushTransform(new TranslateTransform((ActualWidth - side) / 2, (ActualHeight - side) / 2));
        dc.PushTransform(new ScaleTransform(side / 100, side / 100));
        var c = new Point(50, 50);
        switch (s.Family)
        {
            case "mechanical":
                SkinBackdrop.DrawGear(dc, c, 45, 12, pen);
                dc.DrawGeometry(null, secondary, SkinMaterials.Polygon(c, 25, 6, 30));
                dc.DrawGeometry(WuxiaTheme.Brush(s.Secondary), pen, Geometry.Parse("M50,26 L64,50 50,74 36,50Z M50,26 V74 M36,50 H64"));
                break;
            case "tactical":
                SkinBackdrop.DrawCrosshair(dc, c, 43, pen);
                dc.DrawEllipse(null, secondary, c, 28, 28);
                dc.DrawGeometry(null, pen, Geometry.Parse("M10,26 V10 H26 M74,10 H90 V26 M90,74 V90 H74 M26,90 H10 V74"));
                dc.DrawLine(pen, c, new Point(79, 24)); dc.DrawEllipse(WuxiaTheme.Brush(s.Accent), null, new Point(69, 64), 3, 3);
                break;
            case "protocol":
                dc.DrawGeometry(null, pen, Geometry.Parse("M27,8 H80 L93,21 V73 L72,93 H20 L7,80 V28Z M23,23 H72 L79,30 V65 L65,79 H28 L21,72 V37"));
                dc.DrawGeometry(WuxiaTheme.Brush(s.Secondary), null, Geometry.Parse("M29,38 H63 L73,48 H46 L35,64 H21Z"));
                break;
            case "equipment":
                dc.DrawGeometry(null, pen, Geometry.Parse("M50,8 L83,22 V53 Q80,80 50,94 Q20,80 17,53 V22Z"));
                dc.DrawGeometry(null, secondary, Geometry.Parse("M50,18 L73,29 V52 Q70,71 50,82 Q30,71 27,52 V29Z"));
                dc.DrawGeometry(WuxiaTheme.Brush(s.Accent), null, Geometry.Parse("M47,26 H53 V54 H64 V60 H53 V73 H47 V60 H36 V54 H47Z"));
                break;
            case "arsenal":
                dc.DrawGeometry(null, pen, SkinMaterials.Polygon(c, 44, 4));
                dc.DrawGeometry(null, secondary, SkinMaterials.Polygon(c, 33, 4));
                dc.DrawGeometry(WuxiaTheme.Brush(s.Accent), null, Geometry.Parse("M24,20 L70,66 65,71 19,25Z M76,20 L30,66 35,71 81,25Z M62,68 L69,61 82,74 75,81Z M31,61 L38,68 25,81 18,74Z"));
                break;
            case "relic":
                dc.DrawGeometry(null, pen, Geometry.Parse("M22,83 V37 Q22,7 50,7 Q78,7 78,37 V83 Z M14,84 H86 V92 H14Z"));
                for (int i = 0; i < 8; i++) { dc.PushTransform(new RotateTransform(i * 45, 50, 49)); dc.DrawEllipse(null, secondary, new Point(50, 33), 5, 15); dc.Pop(); }
                dc.DrawEllipse(WuxiaTheme.Brush(s.Accent), null, new Point(50, 49), 6, 6);
                break;
            case "fantasy":
                dc.DrawGeometry(null, secondary, Geometry.Parse("M50,7 L62,34 90,27 77,52 90,77 62,68 50,93 38,68 10,77 23,52 10,27 38,34Z"));
                dc.DrawGeometry(WuxiaTheme.Brush(s.Accent), pen, SkinMaterials.Polygon(c, 23, 4));
                dc.DrawEllipse(null, pen, c, 35, 35); break;
            case "formation":
                dc.DrawRoundedRectangle(null, pen, new Rect(14, 14, 72, 72), 13, 13);
                for (int y = 0; y < 3; y++) for (int x = 0; x < 3; x++) dc.DrawRoundedRectangle(x == 1 && y == 1 ? WuxiaTheme.Brush(s.Accent) : null, secondary, new Rect(22 + x * 20, 22 + y * 20, 15, 15), 4, 4);
                dc.DrawGeometry(null, pen, Geometry.Parse("M40,4 L50,11 60,4 M40,96 L50,89 60,96")); break;
            case "astral":
                dc.DrawEllipse(null, pen, c, 43, 43); dc.DrawEllipse(null, secondary, c, 29, 29);
                dc.DrawGeometry(null, pen, Geometry.Parse("M50,4 V17 M50,83 V96 M4,50 H17 M83,50 H96"));
                dc.DrawGeometry(WuxiaTheme.Brush(s.Accent), null, Geometry.Parse("M50,14 L58,42 85,50 58,58 50,86 42,58 15,50 42,42Z"));
                dc.DrawGeometry(WuxiaTheme.Brush(s.Secondary), null, SkinMaterials.Polygon(new Point(25, 22), 4, 4)); break;
            case "wonderland":
                dc.DrawGeometry(null, pen, Geometry.Parse("M28,34 Q16,11 36,14 Q50,9 64,14 Q84,11 72,34 Q92,51 81,78 Q74,93 50,92 Q26,93 19,78 Q8,51 28,34Z"));
                dc.DrawGeometry(null, secondary, Geometry.Parse("M26,34 Q50,45 74,34 M32,31 Q50,36 68,31 M50,38 V51"));
                dc.DrawGeometry(WuxiaTheme.Brush(s.Accent), null, SkinMaterials.Polygon(new Point(50, 65), 15, 4));
                dc.DrawEllipse(WuxiaTheme.Brush(s.Secondary), null, new Point(50, 43), 3, 3); break;
            default:
                dc.DrawEllipse(null, pen, c, 43, 43);
                dc.DrawEllipse(null, secondary, c, 29, 29);
                for (int i = 0; i < 8; i++)
                {
                    dc.PushTransform(new RotateTransform(i * 45, 50, 50));
                    for (int j = 0; j < 3; j++)
                    {
                        double y = 10 + j * 3.5;
                        if (((i >> j) & 1) == 0) dc.DrawRectangle(WuxiaTheme.Brush(s.Accent), null, new Rect(44, y, 12, 1.6));
                        else { dc.DrawRectangle(WuxiaTheme.Brush(s.Accent), null, new Rect(44, y, 4.5, 1.6)); dc.DrawRectangle(WuxiaTheme.Brush(s.Accent), null, new Rect(51.5, y, 4.5, 1.6)); }
                    }
                    dc.Pop();
                }
                dc.DrawEllipse(null, pen, c, 22, 22);
                dc.DrawGeometry(WuxiaTheme.Brush(s.Accent), null, Geometry.Parse("M50,28 A22,22 0 0 1 50,72 A11,11 0 0 1 50,50 A11,11 0 0 0 50,28Z"));
                dc.DrawEllipse(WuxiaTheme.Brush(s.Background), null, new Point(50, 61), 3, 3);
                dc.DrawEllipse(WuxiaTheme.Brush(s.Accent), null, new Point(50, 39), 3, 3);
                break;
        }
        dc.Pop(); dc.Pop();
    }
}
