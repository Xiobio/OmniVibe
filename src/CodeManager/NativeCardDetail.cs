using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace CodeManager;

/// <summary>Artwork sits beneath the real DWM preview and never covers its text.</summary>
internal sealed class NativeCardScene : FrameworkElement
{
    private static readonly Dictionary<string, BitmapSource?> Pictures = new();
    private readonly SkinDefinition _skin;
    private readonly BitmapSource? _image;
    internal NativeCardScene(SkinDefinition skin)
    {
        _skin = skin; IsHitTestVisible = false;
        if (Pictures.TryGetValue(skin.Slug, out _image)) return;
        string path = Path.Combine(AppContext.BaseDirectory, skin.Artwork);
        if (!File.Exists(path) && skin.Id == Skin.InkJade) path = Path.Combine(AppContext.BaseDirectory, "themes/windows-terminal/assets/ink-jade-ornate-v2.png");
        try
        {
            if (File.Exists(path)) { var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.DecodePixelWidth = 720; bitmap.UriSource = new Uri(path); bitmap.EndInit(); bitmap.Freeze(); _image = bitmap; }
        }
        catch (Exception ex) when (ex is IOException or NotSupportedException or FileFormatException) { }
        Pictures[skin.Slug] = _image;
    }
    protected override void OnRender(DrawingContext dc)
    {
        if (!SkinCatalog.DecorationsEnabled || _image == null || ActualWidth < 1 || ActualHeight < 1) return;
        var image = new ImageBrush(_image) { Stretch = Stretch.UniformToFill, AlignmentX = AlignmentX.Right };
        var veil = new LinearGradientBrush(); veil.GradientStops.Add(new GradientStop(Color.FromArgb(4, 255, 255, 255), 0)); veil.GradientStops.Add(new GradientStop(Color.FromArgb(_skin.IsLight ? (byte)18 : (byte)42, 255, 255, 255), .8));
        dc.PushOpacityMask(veil); dc.DrawRectangle(image, null, new Rect(0, 0, ActualWidth, ActualHeight)); dc.Pop();
    }
}

internal sealed class NativeNumberPlaque : FrameworkElement
{
    private readonly int _number;
    private readonly SkinDefinition _skin;
    internal NativeNumberPlaque(int number, SkinDefinition skin) { _number = number; _skin = skin; IsHitTestVisible = false; }
    protected override void OnRender(DrawingContext dc)
    {
        double size = Math.Min(ActualWidth, ActualHeight); if (size < 1) return;
        var c = new Point(ActualWidth / 2, ActualHeight / 2);
        dc.DrawEllipse(WuxiaTheme.Brush(_skin.Background), null, c, size * .39, size * .39);
        if (SkinCatalog.DecorationsEnabled) NativeSkinArt.Core(dc, _skin, c, size);
        else dc.DrawEllipse(null, new Pen(WuxiaTheme.Brush(_skin.Accent), .7), c, size * .42, size * .42);
        var text = new FormattedText(_skin.SlotNumber(_number), CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface(_skin.TitleFont, FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal), size * .37, WuxiaTheme.Brush(_skin.Accent), VisualTreeHelper.GetDpi(this).PixelsPerDip);
        dc.DrawText(text, new Point(c.X - text.Width / 2, c.Y - text.Height / 2));
    }
}
