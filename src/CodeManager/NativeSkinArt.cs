using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace CodeManager;

/// <summary>Shared material art with bounded, frozen caches; drawing never loads files.</summary>
internal static class NativeSkinArt
{
    private sealed record Assets(BitmapSource Core, BitmapSource[] Frame);
    private static readonly Dictionary<string, Assets?> Loaded = new();
    private static readonly Dictionary<(string Slug, double W, double H, double Corner), DrawingGroup> Frames = new();
    internal static bool Available(SkinDefinition skin) => Get(skin) != null;
    private static Assets? Get(SkinDefinition skin)
    {
        if (Loaded.TryGetValue(skin.Slug, out var result)) return result;
        Assets? assets = null;
        try
        {
            string folder = Path.Combine(AppContext.BaseDirectory, "skins/native-v2", skin.Slug);
            if (File.Exists(Path.Combine(folder, "core.png")) && File.Exists(Path.Combine(folder, "frame.png")))
            {
                BitmapSource Load(string name)
                {
                    var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad; image.UriSource = new Uri(Path.Combine(folder, name)); image.EndInit(); image.Freeze(); return image;
                }
                var frame = Load("frame.png"); var slices = new BitmapSource[9];
                int[] x = { 0, 96, frame.PixelWidth - 96, frame.PixelWidth }, y = { 0, 96, frame.PixelHeight - 96, frame.PixelHeight };
                for (int row = 0; row < 3; row++) for (int col = 0; col < 3; col++)
                {
                    var crop = new CroppedBitmap(frame, new Int32Rect(x[col], y[row], x[col + 1] - x[col], y[row + 1] - y[row])); crop.Freeze(); slices[row * 3 + col] = crop;
                }
                assets = new Assets(Load("core.png"), slices);
            }
        }
        catch (Exception ex) when (ex is IOException or NotSupportedException or FileFormatException or ArgumentException) { }
        Loaded[skin.Slug] = assets; return assets;
    }
    internal static void Warm(SkinDefinition skin) => Get(skin);
    internal static void Core(DrawingContext dc, SkinDefinition skin, Point centre, double diameter)
    {
        if (Get(skin) is not Assets art) return;
        dc.DrawImage(art.Core, new Rect(centre.X - diameter / 2, centre.Y - diameter / 2, diameter, diameter));
    }
    internal static bool Frame(DrawingContext dc, SkinDefinition skin, Rect bounds, double corner = 26)
    {
        if (bounds.Width < 8 || bounds.Height < 8 || Get(skin) is not Assets art) return false;
        corner = Math.Min(corner, Math.Min(bounds.Width, bounds.Height) / 3);
        var key = (skin.Slug, bounds.Width, bounds.Height, corner);
        if (!Frames.TryGetValue(key, out var drawing))
        {
            drawing = new DrawingGroup();
            using (var context = drawing.Open())
            {
                double[] x = { 0, corner, bounds.Width - corner, bounds.Width }, y = { 0, corner, bounds.Height - corner, bounds.Height };
                for (int row = 0; row < 3; row++) for (int col = 0; col < 3; col++)
                    if (row != 1 || col != 1) context.DrawImage(art.Frame[row * 3 + col], new Rect(x[col], y[row], Math.Max(0, x[col + 1] - x[col]), Math.Max(0, y[row + 1] - y[row])));
            }
            drawing.Freeze(); if (Frames.Count >= 256) Frames.Clear(); Frames[key] = drawing;
        }
        dc.PushTransform(new TranslateTransform(bounds.X, bounds.Y)); dc.DrawDrawing(drawing); dc.Pop(); return true;
    }
}
