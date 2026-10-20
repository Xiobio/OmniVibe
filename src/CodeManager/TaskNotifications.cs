using System;
using System.Collections.Generic;
using System.Linq;

namespace CodeManager;

internal readonly record struct NotificationTask(string Id, long Handle, string Session)
{
    internal static NotificationTask From(Slot slot) => new(slot.Id, slot.Window?.Handle ?? 0, slot.SessionId);
}
internal sealed record TaskNotice(NotificationTask Task, int Number, string Name, AgentState State);

/// <summary>One notification per outcome per turn, with a bounded merge window.
/// Native balloon callbacks do not carry a task identity, so clicks open the
/// live task overview instead of guessing which historical window was meant.</summary>
internal sealed class TaskNotifications
{
    private readonly Dictionary<NotificationTask, HashSet<AgentState>> _seen = new();
    private readonly Dictionary<NotificationTask, TaskNotice> _pending = new();
    private DateTimeOffset? _flushAt;
    internal bool HasPending => _pending.Count > 0;
    internal static bool Attention(AgentState state) => state is AgentState.Ready or AgentState.Waiting or AgentState.Error;
    internal static bool PlayCompletion(IEnumerable<TaskNotice> notices,bool enabled,bool paused) => enabled && !paused && notices.Any(n=>n.State==AgentState.Ready);
    internal void Observe(Slot slot)
    {
        var key = NotificationTask.From(slot);
        if (!slot.Occupied || !slot.Connected || !Attention(slot.State)) {
            _seen.Remove(key); _pending.Remove(key);
            if (_pending.Count == 0) _flushAt = null;
        }
    }
    internal bool Queue(Slot slot, bool enabled, DateTimeOffset now, long foreground)
    {
        if (!enabled) { Clear(); return false; }
        Observe(slot);
        if (!slot.Occupied || !slot.Connected || !slot.Unread || !Attention(slot.State)) return false;
        var key = NotificationTask.From(slot);
        if (!_seen.TryGetValue(key, out var states)) _seen[key] = states = new();
        if (!states.Add(slot.State)) return false;
        // Restored historical outcomes retain the wheel badge, without a burst
        // of startup notifications. Watching this terminal needs no OS popup.
        if (slot.UpdatedAt is not { } at || now-at > TimeSpan.FromSeconds(45) || at-now > TimeSpan.FromSeconds(5) || key.Handle == foreground) return false;
        _pending[key] = new(key, slot.Number, slot.DisplayName, slot.State);
        _flushAt ??= now.AddMilliseconds(900);
        return true;
    }
    internal TaskNotice[] Flush(IEnumerable<Slot> slots, bool enabled, DateTimeOffset now, long foreground)
    {
        if (!enabled) { Clear(); return Array.Empty<TaskNotice>(); }
        var live = slots.Where(s => s.Occupied && s.Connected).ToDictionary(NotificationTask.From);
        foreach (var key in _seen.Keys.Where(k => !live.ContainsKey(k)).ToArray()) _seen.Remove(key);
        if (_flushAt == null || now < _flushAt) return Array.Empty<TaskNotice>();
        var result = _pending.Values.Where(n => live.TryGetValue(n.Task, out var s) && s.Unread && s.State == n.State && s.Window!.Handle != foreground)
            .Select(n => n with { Number=live[n.Task].Number, Name=live[n.Task].DisplayName }).OrderBy(n => n.Number).ToArray();
        _pending.Clear(); _flushAt = null;
        return result;
    }
    internal void Clear() { _pending.Clear(); _seen.Clear(); _flushAt = null; }
    internal static string Caption(AgentState state) => state switch { AgentState.Ready=>"回复待查看", AgentState.Waiting=>"等待确认", AgentState.Error=>"发生错误", _=>"执行中" };
    internal static string SafeName(string name) => new string(name.Where(c => !char.IsControl(c)).Take(48).ToArray());
}
