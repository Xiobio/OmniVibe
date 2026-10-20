using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace CodeManager;

internal static class WheelMotionDiagnostics
{
    internal static void Write(string path)
    {
        WuxiaTheme.Apply(Skin.Hextech);
        var wheel = new DockWeaponWheel();
        wheel.SetSlots(Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Id = "perf-" + n, Name = "项目 " + n + " · API and integration", Window = new() { Title = "fixture" }, Connected = true, IsActive = n == 1, State = AgentState.Unknown }));
        var window = new Window { Width = 460, Height = 450, Content = wheel, Left = -8000, Top = -8000, ShowActivated = false, ShowInTaskbar = false, WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent };
        try
        {
            window.Show(); window.UpdateLayout(); wheel.Deploy(true, false);
            // Measure warm drawing with all nine real portraits present, not placeholders.
            EquipmentCatalog.PrewarmAsync(wheel.Slots, Skin.Hextech).GetAwaiter().GetResult();
            if (wheel.Slots.Any(slot => EquipmentCatalog.Image(slot, Skin.Hextech, true) == null)) throw new InvalidOperationException("Benchmark portraits failed to warm");
            for (int i = 0; i < 210; i++)
            {
                if (i == 30) wheel.MeasureDrawing = true;
                wheel.Deployment = .2 + .8 * Math.Abs(Math.Sin(i * .07));
                wheel.Flow = i / 210d;
                wheel.Hover(wheel.Slots[i / 7 % 9]);
                Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.Render);
                var bitmap = new RenderTargetBitmap(460, 450, 96, 96, PixelFormats.Pbgra32); bitmap.Render(wheel);
            }
            double[] timings = wheel.DrawTimes.OrderBy(t => t).ToArray();
            var report = new { metric = "UI thread drawing-recording time; excludes OS composition, window activation and screenshot encoding", samples = timings.Length, median_ms = timings[timings.Length / 2], p95_ms = timings[(int)(timings.Length * .95)], max_ms = timings[^1], mean_allocated_bytes = wheel.DrawAllocations.Average() };
            string full = Path.GetFullPath(path); Directory.CreateDirectory(Path.GetDirectoryName(full)!); File.WriteAllText(full, JsonSerializer.Serialize(report, StateStore.Json));
        }
        finally { window.Close(); }
    }
}
