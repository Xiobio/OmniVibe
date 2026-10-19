using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;

namespace CodeManager;

public static class Native
{
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; public Point(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; public Rect(int l, int t, int r, int b) { Left = l; Top = t; Right = r; Bottom = b; } }
    [StructLayout(LayoutKind.Sequential)] public struct Placement
    {
        public uint Length, Flags, ShowCommand;
        public Point MinPosition, MaxPosition;
        public Rect NormalPosition;
    }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
    [StructLayout(LayoutKind.Sequential)] public struct MouseData { public Point Point; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] public struct KeyboardData { public uint Key, Scan, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int X, Y; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit)] private struct InputUnion
    {
        [FieldOffset(0)] public KeyboardInput Keyboard;
        [FieldOffset(0)] public MouseInput Mouse;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public InputUnion Data; }
    [StructLayout(LayoutKind.Sequential)] private struct ThumbnailProperties
    {
        public uint Flags; public Rect Destination, Source; public byte Opacity;
        [MarshalAs(UnmanagedType.Bool)] public bool Visible;
        [MarshalAs(UnmanagedType.Bool)] public bool ClientOnly;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Size { public int Width, Height; }
    public delegate bool EnumProc(IntPtr hwnd, IntPtr parameter);
    public delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
    public delegate void WinEventProc(IntPtr hook, uint evt, IntPtr hwnd, int obj, int child, uint thread, uint time);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc proc, IntPtr parameter);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hwnd, StringBuilder name, int max);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] internal static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr hwnd, ref Placement placement);
    [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr hwnd, ref Placement placement);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string? className, string? title);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attach, uint to, bool yes);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SetWindowsHookEx(int id, HookProc callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr module, WinEventProc callback, uint process, uint thread, uint flags);
    [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(Point point, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint x, out uint y);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out Rect value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmRegisterThumbnail(IntPtr destination, IntPtr source, out IntPtr thumb);
    [DllImport("dwmapi.dll")] public static extern int DwmUnregisterThumbnail(IntPtr thumb);
    [DllImport("dwmapi.dll")] private static extern int DwmUpdateThumbnailProperties(IntPtr thumb, ref ThumbnailProperties properties);
    [DllImport("dwmapi.dll")] private static extern int DwmQueryThumbnailSourceSize(IntPtr thumb, out Size size);

    public static bool Down(int key) => (GetAsyncKeyState(key) & 0x8000) != 0;
    public static bool IsTopmost(IntPtr hwnd) => (GetWindowLongPtr(hwnd, -20).ToInt64() & 8) != 0;
    public static int ZOrder(IntPtr target)
    {
        int rank = 0, found = -1;
        EnumWindows((hwnd, _) => { if (hwnd == target) { found = rank; return false; } rank++; return true; }, IntPtr.Zero);
        return found;
    }
    public static List<IntPtr> VisibleWindowsAbove(IntPtr target)
    {
        var result = new List<IntPtr>();
        EnumWindows((hwnd, _) => { if (hwnd == target) return false; if (IsWindowVisible(hwnd) && !IsIconic(hwnd)) result.Add(hwnd); return true; }, IntPtr.Zero);
        return result;
    }
    public static Rect? VisibleBounds(IntPtr hwnd) => DwmGetWindowAttribute(hwnd, 9, out Rect rect, Marshal.SizeOf<Rect>()) == 0 ? rect : null;
    public static bool PlaceVisibleWindow(IntPtr hwnd, Cell cell)
    {
        ShowWindow(hwnd, 9);
        int left = 0, top = 0, right = 0, bottom = 0;
        if (GetWindowRect(hwnd, out var outer) && VisibleBounds(hwnd) is Rect visible)
        {
            left = visible.Left - outer.Left; top = visible.Top - outer.Top;
            right = outer.Right - visible.Right; bottom = outer.Bottom - visible.Bottom;
        }
        return SetWindowPos(hwnd, IntPtr.Zero, cell.X - left, cell.Y - top, cell.Width + left + right, cell.Height + top + bottom, 0x0010 | 0x0040);
    }
    public static bool ChordDown => MouseGestureRouter.AltOnly(Down(0x12), Down(0x11), Down(0x10), Down(0x5B) || Down(0x5C));
    public static bool ChordDownFor(ShortcutModifiers modifiers) => MouseGestureRouter.Matches(modifiers, Down(0x12), Down(0x11), Down(0x10), Down(0x5B) || Down(0x5C));
    public static bool RequiredModifiersDown(ShortcutModifiers modifiers) => (((int)modifiers & 1) == 0 || Down(0x12)) && (((int)modifiers & 2) == 0 || Down(0x11)) && (((int)modifiers & 4) == 0 || Down(0x10));
    public static bool RequestExit()
    {
        var input = FindWindowEx(new IntPtr(-3), IntPtr.Zero, null, "CodeManager.Input");
        return input != IntPtr.Zero && PostMessage(input, 0x8002, new IntPtr(0x434D), IntPtr.Zero);
    }
    internal static bool RequestClose(WindowIdentity identity) => Matches(identity) && PostMessage(new(identity.Handle), 0x10, IntPtr.Zero, IntPtr.Zero);
    public static bool IsSizingEdge(IntPtr hwnd, Point point)
    {
        int packed = (point.X & 0xffff) | (point.Y << 16);
        return SendMessageTimeout(hwnd, 0x84, IntPtr.Zero, new IntPtr(packed), 2, 80, out var hit) != IntPtr.Zero && hit.ToInt32() is >= 10 and <= 17;
    }
    public static void MaskAltMenu()
    {
        // VK_E8 is unassigned: mark the Alt chord as used without entering text,
        // suppressing Alt-up, or sending a real application's command shortcut.
        var inputs = new[]
        {
            new Input { Type = 1, Data = new InputUnion { Keyboard = new KeyboardInput { Key = 0xE8 } } },
            new Input { Type = 1, Data = new InputUnion { Keyboard = new KeyboardInput { Key = 0xE8, Flags = 2 } } }
        };
        SendInput(2, inputs, Marshal.SizeOf<Input>());
    }
    public static string Title(IntPtr hwnd) { var text = new StringBuilder(1024); GetWindowText(hwnd, text, text.Capacity); return text.ToString(); }
    public static string ClassName(IntPtr hwnd) { var text = new StringBuilder(256); GetClassName(hwnd, text, text.Capacity); return text.ToString(); }
    public static Placement? PlacementOf(IntPtr hwnd)
    {
        var placement = new Placement { Length = (uint)Marshal.SizeOf<Placement>() };
        return GetWindowPlacement(hwnd, ref placement) ? placement : null;
    }
    public static void RestorePlacement(IntPtr hwnd, Placement placement)
    {
        placement.Length = (uint)Marshal.SizeOf<Placement>();
        SetWindowPlacement(hwnd, ref placement);
    }
    public static WindowIdentity? Identify(IntPtr hwnd, bool includeOwn = false)
    {
        if (!IsWindow(hwnd) || !IsWindowVisible(hwnd)) return null;
        GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == 0 || (!includeOwn && pid == Environment.ProcessId)) return null;
        long style = GetWindowLongPtr(hwnd, -20).ToInt64();
        if ((style & 0x80) != 0 || GetWindow(hwnd, 4) != IntPtr.Zero) return null;
        string title = Title(hwnd);
        if (string.IsNullOrWhiteSpace(title) || ClassName(hwnd) is "Progman" or "WorkerW" or "Shell_TrayWnd") return null;
        if (DwmGetWindowAttribute(hwnd, 14, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return null;
        try
        {
            using var process = Process.GetProcessById((int)pid);
            long started = 0;
            try { started = process.StartTime.ToUniversalTime().Ticks; } catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException) { }
            return new() { Handle = hwnd.ToInt64(), ProcessId = (int)pid, ProcessName = process.ProcessName, ProcessStartedUtcTicks = started, Title = title };
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception) { return null; }
    }
    public static List<WindowIdentity> Windows(bool includeOwn = false)
    {
        var result = new List<WindowIdentity>();
        EnumWindows((hwnd, _) => { var identity = Identify(hwnd, includeOwn); if (identity != null) result.Add(identity); return true; }, IntPtr.Zero);
        return result;
    }
    public static bool Matches(WindowIdentity? identity)
    {
        if (identity == null || !IsWindow(new(identity.Handle))) return false;
        GetWindowThreadProcessId(new(identity.Handle), out uint pid);
        if (pid != identity.ProcessId) return false;
        if (identity.ProcessStartedUtcTicks == 0) return true;
        try { using var process = Process.GetProcessById((int)pid); return process.StartTime.ToUniversalTime().Ticks == identity.ProcessStartedUtcTicks; }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception) { return false; }
    }
    public static bool Activate(WindowIdentity identity)
    {
        if (!Matches(identity)) return false;
        var hwnd = new IntPtr(identity.Handle);
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
        if (!IsWindowVisible(hwnd)) ShowWindow(hwnd, 5);
        void Raise()
        {
            // Focus and Z-order are independent: a nonactivating window can cover
            // the foreground window. Always raise, even if focus is already correct.
            BringWindowToTop(hwnd);
            SetWindowPos(hwnd, IsTopmost(hwnd) ? new IntPtr(-1) : IntPtr.Zero, 0, 0, 0, 0, 0x253);
            SetForegroundWindow(hwnd);
        }
        Raise();
        if (GetForegroundWindow() == hwnd) return true;
        uint foregroundThread = GetWindowThreadProcessId(GetForegroundWindow(), out _);
        uint currentThread = GetCurrentThreadId();
        bool attached = foregroundThread != 0 && foregroundThread != currentThread && AttachThreadInput(currentThread, foregroundThread, true);
        try { Raise(); }
        finally { if (attached) AttachThreadInput(currentThread, foregroundThread, false); }
        return GetForegroundWindow() == hwnd;
    }
    public static (Rect Work, double Scale) ScreenAtCursor()
    {
        GetCursorPos(out Point cursor);
        return Screen(MonitorFromPoint(cursor, 2));
    }
    public static (Rect Work, double Scale) ScreenForWindow(IntPtr hwnd) => Screen(MonitorFromWindow(hwnd, 2));
    public static (Rect Work, double Scale) ScreenAt(Point point) => Screen(MonitorFromPoint(point, 2));
    public static void EnsureVisible(IntPtr hwnd)
    {
        if (!GetWindowRect(hwnd, out var rect)) return;
        var area = ScreenForWindow(hwnd).Work;
        var original = new Cell(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top);
        var cell = WindowLayout.Clamp(original, area);
        if (cell != original) SetWindowPos(hwnd, IntPtr.Zero, cell.X, cell.Y, cell.Width, cell.Height, 0x14);
    }
    private static (Rect Work, double Scale) Screen(IntPtr monitor)
    {
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        GetMonitorInfo(monitor, ref info);
        GetDpiForMonitor(monitor, 0, out uint dpi, out _);
        return (info.Work, dpi > 0 ? dpi / 96d : 1);
    }
    public static void PlaceDock(Window window, Rect work, double scale, bool collapsed, double desiredHeight = 748, double desiredWidth = 252, Point? position = null)
    {
        int width = (int)Math.Round((collapsed ? 48 : desiredWidth) * scale);
        int height = Math.Min(work.Bottom - work.Top - (int)(32 * scale), (int)(desiredHeight * scale));
        int x = position.HasValue ? Math.Clamp(position.Value.X, work.Left, Math.Max(work.Left, work.Right - width)) : work.Right - width;
        int y = position.HasValue ? Math.Clamp(position.Value.Y, work.Top, Math.Max(work.Top, work.Bottom - height)) : work.Top + (work.Bottom - work.Top - height) / 2;
        SetWindowPos(new WindowInteropHelper(window).Handle, new IntPtr(-1), x, y, width, height, 0x0010 | 0x0040);
    }
    public static void Decorate(Window window, bool noActivate = true, bool clickThrough = false)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        long style = GetWindowLongPtr(hwnd, -20).ToInt64() | 0x80;
        if (noActivate) style |= 0x08000000;
        if (clickThrough) style |= 0x20;
        SetWindowLongPtr(hwnd, -20, new IntPtr(style));
        int dark = SkinCatalog.Current.IsLight ? 0 : 1, rounded = 2;
        DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int));
        DwmSetWindowAttribute(hwnd, 33, ref rounded, sizeof(int));
    }
    internal static void RemoveOverlayFrame(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        // Layered tool windows must not inherit the normal windows' non-client frame.
        SetWindowLongPtr(hwnd, -16, new IntPtr(GetWindowLongPtr(hwnd, -16).ToInt64() & ~0x00C40000L));
        SetWindowLongPtr(hwnd, -20, new IntPtr(GetWindowLongPtr(hwnd, -20).ToInt64() & ~0x00020300L));
        int disabled = 1, none = unchecked((int)0xFFFFFFFE);
        DwmSetWindowAttribute(hwnd, 2, ref disabled, sizeof(int)); // Non-client rendering disabled.
        DwmSetWindowAttribute(hwnd, 33, ref disabled, sizeof(int)); // Do not round the invisible host rectangle.
        DwmSetWindowAttribute(hwnd, 34, ref none, sizeof(int)); // No system border colour.
        DwmSetWindowAttribute(hwnd, 38, ref disabled, sizeof(int)); // No system backdrop.
        SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0037);
    }
    internal static bool HasOverlayFrame(IntPtr hwnd) => (GetWindowLongPtr(hwnd, -16).ToInt64() & 0x00C40000L) != 0 || (GetWindowLongPtr(hwnd, -20).ToInt64() & 0x00020300L) != 0;
    public static IntPtr Thumbnail(IntPtr destination, IntPtr source, Rect destinationRect, byte opacity = 255)
    {
        if (DwmRegisterThumbnail(destination, source, out IntPtr thumb) != 0) return IntPtr.Zero;
        if (DwmQueryThumbnailSourceSize(thumb, out var size) == 0 && size.Width > 0 && size.Height > 0)
        {
            int availableWidth = destinationRect.Right - destinationRect.Left, availableHeight = destinationRect.Bottom - destinationRect.Top;
            double factor = Math.Min(availableWidth / (double)size.Width, availableHeight / (double)size.Height);
            int width = (int)(size.Width * factor), height = (int)(size.Height * factor);
            int x = destinationRect.Left + (availableWidth - width) / 2, y = destinationRect.Top + (availableHeight - height) / 2;
            destinationRect = new(x, y, x + width, y + height);
        }
        var properties = new ThumbnailProperties { Flags = 1 | 4 | 8 | 16, Destination = destinationRect, Opacity = opacity, Visible = true, ClientOnly = false };
        if (DwmUpdateThumbnailProperties(thumb, ref properties) != 0) { DwmUnregisterThumbnail(thumb); return IntPtr.Zero; }
        return thumb;
    }
    public static void MoveThumbnail(IntPtr thumbnail, Rect destination)
    {
        if (DwmQueryThumbnailSourceSize(thumbnail, out var size) == 0 && size.Width > 0 && size.Height > 0)
        {
            double factor = Math.Min((destination.Right - destination.Left) / (double)size.Width, (destination.Bottom - destination.Top) / (double)size.Height);
            int width = (int)(size.Width * factor), height = (int)(size.Height * factor);
            int left = destination.Left + (destination.Right - destination.Left - width) / 2, top = destination.Top + (destination.Bottom - destination.Top - height) / 2;
            destination = new(left, top, left + width, top + height);
        }
        var properties = new ThumbnailProperties { Flags = 1, Destination = destination };
        DwmUpdateThumbnailProperties(thumbnail, ref properties);
    }
}
