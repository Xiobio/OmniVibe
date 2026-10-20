using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Xml.Linq;
using CodeManager;

internal static class Program
{
    private const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    private static readonly List<object> Results = new();
    private static int Failures;
    private static T Field<T>(object value, string name) => (T)value.GetType().GetField(name, Private)!.GetValue(value)!;
    private static object? Call(object value, string name, params object?[] args) => value.GetType().GetMethod(name, Private)!.Invoke(value, args);
    private static Skin Selected(AudioSettingsPanel panel) => (Skin)typeof(AudioSettingsPanel).GetProperty("SelectedSkin", Private)!.GetValue(panel)!;
    private static void Select(AudioSettingsPanel panel, Skin? skin)
    {
        var choice = Field<ComboBox>(panel, "_theme");
        choice.SelectedItem = choice.Items.OfType<ComboBoxItem>().Single(x => skin.HasValue ? x.Tag is Skin id && id == skin : x.Tag == null);
    }
    private static void Require(bool ok, string text) { if (!ok) throw new InvalidOperationException(text); }
    private static void Test(string name, Func<object> action)
    {
        try { var result = action(); Results.Add(new { name, passed = true, evidence = result }); Console.WriteLine("PASS " + name); }
        catch (Exception error) { Failures++; Results.Add(new { name, passed = false, error = error.ToString() }); Console.WriteLine("FAIL " + name + ": " + error.Message); }
    }
    private static void Pump()
    {
        var frame = new DispatcherFrame(); Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => frame.Continue = false)); Dispatcher.PushFrame(frame);
    }
    private static string Hash(byte[] data) => Convert.ToHexString(SHA256.HashData(data));
    private static Dictionary<string, string?> Overrides() => Enum.GetValues<Skin>().ToDictionary(s => s.ToString(), s => {
        string path = Path.Combine(GameAudio.OverrideDirectory(s), "switch.wav"); return File.Exists(path) ? Hash(File.ReadAllBytes(path)) : null;
    });
    private static string OverrideSnapshot() => JsonSerializer.Serialize(Overrides());
    private static IEnumerable<DependencyObject> Nodes(DependencyObject value)
    {
        yield return value;
        foreach (var child in LogicalTreeHelper.GetChildren(value).OfType<DependencyObject>()) foreach (var node in Nodes(child)) yield return node;
    }
    private static void Capture(FrameworkElement value, string path)
    {
        value.Measure(new Size(620, 720)); value.Arrange(new Rect(0, 0, 620, 720)); value.UpdateLayout();
        var bitmap = new RenderTargetBitmap(620, 720, 96, 96, PixelFormats.Pbgra32); bitmap.Render(value);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var stream = File.Create(path); encoder.Save(stream);
    }

    [STAThread] private static int Main(string[] args)
    {
        string output = Path.GetFullPath("artifacts/signature-settings-validation"); Directory.CreateDirectory(output);
        string isolated = Path.Combine(output, "state-" + Guid.NewGuid().ToString("N"));
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var xaml = XDocument.Load("src/CodeManager/App.xaml"); XNamespace ns = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        app.Resources = (ResourceDictionary)XamlReader.Parse(new XElement(ns + "ResourceDictionary", new XAttribute("xmlns", ns.NamespaceName), new XAttribute(XNamespace.Xmlns + "x", "http://schemas.microsoft.com/winfx/2006/xaml"), xaml.Root!.Element(ns + "Application.Resources")!.Elements()).ToString());
        WuxiaTheme.Apply(Skin.Arsenal, false);
        string beforeOverrides = OverrideSnapshot();
        var source = new Preferences { Skin = Skin.Arsenal, SoundEffects = false, SoundVolume = .35 };
        string before = JsonSerializer.Serialize(source, StateStore.Json);
        Skin previewSkin = Skin.Arsenal;
        var panel = new AudioSettingsPanel(source, () => previewSkin);
        var host = new Window { Content = panel, ShowActivated = false, ShowInTaskbar = false, Width = 660, Height = 760, Left = -10000, Top = -10000 };
        try
        {
            Test("legacy-null-default-follows-current-interface", () => {
                Require(source.SoundTheme == null && Selected(panel) == Skin.Arsenal, "Legacy settings did not follow interface");
                previewSkin = Skin.Hextech; Require(Selected(panel) == Skin.Hextech, "Follow mode was frozen to initial theme");
                var result = source.Copy(); Require(panel.TryCommit(result, out string error), error);
                Require(result.SoundTheme == null, "Follow was saved as a fixed theme");
                return new { nullableDefault = true, followsPreviewSkin = true };
            });
            Test("explicit-selection-survives-hide-show-and-interface-change", () => {
                Select(panel, Skin.Tactical); host.Show(); Pump();
                panel.Visibility = Visibility.Collapsed; Pump(); previewSkin = Skin.Relic; panel.Visibility = Visibility.Visible; Pump();
                Require(Selected(panel) == Skin.Tactical, "Page visibility reset explicit choice");
                Require(Field<ComboBox>(panel, "_theme").SelectedItem is ComboBoxItem { Tag: Skin.Tactical }, "Selected combo item lost");
                return new { selected = Selected(panel).ToString(), pageVisibilityWasToggled = true };
            });
            Test("explicit-theme-roundtrip-restores-on-reopen", () => {
                var result = source.Copy(); Require(panel.TryCommit(result, out string error), error);
                var state = new AppState { Preferences = result }; var store = new StateStore(isolated); store.Save(state);
                var saved = store.Load(); Require(saved.Preferences.SoundTheme == Skin.Tactical, "Sound theme missing from saved JSON");
                var reopened = new AudioSettingsPanel(saved.Preferences, () => Skin.Midnight);
                Require(Selected(reopened) == Skin.Tactical && SignatureAudio.ResolveTheme(saved.Preferences) == Skin.Tactical, "Reopen changed chosen sound theme");
                return new { persisted = saved.Preferences.SoundTheme.ToString(), separateFromInterface = saved.Preferences.Skin.ToString() };
            });
            Test("switching-back-to-follow-persists-null", () => {
                Select(panel, null); Require(Selected(panel) == Skin.Relic, "Follow did not use newly previewed interface");
                var result = source.Copy(); Require(panel.TryCommit(result, out string error), error); result.Skin = previewSkin;
                var store = new StateStore(isolated); store.Save(new AppState { Preferences = result }); var loaded = store.Load().Preferences;
                Require(loaded.SoundTheme == null && SignatureAudio.ResolveTheme(loaded) == Skin.Relic, "Persisted follow mode did not resolve interface");
                return new { nullPersists = true, resolved = SignatureAudio.ResolveTheme(loaded).ToString() };
            });
            Test("invalid-saved-sound-enum-normalizes-to-follow", () => {
                var store = new StateStore(Path.Combine(isolated, "invalid")); var state = new AppState(); state.Preferences.SoundTheme = (Skin)999;
                store.Save(state); var loaded = store.Load(); Require(loaded.Preferences.SoundTheme == null && store.LoadWarning == null, "Invalid enum destroyed state instead of normalizing");
                return new { normalized = "follow", taskSlotsPreserved = loaded.Slots.Count };
            });
            Test("one-signature-ui-no-event-or-character-matrix", () => {
                var controls = Nodes(panel).ToArray(); var boxes = controls.OfType<ComboBox>().ToArray(); var buttons = controls.OfType<Button>().Select(b => b.Content as string).ToArray();
                Require(boxes.Length == 1 && boxes[0].Items.Count == 14, "Unexpected range/event selectors");
                Require(controls.OfType<CheckBox>().Count() == 1 && buttons.Length == 4, "Legacy immersive/notification/matrix controls remained");
                Require(buttons.Contains("试听切换音") && buttons.Contains("导入 WAV…") && buttons.Contains("恢复默认声音"), "Signature actions missing");
                Capture(panel, Path.Combine(output, "single-signature-settings.png"));
                return new { themeOptions = 14, audioActions = buttons, screenshot = "artifacts/signature-settings-validation/single-signature-settings.png" };
            });
            Test("cancelled-import-and-reset-drafts-do-not-touch-files", () => {
                string targetBefore = OverrideSnapshot(); var cancelled = new AudioSettingsPanel(source, () => Skin.Hextech);
                Call(cancelled, "QueueOverride", Path.Combine(output, "not-installed.wav"));
                cancelled.Visibility = Visibility.Collapsed; cancelled.Visibility = Visibility.Visible;
                Call(cancelled, "QueueOverride", new object?[] { null });
                Require(OverrideSnapshot() == targetBefore, "Draft import/reset wrote a real override before save");
                Require(JsonSerializer.Serialize(source, StateStore.Json) == before, "Cancelled draft changed source preferences");
                return new { importAndResetDeferred = true, sourceUnchanged = true, userFilesUnchanged = true };
            });
            Test("failed-import-keeps-result-preferences-unchanged", () => {
                var failed = new AudioSettingsPanel(source, () => Skin.Hextech); Select(failed, Skin.Tactical);
                Field<CheckBox>(failed, "_enabled").IsChecked = true; Field<Slider>(failed, "_volume").Value = 95;
                Call(failed, "QueueOverride", Path.Combine(output, "missing-" + Guid.NewGuid().ToString("N") + ".wav"));
                var result = source.Copy(); string original = JsonSerializer.Serialize(result, StateStore.Json);
                Require(!failed.TryCommit(result, out string error) && error != "", "Missing import accepted");
                Require(JsonSerializer.Serialize(result, StateStore.Json) == original, "Failed file transaction partially changed preferences");
                Require(OverrideSnapshot() == beforeOverrides, "Failed transaction changed existing user sound");
                return new { commitRejected = true, preferencesUnchanged = true, overrideBytesUnchanged = true };
            });
            Test("preferences-commit-volume-and-enable-without-mutating-source", () => {
                var edited = new AudioSettingsPanel(source, () => Skin.Arsenal); Select(edited, Skin.Astral);
                Field<CheckBox>(edited, "_enabled").IsChecked = true; Field<Slider>(edited, "_volume").Value = 60;
                var result = source.Copy(); Require(edited.TryCommit(result, out string error), error);
                Require(result.SoundEffects && result.SoundVolume == .6 && result.SoundTheme == Skin.Astral, "Preferences were not committed together");
                Require(JsonSerializer.Serialize(source, StateStore.Json) == before, "Commit mutated caller's source preferences");
                return new { enabled = result.SoundEffects, volume = result.SoundVolume, soundTheme = result.SoundTheme.ToString(), sourceUnchanged = true };
            });
            if (args.Contains("--playback")) Test("saved-theme-reaches-real-manager-and-native-output", () => {
                var edited = new AudioSettingsPanel(source, () => Skin.Relic); Select(edited, Skin.Hextech);
                Field<CheckBox>(edited, "_enabled").IsChecked = true;
                var result = source.Copy(); Require(edited.TryCommit(result, out string error), error);
                result.Skin = Skin.Relic; result.SoundVolume = .001;
                var store = new StateStore(Path.Combine(isolated, "playback")); store.Save(new AppState { Preferences = result });
                var state = store.Load();
                var manager = (Manager)RuntimeHelpers.GetUninitializedObject(typeof(Manager));
                typeof(Manager).GetField("<State>k__BackingField", Private)!.SetValue(manager, state);
                var heard = new List<object>();
                foreach (bool follow in new[] { false, true })
                {
                    if (follow) { state.Preferences.SoundTheme = null; state.Preferences.Skin = Skin.Protocol; }
                    Skin expected = follow ? Skin.Protocol : Skin.Hextech;
                    string path = SignatureAudio.GetPath(expected); Require(File.Exists(path), "Install both Heartsteel and VALORANT signatures for --playback");
                    GameAudio.Configure(true, .001); Call(manager, "PlayCue", AudioCue.Switch, null);
                    var watch = Stopwatch.StartNew();
                    while (watch.ElapsedMilliseconds < 1500 && (GameAudio.LastSourcePath != path || !GameAudio.Diagnostics.OutputOpen)) Thread.Sleep(2);
                    Require(GameAudio.LastSourcePath == path && GameAudio.Diagnostics.OutputOpen, "Saved theme did not reach playback: " + GameAudio.LastError);
                    heard.Add(new { followsInterface = follow, skin = expected.ToString(), actualPath = GameAudio.LastSourcePath, frames = GameAudio.LastSourceFrames });
                    GameAudio.Stop(); watch.Restart(); while (GameAudio.Diagnostics.OutputOpen && watch.ElapsedMilliseconds < 200) Thread.Sleep(2);
                    Require(!GameAudio.Diagnostics.OutputOpen, "Native audio failed to stop");
                }
                return new { managerConstructorInvoked = false, hooksInstalled = false, playback = heard, volume = .001 };
            });
            Require(OverrideSnapshot() == beforeOverrides, "Validation altered a real theme override");
            File.WriteAllText(Path.Combine(output, "report.json"), JsonSerializer.Serialize(new { passed = Failures == 0, failures = Failures, groups = Results.Count, at = DateTimeOffset.UtcNow, noManagerOrInputHooks = true, noTerminalWindowsTouched = true, userOverridesUnchanged = true, isolatedStateRoot = isolated, results = Results }, new JsonSerializerOptions { WriteIndented = true }));
            return Failures == 0 ? 0 : 1;
        }
        finally { host.Close(); GameAudio.Shutdown(); }
    }
}
