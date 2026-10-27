import Carbon
import Foundation
import OmniVibeCore

struct WindowBehaviorPreferences: Codable, Equatable, Sendable {
    enum WakeMode: String, Codable, CaseIterable, Sendable { case lastPosition, workArea }
    enum OverviewSize: String, Codable, CaseIterable, Sendable { case small, medium, large }

    var layoutGap: Double = 12
    var arrangement: ArrangementMode = .balanced
    var wakeMode: WakeMode = .lastPosition
    var minimizeOnCapture = true
    var wheelSwitchEnabled = true
    var wheelModifiers = UInt32(optionKey)
    var shortcutsPaused = false
    var completionSoundEnabled = true
    // Enabling notifications and asking the OS for access are explicit UI work.
    var systemNotificationsEnabled = false
    var autoReconnectExisting = true
    var autoRestoreRecovery = false
    var showRecoveryOnStartup = true
    var hideLauncherOnArrange = false
    var overviewSize: OverviewSize = .large
    var launcherExtent: Double = 360

    init() {}

    /// Returns a complete candidate before persistence or runtime publication.
    /// Sliders clamp ordinary out-of-range values; non-finite values and
    /// unsupported modifier bits fail rather than silently changing behavior.
    func validated() throws -> Self {
        guard layoutGap.isFinite, launcherExtent.isFinite else { throw ValidationError.invalidNumber }
        let allowed = UInt32(optionKey | controlKey | shiftKey | cmdKey)
        guard wheelModifiers != 0, wheelModifiers & ~allowed == 0 else { throw ValidationError.invalidModifiers }
        var result = self
        result.layoutGap = min(40, max(0, layoutGap))
        result.launcherExtent = min(520, max(280, launcherExtent))
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case layoutGap, arrangement, wakeMode, minimizeOnCapture, wheelSwitchEnabled, wheelModifiers
        case shortcutsPaused, completionSoundEnabled, systemNotificationsEnabled, autoReconnectExisting
        case autoRestoreRecovery, showRecoveryOnStartup, hideLauncherOnArrange, overviewSize, launcherExtent
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        layoutGap = try values.decodeIfPresent(Double.self, forKey: .layoutGap) ?? layoutGap
        if let raw = try values.decodeIfPresent(String.self, forKey: .arrangement) {
            guard let mode = ArrangementMode(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .arrangement, in: values, debugDescription: "Unknown arrangement")
            }
            arrangement = mode
        }
        wakeMode = try values.decodeIfPresent(WakeMode.self, forKey: .wakeMode) ?? wakeMode
        minimizeOnCapture = try values.decodeIfPresent(Bool.self, forKey: .minimizeOnCapture) ?? minimizeOnCapture
        wheelSwitchEnabled = try values.decodeIfPresent(Bool.self, forKey: .wheelSwitchEnabled) ?? wheelSwitchEnabled
        wheelModifiers = try values.decodeIfPresent(UInt32.self, forKey: .wheelModifiers) ?? wheelModifiers
        shortcutsPaused = try values.decodeIfPresent(Bool.self, forKey: .shortcutsPaused) ?? shortcutsPaused
        completionSoundEnabled = try values.decodeIfPresent(Bool.self, forKey: .completionSoundEnabled) ?? completionSoundEnabled
        systemNotificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .systemNotificationsEnabled) ?? systemNotificationsEnabled
        autoReconnectExisting = try values.decodeIfPresent(Bool.self, forKey: .autoReconnectExisting) ?? autoReconnectExisting
        autoRestoreRecovery = try values.decodeIfPresent(Bool.self, forKey: .autoRestoreRecovery) ?? autoRestoreRecovery
        showRecoveryOnStartup = try values.decodeIfPresent(Bool.self, forKey: .showRecoveryOnStartup) ?? showRecoveryOnStartup
        hideLauncherOnArrange = try values.decodeIfPresent(Bool.self, forKey: .hideLauncherOnArrange) ?? hideLauncherOnArrange
        overviewSize = try values.decodeIfPresent(OverviewSize.self, forKey: .overviewSize) ?? overviewSize
        launcherExtent = try values.decodeIfPresent(Double.self, forKey: .launcherExtent) ?? launcherExtent
        self = try validated()
    }

    func encode(to encoder: Encoder) throws {
        let value = try validated()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(value.layoutGap, forKey: .layoutGap)
        try values.encode(value.arrangement.rawValue, forKey: .arrangement)
        try values.encode(value.wakeMode, forKey: .wakeMode)
        try values.encode(value.minimizeOnCapture, forKey: .minimizeOnCapture)
        try values.encode(value.wheelSwitchEnabled, forKey: .wheelSwitchEnabled)
        try values.encode(value.wheelModifiers, forKey: .wheelModifiers)
        try values.encode(value.shortcutsPaused, forKey: .shortcutsPaused)
        try values.encode(value.completionSoundEnabled, forKey: .completionSoundEnabled)
        try values.encode(value.systemNotificationsEnabled, forKey: .systemNotificationsEnabled)
        try values.encode(value.autoReconnectExisting, forKey: .autoReconnectExisting)
        try values.encode(value.autoRestoreRecovery, forKey: .autoRestoreRecovery)
        try values.encode(value.showRecoveryOnStartup, forKey: .showRecoveryOnStartup)
        try values.encode(value.hideLauncherOnArrange, forKey: .hideLauncherOnArrange)
        try values.encode(value.overviewSize, forKey: .overviewSize)
        try values.encode(value.launcherExtent, forKey: .launcherExtent)
    }

    enum ValidationError: LocalizedError {
        case invalidNumber, invalidModifiers, saveFailed
        var errorDescription: String? {
            let localizedSource: String? = {
                switch self {
                case .invalidNumber: return "窗口间距和轮盘尺寸必须是有限数值。"
                case .invalidModifiers: return "滚轮切换请使用至少一个 Control、Option、Shift 或 Command 修饰键。"
                case .saveFailed: return "窗口行为设置未能完整保存，原运行设置仍保留。"
                }
        }()
            return localizedSource.map { L10n.errorText($0) }
        }
    }
}

final class WindowBehaviorPreferencesStore {
    static let key = "OmniVibe.WindowBehavior.v1"
    private let preferences: UserDefaults
    private(set) var value = WindowBehaviorPreferences()
    private(set) var warning: String?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        guard let stored = preferences.object(forKey: Self.key) else { return }
        do {
            guard let bytes = stored as? Data else { throw WindowBehaviorPreferences.ValidationError.saveFailed }
            value = try JSONDecoder().decode(WindowBehaviorPreferences.self, from: bytes)
        } catch {
            // Do not replace corrupt bytes merely by opening settings.
            warning = "窗口行为设置无法读取，已暂用默认值；原配置仍保留，只有明确保存后才会替换。"
        }
    }

    /// One validated JSON value replaces one UserDefaults key. Read-back checks
    /// the defaults domain, not a guarantee that asynchronous disk flushing has
    /// finished. Runtime state changes only after that replacement succeeds.
    func save(_ candidate: WindowBehaviorPreferences) throws {
        let checked = try candidate.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(checked)
        preferences.set(bytes, forKey: Self.key)
        guard preferences.data(forKey: Self.key) == bytes else { throw WindowBehaviorPreferences.ValidationError.saveFailed }
        value = checked
        warning = nil
    }
}
