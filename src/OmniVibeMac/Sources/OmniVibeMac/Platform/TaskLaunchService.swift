import AppKit
import Carbon
import Combine
import Darwin
import Foundation
import OmniVibeCore

struct TaskTerminalSession: Codable, Equatable, Sendable {
    let processID: Int32
    let startedAt: Date
}

struct TaskTerminalTarget: Codable, Equatable, Sendable {
    let session: TaskTerminalSession
    let windowID: Int
    let tty: String
}

struct TaskLaunchWindow: Identifiable, Sendable {
    let id: UUID
    let taskID: UUID
    let window: WindowIdentity
    let openedAt: Date
}

struct TaskLaunchReceipt: Sendable {
    let taskID: UUID
    let window: WindowIdentity
    let configuration: TaskLaunchConfiguration
}

protocol TaskTerminalLaunchBackend: AnyObject {
    func currentSession() throws -> TaskTerminalSession?
    func openEmptyWindow() throws -> TaskTerminalTarget
    func send(command: String, to target: TaskTerminalTarget) throws
}

@MainActor
protocol TaskLaunching: AnyObject {
    func openWindow(configuration: TaskLaunchConfiguration, taskID: UUID,
                    windows: any WindowControlling) async throws -> TaskLaunchWindow
    func start(_ opened: TaskLaunchWindow) async throws -> TaskLaunchReceipt
}

/// Explicit, two-stage launch: the caller must persist the exact new-window
/// binding between openWindow and start. No model runs before that checkpoint.
@MainActor
final class TaskLaunchService: ObservableObject, TaskLaunching {
    @Published private(set) var isBusy = false
    private let root: URL
    private let executableURL: URL
    private let worker: Worker
    private let serverWindows: () -> [WindowServerCandidate]?
    private var pending: [UUID: Pending] = [:]
    private static let queue = DispatchQueue(label: "io.github.xiobio.OmniVibe.task-launch", qos: .userInitiated)
    private struct Pending { let opened: TaskLaunchWindow; let target: TaskTerminalTarget; let configuration: TaskLaunchConfiguration }

    init(root: URL = WorkspaceStore().root, executableURL: URL? = nil, backend: TaskTerminalLaunchBackend? = nil,
         serverWindows: @escaping () -> [WindowServerCandidate]? = { WindowSessionIdentity.serverWindows() }) {
        self.root = root
        self.executableURL = executableURL ?? Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        worker = Worker(backend: backend ?? AppleScriptTaskTerminalLaunchBackend())
        self.serverWindows = serverWindows
    }

    func openWindow(configuration: TaskLaunchConfiguration, taskID: UUID,
                    windows: any WindowControlling) async throws -> TaskLaunchWindow {
        guard !isBusy else { throw TaskLaunchError.expiredWindow }
        _ = try configuration.validated()
        guard windows.isTrusted else { throw WindowServiceError.permission }
        guard let beforeServer = serverWindows() else { throw TaskLaunchError.terminalResponse }
        isBusy = true; defer { isBusy = false }
        let previous = try await perform { try $0.backend.currentSession() }
        let oldNumbers = Set(beforeServer.filter { $0.processID == previous?.processID && $0.layer == 0 }.map(\.number))
        let target = try await perform { try $0.backend.openEmptyWindow() }
        if let previous, previous != target.session { throw TaskLaunchError.terminalUnavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        repeat {
            let currentSession = try await perform { try $0.backend.currentSession() }
            guard currentSession == target.session else { throw TaskLaunchError.terminalUnavailable }
            let fresh = serverWindows()?.filter {
                $0.processID == target.session.processID && $0.layer == 0 && !oldNumbers.contains($0.number)
            } ?? []
            // Concurrently created windows are ambiguous. A title is never a
            // substitute for the observed unique WindowServer creation token.
            if fresh.count > 1 { throw TaskLaunchError.windowNotIdentified }
            if let number = fresh.first?.number {
                let candidates = windows.windows().filter {
                    $0.bundleIdentifier == "com.apple.Terminal" && $0.processID == target.session.processID &&
                    $0.processStartedAt == target.session.startedAt && $0.platformWindowNumber == number &&
                    $0.platformSessionID != nil
                }
                if candidates.count == 1, let window = candidates.first {
                    let opened = TaskLaunchWindow(id: UUID(), taskID: taskID, window: window, openedAt: Date())
                    pending = pending.filter { Date().timeIntervalSince($0.value.opened.openedAt) < 120 }
                    pending[opened.id] = Pending(opened: opened, target: target, configuration: configuration)
                    return opened
                }
            }
            try await Task.sleep(nanoseconds: 120_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw TaskLaunchError.windowNotIdentified
    }

    func start(_ opened: TaskLaunchWindow) async throws -> TaskLaunchReceipt {
        guard !isBusy, let value = pending[opened.id], value.opened.taskID == opened.taskID,
              value.opened.window == opened.window, Date().timeIntervalSince(opened.openedAt) >= 0,
              Date().timeIntervalSince(opened.openedAt) < 120 else { throw TaskLaunchError.expiredWindow }
        _ = try value.configuration.validated()
        let state = try WorkspaceStore(root: root).load().state
        guard state.slots.contains(where: { $0.id == opened.taskID && $0.window?.id == opened.window.id &&
            $0.window?.refersToSamePlatformWindow(as: opened.window) == true }) else { throw TaskLaunchError.bindingNotSaved }
        let session = try await perform { try $0.backend.currentSession() }
        guard session == value.target.session else { throw TaskLaunchError.terminalUnavailable }
        isBusy = true; defer { isBusy = false }
        let request = TaskLaunchExecutionRequest(token: opened.id, taskID: opened.taskID,
            configuration: value.configuration, windowID: opened.window.id,
            windowNumber: opened.window.platformWindowNumber!, platformSessionID: opened.window.platformSessionID!,
            terminal: value.target, expiresAt: Date().addingTimeInterval(120))
        try TaskLaunchRecordStore(root: root).save(value.configuration, for: opened.taskID)
        let planURL = try request.write(to: root)
        let command = Self.terminalCommand(executable: executableURL, root: root, token: opened.id)
        do {
            try await perform { try $0.backend.send(command: command, to: value.target) }
            pending.removeValue(forKey: opened.id)
            return TaskLaunchReceipt(taskID: opened.taskID, window: opened.window, configuration: value.configuration)
        } catch {
            // No arbitrary paths are removed: this is the one plan just created
            // for the failed dispatch. A claimed/running request is retained.
            if FileManager.default.fileExists(atPath: planURL.path) { try? FileManager.default.removeItem(at: planURL) }
            throw error
        }
    }

    static func terminalCommand(executable: URL, root: URL, token: UUID) -> String {
        [executable.path, "launch-agent", "--root", root.path, "--token", token.uuidString]
            .map(AgentIntegration.quote).joined(separator: " ")
    }

    private func perform<T: Sendable>(_ operation: @escaping (Worker) throws -> T) async throws -> T {
        let worker = worker
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { continuation.resume(with: Result { try autoreleasepool { try operation(worker) } }) }
        }
    }
    private final class Worker: @unchecked Sendable {
        let backend: TaskTerminalLaunchBackend
        init(backend: TaskTerminalLaunchBackend) { self.backend = backend }
    }
}

struct TaskLaunchExecutionRequest: Codable, Sendable {
    let token: UUID
    let taskID: UUID
    let configuration: TaskLaunchConfiguration
    let windowID: UUID
    let windowNumber: UInt32
    let platformSessionID: String
    let terminal: TaskTerminalTarget
    let expiresAt: Date

    static func url(root: URL, token: UUID, claimed: Bool = false) -> URL {
        root.appendingPathComponent("launch-inbox", isDirectory: true)
            .appendingPathComponent(token.uuidString + (claimed ? ".claimed" : ".json"))
    }

    func write(to root: URL) throws -> URL {
        let url = Self.url(root: root, token: token)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let bytes = try JSONEncoder().encode(self)
        guard bytes.count <= 65_536 else { throw TaskLaunchError.launchRequestInvalid }
        try bytes.write(to: url, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    func validate(root: URL, token expected: UUID, tty: String, now: Date = Date()) throws {
        _ = try configuration.validated()
        guard token == expected, expiresAt.timeIntervalSince(now) > 0, expiresAt.timeIntervalSince(now) <= 121,
              windowNumber != 0, !platformSessionID.isEmpty,
              terminal.tty == tty, terminal.session.processID > 0 else { throw TaskLaunchError.launchRequestInvalid }
        let state = try WorkspaceStore(root: root).load().state
        guard let task = state.slots.first(where: { $0.id == taskID }), let window = task.window,
              window.id == windowID, window.platformWindowNumber == windowNumber,
              window.platformSessionID == platformSessionID,
              window.processID == terminal.session.processID, window.processStartedAt == terminal.session.startedAt,
              window.bundleIdentifier == "com.apple.Terminal" else { throw TaskLaunchError.bindingNotSaved }
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").filter { !$0.isTerminated }
        guard applications.count == 1, applications[0].processIdentifier == terminal.session.processID,
              applications[0].launchDate == terminal.session.startedAt else { throw TaskLaunchError.wrongTerminal }
        guard matchesCurrentWindow(sessionID: WindowSessionIdentity.current(),
            serverWindows: WindowSessionIdentity.serverWindows()) else { throw TaskLaunchError.wrongTerminal }
    }

    /// A saved workspace and a matching TTY are insufficient: Terminal can
    /// close one window and reuse its TTY for a replacement. Require the same
    /// login session and still-existing original WindowServer owner/token too.
    /// This inspects public metadata only; missing metadata fails closed.
    func matchesCurrentWindow(sessionID: String?, serverWindows: [WindowServerCandidate]?) -> Bool {
        guard !platformSessionID.isEmpty, sessionID == platformSessionID,
              windowNumber != 0, terminal.session.processID > 0, let serverWindows else { return false }
        let matches = serverWindows.filter { $0.number == windowNumber }
        return matches.count == 1 && matches[0].processID == terminal.session.processID && matches[0].layer == 0
    }
}

/// This entry point runs inside the newly created, exact Terminal TTY. It only
/// consumes a short-lived, one-use argv plan after its binding was persisted.
/// It never initializes NSApplication or adds an initial prompt/model turn.
enum TaskLaunchCommandLine {
    static func runIfRequested(arguments: [String]) -> Int32? {
        guard arguments.count > 1, arguments[1] == "launch-agent" else { return nil }
        do {
            guard arguments.count == 6, arguments[2] == "--root", arguments[4] == "--token",
                  TaskLaunchConfiguration.validPath(arguments[3]), let token = UUID(uuidString: arguments[5]),
                  isatty(STDIN_FILENO) == 1, let ttyPointer = ttyname(STDIN_FILENO) else { throw TaskLaunchError.wrongTerminal }
            let root = URL(fileURLWithPath: arguments[3]).standardizedFileURL
            let url = TaskLaunchExecutionRequest.url(root: root, token: token)
            let claimed = TaskLaunchExecutionRequest.url(root: root, token: token, claimed: true)
            guard !FileManager.default.fileExists(atPath: claimed.path) else { throw TaskLaunchError.launchRequestUsed }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? Int.max) <= 65_536,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
                  ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 else {
                throw TaskLaunchError.launchRequestInvalid
            }
            let bytes = try Data(contentsOf: url)
            let request = try JSONDecoder().decode(TaskLaunchExecutionRequest.self, from: bytes)
            let tty = String(cString: ttyPointer)
            try request.validate(root: root, token: token, tty: tty)
            try FileManager.default.moveItem(at: url, to: claimed)
            defer { try? FileManager.default.removeItem(at: claimed) }
            guard try Data(contentsOf: claimed) == bytes else { throw TaskLaunchError.launchRequestInvalid }
            let configuration = request.configuration
            let plan: TrackedSessionPlan
            if let provider = configuration.mode.provider {
                var readArguments = try AgentIntegration.codexReadArguments(forwarded: [])
                readArguments[0] = configuration.executablePath
                let hooks = provider == .codex
                    ? try CodexHookConfiguration.read(directory: configuration.projectDirectory, arguments: readArguments) : [:]
                let tracked = try AgentIntegration.plan(executable: URL(fileURLWithPath: arguments[0]), taskID: request.taskID,
                    provider: provider, root: root, directory: configuration.projectDirectory,
                    resume: configuration.resumeSessionID.isEmpty ? nil : configuration.resumeSessionID, existingCodexHooks: hooks)
                var argv = tracked.arguments
                argv[0] = configuration.executablePath
                plan = TrackedSessionPlan(executable: tracked.executable, arguments: argv, workingDirectory: configuration.projectDirectory)
            } else {
                plan = TrackedSessionPlan(executable: configuration.executablePath, arguments: [], workingDirectory: configuration.projectDirectory)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: plan.executable); process.arguments = plan.arguments
            process.currentDirectoryURL = URL(fileURLWithPath: configuration.projectDirectory)
            process.standardInput = FileHandle.standardInput; process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            // Hook configuration inspection may take time. Recheck immediately
            // before execution rather than trusting the earlier claim-time read.
            try request.validate(root: root, token: token, tty: tty)
            try process.run(); process.waitUntilExit()
            return process.terminationStatus
        } catch {
            fputs("OmniVibe: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}

final class AppleScriptTaskTerminalLaunchBackend: TaskTerminalLaunchBackend {
    func currentSession() throws -> TaskTerminalSession? {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").filter { !$0.isTerminated }
        guard applications.count <= 1 else { throw TaskLaunchError.terminalAmbiguous }
        guard let application = applications.first else { return nil }
        guard let date = application.launchDate else { throw TaskLaunchError.terminalUnavailable }
        return TaskTerminalSession(processID: application.processIdentifier, startedAt: date)
    }

    func openEmptyWindow() throws -> TaskTerminalTarget {
        _ = try currentSession()
        let result = try execute(handler: "open_window", arguments: [])
        guard let session = try currentSession(), result.numberOfItems == 2,
              let window = result.atIndex(1), let tty = result.atIndex(2)?.stringValue,
              window.int32Value > 0, Self.validTTY(tty) else { throw TaskLaunchError.terminalResponse }
        return TaskTerminalTarget(session: session, windowID: Int(window.int32Value), tty: tty)
    }

    func send(command: String, to target: TaskTerminalTarget) throws {
        guard try currentSession() == target.session, target.windowID > 0, target.windowID <= Int(Int32.max),
              Self.validTTY(target.tty), command.utf8.count <= 32_768 else { throw TaskLaunchError.terminalUnavailable }
        _ = try execute(handler: "send_command", arguments: [NSAppleEventDescriptor(string: command),
            NSAppleEventDescriptor(int32: Int32(target.windowID)), NSAppleEventDescriptor(string: target.tty)])
        guard try currentSession() == target.session else { throw TaskLaunchError.terminalUnavailable }
    }

    static func validTTY(_ tty: String) -> Bool {
        tty.hasPrefix("/dev/tty") && tty.utf8.count <= 128 &&
            tty.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/_-.")).contains($0) }
    }

    private func execute(handler: String, arguments: [NSAppleEventDescriptor]) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: Self.script) else { throw TaskLaunchError.terminalResponse }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(keyASSubroutineName))
        let list = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() { list.insert(argument, at: index + 1) }
        event.setParam(list, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if code == -1743 { throw TaskLaunchError.automation("请在系统设置 → 隐私与安全性 → 自动化中允许 OmniVibe 控制 Terminal。") }
            if code == -2701 { throw TaskLaunchError.terminalBusy }
            throw TaskLaunchError.automation("系统错误 \(code)。窗口会保留，尚未确认启动结果。")
        }
        return result
    }

    static let script = """
    on open_window()
        tell application id "com.apple.Terminal"
            launch
            with timeout of 30 seconds
                set newTab to do script ""
                set newTTY to (tty of newTab) as text
                set foundIDs to {}
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        if ((tty of terminalTab) as text) is newTTY then set end of foundIDs to (id of terminalWindow) as integer
                    end repeat
                end repeat
                if (count of foundIDs) is not 1 then error number -2702
                return {item 1 of foundIDs, newTTY}
            end timeout
        end tell
    end open_window

    on send_command(commandText, targetWindowID, targetTTY)
        if application id "com.apple.Terminal" is not running then error number -600
        tell application id "com.apple.Terminal"
            with timeout of 30 seconds
                set matchedTabs to {}
                repeat with terminalWindow in windows
                    if ((id of terminalWindow) as integer) is targetWindowID then
                        repeat with terminalTab in tabs of terminalWindow
                            if ((tty of terminalTab) as text) is targetTTY then set end of matchedTabs to contents of terminalTab
                        end repeat
                    end if
                end repeat
                if (count of matchedTabs) is not 1 then error number -2702
                set targetTab to item 1 of matchedTabs
                repeat with idleAttempt from 1 to 30
                    if not (busy of targetTab) then exit repeat
                    delay 0.1
                end repeat
                if busy of targetTab then error number -2701
                do script commandText in targetTab
                return true
            end timeout
        end tell
    end send_command
    """
}
