using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using CodeManager;
using Forms=System.Windows.Forms;

internal static class Program
{
    private static void Require(bool condition,string reason) { if(!condition)throw new InvalidOperationException(reason); }
    private static void Until(Func<bool> condition,string reason,int milliseconds=2200) { var watch=Stopwatch.StartNew();while(!condition() && watch.ElapsedMilliseconds<milliseconds){Forms.Application.DoEvents();Thread.Sleep(2);}Require(condition(),reason); }
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr handle,uint message,IntPtr wParam,IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [STAThread]
    private static int Main(string[] args)
    {
        string output=Path.GetFullPath(args[0]);Directory.CreateDirectory(output);var results=new List<object>();
        try {
            foreach(var skin in Enum.GetValues<Skin>()) {
                GameAudio.Configure(true,.001);
                GameAudio.PlayCompletion(skin,true,.001);
                Until(()=>string.Equals(GameAudio.LastSourcePath,CompletionAudio.GetPath(skin),StringComparison.OrdinalIgnoreCase) && GameAudio.Diagnostics.OutputOpen,"Native completion playback absent: "+skin);
                Require(GameAudio.LastError==null,"Audio error: "+GameAudio.LastError);
                int frames=GameAudio.LastSourceFrames;Require(frames is >=13230 and <=26460,"Unexpected completion length");
                Until(()=>!GameAudio.Diagnostics.OutputOpen && GameAudio.Diagnostics.ActiveVoices==0,"Idle completion kept the endpoint open");
                results.Add(new{theme=skin.ToString(),passed=true,frames,realNativePlayback=true,endpointReleased=true});
            }
            GameAudio.Configure(false,.001);GameAudio.PlayCompletion(Skin.InkJade,true,.001);Thread.Sleep(30);
            Require(GameAudio.Diagnostics.PendingRequests==0 && !GameAudio.Diagnostics.OutputOpen,"Completion bypassed master mute");
            GameAudio.PreviewCompletion(Skin.InkJade,.001);Until(()=>GameAudio.Diagnostics.OutputOpen,"Explicit completion audition did not bypass mute");
            GameAudio.Stop();Until(()=>!GameAudio.Diagnostics.OutputOpen,"Audition failed to stop",120);
            var assembly=typeof(Manager).Assembly;var type=assembly.GetType("CodeManager.TaskTrayIcon",true)!;
            // Exercise the production manager dispatch too: OS popup and switch
            // sound disabled, completion enabled, explicit switch theme different.
            var manager=(Manager)System.Runtime.CompilerServices.RuntimeHelpers.GetUninitializedObject(typeof(Manager));
            var state=new AppState();state.Preferences.Skin=Skin.Hextech;state.Preferences.SoundTheme=Skin.Relic;
            state.Preferences.SoundEffects=false;state.Preferences.SystemNotifications=false;state.Preferences.SoundNotifications=true;state.Preferences.SoundVolume=.001;
            foreach(var s in state.Slots.Take(2)){s.Window=new(){Handle=11+s.Number};s.Connected=true;s.Unread=true;s.State=AgentState.Ready;s.UpdatedAt=DateTimeOffset.UtcNow;}
            var brokerType=assembly.GetType("CodeManager.TaskNotifications",true)!;var broker=Activator.CreateInstance(brokerType,true)!;
            var privateInstance=BindingFlags.Instance|BindingFlags.NonPublic;
            typeof(Manager).GetField("<State>k__BackingField",privateInstance)!.SetValue(manager,state);
            typeof(Manager).GetField("_notifications",privateInstance)!.SetValue(manager,broker);
            foreach(var s in state.Slots.Take(2))brokerType.GetMethod("Queue",privateInstance)!.Invoke(broker,new object[]{s,true,DateTimeOffset.UtcNow.AddSeconds(-2),99L});
            typeof(Manager).GetMethod("ApplyAudioPreferences",privateInstance)!.Invoke(manager,null);
            typeof(Manager).GetMethod("FlushNotifications",privateInstance)!.Invoke(manager,null);
            Until(()=>string.Equals(GameAudio.LastSourcePath,CompletionAudio.GetPath(Skin.Hextech),StringComparison.OrdinalIgnoreCase) && GameAudio.Diagnostics.OutputOpen,"Manager failed independent sound-only dispatch or followed switch override");
            GameAudio.Stop();Until(()=>!GameAudio.Diagnostics.OutputOpen,"Manager completion did not stop",120);
            using var tray=(IDisposable)Activator.CreateInstance(type,true)!;
            using var icon=(Icon)assembly.GetType("CodeManager.ProductIcon",true)!.GetMethod("CreateTrayIcon",BindingFlags.Static|BindingFlags.Public|BindingFlags.NonPublic)!.Invoke(null,null)!;
            var flags=BindingFlags.Instance|BindingFlags.NonPublic|BindingFlags.Public;
            void Set(string name,object value)=>type.GetProperty(name,flags)!.SetValue(tray,value);
            void Subscribe(string name,Delegate action)=>type.GetEvent(name,flags)!.GetAddMethod(true)!.Invoke(tray,new object[]{action});
            bool shown=false;int clicked=0,leftClicked=0;
            Subscribe("BalloonTipShown",new EventHandler((_,_)=>shown=true));Subscribe("BalloonTipClicked",new EventHandler((_,_)=>clicked++));
            Subscribe("MouseClick",new Forms.MouseEventHandler((_,e)=>{if(e.Button==Forms.MouseButtons.Left)leftClicked++;}));
            Set("Icon",icon);Set("Text","OmniVibe");Set("Visible",true);
            IntPtr handle=((Forms.NativeWindow)tray).Handle,foreground=GetForegroundWindow();
            bool accepted=(bool)type.GetMethod("ShowBalloonTip",flags)!.Invoke(tray,new object[]{6000,"OmniVibe · 完成提醒已就绪","后台任务完成后将轻响一次。可在设置 → 常规 → 任务提醒中试听或关闭。",Forms.ToolTipIcon.Info,true})!;
            Require(accepted,"Shell rejected native silent balloon");Until(()=>shown,"Shell never acknowledged silent balloon",5000);
            Require(GetForegroundWindow()==foreground,"Notification stole foreground focus");
            SendMessage(handle,0x8001,IntPtr.Zero,new IntPtr(0x405));SendMessage(handle,0x8001,IntPtr.Zero,new IntPtr(0x202));
            Require(clicked==1 && leftClicked==1,"Native notification/tray click callback lost");
            tray.Dispose();Require(((Forms.NativeWindow)tray).Handle==IntPtr.Zero,"Disposed tray retained its native window");
            File.WriteAllText(Path.Combine(output,"report.json"),JsonSerializer.Serialize(new{passed=true,themes=results,nativeSilentNotificationAccepted=accepted,nativeShellShown=shown,nativeClickCallback=true,trayClickCallback=true,noFocusSteal=true,disposedWindowReleased=true,masterMuteHonored=true,auditionWorksWhileMuted=true,managerSoundOnlyDispatch=true,completionFollowsVisualSkin=true,packaged=false},new JsonSerializerOptions{WriteIndented=true}));
            return 0;
        } catch(Exception error) {File.WriteAllText(Path.Combine(output,"report.json"),JsonSerializer.Serialize(new{passed=false,error=error.ToString()},new JsonSerializerOptions{WriteIndented=true}));return 1;}
        finally {GameAudio.Stop();GameAudio.Shutdown();}
    }
}
