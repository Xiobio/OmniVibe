using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows.Media.Imaging;
using CodeManager;

// Diagnostic probes, not product acceptance tests. Findings remain in the report.
// No Manager, global input hooks, user tasks, Terminal settings or audio are opened.
internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        string root = Path.GetFullPath(args.Length > 0 ? args[0] : "artifacts/code-review/probes");
        Directory.CreateDirectory(root);
        var store = new StateStore(Path.Combine(root, "config-fixture"));
        var baseline = new AppState();
        baseline.Slots[0].Window = new() { Title = "review fixture", ProcessName = "fixture", Handle = 0 };
        var corrupted = JsonNode.Parse(JsonSerializer.Serialize(baseline, StateStore.Json))!;
        corrupted["Slots"]![0]!["Window"]!["Title"] = null;
        File.WriteAllText(store.StateFile, corrupted.ToJsonString());
        bool nestedAccepted = false;
        string? nestedError = null;
        try
        {
            var loaded = store.Load();
            nestedAccepted = loaded.Slots[0].Window?.Title == null;
            _ = RecoveryLaunch.ExistingMatch(loaded.Slots[0], loaded.Slots, Array.Empty<WindowIdentity>());
        }
        catch (Exception e) { nestedError = e.GetType().Name; }

        var malformed = new StateStore(Path.Combine(root, "malformed-fixture"));
        File.WriteAllText(malformed.StateFile, "{invalid json");
        var recovered = malformed.Load();
        bool backupCreated = Directory.GetFiles(malformed.Root, "tasks.json.recovery-*").Length > 0;

        var memory = new List<object>();
        string repo = Path.GetFullPath(args.Length > 1 ? args[1] : ".");
        string catalog = Path.Combine(repo, "skins/loadouts/suites-v1/catalog.json");
        if (File.Exists(catalog))
        {
            using var json = JsonDocument.Parse(File.ReadAllText(catalog));
            var images = json.RootElement.GetProperty("packs").EnumerateArray()
                .SelectMany(p => p.GetProperty("items").EnumerateArray())
                .Select(i => Path.GetFullPath(Path.Combine(Path.GetDirectoryName(catalog)!, i.GetProperty("image").GetString()!)))
                .Where(File.Exists).Distinct(StringComparer.OrdinalIgnoreCase).Take(90).ToArray();
            var decode = typeof(EquipmentCatalog).GetMethod("Decode", BindingFlags.NonPublic | BindingFlags.Static)!;
            GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
            long initial = Process.GetCurrentProcess().PrivateMemorySize64;
            long decodedBytes = 0;
            var watch = Stopwatch.StartNew();
            for (int i = 0; i < images.Length; i++)
            {
                var image = decode.Invoke(null, new object[] { images[i] }) as BitmapSource;
                if (image != null)
                {
                    int stride = (image.PixelWidth * image.Format.BitsPerPixel + 7) / 8;
                    image.CopyPixels(new byte[stride * image.PixelHeight], stride, 0);
                    decodedBytes += (long)image.PixelWidth * image.PixelHeight * 4;
                }
                if (i == 8 || i == images.Length - 1)
                {
                    GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
                    using var process = Process.GetCurrentProcess();
                    process.Refresh();
                    memory.Add(new { imagesAttempted = i+1, elapsedMs = watch.Elapsed.TotalMilliseconds,
                        privateMemoryGrowthBytes = process.PrivateMemorySize64-initial,
                        retainedManagedBytes = GC.GetTotalMemory(false), decodedPixelBytesEstimate = decodedBytes });
                }
            }
        }
        var report = new {
            generatedAtUtc = DateTimeOffset.UtcNow,
            malformedJson = new { backupCreated, fallbackHasNineSlots = recovered.Slots.Count == 9, warningPresent = malformed.LoadWarning != null },
            nestedNullTitle = new { acceptedByStateStore = nestedAccepted, recoveryException = nestedError, handledWithoutException = nestedError == null },
            imageDecodePressure = memory,
            limitations = new[] { "Synthetic malformed configuration; not a claim about normal saves", "Standalone image decode process, not product idle memory", "Memory includes WPF/native decoder initialization; timings are machine-specific", "No remote input or authorization bypass assessed" }
        };
        File.WriteAllText(Path.Combine(root, "report.json"), JsonSerializer.Serialize(report, StateStore.Json));
        Console.WriteLine(JsonSerializer.Serialize(report, StateStore.Json));
        return 0;
    }
}
