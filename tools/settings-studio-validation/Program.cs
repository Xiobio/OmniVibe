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
        var choices = picker.Children.OfType<ComboBox>().Single();
        Test("13 stable choices and five independent preview views", () =>
        {
            Require(choices.Items.Count == 13, "Missing themes");
            var hashes = new HashSet<string>();
            foreach (var skin in SkinCatalog.All)
            {
                choices.SelectedItem = choices.Items.OfType<ComboBoxItem>().Single(i => i.Tag is Skin id && id == skin.Id); Pump(5);
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
            choices.SelectedIndex = (int)Skin.Hextech; picker.ShowPart("suite"); Pump(5);
            foreach (string name in new[] { "主题套装", "圆环与位置", "窗口与排列", "快捷键", "常规与状态" })
            {
                var button = Nodes(window.Content).OfType<Button>().Single(b => b.Content as string == name); button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); window.UpdateLayout(); Pump(12);
                Capture((FrameworkElement)window.Content, Path.Combine(output, "settings-" + new[] { "theme", "ring", "layout", "keys", "general" }[Array.IndexOf(new[] { "主题套装", "圆环与位置", "窗口与排列", "快捷键", "常规与状态" }, name)] + ".png"));
            }
            Nodes(window.Content).OfType<Button>().Single(b => b.Content as string == "主题套装").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
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
                var c = p.Children.OfType<ComboBox>().Single(); c.SelectedIndex = (int)Skin.Wonderland;
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
        File.WriteAllText(Path.Combine(output, "report.json"), JsonSerializer.Serialize(new { passed = failures == 0, failures, results, themeCount = 13, previewModes = 5, packaged = false, liveTerminalSettingsChanged = false }, new JsonSerializerOptions { WriteIndented = true }));
        app.Shutdown(); return failures == 0 ? 0 : 1;
    }
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
