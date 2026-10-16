using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using System.Windows.Controls.Primitives;

namespace CodeManager;

public partial class DockWindow : Window
{
    public Manager? Manager { get; set; }
    public bool Collapsed { get; private set; }
    public bool MenuOpen { get; private set; }
    public double DesiredDockHeight => Collapsed ? 86 + SlotsList.Items.Cast<Slot>().Count(s => s.IsDisplayed) * 32 : 190 + SlotsList.Items.Cast<Slot>().Count(s => s.IsDisplayed) * 60;
    private readonly DispatcherTimer _previewDelay;
    private Slot? _hover;
    private PreviewWindow? _preview;
    private Slot? _dragSlot;
    private Point _dragOrigin;
    private bool _sorting;
    private Native.Rect _boundsAtDragStart;
    private Native.Point _cursorAtDragStart;
    private bool _boundsDragging;
    public bool IsManipulating => _sorting || _boundsDragging;
    public DockWindow(bool interactionTest = false)
    {
        InitializeComponent();
        RefreshTheme();
        PreviewMouseLeftButtonDown += BeginSlotDrag;
        PreviewMouseMove += TrackSlotDrag;
        PreviewMouseLeftButtonUp += EndSlotDrag;
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape && _sorting) { _dragSlot = null; _sorting = false; ReleaseMouseCapture(); ClearDropMarks(); e.Handled = true; } };
        LostMouseCapture += (_, _) => { _dragSlot = null; _sorting = false; _boundsDragging = false; ClearDropMarks(); };
        _previewDelay = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(450) };
        _previewDelay.Tick += (_, _) => { _previewDelay.Stop(); ShowPreview(); };
        SourceInitialized += (_, _) => { if (!interactionTest) Native.Decorate(this); };
        if (interactionTest) { ShowInTaskbar = true; ShowActivated = true; Title = "CodeManager · 交互验证（示例任务）"; }
        Closing += (_, e) => { if (Manager != null && !Manager.Exiting) { e.Cancel = true; if (interactionTest) Manager.Exit(); else Manager.ToggleVisibility(); } };
    }
    public void SetSlots(System.Collections.Generic.IEnumerable<Slot> slots) { SlotsList.ItemsSource = slots; MiniSlots.ItemsSource = slots; }
    public void SetCollapsed(bool collapsed)
    {
        if (Collapsed == collapsed) return;
        ClosePreview();
        Collapsed = collapsed;
        FullView.Visibility = collapsed ? Visibility.Collapsed : Visibility.Visible;
        MiniView.Visibility = collapsed ? Visibility.Visible : Visibility.Collapsed;
        if (!collapsed && Manager?.State.Preferences.Animate != false)
        {
            FullView.BeginAnimation(OpacityProperty, new DoubleAnimation(0.35, 1, TimeSpan.FromMilliseconds(140)));
            var translation = new TranslateTransform(8, 0);
            FullView.RenderTransform = translation;
            translation.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(8, 0, TimeSpan.FromMilliseconds(170)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        }
    }
    public void UpdateSummary()
    {
        if (Manager == null) return;
        int count = Manager.State.Slots.Count(s => s.Occupied);
        int unread = Manager.State.Slots.Count(s => s.Connected && (s.Unread || s.State == AgentState.Waiting));
        Summary.Text = Manager.ShortcutsPaused ? "快捷键已暂停" : Manager.Dragging ? "选择槽位，松手接入" : unread > 0 ? unread + " 项需要你查看" : count > 0 ? "所有任务 · 随时切换" : "拖入窗口 · 添加第一个任务";
        Summary.Foreground = unread > 0 ? WuxiaTheme.Gold : WuxiaTheme.Ivory;
        CountLabel.Text = count + " / 9";
        OverviewLabel.Text = Manager.State.Layout.Count > 0 ? "恢复布局" : "全部排列";
        Subtitle.Text = SkinCatalog.Current.DockTitle + " · " + StateCount() + " 在线";
    }
    private int StateCount() => Manager?.State.Slots.Count(s => s.Connected) ?? 0;
    public void UpdateChrome()
    {
        if (Manager == null) return;
        ShortcutHint.Text = Manager.TaskChord + " 1–9 唤出/恢复 · " + Manager.MouseChord + " 滚轮切换";
        DockSceneryHost.Child?.InvalidateVisual();
        OverviewShortcut.Text = Manager.State.Preferences.ArrangeGesture.Replace("Oem3", "反引号");
        ShortcutHint.ToolTip = Manager.State.Preferences.TabTogglesInventory ? Manager.State.Preferences.InventoryGesture + " 任务总览 · 滚轮浏览 / 数字直达 / 点击进入" : Manager.ToggleShortcut + " 显示 / 隐藏侧栏";
        UpdateSummary();
    }
    public void SetHint(string text) => Hint.Text = text;
    public void RefreshTheme()
    {
        var skin = SkinCatalog.Current;
        Title = "OmniVibe · " + skin.DockTitle;
        Background = WuxiaTheme.Brush(skin.Background); DockFrame.Background = WuxiaTheme.Wood;
        DockFrame.BorderBrush = WuxiaTheme.Brush(skin.Border); DockFrame.CornerRadius = new CornerRadius(skin.CornerRadius);
        DockTitle.Text = "OmniVibe"; DockTitle.FontFamily = WuxiaTheme.BodyFont;
        Subtitle.Text = skin.DockTitle; Subtitle.ToolTip = skin.Name;
        DockEmblem.FontFamily = skin.TitleFont; MiniEmblem.FontFamily = skin.TitleFont;
        DockEmblem.Text = MiniEmblem.Text = skin.Family switch { "tactical" => "⌖", "protocol" => "/", "mechanical" => "◇", "equipment" => "▣", "arsenal" => "兵", "relic" => "灵", "fantasy" => "✦", "formation" => "♟", "astral" => "✧", "wonderland" => "宝", _ => "匣" };
        DockEmblemFrame.CornerRadius = new CornerRadius(skin.Family is "fantasy" or "mechanical" ? 15 : skin.CornerRadius);
        DockSceneryHost.Child = new SkinBackdrop();
        // Recreate realized item content so its geometry and font change with the palette.
        var fullTemplate = SlotsList.ItemTemplate; var miniTemplate = MiniSlots.ItemTemplate;
        SlotsList.ItemTemplate = null; MiniSlots.ItemTemplate = null;
        SlotsList.ItemTemplate = fullTemplate; MiniSlots.ItemTemplate = miniTemplate;
        SlotsList.Items.Refresh(); MiniSlots.Items.Refresh();
        UpdateSummary();
    }
    private void DockBoundsStart(object sender, DragStartedEventArgs e) { _boundsDragging = true; Native.GetCursorPos(out _cursorAtDragStart); Native.GetWindowRect(new System.Windows.Interop.WindowInteropHelper(this).Handle, out _boundsAtDragStart); ClosePreview(); }
    private void DockMove(object sender, DragDeltaEventArgs e) => Manager?.DragDockBounds(_boundsAtDragStart, _cursorAtDragStart, false);
    private void DockResize(object sender, DragDeltaEventArgs e) => Manager?.DragDockBounds(_boundsAtDragStart, _cursorAtDragStart, true);
    private void DockBoundsDone(object sender, DragCompletedEventArgs e) { _boundsDragging = false; Manager?.Save(); }
    public void CancelManipulation() { _dragSlot = null; _sorting = false; _boundsDragging = false; if (IsMouseCaptureWithin) Mouse.Capture(null); ClearDropMarks(); }
    private void RemoveClick(object sender, RoutedEventArgs e) { if ((sender as FrameworkElement)?.DataContext is Slot slot) Manager?.Remove(slot); e.Handled = true; }
    private void BeginSlotDrag(object sender, MouseButtonEventArgs e)
    {
        DependencyObject? node = e.OriginalSource as DependencyObject;
        Slot? candidate = null;
        while (node != null && node != this)
        {
            if (node is ButtonBase or Thumb) return;
            if (node is FrameworkElement { DataContext: Slot slot } && slot.Occupied) candidate = slot;
            node = VisualTreeHelper.GetParent(node);
        }
        if (candidate != null) { _dragSlot = candidate; _dragOrigin = e.GetPosition(this); }
    }
    private void TrackSlotDrag(object sender, MouseEventArgs e)
    {
        if (_dragSlot == null || e.LeftButton != MouseButtonState.Pressed || Manager == null) return;
        Point p = e.GetPosition(this);
        if (!_sorting && Math.Abs(p.X - _dragOrigin.X) + Math.Abs(p.Y - _dragOrigin.Y) < 9) return;
        if (!_sorting) { _sorting = true; ClosePreview(); CaptureMouse(); }
        Native.GetCursorPos(out var cursor); var target = HitSlot(cursor);
        foreach (var slot in Manager.State.Slots) { slot.IsDropTarget = slot == target && slot != _dragSlot; slot.Refresh(); }
        bool outside = p.X < -28 || p.X > ActualWidth + 28 || p.Y < -28 || p.Y > ActualHeight + 28;
        SetHint(outside ? "松手移出列表 · 终端继续运行" : target != null && target != _dragSlot ? "松手移动到编号 " + target.Number : "拖到任务上排序 · 拖出侧栏移除");
        e.Handled = true;
    }
    private void EndSlotDrag(object sender, MouseButtonEventArgs e)
    {
        var source = _dragSlot; bool sorting = _sorting; Point p = e.GetPosition(this);
        _dragSlot = null; _sorting = false;
        if (!sorting || source == null || Manager == null) return;
        Native.GetCursorPos(out var cursor); var target = HitSlot(cursor); ReleaseMouseCapture(); ClearDropMarks();
        CompleteSlotDrop(source, target, p.X < -28 || p.X > ActualWidth + 28 || p.Y < -28 || p.Y > ActualHeight + 28);
        e.Handled = true;
    }
    internal void CompleteSlotDrop(Slot source, Slot? target, bool outside)
    {
        if (target != null && target != source) Manager?.ReorderSlot(source, target);
        else if (outside) Manager?.Remove(source);
    }
    private void ClearDropMarks() { if (Manager == null) return; foreach (var s in Manager.State.Slots) { s.IsDropTarget = false; s.Refresh(); } }
    public Slot? HitSlot(Native.Point cursor)
    {
        if (Collapsed || !IsVisible) return null;
        var point = PointFromScreen(new System.Windows.Point(cursor.X, cursor.Y));
        if (Manager?.Dragging != true)
        {
            if (point.X < 0 || point.Y < 0 || point.X > ActualWidth || point.Y > ActualHeight) return null;
            return (InputHitTest(point) as FrameworkElement)?.DataContext as Slot;
        }
        // The drop corridor extends inward, away from Windows' edge-snap trigger.
        if (point.X < -58 || point.X > ActualWidth + 4) return null;
        var viewportTop = SlotsScroll.TranslatePoint(new Point(0, 0), this).Y;
        if (point.Y < viewportTop || point.Y > viewportTop + SlotsScroll.ActualHeight) return null;
        foreach (Slot slot in SlotsList.Items.Cast<Slot>().Where(s => s.IsDisplayed))
        {
            if (SlotsList.ItemContainerGenerator.ContainerFromItem(slot) is not FrameworkElement container || container.ActualHeight <= 0) continue;
            double top = container.TranslatePoint(new Point(0, 0), this).Y;
            if (point.Y >= top - 3 && point.Y < top + container.ActualHeight + 3) return slot;
        }
        return null;
    }
    public void Pulse(Slot slot, bool capture = true)
    {
        if (Manager?.State.Preferences.Animate == false) return;
        Dispatcher.BeginInvoke(() =>
        {
            var presenter = (Collapsed ? MiniSlots : SlotsList).ItemContainerGenerator.ContainerFromItem(slot) as ContentPresenter;
            if (presenter != null)
            {
                presenter.BeginAnimation(OpacityProperty, null);
                presenter.RenderTransformOrigin = new Point(0.5, 0.5);
                var scale = new ScaleTransform(1, 1); presenter.RenderTransform = scale;
                var animation = new DoubleAnimation(1, capture ? 1.035 : .95, TimeSpan.FromMilliseconds(capture ? 180 : 90)) { AutoReverse = true, RepeatBehavior = new RepeatBehavior(capture ? 2 : 1), FillBehavior = FillBehavior.Stop };
                scale.BeginAnimation(ScaleTransform.ScaleXProperty, animation); scale.BeginAnimation(ScaleTransform.ScaleYProperty, animation);
                if (capture) InkEffects.Ripple(presenter);
            }
        });
    }
    private void SlotClick(object sender, MouseButtonEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is not Slot slot || Manager == null) return;
        ClosePreview();
        if (slot.Connected) Manager.ActivateSlot(slot.Number);
        else Manager.PickWindow(slot);
        e.Handled = true;
    }
    private void SlotMenu(object sender, MouseButtonEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is Slot slot) ShowSlotMenu((FrameworkElement)sender, slot);
        e.Handled = true;
    }
    private static MenuItem Item(string title, Action action, bool enabled = true)
    {
        var item = new MenuItem { Header = title, IsEnabled = enabled };
        item.Click += (_, _) => action(); return item;
    }
    private void OpenMenu(FrameworkElement target, ContextMenu menu)
    {
        ClosePreview(); MenuOpen = true;
        menu.PlacementTarget = target;
        menu.Closed += (_, _) => MenuOpen = false;
        menu.IsOpen = true;
    }
    private void ShowSlotMenu(FrameworkElement target, Slot slot)
    {
        if (Manager == null) return;
        var menu = new ContextMenu();
        menu.Items.Add(Item(Manager.InventoryMenuLabel, () => Manager.ToggleInventory()));
        if (slot.Occupied)
        {
            menu.Items.Add(Item("唤出窗口", () => Manager.ActivateSlot(slot.Number), slot.Connected));
            menu.Items.Add(Item("编辑名称、颜色与项目…", () => Manager.Rename(slot)));
            menu.Items.Add(Item("恢复这个任务（自动打开并重连）", () => { if (RecoveryLaunch.Validation(slot) != null) Manager.Rename(slot); SetHint(Manager.RestoreTask(slot)); }, !slot.Connected && slot.Recovery == null));
            menu.Items.Add(Item("收起窗口", () => Manager.Park(slot), slot.Connected));
            menu.Items.Add(new Separator());
            var statuses = new MenuItem { Header = "手动标记状态" };
            foreach (var state in Enum.GetValues<AgentState>())
            {
                string label = state switch { AgentState.Unknown => "状态未知", AgentState.Running => "正在执行", AgentState.Waiting => "等待我处理", AgentState.Ready => "本轮已回复", _ => "发生错误" };
                statuses.Items.Add(Item(label, () => Manager.SetStatus(slot, state, "手动标记", "")));
            }
            menu.Items.Add(statuses);
            menu.Items.Add(Item("标记已查看", () => Manager.MarkRead(slot)));
            var integration = new MenuItem { Header = "连接自动任务状态" };
            integration.Items.Add(Item("Claude Code…", () => Manager.ConnectAgent(slot, "claude")));
            integration.Items.Add(Item("Codex…", () => Manager.ConnectAgent(slot, "codex")));
            menu.Items.Add(integration);
            var move = new MenuItem { Header = "移动到槽位" };
            foreach (Slot destination in Manager.State.Slots.Where(s => !s.Occupied))
                move.Items.Add(Item("槽位 " + destination.Number, () => Manager.MoveSlot(slot, destination)));
            move.IsEnabled = move.Items.Count > 0; menu.Items.Add(move);
            menu.Items.Add(new Separator());
        }
        menu.Items.Add(Item(slot.Occupied ? "重新连接窗口（保留名称）…" : "选择一个已有窗口…", () => Manager.PickWindow(slot)));
        if (slot.Occupied) menu.Items.Add(Item("移出武器栏（保留窗口）", () => Manager.Remove(slot)));
        OpenMenu(target, menu);
    }
    private void MenuClick(object sender, RoutedEventArgs e)
    {
        if (Manager == null) return;
        var menu = new ContextMenu();
        menu.Items.Add(Item(Manager.InventoryMenuLabel, () => Manager.ToggleInventory()));
        menu.Items.Add(Item("设置：快捷键、布局与外观…", () => Manager.ShowSettings()));
        menu.Items.Add(Item("恢复上次工作现场…", () => Manager.ShowRecovery()));
        var pause = Item("暂停任务快捷键", () => Manager.TogglePause()); pause.IsCheckable = true; pause.IsChecked = Manager.ShortcutsPaused; menu.Items.Add(pause);
        menu.Items.Add(new Separator());
        var auto = Item("自动收起侧栏", () => Manager.SetAutoHide(!Manager.State.AutoHide));
        auto.IsCheckable = true; auto.IsChecked = Manager.State.AutoHide; menu.Items.Add(auto);
        var minimize = Item("拖入后最小化原窗口", () => { Manager.State.MinimizeOnCapture = !Manager.State.MinimizeOnCapture; Manager.Save(); });
        minimize.IsCheckable = true; minimize.IsChecked = Manager.State.MinimizeOnCapture; menu.Items.Add(minimize);
        menu.Items.Add(Item("收起所有任务窗口", () => Manager.ParkAll()));
        menu.Items.Add(Item("把侧栏移到鼠标所在屏幕", () => Manager.MoveToCursorScreen()));
        menu.Items.Add(Item("侧栏贴回右侧 / 恢复自动高度", () => Manager.ResetDockPosition()));
        menu.Items.Add(Item("隐藏侧栏（" + Manager.ToggleShortcut + "恢复）", () => Manager.ToggleVisibility()));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("使用说明 / 快捷键", () => Manager.ShowHelp()));
        menu.Items.Add(Item("打开任务配置目录", () => Manager.OpenDataDirectory()));
        menu.Items.Add(Item("退出（恢复收起的窗口）", () => Manager.Exit()));
        OpenMenu((FrameworkElement)sender, menu);
    }
    private void OverviewClick(object sender, RoutedEventArgs e) { ClosePreview(); Manager?.RequestOverview(); }
    private void AllSlotsClick(object sender, RoutedEventArgs e) => Manager?.ToggleAllSlots();
    private void ExpandClick(object sender, RoutedEventArgs e) => Manager?.Expand();
    private void SlotEnter(object sender, MouseEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is Slot slot && slot.Connected && Manager?.Dragging != true)
        { _hover = slot; _previewDelay.Stop(); _previewDelay.Start(); }
    }
    private void SlotLeave(object sender, MouseEventArgs e) => ClosePreview();
    private void ShowPreview()
    {
        if (_hover == null || Manager == null || Manager.Dragging || Manager.Selecting || MenuOpen || !Native.Matches(_hover.Window)) return;
        _preview?.Close();
        _preview = new PreviewWindow(_hover);
        _preview.Show();
        var source = PresentationSource.FromVisual(this);
        double scale = source?.CompositionTarget?.TransformToDevice.M11 ?? 1;
        var origin = PointToScreen(new System.Windows.Point(0, 0));
        Native.SetWindowPos(new System.Windows.Interop.WindowInteropHelper(_preview).Handle, new IntPtr(-1), (int)(origin.X - 350 * scale - 12 * scale), (int)Math.Max(Manager.WorkArea.Top + 10, origin.Y), (int)(350 * scale), (int)(260 * scale), 0x10);
        _preview.UpdateThumbnail();
    }
    public void ClosePreview() { _previewDelay.Stop(); _hover = null; _preview?.Close(); _preview = null; }
    public void SetPreviewLabel(bool allSlots = false)
    {
        Subtitle.Text = "界面预览 · 示例任务"; Summary.Text = "3 项需要你查看"; CountLabel.Text = "5 / 9"; Hint.Text = "示例数据 · 当前、选择、新结果分别标记";
        Slot? firstEmpty = SlotsList.Items.Cast<Slot>().FirstOrDefault(s => !s.Occupied);
        foreach (Slot slot in SlotsList.Items) { slot.IsDisplayed = allSlots || slot.Occupied || slot == firstEmpty; slot.Refresh(); }
    }
}
