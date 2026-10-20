using System.IO;

namespace CodeManager;

/// <summary>Short bundled acoustic cues. Completion always follows the visual
/// skin; an explicit window-switch sound override does not change its identity.</summary>
public static class CompletionAudio
{
    public static string GetPath(Skin skin) => Path.Combine(System.AppContext.BaseDirectory,"skins","completion-audio",SkinCatalog.Get(skin).Slug,"complete.wav");
}
