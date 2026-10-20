using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows.Interop;
using System.Windows.Threading;

namespace CodeManager;

internal static class PerformanceTests
{
    internal static IEnumerable<SelfTests.Result> Run(string output)
    {
        var results=new List<SelfTests.Result>();const BindingFlags flags=BindingFlags.Instance|BindingFlags.NonPublic;
        void Check(bool ok,string reason){if(!ok)throw new Exception(reason);}
        void Test(string name,Action action){try{action();results.Add(new(name,true,"OK"));}catch(Exception error){results.Add(new(name,false,error.ToString()));}}
        string root=Path.Combine(output,"performance-fixtures",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        Test("Performance: cached session headers honor title edits, appended outcomes and a same-size foreign-session rewrite",()=>{
            string codex=Path.Combine(root,"codex","sessions"),folder=Path.Combine(codex,DateTime.UtcNow.ToString("yyyy/MM/dd")),id=Guid.NewGuid().ToString();Directory.CreateDirectory(folder);
            string file=Path.Combine(folder,"fixture.jsonl"),index=Path.Combine(root,"codex","session_index.jsonl");var now=DateTimeOffset.UtcNow;
            string header=JsonSerializer.Serialize(new{type="session_meta",timestamp=now,payload=new{id,cwd=root,title="fixture-task"}})+"\n";
            string Row(string type,int seconds)=>JsonSerializer.Serialize(new{type="event_msg",timestamp=now.AddSeconds(seconds),payload=new{type}})+"\n";
            File.WriteAllText(file,header+Row("task_started",0));var source=new SessionStatusSource(codex,Path.Combine(root,"claude"));
            Check(source.DiscoverAsync().GetAwaiter().GetResult().Single().Title=="fixture-task","Initial metadata missing");
            File.WriteAllText(index,JsonSerializer.Serialize(new{id,thread_name="renamed-task"})+"\n");
            Check(source.DiscoverAsync().GetAwaiter().GetResult().Single().Title=="renamed-task","Metadata cache hid title change");
            var target=new SessionTarget("task",1,"",id,file);Check(source.PollAsync(new[]{target}).GetAwaiter().GetResult().Single().Status?.State==AgentState.Running,"Initial bound session lost");
            Check(source.PollAsync(new[]{target}).GetAwaiter().GetResult().Count==0,"Unchanged file emitted twice");
            File.AppendAllText(file,Row("task_complete",1));Check(source.PollAsync(new[]{target}).GetAwaiter().GetResult().Single().Status?.State==AgentState.Ready,"Append missed by fast path");
            string text=File.ReadAllText(file);File.WriteAllText(file,text.Replace(id,Guid.NewGuid().ToString()));File.SetLastWriteTimeUtc(file,DateTime.UtcNow.AddSeconds(2));
            Check(source.PollAsync(new[]{target}).GetAwaiter().GetResult().Count==0,"Replaced file hijacked previous session");
        });
        Test("Performance: mouse movement and unused modifier releases bypass gesture work; in-place shortcut edits still take effect",()=>{
            using var input=new InputService(Dispatcher.CurrentDispatcher);var p=new Preferences{TabTogglesInventory=false,ArrangeGesture="",RadialGesture="",ToggleGesture="Ctrl+Alt+F24"};p.TaskGestures[1]="Ctrl+Alt+F23";
            input.Configure(p,new[]{1},false);Check(input.RegisteredTasks.Contains(1),"Fixture shortcut unavailable");
            p.TaskGestures[1]="";input.Configure(p,new[]{1},false);Check(!input.RegisteredTasks.Contains(1),"Fast snapshot hid in-place shortcut edit");
            int probes=0;input.CanHandleMouse=()=>{probes++;return false;};var hook=typeof(InputService).GetMethod("MouseHook",flags)!;
            for(int i=0;i<100;i++)hook.Invoke(input,new object[]{0,new IntPtr(0x200),IntPtr.Zero});Check(probes==0,"Mouse movement ran modifier/gesture checks");
            int released=0;input.IsSelecting=()=>false;input.Release+=()=>released++;
            IntPtr key=System.Runtime.InteropServices.Marshal.AllocHGlobal(32);
            try{System.Runtime.InteropServices.Marshal.WriteInt32(key,0x12);typeof(InputService).GetMethod("KeyboardHook",flags)!.Invoke(input,new object[]{0,new IntPtr(0x105),key});Dispatcher.CurrentDispatcher.Invoke(()=>{},DispatcherPriority.Background);Check(released==0,"Unrelated Alt release queued a UI action");}
            finally{System.Runtime.InteropServices.Marshal.FreeHGlobal(key);}
        });
        Test("Performance: native validation still rejects wrong process, creation time and destroyed handles",()=>{
            using var host=new HwndSource(new HwndSourceParameters("OmniVibe identity fixture"){ParentWindow=new IntPtr(-3),Width=0,Height=0});using var process=Process.GetCurrentProcess();
            var good=new WindowIdentity{Handle=host.Handle.ToInt64(),ProcessId=Environment.ProcessId,ProcessStartedUtcTicks=process.StartTime.ToUniversalTime().Ticks};Check(Native.Matches(good),"Exact identity rejected");
            Check(!Native.Matches(new(){Handle=good.Handle,ProcessId=good.ProcessId,ProcessStartedUtcTicks=good.ProcessStartedUtcTicks+1}),"Creation-time protection removed");
            Check(!Native.Matches(new(){Handle=good.Handle,ProcessId=good.ProcessId+1}),"Process protection removed");host.Dispose();Check(!Native.Matches(good),"Destroyed handle accepted");
        });
        Test("Performance: session batches persist all outcomes, retain dirty data on write failure and recover after exceptions",()=>{
            var store=new StateStore(Path.Combine(root,"batch"));var state=new AppState();foreach(var s in state.Slots.Take(2)){s.Window=new();s.Connected=true;}
            var manager=(Manager)RuntimeHelpers.GetUninitializedObject(typeof(Manager));var dock=new DockWindow(interactionTest:true);
            void Set(string name,object value)=>typeof(Manager).GetField(name,flags)!.SetValue(manager,value);
            Set("<State>k__BackingField",state);Set("<Store>k__BackingField",store);Set("<Dock>k__BackingField",dock);
            var batch=typeof(Manager).GetMethod("ApplySessionBatch",flags)!;
            try {
                Directory.CreateDirectory(store.StateFile);
                batch.Invoke(manager,new object[]{new Func<bool>(()=>{state.Slots[0].SessionId="bound-session-fixture";return true;})});
                Check((bool)typeof(Manager).GetField("_statusBatchDirty",flags)!.GetValue(manager)!,"Write failure discarded metadata-only binding");
                batch.Invoke(manager,new object[]{new Func<bool>(()=>{foreach(var s in state.Slots.Take(2))manager.SetStatus(s,AgentState.Ready,"fixture","done");return false;})});
                Check((bool)typeof(Manager).GetField("_statusBatchDirty",flags)!.GetValue(manager)!,"Write failure discarded dirty state");
                try{batch.Invoke(manager,new object[]{new Func<bool>(()=>throw new InvalidOperationException("fixture"))});}catch(TargetInvocationException){}
                Check(!(bool)typeof(Manager).GetField("_processingStatusBatch",flags)!.GetValue(manager)!,"Exception left batching enabled");
                Directory.Delete(store.StateFile);batch.Invoke(manager,new object[]{new Func<bool>(()=>false)});
                Check(store.Load().Slots.Take(2).All(s=>s.State==AgentState.Ready && s.Unread),"Retry lost an outcome");
            }finally{dock.Close();}
        });
        return results;
    }
}
