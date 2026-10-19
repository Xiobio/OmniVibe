using System;
using System.Runtime.InteropServices;

// Read-only monitor sizing. Scope DPI awareness to this thread and restore it;
// this never changes the user's display scaling or any system setting.
public static class OmniVibeFrameLayout
{
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    private delegate bool MonitorProc(IntPtr monitor, IntPtr dc, ref Rect rectangle, IntPtr data);
    [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorProc callback, IntPtr data);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("shcore.dll")] private static extern int GetScaleFactorForMonitor(IntPtr monitor, out int scale);

    public static double[] MaximumLogicalScreen()
    {
        double width = 1280, height = 754;
        IntPtr previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        try
        {
            MonitorProc callback = delegate(IntPtr monitor, IntPtr dc, ref Rect r, IntPtr data)
            {
                int scale;
                if (GetScaleFactorForMonitor(monitor, out scale) != 0 || scale < 100) scale = 100;
                width = Math.Max(width, (r.Right - r.Left) * 100.0 / scale);
                height = Math.Max(height, (r.Bottom - r.Top) * 100.0 / scale);
                return true;
            };
            if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero))
                throw new InvalidOperationException("Unable to read monitor bounds for the frame safety margin.");
            return new double[] { width, height };
        }
        finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }

    public static string Padding(double width, double height)
    {
        if (width < 1 || height < 1 || double.IsNaN(width) || double.IsNaN(height) || double.IsInfinity(width) || double.IsInfinity(height))
            throw new ArgumentOutOfRangeException("Invalid frame layout size.");
        int x = Math.Max(36, (int)Math.Ceiling(width * 31 / 1280 + 4));
        int y = Math.Max(32, (int)Math.Ceiling(height * 31 / 754 + 4));
        return x + ", " + y + ", " + x + ", " + y;
    }
}
