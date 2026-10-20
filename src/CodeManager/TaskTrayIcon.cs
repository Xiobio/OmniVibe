using System;
using System.Drawing;
using System.Runtime.InteropServices;
using Forms = System.Windows.Forms;

namespace CodeManager;

/// <summary>One native tray icon, including silent balloons. Public Win32 API
/// avoids private NotifyIcon reflection and supports NIIF_NOSOUND per notice.</summary>
internal sealed class TaskTrayIcon : Forms.NativeWindow, IDisposable
{
    private const int Callback = 0x8001;
    private static readonly uint TaskbarCreated = RegisterWindowMessage("TaskbarCreated");
    private bool _visible, _added, _disposed;
    private Icon? _icon;
    private string _text = "";
    internal Forms.ContextMenuStrip? ContextMenuStrip { get; set; }
    internal Icon? Icon { get => _icon; set { _icon=value; UpdateIcon(); } }
    internal string Text { get => _text; set { _text=value ?? ""; UpdateIcon(); } }
    internal bool Visible { get => _visible; set { _visible=value; UpdateIcon(); } }
    internal event Forms.MouseEventHandler? MouseClick;
    internal event EventHandler? DoubleClick;
    internal event EventHandler? BalloonTipClicked;
    internal event EventHandler? BalloonTipShown;
    internal TaskTrayIcon() { CreateHandle(new Forms.CreateParams { Caption="OmniVibe task notifications" }); }
    private NotificationData Data() => new() { Size=(uint)Marshal.SizeOf<NotificationData>(), Window=Handle, Id=1, Tip="", Info="", Title="" };
    private void UpdateIcon()
    {
        if (_disposed) return;
        var data=Data();
        if (!_visible || _icon == null) { if (_added) Shell_NotifyIcon(2,ref data); _added=false; return; }
        data.Flags=1|2|4; data.Message=Callback; data.Icon=_icon.Handle; data.Tip=_text.Length>127?_text[..127]:_text;
        _added=Shell_NotifyIcon(_added?1u:0u,ref data);
    }
    internal static uint InfoFlags(Forms.ToolTipIcon icon, bool silent) => (uint)icon | (silent?0x10u:0u) | 0x80u;
    internal bool ShowBalloonTip(int timeout, string title, string text, Forms.ToolTipIcon icon, bool silent=false)
    {
        if (_disposed || !_visible) return false;
        if (!_added) UpdateIcon();
        if (!_added) return false;
        var data=Data();data.Flags=0x10;data.Timeout=(uint)timeout;
        data.Title=title.Length>63?title[..63]:title;data.Info=text.Length>255?text[..255]:text;data.InfoFlags=InfoFlags(icon,silent);
        return Shell_NotifyIcon(1,ref data);
    }
    protected override void WndProc(ref Forms.Message message)
    {
        if ((uint)message.Msg==TaskbarCreated) { _added=false; UpdateIcon(); }
        else if (message.Msg==Callback) {
            switch ((int)message.LParam) {
                case 0x202: MouseClick?.Invoke(this,new Forms.MouseEventArgs(Forms.MouseButtons.Left,1,0,0,0)); break;
                case 0x203: DoubleClick?.Invoke(this,EventArgs.Empty); break;
                case 0x205:
                    if (ContextMenuStrip != null) {
                        SetForegroundWindow(Handle); ContextMenuStrip.Show(Forms.Cursor.Position);
                        PostMessage(Handle,0,IntPtr.Zero,IntPtr.Zero);
                    }
                    break;
                case 0x402: BalloonTipShown?.Invoke(this,EventArgs.Empty); break;
                case 0x405: BalloonTipClicked?.Invoke(this,EventArgs.Empty); break;
            }
        }
        base.WndProc(ref message);
    }
    public void Dispose()
    {
        if (_disposed) return;
        _visible=false;UpdateIcon();_disposed=true;
        ContextMenuStrip?.Dispose();ContextMenuStrip=null;DestroyHandle();
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
    private struct NotificationData
    {
        internal uint Size; internal IntPtr Window; internal uint Id,Flags,Message; internal IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] internal string Tip;
        internal uint State,StateMask;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)] internal string Info;
        internal uint Timeout;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=64)] internal string Title;
        internal uint InfoFlags; internal Guid Guid; internal IntPtr BalloonIcon;
    }
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] [return:MarshalAs(UnmanagedType.Bool)] private static extern bool Shell_NotifyIcon(uint message,ref NotificationData data);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr handle,uint message,IntPtr wParam,IntPtr lParam);
}
