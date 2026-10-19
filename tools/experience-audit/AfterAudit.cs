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

internal static class AfterAudit
{
    private static readonly BindingFlags Private=BindingFlags.NonPublic|BindingFlags.Instance;
    private static readonly List<object> Results=new();
    private static readonly List<string> CustomFixtures=new();
    private static int Failures;
    private static T Field<T>(object value,string name)=>(T)value.GetType().GetField(name,Private)!.GetValue(value)!;
    private static void Set(object value,string name,object? field)=>value.GetType().GetField(name,Private)!.SetValue(value,field);
    private static object? Call(object value,string method,params object?[] args)=>value.GetType().GetMethod(method,Private)!.Invoke(value,args);
    private static void Require(bool passed,string message){if(!passed)throw new InvalidOperationException(message);}
    private static void Until(Func<bool> condition,string message,int milliseconds=1000)
    {var watch=Stopwatch.StartNew();while(!condition()&&watch.ElapsedMilliseconds<milliseconds)Thread.Sleep(2);Require(condition(),message);}
    private static void Test(string id,Func<object> action)
    {
        try{object evidence=action();Results.Add(new{id,passed=true,evidence});Console.WriteLine("PASS "+id+" "+JsonSerializer.Serialize(evidence));}
        catch(Exception error){Failures++;Results.Add(new{id,passed=false,error=error.ToString()});Console.WriteLine("FAIL "+id+" "+error);}
    }
    private sealed class WriteProbe:IDisposable
    {
        private readonly FileSystemWatcher _watcher;private int _count;public int Count=>Volatile.Read(ref _count);
        public WriteProbe(string directory){_watcher=new FileSystemWatcher(directory,"tasks.json.tmp-*"){NotifyFilter=NotifyFilters.FileName};_watcher.Created+=(_,_)=>Interlocked.Increment(ref _count);_watcher.EnableRaisingEvents=true;}
        public int Settle(){Thread.Sleep(70);return Count;}
        public void Dispose()=>_watcher.Dispose();
    }
    private static void Queue(AudioSettingsPanel panel,AudioCue cue,string source)
    {
        var cues=Field<ComboBox>(panel,"_cue");cues.SelectedItem=cues.Items.OfType<ComboBoxItem>().First(x=>x.Tag is AudioCue c&&c==cue);Call(panel,"QueueOverride",source);
    }
    private static object AudioFailure(bool readOnly,bool existingFirst)
    {
        string identity="experience-audit-"+Guid.NewGuid().ToString("N"),custom=GameAudio.OverrideDirectory(Skin.Arsenal,identity);CustomFixtures.Add(custom);Directory.CreateDirectory(custom);
        string original=GameAudio.GetPath(Skin.Arsenal,AudioCue.Switch),replacement=GameAudio.GetPath(Skin.Arsenal,AudioCue.Ready);
        string first=Path.Combine(custom,"switch.wav"),second=Path.Combine(custom,"capture.wav");
        if(existingFirst)File.Copy(original,first);File.Copy(original,second);byte[] secondBefore=File.ReadAllBytes(second);byte[]? firstBefore=existingFirst?File.ReadAllBytes(first):null;
        var panel=new AudioSettingsPanel(new Preferences{Skin=Skin.Arsenal,SoundEffects=false,Animate=false},()=>Skin.Arsenal);
        var identities=Field<ComboBox>(panel,"_identity");var item=new ComboBoxItem{Content="Isolated audit entity",Tag=identity};identities.Items.Add(item);identities.SelectedItem=item;
        Queue(panel,AudioCue.Switch,replacement);Queue(panel,AudioCue.Capture,replacement);
        bool success;string error;
        if(readOnly){File.SetAttributes(second,File.GetAttributes(second)|FileAttributes.ReadOnly);try{success=panel.TryCommit(new Preferences(),out error);}finally{File.SetAttributes(second,FileAttributes.Normal);}}
        else{using(var locked=new FileStream(second,FileMode.Open,FileAccess.ReadWrite,FileShare.None))success=panel.TryCommit(new Preferences(),out error);}
        Require(!success,"Injected override failure was accepted");
        bool firstPreserved=existingFirst?File.Exists(first)&&File.ReadAllBytes(first).SequenceEqual(firstBefore!):!File.Exists(first);
        Require(firstPreserved,"Failed batch changed first override");Require(File.ReadAllBytes(second).SequenceEqual(secondBefore),"Failed batch changed second override");
        string[] drafts=Directory.GetFiles(custom,".omnivibe-draft-*");Require(drafts.Length==0,"Rollback succeeded but staging files were abandoned: "+string.Join(",",drafts.Select(Path.GetFileName)));
        return new{readOnly,existingFirst,success,firstPreserved,secondPreserved=true,stagedFilesRemaining=drafts.Length,error,identity};
    }
    [STAThread]private static int Main()
    {
        string output=Path.GetFullPath("artifacts/experience-audit");Directory.CreateDirectory(output);string run=Path.Combine(output,"after-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(run);
        var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};var xaml=XDocument.Load("src/CodeManager/App.xaml");XNamespace ns="http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        app.Resources=(ResourceDictionary)XamlReader.Parse(new XElement(ns+"ResourceDictionary",new XAttribute("xmlns",ns.NamespaceName),new XAttribute(XNamespace.Xmlns+"x","http://schemas.microsoft.com/winfx/2006/xaml"),xaml.Root!.Element(ns+"Application.Resources")!.Elements()).ToString());WuxiaTheme.Apply(Skin.Arsenal,false);
        // Never construct the real Manager: no hooks/timers/tray or shown windows.
        var manager=(Manager)RuntimeHelpers.GetUninitializedObject(typeof(Manager));var state=new AppState();state.Preferences.Animate=false;state.Preferences.SoundEffects=false;
        var store=new StateStore(Path.Combine(run,"state"));var dock=new DockWindow();Set(manager,"<State>k__BackingField",state);Set(manager,"<Store>k__BackingField",store);Set(manager,"<Dock>k__BackingField",dock);dock.Manager=manager;
        Set(manager,"_captureFlashes",new Dictionary<int,DateTime>());Set(manager,"_wheel",new WheelSelection());Set(manager,"_scale",1d);Set(manager,"<WorkArea>k__BackingField",new Native.Rect(0,0,1280,900));
        dock.SetSlots(state.Slots);var slot=state.Slots[0];slot.Window=new WindowIdentity{Handle=-9,ProcessId=-9,Title="isolated fixture",ProcessName="audit"};slot.Name="Task fixture";DateTimeOffset at=DateTimeOffset.UtcNow.AddSeconds(-30);
        void Events(DateTimeOffset start,int count=24){for(int i=0;i<count;i++)store.Send(new StatusEvent{TaskId=slot.Id,State=i%2==0?AgentState.Running:AgentState.Ready,Message="Event "+i,At=start.AddMilliseconds(i*10)});}
        try
        {
            Test("duplicate-state-unread-idempotent",()=>{
                manager.SetStatus(slot,AgentState.Ready,"audit","same reply",at);manager.MarkRead(slot);manager.SetStatus(slot,AgentState.Ready,"audit","same reply",at.AddMilliseconds(1));Require(!slot.Unread,"Duplicate re-armed unread");Require(slot.UpdatedAt==at.AddMilliseconds(1),"Lost monotonic timestamp");
                manager.SetStatus(slot,AgentState.Ready,"audit","new content",at.AddMilliseconds(2));Require(slot.Unread,"Changed content did not re-arm unread");return new{duplicateRemainsRead=true,changedContentBecomesUnread=true};});
            Test("consume-real-24-event-files-one-persist",()=>{
                foreach(var s in state.Slots)s.Notes=new string('x',1500);for(int i=0;i<30;i++)state.RecentTasks.Add(new(){Task=new Slot{Number=1,Name="Recent fixture",Window=new WindowIdentity{Title="Closed"},Notes=new string('x',1500)}});
                store.Save(state);Events(at.AddSeconds(1));Require(Directory.GetFiles(store.EventsDirectory,"*.json").Length==24,"Fixture did not create 24 events");using var writes=new WriteProbe(store.Root);var watch=Stopwatch.StartNew();Call(manager,"ProcessPendingEvents");watch.Stop();int count=writes.Settle();
                Require(count==1,"Expected one atomic write, observed "+count);Require(Directory.GetFiles(store.EventsDirectory,"*.json").Length==0,"Committed events not removed");var saved=store.Load().Slots.Single(x=>x.Id==slot.Id);Require(saved.Message=="Event 23"&&saved.State==AgentState.Ready,"Final ordered event lost");Require(!Field<bool>(manager,"_statusBatchDirty"),"Dirty flag after success");return new{events=24,atomicWrites=count,elapsedMs=watch.Elapsed.TotalMilliseconds,stateBytes=new FileInfo(store.StateFile).Length,finalMessage=saved.Message};});
            Test("consume-save-failure-retains-files-and-retries",()=>{
                DateTimeOffset start=at.AddSeconds(2);Events(start);byte[] before=File.ReadAllBytes(store.StateFile);using(var locked=new FileStream(store.StateFile,FileMode.Open,FileAccess.Read,FileShare.Read))Call(manager,"ProcessPendingEvents");
                Require(Directory.GetFiles(store.EventsDirectory,"*.json").Length==24,"Save failure lost source events");Require(Field<bool>(manager,"_statusBatchDirty"),"Save failure discarded dirty flag");Require(File.ReadAllBytes(store.StateFile).SequenceEqual(before),"Failed save changed persistent state");Require(slot.UpdatedAt==start.AddMilliseconds(230),"In-memory final state lost");
                using var writes=new WriteProbe(store.Root);Call(manager,"ProcessPendingEvents");int count=writes.Settle();Require(count==1,"Retry did not save once");Require(!Field<bool>(manager,"_statusBatchDirty"),"Retry dirty flag");Require(Directory.GetFiles(store.EventsDirectory,"*.json").Length==0,"Successful retry left events");Require(store.Load().Slots.Single(x=>x.Id==slot.Id).UpdatedAt==start.AddMilliseconds(230),"Retry lost state due timestamp dedup");return new{retainedOnFailure=24,retryAtomicWrites=count,retryPersistedFinalTimestamp=true};});
            Test("consume-replayed-event-remains-read-without-write",()=>{
                manager.MarkRead(slot);store.Send(new StatusEvent{TaskId=slot.Id,State=slot.State,Message=slot.Message,At=slot.UpdatedAt!.Value});using var writes=new WriteProbe(store.Root);Call(manager,"ProcessPendingEvents");int count=writes.Settle();Require(count==0,"Replay unnecessarily saved");Require(!slot.Unread,"Replay re-armed unread");Require(Directory.GetFiles(store.EventsDirectory,"*.json").Length==0,"Replay not discarded");return new{atomicWrites=count,remainsRead=true};});
            Test("consume-eight-warm-bursts-write-budget",()=>{
                var times=new List<double>();using var writes=new WriteProbe(store.Root);
                for(int i=0;i<8;i++){Events(at.AddSeconds(3+i));var watch=Stopwatch.StartNew();Call(manager,"ProcessPendingEvents");watch.Stop();times.Add(watch.Elapsed.TotalMilliseconds);Require(Directory.GetFiles(store.EventsDirectory,"*.json").Length==0,"Burst left events");}
                int count=writes.Settle();Require(count==8,"Eight batches did not produce eight writes: "+count);times.Sort();return new{events=192,batches=8,atomicWrites=count,medianMs=times[4],maximumMs=times[^1],includesJsonReadAndEventDeletion=true};});
            Test("override-second-file-exclusive-lock",()=>AudioFailure(false,false));
            Test("override-second-file-readonly-new-first",()=>AudioFailure(true,false));
            Test("override-second-file-readonly-preserves-existing-first",()=>AudioFailure(true,true));
            Test("capture-dialog-audio-enabled-notifications-suppressed",()=>{
                state.Preferences.SoundEffects=true;state.Preferences.ImmersiveAudio=true;state.Preferences.SoundVolume=.001;GameAudio.Configure(true,.001,true);Set(manager,"_dialog",true);Call(manager,"PlayCue",AudioCue.Capture,slot);Until(()=>GameAudio.Diagnostics.ActiveVoices>0&&GameAudio.Diagnostics.OutputOpen,"Dialog capture silent");GameAudio.Stop();Until(()=>GameAudio.Diagnostics.ActiveVoices==0&&!GameAudio.Diagnostics.OutputOpen&&GameAudio.Diagnostics.PendingRequests==0,"Capture did not stop");
                Call(manager,"PlayCue",AudioCue.Error,slot);Thread.Sleep(30);var after=GameAudio.Diagnostics;Require(after.ActiveVoices==0&&after.PendingRequests==0,"Dialog emitted background notification: "+after);Set(manager,"_dialog",false);state.Preferences.SoundEffects=false;return new{captureAudible=true,dialogNotificationSuppressed=true};});
            Test("move-reorder-stable-task-identity-and-routing",()=>{
                string old=slot.Id;var target=state.Slots[4];manager.MoveSlot(slot,target);manager.ReorderSlot(target,state.Slots[1]);bool routed=(bool)Call(manager,"ApplyStatusEvent",target,new StatusEvent{TaskId=old,State=AgentState.Waiting,At=DateTimeOffset.UtcNow})!;Require(target.Id==old&&routed,"Task ID/routing lost");Require(state.Slots.Select(x=>x.Id).Distinct().Count()==9,"Duplicate task IDs");return new{preserved=true,eventRouted=routed,number=target.Number};});
            File.WriteAllText(Path.Combine(output,"report-after.json"),JsonSerializer.Serialize(new{passed=Failures==0,generatedAt=DateTimeOffset.UtcNow,assembly=typeof(Manager).Assembly.Location,productionManagerConstructed=false,foregroundOrTerminalTouched=false,isolatedStateRoot=run,suites=Results.Count,failures=Failures,results=Results},new JsonSerializerOptions{WriteIndented=true}));return Failures==0?0:1;
        }
        finally
        {
            Set(manager,"_disposed",true);dock.Manager=null;dock.Close();GameAudio.Shutdown();foreach(string directory in CustomFixtures)if(Directory.Exists(directory)){foreach(string file in Directory.GetFiles(directory)){File.SetAttributes(file,FileAttributes.Normal);File.Delete(file);}Directory.Delete(directory);}
        }
    }
}
