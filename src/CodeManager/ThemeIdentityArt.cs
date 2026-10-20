using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace CodeManager;

/// <summary>Theme identity is independent of the nine task assignments. No file IO during drawing.</summary>
internal static class ThemeIdentityArt
{
    private static readonly Dictionary<Skin, BitmapSource?> Images = new();
    private static readonly Dictionary<string, string> Files = ReadFiles();
    private static Dictionary<string, string> ReadFiles()
    {
        var files = new Dictionary<string, string>(StringComparer.Ordinal);
        try {
            using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "skins/identities/catalog.json")));
            foreach (var entry in document.RootElement.EnumerateObject())
                if (entry.Value.TryGetProperty("file", out var file) && file.GetString() is string name && name == Path.GetFileName(name) && !Path.IsPathRooted(name)) files[entry.Name] = name;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException) { }
        return files;
    }
    internal static BitmapSource? Image(Skin id)
    {
        if (Images.TryGetValue(id, out var cached)) return cached;
        var skin = SkinCatalog.Get(id);
        string fallback = Path.Combine(AppContext.BaseDirectory, skin.Artwork);
        string file = Files.TryGetValue(skin.Slug, out string? name) ? Path.Combine(AppContext.BaseDirectory, "skins/identities", name) : fallback;
        var image = Decode(file) ?? (file != fallback ? Decode(fallback) : null)
            ?? Decode(Path.Combine(AppContext.BaseDirectory, "skins/native-v2", skin.Slug, "core.png"));
        Images[id] = image; return image;
    }
    private static BitmapSource? Decode(string path)
    {
        try {
            using var stream = File.OpenRead(path);
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
            var frame = decoder.Frames[0];
            int width = frame.PixelWidth, height = frame.PixelHeight;
            if (width < 1 || height < 1 || (long)width * height > 32_000_000) return null;
            stream.Position = 0;
            var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
            if (Math.Max(width, height) > 512) { if (width >= height) image.DecodePixelWidth = 512; else image.DecodePixelHeight = 512; }
            image.StreamSource = stream; image.EndInit(); image.Freeze(); return image;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException or FileFormatException or ArgumentException or InvalidOperationException) { return null; }
    }
    internal static bool DrawCached(DrawingContext dc, Skin id, Rect bounds)
    {
        if (!Images.TryGetValue(id, out var image) || image == null) return false;
        double fit = Math.Min(bounds.Width / image.PixelWidth, bounds.Height / image.PixelHeight);
        double width = image.PixelWidth * fit, height = image.PixelHeight * fit;
        var rect = new Rect(bounds.X + (bounds.Width - width) / 2, bounds.Y + (bounds.Height - height) / 2, width, height);
        dc.PushClip(new RectangleGeometry(rect, 5, 5)); dc.DrawImage(image, rect); dc.Pop(); return true;
    }
}
