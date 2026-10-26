import Foundation
import UserNotifications

private let taskNotificationCategory = "com.xiobio.omnivibe.task-status"
private let taskNotificationUUIDKey = "OmniVibeTaskID"
private let taskNotificationIdentifierPrefix = "OmniVibe.task."

enum TaskNotificationAuthorization: String, Codable, Equatable, Sendable {
    case notDetermined, denied, authorized, provisional, ephemeral, unknown

    var canDeliver: Bool { self == .authorized || self == .provisional || self == .ephemeral }

    var label: String {
        switch self {
        case .notDetermined: return "尚未询问"
        case .denied: return "已拒绝"
        case .authorized: return "已允许"
        case .provisional: return "临时允许 · 安静送达"
        case .ephemeral: return "临时授权"
        case .unknown: return "系统状态未知"
        }
    }

    /// Using documented raw values also handles platforms whose SDK marks
    /// the ephemeral case unavailable, without widening permission requests.
    init(systemRawValue: Int) {
        switch systemRawValue {
        case 0: self = .notDetermined
        case 1: self = .denied
        case 2: self = .authorized
        case 3: self = .provisional
        case 4: self = .ephemeral
        default: self = .unknown
        }
    }
}

enum TaskNotificationDelivery: Equatable, Sendable {
    /// Accepted by the notification center; not confirmation of banner display.
    case sent
    case notAuthorized(TaskNotificationAuthorization)
    case failed(String)
}

struct TaskNotificationContent: Equatable, Sendable {
    let identifier: String
    let categoryIdentifier: String
    let taskID: UUID
    let title: String
    let body: String
}

struct TaskNotificationResponse: Equatable, Sendable {
    enum Action: Equatable, Sendable { case open, dismiss, other }
    let identifier: String
    let categoryIdentifier: String
    let taskID: String?
    let action: Action
}

@MainActor
protocol TaskNotificationBackend: AnyObject {
    var responseHandler: ((TaskNotificationResponse) -> Void)? { get set }
    func authorizationStatus() async -> TaskNotificationAuthorization
    func requestAuthorization() async throws
    func add(_ content: TaskNotificationContent) async throws
}

/// The only permission request is the explicit requestAuthorization() method.
/// A fake backend keeps tests away from system permission and notification UI.
@MainActor
final class TaskNotificationService {
    static let statusBody = "任务状态有更新，点击返回查看。"
    static let maximumTitleCharacters = 80
    private let backend: any TaskNotificationBackend
    private let onOpenTask: (UUID) -> Void

    init(onOpenTask: @escaping (UUID) -> Void, backend: (any TaskNotificationBackend)? = nil) {
        self.onOpenTask = onOpenTask
        self.backend = backend ?? SystemTaskNotificationBackend()
        self.backend.responseHandler = { [weak self] response in self?.handle(response) }
    }

    func authorizationStatus() async -> TaskNotificationAuthorization { await backend.authorizationStatus() }

    func requestAuthorization() async throws -> TaskNotificationAuthorization {
        try await backend.requestAuthorization()
        return await backend.authorizationStatus()
    }

    func notify(taskID: UUID, title: String) async -> TaskNotificationDelivery {
        let status = await backend.authorizationStatus()
        guard status.canDeliver else { return .notAuthorized(status) }
        let content = TaskNotificationContent(identifier: taskNotificationIdentifierPrefix + taskID.uuidString,
            categoryIdentifier: taskNotificationCategory, taskID: taskID, title: Self.cleanTitle(title), body: L10n.text(Self.statusBody))
        do { try await backend.add(content); return .sent }
        catch { return .failed(error.localizedDescription) }
    }

    static func cleanTitle(_ title: String) -> String {
        var scalars = String.UnicodeScalarView()
        // Bound input before normalization as well as final grapheme length.
        for scalar in title.unicodeScalars.prefix(1024) {
            let value = scalar.value
            if (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value) || value == 0x200E || value == 0x200F { continue }
            if value == 0x200C || value == 0x200D { scalars.append(scalar); continue }
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                scalars.append(" ")
            } else if !CharacterSet.illegalCharacters.contains(scalar) { scalars.append(scalar) }
        }
        let normalized = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.isEmpty ? L10n.text("OmniVibe 任务") : String(normalized.prefix(maximumTitleCharacters))
    }

    private func handle(_ response: TaskNotificationResponse) {
        guard response.action == .open, response.categoryIdentifier == taskNotificationCategory,
              let value = response.taskID, let taskID = UUID(uuidString: value),
              response.identifier == taskNotificationIdentifierPrefix + taskID.uuidString else { return }
        onOpenTask(taskID)
    }
}

/// A strong service-owned delegate is installed once. Obtaining the center and
/// assigning its delegate neither requests consent nor schedules a notification.
@MainActor
private final class SystemTaskNotificationBackend: NSObject, TaskNotificationBackend, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    var responseHandler: ((TaskNotificationResponse) -> Void)?

    override init() {
        center = UNUserNotificationCenter.current()
        super.init()
        center.delegate = self
    }

    func authorizationStatus() async -> TaskNotificationAuthorization {
        let settings = await center.notificationSettings()
        return TaskNotificationAuthorization(systemRawValue: settings.authorizationStatus.rawValue)
    }

    func requestAuthorization() async throws {
        // Theme audio already supplies optional completion sounds separately.
        _ = try await center.requestAuthorization(options: [.alert])
    }

    func add(_ payload: TaskNotificationContent) async throws {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.categoryIdentifier = payload.categoryIdentifier
        content.userInfo = [taskNotificationUUIDKey: payload.taskID.uuidString]
        let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: nil)
        try await center.add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let action: TaskNotificationResponse.Action
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: action = .open
        case UNNotificationDismissActionIdentifier: action = .dismiss
        default: action = .other
        }
        let payload = TaskNotificationResponse(identifier: response.notification.request.identifier,
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            taskID: response.notification.request.content.userInfo[taskNotificationUUIDKey] as? String, action: action)
        completionHandler()
        Task { @MainActor [weak self] in self?.responseHandler?(payload) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        guard content.categoryIdentifier == taskNotificationCategory,
              let value = content.userInfo[taskNotificationUUIDKey] as? String, let taskID = UUID(uuidString: value),
              notification.request.identifier == taskNotificationIdentifierPrefix + taskID.uuidString else {
            completionHandler([])
            return
        }
        completionHandler([.banner, .list])
    }
}
