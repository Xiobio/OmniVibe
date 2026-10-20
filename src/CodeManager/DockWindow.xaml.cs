using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using System.Windows.Controls.Primitives;

namespace CodeManager;

public partial class DockWindow : Window
{
    public Manager? Manager { get; set; }
    public bool Collapsed { get; private set; }
    public bool MenuOpen => _activeMenu?.IsOpen == true;
    public double DesiredDockHeight => Math.Max(440, Manager?.State.Preferences.DockWidth ?? Width) + 70;
    private Slot? _hover;
    private SlotHintWindow? _preview;
    private bool _hoveringRemove;
    private Slot? _removePressed;
    internal bool HoverHintVisible => _preview?.IsVisible == true;
    internal int? HoverHintNumber => _preview?.Slot.Number;
    private Slot? _dragSlot;
    private Point _dragOrigin;
    private bool _sorting;
    private Native.Rect _boundsAtDragStart;
    private Native.Point _cursorAtDragStart;
    private bool _boundsDragging;
    private bool _moveArmed;
    private readonly DispatcherTimer _retractDelay;
    private readonly DispatcherTimer _holdDelay;
    private bool _corePressed, _rightPressed;
    private Point _corePressPoint;
    private Slot? _rightSlot;
    private ContextMenu? _activeMenu;
    private DateTime? _outsideSince;
    private string _hint = "";
    internal const double CompactExtent = 116;
    private bool _compactHost, _suppressHoverUntilLeave;
    private double _deckExtent = 360, _hostExtent = CompactExtent, _hostScale = 1;
    private Point _coreScreen;
    private IntPtr _menuPreviousFocus;
    private bool _dismissMenuRelease;
    private bool _openOnCoreTap;
    private DateTime _menuClosedAt;
    public bool IsManipulating => _sorting || _boundsDragging || _corePressed || _rightPressed || _removePressed != null;
    internal bool IsTransitioning => WeaponWheel.DeploymentInMotion;
    public DockWindow(bool interactionTest = false)
    {
        InitializeComponent();
        RefreshTheme();
        SizeChanged += (_, _) => { if (!_compactHost) LayoutWheel(); };
        EquipmentViewport.SizeChanged += (_, _) => { if (!_compactHost) LayoutWheel(); };
        WeaponWheel.DeploymentSettled += () => { if (_compactHost && !WeaponWheel.IsDeployed) ResizeHost(false); };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape && _sorting) { _dragSlot = null; _sorting = false; ReleaseMouseCapture(); ClearDropMarks(); e.Handled = true; } };
        LostMouseCapture += (_, _) => { if (Mouse.Captured == WeaponWheel) return; if (_boundsDragging) FinishDockMove(); _corePressed = false; _rightPressed = false; _removePressed = null; _holdDelay?.Stop(); _dragSlot = null; _sorting = false; ClearDropMarks(); };
        _holdDelay = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        _holdDelay.Tick += (_, _) => { _holdDelay.Stop(); if (_corePressed && Native.Down(0x01)) PromoteCoreDrag(); };
        ToolTipService.SetIsEnabled(WeaponWheel, false);
        _retractDelay = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(24) };
        _retractDelay.Tick += (_, _) =>
        {
            Native.GetCursorPos(out var p);
            if (_suppressHoverUntilLeave && (WeaponWheel.PointFromScreen(new Point(p.X, p.Y)) - WeaponWheel.Centre).Length > 66) _suppressHoverUntilLeave = false;
            if (!WeaponWheel.IsDeployed) { if (!_suppressHoverUntilLeave) _retractDelay.Stop(); return; }
            var point = WeaponWheel.PointFromScreen(new Point(p.X, p.Y));
            if (!IsManipulating && !MenuOpen) HandleWheelPointerMove(point);
            CheckRetraction(point, DateTime.UtcNow);
        };
        MouseLeave += (_, _) => { if (!_corePressed && !_boundsDragging) _retractDelay.Start(); };
        SourceInitialized += (_, _) =>
        {
            if (!interactionTest) { Native.Decorate(this); Native.RemoveOverlayFrame(this); }
            System.Windows.Interop.HwndSource.FromHwnd(new System.Windows.Interop.WindowInteropHelper(this).Handle)?.AddHook(PointerMessage);
        };
        if (interactionTest) { ShowInTaskbar = true; ShowActivated = true; Title = L.T("CodeManager · 交互验证（示例任务）"); }
        Closing += (_, e) => { if (Manager != null && !Manager.Exiting) { e.Cancel = true; if (interactionTest) Manager.Exit(); else Manager.ToggleVisibility(); } };
        Closed += (_, _) => { CompositionTarget.Rendering -= DragFrame; _holdDelay.Stop(); _retractDelay.Stop(); if (_activeMenu != null) _activeMenu.IsOpen = false; ClosePreview(); };
    }
    private void LayoutWheel()
    {
        EquipmentViewport.Width = _compactHost ? _hostExtent : Math.Max(1, ActualWidth > 1 ? ActualWidth : Width);
        EquipmentViewport.Height = _compactHost ? _hostExtent : Math.Max(1, ActualHeight > 1 ? ActualHeight : Height);
        WeaponWheel.Width = _compactHost ? _deckExtent : Math.Max(1, (ActualWidth > 1 ? ActualWidth : Width) - 6);
        WeaponWheel.Height = _compactHost ? _deckExtent : Math.Max(1, (ActualHeight > 1 ? ActualHeight : Height) - 82);
        Canvas.SetLeft(WeaponWheel, _compactHost ? (_hostExtent - _deckExtent) / 2 : 3);
        Canvas.SetTop(WeaponWheel, _compactHost ? (_hostExtent - _deckExtent) / 2 : 34);
    }
    internal void PlaceCompactHost(Native.Point centre, double scale, double extent)
    {
        _compactHost = true; _coreScreen = new Point(centre.X, centre.Y); _hostScale = scale;
        _deckExtent = Math.Clamp(extent, 320, 480);
        ResizeHost(WeaponWheel.IsDeployed || WeaponWheel.DeploymentInMotion);
    }
    private void ResizeHost(bool expanded)
    {
        if (!_compactHost) return;
        _hostExtent = expanded ? _deckExtent : CompactExtent;
        LayoutWheel();
        int size = (int)Math.Round(_hostExtent * _hostScale);
        Native.SetWindowPos(new System.Windows.Interop.WindowInteropHelper(this).Handle, new IntPtr(-1), (int)Math.Round(_coreScreen.X - size / 2d), (int)Math.Round(_coreScreen.Y - size / 2d), size, size, 0x0010);
        UpdateLayout();
    }
    internal Point CoreScreen => WeaponWheel.PointToScreen(WeaponWheel.Centre);
    internal bool CompactHostEnabled => _compactHost;
    public void SetSlots(System.Collections.Generic.IEnumerable<Slot> slots) { WeaponWheel.SetSlots(slots); WeaponWheel.MotionEnabled = Manager?.State.Preferences.Animate == true; }
    public void SetCollapsed(bool collapsed)
    {
        if (Collapsed == collapsed) return;
        ClosePreview();
        Collapsed = collapsed;
        if (collapsed) SetEquipmentDeployment(false);
    }
    internal void SetEquipmentDeployment(bool expanded, bool? animate = null)
    {
        bool changed = WeaponWheel.IsDeployed != expanded;
        WeaponWheel.CaptureTargetsVisible = expanded && Manager?.Dragging == true;
        if (!_compactHost) LayoutWheel();
        bool motion = (animate ?? Manager?.State.Preferences.Animate == true) && SkinCatalog.DecorationsEnabled;
        if (_compactHost && expanded && !WeaponWheel.IsDeployed) ResizeHost(true);
        WeaponWheel.Deploy(expanded, motion);
        if (_compactHost && !expanded && !motion) ResizeHost(false);
        _outsideSince = null;
        if (!expanded) { _retractDelay.Stop(); ClosePreview(); WeaponWheel.ToolTip = null; }
        else if (Manager != null) _retractDelay.Start();
        if (changed) Manager?.PlayCue(expanded ? AudioCue.Expand : AudioCue.Collapse);
    }
    internal bool PointerNearInstrument(Native.Point point)
    {
        var p = WeaponWheel.PointFromScreen(new Point(point.X, point.Y));
        return WeaponWheel.IsDeployed ? (p - WeaponWheel.Centre).Length <= WeaponWheel.Radius * .8 + 54 : WeaponWheel.InCore(p);
    }
    // Poll geometry rather than MouseLeave: alpha-zero gaps are real desktop, not exit intent.
    internal void CheckRetraction(Point point, DateTime now)
    {
        if (!WeaponWheel.IsDeployed || IsManipulating || MenuOpen || Manager?.Dragging == true ||
            (point - WeaponWheel.Centre).Length <= WeaponWheel.Radius * .8 + 68)
        { _outsideSince = null; return; }
        _outsideSince ??= now;
        if (now - _outsideSince.Value >= TimeSpan.FromMilliseconds(400)) SetEquipmentDeployment(false);
    }
    public void UpdateSummary()
    {
        if (Manager != null) WeaponWheel.MotionEnabled = Manager.State.Preferences.Animate;
    }
    public void UpdateChrome() { WeaponWheel.InvalidateVisual(); UpdateSummary(); }
    public void SetHint(string text) => _hint = text;
    public void RefreshTheme()
    {
        NativeSkinArt.Warm(SkinCatalog.Current);
        ThemeIdentityArt.Image(SkinCatalog.Current.Id);
        var skin = SkinCatalog.Current;
        Title = "OmniVibe · " + skin.DockTitle;
        Background = Brushes.Transparent;
        WeaponWheel.InvalidateVisual();
        UpdateSummary();
    }
    private void ArmDockMove()
    {
        _moveArmed = true; WeaponWheel.Cursor = Cursors.SizeAll;
        SetEquipmentDeployment(false);
    }
    internal void BeginCorePress(Point point, bool capture = true)
    {
        // The click dismissing a popup must not also equip/open the surface below it.
        _openOnCoreTap = !_suppressHoverUntilLeave && DateTime.UtcNow - _menuClosedAt > TimeSpan.FromMilliseconds(180);
        CloseMenu();
        SetEquipmentDeployment(false, false);
        _corePressed = true; _corePressPoint = point;
        Native.GetCursorPos(out _cursorAtDragStart);
        Native.GetWindowRect(new System.Windows.Interop.WindowInteropHelper(this).Handle, out _boundsAtDragStart);
        _retractDelay.Stop(); ClosePreview(); WeaponWheel.Hover(null);
        if (capture) Mouse.Capture(WeaponWheel, CaptureMode.Element);
        if (_moveArmed || Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) PromoteCoreDrag();
        else _holdDelay.Start();
    }
    internal void PromoteCoreDrag()
    {
        if (!_corePressed || _boundsDragging) return;
        _holdDelay.Stop();
        _moveArmed = false; _boundsDragging = true;
        WeaponWheel.Cursor = Cursors.SizeAll;
        CompositionTarget.Rendering += DragFrame;
        Manager?.DragDockBounds(_boundsAtDragStart, _cursorAtDragStart, false);
    }
    internal void EndCorePress()
    {
        if (!_corePressed && !_boundsDragging) return;
        _holdDelay.Stop(); _corePressed = false;
        if (_boundsDragging) FinishDockMove();
        else { if (IsMouseCaptureWithin) Mouse.Capture(null); SetEquipmentDeployment(_openOnCoreTap); }
    }
    private void FinishDockMove()
    {
        CompositionTarget.Rendering -= DragFrame;
        Manager?.DragDockBounds(_boundsAtDragStart, _cursorAtDragStart, false);
        _boundsDragging = false; WeaponWheel.Cursor = Cursors.Hand;
        if (IsMouseCaptureWithin) Mouse.Capture(null);
        Manager?.CommitDockMove();
        _suppressHoverUntilLeave = true; _retractDelay.Start();
    }
    private void DragFrame(object? sender, EventArgs e) { if (_boundsDragging) Manager?.DragDockBounds(_boundsAtDragStart, _cursorAtDragStart, false); }
    public void CancelManipulation() { CloseMenu(); _holdDelay.Stop(); _corePressed = false; _rightPressed = false; if (_boundsDragging) FinishDockMove(); _moveArmed = false; WeaponWheel.Cursor = Cursors.Hand; _dragSlot = null; _sorting = false; SetEquipmentDeployment(false); if (IsMouseCaptureWithin) Mouse.Capture(null); ClearDropMarks(); }
    // Layered/no-activate hosts can receive Win32 button messages without WPF promoting
    // them to routed button events. Own this host's buttons once at the native boundary.
    private IntPtr PointerMessage(IntPtr hwnd, int message, IntPtr wparam, IntPtr lparam, ref bool handled)
    {
        bool moving = message == 0x200 && (_corePressed || _boundsDragging || _dragSlot != null);
        if (!moving && message is not (0x201 or 0x202 or 0x203 or 0x204 or 0x205)) return IntPtr.Zero;
        var source = System.Windows.Interop.HwndSource.FromHwnd(hwnd);
        long packed = lparam.ToInt64();
        var client = new Point(unchecked((short)(packed & 0xffff)), unchecked((short)((packed >> 16) & 0xffff)));
        var logical = source?.CompositionTarget?.TransformFromDevice.Transform(client) ?? client;
        var point = TranslatePoint(logical, WeaponWheel);
        if (moving) TrackPointerDrag(point, Native.Down(0x01));
        else HandlePointerButton(message is 0x204 or 0x205 ? MouseButton.Right : MouseButton.Left, message is 0x201 or 0x203 or 0x204, point);
        handled = true; return IntPtr.Zero;
    }
    internal void HandlePointerButton(MouseButton button, bool down, Point point)
    {
        if (_dismissMenuRelease) { if (!down) _dismissMenuRelease = false; return; }
        if (MenuOpen) { if (down) { CloseMenu(); _dismissMenuRelease = true; } return; }
        if (button == MouseButton.Right)
        {
            if (down)
            {
                Slot? slot = WeaponWheel.InCore(point) ? null : WeaponWheel.HitSlot(point);
                if (IsManipulating) CancelManipulation(); else ClosePreview();
                _rightSlot = slot; _rightPressed = true;
                Mouse.Capture(WeaponWheel, CaptureMode.Element);
            }
            else
            {
                Slot? slot = _rightSlot ?? (_rightPressed ? null : WeaponWheel.HitSlot(point));
                _rightPressed = false; _rightSlot = null;
                if (IsMouseCaptureWithin) Mouse.Capture(null);
                SetEquipmentDeployment(false, false);
                OpenWheelMenu(slot);
            }
            return;
        }
        if (button != MouseButton.Left) return;
        if (down && WeaponWheel.HitRemove(point) is Slot removal) {
            _removePressed = removal; ClosePreview(); Mouse.Capture(WeaponWheel, CaptureMode.Element); return;
        }
        if (!down && _removePressed is Slot pressed) {
            _removePressed = null;
            bool remove = WeaponWheel.HitRemove(point) == pressed;
            if (IsMouseCaptureWithin) Mouse.Capture(null);
            if (remove) { Manager?.Remove(pressed); WeaponWheel.Hover(null); }
            return;
        }
        if (down)
        {
            if (WeaponWheel.InCore(point)) BeginCorePress(point);
            else if (WeaponWheel.HitSlot(point) is { Occupied: true } task)
            { _dragSlot = task; _dragOrigin = WeaponWheel.TranslatePoint(point, this); }
            return;
        }
        if (_corePressed || _boundsDragging) { EndCorePress(); return; }
        var sourceSlot = _dragSlot; bool sorting = _sorting;
        _dragSlot = null; _sorting = false;
        var target = WeaponWheel.HitSlot(point);
        if (sorting && sourceSlot != null)
        {
            if (IsMouseCaptureWithin) Mouse.Capture(null);
            ClearDropMarks(); var p = WeaponWheel.TranslatePoint(point, this);
            CompleteSlotDrop(sourceSlot, target, p.X < -28 || p.X > ActualWidth + 28 || p.Y < -28 || p.Y > ActualHeight + 28);
        }
        else if (target != null && Manager != null)
        {
            ClosePreview();
            if (target.Connected) Manager.ActivateSlot(target.Number); else Manager.PickWindow(target);
        }
    }
    internal void TrackPointerDrag(Point point, bool leftDown)
    {
        if (_corePressed || _boundsDragging)
        {
            if (!leftDown) { EndCorePress(); return; }
            if (!_boundsDragging && (point - _corePressPoint).Length >= 3) PromoteCoreDrag();
            return;
        }
        if (_dragSlot == null || !leftDown || Manager == null) return;
        Point p = WeaponWheel.TranslatePoint(point, this);
        if (!_sorting && (p - _dragOrigin).Length < 9) return;
        if (!_sorting) { _sorting = true; ClosePreview(); Mouse.Capture(WeaponWheel, CaptureMode.Element); }
        var target = WeaponWheel.HitSlot(point);
        foreach (var slot in Manager.State.Slots) { slot.IsDropTarget = slot == target && slot != _dragSlot; slot.Refresh(); }
    }
    internal void CompleteSlotDrop(Slot source, Slot? target, bool outside)
    {
        if (target != null && target != source) Manager?.ReorderSlot(source, target);
        else if (outside) Manager?.Remove(source);
    }
    private void ClearDropMarks() { if (Manager == null) return; foreach (var s in Manager.State.Slots) { s.IsDropTarget = false; s.Refresh(); } }
    public Slot? HitSlot(Native.Point cursor)
    {
        if (!IsVisible) return null;
        return WeaponWheel.HitSlot(WeaponWheel.PointFromScreen(new Point(cursor.X, cursor.Y)), Manager?.Dragging == true);
    }
    public void Pulse(Slot slot, bool capture = true)
    {
        Dispatcher.BeginInvoke(() => WeaponWheel.Pulse(slot, Manager?.State.Preferences.Animate != false));
    }
    private void WheelHover(object sender, MouseEventArgs e) => HandleWheelPointerMove(e.GetPosition(WeaponWheel));
    internal void HandleWheelPointerMove(Point point)
    {
        if (_suppressHoverUntilLeave && (point - WeaponWheel.Centre).Length > 66) _suppressHoverUntilLeave = false;
        if (IsManipulating || MenuOpen || _moveArmed || _suppressHoverUntilLeave) return;
        if (!WeaponWheel.IsDeployed && WeaponWheel.InCore(point))
        {
            Manager?.Expand(); SetEquipmentDeployment(true);
        }
        if ((point - WeaponWheel.Centre).Length <= WeaponWheel.Radius * .8 + 54) _outsideSince = null;
        Slot? slot = WeaponWheel.HitSlot(point);
        if (WeaponWheel.Hover(slot) && slot != null) Manager?.PlayCue(AudioCue.Detent, slot);
        bool removing = WeaponWheel.HitRemove(point) != null;
        WeaponWheel.RemoveHovered = removing;
        if (_sorting || Manager?.Dragging == true || (_hover == slot && _hoveringRemove == removing)) return;
        ClosePreview();
        _hover = slot; _hoveringRemove = removing;
        if (slot != null) ShowPreview();
    }
    internal void OpenWheelMenu(Slot? slot = null)
    {
        if (slot != null) ShowSlotMenu(WeaponWheel, slot); else MenuClick(WeaponWheel, new RoutedEventArgs());
    }
    private MenuItem Item(string title, Action action, bool enabled = true)
    {
        var item = new MenuItem { Header = title, IsEnabled = enabled };
        item.Click += (_, e) => { e.Handled = true; CloseMenu(); action(); }; return item;
    }
    internal ContextMenu CreateMenu()
    {
        var menu = new ContextMenu { StaysOpen = false, FontSize = 12, MinWidth = 184, MaxWidth = 250 };
        var row = new Style(typeof(MenuItem), (Style)Application.Current.FindResource(typeof(MenuItem)));
        row.Setters.Add(new Setter(FontSizeProperty, 12d));
        row.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(8, 5, 8, 5)));
        menu.Resources[typeof(MenuItem)] = row;
        menu.Resources[SystemParameters.MenuPopupAnimationKey] = PopupAnimation.None;
        menu.Template = (ControlTemplate)System.Windows.Markup.XamlReader.Parse(L.T("""
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="ContextMenu">
  <Border Background="{DynamicResource SkinBackgroundBrush}" BorderBrush="{DynamicResource SkinBorderBrush}" BorderThickness="1" CornerRadius="9" Padding="6">
    <StackPanel>
      <DockPanel Margin="8,0,0,5">
        <Button x:Name="CloseMenuButton" DockPanel.Dock="Right" Content="×" Width="26" Height="24" FontSize="16" Focusable="False" Foreground="{DynamicResource SkinMutedBrush}" Background="Transparent" BorderThickness="0" Padding="0" ToolTip="关闭 · Esc"/>
        <TextBlock Text="快捷操作" FontSize="10" Foreground="{DynamicResource SkinMutedBrush}" VerticalAlignment="Center"/>
      </DockPanel>
      <ItemsPresenter/>
    </StackPanel>
  </Border>
</ControlTemplate>
"""));
        menu.Loaded += (_, _) =>
        {
            if (menu.Parent is Popup popup) popup.PopupAnimation = PopupAnimation.None;
            if (menu.Template.FindName("CloseMenuButton", menu) is Button close) close.Click += (_, _) => CloseMenu();
        };
        menu.PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { CloseMenu(); e.Handled = true; } };
        return menu;
    }
    internal void CloseMenu()
    {
        var menu = _activeMenu; _activeMenu = null;
        if (menu == null) return;
        _menuClosedAt = DateTime.UtcNow;
        menu.IsOpen = false;
        var foreground = Native.GetForegroundWindow();
        Native.GetWindowThreadProcessId(foreground, out uint foregroundProcess);
        if (_menuPreviousFocus != IntPtr.Zero && Native.IsWindow(_menuPreviousFocus) && foregroundProcess == Environment.ProcessId && foreground != _menuPreviousFocus)
            Native.SetForegroundWindow(_menuPreviousFocus);
        _outsideSince = null;
        _suppressHoverUntilLeave = true;
        if (_retractDelay != null) _retractDelay.Start();
    }
    internal void DismissMenuOutside(Native.Point point)
    {
        if (!MenuOpen || _activeMenu == null) return;
        bool Contains(FrameworkElement element)
        {
            if (!element.IsVisible || PresentationSource.FromVisual(element) == null) return false;
            var top = element.PointToScreen(new Point());
            var bottom = element.PointToScreen(new Point(element.ActualWidth, element.ActualHeight));
            return point.X >= top.X && point.X < bottom.X && point.Y >= top.Y && point.Y < bottom.Y;
        }
        bool InMenu(ItemsControl items)
        {
            if (Contains(items)) return true;
            foreach (var child in items.Items.OfType<MenuItem>())
                if (child.IsSubmenuOpen && child.Template.FindName("PART_Popup", child) is Popup { Child: FrameworkElement popup } && (Contains(popup) || InMenu(child))) return true;
            return false;
        }
        if (!InMenu(_activeMenu)) CloseMenu();
    }
    private void OpenMenu(FrameworkElement target, ContextMenu menu)
    {
        CloseMenu(); ClosePreview(); _activeMenu = menu;
        target.ContextMenu = menu;
        menu.PlacementTarget = target;
        menu.Placement = PlacementMode.MousePoint;
        menu.Resources[SystemParameters.MenuPopupAnimationKey] = PopupAnimation.None;
        menu.Closed += (_, _) => { if (_activeMenu == menu) CloseMenu(); _outsideSince = null; };
        // Opening a menu is an explicit focus action; hovering the ring stays nonactivating.
        _menuPreviousFocus = Native.GetForegroundWindow();
        Native.SetForegroundWindow(new System.Windows.Interop.WindowInteropHelper(this).Handle);
        menu.IsOpen = true;
    }
    private void ShowSlotMenu(FrameworkElement target, Slot slot)
    {
        if (Manager == null) return;
        var menu = CreateMenu();
        if (slot.Connected) menu.Items.Add(Item(L.T("进入任务"), () => Manager.ActivateSlot(slot.Number)));
        menu.Items.Add(Item(L.T("更换角色 / 配装…"), () => Manager.ShowLoadout(slot)));
        if (slot.Occupied) menu.Items.Add(Item(L.T("编辑任务"), () => Manager.Rename(slot)));
        var advanced = new MenuItem { Header = L.T("更多任务操作") };
        var legacy = new ContextMenu();
        if (slot.Occupied)
        {
            legacy.Items.Add(Item(L.T("唤出窗口"), () => Manager.ActivateSlot(slot.Number), slot.Connected));
            legacy.Items.Add(Item(L.T("编辑名称、颜色与项目…"), () => Manager.Rename(slot)));
            legacy.Items.Add(Item(L.T("恢复这个任务（自动打开并重连）"), () => { if (RecoveryLaunch.Validation(slot) != null) Manager.Rename(slot); SetHint(Manager.RestoreTask(slot)); }, !slot.Connected && slot.Recovery == null));
            legacy.Items.Add(Item(L.T("收起窗口"), () => Manager.Park(slot), slot.Connected));
            legacy.Items.Add(new Separator());
            var statuses = new MenuItem { Header = L.T("手动标记状态") };
            foreach (var state in Enum.GetValues<AgentState>())
            {
                string label = state switch { AgentState.Unknown => L.T("状态未知"), AgentState.Running => L.T("正在执行"), AgentState.Waiting => L.T("等待我处理"), AgentState.Ready => L.T("本轮已回复"), _ => L.T("发生错误") };
                statuses.Items.Add(Item(label, () => Manager.SetStatus(slot, state, "手动标记", "")));
            }
            legacy.Items.Add(statuses);
            legacy.Items.Add(Item(L.T("标记已查看"), () => Manager.MarkRead(slot)));
            menu.Items.Add(Item(L.T("连接当前 CLI 会话状态…"), () => Manager.ConnectExistingSession(slot)));
            var integration = new MenuItem { Header = L.T("精确状态 hooks 接入") };
            integration.Items.Add(Item("Claude Code…", () => Manager.ConnectAgent(slot, "claude")));
            integration.Items.Add(Item("Codex…", () => Manager.ConnectAgent(slot, "codex")));
            legacy.Items.Add(integration);
            var move = new MenuItem { Header = L.T("移动到槽位") };
            foreach (Slot destination in Manager.State.Slots.Where(s => !s.Occupied))
                move.Items.Add(Item(L.T("槽位 ") + destination.Number, () => Manager.MoveSlot(slot, destination)));
            move.IsEnabled = move.Items.Count > 0; legacy.Items.Add(move);
            legacy.Items.Add(new Separator());
        }
        legacy.Items.Add(Item(slot.Occupied ? L.T("重新连接窗口（保留名称）…") : L.T("选择一个已有窗口…"), () => Manager.PickWindow(slot)));
        if (slot.Occupied) legacy.Items.Add(Item(L.T("移出武器栏（保留窗口）"), () => Manager.Remove(slot)));
        legacy.Items.Add(new Separator());
        var management = new MenuItem { Header = L.T("OmniVibe 管理") };
        var commands = BuildManagementMenu();
        while (commands.Items.Count > 0) { var command = commands.Items[0]; commands.Items.RemoveAt(0); management.Items.Add(command); }
        legacy.Items.Add(management);
        while (legacy.Items.Count > 0) { var command = legacy.Items[0]; legacy.Items.RemoveAt(0); advanced.Items.Add(command); }
        if (!slot.Occupied) menu.Items.Add(Item(L.T("选择窗口"), () => Manager.PickWindow(slot)));
        menu.Items.Add(advanced);
        if (slot.Occupied) menu.Items.Add(Item(L.T("移出管理"), () => Manager.Remove(slot)));
        OpenMenu(target, menu);
    }
    private void MenuClick(object sender, RoutedEventArgs e)
    {
        if (Manager == null) return;
        OpenMenu((FrameworkElement)sender, BuildManagementMenu());
    }
    internal ContextMenu BuildManagementMenu()
    {
        var menu = CreateMenu();
        if (Manager == null) return menu;
        menu.Items.Add(Item(L.T("添加窗口"), AddWindow, Manager.State.Slots.Any(s => !s.Occupied)));
        menu.Items.Add(Item(L.T("任务总览"), () => Manager.ToggleInventory()));
        menu.Items.Add(Item(Manager.State.Layout.Count > 0 ? L.T("恢复布局") : L.T("排列窗口"), () => Manager.RequestOverview()));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L.T("设置"), () => Manager.ShowSettings()));
        menu.Items.Add(Item(L.T("最近任务 / 恢复工作现场"), () => Manager.ShowRecovery()));
        menu.Items.Add(Item(L.T("快速上手"), () => Manager.ShowHelp()));
        menu.Items.Add(Item(L.T("隐藏悬浮入口"), () => Manager.ToggleVisibility()));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L.T("退出 · 终端继续运行"), () => Manager.Exit()));
        return menu;
    }
    private void AddWindow()
    {
        var empty = Manager?.State.Slots.FirstOrDefault(s => !s.Occupied);
        if (empty != null) Manager!.PickWindow(empty); else Manager?.ToggleInventory();
    }
    private void SlotLeave(object sender, MouseEventArgs e)
    {
        // Native teardown can send MouseLeave after the visual loses its HWND.
        // PointFromScreen requires a live presentation source even during exit.
        if (PresentationSource.FromVisual(WeaponWheel) == null) { ClosePreview(); return; }
        Native.GetCursorPos(out var cursor);
        var point = WeaponWheel.PointFromScreen(new Point(cursor.X,cursor.Y));
        if (WeaponWheel.IsDeployed && WeaponWheel.HitSlot(point) != null) return;
        if (!IsManipulating) WeaponWheel.Hover(null);
        ClosePreview();
    }
    private void ShowPreview()
    {
        if (_hover == null || Manager == null || Manager.Dragging || Manager.Selecting || MenuOpen) return;
        _preview?.Close();
        _preview = new SlotHintWindow(_hover, _hoveringRemove);
        _preview.Show();
        var source = PresentationSource.FromVisual(this);
        double scale = source?.CompositionTarget?.TransformToDevice.M11 ?? 1;
        var origin = PointToScreen(new System.Windows.Point(0, 0));
        var area = Manager.WorkArea;
        double x = origin.X - 328 * scale;
        if (x < area.Left) x = origin.X + (ActualWidth + 12) * scale;
        x = Math.Clamp(x, area.Left, Math.Max(area.Left, area.Right - 316 * scale));
        var target = WeaponWheel.PointToScreen(WeaponWheel.SlotPoint(_hover.Number));
        int height = (int)Math.Ceiling(_preview.ActualHeight * scale);
        double y = Math.Clamp(target.Y - height/2d, area.Top, Math.Max(area.Top, area.Bottom - height));
        Native.SetWindowPos(new System.Windows.Interop.WindowInteropHelper(_preview).Handle, new IntPtr(-1), (int)x, (int)y, (int)(316 * scale), height, 0x10);
    }
    public void ClosePreview() { _hover = null; _preview?.Close(); _preview = null; }
    public void SetPreviewLabel(bool allSlots = false)
    {
        WeaponWheel.InvalidateVisual();
    }
}
