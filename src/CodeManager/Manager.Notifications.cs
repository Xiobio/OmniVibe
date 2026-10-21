using System;
using System.Linq;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace CodeManager;

public sealed partial class Manager
{
    private readonly TaskNotifications _notifications = new();
    private DispatcherTimer? _notificationTimer;
    private void InitializeNotifications()
    {
        _notificationTimer = new DispatcherTimer { Interval=TimeSpan.FromMilliseconds(300) };
        _notificationTimer.Tick += (_, _) => FlushNotifications();
        _tray.BalloonTipClicked += (_, _) => Dock.Dispatcher.BeginInvoke(new Action(() => {
            if (_disposed || Exiting || _dialog) return;
            // An OS balloon has no activation payload: always show current tasks,
            // never activate a possibly removed/reused slot from an old popup.
            if (_inventory == null) ToggleInventory();
        }));
    }
    private void QueueNotification(Slot slot)
    {
        if (_notifications == null || _notificationTimer == null || _disposed) return;
        var p=State.Preferences;
        if (_notifications.Queue(slot, p.SystemNotifications || p.SoundNotifications, DateTimeOffset.UtcNow, Native.GetForegroundWindow().ToInt64())) _notificationTimer.Start();
    }
    private void FlushNotifications()
    {
        if (_disposed) { _notificationTimer?.Stop(); return; }
        var p=State.Preferences;
        var notices = _notifications.Flush(State.Slots, p.SystemNotifications || p.SoundNotifications, DateTimeOffset.UtcNow, Native.GetForegroundWindow().ToInt64());
        if (!_notifications.HasPending) _notificationTimer?.Stop();
        if (notices.Length == 0) return;
        _notificationTimer?.Stop();
        bool completion=TaskNotifications.PlayCompletion(notices,p.SoundNotifications,ShortcutsPaused);
        if (completion) GameAudio.PlayCompletion(p.Skin,true,p.SoundVolume);
        if (!p.SystemNotifications) return;
        string title = notices.Length == 1 ? "OmniVibe · " + TaskNotifications.Caption(notices[0].State) : "OmniVibe · " + notices.Length + L.T(" 项待处理");
        string body = string.Join("\n", notices.Take(3).Select(n => n.Number + " · " + TaskNotifications.SafeName(n.Name) + " — " + TaskNotifications.Caption(n.State)));
        if (notices.Length > 3) body += "\n" + L.T("另有 ") + (notices.Length-3) + L.T(" 项");
        body += "\n" + L.T("点击打开任务总览");
        try { _tray.ShowBalloonTip(6000, title, body, notices.Any(n => n.State==AgentState.Error) ? Forms.ToolTipIcon.Warning : Forms.ToolTipIcon.Info, silent:completion || notices.All(n=>n.State==AgentState.Ready)); }
        catch (InvalidOperationException e) { Store.Log("System notification: " + e.Message); }
        catch (System.ComponentModel.Win32Exception e) { Store.Log("System notification: " + e.Message); }
    }
}
