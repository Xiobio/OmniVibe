import Foundation
import XCTest
@testable import OmniVibeMac

final class TaskNotificationServiceTests: XCTestCase {
    @MainActor
    func testInitializationDoesNotReadRequestOrSendAnything() {
        let backend = FakeTaskNotificationBackend()
        let service = TaskNotificationService(onOpenTask: { _ in }, backend: backend)
        XCTAssertEqual(backend.statusReads, 0)
        XCTAssertEqual(backend.authorizationRequests, 0)
        XCTAssertTrue(backend.contents.isEmpty)
        withExtendedLifetime(service) {}
    }

    @MainActor
    func testStatusReadsNeverRequestAuthorizationAndExplicitRequestReturnsSystemState() async throws {
        let backend = FakeTaskNotificationBackend()
        let service = TaskNotificationService(onOpenTask: { _ in }, backend: backend)
        let initial = await service.authorizationStatus()
        XCTAssertEqual(initial, .notDetermined)
        XCTAssertEqual(backend.authorizationRequests, 0)
        backend.requestResult = .authorized
        let requested = try await service.requestAuthorization()
        XCTAssertEqual(requested, .authorized)
        XCTAssertEqual(backend.authorizationRequests, 1)
        XCTAssertEqual(backend.statusReads, 2)
        XCTAssertTrue(backend.contents.isEmpty)
    }

    @MainActor
    func testUnaskedDeniedAndUnknownStatesDoNotSendOrAskForPermission() async {
        for status in [TaskNotificationAuthorization.notDetermined, .denied, .unknown] {
            let backend = FakeTaskNotificationBackend(status: status)
            let service = TaskNotificationService(onOpenTask: { _ in }, backend: backend)
            let result = await service.notify(taskID: UUID(), title: "Task")
            XCTAssertEqual(result, .notAuthorized(status))
            XCTAssertEqual(backend.authorizationRequests, 0)
            XCTAssertTrue(backend.contents.isEmpty)
        }
    }

    @MainActor
    func testAllDeliverableStatesQueueOnlyTaskTitleFixedBodyAndUUID() async throws {
        for status in [TaskNotificationAuthorization.authorized, .provisional, .ephemeral] {
            let backend = FakeTaskNotificationBackend(status: status)
            let service = TaskNotificationService(onOpenTask: { _ in }, backend: backend)
            let taskID = UUID()
            let result = await service.notify(taskID: taskID, title: "API task")
            XCTAssertEqual(result, .sent)
            XCTAssertEqual(backend.authorizationRequests, 0)
            let payload = try XCTUnwrap(backend.contents.first)
            XCTAssertEqual(payload.taskID, taskID)
            XCTAssertEqual(payload.title, "API task")
            XCTAssertEqual(payload.body, TaskNotificationService.statusBody)
            XCTAssertEqual(payload.identifier, "OmniVibe.task." + taskID.uuidString)
            XCTAssertEqual(backend.contents.count, 1)
        }
    }

    @MainActor
    func testTitleCleanupBoundsLengthRemovesControlsAndKeepsUnicodeGraphemes() async throws {
        let backend = FakeTaskNotificationBackend(status: .authorized)
        let service = TaskNotificationService(onOpenTask: { _ in }, backend: backend)
        _ = await service.notify(taskID: UUID(), title: " \nAPI\t\u{202E} task\0 ")
        XCTAssertEqual(backend.contents.last?.title, "API task")
        let emoji = "👨‍👩‍👧‍👦"
        _ = await service.notify(taskID: UUID(), title: String(repeating: emoji, count: 120))
        let title = try XCTUnwrap(backend.contents.last?.title)
        XCTAssertEqual(title.count, TaskNotificationService.maximumTitleCharacters)
        XCTAssertEqual(title, String(repeating: emoji, count: 80))
        _ = await service.notify(taskID: UUID(), title: " \n\t\0 ")
        XCTAssertEqual(backend.contents.last?.title, "OmniVibe 任务")
    }

    @MainActor
    func testRequestAndAddFailuresAreReportedWithoutImplicitRetryOrAuthorization() async {
        let backend = FakeTaskNotificationBackend(status: .authorized)
        let service = TaskNotificationService(onOpenTask: { _ in }, backend: backend)
        backend.requestError = NotificationFixtureError.failed
        do { _ = try await service.requestAuthorization(); XCTFail("The explicit permission error must reach the caller.") }
        catch { XCTAssertEqual(error as? NotificationFixtureError, .failed) }
        backend.addError = NotificationFixtureError.failed
        let result = await service.notify(taskID: UUID(), title: "Task")
        XCTAssertEqual(result, .failed(NotificationFixtureError.failed.localizedDescription))
        XCTAssertEqual(backend.authorizationRequests, 1)
        XCTAssertEqual(backend.contents.count, 1)
    }

    @MainActor
    func testOnlyValidDefaultClickRoutesByUUID() {
        let backend = FakeTaskNotificationBackend()
        var opened: [UUID] = []
        let service = TaskNotificationService(onOpenTask: { opened.append($0) }, backend: backend)
        let taskID = UUID()
        let identifier = "OmniVibe.task." + taskID.uuidString
        let category = "com.xiobio.omnivibe.task-status"
        for action in [TaskNotificationResponse.Action.dismiss, .other] {
            backend.responseHandler?(.init(identifier: identifier, categoryIdentifier: category, taskID: taskID.uuidString, action: action))
        }
        backend.responseHandler?(.init(identifier: identifier, categoryIdentifier: category, taskID: "old slot 4", action: .open))
        backend.responseHandler?(.init(identifier: "other-request", categoryIdentifier: category, taskID: taskID.uuidString, action: .open))
        backend.responseHandler?(.init(identifier: identifier, categoryIdentifier: "other-category", taskID: taskID.uuidString, action: .open))
        XCTAssertTrue(opened.isEmpty)
        backend.responseHandler?(.init(identifier: identifier, categoryIdentifier: category, taskID: taskID.uuidString, action: .open))
        XCTAssertEqual(opened, [taskID])
        withExtendedLifetime(service) {}
    }

    @MainActor
    func testAuthorizationLabelsAndDeliverabilityIncludeFutureSafeUnknownState() {
        let states: [TaskNotificationAuthorization] = [.notDetermined, .denied, .authorized, .provisional, .ephemeral]
        for (raw, expected) in states.enumerated() {
            let status = TaskNotificationAuthorization(systemRawValue: raw)
            XCTAssertEqual(status, expected)
            XCTAssertFalse(status.label.isEmpty)
            XCTAssertEqual(status.canDeliver, [.authorized, .provisional, .ephemeral].contains(status))
        }
        XCTAssertEqual(TaskNotificationAuthorization(systemRawValue: 99), .unknown)
        XCTAssertFalse(TaskNotificationAuthorization.unknown.canDeliver)
    }
}

private enum NotificationFixtureError: Error, Equatable { case failed }

@MainActor
private final class FakeTaskNotificationBackend: TaskNotificationBackend {
    var responseHandler: ((TaskNotificationResponse) -> Void)?
    var status: TaskNotificationAuthorization
    var requestResult: TaskNotificationAuthorization = .denied
    var requestError: Error?
    var addError: Error?
    var statusReads = 0
    var authorizationRequests = 0
    var contents: [TaskNotificationContent] = []

    init(status: TaskNotificationAuthorization = .notDetermined) { self.status = status }

    func authorizationStatus() async -> TaskNotificationAuthorization { statusReads += 1; return status }
    func requestAuthorization() async throws {
        authorizationRequests += 1
        if let requestError { throw requestError }
        status = requestResult
    }
    func add(_ content: TaskNotificationContent) async throws {
        contents.append(content)
        if let addError { throw addError }
    }
}
