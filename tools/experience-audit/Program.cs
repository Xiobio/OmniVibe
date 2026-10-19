using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Xml.Linq;
using CodeManager;

internal static class Program
{
    private static readonly BindingFlags Private = BindingFlags.NonPublic | BindingFlags.Instance;
    private static readonly List<object> Results = new();
    private static T Field<T>(object value, string name) => (T)value.GetType().GetField(name, Private)!.GetValue(value)!;
    private static void Set(object value, string name, object? field) => value.GetType().GetField(name, Private)!.SetValue(value, field);
    private static object? Call(object value, string method, params object?[] args) => value.GetType().GetMethod(method, Private)!.Invoke(value, args);
    private static void Record(string id, string kind, object evidence) { Results.Add(new { id, kind, evidence }); Console.WriteLine(id + " " + JsonSerializer.Serialize(evidence)); }
    [STAThread] private static int Main()
    {
        string output = Path.GetFullPath("artifacts/experience-audit"); Directory.CreateDirectory(output);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var xaml = XDocument.Load("src/CodeManager/App.xaml"); XNamespace ns = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        app.Resources = (ResourceDictionary)XamlReader.Parse(new XElement(ns + "ResourceDictionary", new XAttribute("xmlns", ns.NamespaceName), new XAttribute(XNamespace.Xmlns + "x", "http://schemas.microsoft.com/winfx/2006/xaml"), xaml.Root!.Element(ns + "Application.Resources")!.Elements()).ToString());
        WuxiaTheme.Apply(Skin.Arsenal, false);
        // No Manager constructor: no hooks, timers, tray, terminal actions or shown
        // windows. Invoke only production methods whose dependencies are supplied.
        var manager = (Manager)RuntimeHelpers.GetUninitializedObject(typeof(Manager));
        var state = new AppState(); state.Preferences.Animate = false; state.Preferences.SoundEffects = false;
        var store = new StateStore(Path.Combine(output, "isolated-state"));
        var dock = new DockWindow(); Set(manager, "<State>k__BackingField", state); Set(manager, "<Store>k__BackingField", store); Set(manager, "<Dock>k__BackingField", dock); dock.Manager = manager;
        Set(manager, "_captureFlashes", new Dictionary<int, DateTime>()); Set(manager, "_wheel", new WheelSelection()); Set(manager, "_scale", 1d); Set(manager, "<WorkArea>k__BackingField", new Native.Rect(0,0,1280,900));
        dock.SetSlots(state.Slots); var slot = state.Slots[0]; slot.Window = new WindowIdentity { Handle = -9, ProcessId = -9, Title = "isolated fixture", ProcessName = "audit" }; slot.Name = "Task fixture";
        string identity = "experience-audit-" + Guid.NewGuid().ToString("N"); string? custom = null;
        try
        {
            var at = DateTimeOffset.UtcNow;
            manager.SetStatus(slot, AgentState.Ready, "audit", "same reply", at); manager.MarkRead(slot);
            bool readBefore = !slot.Unread; manager.SetStatus(slot, AgentState.Ready, "audit", "same reply", at.AddMilliseconds(1));
            Record("duplicate-state-unread", "reproduced", new { readBefore, sameStateSameMessageNewTimestampMarksUnread = slot.Unread, stateTransition = false });

            var timings = new List<double>();
            foreach (var s in state.Slots) s.Notes = new string('x', 1500);
            for (int i=0;i<30;i++) state.RecentTasks.Add(new() { Task = new Slot { Number=1,Name="Recent fixture",Window=new WindowIdentity {Title="Closed"},Notes=new string('x',1500) } });
            store.Save(state);
            for (int batch=0;batch<8;batch++)
            {
                var timer=Stopwatch.StartNew();
                for(int i=0;i<24;i++) manager.SetStatus(slot, i%2==0 ? AgentState.Running : AgentState.Ready,"audit","event fixture",at.AddSeconds(1+batch*24+i));
                timer.Stop();timings.Add(timer.Elapsed.TotalMilliseconds);
            }
            timings.Sort();Record("synchronous-event-batch", "measured",new { stateBytes=new FileInfo(store.StateFile).Length, batchEvents=24, batches=timings.Count,medianMs=timings[timings.Count/2],maximumMs=timings[^1],writesPerStatus=1 });

            var panel = new AudioSettingsPanel(new Preferences { Skin=Skin.Arsenal,SoundEffects=false,Animate=false },()=>Skin.Arsenal);
            var identities=Field<ComboBox>(panel,"_identity");var targetItem=new ComboBoxItem {Content="Isolated audit entity",Tag=identity};identities.Items.Add(targetItem);identities.SelectedItem=targetItem;
            var cues=Field<ComboBox>(panel,"_cue");
            string source=GameAudio.GetPath(Skin.Arsenal,AudioCue.Switch);
            cues.SelectedItem=cues.Items.OfType<ComboBoxItem>().First(x=>x.Tag is AudioCue c&&c==AudioCue.Switch);Call(panel,"QueueOverride",source);
            cues.SelectedItem=cues.Items.OfType<ComboBoxItem>().First(x=>x.Tag is AudioCue c&&c==AudioCue.Capture);Call(panel,"QueueOverride",source);
            custom=GameAudio.OverrideDirectory(Skin.Arsenal,identity);Directory.CreateDirectory(custom);string second=Path.Combine(custom,"capture.wav");File.Copy(source,second,true);
            bool success;string error;
            using(var locked=new FileStream(second,FileMode.Open,FileAccess.ReadWrite,FileShare.None))success=panel.TryCommit(new Preferences(),out error);
            Record("override-partial-commit", "reproduced",new { success,firstOverrideWasSavedDespiteFailedCommit=File.Exists(Path.Combine(custom,"switch.wav")),error,isolatedIdentity=identity });

            state.Preferences.SoundEffects=true;state.Preferences.ImmersiveAudio=true;state.Preferences.SoundVolume=.001;GameAudio.Configure(true,.001,true);
            Set(manager,"_dialog",true);Call(manager,"PlayCue",AudioCue.Capture,slot);Thread.Sleep(35);bool dialogSound=GameAudio.Diagnostics.ActiveVoices>0||GameAudio.Diagnostics.PendingRequests>0;
            Set(manager,"_dialog",false);Call(manager,"PlayCue",AudioCue.Capture,slot);Thread.Sleep(35);bool directSound=GameAudio.Diagnostics.ActiveVoices>0||GameAudio.Diagnostics.PendingRequests>0;
            Record("capture-dialog-audio", "reproduced",new { dialogSound,directSound,reason="PickWindow calls Bind before EndDialog; PlayCue rejects _dialog" });GameAudio.Stop();state.Preferences.SoundEffects=false;

            string oldId=slot.Id;var target=state.Slots[4];manager.MoveSlot(slot,target);manager.ReorderSlot(target,state.Slots[1]);
            var routed=(bool)Call(manager,"ApplyStatusEvent",target,new StatusEvent {TaskId=oldId,State=AgentState.Waiting,At=at.AddHours(1)})!;
            Record("move-reorder-identity", "passed",new { preserved=target.Id==oldId,eventRouted=routed,number=target.Number,allNineIdsUnique=state.Slots.Select(x=>x.Id).Distinct().Count()==9 });
            File.WriteAllText(Path.Combine(output,"report.json"),JsonSerializer.Serialize(new { generatedAt=DateTimeOffset.UtcNow,assembly=typeof(Manager).Assembly.Location,productionManagerConstructed=false,foregroundOrTerminalTouched=false,results=Results },new JsonSerializerOptions {WriteIndented=true}));return 0;
        }
        catch(Exception e){Console.Error.WriteLine(e);return 1;}
        finally
        {
            Set(manager,"_disposed",true);dock.Manager=null;dock.Close();GameAudio.Shutdown();
            if(custom!=null&&Directory.Exists(custom)) {foreach(string file in Directory.GetFiles(custom))File.Delete(file);Directory.Delete(custom);}
        }
    }
}
