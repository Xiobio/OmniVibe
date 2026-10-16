using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace CodeManager;

public static class SkinTests
{
    public static IEnumerable<SelfTests.Result> Run()
    {
        var results = new List<SelfTests.Result>();
        void Test(string name, Action action)
        {
            try { action(); results.Add(new(name, true, "OK")); }
            catch (Exception ex) { results.Add(new(name, false, ex.ToString())); }
        }
        static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
        Skin original = WuxiaTheme.CurrentSkin; bool decorations = SkinCatalog.DecorationsEnabled;
        try
        {
            Test("Skins: all 13 palettes meet body, panel, card and status text contrast >= 4.5", () =>
            {
                Check((int)Skin.InkJade == 0 && (int)Skin.Midnight == 1 && (int)Skin.Cinnabar == 2, "Legacy persisted enum values changed");
                Check(SkinCatalog.All.Count == 13 && SkinCatalog.All.Select(s => s.Slug).Distinct().Count() == 13, "Duplicate or missing palette");
                foreach (var s in SkinCatalog.All)
                {
                    foreach (string bg in new[] { s.Background, s.Surface, s.Elevated })
                        foreach (string fg in new[] { s.Text, s.Muted, s.Accent, s.Running, s.Waiting, s.Ready, s.Error, s.Unknown })
                            Check(SkinCatalog.Contrast(fg, bg) >= 4.5, $"{s.Slug}: {fg} on {bg} has contrast {SkinCatalog.Contrast(fg, bg):F3}");
                    Check(SkinCatalog.Contrast(s.CardText, s.CardBackground) >= 4.5, s.Slug + ": card text contrast");
                    var cardForeground = (Color)ColorConverter.ConvertFromString(s.CardText); var bgColor = (Color)ColorConverter.ConvertFromString(s.CardBackground);
                    static byte Blend(byte foreground, byte background) => (byte)Math.Round(foreground * .8 + background * .2);
                    string metadata = $"#{Blend(cardForeground.R, bgColor.R):X2}{Blend(cardForeground.G, bgColor.G):X2}{Blend(cardForeground.B, bgColor.B):X2}";
                    Check(SkinCatalog.Contrast(metadata, s.CardBackground) >= 4.5, s.Slug + ": 80% metadata text contrast");
                    Check(Enumerable.Range(1, 9).Select(s.SlotNumber).Distinct().Count() == 9, s.Slug + ": slot numerals collide");
                }
                Check(SkinCatalog.Get((Skin)999) == SkinCatalog.All[0], "Unknown persisted skin did not use safe fallback");
            });
            Test("Skins: terminal/native JSON palette contract matches every new skin", () =>
            {
                using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "skins", "catalog.json")));
                Check(document.RootElement.GetArrayLength() == 10, "Published palette count differs");
                foreach (var row in document.RootElement.EnumerateArray())
                {
                    var s = SkinCatalog.All.Single(s => s.Slug == row.GetProperty("slug").GetString());
                    foreach (var pair in new[] { ("background", s.Background), ("surface", s.Surface), ("elevated", s.Elevated), ("text", s.Text), ("muted", s.Muted), ("accent", s.Accent), ("secondary", s.Secondary), ("border", s.Border), ("running", s.Running), ("waiting", s.Waiting), ("ready", s.Ready), ("error", s.Error), ("unknown", s.Unknown), ("cardBackground", s.CardBackground), ("cardText", s.CardText), ("family", s.Family), ("artwork", s.Artwork) })
                        Check(row.GetProperty(pair.Item1).GetString() == pair.Item2, s.Slug + ": JSON diverged at " + pair.Item1);
                    Check(row.GetProperty("id").GetString() == s.Id.ToString(), s.Slug + ": ID mismatch");
                }
            });
            Test("Skins: switching and rendering each task state preserves task IDs, launch, session and window snapshots", () =>
            {
                var state = new AppState();
                foreach (var slot in state.Slots)
                {
                    slot.Name = "中英文 very long task / " + slot.Number;
                    if (slot.Number <= 6) slot.Window = new() { Handle = 10000 + slot.Number, ProcessId = 20000 + slot.Number, ProcessStartedUtcTicks = 50000 + slot.Number, ProcessName = "fixture", Title = "Task " + slot.Number };
                    slot.Connected = slot.Number <= 5; slot.State = (AgentState)((slot.Number - 1) % 5); slot.Unread = slot.Number is 2 or 3;
                    slot.ProjectDirectory = "D:\\fixture\\项目 " + slot.Number; slot.SessionId = "session-" + slot.Number;
                    slot.LaunchMode = LaunchMode.Codex; slot.ResumeSessionId = slot.SessionId; slot.Notes = "保留任务备忘";
                }
                var first = state.Slots[0]; state.Popup = new() { SlotId = first.Id, Window = first.Window!, ParkedByApp = true };
                state.Layout.Add(new() { SlotId = first.Id, Window = first.Window!, ParkedByApp = false }); state.DockVisibleBeforeLayout = false;
                string before = JsonSerializer.Serialize(state, StateStore.Json);
                foreach (var s in SkinCatalog.All)
                {
                    WuxiaTheme.Apply(s.Id);
                    var resource = (SolidColorBrush)Application.Current.Resources["SkinTextBrush"];
                    Check(resource.Color == ((SolidColorBrush)WuxiaTheme.Brush(s.Text)).Color, s.Slug + ": dynamic control text did not switch");
                    foreach (var slot in state.Slots)
                    {
                        var card = new SkinTaskCard(slot, false); card.Measure(new Size(360, 240)); card.Arrange(new Rect(0, 0, 360, 240)); card.Update(slot.Number == 3); card.StopAnimations();
                    }
                    Check(JsonSerializer.Serialize(state, StateStore.Json) == before, s.Slug + ": rendering changed saved task or window state");
                }
            });
            Test("Skins: family glyphs are distinct and decorations-off renders a clean interactive background", () =>
            {
                var hashes = new HashSet<string>();
                foreach (var s in SkinCatalog.All.Where(s => s.Id >= Skin.Hextech))
                {
                    WuxiaTheme.Apply(s.Id); SkinCatalog.DecorationsEnabled = true;
                    var glyph = new SkinGlyph(false); byte[] pixels = Render(glyph);
                    Check(pixels.Any(b => b != 0), s.Slug + ": missing family emblem");
                    Check(hashes.Add(Convert.ToHexString(SHA256.HashData(pixels))), s.Slug + ": emblem duplicates another family");
                    SkinCatalog.DecorationsEnabled = false;
                    Check(Render(new SkinGlyph(false)).All(b => b == 0), s.Slug + ": decorations-off still drew emblem");
                    pixels = Render(new SkinBackdrop());
                    var bg = (Color)ColorConverter.ConvertFromString(s.Background);
                    for (int i = 0; i < pixels.Length; i += 4) Check(pixels[i] == bg.B && pixels[i + 1] == bg.G && pixels[i + 2] == bg.R && pixels[i + 3] == 255, s.Slug + ": decorations-off altered the plain background");
                }
            });
            Test("Skins: narrow task dock keeps its themed five-pixel scrollbar after content rendering", () =>
            {
                WuxiaTheme.Apply(Skin.Protocol);
                var dock = new DockWindow { Width = 210, Height = 460 };
                try
                {
                    dock.SetSlots(Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Window = new() { Title = "fixture" }, Connected = true }).ToList());
                    var content = (FrameworkElement)dock.Content; content.Measure(new Size(210, 460)); content.Arrange(new Rect(0, 0, 210, 460)); content.UpdateLayout();
                    var scroll = (ScrollViewer)dock.FindName("SlotsScroll"); scroll.ApplyTemplate(); scroll.UpdateLayout();
                    var bar = (ScrollBar?)scroll.Template.FindName("PART_VerticalScrollBar", scroll);
                    Check(bar != null && bar.Style == dock.Resources["DockScrollbar"], "Dock scrollbar did not retain the explicit theme style");
                    Check(bar!.Width == 5 && bar.ActualWidth <= 6, "Dock scrollbar exceeded five DIP: " + bar.ActualWidth);
                    Check(bar.Template != null, "Dock scrollbar lost its theme template");
                }
                finally { dock.Close(); }
            });
            Test("Skins: 13 settings choices use stable enum tags; cancel and save preserve preference boundaries", () =>
            {
                Skin active = WuxiaTheme.CurrentSkin;
                foreach (var s in SkinCatalog.All)
                {
                    var source = new Preferences { Skin = s.Id, DecorationsEnabled = false, Animate = false, SoundEffects = false };
                    string before = JsonSerializer.Serialize(source, StateStore.Json);
                    var window = new SettingsWindow(source, new Native.Rect(0, 0, 1920, 1040), "", page: 2);
                    try
                    {
                        var picker = Descendants(window.Content).OfType<SkinPicker>().Single();
                        Check(picker.SelectedSkin == s.Id, s.Slug + ": saved enum selected the wrong theme");
                        var choices = picker.Children.OfType<ComboBox>().Single();
                        choices.SelectedIndex = (choices.SelectedIndex + 1) % SkinCatalog.All.Count;
                        Check(picker.SelectedSkin == (Skin)((int)s.Id + 1 == SkinCatalog.All.Count ? 0 : (int)s.Id + 1), s.Slug + ": choice does not map to enum tag");
                        Check(window.Result.Skin == s.Id && !window.Result.DecorationsEnabled, "Preview changed uncommitted settings");
                        Check(JsonSerializer.Serialize(source, StateStore.Json) == before && WuxiaTheme.CurrentSkin == active, "Preview changed the active palette or source preferences");
                    }
                    finally { window.Close(); }
                }
                var preferences = new Preferences { Skin = Skin.Tactical, DecorationsEnabled = true };
                var dialog = new SettingsWindow(preferences, new Native.Rect(0, 0, 1920, 1040), "", page: 2) { ShowActivated = false, Topmost = false, Left = -20000, Top = -20000 };
                Dispatcher.CurrentDispatcher.BeginInvoke(() =>
                {
                    var picker = Descendants(dialog.Content).OfType<SkinPicker>().Single();
                    picker.Children.OfType<ComboBox>().Single().SelectedItem = picker.Children.OfType<ComboBox>().Single().Items.OfType<ComboBoxItem>().Single(i => i.Tag is Skin s && s == Skin.Wonderland);
                    var decoration = Descendants(dialog.Content).OfType<CheckBox>().Single(c => c.Content is TextBlock t && t.Text.Contains("装饰")); decoration.IsChecked = false;
                    Descendants(dialog.Content).OfType<Button>().Single(b => b.Content as string == "保存并应用").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                }, DispatcherPriority.ApplicationIdle);
                Check(dialog.ShowDialog() == true, "Settings save failed");
                Check(dialog.Result.Skin == Skin.Wonderland && !dialog.Result.DecorationsEnabled, "Settings did not commit selected skin and decoration toggle");
                Check(preferences.Skin == Skin.Tactical && preferences.DecorationsEnabled && WuxiaTheme.CurrentSkin == active, "Settings commit mutated caller preferences or applied before manager accepted");
                var roundtrip = JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(dialog.Result, StateStore.Json), StateStore.Json)!;
                Check(roundtrip.Skin == Skin.Wonderland && !roundtrip.DecorationsEnabled, "Skin/decorations did not round-trip");
            });
            Test("Skins: nine-card overview remains readable at 780x650 and 200-percent display scaling", () =>
            {
                SkinCatalog.DecorationsEnabled = true;
                foreach (var s in SkinCatalog.All)
                {
                    WuxiaTheme.Apply(s.Id);
                    foreach (var viewport in new[] { (Area: new Native.Rect(0, 0, 836, 698), Scale: 1d), (Area: new Native.Rect(0, 0, 1920, 1040), Scale: 2d) })
                    {
                        var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Window = n <= 6 ? new() { Title = "Mixed 中英文任务 " + n } : null, Connected = n <= 5, State = (AgentState)((n - 1) % 5) }).ToList();
                        var window = new InventoryWindow(slots, viewport.Area, viewport.Scale, 3, false, presentationPreview: true);
                        try
                        {
                            var content = (FrameworkElement)window.Content;
                            content.Measure(new Size(window.Width, window.Height)); content.Arrange(new Rect(0, 0, window.Width, window.Height)); content.UpdateLayout();
                            foreach (var card in Descendants(content).OfType<SkinTaskCard>())
                            {
                                var preview = card.PreviewRegion;
                                Check(preview.ActualHeight >= (viewport.Scale == 2 ? 25 : 30), $"{s.Slug}: preview crushed to {preview.ActualHeight:F1} at scale {viewport.Scale}");
                                foreach (var label in Descendants(preview).OfType<TextBlock>().Where(t => t.Visibility == Visibility.Visible && t.ActualHeight > 0))
                                {
                                    Rect bounds = label.TransformToAncestor(preview).TransformBounds(new Rect(label.RenderSize));
                                    Check(bounds.Top >= -1 && bounds.Bottom <= preview.ActualHeight + 1 && bounds.Left >= -1 && bounds.Right <= preview.ActualWidth + 1, s.Slug + ": preview status text clipped at scale " + viewport.Scale);
                                }
                            }
                        }
                        finally { window.Close(); }
                    }
                }
            });
            Test("Skins: themed settings scroll viewer retains vertical and horizontal scrolling", () =>
            {
                WuxiaTheme.Apply(Skin.Wonderland);
                var viewer = new ScrollViewer { Width = 300, Height = 200, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = new Border { Width = 2000, Height = 2000 } };
                viewer.Measure(new Size(300, 200)); viewer.Arrange(new Rect(0, 0, 300, 200)); viewer.UpdateLayout(); viewer.ApplyTemplate();
                var vertical = (ScrollBar?)viewer.Template.FindName("PART_VerticalScrollBar", viewer);
                var horizontal = (ScrollBar?)viewer.Template.FindName("PART_HorizontalScrollBar", viewer);
                Check(vertical != null && horizontal != null, "Global themed scroll viewer lost a scrollbar PART");
                Check(vertical!.Width == 10 && horizontal!.Height == 10, "Themed scrollbar hit targets changed size");
                viewer.ScrollToHorizontalOffset(40); viewer.ScrollToVerticalOffset(50); viewer.UpdateLayout();
                Check(viewer.HorizontalOffset >= 40 && viewer.VerticalOffset >= 50, "ScrollTo stopped routing to content");
                double x = viewer.HorizontalOffset, y = viewer.VerticalOffset; viewer.LineRight(); viewer.LineDown(); viewer.UpdateLayout();
                Check(viewer.HorizontalOffset > x && viewer.VerticalOffset > y, "Line scrolling stopped routing to content");
            });
            Test("Skins: short work areas scroll all nine tasks and suppress clipped native thumbnails", () =>
            {
                WuxiaTheme.Apply(Skin.Protocol);
                var fixture = new Window { Title = "OmniVibe skin thumbnail fixture", Width = 320, Height = 180, ShowActivated = false, ShowInTaskbar = false, Left = -19000, Top = -19000 };
                InventoryWindow? window = null;
                try
                {
                    fixture.Show(); fixture.UpdateLayout();
                    // The fixture is intentionally a tool window, so it bypasses the user-window picker filter.
                    var identity = new WindowIdentity { Handle = new WindowInteropHelper(fixture).Handle.ToInt64(), ProcessId = Environment.ProcessId, ProcessName = "fixture", Title = fixture.Title };
                    var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Window = identity, Connected = true, Name = "short task " + n, State = AgentState.Running }).ToList();
                    window = new InventoryWindow(slots, new Native.Rect(0, 0, 1920, 698), 2, 1, false, presentationPreview: true) { ShowActivated = false, Topmost = false };
                    Check(window.Height <= 349 && window.Top >= 0 && window.Top + window.Height <= 349, "Short-area overview escaped work area");
                    window.Left = -18000; window.Top = -18000; window.Show(); window.UpdateLayout();
                    Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                    var viewport = Descendants(window.Content).OfType<ScrollViewer>().Single();
                    Check(viewport.ScrollableHeight > 0, "Short work area did not provide a scroll fallback");
                    var baseline = Native.Thumbnail(new WindowInteropHelper(window).Handle, new(identity.Handle), new Native.Rect(20, 20, 140, 100));
                    Check(baseline != IntPtr.Zero, "Native thumbnail baseline did not register"); Native.DwmUnregisterThumbnail(baseline);
                    window.UpdateThumbnails();
                    Check(window.ThumbnailCount > 0 && window.ThumbnailCount < 9, "Visible native previews were absent, or clipped previews were not suppressed");
                    window.Select(9); window.UpdateLayout(); Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                    Check(window.SelectedNumber == 9 && viewport.VerticalOffset > 0, "Last task was unreachable through overview selection");
                    int entered = 0; window.Choose += number => entered = number; window.Enter(); Check(entered == 9, "Enter did not route to selected last task");
                    window.UpdateThumbnails(); Check(window.ThumbnailCount < 9, "Scrolling exposed clipped native previews");
                }
                finally { window?.Close(); fixture.Close(); }
            });
            Test("Skins: themed slider retains native commands; menu and combo popups honor animation off/on", () =>
            {
                var slider = new Slider { Minimum = 0, Maximum = 100, Value = 0, TickFrequency = 10, IsSnapToTickEnabled = true, LargeChange = 10, Width = 300, Height = 30 };
                var combo = new ComboBox { Width = 200 }; combo.Items.Add("fixture");
                var menu = new MenuItem { Header = "fixture" }; menu.Items.Add(new MenuItem { Header = "submenu" });
                var panel = new StackPanel(); panel.Children.Add(combo); panel.Children.Add(menu); panel.Children.Add(slider);
                WuxiaTheme.Apply(Skin.Protocol, false);
                var host = new Window { Content = panel, Width = 340, Height = 180, Left = -17000, Top = -17000, ShowActivated = false, ShowInTaskbar = false };
                try
                {
                    host.Show(); host.UpdateLayout(); Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                    Check(slider.Style == Application.Current.Resources[typeof(Slider)], "Shown slider did not inherit the application theme");
                    var track = (Track?)slider.Template.FindName("PART_Track", slider);
                    Check(track?.Thumb != null && track.Thumb.Width == 12 && track.Thumb.Height == 18, "Themed slider lost its native track/thumb");
                    Slider.IncreaseLarge.Execute(null, slider);
                    Check(slider.Value > 0 && slider.Value % 10 == 0, "Large-step command did not honor ticks");
                    Slider.DecreaseLarge.Execute(null, slider); Check(slider.Value == 0, "DecreaseLarge stopped routing");
                    var comboPopup = combo.Template.FindName("PART_Popup", combo) as Popup ?? throw new Exception("Combo popup template PART missing");
                    var menuPopup = menu.Template.FindName("PART_Popup", menu) as Popup ?? throw new Exception("Menu popup template PART missing");
                    Check(comboPopup.PopupAnimation == PopupAnimation.None && menuPopup.PopupAnimation == PopupAnimation.None, "Popup animation ignored disabled preference");
                    WuxiaTheme.Apply(Skin.Protocol, true); host.UpdateLayout();
                    Check(comboPopup.PopupAnimation == PopupAnimation.Fade && menuPopup.PopupAnimation == PopupAnimation.Fade, "Popup animation did not re-enable dynamically");
                    WuxiaTheme.Apply(Skin.Protocol, false); host.UpdateLayout();
                    Check(comboPopup.PopupAnimation == PopupAnimation.None && menuPopup.PopupAnimation == PopupAnimation.None, "Existing popup did not react to disabling motion");
                }
                finally { host.Close(); }
            });
        }
        finally { SkinCatalog.DecorationsEnabled = decorations; WuxiaTheme.Apply(original); }
        return results;
    }
    private static byte[] Render(FrameworkElement element)
    {
        element.Width = element.Height = 100; element.Measure(new Size(100, 100)); element.Arrange(new Rect(0, 0, 100, 100)); element.UpdateLayout();
        var bitmap = new RenderTargetBitmap(100, 100, 96, 96, PixelFormats.Pbgra32); bitmap.Render(element);
        var pixels = new byte[100 * 100 * 4]; bitmap.CopyPixels(pixels, 400, 0); return pixels;
    }
    private static IEnumerable<DependencyObject> Descendants(object? node)
    {
        if (node is not DependencyObject current) yield break;
        yield return current;
        foreach (object child in LogicalTreeHelper.GetChildren(current)) foreach (var item in Descendants(child)) yield return item;
    }
}
