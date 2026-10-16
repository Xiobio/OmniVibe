using System;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace CodeManager;

public static class Diagnostics
{
    public static void Write(string path)
    {
        var state = new StateStore().Load();
        var foreground = Native.GetForegroundWindow();
        var report = new
        {
            At = DateTimeOffset.Now,
            Foreground = foreground.ToInt64(),
            LayoutCount = state.Layout.Count,
            PopupSlot = state.Slots.FirstOrDefault(s => s.Id == state.Popup?.SlotId)?.Number,
            AbovePopup = state.Popup == null ? null : Native.VisibleWindowsAbove(new(state.Popup.Window.Handle)).Select(hwnd =>
            {
                Native.GetWindowThreadProcessId(hwnd, out uint pid); Native.GetWindowRect(hwnd, out var bounds);
                string process;
                try { using var p = System.Diagnostics.Process.GetProcessById((int)pid); process = p.ProcessName; } catch { process = "unavailable"; }
                return new { Handle = hwnd.ToInt64(), Process = process, Topmost = Native.IsTopmost(hwnd), Bounds = bounds };
            }).ToArray(),
            Slots = state.Slots.Where(s => s.Occupied).Select(s =>
            {
                var hwnd = new IntPtr(s.Window!.Handle);
                Native.GetWindowRect(hwnd, out var bounds);
                return new { s.Number, Matches = Native.Matches(s.Window), Visible = Native.IsWindowVisible(hwnd), Minimized = Native.IsIconic(hwnd), Foreground = hwnd == foreground, Topmost = Native.IsTopmost(hwnd), ZOrder = Native.ZOrder(hwnd), Bounds = bounds, Placement = Native.PlacementOf(hwnd), LastPlacement = s.LastPlacement, s.ParkedByApp };
            }).ToArray()
        };
        StateStore.AtomicWrite(Path.GetFullPath(path), JsonSerializer.Serialize(report, StateStore.Json));
    }
}
