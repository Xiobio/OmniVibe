import Foundation
import OmniVibeCore

enum AgentProvider: String, CaseIterable, Identifiable {
    case codex, claude
    var id: String { rawValue }
    var label: String { self == .codex ? "Codex" : "Claude Code" }
}

struct TrackedSessionPlan: Encodable {
    let executable: String
    let arguments: [String]
    let workingDirectory: String?
}

enum AgentIntegration {
    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func hookCommand(executable: URL, taskID: UUID, provider: AgentProvider, root: URL) -> String {
        [executable.path, "hook", "--provider", provider.rawValue, "--task", taskID.uuidString,
         "--root", root.path].map(quote).joined(separator: " ")
    }

    static func connectionCommand(executable: URL, taskID: UUID, provider: AgentProvider,
                                  root: URL, directory: String = "", resume: String = "") -> String {
        var args = [executable.path, "track", "--provider", provider.rawValue,
                    "--task", taskID.uuidString, "--root", root.path]
        if !directory.isEmpty { args += ["--cwd", directory] }
        if !resume.isEmpty { args += ["--resume", resume] }
        args.append("--")
        return args.map(quote).joined(separator: " ")
    }

    static func plan(executable: URL, taskID: UUID, provider: AgentProvider, root: URL,
                     directory: String? = nil, resume: String? = nil, arguments: [String] = [],
                     existingCodexHooks: [String: Any] = [:]) throws -> TrackedSessionPlan {
        if provider == .codex { _ = try codexReadArguments(forwarded: arguments) }
        let command = hookCommand(executable: executable, taskID: taskID, provider: provider, root: root)
        let events = provider == .codex
            ? ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "Interrupt", "SessionEnd"]
            : ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Notification", "Stop", "StopFailure", "Elicitation", "ElicitationResult", "SessionEnd"]
        var agentArguments: [String]
        if provider == .claude {
            var hooks: [String: Any] = [:]
            for event in events {
                hooks[event] = [["hooks": [["type": "command", "command": command, "timeout": event == "SessionEnd" ? 2 : 3]]]]
            }
            let data = try JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.sortedKeys, .withoutEscapingSlashes])
            agentArguments = [provider.rawValue, "--settings", String(decoding: data, as: UTF8.self)]
        } else {
            agentArguments = [provider.rawValue, "--no-daemon"]
            for event in events {
                let timeout = event == "SessionEnd" || event == "Interrupt" ? 2 : 3
                var existing: [Any] = []
                if let value = existingCodexHooks[event] {
                    guard let list = value as? [Any] else {
                        throw IntegrationError("无法合并 Codex 的 \(event) hooks；请检查原 CLI 配置。")
                    }
                    existing = list
                }
                existing.append(["hooks": [["type": "command", "command": command, "timeout": timeout]]])
                agentArguments += ["-c", "hooks.\(event)=\(try tomlValue(existing))"]
            }
        }
        if let resume, !resume.isEmpty {
            guard resume.first != "-", resume.count <= 160,
                  resume.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).contains($0) }) else {
                throw IntegrationError("会话 ID 无效，请使用 CLI 提供的确切会话 ID。")
            }
            agentArguments += provider == .codex ? ["resume", resume] : ["--resume", resume]
        }
        agentArguments += arguments
        return TrackedSessionPlan(executable: "/usr/bin/env", arguments: agentArguments, workingDirectory: directory)
    }

    /// Effective Codex configuration comes from its own read-only config API.
    /// Keep every existing hook entry before appending this observer. Optional
    /// null dictionary fields are omitted because TOML has no null value.
    static func tomlValue(_ value: Any) throws -> String {
        if let dictionary = value as? [String: Any] {
            let fields = try dictionary.keys.sorted().compactMap { key -> String? in
                guard let field = dictionary[key], !(field is NSNull) else { return nil }
                return try tomlValue(key) + "=" + tomlValue(field)
            }
            return "{" + fields.joined(separator: ",") + "}"
        }
        if let array = value as? [Any] { return "[" + (try array.map(tomlValue)).joined(separator: ",") + "]" }
        guard value is String || value is NSNumber,
              JSONSerialization.isValidJSONObject([value]) else {
            throw IntegrationError("Codex hooks 包含无法安全合并的配置值，本次未启动会话。")
        }
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Keep CLI config overrides in the read-only inspection too. Profiles,
    /// managed worktrees, and remote servers have different configuration roots
    /// and are intentionally rejected until those roots can be read faithfully.
    static func codexReadArguments(forwarded: [String]) throws -> [String] {
        var result = ["codex"]
        var index = 0
        while index < forwarded.count {
            let token = forwarded[index]
            if token == "--" { break }
            let unsupported = ["-p", "--profile", "-C", "--cd", "--worktree", "--remote", "--remote-auth-token-env"]
            if unsupported.contains(token) || token.hasPrefix("-p") && !token.hasPrefix("--") ||
                token.hasPrefix("-C") || unsupported.contains(where: { token.hasPrefix($0 + "=") }) {
                throw IntegrationError("当前状态连接不支持 Codex 的 profile、worktree 或 remote 选项；项目目录请通过 OmniVibe --cwd 指定。")
            }
            if ["-c", "--config", "--enable", "--disable"].contains(token) {
                guard index + 1 < forwarded.count else { throw IntegrationError("Codex 配置参数缺少值。") }
                result += [token, forwarded[index + 1]]
                index += 2
                continue
            }
            if token.hasPrefix("--config=") || token.hasPrefix("--enable=") || token.hasPrefix("--disable=") ||
                token.hasPrefix("-c") && !token.hasPrefix("--") { result.append(token) }
            index += 1
        }
        return result + ["app-server", "--listen", "stdio://"]
    }
}

struct IntegrationError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// The observer path never initializes NSApplication, prints model instructions,
/// changes CLI approval settings, or starts a new model turn.
enum AgentCommandLine {
    static func runIfRequested(arguments: [String]) -> Int32? {
        guard arguments.count > 1, ["hook", "status", "track", "plan"].contains(arguments[1]) else { return nil }
        let command = arguments[1]
        do {
            let options = try Options(Array(arguments.dropFirst(2)))
            let root = options.values["--root"].map { URL(fileURLWithPath: $0) } ?? WorkspaceStore().root
            if command == "hook" {
                guard let text = options.values["--task"], let id = UUID(uuidString: text),
                      let provider = options.values["--provider"] else { return 0 }
                var payload = Data()
                while payload.count <= 1_048_576 {
                    let chunk = FileHandle.standardInput.readData(ofLength: 32_768)
                    if chunk.isEmpty { break }
                    payload.append(chunk)
                }
                _ = try publishHook(provider: provider, taskID: id, payload: payload, root: root)
                return 0
            }
            let store = WorkspaceStore(root: root)
            let workspace = try store.load().state
            if command == "status" {
                guard let number = options.values["--slot"].flatMap(Int.init),
                      let slot = workspace.slots.first(where: { $0.number == number && $0.window != nil }),
                      let rawState = options.values["--state"], let state = AgentState(rawValue: rawState.lowercased()) else {
                    throw IntegrationError("用法：status --slot 1 --state running|waiting|ready|error|unknown [--message 文本]")
                }
                let event = AgentStatusEvent(taskID: slot.id, state: state,
                    message: String((options.values["--message"] ?? "手动标记").prefix(512)),
                    provider: "manual", eventName: "Manual")
                _ = try StatusEventInbox.publish(event, root: root)
                return 0
            }
            guard let text = options.values["--task"], let id = UUID(uuidString: text),
                  workspace.slots.contains(where: { $0.id == id && $0.window != nil }),
                  let rawProvider = options.values["--provider"], let provider = AgentProvider(rawValue: rawProvider) else {
                throw IntegrationError("任务已解除或重新绑定，请从 OmniVibe 重新复制连接命令。")
            }
            let existingHooks = provider == .codex ? try CodexHookConfiguration.read(directory: options.values["--cwd"],
                arguments: AgentIntegration.codexReadArguments(forwarded: options.forwarded)) : [:]
            let plan = try AgentIntegration.plan(executable: URL(fileURLWithPath: arguments[0]).standardizedFileURL,
                taskID: id, provider: provider, root: root, directory: options.values["--cwd"],
                resume: options.values["--resume"], arguments: options.forwarded, existingCodexHooks: existingHooks)
            if command == "plan" {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(plan))
                return 0
            }
            if let directory = plan.workingDirectory {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw IntegrationError("项目目录不存在。")
                }
            }
            if provider == .codex {
                fputs("OmniVibe：首次使用请在 Codex /hooks 中查看并信任本地状态观察器。\n", stderr)
            }
            if let mode = TaskLaunchMode(rawValue: provider.rawValue) {
                let executable = TaskLaunchConfiguration.defaultExecutable(for: mode)
                if !executable.isEmpty {
                    let configuration = TaskLaunchConfiguration(mode: mode,
                        projectDirectory: plan.workingDirectory ?? FileManager.default.currentDirectoryPath,
                        executablePath: executable, resumeSessionID: options.values["--resume"] ?? "")
                    do { try TaskLaunchRecordStore(root: root).save(configuration, for: id) }
                    catch { fputs("OmniVibe: launch configuration was not saved: \(error.localizedDescription)\n", stderr) }
                }
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: plan.executable)
            process.arguments = plan.arguments
            process.currentDirectoryURL = plan.workingDirectory.map { URL(fileURLWithPath: $0) }
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            if command == "hook" { return 0 }
            fputs("OmniVibe：\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    /// Hook processes only enqueue observations. The coordinator decides
    /// whether their session/time identity is current before saving a recipe.
    @discardableResult
    static func publishHook(provider: String, taskID: UUID, payload: Data, root: URL) throws -> URL? {
        guard payload.count <= 1_048_576,
              let event = HookBridge.parse(provider: provider, taskID: taskID, payload: payload) else { return nil }
        return try StatusEventInbox.publish(event, root: root)
    }

    private struct Options {
        var values: [String: String] = [:]
        var forwarded: [String] = []
        init(_ arguments: [String]) throws {
            let known = Set(["--root", "--task", "--provider", "--slot", "--state", "--message", "--cwd", "--resume"])
            var index = 0
            while index < arguments.count {
                let key = arguments[index]
                if key == "--" { forwarded = Array(arguments.dropFirst(index + 1)); break }
                guard known.contains(key), index + 1 < arguments.count, values[key] == nil else {
                    throw IntegrationError("参数无效：\(key)")
                }
                values[key] = arguments[index + 1]
                index += 2
            }
        }
    }
}
