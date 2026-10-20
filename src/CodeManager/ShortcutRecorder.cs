using System;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;

namespace CodeManager;

/// <summary>Keyboard capture is a local settings draft. It never installs hooks or writes preferences.</summary>
public sealed class ShortcutRecorder : Grid
{
    private readonly Button _capture;
    private readonly bool _wheel;
    private readonly string _default;
    private string _gesture, _before = "";
    public string Gesture => _gesture;
    public bool IsCapturing { get; private set; }
    public event Action? Changed;
    public ShortcutRecorder(string label, string gesture, string defaultGesture, bool wheel = false)
    {
        _gesture = gesture ?? ""; _default = defaultGesture ?? ""; _wheel = wheel;
        ColumnDefinitions.Add(new()); ColumnDefinitions.Add(new() { Width = GridLength.Auto }); ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        _capture = new Button { MinWidth = 150, MinHeight = 36, Padding = new Thickness(10, 6, 10, 6), HorizontalContentAlignment = HorizontalAlignment.Center, ToolTip = wheel ? "点击后按住修饰键并滚动滚轮；Esc 取消" : "点击后直接按下新快捷键；Esc 取消" };
        AutomationProperties.SetName(_capture, "录入" + label); _capture.Click += (_, _) => BeginCapture(); Children.Add(_capture);
        var clear = new Button { Content = "×", Width = 30, Margin = new Thickness(4, 0, 0, 0), Padding = new Thickness(0), ToolTip = "清除此快捷键" };
        AutomationProperties.SetName(clear, "清除" + label); clear.Click += (_, _) => SetGesture(""); SetColumn(clear, 1); Children.Add(clear);
        var reset = new Button { Content = "↺", Width = 30, Margin = new Thickness(4, 0, 0, 0), Padding = new Thickness(0), ToolTip = "恢复此项默认快捷键" };
        AutomationProperties.SetName(reset, "恢复默认" + label); reset.Click += (_, _) => SetGesture(_default); SetColumn(reset, 2); Children.Add(reset);
        _capture.PreviewKeyDown += (_, e) => {
            if (!IsCapturing) return;
            e.Handled = true;
            Key key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key == Key.Escape && Keyboard.Modifiers == ModifierKeys.None) { CancelCapture(); return; }
            if (key is Key.LeftAlt or Key.RightAlt or Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin) { _capture.Content = Keyboard.Modifiers + " + …"; return; }
            if (_wheel) { _capture.Content = "按住修饰键并滚动"; return; }
            string modifiers = Preferences.ModifierLabel((ShortcutModifiers)NativeModifiers(Keyboard.Modifiers));
            string name = new KeyConverter().ConvertToInvariantString(key) ?? key.ToString();
            string value = (modifiers.Length == 0 ? "" : modifiers + "+") + name;
            if (InputService.TryParseGesture(value, out uint capturedModifiers, out uint capturedKey)) SetGesture(value);
        };
        _capture.PreviewMouseWheel += (_, e) => {
            if (!IsCapturing || !_wheel) return;
            e.Handled = true; int mods = NativeModifiers(Keyboard.Modifiers);
            if (mods == 0) { _capture.Content = "请同时按住 Ctrl / Alt 等"; return; }
            SetGesture(Preferences.ModifierLabel((ShortcutModifiers)mods) + "+Wheel");
        };
        _capture.LostKeyboardFocus += (_, _) => { if (IsCapturing) CancelCapture(); };
        RenderCaption();
    }
    internal static int NativeModifiers(ModifierKeys keys) => (keys.HasFlag(ModifierKeys.Alt) ? 1 : 0) | (keys.HasFlag(ModifierKeys.Control) ? 2 : 0) | (keys.HasFlag(ModifierKeys.Shift) ? 4 : 0) | (keys.HasFlag(ModifierKeys.Windows) ? 8 : 0);
    public void BeginCapture() { _before = _gesture; IsCapturing = true; _capture.Content = _wheel ? "按住修饰键并滚动…" : "请按快捷键…"; _capture.Focus(); }
    public void CancelCapture() { _gesture = _before; IsCapturing = false; RenderCaption(); }
    public void SetGesture(string value) { _gesture = value; IsCapturing = false; RenderCaption(); Changed?.Invoke(); }
    private void RenderCaption() => _capture.Content = ShortcutBindings.Display(_gesture);
}
