using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using CodeManager;

internal static class Program
{
    private const BindingFlags Private=BindingFlags.Instance|BindingFlags.NonPublic;
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
    private static void Pump(int ms) {var frame=new DispatcherFrame();var timer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(ms)};timer.Tick+=(_,_)=>{timer.Stop();frame.Continue=false;};timer.Start();Dispatcher.PushFrame(frame);}
    private static void Require(bool value,string reason) {if(!value)throw new InvalidOperationException(reason);}
    private static object Sample(string name,int seconds,Process process)
    {
        process.Refresh();double cpu=process.TotalProcessorTime.TotalMilliseconds;var watch=Stopwatch.StartNew();Pump(seconds*1000);process.Refresh();
        return new{name,seconds=watch.Elapsed.TotalSeconds,one_core_percent=100*(process.TotalProcessorTime.TotalMilliseconds-cpu)/watch.Elapsed.TotalMilliseconds,private_bytes=process.PrivateMemorySize64,handles=process.HandleCount};
    }
    [STAThread] private static int Main(string[] args)
    {
        string output=Path.GetFullPath(args[0]);Directory.CreateDirectory(output);int seconds=args.Length>1 && int.TryParse(args[1],out int duration)?duration:300;
        var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};var windows=new List<Window>();Manager? manager=null;
        try {
            if(args.Length>1 && args[1]=="--monitor-smoke") {
                var fixture=new Window{Title="OmniVibe monitor fixture",Width=320,Height=180,ShowActivated=false,ShowInTaskbar=false};fixture.Show();windows.Add(fixture);
                var monitorHandle=new WindowInteropHelper(fixture).Handle;var monitorSamples=new List<object>();
                foreach(var screen in System.Windows.Forms.Screen.AllScreens) {
                    var area=screen.WorkingArea;var cell=new Cell(area.Left+100,area.Top+100,320,180);
                    Require(Native.PlaceVisibleWindow(monitorHandle,cell),"Fixture could not move to monitor");Pump(180);
                    var visible=Native.VisibleBounds(monitorHandle)!.Value;var actual=Native.ScreenForWindow(monitorHandle);
                    Require(Math.Abs(visible.Left-cell.X)<3 && Math.Abs(visible.Top-cell.Y)<3,"Wrong visible origin on physical monitor");
                    Require(actual.Work.Left==area.Left && actual.Work.Top==area.Top,"Wrong physical monitor selected");
                    var placement=Native.PlacementOf(monitorHandle)!.Value;Native.ShowWindow(monitorHandle,6);Pump(80);Require(Native.IsIconic(monitorHandle),"Fixture did not minimize");Native.RestorePlacement(monitorHandle,placement);Pump(120);
                    Require(!Native.IsIconic(monitorHandle),"Fixture failed to restore on physical monitor");
                    var restored=Native.VisibleBounds(monitorHandle)!.Value;Require(Math.Abs(restored.Left-visible.Left)<3 && Math.Abs(restored.Top-visible.Top)<3,"Restore moved fixture to another origin");
                    monitorSamples.Add(new{left=area.Left,top=area.Top,width=area.Width,height=area.Height,scale=actual.Scale});
                }
                File.WriteAllText(Path.Combine(output,"monitors.json"),JsonSerializer.Serialize(new{passed=true,physical_monitors=monitorSamples,fixture_only=true,display_configuration_changed=false}));return 0;
            }
            if(args.Length>3 && args[1]=="--observe-codex") {
                string file=Path.GetFullPath(args[2]),session=args[3];
                var transcriptObserver=new SessionStatusSource(Path.GetDirectoryName(file),Path.Combine(output,"empty-claude"));
                var targetType=typeof(Manager).Assembly.GetType("CodeManager.SessionTarget",true)!;
                var target=Activator.CreateInstance(targetType,new object[]{Guid.NewGuid().ToString("N"),(long)1,"release-fixture",session,file})!;
                var targets=Array.CreateInstance(targetType,1);targets.SetValue(target,0);
                var pending=(System.Threading.Tasks.Task)typeof(SessionStatusSource).GetMethod("PollAsync",Private)!.Invoke(transcriptObserver,new object[]{targets})!;pending.GetAwaiter().GetResult();
                var updates=(System.Collections.IEnumerable)pending.GetType().GetProperty("Result")!.GetValue(pending)!;
                var rows=updates.Cast<object>().ToArray();Require(rows.Length==1,"Actual Codex transcript did not resolve uniquely");
                var status=(StatusEvent)rows[0].GetType().GetProperty("Status")!.GetValue(rows[0])!;
                Require(status.State==AgentState.Ready,"Actual Codex completion did not parse as Ready");
                File.WriteAllText(Path.Combine(output,"real-transcript.json"),JsonSerializer.Serialize(new{passed=true,provider="codex",state=status.State.ToString(),actual_persisted_transcript=true,transcript_modified=false}));return 0;
            }
            var store=new StateStore(Path.Combine(output,"fixture-"+Guid.NewGuid().ToString("N")));var state=new AppState();
            state.MinimizeOnCapture=false;state.Preferences.SoundEffects=false;state.Preferences.SoundNotifications=false;state.Preferences.SystemNotifications=false;state.Preferences.Animate=false;state.Preferences.TabTogglesInventory=false;state.Preferences.HasSeenIntroduction=true;store.Save(state);
            manager=new Manager(store,interactionTest:true);manager.TogglePause();
            // Redirect only this test manager's transcript discovery to empty fixture roots.
            var source=typeof(Manager).Assembly.GetType("CodeManager.SessionStatusSource",true)!;
            var observer=Activator.CreateInstance(source,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,new object[]{Path.Combine(store.Root,"codex"),Path.Combine(store.Root,"claude")},null)!;
            typeof(Manager).GetField("_sessionStatus",Private)!.SetValue(manager,observer);
            for(int i=0;i<9;i++) {
                var w=new Window{Title="OmniVibe release fixture "+Guid.NewGuid().ToString("N"),Width=160,Height=100,Left=-9000,Top=-9000,ShowActivated=false,ShowInTaskbar=false};w.Show();windows.Add(w);
                using var p=Process.GetCurrentProcess();manager.Bind(manager.State.Slots[i],new WindowIdentity{Handle=new WindowInteropHelper(w).Handle.ToInt64(),ProcessId=Environment.ProcessId,ProcessStartedUtcTicks=p.StartTime.ToUniversalTime().Ticks,ProcessName="fixture",Title=w.Title});
            }
            manager.State.Preferences.Animate=true;manager.Dock.UpdateSummary();Pump(12000);
            using var process=Process.GetCurrentProcess();var samples=new List<object>{Sample("nine_unknown_compact",15,process)};
            foreach(var slot in manager.State.Slots)manager.SetStatus(slot,AgentState.Running,"手动标记","fixture");
            samples.Add(Sample("nine_running_compact",15,process));
            File.WriteAllText(Path.Combine(output,"cpu-samples.json"),JsonSerializer.Serialize(samples,new JsonSerializerOptions{WriteIndented=true}));
            if(args.Contains("--sample-only"))return 0;
            GC.Collect();GC.WaitForPendingFinalizers();process.Refresh();long managedBefore=GC.GetTotalMemory(true);int handlesBefore=process.HandleCount;
            var tray=typeof(Manager).GetField("_tray",Private)!.GetValue(manager)!;var handle=((System.Windows.Forms.NativeWindow)tray).Handle;
            void Click(int message)=>SendMessage(handle,0x8001,new IntPtr(1),new IntPtr(message));
            Click(0x202);Require(!manager.Dock.IsVisible,"Single click did not hide");Pump(650);Require(!manager.Dock.IsVisible,"Heartbeat undid hide");
            Click(0x202);Require(manager.Dock.IsVisible,"Single click did not restore");Click(0x202);Click(0x203);Click(0x202);Require(!manager.Dock.IsVisible,"Double click toggled twice");Click(0x202);
            var deployment=manager.Dock.GetType().GetMethod("SetEquipmentDeployment",Private)!;var watch=Stopwatch.StartNew();int cycles=0;
            while(watch.Elapsed.TotalSeconds<seconds) {
                int n=cycles%9;var slot=manager.State.Slots[n];manager.SetStatus(slot,cycles%3==0?AgentState.Ready:AgentState.Running,"手动标记","fixture");
                if(cycles%10==0)deployment.Invoke(manager.Dock,new object?[]{true,null});
                if(cycles%10==3)deployment.Invoke(manager.Dock,new object?[]{false,null});
                if(cycles%20==5) {Click(0x202);Pump(100);Click(0x202);}
                Pump(900);cycles++;
            }
            deployment.Invoke(manager.Dock,new object?[]{false,false});Pump(1500);GC.Collect();GC.WaitForPendingFinalizers();process.Refresh();long managedAfter=GC.GetTotalMemory(true);int handlesAfter=process.HandleCount;
            Require(managedAfter-managedBefore<16*1024*1024,"Managed heap grew by more than 16 MiB after warmup");Require(handlesAfter-handlesBefore<32,"Native handle count grew by 32 or more");
            foreach(var slot in manager.State.Slots)Require(slot.Connected && Native.Matches(slot.Window),"Fixture identity lost during soak");
            var ids=manager.State.Slots.Select(s=>s.Id).ToArray();manager.Save();manager.Dispose();manager.Dock.Close();manager=null;
            var saved=store.Load();Require(saved.Slots.Select(s=>s.Id).SequenceEqual(ids),"Saved identities changed");
            // Restart only the isolated manager against the same still-live windows.
            manager=new Manager(store,interactionTest:true);manager.TogglePause();Pump(250);Require(manager.State.Slots.All(s=>s.Connected),"Restart failed to reconnect live fixture windows");
            windows[4].Close();Pump(1100);Require(!manager.State.Slots[4].Occupied && manager.State.RecentTasks.Count>0,"Closed fixture left a zombie slot");
            var report=new{passed=true,assembly_sha256=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(Manager).Assembly.Location))),samples,soak_seconds=watch.Elapsed.TotalSeconds,cycles,managed_before=managedBefore,managed_after=managedAfter,handles_before=handlesBefore,handles_after=handlesAfter,tray_native_dispatch=true,hidden_survives_heartbeat=true,double_click_acts_once=true,restart_live_windows=true,closed_window_archived=true,fixture_only=true,packaged=false};
            File.WriteAllText(Path.Combine(output,"report.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine(JsonSerializer.Serialize(report));return 0;
        } catch(Exception e) {File.WriteAllText(Path.Combine(output,"failure.txt"),e.ToString());Console.Error.WriteLine(e);return 1;}
        finally {manager?.Dispose();manager?.Dock.Close();foreach(var w in windows)if(w.IsVisible)w.Close();app.Shutdown();}
    }
}
