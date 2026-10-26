import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class TaskLaunchTests: XCTestCase {
    private func fixture() throws -> (URL, TaskLaunchConfiguration) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeLaunchTests-\(UUID())")
        let project = root.appendingPathComponent("project ' $(touch unwanted)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let binary = root.appendingPathComponent("cli ' $ literal")
        try Data("not executed by tests".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, TaskLaunchConfiguration(mode: .codex, projectDirectory: project.path, executablePath: binary.path))
    }

    func testConfigurationAcceptsLiteralMetacharactersButRejectsRelativeControlAndNonUUIDResumeValues() throws {
        let (_, configuration) = try fixture()
        XCTAssertEqual(try configuration.validated(), configuration)
        for invalid in ["../project", "/tmp/new\ncommand", ""] {
            var changed = configuration; changed.projectDirectory = invalid
            XCTAssertThrowsError(try changed.validated(checkFiles: false))
        }
        var changed = configuration; changed.resumeSessionID = "--last"
        XCTAssertThrowsError(try changed.validated())
        changed.resumeSessionID = UUID().uuidString
        XCTAssertNoThrow(try changed.validated())
        changed.mode = .terminal
        XCTAssertThrowsError(try changed.validated())
    }

    func testSavedRecipesKeepExactTaskIdentityAndSessionOnlyChangesTheMatchingProvider() throws {
        let (root, configuration) = try fixture()
        let store = TaskLaunchRecordStore(root: root), task = UUID(), replacement = UUID(), session = UUID().uuidString
        try store.save(configuration, for: task)
        try store.updateSession(taskID: task, provider: "claude", sessionID: session)
        XCTAssertEqual(try store.record(for: task)?.configuration.resumeSessionID, "")
        try store.updateSession(taskID: task, provider: "codex", sessionID: session)
        try store.transfer(from: task, to: replacement)
        XCTAssertEqual(try store.record(for: replacement)?.configuration.resumeSessionID, session)
        XCTAssertNotNil(try store.record(for: task))
        try store.remove(replacement)
        XCTAssertNil(try store.record(for: replacement))
        XCTAssertNotNil(try store.record(for: task))
    }

    func testExecutableResolutionUsesExplicitAbsolutePATHBeforeConventionalDirectoriesWithoutRunningAnything() throws {
        let (root, _) = try fixture()
        let custom = root.appendingPathComponent("custom-bin"), conventional = root.appendingPathComponent(".local/bin")
        for directory in [custom, conventional] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("codex")
            try Data("not executed".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        XCTAssertEqual(TaskLaunchConfiguration.defaultExecutable(for: .codex, home: root,
            environment: ["PATH": "relative:" + custom.path]), custom.appendingPathComponent("codex").path)
        XCTAssertEqual(TaskLaunchConfiguration.defaultExecutable(for: .codex, home: root,
            environment: ["PATH": "relative"]), conventional.appendingPathComponent("codex").path)
        XCTAssertEqual(TaskLaunchConfiguration.defaultExecutable(for: .terminal, home: root,
            environment: ["PATH": custom.path]), "/bin/zsh")
    }

    func testDamagedRecipeFileIsNotReplacedByAnEmptySave() throws {
        let (root, configuration) = try fixture()
        let store = TaskLaunchRecordStore(root: root)
        let bytes = Data("unreadable existing launch data".utf8)
        try bytes.write(to: store.fileURL)
        XCTAssertThrowsError(try store.save(configuration, for: UUID()))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
    }

    @MainActor
    func testTerminalDispatchContainsOnlyQuotedBridgeArgumentsAndNoProjectOrAgentCommand() {
        let command = TaskLaunchService.terminalCommand(executable: URL(fileURLWithPath: "/tmp/bridge ' $(touch no)"),
            root: URL(fileURLWithPath: "/tmp/root ' $(touch no)"), token: UUID())
        XCTAssertTrue(command.contains("'\\''"))
        XCTAssertFalse(command.contains("--dangerously"))
        XCTAssertTrue(command.contains("'launch-agent' '--root'"))
        XCTAssertFalse(AppleScriptTaskTerminalLaunchBackend.script.contains("contents of targetTab"))
        XCTAssertTrue(AppleScriptTaskTerminalLaunchBackend.script.contains("if busy of targetTab then error"))
        XCTAssertTrue(AppleScriptTaskTerminalLaunchBackend.validTTY("/dev/ttys012"))
        XCTAssertFalse(AppleScriptTaskTerminalLaunchBackend.validTTY("/dev/ttys012\ncommand"))
    }

    @MainActor
    func testOpenCreatesOnlyEmptyWindowAndStartWaitsForPersistedExactBinding() async throws {
        let (root, configuration) = try fixture()
        let fake = FakeTaskTerminalLaunchBackend()
        let windows = FakeTaskLaunchWindows(window: fake.window)
        let service = TaskLaunchService(root: root, executableURL: URL(fileURLWithPath: "/tmp/OmniVibe"), backend: fake,
            serverWindows: { fake.serverWindows })
        let workspace = WorkspaceState(), taskID = workspace.slots[0].id
        try WorkspaceStore(root: root).save(workspace)
        let opened = try await service.openWindow(configuration: configuration, taskID: taskID, windows: windows)
        XCTAssertEqual(opened.window.id, fake.window.id)
        XCTAssertEqual(fake.commandCount, 0)
        do { _ = try await service.start(opened); XCTFail("Expected no start without binding") }
        catch TaskLaunchError.bindingNotSaved {}
        catch { XCTFail("Unexpected error \(error)") }
        XCTAssertEqual(fake.commandCount, 0)
        var bound = workspace
        try bound.bind(opened.window, to: 1)
        try WorkspaceStore(root: root).save(bound)
        let receipt = try await service.start(opened)
        XCTAssertEqual(receipt.taskID, taskID)
        XCTAssertEqual(fake.commandCount, 1)
        XCTAssertEqual(try TaskLaunchRecordStore(root: root).record(for: taskID)?.configuration, configuration)
        let request = try JSONDecoder().decode(TaskLaunchExecutionRequest.self,
            from: Data(contentsOf: TaskLaunchExecutionRequest.url(root: root, token: opened.id)))
        XCTAssertEqual(request.configuration, configuration)
        XCTAssertEqual(request.terminal.tty, fake.target.tty)
        XCTAssertEqual(request.windowID, fake.window.id)
        do { _ = try await service.start(opened); XCTFail("Expected one-use dispatch") }
        catch TaskLaunchError.expiredWindow {}
        catch { XCTFail("Unexpected error \(error)") }
        XCTAssertEqual(fake.commandCount, 1)
    }

    @MainActor
    func testConcurrentNewWindowsAreNotGuessedByTitleAndNoCommandIsSent() async throws {
        let (root, configuration) = try fixture()
        let fake = FakeTaskTerminalLaunchBackend(); fake.concurrentWindow = true
        let service = TaskLaunchService(root: root, backend: fake, serverWindows: { fake.serverWindows })
        do {
            _ = try await service.openWindow(configuration: configuration, taskID: UUID(), windows: FakeTaskLaunchWindows(window: fake.window))
            XCTFail("Expected ambiguous creation rejection")
        } catch TaskLaunchError.windowNotIdentified {}
        catch { XCTFail("Unexpected error \(error)") }
        XCTAssertEqual(fake.commandCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("task-launches.json").path))
    }

    func testExecutionRequestRejectsWrongTokenTTYAndExpiredPlansBeforeAnyProgramStarts() throws {
        let (root, configuration) = try fixture()
        let fake = FakeTaskTerminalLaunchBackend()
        let request = TaskLaunchExecutionRequest(token: UUID(), taskID: UUID(), configuration: configuration,
            windowID: fake.window.id, windowNumber: 202, platformSessionID: "test-login", terminal: fake.target,
            expiresAt: Date().addingTimeInterval(60))
        XCTAssertThrowsError(try request.validate(root: root, token: UUID(), tty: fake.target.tty))
        XCTAssertThrowsError(try request.validate(root: root, token: request.token, tty: "/dev/ttys099"))
        XCTAssertThrowsError(try request.validate(root: root, token: request.token, tty: fake.target.tty, now: Date().addingTimeInterval(200)))
        XCTAssertNil(TaskLaunchCommandLine.runIfRequested(arguments: ["OmniVibe", "status"]))
        XCTAssertEqual(TaskLaunchCommandLine.runIfRequested(arguments: ["OmniVibe", "launch-agent"]), 1)
    }

    func testExecutionRequiresTheOriginalWindowServerTokenAndLoginSessionEvenIfTTYIsReused() throws {
        let (_, configuration) = try fixture()
        let fake = FakeTaskTerminalLaunchBackend()
        let request = TaskLaunchExecutionRequest(token: UUID(), taskID: UUID(), configuration: configuration,
            windowID: fake.window.id, windowNumber: 202, platformSessionID: "test-login", terminal: fake.target,
            expiresAt: Date().addingTimeInterval(60))
        let frame = WindowFrame(x: 80, y: 90, width: 900, height: 600)
        let original = WindowServerCandidate(number: 202, processID: fake.session.processID,
            title: "A renamed window", frame: frame, layer: 0)
        let replacement = WindowServerCandidate(number: 203, processID: fake.session.processID,
            title: "A renamed window", frame: frame, layer: 0)
        XCTAssertTrue(request.matchesCurrentWindow(sessionID: "test-login", serverWindows: [original, replacement]))
        XCTAssertFalse(request.matchesCurrentWindow(sessionID: "another-login", serverWindows: [original]))
        XCTAssertFalse(request.matchesCurrentWindow(sessionID: nil, serverWindows: [original]))
        XCTAssertFalse(request.matchesCurrentWindow(sessionID: "test-login", serverWindows: nil))
        XCTAssertFalse(request.matchesCurrentWindow(sessionID: "test-login", serverWindows: []))
        XCTAssertFalse(request.matchesCurrentWindow(sessionID: "test-login", serverWindows: [replacement]))
    }

    func testExecutionRejectsReusedWindowNumbersWithOtherOwnersLayersOrAmbiguousMetadata() throws {
        let (_, configuration) = try fixture()
        let fake = FakeTaskTerminalLaunchBackend()
        let request = TaskLaunchExecutionRequest(token: UUID(), taskID: UUID(), configuration: configuration,
            windowID: fake.window.id, windowNumber: 202, platformSessionID: "test-login", terminal: fake.target,
            expiresAt: Date().addingTimeInterval(60))
        let frame = WindowFrame(x: 0, y: 0, width: 600, height: 400)
        func candidate(_ pid: Int32, layer: Int) -> WindowServerCandidate {
            WindowServerCandidate(number: 202, processID: pid, title: nil, frame: frame, layer: layer)
        }
        XCTAssertFalse(request.matchesCurrentWindow(sessionID: "test-login", serverWindows: [candidate(999, layer: 0)]))
        XCTAssertFalse(request.matchesCurrentWindow(sessionID: "test-login", serverWindows: [candidate(fake.session.processID, layer: 1)]))
        let original = candidate(fake.session.processID, layer: 0)
        XCTAssertFalse(request.matchesCurrentWindow(sessionID: "test-login", serverWindows: [original, original]))
    }
}

private final class FakeTaskTerminalLaunchBackend: TaskTerminalLaunchBackend, @unchecked Sendable {
    let session = TaskTerminalSession(processID: 12345, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
    private let lock = NSLock()
    private var opened = false
    private var commands: [String] = []
    var concurrentWindow = false
    var target: TaskTerminalTarget { TaskTerminalTarget(session: session, windowID: 202, tty: "/dev/ttys042") }
    lazy var window = WindowIdentity(processID: session.processID, processStartedAt: session.startedAt,
        bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", title: "An empty shell",
        platformWindowNumber: 202, platformSessionID: "test-login")
    var commandCount: Int { lock.lock(); defer { lock.unlock() }; return commands.count }
    var serverWindows: [WindowServerCandidate] {
        lock.lock(); defer { lock.unlock() }
        let frame = WindowFrame(x: 20, y: 30, width: 600, height: 400)
        var values = [WindowServerCandidate(number: 201, processID: session.processID, title: nil, frame: frame, layer: 0)]
        if opened {
            values.append(WindowServerCandidate(number: 202, processID: session.processID, title: nil, frame: frame, layer: 0))
            if concurrentWindow { values.append(WindowServerCandidate(number: 203, processID: session.processID, title: nil, frame: frame, layer: 0)) }
        }
        return values
    }
    func currentSession() throws -> TaskTerminalSession? { session }
    func openEmptyWindow() throws -> TaskTerminalTarget { lock.lock(); opened = true; lock.unlock(); return target }
    func send(command: String, to target: TaskTerminalTarget) throws { lock.lock(); commands.append(command); lock.unlock() }
}

@MainActor
private final class FakeTaskLaunchWindows: WindowControlling {
    let window: WindowIdentity
    init(window: WindowIdentity) { self.window = window }
    var isTrusted: Bool { true }
    func requestAccess() {}
    func openAccessibilitySettings() {}
    func windows() -> [WindowIdentity] { [window] }
    func isAvailable(_ window: WindowIdentity) -> Bool { window.id == self.window.id }
    func isDefinitelyClosed(_ window: WindowIdentity) -> Bool { false }
    func currentWindow() -> WindowIdentity? { window }
    func activate(_ window: WindowIdentity) throws {}
    func confirmActivation(_ window: WindowIdentity) async throws {}
    func capturePlacement(_ window: WindowIdentity) throws -> WindowPlacement { WindowPlacement(frame: workArea(for: window), minimized: false) }
    func restore(_ window: WindowIdentity, to placement: WindowPlacement) throws {}
    func setFrame(_ target: WindowFrame, for window: WindowIdentity) throws {}
    func workArea(for window: WindowIdentity?) -> WindowFrame { WindowFrame(x: 0, y: 0, width: 900, height: 600) }
}
