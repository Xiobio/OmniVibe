using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace CodeManager;

public static class SkinTests
{
    public static IEnumerable<SelfTests.Result> Run()
    {
        var results = new List<SelfTests.Result>();
        void Test(string name, Action action)
        {
            try { action(); results.Add(new(name, true, "OK")); }
            catch (Exception ex) { results.Add(new(name, false, ex.ToString())); }
        }
        static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
        Skin original = WuxiaTheme.CurrentSkin; bool decorations = SkinCatalog.DecorationsEnabled;
        try
        {
            Test("Motion: repeated commands preserve transitions and reversal renders intermediate frames", () =>
            {
                SkinCatalog.DecorationsEnabled = true;
                var wheel = new DockWeaponWheel();
                wheel.SetSlots(Enumerable.Range(1, 9).Select(n => new Slot { Number = n }));
                var host = new Window { Width = 460, Height = 450, Content = wheel, Left = -8000, Top = -8000, ShowActivated = false, ShowInTaskbar = false };
                void Advance(int milliseconds)
                {
                    var frame = new DispatcherFrame();
                    var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(milliseconds) };
                    timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
                    timer.Start(); Dispatcher.PushFrame(frame);
                }
                try
                {
                    host.Show(); host.UpdateLayout(); Advance(30);
                    wheel.Deploy(true, true); int transitions = wheel.DeploymentTransitions;
                    for (int i = 0; i < 12; i++) wheel.Deploy(true, true);
                    Check(wheel.DeploymentTransitions == transitions, "Repeated input restarted opening");
                    wheel.BeginAim(true); Check(wheel.DeploymentTransitions == transitions && wheel.Aiming, "Selection restarted deployment");
                    Advance(70);
                    var closing = new List<double>();
                    EventHandler collect = (_, _) => closing.Add(wheel.Deployment);
                    CompositionTarget.Rendering += collect;
                    try
                    {
                        wheel.Deploy(false, true); transitions = wheel.DeploymentTransitions;
                        wheel.Deploy(false, true); Check(wheel.DeploymentTransitions == transitions, "Repeated cancel restarted retraction");
                        Advance(180);
                    }
                    finally { CompositionTarget.Rendering -= collect; }
                    Check(closing.Any(v => v > .01 && v < .99), "Retraction skipped intermediate rendered frames");
                    wheel.Deploy(false, false); Check(wheel.Deployment == 0, "Animation-off did not settle immediately");
                }
                finally { host.Close(); }
            });
            Test("Motion: warm text layouts ignore task renames while changing equipment updates the rendered identity", () =>
            {
                var wheel = new DockWeaponWheel();
                var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Id = "cache-" + n, Name = "Task " + n, Window = new() { Title = "fixture" }, Connected = true, IsActive = n == 1 }).ToList();
                wheel.SetSlots(slots); wheel.Deploy(true, false);
                wheel.Measure(new Size(460, 450)); wheel.Arrange(new Rect(0, 0, 460, 450));
                void Frame(int i)
                {
                    wheel.Flow = i * .03; wheel.Deployment = .65 + i * .001;
                    wheel.UpdateLayout(); var bitmap = new RenderTargetBitmap(460, 450, 96, 96, PixelFormats.Pbgra32); bitmap.Render(wheel);
                }
                Frame(0); int warm = wheel.TextBuilds;
                for (int i = 1; i < 15; i++) Frame(i);
                Check(wheel.TextBuilds == warm, "Geometry animation repeatedly laid out unchanged text");
                slots[0].Name = "Renamed project"; wheel.InvalidateVisual(); Frame(16);
                Check(wheel.TextBuilds == warm, "Task rename rebuilt unrelated equipment labels");
                byte[] Pixels() { var bitmap = new RenderTargetBitmap(460, 450, 96, 96, PixelFormats.Pbgra32); bitmap.Render(wheel); var bytes = new byte[460*450*4]; bitmap.CopyPixels(bytes, 460*4, 0); return bytes; }
                var before = Pixels(); var taskId = slots[0].Id; var taskWindow = slots[0].Window;
                slots[0].EquipmentSelections[SkinCatalog.Current.Id.ToString()] = EquipmentCatalog.ForSkin(SkinCatalog.Current.Id)[1].Id;
                slots[0].Refresh(); wheel.InvalidateVisual(); wheel.UpdateLayout();
                Check(!before.SequenceEqual(Pixels()), "Changing equipment did not update its visual identity");
                Check(slots[0].Id == taskId && ReferenceEquals(slots[0].Window, taskWindow) && slots[0].Name == "Renamed project", "Equipment change altered task identity or window binding");
            });
            Test("Overlay: desktop gaps are alpha-zero and native clicks pass to the window underneath", () =>
            {
                WuxiaTheme.Apply(Skin.Hextech);
                var screen = Native.ScreenAtCursor();
                double left = screen.Work.Left / screen.Scale + 24, top = screen.Work.Top / screen.Scale + 24;
                var behind = new Window { Width = 560, Height = 620, Left = left, Top = top, Background = Brushes.DarkSlateGray, Topmost = true, ShowActivated = false, ShowInTaskbar = false };
                var dock = new DockWindow { Width = 460, Height = 530, Left = left + 12, Top = top + 12, Topmost = true, ShowActivated = false };
                dock.SetSlots(Enumerable.Range(1, 9).Select(n => new Slot { Number = n }));
                try
                {
                    IntPtr focus = Native.GetForegroundWindow();
                    behind.Show(); dock.Show(); dock.UpdateLayout();
                    Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                    var wheel = (DockWeaponWheel)dock.FindName("WeaponWheel");
                    var hwnd = new WindowInteropHelper(dock).Handle;
                    Check(!Native.HasOverlayFrame(hwnd), "Overlay retained a system frame");
                    var shot = new RenderTargetBitmap(460, 530, 96, 96, PixelFormats.Pbgra32); shot.Render(dock);
                    var pixels = new byte[460 * 530 * 4]; shot.CopyPixels(pixels, 460 * 4, 0);
                    Point gap = wheel.TranslatePoint(new Point(wheel.Centre.X + 80, wheel.Centre.Y), dock);
                    Point oldLabel = wheel.TranslatePoint(wheel.Centre + new Vector(0, 90), dock);
                    foreach (var p in new[] { new Point(1, 1), new Point(458, 528), gap, oldLabel })
                        Check(pixels[((int)p.Y * 460 + (int)p.X) * 4 + 3] == 0, "An invisible host or broad shadow painted desktop space");
                    Point screenGap = dock.PointToScreen(gap);
                    Check(Native.WindowFromPoint(new Native.Point((int)screenGap.X, (int)screenGap.Y)) == new WindowInteropHelper(behind).Handle, "Empty overlay space intercepted the underlying application");
                    Point screenCore = wheel.PointToScreen(wheel.Centre);
                    Check(Native.WindowFromPoint(new Native.Point((int)screenCore.X, (int)screenCore.Y)) == hwnd, "Removing the frame broke the visible core hit target");
                    Check(Native.GetForegroundWindow() == focus, "Frame cleanup stole keyboard focus");
                }
                finally { dock.Close(); behind.Close(); }
            });
            Test("Compact host: native bounds shrink to the ring, deployment preserves the screen anchor", () =>
            {
                var screen = Native.ScreenAtCursor();
                var dock = new DockWindow { ShowActivated = false, Topmost = false };
                dock.SetSlots(Enumerable.Range(1, 9).Select(n => new Slot { Number = n }));
                try
                {
                    IntPtr focus = Native.GetForegroundWindow();
                    dock.Show(); dock.PlaceCompactHost(new Native.Point(screen.Work.Left + 300, screen.Work.Top + 300), screen.Scale, 360);
                    var wheel = (DockWeaponWheel)dock.FindName("WeaponWheel");
                    Point anchor = dock.CoreScreen; var hwnd = new WindowInteropHelper(dock).Handle;
                    Native.GetWindowRect(hwnd, out var idle);
                    Check(Math.Abs(idle.Right - idle.Left - DockWindow.CompactExtent * screen.Scale) <= 1 && idle.Right - idle.Left == idle.Bottom - idle.Top, "Idle retained the expanded native rectangle");
                    dock.SetEquipmentDeployment(true, false); Native.GetWindowRect(hwnd, out var expanded);
                    Check(Math.Abs(expanded.Right - expanded.Left - 360 * screen.Scale) <= 1, "Hover did not allocate the task viewport");
                    Check((dock.CoreScreen - anchor).Length <= 1, "Expanding moved the core on screen");
                    foreach (var slot in wheel.Slots) Check(wheel.HitSlot(wheel.SlotPoint(slot.Number)) == slot, "Compact deck lost a fixed task target");
                    dock.SetEquipmentDeployment(false, false); Native.GetWindowRect(hwnd, out var closed);
                    Check(closed.Right - closed.Left == idle.Right - idle.Left && (dock.CoreScreen - anchor).Length <= 1, "Retraction did not release the task viewport");
                    Check(Native.GetForegroundWindow() == focus, "Resizing the overlay stole focus");
                }
                finally { dock.Close(); }
            });
            Test("Equipment gesture: dead zone, connected-only release and boundary hysteresis preserve task data", () =>
            {
                var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Id = "identity-" + n, Name = "Fixture " + n, Window = n <= 3 ? new() { Title = "fixture" } : null, Connected = n <= 2, IsActive = n == 1 }).ToList();
                var wheel = new DockWeaponWheel(); wheel.SetSlots(slots);
                wheel.Measure(new Size(460, 448)); wheel.Arrange(new Rect(0, 0, 460, 448));
                string before = JsonSerializer.Serialize(slots, StateStore.Json);
                Check(!wheel.IsDeployed && wheel.HitSlot(wheel.SlotPoint(1)) == null, "Idle core exposed invisible hit targets");
                foreach (int n in new[] { 2, 3, 9 })
                {
                    wheel.BeginAim(false); wheel.AimAt(wheel.SlotPoint(n));
                    Check(wheel.EndAim(true) == (n == 2 ? 2 : null), "Gesture accepted an empty or disconnected slot");
                }
                wheel.BeginAim(false); wheel.AimAt(wheel.SlotPoint(2)); wheel.AimAt(wheel.Centre);
                Check(wheel.EndAim(true) == null, "Returning to the core did not cancel");
                wheel.BeginAim(false); wheel.AimAt(wheel.SlotPoint(2));
                Point AtAngle(double a) => new(wheel.Centre.X + Math.Sin(a * Math.PI / 180) * 155, wheel.Centre.Y - Math.Cos(a * Math.PI / 180) * 155);
                wheel.AimAt(AtAngle(61)); Check(wheel.AimCandidate == 2, "Boundary tremor changed the task");
                wheel.AimAt(AtAngle(65)); Check(wheel.AimCandidate == null, "Hysteresis swallowed an intentional direction change");
                wheel.EndAim(false); wheel.Deploy(false, false);
                Check(before == JsonSerializer.Serialize(slots, StateStore.Json), "Aim changed bindings, numbering or unread state");
                Check(slots.Select(TaskEmblem.Seed).Distinct().Count() == 9, "Task identities collided");
            });
            Test("Equipment core: hover opens without focus, desktop gaps retain it, leaving retracts with reentry grace", () =>
            {
                var dock = new DockWindow { Left = -8000, Top = -8000, ShowActivated = false, Topmost = false, Width = 460, Height = 530 };
                dock.SetSlots(Enumerable.Range(1, 9).Select(n => new Slot { Number = n }));
                try
                {
                    dock.Show(); dock.UpdateLayout(); var wheel = (DockWeaponWheel)dock.FindName("WeaponWheel");
                    Point anchor = wheel.PointToScreen(wheel.Centre); IntPtr focus = Native.GetForegroundWindow();
                    dock.HandleWheelPointerMove(wheel.SlotPoint(1));
                    Check(!wheel.IsDeployed, "Invisible peripheral target triggered deployment");
                    dock.HandleWheelPointerMove(wheel.Centre);
                    Check(wheel.IsDeployed && !dock.IsManipulating && !dock.IsMouseCaptureWithin, "Hover did not open without requiring a press or capture");
                    int transitions = wheel.DeploymentTransitions;
                    for (int i = 0; i < 10; i++) dock.HandleWheelPointerMove(wheel.Centre);
                    Check(wheel.DeploymentTransitions == transitions, "Repeated hover restarted opening");
                    var now = DateTime.UtcNow; var outside = wheel.Centre + new Vector(600, 0);
                    dock.CheckRetraction(wheel.Centre + new Vector(100, 0), now);
                    dock.CheckRetraction(wheel.Centre + new Vector(100, 0), now.AddSeconds(2));
                    Check(wheel.IsDeployed, "Crossing a transparent desktop gap closed the task targets");
                    dock.CheckRetraction(outside, now); dock.CheckRetraction(outside, now.AddMilliseconds(120));
                    Check(wheel.IsDeployed, "Leaving retracted without a grace period");
                    dock.CheckRetraction(wheel.SlotPoint(1), now.AddMilliseconds(130));
                    dock.CheckRetraction(outside, now.AddMilliseconds(200)); dock.CheckRetraction(outside, now.AddMilliseconds(320));
                    Check(wheel.IsDeployed, "Reentering did not reset the retraction deadline");
                    dock.CheckRetraction(outside, now.AddMilliseconds(650));
                    Check(!wheel.IsDeployed && wheel.Deployment == 0, "Leaving did not return to the idle ring");
                    dock.BeginCorePress(wheel.Centre, capture: false); dock.EndCorePress();
                    Check(wheel.IsDeployed && !dock.IsManipulating, "Quick click did not keep tasks accessible");
                    dock.BeginCorePress(wheel.Centre, capture: false); dock.EndCorePress();
                    Check(wheel.IsDeployed, "Clicking the already hovered core unexpectedly hid the tasks");
                    dock.BeginCorePress(wheel.Centre, capture: false); dock.CancelManipulation();
                    Check(!dock.IsManipulating && !wheel.IsDeployed && !wheel.Aiming, "Escape/cancel retained a gesture");
                    Check(wheel.PointToScreen(wheel.Centre) == anchor && Native.GetForegroundWindow() == focus, "Deploy changed the core anchor or keyboard focus");
                }
                finally { dock.Close(); }
            });
            Test("Radial inventory: fixed sectors, centre cancel, outer cancel and scaled hit testing", () =>
            {
                foreach (double scale in new[] { .5, 1, 1.5, 2 })
                {
                    var centre = new Point(330, 370);
                    for (int number = 1; number <= 9; number++)
                    {
                        double angle = (number - 1) * 40 * Math.PI / 180;
                        Check(RadialSelection.Hit(new Point(centre.X + Math.Sin(angle) * 190 * scale, centre.Y - Math.Cos(angle) * 190 * scale), centre, scale) == number, "Sector or DPI mapping changed: " + number);
                    }
                    Check(RadialSelection.Hit(centre, centre, scale) == null, "Centre did not cancel");
                    Check(RadialSelection.Hit(new Point(centre.X, centre.Y - 100 * scale), centre, scale) == null, "Dead zone selected a task");
                    Check(RadialSelection.Hit(new Point(centre.X, centre.Y - 280 * scale), centre, scale) == null, "Beyond rim selected a task");
                }
            });
            Test("Radial inventory: confirm only connected slots; no focus steal, reordering or retained window", () =>
            {
                var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Name = "轮盘 fixture " + n, Window = n <= 3 ? new() { Title = "fixture" } : null, Connected = n <= 2 }).ToList();
                string before = JsonSerializer.Serialize(slots, StateStore.Json);
                IntPtr focus = Native.GetForegroundWindow(); int windows = Application.Current.Windows.Count;
                foreach (int? number in new int?[] { null, 1, 3, 9 })
                {
                    var wheel = new RadialInventoryWindow(slots, new Native.Rect(0, 0, 940, 760), 1, false, "Alt+Q", preview: true) { Left = -8000, Top = -8000 };
                    int? result = -1;
                    try
                    {
                        wheel.Finish += chosen => { result = chosen; wheel.Close(); };
                        wheel.Show(); wheel.UpdateLayout();
                        Check(Native.GetForegroundWindow() == focus, "Wheel stole terminal focus");
                        wheel.Surface.Select(number); wheel.Complete(true);
                        Check(result == (number == 1 ? 1 : null), "Empty, disconnected or centre target was accepted");
                        Check(Application.Current.Windows.Count == windows, "Wheel retained a native window");
                    }
                    finally { if (wheel.IsVisible) wheel.Close(); }
                }
                Check(before == JsonSerializer.Serialize(slots, StateStore.Json), "Wheel mutated slot bindings");
            });
            Test("Radial inventory: release after a quick chord cancels once and stops its timer", () =>
            {
                var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n }).ToList();
                var wheel = new RadialInventoryWindow(slots, new Native.Rect(0, 0, 940, 760), 1, false, "Alt+Q", () => false) { Left = -8000, Top = -8000, Topmost = false };
                int callbacks = 0;
                try
                {
                    wheel.Finish += chosen => { callbacks++; Check(chosen == null, "Quick tap selected a task"); wheel.Close(); };
                    wheel.Show();
                    var deadline = DateTime.UtcNow.AddSeconds(1);
                    while (wheel.IsVisible && DateTime.UtcNow < deadline) { Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle); System.Threading.Thread.Sleep(20); }
                    Check(callbacks == 1 && !wheel.IsVisible, "Release was missed or emitted twice");
                }
                finally { if (wheel.IsVisible) wheel.Close(); }
            });
            Test("Dock wheel: nine permanent sectors replace the list across skins without changing bindings", () =>
            {
                foreach (var skin in SkinCatalog.All)
                {
                    WuxiaTheme.Apply(skin.Id);
                    var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Name = "Equipment fixture " + n, Window = n <= 2 ? new() { Title = "fixture", ProcessName = "pwsh" } : null, Connected = n <= 2, IsActive = n == 2 }).ToList();
                    string before = JsonSerializer.Serialize(slots, StateStore.Json);
                    var dock = new DockWindow { Width = 460, Height = 530, Left = -8000, Top = -8000, Topmost = false, ShowActivated = false };
                    try
                    {
                        dock.SetSlots(slots); dock.SetPreviewLabel(); dock.SetEquipmentDeployment(true, false); dock.Show(); dock.UpdateLayout();
                        Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                        var wheel = (DockWeaponWheel)dock.FindName("WeaponWheel");
                        Check(wheel.Slots.Select(s => s.Number).SequenceEqual(Enumerable.Range(1, 9)), skin.Slug + ": nine sectors changed order");
                        Check(dock.FindName("SlotsList") == null && dock.FindName("QuickSlots") == null, "Old task list still exists");
                        Check(dock.FindName("DockHeader") == null && dock.FindName("DockActions") == null && dock.FindName("HintHost") == null && dock.FindName("ResizeGrip") == null, "Toolbar chrome returned to the ring");
                        Check(wheel.FocusedSlot == slots[1], skin.Slug + ": centre did not follow active task");
                        foreach (var slot in slots)
                        {
                            Point target = wheel.PointToScreen(wheel.SlotPoint(slot.Number));
                            var expected = slot;
                            Check(dock.HitSlot(new Native.Point((int)target.X, (int)target.Y)) == expected, skin.Slug + ": native hit testing missed a task or intercepted a hidden empty sector " + slot.Number);
                            Check(wheel.HitSlot(wheel.SlotPoint(slot.Number), duringCapture: true) == slot, skin.Slug + ": capture target missing at " + slot.Number);
                        }
                        wheel.Hover(slots[4]); Check(wheel.FocusedSlot == slots[1], "Empty hover replaced the current task context");
                        wheel.Hover(slots[0]); Check(wheel.FocusedSlot == slots[0], "Occupied hover did not expose task identity");
                        wheel.Hover(null); slots[1].IsActive = false; slots[0].IsActive = true; slots[0].Refresh(); slots[1].Refresh();
                        Check(wheel.FocusedSlot == slots[0], "Centre did not follow switched task");
                        Check(before == JsonSerializer.Serialize(slots, StateStore.Json), "Wheel rendering changed saved bindings");
                        Point anchor = wheel.PointToScreen(wheel.Centre);
                        dock.SetCollapsed(true); dock.UpdateLayout(); Check(!wheel.IsDeployed && wheel.Deployment == 0, "Auto-hide did not return to the equipment core");
                        var shot = new RenderTargetBitmap(460, 530, 96, 96, PixelFormats.Pbgra32); shot.Render(dock);
                        var pixels = new byte[460 * 530 * 4]; shot.CopyPixels(pixels, 460 * 4, 0);
                        Point centre = wheel.TranslatePoint(wheel.Centre, dock);
                        for (int y = 0; y < 530; y++) for (int x = 0; x < 460; x++)
                            if (Math.Abs(x-centre.X) > 58 || Math.Abs(y-centre.Y) > 58)
                                Check(pixels[(y * 460 + x) * 4 + 3] == 0, skin.Slug + ": idle painted beyond its resting host");
                        Check(wheel.PointToScreen(wheel.Centre) == anchor, "Core moved during retraction");
                        dock.SetCollapsed(false); Check(wheel.Slots.Count == 9, "Expanding lost a sector");
                    }
                    finally { dock.Close(); }
                }
            });
            Test("Dock equipment: switch cue never takes focus and releases itself after feedback", () =>
            {
                IntPtr foreground = Native.GetForegroundWindow();
                int before = Application.Current.Windows.Count;
                var cue = new EquipmentSwitchCue(new Slot { Number = 2, Name = "Switch fixture", Window = new() { Title = "fixture" }, Connected = true, IsActive = true }, -8000, -8000);
                try
                {
                    cue.Show(); cue.UpdateLayout();
                    Check(Native.GetForegroundWindow() == foreground, "Equip cue stole input focus");
                    var deadline = DateTime.UtcNow.AddSeconds(2);
                    while (cue.IsVisible && DateTime.UtcNow < deadline) { Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle); System.Threading.Thread.Sleep(20); }
                    Check(!cue.IsVisible && Application.Current.Windows.Count == before, "Equip cue retained a window after expiry");
                }
                finally { if (cue.IsVisible) cue.Close(); }
            });
            Test("Skins: all 13 palettes meet body, panel, card and status text contrast >= 4.5", () =>
            {
                Check((int)Skin.InkJade == 0 && (int)Skin.Midnight == 1 && (int)Skin.Cinnabar == 2, "Legacy persisted enum values changed");
                Check(SkinCatalog.All.Count == 13 && SkinCatalog.All.Select(s => s.Slug).Distinct().Count() == 13, "Duplicate or missing palette");
                foreach (var s in SkinCatalog.All)
                {
                    foreach (string bg in new[] { s.Background, s.Surface, s.Elevated })
                        foreach (string fg in new[] { s.Text, s.Muted, s.Accent, s.Running, s.Waiting, s.Ready, s.Error, s.Unknown })
                            Check(SkinCatalog.Contrast(fg, bg) >= 4.5, $"{s.Slug}: {fg} on {bg} has contrast {SkinCatalog.Contrast(fg, bg):F3}");
                    Check(SkinCatalog.Contrast(s.CardText, s.CardBackground) >= 4.5, s.Slug + ": card text contrast");
                    var cardForeground = (Color)ColorConverter.ConvertFromString(s.CardText); var bgColor = (Color)ColorConverter.ConvertFromString(s.CardBackground);
                    static byte Blend(byte foreground, byte background) => (byte)Math.Round(foreground * .8 + background * .2);
                    string metadata = $"#{Blend(cardForeground.R, bgColor.R):X2}{Blend(cardForeground.G, bgColor.G):X2}{Blend(cardForeground.B, bgColor.B):X2}";
                    Check(SkinCatalog.Contrast(metadata, s.CardBackground) >= 4.5, s.Slug + ": 80% metadata text contrast");
                    Check(Enumerable.Range(1, 9).Select(s.SlotNumber).Distinct().Count() == 9, s.Slug + ": slot numerals collide");
                }
                Check(SkinCatalog.Get((Skin)999) == SkinCatalog.All[0], "Unknown persisted skin did not use safe fallback");
            });
            Test("Skins: terminal/native JSON palette contract matches every new skin", () =>
            {
                using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "skins", "catalog.json")));
                Check(document.RootElement.GetArrayLength() == 10, "Published palette count differs");
                foreach (var row in document.RootElement.EnumerateArray())
                {
                    var s = SkinCatalog.All.Single(s => s.Slug == row.GetProperty("slug").GetString());
                    foreach (var pair in new[] { ("background", s.Background), ("surface", s.Surface), ("elevated", s.Elevated), ("text", s.Text), ("muted", s.Muted), ("accent", s.Accent), ("secondary", s.Secondary), ("border", s.Border), ("running", s.Running), ("waiting", s.Waiting), ("ready", s.Ready), ("error", s.Error), ("unknown", s.Unknown), ("cardBackground", s.CardBackground), ("cardText", s.CardText), ("family", s.Family), ("artwork", s.Artwork) })
                        Check(row.GetProperty(pair.Item1).GetString() == pair.Item2, s.Slug + ": JSON diverged at " + pair.Item1);
                    Check(row.GetProperty("id").GetString() == s.Id.ToString(), s.Slug + ": ID mismatch");
                }
            });
            Test("Skins: switching and rendering each task state preserves task IDs, launch, session and window snapshots", () =>
            {
                var state = new AppState();
                foreach (var slot in state.Slots)
                {
                    slot.Name = "中英文 very long task / " + slot.Number;
                    if (slot.Number <= 6) slot.Window = new() { Handle = 10000 + slot.Number, ProcessId = 20000 + slot.Number, ProcessStartedUtcTicks = 50000 + slot.Number, ProcessName = "fixture", Title = "Task " + slot.Number };
                    slot.Connected = slot.Number <= 5; slot.State = (AgentState)((slot.Number - 1) % 5); slot.Unread = slot.Number is 2 or 3;
                    slot.ProjectDirectory = "D:\\fixture\\项目 " + slot.Number; slot.SessionId = "session-" + slot.Number;
                    slot.LaunchMode = LaunchMode.Codex; slot.ResumeSessionId = slot.SessionId; slot.Notes = "保留任务备忘";
                }
                var first = state.Slots[0]; state.Popup = new() { SlotId = first.Id, Window = first.Window!, ParkedByApp = true };
                state.Layout.Add(new() { SlotId = first.Id, Window = first.Window!, ParkedByApp = false }); state.DockVisibleBeforeLayout = false;
                string before = JsonSerializer.Serialize(state, StateStore.Json);
                foreach (var s in SkinCatalog.All)
                {
                    WuxiaTheme.Apply(s.Id);
                    var resource = (SolidColorBrush)Application.Current.Resources["SkinTextBrush"];
                    Check(resource.Color == ((SolidColorBrush)WuxiaTheme.Brush(s.Text)).Color, s.Slug + ": dynamic control text did not switch");
                    foreach (var slot in state.Slots)
                    {
                        var card = new SkinTaskCard(slot, false); card.Measure(new Size(360, 240)); card.Arrange(new Rect(0, 0, 360, 240)); card.Update(slot.Number == 3); card.StopAnimations();
                    }
                    Check(JsonSerializer.Serialize(state, StateStore.Json) == before, s.Slug + ": rendering changed saved task or window state");
                }
            });
            Test("Skins: family glyphs are distinct and decorations-off renders a clean interactive background", () =>
            {
                var hashes = new HashSet<string>();
                foreach (var s in SkinCatalog.All.Where(s => s.Id >= Skin.Hextech))
                {
                    WuxiaTheme.Apply(s.Id); SkinCatalog.DecorationsEnabled = true;
                    var glyph = new SkinGlyph(false); byte[] pixels = Render(glyph);
                    Check(pixels.Any(b => b != 0), s.Slug + ": missing family emblem");
                    Check(hashes.Add(Convert.ToHexString(SHA256.HashData(pixels))), s.Slug + ": emblem duplicates another family");
                    SkinCatalog.DecorationsEnabled = false;
                    Check(Render(new SkinGlyph(false)).All(b => b == 0), s.Slug + ": decorations-off still drew emblem");
                    pixels = Render(new SkinBackdrop());
                    var bg = (Color)ColorConverter.ConvertFromString(s.Background);
                    for (int i = 0; i < pixels.Length; i += 4) Check(pixels[i] == bg.B && pixels[i + 1] == bg.G && pixels[i + 2] == bg.R && pixels[i + 3] == 255, s.Slug + ": decorations-off altered the plain background");
                }
            });
            Test("Dock wheel: resize preserves nine hit targets and centre capture resolves to an empty slot", () =>
            {
                WuxiaTheme.Apply(Skin.Hextech);
                var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Window = n <= 2 ? new() { Title = "fixture" } : null, Connected = n <= 2 }).ToList();
                foreach (var size in new[] { new Size(440, 500), new Size(460, 530), new Size(620, 680) })
                {
                    var dock = new DockWindow { Width = size.Width, Height = size.Height };
                    try
                    {
                        dock.SetSlots(slots); dock.SetEquipmentDeployment(true, false);
                        var content = (FrameworkElement)dock.Content; content.Measure(size); content.Arrange(new Rect(new Point(), size)); content.UpdateLayout();
                        var wheel = (DockWeaponWheel)dock.FindName("WeaponWheel");
                        Check(wheel.ActualWidth > 0 && wheel.Radius >= 100, "Wheel was crushed by layout");
                        foreach (Slot slot in slots) Check(wheel.HitSlot(wheel.SlotPoint(slot.Number)) == slot, "Resize lost slot " + slot.Number);
                        Check(wheel.HitSlot(wheel.Centre) == null, "Centre activated an arbitrary task");
                        Check(wheel.HitSlot(wheel.Centre, duringCapture: true) == slots[2], "Centre capture did not use first empty slot");
                        Check(wheel.HitSlot(new Point(0, 0)) == null, "Transparent corner became a task target");
                        slots[2].IsDropTarget = true; slots[2].Refresh(); Check(wheel.FocusedSlot == slots[2], "Drop target was not shown in centre"); slots[2].IsDropTarget = false;
                    }
                    finally { dock.Close(); }
                }
            });
            Test("Skins: 13 settings choices use stable enum tags; cancel and save preserve preference boundaries", () =>
            {
                Skin active = WuxiaTheme.CurrentSkin;
                foreach (var s in SkinCatalog.All)
                {
                    var source = new Preferences { Skin = s.Id, DecorationsEnabled = false, Animate = false, SoundEffects = false };
                    string before = JsonSerializer.Serialize(source, StateStore.Json);
                    var window = new SettingsWindow(source, new Native.Rect(0, 0, 1920, 1040), "", page: 2);
                    try
                    {
                        var picker = Descendants(window.Content).OfType<SkinPicker>().Single();
                        Check(picker.SelectedSkin == s.Id, s.Slug + ": saved enum selected the wrong theme");
                        var choices = picker.Children.OfType<ComboBox>().Single();
                        choices.SelectedIndex = (choices.SelectedIndex + 1) % SkinCatalog.All.Count;
                        Check(picker.SelectedSkin == (Skin)((int)s.Id + 1 == SkinCatalog.All.Count ? 0 : (int)s.Id + 1), s.Slug + ": choice does not map to enum tag");
                        Check(window.Result.Skin == s.Id && !window.Result.DecorationsEnabled, "Preview changed uncommitted settings");
                        Check(JsonSerializer.Serialize(source, StateStore.Json) == before && WuxiaTheme.CurrentSkin == active, "Preview changed the active palette or source preferences");
                    }
                    finally { window.Close(); }
                }
                var preferences = new Preferences { Skin = Skin.Tactical, DecorationsEnabled = true };
                var dialog = new SettingsWindow(preferences, new Native.Rect(0, 0, 1920, 1040), "", page: 2) { ShowActivated = false, Topmost = false, Left = -20000, Top = -20000 };
                Dispatcher.CurrentDispatcher.BeginInvoke(() =>
                {
                    var picker = Descendants(dialog.Content).OfType<SkinPicker>().Single();
                    picker.Children.OfType<ComboBox>().Single().SelectedItem = picker.Children.OfType<ComboBox>().Single().Items.OfType<ComboBoxItem>().Single(i => i.Tag is Skin s && s == Skin.Wonderland);
                    var decoration = Descendants(dialog.Content).OfType<CheckBox>().Single(c => c.Content is TextBlock t && t.Text.Contains("装饰")); decoration.IsChecked = false;
                    Descendants(dialog.Content).OfType<Button>().Single(b => b.Content as string == "保存并应用").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                }, DispatcherPriority.ApplicationIdle);
                Check(dialog.ShowDialog() == true, "Settings save failed");
                Check(dialog.Result.Skin == Skin.Wonderland && !dialog.Result.DecorationsEnabled, "Settings did not commit selected skin and decoration toggle");
                Check(preferences.Skin == Skin.Tactical && preferences.DecorationsEnabled && WuxiaTheme.CurrentSkin == active, "Settings commit mutated caller preferences or applied before manager accepted");
                var roundtrip = JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(dialog.Result, StateStore.Json), StateStore.Json)!;
                Check(roundtrip.Skin == Skin.Wonderland && !roundtrip.DecorationsEnabled, "Skin/decorations did not round-trip");
            });
            Test("Skins: nine-card overview remains readable at 780x650 and 200-percent display scaling", () =>
            {
                SkinCatalog.DecorationsEnabled = true;
                foreach (var s in SkinCatalog.All)
                {
                    WuxiaTheme.Apply(s.Id);
                    foreach (var viewport in new[] { (Area: new Native.Rect(0, 0, 836, 698), Scale: 1d), (Area: new Native.Rect(0, 0, 1920, 1040), Scale: 2d) })
                    {
                        var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Window = n <= 6 ? new() { Title = "Mixed 中英文任务 " + n } : null, Connected = n <= 5, State = (AgentState)((n - 1) % 5) }).ToList();
                        var window = new InventoryWindow(slots, viewport.Area, viewport.Scale, 3, false, presentationPreview: true);
                        try
                        {
                            var content = (FrameworkElement)window.Content;
                            content.Measure(new Size(window.Width, window.Height)); content.Arrange(new Rect(0, 0, window.Width, window.Height)); content.UpdateLayout();
                            foreach (var card in Descendants(content).OfType<SkinTaskCard>())
                            {
                                var preview = card.PreviewRegion;
                                Check(preview.ActualHeight >= (viewport.Scale == 2 ? 25 : 30), $"{s.Slug}: preview crushed to {preview.ActualHeight:F1} at scale {viewport.Scale}");
                                foreach (var label in Descendants(preview).OfType<TextBlock>().Where(t => t.Visibility == Visibility.Visible && t.ActualHeight > 0))
                                {
                                    Rect bounds = label.TransformToAncestor(preview).TransformBounds(new Rect(label.RenderSize));
                                    Check(bounds.Top >= -1 && bounds.Bottom <= preview.ActualHeight + 1 && bounds.Left >= -1 && bounds.Right <= preview.ActualWidth + 1, s.Slug + ": preview status text clipped at scale " + viewport.Scale);
                                }
                            }
                        }
                        finally { window.Close(); }
                    }
                }
            });
            Test("Skins: themed settings scroll viewer retains vertical and horizontal scrolling", () =>
            {
                WuxiaTheme.Apply(Skin.Wonderland);
                var viewer = new ScrollViewer { Width = 300, Height = 200, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = new Border { Width = 2000, Height = 2000 } };
                viewer.Measure(new Size(300, 200)); viewer.Arrange(new Rect(0, 0, 300, 200)); viewer.UpdateLayout(); viewer.ApplyTemplate();
                var vertical = (ScrollBar?)viewer.Template.FindName("PART_VerticalScrollBar", viewer);
                var horizontal = (ScrollBar?)viewer.Template.FindName("PART_HorizontalScrollBar", viewer);
                Check(vertical != null && horizontal != null, "Global themed scroll viewer lost a scrollbar PART");
                Check(vertical!.Width == 10 && horizontal!.Height == 10, "Themed scrollbar hit targets changed size");
                viewer.ScrollToHorizontalOffset(40); viewer.ScrollToVerticalOffset(50); viewer.UpdateLayout();
                Check(viewer.HorizontalOffset >= 40 && viewer.VerticalOffset >= 50, "ScrollTo stopped routing to content");
                double x = viewer.HorizontalOffset, y = viewer.VerticalOffset; viewer.LineRight(); viewer.LineDown(); viewer.UpdateLayout();
                Check(viewer.HorizontalOffset > x && viewer.VerticalOffset > y, "Line scrolling stopped routing to content");
            });
            Test("Skins: short work areas scroll all nine tasks and suppress clipped native thumbnails", () =>
            {
                WuxiaTheme.Apply(Skin.Protocol);
                var fixture = new Window { Title = "OmniVibe skin thumbnail fixture", Width = 320, Height = 180, ShowActivated = false, ShowInTaskbar = false, Left = -19000, Top = -19000 };
                InventoryWindow? window = null;
                try
                {
                    fixture.Show(); fixture.UpdateLayout();
                    // The fixture is intentionally a tool window, so it bypasses the user-window picker filter.
                    var identity = new WindowIdentity { Handle = new WindowInteropHelper(fixture).Handle.ToInt64(), ProcessId = Environment.ProcessId, ProcessName = "fixture", Title = fixture.Title };
                    var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Window = identity, Connected = true, Name = "short task " + n, State = AgentState.Running }).ToList();
                    window = new InventoryWindow(slots, new Native.Rect(0, 0, 1920, 698), 2, 1, false, presentationPreview: true) { ShowActivated = false, Topmost = false };
                    Check(window.Height <= 349 && window.Top >= 0 && window.Top + window.Height <= 349, "Short-area overview escaped work area");
                    window.Left = -18000; window.Top = -18000; window.Show(); window.UpdateLayout();
                    Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                    var viewport = Descendants(window.Content).OfType<ScrollViewer>().Single();
                    Check(viewport.ScrollableHeight > 0, "Short work area did not provide a scroll fallback");
                    var baseline = Native.Thumbnail(new WindowInteropHelper(window).Handle, new(identity.Handle), new Native.Rect(20, 20, 140, 100));
                    Check(baseline != IntPtr.Zero, "Native thumbnail baseline did not register"); Native.DwmUnregisterThumbnail(baseline);
                    window.UpdateThumbnails();
                    Check(window.ThumbnailCount > 0 && window.ThumbnailCount < 9, "Visible native previews were absent, or clipped previews were not suppressed");
                    window.Select(9); window.UpdateLayout(); Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                    Check(window.SelectedNumber == 9 && viewport.VerticalOffset > 0, "Last task was unreachable through overview selection");
                    int entered = 0; window.Choose += number => entered = number; window.Enter(); Check(entered == 9, "Enter did not route to selected last task");
                    window.UpdateThumbnails(); Check(window.ThumbnailCount < 9, "Scrolling exposed clipped native previews");
                }
                finally { window?.Close(); fixture.Close(); }
            });
            Test("Skins: themed slider retains native commands; menu and combo popups honor animation off/on", () =>
            {
                var slider = new Slider { Minimum = 0, Maximum = 100, Value = 0, TickFrequency = 10, IsSnapToTickEnabled = true, LargeChange = 10, Width = 300, Height = 30 };
                var combo = new ComboBox { Width = 200 }; combo.Items.Add("fixture");
                var menu = new MenuItem { Header = "fixture" }; menu.Items.Add(new MenuItem { Header = "submenu" });
                var panel = new StackPanel(); panel.Children.Add(combo); panel.Children.Add(menu); panel.Children.Add(slider);
                WuxiaTheme.Apply(Skin.Protocol, false);
                var host = new Window { Content = panel, Width = 340, Height = 180, Left = -17000, Top = -17000, ShowActivated = false, ShowInTaskbar = false };
                try
                {
                    host.Show(); host.UpdateLayout(); Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                    Check(slider.Style == Application.Current.Resources[typeof(Slider)], "Shown slider did not inherit the application theme");
                    var track = (Track?)slider.Template.FindName("PART_Track", slider);
                    Check(track?.Thumb != null && track.Thumb.Width == 12 && track.Thumb.Height == 18, "Themed slider lost its native track/thumb");
                    Slider.IncreaseLarge.Execute(null, slider);
                    Check(slider.Value > 0 && slider.Value % 10 == 0, "Large-step command did not honor ticks");
                    Slider.DecreaseLarge.Execute(null, slider); Check(slider.Value == 0, "DecreaseLarge stopped routing");
                    var comboPopup = combo.Template.FindName("PART_Popup", combo) as Popup ?? throw new Exception("Combo popup template PART missing");
                    var menuPopup = menu.Template.FindName("PART_Popup", menu) as Popup ?? throw new Exception("Menu popup template PART missing");
                    Check(comboPopup.PopupAnimation == PopupAnimation.None && menuPopup.PopupAnimation == PopupAnimation.None, "Popup animation ignored disabled preference");
                    WuxiaTheme.Apply(Skin.Protocol, true); host.UpdateLayout();
                    Check(comboPopup.PopupAnimation == PopupAnimation.Fade && menuPopup.PopupAnimation == PopupAnimation.Fade, "Popup animation did not re-enable dynamically");
                    WuxiaTheme.Apply(Skin.Protocol, false); host.UpdateLayout();
                    Check(comboPopup.PopupAnimation == PopupAnimation.None && menuPopup.PopupAnimation == PopupAnimation.None, "Existing popup did not react to disabling motion");
                }
                finally { host.Close(); }
            });
        }
        finally { SkinCatalog.DecorationsEnabled = decorations; WuxiaTheme.Apply(original); }
        return results;
    }
    private static byte[] Render(FrameworkElement element)
    {
        element.Width = element.Height = 100; element.Measure(new Size(100, 100)); element.Arrange(new Rect(0, 0, 100, 100)); element.UpdateLayout();
        var bitmap = new RenderTargetBitmap(100, 100, 96, 96, PixelFormats.Pbgra32); bitmap.Render(element);
        var pixels = new byte[100 * 100 * 4]; bitmap.CopyPixels(pixels, 400, 0); return pixels;
    }
    private static IEnumerable<DependencyObject> Descendants(object? node)
    {
        if (node is not DependencyObject current) yield break;
        yield return current;
        foreach (object child in LogicalTreeHelper.GetChildren(current)) foreach (var item in Descendants(child)) yield return item;
    }
    private static IEnumerable<DependencyObject> VisualDescendants(DependencyObject node)
    {
        yield return node;
        if (node is not Visual) yield break;
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(node); i++)
            foreach (var child in VisualDescendants(VisualTreeHelper.GetChild(node, i))) yield return child;
    }
}
