using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;

namespace CodeManager;

/// <summary>Localizes application-owned strings only; task names and paths are never rewritten.</summary>
internal static class L
{
    private static readonly Dictionary<string, string> English = Load();
    private static readonly CultureInfo SystemCulture = CultureInfo.CurrentUICulture;
    internal static bool IsEnglish { get; private set; }
    internal static string? Override { get; private set; }

    internal static void Initialize(string[] args)
    {
        Override = args.FirstOrDefault(a => a.StartsWith("--language=", StringComparison.OrdinalIgnoreCase))?.Split('=', 2)[1]
            ?? Environment.GetEnvironmentVariable("OMNIVIBE_LANGUAGE");
        Apply("auto");
    }

    internal static void Apply(string? language)
    {
        string selected = Override ?? language ?? "auto";
        IsEnglish = selected.Equals("en", StringComparison.OrdinalIgnoreCase) ||
            (selected == "auto" && !SystemCulture.TwoLetterISOLanguageName.Equals("zh", StringComparison.OrdinalIgnoreCase));
        CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo(IsEnglish ? "en-US" : "zh-CN");
    }

    internal static string T(string value)
    {
        if (!IsEnglish || string.IsNullOrEmpty(value)) return value;
        if (English.TryGetValue(value, out string? translated)) return translated;
        // A small code-owned menu template embeds these labels. Never apply replacement to user data.
        if (value.StartsWith("<ControlTemplate", StringComparison.Ordinal))
            return value.Replace("关闭 · Esc", "Close · Esc", StringComparison.Ordinal)
                .Replace("快捷操作", "Quick actions", StringComparison.Ordinal);
        return value;
    }

    internal static string F(FormattableString value) =>
        string.Format(CultureInfo.CurrentCulture, T(value.Format), value.GetArguments());

    internal static bool HasTranslation(string value) => English.ContainsKey(value);
    private static Dictionary<string, string> Load()
    {
        using var stream = typeof(L).Assembly.GetManifestResourceStream("OmniVibe.Localization.English");
        if (stream == null) throw new InvalidOperationException("English language resource is missing.");
        using var reader = new StreamReader(stream);
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        while (reader.ReadLine() is string line)
        {
            int tab = line.IndexOf('\t');
            if (tab < 0) continue;
            string key = line[..tab].Replace("\\n", "\n", StringComparison.Ordinal);
            string value = line[(tab + 1)..].Replace("\\n", "\n", StringComparison.Ordinal);
            if (!result.TryAdd(key, value)) throw new InvalidOperationException("Duplicate translation key: " + key);
        }
        return result;
    }
}
