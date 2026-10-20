using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CodeManager;

internal static class Program
{
    private static readonly BindingFlags Private=BindingFlags.Instance|BindingFlags.NonPublic;
    private static object Measure(string name,int count,Action action)
    {
        action();GC.Collect();GC.WaitForPendingFinalizers();long allocated=GC.GetTotalAllocatedBytes(true);var watch=Stopwatch.StartNew();
        for(int i=0;i<count;i++)action();watch.Stop();
        return new{name,iterations=count,total_ms=watch.Elapsed.TotalMilliseconds,mean_ms=watch.Elapsed.TotalMilliseconds/count,allocated_bytes=GC.GetTotalAllocatedBytes(true)-allocated};
    }
    [STAThread]
    private static int Main(string[] args)
    {
        string output=Path.GetFullPath(args[0]);Directory.CreateDirectory(output);var rows=new List<object>();var app=new Application();
        var window=new Window{Title="OmniVibe performance fixture",Width=320,Height=200,Left=-8000,Top=-8000,ShowActivated=false,ShowInTaskbar=false};
        try {
            window.Show();using var process=Process.GetCurrentProcess();var identity=new WindowIdentity{Handle=new WindowInteropHelper(window).Handle.ToInt64(),ProcessId=Environment.ProcessId,ProcessStartedUtcTicks=process.StartTime.ToUniversalTime().Ticks};
            rows.Add(Measure("Exact native window identity validation",1200,()=>{if(!Native.Matches(identity))throw new Exception("Identity check failed");}));
            using(var input=new InputService(Dispatcher.CurrentDispatcher)) {
                var p=new Preferences();int[] numbers={1,2,3,4};input.Configure(p,numbers,true);
                rows.Add(Measure("Unchanged shortcut configuration",1200,()=>input.Configure(p,numbers,true)));
                int checks=0;input.CanHandleMouse=()=>{checks++;return true;};
                var hook=typeof(InputService).GetMethod("MouseHook",Private)!;
                rows.Add(Measure("Ordinary mouse-move hook",3000,()=>hook.Invoke(input,new object[]{0,new IntPtr(0x200),IntPtr.Zero})));
                rows.Add(new{name="Ordinary mouse-move gesture evaluations",count=checks});
            }
            string fixture=Path.Combine(output,"sessions"),codex=Path.Combine(fixture,"codex","sessions"),claude=Path.Combine(fixture,"claude");
            string folder=Path.Combine(codex,DateTime.UtcNow.ToString("yyyy/MM/dd"));Directory.CreateDirectory(folder);var files=new List<(string Id,string File)>();
            string filler=JsonSerializer.Serialize(new{type="response_item",timestamp=DateTimeOffset.UtcNow,payload=new{type="message",text=new string('x',500)}})+"\n";
            for(int i=0;i<24;i++) {
                string id=Guid.NewGuid().ToString(),file=Path.Combine(folder,"fixture-"+i+".jsonl");
                string header=JsonSerializer.Serialize(new{type="session_meta",timestamp=DateTimeOffset.UtcNow,payload=new{id,cwd=fixture,title="performance-fixture-"+i}})+"\n";
                File.WriteAllText(file,header+string.Concat(Enumerable.Repeat(filler,280)));files.Add((id,file));
            }
            var source=new SessionStatusSource(codex,claude);
            rows.Add(Measure("Unchanged session metadata discovery",8,()=>{if(source.DiscoverAsync().GetAwaiter().GetResult().Count!=24)throw new Exception("Missing sessions");}));
            Type targetType=typeof(Manager).Assembly.GetType("CodeManager.SessionTarget",true)!;
            var targets=Array.CreateInstance(targetType,4);
            for(int i=0;i<4;i++)targets.SetValue(Activator.CreateInstance(targetType,new object[]{"task-"+i,1L+i,"performance-fixture-"+i,files[i].Id,files[i].File}),i);
            var poll=typeof(SessionStatusSource).GetMethod("PollAsync",Private)!;
            void Poll()=>((Task)poll.Invoke(source,new object[]{targets})!).GetAwaiter().GetResult();
            rows.Add(Measure("Unchanged four bound transcript polls",100,Poll));
            Type diagnostics=typeof(Manager).Assembly.GetType("CodeManager.WheelMotionDiagnostics",true)!;
            diagnostics.GetMethod("Write",BindingFlags.NonPublic|BindingFlags.Static)!.Invoke(null,new object[]{Path.Combine(output,"wheel.json")});
            Type wheelType=typeof(Manager).Assembly.GetType("CodeManager.DockWeaponWheel",true)!;
            var wheel=(FrameworkElement)Activator.CreateInstance(wheelType,true)!;
            var wheelWindow=new Window{Width=460,Height=450,Content=wheel,Left=-8000,Top=-8000,ShowActivated=false,ShowInTaskbar=false};
            try {
                var slots=Enumerable.Range(1,9).Select(n=>new Slot{Number=n,Window=new(),Connected=true,State=n==2?AgentState.Ready:AgentState.Running,Unread=n==2}).ToArray();EquipmentCatalog.EnsureDefaults(slots);
                wheelType.GetMethod("SetSlots",Private)!.Invoke(wheel,new object[]{slots});wheelType.GetProperty("MotionEnabled",Private)!.SetValue(wheel,false);
                wheelWindow.Show();wheelWindow.UpdateLayout();wheelType.GetMethod("Deploy",Private)!.Invoke(wheel,new object[]{true,false});
                foreach(var slot in slots)EquipmentCatalog.Image(slot);
                var bitmap=new RenderTargetBitmap(460,450,96,96,PixelFormats.Pbgra32);
                var flow=wheelType.GetProperty("Flow")!;
                for(int i=0;i<10;i++){flow.SetValue(wheel,i*.01);Dispatcher.CurrentDispatcher.Invoke(()=>{},DispatcherPriority.Render);bitmap.Render(wheel);}
                wheelType.GetProperty("MeasureDrawing",Private)!.SetValue(wheel,true);
                for(int i=0;i<120;i++){flow.SetValue(wheel,i*.007);Dispatcher.CurrentDispatcher.Invoke(()=>{},DispatcherPriority.Render);bitmap.Render(wheel);}
                var times=(List<double>)wheelType.GetProperty("DrawTimes",Private)!.GetValue(wheel)!;var bytes=(List<long>)wheelType.GetProperty("DrawAllocations",Private)!.GetValue(wheel)!;
                double[] sorted=times.OrderBy(x=>x).ToArray();rows.Add(new{name="Settled nine-slot status animation drawing",frames=times.Count,median_ms=sorted[sorted.Length/2],p95_ms=sorted[(int)(sorted.Length*.95)],mean_allocated_bytes=bytes.Average()});
            }finally{wheelWindow.Close();}
            File.WriteAllText(Path.Combine(output,"report.json"),JsonSerializer.Serialize(new{passed=true,results=rows,limits="Synthetic identical fixtures; not end-to-end foreground activation latency. Live process metrics are separate.",privateConversationRead=false},new JsonSerializerOptions{WriteIndented=true}));
            return 0;
        } catch(Exception e) {File.WriteAllText(Path.Combine(output,"report.json"),JsonSerializer.Serialize(new{passed=false,error=e.ToString()},new JsonSerializerOptions{WriteIndented=true}));return 1;}
        finally {window.Close();GameAudio.Stop();}
    }
}
