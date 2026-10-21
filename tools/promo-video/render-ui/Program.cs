using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CodeManager;

// Renders native OmniVibe UI at 2x for the promotional video. Uses sample tasks
// only; never reads the user's configuration, windows or sessions.
internal static class Program
{
    private const BindingFlags Any = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
    private const double Scale = 2;
    private static readonly List<Task> Encoding = new();

    private static object? Call(object target, string name, params object?[] args)
    {
        var type = target as Type ?? target.GetType();
        var method = type.GetMethods(Any).First(m => m.Name == name && m.GetParameters().Length == args.Length);
        return method.Invoke(target is Type ? null : target, args);
    }
    private static void Pump(int ms)
    {
        var frame = new DispatcherFrame(); var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(ms) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; }; timer.Start(); Dispatcher.PushFrame(frame);
    }
    private static void Idle() => Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
    private static RenderTargetBitmap Capture(Visual visual, double width, double height)
    {
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(width * Scale), (int)Math.Ceiling(height * Scale), 96 * Scale, 96 * Scale, PixelFormats.Pbgra32);
        bitmap.Render(visual); bitmap.Freeze(); return bitmap;
    }
    private static void Save(BitmapSource bitmap, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        Encoding.Add(Task.Run(() => { var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap)); using var stream = File.Create(path); png.Save(stream); }));
    }

    private static List<Slot> Tasks(bool english)
    {
        string[] names = english
            ? new[] { "web · checkout flow", "api · payments", "tests · e2e suite", "docs · release notes", "infra · deploy", "data · migration" }
            : new[] { "前端 · 结算流程", "接口 · 支付回调", "测试 · 端到端", "文档 · 发布说明", "运维 · 部署脚本", "数据 · 迁移任务" };
        AgentState[] states = { AgentState.Running, AgentState.Waiting, AgentState.Ready, AgentState.Running, AgentState.Unknown, AgentState.Error };
        string[] providers = { "claude", "claude", "codex", "codex", "", "codex" };
        var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Id = "promo-slot-" + n }).ToList();
        for (int i = 0; i < names.Length; i++)
        {
            var s = slots[i];
            s.Name = names[i]; s.Window = new() { ProcessName = "WindowsTerminal", Title = names[i] };
            s.Connected = true; s.State = states[i]; s.AgentProvider = providers[i]; s.IntegrationConnected = providers[i] != "";
            s.Unread = states[i] is AgentState.Waiting or AgentState.Ready or AgentState.Error;
            s.UpdatedAt = DateTimeOffset.UtcNow.AddSeconds(-20 - i * 7);
        }
        slots[0].IsActive = true;
        EquipmentCatalog.EnsureDefaults(slots);
        return slots;
    }

    private static DockWindow Dock(List<Slot> slots)
    {
        var dock = new DockWindow(); dock.SetSlots(slots); dock.SetPreviewLabel(false);
        dock.Width = 460; dock.Height = dock.DesiredDockHeight; dock.Left = -9000; dock.Top = -9000;
        dock.ShowActivated = false; dock.Topmost = false; dock.Show(); dock.UpdateLayout(); Idle();
        return dock;
    }

    [STAThread]
    private static int Main(string[] args)
    {
        string output = Path.GetFullPath(args[0]); string language = args.Length > 1 ? args[1] : "en";
        bool english = language == "en";
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        try
        {
            Call(typeof(Manager).Assembly.GetType("CodeManager.L", true)!, "Apply", language);
            string dir = Path.Combine(output, english ? "en" : "zh");
            var montage = new[] { Skin.Relic, Skin.InkJade, Skin.Midnight, Skin.Cinnabar, Skin.Formation, Skin.Wonderland, Skin.Tactical };

            // Static decks for every theme shown in the montage, deployed and compact.
            foreach (var skin in montage)
            {
                WuxiaTheme.Apply(skin, false); SkinCatalog.DecorationsEnabled = true;
                string slug = SkinCatalog.Get(skin).Slug;
                var slots = Tasks(english);
                var dock = Dock(slots);
                Call(dock, "SetEquipmentDeployment", true, false); dock.UpdateLayout(); Idle(); Pump(120);
                Save(Capture((Visual)dock.Content, dock.Width, dock.Height), Path.Combine(dir, "deck-" + slug + ".png"));
                dock.Close();
            }

            WuxiaTheme.Apply(Skin.Relic, true); SkinCatalog.DecorationsEnabled = true;

            // Capture sequence: the deck as tasks are added one by one.
            for (int filled = 0; filled <= 6; filled++)
            {
                var slots = Tasks(english);
                foreach (var s in slots.Where(s => s.Number > filled)) { s.Window = null; s.Name = ""; s.Connected = s.IsActive = s.Unread = false; s.State = AgentState.Unknown; }
                foreach (var s in slots) s.IsActive = s.Number == Math.Max(1, filled);
                var dock = Dock(slots);
                Call(dock, "SetEquipmentDeployment", true, false); dock.UpdateLayout(); Idle(); Pump(120);
                Save(Capture((Visual)dock.Content, dock.Width, dock.Height), Path.Combine(dir, "fill", filled + ".png"));
                dock.Close();
            }

            // Real-time dock interaction: compact → expand → point at 2 → point at 3 → switch → retract.
            {
                var slots = Tasks(english);
                var dock = Dock(slots);
                var wheel = (DockWeaponWheel)dock.FindName("WeaponWheel");
                var actions = new SortedList<double, Action>
                {
                    [0.9] = () => Call(dock, "SetEquipmentDeployment", true, true),
                    [2.0] = () => Call(wheel, "Hover", slots[1]),
                    [2.8] = () => Call(wheel, "Hover", slots[2]),
                    [3.6] = () => { foreach (var s in slots) { s.IsActive = s.Number == 3; s.Refresh(); } Call(wheel, "Hover", (Slot?)null); dock.Pulse(slots[2], false); },
                    [4.8] = () => Call(dock, "SetEquipmentDeployment", false, true),
                };
                var frames = new List<object>(); var clock = Stopwatch.StartNew(); int index = 0;
                while (clock.Elapsed.TotalSeconds < 6.2)
                {
                    while (actions.Count > 0 && actions.Keys[0] <= clock.Elapsed.TotalSeconds) { actions.Values[0](); actions.RemoveAt(0); }
                    dock.UpdateLayout(); Idle();
                    double at = clock.Elapsed.TotalSeconds;
                    Save(Capture((Visual)dock.Content, dock.Width, dock.Height), Path.Combine(dir, "dock-motion", index.ToString("D3") + ".png"));
                    frames.Add(new { index, at }); index++;
                    Pump(15);
                }
                File.WriteAllText(Path.Combine(dir, "dock-motion", "timing.json"), JsonSerializer.Serialize(frames));
                dock.Close();
            }

            // Radial selector: deterministic frames sweeping 1 → 2 → 3.
            {
                var slots = Tasks(english);
                var radialType = typeof(Manager).Assembly.GetType("CodeManager.RadialInventoryWindow", true)!;
                var radial = (Window)Activator.CreateInstance(radialType, Any, null, new object?[] { slots, new Native.Rect(0, 0, 940, 760), 1.0, false, "Alt+Q", (Func<bool>)(() => true), true }, null)!;
                radial.Left = -9000; radial.Top = -9000; radial.Show(); radial.UpdateLayout(); Idle();
                var surface = radialType.GetProperty("Surface", Any)!.GetValue(radial)!;
                for (int i = 0; i < 90; i++)
                {
                    if (i == 0) Call(surface, "Select", (int?)1);
                    if (i == 30) Call(surface, "Select", (int?)2);
                    if (i == 60) Call(surface, "Select", (int?)3);
                    Call(surface, "SetPhase", i / 30.0);
                    radial.UpdateLayout();
                    Save(Capture((Visual)radial.Content, radial.Width, radial.Height), Path.Combine(dir, "radial", i.ToString("D3") + ".png"));
                }
                radial.Close();
            }

            // Task overview with status cards.
            {
                var slots = Tasks(english);
                var inventory = new InventoryWindow(slots, new Native.Rect(0, 0, 1920, 1080), 1, 2, false, presentationPreview: true, size: OverviewSize.Large);
                inventory.Left = -9000; inventory.Top = -9000; inventory.ShowActivated = false; inventory.Topmost = false; inventory.Show(); inventory.UpdateLayout(); Idle(); Pump(150);
                var visual = (FrameworkElement)inventory.Content; inventory.Content = null;
                var frame = new System.Windows.Controls.Border { Background = inventory.Background, Width = inventory.Width, Height = inventory.Height, Child = visual };
                frame.Measure(new Size(inventory.Width, inventory.Height)); frame.Arrange(new Rect(0, 0, inventory.Width, inventory.Height)); frame.UpdateLayout();
                Save(Capture(frame, inventory.Width, inventory.Height), Path.Combine(dir, "inventory-relic.png"));
                inventory.Close();
            }
            Task.WaitAll(Encoding.ToArray());
            Console.WriteLine("rendered " + dir);
            return 0;
        }
        catch (Exception e) { File.WriteAllText(Path.Combine(output, "render-failure-" + language + ".txt"), e.ToString()); return 1; }
        finally { app.Shutdown(); }
    }
}
