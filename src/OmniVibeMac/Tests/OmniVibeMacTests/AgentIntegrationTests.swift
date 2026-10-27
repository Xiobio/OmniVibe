import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class AgentIntegrationTests: XCTestCase {
    private let taskID = UUID(uuidString: "A1234567-89AB-4CDE-8123-123456789ABC")!
    private let executable = URL(fileURLWithPath: "/tmp/Omni'Vibe 应用.app/Contents/MacOS/OmniVibeMac")
    private let root = URL(fileURLWithPath: "/tmp/状态 '任务' root/$(printf SHOULD_NOT_EXPAND)")
    private let directory = "/tmp/项目 '前端' workspace"

    func testShellQuotingPreservesLiteralCharactersWithoutExecutingThem() throws {
        let values = [
            "", "plain", "with spaces", "用户的中文路径", "O'Brien", "two'quotes'here",
            "$(printf SHOULD_NOT_EXPAND)", "`printf SHOULD_NOT_EXPAND`", "; printf SECOND_COMMAND",
            "a\\b", "a\"b", "$HOME", "first\nsecond", "tab\tvalue"
        ]
        for value in values {
            XCTAssertEqual(try shellWords(AgentIntegration.quote(value)), [value], "Failed literal: \(value.debugDescription)")
        }
    }

    func testConnectionCommandRoundTripsSpecialPathsAndExactSessionOptions() throws {
        for provider in AgentProvider.allCases {
            let command = AgentIntegration.connectionCommand(executable: executable, taskID: taskID,
                provider: provider, root: root, directory: directory, resume: "thr_exact_123")
            XCTAssertEqual(try shellWords(command), [
                executable.path, "track", "--provider", provider.rawValue, "--task", taskID.uuidString,
                "--root", root.path, "--cwd", directory, "--resume", "thr_exact_123", "--"
            ])
        }
    }

    func testConnectionCommandOmitsEmptyOptionsAndLeavesAnExplicitForwardingBoundary() throws {
        let command = AgentIntegration.connectionCommand(executable: executable, taskID: taskID,
            provider: .codex, root: root)
        let words = try shellWords(command)
        XCTAssertEqual(words, [executable.path, "track", "--provider", "codex", "--task", taskID.uuidString,
                               "--root", root.path, "--"])
        XCTAssertFalse(words.contains("--cwd"))
        XCTAssertFalse(words.contains("--resume"))
    }

    func testClaudeInlineSettingsContainOnlyCommandObserversWithCorrectEventShape() throws {
        let plan = try AgentIntegration.plan(executable: executable, taskID: taskID,
            provider: .claude, root: root, directory: directory)
        XCTAssertEqual(plan.executable, "/usr/bin/env")
        XCTAssertEqual(plan.workingDirectory, directory)
        XCTAssertEqual(plan.arguments.count, 3)
        XCTAssertEqual(Array(plan.arguments.prefix(2)), ["claude", "--settings"])
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(plan.arguments[2].utf8)) as? [String: Any])
        XCTAssertEqual(Set(document.keys), ["hooks"])
        let hooks = try XCTUnwrap(document["hooks"] as? [String: Any])
        let expected = Set(["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse",
                            "Notification", "Stop", "StopFailure", "Elicitation", "ElicitationResult", "SessionEnd"])
        XCTAssertEqual(Set(hooks.keys), expected)
        for name in expected {
            let matchers = try XCTUnwrap(hooks[name] as? [[String: Any]])
            XCTAssertEqual(matchers.count, 1)
            XCTAssertEqual(Set(matchers[0].keys), ["hooks"])
            let observers = try XCTUnwrap(matchers[0]["hooks"] as? [[String: Any]])
            XCTAssertEqual(observers.count, 1)
            let observer = observers[0]
            XCTAssertEqual(Set(observer.keys), ["type", "command", "timeout"])
            XCTAssertEqual(observer["type"] as? String, "command")
            XCTAssertEqual(observer["timeout"] as? Int, name == "SessionEnd" ? 2 : 3)
            try assertObserverCommand(try XCTUnwrap(observer["command"] as? String), provider: .claude)
        }
    }

    func testCodexSessionOverridesUseValidTOMLBasicStringEscapesAndExactObserverArguments() throws {
        let plan = try AgentIntegration.plan(executable: executable, taskID: taskID, provider: .codex, root: root)
        XCTAssertEqual(plan.executable, "/usr/bin/env")
        XCTAssertEqual(Array(plan.arguments.prefix(2)), ["codex", "--no-daemon"])
        let expected = Set(["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "Interrupt", "SessionEnd"])
        XCTAssertEqual(plan.arguments.count, 2 + expected.count * 2)
        var events = Set<String>()
        for offset in stride(from: 2, to: plan.arguments.count, by: 2) {
            XCTAssertEqual(plan.arguments[offset], "-c")
            let override = plan.arguments[offset + 1]
            let equals = try XCTUnwrap(override.firstIndex(of: "="))
            let key = String(override[..<equals])
            XCTAssertTrue(key.hasPrefix("hooks."))
            let name = String(key.dropFirst("hooks.".count))
            events.insert(name)
            XCTAssertTrue(override.contains("\"hooks\"=[{"))
            XCTAssertTrue(override.contains("\"type\"=\"command\""))
            XCTAssertTrue(override.contains("\"timeout\"=\(name == "SessionEnd" || name == "Interrupt" ? 2 : 3)"))
            let literal = try commandLiteral(in: override)
            try assertValidTOMLBasicStringEscapes(literal)
            XCTAssertFalse(literal.contains("\\/"), "JSON slash escapes are invalid in TOML basic strings.")
            let command = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
            try assertObserverCommand(command, provider: .codex)
            XCTAssertFalse(command.contains("powershell"))
            XCTAssertFalse(override.contains("command_windows"))
        }
        XCTAssertEqual(events, expected)
    }

    func testCodexExistingHookEntriesRemainBeforeObserverWithoutLosingFields() throws {
        let existing: [String: Any] = ["Stop": [["matcher": "trusted.*", "hooks": [
            ["type": "command", "command": "existing approval hook", "timeout": 25, "async": true]
        ]]], "UnchangedEvent": [["hooks": [["type": "command", "command": "untouched"]]]]]
        let plan = try AgentIntegration.plan(executable: executable, taskID: taskID, provider: .codex,
            root: root, existingCodexHooks: existing)
        let stop = try XCTUnwrap(plan.arguments.first { $0.hasPrefix("hooks.Stop=") })
        XCTAssertTrue(stop.contains("\"matcher\"=\"trusted.*\""))
        XCTAssertTrue(stop.contains("\"timeout\"=25"))
        XCTAssertTrue(stop.contains("\"async\"=true"))
        let prior = try XCTUnwrap(stop.range(of: "existing approval hook"))
        let observer = try XCTUnwrap(stop.range(of: "--provider"))
        XCTAssertLessThan(prior.lowerBound, observer.lowerBound)
        XCTAssertFalse(plan.arguments.contains { $0.hasPrefix("hooks.UnchangedEvent=") })
        XCTAssertThrowsError(try AgentIntegration.plan(executable: executable, taskID: taskID, provider: .codex,
            root: root, existingCodexHooks: ["Stop": "invalid array"]))
    }

    func testCodexReadUsesTheSameConfigOverridesAndRejectsDifferentConfigurationRoots() throws {
        let args = ["--model", "sample", "-c", "features.example=true", "--config=hooks.Stop=[]",
                    "--enable", "sample-feature", "--", "--profile", "literal prompt"]
        XCTAssertEqual(try AgentIntegration.codexReadArguments(forwarded: args),
            ["codex", "-c", "features.example=true", "--config=hooks.Stop=[]", "--enable", "sample-feature",
             "app-server", "--listen", "stdio://"])
        for args in [["--profile", "custom"], ["-pcustom"], ["--cd=/other"], ["-C", "/other"],
                     ["--worktree"], ["--remote", "ws://example"]] {
            XCTAssertThrowsError(try AgentIntegration.plan(executable: executable, taskID: taskID,
                provider: .codex, root: root, arguments: args))
        }
        XCTAssertThrowsError(try AgentIntegration.codexReadArguments(forwarded: ["--config"]))
    }

    func testBothProvidersResumeOnlyTheExplicitSessionWithProviderSpecificSyntax() throws {
        for provider in AgentProvider.allCases {
            for session in ["thr_123", "thread-with_underscores", "A1234567-89AB-4CDE-8123-123456789ABC"] {
                let plan = try AgentIntegration.plan(executable: executable, taskID: taskID,
                    provider: provider, root: root, resume: session, arguments: ["--model", "test-model"])
                XCTAssertEqual(Array(plan.arguments.suffix(4)),
                    [provider == .codex ? "resume" : "--resume", session, "--model", "test-model"])
                XCTAssertFalse(plan.arguments.contains("--last"))
            }
        }
    }

    func testInvalidResumeIdentifiersAreRejectedBeforeAnyAgentIsStarted() {
        let invalid = ["-last", "--last", "with space", "two\nlines", "id/path", "id;command", "id$(command)",
                       "id\"quoted", "id'quoted", "id\u{0}nul", String(repeating: "a", count: 161)]
        for provider in AgentProvider.allCases {
            for session in invalid {
                XCTAssertThrowsError(try AgentIntegration.plan(executable: executable, taskID: taskID,
                    provider: provider, root: root, resume: session), "Accepted resume ID: \(session.debugDescription)")
            }
        }
    }

    func testNilAndEmptyResumeNeverChooseAnImplicitRecentConversation() throws {
        for provider in AgentProvider.allCases {
            let fresh = try AgentIntegration.plan(executable: executable, taskID: taskID, provider: provider, root: root)
            let empty = try AgentIntegration.plan(executable: executable, taskID: taskID, provider: provider, root: root, resume: "")
            XCTAssertEqual(fresh.arguments, empty.arguments)
            XCTAssertFalse(fresh.arguments.contains("resume"))
            XCTAssertFalse(fresh.arguments.contains("--resume"))
            XCTAssertFalse(fresh.arguments.contains("--last"))
        }
    }

    func testForwardedArgumentsKeepExactValuesAndOrderAfterGeneratedHooksAndResume() throws {
        let forwarded = ["--model", "model with spaces", "--config", "feature.option=\"中文 '原样'\"", "--", "literal $(printf NO)\nsecond line", ""]
        for provider in AgentProvider.allCases {
            let fresh = try AgentIntegration.plan(executable: executable, taskID: taskID,
                provider: provider, root: root)
            let plan = try AgentIntegration.plan(executable: executable, taskID: taskID,
                provider: provider, root: root, resume: "thr_specific", arguments: forwarded)
            XCTAssertEqual(Array(plan.arguments.prefix(fresh.arguments.count)), fresh.arguments)
            XCTAssertEqual(Array(plan.arguments.dropFirst(fresh.arguments.count).prefix(2)),
                [provider == .codex ? "resume" : "--resume", "thr_specific"])
            XCTAssertEqual(Array(plan.arguments.suffix(forwarded.count)), forwarded)
        }
    }

    func testGeneratedPlansDoNotDisableApprovalOrSandboxAndDoNotChangeGlobalSettings() throws {
        let prohibited = ["--dangerously-skip-permissions", "--dangerously-bypass-approvals-and-sandbox", "--yolo",
                          "--full-auto", "--ask-for-approval", "--approval-mode", "--sandbox", "--yes", "-y"]
        for provider in AgentProvider.allCases {
            let plan = try AgentIntegration.plan(executable: executable, taskID: taskID, provider: provider, root: root)
            for token in prohibited { XCTAssertFalse(plan.arguments.contains(token), "Generated approval bypass: \(token)") }
            for argument in plan.arguments {
                XCTAssertFalse(argument.contains("approval_policy="))
                XCTAssertFalse(argument.contains("sandbox_mode="))
                XCTAssertFalse(argument.contains("danger-full-access"))
                XCTAssertFalse(argument.contains("permissionDecision"))
            }
        }
    }

    func testPlanningDoesNotWriteConfigurationFilesOrCreateASessionDirectory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeIntegrationPlanTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = folder.appendingPathComponent("config.toml")
        let original = Data("# existing user configuration\nmodel = \"keep\"\n".utf8)
        try original.write(to: config)
        for provider in AgentProvider.allCases {
            _ = try AgentIntegration.plan(executable: executable, taskID: taskID, provider: provider, root: folder,
                directory: directory, resume: "thr_exact")
        }
        XCTAssertEqual(try Data(contentsOf: config), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["config.toml"])
    }

    func testPublishingAnOldSessionHookOnlyEnqueuesAndCannotRewriteTheResumeRecipe() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeHookRecipeTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let currentSession = UUID().uuidString, oldSession = UUID().uuidString
        let window = WindowIdentity(processID: 123, processStartedAt: Date(), bundleIdentifier: "com.example.terminal",
            applicationName: "Terminal", title: "Exact task")
        var workspace = WorkspaceState()
        try workspace.bind(window, to: 2)
        let task = workspace.slots[1].id
        _ = try workspace.apply(.init(taskID: task, state: .running, provider: "codex",
            sessionID: currentSession, eventName: "SessionStart"))
        let store = WorkspaceStore(root: folder)
        try store.save(workspace)
        let recipes = TaskLaunchRecordStore(root: folder)
        try recipes.save(.init(mode: .codex, projectDirectory: folder.path, executablePath: "/bin/echo",
            resumeSessionID: currentSession), for: task)
        let recipeBytes = try Data(contentsOf: recipes.fileURL)
        let workspaceBytes = try Data(contentsOf: store.stateFile)
        let body = "private payload must never be persisted"
        let payload = try JSONSerialization.data(withJSONObject: ["hook_event_name": "SessionEnd",
            "session_id": oldSession, "prompt": body])

        let eventURL = try XCTUnwrap(AgentCommandLine.publishHook(provider: "codex", taskID: task, payload: payload, root: folder))

        let bytes = try Data(contentsOf: eventURL)
        XCTAssertEqual(try JSONDecoder().decode(AgentStatusEvent.self, from: bytes).sessionID, oldSession)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(body))
        XCTAssertEqual(try Data(contentsOf: recipes.fileURL), recipeBytes)
        XCTAssertEqual(try Data(contentsOf: store.stateFile), workspaceBytes)
    }

    private func assertObserverCommand(_ command: String, provider: AgentProvider,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try shellWords(command), [executable.path, "hook", "--provider", provider.rawValue,
            "--task", taskID.uuidString, "--root", root.path], file: file, line: line)
    }

    /// Uses the system shell as a parser only: set -- assigns arguments and
    /// printf serializes them. It never executes the application or an agent.
    private func shellWords(_ expression: String) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "set -- \(expression)\nprintf '%s\\0' \"$@\""]
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: error, as: UTF8.self))
        XCTAssertEqual(bytes.last, 0)
        return bytes.split(separator: 0, omittingEmptySubsequences: false).dropLast().map { String(decoding: $0, as: UTF8.self) }
    }

    private func commandLiteral(in override: String) throws -> String {
        let marker = try XCTUnwrap(override.range(of: "\"command\"=") ?? override.range(of: "command="))
        let characters = Array(override[marker.upperBound...])
        XCTAssertEqual(characters.first, "\"")
        var escaped = false
        for index in characters.indices.dropFirst() {
            if escaped { escaped = false; continue }
            if characters[index] == "\\" { escaped = true; continue }
            if characters[index] == "\"" { return String(characters[...index]) }
        }
        throw NSError(domain: "OmniVibeIntegrationTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unterminated TOML command literal"])
    }

    private func assertValidTOMLBasicStringEscapes(_ literal: String,
                                                file: StaticString = #filePath, line: UInt = #line) throws {
        let characters = Array(literal)
        let allowed: Set<Character> = ["b", "t", "n", "f", "r", "\"", "\\", "u", "U"]
        var index = 1
        while index < characters.count - 1 {
            if characters[index] == "\\" {
                index += 1
                XCTAssertLessThan(index, characters.count - 1, file: file, line: line)
                XCTAssertTrue(allowed.contains(characters[index]),
                    "Illegal TOML escape: \\\(characters[index])", file: file, line: line)
            }
            index += 1
        }
    }
}
