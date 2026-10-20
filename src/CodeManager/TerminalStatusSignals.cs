using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Automation;

namespace CodeManager;

/// <summary>Reads the CLI's explicit title spinner and Terminal's selected-tab
/// progress/bell accessibility elements. Bell means attention, never proof of success.</summary>
internal sealed class TerminalStatusSignals
{
    private readonly Dictionary<string,(bool Bell, bool Running, bool Progress, DateTime Next, DateTime LastActivity)> _last = new();
    private readonly Dictionary<long,Task<(bool Bell,bool Progress)>> _probes = new();
    internal void Retain(IReadOnlyList<SessionTarget> targets)
    {
        var ids=targets.Select(t=>t.TaskId).ToHashSet();var handles=targets.Select(t=>t.Handle).ToHashSet();
        foreach(string id in _last.Keys.Where(k=>!ids.Contains(k)).ToArray())_last.Remove(id);
        foreach(long handle in _probes.Keys.Where(k=>!handles.Contains(k) && _probes[k].IsCompleted).ToArray())_probes.Remove(handle);
    }
    internal static bool BusyTitle(string title) => title.TrimStart().Length>1 && title.TrimStart()[0] is >= '\u2801' and <= '\u28ff';
    internal static string CleanTitle(string title) => BusyTitle(title) ? title.TrimStart()[1..].TrimStart() : title.Trim();
    internal static AgentState? Classify(bool spinner,bool progress,bool bell) => spinner || progress ? AgentState.Running : bell ? AgentState.Waiting : null;
    internal StatusEvent? Read(SessionTarget target)
    {
        bool busy=BusyTitle(target.Title);
        var old=_last.GetValueOrDefault(target.TaskId);DateTime next=old.Next;
        bool bell=old.Bell,progress=old.Progress;
        if(!busy) {
            _probes.TryGetValue(target.Handle,out var probe);
            if(probe is {IsCompletedSuccessfully:true}) { (bell,progress)=probe.Result; }
            // An unresponsive accessibility provider never stalls transcript reads
            // or creates an unbounded queue of replacement probes.
            if(DateTime.UtcNow>=next && (probe==null || probe.IsCompleted) && _probes.Values.Count(p=>!p.IsCompleted)<4) {
                next=DateTime.UtcNow.AddSeconds(3);
                _probes[target.Handle]=Task.Run(() => Probe(target.Handle));
            }
        }
        bool running=busy||progress;
        bool stopped=old.Running && !running && !bell;
        bool emit=running ? !old.Running || DateTime.UtcNow-old.LastActivity>TimeSpan.FromSeconds(30) : bell && !old.Bell || stopped;
        _last[target.TaskId]=(bell,running,progress,next,emit&&running?DateTime.UtcNow:old.LastActivity);
        var state=Classify(busy,progress,bell) ?? (stopped?AgentState.Unknown:null);
        if(!emit || state==null)return null;
        return new() { TaskId=target.TaskId,State=state.Value,At=DateTimeOffset.UtcNow,EventName="TerminalSignal",Message=running?"终端正在执行（标题或进度信号）":bell?"终端发出通知，请查看结果或确认请求":"忙碌标记已结束，完成状态待确认" };
    }
    private static (bool Bell,bool Progress) Probe(long handle)
    {
        bool bell=false,progress=false;
            try {
                var root=AutomationElement.FromHandle(new IntPtr(handle));
                // Search the header first. A global FindAll walks the terminal's
                // document provider even though only one tab header is needed.
                var strip=root.FindFirst(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Tab));
                AutomationElement? selected=null;
                if(strip!=null && strip.TryGetCurrentPattern(SelectionPattern.Pattern,out var selection))selected=((SelectionPattern)selection).Current.GetSelection().FirstOrDefault();
                if(selected==null) {
                    var tab=strip?.FindFirst(TreeScope.Children,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.TabItem)) ?? root.FindFirst(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.TabItem));
                    for(int visited=0;tab!=null && visited<64;visited++,tab=TreeWalker.ControlViewWalker.GetNextSibling(tab))
                        if(tab.Current.ControlType==ControlType.TabItem && tab.TryGetCurrentPattern(SelectionItemPattern.Pattern,out var pattern) && ((SelectionItemPattern)pattern).Current.IsSelected) {selected=tab;break;}
                }
                if(selected!=null) foreach(var pair in new[]{("HeaderProgressRing",true),("HeaderBellIndicator",false)}) {
                    var icon=selected.FindFirst(TreeScope.Descendants,new PropertyCondition(AutomationElement.AutomationIdProperty,pair.Item1));
                    bool visible=icon!=null && !icon.Current.IsOffscreen && !icon.Current.BoundingRectangle.IsEmpty;
                    if(pair.Item2)progress=visible;else bell=visible;
                }
            } catch(Exception e) when(e is ElementNotAvailableException or InvalidOperationException or System.Runtime.InteropServices.COMException or UnauthorizedAccessException or ArgumentException) { }
        return (bell,progress);
    }
}
