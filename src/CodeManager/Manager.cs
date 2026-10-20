using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace CodeManager;

public sealed class Manager : IDisposable
{
    public AppState State { get; }
    public StateStore Store { get; }
    public DockWindow Dock { get; }
    public Native.Rect WorkArea { get; private set; }
    private double _scale;
    private readonly InputService _input;
    private readonly DispatcherTimer _heartbeat, _dragTimer;
    private readonly Forms.NotifyIcon _tray;
    private readonly System.Drawing.Icon _trayIcon;
    private readonly WheelSelection _wheel = new();
    private WindowIdentity? _dragWindow;
    private Native.Placement? _dragPlacement;
    private Native.Rect _dragStartRect;
    private bool _wasCollapsed, _dialog;
    private int _dialogDepth;
    private RecoveryWindow? _recoveryWindow;
    private DateTime _lastCheckpoint = DateTime.MinValue;
    private readonly Action<ProcessStartInfo> _startRecovery;
    private DateTime _lastHint = DateTime.MinValue;
    private bool _disposed;
    private bool _resizeGesture;
    private bool _dockHiddenByUser;
    private bool _startupRecoveryProcessed;
    private bool _processingStatusBatch, _statusBatchDirty;
    private Dictionary<string, Slot>? _statusBatchNotices;
    private InventoryWindow? _inventory;
    private RadialInventoryWindow? _radial;
    internal RadialInventoryWindow? Radial => _radial;
    private IntPtr _inventoryPreviousFocus;
    public InventoryWindow? Inventory => _inventory;
    private readonly Dictionary<int, DateTime> _captureFlashes = new();
    public bool ShortcutsPaused { get; private set; }
    public bool ShowingAllSlots { get; private set; }
    public bool Exiting { get; private set; }
    public bool Dragging => _dragWindow != null;
    public bool Selecting => _wheel.Active || _radial != null;
    public string TaskChord => Preferences.ModifierLabel(State.Preferences.TaskModifiers);
    public string MouseChord => Preferences.ModifierLabel(State.Preferences.MouseModifiers);
    public string ToggleShortcut => _input.ToggleShortcut;
    public string InventoryMenuLabel => "任务总览" + (State.Preferences.TabTogglesInventory ? "（" + ShortcutBindings.Display(State.Preferences.InventoryGesture) + "）" : "");

    public Manager(StateStore? store = null, bool interactionTest = false, Action<ProcessStartInfo>? startRecovery = null)
    {
        _startRecovery = startRecovery ?? (info => { using var process = Process.Start(info); if (process == null) throw new InvalidOperationException("启动器没有返回进程"); });
        Store = store ?? new StateStore(); State = Store.Load();
        ApplyAudioPreferences();

        SkinCatalog.DecorationsEnabled = State.Preferences.DecorationsEnabled; WuxiaTheme.Apply(State.Preferences.Skin, State.Preferences.Animate);
        Dock = new DockWindow(interactionTest) { Manager = this }; Dock.SetSlots(State.Slots);
        Dock.Show();
        if (State.Preferences.HasDockAnchor) { var screen = Native.ScreenAt(State.Preferences.DockAnchor); WorkArea = screen.Work; _scale = screen.Scale; }
        else MoveToCursorScreen();
        _input = new InputService(Dock.Dispatcher);
        _input.IsSelecting = () => Selecting || Dock.MenuOpen || Dock.IsManipulating || (Dragging && _inventory != null);
        _input.CanHandleMouse = () => !_dialog && !Dragging && !ShortcutsPaused && _radial == null && !Dock.IsManipulating && State.Slots.Any(s => s.Connected);
        _input.IsDockMenuOpen = () => Dock.MenuOpen;
        _input.PointerDown += point => Dock.DismissMenuOutside(point);
        _input.Hotkey += Hotkey;
        _input.Wheel += Wheel;
        _input.IsInventoryOpen = () => _inventory?.IsActive == true;
        _input.InventoryWheel += delta => _inventory?.Browse(delta);
        _input.Release += CommitSelection;
        _input.Cancel += CancelInteraction;
        _input.Quit += Exit;
        _input.Drag += DragEvent;
        _heartbeat = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        _heartbeat.Tick += (_, _) => Tick(); _heartbeat.Start();
        _dragTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(30) };
        _dragTimer.Tick += (_, _) => DragTick();
        _trayIcon = ProductIcon.CreateTrayIcon();
        _tray = new Forms.NotifyIcon { Icon = _trayIcon, Text = "OmniVibe · AI 任务武器栏", Visible = true };
        var menu = new Forms.ContextMenuStrip { BackColor = System.Drawing.Color.FromArgb(22, 30, 27), ForeColor = System.Drawing.Color.FromArgb(250, 234, 203), Font = new System.Drawing.Font("Microsoft YaHei UI", 10), Renderer = new TrayMenuRenderer() };
        menu.Items.Add("显示 / 隐藏悬浮入口", null, (_, _) => Dock.Dispatcher.Invoke(ToggleVisibility));
        menu.Items.Add(InventoryMenuLabel, null, (_, _) => Dock.Dispatcher.Invoke(ToggleInventory));
        menu.Items.Add("最近关闭 / 恢复工作现场…", null, (_, _) => Dock.Dispatcher.Invoke(ShowRecovery));
        menu.Items.Add("排列 / 恢复窗口", null, (_, _) => Dock.Dispatcher.Invoke(RequestOverview));
        menu.Items.Add("设置", null, (_, _) => Dock.Dispatcher.Invoke(ShowSettings));
        menu.Items.Add("快速上手", null, (_, _) => Dock.Dispatcher.Invoke(ShowHelp));
        menu.Items.Add("退出并恢复窗口", null, (_, _) => Dock.Dispatcher.Invoke(Exit));
        _tray.ContextMenuStrip = menu; RefreshTrayTheme();
        _tray.DoubleClick += (_, _) => Dock.Dispatcher.Invoke(() => { _dockHiddenByUser = false; EnsureDockVisible(); Expand(); });
        if (State.AutoHide) Collapse();
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += DisplayChanged;
        RestorePopup(restoreFocus: false);
        RefreshConnections(); UpdateSlotsVisibility(); Dock.UpdateSummary(); Save();
        if (Store.LoadWarning != null) Hint(Store.LoadWarning);
        else if (_input.Warnings.Count > 0) Hint(string.Join("；", _input.Warnings));
        else Hint("拖动窗口标题栏到槽位；右键可选择窗口");
        foreach (string warning in _input.Warnings) Store.Log(warning);
    }
    private void RefreshTrayTheme()
    {
        if (_tray.ContextMenuStrip is not { } menu) return;
        menu.BackColor = System.Drawing.ColorTranslator.FromHtml(SkinCatalog.Current.Background);
        menu.ForeColor = System.Drawing.ColorTranslator.FromHtml(SkinCatalog.Current.Text);
        menu.Invalidate();
    }
    public bool Save()
    {
        try { Store.Save(State); return true; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        { Hint("配置保存失败：" + ex.Message); Store.Log(ex.ToString()); return false; }
    }
    private void Hint(string message) { Dock.SetHint(message); _lastHint = DateTime.UtcNow; }
    private void ApplyAudioPreferences() => GameAudio.Configure(State.Preferences.SoundEffects, State.Preferences.SoundVolume, State.Preferences.ImmersiveAudio);
    internal void PlayCue(AudioCue cue, Slot? slot = null)
    {
        var p = State.Preferences;
        if (_disposed || Exiting || ShortcutsPaused || cue != AudioCue.Switch) return;
        GameAudio.PlaySignature(SignatureAudio.ResolveTheme(p), p.SoundEffects, p.SoundVolume);
    }
    public void StartupRecovery()
    {
        if (GettingStartedPanel.ShouldOpenOnStartup(State)) ShowHelp();
        if (State.Preferences.AutoReconnectExisting) ReconnectExisting();
        if (State.Preferences.AutoRestoreOnStartup) RestoreAllTasks();
        ArchiveClosedWindows(includePreviouslyDisconnected: true);
        _startupRecoveryProcessed = true;
        if (State.Preferences.ShowRecoveryOnStartup && State.Slots.Any(s => s.Occupied && !s.Connected)) ShowRecovery();
    }
    public void ShowRecovery()
    {
        if (_disposed) return;
        if (_recoveryWindow != null) { _recoveryWindow.Activate(); return; }
        BeginDialog();
        try { _recoveryWindow = new RecoveryWindow(this, WorkArea); _recoveryWindow.ShowDialog(); }
        finally { _recoveryWindow = null; EndDialog(); }
    }
    public int ReconnectExisting()
    {
        RefreshConnections(); var windows = Native.Windows(); int count = 0;
        foreach (var slot in State.Slots.Where(s => s.Occupied && !s.Connected && s.Recovery == null))
        {
            var match = RecoveryLaunch.ExistingMatch(slot, State.Slots, windows);
            if (match != null && AttachRecoveredWindow(slot, match, restorePosition: false)) count++;
        }
        Hint("已匹配重连 " + count + " 个窗口；无法唯一确认的任务保留待处理"); return count;
    }
    public string RestoreTask(Slot slot)
    {
        if (!State.Slots.Contains(slot)) {
            string? error = RecoveryLaunch.Validation(slot);
            if (error != null) return error;
            if (!ReclaimRecentTask(slot)) return "当前九个槽位已满，请先移出一个任务";
        }
        if (!slot.Occupied) return "这个任务已移出列表";
        if (Native.Matches(slot.Window)) { slot.Connected = true; slot.Refresh(); return "窗口已连接，无需重复打开"; }
        if (slot.Recovery != null) return "正在恢复，已阻止重复打开";
        var match = RecoveryLaunch.ExistingMatch(slot, State.Slots, Native.Windows());
        if (match != null && AttachRecoveredWindow(slot, match, false)) return "已重连现有窗口";
        string? validation = RecoveryLaunch.Validation(slot);
        if (validation != null) { slot.RecoveryError = validation; slot.Refresh(); return validation; }
        var pending = new PendingRecovery { Token = Guid.NewGuid().ToString("N") };
        Directory.CreateDirectory(Path.Combine(Store.Root, "recovery")); slot.Recovery = pending; slot.RecoveryError = ""; slot.Refresh();
        if (!Save()) { slot.Recovery = null; slot.Refresh(); return "配置未保存，未打开新窗口"; }
        try { _startRecovery(RecoveryLaunch.StartInfo(slot, Store, pending)); return "正在打开并自动重连"; }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException or IOException or UnauthorizedAccessException)
        { slot.Recovery = null; slot.RecoveryError = "打开失败：" + ex.Message; slot.Refresh(); Save(); return slot.RecoveryError; }
    }
    public string RestoreAllTasks()
    {
        RefreshConnections(); ReconnectExisting(); int started = 0, skipped = 0;
        foreach (var slot in State.Slots.Where(s => s.Occupied && !s.Connected && s.Recovery == null).Concat(State.RecentTasks.Select(r => r.Task)).ToArray())
        { if (RecoveryLaunch.Validation(slot) != null) { skipped++; continue; } RestoreTask(slot); if (slot.Recovery != null || slot.Connected) started++; else skipped++; }
        string result = "已开始恢复 " + started + " 个任务" + (skipped > 0 ? " · " + skipped + " 个需补充启动信息" : ""); Hint(result); return result;
    }
    private bool ReclaimRecentTask(Slot task)
    {
        var record = State.RecentTasks.FirstOrDefault(r => r.Task == task);
        if (record == null) return State.Slots.Contains(task);
        var empty = State.Slots.FirstOrDefault(s => !s.Occupied);
        if (empty == null) return false;
        int index = State.Slots.IndexOf(empty); task.Number = empty.Number; task.Connected = task.IsActive = false;
        task.IntegrationConnected = false; task.SessionId = ""; task.State = AgentState.Unknown; task.Unread = false;
        State.Slots[index] = task; State.RecentTasks.Remove(record);
        Dock.SetSlots(State.Slots); Save(); UpdateSlotsVisibility(); return true;
    }
    public void PickRecoveryWindow(Slot task)
    {
        if (State.Slots.Contains(task)) { PickWindow(task); return; }
        if (!State.Slots.Any(s => !s.Occupied)) { Hint("当前九个槽位已满，请先移出一个任务"); return; }
        BeginDialog();
        try {
            var picked = Dialogs.Pick(task.Number, WorkArea, task, State.Slots);
            if (picked != null && ReclaimRecentTask(task)) Bind(task, picked);
        } finally { EndDialog(); }
    }
    internal int ArchiveClosedWindows(bool includePreviouslyDisconnected = false)
    {
        static bool Closed(WindowIdentity window) {
            var hwnd = new IntPtr(window.Handle);
            if (!Native.IsWindow(hwnd)) return true;
            Native.GetWindowThreadProcessId(hwnd, out uint pid);
            return pid != 0 && pid != window.ProcessId;
        }
        var closed = State.Slots.Where(s => s.Occupied && s.Recovery == null && (s.Connected || includePreviouslyDisconnected || _startupRecoveryProcessed) && Closed(s.Window!)).ToArray();
        foreach (var slot in closed) {
            var snapshot = JsonSerializer.Deserialize<Slot>(JsonSerializer.Serialize(slot, StateStore.Json), StateStore.Json)!;
            snapshot.Connected = false; snapshot.IsActive = false;
            State.RecentTasks.RemoveAll(r => r.Task.Id == slot.Id); State.RecentTasks.Insert(0, new() { Task = snapshot });
            State.Layout.RemoveAll(e => e.SlotId == slot.Id);
            if (State.Popup?.SlotId == slot.Id) State.Popup = null;
            _captureFlashes.Remove(slot.Number); ClearSlot(slot);
        }
        if (closed.Length > 0) {
            State.RecentTasks = State.RecentTasks.Take(30).ToList();
            Save(); UpdateSlotsVisibility();
            Hint(closed.Length + " 个已关闭窗口已移到最近关闭，槽位已腾出");
        }
        return closed.Length;
    }
    internal bool AttachRecoveredWindow(Slot slot, WindowIdentity identity, bool restorePosition)
    {
        if (!slot.Occupied || !Native.Matches(identity) || State.Slots.Any(s => s != slot && Native.Matches(s.Window) && s.Window!.Handle == identity.Handle)) return false;
        var placement = slot.LastPlacement; slot.Window = identity; slot.CapturePlacement = Native.PlacementOf(new(identity.Handle));
        slot.Connected = true; slot.ParkedByApp = false; slot.IntegrationConnected = false; slot.SessionId = "";
        slot.State = AgentState.Unknown; slot.UpdatedAt = null; slot.StateSource = "工作现场恢复"; slot.RecoveryError = ""; slot.LastSeenAt = DateTimeOffset.UtcNow;
        if (restorePosition && placement.HasValue) { Native.RestorePlacement(new(identity.Handle), placement.Value); Native.ShowWindow(new(identity.Handle), 9); Native.EnsureVisible(new(identity.Handle)); }
        slot.LastPlacement = Native.PlacementOf(new(identity.Handle)); slot.Refresh(); Save(); RefreshBindings(); UpdateSlotsVisibility(); return true;
    }
    internal void ProcessRecoveries(IReadOnlyList<WindowIdentity>? availableWindows = null)
    {
        var pending = State.Slots.Where(s => s.Occupied && s.Recovery != null).ToArray(); if (pending.Length == 0) return;
        var windows = availableWindows ?? Native.Windows();
        foreach (var slot in pending)
        {
            var launch = slot.Recovery!;
            if (Native.Matches(slot.Window) && File.Exists(RecoveryLaunch.Acknowledgement(Store, launch))) { slot.Recovery = null; slot.Refresh(); Save(); continue; }
            if (DateTimeOffset.UtcNow - launch.StartedAt > TimeSpan.FromSeconds(24)) { slot.Recovery = null; slot.RecoveryError = "恢复超时，请选择已有窗口；未重复启动"; slot.Refresh(); Save(); continue; }
            var match = RecoveryLaunch.PendingMatch(launch, windows);
            if (match != null && AttachRecoveredWindow(slot, match, true))
            {
                if (!Save()) continue;
                try { StateStore.AtomicWrite(RecoveryLaunch.Acknowledgement(Store, launch), "ready"); slot.Recovery = null; slot.Refresh(); Save(); }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Store.Log("Recovery acknowledgement: " + ex.Message); }
            }
        }
    }
    private void CheckpointWindows()
    {
        if (DateTime.UtcNow - _lastCheckpoint < TimeSpan.FromSeconds(30)) return; _lastCheckpoint = DateTime.UtcNow; bool changed = false;
        foreach (var slot in State.Slots.Where(s => Native.Matches(s.Window)))
        { string title = Native.Title(new(slot.Window!.Handle)); if (title != "" && !title.StartsWith("CM-RESTORE-", StringComparison.Ordinal)) slot.Window.Title = title; slot.LastSeenAt = DateTimeOffset.UtcNow; changed = true; }
        if (changed) Save();
    }
    public void MoveToCursorScreen()
    {
        var screen = Native.ScreenAtCursor(); WorkArea = screen.Work; _scale = screen.Scale;
        State.Preferences.FreeDockPosition = false;
        State.Preferences.RingCentre = new((int)(WorkArea.Right - State.Preferences.DockWidth * _scale / 2), (WorkArea.Top + WorkArea.Bottom) / 2);
        State.Preferences.HasDockAnchor = true;
        State.Preferences.DockAnchor = new(WorkArea.Left + (WorkArea.Right - WorkArea.Left) / 2, WorkArea.Top + (WorkArea.Bottom - WorkArea.Top) / 2);
        Reposition();
    }
    private void Reposition()
    {
        var p = State.Preferences;
        if (p.RingCentre == null)
        {
            double legacyWidth = Math.Max(440, p.DockWidth);
            double legacyHeight = Math.Max(legacyWidth + 60, p.DockHeight > 0 ? p.DockHeight : legacyWidth + 70);
            double x = p.FreeDockPosition ? p.DockPosition.X + legacyWidth * _scale / 2 : WorkArea.Right - legacyWidth * _scale / 2;
            double y = p.FreeDockPosition ? p.DockPosition.Y + (legacyHeight / 2 - 7) * _scale : (WorkArea.Top + WorkArea.Bottom) / 2d;
            p.RingCentre = new((int)x, (int)y);
            if (p.DockWidth >= 440) p.DockWidth = Math.Clamp(p.DockWidth * .82, 320, 480);
            p.DockHeight = 0;
        }
        p.DockWidth = Math.Clamp(p.DockWidth, 320, 480);
        if (!p.FreeDockPosition) p.RingCentre = new((int)(WorkArea.Right - p.DockWidth * _scale / 2), (WorkArea.Top + WorkArea.Bottom) / 2);
        var centre = p.RingCentre.Value;
        int half = (int)Math.Ceiling(DockWindow.CompactExtent * _scale / 2);
        centre.X = Math.Clamp(centre.X, WorkArea.Left + half, WorkArea.Right - half);
        centre.Y = Math.Clamp(centre.Y, WorkArea.Top + half, WorkArea.Bottom - half);
        p.RingCentre = centre;
        p.DockAnchor = centre;
        Dock.PlaceCompactHost(centre, _scale, p.DockWidth);
        Native.GetWindowRect(new WindowInteropHelper(Dock).Handle, out var actual);
        p.DockPosition = new(actual.Left, actual.Top);
    }
    public void DragDockBounds(Native.Rect start, Native.Point pointerStart, bool resize)
    {
        Native.GetCursorPos(out var cursor);
        if (resize) { ChangeDockBounds(cursor.X - pointerStart.X, cursor.Y - pointerStart.Y, true); return; }
        var desktop = Forms.SystemInformation.VirtualScreen;
        int x = Math.Clamp(start.Left + cursor.X - pointerStart.X, desktop.Left, Math.Max(desktop.Left, desktop.Right - (start.Right - start.Left)));
        int y = Math.Clamp(start.Top + cursor.Y - pointerStart.Y, desktop.Top, Math.Max(desktop.Top, desktop.Bottom - (start.Bottom - start.Top)));
        Native.SetWindowPos(new WindowInteropHelper(Dock).Handle, IntPtr.Zero, x, y, 0, 0, 0x0015);
    }
    public void CommitDockMove()
    {
        var centre = Dock.CoreScreen; var p = State.Preferences;
        p.RingCentre = new((int)Math.Round(centre.X), (int)Math.Round(centre.Y));
        p.FreeDockPosition = true; p.HasDockAnchor = true; p.DockAnchor = p.RingCentre.Value;
        var screen = Native.ScreenAt(p.DockAnchor); WorkArea = screen.Work; _scale = screen.Scale;
        Native.GetWindowRect(new WindowInteropHelper(Dock).Handle, out var rect);
        p.DockPosition = new(rect.Left, rect.Top);
        Reposition();
        Save();
    }
    public void ChangeDockBounds(double dx, double dy, bool resize)
    {
        var p = State.Preferences;
        if (resize) { p.DockWidth = Math.Clamp(p.DockWidth + dx, 320, 480); p.DockHeight = p.DockWidth; }
        else
        {
            var centre = Dock.CoreScreen;
            p.RingCentre = new((int)(centre.X + dx * _scale), (int)(centre.Y + dy * _scale));
            p.FreeDockPosition = true; p.HasDockAnchor = true; p.DockAnchor = p.RingCentre.Value;
        }
        Reposition();
    }
    public void ResetDockPosition()
    {
        var p = State.Preferences; p.FreeDockPosition = false; p.DockHeight = 0;
        p.RingCentre = new((int)(WorkArea.Right - Math.Max(64, p.DockWidth / 2) * _scale), (WorkArea.Top + WorkArea.Bottom) / 2);
        Reposition(); Save();
    }
    public void Expand() => Dock.SetCollapsed(false);
    private void Collapse() => Dock.SetCollapsed(true);
    public void SetAutoHide(bool autoHide) { State.AutoHide = autoHide; if (autoHide) Collapse(); else Expand(); Save(); }
    public void ToggleVisibility()
    {
        CancelInteraction(); Dock.ClosePreview();
        _dockHiddenByUser = Dock.IsVisible;
        if (_dockHiddenByUser) Dock.Hide(); else EnsureDockVisible();
    }
    internal void EnsureDockVisible()
    {
        if (_disposed || Exiting || _dockHiddenByUser) return;
        if (!Dock.IsVisible) { Dock.Show(); Reposition(); }
        var hwnd = new WindowInteropHelper(Dock).Handle;
        if (Native.IsIconic(hwnd)) { Native.ShowWindow(hwnd, 4); Reposition(); }
        if (!_dialog && !Dock.MenuOpen && _inventory == null && _radial == null)
            Native.SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, 0x0013);
    }
    public void ToggleInventory()
    {
        if (_dialog) return;
        if (_inventory != null) { CloseInventory(restoreFocus: true); return; }
        _inventoryPreviousFocus = Native.GetForegroundWindow();
        CancelInteraction(); Dock.ClosePreview(); RefreshConnections();
        int? selected = State.Slots.FirstOrDefault(s => s.IsActive)?.Number;
        var window = new InventoryWindow(State.Slots, WorkArea, _scale, selected, State.Preferences.Animate && !ShortcutsPaused, duringDrag: Dragging, size: State.Preferences.OverviewSize);
        _inventory = window;
        window.Remove += number => { var slot = State.Slots.Single(s => s.Number == number); CloseInventory(restoreFocus: false); Remove(slot); };
        window.Choose += number => { CloseInventory(restoreFocus: false); var slot = State.Slots.Single(s => s.Number == number); if (!slot.Occupied) PickWindow(slot); else ActivateSlot(number); };
        window.Dismiss += () => CloseInventory(restoreFocus: true);
        window.Deactivated += (_, _) => { if (_inventory == window && !Dragging) CloseInventory(restoreFocus: false); };
        window.Show(); if (!Dragging) { window.Activate(); window.Focus(); }
        PlayCue(AudioCue.InventoryOpen);
    }
    private void CloseInventory(bool restoreFocus)
    {
        var window = _inventory; _inventory = null;
        if (window == null) return;
        window.Close();
        PlayCue(AudioCue.InventoryClose);
        if (restoreFocus && Native.IsWindow(_inventoryPreviousFocus)) Native.SetForegroundWindow(_inventoryPreviousFocus);
    }
    public void OpenRadial(bool hold = false)
    {
        if (_dialog || Dragging || (hold && ShortcutsPaused) || _radial != null) return;
        CancelInteraction(); Dock.ClosePreview(); RefreshConnections();
        var screen = Native.ScreenAtCursor();
        string gesture = State.Preferences.RadialGesture;
        var window = new RadialInventoryWindow(State.Slots, screen.Work, screen.Scale, State.Preferences.Animate,
            gesture, hold ? () => InputService.GestureDown(gesture) : null);
        _radial = window;
        window.Finish += number =>
        {
            CloseRadial();
            if (number.HasValue && State.Slots.Single(s => s.Number == number).Connected) ActivateSlot(number.Value);
        };
        window.Closed += (_, _) => { if (_radial == window) _radial = null; };
        window.Show();
        PlayCue(AudioCue.InventoryOpen);
    }
    private void CloseRadial() { var window = _radial; _radial = null; if (window != null) { window.Close(); PlayCue(AudioCue.InventoryClose); } }
    internal void Hotkey(int number)
    {
        if (_dialog) return;
        if (number == 0) ToggleOverview();
        else if (number == 10) ToggleVisibility();
        else if (number == 11) ToggleInventory();
        else if (number == 13) OpenRadial(hold: true);
        else ToggleSlot(number);
    }
    private void ToggleSlot(int number)
    {
        var slot = State.Slots.Single(s => s.Number == number);
        if (State.Popup?.SlotId == slot.Id && Native.Matches(State.Popup.Window))
        {
            CancelInteraction(); Dock.ClosePreview(); RestorePopup(restoreFocus: true);
            RefreshConnections(); Dock.UpdateSummary(); Hint("已恢复 " + number + " 唤出前的状态");
            PlayCue(AudioCue.Restore, slot);
        }
        else ActivateSlot(number);
    }
    internal void Wheel(int delta)
    {
        if (_dialog || Dragging || ShortcutsPaused) return;
        RefreshConnections();
        var slots = State.Slots.Where(s => s.Connected).Select(s => s.Number).ToList();
        int? active = State.Slots.FirstOrDefault(s => s.IsActive)?.Number;
        int? previous = _wheel.Selected;
        int? selected = _wheel.Move(delta, slots, active);
        if (selected == null) { if (slots.Count == 0) Hint("先拖入一个窗口，或右键槽位进行绑定"); return; }
        if (selected == previous) return;
        ActivateSlot(selected.Value, keepWheelGesture: true);
    }
    private void CommitSelection()
    {
        // Windows are activated on each detent, never again on modifier release.
        CancelSelection();
    }
    private void CancelSelection() { _wheel.Reset(); ClearSelection(); }
    private void CancelInteraction() { Dock.CancelManipulation(); CancelSelection(); CloseInventory(restoreFocus: false); CloseRadial(); }
    private void ClearSelection() { foreach (Slot slot in State.Slots) { if (slot.IsSelected) { slot.IsSelected = false; slot.Refresh(); } } }
    public void ActivateSlot(int number) => ActivateSlot(number, keepWheelGesture: false);
    private void ActivateSlot(int number, bool keepWheelGesture)
    {
        Slot slot = State.Slots.Single(s => s.Number == number);
        CloseInventory(restoreFocus: false);
        if (keepWheelGesture) ClearSelection();
        else CancelInteraction();
        Dock.ClosePreview();
        if (!Native.Matches(slot.Window)) { if (slot.Occupied) PickWindow(slot); else Hint("槽位 " + number + " 还没有窗口"); return; }
        var hwnd = new IntPtr(slot.Window!.Handle);
        if (State.Popup?.SlotId != slot.Id || !Native.Matches(State.Popup.Window))
        {
            var previous = Native.Identify(Native.GetForegroundWindow(), includeOwn: true);
            if (State.Popup != null && previous?.Handle == State.Popup.Window.Handle) previous = State.Popup.PreviousFocus;
            RestorePopup(restoreFocus: false);
            var placement = Native.PlacementOf(hwnd);
            if (!placement.HasValue) { Hint("无法记录窗口位置，请重试"); return; }
            State.Popup = new() { SlotId = slot.Id, Window = slot.Window!, Placement = placement.Value, ParkedByApp = slot.ParkedByApp, PreviousFocus = previous };
            if (!Save()) { State.Popup = null; return; }
        }
        if (State.Layout.Count > 0 || State.Preferences.WakeMode == WakeMode.WorkArea)
        {
            var cell = Tiling.Arrange(1, WorkArea)[0];
            Native.PlaceVisibleWindow(hwnd, cell);
        }
        else
        {
            if (Native.IsIconic(hwnd) && slot.LastPlacement.HasValue) Native.RestorePlacement(hwnd, slot.LastPlacement.Value);
            Native.EnsureVisible(hwnd);
        }
        if (Native.Activate(slot.Window!))
        {
            slot.ParkedByApp = false;
            slot.Unread = false;
            Hint("已唤出 " + number + " · " + slot.DisplayName);
            Dock.Pulse(slot, capture: false);
            PlayCue(AudioCue.Switch, slot);
        }
        else
        {
            RestorePopup(restoreFocus: false);
            Hint("未能取得窗口焦点，可尝试点击窗口或用相同权限运行");
        }
        Save(); RefreshConnections(); Dock.UpdateSummary();
    }
    private void RestorePopup(bool restoreFocus)
    {
        var popup = State.Popup; State.Popup = null;
        if (popup == null) return;
        if (Native.Matches(popup.Window))
        {
            Native.RestorePlacement(new(popup.Window.Handle), popup.Placement);
            var slot = State.Slots.FirstOrDefault(s => s.Id == popup.SlotId && s.Window?.Handle == popup.Window.Handle);
            if (slot != null) slot.ParkedByApp = popup.ParkedByApp;
        }
        if (restoreFocus && Native.Matches(popup.PreviousFocus))
        {
            var previous = new IntPtr(popup.PreviousFocus!.Handle);
            if (Native.IsWindowVisible(previous) && !Native.IsIconic(previous)) Native.Activate(popup.PreviousFocus);
        }
        Save();
    }
    public void Park(Slot slot)
    {
        if (State.Popup?.SlotId == slot.Id) RestorePopup(restoreFocus: false);
        if (!Native.Matches(slot.Window)) return;
        RememberPlacement(slot);
        Native.ShowWindow(new(slot.Window!.Handle), 6);
        slot.ParkedByApp = true; Save(); Hint("已收起 " + slot.DisplayName);
    }
    public void ParkAll()
    {
        CancelSelection();
        RestorePopup(restoreFocus: false);
        if (State.Layout.Count > 0) RestoreLayout();
        foreach (Slot slot in State.Slots.Where(s => Native.Matches(s.Window)))
        { RememberPlacement(slot); Native.ShowWindow(new(slot.Window!.Handle), 6); slot.ParkedByApp = true; }
        Save(); Hint("已收起所有任务窗口，进程继续运行");
    }
    public void Bind(Slot slot, WindowIdentity identity, Native.Placement? original = null)
    {
        if (!Native.Matches(identity)) { Hint("这个窗口已经关闭，请重新选择"); return; }
        RestorePopup(restoreFocus: false);
        if (State.Layout.Count > 0) RestoreLayout();
        var duplicate = State.Slots.FirstOrDefault(s => s.Window?.Handle == identity.Handle && Native.Matches(s.Window));
        if (duplicate != null && duplicate != slot)
        {
            if (slot.Occupied) { Hint("目标槽位已占用，请先移出原任务"); return; }
            MoveSlot(duplicate, slot);
            if (original.HasValue) Native.RestorePlacement(new(identity.Handle), original.Value);
            if (State.MinimizeOnCapture) Park(slot);
            return;
        }
        string previousName = slot.Name, previousColor = slot.TagColor, previousProject = slot.ProjectDirectory;
        bool preserving = slot.Occupied;
        if (slot.Occupied) ReleaseSlotWindow(slot);
        slot.Id = Guid.NewGuid().ToString("N");
        slot.Name = preserving ? previousName : identity.Title; slot.Window = identity;
        slot.CustomName = preserving && slot.CustomName;
        slot.TagColor = previousColor; slot.ProjectDirectory = previousProject;
        slot.CapturePlacement = original ?? Native.PlacementOf(new(identity.Handle));
        slot.LastPlacement = slot.CapturePlacement;
        slot.Connected = true; slot.State = AgentState.Unknown; slot.StateSource = "";
        slot.Message = ""; slot.UpdatedAt = null; slot.Unread = false; slot.ParkedByApp = false;
        slot.SessionId = ""; slot.AgentProvider = ""; slot.IntegrationConnected = false;
        slot.Recovery = null; slot.RecoveryError = ""; slot.LastSeenAt = DateTimeOffset.UtcNow;
        // The capture gesture must not become the restored working position.
        if (original.HasValue) Native.RestorePlacement(new(identity.Handle), original.Value);
        if (!Save()) return; // Persist identity and working placement before minimizing anything.
        if (State.MinimizeOnCapture) Park(slot);
        slot.JustCaptured = true; _captureFlashes[slot.Number] = DateTime.UtcNow.AddMilliseconds(900);
        RefreshConnections(); UpdateSlotsVisibility(); slot.Refresh(); Save(); Dock.UpdateSummary(); Dock.Pulse(slot);
        PlayCue(AudioCue.Capture, slot);
        InkEffects.Sweep(WorkArea, _scale, State.Preferences.Animate, capture: true);
        Hint("已收录至 " + slot.Number + " · 右键可重命名任务");
    }
    public void PickWindow(Slot slot)
    {
        BeginDialog();
        try
        {
            var picked = Dialogs.Pick(slot.Number, WorkArea, slot, State.Slots);
            if (picked != null) Bind(slot, picked);
        }
        finally { EndDialog(); }
    }
    public void Rename(Slot slot)
    {
        BeginDialog();
        try
        {
            var editor = new TaskEditorWindow(slot, WorkArea);
            if (editor.ShowDialog() == true) { slot.Name = editor.TaskName; slot.CustomName = true; slot.TagColor = editor.TagColor; slot.ProjectDirectory = editor.ProjectDirectory; slot.LaunchMode = editor.LaunchMode; slot.ResumeSessionId = editor.ResumeSessionId; slot.ResumeConversation = editor.ResumeConversation; slot.Notes = editor.Notes; slot.RecoveryError = ""; slot.Refresh(); Save(); }
        }
        finally { EndDialog(); }
    }
    public void MoveSlot(Slot source, Slot target)
    {
        if (source == target || !source.Occupied || target.Occupied) return;
        if (State.Layout.Count > 0) RestoreLayout();
        target.Id = source.Id; target.Name = source.Name; target.Window = source.Window;
        EquipmentCatalog.EnsureDefaults(State.Slots);
        var destinationEquipment = EquipmentAssignment.From(target);
        EquipmentAssignment.From(source).Apply(target); destinationEquipment.Apply(source);
        target.CapturePlacement = source.CapturePlacement; target.ParkedByApp = source.ParkedByApp;
        target.LastPlacement = source.LastPlacement; target.CustomName = source.CustomName; target.TagColor = source.TagColor; target.ProjectDirectory = source.ProjectDirectory;
        target.AgentProvider = source.AgentProvider; target.SessionId = source.SessionId; target.IntegrationConnected = source.IntegrationConnected;
        target.LaunchMode = source.LaunchMode; target.ResumeSessionId = source.ResumeSessionId; target.ResumeConversation = source.ResumeConversation; target.Notes = source.Notes; target.LastSeenAt = source.LastSeenAt; target.Recovery = source.Recovery; target.RecoveryError = source.RecoveryError;
        target.State = source.State; target.StateSource = source.StateSource; target.UpdatedAt = source.UpdatedAt;
        target.Unread = source.Unread; target.Message = source.Message;
        ClearSlot(source); RefreshConnections(); UpdateSlotsVisibility(); Save(); Dock.UpdateSummary();
        Hint("任务已移动到槽位 " + target.Number);
        PlayCue(AudioCue.Reorder, target);
    }
    public void ReorderSlot(Slot source, Slot target)
    {
        if (source == target || !source.Occupied) return;
        int destination = State.Slots.IndexOf(target);
        State.Slots.Remove(source); State.Slots.Insert(destination, source);
        for (int i = 0; i < State.Slots.Count; i++) State.Slots[i].Number = i + 1;
        _captureFlashes.Clear(); CancelSelection();
        Dock.SetSlots(State.Slots.ToArray());
        foreach (var slot in State.Slots) { slot.JustCaptured = false; slot.Refresh(); }
        RefreshBindings(); UpdateSlotsVisibility(); Save(); Hint("顺序已更新 · 各窗口使用新槽位对应的快捷键");
        PlayCue(AudioCue.Reorder, source);
    }
    private static void ClearSlot(Slot slot)
    {
        slot.Id = Guid.NewGuid().ToString("N"); slot.Name = ""; slot.Window = null; slot.CapturePlacement = null;
        slot.Connected = false; slot.ParkedByApp = false; slot.Unread = false; slot.State = AgentState.Unknown;
        slot.StateSource = ""; slot.Message = ""; slot.UpdatedAt = null; slot.IsActive = slot.IsSelected = slot.IsDropTarget = false; slot.Refresh();
        slot.LastPlacement = null; slot.CustomName = false; slot.ProjectDirectory = ""; slot.TagColor = "#7EB5C8";
        slot.SessionId = ""; slot.AgentProvider = ""; slot.IntegrationConnected = false; slot.JustCaptured = false;
        slot.LaunchMode = LaunchMode.Unconfigured; slot.ResumeSessionId = ""; slot.ResumeConversation = true; slot.Notes = ""; slot.LastSeenAt = null; slot.Recovery = null; slot.RecoveryError = "";
    }
    private static void ReleaseSlotWindow(Slot slot)
    {
        if (slot.ParkedByApp && Native.Matches(slot.Window))
        {
            var placement = slot.LastPlacement ?? slot.CapturePlacement;
            if (placement.HasValue) Native.RestorePlacement(new(slot.Window!.Handle), placement.Value);
            else Native.ShowWindow(new(slot.Window!.Handle), 9);
        }
    }
    public void Remove(Slot slot)
    {
        if (State.Popup?.SlotId == slot.Id) RestorePopup(restoreFocus: false);
        if (State.Layout.Count > 0) RestoreLayout();
        ReleaseSlotWindow(slot); ClearSlot(slot); RefreshConnections(); UpdateSlotsVisibility(); Save(); Dock.UpdateSummary();
        Hint("已移出武器栏，原窗口保留");
        PlayCue(AudioCue.Remove, slot);
    }
    public void SetStatus(Slot slot, AgentState state, string source, string message, DateTimeOffset? at = null)
    {
        if (!slot.Occupied) return;
        var timestamp = at ?? DateTimeOffset.UtcNow;
        if (slot.UpdatedAt.HasValue && timestamp <= slot.UpdatedAt) return;
        bool changed = slot.State != state || slot.Message != message;
        slot.State = state; slot.StateSource = source; slot.Message = message;
        slot.UpdatedAt = timestamp;
        slot.Unread = (state is AgentState.Waiting or AgentState.Ready or AgentState.Error) && !slot.IsActive && (changed || slot.Unread);
        slot.Refresh();
        if (_processingStatusBatch)
        {
            _statusBatchDirty = true;
            if (slot.Unread && changed) (_statusBatchNotices ??= new())[slot.Id] = slot;
            else if (!slot.Unread) _statusBatchNotices?.Remove(slot.Id);
            return;
        }
        Save(); Dock.UpdateSummary();
        if (slot.Unread && changed) NotifyStatus(slot);
    }
    private void NotifyStatus(Slot slot)
    {
        Dock.Pulse(slot); Hint(slot.Number + " · " + slot.DisplayName + "：" + slot.StateLabel);
        if (slot.State == AgentState.Waiting) PlayCue(AudioCue.Waiting, slot);
        else if (slot.State == AgentState.Ready) PlayCue(AudioCue.Ready, slot);
        else if (slot.State == AgentState.Error) PlayCue(AudioCue.Error, slot);
    }
    public void MarkRead(Slot slot) { slot.Unread = false; Save(); Dock.UpdateSummary(); }
    public void RequestOverview() { if (!_dialog) ToggleOverview(); }
    public void ToggleOverview()
    {
        CancelInteraction(); Dock.ClosePreview();
        RestorePopup(restoreFocus: false);
        if (State.Layout.Count > 0) { RestoreLayout(); Hint("已恢复展开之前的布局"); PlayCue(AudioCue.Restore); return; }
        RefreshConnections();
        var slots = State.Slots.Where(s => s.Connected).ToList();
        if (slots.Count == 0) { Hint("先收录窗口，再一起展开"); return; }
        ApplyOverview(slots, Tiling.Arrange(slots.Count, WorkArea, State.Preferences.Arrangement, (int)(State.Preferences.LayoutGap * _scale)));
    }
    private void ApplyOverview(System.Collections.Generic.IReadOnlyList<Slot> slots, System.Collections.Generic.IReadOnlyList<Cell> cells)
    {
        foreach (Slot slot in slots)
        {
            var placement = Native.PlacementOf(new(slot.Window!.Handle));
            if (placement.HasValue) State.Layout.Add(new() { SlotId = slot.Id, Window = slot.Window, Placement = placement.Value, ParkedByApp = slot.ParkedByApp });
        }
        State.DockVisibleBeforeLayout = Dock.IsVisible;
        if (!Save()) { State.Layout.Clear(); State.DockVisibleBeforeLayout = null; return; }
        EnsureDockVisible();
        int failed = 0;
        for (int i = 0; i < slots.Count; i++)
        {
            var slot = slots[i]; var cell = cells[i]; var hwnd = new IntPtr(slot.Window!.Handle);
            if (!Native.PlaceVisibleWindow(hwnd, cell)) failed++;
            slot.ParkedByApp = false;
        }
        Save(); Dock.UpdateSummary();
        Hint(failed == 0 ? "窗口已排列 · " + State.Preferences.ArrangeGesture.Replace("Oem3", "反引号") + " 恢复布局" : failed + " 个窗口未能排列，其余窗口已展开");
        PlayCue(AudioCue.Arrange);
    }
    private void RestoreLayout()
    {
        RestorePopup(restoreFocus: false);
        foreach (LayoutEntry entry in State.Layout)
        {
            if (!Native.Matches(entry.Window)) continue;
            Native.RestorePlacement(new(entry.Window.Handle), entry.Placement);
            var slot = State.Slots.FirstOrDefault(s => s.Id == entry.SlotId);
            if (slot != null) slot.ParkedByApp = entry.ParkedByApp;
        }
        State.Layout.Clear();
        State.DockVisibleBeforeLayout = null;
        EnsureDockVisible();
        Save(); Dock.UpdateSummary();
    }
    private void DragEvent(IntPtr hwnd, bool start)
    {
        if (_dialog) return;
        if (start)
        {
            var identity = Native.Identify(hwnd);
            if (identity == null) return;
            CancelSelection(); Dock.ClosePreview();
            _dragWindow = identity; _dragPlacement = Native.PlacementOf(hwnd);
            Native.GetCursorPos(out var cursor); _resizeGesture = Native.IsSizingEdge(hwnd, cursor);
            Native.GetWindowRect(hwnd, out _dragStartRect);
            _wasCollapsed = Dock.Collapsed; _dragTimer.Start();
        }
        else if (_dragWindow?.Handle == hwnd.ToInt64()) FinishDrag();
    }
    private void DragTick()
    {
        if (_dragWindow == null || _resizeGesture) return;
        Native.GetCursorPos(out var cursor);
        var screen = Native.ScreenAtCursor();
        Native.GetWindowRect(new WindowInteropHelper(Dock).Handle, out var dockBounds);
        bool nearDock = Dock.IsVisible && cursor.X >= dockBounds.Left - 80 * _scale && cursor.X <= dockBounds.Right + 40 * _scale && cursor.Y >= dockBounds.Top - 30 * _scale && cursor.Y <= dockBounds.Bottom + 30 * _scale;
        if (!_dockHiddenByUser && _inventory == null && (nearDock || cursor.X >= screen.Work.Right - (int)(280 * screen.Scale)))
        {
            WorkArea = screen.Work; _scale = screen.Scale;
            Dock.Show(); Expand(); Dock.SetEquipmentDeployment(true); UpdateSlotsVisibility();
        }
        var target = _inventory?.HitSlot(cursor) ?? Dock.HitSlot(cursor);
        foreach (Slot slot in State.Slots)
        {
            bool highlighted = slot == target;
            if (slot.IsDropTarget != highlighted) { slot.IsDropTarget = highlighted; slot.Refresh(); }
        }
        if (target != null) Hint(target.Occupied ? "槽位 " + target.Number + " 已占用，请选择空槽位" : "松手，将窗口收录到 " + target.Number);
        if (!Native.Down(1)) FinishDrag();
    }
    private void FinishDrag()
    {
        if (_dragWindow == null) return;
        var identity = _dragWindow; var placement = _dragPlacement;
        bool resizing = _resizeGesture;
        _dragWindow = null; _dragTimer.Stop();
        Native.GetCursorPos(out var cursor);
        Slot? target = _inventory?.HitSlot(cursor) ?? Dock.HitSlot(cursor);
        if (_inventory != null) CloseInventory(restoreFocus: false);
        foreach (Slot slot in State.Slots) { slot.IsDropTarget = false; slot.Refresh(); }
        if (target != null && !resizing)
        {
            if (!target.Occupied) Bind(target, identity, placement);
            else
            {
                if (placement.HasValue && Native.Matches(identity)) Native.RestorePlacement(new(identity.Handle), placement.Value);
                Hint("槽位已占用，原任务未替换");
            }
        }
        else
        {
            var managed = State.Slots.FirstOrDefault(s => s.Window?.Handle == identity.Handle);
            if (managed != null && RememberPlacement(managed)) Save();
        }
        UpdateSlotsVisibility();
        if (State.AutoHide && _wasCollapsed) Collapse();
        Dock.SetEquipmentDeployment(false);
    }
    private void RefreshConnections()
    {
        ArchiveClosedWindows();
        long foreground = Native.GetForegroundWindow().ToInt64();
        foreach (Slot slot in State.Slots)
        {
            bool connected = Native.Matches(slot.Window);
            bool active = connected && slot.Window!.Handle == foreground;
            if (slot.Connected != connected || slot.IsActive != active)
            { slot.Connected = connected; slot.IsActive = active; slot.Refresh(); }
        }
        RefreshBindings();
    }
    private void Tick()
    {
        EnsureDockVisible();
        // Native inspection and disk polling wait until manipulation or a hover transition ends.
        if (Dock.IsManipulating || Dock.IsTransitioning) return;
        ProcessRecoveries(); RefreshConnections(); ConsumeEvents(); CheckpointWindows(); Dock.UpdateSummary();
        if (Selecting && !Native.RequiredModifiersDown(State.Preferences.MouseModifiers)) CommitSelection();
        foreach (int number in _captureFlashes.Where(p => p.Value <= DateTime.UtcNow).Select(p => p.Key).ToList())
        { State.Slots[number - 1].JustCaptured = false; State.Slots[number - 1].Refresh(); _captureFlashes.Remove(number); }
        if (State.AutoHide && Dock.IsVisible && !Dragging && !Selecting && !Dock.IsManipulating && !Dock.MenuOpen && !_dialog)
        {
            Native.GetCursorPos(out var cursor);
            bool inside = Dock.PointerNearInstrument(cursor);
            if (inside && Dock.Collapsed) Expand();
            else if (!inside && !Dock.Collapsed && DateTime.UtcNow - _lastHint > TimeSpan.FromSeconds(2)) Collapse();
        }
        if (DateTime.UtcNow - _lastHint > TimeSpan.FromSeconds(8)) Dock.SetHint("拖入收纳 · 右键管理 · 悬停预览");
    }
    private void ConsumeEvents()
    {
        try
        {
            // A bounded batch prevents a noisy producer from blocking the UI thread.
            var pending = new List<(string Path, StatusEvent Status)>();
            foreach (string path in Directory.EnumerateFiles(Store.EventsDirectory, "*.json").OrderBy(File.GetLastWriteTimeUtc).Take(24))
            {
                try
                {
                    if (new FileInfo(path).Length > 32768) { File.Move(path, path + ".rejected", true); continue; }
                    var status = JsonSerializer.Deserialize<StatusEvent>(File.ReadAllText(path), StateStore.Json);
                    if (status != null && Enum.IsDefined(status.State) && status.At <= DateTimeOffset.UtcNow.AddMinutes(1))
                        pending.Add((path, status));
                    else File.Delete(path);
                }
                catch (JsonException) { File.Move(path, path + ".rejected", true); }
                catch (IOException) { /* A writer or antivirus may temporarily own the file. */ }
            }
            _processingStatusBatch = true;
            try
            {
                foreach (var item in pending.OrderBy(p => p.Status.At))
                {
                    var slot = State.Slots.FirstOrDefault(s => s.Id == item.Status.TaskId && s.Occupied);
                    if (slot != null) ApplyStatusEvent(slot, item.Status);
                }
            }
            finally { _processingStatusBatch = false; }
            // Persist once per bounded batch. Retain event files on write failure
            // so the in-memory update can be checkpointed again next heartbeat.
            if (_statusBatchDirty && !Save()) return;
            if (_statusBatchDirty) Dock.UpdateSummary();
            _statusBatchDirty = false;
            if (_statusBatchNotices != null) { foreach (var notice in _statusBatchNotices) if (notice.Value.Id == notice.Key && notice.Value.Unread) NotifyStatus(notice.Value); _statusBatchNotices.Clear(); }
            foreach (var item in pending) try { File.Delete(item.Path); } catch (IOException) { }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Store.Log("Status events: " + ex.Message); }
    }
    internal void ProcessPendingEvents() => ConsumeEvents();
    internal bool ApplyStatusEvent(Slot slot, StatusEvent status)
    {
        if (!slot.Occupied || slot.Id != status.TaskId) return false;
        if (slot.UpdatedAt.HasValue && status.At <= slot.UpdatedAt) return false;
        if (status.Provider != "")
        {
            if (slot.SessionId != "" && status.SessionId != "" && slot.SessionId != status.SessionId && status.EventName is not ("SessionStart" or "UserPromptSubmit")) return false;
            slot.AgentProvider = status.Provider; slot.SessionId = status.SessionId;
            slot.IntegrationConnected = !status.SessionEnded;
            if (Guid.TryParse(status.SessionId, out _)) slot.ResumeSessionId = status.SessionId;
            if (slot.LaunchMode == LaunchMode.Unconfigured) slot.LaunchMode = status.Provider == "claude" ? LaunchMode.Claude : LaunchMode.Codex;
            if (status.ProjectDirectory != "") slot.ProjectDirectory = status.ProjectDirectory;
            if (!slot.CustomName && status.SuggestedName != "") slot.Name = status.SuggestedName;
        }
        SetStatus(slot, status.State, status.Provider == "" ? "外部事件" : status.Provider == "claude" ? "Claude Code hooks" : "Codex hooks", status.Message, status.At);
        slot.Refresh(); return true;
    }
    private bool RememberPlacement(Slot slot)
    {
        if (State.Layout.Count > 0 || !Native.Matches(slot.Window) || Native.IsIconic(new(slot.Window!.Handle))) return false;
        var placement = Native.PlacementOf(new(slot.Window!.Handle));
        if (!placement.HasValue || (slot.LastPlacement.HasValue && WindowLayout.Same(slot.LastPlacement.Value, placement.Value))) return false;
        slot.LastPlacement = placement; return true;
    }
    private void RefreshBindings() => _input?.Configure(State.Preferences, State.Slots.Where(s => s.Connected).Select(s => s.Number), _dialog || ShortcutsPaused);
    private void BeginDialog() { _dialogDepth++; _dialog = true; CancelInteraction(); Dock.ClosePreview(); RefreshBindings(); }
    private void EndDialog() { _dialogDepth = Math.Max(0, _dialogDepth - 1); _dialog = _dialogDepth > 0; if (!_disposed) RefreshConnections(); }
    public void TogglePause()
    {
        ShortcutsPaused = !ShortcutsPaused; CancelInteraction(); RefreshBindings(); Dock.UpdateSummary();
        Hint(ShortcutsPaused ? "快捷键已暂停，Tab、数字和鼠标操作交还原应用" : "任务快捷键已恢复");
    }
    public void ToggleAllSlots() { ShowingAllSlots = !ShowingAllSlots; UpdateSlotsVisibility(); }
    public void UpdateSlotsVisibility()
    {
        foreach (Slot slot in State.Slots)
        {
            if (!slot.IsDisplayed) { slot.IsDisplayed = true; slot.Refresh(); }
        }
        Dock.UpdateChrome(); Reposition();
    }
    public void ShowLoadout(Slot? focus = null)
    {
        BeginDialog();
        try { EditLoadout(focus); }
        finally { EndDialog(); }
    }
    private void EditLoadout(Slot? focus = null, Window? owner = null, Skin? previewSkin = null)
    {
        var picker = new LoadoutWindow(State.Slots, WorkArea, focus, previewSkin) { Owner = owner };
        if (picker.ShowDialog() != true) return;
        var before = State.Slots.ToDictionary(s => s.Id, EquipmentAssignment.From);
        var result = picker.Result;
        foreach (var slot in State.Slots) if (result.TryGetValue(slot.Id, out var equipment)) equipment.Apply(slot);
        if (!Save()) { foreach (var slot in State.Slots) before[slot.Id].Apply(slot); Hint("配装未保存，请检查配置目录是否可写"); return; }
        Dock.UpdateChrome(); Hint("主题配装已保存 · 右键槽位可再次更换");
    }
    public void ShowSettings()
        => ShowSettingsPage(2);
    public void ShowSettingsPage(int page)
    {
        string warnings = string.Join("\n", _input.Warnings);
        BeginDialog();
        try
        {
            var settings = new SettingsWindow(State.Preferences, WorkArea, warnings, State.AutoHide, State.MinimizeOnCapture, page, ShortcutsPaused);
            settings.ShortcutAvailabilityCheck = p => InputService.RegistrationConflict(p, State.Preferences);
            settings.ApplyThemeAsync = p => TerminalThemeService.ApplyAsync(p);
            IReadOnlyDictionary<string, EquipmentAssignment>? equipmentDraft = null;
            settings.LoadoutRequested += () => {
                var draft = LoadoutWindow.CreateDraft(State.Slots, equipmentDraft);
                var picker = new LoadoutWindow(draft, WorkArea, previewSkin: settings.LoadoutSkin, settingsDraft: true) { Owner = settings };
                if (picker.ShowDialog() == true) equipmentDraft = picker.Result;
            };
            settings.AddWindowRequested += AddWindow;
            settings.RecoveryRequested += ShowRecovery;
            settings.DataDirectoryRequested += OpenDataDirectory;
            if (settings.ShowDialog() == true)
            {
                State.Preferences = settings.Result; State.MinimizeOnCapture = settings.MinimizeOnCapture;
                if (equipmentDraft != null) foreach (var slot in State.Slots) if (equipmentDraft.TryGetValue(slot.Id, out var assignment)) assignment.Apply(slot);
                if (settings.PauseShortcuts != ShortcutsPaused) TogglePause();
                if (settings.ResetDockPositionRequested) ResetDockPosition();
                ApplyAudioPreferences();
                InkEffects.CancelVisuals();
                SkinCatalog.DecorationsEnabled = State.Preferences.DecorationsEnabled;
                WuxiaTheme.Apply(State.Preferences.Skin, State.Preferences.Animate);
                foreach (var slot in State.Slots) slot.Refresh();
                Dock.RefreshTheme(); RefreshTrayTheme(); SetAutoHide(settings.AutoHide); Save(); UpdateSlotsVisibility();
                _tray.ContextMenuStrip!.Items[1].Text = InventoryMenuLabel;
                Hint("设置已保存 · " + settings.TerminalApplyMessage);
            }
        }
        finally { EndDialog(); }
    }
    public void ConnectAgent(Slot slot, string provider)
    {
        BeginDialog();
        try
        {
            var window = new IntegrationWindow(slot, provider, Store.Root, WorkArea); window.ShowDialog();
        }
        finally { EndDialog(); }
    }
    private void DisplayChanged(object? sender, EventArgs args)
    {
        if (_disposed) return;
        Dock.Dispatcher.BeginInvoke(() =>
        {
            if (_disposed) return;
            CancelInteraction(); var screen = Native.ScreenAt(State.Preferences.DockAnchor); WorkArea = screen.Work; _scale = screen.Scale; Reposition();
            Hint("显示器布局已更新，窗口唤出时会校正可见位置");
        });
    }
    public void OpenDataDirectory() => Process.Start(new ProcessStartInfo("explorer.exe", Store.Root) { UseShellExecute = true });
    public void AddWindow()
    {
        var empty = State.Slots.FirstOrDefault(s => !s.Occupied);
        if (empty != null) PickWindow(empty); else Hint("九个槽位已满，请先移出一个任务");
    }
    public void ShowHelp()
    {
        string? next = null;
        string warnings = string.Join("\n", _input.Warnings);
        BeginDialog();
        try
        {
            var guide = new GettingStartedWindow(State.Preferences, WorkArea, warnings, ShortcutsPaused);
            guide.ShowDialog(); next = guide.NextAction;
            State.Preferences.HasSeenIntroduction = true; Save();
        }
        finally { EndDialog(); }
        if (next == "add") AddWindow();
        else if (next == "keys") ShowSettingsPage(0);
        else if (next == "recovery") ShowRecovery();
    }
    public void Exit()
    {
        if (Exiting) return;
        Exiting = true; Dispose(); Application.Current.Shutdown();
    }
    public void Dispose()
    {
        if (_disposed) return; _disposed = true; Exiting = true;
        _heartbeat.Stop(); _dragTimer.Stop();
        CheckpointWindows();
        _input.Dispose(); CancelInteraction(); Dock.ClosePreview(); InkEffects.CancelVisuals();
        GameAudio.Stop();
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= DisplayChanged;
        RestorePopup(restoreFocus: false);
        if (State.Layout.Count > 0) RestoreLayout();
        foreach (Slot slot in State.Slots)
        {
            ReleaseSlotWindow(slot); slot.ParkedByApp = false;
        }
        Save(); _tray.Visible = false; _tray.Dispose(); _trayIcon.Dispose();
    }
}
