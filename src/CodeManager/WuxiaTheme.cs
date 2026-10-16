using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace CodeManager;

public static class WuxiaTheme
{
    public static Skin CurrentSkin { get; private set; }
    public static readonly FontFamily Calligraphy = new("KaiTi, STKaiti, FangSong, SimSun");
    public static readonly FontFamily BodyFont = new("Microsoft YaHei UI, Segoe UI");
    public static Brush Ink { get; private set; } = Brush("#111714");
    public static readonly Brush Ivory = Brush("#E7D8B6"), Bronze = Brush("#A58A53");
    public static readonly Brush Jade = Brush("#82B89B"), Gold = Brush("#D8B56B"), Cinnabar = Brush("#CB6555");
    public static readonly Brush Paper = Texture(false);
    public static DrawingBrush Wood { get; private set; } = (DrawingBrush)Texture(true);
    public static void Apply(Skin skin)
    {
        CurrentSkin = skin;
        Ink = Brush(skin == Skin.Midnight ? "#111827" : skin == Skin.Cinnabar ? "#211516" : "#111714");
        var group = new DrawingGroup(); group.Children.Add(new GeometryDrawing(Texture(true), null, new RectangleGeometry(new Rect(0, 0, 256, 256))));
        group.Children.Add(new GeometryDrawing(new SolidColorBrush(skin == Skin.Midnight ? Color.FromArgb(165, 14, 34, 66) : skin == Skin.Cinnabar ? Color.FromArgb(145, 71, 16, 25) : Color.FromArgb(35, 20, 52, 35)), null, new RectangleGeometry(new Rect(0, 0, 256, 256))));
        Wood = new DrawingBrush(group) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 256, 256), ViewportUnits = BrushMappingMode.Absolute }; Wood.Freeze();
    }
    public static readonly Brush GoldPaper = TintPaper(Color.FromArgb(26, 201, 153, 47)), RedPaper = TintPaper(Color.FromArgb(36, 173, 57, 42));
    private static Brush TintPaper(Color color)
    {
        var group = new DrawingGroup();
        group.Children.Add(new GeometryDrawing(Paper, null, new RectangleGeometry(new Rect(0, 0, 256, 256))));
        group.Children.Add(new GeometryDrawing(new SolidColorBrush(color), null, new RectangleGeometry(new Rect(0, 0, 256, 256))));
        var b = new DrawingBrush(group) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 256, 256), ViewportUnits = BrushMappingMode.Absolute }; b.Freeze(); return b;
    }
    public static string Numeral(int n) => n is >= 1 and <= 9 ? new[] { "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖" }[n - 1] : "零";
    public static SolidColorBrush Brush(string color) { var b = (SolidColorBrush)new BrushConverter().ConvertFromString(color)!; b.Freeze(); return b; }
    private static Brush Texture(bool wood)
    {
        var drawing = new DrawingGroup { ClipGeometry = new RectangleGeometry(new Rect(0, 0, 256, 256)) }; var random = new Random(wood ? 19 : 31);
        using (var dc = drawing.Open())
        {
            dc.DrawRectangle(Brush(wood ? "#211B17" : "#D8C8A5"), null, new Rect(0, 0, 256, 256));
            for (int i = 0; i < (wood ? 95 : 950); i++)
            {
                double x = random.NextDouble() * 256, y = random.NextDouble() * 256;
                var color = Color.FromArgb((byte)random.Next(wood ? 8 : 5, wood ? 35 : 28), wood ? (byte)147 : (byte)84, wood ? (byte)106 : (byte)72, wood ? (byte)58 : (byte)48);
                var pen = new Pen(new SolidColorBrush(color), wood ? .5 : .35);
                dc.DrawLine(pen, new Point(x, y), new Point(x + (wood ? Math.Sin(y) * 5 : random.NextDouble() * 7), wood ? y + 45 + random.Next(90) : y + random.NextDouble() * 3));
            }
            if (!wood)
                for (int i = 0; i < 12; i++) dc.DrawEllipse(new SolidColorBrush(Color.FromArgb(5, 94, 76, 46)), null, new Point(random.Next(256), random.Next(256)), random.Next(8, 45), random.Next(8, 45));
        }
        var brush = new DrawingBrush(drawing) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 256, 256), ViewportUnits = BrushMappingMode.Absolute, Viewbox = new Rect(0, 0, 256, 256), ViewboxUnits = BrushMappingMode.Absolute, Stretch = Stretch.Fill };
        brush.Freeze(); return brush;
    }
}

public sealed class BaguaGlyph : FrameworkElement
{
    public BaguaGlyph() : this(false) { }
    public BaguaGlyph(bool animate)
    {
        IsHitTestVisible = false; RenderTransformOrigin = new Point(.5, .5);
        if (animate)
        {
            var rotation = new RotateTransform(); RenderTransform = rotation;
            rotation.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(100)) { RepeatBehavior = RepeatBehavior.Forever });
        }
    }
    protected override void OnRender(DrawingContext dc)
    {
        double r = Math.Max(1, Math.Min(ActualWidth, ActualHeight) / 2 - 4); var c = new Point(ActualWidth / 2, ActualHeight / 2);
        var pen = new Pen(WuxiaTheme.Bronze, Math.Max(.6, r / 180));
        dc.DrawEllipse(null, pen, c, r, r); dc.DrawEllipse(null, pen, c, r * .75, r * .75); dc.DrawEllipse(null, pen, c, r * .67, r * .67);
        for (int i = 0; i < 8; i++)
        {
            dc.PushTransform(new RotateTransform(i * 45, c.X, c.Y));
            for (int j = 0; j < 3; j++)
            {
                double y = c.Y - r * (.8 + j * .055), width = r * .23, h = Math.Max(1, r * .018);
                if (((i >> j) & 1) == 0) dc.DrawRectangle(WuxiaTheme.Bronze, null, new Rect(c.X - width / 2, y, width, h));
                else { dc.DrawRectangle(WuxiaTheme.Bronze, null, new Rect(c.X - width / 2, y, width * .4, h)); dc.DrawRectangle(WuxiaTheme.Bronze, null, new Rect(c.X + width * .1, y, width * .4, h)); }
            }
            dc.Pop();
        }
        var yin = Geometry.Parse("M 0,-1 A 1,1 0 0 1 0,1 A .5,.5 0 0 1 0,0 A .5,.5 0 0 0 0,-1 Z");
        dc.PushTransform(new MatrixTransform(r * .52, 0, 0, r * .52, c.X, c.Y));
        dc.DrawEllipse(null, new Pen(WuxiaTheme.Bronze, .018), new Point(), 1, 1); dc.DrawGeometry(WuxiaTheme.Bronze, null, yin);
        dc.DrawEllipse(WuxiaTheme.Ink, null, new Point(0, .5), .12, .12); dc.DrawEllipse(WuxiaTheme.Bronze, null, new Point(0, -.5), .12, .12); dc.Pop();
    }
}

public sealed class InkSplash : FrameworkElement
{
    protected override void OnRender(DrawingContext dc)
    {
        var random = new Random(27); var color = new SolidColorBrush(Color.FromArgb(42, 145, 44, 33));
        for (int i = 0; i < 24; i++)
        {
            double x = ActualWidth * (.5 + random.NextDouble() * .5), y = ActualHeight * (.5 + random.NextDouble() * .5);
            dc.DrawEllipse(color, null, new Point(x, y), random.Next(1, 9), random.Next(1, 5));
        }
        dc.DrawGeometry(color, null, Geometry.Parse("M30,60 L41,48 L45,54 L61,30 L60,52 L78,48 L69,65 L96,74 L71,77 L80,94 L61,86 L51,100 L45,77 L19,80 L38,70 Z"));
    }
}

public sealed class InkScenery : FrameworkElement
{
    public bool Translucent { get; set; }
    protected override void OnRender(DrawingContext dc)
    {
        var area = new Rect(0, 0, ActualWidth, ActualHeight);
        var fog = new RadialGradientBrush { Center = new Point(.5, .44), GradientOrigin = new Point(.5, .44), RadiusX = .72, RadiusY = .85 };
        var center = (Color)ColorConverter.ConvertFromString(WuxiaTheme.CurrentSkin == Skin.Midnight ? "#1C2E47" : WuxiaTheme.CurrentSkin == Skin.Cinnabar ? "#42282B" : "#242C24");
        center.A = Translucent ? (byte)180 : (byte)255; fog.GradientStops.Add(new GradientStop(center, 0));
        fog.GradientStops.Add(new GradientStop(Color.FromArgb(Translucent ? (byte)235 : (byte)255, 10, 16, 13), 1)); dc.DrawRectangle(fog, null, area);
        dc.PushOpacity(.055); dc.DrawRectangle(WuxiaTheme.Paper, null, area); dc.Pop();
        var random = new Random(42);
        for (int layer = 0; layer < 4; layer++)
        {
            var geometry = new StreamGeometry();
            using (var ctx = geometry.Open())
            {
                ctx.BeginFigure(new Point(0, ActualHeight), true, true);
                for (int i = 0; i <= 20; i++) ctx.LineTo(new Point(ActualWidth * i / 20, ActualHeight * (.83 + layer * .04) - random.NextDouble() * ActualHeight * .09), true, false);
                ctx.LineTo(new Point(ActualWidth, ActualHeight), true, false);
            }
            dc.DrawGeometry(new SolidColorBrush(Color.FromArgb((byte)(16 + layer * 9), 3, 11, 8)), null, geometry);
        }
        var border = new Pen(new SolidColorBrush(Color.FromArgb(60, 165, 138, 83)), 1);
        dc.DrawRectangle(null, border, new Rect(12, 12, Math.Max(0, ActualWidth - 24), Math.Max(0, ActualHeight - 24)));
        int corner = 0;
        foreach (var p in new[] { new Point(12, 12), new Point(ActualWidth - 12, 12), new Point(ActualWidth - 12, ActualHeight - 12), new Point(12, ActualHeight - 12) })
        {
            dc.PushTransform(new TranslateTransform(p.X, p.Y)); dc.PushTransform(new RotateTransform(corner++ * 90));
            dc.DrawGeometry(null, new Pen(WuxiaTheme.Bronze, 1), Geometry.Parse("M0,0 L22,0 L22,6 L6,6 L6,14 L15,14 L15,10")); dc.Pop(); dc.Pop();
        }
    }
}
