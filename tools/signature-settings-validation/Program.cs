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
    private static string ProtectedSettingsSnapshot()
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string[] files = {
            Path.Combine(local, "CodeManager", "tasks.json"),
            Path.Combine(local, "OmniVibe", "tasks.json"),
            Path.Combine(local, "Packages", "Microsoft.WindowsTerminal_8wekyb3d8bbwe", "LocalState", "settings.json"),
            Path.Combine(local, "Packages", "Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe", "LocalState", "settings.json"),
            Path.Combine(local, "Microsoft", "Windows Terminal", "settings.json")
        };
        // Store hashes only: never copy commands, sessions or other private settings into evidence.
        return JsonSerializer.Serialize(files.Select((path, index) => new { index, sha256 = File.Exists(path) ? Hash(File.ReadAllBytes(path)) : null }));
    }
    private sealed record WaveEvidence(string Sha256, int SourceRate, int SourceFrames, int PlaybackFrames, double Seconds);
    private static WaveEvidence InspectWave(string path)
    {
        Require(GameAudio.ValidateWave(path, out string error), "Invalid installed signature: " + path + ": " + error);
        byte[] bytes = File.ReadAllBytes(path);
        using var reader = new BinaryReader(new MemoryStream(bytes));
        reader.BaseStream.Position = 12;
        int channels = 0, rate = 0, dataBytes = 0;
        while (reader.BaseStream.Position + 8 <= bytes.Length)
        {
            string id = new(reader.ReadChars(4)); uint length = reader.ReadUInt32(); long start = reader.BaseStream.Position;
            Require(length <= bytes.Length - start, "Truncated signature chunk");
            if (id == "fmt ") { _ = reader.ReadUInt16(); channels = reader.ReadUInt16(); rate = reader.ReadInt32(); }
            else if (id == "data") dataBytes = checked((int)length);
            reader.BaseStream.Position = start + length + (length & 1);
        }
        Require(channels > 0 && rate > 0 && dataBytes > 0, "Signature has no PCM frames");
        int frames = dataBytes / (channels * 2);
        return new WaveEvidence(Hash(bytes), rate, frames, (int)((long)frames * 44100 / rate), frames / (double)rate);
    }
    private static Manager PlaybackManager(AppState state)
    {
        var manager = (Manager)RuntimeHelpers.GetUninitializedObject(typeof(Manager));
        typeof(Manager).GetField("<State>k__BackingField", Private)!.SetValue(manager, state);
        return manager;
    }
    private static object PlayCompleteSignature(Manager manager, Skin expected, WaveEvidence wave, bool followsInterface, string evidenceDirectory)
    {
        string path = SignatureAudio.GetPath(expected);
        var watch = Stopwatch.StartNew();
        Require(!GameAudio.Diagnostics.OutputOpen, "Previous native output did not release");
        Require(SignatureAudio.ResolveTheme(manager.State.Preferences) == expected, "Saved preferences resolved the wrong theme");
        var timeline = new List<object>(); bool completed = false;
        double? openedAtMilliseconds = null;
        double? voiceCompletedAfterMilliseconds = null;
        double expectedDeadlineSeconds = wave.Seconds + 4;
        double observationDeadlineSeconds = Math.Max(16, wave.Seconds * 5 + 4);
        void Sample()
        {
            var d = GameAudio.Diagnostics;
            timeline.Add(new { elapsedMilliseconds = watch.Elapsed.TotalMilliseconds, activeVoices = d.ActiveVoices,
                pendingRequests = d.PendingRequests, outputOpen = d.OutputOpen, cachedSounds = d.CachedSounds,
                actualPath = GameAudio.LastSourcePath, frames = GameAudio.LastSourceFrames, error = GameAudio.LastError });
        }
        try
        {
            GameAudio.Configure(true, .001); watch.Restart(); Call(manager, "PlayCue", AudioCue.Switch, null);
            while (watch.ElapsedMilliseconds < 2000 && (GameAudio.LastSourcePath != path || !GameAudio.Diagnostics.OutputOpen)) Thread.Sleep(2);
            Sample();
            Require(GameAudio.LastSourcePath == path && GameAudio.Diagnostics.OutputOpen && GameAudio.LastError == null,
                "Manager signature did not reach native output for " + expected + ": " + GameAudio.LastError);
            Require(GameAudio.LastSourceFrames == wave.PlaybackFrames, "Native voice did not load the complete signature for " + expected);
            openedAtMilliseconds = watch.Elapsed.TotalMilliseconds;
            double nextSample = 200;
            // Observe beyond the original deadline only to diagnose the actual duration.
            // The original deadline below still fails; no timeout relaxation or Stop.
            while (GameAudio.Diagnostics.OutputOpen && watch.Elapsed.TotalSeconds < observationDeadlineSeconds)
            {
                if (voiceCompletedAfterMilliseconds == null && GameAudio.Diagnostics.ActiveVoices == 0)
                    voiceCompletedAfterMilliseconds = watch.Elapsed.TotalMilliseconds;
                if (watch.Elapsed.TotalMilliseconds >= nextSample) { Sample(); nextSample += 200; }
                Thread.Sleep(2);
            }
            Sample();
            Require(GameAudio.LastError == null && !GameAudio.Diagnostics.OutputOpen && GameAudio.Diagnostics.ActiveVoices == 0 && GameAudio.Diagnostics.PendingRequests == 0,
                "Native playback did not finish and release cleanly for " + expected + "; elapsed " + watch.Elapsed.TotalSeconds.ToString("F3") + " s; voices " + GameAudio.Diagnostics.ActiveVoices + "; pending " + GameAudio.Diagnostics.PendingRequests + "; output " + GameAudio.Diagnostics.OutputOpen + ": " + GameAudio.LastError);
            Require(watch.Elapsed.TotalSeconds <= expectedDeadlineSeconds,
                "Native playback exceeded its original deadline for " + expected + "; WAV " + wave.Seconds.ToString("F3") + " s, voice completed " + voiceCompletedAfterMilliseconds + " ms, endpoint released " + watch.Elapsed.TotalMilliseconds.ToString("F1") + " ms");
            Require(voiceCompletedAfterMilliseconds.HasValue && voiceCompletedAfterMilliseconds.Value >= Math.Max(0, wave.Seconds * 1000 - 80),
                "Native voice ended before the complete signature duration for " + expected);
            double nativeActiveMilliseconds = voiceCompletedAfterMilliseconds!.Value - openedAtMilliseconds!.Value;
            Require(nativeActiveMilliseconds <= wave.Seconds * 1250 + 100,
                "Native playback ran slower than the WAV for " + expected + "; WAV " + wave.Seconds.ToString("F3") + " s, output-open to voice-end " + nativeActiveMilliseconds.ToString("F1") + " ms");
            Require(Hash(File.ReadAllBytes(path)) == wave.Sha256, "Signature changed during playback");
            completed = true;
            return new { skin = expected.ToString(), slug = SkinCatalog.Get(expected).Slug, followsInterface, actualPath = GameAudio.LastSourcePath,
                sha256 = wave.Sha256, sourceRate = wave.SourceRate, sourceFrames = wave.SourceFrames, frames = GameAudio.LastSourceFrames,
                sourceSeconds = wave.Seconds, outputOpenedAfterMilliseconds = openedAtMilliseconds, voiceCompletedAfterMilliseconds, nativeActiveMilliseconds,
                maxNativeActiveMilliseconds = wave.Seconds * 1250 + 100, completedAfterMilliseconds = watch.Elapsed.TotalMilliseconds,
                outputOpened = true, outputReleasedNaturally = true, noPlaybackError = true };
        }
        finally
        {
            Directory.CreateDirectory(evidenceDirectory);
            File.WriteAllText(Path.Combine(evidenceDirectory, SkinCatalog.Get(expected).Slug + (followsInterface ? "-follow.json" : "-explicit.json")),
                JsonSerializer.Serialize(new { passed = completed, skin = expected.ToString(), followsInterface, sha256 = wave.Sha256, expectedFrames = wave.PlaybackFrames,
                    sourceSeconds = wave.Seconds, expectedDeadlineSeconds, observationDeadlineSeconds, openedAtMilliseconds, voiceCompletedAfterMilliseconds,
                    nativeActiveMilliseconds = voiceCompletedAfterMilliseconds - openedAtMilliseconds, maxNativeActiveMilliseconds = wave.Seconds * 1250 + 100,
                    observedAfterMilliseconds = watch.Elapsed.TotalMilliseconds, timeline }, new JsonSerializerOptions { WriteIndented = true }));
        }
    }
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
        string beforeSettings = ProtectedSettingsSnapshot();
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
            Test("classic-signatures-work-offline-and-preserve-installed-precedence", () => {
                var resolve = typeof(SignatureAudio).GetMethod("ResolveDefaultPath", BindingFlags.Static | BindingFlags.NonPublic)!;
                string cache = Path.Combine(isolated, "offline-cache");
                var evidence = new List<object>();
                foreach (Skin skin in new[] { Skin.InkJade, Skin.Midnight, Skin.Cinnabar })
                {
                    string slug = SkinCatalog.Get(skin).Slug;
                    string bundled = Path.Combine(AppContext.BaseDirectory, "skins", "signature-audio", "bundled", slug, "signature.wav");
                    string found = (string)resolve.Invoke(null, new object[] { skin, cache, AppContext.BaseDirectory })!;
                    Require(found == bundled && GameAudio.ValidateWave(found, out _), "Fresh offline install has no valid classic sound: " + slug);
                    string installed = Path.Combine(cache, slug, "signature.wav"); Directory.CreateDirectory(Path.GetDirectoryName(installed)!);
                    File.Copy(bundled, installed);
                    Require((string)resolve.Invoke(null, new object[] { skin, cache, AppContext.BaseDirectory })! == installed, "Existing local signature lost precedence");
                    evidence.Add(new { slug, bundledHash = InspectWave(bundled).Sha256, offlineDefault = true, installedPreserved = true });
                }
                string absent = (string)resolve.Invoke(null, new object[] { Skin.Hextech, cache, AppContext.BaseDirectory })!;
                Require(!File.Exists(absent), "Missing game audio unexpectedly fell back to another theme or legacy cue");
                return new { classics = evidence, missingGameStaysMissing = true, userFilesUntouched = true };
            });
            if (args.Contains("--playback-all")) Test("all-thirteen-signatures-persist-and-play-completely-through-manager", () => {
                var games = SkinCatalog.All.ToArray();
                Require(games.Length == 13, "The signature fixture must cover all thirteen themes");
                using var catalog = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "skins", "signature-audio", "catalog.json")));
                var entries = catalog.RootElement.GetProperty("sounds").EnumerateArray().ToDictionary(x => x.GetProperty("slug").GetString()!, x => x);
                var waves = new Dictionary<Skin, WaveEvidence>();
                // No skips and no synthesized substitute. Preflight every clip before playing any.
                foreach (var game in games)
                {
                    Require(entries.TryGetValue(game.Slug, out var entry) && entry.GetProperty("status").GetString() == "verified", "Missing verified catalog entry for " + game.Slug);
                    string path = SignatureAudio.DefaultPath(game.Id);
                    Require(File.Exists(path), "Missing real installed signature for " + game.Slug + ": " + path);
                    Require(string.Equals(SignatureAudio.GetPath(game.Id), path, StringComparison.OrdinalIgnoreCase), "A user override shadows the real signature for " + game.Slug + "; leave it intact and run this verification on an unshadowed install");
                    var wave = InspectWave(path);
                    Require(string.Equals(wave.Sha256, entry.GetProperty("output_sha256").GetString(), StringComparison.OrdinalIgnoreCase), "Installed signature differs from the verified catalog for " + game.Slug);
                    waves.Add(game.Id, wave);
                }
                var playback = new List<object>();
                foreach (var game in games)
                {
                    var edited = new AudioSettingsPanel(source, () => Skin.InkJade); Select(edited, game.Id);
                    Field<CheckBox>(edited, "_enabled").IsChecked = true;
                    var explicitPreferences = source.Copy(); Require(edited.TryCommit(explicitPreferences, out string error), error);
                    explicitPreferences.Skin = Skin.InkJade; explicitPreferences.SoundVolume = .001;
                    var store = new StateStore(Path.Combine(isolated, "all-playback", game.Slug));
                    store.Save(new AppState { Preferences = explicitPreferences });
                    var state = store.Load(); Require(state.Preferences.SoundTheme == game.Id, "Explicit game selection failed to persist for " + game.Slug);
                    var manager = PlaybackManager(state);
                    playback.Add(PlayCompleteSignature(manager, game.Id, waves[game.Id], false, Path.Combine(output, "playback-all")));

                    var follow = new AudioSettingsPanel(state.Preferences, () => game.Id); Select(follow, null);
                    var followPreferences = state.Preferences.Copy(); Require(follow.TryCommit(followPreferences, out error), error);
                    followPreferences.Skin = game.Id;
                    store.Save(new AppState { Preferences = followPreferences });
                    state = store.Load(); Require(state.Preferences.SoundTheme == null && state.Preferences.Skin == game.Id, "Follow selection failed to persist for " + game.Slug);
                    manager = PlaybackManager(state);
                    playback.Add(PlayCompleteSignature(manager, game.Id, waves[game.Id], true, Path.Combine(output, "playback-all")));
                    Console.WriteLine("PLAYED " + game.Slug + " explicit + follow; SHA256 " + waves[game.Id].Sha256 + "; frames " + waves[game.Id].PlaybackFrames);
                }
                Require(OverrideSnapshot() == beforeOverrides && ProtectedSettingsSnapshot() == beforeSettings, "All-game playback changed real user configuration");
                return new { themes = games.Length, nativePlaybacks = playback.Count, managerConstructorInvoked = false, hooksInstalled = false, volume = .001,
                    installedHashesMatchVerifiedCatalog = true, completeClipsFinishedNaturally = true, playback };
            });
            Require(OverrideSnapshot() == beforeOverrides, "Validation altered a real theme override");
            Require(ProtectedSettingsSnapshot() == beforeSettings, "Validation altered real task or Terminal settings");
            File.WriteAllText(Path.Combine(output, "report.json"), JsonSerializer.Serialize(new { passed = Failures == 0, failures = Failures, groups = Results.Count, at = DateTimeOffset.UtcNow, noManagerOrInputHooks = true, noTerminalWindowsTouched = true, userOverridesUnchanged = true, realTaskAndTerminalSettingsUnchanged = true, protectedSettingsHashes = JsonDocument.Parse(beforeSettings).RootElement, productAssemblySha256 = Hash(File.ReadAllBytes(typeof(GameAudio).Assembly.Location)), playbackAllRequested = args.Contains("--playback-all"), isolatedStateRoot = isolated, results = Results }, new JsonSerializerOptions { WriteIndented = true }));
            return Failures == 0 ? 0 : 1;
        }
        finally { host.Close(); GameAudio.Shutdown(); }
    }
}
