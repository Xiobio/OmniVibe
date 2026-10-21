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
        LoadWarning = null;
        if (!File.Exists(StateFile)) return new();
        try
        {
            var result = JsonSerializer.Deserialize<AppState>(File.ReadAllText(StateFile), Json) ?? throw new InvalidDataException("Empty state");
            if (result.SchemaVersion != 1 || result.Slots == null || result.Slots.Count != 9 || result.Slots.Any(s => s == null || string.IsNullOrWhiteSpace(s.Id)) || result.Slots.Select(s => s.Number).OrderBy(n => n).SequenceEqual(Enumerable.Range(1, 9)) == false || result.Slots.Select(s => s.Id).Distinct().Count() != 9)
                throw new InvalidDataException("Invalid task slots");
            result.Layout ??= new();
            result.Preferences ??= new();
            bool repaired = false;
            foreach (var slot in result.Slots) repaired |= NormalizeSlot(slot);
            repaired |= result.Layout.RemoveAll(entry => entry == null || entry.Window == null || string.IsNullOrWhiteSpace(entry.SlotId)) > 0;
            foreach (var entry in result.Layout) repaired |= NormalizeWindow(entry.Window);
            if (result.Popup is { } popup)
            {
                if (popup.Window == null || string.IsNullOrWhiteSpace(popup.SlotId)) { result.Popup = null; repaired = true; }
                else { repaired |= NormalizeWindow(popup.Window); if (popup.PreviousFocus != null) repaired |= NormalizeWindow(popup.PreviousFocus); }
            }
            result.Preferences.HideDockOnArrange = false;
            result.RecentTasks ??= new();
            result.RecentTasks = result.RecentTasks.Where(r => r?.Task?.Window != null && !string.IsNullOrWhiteSpace(r.Task.Id) && !result.Slots.Any(s => s.Id == r.Task.Id))
                .DistinctBy(r => r.Task.Id).OrderByDescending(r => r.ClosedAt).Take(30).ToList();
            foreach (var recent in result.RecentTasks) { repaired |= NormalizeSlot(recent.Task); recent.Task.Number = Math.Clamp(recent.Task.Number, 1, 9); recent.Task.Recovery = null; EquipmentCatalog.EnsureDefaults(new[] { recent.Task }); }
            if (!Enum.IsDefined(result.Preferences.TaskModifiers)) result.Preferences.TaskModifiers = ShortcutModifiers.Alt;
            if (!Enum.IsDefined(result.Preferences.MouseModifiers)) result.Preferences.MouseModifiers = ShortcutModifiers.Alt;
            if (!Enum.IsDefined(result.Preferences.Arrangement)) result.Preferences.Arrangement = ArrangementMode.Balanced;
            if (!Enum.IsDefined(result.Preferences.Skin)) result.Preferences.Skin = Skin.Relic;
            if (result.Preferences.Language is not ("auto" or "en" or "zh-CN")) result.Preferences.Language = "auto";
            if (result.Preferences.SoundTheme is Skin soundTheme && !Enum.IsDefined(soundTheme)) result.Preferences.SoundTheme = null;
            result.Preferences.SoundVolume = double.IsFinite(result.Preferences.SoundVolume) ? Math.Clamp(result.Preferences.SoundVolume, 0, 1) : .45;
            result.Preferences.DockWidth = double.IsFinite(result.Preferences.DockWidth) ? Math.Clamp(result.Preferences.DockWidth, 210, 620) : 460;
            result.Preferences.DockHeight = double.IsFinite(result.Preferences.DockHeight) ? Math.Clamp(result.Preferences.DockHeight, 0, 1800) : 0;
            result.Preferences.LayoutGap = Math.Clamp(result.Preferences.LayoutGap, 0, 32);
            result.Preferences.ToggleGesture ??= "Ctrl+Alt+Space";
            result.Preferences.ArrangeGesture ??= "Alt+Oem3";
            result.Preferences.InventoryGesture ??= "Tab";
            result.Preferences.RadialGesture ??= "Alt+Q";
            if (!string.IsNullOrWhiteSpace(result.Preferences.ArrangeGesture) && !InputService.TryParseGesture(result.Preferences.ArrangeGesture, out _, out _)) result.Preferences.ArrangeGesture = "Alt+Oem3";
            if (!string.IsNullOrWhiteSpace(result.Preferences.InventoryGesture) && !InputService.TryParseGesture(result.Preferences.InventoryGesture, out _, out _)) result.Preferences.InventoryGesture = "Tab";
            result.Preferences.TaskGestures ??= new();
            foreach (int number in result.Preferences.TaskGestures.Keys.ToArray())
                if (number is < 1 or > 9 || result.Preferences.TaskGestures[number] is not string value || value != "" && !InputService.TryParseGesture(value, out _, out _)) result.Preferences.TaskGestures.Remove(number);
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
            if (repaired) LoadWarning = L.T("配置含有无效字段，已修复并保留原文件：") + BackupOriginal();
            return result;
        }
        catch (Exception ex) when (ex is IOException or JsonException or InvalidDataException or ArgumentException)
        {
            // Preserve the original before a fresh state is ever written.
            var backup = BackupOriginal();
            LoadWarning = L.T("配置读取失败，原文件已备份：") + backup;
            return new();
        }
    }
    private string BackupOriginal()
    {
        string backup = StateFile + ".recovery-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + "-" + Guid.NewGuid().ToString("N")[..8];
        File.Copy(StateFile, backup, false);
        return backup;
    }
    private static bool NormalizeWindow(WindowIdentity window)
    {
        bool repaired = window.Title == null || window.ProcessName == null;
        window.Title ??= ""; window.ProcessName ??= "";
        return repaired;
    }
    private static bool NormalizeSlot(Slot slot)
    {
        bool repaired = slot.Name == null || slot.ProjectDirectory == null || slot.AgentProvider == null || slot.SessionId == null ||
            slot.Message == null || slot.StateSource == null || slot.Notes == null || slot.ResumeSessionId == null || slot.RecoveryError == null || !Enum.IsDefined(slot.State);
        slot.Name ??= ""; slot.ProjectDirectory ??= ""; slot.AgentProvider ??= ""; slot.SessionId ??= "";
        slot.Message ??= ""; slot.StateSource ??= ""; slot.Notes ??= ""; slot.ResumeSessionId ??= ""; slot.RecoveryError ??= "";
        if (!Enum.IsDefined(slot.State)) slot.State = AgentState.Unknown;
        if (slot.Window != null) repaired |= NormalizeWindow(slot.Window);
        return repaired;
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
