using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodeManager;

public sealed class StateStore
{
    public static readonly JsonSerializerOptions Json = new() { WriteIndented = true, PropertyNameCaseInsensitive = true, IncludeFields = true, Converters = { new JsonStringEnumConverter() } };
    public string Root { get; }
    public string StateFile => Path.Combine(Root, "tasks.json");
    public string EventsDirectory => Path.Combine(Root, "events");
    public string? LoadWarning { get; private set; }
    public StateStore(string? root = null)
    {
        Root = root ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodeManager");
        Directory.CreateDirectory(EventsDirectory);
    }
    public AppState Load()
    {
        if (!File.Exists(StateFile)) return new();
        try
        {
            var result = JsonSerializer.Deserialize<AppState>(File.ReadAllText(StateFile), Json) ?? throw new InvalidDataException("Empty state");
            if (result.SchemaVersion != 1 || result.Slots == null || result.Slots.Count != 9 || result.Slots.Any(s => s == null || string.IsNullOrWhiteSpace(s.Id)) || result.Slots.Select(s => s.Number).OrderBy(n => n).SequenceEqual(Enumerable.Range(1, 9)) == false || result.Slots.Select(s => s.Id).Distinct().Count() != 9)
                throw new InvalidDataException("Invalid task slots");
            result.Layout ??= new();
            result.Preferences ??= new();
            result.Preferences.HideDockOnArrange = false;
            result.RecentTasks ??= new();
            result.RecentTasks = result.RecentTasks.Where(r => r?.Task?.Window != null && !string.IsNullOrWhiteSpace(r.Task.Id) && !result.Slots.Any(s => s.Id == r.Task.Id))
                .DistinctBy(r => r.Task.Id).OrderByDescending(r => r.ClosedAt).Take(30).ToList();
            foreach (var recent in result.RecentTasks) { recent.Task.Number = Math.Clamp(recent.Task.Number, 1, 9); recent.Task.Recovery = null; EquipmentCatalog.EnsureDefaults(new[] { recent.Task }); }
            if (!Enum.IsDefined(result.Preferences.TaskModifiers)) result.Preferences.TaskModifiers = ShortcutModifiers.Alt;
            if (!Enum.IsDefined(result.Preferences.MouseModifiers)) result.Preferences.MouseModifiers = ShortcutModifiers.Alt;
            if (!Enum.IsDefined(result.Preferences.Arrangement)) result.Preferences.Arrangement = ArrangementMode.Balanced;
            if (!Enum.IsDefined(result.Preferences.Skin)) result.Preferences.Skin = Skin.InkJade;
            result.Preferences.SoundVolume = double.IsFinite(result.Preferences.SoundVolume) ? Math.Clamp(result.Preferences.SoundVolume, 0, 1) : .45;
            result.Preferences.DockWidth = double.IsFinite(result.Preferences.DockWidth) ? Math.Clamp(result.Preferences.DockWidth, 210, 620) : 460;
            result.Preferences.DockHeight = double.IsFinite(result.Preferences.DockHeight) ? Math.Clamp(result.Preferences.DockHeight, 0, 1800) : 0;
            result.Preferences.LayoutGap = Math.Clamp(result.Preferences.LayoutGap, 0, 32);
            if (!InputService.TryParseGesture(result.Preferences.ArrangeGesture, out _, out _)) result.Preferences.ArrangeGesture = "Alt+Oem3";
            if (result.Preferences.InventoryGesture != "Tab" && !InputService.TryParseGesture(result.Preferences.InventoryGesture, out _, out _)) result.Preferences.InventoryGesture = "Tab";
            foreach (Slot slot in result.Slots)
            {
                if (!Enum.IsDefined(slot.LaunchMode)) slot.LaunchMode = LaunchMode.Unconfigured;
                if (slot.Recovery != null && !Guid.TryParseExact(slot.Recovery.Token, "N", out _)) slot.Recovery = null;
                slot.Notes ??= ""; slot.ResumeSessionId ??= ""; slot.RecoveryError ??= "";
                slot.LastPlacement ??= slot.CapturePlacement;
                if (slot.Occupied && slot.Name != slot.Window!.Title) slot.CustomName = true;
                if (!System.Text.RegularExpressions.Regex.IsMatch(slot.TagColor ?? "", "^#[0-9A-Fa-f]{6}$")) slot.TagColor = "#7EB5C8";
            }
            result.Slots = result.Slots.OrderBy(s => s.Number).ToList();
            EquipmentCatalog.EnsureDefaults(result.Slots);
            return result;
        }
        catch (Exception ex) when (ex is IOException or JsonException or InvalidDataException or ArgumentException)
        {
            // Preserve the original before a fresh state is ever written.
            var backup = StateFile + ".recovery-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff");
            File.Copy(StateFile, backup, false);
            LoadWarning = "配置读取失败，原文件已备份：" + backup;
            return new();
        }
    }
    public void Save(AppState state) => AtomicWrite(StateFile, JsonSerializer.Serialize(state, Json));
    public void Send(StatusEvent status) => AtomicWrite(Path.Combine(EventsDirectory, Guid.NewGuid().ToString("N") + ".json"), JsonSerializer.Serialize(status, Json));
    public static void AtomicWrite(string path, string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
        try { File.WriteAllText(temporary, content); File.Move(temporary, path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public void Log(string message)
    {
        try { File.AppendAllText(Path.Combine(Root, "app.log"), DateTimeOffset.Now.ToString("O") + " " + message + Environment.NewLine); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
