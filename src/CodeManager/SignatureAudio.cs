using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace CodeManager;

/// <summary>One identifiable sound per theme. Missing packs stay silent;
/// legacy synthesized event cues are never used as a substitute.</summary>
public static class SignatureAudio
{
    public static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodeManager", "SignatureAudio");
    public static Skin ResolveTheme(Preferences preferences) => preferences.SoundTheme ?? preferences.Skin;
    public static string DefaultPath(Skin skin)
        => ResolveDefaultPath(skin, Root, AppContext.BaseDirectory);
    internal static string ResolveDefaultPath(Skin skin, string installedRoot, string assetRoot)
    {
        string slug = SkinCatalog.Get(skin).Slug;
        string installed = Path.Combine(installedRoot, slug, "signature.wav");
        if (File.Exists(installed)) return installed;
        string bundled = Path.Combine(assetRoot, "skins", "signature-audio", "bundled", slug, "signature.wav");
        return File.Exists(bundled) ? bundled : installed;
    }
    public static string GetPath(Skin skin)
    {
        string custom = Path.Combine(GameAudio.OverrideDirectory(skin), "switch.wav");
        return File.Exists(custom) ? custom : DefaultPath(skin);
    }
    private static readonly Lazy<IReadOnlyDictionary<string, string>> Names = new(ReadNames);
    public static string Description(Skin skin) => Names.Value.TryGetValue(SkinCatalog.Get(skin).Slug, out string? name) ? name : L.T("尚未安装主题标志音，可导入 WAV");
    private static IReadOnlyDictionary<string, string> ReadNames()
    {
        var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var json = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "skins", "signature-audio", "catalog.json")));
            foreach (var sound in json.RootElement.GetProperty("sounds").EnumerateArray())
                if (sound.TryGetProperty("slug", out var slug) && sound.TryGetProperty("name", out var name))
                    names[slug.GetString() ?? ""] = name.GetString() ?? "";
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or KeyNotFoundException) { }
        return names;
    }
}
