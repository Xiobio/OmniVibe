using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

namespace CodeManager;

public static class SelfTests
{
    public record Result(string Name, bool Passed, string Detail);
    public static List<Result> Run()
    {
        var results = new List<Result>();
        void Test(string name, Action action)
        {
            try { action(); results.Add(new(name, true, "OK")); }
            catch (Exception ex) { results.Add(new(name, false, ex.ToString())); }
        }
        static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
        Test("Tiling: 1–9 windows fill the work area exactly, including odd dimensions and negative origins", () =>
        {
            foreach (var area in new[] { new Native.Rect(0, 0, 1920, 1040), new Native.Rect(-1920, -100, 0, 980), new Native.Rect(0, 0, 1279, 719) })
                for (int count = 1; count <= 9; count++)
                {
                    var cells = Tiling.Arrange(count, area); Check(cells.Count == count, "Count mismatch");
                    foreach (var c in cells) Check(c.X >= area.Left && c.Y >= area.Top && c.X + c.Width <= area.Right && c.Y + c.Height <= area.Bottom && c.Width > 0 && c.Height > 0, "Out of bounds");
                    Check(cells.Sum(c => (long)c.Width * c.Height) == (long)(area.Right - area.Left) * (area.Bottom - area.Top), "Layout left unused space");
                    for (int i = 0; i < count; i++) for (int j = i + 1; j < count; j++)
                        Check(cells[i].X + cells[i].Width <= cells[j].X || cells[j].X + cells[j].Width <= cells[i].X || cells[i].Y + cells[i].Height <= cells[j].Y || cells[j].Y + cells[j].Height <= cells[i].Y, "Overlapping windows");
                }
        });
        Test("Arrangement preferences: every mode fills work area; gaps stay bounded", () =>
        {
            var area = new Native.Rect(-1279, -100, 0, 619);
            foreach (var mode in Enum.GetValues<ArrangementMode>()) for (int count = 1; count <= 9; count++)
            {
                var cells = Tiling.Arrange(count, area, mode);
                Check(cells.Count == count && cells.Sum(c => (long)c.Width * c.Height) == 1279L * 719, "Preference left unused cells");
                for (int i = 0; i < count; i++) for (int j = i + 1; j < count; j++) Check(cells[i].X + cells[i].Width <= cells[j].X || cells[j].X + cells[j].Width <= cells[i].X || cells[i].Y + cells[i].Height <= cells[j].Y || cells[j].Y + cells[j].Height <= cells[i].Y, "Preference overlapped windows");
                Check(Tiling.Arrange(count, area, mode, 20).All(c => c.Width > 0 && c.Height > 0 && c.X >= area.Left && c.Y >= area.Top && c.X + c.Width <= area.Right && c.Y + c.Height <= area.Bottom), "Gap moved windows outside screen");
            }
        });
        Test("Selection: fixed sparse slots, high-resolution wheel, cancel and wrap", () =>
        {
            var selection = new WheelSelection(); int[] numbers = { 1, 4, 9 };
            Check(selection.Move(60, numbers, 1) == null, "Partial wheel should accumulate");
            Check(selection.Move(60, numbers, 1) == 9, "Previous wraps across sparse slots");
            Check(selection.Move(-240, numbers, 1) == 4, "Multiple detents");
            Check(selection.Reset() == 4 && !selection.Active, "Commit clears gesture");
            Check(selection.Move(-120, numbers, 1) == 4, "New gesture uses foreground"); selection.Reset();
            Check(selection.Move(-60, numbers, 1) == null, "Partial gesture"); selection.Reset();
            Check(selection.Move(-60, numbers, 1) == null, "Remainder resets on key release");
            selection.Reset(); Check(selection.Move(-120, numbers, null) == 1, "First gesture from an unrelated app should select the first task");
        });
        Test("Alt mouse gestures: wheel routing, AltGr exclusion and middle-click passthrough", () =>
        {
            Check(MouseGestureRouter.AltOnly(true, false, false, false), "Plain Alt was not accepted");
            Check(!MouseGestureRouter.AltOnly(false, false, false, false), "Bare input was intercepted");
            Check(!MouseGestureRouter.AltOnly(true, true, false, false), "Ctrl+Alt / AltGr was intercepted");
            Check(!MouseGestureRouter.AltOnly(true, false, true, false) && !MouseGestureRouter.AltOnly(true, false, false, true), "Additional modifiers were intercepted");
            var router = new MouseGestureRouter();
            Check(!router.Route(0x20A, false, 120).Consume, "Normal scroll was swallowed");
            Check(!router.Route(0x207, false).Consume && !router.Route(0x208, false).Consume, "Normal middle click was swallowed");
            var wheel = router.Route(0x20A, true, -120);
            Check(wheel.Consume && wheel.WheelDelta == -120 && wheel.MaskAlt, "Alt+wheel was not routed");
            Check(!router.Route(0x20A, true, 120).MaskAlt, "Menu mask repeated within one Alt chord");
            Check(!router.Route(0x207, true).Consume && !router.Route(0x208, true).Consume, "Old Alt+middle binding still intercepted clicks");
            router.AltReleased();
            Check(!router.Route(0x208, false).Consume, "Unrelated release was swallowed");
            Check(router.Route(0x20A, true, 120).MaskAlt, "Next Alt chord did not start cleanly");
        });
        Test("Settings: configurable modifiers, valid toggle keys and off-screen placement", () =>
        {
            Check(MouseGestureRouter.Matches(ShortcutModifiers.CtrlAlt, true, true, false, false), "CtrlAlt setting ignored");
            Check(!MouseGestureRouter.Matches(ShortcutModifiers.Alt, true, true, false, false), "AltGr matched plain Alt");
            Check(MouseGestureRouter.Matches(ShortcutModifiers.CtrlShift, false, true, true, false), "CtrlShift setting ignored");
            Check(InputService.TryParseGesture("Ctrl+Alt+Space", out uint mods, out uint key) && mods == 3 && key == 0x20, "Toggle gesture parsing failed");
            Check(InputService.TryParseGesture("1", out _, out _) && ShortcutBindings.IsTypingKey("1"), "Explicit single-key binding or typing-impact classification failed");
            var area = new Native.Rect(-1920, 0, 0, 1080);
            var cell = WindowLayout.Clamp(new Cell(2400, -500, 2400, 1400), area);
            Check(cell.X == -1920 && cell.Y == 0 && cell.Width == 1920 && cell.Height == 1080, "Disconnected monitor placement was not clamped");
        });
        Test("Input: connected digits only; Tab toggles inventory and yields when paused or disabled", () =>
        {
            using var input = new InputService(Dispatcher.CurrentDispatcher);
            Check(input.RegisteredTasks.Length == 0, "Empty task slots reserve digits");
            Check(!input.ArrangeRegistered, "Empty inventory reserved the arrange shortcut");
            Check(input.TabRegistered || input.Warnings.Any(w => w.StartsWith("总览快捷键")), "Default Tab inventory shortcut neither registered nor reported a conflict");
            input.Configure(new(), new[] { 2, 7 }, false);
            Check(input.ArrangeRegistered || input.Warnings.Any(w => w.StartsWith("排列快捷键")), "Arrange shortcut neither registered nor reported a conflict");
            Check(input.RegisteredTasks.All(n => n is 2 or 7), "Unconnected slot registered a digit");
            input.Configure(new(), new[] { 2, 7 }, true);
            Check(input.RegisteredTasks.Length == 0, "Pause left task keys registered");
            Check(!input.TabRegistered, "Pause left Tab registered");
            Check(!input.ArrangeRegistered, "Pause left Alt+backquote registered");
            Check(!input.RadialRegistered, "Pause left radial chord registered");
            input.Configure(new(), Array.Empty<int>(), false);
            Check(input.RegisteredTasks.Length == 0, "Disconnect left task keys registered");
            Check(!input.ArrangeRegistered, "Disconnected inventory left Alt+backquote registered");
            Check(input.TabRegistered || input.Warnings.Any(w => w.StartsWith("总览快捷键")), "Empty inventory silently lost Tab");
            input.Configure(new() { TabTogglesInventory = false }, Array.Empty<int>(), false);
            Check(!input.TabRegistered, "Disabling Tab did not restore input");
            input.Configure(new() { InventoryGesture = "Ctrl+Alt+Shift+F8", ArrangeGesture = "Ctrl+Alt+Shift+F9" }, new[] { 2 }, false);
            Check(input.TabRegistered && input.ArrangeRegistered, "Custom overview or arrangement gesture was not registered");
        });
        Test("Agent events: real lifecycle mapping, nested-agent filtering and idle notifications", () =>
        {
            string id = Guid.NewGuid().ToString("N");
            StatusEvent? Parse(string provider, string evt, string extra = "") => HookBridge.Parse(provider, id, "{\"hook_event_name\":\"" + evt + "\",\"session_id\":\"session-a\",\"cwd\":\"D:/project\"" + extra + "}");
            Check(Parse("claude", "UserPromptSubmit", ",\"prompt\":\"修复登录\\n详细内容\"") is { State: AgentState.Running, SuggestedName: "修复登录" }, "Prompt was not mapped to running/name");
            Check(Parse("codex", "PermissionRequest")?.State == AgentState.Waiting, "Permission request not mapped to waiting");
            Check(Parse("claude", "PostToolUse")?.State == AgentState.Running, "Permission resumption not mapped to running");
            Check(Parse("codex", "Stop")?.State == AgentState.Ready, "Stop not mapped to turn reply");
            Check(Parse("claude", "StopFailure")?.State == AgentState.Error, "Failure not mapped to error");
            Check(Parse("codex", "SessionEnd")?.SessionEnded == true, "Session end not mapped");
            Check(Parse("claude", "Notification", ",\"notification_type\":\"idle_prompt\"") == null, "Idle reminder incorrectly requires user action");
            Check(Parse("claude", "Notification", ",\"notification_type\":\"permission_prompt\"")?.State == AgentState.Waiting, "Permission notification ignored");
            Check(Parse("codex", "Stop", ",\"agent_id\":\"child\"") == null, "Nested agent overwrote root task state");
            Check(Parse("claude", "SessionStart", ",\"source\":\"compact\"") == null, "Compaction reset active status");
        });
        Test("Persistence: identity, stable task ID, placement, atomic events and corrupt recovery", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "CodeManager-test-" + Guid.NewGuid().ToString("N"));
            try
            {
                var store = new StateStore(directory); var state = new AppState();
                state.Preferences.TaskModifiers = ShortcutModifiers.CtrlShift; state.Preferences.WakeMode = WakeMode.WorkArea;
                state.Preferences.Compact = false; state.Preferences.ToggleGesture = "Ctrl+Shift+F8"; state.Preferences.TabTogglesInventory = false; state.Preferences.SoundEffects = false;
                state.DockVisibleBeforeLayout = true;
                state.Slots[3].Name = "测试任务"; state.Slots[3].Window = new() { Handle = 1234, ProcessId = 42, ProcessStartedUtcTicks = 55 };
                state.Slots[3].CapturePlacement = new Native.Placement { ShowCommand = 1, NormalPosition = new Native.Rect(-1700, 20, -900, 700) };
                string id = state.Slots[3].Id;
                state.Popup = new() { SlotId = id, Window = state.Slots[3].Window!, Placement = state.Slots[3].CapturePlacement!.Value, ParkedByApp = true };
                store.Save(state); var read = store.Load();
                Check(read.Slots[3].Name == "测试任务" && read.Slots[3].Id == id && read.Slots[3].Number == 4, "Task changed");
                Check(read.Slots[3].CapturePlacement!.Value.NormalPosition.Left == -1700, "Placement not persisted");
                Check(read.Preferences.TaskModifiers == ShortcutModifiers.CtrlShift && read.Preferences.WakeMode == WakeMode.WorkArea && !read.Preferences.Compact && read.Preferences.ToggleGesture == "Ctrl+Shift+F8", "Settings did not persist");
                Check(!read.Preferences.TabTogglesInventory, "Tab preference did not persist");
                Check(!read.Preferences.SoundEffects, "Audio preference did not persist");
                Check(read.DockVisibleBeforeLayout == true, "Sidebar restore state did not persist");
                Check(read.Popup?.SlotId == id && read.Popup.ParkedByApp && read.Popup.Placement.NormalPosition.Left == -1700, "Popup restore state did not persist");
                Check(read.Slots[0].Number == 1 && !read.Slots[0].Occupied, "Empty slots compacted");
                store.Send(new() { TaskId = id, State = AgentState.Ready });
                Check(Directory.GetFiles(store.EventsDirectory, "*.json").Length == 1, "Status event missing");
                File.WriteAllText(store.StateFile, "{broken"); Check(store.Load().Slots.Count == 9 && store.LoadWarning != null, "Corrupt state did not recover");
                Check(Directory.GetFiles(directory, "*.recovery-*").Length == 1, "Original state not preserved");
            }
            finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
        });
        Test("Win32: enumerate, validate identity, tile/minimize/restore owned fixture", () =>
        {
            var fixture = new Window { Title = "CodeManager native self-test", Width = 500, Height = 300, Left = 60, Top = 60, ShowActivated = false };
            try
            {
                fixture.Show(); Pump(); var hwnd = new WindowInteropHelper(fixture).Handle;
                var identity = Native.Identify(hwnd, true); Check(identity != null && Native.Matches(identity), "Window not found");
                Check(Native.Windows(true).Any(w => w.Handle == hwnd.ToInt64()), "EnumWindows missed fixture");
                var stale = new WindowIdentity { Handle = hwnd.ToInt64(), ProcessId = Environment.ProcessId, ProcessStartedUtcTicks = 1 };
                Check(!Native.Matches(stale), "Stale identity accepted");
                var original = Native.PlacementOf(hwnd); Check(original.HasValue, "Placement failed");
                Check(Native.SetWindowPos(hwnd, IntPtr.Zero, 90, 90, 640, 400, 0x14), "Tiling failed");
                Native.GetWindowRect(hwnd, out var rect); Check(rect.Right - rect.Left == 640, "Resize failed");
                Check(Native.PlaceVisibleWindow(hwnd, new Cell(120, 120, 600, 360)), "Visible frame placement failed"); Pump();
                var visible = Native.VisibleBounds(hwnd);
                Check(visible.HasValue && Math.Abs(visible.Value.Left - 120) <= 1 && Math.Abs(visible.Value.Top - 120) <= 1 && Math.Abs(visible.Value.Right - 720) <= 1 && Math.Abs(visible.Value.Bottom - 480) <= 1, "Invisible borders left a gap around the target cell");
                Native.ShowWindow(hwnd, 6); Pump(); Check(Native.IsIconic(hwnd), "Minimize failed");
                Native.RestorePlacement(hwnd, original!.Value); Pump(); Check(!Native.IsIconic(hwnd), "Restore failed");
                fixture.Close(); Pump(); Check(!Native.Matches(identity), "Closed window still accepted");
            }
            finally { fixture.Close(); }
        });
        Test("Win32: activating an already focused window raises it above a nonactivating covering window", () =>
        {
            var target = new Window { Title = "CodeManager focus target", Width = 640, Height = 400, Left = 100, Top = 100, ShowActivated = false };
            var covering = new Window { Title = "CodeManager covering fixture", Width = 640, Height = 400, Left = 100, Top = 100, ShowActivated = false };
            try
            {
                target.Show(); covering.Show(); Pump();
                var hwnd = new WindowInteropHelper(target).Handle;
                var cover = new WindowInteropHelper(covering).Handle;
                var identity = Native.Identify(hwnd, true)!;
                Check(Native.Activate(identity), "Could not focus the owned fixture");
                Native.SetWindowPos(cover, IntPtr.Zero, 0, 0, 0, 0, 0x53); Pump();
                Check(Native.GetForegroundWindow() == hwnd && Native.ZOrder(cover) < Native.ZOrder(hwnd), "Could not reproduce a focused but covered window");
                Check(Native.Activate(identity), "Activation failed"); Pump();
                Check(Native.ZOrder(hwnd) < Native.ZOrder(cover), "Foreground API succeeded but the task remained behind the covering window");
                Check(!Native.IsTopmost(hwnd), "Activation left the window permanently topmost");
            }
            finally { target.Close(); covering.Close(); }
        });
        Test("Win32: hotkey registration and low-level mouse/keyboard/drag hooks", () =>
        {
            using var source = new HwndSource(new HwndSourceParameters("CodeManager.Test") { ParentWindow = new IntPtr(-3) });
            Check(Native.RegisterHotKey(source.Handle, 99, 0x4007, 0x7A), "Test shortcut unavailable"); Native.UnregisterHotKey(source.Handle, 99);
            Native.HookProc proc = (code, msg, data) => Native.CallNextHookEx(IntPtr.Zero, code, msg, data);
            Native.WinEventProc winEvent = (_, _, _, _, _, _, _) => { };
            var mouse = Native.SetWindowsHookEx(14, proc, Native.GetModuleHandle(null), 0);
            var keyboard = Native.SetWindowsHookEx(13, proc, Native.GetModuleHandle(null), 0);
            var events = Native.SetWinEventHook(0xA, 0xB, IntPtr.Zero, winEvent, 0, 0, 2);
            try { Check(mouse != IntPtr.Zero && keyboard != IntPtr.Zero && events != IntPtr.Zero, "Hook registration failed: " + Marshal.GetLastWin32Error()); }
            finally { if (mouse != IntPtr.Zero) Native.UnhookWindowsHookEx(mouse); if (keyboard != IntPtr.Zero) Native.UnhookWindowsHookEx(keyboard); if (events != IntPtr.Zero) Native.UnhookWinEvent(events); }
            GC.KeepAlive(proc); GC.KeepAlive(winEvent);
        });
        Test("Win32: DWM live preview relationship between owned fixture windows", () =>
        {
            var source = new Window { Title = "Thumbnail source", Width = 320, Height = 200, ShowActivated = false };
            var destination = new Window { Title = "Thumbnail destination", Width = 320, Height = 200, ShowActivated = false };
            IntPtr thumbnail = IntPtr.Zero;
            try
            {
                source.Show(); destination.Show(); Pump();
                thumbnail = Native.Thumbnail(new WindowInteropHelper(destination).Handle, new WindowInteropHelper(source).Handle, new Native.Rect(10, 10, 250, 150));
                Check(thumbnail != IntPtr.Zero, "DWM registration failed");
            }
            finally { if (thumbnail != IntPtr.Zero) Native.DwmUnregisterThumbnail(thumbnail); source.Close(); destination.Close(); }
        });
        Test("Integration: capture, rename, external status, move fixed slot, overview and cleanup", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "CodeManager-integration-" + Guid.NewGuid().ToString("N"));
            var first = new Window { Title = "AI fixture A", Width = 520, Height = 360, Left = 80, Top = 80, ShowActivated = false };
            var second = new Window { Title = "AI fixture B", Width = 520, Height = 360, Left = 120, Top = 120, ShowActivated = false };
            Manager? manager = null;
            try
            {
                first.Show(); second.Show(); Pump();
                var firstIdentity = Native.Identify(new WindowInteropHelper(first).Handle, true)!;
                var secondIdentity = Native.Identify(new WindowInteropHelper(second).Handle, true)!;
                manager = new Manager(new StateStore(directory));
                manager.State.Preferences.Animate = false; manager.State.Preferences.SoundEffects = false;
                manager.Bind(manager.State.Slots[0], firstIdentity);
                manager.Bind(manager.State.Slots[3], secondIdentity); Pump();
                Check(Native.IsIconic(new(firstIdentity.Handle)) && Native.IsIconic(new(secondIdentity.Handle)), "Capture did not park fixtures");
                manager.State.Slots[0].Name = "登录修复"; manager.Save();
                var now = DateTimeOffset.UtcNow;
                manager.Store.Send(new() { TaskId = manager.State.Slots[0].Id, State = AgentState.Ready, At = now });
                WaitForTask(manager.ProcessPendingEvents());
                Check(manager.State.Slots[0].State == AgentState.Ready && manager.State.Slots[0].Unread, "External result did not show unread");
                manager.Store.Send(new() { TaskId = manager.State.Slots[0].Id, State = AgentState.Running, At = now.AddSeconds(-1) });
                WaitForTask(manager.ProcessPendingEvents()); Check(manager.State.Slots[0].State == AgentState.Ready, "Old event overwrote newer state");
                // Simulate an unwritable state target without touching user settings.
                string savedState = manager.Store.StateFile + ".fixture";
                File.Move(manager.Store.StateFile, savedState); Directory.CreateDirectory(manager.Store.StateFile);
                try {
                    manager.Store.Send(new() { TaskId = manager.State.Slots[0].Id, State = AgentState.Ready, Message = "durability fixture", At = now.AddMilliseconds(100) });
                    var batch = manager.ProcessPendingEvents();
                    Check(ReferenceEquals(batch, manager.ProcessPendingEvents()), "Concurrent polls started duplicate batches");
                    WaitForTask(batch);
                    Check(Directory.GetFiles(manager.Store.EventsDirectory, "*.json").Length == 1, "Failed persistence acknowledged an event");
                }
                finally { Directory.Delete(manager.Store.StateFile); File.Move(savedState, manager.Store.StateFile); }
                WaitForTask(manager.ProcessPendingEvents());
                Check(Directory.GetFiles(manager.Store.EventsDirectory, "*.json").Length == 0 && manager.Store.Load().Slots[0].Message == "durability fixture", "Retry did not durably save before acknowledgement");
                manager.MarkRead(manager.State.Slots[0]); Check(!manager.State.Slots[0].Unread && manager.State.Slots[0].State == AgentState.Ready, "Read conflated with task completion");
                manager.Hotkey(1); Pump();
                Check(manager.State.Popup?.SlotId == manager.State.Slots[0].Id && !Native.IsIconic(new(firstIdentity.Handle)), "Number did not bring up the minimized task");
                manager.Hotkey(1); Pump();
                Check(manager.State.Popup == null && Native.IsIconic(new(firstIdentity.Handle)) && manager.State.Slots[0].ParkedByApp, "Repeated number did not restore minimized state");
                Native.ShowWindow(new(firstIdentity.Handle), 9); Pump();
                var normalPlacement = Native.PlacementOf(new(firstIdentity.Handle))!.Value;
                manager.State.Preferences.WakeMode = WakeMode.WorkArea;
                manager.Hotkey(1); Pump(); manager.Hotkey(1); Pump();
                Check(manager.State.Popup == null && WindowLayout.Same(normalPlacement, Native.PlacementOf(new(firstIdentity.Handle))!.Value), "Repeated number lost a visible window's original size or position");
                manager.State.Preferences.WakeMode = WakeMode.LastPosition; manager.Park(manager.State.Slots[0]);
                var task = manager.State.Slots[0]; task.CustomName = true;
                var linked = HookBridge.Parse("claude", task.Id, "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"current-session\",\"cwd\":\"D:/project\"}", now.AddSeconds(1))!;
                Check(manager.ApplyStatusEvent(task, linked) && task.IntegrationConnected, "Session did not connect");
                var other = HookBridge.Parse("claude", task.Id, "{\"hook_event_name\":\"Stop\",\"session_id\":\"stale-session\"}", now.AddSeconds(2))!;
                Check(!manager.ApplyStatusEvent(task, other), "Another session overwrote this task");
                var prompt = HookBridge.Parse("claude", task.Id, "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"current-session\",\"prompt\":\"不应替换手工名称\"}", now.AddSeconds(3))!;
                Check(manager.ApplyStatusEvent(task, prompt) && task.Name == "登录修复", "Hook replaced a custom task name");
                string id = manager.State.Slots[0].Id;
                new EquipmentAssignment("bow", "", "").Apply(manager.State.Slots[0]);
                manager.State.Slots[0].EquipmentSelections[Skin.Hextech.ToString()] = EquipmentCatalog.ForSkin(Skin.Hextech)[2].Id;
                var movedEquipment = EquipmentAssignment.From(manager.State.Slots[0]);
                var emptyEquipment = EquipmentAssignment.From(manager.State.Slots[8]);
                manager.MoveSlot(manager.State.Slots[0], manager.State.Slots[8]);
                Check(EquipmentAssignment.From(manager.State.Slots[8]) == movedEquipment && EquipmentAssignment.From(manager.State.Slots[0]) == emptyEquipment, "Moving a task lost its weapon assignment or the empty slot preset");
                Check(!manager.State.Slots[0].Occupied && manager.State.Slots[8].Id == id && manager.State.Slots[8].Name == "登录修复" && manager.State.Slots[3].Number == 4, "Move changed unrelated fixed slot");
                int windowsBeforeInventory = Application.Current.Windows.Count;
                manager.Hotkey(11); Pump();
                Check(manager.Inventory != null && manager.State.Layout.Count == 0 && Native.IsIconic(new(firstIdentity.Handle)) && Native.IsIconic(new(secondIdentity.Handle)), "Tab moved windows instead of showing inventory");
                var inventory = manager.Inventory!;
                Check(inventory.ThumbnailCount == 2, "Wuxia scrolls did not register the real fixture thumbnails");
                Check(Application.Current.Windows.Count == windowsBeforeInventory + 1, "Compact overview opened an extra full-screen surface");
                inventory.Select(9); Check(inventory.SelectedNumber == 9, "Compact overview lost a sparse occupied slot");
                inventory.Browse(-120); Pump();
                Check(manager.Inventory != null && Native.IsIconic(new(firstIdentity.Handle)) && Native.IsIconic(new(secondIdentity.Handle)), "Inventory wheel activated without confirmation");
                int chosen = inventory.SelectedNumber!.Value;
                inventory.Enter(); Pump();
                Check(Application.Current.Windows.Count == windowsBeforeInventory, "Closing inventory left an overview or thumbnail window behind");
                Check(manager.Inventory == null && !Native.IsIconic(new(manager.State.Slots[chosen - 1].Window!.Handle)), "Inventory selection did not close and enter its window");
                manager.ParkAll();
                manager.ToggleInventory(); Pump(); manager.ToggleInventory(); Pump();
                Check(manager.Inventory == null && manager.State.Layout.Count == 0, "Second Tab did not dismiss inventory");
                var priorFocus = Native.GetForegroundWindow();
                manager.OpenRadial(); Pump();
                Check(manager.Radial != null && manager.Inventory == null && Native.GetForegroundWindow() == priorFocus, "Wheel did not open without taking focus");
                Check(Native.IsIconic(new(firstIdentity.Handle)) && Native.IsIconic(new(secondIdentity.Handle)), "Wheel moved tasks before confirmation");
                manager.Radial!.Surface.Select(4); manager.Radial.Complete(true); Pump();
                Check(manager.Radial == null && Native.GetForegroundWindow().ToInt64() == secondIdentity.Handle, "Wheel did not equip its confirmed task");
                manager.ParkAll();
                manager.OpenRadial(); Pump(); manager.Radial!.Surface.Select(1); manager.Radial.Complete(true); Pump();
                Check(manager.Radial == null && Native.IsIconic(new(firstIdentity.Handle)) && Native.IsIconic(new(secondIdentity.Handle)), "Empty wheel sector woke a task");
                manager.OpenRadial(); Pump(); manager.TogglePause(); Pump();
                Check(manager.Radial == null, "Pause left the wheel open"); manager.TogglePause();
                var equipment = (DockWeaponWheel)manager.Dock.FindName("WeaponWheel");
                manager.Dock.UpdateLayout();
                IntPtr hoverFocus = Native.GetForegroundWindow();
                manager.Dock.HandleWheelPointerMove(equipment.Centre);
                Check(equipment.IsDeployed && !manager.Dock.IsManipulating && Native.GetForegroundWindow() == hoverFocus && Native.IsIconic(new(firstIdentity.Handle)) && Native.IsIconic(new(secondIdentity.Handle)), "Hover activated a task or stole terminal focus");
                var management = manager.Dock.BuildManagementMenu();
                var commands = management.Items.OfType<System.Windows.Controls.MenuItem>().ToList();
                Check(commands.Count == 8 && commands.All(c => c.Items.Count == 0), "Management menu must stay flat and contain only eight immediate actions");
                foreach (string command in new[] { "添加窗口", "任务总览", "排列窗口", "设置", "快速上手", "最近任务 / 恢复工作现场" })
                    Check(commands.Any(i => i.Header?.ToString() == command), "Quick command missing from menu: " + command);
                manager.Dock.CancelManipulation();
                Check(equipment.Cursor == System.Windows.Input.Cursors.Hand, "Cancel did not restore the core cursor");
                IntPtr dragFocus = Native.GetForegroundWindow();
                Native.GetWindowRect(new WindowInteropHelper(manager.Dock).Handle, out var beforeDrag);
                manager.Dock.BeginCorePress(equipment.Centre);
                Check(manager.Dock.IsManipulating && manager.Dock.IsMouseCaptureWithin && !equipment.Aiming, "Core press did not capture without selecting a task");
                manager.Dock.PromoteCoreDrag();
                Check(!equipment.IsDeployed && equipment.Cursor == System.Windows.Input.Cursors.SizeAll, "Hold did not promote to moving the ring");
                manager.Dock.EndCorePress(); Pump();
                manager.ChangeDockBounds(-48, 24, false); manager.CommitDockMove();
                Native.GetWindowRect(new WindowInteropHelper(manager.Dock).Handle, out var movedDock);
                Check(movedDock.Left != beforeDrag.Left || movedDock.Top != beforeDrag.Top, "Drag did not move the native overlay");
                var savedDock = manager.Store.Load().Preferences;
                Check(savedDock.FreeDockPosition && savedDock.DockPosition.X == movedDock.Left && savedDock.DockPosition.Y == movedDock.Top, "Release did not persist the moved ring");
                Check(!manager.Dock.IsManipulating && !manager.Dock.IsMouseCaptureWithin && equipment.Cursor == System.Windows.Input.Cursors.Hand && !equipment.IsDeployed, "Release retained drag capture or reopened tasks");
                Check(Native.GetForegroundWindow() == dragFocus && Native.IsIconic(new(firstIdentity.Handle)) && Native.IsIconic(new(secondIdentity.Handle)), "Moving the ring activated a task or stole focus");
                manager.Dock.HandleWheelPointerMove(equipment.Centre + new Vector(600, 0));
                manager.Dock.HandleWheelPointerMove(equipment.Centre);
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Right, true, equipment.Centre);
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Right, false, equipment.Centre); Pump();
                var openedMenu = equipment.ContextMenu;
                Check(manager.Dock.MenuOpen && openedMenu?.IsOpen == true && openedMenu.ActualHeight > 20, "Right-click management menu did not render a popup");
                manager.Dock.CheckRetraction(equipment.Centre + new Vector(900, 0), DateTime.UtcNow.AddSeconds(2));
                Check(openedMenu!.IsOpen, "Retraction dismissed an open menu");
                var closeButton = openedMenu.Template.FindName("CloseMenuButton", openedMenu) as System.Windows.Controls.Button;
                Check(closeButton != null, "Compact menu has no explicit close button");
                closeButton!.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
                Check(!manager.Dock.MenuOpen && !openedMenu.IsOpen, "Close button did not dismiss immediately");
                manager.Dock.OpenWheelMenu(); Pump();
                manager.Dock.DismissMenuOutside(new Native.Point(-30000, -30000)); Pump();
                Check(!manager.Dock.MenuOpen, "Closing the menu retained the open-menu guard");
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Left, true, equipment.Centre);
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Left, false, equipment.Centre);
                Check(!equipment.IsDeployed, "Dismissal click immediately reopened the task deck");
                manager.Dock.SetEquipmentDeployment(true, false);
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Right, true, equipment.SlotPoint(4));
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Right, false, equipment.SlotPoint(4)); Pump();
                Check(equipment.ContextMenu?.IsOpen == true && equipment.ContextMenu.Items.OfType<System.Windows.Controls.MenuItem>().Any(i => i.Header?.ToString() == "\u66f4\u591a\u4efb\u52a1\u64cd\u4f5c"), "Slot context menu did not retain global management commands");
                equipment.ContextMenu!.IsOpen = false; Pump();
                manager.ToggleVisibility(); manager.Wheel(-120); Pump();
                Check(!manager.Dock.IsVisible && manager.State.Layout.Count == 0 && (!Native.IsIconic(new(firstIdentity.Handle)) || !Native.IsIconic(new(secondIdentity.Handle))), "Alt wheel showed intermediate UI or failed to activate immediately");
                manager.ParkAll();
                manager.ToggleVisibility();
                manager.Hotkey(0); Pump();
                Check(manager.State.Layout.Count == 2 && !Native.IsIconic(new(firstIdentity.Handle)) && !Native.IsIconic(new(secondIdentity.Handle)), "Overview did not expand fixtures");
                Check(manager.Dock.IsVisible && manager.State.DockVisibleBeforeLayout == true, "Arrangement hid the persistent dock entrance");
                var firstTile = Native.PlacementOf(new(firstIdentity.Handle))!.Value;
                var secondTile = Native.PlacementOf(new(secondIdentity.Handle))!.Value;
                manager.Hotkey(9); Pump();
                var expanded = Native.VisibleBounds(new(firstIdentity.Handle))!.Value;
                Check(manager.State.Layout.Count == 2 && manager.State.Popup?.Window.Handle == firstIdentity.Handle && expanded.Left == manager.WorkArea.Left && expanded.Top == manager.WorkArea.Top && expanded.Right == manager.WorkArea.Right && expanded.Bottom == manager.WorkArea.Bottom, "Number after arrangement failed to expand the task or discarded the layout");
                Check(WindowLayout.Same(secondTile, Native.PlacementOf(new(secondIdentity.Handle))!.Value), "Popup changed another tiled window");
                manager.Hotkey(9); Pump();
                Check(manager.State.Popup == null && manager.State.Layout.Count == 2 && WindowLayout.Same(firstTile, Native.PlacementOf(new(firstIdentity.Handle))!.Value) && manager.Dock.IsVisible, "Repeated number did not restore the original tile or hid the dock");
                manager.Hotkey(9); manager.Hotkey(4); Pump();
                Check(manager.State.Popup?.Window.Handle == secondIdentity.Handle && WindowLayout.Same(firstTile, Native.PlacementOf(new(firstIdentity.Handle))!.Value), "Switching numbers left the previous task expanded");
                manager.Hotkey(4); Pump();
                Check(manager.State.Popup == null && WindowLayout.Same(secondTile, Native.PlacementOf(new(secondIdentity.Handle))!.Value), "Second task did not return to its tile");
                manager.Hotkey(9);
                manager.Hotkey(0); Pump();
                Check(manager.State.Layout.Count == 0 && manager.State.Popup == null && Native.IsIconic(new(firstIdentity.Handle)), "Overview did not restore parked placement and clear the popup");
                Check(manager.Dock.IsVisible && manager.State.DockVisibleBeforeLayout == null, "Layout restore lost the visible sidebar");
                manager.Hotkey(9); Pump();
                Check(manager.State.Popup?.Window.Handle == firstIdentity.Handle && !Native.IsIconic(new(firstIdentity.Handle)), "Arrange -> restore -> number failed to show the task");
                manager.Hotkey(9); Pump();
                Check(manager.State.Popup == null && Native.IsIconic(new(firstIdentity.Handle)), "Number after layout restore did not toggle back");
                Native.ShowWindow(new(firstIdentity.Handle), 9); Pump();
                var visibleBefore = Native.PlacementOf(new(firstIdentity.Handle))!.Value;
                manager.Hotkey(0); manager.Hotkey(0); manager.Hotkey(9); Pump();
                Check(manager.State.Layout.Count == 0 && manager.State.Popup?.Window.Handle == firstIdentity.Handle && Native.GetForegroundWindow().ToInt64() == firstIdentity.Handle, "Visible window did not become foreground after arrange/restore");
                manager.Hotkey(9); Pump();
                Check(WindowLayout.Same(visibleBefore, Native.PlacementOf(new(firstIdentity.Handle))!.Value), "Visible window did not return to its pre-popup placement");
                manager.ParkAll();
                manager.ToggleVisibility(); manager.Hotkey(0); manager.Hotkey(0); Pump();
                Check(!manager.Dock.IsVisible, "Layout restore showed an originally hidden sidebar");
                manager.TogglePause(); manager.TogglePause();
                manager.Bind(manager.State.Slots[8], firstIdentity); Pump();
                Check(manager.State.Slots[8].Name == "登录修复" && !manager.State.Slots[8].IntegrationConnected && manager.State.Slots[8].SessionId == "", "Reconnect lost name or kept a stale session");
                manager.Hotkey(9);
                var movedTask = manager.State.Slots[8]; string stableId = movedTask.Id;
                manager.ReorderSlot(movedTask, manager.State.Slots[3]); Pump();
                Check(EquipmentAssignment.From(movedTask) == movedEquipment && manager.Store.Load().Slots.Single(s => s.Id == movedTask.Id).EquipmentId == "bow", "Reorder or reconnect changed the chosen weapon");
                Check(movedTask.Number == 4 && manager.State.Slots[3] == movedTask && manager.State.Slots.Select(s => s.Number).SequenceEqual(Enumerable.Range(1, 9)), "Reordering lost sequential slot numbers");
                Check(manager.State.Popup?.SlotId == stableId && manager.State.Slots.Select(s => s.Id).Distinct().Count() == 9, "Reorder lost popup identity or duplicated task IDs");
                var reorderedStatus = new StatusEvent { TaskId = stableId, State = AgentState.Waiting, At = now.AddMinutes(1) };
                Check(manager.ApplyStatusEvent(movedTask, reorderedStatus) && movedTask.State == AgentState.Waiting, "Reordered task lost its status event routing");
                manager.Hotkey(4); Pump(); Check(manager.State.Popup == null, "New number failed to restore the original popup");
                manager.ChangeDockBounds(-50000, -50000, false); manager.ChangeDockBounds(80, 40, true); Pump();
                var dockBounds = Native.VisibleBounds(new WindowInteropHelper(manager.Dock).Handle)!.Value;
                Check(dockBounds.Left >= manager.WorkArea.Left && dockBounds.Top >= manager.WorkArea.Top && manager.State.Preferences.FreeDockPosition && manager.State.Preferences.DockHeight > 0, "Moved dock left the work area or lost its custom size");
                manager.Dock.CompleteSlotDrop(movedTask, movedTask, false); Check(movedTask.Occupied, "Dropping onto original task unexpectedly removed it");
                manager.Dock.CompleteSlotDrop(movedTask, null, true); Pump();
                Check(!movedTask.Occupied && Native.Matches(firstIdentity) && !Native.IsIconic(new(firstIdentity.Handle)), "Quick removal closed or stranded the terminal window");
                foreach (var skin in Enum.GetValues<Skin>()) { var old = WuxiaTheme.Wood; WuxiaTheme.Apply(skin); manager.Dock.RefreshTheme(); Pump(); Check(WuxiaTheme.CurrentSkin == skin && !ReferenceEquals(old, WuxiaTheme.Wood), "Live skin switching failed"); }
                var savedPreferences = manager.Store.Load().Preferences;
                Check(savedPreferences.FreeDockPosition && savedPreferences.DockWidth == manager.State.Preferences.DockWidth && savedPreferences.DockHeight == manager.State.Preferences.DockHeight, "Dock bounds did not survive persistence");
                manager.Dispose(); manager.Dock.Close(); Pump();
                Check(!Native.IsIconic(new(firstIdentity.Handle)) && !Native.IsIconic(new(secondIdentity.Handle)), "Exit stranded parked fixtures");
                Check(manager.State.Popup == null, "Exit kept a pending popup snapshot");
                manager = null;
            }
            finally
            {
                if (manager != null) { manager.Dispose(); manager.Dock.Close(); }
                first.Close(); second.Close();
                if (Directory.Exists(directory)) Directory.Delete(directory, true);
            }
        });
        Test("Interaction: persistent entrance, immediate hints, direct removal and closed-task history", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "OmniVibe-interaction-" + Guid.NewGuid().ToString("N"));
            var first = new Window { Title = "Interaction fixture A", Width = 420, Height = 260, ShowActivated = false };
            var second = new Window { Title = "Interaction fixture B", Width = 420, Height = 260, ShowActivated = false };
            Manager? manager = null; int starts = 0;
            try {
                first.Show(); second.Show(); Pump();
                var firstIdentity = Native.Identify(new WindowInteropHelper(first).Handle, true)!;
                var secondIdentity = Native.Identify(new WindowInteropHelper(second).Handle, true)!;
                var store = new StateStore(directory); var initial = new AppState();
                initial.Preferences.Skin = Skin.Arsenal; initial.Preferences.Animate = false; initial.Preferences.SoundEffects = false;
                initial.Preferences.HideDockOnArrange = true; initial.Preferences.ShowRecoveryOnStartup = false; store.Save(initial);
                manager = new Manager(store, startRecovery: _ => starts++);
                manager.Bind(manager.State.Slots[0], firstIdentity); manager.Bind(manager.State.Slots[1], secondIdentity);
                var slot = manager.State.Slots[1]; slot.Name = "Keep recovery metadata"; slot.ProjectDirectory = directory; slot.Notes = "Resume this work"; slot.LaunchMode = LaunchMode.Terminal; slot.EquipmentId = "bow";
                string closedId = slot.Id;
                var wheel = (DockWeaponWheel)manager.Dock.FindName("WeaponWheel");
                manager.ToggleOverview(); Check(manager.Dock.IsVisible && Native.IsTopmost(new WindowInteropHelper(manager.Dock).Handle), "Arrangement hid or covered the entrance");
                manager.ToggleOverview(); Check(manager.Dock.IsVisible, "Layout restoration hid the entrance");
                manager.Dock.SetEquipmentDeployment(true, false); manager.Dock.UpdateLayout();
                var focus = Native.GetForegroundWindow(); var watch = Stopwatch.StartNew();
                manager.Dock.HandleWheelPointerMove(wheel.SlotPoint(1)); watch.Stop();
                Check(manager.Dock.HoverHintVisible && manager.Dock.HoverHintNumber == 1 && watch.ElapsedMilliseconds < 250, "Task hint waited for a dwell timer");
                Check(Native.GetForegroundWindow() == focus, "Immediate hint took terminal focus");
                manager.Dock.HandleWheelPointerMove(wheel.SlotPoint(2)); Check(manager.Dock.HoverHintNumber == 2, "Moving to another task retained a stale hint");
                Check(wheel.HitSlot(wheel.SlotPoint(3)) == manager.State.Slots[2], "Empty plus target requires a right click or external drag");
                bool pickerOpened = false;
                Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, () => {
                    var picker = Application.Current.Windows.OfType<Window>().FirstOrDefault(w => w.Title == "绑定窗口到槽位 3");
                    if (picker != null) { pickerOpened = true; picker.DialogResult = false; }
                });
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Left, true, wheel.SlotPoint(3));
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Left, false, wheel.SlotPoint(3));
                Check(pickerOpened && !manager.State.Slots[2].Occupied, "Left clicking plus did not open the picker, or cancelling changed the slot");
                manager.Dock.SetEquipmentDeployment(true, false);
                manager.Dock.HandleWheelPointerMove(wheel.SlotPoint(1));
                var removePoint = wheel.RemovePoint(manager.State.Slots[0]); Check(wheel.HitRemove(removePoint) == manager.State.Slots[0], "Hover removal has no direct hit target");
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Left, true, removePoint);
                manager.Dock.HandlePointerButton(System.Windows.Input.MouseButton.Left, false, removePoint);
                Check(!manager.State.Slots[0].Occupied && Native.Matches(firstIdentity) && !Native.IsIconic(new(firstIdentity.Handle)), "Removal closed or stranded the actual terminal");
                manager.Dock.ClosePreview(); second.Close();
                manager.ArchiveClosedWindows();
                Check(!slot.Occupied && manager.State.RecentTasks.Count == 1, "Closed window left a zombie task in the live deck");
                var saved = store.Load().RecentTasks.Single().Task;
                Check(saved.Id == closedId && saved.Notes == "Resume this work" && saved.EquipmentId == "bow" && saved.ProjectDirectory == directory, "Closed-task history lost recovery data");
                manager.RestoreTask(manager.State.RecentTasks[0].Task);
                Check(starts == 1 && manager.State.RecentTasks.Count == 0 && manager.State.Slots.Any(s => s.Id == closedId && s.Recovery != null), "History could not reclaim a free slot under the original identity");
                var startupMissing = manager.State.Slots[2]; string startupId = startupMissing.Id;
                startupMissing.Window = new() { Handle = 0, Title = "Startup missing fixture", ProcessName = "WindowsTerminal" };
                manager.StartupRecovery();
                Check(!startupMissing.Occupied && store.Load().RecentTasks.Any(r => r.Task.Id == startupId), "An already-closed startup window remained a zombie slot or lost its history");
                manager.Dock.Hide(); manager.EnsureDockVisible(); Check(manager.Dock.IsVisible, "Unexpected visibility loss was not repaired");
                manager.ToggleVisibility(); manager.EnsureDockVisible(); Check(!manager.Dock.IsVisible, "Visibility repair overrode explicit hide");
                manager.ToggleVisibility(); Check(manager.Dock.IsVisible, "Explicit show did not restore the entrance");
                manager.Dispose(); manager.Dock.Close(); manager = null;
            } finally {
                if (manager != null) { manager.Dispose(); manager.Dock.Close(); }
                first.Close(); second.Close(); if (Directory.Exists(directory)) Directory.Delete(directory, true);
            }
        });
        Test("Hook transport: PowerShell observer emits Unicode event without agent instructions", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "CodeManager-hook-" + Guid.NewGuid().ToString("N"));
            try
            {
                var store = new StateStore(directory); string id = Guid.NewGuid().ToString("N");
                var info = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardInputEncoding = Encoding.UTF8 };
                foreach (string argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(AppContext.BaseDirectory, "scripts", "Receive-AgentHook.ps1"), "-TaskId", id, "-Provider", "claude", "-DataRoot", directory, "-ApplicationPath", Path.Combine(AppContext.BaseDirectory, "CodeManager.exe") }) info.ArgumentList.Add(argument);
                using var process = Process.Start(info)!;
                process.StandardInput.Write("{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s1\",\"cwd\":\"D:/测试项目\",\"prompt\":\"修复登录问题\"}"); process.StandardInput.Close();
                if (!process.WaitForExit(10000)) { process.Kill(true); throw new Exception("Observer timed out"); }
                string output = process.StandardOutput.ReadToEnd(); string error = process.StandardError.ReadToEnd();
                Check(process.ExitCode == 0 && output.Trim() == "" && error.Trim() == "", "Observer wrote to agent output: " + output + error);
                var files = Directory.GetFiles(store.EventsDirectory, "*.json");
                string diagnostics = string.Join(" ", Directory.GetFiles(directory, "*.log").Select(File.ReadAllText));
                Check(files.Length == 1, "Observer emitted no event: " + diagnostics);
                var evt = JsonSerializer.Deserialize<StatusEvent>(File.ReadAllText(files[0]), StateStore.Json)!;
                Check(evt.TaskId == id && evt.State == AgentState.Running && evt.ProjectDirectory == "D:/测试项目" && evt.SuggestedName == "修复登录问题", "Observer corrupted Unicode or task identity");
            }
            finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
        });
        Test("Recovery: exact matching, ambiguity rejection, startup quoting and saved session metadata", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "CodeManager-recovery-" + Guid.NewGuid().ToString("N"));
            try
            {
                var store = new StateStore(directory); var state = new AppState(); var slot = state.Slots[0];
                slot.Window = new() { Title = "测试任务 | unique-project", ProcessName = "WindowsTerminal" }; slot.Name = "测试任务";
                Check(RecoveryLaunch.Validation(slot) != null, "Unconfigured task was launched");
                slot.LaunchMode = LaunchMode.Codex; slot.ProjectDirectory = directory; slot.ResumeConversation = true;
                Check(RecoveryLaunch.Validation(slot)!.Contains("会话 ID"), "Missing session was silently replaced by latest chat");
                slot.ResumeSessionId = Guid.NewGuid().ToString(); slot.Notes = "先看未提交修改"; slot.Recovery = new() { Token = Guid.NewGuid().ToString("N") };
                Check(RecoveryLaunch.Validation(slot) == null, "Configured task was rejected");
                state.Preferences.AutoRestoreOnStartup = true; store.Save(state); var read = store.Load();
                Check(read.Slots[0].Id == slot.Id && read.Slots[0].ResumeSessionId == slot.ResumeSessionId && read.Slots[0].Notes == slot.Notes && read.Slots[0].Recovery!.Token == slot.Recovery.Token && read.Preferences.AutoRestoreOnStartup, "Recovery checkpoint did not survive reload");
                var candidate = new WindowIdentity { Title = slot.Window.Title, ProcessName = "WindowsTerminal", Handle = 9999 };
                Check(RecoveryLaunch.ExistingMatch(slot, state.Slots, new[] { candidate }) == candidate, "Unique exact title did not reconnect");
                Check(RecoveryLaunch.ExistingMatch(slot, state.Slots, new[] { candidate, new WindowIdentity { Title = candidate.Title, ProcessName = candidate.ProcessName, Handle = 9998 } }) == null, "Ambiguous titles were guessed");
                state.Slots[1].Window = new() { Title = candidate.Title, ProcessName = candidate.ProcessName };
                Check(RecoveryLaunch.ExistingMatch(slot, state.Slots, new[] { candidate }) == null, "Same-title tasks shared a window"); state.Slots[1].Window = null;
                slot.Window.Title = candidate.Title = "Windows Terminal"; Check(RecoveryLaunch.ExistingMatch(slot, state.Slots, new[] { candidate }) == null, "Generic shell title was trusted");
                candidate.Title = "CM-RESTORE-" + slot.Recovery.Token;
                Check(RecoveryLaunch.PendingMatch(slot.Recovery, new[] { candidate }) == candidate && RecoveryLaunch.PendingMatch(new() { Token = "bad-token" }, new[] { candidate }) == null, "Launch identity validation failed");
                string script = RecoveryLaunch.Script(slot, store, slot.Recovery);
                Check(script.Contains("-ResumeSessionId '" + slot.ResumeSessionId + "'") && !script.Contains("--last") && !script.Contains("Invoke-Expression"), "Resume could target another task or execute captured title");
                Check(RecoveryLaunch.Quote("任务' $(whoami)") == "'任务'' $(whoami)'", "PowerShell literals were not escaped");
                var start = RecoveryLaunch.StartInfo(slot, store, slot.Recovery, Path.Combine(directory, "missing-wt.exe"));
                Check(start.ArgumentList.Contains("-EncodedCommand") && start.ArgumentList.Contains("-NoExit"), "Recovery shell was not interactive or command encoding was missing");
                var cliSlot = new Slot { Id = slot.Id, Window = slot.Window }; var id = Guid.NewGuid().ToString();
                var evt = HookBridge.Parse("claude", cliSlot.Id, "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"" + id + "\",\"cwd\":\"D:/project\"}")!;
                Check(evt.SessionId == id, "Hook dropped the saved session ID");
            }
            finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
        });
        Test("Recovery: repeat suppression, title handshake, stable identity, move and timeout", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "CodeManager-recovery-flow-" + Guid.NewGuid().ToString("N")); Manager? manager = null;
            var fixture = new Window { Width = 420, Height = 260, Left = 100, Top = 100, ShowActivated = false }; int starts = 0;
            try
            {
                var store = new StateStore(directory); var initial = new AppState(); initial.Preferences.Animate = false; initial.Preferences.SoundEffects = false; initial.Preferences.TabTogglesInventory = false;
                initial.Slots[0].Window = new() { Title = "Saved recovery fixture", ProcessName = "WindowsTerminal" }; initial.Slots[0].Name = "保存的任务"; initial.Slots[0].ProjectDirectory = directory; initial.Slots[0].LaunchMode = LaunchMode.Terminal; store.Save(initial);
                manager = new Manager(store, startRecovery: _ => starts++); var slot = manager.State.Slots[0]; string id = slot.Id;
                manager.RestoreTask(slot); manager.RestoreTask(slot); Check(starts == 1 && slot.Recovery != null, "Repeated clicks opened duplicate windows");
                var pending = slot.Recovery!; Check(store.Load().Slots[0].Recovery?.Token == pending.Token, "Launch was not checkpointed before starting");
                fixture.Title = "CM-RESTORE-" + pending.Token; fixture.Show(); Pump();
                var identity = Native.Identify(new WindowInteropHelper(fixture).Handle, true)!; identity.ProcessName = "WindowsTerminal";
                manager.ProcessRecoveries(new[] { identity }); Pump();
                Check(slot.Connected && slot.Id == id && slot.Recovery == null && File.Exists(RecoveryLaunch.Acknowledgement(store, pending)), "New terminal was not bound before acknowledgement");
                manager.RestoreTask(slot); Check(starts == 1, "Connected window was relaunched");
                manager.MoveSlot(slot, manager.State.Slots[4]); var moved = manager.State.Slots[4]; Check(moved.LaunchMode == LaunchMode.Terminal && moved.ProjectDirectory == directory && moved.Id == id, "Moving a task lost recovery data");
                var evt = new StatusEvent { TaskId = id, Provider = "claude", SessionId = Guid.NewGuid().ToString(), EventName = "SessionStart", ProjectDirectory = directory, State = AgentState.Unknown, At = DateTimeOffset.UtcNow };
                moved.LaunchMode = LaunchMode.Unconfigured; manager.ApplyStatusEvent(moved, evt); Check(moved.ResumeSessionId == evt.SessionId && moved.LaunchMode == LaunchMode.Claude, "Hook did not remember the AI session and launch mode");
                fixture.Close(); Pump(); moved.Window = new() { Title = "Missing", ProcessName = "WindowsTerminal" }; moved.Recovery = new() { Token = Guid.NewGuid().ToString("N"), StartedAt = DateTimeOffset.UtcNow.AddMinutes(-1) };
                manager.ProcessRecoveries(Array.Empty<WindowIdentity>()); Check(moved.Recovery == null && moved.RecoveryError.Contains("超时") && starts == 1, "Expired launch retried or remained pending");
            }
            finally { manager?.Dispose(); manager?.Dock.Close(); fixture.Close(); if (Directory.Exists(directory)) Directory.Delete(directory, true); }
        });
        Test("Recovery: Claude launcher forwards only the specified resume ID", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "CodeManager-resume-" + Guid.NewGuid().ToString("N"));
            try
            {
                var store = new StateStore(directory); var state = new AppState(); state.Slots[0].Window = new() { Title = "fixture" }; store.Save(state);
                string output = Path.Combine(directory, "args.json"), id = Guid.NewGuid().ToString();
                string starter = Path.Combine(AppContext.BaseDirectory, "scripts", "Start-TrackedSession.ps1");
                string script = "function global:claude { $args | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath " + RecoveryLaunch.Quote(output) + "; $global:LASTEXITCODE=0 }; & " + RecoveryLaunch.Quote(starter) + " -TaskId " + RecoveryLaunch.Quote(state.Slots[0].Id) + " -Provider claude -DataRoot " + RecoveryLaunch.Quote(directory) + " -ResumeSessionId " + RecoveryLaunch.Quote(id);
                var info = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
                foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-EncodedCommand", Convert.ToBase64String(Encoding.Unicode.GetBytes(script)) }) info.ArgumentList.Add(argument);
                using var process = Process.Start(info)!; if (!process.WaitForExit(10000)) { process.Kill(true); throw new Exception("Resume launcher test timed out"); }
                Check(process.ExitCode == 0 && File.Exists(output), "Resume argument forwarding failed: " + process.StandardError.ReadToEnd());
                var arguments = JsonSerializer.Deserialize<string[]>(File.ReadAllText(output).TrimStart('\uFEFF'))!;
                Check(arguments.Contains("--resume") && arguments.Last() == id && !arguments.Contains("--continue"), "Launcher resumed a different session or submitted a prompt");
            }
            finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
        });
        results.AddRange(ReliabilityTests.Run());
        results.AddRange(SkinTests.Run());
        return results;
    }
    public static Result RecoverySmoke()
    {
        string directory = Path.Combine(Path.GetTempPath(), "CodeManager-live-recovery-" + Guid.NewGuid().ToString("N")); Manager? manager = null; WindowIdentity? opened = null;
        string expectedTitle = "CodeManager recovery smoke " + Guid.NewGuid().ToString("N"); bool passed = false; string detail = "";
        bool Wait(Func<bool> done, int seconds)
        {
            var frame = new DispatcherFrame(); var watch = Stopwatch.StartNew(); bool finished = false;
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
            timer.Tick += (_, _) => { if (done()) { finished = true; frame.Continue = false; } else if (watch.Elapsed.TotalSeconds > seconds) frame.Continue = false; };
            timer.Start(); Dispatcher.PushFrame(frame); timer.Stop(); return finished;
        }
        try
        {
            var store = new StateStore(directory); var initial = new AppState(); initial.Preferences.Animate = false; initial.Preferences.SoundEffects = false; initial.Preferences.TabTogglesInventory = false;
            var saved = initial.Slots[0]; saved.Name = expectedTitle; saved.Window = new() { Title = expectedTitle, ProcessName = "WindowsTerminal" }; saved.LaunchMode = LaunchMode.Terminal; saved.ProjectDirectory = directory; store.Save(initial);
            manager = new Manager(store); var slot = manager.State.Slots[0]; string id = slot.Id;
            string started = manager.RestoreTask(slot);
            if (!Wait(() => { manager.ProcessRecoveries(); if (slot.Connected && Native.Matches(slot.Window)) opened = slot.Window; return opened != null && Native.Title(new(opened.Handle)).Contains(expectedTitle, StringComparison.Ordinal); }, 18)) throw new Exception("Real shell did not finish title handshake: " + started + " / " + slot.RecoveryError + " / connected=" + slot.Connected);
            if (slot.Id != id || slot.Recovery != null || store.Load().Slots[0].Window?.Handle != opened!.Handle) throw new Exception("Recovery did not persist the new window under the original task ID");
            string repeat = manager.RestoreTask(slot); if (!repeat.Contains("无需重复")) throw new Exception("Reconnected shell was duplicated");
            passed = true; detail = "A real isolated terminal opened, completed acknowledgement, reconnected to its original task ID and suppressed duplicate launch.";
        }
        catch (Exception ex) { detail = ex.ToString(); }
        finally
        {
            if (opened == null && manager?.State.Slots[0].Recovery is PendingRecovery pending) opened = RecoveryLaunch.PendingMatch(pending, Native.Windows());
            manager?.Dispose(); manager?.Dock.Close();
            if (opened != null && Native.Matches(opened) && (Native.Title(new(opened.Handle)).Contains(expectedTitle, StringComparison.Ordinal) || Native.Title(new(opened.Handle)).StartsWith("CM-RESTORE-", StringComparison.Ordinal)))
            { Native.RequestClose(opened); if (!Wait(() => !Native.Matches(opened), 5)) { passed = false; detail += " Test shell did not close after cleanup."; } }
            try { if (Directory.Exists(directory)) Directory.Delete(directory, true); } catch (IOException) { }
        }
        return new("Real terminal recovery smoke", passed, detail);
    }
    internal static void WaitForTask(Task task)
    {
        if (!task.IsCompleted) {
            var frame = new DispatcherFrame(); var watch = Stopwatch.StartNew();
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(5) };
            timer.Tick += (_, _) => { if (task.IsCompleted || watch.Elapsed.TotalSeconds > 15) frame.Continue = false; };
            timer.Start(); try { Dispatcher.PushFrame(frame); } finally { timer.Stop(); }
            if (!task.IsCompleted) throw new TimeoutException("Background operation did not finish");
        }
        task.GetAwaiter().GetResult();
    }
    private static void Pump() { var frame = new DispatcherFrame(); Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background, () => frame.Continue = false); Dispatcher.PushFrame(frame); }
}
