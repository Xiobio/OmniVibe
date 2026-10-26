import Foundation
import SQLite3
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class SessionDiscoveryTests: XCTestCase {
    private func fixture() throws -> (URL, SessionDiscoveryRoots, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeSessionTests-\(UUID())")
        let roots = SessionDiscoveryRoots(codex: root.appendingPathComponent("codex"), claude: root.appendingPathComponent("claude"))
        let project = root.appendingPathComponent("metadata-project")
        for directory in [roots.codex, roots.codexSessions, roots.claudeProjects, project] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, roots, project)
    }

    private func codexFile(roots: SessionDiscoveryRoots, project: URL, id: String) throws -> URL {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy/MM/dd"
        let day = roots.codexSessions.appendingPathComponent(formatter.string(from: Date()))
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let file = day.appendingPathComponent("rollout-date-\(id).jsonl")
        let header: [String: Any] = ["type": "session_meta", "payload": ["id": id, "cwd": project.path,
            "developer_instructions": "PRIVATE_PROMPT_SENTINEL", "source": "cli"]]
        var bytes = try JSONSerialization.data(withJSONObject: header); bytes.append(10)
        try bytes.write(to: file)
        return file
    }

    private func append(_ object: [String: Any], to file: URL, newline: Bool = true) throws {
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
        _ = try handle.seekToEnd()
        var bytes = try JSONSerialization.data(withJSONObject: object)
        if newline { bytes.append(10) }; try handle.write(contentsOf: bytes)
    }

    func testProjectionReadsMetadataButNeverDecodesMessagePromptArgumentsOrFirstPrompt() throws {
        let data = Data(#"{"type":"assistant","timestamp":"2026-10-26T10:00:00Z","sessionId":"d888c0cc-7bf8-435f-aa1f-74ce3ec9e39e","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{"question":"PRIVATE_PROMPT_SENTINEL"}},{"type":"text","text":"PRIVATE_RESPONSE_SENTINEL"}],"stop_reason":"tool_use"},"prompt":"PRIVATE_PROMPT_SENTINEL"}"#.utf8)
        let fields = try SessionMetadataProjection.fields(data)
        XCTAssertEqual(fields["type"], "assistant")
        XCTAssertEqual(fields["message.stop_reason"], "tool_use")
        XCTAssertEqual(fields["message.content.*.name"], "AskUserQuestion")
        XCTAssertFalse(fields.values.joined().contains("PRIVATE_"))
        XCTAssertNil(fields["message.content.*.input.question"])
        XCTAssertNil(fields["prompt"])
        let index = Data(#"{"version":1,"entries":[{"sessionId":"d888c0cc-7bf8-435f-aa1f-74ce3ec9e39e","projectPath":"/tmp/project","fullPath":"/tmp/record.jsonl","firstPrompt":"PRIVATE_PROMPT_SENTINEL","summary":"PRIVATE_SUMMARY_SENTINEL"}]}"#.utf8)
        let rows = try SessionMetadataProjection.indexRows(index)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["projectPath"], "/tmp/project")
        XCTAssertFalse(rows[0].values.joined().contains("PRIVATE_"))
    }

    func testPromptStringsCannotInjectMetadataAndMalformedOrOversizedJSONIsRejected() throws {
        let fields = try SessionMetadataProjection.fields(Data(#"{"type":"user","message":{"content":"\"sessionId\":\"forged\",\"cwd\":\"/evil\""},"sessionId":"real"}"#.utf8))
        XCTAssertEqual(fields["sessionId"], "real")
        XCTAssertNil(fields["cwd"])
        XCTAssertThrowsError(try SessionMetadataProjection.fields(Data(#"{"type":"user"} trailing"#.utf8)))
        XCTAssertThrowsError(try SessionMetadataProjection.fields(Data(repeating: 32, count: 262_145)))
        XCTAssertThrowsError(try SessionMetadataProjection.indexRows(Data("{} garbage".utf8)))
    }

    func testDiscoveryFindsExactHeaderWithoutUsingPromptAsTitleOrGuessingEncodedProjectFolder() async throws {
        let (_, roots, project) = try fixture(), id = UUID().uuidString
        let file = try codexFile(roots: roots, project: project, id: id)
        let result = await SessionDiscoveryService(roots: roots).discover()
        XCTAssertEqual(result.sessions.count, 1)
        let session = try XCTUnwrap(result.sessions.first)
        XCTAssertEqual(session.provider, "codex")
        XCTAssertEqual(session.sessionID, id)
        XCTAssertEqual(session.projectDirectory, project.path)
        XCTAssertEqual(session.transcriptPath, file.path)
        XCTAssertFalse(session.title.contains("PRIVATE_"))
        XCTAssertTrue(session.title.contains(String(id.prefix(8))))
    }

    func testClaudeIndexExposesOnlyWhitelistedMetadataAndRejectsOutsideTranscriptRoots() async throws {
        let (root, roots, project) = try fixture(), id = UUID().uuidString, outsideID = UUID().uuidString
        let folder = roots.claudeProjects.appendingPathComponent("encoded-name-not-decoded")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(id + ".jsonl")
        try Data("{}\n".utf8).write(to: file)
        let outside = root.appendingPathComponent(outsideID + ".jsonl")
        try Data("{}\n".utf8).write(to: outside)
        let index: [String: Any] = ["entries": [
            ["sessionId": id, "projectPath": project.path, "fullPath": file.path, "firstPrompt": "PRIVATE_PROMPT_SENTINEL"],
            ["sessionId": outsideID, "projectPath": project.path, "fullPath": outside.path]
        ]]
        try JSONSerialization.data(withJSONObject: index).write(to: folder.appendingPathComponent("sessions-index.json"))
        let result = await SessionDiscoveryService(roots: roots).discover()
        XCTAssertEqual(result.sessions.map(\.sessionID), [id])
        XCTAssertFalse(result.sessions[0].title.contains("PRIVATE_"))
        XCTAssertFalse(roots.allows(outside, provider: "claude"))
    }

    func testCodexReadOnlySQLiteMetadataDoesNotRequireConversationBodyParsing() async throws {
        let (_, roots, project) = try fixture(), id = UUID().uuidString
        let day = roots.codexSessions.appendingPathComponent("2001/01/01")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let file = day.appendingPathComponent("rollout-old-\(id).jsonl")
        try Data("PRIVATE_BODY_IS_NOT_JSON\n".utf8).write(to: file)
        let dbURL = roots.codex.appendingPathComponent("state_5.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        let escapedFile = file.path.replacingOccurrences(of: "'", with: "''")
        let escapedProject = project.path.replacingOccurrences(of: "'", with: "''")
        let sql = "CREATE TABLE threads(id TEXT,cwd TEXT,rollout_path TEXT,title TEXT,archived INTEGER,updated_at INTEGER); " +
            "INSERT INTO threads VALUES('\(id)','\(escapedProject)','\(escapedFile)','Chosen metadata title',0,1);"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let before = try Data(contentsOf: dbURL)
        let result = await SessionDiscoveryService(roots: roots).discover()
        XCTAssertEqual(result.sessions.first?.sessionID, id)
        XCTAssertEqual(result.sessions.first?.title, "Chosen metadata title")
        XCTAssertEqual(try Data(contentsOf: dbURL), before)
    }

    func testAssociationsRequireAnExactUniqueSessionAndPersistOnlyMetadata() throws {
        let (root, _, project) = try fixture(), id = UUID().uuidString, task = UUID(), window = UUID()
        let session = DiscoveredAgentSession(provider: "codex", sessionID: id, projectDirectory: project.path,
            title: "Metadata title", transcriptPath: root.appendingPathComponent(id + ".jsonl").path, modifiedAt: Date())
        let store = SessionDiscoveryAssociationStore(root: root)
        try store.bind(taskID: task, windowID: window, session: session)
        XCTAssertThrowsError(try store.bind(taskID: UUID(), windowID: UUID(), session: session))
        let newTask = UUID(), newWindow = UUID()
        try store.transfer(from: task, to: newTask, windowID: newWindow)
        XCTAssertEqual(try store.load().first?.taskID, newTask)
        XCTAssertEqual(try store.load().first?.windowID, newWindow)
        try store.remove(newTask)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testObserverAnchorsEOFAndOnlyEmitsNewStructuredEventsForTheExactFileAndSession() async throws {
        let (_, roots, project) = try fixture(), id = UUID().uuidString, task = UUID(), window = UUID()
        let file = try codexFile(roots: roots, project: project, id: id)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try append(["type": "event_msg", "timestamp": timestamp, "payload": ["type": "task_complete", "last_agent_message": "PRIVATE_REPLY"]], to: file)
        let session = DiscoveredAgentSession(provider: "codex", sessionID: id, projectDirectory: project.path,
            title: "Metadata", transcriptPath: file.path, modifiedAt: Date())
        let association = SessionDiscoveryAssociation(taskID: task, windowID: window, session: session, linkedAt: Date())
        let observer = SessionDiscoveryObserver(roots: roots)
        let initial = await observer.poll([association]); XCTAssertTrue(initial.isEmpty)
        try append(["type": "event_msg", "timestamp": timestamp, "payload": ["type": "task_started", "prompt": "PRIVATE_PROMPT"]], to: file)
        let updates = await observer.poll([association])
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].taskID, task)
        XCTAssertEqual(updates[0].windowID, window)
        XCTAssertEqual(updates[0].event.state, .running)
        XCTAssertEqual(updates[0].event.sessionID, id)
        XCTAssertFalse(updates[0].event.message.contains("PRIVATE_"))
        let unchanged = await observer.poll([association]); XCTAssertTrue(unchanged.isEmpty)
    }

    func testObserverNeverReplaysAReplacedFileAndDoesNotPublishPartialJSONLines() async throws {
        let (_, roots, project) = try fixture(), id = UUID().uuidString
        let file = try codexFile(roots: roots, project: project, id: id)
        let session = DiscoveredAgentSession(provider: "codex", sessionID: id, projectDirectory: project.path,
            title: "Metadata", transcriptPath: file.path, modifiedAt: Date())
        let association = SessionDiscoveryAssociation(taskID: UUID(), windowID: UUID(), session: session, linkedAt: Date())
        let observer = SessionDiscoveryObserver(roots: roots)
        _ = await observer.poll([association])
        try append(["type": "event_msg", "timestamp": "2026-10-26T10:00:00Z", "payload": ["type": "turn_complete"]], to: file, newline: false)
        let partial = await observer.poll([association]); XCTAssertTrue(partial.isEmpty)
        let handle = try FileHandle(forWritingTo: file); _ = try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        let completed = await observer.poll([association]); XCTAssertEqual(completed.first?.event.state, .ready)
        try Data("{}\n".utf8).write(to: file, options: .atomic)
        let replaced = await observer.poll([association]); XCTAssertTrue(replaced.isEmpty)
    }

    func testStructuredClaudeActivityIgnoresUserSlashCommandBodiesAndHonorsExactSessionID() throws {
        let id = UUID().uuidString, task = UUID()
        func parse(_ object: [String: Any]) throws -> AgentStatusEvent? {
            try SessionDiscoveryObserver.parse(provider: "claude", taskID: task, sessionID: id,
                data: JSONSerialization.data(withJSONObject: object))
        }
        let base: [String: Any] = ["timestamp": "2026-10-26T10:00:00Z", "sessionId": id]
        var entry = base; entry["type"] = "user"; entry["message"] = ["content": "/model command body"]
        XCTAssertNil(try parse(entry))
        entry["type"] = "assistant"; entry["message"] = ["stop_reason": "tool_use", "content": [["type": "tool_use", "name": "AskUserQuestion", "input": ["question": "PRIVATE_PROMPT"]]]]
        XCTAssertEqual(try parse(entry)?.state, .waiting)
        entry["message"] = ["stop_reason": "end_turn", "content": "PRIVATE_REPLY"]
        XCTAssertEqual(try parse(entry)?.state, .ready)
        entry["sessionId"] = UUID().uuidString
        XCTAssertNil(try parse(entry))
    }
}
