using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace CodeManager;

public partial class App : Application
{
    private Mutex? _mutex;
    private Manager? _manager;
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        try
        {
            if (e.Args.FirstOrDefault() == "--quit") { Native.RequestExit(); Shutdown(); return; }
            if (e.Args.FirstOrDefault() == "--diagnose") { Diagnostics.Write(e.Args[1]); Shutdown(); return; }
            if (e.Args.FirstOrDefault() == "--wheel-benchmark") { WheelMotionDiagnostics.Write(e.Args[1]); Shutdown(); return; }
            if (e.Args.FirstOrDefault() == "hook")
            {
                try
                {
                    string? Value(string key) { int i = Array.IndexOf(e.Args, key); return i >= 0 && i + 1 < e.Args.Length ? e.Args[i + 1] : null; }
                    Console.InputEncoding = System.Text.Encoding.UTF8;
                    string payload = Console.In.ReadToEnd();
                    var status = HookBridge.Parse(Value("--provider") ?? "", Value("--task") ?? "", payload, DateTimeOffset.TryParse(Value("--at"), out var at) ? at : null);
                    if (status != null) new StateStore(Value("--root")).Send(status);
                }
                catch (Exception ex)
                {
                    int rootIndex = Array.IndexOf(e.Args, "--root");
                    if (rootIndex >= 0 && rootIndex + 1 < e.Args.Length)
                        try { new StateStore(e.Args[rootIndex + 1]).Log("Hook observer: " + ex.Message); } catch (Exception) { }
                }
                Shutdown(); return;
            }
            if (e.Args.FirstOrDefault() is "--self-test" or "--skin-test" or "--loadout-test" or "--theme-test" or "--task-status-test")
            {
                string path = e.Args.Length > 1 ? Path.GetFullPath(e.Args[1]) : Path.Combine(AppContext.BaseDirectory, "self-test.json");
                var results = e.Args[0] == "--task-status-test" ? TaskStatusTests.Run(Path.GetDirectoryName(path)!) : e.Args[0] == "--theme-test" ? UnifiedThemeTests.Run(Path.GetDirectoryName(path)!) : e.Args[0] == "--loadout-test" ? EquipmentTests.Run(Path.GetDirectoryName(path)!).ToList() : e.Args[0] == "--skin-test" ? SkinTests.Run().ToList() : SelfTests.Run();
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllText(path, JsonSerializer.Serialize(results, StateStore.Json));
                Shutdown(results.All(r => r.Passed) ? 0 : 1); return;
            }
            if (e.Args.FirstOrDefault() == "--recovery-smoke")
            {
                var result = SelfTests.RecoverySmoke();
                StateStore.AtomicWrite(Path.GetFullPath(e.Args[1]), JsonSerializer.Serialize(result, StateStore.Json));
                Shutdown(result.Passed ? 0 : 1); return;
            }
            if (e.Args.FirstOrDefault() == "--preview")
            {
                RenderPreview(e.Args.Length > 1 ? e.Args[1] : "preview.png", e.Args.Length > 2 ? e.Args[2] : "compact"); Shutdown(); return;
            }
            if (e.Args.FirstOrDefault() == "--interaction-test")
            {
                string root = Path.GetFullPath(e.Args[1]);
                var store = new StateStore(root);
                var state = new AppState(); state.Preferences.SoundEffects = false; state.Preferences.TabTogglesInventory = false;
                state.Preferences.DockWidth = 330; state.Preferences.HasDockAnchor = true; state.Preferences.DockAnchor = new(150, 100); state.Preferences.FreeDockPosition = true; state.Preferences.DockPosition = new(150, 100); state.MinimizeOnCapture = false; store.Save(state);
                _manager = new Manager(store, interactionTest: true); _manager.TogglePause();
                foreach (int n in new[] { 1, 2 })
                {
                    var fixture = new Window { Title = "交互验证示例窗口 " + n, Width = 380, Height = 240, Left = 500 + n * 30, Top = 150 + n * 30, Background = WuxiaTheme.Ink, Content = new System.Windows.Controls.TextBlock { Text = "示例任务 " + n + " · 不包含终端进程", Foreground = WuxiaTheme.Ivory, Margin = new Thickness(24) } };
                    fixture.Show(); _manager.Bind(_manager.State.Slots[n - 1], Native.Identify(new System.Windows.Interop.WindowInteropHelper(fixture).Handle, true)!);
                }
                Native.SetForegroundWindow(new System.Windows.Interop.WindowInteropHelper(_manager.Dock).Handle);
                return;
            }
            if (e.Args.FirstOrDefault() is "status" or "--status")
            {
                WriteStatus(e.Args); Shutdown(); return;
            }
            _mutex = new Mutex(true, "Local\\CodeManager.TaskDock.v1", out bool created);
            if (!created) { MessageBox.Show("CodeManager 已经在运行，请双击系统托盘图标显示侧栏。", "CodeManager"); Shutdown(); return; }
            DispatcherUnhandledException += Unhandled;
            _manager = new Manager();
            if (e.Args.Contains("--recovery")) { _manager.ShowRecovery(); return; }
            if (e.Args.Contains("--arrange")) _manager.RequestOverview();
            if (e.Args.Contains("--inventory")) _manager.ToggleInventory();
            if (e.Args.Length == 0) Dispatcher.BeginInvoke(() => _manager.StartupRecovery(), DispatcherPriority.ApplicationIdle);
        }
        catch (Exception ex)
        {
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodeManager");
            Directory.CreateDirectory(root); File.AppendAllText(Path.Combine(root, "app.log"), DateTime.Now.ToString("O") + " " + ex + Environment.NewLine);
            if (e.Args.Length == 0) MessageBox.Show("启动失败：" + ex.Message + "\n\n日志：" + root, "CodeManager");
            Shutdown(1);
        }
    }
    private void Unhandled(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        _manager?.Store.Log(e.Exception.ToString());
        // Exit through cleanup so parked windows are not stranded after an unexpected error.
        e.Handled = true;
        MessageBox.Show("发生错误，程序将恢复收起的窗口并退出。\n" + e.Exception.Message, "CodeManager");
        _manager?.Exit(); Shutdown(1);
    }
    private static void WriteStatus(string[] args)
    {
        string? Value(string key) { int index = Array.IndexOf(args, key); return index >= 0 && index + 1 < args.Length ? args[index + 1] : null; }
        if (!int.TryParse(Value("--slot"), out int number) || number is < 1 or > 9) throw new ArgumentException("Use: status --slot 1 --state running|waiting|ready|error|unknown [--message text]");
        string? stateText = Value("--state");
        if (!Enum.TryParse<AgentState>(stateText, true, out var state) || !Enum.IsDefined(state)) throw new ArgumentException("Invalid state");
        var store = new StateStore();
        var slot = store.Load().Slots.Single(s => s.Number == number);
        if (!slot.Occupied) throw new ArgumentException("Slot is empty");
        // Resolve number to immutable task ID now; a later rebind cannot receive this event.
        store.Send(new() { TaskId = slot.Id, State = state, Message = Value("--message") ?? "" });
    }
    private static void RenderPreview(string path, string mode)
    {
        // Match the complete suffix first: ink-jade and settings-skin both contain hyphens.
        var skin = SkinCatalog.All.OrderByDescending(s => s.Slug.Length).FirstOrDefault(s => mode.EndsWith("-" + s.Slug, StringComparison.OrdinalIgnoreCase));
        if (skin != null) mode = mode[..^(skin.Slug.Length + 1)];
        var overviewSize = OverviewSize.Large;
        if (mode.StartsWith("inventory-size-", StringComparison.OrdinalIgnoreCase) && Enum.TryParse<OverviewSize>(mode[15..], true, out var requestedSize)) { overviewSize = OverviewSizing.Normalize(requestedSize); mode = "inventory"; }
        WuxiaTheme.Apply(skin?.Id ?? (mode.Contains("midnight") ? Skin.Midnight : mode.Contains("cinnabar") ? Skin.Cinnabar : Skin.InkJade));
        var slots = Enumerable.Range(1, 9).Select(n => new Slot { Number = n, Id = "preview-slot-" + n }).ToList();
        string[] names = { "商城 · 修复登录与多语言账户验证", "OmniVibe · Permission required / 等待确认", "API gateway · Response ready", "数据脚本 · 状态未知", "CI / Build failed · 构建错误", "昨日任务 · 窗口已断开" };
        AgentState[] states = { AgentState.Running, AgentState.Waiting, AgentState.Ready, AgentState.Unknown, AgentState.Error, AgentState.Running };
        for (int i = 0; i < names.Length; i++)
        {
            slots[i].Name = names[i]; slots[i].Window = new() { ProcessName = i % 2 == 0 ? "WindowsTerminal" : "powershell" };
            slots[i].Connected = i != 5; slots[i].State = states[i]; slots[i].Unread = i is 1 or 2 or 4;
        }
        slots[0].IsActive = true; slots[2].IsSelected = true;
        if (mode is "inventory-empty" or "dock-empty" or "dock-empty-rest") foreach (var slot in slots) { slot.Window = null; slot.Connected = slot.IsActive = slot.IsSelected = slot.Unread = false; }
        EquipmentCatalog.EnsureDefaults(slots);
        slots[1].TagColor = "#A8A0F5"; slots[2].TagColor = "#F2BC78"; slots[3].TagColor = "#EE97B6";
        if (mode.StartsWith("nexus"))
        {
            string[] tasks = { "登录服务", "OmniVibe", "API 网关", "构建流水线" };
            for (int i = 0; i < slots.Count; i++)
            {
                slots[i].Window = i < 4 ? new() { ProcessName = "WindowsTerminal", Title = tasks[i] } : null;
                slots[i].Name = i < 4 ? tasks[i] : ""; slots[i].Connected = i < 4;
                slots[i].AgentProvider = i == 1 ? "claude" : "codex";
                slots[i].IsActive = i == 0; slots[i].IsSelected = false;
                slots[i].State = i == 0 ? AgentState.Running : i == 1 ? AgentState.Waiting : i == 2 ? AgentState.Ready : AgentState.Error;
                slots[i].Unread = i is 1 or 3;
            }
        }
        if (mode is "nexus-live" or "nexus-rest")
        {
            slots = new StateStore().Load().Slots;
            long foreground = Native.GetForegroundWindow().ToInt64();
            foreach (var slot in slots) { slot.Connected = Native.Matches(slot.Window); slot.IsActive = slot.Connected && slot.Window!.Handle == foreground; }
        }
        if (mode is "duo" or "duo-motion" or "duo-live")
        {
            foreach (var slot in slots) { slot.Window = null; slot.Connected = slot.IsActive = slot.IsSelected = slot.Unread = false; }
            slots[0].Window = new() { ProcessName = "WindowsTerminal", Title = "优化终端与 CLI 使用" }; slots[0].Name = "优化终端与 CLI 使用"; slots[0].Connected = true; slots[0].AgentProvider = "codex"; slots[0].State = AgentState.Running;
            slots[1].Window = new() { ProcessName = "WindowsTerminal", Title = "codemanager" }; slots[1].Name = "codemanager"; slots[1].Connected = slots[1].IsActive = true; slots[1].AgentProvider = "codex"; slots[1].State = AgentState.Unknown;
        }
        Window window;
        System.Windows.Controls.ContextMenu? previewMenu = null;
        if (mode == "recovery") { slots[0].Notes = "下次检查登录接口的错误处理"; slots[0].ProjectDirectory = "D:\\projects\\shop"; window = new RecoveryWindow(slots, new Native.Rect(0, 0, 1920, 1040)); }
        else if (mode == "recent") {
            foreach (var recent in slots.Skip(4)) recent.Connected = false;
            window = new RecoveryWindow(slots.Skip(4).Concat(slots.Take(4)), new Native.Rect(0,0,1920,1040), recentIds: slots.Skip(4).Select(s => s.Id).ToHashSet());
        }
        else if (mode == "ux-hint") window = new SlotHintWindow(slots[1]) { SizeToContent = SizeToContent.Manual, Height = 140 };
        else if (mode is "loadout" or "loadout-short") window = new LoadoutWindow(slots, mode == "loadout-short" ? new Native.Rect(0, 0, 1100, 580) : new Native.Rect(0, 0, 1920, 1040));
        else if (mode.StartsWith("radial"))
        {
            var radial = new RadialInventoryWindow(slots, mode == "radial-small" ? new Native.Rect(0, 0, 640, 540) : new Native.Rect(0, 0, 940, 760), 1, false, "Alt+Q", () => true, preview: true);
            radial.Surface.Select(3); radial.Surface.SetPhase(.23); window = radial;
        }
        else if (mode is "inventory" or "inventory-empty" or "inventory-small" or "inventory-hidpi" or "inventory-short") window = new InventoryWindow(slots, mode == "inventory-small" ? new Native.Rect(0, 0, 836, 698) : mode == "inventory-short" ? new Native.Rect(0, 0, 1920, 698) : new Native.Rect(0, 0, 1920, 1040), mode is "inventory-hidpi" or "inventory-short" ? 2 : 1, 3, false, presentationPreview: true, size: overviewSize);
        else if (mode.StartsWith("settings")) window = new SettingsWindow(new() { Skin = SkinCatalog.Current.Id, Animate = false, SoundEffects = false }, new Native.Rect(0, 0, 1920, 1040), "", page: mode.Contains("guide") ? 4 : mode.Contains("audio") ? 5 : mode.Contains("layout") ? 1 : mode.Contains("skin") ? 2 : mode.Contains("general") ? 3 : 0);
        else if (mode == "menu")
        {
            var menu = new System.Windows.Controls.ContextMenu();
            foreach (string title in new[] { "打开任务背包", "唤出窗口", "编辑名称、颜色与项目…", "收起窗口" }) menu.Items.Add(new System.Windows.Controls.MenuItem { Header = title });
            menu.Items.Add(new System.Windows.Controls.Separator());
            var submenu = new System.Windows.Controls.MenuItem { Header = "连接自动任务状态" }; submenu.Items.Add(new System.Windows.Controls.MenuItem { Header = "Claude Code…" }); submenu.Items.Add(new System.Windows.Controls.MenuItem { Header = "Codex…" }); menu.Items.Add(submenu);
            menu.Items.Add(new System.Windows.Controls.MenuItem { Header = "自动收起侧栏", IsCheckable = true, IsChecked = true });
            menu.Items.Add(new System.Windows.Controls.MenuItem { Header = "移动到槽位（当前无空位）", IsEnabled = false });
            menu.Items.Add(new System.Windows.Controls.Separator()); menu.Items.Add(new System.Windows.Controls.MenuItem { Header = "移出列表 · 保留终端窗口" });
            previewMenu = menu;
            window = new Window { Width = 410, Height = 455, Background = WuxiaTheme.Ink, Content = new System.Windows.Controls.Border() };
        }
        else if (mode == "task") window = new TaskEditorWindow(slots[0], new Native.Rect(0, 0, 1920, 1040));
        else if (mode == "integration") window = new IntegrationWindow(slots[0], "codex", new StateStore().Root, new Native.Rect(0, 0, 1920, 1040));
        else
        {
            var dock = new DockWindow(); dock.SetSlots(slots); dock.SetPreviewLabel(mode == "expanded");
            if (mode == "mini") dock.SetCollapsed(true);
            dock.Width = mode == "narrow" ? 440 : 460; dock.Height = dock.DesiredDockHeight; window = dock;
            if (mode is not ("mini" or "dock-empty-rest" or "nexus-idle" or "nexus-motion" or "nexus-rest")) dock.SetEquipmentDeployment(true, false);
            if (mode == "nexus-aim") { var wheel = (DockWeaponWheel)dock.FindName("WeaponWheel"); wheel.BeginAim(false); wheel.AimAt(wheel.SlotPoint(2)); }
        }
        if (mode == "duo-motion") { window.Left = -8000; window.Top = -8000; }
        if (mode == "radial-motion") { window.Left = -8000; window.Top = -8000; }
        if (mode.StartsWith("nexus")) { window.Left = -8000; window.Top = -8000; }
        window.ShowActivated = false; window.Topmost = false; window.Show(); window.UpdateLayout();
        Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        if (mode == "ux-hover" && window is DockWindow hoverDock) ((DockWeaponWheel)hoverDock.FindName("WeaponWheel")).Hover(slots[0]);
        if (mode == "nexus-aim" && window is DockWindow aimingDock)
        {
            var wheel = (DockWeaponWheel)aimingDock.FindName("WeaponWheel"); wheel.AimAt(wheel.SlotPoint(2));
        }
        if (mode == "nexus-motion" && window is DockWindow nexusDock)
        {
            string frames = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path))!, "nexus-motion-frames"); Directory.CreateDirectory(frames);
            var wheel = (DockWeaponWheel)nexusDock.FindName("WeaponWheel");
            for (int i = 0; i < 66; i++)
            {
                if (i == 7) { nexusDock.HandleWheelPointerMove(wheel.Centre); wheel.Deploy(true, true); }
                if (i == 15) nexusDock.HandleWheelPointerMove(wheel.SlotPoint(2));
                if (i == 25) nexusDock.HandleWheelPointerMove(wheel.SlotPoint(3));
                if (i == 35)
                {
                    int? result = 3; nexusDock.SetEquipmentDeployment(false, true);
                    if (result.HasValue) { foreach (var slot in slots) { slot.IsActive = slot.Number == result; slot.Refresh(); } wheel.Pulse(slots[result.Value - 1], true); }
                }
                if (i == 46) { nexusDock.SetEquipmentDeployment(true, true); }
                if (i == 54) wheel.Hover(slots[8]);
                if (i == 59) nexusDock.SetEquipmentDeployment(false, true);
                Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle); window.UpdateLayout();
                var shot = new RenderTargetBitmap((int)window.Width, (int)window.Height, 96, 96, PixelFormats.Pbgra32); shot.Render((Visual)window.Content);
                var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(shot));
                using (var stream = File.Create(Path.Combine(frames, i.ToString("D2") + ".png"))) png.Save(stream);
                System.Threading.Thread.Sleep(65);
            }
            window.Close(); return;
        }
        if (mode == "radial-motion" && window is RadialInventoryWindow motionRadial)
        {
            string frames = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path))!, "radial-motion-frames");
            Directory.CreateDirectory(frames);
            for (int i = 0; i < 36; i++)
            {
                motionRadial.Surface.SetPhase(i * .065);
                if (i % 12 == 0) motionRadial.Surface.Select(new[] { 2, 3, 5 }[i / 12]);
                window.UpdateLayout();
                var shot = new RenderTargetBitmap((int)window.Width, (int)window.Height, 96, 96, PixelFormats.Pbgra32);
                shot.Render((Visual)window.Content);
                var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(shot));
                using var stream = File.Create(Path.Combine(frames, i.ToString("D2") + ".png")); png.Save(stream);
            }
            window.Close(); return;
        }
        if (mode == "duo-motion" && window is DockWindow motionDock)
        {
            string frames = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path))!, "equipment-motion-frames");
            Directory.CreateDirectory(frames);
            for (int frameNumber = 0; frameNumber < 30; frameNumber++)
            {
                if (frameNumber % 10 == 0)
                {
                    int active = frameNumber / 10 % 2;
                    foreach (Slot slot in slots) { slot.IsActive = slot == slots[active]; slot.Refresh(); }
                    motionDock.Pulse(slots[active], capture: false);
                }
                Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                window.UpdateLayout();
                var frameBitmap = new RenderTargetBitmap((int)window.Width, (int)window.Height, 96, 96, PixelFormats.Pbgra32);
                frameBitmap.Render((Visual)window.Content);
                var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(frameBitmap));
                using (var stream = File.Create(Path.Combine(frames, frameNumber.ToString("D2") + ".png"))) png.Save(stream);
                System.Threading.Thread.Sleep(66);
            }
            window.Close(); return;
        }
        if (previewMenu != null)
        {
            previewMenu.PlacementTarget = window; previewMenu.IsOpen = true; previewMenu.UpdateLayout();
            Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
            var shot = new RenderTargetBitmap((int)Math.Ceiling(previewMenu.ActualWidth), (int)Math.Ceiling(previewMenu.ActualHeight), 96, 96, PixelFormats.Pbgra32); shot.Render(previewMenu);
            var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(shot));
            string destination = Path.GetFullPath(path); Directory.CreateDirectory(Path.GetDirectoryName(destination)!); using (var stream = File.Create(destination)) png.Save(stream);
            previewMenu.IsOpen = false; window.Close(); return;
        }
        var visual = (FrameworkElement)window.Content;
        window.Content = null;
        var frame = new System.Windows.Controls.Border { Background = window.Background, Width = window.Width, Height = window.Height, Child = visual };
        frame.Measure(new System.Windows.Size(window.Width, window.Height)); frame.Arrange(new System.Windows.Rect(0, 0, window.Width, window.Height)); frame.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(window.Width), (int)Math.Ceiling(window.Height), 96, 96, PixelFormats.Pbgra32); bitmap.Render(frame);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        string full = Path.GetFullPath(path); Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        using var output = File.Create(full); encoder.Save(output); window.Close();
    }
    protected override void OnExit(ExitEventArgs e) { _manager?.Dispose(); GameAudio.Shutdown(); _mutex?.Dispose(); base.OnExit(e); }
}
