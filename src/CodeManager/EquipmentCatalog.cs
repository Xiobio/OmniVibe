using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace CodeManager;

public sealed record EquipmentItem(string Id, string Name, string Kind, string Portrait, string Source = "", string Provenance = "");
public sealed record EquipmentPack(string Skin, string Slug, string Title, string Subtitle, IReadOnlyList<EquipmentItem> Items);
public sealed record EquipmentAssignment(string Id, string Image, string Name, string Selections = "")
{
    public static EquipmentAssignment From(Slot s) => new(s.EquipmentId, s.EquipmentImage, s.EquipmentName, JsonSerializer.Serialize((s.EquipmentSelections ?? new()).OrderBy(x => x.Key).ToDictionary(x => x.Key, x => x.Value)));
    public void Apply(Slot s) {
        s.EquipmentId = Id; s.EquipmentImage = Image; s.EquipmentName = Name;
        if (Selections != "") try { s.EquipmentSelections = JsonSerializer.Deserialize<Dictionary<string, string>>(Selections) ?? new(); } catch (JsonException) { }
        s.Refresh();
    }
}

/// <summary>Real weapon portraits are independent of task titles, processes and slot ordering.</summary>
public static class EquipmentCatalog
{
    private static IReadOnlyList<EquipmentItem> Legacy { get; } = new[] {
        new EquipmentItem("katana", "宁红夜", "角色持武器 · 太刀", "nhy"), new EquipmentItem("greatsword", "妖刀姬", "角色持武器 · 妖刀", "ydj"),
        new EquipmentItem("longsword", "无尘", "角色持武器 · 长剑", "wc"), new EquipmentItem("spear", "岳山", "角色持武器 · 重剑", "ys"),
        new EquipmentItem("dagger", "顾清寒", "角色持武器 · 太刀", "gqh"), new EquipmentItem("staff", "土御门胡桃", "角色持武器 · 伞", "tymht"),
        new EquipmentItem("bow", "殷紫萍", "角色持武器 · 长枪", "yzp"), new EquipmentItem("dualblades", "季莹莹", "角色持武器 · 双刃", "jyy"),
        new EquipmentItem("halberds", "崔三娘", "角色持武器 · 长兵", "csn") };
    private static readonly Dictionary<string, string> SuitePaths = new(StringComparer.Ordinal);
    private static readonly Dictionary<string, EquipmentPack> Packs = LoadPacks();
    private static readonly Dictionary<string, int> EntityIndexes = BuildIndexes();
    private static readonly Dictionary<Skin, EquipmentPack> FallbackPacks = SkinCatalog.All.ToDictionary(s => s.Id, s => new EquipmentPack(s.Id.ToString(), "naraka-legacy", s.Name + " · 兼容配装", "内容包缺失，使用兼容角色；仍可导入自己的图片", Legacy));
    private static readonly Dictionary<string, BitmapSource?> Images = new(StringComparer.OrdinalIgnoreCase);
    private static readonly Dictionary<string, LinkedListNode<string>> ImageNodes = new(StringComparer.OrdinalIgnoreCase);
    private static readonly LinkedList<string> ImageOrder = new();
    private static readonly Dictionary<string, long> FailedImages = new(StringComparer.OrdinalIgnoreCase);
    private static readonly object ImageLock = new();
    private static readonly SemaphoreSlim WarmGate = new(1, 1);
    private const int RuntimeEdge = 512, MaxCachedImages = 72;
    private const long PixelBudget = 48L * 1024 * 1024;
    private static long _pixelBytes;
    public static IReadOnlyList<EquipmentItem> All => Pack(SkinCatalog.Current.Id).Items;
    public static string SuiteRoot => Path.Combine(AppContext.BaseDirectory, "skins", "loadouts", "suites-v1");
    private static Dictionary<string, EquipmentPack> LoadPacks()
    {
        var packs = new Dictionary<string, EquipmentPack>(StringComparer.OrdinalIgnoreCase);
        try {
            string path = Path.Combine(SuiteRoot, "catalog.json"); if (!File.Exists(path)) return packs;
            using var json = JsonDocument.Parse(File.ReadAllText(path));
            foreach (var pack in json.RootElement.GetProperty("packs").EnumerateArray()) {
                string skin = pack.GetProperty("skin").GetString() ?? "";
                if (!Enum.TryParse<Skin>(skin, true, out _)) continue;
                string Value(JsonElement element, string key) => element.TryGetProperty(key, out var value) ? value.GetString() ?? "" : "";
                var items = pack.GetProperty("items").EnumerateArray().Select(item => new EquipmentItem(
                    Value(item, "id"), Value(item, "name"), Value(item, "kind"), Value(item, "image"), Value(item, "source"), Value(item, "provenance"))).ToArray();
                if (items.Length != 9 || items.Any(x => x.Id == "" || x.Name == "" || SuitePath(x.Portrait) == null) || items.Select(x => x.Id).Distinct().Count() != 9) continue;
                packs[skin] = new(skin, Value(pack, "slug"), Value(pack, "title"), Value(pack, "subtitle"), items);
            }
        } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or KeyNotFoundException or ArgumentException) { }
        return packs;
    }
    private static string? SuitePath(string relative)
    {
        if (string.IsNullOrWhiteSpace(relative) || Path.IsPathRooted(relative)) return null;
        if (SuitePaths.TryGetValue(relative, out var cached)) return cached;
        string root = Path.GetFullPath(SuiteRoot) + Path.DirectorySeparatorChar;
        string path = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return null;
        if (SuitePaths.Count < 512) SuitePaths[relative] = path;
        return path;
    }
    private static Dictionary<string, int> BuildIndexes()
    {
        var indexes = new Dictionary<string, int>(StringComparer.Ordinal);
        for (int i = 0; i < Legacy.Count; i++) indexes[Legacy[i].Id] = i;
        foreach (var pack in Packs.Values) for (int i = 0; i < pack.Items.Count; i++) indexes.TryAdd(pack.Items[i].Id, i);
        return indexes;
    }
    public static bool HasPack(Skin skin) => Packs.ContainsKey(skin.ToString());
    public static IReadOnlyList<EquipmentItem> ForSkin(Skin skin) => Pack(skin).Items;
    private static EquipmentPack OriginalPack(Skin skin) => Packs.TryGetValue(skin.ToString(), out var pack) ? pack : FallbackPacks.TryGetValue(skin, out var fallback) ? fallback : FallbackPacks[Skin.InkJade];
    private static readonly Dictionary<Skin, EquipmentPack> EnglishPacks = new();
    public static EquipmentPack Pack(Skin skin)
    {
        var pack = OriginalPack(skin);
        if (!L.IsEnglish) return pack;
        if (EnglishPacks.TryGetValue(skin, out var cached)) return cached;
        string Label(EquipmentItem item) => System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase(item.Id.Replace(pack.Slug + "-", "", StringComparison.Ordinal).Replace('-', ' '));
        return EnglishPacks[skin] = pack with { Title = SkinCatalog.Get(skin).Name, Subtitle = "Choose a task portrait, or import your own image", Items = pack.Items.Select(item => item with { Name = Label(item), Kind = "Task portrait" }).ToArray() };
    }
    public static string CustomRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodeManager", "Loadout");
    public static EquipmentItem Default(int number) => Legacy[Math.Clamp(number - 1, 0, 8)];
    public static EquipmentItem Item(Slot slot, Skin? skin = null)
    {
        Skin id = skin ?? SkinCatalog.Current.Id;
        var pack = Pack(id);
        if (slot.EquipmentSelections?.TryGetValue(id.ToString(), out string? selection) == true)
            for (int i = 0; i < pack.Items.Count; i++) if (pack.Items[i].Id == selection) return pack.Items[i];
        for (int i = 0; i < pack.Items.Count; i++) if (pack.Items[i].Id == slot.EquipmentId) return pack.Items[i];
        return pack.Items[EntityIndexes.TryGetValue(slot.EquipmentId, out int index) ? index : Math.Clamp(slot.Number - 1, 0, 8)];
    }
    public static string Name(Slot slot) => Name(slot, SkinCatalog.Current.Id);
    public static string Name(Slot slot, Skin skin) => string.IsNullOrWhiteSpace(slot.EquipmentImage) || string.IsNullOrWhiteSpace(slot.EquipmentName) ? Item(slot, skin).Name : slot.EquipmentName;
    public static void EnsureDefaults(IEnumerable<Slot> slots)
    {
        foreach (var slot in slots) {
            if (string.IsNullOrWhiteSpace(slot.EquipmentId)) slot.EquipmentId = Default(slot.Number).Id;
            slot.EquipmentImage ??= ""; slot.EquipmentName ??= "";
            slot.EquipmentSelections ??= new();
        }
    }
    private static string? CustomPath(string file)
    {
        // Config stores only a managed filename; never follow an arbitrary URI or external path.
        if (string.IsNullOrWhiteSpace(file) || file != Path.GetFileName(file) || file.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return null;
        return Path.Combine(CustomRoot, file);
    }
    private static BitmapSource? Decode(string path) => DecodeCore(path, false);
    private static BitmapSource? DecodeCore(string path, bool cachedOnly)
    {
        lock (ImageLock)
        {
            if (Images.TryGetValue(path, out var image)) {
                if (ImageNodes.TryGetValue(path, out var node)) { ImageOrder.Remove(node); ImageOrder.AddLast(node); }
                return image;
            }
            if (cachedOnly) return null;
            long now = System.Diagnostics.Stopwatch.GetTimestamp();
            if (FailedImages.TryGetValue(path, out long failed) && System.Diagnostics.Stopwatch.GetElapsedTime(failed, now).TotalSeconds < 5) return null;
        }
        // WIC decoding/materialization never holds the cache lock needed by rendering.
        var result = DecodeFile(path, RuntimeEdge);
        if (result != null) {
            int stride = (result.PixelWidth * result.Format.BitsPerPixel + 7) / 8;
            var pixels = System.Buffers.ArrayPool<byte>.Shared.Rent(stride * result.PixelHeight);
            try { result.CopyPixels(pixels, stride, 0); }
            finally { System.Buffers.ArrayPool<byte>.Shared.Return(pixels); }
        }
        lock (ImageLock)
        {
            if (Images.TryGetValue(path, out var existing)) return existing;
            if (result == null) {
                if (FailedImages.Count >= 96) FailedImages.Clear(); FailedImages[path] = System.Diagnostics.Stopwatch.GetTimestamp(); return null;
            }
            FailedImages.Remove(path);
            long bytes = (long)result.PixelWidth * result.PixelHeight * 4;
            while (ImageOrder.First is { } oldest && (Images.Count >= MaxCachedImages || _pixelBytes + bytes > PixelBudget)) Forget(oldest.Value);
            Images[path] = result; ImageNodes[path] = ImageOrder.AddLast(path); _pixelBytes += bytes;
            return result;
        }
    }
    private static void Forget(string path)
    {
        lock (ImageLock)
        {
            if (Images.Remove(path, out var image) && image != null) _pixelBytes -= (long)image.PixelWidth * image.PixelHeight * 4;
            if (ImageNodes.Remove(path, out var node)) ImageOrder.Remove(node);
            FailedImages.Remove(path);
        }
    }
    private static BitmapSource? DecodeFile(string path, int edge)
    {
        try {
            if (!File.Exists(path) || new FileInfo(path).Length > 20 * 1024 * 1024) return null;
            using var stream = File.OpenRead(path);
            // Read dimensions first, then let WIC decode directly to the display size.
            // A TransformedBitmap retains its full-resolution decoder source.
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
            var frame = decoder.Frames[0];
            if (frame.PixelWidth < 1 || frame.PixelHeight < 1 || (long)frame.PixelWidth * frame.PixelHeight > 32_000_000) return null;
            int width = frame.PixelWidth, height = frame.PixelHeight;
            stream.Position = 0;
            var result = new BitmapImage(); result.BeginInit(); result.CacheOption = BitmapCacheOption.OnLoad;
            if (Math.Max(width, height) > edge) {
                if (width >= height) result.DecodePixelWidth = edge; else result.DecodePixelHeight = edge;
            }
            result.StreamSource = stream; result.EndInit(); result.Freeze(); return result;
        } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException or System.IO.FileFormatException or ArgumentException or InvalidOperationException) { return null; }
    }
    public static BitmapSource? Image(Slot slot) => Image(slot, SkinCatalog.Current.Id);
    public static BitmapSource? Image(Slot slot, Skin skin) => Image(slot, skin, false);
    internal static BitmapSource? Image(Slot slot, Skin skin, bool cachedOnly)
    {
        var custom = CustomPath(slot.EquipmentImage);
        var item = Item(slot, skin);
        var fallback = EntityIndexes.TryGetValue(item.Id, out int index) ? Legacy[index] : Default(slot.Number);
        return (custom == null ? null : DecodeCore(custom, cachedOnly))
            ?? (SuitePath(item.Portrait) is string path ? DecodeCore(path, cachedOnly) : null)
            ?? DecodeCore(Path.Combine(AppContext.BaseDirectory, "skins", "loadouts", "naraka", "characters-v2", fallback.Portrait + ".png"), cachedOnly)
            ?? DecodeCore(Path.Combine(AppContext.BaseDirectory, "skins", "loadouts", "naraka", "assets", fallback.Id + ".png"), cachedOnly);
    }
    internal static Task PrewarmAsync(IEnumerable<Slot> slots, Skin skin, Action? imageReady = null, CancellationToken cancellation = default)
    {
        // Snapshot UI-owned task fields before entering the worker; only paths cross threads.
        var paths = slots.Select(slot => {
            var item = Item(slot, skin);
            var fallback = EntityIndexes.TryGetValue(item.Id, out int index) ? Legacy[index] : Default(slot.Number);
            return new[] { CustomPath(slot.EquipmentImage), SuitePath(item.Portrait),
                Path.Combine(AppContext.BaseDirectory, "skins", "loadouts", "naraka", "characters-v2", fallback.Portrait + ".png"),
                Path.Combine(AppContext.BaseDirectory, "skins", "loadouts", "naraka", "assets", fallback.Id + ".png") };
        }).ToArray();
        return Task.Run(async () => {
            await WarmGate.WaitAsync(cancellation).ConfigureAwait(false);
            try {
                foreach (var choices in paths) {
                    cancellation.ThrowIfCancellationRequested();
                    foreach (var path in choices) if (path != null && Decode(path) != null) break;
                    imageReady?.Invoke();
                }
            }
            finally { WarmGate.Release(); }
        }, cancellation);
    }
    public static bool CustomMissing(Slot slot) => slot.EquipmentImage != "" && (CustomPath(slot.EquipmentImage) is not string path || !File.Exists(path) || Decode(path) == null);
    public static bool BuiltInMissing(Slot slot, Skin? skin = null)
    {
        Skin id = skin ?? SkinCatalog.Current.Id;
        if (!HasPack(id)) return id != Skin.Arsenal;
        string? path = SuitePath(Item(slot, id).Portrait);
        return path == null || !File.Exists(path) || Decode(path) == null;
    }
    public static string Import(string source)
    {
        if (!new[] { ".png", ".jpg", ".jpeg", ".bmp" }.Contains(Path.GetExtension(source).ToLowerInvariant())) throw new InvalidDataException("请选择 PNG、JPG 或 BMP 图片。");
        // Import retains source detail independently of the bounded display cache.
        var image = DecodeFile(source, 2048) ?? throw new InvalidDataException("图片无法读取，或超过 20 MB / 3200 万像素限制。");
        Directory.CreateDirectory(CustomRoot);
        using var buffer = new MemoryStream(); var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(image)); png.Save(buffer);
        byte[] bytes = buffer.ToArray(); string name = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant() + ".png";
        string destination = Path.Combine(CustomRoot, name);
        if (!File.Exists(destination)) File.WriteAllBytes(destination, bytes);
        Forget(destination);
        return name;
    }
    public static string Detail(Slot slot) => Name(slot) + " · " + slot.Number + "\n" + (slot.Occupied ? slot.Tooltip : "空槽位 · 拖入窗口即可绑定") +
        (CustomMissing(slot) ? "\n自定义图片不可用，已显示内置藏品" : "") +
        (BuiltInMissing(slot) && (slot.EquipmentImage == "" || CustomMissing(slot)) ? "\n主题素材缺失或损坏，暂时显示兼容藏品" : "");
    public static void Draw(DrawingContext dc, Slot slot, Rect bounds, double opacity = 1, Skin? skin = null, bool cachedOnly = false)
    {
        var image = Image(slot, skin ?? SkinCatalog.Current.Id, cachedOnly); if (image == null) return;
        DrawImage(dc, image, bounds, opacity);
    }
    internal static bool TryDrawCached(DrawingContext dc, Slot slot, Rect bounds, double opacity = 1)
    {
        var image = Image(slot, SkinCatalog.Current.Id, true);
        if (image == null) return false;
        DrawImage(dc, image, bounds, opacity); return true;
    }
    private static void DrawImage(DrawingContext dc, BitmapSource image, Rect bounds, double opacity)
    {
        double scale = Math.Min(bounds.Width / image.PixelWidth, bounds.Height / image.PixelHeight);
        var rect = new Rect(bounds.X + (bounds.Width - image.PixelWidth * scale) / 2, bounds.Y + (bounds.Height - image.PixelHeight * scale) / 2, image.PixelWidth * scale, image.PixelHeight * scale);
        dc.PushOpacity(opacity); dc.DrawImage(image, rect); dc.Pop();
    }
}
