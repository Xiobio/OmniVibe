using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Windows.Markup;
using System.Xml.Linq;
using System.Windows.Input;
using System.Windows.Interop;
using CodeManager;

internal static class Program
{
    [STAThread] private static int Main(string[] args)
    {
        string output = Path.GetFullPath(args.Length == 0 ? "artifacts/settings-studio/validation" : args[0]); Directory.CreateDirectory(output);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        // Load the same style definitions without starting the product manager.
        var xaml = XDocument.Load("src/CodeManager/App.xaml");
        XNamespace ns = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        var dictionary = new XElement(ns + "ResourceDictionary", new XAttribute("xmlns", ns.NamespaceName), new XAttribute(XNamespace.Xmlns + "x", "http://schemas.microsoft.com/winfx/2006/xaml"), xaml.Root!.Element(ns + "Application.Resources")!.Elements());
        app.Resources = (ResourceDictionary)XamlReader.Parse(dictionary.ToString());
        var results = new List<object>(); int failures = 0;
        void Test(string name, Action action)
        {
            try { action(); results.Add(new { name, passed = true }); Console.WriteLine("PASS " + name); }
            catch (Exception ex) { failures++; results.Add(new { name, passed = false, error = ex.ToString() }); Console.WriteLine("FAIL " + name + ": " + ex.Message); }
        }
        WuxiaTheme.Apply(Skin.Hextech, false); Skin active = WuxiaTheme.CurrentSkin;
        string terminalSettings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json");
        string? settingsBefore = File.Exists(terminalSettings) ? Hash(File.ReadAllBytes(terminalSettings)) : null;
        var source = new Preferences { Skin = Skin.Hextech, Animate = false, SoundEffects = false };
        string before = JsonSerializer.Serialize(source, StateStore.Json);
        var window = NewWindow(source); window.Show(); Pump(40);
        var picker = Nodes(window.Content).OfType<SkinPicker>().Single();
        var choices = Nodes(picker).OfType<Button>().Where(b => b.Tag is Skin).ToArray();
        Test("13 stable choices and five independent preview views", () =>
        {
            Require(choices.Length == 13 && !Nodes(picker).OfType<ComboBox>().Any(), "Missing image choices or duplicate text selector remained");
            var hashes = new HashSet<string>();
            foreach (var skin in SkinCatalog.All)
            {
                choices.Single(i => i.Tag is Skin id && id == skin.Id).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump(5);
                Require(picker.SelectedSkin == skin.Id && picker.Scene.PreviewSkin == skin.Id, "Selection/preview mismatch");
                foreach (string mode in new[] { "suite", "dock", "overview", "terminal", "states" })
                {
                    picker.ShowPart(mode); window.UpdateLayout(); Pump(12);
                    byte[] pixels = Capture(picker.Scene, Path.Combine(output, skin.Slug + "-" + mode + ".png"));
                    Require(pixels.Any(b => b != 0), "Blank preview"); hashes.Add(Hash(pixels));
                }
                Require(JsonSerializer.Serialize(source, StateStore.Json) == before && window.Result.Skin == source.Skin && WuxiaTheme.CurrentSkin == active, "Preview committed settings or changed global palette");
            }
            Require(hashes.Count == 65, "Different theme/view combinations rendered identical images");
        });
        Test("Full settings, gallery and five grouped pages render", () =>
        {
            picker.SelectSkin(Skin.Hextech); picker.ShowPart("suite"); Pump(5);
            foreach (string name in new[] { "主题与换装", "快速上手", "窗口与布局", "快捷键", "常规" })
            {
                var button = Nodes(window.Content).OfType<Button>().Single(b => b.Content as string == name); button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); window.UpdateLayout(); Pump(12);
                Capture((FrameworkElement)window.Content, Path.Combine(output, "settings-" + new[] { "theme", "guide", "layout", "keys", "general" }[Array.IndexOf(new[] { "主题与换装", "快速上手", "窗口与布局", "快捷键", "常规" }, name)] + ".png"));
            }
            Nodes(window.Content).OfType<Button>().Single(b => b.Content as string == "主题与换装").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Pump(12);
            var scroll = Nodes(window.Content).OfType<ScrollViewer>().Single(v => v.IsVisible); scroll.ScrollToEnd(); Pump(10);
            Capture((FrameworkElement)window.Content, Path.Combine(output, "settings-gallery.png")); scroll.ScrollToTop();
        });
        Test("Static frame-only preview stays visible; explicit animation advances and stops when hidden or unloaded", () =>
        {
            picker.EffectsEnabled = () => true; picker.DecorationsEnabled = () => false; picker.ShowPart("terminal"); Pump(50);
            Require(picker.Scene.OpenAnimationCount == 0 && !picker.Scene.IsPlaying, "Global UI motion started a Terminal GIF without explicit opt-in");
            var terminalAsset = typeof(SkinSuitePreview).GetField("_terminal", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!;
            object? staticAsset = terminalAsset.GetValue(picker.Scene); Require(staticAsset != null, "Frame-only static PNG was not loaded");
            string withFrame = Hash(Capture(picker.Scene, Path.Combine(output, "static-frame-only.png")));
            string withoutFrame;
            try { terminalAsset.SetValue(picker.Scene, null); picker.Scene.InvalidateVisual(); Pump(5); withoutFrame = Hash(Capture(picker.Scene, Path.Combine(output, "static-without-asset.png"))); }
            finally { terminalAsset.SetValue(picker.Scene, staticAsset); picker.Scene.InvalidateVisual(); }
            Require(withFrame != withoutFrame, "Static frame-only PNG was loaded but not rendered when artwork and animation were off");
            picker.DecorationsEnabled = () => true;
            var terminalMotion = Nodes(window.Content).OfType<CheckBox>().Single(c => System.Windows.Automation.AutomationProperties.GetName(c) == "Terminal 背景动画");
            terminalMotion.IsChecked = true; Pump(50);
            Require(picker.Scene.OpenAnimationCount == 1 && picker.Scene.IsPlaying, "Animation did not start");
            string first = Hash(Capture(picker.Scene, Path.Combine(output, "animation-before.png"))); Pump(350);
            string second = Hash(Capture(picker.Scene, Path.Combine(output, "animation-after.png"))); Require(first != second, "Real GIF frame did not advance");
            picker.Scene.Visibility = Visibility.Collapsed; Pump(5); Require(!picker.Scene.IsPlaying, "Hidden preview kept rendering");
            picker.Scene.Visibility = Visibility.Visible; Pump(5); Require(picker.Scene.IsPlaying, "Visible preview did not resume");
            window.Close(); Pump(10); Require(!picker.Scene.IsPlaying && picker.Scene.OpenAnimationCount == 0, "Closing settings retained the GIF or timer");
        });
        if (window.IsVisible) window.Close();
        Test("Save commits the draft while caller preferences remain unchanged", () =>
        {
            var dialog = NewWindow(source);
            Dispatcher.CurrentDispatcher.BeginInvoke(() =>
            {
                var p = Nodes(dialog.Content).OfType<SkinPicker>().Single();
                p.SelectSkin(Skin.Wonderland);
                Nodes(dialog.Content).OfType<Button>().Single(b => b.Content as string == "保存并应用").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            }, DispatcherPriority.ApplicationIdle);
            Require(dialog.ShowDialog() == true && dialog.Result.Skin == Skin.Wonderland, "Save did not commit selected theme");
            Require(JsonSerializer.Serialize(source, StateStore.Json) == before && WuxiaTheme.CurrentSkin == active, "Save mutated source/global skin before manager accepted it");
        });
        Test("Narrow/short layouts keep footer actions inside the window", () =>
        {
            foreach (Skin skin in new[] { Skin.Hextech, Skin.Wonderland, Skin.InkJade })
            {
                WuxiaTheme.Apply(skin, false);
                var small = NewWindow(new Preferences { Skin = skin, Animate = false }); small.Width = 720; small.Height = 580; small.Show(); Pump(20);
                try
                {
                    var root = (FrameworkElement)small.Content;
                    foreach (string label in new[] { "取消", "保存并应用", "恢复默认" })
                    {
                        var b = Nodes(root).OfType<Button>().Single(b => b.Content as string == label);
                        var bounds = b.TransformToAncestor(root).TransformBounds(new Rect(b.RenderSize));
                        Require(bounds.Left >= 0 && bounds.Top >= 0 && bounds.Right <= root.ActualWidth + 1 && bounds.Bottom <= root.ActualHeight + 1, "Footer action clipped");
                    }
                    Capture(root, Path.Combine(output, "narrow-" + SkinCatalog.Get(skin).Slug + ".png"));
                    var scroll = Nodes(root).OfType<ScrollViewer>().Single(v => v.IsVisible); scroll.ScrollToEnd(); Pump(5); Require(scroll.VerticalOffset > 0, "Long theme content could not scroll");
                }
                finally { small.Close(); }
            }
        });
        Test("Preview and validation never write live Terminal settings", () =>
        {
            Require(settingsBefore == (File.Exists(terminalSettings) ? Hash(File.ReadAllBytes(terminalSettings)) : null), "Live Terminal settings were changed");
        });
        Test("Custom bindings preserve legacy defaults, deep drafts, clears and saved round trips", () =>
        {
            var legacy = new Preferences { TaskModifiers = ShortcutModifiers.CtrlShift, SoundEffects = false };
            Require(legacy.TaskGesture(7) == "Ctrl+Shift+7", "Legacy modifier preference was not migrated lazily");
            var draft = legacy.Copy(); draft.TaskGestures[1] = "Ctrl+Shift+F18"; draft.TaskGestures[7] = ""; draft.ArrangeGesture = "";
            Require(!legacy.TaskGestures.Any() && legacy.TaskGesture(1) == "Ctrl+Shift+1", "Draft mutated the source dictionary");
            var store = new StateStore(Path.Combine(output, "isolated-state")); store.Save(new AppState { Preferences = draft }); var loaded = store.Load().Preferences;
            Require(loaded.TaskGesture(1) == "Ctrl+Shift+F18" && loaded.TaskGesture(7) == "" && loaded.ArrangeGesture == "", "State loading re-enabled a deliberately cleared shortcut");
            Require(InputService.TryParseGesture("F18", out uint fm, out uint fk) && fm == 0 && fk == 0x81, "Bare function key not supported");
            Require(InputService.TryParseGesture("Ctrl+Win+OemPlus", out uint wm, out uint wk) && wm == 10 && wk == 0xBB, "Windows/OEM chord not supported");
            draft.TaskGestures[2] = "Control+Shift+F18";
            Require(!ShortcutBindings.Validate(draft, out string conflict) && conflict.Contains("窗口 1") && conflict.Contains("窗口 2"), "Canonical duplicate did not identify both actions");
            draft.TaskGestures[2] = "Win+L"; Require(!ShortcutBindings.Validate(draft, out string reserved) && reserved.Contains("Windows"), "Protected system chord not identified");
        });
        Test("Recorder consumes routed function keys, cancels with Escape, clears and restores defaults", () =>
        {
            var dialog = NewWindow(source); dialog.Show(); Pump(8);
            try {
                Nodes(dialog.Content).OfType<Button>().Single(b => b.Content as string == "快捷键").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump(8);
                var recorder = Recorder(dialog, "窗口 1");
                var capture = Nodes(recorder).OfType<Button>().Single(b => System.Windows.Automation.AutomationProperties.GetName(b) == "录入窗口 1");
                recorder.BeginCapture();
                var press = new KeyEventArgs(Keyboard.PrimaryDevice, PresentationSource.FromVisual(dialog), Environment.TickCount, Key.F18) { RoutedEvent = Keyboard.PreviewKeyDownEvent };
                capture.RaiseEvent(press); Require(press.Handled && recorder.Gesture == "F18" && !recorder.IsCapturing, "Routed key was not captured and consumed");
                recorder.BeginCapture(); var escape = new KeyEventArgs(Keyboard.PrimaryDevice, PresentationSource.FromVisual(dialog), Environment.TickCount, Key.Escape) { RoutedEvent = Keyboard.PreviewKeyDownEvent }; capture.RaiseEvent(escape);
                Require(recorder.Gesture == "F18" && !recorder.IsCapturing, "Escape failed to restore the prior draft");
                Nodes(recorder).OfType<Button>().Single(b => System.Windows.Automation.AutomationProperties.GetName(b) == "清除窗口 1").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Require(recorder.Gesture == "", "Clear failed");
                Nodes(recorder).OfType<Button>().Single(b => System.Windows.Automation.AutomationProperties.GetName(b) == "恢复默认窗口 1").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Require(recorder.Gesture == "Alt+1", "Per-action default failed");
                Require(JsonSerializer.Serialize(source, StateStore.Json) == before, "Recorder wrote preferences before Save");
            }
            finally { dialog.Close(); }
        });
        Test("Saved UI bindings reach preferences; conflicts keep the dialog open without committing", () =>
        {
            var dialog = NewWindow(source); string? outcome = null;
            Dispatcher.CurrentDispatcher.BeginInvoke(() => {
                Recorder(dialog, "窗口 1").SetGesture("Ctrl+Shift+F18"); Recorder(dialog, "排列 / 恢复").SetGesture(""); Recorder(dialog, "任务总览").SetGesture("");
                dialog.ShortcutAvailabilityCheck = p => { outcome = p.TaskGesture(1); return "验证占用：Ctrl+Shift+F18"; };
                var save = Nodes(dialog.Content).OfType<Button>().Single(b => b.Content as string == "保存并应用"); save.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                Require(dialog.IsVisible && dialog.Result.TaskGesture(1) == "Alt+1", "Conflict committed or closed the dialog");
                dialog.ShortcutAvailabilityCheck = null; save.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            }, DispatcherPriority.ApplicationIdle);
            Require(dialog.ShowDialog() == true && outcome == "Ctrl+Shift+F18", "Draft did not reach availability validation");
            Require(dialog.Result.TaskGesture(1) == "Ctrl+Shift+F18" && dialog.Result.ArrangeGesture == "" && !dialog.Result.TabTogglesInventory, "Custom/cleared UI bindings did not save");
            Require(JsonSerializer.Serialize(source, StateStore.Json) == before, "Save mutated caller preferences");
        });
        Test("Native registration follows per-slot custom keys and releases every chord during recording", () =>
        {
            var p = new Preferences { ToggleGesture = "", ArrangeGesture = "", RadialGesture = "", TabTogglesInventory = false, WheelSwitchEnabled = false, TaskGestures = Enumerable.Range(1,9).ToDictionary(n => n, _ => "") };
            p.TaskGestures[7] = "Ctrl+Shift+F18";
            using var input = new InputService(Dispatcher.CurrentDispatcher); input.Configure(p, new[] { 7 }, false);
            using var probe = new HwndSource(new HwndSourceParameters("OmniVibe.ValidationProbe") { ParentWindow = new IntPtr(-3), Width = 0, Height = 0 });
            bool occupied = Native.RegisterHotKey(probe.Handle, 190, 6 | 0x4000, 0x81); if (occupied) Native.UnregisterHotKey(probe.Handle, 190);
            Require(!occupied, "Custom chord was not actually registered by InputService");
            Require(InputService.RegistrationConflict(p) is string blocked && blocked.Contains("窗口 7"), "Availability probe did not detect a real occupied custom chord");
            Require(InputService.RegistrationConflict(p, p.Copy()) == null, "Unchanged bindings blocked an unrelated settings save");
            input.Configure(p, new[] { 7 }, true);
            bool released = Native.RegisterHotKey(probe.Handle, 190, 6 | 0x4000, 0x81); if (released) Native.UnregisterHotKey(probe.Handle, 190);
            Require(released, "Suspended input retained the recorded chord");
            p.ToggleGesture = "Ctrl+Shift+F19"; input.Configure(p, Array.Empty<int>(), false);
            bool toggleOccupied = Native.RegisterHotKey(probe.Handle, 191, 6 | 0x4000, 0x82); if (toggleOccupied) Native.UnregisterHotKey(probe.Handle, 191);
            Require(!toggleOccupied, "Toggle chord was not registered");
            input.Configure(p, Array.Empty<int>(), true);
            bool toggleReleased = Native.RegisterHotKey(probe.Handle, 191, 6 | 0x4000, 0x82); if (toggleReleased) Native.UnregisterHotKey(probe.Handle, 191);
            Require(toggleReleased, "Opening settings kept the visibility hotkey registered");
        });
        Test("Guide uses saved custom keys and disabled actions; visual equipment draft preserves task identity", () =>
        {
            var p = source.Copy(); p.TaskGestures[1] = "Ctrl+Shift+F18"; p.InventoryGesture = ""; p.TabTogglesInventory = false; p.ArrangeGesture = "Ctrl+Alt+F19";
            var guide = new GettingStartedPanel(p); var text = string.Join("\n", Nodes(guide).OfType<TextBlock>().Select(t => t.Text));
            Require(text.Contains("Ctrl+Shift+F18") && text.Contains("Ctrl+Alt+F19") && !text.Contains("Tab 补全会被接管"), "Guide showed hardcoded/default shortcuts after customization");
            Require(guide.Bindings.Single(b => b.Id == 11).Gesture == "", "Disabled overview incorrectly advertised a shortcut");
            var paused = new GettingStartedPanel(p, shortcutsPaused: true); Require(Nodes(paused).OfType<TextBlock>().Any(t => t.Text.Contains("全局快捷键已暂时暂停")), "Guide advertised paused keys as active");
            var slots = Enumerable.Range(1,9).Select(n => new Slot { Number=n, Id="task-"+n }).ToList(); var ids = slots.Select(s=>s.Id).ToArray();
            var loadout = new LoadoutWindow(slots, new Native.Rect(0,0,1920,1080), previewSkin: Skin.Hextech) { Left=-20000,Top=-20000,ShowActivated=false,Topmost=false };
            try {
                loadout.Show(); Pump(10); Require(Nodes(loadout.Content).OfType<Image>().Count(i => i.Source != null) >= 19, "Equipment portraits not displayed together");
                var root = (FrameworkElement)loadout.Content; var gallery = Nodes(root).OfType<System.Windows.Controls.Primitives.UniformGrid>().Single();
                var galleryBounds = gallery.TransformToAncestor(root).TransformBounds(new Rect(gallery.RenderSize));
                var save = Nodes(root).OfType<Button>().Single(b => b.Content as string == "保存配装"); var saveBounds = save.TransformToAncestor(root).TransformBounds(new Rect(save.RenderSize));
                Require(gallery.Children.Count == 9 && galleryBounds.Bottom < saveBounds.Top - 8 && saveBounds.Bottom <= root.ActualHeight + 1 && save.IsVisible, "Nine equipment choices or footer actions are hidden or require scrolling");
                loadout.SelectWeapon(EquipmentCatalog.ForSkin(Skin.Hextech)[4].Id); Require(slots.Select(s=>s.Id).SequenceEqual(ids) && slots.All(s=>s.EquipmentSelections.Count==0), "Visual draft changed live task bindings"); Pump(20); Capture(root,Path.Combine(output,"visual-loadout.png"));
            }
            finally { loadout.Close(); }
            var pending = loadout.Result; var reopened = LoadoutWindow.CreateDraft(slots, pending);
            Require(EquipmentCatalog.Item(reopened[0], Skin.Hextech).Id == EquipmentCatalog.ForSkin(Skin.Hextech)[4].Id && slots[0].EquipmentSelections.Count == 0, "Reopening a settings wardrobe lost its draft or changed a live task");
        });
        Test("First-run guide is fresh-install only and its three entry points dispatch real actions", () =>
        {
            var fresh = new AppState(); Require(GettingStartedPanel.ShouldOpenOnStartup(fresh), "Fresh user would receive no introduction");
            fresh.Preferences.HasSeenIntroduction = true; Require(!GettingStartedPanel.ShouldOpenOnStartup(fresh), "Guide repeats after being seen");
            fresh.Preferences.HasSeenIntroduction = false; fresh.RecentTasks.Add(new()); Require(!GettingStartedPanel.ShouldOpenOnStartup(fresh), "Existing recovery user interrupted by a fresh-install guide");
            var guide = new GettingStartedPanel(source); int add = 0, keys = 0, recovery = 0;
            guide.AddWindowRequested += () => add++; guide.ConfigureShortcutsRequested += () => keys++; guide.RecoveryRequested += () => recovery++;
            foreach (string label in new[] { "选择一个已有窗口", "修改快捷键", "恢复上次任务" }) Nodes(guide).OfType<Button>().Single(b => b.Content as string == label).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Require(add == 1 && keys == 1 && recovery == 1, "Guide entry was only decoration without an action");
            foreach (string page in new[] { "快速上手", "快捷键", "窗口与布局", "常规" }) {
                var small = NewWindow(source); small.Width = 720; small.Height = 580; small.Show(); Pump(10);
                try { Nodes(small.Content).OfType<Button>().Single(b => b.Content as string == page).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump(8); var root = (FrameworkElement)small.Content; var save = Nodes(root).OfType<Button>().Single(b => b.Content as string == "保存并应用"); var bounds = save.TransformToAncestor(root).TransformBounds(new Rect(save.RenderSize)); Require(bounds.Right <= root.ActualWidth + 1 && bounds.Bottom <= root.ActualHeight + 1, page + " footer clipped"); Capture(root,Path.Combine(output,"narrow-page-"+page+".png")); }
                finally { small.Close(); }
            }
        });
        File.WriteAllText(Path.Combine(output, "report.json"), JsonSerializer.Serialize(new { passed = failures == 0, failures, results, themeCount = 13, previewModes = 5, packaged = false, liveTerminalSettingsChanged = false }, new JsonSerializerOptions { WriteIndented = true }));
        app.Shutdown(); return failures == 0 ? 0 : 1;
    }
    private static ShortcutRecorder Recorder(SettingsWindow window, string name) => Nodes(window.Content).OfType<ShortcutRecorder>().Single(r => Nodes(r).OfType<Button>().Any(b => System.Windows.Automation.AutomationProperties.GetName(b) == "录入" + name));
    private static SettingsWindow NewWindow(Preferences p) => new(p, new Native.Rect(0, 0, 2560, 1440), "", page: 2) { Width = 1180, Height = 900, ShowActivated = false, ShowInTaskbar = false, Topmost = false, Left = -20000, Top = -20000 };
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static void Pump(int milliseconds)
    {
        var end = DateTime.UtcNow.AddMilliseconds(milliseconds);
        do { Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle); System.Threading.Thread.Sleep(2); } while (DateTime.UtcNow < end);
    }
    private static byte[] Capture(FrameworkElement element, string path)
    {
        element.UpdateLayout(); int width = (int)Math.Ceiling(element.ActualWidth), height = (int)Math.Ceiling(element.ActualHeight);
        var image = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        var background = new DrawingVisual(); using (var dc = background.RenderOpen()) dc.DrawRectangle(Window.GetWindow(element)?.Background ?? Brushes.Transparent, null, new Rect(0, 0, width, height));
        image.Render(background); image.Render(element);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image)); using (var stream = File.Create(path)) encoder.Save(stream);
        var bytes = new byte[width * height * 4]; image.CopyPixels(bytes, width * 4, 0); return bytes;
    }
    private static IEnumerable<DependencyObject> Nodes(object? root)
    {
        if (root is not DependencyObject node) yield break; yield return node;
        foreach (object child in LogicalTreeHelper.GetChildren(node)) foreach (var descendant in Nodes(child)) yield return descendant;
    }
}
