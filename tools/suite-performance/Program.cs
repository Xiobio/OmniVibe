using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Media.Imaging;
using CodeManager;

internal static class Program
{
    [STAThread] private static int Main(string[] args)
    {
        string output = Path.GetFullPath(args.Length == 0 ? "artifacts/suite-performance/report.json" : args[0]);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        try
        {
            var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n }).ToArray();
            EquipmentCatalog.EnsureDefaults(slots);
            long beforePrivate = Memory();
            var timer = Stopwatch.StartNew();
            foreach (var slot in slots) Touch(EquipmentCatalog.Image(slot, Skin.Arsenal));
            double firstLoad = timer.Elapsed.TotalMilliseconds;
            object firstTheme = Cache();
            long afterFirstPrivate = Memory();
            var latencies = new List<double>();
            long allocated = GC.GetAllocatedBytesForCurrentThread();
            for (int round = 0; round < 100; round++)
                foreach (var slot in slots)
                {
                    long started = Stopwatch.GetTimestamp();
                    if (EquipmentCatalog.Image(slot, Skin.Arsenal) == null) throw new Exception("An entity failed to decode");
                    latencies.Add(Stopwatch.GetElapsedTime(started).TotalMilliseconds);
                }
            long warmAllocated = GC.GetAllocatedBytesForCurrentThread() - allocated;
            var rotation = new List<object>();
            foreach (var skin in SkinCatalog.All)
            {
                timer.Restart();
                foreach (var slot in slots) Touch(EquipmentCatalog.Image(slot, skin.Id));
                rotation.Add(new { skin = skin.Slug, has_pack = EquipmentCatalog.HasPack(skin.Id), load_ms = timer.Elapsed.TotalMilliseconds });
            }
            latencies.Sort();
            var report = new
            {
                at = DateTimeOffset.UtcNow, original_assets_unchanged = true,
                first_theme = new { load_and_materialize_ms = firstLoad, cache = firstTheme },
                same_theme_warm = new { calls = latencies.Count, median_ms = latencies[latencies.Count / 2], p95_ms = latencies[(int)(latencies.Count * .95)], allocated_bytes_per_call = warmAllocated / (double)latencies.Count },
                all_theme_rotation = rotation, final_cache = Cache(),
                observed_private_bytes = new { before = beforePrivate, after_first_theme = afterFirstPrivate, after_rotation = Memory() },
                limits = "Private bytes include WPF/WIC/JIT and are process observations, not exact texture accounting. Cache pixel bytes estimate retained runtime bitmap surfaces; original PNG files remain full resolution. Timings include decoding/materialization, not native window switching."
            };
            File.WriteAllText(output, JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
            Console.WriteLine(JsonSerializer.Serialize(report)); return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally { app.Shutdown(); }
    }
    private static void Touch(BitmapSource? image)
    {
        if (image == null) throw new Exception("Missing image");
        // Force WIC to materialize the image rather than timing metadata alone.
        int stride = (image.PixelWidth * image.Format.BitsPerPixel + 7) / 8;
        image.CopyPixels(new byte[stride * image.PixelHeight], stride, 0);
    }
    private static object Cache()
    {
        var cache = (IDictionary)typeof(EquipmentCatalog).GetField("Images", BindingFlags.Static | BindingFlags.NonPublic)!.GetValue(null)!;
        var images = cache.Values.Cast<object?>().OfType<BitmapSource>().ToArray();
        return new { entries = images.Length, estimated_pixel_bytes = images.Sum(x => (long)x.PixelWidth * x.PixelHeight * ((x.Format.BitsPerPixel + 7) / 8)), longest_decoded_edge = images.Length == 0 ? 0 : images.Max(x => Math.Max(x.PixelWidth, x.PixelHeight)) };
    }
    private static long Memory() { GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect(); using var process = Process.GetCurrentProcess(); return process.PrivateMemorySize64; }
}
