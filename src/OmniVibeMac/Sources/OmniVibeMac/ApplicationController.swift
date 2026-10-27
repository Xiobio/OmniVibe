import AppKit
import Combine
import OmniVibeCore

@MainActor
final class ApplicationController: ObservableObject {
    @Published private(set) var workspace = WorkspaceState()
    @Published private(set) var permissionGranted = false
    @Published private(set) var connectedWindows = Set<UUID>()
    @Published private(set) var candidates: [WindowIdentity] = []
    @Published private(set) var activeSlot: Int?
    @Published private(set) var isArranged = false
    @Published var pickerSlot: Int? {
        didSet { if pickerSlot == nil { pendingRecentBinding = nil } }
    }
    @Published var renameSlot: Int?
    @Published var integrationSlot: Int?
    @Published var launchSlot: Int? {
        didSet { if launchSlot == nil { launchSourceTaskID = nil } }
    }
    @Published var sessionDiscoverySlot: Int?
    @Published private(set) var taskLaunchBusy = false
    @Published private(set) var sessionLinkWarning: String?
    private(set) var launchSourceTaskID: UUID?
    @Published var renameText = ""
    @Published var notice: String?
    @Published private(set) var hotKeyWarning: String?
    @Published private(set) var registeredTaskShortcuts = Set<Int>()
    @Published private(set) var registeredWheelShortcuts = Set<String>()
    @Published var permissionSettingsRequested = false
    @Published private(set) var lastShortcut = "尚未收到快捷键"
    @Published private(set) var shortcutScheme: ShortcutScheme
    @Published private(set) var shortcutConfiguration: ShortcutConfiguration
    @Published private(set) var isRecordingShortcut = false
    @Published private(set) var shortcutEditError: String?
    @Published private(set) var isPresentingArrangement = false
    @Published private(set) var arrangementWarning: String?
    @Published var arrangementFailure: String?
    @Published var taskOperationFailure: String?
    @Published var activationFailure: String?
    @Published private(set) var arrangementSummary: String?
    @Published private(set) var windowBehavior: WindowBehaviorPreferences
    @Published private(set) var windowBehaviorWarning: String?
    @Published private(set) var recoveryWarning: String?
    @Published private(set) var recoveryCount = 0
    @Published var notificationStatus: String?
    @Published private(set) var recentTasks: [RecentTaskRecord] = []
    @Published private(set) var recentTasksWarning: String?
    @Published private(set) var arrangementTargets: [UUID: WindowFrame] = [:]
    @Published private(set) var arrangementAreas: [UUID: WindowFrame] = [:]
    @Published var arrangement: ArrangementMode = .balanced {
        didSet {
            guard arrangement != oldValue, arrangement != windowBehavior.arrangement else { return }
            updateWindowBehavior { $0.arrangement = arrangement }
        }
    }

    let isDemo: Bool
    let windows: any WindowControlling
    private let store: WorkspaceStore
    private let startsMonitoring: Bool
    private let preferences: UserDefaults
    private let behaviorStore: WindowBehaviorPreferencesStore
    private let recoveryStore: RecoveryJournalStore
    private let recentTaskStore: RecentTaskStore
    private let taskLaunchRecords: TaskLaunchRecordStore
    private let taskLauncher: any TaskLaunching
    private let sessionAssociations: SessionDiscoveryAssociationStore
    private let sessionDiscovery = SessionDiscoveryService()
    private let sessionObserver = SessionDiscoveryObserver()
    private let statusInbox: StatusEventInbox
    var onFeedback: ((AudioCue) -> Void)?
    var onRequestInventory: (() -> Void)?
    var onRequestPermission: (() -> Void)?
    var onRetryWheelShortcuts: (() -> Void)?
    var onToggleInventory: (() -> Void)?
    var onBeforeArrangement: (() -> Void)?
    var onBeforeTaskActivation: (() -> Void)?
    var managementWindowIsActive: (() -> Bool)?
    var onWindowBehaviorChanged: (() -> Void)?
    var onTaskReady: ((UUID, String) -> Void)?
    var onRequestSystemNotifications: (() -> Void)?
    var onArrangementRestored: (() -> Void)?
    var onTaskIdentityReplaced: ((UUID, UUID) throws -> Void)?
    var onSuspendWheelShortcuts: (() -> Void)?
    var onPrepareSlotOrdering: (([TaskSlot]) throws -> Void)?
    private var shortcutConfigurationWarning: String?
    private var taskShortcutWarnings: [String] = []
    private var wheelShortcutWarnings: [String] = []
    private var hotKeys: HotKeyService?
    private var refreshTimer: Timer?
    private var statusTimer: Timer?
    private var statusPollBusy = false
    private var stopping = false
    private var wheelInteraction = false
    private var activationTask: Task<Void, Never>?
    private var activationEpoch: UInt64 = 0
    private var arrangementPresentation: Task<Void, Never>?
    private var arrangementEpoch: UInt64 = 0
    private var lastExternalWindow: WindowIdentity?
    private var toggleSnapshot: ToggleSnapshot?
    private var lastActivationTaskID: UUID?
    private var layoutSnapshots: [UUID: WindowSnapshot] = [:]
    private var parkedSnapshots: [UUID: WindowSnapshot] = [:]
    private var pendingRecovery: [WindowRecoveryRecord] = []
    private var recoveryPersistenceAvailable = true
    private var pendingRecentPicker: Int?
    private var pendingRecentBinding: (record: RecentTaskRecord, slot: Int)?
    private var reconnectAttempts: [UUID: TimeInterval] = [:]
    private var pendingLaunchRequest: (number: Int, source: UUID?)?
    private var lastSessionScan = -Double.infinity
    private var sessionUpdateBacklog: [UUID: SessionDiscoveryUpdate] = [:]
    private var launchOperation: Task<Void, Never>?

    private struct WindowSnapshot {
        let window: WindowIdentity
        let placement: WindowPlacement
    }

    private struct ToggleSnapshot {
        let number: Int
        let original: WindowSnapshot
        let previousFocus: WindowIdentity?
    }

    var occupiedCount: Int { workspace.slots.filter { $0.window != nil }.count }
    var connectedCount: Int { workspace.slots.filter { isConnected($0) }.count }
    var canControlWindows: Bool { !isDemo && permissionGranted }
    var shortcutsPaused: Bool { windowBehavior.shortcutsPaused }
    var wheelSwitchEnabled: Bool { windowBehavior.wheelSwitchEnabled }
    var wheelModifiers: UInt32 { windowBehavior.wheelModifiers }

    convenience init(demo: Bool = false) {
        self.init(demo: demo, windowService: WindowService(), store: WorkspaceStore())
    }

    init(demo: Bool = false, windowService: any WindowControlling,
         store: WorkspaceStore = WorkspaceStore(), startsMonitoring: Bool = true,
         preferences: UserDefaults = .standard, taskLauncher: (any TaskLaunching)? = nil) {
        isDemo = demo
        windows = windowService
        self.store = store
        self.startsMonitoring = startsMonitoring
        self.preferences = preferences
        let behavior = WindowBehaviorPreferencesStore(preferences: preferences)
        behaviorStore = behavior
        windowBehavior = behavior.value
        windowBehaviorWarning = behavior.warning
        arrangement = behavior.value.arrangement
        recoveryStore = RecoveryJournalStore(root: store.root)
        recentTaskStore = RecentTaskStore(root: store.root)
        taskLaunchRecords = TaskLaunchRecordStore(root: store.root)
        self.taskLauncher = taskLauncher ?? TaskLaunchService(root: store.root)
        sessionAssociations = SessionDiscoveryAssociationStore(root: store.root)
        let savedScheme = preferences.string(forKey: "OmniVibe.ShortcutScheme.v1").flatMap(ShortcutScheme.init(rawValue:)) ?? .optionNumbers
        if let data = preferences.data(forKey: "OmniVibe.ShortcutConfiguration.v1") {
            do {
                let configuration = try JSONDecoder().decode(ShortcutConfiguration.self, from: data)
                shortcutConfiguration = configuration
                shortcutScheme = configuration.base
            } catch {
                shortcutConfiguration = ShortcutConfiguration(base: savedScheme)
                shortcutScheme = savedScheme
                shortcutConfigurationWarning = "自定义快捷键配置无法载入，已使用预设。原配置仍保留，可在设置中重新编辑。"
            }
        } else {
            shortcutConfiguration = ShortcutConfiguration(base: savedScheme)
            shortcutScheme = savedScheme
        }
        statusInbox = StatusEventInbox(root: store.root)
        if demo {
            for (offset, name) in ["OmniVibe · macOS 适配", "API Gateway · 接口开发", "Build & Test · 构建验证"].enumerated() {
                let identity = WindowIdentity(id: UUID(), processID: Int32(offset + 100), processStartedAt: nil,
                    bundleIdentifier: nil, applicationName: offset == 1 ? "iTerm2" : "Terminal", title: name)
                try? workspace.bind(identity, to: offset + 1)
            }
            return
        }
        do {
            let loaded = try store.load()
            workspace = loaded.state
            notice = loaded.warning
        } catch {
            notice = "无法读取任务配置：\(error.localizedDescription)。为保护原文件，本次不会自动覆盖配置。"
            persistenceAvailable = false
        }
        do {
            let recovered = try recoveryStore.load()
            pendingRecovery = recovered.records
            recoveryCount = pendingRecovery.count
            recoveryWarning = recovered.warning
            if !pendingRecovery.isEmpty { recoveryWarning = "发现 \(pendingRecovery.count) 条上次未完成的窗口恢复记录。" }
        } catch {
            recoveryPersistenceAvailable = false
            recoveryWarning = "窗口恢复记录无法读取或备份，本次保留原文件：\(error.localizedDescription)"
        }
        if windows.isTrusted && windowBehavior.autoReconnectExisting { reconnectExistingTasks() }
        do {
            let recent = try recentTaskStore.load()
            recentTasks = recent.records
            recentTasksWarning = recent.warning
        } catch { recentTasksWarning = error.localizedDescription }
        recheckPermissions()
        startMonitoring()
    }

    private var persistenceAvailable = true

    func isConnected(_ slot: TaskSlot) -> Bool {
        guard let window = slot.window else { return false }
        return !isDemo && connectedWindows.contains(window.id)
    }

    func rememberExternalFocus() {
        guard !isDemo, permissionGranted, let current = windows.currentWindow() else { return }
        lastExternalWindow = current
    }

    func recheckPermissions() {
        guard !isDemo else { return }
        permissionGranted = windows.isTrusted
        if startsMonitoring && !isRecordingShortcut && !shortcutsPaused && hotKeys == nil {
            let keys = HotKeyService(configuration: shortcutConfiguration, scheme: shortcutScheme, onSlot: { [weak self] number in
                self?.recordShortcut(self?.shortcutLabel(.slot(number)) ?? ""); self?.toggleSlot(number)
            }, onArrange: { [weak self] in
                self?.recordShortcut(self?.shortcutLabel(.arrange) ?? ""); self?.toggleArrangement()
            })
            do {
                try keys.register()
                hotKeys = keys
                registeredTaskShortcuts = keys.registeredSlots.union(keys.arrangementRegistered ? [0] : [])
                taskShortcutWarnings = keys.warnings
                updateShortcutWarning()
            } catch {
                registeredTaskShortcuts = []
                taskShortcutWarnings = [error.localizedDescription]
                updateShortcutWarning()
            }
        }
        refreshConnections()
    }

    func reportWheelShortcuts(registered: Set<String>, warnings: [String]) {
        registeredWheelShortcuts = registered
        wheelShortcutWarnings = warnings
        updateShortcutWarning()
    }

    func recordShortcut(_ label: String) { lastShortcut = label }

    func shortcutLabel(_ action: ShortcutAction) -> String { shortcutConfiguration.binding(for: action)?.label ?? "" }

    func setShortcutScheme(_ scheme: ShortcutScheme) {
        guard shortcutScheme != scheme else { return }
        do { try applyShortcutConfiguration(shortcutConfiguration.changingBase(to: scheme, preservingOverrides: false)) }
        catch { shortcutEditError = error.localizedDescription }
    }

    @discardableResult
    func setCustomShortcut(_ binding: ShortcutBinding) -> Bool {
        do { try applyShortcutConfiguration(shortcutConfiguration.setting(binding)); return true }
        catch { shortcutEditError = error.localizedDescription; return false }
    }

    @discardableResult
    func disableShortcut(_ action: ShortcutAction) -> Bool {
        do { try applyShortcutConfiguration(shortcutConfiguration.disabling(action)); return true }
        catch { shortcutEditError = error.localizedDescription; return false }
    }

    func resetShortcut(_ action: ShortcutAction) {
        do { try applyShortcutConfiguration(shortcutConfiguration.resetting(action)) }
        catch { shortcutEditError = error.localizedDescription }
    }

    func resetAllCustomShortcuts() {
        do { try applyShortcutConfiguration(ShortcutConfiguration(base: shortcutScheme)) }
        catch { shortcutEditError = error.localizedDescription }
    }

    private func applyShortcutConfiguration(_ configuration: ShortcutConfiguration) throws {
        try configuration.validate()
        let data = try JSONEncoder().encode(configuration)
        if !isDemo {
            preferences.set(data, forKey: "OmniVibe.ShortcutConfiguration.v1")
            preferences.set(configuration.base.rawValue, forKey: "OmniVibe.ShortcutScheme.v1")
        }
        shortcutConfiguration = configuration
        shortcutScheme = configuration.base
        shortcutConfigurationWarning = nil
        shortcutEditError = nil
        registeredTaskShortcuts = []
        registeredWheelShortcuts = []
        lastShortcut = "尚未收到快捷键"
        retryShortcuts()
    }

    func beginShortcutRecording() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        hotKeys?.unregister(); hotKeys = nil
        registeredTaskShortcuts = []
        onSuspendWheelShortcuts?()
    }

    func endShortcutRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        if !stopping { retryShortcuts() }
    }

    func toggleInventoryFromShortcut() { onToggleInventory?() }

    func setWheelInteraction(_ active: Bool) { wheelInteraction = active }

    private func updateShortcutWarning() {
        let warnings = [shortcutConfigurationWarning].compactMap { $0 } + taskShortcutWarnings + wheelShortcutWarnings
        hotKeyWarning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    func retryShortcuts() {
        hotKeys?.unregister()
        hotKeys = nil
        registeredTaskShortcuts = []
        recheckPermissions()
        if !isRecordingShortcut { onRetryWheelShortcuts?() }
    }

    func updateWindowBehavior(_ update: (inout WindowBehaviorPreferences) -> Void) {
        var candidate = windowBehavior
        update(&candidate)
        do {
            let checked = try candidate.validated()
            if !isDemo { try behaviorStore.save(checked) }
            let changesShortcuts = checked.shortcutsPaused != windowBehavior.shortcutsPaused ||
                checked.wheelSwitchEnabled != windowBehavior.wheelSwitchEnabled || checked.wheelModifiers != windowBehavior.wheelModifiers
            windowBehavior = checked
            windowBehaviorWarning = nil
            if arrangement != checked.arrangement { arrangement = checked.arrangement }
            if changesShortcuts { retryShortcuts() }
            onWindowBehaviorChanged?()
        } catch { windowBehaviorWarning = error.localizedDescription }
    }

    func setShortcutsPaused(_ paused: Bool) { updateWindowBehavior { $0.shortcutsPaused = paused } }

    func requestSystemNotifications() { onRequestSystemNotifications?() }

    func openScrollPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    func openTaskFromNotification(_ taskID: UUID) {
        guard let slot = workspace.slots.first(where: { $0.id == taskID && $0.window != nil }) else {
            notice = "通知对应的原任务已移出管理。"; onRequestInventory?(); return
        }
        enterSlot(slot.number)
    }

    func cycleTask(direction: Int) {
        guard direction != 0, !shortcutsPaused, !isRecordingShortcut, !isDemo else { return }
        let available = workspace.slots.filter { isConnected($0) }.sorted { $0.number < $1.number }
        guard !available.isEmpty else { notice = "先收纳一个可连接的窗口。"; return }
        let focused = windows.currentWindow()?.id
        let index = available.firstIndex { $0.window?.id == focused } ?? available.firstIndex { $0.number == activeSlot }
        let next = index.map { ($0 + (direction > 0 ? 1 : -1) + available.count) % available.count }
            ?? (direction > 0 ? 0 : available.count - 1)
        enterSlot(available[next].number)
    }

    func reconnectExistingTasks() {
        guard !isDemo, windows.isTrusted else { return }
        var candidate = workspace
        for slot in workspace.slots {
            guard let saved = slot.window else { continue }
            if workspace.slots.contains(where: { $0.id != slot.id && $0.window?.refersToSamePlatformWindow(as: saved) == true }) { continue }
            reconnectAttempts[saved.id] = ProcessInfo.processInfo.systemUptime
            guard let restored = windows.reconnect(saved) else { continue }
            do { _ = try refreshVerifiedWindowMetadata(restored, for: slot.id, in: &candidate) }
            catch { notice = error.localizedDescription }
        }
        if candidate != workspace {
            do { try persist(candidate) } catch { report(error) }
        }
        connectedWindows = Set(workspace.slots.compactMap { slot in
            guard let window = slot.window, windows.isAvailable(window) else { return nil }
            return window.id
        })
    }

    /// Legacy boot timestamps can change during clock correction. Only a live
    /// alias with the same process lifetime and exact WindowServer token may
    /// replace that old session token; task identity and metadata stay intact.
    private func refreshVerifiedWindowMetadata(_ identity: WindowIdentity, for taskID: UUID,
                                              in state: inout WorkspaceState) throws -> Bool {
        guard let index = state.slots.firstIndex(where: { $0.id == taskID }),
              let previous = state.slots[index].window else { return false }
        if previous.platformSessionID == nil || previous.platformSessionID == identity.platformSessionID {
            return try state.refreshWindowMetadata(identity, for: taskID)
        }
        guard WindowReconnectionMatcher.alias(saved: previous, current: identity,
                  sessionID: identity.platformSessionID) == identity else { return false }
        var updated = state
        updated.slots[index].window = identity
        try updated.validate()
        state = updated
        return true
    }

    @discardableResult
    func restoreRecentTask(_ id: UUID) -> Bool {
        guard !workspace.slots.contains(where: { $0.id == id }),
              let record = recentTasks.first(where: { $0.id == id }),
              let target = workspace.slots.first(where: { $0.window == nil }) else {
            return failTaskOperation("任务已在槽位中，或当前没有空槽位可恢复。")
        }
        do {
            guard let originalWindow = record.task.window else { return false }
            let live = windows.isAvailable(originalWindow) ? originalWindow : windows.reconnect(originalWindow)
            if live == nil {
                pendingRecentBinding = (record, target.number)
                pendingRecentPicker = target.number
                notice = "请选择要连接到原任务的具体窗口。"
                return true
            }
            var updated = workspace
            var task = record.task
            task.number = target.number
            task.agentState = .unknown
            task.unread = false
            task.integrationConnected = false
            task.sessionID = ""
            task.message = ""
            task.updatedAt = nil
            task.stateSource = "最近关闭"
            task.lastAgentEventName = ""
            task.lastAgentTurnID = ""
            task.window = live
            if let index = updated.slots.firstIndex(where: { $0.number == target.number }) { updated.slots[index] = task }
            try updated.validate()
            try persist(updated)
            let remaining = recentTasks.filter { $0.id != id }
            do { try recentTaskStore.save(remaining); recentTasks = remaining }
            catch { recentTasksWarning = error.localizedDescription }
            notice = "任务配置已恢复到 \(target.number) 号槽位。"
            refreshConnections()
            return true
        } catch { return failTaskOperation(error.localizedDescription) }
    }

    func presentRestoredRecentPickerIfNeeded() {
        if pendingLaunchRequest != nil { presentDeferredLaunchIfNeeded(); return }
        guard let number = pendingRecentPicker else { return }
        pendingRecentPicker = nil
        openPicker(for: number)
    }

    func beginNewTask() {
        guard let slot = workspace.slots.first(where: { $0.window == nil }) else {
            _ = failTaskOperation("九个槽位都已占用，请先移出一个任务再新建。")
            return
        }
        beginLaunching(slot.number)
    }

    func beginLaunching(_ number: Int, sourceTaskID: UUID? = nil) {
        guard canControlWindows, !taskLaunchBusy else {
            if !permissionGranted { requireAccessibilityPermission(reason: "创建任务窗口需要辅助功能权限") }
            return
        }
        guard workspace.slots.contains(where: { $0.number == number }), permitsNewWindowMutation() else { return }
        do { _ = try taskLaunchRecords.load() }
        catch { _ = failTaskOperation(error.localizedDescription); return }
        launchSourceTaskID = sourceTaskID
        launchSlot = number
        onRequestInventory?()
    }

    func requestLaunchFromPicker() {
        guard let number = pickerSlot else { return }
        pendingLaunchRequest = (number, nil)
        pickerSlot = nil
    }

    func presentDeferredLaunchIfNeeded() {
        guard let request = pendingLaunchRequest else { return }
        pendingLaunchRequest = nil
        beginLaunching(request.number, sourceTaskID: request.source)
    }

    func canLaunchRecentTask(_ id: UUID) -> Bool {
        guard let task = recentTasks.first(where: { $0.id == id })?.task else { return false }
        return (try? taskLaunchRecords.record(for: id)) != nil || task.window?.bundleIdentifier == "com.apple.Terminal" ||
            ["codex", "claude"].contains(task.agentProvider)
    }

    func requestLaunchRecentTask(_ id: UUID) -> Bool {
        guard canLaunchRecentTask(id), !workspace.slots.contains(where: { $0.id == id }),
              let empty = workspace.slots.first(where: { $0.window == nil }) else {
            return failTaskOperation("任务已在槽位中，或当前没有空槽位可恢复。")
        }
        pendingLaunchRequest = (empty.number, id)
        return true
    }

    func launchConfiguration(for number: Int) -> TaskLaunchConfiguration? {
        guard let slot = workspace.slots.first(where: { $0.number == number }) else { return nil }
        let source = launchSourceTaskID ?? slot.id
        if let record = try? taskLaunchRecords.record(for: source) { return record.configuration }
        if let association = (try? sessionAssociations.load())?.first(where: { $0.taskID == source }),
           let mode = TaskLaunchMode(rawValue: association.session.provider) {
            return TaskLaunchConfiguration(mode: mode, projectDirectory: association.session.projectDirectory,
                executablePath: TaskLaunchConfiguration.defaultExecutable(for: mode), resumeSessionID: association.session.sessionID)
        }
        let sourceTask = recentTasks.first(where: { $0.id == source })?.task ?? slot
        guard let mode = TaskLaunchMode(rawValue: sourceTask.agentProvider), mode != .terminal else { return nil }
        return TaskLaunchConfiguration(mode: mode, executablePath: TaskLaunchConfiguration.defaultExecutable(for: mode),
            resumeSessionID: UUID(uuidString: sourceTask.sessionID) == nil ? "" : sourceTask.sessionID)
    }

    func saveLaunchConfiguration(_ configuration: TaskLaunchConfiguration) {
        guard let number = launchSlot, let slot = workspace.slots.first(where: { $0.number == number }), !isDemo else { return }
        do {
            _ = try configuration.validated()
            try taskLaunchRecords.save(configuration, for: launchSourceTaskID ?? slot.id)
            launchSlot = nil
            notice = "启动配置已保存，窗口关闭后可在最近关闭中继续任务。"
        } catch { _ = failTaskOperation(error.localizedDescription) }
    }

    func launchTask(_ configuration: TaskLaunchConfiguration) {
        guard canControlWindows else {
            requireAccessibilityPermission(reason: "创建任务窗口需要辅助功能权限")
            return
        }
        guard !taskLaunchBusy, permitsNewWindowMutation(), let number = launchSlot,
              let original = workspace.slots.first(where: { $0.number == number }) else { return }
        if let window = original.window, windows.isAvailable(window) {
            _ = failTaskOperation("当前任务窗口仍在运行，请直接进入任务；新任务请使用空槽位。")
            return
        }
        if let window = original.window, !windows.isDefinitelyClosed(window) {
            _ = failTaskOperation("原窗口只是暂时不可访问，尚不能确认已经关闭。请先重连原窗口，或在空槽位新建任务。")
            return
        }
        if !configuration.resumeSessionID.isEmpty, workspace.slots.contains(where: {
            $0.id != original.id && $0.window != nil && $0.agentProvider == configuration.mode.rawValue &&
                $0.sessionID.caseInsensitiveCompare(configuration.resumeSessionID) == .orderedSame
        }) {
            _ = failTaskOperation("这个会话已由其他槽位管理，请进入原任务，避免重复启动。")
            return
        }
        let sourceID = launchSourceTaskID ?? original.id
        let sourceTask = recentTasks.first(where: { $0.id == sourceID })?.task ?? original
        let newID = original.window == nil ? original.id : UUID()
        taskOperationFailure = nil
        taskLaunchBusy = true
        launchOperation = Task { [weak self] in
            guard let self else { return }
            defer { self.taskLaunchBusy = false; self.launchOperation = nil }
            do {
                _ = try configuration.validated()
                let opened = try await self.taskLauncher.openWindow(configuration: configuration, taskID: newID, windows: self.windows)
                try Task.checkCancellation()
                guard !self.stopping, let current = self.workspace.slots.first(where: { $0.id == original.id }),
                      current.window?.id == original.window?.id else {
                    throw TaskLaunchError.expiredWindow
                }
                if let oldWindow = current.window, !self.windows.isDefinitelyClosed(oldWindow) || self.windows.isAvailable(oldWindow) {
                    throw TaskLaunchError.expiredWindow
                }
                var updated = self.workspace
                guard let index = updated.slots.firstIndex(where: { $0.id == original.id }) else { throw TaskLaunchError.expiredWindow }
                updated.slots[index] = TaskSlot(id: newID, number: current.number,
                    name: sourceID == original.id ? current.name : sourceTask.name.isEmpty ? sourceTask.displayName : sourceTask.name,
                    window: opened.window, agentProvider: configuration.mode.provider?.rawValue ?? "",
                    sessionID: configuration.resumeSessionID, stateSource: "启动请求")
                try updated.validate()
                if sourceID != newID {
                    try self.taskLaunchRecords.transfer(from: sourceID, to: newID)
                    try self.onTaskIdentityReplaced?(sourceID, newID)
                }
                try self.persist(updated)
                // The launcher independently reads this durable exact binding
                // before it can send a command to the newly created TTY.
                _ = try await self.taskLauncher.start(opened)
                if sourceID != newID { try? self.sessionAssociations.remove(sourceID) }
                let remaining = self.recentTasks.filter { $0.id != sourceID }
                do { try self.recentTaskStore.save(remaining); self.recentTasks = remaining }
                catch { self.recentTasksWarning = error.localizedDescription }
                self.launchSlot = nil
                self.lastSessionScan = -Double.infinity
                self.notice = "新窗口已绑定，启动请求已发送；请查看终端中的 CLI 授权或启动提示。"
                self.refreshConnections()
            } catch {
                self.taskOperationFailure = "任务启动未完成：\(error.localizedDescription) 已打开的窗口和已保存的绑定会保留，请检查终端后再操作。"
                self.notice = self.taskOperationFailure
            }
        }
    }

    func attachExistingSession(_ session: DiscoveredAgentSession) {
        guard let number = sessionDiscoverySlot,
              let slot = workspace.slots.first(where: { $0.number == number }), let window = slot.window, !isDemo else { return }
        do {
            _ = try session.validated()
            guard windows.isAvailable(window) else { throw ControllerError.unavailable }
            let previous = try sessionAssociations.load()
            try sessionAssociations.bind(taskID: slot.id, windowID: window.id, session: session)
            var updated = workspace
            if let index = updated.slots.firstIndex(where: { $0.id == slot.id }) {
                updated.slots[index].agentProvider = session.provider
                updated.slots[index].sessionID = session.sessionID
                updated.slots[index].agentState = .unknown
                updated.slots[index].integrationConnected = false
                updated.slots[index].unread = false
                updated.slots[index].message = "已关联会话记录，等待新的状态事件"
                updated.slots[index].updatedAt = nil
                updated.slots[index].stateSource = session.provider == "claude" ? "Claude Code 会话记录" : "Codex 会话记录"
                updated.slots[index].lastAgentEventName = ""
                updated.slots[index].lastAgentTurnID = ""
            }
            do { try persist(updated) }
            catch {
                try? TaskLaunchMetadataFile.save(previous, to: sessionAssociations.fileURL)
                throw error
            }
            if let mode = TaskLaunchMode(rawValue: session.provider) {
                let executable = TaskLaunchConfiguration.defaultExecutable(for: mode)
                if !executable.isEmpty {
                    do { try taskLaunchRecords.save(.init(mode: mode, projectDirectory: session.projectDirectory,
                        executablePath: executable, resumeSessionID: session.sessionID), for: slot.id) }
                    catch { sessionLinkWarning = error.localizedDescription }
                }
            }
            sessionDiscoverySlot = nil
            notice = "已关联确切会话，保持现有 CLI 运行；收到新事件后更新状态。"
        } catch { _ = failTaskOperation(error.localizedDescription) }
    }

    private func archiveConfirmedClosedTasks() {
        guard persistenceAvailable else { return }
        var updated = workspace
        var changed = false
        for slot in workspace.slots {
            guard slot.number != pickerSlot, slot.number != renameSlot, slot.number != integrationSlot,
                  slot.number != launchSlot, slot.number != sessionDiscoverySlot else { continue }
            guard let window = slot.window, windows.isDefinitelyClosed(window) else { continue }
            do {
                let archived = try recentTaskStore.upsert(task: slot, closedAt: Date())
                recentTasks = archived.records
                recentTasksWarning = archived.warning
                try updated.remove(slot: slot.number)
                changed = true
            } catch { recentTasksWarning = error.localizedDescription }
        }
        if changed {
            do { try persist(updated) } catch { recentTasksWarning = error.localizedDescription }
        }
    }

    private func refreshLiveWindowMetadata() {
        let discovered = windows.windows()
        var candidate = workspace
        for slot in workspace.slots {
            guard let saved = slot.window, let live = discovered.first(where: { $0.id == saved.id }) else { continue }
            _ = try? refreshVerifiedWindowMetadata(live, for: slot.id, in: &candidate)
        }
        if candidate != workspace { try? persist(candidate) }
    }

    private func checkpointRecovery() throws {
        guard !isDemo else { return }
        guard recoveryPersistenceAvailable else { throw ControllerError.persistence }
        var records = pendingRecovery
        func append(_ snapshot: WindowSnapshot, kind: WindowRecoveryRecord.Kind, previous: WindowIdentity? = nil) {
            guard !records.contains(where: { $0.kind == kind && $0.window.id == snapshot.window.id }) else { return }
            records.append(WindowRecoveryRecord(kind: kind,
                taskID: workspace.slots.first(where: { $0.window?.id == snapshot.window.id })?.id,
                window: snapshot.window, frame: snapshot.placement.frame, minimized: snapshot.placement.minimized, previousFocus: previous))
        }
        if let toggleSnapshot { append(toggleSnapshot.original, kind: .toggle, previous: toggleSnapshot.previousFocus) }
        for snapshot in layoutSnapshots.values { append(snapshot, kind: .layout) }
        for snapshot in parkedSnapshots.values { append(snapshot, kind: .parked) }
        try recoveryStore.save(records: records)
    }

    func restorePendingRecovery() {
        guard !isDemo, permissionGranted else { requireAccessibilityPermission(reason: "恢复窗口布局需要辅助功能权限"); return }
        let order: [WindowRecoveryRecord.Kind: Int] = [.toggle: 0, .layout: 1, .parked: 2]
        var remaining: [WindowRecoveryRecord] = []
        var errors: [String] = []
        var blocked: [WindowIdentity] = []
        for record in pendingRecovery.sorted(by: { order[$0.kind, default: 0] < order[$1.kind, default: 0] }) {
            if blocked.contains(where: { $0.id == record.window.id || $0.refersToSamePlatformWindow(as: record.window) }) {
                remaining.append(record); continue
            }
            if windows.isDefinitelyClosed(record.window) { continue }
            guard let live = windows.isAvailable(record.window) ? record.window : windows.reconnect(record.window) else {
                remaining.append(record)
                blocked.append(record.window)
                errors.append(record.window.applicationName + "：尚未安全连接原窗口。")
                continue
            }
            do { try windows.restore(live, to: WindowPlacement(frame: record.frame, minimized: record.minimized)) }
            catch { remaining.append(record); blocked.append(record.window); errors.append(record.window.applicationName + "：" + error.localizedDescription) }
        }
        let before = pendingRecovery
        pendingRecovery = remaining
        do { try checkpointRecovery() }
        catch { pendingRecovery = before; errors.append("恢复记录尚未保存：" + error.localizedDescription) }
        recoveryCount = pendingRecovery.count
        recoveryWarning = errors.isEmpty ? nil : errors.joined(separator: "\n")
        if errors.isEmpty { notice = "上次的窗口布局已恢复。" }
        refreshConnections()
    }

    func archiveAndSkipPendingRecovery() {
        guard !pendingRecovery.isEmpty else { return }
        do {
            let archive = store.root.appendingPathComponent("window-recovery.skipped-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: recoveryStore.journalURL, to: archive)
            let before = pendingRecovery
            pendingRecovery = []
            do { try checkpointRecovery() } catch { pendingRecovery = before; throw error }
            recoveryCount = 0
            recoveryWarning = nil
            notice = "已保留恢复记录备份并跳过本次恢复。"
        } catch { recoveryWarning = error.localizedDescription }
    }

    private func permitsNewWindowMutation() -> Bool {
        guard pendingRecovery.isEmpty else {
            recoveryWarning = "请先恢复上次布局，或保留备份后跳过恢复。"
            onRequestInventory?()
            return false
        }
        return true
    }

    func parkAllTasks() {
        guard canControlWindows, permitsNewWindowMutation() else { return }
        do {
            try restoreToggle(restoreFocus: false)
            let failures = restoreLayout()
            guard failures.isEmpty else { throw ControllerError.layout }
            for slot in workspace.slots where slot.window != nil {
                if let window = slot.window, windows.isAvailable(window) { try park(window) }
            }
            notice = "已收起任务窗口，进程继续运行。"
            refreshConnections()
        } catch { taskOperationFailure = error.localizedDescription; onRequestInventory?() }
    }

    private func park(_ window: WindowIdentity) throws {
        let live = workspace.slots.first(where: { $0.window?.id == window.id })?.window ?? window
        let placement = try windows.capturePlacement(live)
        if placement.minimized, parkedSnapshots[window.id] != nil { return }
        let previous = parkedSnapshots[window.id]
        parkedSnapshots[window.id] = WindowSnapshot(window: live, placement: placement)
        do { try checkpointRecovery() }
        catch { parkedSnapshots[window.id] = previous; throw error }
        try windows.restore(live, to: WindowPlacement(frame: placement.frame, minimized: true))
    }

    func requireAccessibilityPermission(reason: String) {
        guard !isDemo else { return }
        notice = reason + "。请在辅助功能中允许 OmniVibe 控制窗口；若系统开关已打开但仍未授权，请关闭后重新打开该开关并重启应用。"
        permissionSettingsRequested = true
        onRequestPermission?()
    }

    func requestAccess() {
        guard !isDemo else { return }
        windows.requestAccess()
        recheckPermissions()
    }

    func openAccessibilitySettings() { if !isDemo { windows.openAccessibilitySettings() } }

    func refreshConnections() {
        guard !isDemo, !wheelInteraction else { return }
        let trusted = windows.isTrusted
        if trusted && !permissionGranted {
            recheckPermissions()
            return
        }
        permissionGranted = trusted
        if permissionGranted && windowBehavior.autoReconnectExisting {
            let now = ProcessInfo.processInfo.systemUptime
            for slot in workspace.slots {
                guard let window = slot.window, !windows.isAvailable(window), window.platformWindowNumber != nil,
                      now - reconnectAttempts[window.id, default: -100] >= 30 else { continue }
                reconnectAttempts[window.id] = now
                if let live = windows.reconnect(window) {
                    var candidate = workspace
                    if (try? refreshVerifiedWindowMetadata(live, for: slot.id, in: &candidate)) == true { try? persist(candidate) }
                }
            }
        }
        if permissionGranted { archiveConfirmedClosedTasks() }
        connectedWindows = permissionGranted ? Set(workspace.slots.compactMap { slot in
            guard let window = slot.window, windows.isAvailable(window) else { return nil }
            return window.id
        }) : []
        if permissionGranted, let current = windows.currentWindow() { lastExternalWindow = current }
    }

    func openPicker(for number: Int) {
        guard canControlWindows else {
            if isDemo { notice = "这是界面演示，窗口操作已停用。" }
            else { requireAccessibilityPermission(reason: "绑定窗口需要辅助功能权限") }
            return
        }
        invalidateActivation()
        rememberExternalFocus()
        pickerSlot = number
        reloadCandidates()
        onRequestInventory?()
    }

    func reloadCandidates() {
        guard canControlWindows else { candidates = []; return }
        candidates = windows.windows()
        var refreshed = workspace
        for slot in workspace.slots {
            guard let old = slot.window, let live = candidates.first(where: { $0.id == old.id }) else { continue }
            _ = try? refreshVerifiedWindowMetadata(live, for: slot.id, in: &refreshed)
        }
        if refreshed != workspace { try? persist(refreshed) }
        refreshConnections()
    }

    func candidateIsBound(_ identity: WindowIdentity) -> Bool {
        workspace.slots.contains { $0.number != pickerSlot && $0.window?.id == identity.id }
    }

    @discardableResult
    func bind(_ identity: WindowIdentity) -> Bool {
        guard canControlWindows, let number = pickerSlot else { return false }
        guard permitsNewWindowMutation() else { return false }
        invalidateActivation()
        do {
            guard windows.isAvailable(identity) else { throw ControllerError.unavailable }
            let live = windows.currentWindow().flatMap { $0.id == identity.id ? $0 : nil } ?? identity
            let recent = pendingRecentBinding.flatMap { $0.slot == number ? $0.record : nil }
            var updated = workspace
            let previousSlot = updated.slots.first(where: { $0.number == number })
            if let old = previousSlot?.window, old.id != identity.id {
                try restoreChanges(for: old)
                try updated.remove(slot: number)
            }
            try updated.bind(live, to: number)
            if let recent {
                try updated.rename(slot: number, to: recent.task.displayName)
                if let replacement = updated.slots.first(where: { $0.number == number }) {
                    try onTaskIdentityReplaced?(recent.task.id, replacement.id)
                }
            } else if let customName = previousSlot?.name, !customName.isEmpty {
                try updated.rename(slot: number, to: customName)
            }
            if let previousSlot, previousSlot.window != nil,
               let replacement = updated.slots.first(where: { $0.number == number }), replacement.id != previousSlot.id {
                try taskLaunchRecords.transfer(from: previousSlot.id, to: replacement.id)
                try onTaskIdentityReplaced?(previousSlot.id, replacement.id)
            }
            try persist(updated)
            if let previousSlot, updated.slots.first(where: { $0.number == number })?.id != previousSlot.id {
                do { try sessionAssociations.remove(previousSlot.id) }
                catch { sessionLinkWarning = error.localizedDescription }
            }
            pickerSlot = nil
            if let recent {
                let remaining = recentTasks.filter { $0.id != recent.id }
                do { try recentTaskStore.save(remaining); recentTasks = remaining }
                catch { recentTasksWarning = error.localizedDescription }
            }
            if windowBehavior.minimizeOnCapture { try park(live) }
            notice = "已绑定到 \(String(format: "%02d", number)) 号槽位。原窗口保持打开。"
            playFeedback(.capture)
            refreshConnections()
            return true
        } catch {
            taskOperationFailure = "收纳未完成，已保存的任务绑定会保留：\(error.localizedDescription)"
            report(error)
            onRequestInventory?()
            return false
        }
    }

    @discardableResult
    func captureDraggedWindow(_ identity: WindowIdentity, originalFrame: WindowFrame, to number: Int) -> Bool {
        guard canControlWindows else { return false }
        do {
            // Dragging the title bar physically moves the source window. Put it
            // back before saving the binding, so capture never parks it under
            // the launcher or leaves a binding after failed recovery.
            try windows.restore(identity, to: WindowPlacement(frame: originalFrame, minimized: false))
            guard permitsNewWindowMutation() else { return false }
            guard workspace.slots.contains(where: { $0.number == number && $0.window == nil }) else {
                return failTaskOperation("目标槽位已占用，原窗口已恢复拖入前的位置。")
            }
            if let existing = workspace.slots.first(where: { $0.window?.id == identity.id }) {
                guard moveSlot(from: existing.number, to: number, expectedTaskID: existing.id) else { return false }
                try windows.restore(identity, to: WindowPlacement(frame: originalFrame, minimized: false))
                if windowBehavior.minimizeOnCapture { try park(identity) }
                notice = "原任务已移动到 \(number) 号槽位，名称、配装和会话保持。"
                return true
            }
            pickerSlot = number
            guard bind(identity) else { return false }
            guard workspace.slots.contains(where: { $0.number == number && $0.window?.id == identity.id }) else { return false }
            notice = "已收纳到 \(number) 号槽位，并恢复窗口拖入前的位置。"
            return true
        } catch {
            return failTaskOperation("收纳前未能恢复窗口原位置，尚未建立绑定：\(error.localizedDescription)")
        }
    }

    @discardableResult
    func restoreRejectedDrop(_ identity: WindowIdentity, originalFrame: WindowFrame) -> Bool {
        do {
            try windows.restore(identity, to: WindowPlacement(frame: originalFrame, minimized: false))
            return true
        } catch { return failTaskOperation("拖入未完成，原窗口尚未恢复位置：\(error.localizedDescription)") }
    }

    @discardableResult
    func remove(_ number: Int, expectedTaskID: UUID? = nil) -> Bool {
        guard !isDemo else { return false }
        guard let slot = workspace.slots.first(where: { $0.number == number }), slot.window != nil else {
            notice = "这个槽位已经为空。"; return false
        }
        guard expectedTaskID == nil || slot.id == expectedTaskID else {
            return failTaskOperation("任务顺序已经变化，请重新选择要移出的任务。")
        }
        var references = runtimeTaskReferences()
        invalidateActivation()
        do {
            if !layoutSnapshots.isEmpty {
                if toggleSnapshot != nil {
                    try restoreToggle(restoreFocus: false)
                    references.active = nil
                }
                let errors = restoreLayout()
                guard errors.isEmpty else {
                    reconcileRuntimeTaskReferences(references)
                    return failTaskOperation("尚未恢复全部窗口原布局，任务仍保留。请重试恢复后再移出：\n" + errors.joined(separator: "\n"))
                }
            }
            if let window = workspace.slots.first(where: { $0.number == number })?.window {
                try restoreChanges(for: window)
            }
            var updated = workspace
            try updated.remove(slot: number)
            try persist(updated)
            do { try taskLaunchRecords.remove(slot.id); try sessionAssociations.remove(slot.id) }
            catch { sessionLinkWarning = error.localizedDescription }
            reconcileRuntimeTaskReferences(references)
            notice = "已移出管理，原窗口继续运行。"
            playFeedback(.remove)
            refreshConnections()
            return true
        } catch {
            reconcileRuntimeTaskReferences(references)
            return failTaskOperation("未能移出任务，原绑定仍保留：\(error.localizedDescription)")
        }
    }

    @discardableResult
    func reorderSlot(from source: Int, to target: Int, expectedTaskID: UUID) -> Bool {
        orderSlot(from: source, to: target, expectedTaskID: expectedTaskID, moveOnly: false)
    }

    @discardableResult
    func moveSlot(from source: Int, to target: Int, expectedTaskID: UUID) -> Bool {
        orderSlot(from: source, to: target, expectedTaskID: expectedTaskID, moveOnly: true)
    }

    private func orderSlot(from source: Int, to target: Int, expectedTaskID: UUID, moveOnly: Bool) -> Bool {
        guard !isDemo else { return false }
        guard let task = workspace.slots.first(where: { $0.number == source }),
              task.id == expectedTaskID, task.window != nil else {
            return failTaskOperation("拖动的任务已经变化，请重新拖动当前任务。")
        }
        do {
            var updated = workspace
            if moveOnly { try updated.move(from: source, to: target) }
            else { try updated.reorder(from: source, to: target) }
            guard updated != workspace else { return true }
            var references = runtimeTaskReferences()
            cancelArrangementPresentation()
            if moveOnly, !layoutSnapshots.isEmpty {
                if toggleSnapshot != nil {
                    do { try restoreToggle(restoreFocus: false); references.active = nil }
                    catch { reconcileRuntimeTaskReferences(references); throw error }
                }
                let errors = restoreLayout()
                guard errors.isEmpty else {
                    reconcileRuntimeTaskReferences(references)
                    return failTaskOperation("移动前未能完整恢复窗口布局，请重试：\n" + errors.joined(separator: "\n"))
                }
            }
            reconcileRuntimeTaskReferences(references)
            try onPrepareSlotOrdering?(workspace.slots)
            try persist(updated)
            invalidateActivation()
            reconcileRuntimeTaskReferences(references)
            notice = moveOnly ? "任务已移动到 \(target) 号槽位。" : "顺序已更新，各任务使用新编号对应的快捷键。"
            playFeedback(.reorder)
            refreshConnections()
            return true
        } catch { return failTaskOperation("未能调整任务顺序，原任务仍保留：\(error.localizedDescription)") }
    }

    private struct RuntimeTaskReferences {
        var active: UUID?
        let picker: UUID?
        let rename: UUID?
        let integration: UUID?
        let launch: UUID?
        let discovery: UUID?
    }

    private func runtimeTaskReferences() -> RuntimeTaskReferences {
        func id(_ number: Int?) -> UUID? { workspace.slots.first(where: { $0.number == number })?.id }
        return RuntimeTaskReferences(active: id(activeSlot), picker: id(pickerSlot), rename: id(renameSlot), integration: id(integrationSlot),
            launch: id(launchSlot), discovery: id(sessionDiscoverySlot))
    }

    private func reconcileRuntimeTaskReferences(_ references: RuntimeTaskReferences) {
        func number(_ id: UUID?) -> Int? { workspace.slots.first(where: { $0.id == id })?.number }
        activeSlot = number(references.active)
        pickerSlot = number(references.picker)
        renameSlot = number(references.rename)
        integrationSlot = number(references.integration)
        launchSlot = number(references.launch)
        sessionDiscoverySlot = number(references.discovery)
        if let snapshot = toggleSnapshot {
            if let number = workspace.slots.first(where: { $0.window?.id == snapshot.original.window.id })?.number {
                toggleSnapshot = ToggleSnapshot(number: number, original: snapshot.original, previousFocus: snapshot.previousFocus)
            } else { toggleSnapshot = nil }
        }
    }

    @discardableResult
    private func failTaskOperation(_ message: String) -> Bool {
        taskOperationFailure = message
        notice = message
        onRequestInventory?()
        return false
    }

    func beginRenaming(_ slot: TaskSlot) { renameText = slot.displayName; renameSlot = slot.number }

    func finishRenaming() {
        guard let number = renameSlot, !isDemo else { return }
        do {
            var updated = workspace
            try updated.rename(slot: number, to: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
            try persist(updated)
            renameSlot = nil
        } catch { report(error) }
    }

    func enterSlot(_ number: Int) { toggleSlot(number, forceEnter: true) }

    func toggleSlot(_ number: Int, forceEnter: Bool = false, previousWindow: WindowIdentity? = nil) {
        guard canControlWindows else {
            requireAccessibilityPermission(reason: "切换任务需要辅助功能权限")
            return
        }
        guard permitsNewWindowMutation() else { return }
        cancelArrangementPresentation()
        invalidateActivation()
        guard let slot = workspace.slots.first(where: { $0.number == number }), let window = slot.window else {
            openPicker(for: number)
            return
        }
        lastActivationTaskID = slot.id
        do {
            let current = windows.currentWindow()
            if !forceEnter, managementWindowIsActive?() != true,
               toggleSnapshot?.number == number, current?.id == window.id {
                onBeforeTaskActivation?()
                try restoreToggle(restoreFocus: true)
                activationFailure = nil
                notice = "已恢复窗口原状态。"
                return
            }
            guard windows.isAvailable(window) else {
                notice = "这个窗口暂时不可访问，请重试；若已关闭，请重新绑定。"
                activationFailure = "\(number) 号 · \(slot.displayName)：窗口暂时不可访问，请重新连接这个具体窗口。"
                if windows.isDefinitelyClosed(window) { openPicker(for: number) }
                else { reconnectThenEnter(slot, forceEnter: forceEnter, previousWindow: previousWindow ?? current ?? lastExternalWindow) }
                return
            }
            // Returning from inventory/settings is a request to enter this
            // task again, even when its previous toggle snapshot still exists.
            if toggleSnapshot?.number == number {
                onBeforeTaskActivation?()
                if !layoutSnapshots.isEmpty || windowBehavior.wakeMode == .workArea {
                    if let area = LayoutEngine.frames(count: 1, workArea: windows.workArea(for: window), gap: windowBehavior.layoutGap).first {
                        try windows.setFrame(area, for: window)
                    }
                }
                try windows.activate(window)
                confirmActivation(window, slot: number)
                return
            }
            let previous = previousWindow ?? current ?? lastExternalWindow
            let previousFocus = previous?.id == toggleSnapshot?.original.window.id ? toggleSnapshot?.previousFocus : previous
            try restoreToggle(restoreFocus: false)
            let snapshot = WindowSnapshot(window: window, placement: try windows.capturePlacement(window))
            // Activation can partially mutate the window before an AX failure.
            // Keep recovery data before the first system operation.
            toggleSnapshot = ToggleSnapshot(number: number, original: snapshot, previousFocus: previousFocus)
            do { try checkpointRecovery() }
            catch { toggleSnapshot = nil; throw error }
            onBeforeTaskActivation?()
            if !layoutSnapshots.isEmpty || windowBehavior.wakeMode == .workArea {
                if let area = LayoutEngine.frames(count: 1, workArea: windows.workArea(for: window), gap: windowBehavior.layoutGap).first {
                    try windows.setFrame(area, for: window)
                }
            }
            try windows.activate(window)
            confirmActivation(window, slot: number)
            refreshConnections()
        } catch {
            activationFailure = "\(number) 号 · \(slot.displayName)：\(error.localizedDescription)"
            report(error)
            onRequestInventory?()
        }
    }

    /// A few applications expose AX windows only after an explicit foreground
    /// request. Keep this out of background reconnection and route completion
    /// by immutable task identity so a later user action cancels the old one.
    private func reconnectThenEnter(_ slot: TaskSlot, forceEnter: Bool, previousWindow: WindowIdentity?) {
        guard let original = slot.window else { return }
        let epoch = activationEpoch
        activationTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.activationEpoch == epoch { self.activationTask = nil } }
            do {
                let restored = try await self.windows.reconnectForActivation(original)
                guard !Task.isCancelled, !self.stopping, self.activationEpoch == epoch,
                      let current = self.workspace.slots.first(where: { $0.id == slot.id }),
                      current.window?.id == original.id else { return }
                guard let restored, restored.id == original.id, self.windows.isAvailable(restored) else {
                    self.openPicker(for: current.number)
                    return
                }
                var updated = self.workspace
                _ = try self.refreshVerifiedWindowMetadata(restored, for: current.id, in: &updated)
                if updated != self.workspace { try self.persist(updated) }
                self.connectedWindows.insert(original.id)
                self.activationTask = nil
                self.toggleSlot(current.number, forceEnter: forceEnter, previousWindow: previousWindow)
            } catch {
                guard !Task.isCancelled, !self.stopping, self.activationEpoch == epoch,
                      let current = self.workspace.slots.first(where: { $0.id == slot.id }),
                      current.window?.id == original.id else { return }
                self.activationFailure = error.localizedDescription
                self.notice = error.localizedDescription
                self.openPicker(for: current.number)
            }
        }
    }

    private func reconnectThenArrange(_ slots: [TaskSlot], previousWindow: WindowIdentity?) {
        let epoch = activationEpoch
        let bindings = workspace.slots.map { ($0.id, $0.window?.id) }
        activationTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.activationEpoch == epoch { self.activationTask = nil } }
            @MainActor func stillCurrent() -> Bool {
                !Task.isCancelled && !self.stopping && self.activationEpoch == epoch &&
                    self.workspace.slots.count == bindings.count &&
                    zip(self.workspace.slots, bindings).allSatisfy { slot, saved in slot.id == saved.0 && slot.window?.id == saved.1 }
            }
            do {
                for slot in slots {
                    guard stillCurrent(), let original = slot.window else { return }
                    guard let restored = try await self.windows.reconnectForActivation(original) else {
                        if stillCurrent() { self.reportArrangementReconnectFailure() }
                        return
                    }
                    guard stillCurrent() else { return }
                    guard restored.id == original.id, self.windows.isAvailable(restored) else {
                        self.reportArrangementReconnectFailure()
                        return
                    }
                    var updated = self.workspace
                    _ = try self.refreshVerifiedWindowMetadata(restored, for: slot.id, in: &updated)
                    if updated != self.workspace { try self.persist(updated) }
                    self.connectedWindows.insert(restored.id)
                }
                guard stillCurrent() else { return }
                self.activationTask = nil
                self.toggleArrangement(preservingFocus: previousWindow)
            } catch {
                guard stillCurrent() else { return }
                self.reportArrangementReconnectFailure()
            }
        }
    }

    private func reportArrangementReconnectFailure() {
        let message = "有窗口尚未连接，本次未修改布局。请先重连后重试。"
        arrangementSummary = message
        arrangementWarning = message
        arrangementFailure = message
        notice = message
        onRequestInventory?()
    }

    func retryLastActivation() {
        guard let taskID = lastActivationTaskID,
              let slot = workspace.slots.first(where: { $0.id == taskID && $0.window != nil }) else {
            activationFailure = "原任务已移出管理，请选择当前槽位。"; return
        }
        if managementWindowIsActive?() != true, windows.currentWindow()?.id == slot.window?.id { activationFailure = nil; return }
        enterSlot(slot.number)
    }

    func toggleArrangement() { toggleArrangement(preservingFocus: nil) }

    private func toggleArrangement(preservingFocus: WindowIdentity?) {
        guard canControlWindows else {
            requireAccessibilityPermission(reason: "排列窗口需要辅助功能权限")
            return
        }
        guard permitsNewWindowMutation() else { return }
        invalidateActivation()
        if let preservingFocus { lastExternalWindow = preservingFocus }
        else { rememberExternalFocus() }
        do {
            if layoutSnapshots.isEmpty {
                let disconnected = workspace.slots.filter { slot in
                    guard let window = slot.window else { return false }
                    return !windows.isAvailable(window) && !windows.isDefinitelyClosed(window)
                }
                if !disconnected.isEmpty {
                    reconnectThenArrange(disconnected, previousWindow: lastExternalWindow)
                    return
                }
            }
            try restoreToggle(restoreFocus: false)
            if !layoutSnapshots.isEmpty {
                let errors = restoreLayout()
                arrangementSummary = errors.isEmpty ? "已恢复排列前的窗口布局。" : "布局恢复尚未完成，仍保留恢复记录。"
                arrangementWarning = errors.isEmpty ? nil : errors.joined(separator: "\n")
                notice = arrangementWarning ?? "已恢复排列前的窗口布局。"
                if errors.isEmpty { playFeedback(.restore) }
                return
            }
            var available: [WindowIdentity] = []
            var skipped: [String] = []
            for window in workspace.slots.sorted(by: { $0.number < $1.number }).compactMap(\.window) {
                guard !windows.isDefinitelyClosed(window) else { skipped.append(window.applicationName + "：窗口已关闭"); continue }
                if let reason = windows.arrangementBlockReason(window) { skipped.append(window.applicationName + "：" + reason) }
                else { available.append(window) }
            }
            guard !available.isEmpty else {
                arrangementSummary = "已收纳 \(occupiedCount) 个窗口，本次可排列 0 个。"
                arrangementWarning = skipped.isEmpty ? nil : skipped.joined(separator: "\n")
                notice = arrangementWarning ?? "先绑定至少一个可用窗口，再排列工作空间。"
                return
            }
            let focused = available.first { $0.id == lastExternalWindow?.id } ?? available.first!
            let snapshots = try available.map { WindowSnapshot(window: $0, placement: try windows.captureArrangementPlacement($0)) }
            // Each display retains its own windows. An unrelated foreground
            // application must not move the whole workspace onto its monitor.
            var groups: [(displayID: String, area: WindowFrame, snapshots: [WindowSnapshot])] = []
            for snapshot in snapshots {
                let display = windows.arrangementDisplay(for: snapshot.window)
                // Dock/menu animation can change visibleFrame between AX calls.
                // Group by physical display, retaining its first sampled area.
                if let index = groups.firstIndex(where: { $0.displayID == display.id }) { groups[index].snapshots.append(snapshot) }
                else { groups.append((display.id, display.workArea, [snapshot])) }
            }
            var plan: [(window: WindowIdentity, frame: WindowFrame)] = []
            for group in groups {
                var ordered = group.snapshots
                if arrangement == .mainLeft, let index = ordered.firstIndex(where: { $0.window.id == focused.id }) {
                    ordered.insert(ordered.remove(at: index), at: 0)
                }
                let frames = LayoutEngine.frames(count: ordered.count, workArea: group.area, gap: windowBehavior.layoutGap, mode: arrangement)
                guard frames.count == ordered.count else { throw ControllerError.layout }
                plan += zip(ordered, frames).map { ($0.0.window, $0.1) }
            }
            arrangementWarning = nil
            // One failed resize rolls the complete operation back. Keep every
            // original until rollback is confirmed, including the failed window.
            layoutSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.window.id, $0) })
            do { try checkpointRecovery() }
            catch { layoutSnapshots = [:]; throw error }
            onBeforeArrangement?()
            var resizingApplication = ""
            do {
                for item in plan {
                    resizingApplication = item.window.applicationName
                    try windows.setFrame(item.frame, for: item.window)
                }
            } catch {
                let cause = resizingApplication + "：" + error.localizedDescription
                let recovery = restoreLayout()
                arrangementSummary = recovery.isEmpty ? "本次排列未完成，已恢复原布局。" : "本次排列未完成，部分窗口仍待恢复。"
                arrangementWarning = recovery.isEmpty
                    ? "排列未完成，已恢复原布局：\(cause) 可减少窗口数量或改用其他排列方式。"
                    : "排列未完成，部分原布局仍待恢复：\(cause)\n" + recovery.joined(separator: "\n")
                notice = arrangementWarning
                arrangementFailure = arrangementWarning
                onRequestInventory?()
                return
            }
            isArranged = true
            arrangementSummary = "已收纳 \(occupiedCount) 个窗口，本次已排列 \(available.count) 个" + (skipped.isEmpty ? "。" : "，跳过 \(skipped.count) 个。")
            arrangementTargets = Dictionary(uniqueKeysWithValues: plan.map { ($0.window.id, $0.frame) })
            arrangementAreas = Dictionary(uniqueKeysWithValues: groups.flatMap { group in group.snapshots.map { ($0.window.id, group.area) } })
            let restoreKey = shortcutLabel(.arrange)
            notice = restoreKey.isEmpty ? "窗口已排列，再点恢复布局即可还原。" : "窗口已排列，再按 \(restoreKey) 恢复。"
            if !skipped.isEmpty { arrangementWarning = "已跳过：" + skipped.joined(separator: "\n") }
            playFeedback(.arrange)
            presentArrangement(available, focusing: focused)
        } catch {
            arrangementSummary = "本次排列未完成。"
            arrangementWarning = error.localizedDescription
            arrangementFailure = arrangementWarning
            report(error)
            onRequestInventory?()
        }
    }

    func cancelArrangementPresentation() {
        arrangementEpoch &+= 1
        arrangementPresentation?.cancel()
        arrangementPresentation = nil
        isPresentingArrangement = false
    }

    private func presentArrangement(_ arranged: [WindowIdentity], focusing focus: WindowIdentity) {
        let epoch = arrangementEpoch
        isPresentingArrangement = true
        let order = arranged.filter { $0.id != focus.id } + [focus]
        arrangementPresentation = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.arrangementEpoch == epoch { self.isPresentingArrangement = false; self.arrangementPresentation = nil }
            }
            for window in order {
                guard !Task.isCancelled, self.arrangementEpoch == epoch else { return }
                do {
                    try self.windows.activate(window)
                    try await self.windows.confirmActivation(window)
                } catch {
                    guard !Task.isCancelled, self.arrangementEpoch == epoch else { return }
                    self.arrangementWarning = "布局已完成，未能置前 \(window.applicationName)：\(error.localizedDescription)"
                    self.notice = self.arrangementWarning
                }
            }
            self.refreshConnections()
        }
    }

    private func restoreToggle(restoreFocus: Bool, confirmsFocus: Bool = true) throws {
        invalidateActivation()
        guard let snapshot = toggleSnapshot else { return }
        if !windows.isDefinitelyClosed(snapshot.original.window) {
            try windows.restore(snapshot.original.window, to: snapshot.original.placement)
        }
        toggleSnapshot = nil
        do { try checkpointRecovery() }
        catch { toggleSnapshot = snapshot; throw error }
        activeSlot = nil
        if restoreFocus, let previous = snapshot.previousFocus, !windows.isDefinitelyClosed(previous) {
            try windows.activate(previous)
            if confirmsFocus { confirmActivation(previous, slot: nil) }
        }
    }

    private func restoreLayout() -> [String] {
        var failures: [String] = []
        let before = layoutSnapshots
        for (id, snapshot) in Array(layoutSnapshots) {
            do {
                if !windows.isDefinitelyClosed(snapshot.window) {
                    try windows.restore(snapshot.window, to: snapshot.placement)
                }
                layoutSnapshots.removeValue(forKey: id)
                arrangementTargets.removeValue(forKey: id)
                arrangementAreas.removeValue(forKey: id)
            } catch { failures.append("\(snapshot.window.applicationName)：\(error.localizedDescription)") }
        }
        do { try checkpointRecovery() }
        catch { layoutSnapshots = before; failures.append("窗口恢复记录未能保存：" + error.localizedDescription) }
        isArranged = !layoutSnapshots.isEmpty
        if !before.isEmpty, layoutSnapshots.isEmpty { onArrangementRestored?() }
        return failures
    }

    private func restoreChanges(for window: WindowIdentity) throws {
        let priorLayout = layoutSnapshots
        let priorParked = parkedSnapshots
        if toggleSnapshot?.original.window.id == window.id { try restoreToggle(restoreFocus: false) }
        if let snapshot = layoutSnapshots[window.id] {
            if !windows.isDefinitelyClosed(window) { try windows.restore(window, to: snapshot.placement) }
            layoutSnapshots.removeValue(forKey: window.id)
            arrangementTargets.removeValue(forKey: window.id)
            arrangementAreas.removeValue(forKey: window.id)
            isArranged = !layoutSnapshots.isEmpty
        }
        if let parked = parkedSnapshots[window.id] {
            if !windows.isDefinitelyClosed(window) { try windows.restore(window, to: parked.placement) }
            parkedSnapshots.removeValue(forKey: window.id)
        }
        do { try checkpointRecovery() }
        catch { layoutSnapshots = priorLayout; parkedSnapshots = priorParked; isArranged = !layoutSnapshots.isEmpty; throw error }
    }

    func prepareToQuit() -> [String] {
        cancelArrangementPresentation()
        stopping = true
        launchOperation?.cancel()
        launchOperation = nil
        isRecordingShortcut = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        statusTimer?.invalidate()
        statusTimer = nil
        hotKeys?.unregister()
        hotKeys = nil
        guard !isDemo else { return [] }
        var failures: [String] = []
        do { try restoreToggle(restoreFocus: true, confirmsFocus: false) } catch { failures.append(error.localizedDescription) }
        failures += restoreLayout()
        for snapshot in Array(parkedSnapshots.values) {
            do {
                if !windows.isDefinitelyClosed(snapshot.window) { try windows.restore(snapshot.window, to: snapshot.placement) }
                parkedSnapshots.removeValue(forKey: snapshot.window.id)
            } catch { failures.append(snapshot.window.applicationName + "：" + error.localizedDescription) }
        }
        do { try checkpointRecovery() } catch { failures.append(error.localizedDescription) }
        return failures
    }

    func resumeAfterCancelledQuit() {
        stopping = false
        recheckPermissions()
        startMonitoring()
    }

    private func startMonitoring() {
        guard startsMonitoring, !isDemo else { return }
        refreshTimer?.invalidate()
        statusTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshConnections() }
        }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollStatusEvents() }
        }
    }

    func playFeedback(_ cue: AudioCue) { if !isDemo { onFeedback?(cue) } }

    /// Acknowledge accepted events only after the matching workspace is safely
    /// saved. Ignored old/task-rebound events can be retired without a write.
    func pollStatusEvents() async {
        guard !isDemo, !stopping, !statusPollBusy else { return }
        statusPollBusy = true
        defer { statusPollBusy = false }
        do {
            if startsMonitoring { await pollLinkedSessions() }
            let batch = try await statusInbox.read()
            guard !stopping, !batch.isEmpty else { return }
            var updated = workspace
            var changed = false
            var acceptedSessionTasks = Set<UUID>()
            var attention: [UUID: AudioCue] = [:]
            for item in batch {
                let previous = updated.slots.first { $0.id == item.event.taskID }
                if try updated.apply(item.event) {
                    changed = true
                    if ["claude", "codex"].contains(item.event.provider), UUID(uuidString: item.event.sessionID) != nil {
                        acceptedSessionTasks.insert(item.event.taskID)
                    }
                    if let slot = updated.slots.first(where: { $0.id == item.event.taskID }) {
                        if slot.unread && (previous?.unread != true || previous?.agentState != slot.agentState) {
                            switch slot.agentState {
                            case .waiting: attention[slot.id] = .waiting
                            case .ready: attention[slot.id] = .ready
                            case .error: attention[slot.id] = .error
                            default: attention.removeValue(forKey: slot.id)
                            }
                        } else if !slot.unread { attention.removeValue(forKey: slot.id) }
                    }
                }
            }
            if changed {
                try persist(updated)
                for slot in workspace.slots where acceptedSessionTasks.contains(slot.id) {
                    do { try taskLaunchRecords.updateSession(taskID: slot.id, provider: slot.agentProvider, sessionID: slot.sessionID) }
                    catch { sessionLinkWarning = error.localizedDescription }
                }
            }
            try await statusInbox.acknowledge(batch)
            if notice?.hasPrefix("任务状态暂未保存") == true { notice = nil }
            for (taskID, cue) in attention {
                playFeedback(cue)
                if cue == .ready, let slot = workspace.slots.first(where: { $0.id == taskID && $0.window != nil }),
                   windows.currentWindow()?.id != slot.window?.id { onTaskReady?(taskID, slot.displayName) }
            }
        } catch {
            let message = "任务状态暂未保存，将保留事件并重试：\(error.localizedDescription)"
            if notice != message { notice = message }
        }
    }

    private func pollLinkedSessions() async {
        do {
            var associations = try sessionAssociations.load()
            func shouldObserve(_ slot: TaskSlot) -> Bool {
                slot.window != nil && ["claude", "codex"].contains(slot.agentProvider) &&
                    UUID(uuidString: slot.sessionID) != nil &&
                    (slot.lastAgentEventName.isEmpty || slot.lastAgentEventName == "Transcript")
            }
            let needsKnownSession = workspace.slots.filter { slot in
                shouldObserve(slot) && !associations.contains(where: { $0.taskID == slot.id && $0.windowID == slot.window?.id })
            }
            let now = ProcessInfo.processInfo.systemUptime
            if !needsKnownSession.isEmpty, now - lastSessionScan >= 30 {
                lastSessionScan = now
                let result = await sessionDiscovery.discover()
                guard !stopping else { return }
                if !result.warnings.isEmpty { sessionLinkWarning = result.warnings.prefix(3).joined(separator: "\n") }
                for requested in needsKnownSession {
                    guard let slot = workspace.slots.first(where: { $0.id == requested.id }), shouldObserve(slot),
                          let window = slot.window else { continue }
                    let matches = result.sessions.filter { $0.provider == slot.agentProvider &&
                        $0.sessionID.caseInsensitiveCompare(slot.sessionID) == .orderedSame }
                    if matches.count == 1, let session = matches.first {
                        try sessionAssociations.bind(taskID: slot.id, windowID: window.id, session: session)
                    }
                }
                associations = try sessionAssociations.load()
            }
            let active = associations.filter { association in
                workspace.slots.contains { slot in
                    slot.id == association.taskID && slot.window?.id == association.windowID && shouldObserve(slot) &&
                        slot.agentProvider == association.session.provider &&
                        slot.sessionID.caseInsensitiveCompare(association.session.sessionID) == .orderedSame
                }
            }
            for update in await sessionObserver.poll(active) {
                if sessionUpdateBacklog[update.taskID].map({ $0.event.at < update.event.at }) ?? true {
                    sessionUpdateBacklog[update.taskID] = update
                }
            }
            for (taskID, update) in sessionUpdateBacklog {
                guard workspace.slots.contains(where: { $0.id == taskID && $0.window?.id == update.windowID && shouldObserve($0) &&
                    $0.agentProvider == update.event.provider && $0.sessionID.caseInsensitiveCompare(update.event.sessionID) == .orderedSame }) else {
                    sessionUpdateBacklog.removeValue(forKey: taskID); continue
                }
                _ = try StatusEventInbox.publish(update.event, root: store.root)
                sessionUpdateBacklog.removeValue(forKey: taskID)
            }
            if sessionLinkWarning?.hasPrefix("会话记录暂未同步") == true { sessionLinkWarning = nil }
        } catch { sessionLinkWarning = "会话记录暂未同步，将保留事件并重试：" + error.localizedDescription }
    }

    private func invalidateActivation() {
        cancelArrangementPresentation()
        activationEpoch &+= 1
        activationTask?.cancel()
        activationTask = nil
        activeSlot = nil
    }

    private func confirmActivation(_ window: WindowIdentity, slot number: Int?) {
        let epoch = activationEpoch
        activationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.windows.confirmActivation(window)
                guard !Task.isCancelled, self.activationEpoch == epoch else { return }
                if let number {
                    guard self.workspace.slots.first(where: { $0.number == number })?.window?.id == window.id,
                          self.toggleSnapshot?.original.window.id == window.id else { return }
                    self.activeSlot = number
                    self.activationFailure = nil
                    var updated = self.workspace
                    if updated.slots.first(where: { $0.number == number })?.unread == true {
                        try updated.markRead(slot: number)
                        try self.persist(updated)
                    }
                    self.notice = nil
                    self.playFeedback(.switch)
                }
                self.activationTask = nil
                self.refreshConnections()
            } catch {
                guard !Task.isCancelled, self.activationEpoch == epoch else { return }
                self.activeSlot = nil
                self.activationTask = nil
                self.notice = number == nil
                    ? "窗口布局已恢复，但未能确认返回先前窗口：\(error.localizedDescription)"
                    : "未能确认目标窗口已激活：\(error.localizedDescription)。原状态仍保留，可再次按键恢复。"
                self.activationFailure = self.notice
            }
        }
    }

    private func persist(_ updated: WorkspaceState) throws {
        guard !isDemo else { return }
        guard persistenceAvailable else { throw ControllerError.persistence }
        try store.save(updated)
        workspace = updated
    }

    private func report(_ error: Error) { notice = error.localizedDescription }
}

private enum ControllerError: LocalizedError {
    case unavailable, layout, persistence
    var errorDescription: String? {
        switch self {
        case .unavailable: return "窗口已关闭或不可访问，请刷新列表后重新选择。"
        case .layout: return "无法计算窗口排列，原窗口未被修改。"
        case .persistence: return "配置文件未能安全读取。请先检查原配置及备份，本次未保存修改。"
        }
    }
}
