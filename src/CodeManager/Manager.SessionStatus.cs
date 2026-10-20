using System;
using System.Linq;
using System.Threading.Tasks;

namespace CodeManager;

public sealed partial class Manager
{
    private readonly SessionStatusSource _sessionStatus = new();
    private readonly TerminalStatusSignals _terminalSignals = new();
    private Task? _sessionPoll;
    private DateTime _sessionPollAfter;
    private void PollSessionStatus()
    {
        if (_disposed || DateTime.UtcNow < _sessionPollAfter || _sessionPoll is { IsCompleted:false }) return;
        _sessionPollAfter = DateTime.UtcNow.AddSeconds(1);
        var targets = State.Slots.Where(s => s.Occupied && s.Connected).Select(s => new SessionTarget(s.Id,s.Window!.Handle,Native.Title(new(s.Window.Handle)),s.SessionId,s.StatusSessionPath ?? "")).ToArray();
        if(targets.Length==0)return;
        _sessionPoll = ReadSessionStatusAsync(targets);
    }
    private async Task ReadSessionStatusAsync(SessionTarget[] targets)
    {
        try {
            var signals = await Task.Run(() => { _terminalSignals.Retain(targets); return targets.Select(t=>(Target:t,Status:_terminalSignals.Read(t))).Where(s=>s.Status!=null).ToArray(); });
            if(_disposed)return;
            ApplySessionBatch(()=>{
            foreach(var signal in signals) {
                var slot=State.Slots.FirstOrDefault(s=>s.Id==signal.Target.TaskId && s.Window?.Handle==signal.Target.Handle);
                if(slot==null)continue;
                // Precise unread hook/transcript outcomes outrank a generic bell.
                if(signal.Status!.State==AgentState.Waiting && slot.Unread && slot.State is AgentState.Ready or AgentState.Waiting or AgentState.Error)continue;
                if(signal.Status.State==AgentState.Unknown && slot.StateSource!="终端状态信号")continue;
                if(signal.Status.State==AgentState.Running && slot.Unread && slot.StateSource!="终端状态信号" && slot.State is AgentState.Waiting or AgentState.Error)continue;
                if(signal.Status.State==AgentState.Running && slot.State==AgentState.Running && slot.StateSource!="终端状态信号")continue;
                SetStatus(slot,signal.Status.State,"终端状态信号",signal.Status.Message,signal.Status.At);
            }
            return false;
            });
            var updates = await _sessionStatus.PollAsync(targets);
            if (_disposed) return;
            ApplySessionBatch(()=>{
            bool bound = false;
            foreach (var update in updates) {
                var slot = State.Slots.FirstOrDefault(s => s.Id == update.Target.TaskId && s.Occupied && s.Window!.Handle == update.Target.Handle);
                if (slot == null || slot.SessionId != update.Target.SessionId || slot.StatusSessionPath != update.Target.File) continue;
                var session = update.Session;
                if (State.Slots.Any(s => s != slot && s.Occupied && s.SessionId == session.Id)) continue;
                if (slot.StatusSessionPath != session.File) { BindSession(slot,session); bound = true; }
                var status = update.Status;
                if (status == null || (slot.StateSource!="终端状态信号" && slot.UpdatedAt.HasValue && slot.UpdatedAt >= status.At)) continue;
                if(slot.StateSource=="终端状态信号" && slot.State==AgentState.Running && slot.UpdatedAt.HasValue && status.At<slot.UpdatedAt.Value.AddSeconds(-2))continue;
                // Tool-output records provide liveness but should not cause one disk
                // write per tool. Genuine state changes remain immediate.
                if (slot.State == AgentState.Running && status.State == AgentState.Running && slot.UpdatedAt.HasValue && status.At-slot.UpdatedAt.Value < TimeSpan.FromSeconds(30)) continue;
                string source = (session.Provider == "codex" ? "Codex" : "Claude Code") + L.T(" 会话记录");
                if (update.Initial && slot.UpdatedAt == null) {
                    slot.State=status.State; slot.StateSource=source; slot.Message=status.Message; slot.UpdatedAt=status.At;
                    slot.Unread=status.State is AgentState.Ready or AgentState.Waiting or AgentState.Error;
                    slot.Refresh(); bound=true;
                    if(slot.Unread)NotifyStatus(slot);
                } else {
                    slot.IntegrationConnected=true;
                    var receivedAt=slot.StateSource=="终端状态信号" && slot.UpdatedAt>=status.At ? DateTimeOffset.UtcNow : status.At;
                    SetStatus(slot,status.State,source,status.Message,receivedAt);
                }
            }
            return bound;
            });
        } catch (Exception e) when (e is System.IO.IOException or UnauthorizedAccessException or InvalidOperationException) { Store.Log("Session status: " + e.Message); }
    }
    private static void BindSession(Slot slot, AgentSession session)
    {
        slot.StatusSessionPath=session.File; slot.SessionId=session.Id; slot.ResumeSessionId=session.Id;
        slot.AgentProvider=session.Provider; slot.IntegrationConnected=true;
        if (slot.ProjectDirectory == "") slot.ProjectDirectory=session.Project;
        if (slot.LaunchMode == LaunchMode.Unconfigured) slot.LaunchMode=session.Provider == "codex" ? LaunchMode.Codex : LaunchMode.Claude;
        slot.Refresh();
    }
    public async void ConnectExistingSession(Slot slot)
    {
        if (!slot.Occupied) return;
        BeginDialog();
        try {
            var sessions = await _sessionStatus.DiscoverAsync();
            if (_disposed || !slot.Occupied) return;
            var available = sessions.Where(s => !State.Slots.Any(t => t != slot && t.Occupied && t.SessionId == s.Id)).ToArray();
            var window = new SessionLinkWindow(available,slot,WorkArea);
            if (window.ShowDialog() == true && window.SelectedSession is AgentSession session) {
                BindSession(slot,session); slot.UpdatedAt=null; slot.State=AgentState.Unknown; slot.Unread=false;
                _sessionStatus.Reset(slot.Id);
                Save(); Dock.UpdateSummary(); _sessionPollAfter=DateTime.MinValue;
                Hint(slot.Number + L.T(" · 已连接会话，正在读取状态"));
            }
        } catch (Exception e) when (e is System.IO.IOException or UnauthorizedAccessException) { Hint(L.T("会话记录暂不可读：") + e.Message); }
        finally { EndDialog(); }
    }
}
