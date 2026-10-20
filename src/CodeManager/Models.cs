using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace CodeManager;

public enum AgentState { Unknown, Running, Waiting, Ready, Error }
public enum WakeMode { LastPosition, WorkArea }
public enum ArrangementMode { Balanced, Columns, Rows, MainLeft }
public enum Skin { InkJade = 0, Midnight = 1, Cinnabar = 2, Hextech, Tactical, Protocol, Adventure, Arsenal, Relic, Starlight, Formation, Astral, Wonderland }
public enum LaunchMode { Unconfigured, Terminal, Claude, Codex }
[Flags]
public enum ShortcutModifiers { Alt = 1, Ctrl = 2, CtrlAlt = 3, Shift = 4, AltShift = 5, CtrlShift = 6, CtrlAltShift = 7, Win = 8, WinAlt = 9, WinCtrl = 10, WinCtrlAlt = 11, WinShift = 12, WinAltShift = 13, WinCtrlShift = 14, WinCtrlAltShift = 15 }

public sealed class Preferences
{
    public ShortcutModifiers TaskModifiers { get; set; } = ShortcutModifiers.Alt;
    public ShortcutModifiers MouseModifiers { get; set; } = ShortcutModifiers.Alt;
    public Dictionary<int, string> TaskGestures { get; set; } = new();
    public bool WheelSwitchEnabled { get; set; } = true;
    public bool HasSeenIntroduction { get; set; }
    public string ToggleGesture { get; set; } = "Ctrl+Alt+Space";
    public string ArrangeGesture { get; set; } = "Alt+Oem3";
    public string InventoryGesture { get; set; } = "Tab";
    public string RadialGesture { get; set; } = "Alt+Q";
    public ArrangementMode Arrangement { get; set; }
    public int LayoutGap { get; set; }
    public bool HideDockOnArrange { get; set; }
    public Skin Skin { get; set; }
    public double DockWidth { get; set; } = 360;
    public Native.Point? RingCentre { get; set; }
    public double DockHeight { get; set; }
    public bool FreeDockPosition { get; set; }
    public Native.Point DockPosition { get; set; }
    public bool TabTogglesInventory { get; set; } = true;
    public WakeMode WakeMode { get; set; } = WakeMode.LastPosition;
    public bool Compact { get; set; } = true;
    public bool Animate { get; set; } = true;
    public bool DecorationsEnabled { get; set; } = true;
    public bool SoundEffects { get; set; } = true;
    public Skin? SoundTheme { get; set; }
    public double SoundVolume { get; set; } = .45;
    public bool ImmersiveAudio { get; set; } = true;
    public bool SoundNotifications { get; set; } = true;
    public bool ShowRecoveryOnStartup { get; set; } = true;
    public bool AutoReconnectExisting { get; set; } = true;
    public bool AutoRestoreOnStartup { get; set; }
    public bool HasDockAnchor { get; set; }
    public Native.Point DockAnchor { get; set; }
    public static string ModifierLabel(ShortcutModifiers modifiers) => string.Join("+", new[] { ((int)modifiers & 2) != 0 ? "Ctrl" : null, ((int)modifiers & 1) != 0 ? "Alt" : null, ((int)modifiers & 4) != 0 ? "Shift" : null, ((int)modifiers & 8) != 0 ? "Win" : null }.Where(x => x != null));
    public string TaskGesture(int number) => TaskGestures != null && TaskGestures.TryGetValue(number, out string? gesture) ? gesture ?? "" : ModifierLabel(TaskModifiers) + "+" + number;
    public Preferences Copy() { var result = (Preferences)MemberwiseClone(); result.TaskGestures = new(TaskGestures ?? new()); return result; }
}

public sealed class WindowIdentity
{
    public long Handle { get; set; }
    public int ProcessId { get; set; }
    public long ProcessStartedUtcTicks { get; set; }
    public string ProcessName { get; set; } = "";
    public string Title { get; set; } = "";
}

public sealed class Slot : INotifyPropertyChanged
{
    public int Number { get; set; }
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string EquipmentId { get; set; } = "";
    public string EquipmentImage { get; set; } = "";
    public string EquipmentName { get; set; } = "";
    public Dictionary<string, string> EquipmentSelections { get; set; } = new();
    private string _name = "";
    public string Name { get => _name; set { _name = value; Changed(); Changed(nameof(DisplayName)); } }
    public WindowIdentity? Window { get; set; }
    public Native.Placement? CapturePlacement { get; set; }
    public Native.Placement? LastPlacement { get; set; }
    public bool CustomName { get; set; }
    public string TagColor { get; set; } = "#7EB5C8";
    public string ProjectDirectory { get; set; } = "";
    public string AgentProvider { get; set; } = "";
    public string SessionId { get; set; } = "";
    public bool IntegrationConnected { get; set; }
    public LaunchMode LaunchMode { get; set; }
    public string ResumeSessionId { get; set; } = "";
    public bool ResumeConversation { get; set; } = true;
    public string Notes { get; set; } = "";
    public DateTimeOffset? LastSeenAt { get; set; }
    public PendingRecovery? Recovery { get; set; }
    public string RecoveryError { get; set; } = "";
    public bool ParkedByApp { get; set; }
    private AgentState _state;
    public AgentState State { get => _state; set { _state = value; Refresh(); } }
    private bool _unread;
    public bool Unread { get => _unread; set { _unread = value; Refresh(); } }
    public string Message { get; set; } = "";
    public DateTimeOffset? UpdatedAt { get; set; }
    public string StateSource { get; set; } = "";
    [JsonIgnore] public bool Connected { get; set; }
    [JsonIgnore] public bool IsActive { get; set; }
    [JsonIgnore] public bool IsSelected { get; set; }
    [JsonIgnore] public bool IsDropTarget { get; set; }
    [JsonIgnore] public bool IsDisplayed { get; set; } = true;
    [JsonIgnore] public bool JustCaptured { get; set; }
    [JsonIgnore] public bool Occupied => Window != null;
    [JsonIgnore] public string DisplayName => Occupied ? (string.IsNullOrWhiteSpace(Name) ? Window!.Title : Name) : "拖入窗口";
    [JsonIgnore] public string ToolName => Window?.ProcessName.ToLowerInvariant() switch
    {
        "windowsterminal" or "windowsterminalpreview" => "Windows Terminal",
        "cmd" => "CMD", "powershell" => "PowerShell", "pwsh" => "PowerShell 7",
        "openconsole" or "conhost" => "Console", null => "空槽位", _ => Window.ProcessName
    };
    [JsonIgnore] public string StateLabel => !Occupied ? "拖入或点击添加" : !Connected ? "已断开 · 点击重连" : State switch
    { AgentState.Running => "正在执行", AgentState.Waiting => "等待你处理", AgentState.Ready => "本轮已回复", AgentState.Error => "发生错误", _ => "状态未知" };
    [JsonIgnore] public string StateColor => !Connected ? SkinCatalog.Current.Unknown : State switch
    { AgentState.Running => SkinCatalog.Current.Running, AgentState.Waiting => SkinCatalog.Current.Waiting, AgentState.Ready => SkinCatalog.Current.Ready, AgentState.Error => SkinCatalog.Current.Error, _ => SkinCatalog.Current.Unknown };
    [JsonIgnore] public string StatusGlyph => !Occupied ? "+" : !Connected ? "↺" : State switch
    { AgentState.Running => "▶", AgentState.Waiting => "Ⅱ", AgentState.Ready => "✓", AgentState.Error => "!", _ => "?" };
    [JsonIgnore] public string SurfaceColor => IsDropTarget || IsSelected || IsActive ? SkinCatalog.Current.Elevated : SkinCatalog.Current.Surface;
    [JsonIgnore] public string OutlineColor => IsDropTarget || IsSelected ? SkinCatalog.Current.Accent : JustCaptured || IsActive ? SkinCatalog.Current.Running : SkinCatalog.Current.Border;
    [JsonIgnore] public string NumberColor => IsSelected ? SkinCatalog.Current.Accent : IsDropTarget || IsActive ? SkinCatalog.Current.Running : Unread && Connected ? StateColor : SkinCatalog.Current.Muted;
    [JsonIgnore] public string ActivityColor => IsSelected ? SkinCatalog.Current.Accent : IsActive ? SkinCatalog.Current.Running : StateColor;
    [JsonIgnore] public string Detail => IsDropTarget ? Occupied ? "松手调整任务顺序" : "松手收纳到这个槽位" : JustCaptured ? "已收录 · 右键可编辑任务" : Occupied ? !IntegrationConnected && State == AgentState.Unknown ? "未接入自动状态 · 右键连接" : (AgentProvider == "" ? ToolName : AgentProvider == "claude" ? "Claude Code" : "Codex") + " · " + StateLabel : StateLabel;
    [JsonIgnore] public string IntegrationLabel => (IntegrationConnected ? "已接入 " + (AgentProvider == "claude" ? "Claude Code" : "Codex") : "未接入 / 会话已结束") + (UpdatedAt.HasValue ? "\n最近事件：" + UpdatedAt.Value.ToLocalTime().ToString("MM-dd HH:mm:ss") + " · " + StateLabel + "\n来源：" + StateSource : "\n尚未收到任务状态事件");
    [JsonIgnore] public string ActivityLabel => IsSelected ? "选择" : IsActive ? "当前" : Unread && Connected ? "新" : "";
    [JsonIgnore] public string ProjectLabel => string.IsNullOrWhiteSpace(ProjectDirectory) ? "" : System.IO.Path.GetFileName(ProjectDirectory.TrimEnd('\\', '/'));
    [JsonIgnore] public string Inscription => SkinCatalog.Current.SlotNumber(Number);
    [JsonIgnore] public string WuxiaStateLabel => !Occupied ? "空阵眼" : !Connected ? "已断开 · 待重连" : State switch { AgentState.Running => "运转中", AgentState.Waiting => "候君决断", AgentState.Ready => "本轮已回复", AgentState.Error => "阵法崩坏 · 发生错误", _ => "状态未知" };
    [JsonIgnore] public string Tooltip => DisplayName + "\n" + (Window?.Title ?? "空槽位") + (ProjectDirectory == "" ? "" : "\n" + ProjectDirectory) + "\n" + StateLabel + "\n" + (IntegrationConnected ? "已连接 " + AgentProvider + " 状态事件" : "未连接自动状态") + (Message == "" ? "" : "\n" + Message);
    [JsonIgnore] public string RecoveryLabel => Recovery != null ? "正在打开并重连…" : Connected ? "窗口已连接" : RecoveryError != "" ? RecoveryError : RecoveryLaunch.Validation(this) is string error ? error : "可以恢复 · " + (LaunchMode == LaunchMode.Terminal ? "项目终端" : LaunchMode == LaunchMode.Claude ? "Claude Code" : "Codex") + (ResumeConversation && LaunchMode != LaunchMode.Terminal ? " · 原会话" : "");
    [JsonIgnore] public string RecoveryDetails => (ProjectDirectory == "" ? "项目目录未记录" : ProjectDirectory) + (LastSeenAt.HasValue ? "\n上次在线 " + LastSeenAt.Value.ToLocalTime().ToString("MM-dd HH:mm") : "") + (Notes == "" ? "" : "\n备忘：" + Notes) + (Message == "" ? "" : "\n上次状态：" + Message);
    public event PropertyChangedEventHandler? PropertyChanged;
    public void Refresh() => Changed("");
    private void Changed([CallerMemberName] string? property = null) => PropertyChanged?.Invoke(this, new(property));
}

public sealed class PendingRecovery
{
    public string Token { get; set; } = "";
    public DateTimeOffset StartedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class LayoutEntry
{
    public string SlotId { get; set; } = "";
    public WindowIdentity Window { get; set; } = new();
    public Native.Placement Placement { get; set; } = new();
    public bool ParkedByApp { get; set; }
}

public sealed class AppState
{
    public int SchemaVersion { get; set; } = 1;
    public List<Slot> Slots { get; set; } = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, EquipmentId = EquipmentCatalog.Default(n).Id }).ToList();
    public List<ClosedTaskRecord> RecentTasks { get; set; } = new();
    public bool AutoHide { get; set; }
    public bool MinimizeOnCapture { get; set; } = true;
    public List<LayoutEntry> Layout { get; set; } = new();
    public bool? DockVisibleBeforeLayout { get; set; }
    public PopupEntry? Popup { get; set; }
    public Preferences Preferences { get; set; } = new();
}

public sealed class ClosedTaskRecord
{
    public Slot Task { get; set; } = new();
    public DateTimeOffset ClosedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PopupEntry
{
    public string SlotId { get; set; } = "";
    public WindowIdentity Window { get; set; } = new();
    public Native.Placement Placement { get; set; }
    public bool ParkedByApp { get; set; }
    public WindowIdentity? PreviousFocus { get; set; }
}

public sealed class StatusEvent
{
    public string TaskId { get; set; } = "";
    public AgentState State { get; set; }
    public string Message { get; set; } = "";
    public DateTimeOffset At { get; set; } = DateTimeOffset.UtcNow;
    public string Provider { get; set; } = "";
    public string SessionId { get; set; } = "";
    public string ProjectDirectory { get; set; } = "";
    public string SuggestedName { get; set; } = "";
    public bool SessionEnded { get; set; }
    public string EventName { get; set; } = "";
}

public readonly record struct Cell(int X, int Y, int Width, int Height);

public readonly record struct MouseGesture(bool Consume, int WheelDelta = 0, bool MaskAlt = false);

public sealed class MouseGestureRouter
{
    private bool _altUsed;
    public static bool AltOnly(bool alt, bool ctrl, bool shift, bool windows) => alt && !ctrl && !shift && !windows;
    public static bool Matches(ShortcutModifiers modifiers, bool alt, bool ctrl, bool shift, bool windows) => ((alt ? 1 : 0) | (ctrl ? 2 : 0) | (shift ? 4 : 0) | (windows ? 8 : 0)) == (int)modifiers;
    public MouseGesture Route(int message, bool altOnly, int wheelDelta = 0)
    {
        if (!altOnly) return default;
        if (message == 0x20A && wheelDelta != 0)
        {
            bool mask = !_altUsed; _altUsed = true;
            return new(true, wheelDelta, MaskAlt: mask);
        }
        return default;
    }
    public void AltReleased() => _altUsed = false;
}

public static class WindowLayout
{
    public static Cell Clamp(Cell cell, Native.Rect area)
    {
        int width = Math.Clamp(cell.Width, 1, Math.Max(1, area.Right - area.Left));
        int height = Math.Clamp(cell.Height, 1, Math.Max(1, area.Bottom - area.Top));
        return new(Math.Clamp(cell.X, area.Left, area.Right - width), Math.Clamp(cell.Y, area.Top, area.Bottom - height), width, height);
    }
    public static bool Same(Native.Placement left, Native.Placement right) => left.ShowCommand == right.ShowCommand && left.NormalPosition.Left == right.NormalPosition.Left && left.NormalPosition.Top == right.NormalPosition.Top && left.NormalPosition.Right == right.NormalPosition.Right && left.NormalPosition.Bottom == right.NormalPosition.Bottom;
}

public static class Tiling
{
    public static List<Cell> Arrange(int count, Native.Rect area, ArrangementMode mode = ArrangementMode.Balanced, int gap = 0)
    {
        if (count < 1 || count > 9) throw new ArgumentOutOfRangeException(nameof(count));
        int width = Math.Max(1, area.Right - area.Left);
        int height = Math.Max(1, area.Bottom - area.Top);
        if (mode == ArrangementMode.MainLeft && count > 1)
        {
            int split = area.Left + width * 3 / 5;
            var result = new List<Cell> { new(area.Left, area.Top, split - area.Left, height) };
            result.AddRange(Arrange(count - 1, new(split, area.Top, area.Right, area.Bottom), ArrangementMode.Rows));
            return Inset(result, gap);
        }
        int cols = mode == ArrangementMode.Columns ? count : mode == ArrangementMode.Rows ? 1 : count == 1 ? 1 : count <= 4 ? 2 : 3;
        int rows = (count + cols - 1) / cols;
        var cells = new List<Cell>();
        for (int i = 0; i < count; i++)
        {
            int row = i / cols, col = i % cols;
            int rowCount = Math.Min(cols, count - row * cols);
            int left = area.Left + width * col / rowCount, right = area.Left + width * (col + 1) / rowCount;
            int top = area.Top + height * row / rows, bottom = area.Top + height * (row + 1) / rows;
            cells.Add(new(left, top, Math.Max(1, right - left), Math.Max(1, bottom - top)));
        }
        return Inset(cells, gap);
    }
    private static List<Cell> Inset(List<Cell> cells, int gap) => cells.Select(c => { int g = Math.Clamp(gap, 0, Math.Max(0, Math.Min(c.Width, c.Height) - 1)); return new Cell(c.X + g / 2, c.Y + g / 2, c.Width - g, c.Height - g); }).ToList();
}

public sealed class WheelSelection
{
    private int _remainder;
    public int? Selected { get; private set; }
    public bool Active { get; private set; }
    public int? Move(int delta, IReadOnlyList<int> numbers, int? current)
    {
        if (numbers.Count == 0) return null;
        _remainder += delta;
        if (Math.Abs(_remainder) < 120) return Selected;
        bool starting = !Active;
        bool hasCurrent = current.HasValue && numbers.Contains(current.Value);
        if (starting) { Selected = hasCurrent ? current : numbers[0]; Active = true; }
        int steps = _remainder / 120;
        _remainder %= 120;
        int index = numbers.ToList().IndexOf(Selected!.Value);
        if (starting && !hasCurrent && steps < 0) index = -1;
        Selected = numbers[((index - steps) % numbers.Count + numbers.Count) % numbers.Count];
        return Selected;
    }
    public int? Reset() { int? result = Active ? Selected : null; Active = false; Selected = null; _remainder = 0; return result; }
}
