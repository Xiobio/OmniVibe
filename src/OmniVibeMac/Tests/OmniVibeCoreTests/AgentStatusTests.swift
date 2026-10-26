import Foundation
import XCTest
@testable import OmniVibeCore

final class AgentStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func boundState() throws -> WorkspaceState {
        var state = WorkspaceState()
        try state.bind(WindowIdentity(processID: 12, processStartedAt: now,
            applicationName: "Terminal", title: "Work"), to: 3)
        return state
    }

    private func event(_ state: WorkspaceState, state agentState: AgentState = .running,
                       offset: TimeInterval = 0, session: String = "thr_main",
                       eventName: String = "UserPromptSubmit", turn: String = "") -> AgentStatusEvent {
        AgentStatusEvent(taskID: state.slots[2].id, state: agentState, message: agentState.rawValue,
            at: now.addingTimeInterval(offset), provider: "codex", sessionID: session,
            sessionEnded: eventName == "SessionEnd", eventName: eventName, turnID: turn)
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeAgentTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testExistingWorkspaceWithoutNewIntegrationFieldsLoadsWithoutRecovery() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try boundState()
        let encoded = try JSONEncoder().encode(state)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var slots = try XCTUnwrap(document["slots"] as? [[String: Any]])
        for index in slots.indices {
            for key in ["agentProvider", "sessionID", "integrationConnected", "stateSource", "lastAgentTurnID", "lastAgentEventName"] {
                slots[index].removeValue(forKey: key)
            }
        }
        document["slots"] = slots
        let store = WorkspaceStore(root: root)
        try JSONSerialization.data(withJSONObject: document).write(to: store.stateFile)
        let result = try store.load()
        XCTAssertNil(result.warning)
        XCTAssertEqual(result.state.slots[2].id, state.slots[2].id)
        XCTAssertEqual(result.state.slots[2].agentProvider, "")
        XCTAssertEqual(result.state.slots[2].sessionID, "")
        XCTAssertFalse(result.state.slots[2].integrationConnected)
    }

    func testHookMappingFiltersSubagentsAndNeverCopiesPromptOrTranscriptContent() throws {
        let task = UUID()
        let samples: [(String, AgentState)] = [
            ("SessionStart", .unknown), ("UserPromptSubmit", .running), ("PreToolUse", .running),
            ("PostToolUse", .running), ("PermissionRequest", .waiting), ("Elicitation", .waiting),
            ("ElicitationResult", .running), ("Stop", .ready), ("StopFailure", .error),
            ("Interrupt", .unknown), ("SessionEnd", .unknown)
        ]
        for (name, expected) in samples {
            let payload = try JSONSerialization.data(withJSONObject: [
                "hook_event_name": name, "session_id": "session_without_uuid", "prompt": "PRIVATE PROMPT",
                "transcript_path": "/private/transcript", "session_title": "PRIVATE TITLE"
            ])
            let parsed = try XCTUnwrap(HookBridge.parse(provider: "claude", taskID: task, payload: payload, at: now))
            XCTAssertEqual(parsed.state, expected)
            XCTAssertEqual(parsed.sessionID, "session_without_uuid")
            XCTAssertEqual(parsed.sessionEnded, name == "SessionEnd")
            let persisted = String(decoding: try JSONEncoder().encode(parsed), as: UTF8.self)
            XCTAssertFalse(persisted.contains("PRIVATE"))
            XCTAssertFalse(persisted.contains("transcript"))
        }
        for field in ["agent_id", "subagent_id"] {
            let data = try JSONSerialization.data(withJSONObject: ["hook_event_name": "Stop", field: "child-1"])
            XCTAssertNil(HookBridge.parse(provider: "codex", taskID: task, payload: data, at: now))
        }
        let malformedChild = Data(#"{"hook_event_name":"Stop","agent_id":7}"#.utf8)
        XCTAssertNil(HookBridge.parse(provider: "claude", taskID: task, payload: malformedChild, at: now))
    }

    func testUnknownToolFailureAndCompactEventsDoNotInventTurnOutcomes() {
        for payload in [
            #"{"hook_event_name":"PostToolUseFailure"}"#,
            #"{"hook_event_name":"SubagentStop"}"#,
            #"{"hook_event_name":"SessionStart","source":"compact"}"#,
            #"{"hook_event_name":"Notification","notification_type":"idle_prompt"}"#,
            #"{"hook_event_name":"SomethingNew"}"#
        ] {
            XCTAssertNil(HookBridge.parse(provider: "claude", taskID: UUID(), payload: Data(payload.utf8), at: now))
        }
        XCTAssertNil(HookBridge.parse(provider: "other", taskID: UUID(), payload: Data("{}".utf8), at: now))
        XCTAssertNil(HookBridge.parse(provider: "codex", taskID: UUID(), payload: Data(repeating: 65, count: 1_048_577), at: now))
        for name in ["permission_prompt", "elicitation_dialog"] {
            let data = Data("{\"hook_event_name\":\"Notification\",\"notification_type\":\"\(name)\"}".utf8)
            XCTAssertEqual(HookBridge.parse(provider: "claude", taskID: UUID(), payload: data, at: now)?.state, .waiting)
        }
    }

    func testCodexNotifyUsesSessionAndTurnIdentityWithoutSavingResponseText() throws {
        let payload = Data(#"{"type":"agent-turn-complete","thread-id":"thr_123","turn-id":"turn_456","last-assistant-message":"SECRET OUTPUT","input-messages":["SECRET PROMPT"]}"#.utf8)
        let parsed = try XCTUnwrap(HookBridge.parse(provider: "codex", taskID: UUID(), payload: payload, at: now))
        XCTAssertEqual(parsed.state, .ready)
        XCTAssertEqual(parsed.sessionID, "thr_123")
        XCTAssertEqual(parsed.turnID, "turn_456")
        XCTAssertEqual(parsed.eventName, "agent-turn-complete")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(parsed), as: UTF8.self).contains("SECRET"))
    }

    func testRemovedTaskCannotFollowAReusedSlotAndRebindResetsIntegration() throws {
        var state = try boundState()
        let old = event(state)
        XCTAssertTrue(try state.apply(old, now: now))
        let oldTask = state.slots[2].id
        try state.remove(slot: 3)
        try state.bind(WindowIdentity(processID: 14, processStartedAt: now,
            applicationName: "Terminal", title: "New"), to: 3)
        XCTAssertNotEqual(state.slots[2].id, oldTask)
        XCTAssertFalse(try state.apply(AgentStatusEvent(taskID: oldTask, state: .error, at: now.addingTimeInterval(2)), now: now.addingTimeInterval(2)))
        XCTAssertEqual(state.slots[2].agentState, .unknown)
        XCTAssertFalse(state.slots[2].integrationConnected)
        XCTAssertEqual(state.slots[2].sessionID, "")
        XCTAssertEqual(state.slots[2].agentProvider, "")
    }

    func testOldFutureDuplicateAndUnrelatedEventsDoNotMutateWorkspace() throws {
        var state = try boundState()
        XCTAssertTrue(try state.apply(event(state, offset: 10), now: now.addingTimeInterval(10)))
        let accepted = state
        for rejected in [
            event(state, state: .ready, offset: 9, eventName: "Stop"),
            event(state, state: .error, offset: 10, eventName: "StopFailure"),
            event(state, state: .ready, offset: 72, eventName: "Stop"),
            AgentStatusEvent(taskID: UUID(), state: .ready, at: now.addingTimeInterval(11))
        ] {
            XCTAssertFalse(try state.apply(rejected, now: now.addingTimeInterval(10)))
            XCTAssertEqual(state, accepted)
        }
    }

    func testOnlyExplicitNewConversationCanReplaceTrackedMainSession() throws {
        var state = try boundState()
        XCTAssertTrue(try state.apply(event(state), now: now))
        let original = state
        for session in ["another_main", ""] {
            XCTAssertFalse(try state.apply(event(state, state: .ready, offset: 1, session: session, eventName: "Stop"), now: now.addingTimeInterval(1)))
            XCTAssertEqual(state, original)
        }
        XCTAssertTrue(try state.apply(event(state, state: .unknown, offset: 2, session: "another_main", eventName: "SessionStart"), now: now.addingTimeInterval(2)))
        XCTAssertEqual(state.slots[2].sessionID, "another_main")
        XCTAssertFalse(try state.apply(event(state, state: .error, offset: 3, eventName: "StopFailure"), now: now.addingTimeInterval(3)))
        XCTAssertEqual(state.slots[2].agentState, .unknown)
    }

    func testSameSessionCannotBeClaimedByTwoTasks() throws {
        var state = try boundState()
        try state.bind(WindowIdentity(processID: 18, processStartedAt: now,
            applicationName: "Terminal", title: "Second"), to: 7)
        XCTAssertTrue(try state.apply(event(state), now: now))
        let duplicate = AgentStatusEvent(taskID: state.slots[6].id, state: .running, at: now,
            provider: "codex", sessionID: "thr_main", eventName: "UserPromptSubmit")
        XCTAssertFalse(try state.apply(duplicate, now: now))
        XCTAssertFalse(state.slots[6].integrationConnected)
    }

    func testSessionEndDisconnectsAndLateResultsCannotReviveIt() throws {
        var state = try boundState()
        XCTAssertTrue(try state.apply(event(state), now: now))
        XCTAssertTrue(try state.apply(event(state, state: .unknown, offset: 1, eventName: "SessionEnd"), now: now.addingTimeInterval(1)))
        XCTAssertFalse(state.slots[2].integrationConnected)
        XCTAssertEqual(state.slots[2].agentState, .unknown)
        XCTAssertFalse(state.slots[2].unread)
        XCTAssertFalse(try state.apply(event(state, state: .ready, offset: 2, eventName: "Stop"), now: now.addingTimeInterval(2)))
        XCTAssertTrue(try state.apply(event(state, offset: 3), now: now.addingTimeInterval(3)))
        XCTAssertTrue(state.slots[2].integrationConnected)
    }

    func testReadingDoesNotChangeOutcomeAndNotifyNewTurnCanBecomeUnreadAgain() throws {
        var state = try boundState()
        XCTAssertTrue(try state.apply(event(state, state: .ready, eventName: "agent-turn-complete", turn: "turn_one"), now: now))
        XCTAssertTrue(state.slots[2].unread)
        try state.markRead(slot: 3)
        XCTAssertEqual(state.slots[2].agentState, .ready)
        XCTAssertFalse(state.slots[2].unread)
        XCTAssertTrue(try state.apply(event(state, state: .ready, offset: 1, eventName: "agent-turn-complete", turn: "turn_one"), now: now.addingTimeInterval(1)))
        XCTAssertFalse(state.slots[2].unread)
        XCTAssertTrue(try state.apply(event(state, state: .ready, offset: 2, eventName: "agent-turn-complete", turn: "turn_two"), now: now.addingTimeInterval(2)))
        XCTAssertTrue(state.slots[2].unread)
    }

    func testOldRunningEventsOnlyAddUncertaintyAndNeverBecomeFailure() throws {
        var state = try boundState()
        XCTAssertTrue(try state.apply(event(state), now: now))
        let slot = state.slots[2]
        XCTAssertFalse(slot.statusMayBeStaleAt(now.addingTimeInterval(599)))
        XCTAssertTrue(slot.statusMayBeStaleAt(now.addingTimeInterval(600)))
        XCTAssertEqual(slot.agentState, .running)
        XCTAssertEqual(state.slots[2], slot)
        try state.setStatus(slot: 3, state: .waiting, message: "Manual")
        XCTAssertFalse(state.slots[2].statusMayBeStaleAt(Date().addingTimeInterval(3600)))
    }

    func testTimestampRoundTripPreservesSubMillisecondOrdering() throws {
        let first = AgentStatusEvent(taskID: UUID(), state: .running, at: now.addingTimeInterval(0.00001))
        let second = AgentStatusEvent(taskID: first.taskID, state: .ready, at: now.addingTimeInterval(0.00002))
        let decodedFirst = try JSONDecoder().decode(AgentStatusEvent.self, from: JSONEncoder().encode(first))
        let decodedSecond = try JSONDecoder().decode(AgentStatusEvent.self, from: JSONEncoder().encode(second))
        XCTAssertEqual(decodedFirst.at, first.at)
        XCTAssertLessThan(decodedFirst.at, decodedSecond.at)
        let isoOnly = Data("{\"taskID\":\"\(first.taskID)\",\"state\":\"ready\",\"at\":\"2026-10-24T07:00:00.123Z\"}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(AgentStatusEvent.self, from: isoOnly).state, .ready)
    }

    func testManualEventsPreserveIntegrationAndMarkReadNeverChangesExecutionState() throws {
        var state = try boundState()
        XCTAssertTrue(try state.apply(event(state), now: now))
        let tracked = state.slots[2]
        let manual = AgentStatusEvent(taskID: tracked.id, state: .waiting, message: "人工检查",
            at: now.addingTimeInterval(1), provider: "manual", eventName: "Manual")
        XCTAssertTrue(try state.apply(manual, now: now.addingTimeInterval(1)))
        XCTAssertEqual(state.slots[2].stateSource, "手动标记")
        XCTAssertEqual(state.slots[2].agentProvider, tracked.agentProvider)
        XCTAssertEqual(state.slots[2].sessionID, tracked.sessionID)
        XCTAssertEqual(state.slots[2].integrationConnected, tracked.integrationConnected)
        XCTAssertTrue(state.slots[2].unread)
        let at = state.slots[2].updatedAt
        try state.markRead(slot: 3)
        XCTAssertFalse(state.slots[2].unread)
        XCTAssertEqual(state.slots[2].agentState, .waiting)
        XCTAssertEqual(state.slots[2].updatedAt, at)
        XCTAssertTrue(try state.apply(event(state, offset: 2, eventName: "PostToolUse"), now: now.addingTimeInterval(2)))
        XCTAssertEqual(state.slots[2].agentState, .running)
        XCTAssertEqual(state.slots[2].stateSource, "Codex hooks")
    }

    func testInboxReadDoesNotAcknowledgeAndFailedSaveLeavesEventForRetry() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = StatusEventInbox(root: root)
        let original = try boundState()
        let path = try StatusEventInbox.publish(event(original), root: root)
        let pending = try await inbox.read(now: now)
        XCTAssertEqual(pending.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        var updated = original
        XCTAssertTrue(try updated.apply(pending[0].event, now: now))
        let store = WorkspaceStore(root: root)
        try FileManager.default.createDirectory(at: store.stateFile, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.save(updated))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        try FileManager.default.removeItem(at: store.stateFile)
        try store.save(updated)
        try await inbox.acknowledge(pending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(try store.load().state.slots[2].agentState, .running)
    }

    func testInboxRejectsMalformedOversizedAndFutureFilesWithoutBlockingGoodEvents() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = StatusEventInbox(root: root)
        let folder = inbox.eventsDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ broken }".utf8).write(to: folder.appendingPathComponent("bad.json"))
        try Data(repeating: 65, count: 32_769).write(to: folder.appendingPathComponent("large.json"))
        let state = try boundState()
        try JSONEncoder().encode(event(state, offset: 61)).write(to: folder.appendingPathComponent("future.json"))
        let good = try StatusEventInbox.publish(event(state), root: root)
        let batch = try await inbox.read(now: now)
        XCTAssertEqual(batch.map { $0.url.resolvingSymlinksInPath() }, [good.resolvingSymlinksInPath()])
        let rejected = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "rejected" }
        XCTAssertEqual(rejected.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: good.path))
    }

    func testInboxTakesOldestBoundedBatchAndOrdersEventsByEventTime() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = StatusEventInbox(root: root)
        let state = try boundState()
        for index in 0..<30 {
            let value = event(state, offset: Double(30 - index))
            let file = try StatusEventInbox.publish(value, root: root)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(Double(index))], ofItemAtPath: file.path)
        }
        let pending = try await inbox.read(now: now.addingTimeInterval(30))
        XCTAssertEqual(pending.count, 24)
        XCTAssertEqual(pending.first?.event.at, now.addingTimeInterval(7))
        XCTAssertEqual(pending.last?.event.at, now.addingTimeInterval(30))
        try await inbox.acknowledge(pending)
        let remaining = try await inbox.read(now: now.addingTimeInterval(30))
        XCTAssertEqual(remaining.count, 6)
        XCTAssertEqual(remaining.first?.event.at, now.addingTimeInterval(1))
    }

    func testAcknowledgementCannotDeleteReplacementEventAtSamePath() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = StatusEventInbox(root: root)
        let state = try boundState()
        let file = try StatusEventInbox.publish(event(state), root: root)
        let prior = try await inbox.read(now: now)
        let replacement = event(state, state: .ready, offset: 1, eventName: "Stop")
        try JSONEncoder().encode(replacement).write(to: file, options: .atomic)
        try await inbox.acknowledge(prior)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let next = try await inbox.read(now: now.addingTimeInterval(1))
        XCTAssertEqual(next.first?.event.id, replacement.id)
    }
}
