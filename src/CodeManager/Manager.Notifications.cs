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
        if (_notifications.Queue(slot, State.Preferences.SystemNotifications, DateTimeOffset.UtcNow, Native.GetForegroundWindow().ToInt64())) _notificationTimer.Start();
    }
    private void FlushNotifications()
    {
        if (_disposed) { _notificationTimer?.Stop(); return; }
        var notices = _notifications.Flush(State.Slots, State.Preferences.SystemNotifications, DateTimeOffset.UtcNow, Native.GetForegroundWindow().ToInt64());
        if (!_notifications.HasPending) _notificationTimer?.Stop();
        if (notices.Length == 0) return;
        _notificationTimer?.Stop();
        string title = notices.Length == 1 ? "OmniVibe · " + TaskNotifications.Caption(notices[0].State) : "OmniVibe · " + notices.Length + " 项待处理";
        string body = string.Join("\n", notices.Take(3).Select(n => n.Number + " · " + TaskNotifications.SafeName(n.Name) + " — " + TaskNotifications.Caption(n.State)));
        if (notices.Length > 3) body += "\n另有 " + (notices.Length-3) + " 项";
        body += "\n点击打开任务总览";
        try { _tray.ShowBalloonTip(6000, title, body, notices.Any(n => n.State==AgentState.Error) ? Forms.ToolTipIcon.Warning : Forms.ToolTipIcon.Info); }
        catch (InvalidOperationException e) { Store.Log("System notification: " + e.Message); }
        catch (System.ComponentModel.Win32Exception e) { Store.Log("System notification: " + e.Message); }
    }
}
