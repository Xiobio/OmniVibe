using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace CodeManager;

public sealed class InputService : IDisposable
{
    private readonly HwndSource _source;
    private readonly HashSet<int> _registered = new();
    private readonly Native.HookProc _mouseProc, _keyboardProc;
    private readonly Native.WinEventProc _eventProc;
    private readonly Dispatcher _dispatcher;
    private readonly MouseGestureRouter _mouseGestures = new();
    private readonly List<string> _hookWarnings = new();
    private IntPtr _mouse, _keyboard, _events;
    private string _signature = "", _toggleSetting = "", _toggleWarning = "";
    private ShortcutModifiers _mouseModifiers = ShortcutModifiers.Alt;
    private bool _wheelEnabled = true;
    public event Action<int>? Hotkey;
    public event Action<int>? Wheel;
    public event Action<int>? InventoryWheel;
    public event Action? Release, Cancel, Quit;
    public event Action<IntPtr, bool>? Drag;
    public Func<bool>? IsSelecting, CanHandleMouse;
    public Func<bool>? IsInventoryOpen;
    public Func<bool>? IsDockMenuOpen;
    public event Action<Native.Point>? PointerDown;
    public List<string> Warnings { get; } = new();
    public string ToggleShortcut { get; private set; } = L.T("Ctrl+Alt+空格");
    internal int[] RegisteredTasks => _registered.Where(n => n < 10).OrderBy(n => n).ToArray();
    internal bool TabRegistered => _registered.Contains(11);
    internal bool ArrangeRegistered => _registered.Contains(12);
    internal bool RadialRegistered => _registered.Contains(13);
    public InputService(Dispatcher dispatcher)
    {
        _dispatcher = dispatcher;
        _source = new HwndSource(new HwndSourceParameters("CodeManager.Input") { ParentWindow = new IntPtr(-3), Width = 0, Height = 0 });
        _source.AddHook(WndProc);
        _mouseProc = MouseHook; _keyboardProc = KeyboardHook; _eventProc = WindowEvent;
        IntPtr module = Native.GetModuleHandle(null);
        _mouse = Native.SetWindowsHookEx(14, _mouseProc, module, 0);
        _keyboard = Native.SetWindowsHookEx(13, _keyboardProc, module, 0);
        _events = Native.SetWinEventHook(0xA, 0xB, IntPtr.Zero, _eventProc, 0, 0, 2);
        if (_mouse == IntPtr.Zero) _hookWarnings.Add(L.T("滚轮监听不可用"));
        if (_keyboard == IntPtr.Zero) _hookWarnings.Add(L.T("松键确认不可用，请点击任务卡片"));
        if (_events == IntPtr.Zero) _hookWarnings.Add(L.T("拖动监听不可用，请点击添加窗口"));
        Configure(new(), Array.Empty<int>(), false);
    }
    public void Configure(Preferences preferences, IEnumerable<int> connectedNumbers, bool suspended)
    {
        int[] numbers = suspended ? Array.Empty<int>() : connectedNumbers.Distinct().OrderBy(n => n).ToArray();
        string signature = string.Join("|", ShortcutBindings.All(preferences).Select(b => b.Id + ":" + b.Gesture)) + ":" + preferences.MouseModifiers + ":" + preferences.WheelSwitchEnabled + ":" + suspended + ":" + string.Join(",", numbers);
        if (signature == _signature) return;
        _signature = signature; _mouseModifiers = preferences.MouseModifiers; _wheelEnabled = preferences.WheelSwitchEnabled;
        foreach (int number in _registered.Where(n => n < 10).ToList()) { Native.UnregisterHotKey(_source.Handle, number); _registered.Remove(number); }
        Warnings.Clear(); Warnings.AddRange(_hookWarnings);
        if (_registered.Remove(13)) Native.UnregisterHotKey(_source.Handle, 13);
        if (!suspended)
        {
            if (TryParseGesture(preferences.RadialGesture, out uint rm, out uint rk) && Native.RegisterHotKey(_source.Handle, 13, 0x4000 | rm, rk)) _registered.Add(13);
            else if (!string.IsNullOrWhiteSpace(preferences.RadialGesture)) Warnings.Add(L.T("轮盘快捷键不可用：") + ShortcutBindings.Display(preferences.RadialGesture));
        }
        if (_registered.Remove(12)) Native.UnregisterHotKey(_source.Handle, 12);
        if (!suspended && numbers.Length > 0)
        {
            if (TryParseGesture(preferences.ArrangeGesture, out uint am, out uint ak) && Native.RegisterHotKey(_source.Handle, 12, 0x4000 | am, ak)) _registered.Add(12);
            else if (!string.IsNullOrWhiteSpace(preferences.ArrangeGesture)) Warnings.Add(L.T("排列快捷键被占用：") + ShortcutBindings.Display(preferences.ArrangeGesture));
        }
        if (_registered.Remove(11)) Native.UnregisterHotKey(_source.Handle, 11);
        if (preferences.TabTogglesInventory && !suspended && !string.IsNullOrWhiteSpace(preferences.InventoryGesture))
        {
            bool bareTab = preferences.InventoryGesture == "Tab";
            uint im = 0, ik = 0x09;
            if ((bareTab || TryParseGesture(preferences.InventoryGesture, out im, out ik)) && Native.RegisterHotKey(_source.Handle, 11, 0x4000 | im, ik)) _registered.Add(11);
            else Warnings.Add(L.T("总览快捷键被占用：") + ShortcutBindings.Display(preferences.InventoryGesture));
        }
        foreach (int number in numbers)
        {
            string gesture = preferences.TaskGesture(number);
            if (string.IsNullOrWhiteSpace(gesture)) continue;
            if (TryParseGesture(gesture, out uint tm, out uint tk) && Native.RegisterHotKey(_source.Handle, number, 0x4000 | tm, tk)) _registered.Add(number);
            else Warnings.Add(L.T("窗口 ") + number + L.T(" 快捷键被占用：") + ShortcutBindings.Display(gesture));
        }
        if (suspended) { if (_registered.Remove(10)) Native.UnregisterHotKey(_source.Handle, 10); }
        else if (_toggleSetting != preferences.ToggleGesture || !_registered.Contains(10)) RegisterToggle(preferences.ToggleGesture);
        if (_toggleWarning != "") Warnings.Add(_toggleWarning);
    }
    public static bool TryParseGesture(string text, out uint modifiers, out uint key)
    {
        modifiers = key = 0;
        try
        {
            if (string.IsNullOrWhiteSpace(text)) return false;
            var parts = text.Split('+', StringSplitOptions.TrimEntries);
            if (parts.Any(string.IsNullOrEmpty)) return false;
            foreach (string part in parts.Take(parts.Length - 1)) {
                uint bit = part.ToUpperInvariant() switch { "CTRL" or "CONTROL" => 2, "ALT" => 1, "SHIFT" => 4, "WIN" or "WINDOWS" => 8, _ => 0 };
                if (bit == 0 || (modifiers & bit) != 0) return false;
                modifiers |= bit;
            }
            if (new KeyConverter().ConvertFromInvariantString(parts[^1]) is not Key parsed) return false;
            key = (uint)KeyInterop.VirtualKeyFromKey(parsed);
            return key != 0 && key is not (0x10 or 0x11 or 0x12 or 0x5B or 0x5C or >= 0xA0 and <= 0xA5);
        }
        catch (Exception ex) when (ex is NotSupportedException or ArgumentException or FormatException) { return false; }
    }
    internal static bool GestureDown(string gesture)
    {
        return TryParseGesture(gesture, out uint mods, out uint key) && Native.Down((int)key)
            && ((mods & 1) == 0 || Native.Down(0x12)) && ((mods & 2) == 0 || Native.Down(0x11))
            && ((mods & 4) == 0 || Native.Down(0x10)) && ((mods & 8) == 0 || Native.Down(0x5B) || Native.Down(0x5C));
    }
    private void RegisterToggle(string setting)
    {
        if (_registered.Remove(10)) Native.UnregisterHotKey(_source.Handle, 10);
        _toggleSetting = setting; _toggleWarning = "";
        if (string.IsNullOrWhiteSpace(setting)) { ToggleShortcut = L.T("未设置（双击托盘图标可显示）"); return; }
        string[] choices = { setting };
        foreach (string choice in choices.Distinct())
        {
            if (!TryParseGesture(choice, out uint modifiers, out uint key) || !Native.RegisterHotKey(_source.Handle, 10, modifiers | 0x4000, key)) continue;
            _registered.Add(10); ToggleShortcut = choice.Replace("Space", L.T("空格"));
            return;
        }
        ToggleShortcut = L.T("系统托盘图标"); _toggleWarning = L.T("显示快捷键不可用，请双击托盘图标恢复侧栏");
    }
    private IntPtr WndProc(IntPtr hwnd, int message, IntPtr wparam, IntPtr lparam, ref bool handled)
    {
        if (message == 0x312) { int id = wparam.ToInt32(); Hotkey?.Invoke(id == 12 ? 0 : id); handled = true; }
        if (message == 0x8002 && wparam.ToInt64() == 0x434D) { _dispatcher.BeginInvoke(() => Quit?.Invoke()); handled = true; }
        return IntPtr.Zero;
    }
    private IntPtr MouseHook(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            int msg = message.ToInt32();
            if (msg is 0x201 or 0x204 && IsDockMenuOpen?.Invoke() == true)
            {
                var point = Marshal.PtrToStructure<Native.MouseData>(data).Point;
                _dispatcher.BeginInvoke(() => PointerDown?.Invoke(point), DispatcherPriority.Input);
            }
            int delta = msg == 0x20A ? unchecked((short)(Marshal.PtrToStructure<Native.MouseData>(data).Data >> 16)) : 0;
            if (delta != 0 && IsInventoryOpen?.Invoke() == true && !Native.Down(0x12) && !Native.Down(0x11) && !Native.Down(0x10) && !Native.Down(0x5B) && !Native.Down(0x5C))
            {
                _dispatcher.BeginInvoke(() => InventoryWheel?.Invoke(delta));
                return new IntPtr(1);
            }
            var gesture = _mouseGestures.Route(msg, _wheelEnabled && CanHandleMouse?.Invoke() == true && Native.ChordDownFor(_mouseModifiers), delta);
            if (gesture.Consume)
            {
                if (gesture.MaskAlt && ((int)_mouseModifiers & 1) != 0) Native.MaskAltMenu();
                if (gesture.WheelDelta != 0) _dispatcher.BeginInvoke(() => Wheel?.Invoke(gesture.WheelDelta));
                return new IntPtr(1);
            }
        }
        return Native.CallNextHookEx(_mouse, code, message, data);
    }
    private IntPtr KeyboardHook(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            uint key = Marshal.PtrToStructure<Native.KeyboardData>(data).Key;
            int msg = message.ToInt32();
            if ((msg == 0x100 || msg == 0x104) && key == 0x1B && IsSelecting?.Invoke() == true)
            { _dispatcher.BeginInvoke(() => Cancel?.Invoke()); return new IntPtr(1); }
            if ((msg == 0x101 || msg == 0x105) && IsRequiredRelease(key))
            { _mouseGestures.AltReleased(); _dispatcher.BeginInvoke(() => Release?.Invoke()); }
        }
        return Native.CallNextHookEx(_keyboard, code, message, data);
    }
    private bool IsRequiredRelease(uint key) =>
        (((int)_mouseModifiers & 1) != 0 && key is 0x12 or 0xA4 or 0xA5) ||
        (((int)_mouseModifiers & 2) != 0 && key is 0x11 or 0xA2 or 0xA3) ||
        (((int)_mouseModifiers & 4) != 0 && key is 0x10 or 0xA0 or 0xA1) ||
        (((int)_mouseModifiers & 8) != 0 && key is 0x5B or 0x5C);
    public static string? RegistrationConflict(Preferences preferences, Preferences? baseline = null)
    {
        using var probe = new HwndSource(new HwndSourceParameters("OmniVibe.ShortcutProbe") { ParentWindow = new IntPtr(-3), Width = 0, Height = 0 });
        var registrations = new List<int>();
        try {
            foreach (var binding in ShortcutBindings.All(preferences)) {
                if (string.IsNullOrWhiteSpace(binding.Gesture)) continue;
                // A theme/layout save must not be blocked by an unchanged key
                // that was already unavailable before opening settings.
                var prior = baseline == null ? null : ShortcutBindings.All(baseline).First(b => b.Id == binding.Id);
                if (prior != null && TryParseGesture(prior.Gesture, out uint oldMods, out uint oldKey) && TryParseGesture(binding.Gesture, out uint newMods, out uint newKey) && oldMods == newMods && oldKey == newKey) continue;
                if (!TryParseGesture(binding.Gesture, out uint mods, out uint key) || !Native.RegisterHotKey(probe.Handle, binding.Id + 200, mods | 0x4000, key))
                    return binding.Name + "：" + ShortcutBindings.Display(binding.Gesture) + L.T(" 已被系统或其他程序占用，请换一个组合。");
                registrations.Add(binding.Id + 200);
            }
            return null;
        }
        finally { foreach (int id in registrations) Native.UnregisterHotKey(probe.Handle, id); }
    }
    private void WindowEvent(IntPtr hook, uint evt, IntPtr hwnd, int obj, int child, uint thread, uint time)
    { if (hwnd != IntPtr.Zero && obj == 0 && child == 0) _dispatcher.BeginInvoke(() => Drag?.Invoke(hwnd, evt == 0xA)); }
    public void Dispose()
    {
        if (_mouse != IntPtr.Zero) Native.UnhookWindowsHookEx(_mouse);
        if (_keyboard != IntPtr.Zero) Native.UnhookWindowsHookEx(_keyboard);
        if (_events != IntPtr.Zero) Native.UnhookWinEvent(_events);
        _mouse = _keyboard = _events = IntPtr.Zero;
        foreach (int id in _registered) Native.UnregisterHotKey(_source.Handle, id);
        _source.Dispose();
    }
}
