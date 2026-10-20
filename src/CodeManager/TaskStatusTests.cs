using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace CodeManager;

public static class TaskStatusTests
{
    public static List<SelfTests.Result> Run(string output)
    {
        Directory.CreateDirectory(output);var results=new List<SelfTests.Result>();
        void Test(string name,Action action) { try { action();results.Add(new(name,true,"OK")); }catch(Exception e){results.Add(new(name,false,e.ToString()));} }
        static void Check(bool condition,string reason) { if(!condition)throw new Exception(reason); }
        string id=Guid.NewGuid().ToString(),task=Guid.NewGuid().ToString("N");var now=DateTimeOffset.UtcNow;
        string Record(string type,string payload,int seconds=0)=>JsonSerializer.Serialize(new{timestamp=now.AddSeconds(seconds).ToString("o"),type,payload=JsonSerializer.Deserialize<JsonElement>(payload)});
        Test("Explicit terminal signals: braille spinner is busy; bell is attention; silence and task names never imply completion",()=>{
            Check(TerminalStatusSignals.BusyTitle("⠼ fixture | repo"),"Spinner not recognized");
            Check(TerminalStatusSignals.CleanTitle("⠼ fixture | repo")=="fixture | repo","Spinner not removed for matching");
            Check(!TerminalStatusSignals.BusyTitle("完成BIG-2529"),"Task title guessed as state");
            Check(TerminalStatusSignals.Classify(false,false,true)==AgentState.Waiting,"Bell falsely means success");
            Check(TerminalStatusSignals.Classify(false,false,false)==null,"Silence falsely means completion");
            Check(TerminalStatusSignals.Classify(true,false,true)==AgentState.Running,"Busy signal lost to stale bell");
        });
        Test("Codex lifecycle records distinguish turn completion, interruption and errors, ignoring token updates",()=>{
            foreach(var pair in new[]{("task_started",AgentState.Running),("task_complete",AgentState.Ready),("task_failed",AgentState.Error),("turn_aborted",AgentState.Unknown)})
                Check(SessionStatusSource.Parse("codex",task,id,Record("event_msg",JsonSerializer.Serialize(new{type=pair.Item1})))?.State==pair.Item2,"Wrong lifecycle: "+pair.Item1);
            Check(SessionStatusSource.Parse("codex",task,id,Record("event_msg","{\"type\":\"token_count\"}"))==null,"Token count guessed as state");
            Check(SessionStatusSource.Parse("codex",task,id,"{bad")==null,"Malformed JSON escaped parser");
        });
        Test("Claude records: submitted turn, explicit reply end and questions; subagents and foreign sessions ignored",()=>{
            string Row(object value)=>JsonSerializer.Serialize(value);
            Check(SessionStatusSource.Parse("claude",task,id,Row(new{type="user",sessionId=id,timestamp=now,message=new{role="user"}}))?.State==AgentState.Running,"Prompt not running");
            Check(SessionStatusSource.Parse("claude",task,id,Row(new{type="system",subtype="turn_duration",sessionId=id,timestamp=now}))?.State==AgentState.Ready,"End not ready");
            Check(SessionStatusSource.Parse("claude",task,id,Row(new{type="assistant",sessionId=id,timestamp=now,message=new{content=new[]{new{type="tool_use",name="AskUserQuestion"}}}}))?.State==AgentState.Waiting,"Question not waiting");
            Check(SessionStatusSource.Parse("claude",task,id,Row(new{type="user",isSidechain=true,sessionId=id,timestamp=now}))==null,"Subagent leaked");
            Check(SessionStatusSource.Parse("claude",task,id,Row(new{type="user",sessionId="other",timestamp=now}))==null,"Other session leaked");
        });
        string fixture=Path.Combine(output,"isolated",Guid.NewGuid().ToString("N")),codex=Path.Combine(fixture,"codex","sessions"),claude=Path.Combine(fixture,"claude","projects");
        string directory=Path.Combine(codex,DateTime.UtcNow.ToString("yyyy/MM/dd"));Directory.CreateDirectory(directory);
        string path=Path.Combine(directory,"rollout-"+id+".jsonl");
        string Header(string session,string title)=>Record("session_meta",JsonSerializer.Serialize(new{id=session,cwd=fixture,source="cli",title}));
        File.WriteAllText(path,Header(id,"fixture-login")+"\n"+Record("event_msg","{\"type\":\"task_started\"}")+"\n",new UTF8Encoding(false));
        Test("Incremental session observation: initial state, partial UTF-8 rows, completion and idempotence",()=>{
            var source=new SessionStatusSource(codex,claude);var target=new SessionTarget(task,1,"fixture-login",id,path);
            var first=source.PollAsync(new[]{target}).GetAwaiter().GetResult();Check(first.Count==1 && first[0].Initial && first[0].Status?.State==AgentState.Running,"Initial state missing");
            string completion=Record("event_msg","{\"type\":\"task_complete\",\"last_agent_message\":\"中文结果\"}",1)+"\n";
            byte[] bytes=Encoding.UTF8.GetBytes(completion);int split=bytes.Length-8;
            using(var f=new FileStream(path,FileMode.Append,FileAccess.Write,FileShare.ReadWrite))f.Write(bytes,0,split);
            Check(source.PollAsync(new[]{target}).GetAwaiter().GetResult().Count==0,"Partial line incorrectly applied");
            using(var f=new FileStream(path,FileMode.Append,FileAccess.Write,FileShare.ReadWrite))f.Write(bytes,split,bytes.Length-split);
            var ready=source.PollAsync(new[]{target}).GetAwaiter().GetResult();Check(ready.Single().Status?.State==AgentState.Ready && !ready[0].Initial,"Reply not delivered");
            Check(source.PollAsync(new[]{target}).GetAwaiter().GetResult().Count==0,"Duplicate event");
            source.Reset(task);Check(source.PollAsync(new[]{target}).GetAwaiter().GetResult().Single().Initial,"Explicit relink failed to reread state");
            File.WriteAllText(path,Header(id,"fixture-login")+"\n",new UTF8Encoding(false));
            Check(source.PollAsync(new[]{target}).GetAwaiter().GetResult().Single().Initial,"Truncation not reset");
        });
        Test("Unique exact title linking strips spinners; duplicate window names never auto-bind",()=>{
            var source=new SessionStatusSource(codex,claude);
            var target=new SessionTarget("one",1,"⠋ fixture-login | repo","","");
            Check(source.PollAsync(new[]{target}).GetAwaiter().GetResult().Count==1,"Exact title did not link");
            var ambiguous=new SessionStatusSource(codex,claude);
            Check(ambiguous.PollAsync(new[]{target,target with{TaskId="two",Handle=2}}).GetAwaiter().GetResult().Count==0,"Ambiguous windows were guessed");
            Check(!SessionStatusSource.MatchesTitle("fixture-login-other | repo","fixture-login"),"Partial name accepted");
        });
        Test("Attention persists even if terminal is foreground; a new turn clears acknowledgement",()=>{
            var manager=(Manager)RuntimeHelpers.GetUninitializedObject(typeof(Manager));
            typeof(Manager).GetField("_processingStatusBatch",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(manager,true);
            var slot=new Slot{Window=new(),Connected=true,IsActive=true};
            manager.SetStatus(slot,AgentState.Ready,"fixture","reply",now);Check(slot.Unread,"Foreground suppressed completion reminder");
            manager.SetStatus(slot,AgentState.Running,"fixture","new turn",now.AddSeconds(1));Check(!slot.Unread,"New turn retained old notification");
        });
        Test("Compact summary includes other tasks; disconnects are excluded and read markers do not erase outcomes",()=>{
            var slots=new[]{new Slot{Window=new(),Connected=true,State=AgentState.Running},new Slot{Window=new(),Connected=true,State=AgentState.Ready,Unread=true},new Slot{Window=new(),Connected=false,State=AgentState.Error,Unread=true}};
            var summary=WheelStatusSummary.From(slots);Check(summary.Running==1 && summary.Ready==1 && summary.Errors==0 && summary.Attention==1,"Aggregate wrong");
            slots[1].Unread=false;Check(WheelStatusSummary.From(slots).Attention==0 && slots[1].State==AgentState.Ready,"Viewing erased result");
        });
        Test("Observed completion reaches the real manager and saved state; acknowledgement and the next turn remain distinct",()=>{
            File.WriteAllText(path,Header(id,"fixture-login")+"\n"+Record("event_msg","{\"type\":\"task_complete\"}",2)+"\n",new UTF8Encoding(false));
            var store=new StateStore(Path.Combine(fixture,"manager-state"));var state=new AppState();var slot=state.Slots[0];
            slot.Window=new WindowIdentity{Handle=1,Title="fixture-login"};slot.Connected=true;
            var manager=(Manager)RuntimeHelpers.GetUninitializedObject(typeof(Manager));var dock=new DockWindow(interactionTest:true);
            void Field(string name,object value)=>typeof(Manager).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(manager,value);
            Field("<State>k__BackingField",state);Field("<Store>k__BackingField",store);Field("<Dock>k__BackingField",dock);
            Field("_sessionStatus",new SessionStatusSource(codex,claude));Field("_terminalSignals",new TerminalStatusSignals());
            void Poll() {
                var targets=new[]{new SessionTarget(slot.Id,1,"fixture-login",slot.SessionId,slot.StatusSessionPath)};
                var pending=(System.Threading.Tasks.Task)typeof(Manager).GetMethod("ReadSessionStatusAsync",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(manager,new object[]{targets})!;
                var watch=Stopwatch.StartNew();while(!pending.IsCompleted && watch.ElapsedMilliseconds<5000) {var frame=new DispatcherFrame();Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background,new Action(()=>frame.Continue=false));Dispatcher.PushFrame(frame);Thread.Sleep(1);}Check(pending.IsCompleted,"Manager poll stalled");pending.GetAwaiter().GetResult();
            }
            try {
                Poll();Check(slot.State==AgentState.Ready && slot.Unread && slot.IntegrationConnected,"Initial completion did not notify");
                Check(store.Load().Slots[0].StatusSessionPath==path,"Connection not persisted");
                manager.MarkRead(slot);Check(!slot.Unread && slot.State==AgentState.Ready,"Acknowledgement erased result");
                File.AppendAllText(path,Record("event_msg","{\"type\":\"task_started\"}",3)+"\n");
                Poll();Check(slot.State==AgentState.Running && !slot.Unread,"Next turn failed to resume");
            } finally {dock.Close();}
        });
        Test("All thirteen themes: native compact/expanded status surfaces, animated attention and static motion-off fallback",()=>{
            Skin before=WuxiaTheme.CurrentSkin;bool decorations=SkinCatalog.DecorationsEnabled;
            try { foreach(var skin in SkinCatalog.All) {
                WuxiaTheme.Apply(skin.Id,true);
                var slots=Enumerable.Range(1,9).Select(n=>new Slot{Id="status-fixture-"+n,Number=n,Window=n<=4?new WindowIdentity{Title="fixture"}:null,Connected=n<=4,State=n switch{1=>AgentState.Running,2=>AgentState.Ready,3=>AgentState.Waiting,_=>AgentState.Error},Unread=n is 2 or 3 or 4,IntegrationConnected=n<=4}).ToArray();
                slots[0].IsActive=true;EquipmentCatalog.EnsureDefaults(slots);
                var wheel=new DockWeaponWheel{Width=460,Height=510,MotionEnabled=false};wheel.SetSlots(slots);wheel.Deploy(true,false);
                wheel.Measure(new Size(460,510));wheel.Arrange(new Rect(0,0,460,510));wheel.Flow=.09;
                Save(wheel,Path.Combine(output,skin.Slug+"-expanded.png"),460,510);
                foreach(string state in new[]{"running","ready"}) {
                    var group=new DrawingGroup();using(var dc=group.Open()) {
                        dc.DrawRectangle(new SolidColorBrush((Color)ColorConverter.ConvertFromString(skin.Background)),null,new Rect(0,0,180,180));
                        dc.PushTransform(new TranslateTransform(90,90));
                        EquipmentCatalog.Draw(dc,slots[0],new Rect(-53,-55,106,106));
                        if(state=="running")foreach(var s in slots.Skip(1))s.Unread=false;
                        else slots[1].Unread=true;
                        WheelTaskStatus.DrawCore(dc,skin,slots,slots[0],.08,true);dc.Pop();
                    }
                    Save(group,Path.Combine(output,skin.Slug+"-compact-"+state+".png"),180,180);
                }
                Check(WheelTaskStatus.NeedsMotion(slots),"Motion absent "+skin.Slug);
                var a=new DrawingGroup();using(var c=a.Open())WheelTaskStatus.DrawCore(c,skin,slots,slots[0],.01,false);
                var b=new DrawingGroup();using(var c=b.Open())WheelTaskStatus.DrawCore(c,skin,slots,slots[0],.22,false);
                Check(Pixels(a).SequenceEqual(Pixels(b)),"Disabled effects still animate "+skin.Slug);
                var animatedA=new DrawingGroup();using(var d=animatedA.Open())WheelTaskStatus.DrawCore(d,skin,slots,slots[0],.01,true);
                var animatedB=new DrawingGroup();using(var d=animatedB.Open())WheelTaskStatus.DrawCore(d,skin,slots,slots[0],.22,true);
                Check(!Pixels(animatedA).SequenceEqual(Pixels(animatedB)),"Attention animation does not change pixels "+skin.Slug);
            }} finally {WuxiaTheme.Apply(before,decorations);}
        });
        Test("Read-only local discovery: bounded background scan and actual window-title match coverage",()=>{
            var watch=Stopwatch.StartNew();var sessions=new SessionStatusSource().DiscoverAsync().GetAwaiter().GetResult();
            var state=new StateStore().Load();var occupied=state.Slots.Where(s=>s.Occupied && Native.Matches(s.Window)).ToArray();
            var evidence=new{sessions=sessions.Count,scanMilliseconds=watch.Elapsed.TotalMilliseconds,boundWindows=occupied.Length,uniqueTitleMatches=occupied.Count(s=>sessions.Count(t=>SessionStatusSource.MatchesTitle(Native.Title(new(s.Window!.Handle)),t.Title))==1),privateConversationContentRecorded=false};
            File.WriteAllText(Path.Combine(output,"local-discovery.json"),JsonSerializer.Serialize(evidence,new JsonSerializerOptions{WriteIndented=true}));Check(sessions.Count<=96,"Unbounded session scan");
        });
        return results;
    }
    private static byte[] Pixels(Drawing drawing) {var v=new DrawingVisual();using(var d=v.RenderOpen())d.DrawDrawing(drawing);var b=new RenderTargetBitmap(180,180,96,96,PixelFormats.Pbgra32);b.Render(v);var bytes=new byte[180*180*4];b.CopyPixels(bytes,180*4,0);return bytes;}
    private static void Save(object item,string path,int width,int height) {var bitmap=new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32);if(item is Visual visual)bitmap.Render(visual);else{var v=new DrawingVisual();using(var d=v.RenderOpen())d.DrawDrawing((Drawing)item);bitmap.Render(v);}var e=new PngBitmapEncoder();e.Frames.Add(BitmapFrame.Create(bitmap));using var f=File.Create(path);e.Save(f);}
}
