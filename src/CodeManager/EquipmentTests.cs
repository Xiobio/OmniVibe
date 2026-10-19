using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace CodeManager;

public static class EquipmentTests
{
    public static IEnumerable<SelfTests.Result> Run(string output)
    {
        Directory.CreateDirectory(output);
        var results = new List<SelfTests.Result>();
        var original = WuxiaTheme.CurrentSkin; bool decorations = SkinCatalog.DecorationsEnabled;
        var liveState = new StateStore().StateFile;
        string? liveBefore = File.Exists(liveState) ? File.ReadAllText(liveState) : null;
        string LiveIdentity(string? json) {
            if (json == null) return "";
            var state = JsonSerializer.Deserialize<AppState>(json, StateStore.Json)!;
            return JsonSerializer.Serialize(new {
                state.Preferences,
                Slots = state.Slots.OrderBy(x => x.Number).Select(x => new { x.Id, x.Number, x.Name, x.EquipmentId, x.EquipmentImage, x.EquipmentName, Selections = (x.EquipmentSelections ?? new()).OrderBy(y => y.Key).ToArray(), Handle = x.Window?.Handle, Process = x.Window?.ProcessId })
            }, StateStore.Json);
        }
        string liveIdentityBefore = LiveIdentity(liveBefore);
        string temporary = Path.Combine(Path.GetTempPath(), "OmniVibe-loadout-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(temporary);
        void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
        void Test(string name, Action action) {
            try { action(); results.Add(new(name, true, "OK")); }
            catch (Exception ex) { results.Add(new(name, false, ex.ToString())); }
        }
        var slots = new AppState().Slots;
        foreach (var slot in slots) { slot.Name = "Task " + slot.Number; slot.Window = new() { Handle = slot.Number, ProcessId = 0, Title = slot.Name, ProcessName = "fixture" }; slot.Connected = true; }
        slots[0].IsActive = true;
        try {
            WuxiaTheme.Apply(Skin.Arsenal, false); SkinCatalog.DecorationsEnabled = true;
            Test("Nine distinct HD transparent character cutouts match their provenance manifest", () => {
                var manifest = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "skins/loadouts/naraka/catalog.json")))!;
                var hashes = new HashSet<string>();
                foreach (var slot in slots) {
                    var image = EquipmentCatalog.Image(slot); Check(image != null && image.IsFrozen, "Weapon failed native decoding");
                    var record = manifest["items"]!.AsArray().Single(x => x!["id"]!.GetValue<string>() == slot.EquipmentId)!;
                    var path = Path.Combine(AppContext.BaseDirectory, "skins/loadouts/naraka", record["character_image"]!.GetValue<string>());
                    string hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).ToLowerInvariant();
                    Check(hash == record["character_sha256"]!.GetValue<string>() && record["character_source"]!.GetValue<string>().StartsWith("https://www.narakathegame.com/"), "Source manifest mismatch"); hashes.Add(hash);
                    using var sourceStream = File.OpenRead(path);
                    var originalFrame = BitmapDecoder.Create(sourceStream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
                    Check(originalFrame.PixelWidth >= 1024 && originalFrame.PixelHeight >= 1024, "Low-resolution icon used as source character artwork");
                    var rgba = new FormatConvertedBitmap(image!, PixelFormats.Bgra32, null, 0); var bytes = new byte[rgba.PixelWidth * rgba.PixelHeight * 4]; rgba.CopyPixels(bytes, rgba.PixelWidth * 4, 0);
                    Check(Enumerable.Range(0, bytes.Length / 4).Any(i => bytes[i*4+3] == 0) && Enumerable.Range(0, bytes.Length / 4).Any(i => bytes[i*4+3] > 200), "Missing transparent weapon silhouette");
                }
                Check(hashes.Count == 9 && slots.Select(EquipmentCatalog.Name).Distinct().Count() == 9, "Weapon identities are not distinct");
            });
            Test("Legacy migration and restart preserve task identity and chosen weapon", () => {
                var store = new StateStore(Path.Combine(temporary, "migration")); var state = new AppState();
                state.Slots[0].Window = new() { Handle = 123, ProcessId = 456, Title = "Legacy task" }; state.Slots[0].Name = "Custom task";
                string id = state.Slots[0].Id;
                var legacy = JsonSerializer.SerializeToNode(state, StateStore.Json)!;
                foreach (var node in legacy["Slots"]!.AsArray()) { node!.AsObject().Remove("EquipmentId"); node.AsObject().Remove("EquipmentImage"); node.AsObject().Remove("EquipmentName"); }
                File.WriteAllText(store.StateFile, legacy.ToJsonString()); var loaded = store.Load();
                Check(loaded.Slots.Select(x => x.EquipmentId).Distinct().Count() == 9 && loaded.Slots[0].Id == id && loaded.Slots[0].Window!.Handle == 123, "Legacy migration changed task bindings");
                loaded.Slots[0].EquipmentId = "bow"; loaded.Slots[0].Number = 9; loaded.Slots[8].Number = 1; store.Save(loaded);
                var restarted = store.Load(); Check(restarted.Slots.Single(x => x.Id == id).EquipmentId == "bow" && restarted.Slots.Single(x => x.Id == id).Name == "Custom task", "Restart or renumbering changed equipment");
            });
            Test("Picker is an isolated draft, supports per-slot choices and fixed short-window actions", () => {
                string before = JsonSerializer.Serialize(slots, StateStore.Json);
                var window = new LoadoutWindow(slots, new Native.Rect(0, 0, 2560, 1440)) { Width = 1040, Height = 840, Left = -20000, Top = -20000, Topmost = false, ShowActivated = false };
                try {
                    string untouchedThemeEntity = EquipmentCatalog.Item(slots[1], Skin.Hextech).Id;
                    window.Show(); Pump(); window.SelectSlot(2); window.SelectWeapon("bow");
                    var savedDraft = new Slot { Number = slots[1].Number }; window.Result[slots[1].Id].Apply(savedDraft);
                    Check(EquipmentCatalog.Item(savedDraft, Skin.Arsenal).Id == EquipmentCatalog.Item(new Slot { Number = 7, EquipmentId = "bow" }, Skin.Arsenal).Id && window.Result[slots[0].Id].Id == "katana", "Choice applied to wrong slot");
                    Check(EquipmentCatalog.Item(savedDraft, Skin.Hextech).Id == untouchedThemeEntity, "Selecting Arsenal changed an untouched theme's default entity");
                    Check(JsonSerializer.Serialize(slots, StateStore.Json) == before, "Draft mutated live tasks before acceptance");
                    Capture((FrameworkElement)window.Content, Path.Combine(output, "picker-full.png"));
                    window.Width = 720; window.Height = 470; Pump();
                    var root = (FrameworkElement)window.Content;
                    foreach (string name in new[] { "取消", "保存配装" }) {
                        var button = Nodes(root).OfType<Button>().Single(b => b.Content as string == name);
                        var bounds = button.TransformToAncestor(root).TransformBounds(new Rect(button.RenderSize));
                        Check(bounds.Left >= 0 && bounds.Right <= root.ActualWidth + 1 && bounds.Bottom <= root.ActualHeight + 1, "Short window clipped save/cancel");
                    }
                    foreach (var scroll in Nodes(root).OfType<ScrollViewer>()) { scroll.ScrollToEnd(); Pump(); Check(scroll.VerticalOffset > 0, "Weapon or slot list cannot scroll on short screen"); }
                    Capture(root, Path.Combine(output, "picker-short-scrolled.png"));
                } finally { window.Close(); }
                Check(JsonSerializer.Serialize(slots, StateStore.Json) == before, "Closing picker committed a draft");
            });
            Test("Custom import survives original removal; missing, corrupt and unsafe files fall back", () => {
                string source = Path.Combine(temporary, "portrait.png");
                var pixels = new byte[64 * 64 * 4]; Random.Shared.NextBytes(pixels); for (int i = 3; i < pixels.Length; i += 4) pixels[i] = 255;
                var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(BitmapSource.Create(64, 64, 96, 96, PixelFormats.Bgra32, null, pixels, 64*4)));
                using (var file = File.Create(source)) encoder.Save(file);
                string managed = EquipmentCatalog.Import(source); string managedPath = Path.Combine(EquipmentCatalog.CustomRoot, managed);
                try {
                    File.Delete(source); var slot = new Slot { Number = 1, EquipmentId = "katana", EquipmentImage = managed, EquipmentName = "My portrait" };
                    Check(EquipmentCatalog.Image(slot)?.PixelWidth == 64 && EquipmentCatalog.Name(slot) == "My portrait" && !EquipmentCatalog.CustomMissing(slot), "Imported portrait depends on its original file");
                    var store = new StateStore(Path.Combine(temporary, "custom")); var state = new AppState(); EquipmentAssignment.From(slot).Apply(state.Slots[0]); store.Save(state);
                    Check(EquipmentAssignment.From(store.Load().Slots[0]) == EquipmentAssignment.From(slot), "Custom image/name did not persist");
                    var expected = EquipmentCatalog.Image(new Slot { Number = 1, EquipmentId = "katana" });
                    foreach (string bad in new[] { "missing-file.png", "../portrait.png", "https://example.com/image.png", "C:\\other\\image.png" }) {
                        slot.EquipmentImage = bad; Check(ReferenceEquals(expected, EquipmentCatalog.Image(slot)) && EquipmentCatalog.CustomMissing(slot), "Unsafe or missing file did not fall back");
                    }
                    string corrupt = Path.Combine(temporary, "corrupt.png"); File.WriteAllText(corrupt, "not an image");
                    bool rejected = false; try { EquipmentCatalog.Import(corrupt); } catch (InvalidDataException) { rejected = true; }
                    Check(rejected, "Corrupt image accepted"); slot.EquipmentId = "future-pack-item"; slot.EquipmentImage = "";
                    Check(EquipmentCatalog.Image(slot) != null && slot.EquipmentId == "future-pack-item", "Unknown item lost data or failed to render fallback");
                } finally { File.Delete(managedPath); }
            });
            Test("Resting 116-DIP core is contained and weapon identity ignores task titles", () => {
                var wheel = new DockWeaponWheel(); wheel.SetSlots(slots); wheel.Deploy(false, false);
                var window = Host(wheel, 116);
                try {
                    window.Show(); Pump(); var before = Capture(wheel, Path.Combine(output, "core-116.png"));
                    Check(before[(58*116+8)*4+3] == 0 && before[(58*116+108)*4+3] == 0, "The removed circular chassis or backdrop returned beside the character");
                    Check(wheel.InCore(wheel.Centre + new Vector(50, 50)), "Visible character corners cannot be grabbed or opened");
                    slots[0].Name = "A completely different terminal title"; Pump();
                    Check(before.SequenceEqual(Capture(wheel)), "Core still depends on terminal initials or names");
                    wheel.Hover(slots[1]); Pump(); Check(before.SequenceEqual(Capture(wheel)), "Hover replaced the actual current weapon");
                    var hashes = new HashSet<string>();
                    for (int i = 0; i < 9; i++) {
                        foreach (var slot in slots) { slot.IsActive = slot.Number == i + 1; slot.Refresh(); }
                        Pump(); var bytes = Capture(wheel, Path.Combine(output, "core-" + (i+1) + ".png")); hashes.Add(Convert.ToHexString(SHA256.HashData(bytes)));
                        for (int y = 0; y < 116; y++) for (int x = 0; x < 116; x++) if (x < 3 || y < 3 || x > 112 || y > 112) Check(bytes[(y*116+x)*4+3] == 0, "Character painted beyond resting host boundary");
                        Check(bytes[3] == 0 && bytes[115*4+3] == 0, "Character gained an opaque backdrop");
                    }
                    Check(hashes.Count == 9, "Different equipped weapons have identical core portraits");
                } finally { window.Close(); }
            });
            Test("Reordering a task preserves the remembered current entity after focus leaves managed terminals", () => {
                var fixture = new AppState().Slots;
                foreach (var slot in fixture) { slot.Window = new() { Handle = slot.Number, ProcessId = 0, Title = "Task " + slot.Number }; slot.Connected = true; }
                var wheel = new DockWeaponWheel(); wheel.SetSlots(fixture); wheel.Pulse(fixture[3], false);
                string equipped = fixture[3].Id; var image = EquipmentCatalog.Image(fixture[3]);
                Check(wheel.CurrentSlot?.Id == equipped, "A freshly equipped task was not remembered");
                (fixture[3].Number, fixture[7].Number) = (fixture[7].Number, fixture[3].Number); wheel.SetSlots(fixture);
                Check(wheel.CurrentSlot?.Id == equipped && ReferenceEquals(image, EquipmentCatalog.Image(wheel.CurrentSlot!)), "Slot renumbering replaced the remembered task or entity");
                fixture[3].Connected = false; fixture[3].Window = null; fixture[3].Refresh();
                Check(wheel.CurrentSlot?.Id != equipped, "A removed task remained equipped");
            });
            Test("All nine deployed weapons retain fixed hit positions at 320, 360 and 480 DIP", () => {
                foreach (int size in new[] { 320, 360, 480 }) {
                    var wheel = new DockWeaponWheel(); wheel.SetSlots(slots); wheel.Deploy(true, false); var window = Host(wheel, size);
                    try {
                        window.Show(); Pump();
                        foreach (var slot in slots) {
                            Check(wheel.HitSlot(wheel.SlotPoint(slot.Number)) == slot, "Weapon hit mapping changed");
                            wheel.Hover(slot); Point remove = wheel.RemovePoint(slot);
                            Check(wheel.HitRemove(remove) == slot && remove.X >= 11 && remove.Y >= 11 && remove.X <= size-11 && remove.Y <= size-11, "Subtle removal target is unreachable or clipped");
                        }
                        wheel.Hover(null); Capture(wheel, Path.Combine(output, "deck-" + size + ".png"));
                    }
                    finally { window.Close(); }
                }
            });
            Test("Empty slots visibly offer direct add targets without moving existing task positions", () => {
                var sparse = new AppState().Slots;
                sparse[0].Window = new() { Handle = 1, Title = "Task" }; sparse[0].Connected = true; sparse[0].IsActive = true;
                var wheel = new DockWeaponWheel(); wheel.SetSlots(sparse); wheel.Deploy(true, false); var window = Host(wheel, 360);
                try {
                    window.Show(); Pump(); var bytes = Capture(wheel, Path.Combine(output, "sparse-360.png"));
                    foreach (var slot in sparse.Skip(1)) {
                        Point p = wheel.SlotPoint(slot.Number); Check(wheel.HitSlot(p) == slot, "Visible plus slot cannot be clicked");
                        int x = (int)p.X, y = (int)p.Y;
                        Check(bytes[(y*360+x)*4+3] > 0, "Empty slot has no visible add affordance");
                        Check(wheel.HitSlot(p, duringCapture: true) == slot, "Capture cannot address an empty slot");
                    }
                    var activePoint = wheel.SlotPoint(1); wheel.CaptureTargetsVisible = true; Pump();
                    foreach (var slot in sparse) Check(wheel.HitSlot(wheel.SlotPoint(slot.Number)) == slot, "Drag capture lost fixed target positions");
                    Capture(wheel, Path.Combine(output, "capture-360.png")); wheel.CaptureTargetsVisible = false; Pump();
                    Check(wheel.SlotPoint(1) == activePoint && bytes.SequenceEqual(Capture(wheel)), "Hiding empty targets moved existing tasks or left painted targets");
                    sparse[0].Window = null; sparse[0].IsActive = false; sparse[0].Connected = false; sparse[0].Refresh(); Pump();
                    Check(wheel.CurrentSlot == null, "An empty slot remained equipped"); Capture(wheel, Path.Combine(output, "empty-360.png"));
                } finally { window.Close(); }
            });
            Test("Every theme has nine distinct readable entities with explicit provenance", () => {
                foreach (var skin in SkinCatalog.All) {
                    Check(EquipmentCatalog.HasPack(skin.Id), skin.Name + " has no dedicated content pack");
                    var pack = EquipmentCatalog.Pack(skin.Id); Check(pack.Items.Count == 9 && pack.Items.Select(x => x.Id).Distinct().Count() == 9 && pack.Items.Select(x => x.Name).Distinct().Count() == 9, skin.Name + " has repeated identity labels");
                    var hashes = new HashSet<string>();
                    foreach (var item in pack.Items) {
                        string path = Path.GetFullPath(Path.Combine(EquipmentCatalog.SuiteRoot, item.Portrait));
                        Check(File.Exists(path), skin.Name + ": missing " + item.Portrait);
                        hashes.Add(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))));
                        var sample = new Slot { Number = 1, EquipmentId = item.Id };
                        var image = EquipmentCatalog.Image(sample, skin.Id);
                        Check(image is { IsFrozen: true } && Math.Max(image.PixelWidth, image.PixelHeight) >= 64, skin.Name + ": runtime entity is unreadable");
                        using var stream = File.OpenRead(path); var originalFrame = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None).Frames[0];
                        Check(Math.Max(originalFrame.PixelWidth, originalFrame.PixelHeight) >= 512, skin.Name + ": source entity is too small");
                        Check(item.Provenance.Length > 0, skin.Name + ": source type is not disclosed");
                    }
                    Check(hashes.Count == 9, skin.Name + " reuses the same picture across multiple slots");
                }
            });
            Test("Theme loadouts remain independent and equipment assignment copies value semantics", () => {
                var slot = new Slot { Number = 2, EquipmentId = "greatsword" };
                var first = EquipmentCatalog.ForSkin(Skin.Hextech)[4]; var second = EquipmentCatalog.ForSkin(Skin.Astral)[6];
                slot.EquipmentSelections[Skin.Hextech.ToString()] = first.Id; slot.EquipmentSelections[Skin.Astral.ToString()] = second.Id;
                Check(EquipmentCatalog.Item(slot, Skin.Hextech).Id == first.Id && EquipmentCatalog.Item(slot, Skin.Astral).Id == second.Id, "Switching theme overwrote another theme's entity");
                var assigned = EquipmentAssignment.From(slot); var copy = new Slot { Number = 8 }; assigned.Apply(copy);
                Check(EquipmentAssignment.From(copy) == assigned && !ReferenceEquals(copy.EquipmentSelections, slot.EquipmentSelections), "Equipment map has reference equality or a shared mutable dictionary");
                var store = new StateStore(Path.Combine(temporary, "suite-map")); var state = new AppState(); assigned.Apply(state.Slots[0]); store.Save(state);
                Check(EquipmentAssignment.From(store.Load().Slots[0]) == assigned, "Theme-specific choices did not survive restart");
                slot.EquipmentImage = "missing-custom.png"; slot.EquipmentName = "My custom name";
                Check(EquipmentCatalog.Name(slot, Skin.Astral) == "My custom name" && EquipmentCatalog.CustomMissing(slot), "Custom identity did not survive changing a theme");
            });
            Test("All theme entities render with fixed targets and no task initials, with decorations on or off", () => {
                foreach (var skin in SkinCatalog.All) foreach (bool decorated in new[] { true, false }) {
                    WuxiaTheme.Apply(skin.Id, false); SkinCatalog.DecorationsEnabled = decorated;
                    var wheel = new DockWeaponWheel(); wheel.SetSlots(slots); wheel.Deploy(true, false); var window = Host(wheel, 360);
                    try {
                        window.Show(); Pump(); foreach (var slot in slots) Check(wheel.HitSlot(wheel.SlotPoint(slot.Number)) == slot, skin.Name + " lost a fixed hit target");
                        var before = Capture(wheel, Path.Combine(output, "suite-" + skin.Slug + (decorated ? "-decorated" : "-plain") + ".png"));
                        slots[0].Name = "A new process title " + Guid.NewGuid().ToString("N"); slots[0].Refresh(); Pump();
                        Check(before.SequenceEqual(Capture(wheel)), skin.Name + " still paints task initials instead of the chosen entity");
                    } finally { window.Close(); }
                }
            });
            Test("Loadout validation preserves live window bindings, appearance and preferences", () => Check(liveIdentityBefore == LiveIdentity(File.Exists(liveState) ? File.ReadAllText(liveState) : null), "Live task bindings, appearance or preferences changed during validation"));
        } finally { WuxiaTheme.Apply(original, false); SkinCatalog.DecorationsEnabled = decorations; Directory.Delete(temporary, true); }
        return results;
    }
    private static Window Host(FrameworkElement element, int size) => new() { WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, Width = size, Height = size, Content = element, Left = -20000, Top = -20000, ShowActivated = false, ShowInTaskbar = false };
    private static void Pump() { Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle); }
    private static byte[] Capture(FrameworkElement element, string? path = null) {
        element.UpdateLayout(); int w = (int)Math.Round(element.ActualWidth), h = (int)Math.Round(element.ActualHeight);
        var bitmap = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32); bitmap.Render(element);
        if (Window.GetWindow(element)?.Background is Brush background) {
            var backdrop = new DrawingVisual(); using (var dc = backdrop.RenderOpen()) dc.DrawRectangle(background, null, new Rect(0, 0, w, h));
            bitmap = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32); bitmap.Render(backdrop); bitmap.Render(element);
        }
        var bytes = new byte[w*h*4]; bitmap.CopyPixels(bytes, w*4, 0);
        if (path != null) { var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var file = File.Create(path); encoder.Save(file); }
        return bytes;
    }
    private static IEnumerable<DependencyObject> Nodes(object? root) {
        if (root is not DependencyObject node) yield break; yield return node;
        foreach (object child in LogicalTreeHelper.GetChildren(node)) foreach (var descendant in Nodes(child)) yield return descendant;
    }
}
