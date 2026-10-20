using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using CodeManager;

internal static class Program
{
    private static readonly List<object> Results = new();
    private static readonly List<object> SignaturePlayback = new();
    private static void Require(bool ok, string message) { if (!ok) throw new InvalidOperationException(message); }
    private static void Until(Func<bool> done, string message, int milliseconds = 1200)
    { var timer = Stopwatch.StartNew(); while (!done() && timer.ElapsedMilliseconds < milliseconds) Thread.Sleep(2); Require(done(), message); }
    private static void Test(string name, Action action) { action(); Results.Add(new { name, passed = true }); }
    private static int Main(string[] args)
    {
        string output = Path.GetFullPath(args.Length == 0 ? "artifacts/game-audio" : args[0]); Directory.CreateDirectory(output);
        string identity = "audio-validation-" + Guid.NewGuid().ToString("N"), source = GameAudio.GetPath(Skin.Hextech, AudioCue.Switch);
        try
        {
            Test("All 182 PCM files decode and have independent hashes", () =>
            {
                var hashes = new HashSet<string>(); int count = 0;
                foreach (Skin skin in Enum.GetValues<Skin>()) foreach (AudioCue cue in Enum.GetValues<AudioCue>())
                {
                    string path = GameAudio.GetPath(skin, cue); Require(File.Exists(path), path);
                    Require(GameAudio.ValidateWave(path, out string error), error);
                    Require(hashes.Add(Convert.ToHexString(SHA256.HashData(GameAudio.ReadCue(skin, cue)))), "Duplicate PCM"); count++;
                }
                Require(count == 182, "Incomplete cue matrix");
            });
            Test("Strict malformed RIFF rejection and safe identity paths", () =>
            {
                string bad = Path.Combine(output, "invalid.wav"); File.WriteAllBytes(bad, new byte[45]);
                Require(!GameAudio.ValidateWave(bad, out _), "Invalid data accepted");
                string sanitized = GameAudio.OverrideDirectory(Skin.Hextech, "../../outside\\audio.wav");
                Require(sanitized.StartsWith(GameAudio.OverrideDirectory(Skin.Hextech) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase), "Unsafe identity path");
                Require(!Path.GetFileName(sanitized).Contains('.'), "Unsafe identity filename");
                string huge = Path.Combine(output, "oversized.wav");
                using (var file = File.Create(huge)) file.SetLength(1_200_001);
                Require(!GameAudio.ValidateWave(huge, out _), "Oversized audio was accepted"); File.Delete(huge);
            });
            Test("User item import, precedence, safe invalid fallback and reset", () =>
            {
                string target = GameAudio.ImportOverride(Skin.Hextech, AudioCue.Switch, source, identity);
                Require(GameAudio.GetPath(Skin.Hextech, AudioCue.Switch, identity) == target, "Item override not selected");
                Require(GameAudio.ReadCue(Skin.Hextech, AudioCue.Switch, identity).SequenceEqual(File.ReadAllBytes(source)), "Import changed PCM");
                File.WriteAllBytes(target, new byte[50]);
                Require(GameAudio.ReadCue(Skin.Hextech, AudioCue.Switch, identity).SequenceEqual(File.ReadAllBytes(source)), "Damaged custom file not safely falling back");
                GameAudio.RemoveOverride(Skin.Hextech, AudioCue.Switch, identity);
                Require(GameAudio.GetPath(Skin.Hextech, AudioCue.Switch, identity) == source, "Reset did not restore built-in");
            });
            Test("Native output opens; calls are nonblocking and bounded; stop cancels voices", () =>
            {
                // Almost silent probe: exercises the real WinMM device without
                // disturbing the user's current terminal or foreground application.
                GameAudio.Play(Skin.Hextech, AudioCue.Ready, true, .001, true);
                Until(() => GameAudio.Diagnostics.OutputOpen && GameAudio.Diagnostics.ActiveVoices > 0, "Native audio output did not start: " + GameAudio.LastError);
                var timer = Stopwatch.StartNew();
                for (int i = 0; i < 1000; i++) GameAudio.Play((Skin)(i % 13), (AudioCue)(i % 14), true, .001, true, (i % 9).ToString());
                timer.Stop(); Require(timer.ElapsedMilliseconds < 250, "UI call blocked: " + timer.ElapsedMilliseconds);
                Require(GameAudio.Diagnostics.PendingRequests <= 4 && GameAudio.Diagnostics.ActiveVoices <= 4, "Unbounded playback queue");
                GameAudio.Stop(); Until(() => GameAudio.Diagnostics.ActiveVoices == 0 && GameAudio.Diagnostics.PendingRequests == 0 && !GameAudio.Diagnostics.OutputOpen, "Stop did not cancel and release output", 80);
            });
            Test("Quiet mode suppresses hover; disabled master remains silent; explicit audition works", () =>
            {
                GameAudio.Play(Skin.Tactical, AudioCue.Detent, true, .001, false); Thread.Sleep(30);
                Require(GameAudio.Diagnostics.ActiveVoices == 0, "Quiet mode emitted hover sound");
                GameAudio.Play(Skin.Relic, AudioCue.Ready, false, .001, true); Thread.Sleep(30);
                Require(GameAudio.Diagnostics.ActiveVoices == 0 && GameAudio.Diagnostics.PendingRequests == 0, "Disabled playback queued");
                GameAudio.Configure(false, .001, true);
                GameAudio.Play(Skin.Arsenal, AudioCue.Capture, true, .001, true); Thread.Sleep(30);
                Require(GameAudio.Diagnostics.ActiveVoices == 0 && GameAudio.Diagnostics.PendingRequests == 0, "Action enabled flag undid master mute");
                GameAudio.Preview(Skin.Relic, AudioCue.Ready, .001, true);
                Until(() => GameAudio.Diagnostics.ActiveVoices > 0, "Explicit audition did not play");
                GameAudio.Configure(false, .45, true);
                Until(() => GameAudio.Diagnostics.ActiveVoices == 0 && !GameAudio.Diagnostics.OutputOpen, "Mute did not stop audition", 80);
            });
            Test("Natural completion releases idle native device", () =>
            {
                GameAudio.Preview(Skin.Astral, AudioCue.Switch, .001, true);
                Until(() => GameAudio.Diagnostics.OutputOpen, "Idle probe did not open output");
                Until(() => GameAudio.Diagnostics.ActiveVoices == 0 && !GameAudio.Diagnostics.OutputOpen, "Idle device was retained", 2000);
            });
            Test("Unsaved file audition and built-in audition do not import or change overrides", () =>
            {
                string draft = Path.Combine(output, "unsaved-draft.wav"); File.Copy(source, draft, true);
                string builtin = GameAudio.GetPath(Skin.Arsenal, AudioCue.Ready, identity);
                GameAudio.PreviewFile(Skin.Arsenal, AudioCue.Ready, draft, .001, true);
                Until(() => GameAudio.Diagnostics.ActiveVoices > 0, "Unsaved file preview did not start");
                Require(GameAudio.GetPath(Skin.Arsenal, AudioCue.Ready, identity) == builtin, "Draft audition wrote an override");
                GameAudio.Stop(); Until(() => !GameAudio.Diagnostics.OutputOpen, "Draft audition did not stop", 80);
                GameAudio.PreviewBuiltIn(Skin.Arsenal, AudioCue.Ready, .001, true);
                Until(() => GameAudio.Diagnostics.ActiveVoices > 0, "Built-in preview did not start");
                GameAudio.Stop(); Until(() => !GameAudio.Diagnostics.OutputOpen, "Built-in audition did not stop", 80);
                File.Delete(draft);
            });
            Test("Missing signature stays silent instead of playing a synthesized substitute", () =>
            {
                var missing = Enum.GetValues<Skin>().Where(s => !File.Exists(SignatureAudio.GetPath(s))).ToArray();
                Require(missing.Length > 0, "Missing-signature fixture unavailable");
                GameAudio.Configure(true, .001);
                GameAudio.PlaySignature(missing[0], true, .001);
                Until(() => GameAudio.LastError != null, "Missing signature did not report unavailable");
                Require(GameAudio.Diagnostics.ActiveVoices == 0 && !GameAudio.Diagnostics.OutputOpen, "Missing signature played legacy audio");
            });
            Test("Actual signature path changes with theme and plays beyond the former 140 ms truncation", () =>
            {
                var installed = Enum.GetValues<Skin>().Where(s => File.Exists(SignatureAudio.GetPath(s))).Take(2).ToArray();
                Require(installed.Length == 2 && installed.Contains(Skin.Hextech), "Install Heartsteel and at least one other signature before this integration test");
                bool verifiedLong = false;
                foreach (Skin skin in installed)
                {
                    string expected = SignatureAudio.GetPath(skin);
                    Require(GameAudio.ValidateWave(expected, out string error), error);
                    GameAudio.PlaySignature(skin, true, .001);
                    Until(() => GameAudio.LastSourcePath == expected && GameAudio.Diagnostics.OutputOpen, "Wrong signature selected: " + skin);
                    SignaturePlayback.Add(new { skin = skin.ToString(), path = GameAudio.LastSourcePath, frames = GameAudio.LastSourceFrames, sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(expected))).ToLowerInvariant(), volume = .001 });
                    if (GameAudio.LastSourceFrames > 44100 * .3)
                    {
                        Thread.Sleep(180);
                        Require(GameAudio.Diagnostics.ActiveVoices > 0, "Signature was truncated to legacy quiet mode");
                        verifiedLong = true;
                    }
                    GameAudio.Stop(); Until(() => !GameAudio.Diagnostics.OutputOpen && GameAudio.Diagnostics.ActiveVoices == 0, "Signature did not stop", 100);
                }
                Require(verifiedLong, "No signature was long enough to verify removal of quiet-mode truncation");
            });
            Test("Shutdown releases native audio output", () =>
            {
                GameAudio.Shutdown(); Until(() => !GameAudio.Diagnostics.OutputOpen, "Output device leaked on shutdown");
                Require(GameAudio.LastError == null, "Audio output error: " + GameAudio.LastError);
            });
            var report = new { passed = true, suites = Results.Count, legacyDecoderFixtureFiles = 182, nativeOutputExercised = true, signatures = SignaturePlayback, tests = Results };
            File.WriteAllText(Path.Combine(output, "engine-validation.json"), JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
            Console.WriteLine(JsonSerializer.Serialize(report)); return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error); File.WriteAllText(Path.Combine(output, "engine-validation.json"), JsonSerializer.Serialize(new { passed = false, tests = Results, error = error.ToString() })); return 1;
        }
        finally
        {
            GameAudio.Shutdown();
            string target = GameAudio.OverrideDirectory(Skin.Hextech, identity);
            if (Directory.Exists(target)) { foreach (string file in Directory.GetFiles(target)) File.Delete(file); Directory.Delete(target); }
        }
    }
}
