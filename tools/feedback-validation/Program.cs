using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Media;
using System.Reflection;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CodeManager;
using Forms = System.Windows.Forms;
using Drawing = System.Drawing;

internal static class Program
{
    [STAThread] private static int Main(string[] args)
    {
        string output = Path.GetFullPath(args.Length > 0 ? args[0] : "artifacts/skin-feedback-validation"); Directory.CreateDirectory(output);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var sounds = new List<object>(); var hashes = new HashSet<string>(); var results = new List<object>();
        foreach (var skin in SkinCatalog.All.Where(s => (int)s.Id >= (int)Skin.Hextech))
        {
            foreach (bool capture in new[] { false, true })
            {
                byte[] wave = InkEffects.CreateSound(skin.Id, capture);
                using var stream = new MemoryStream(wave); using var player = new SoundPlayer(stream); player.Load();
                int samples = (wave.Length - 44) / 2; double peak = 0, square = 0, sum = 0;
                for(int i=0;i<samples;i++) { double value = BitConverter.ToInt16(wave,44+i*2)/32768d; peak=Math.Max(peak,Math.Abs(value)); square+=value*value; sum+=value; }
                double rms = Math.Sqrt(square/samples); string hash = Convert.ToHexString(SHA256.HashData(wave));
                Require(hashes.Add(hash),"Duplicate sound"); Require(peak < .15 && rms > .001 && Math.Abs(sum/samples)<.004,"Invalid audio levels");
                Require(BitConverter.ToInt16(wave,44)==0 && Math.Abs(BitConverter.ToInt16(wave,wave.Length-2))<=5,"Unsmooth endpoints");
                string file=skin.Slug+(capture?"-capture":"-switch")+".wav"; File.WriteAllBytes(Path.Combine(output,file),wave);
                sounds.Add(new { skin=skin.Slug,capture,file,sampleRate=22050,duration=samples/22050d,peak,rms,dcOffset=sum/samples,sha256=hash,decodedBySoundPlayer=true });
            }
        }
        var fixture = new Window { Width=220,Height=160,Left=70,Top=70,ShowActivated=false,ShowInTaskbar=false,WindowStyle=WindowStyle.None,Opacity=.01,Content=new Border { Width=140,Height=100,Background=Brushes.Black } };
        fixture.SourceInitialized+=(_,_)=>Native.Decorate(fixture);
        IntPtr before = Native.GetForegroundWindow(); fixture.Show(); Pump(40);
        int baseline = app.Windows.Count; int maximum = 0; var sw = Stopwatch.StartNew();
        foreach (var skin in SkinCatalog.All.Where(s => (int)s.Id >= (int)Skin.Hextech))
        {
            int nativeBaseline = VisibleOwnWindowCount();
            WuxiaTheme.Apply(skin.Id); SkinCatalog.DecorationsEnabled=true;
            InkEffects.Sweep(new Native.Rect(70,70,600,430),1,true); InkEffects.Ripple((FrameworkElement)fixture.Content);
            maximum=Math.Max(maximum,InkEffects.ActiveVisualCount);
            Require(InkEffects.ActiveVisualCount<=3,"Unbounded effects");
            var nativeHandles = new List<IntPtr>();
            foreach(Window overlay in app.Windows.OfType<Window>().Where(w=>w!=fixture))
            {
                IntPtr handle=new WindowInteropHelper(overlay).Handle; nativeHandles.Add(handle);
                long style=GetWindowLongPtr(handle,-20).ToInt64();
                Require((style & 0x08000020)==0x08000020,"Overlay is not NOACTIVATE/click-through");
            }
            Pump(370); Require(InkEffects.ActiveVisualCount==0,"Effect lease leaked"); Require(app.Windows.Count==baseline,"Effect native window leaked");
            Require(VisibleOwnWindowCount()==nativeBaseline,"Native HWND leaked after expiry");
            Require(nativeHandles.All(h=>!Native.IsWindow(h)),"Closed effect still owns native HWND");
            Require(Native.GetForegroundWindow()==before,"Effect stole focus");
            RenderMenu(skin,output);
            RenderGlyph(skin,output);
            results.Add(new { skin=skin.Slug,afterExpiryActive=InkEffects.ActiveVisualCount,windowsReturnedToBaseline=true,nativeVisibleHwndReturnedToBaseline=true,allEffectHwndDestroyed=true,noActivateAndClickThroughStylesVerified=true,foregroundUnchanged=true });
        }
        var burstHandles=new HashSet<IntPtr>();
        for(int i=0;i<30;i++) { InkEffects.Sweep(new Native.Rect(70,70,600,430),1,true); InkEffects.Ripple((FrameworkElement)fixture.Content); Require(InkEffects.ActiveVisualCount<=3,"Burst exceeded cap"); foreach(Window overlay in app.Windows.OfType<Window>().Where(w=>w!=fixture))burstHandles.Add(new WindowInteropHelper(overlay).Handle); }
        InkEffects.CancelVisuals(); Require(InkEffects.ActiveVisualCount==0 && app.Windows.Count==baseline,"Cancel did not release");
        Require(burstHandles.All(h=>!Native.IsWindow(h)),"Burst cancellation leaked a native HWND");
        SkinCatalog.DecorationsEnabled=false; InkEffects.Sweep(new Native.Rect(70,70,600,430),1,true); InkEffects.Ripple((FrameworkElement)fixture.Content); Require(InkEffects.ActiveVisualCount==0,"Decorations-off created windows");
        SkinCatalog.DecorationsEnabled=true; InkEffects.Sweep(new Native.Rect(70,70,600,430),1,false); Require(InkEffects.ActiveVisualCount==0,"Animation-off created windows");
        InkEffects.Sweep(new Native.Rect(70,70,600,430),double.NaN,true); InkEffects.Ripple(new Border()); Require(InkEffects.ActiveVisualCount==0,"Invalid target created windows");
        var show = typeof(InkEffects).GetMethod("ShowTransient",BindingFlags.NonPublic|BindingFlags.Static)!;
        var failed = new Window { ShowActivated=false,ShowInTaskbar=false,Width=60,Height=60,Left=-5000,Top=-5000 };
        show.Invoke(null,new object[]{failed,TimeSpan.FromMilliseconds(10),(Action)(()=>throw new InvalidOperationException("Probe animation failure"))});
        Require(InkEffects.ActiveVisualCount==0 && app.Windows.Count==baseline,"Animation error leaked window");
        InkEffects.Sound(false); fixture.Close(); app.Shutdown();
        var report = new { sounds, visualSkins=results, uniqueOriginalSounds=hashes.Count, maximumConcurrentVisuals=maximum, burstActions=60, burstCap=3, cancelReleasesAll=true, decorationOffCreatesNoWindows=true, animationOffCreatesNoWindows=true, invalidTargetIgnored=true, animationExceptionReleasesWindow=true, soundOffDidNotPlay=true, actualAudioPlaybackPerformed=false, elapsedMilliseconds=sw.ElapsedMilliseconds };
        File.WriteAllText(Path.Combine(output,"report.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions { WriteIndented=true }));
        using(var sheet=new Drawing.Bitmap(880,440))
        using(var graphics=Drawing.Graphics.FromImage(sheet))
        using(var font=new Drawing.Font("Microsoft YaHei UI",10))
        {
            graphics.Clear(Drawing.Color.FromArgb(20,24,30));int index=0;
            foreach(var skin in SkinCatalog.All.Where(s => (int)s.Id >= (int)Skin.Hextech))
            {
                int x=index%5*176,y=index/5*220;
                using var tile=Drawing.Image.FromFile(Path.Combine(output,skin.Slug+"-glyph.png"));graphics.DrawImage(tile,x,y,176,176);
                graphics.DrawString(skin.Name,font,Drawing.Brushes.White,x+12,y+184);index++;
            }
            sheet.Save(Path.Combine(output,"feedback-glyphs-contact.png"));
        }
        Console.WriteLine(JsonSerializer.Serialize(new { passed=true,sounds=hashes.Count,visualSkins=results.Count,report=Path.Combine(output,"report.json") })); return 0;
    }
    private static void Require(bool condition,string message) { if(!condition) throw new Exception(message); }
    private delegate bool WindowCallback(IntPtr window,IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback,IntPtr parameter);
    [DllImport("user32.dll")] private static extern IntPtr GetWindowLongPtr(IntPtr window,int index);
    private static int VisibleOwnWindowCount()
    {
        int count=0;uint process=(uint)Environment.ProcessId;
        EnumWindows((window,_)=>{Native.GetWindowThreadProcessId(window,out uint owner);if(owner==process && Native.IsWindowVisible(window))count++;return true;},IntPtr.Zero);return count;
    }
    private static void Pump(int ms)
    {
        var frame=new DispatcherFrame(); var timer=new DispatcherTimer { Interval=TimeSpan.FromMilliseconds(ms) };
        timer.Tick+=(_,_)=>{timer.Stop();frame.Continue=false;};timer.Start();Dispatcher.PushFrame(frame);
    }
    private static void RenderMenu(SkinDefinition skin,string output)
    {
        var renderer=(Forms.ToolStripRenderer)Activator.CreateInstance(typeof(SkinCatalog).Assembly.GetType("CodeManager.TrayMenuRenderer")!,true)!;
        using var menu=new Forms.ContextMenuStrip { Renderer=renderer,BackColor=Drawing.ColorTranslator.FromHtml(skin.Background),ForeColor=Drawing.ColorTranslator.FromHtml(skin.Text),Font=new Drawing.Font("Microsoft YaHei UI",10),ShowCheckMargin=true };
        menu.Items.Add(new Forms.ToolStripMenuItem("任务总览    Tab") { Checked=true });
        menu.Items.Add(new Forms.ToolStripMenuItem("全部排列    Alt + `"));
        var child=new Forms.ToolStripMenuItem("选择皮肤");child.DropDownItems.Add("海克斯枢纽");menu.Items.Add(child);
        menu.Items.Add(new Forms.ToolStripSeparator());menu.Items.Add(new Forms.ToolStripMenuItem("不可用的操作") { Enabled=false });
        menu.Size=menu.GetPreferredSize(Drawing.Size.Empty);menu.CreateControl();
        using var bitmap=new Drawing.Bitmap(menu.Width,menu.Height);menu.DrawToBitmap(bitmap,new Drawing.Rectangle(Drawing.Point.Empty,menu.Size));bitmap.Save(Path.Combine(output,skin.Slug+"-tray.png"));
    }
    private static void RenderGlyph(SkinDefinition skin,string output)
    {
        var type=typeof(InkEffects).GetNestedType("FeedbackGlyph",BindingFlags.NonPublic)!;
        var glyph=(FrameworkElement)Activator.CreateInstance(type,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,new object[]{skin},null)!;
        glyph.Width=112;glyph.Height=112;glyph.HorizontalAlignment=HorizontalAlignment.Center;glyph.VerticalAlignment=VerticalAlignment.Center;
        var root=new Grid { Width=176,Height=176,Background=WuxiaTheme.Brush(skin.Background) };root.Children.Add(glyph);
        root.Measure(new Size(176,176));root.Arrange(new Rect(0,0,176,176));root.UpdateLayout();
        var bitmap=new RenderTargetBitmap(176,176,96,96,PixelFormats.Pbgra32);bitmap.Render(root);
        var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using var stream=File.Create(Path.Combine(output,skin.Slug+"-glyph.png"));encoder.Save(stream);
    }
}
