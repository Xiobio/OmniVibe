// Isolate the production audio engine from concurrent WPF UI work. The enum and
// stable slugs mirror the shared SkinCatalog contract; no fake audio implementation.
namespace CodeManager;
public enum Skin { InkJade, Midnight, Cinnabar, Hextech, Tactical, Protocol, Adventure, Arsenal, Relic, Starlight, Formation, Astral, Wonderland }
public sealed class Preferences { public Skin Skin { get; set; } public Skin? SoundTheme { get; set; } }
public static class SkinCatalog
{
    public sealed record Definition(string Slug);
    public static Definition Get(Skin skin) => new(new[] { "ink-jade", "midnight", "cinnabar", "hextech", "tactical", "protocol", "adventure", "arsenal", "relic", "starlight", "formation", "astral", "wonderland" }[(int)skin]);
}
