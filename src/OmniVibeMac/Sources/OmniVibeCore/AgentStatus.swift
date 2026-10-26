import Foundation

public struct AgentStatusEvent: Codable, Equatable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var state: AgentState
    public var message: String
    public var at: Date
    public var provider: String
    public var sessionID: String
    public var sessionEnded: Bool
    public var eventName: String
    public var turnID: String

    public init(id: UUID = UUID(), taskID: UUID, state: AgentState, message: String = "",
                at: Date = Date(), provider: String = "", sessionID: String = "",
                sessionEnded: Bool = false, eventName: String = "", turnID: String = "") {
        self.id = id; self.taskID = taskID; self.state = state; self.message = message
        self.at = at; self.provider = provider; self.sessionID = sessionID
        self.sessionEnded = sessionEnded; self.eventName = eventName; self.turnID = turnID
    }

    public func isValid(at now: Date = Date()) -> Bool {
        ["", "manual", "claude", "codex"].contains(provider) && at.timeIntervalSince1970.isFinite &&
            at <= now.addingTimeInterval(60) && message.utf8.count <= 16_384 &&
            sessionID.utf8.count <= 1024 && eventName.utf8.count <= 256 && turnID.utf8.count <= 1024 &&
            (!sessionEnded || state == .unknown)
    }

    private enum CodingKeys: String, CodingKey {
        case id, taskID, state, message, at, atEpoch, provider, sessionID, sessionEnded, eventName, turnID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        taskID = try values.decode(UUID.self, forKey: .taskID)
        state = try values.decode(AgentState.self, forKey: .state)
        message = try values.decodeIfPresent(String.self, forKey: .message) ?? ""
        provider = try values.decodeIfPresent(String.self, forKey: .provider) ?? ""
        sessionID = try values.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        sessionEnded = try values.decodeIfPresent(Bool.self, forKey: .sessionEnded) ?? false
        eventName = try values.decodeIfPresent(String.self, forKey: .eventName) ?? ""
        turnID = try values.decodeIfPresent(String.self, forKey: .turnID) ?? ""
        if let epoch = try values.decodeIfPresent(Double.self, forKey: .atEpoch) {
            at = Date(timeIntervalSince1970: epoch)
        } else if let text = try? values.decode(String.self, forKey: .at), let parsed = Self.date(text) {
            at = parsed
        } else if let raw = try? values.decode(Double.self, forKey: .at) {
            // Compatibility with JSONEncoder's default Date representation.
            at = Date(timeIntervalSinceReferenceDate: raw)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .at, in: values, debugDescription: "Missing or invalid event timestamp")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(taskID, forKey: .taskID)
        try values.encode(state, forKey: .state)
        try values.encode(message, forKey: .message)
        try values.encode(provider, forKey: .provider)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(sessionEnded, forKey: .sessionEnded)
        try values.encode(eventName, forKey: .eventName)
        try values.encode(turnID, forKey: .turnID)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try values.encode(formatter.string(from: at), forKey: .at)
        // Keep exact ordering when several hooks arrive in the same millisecond.
        try values.encode(at.timeIntervalSince1970, forKey: .atEpoch)
    }

    private static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: string) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

public enum HookBridge {
    /// Observes events only. It never approves permissions, emits instructions,
    /// stores prompt/transcript contents, or equates a reply with task completion.
    public static func parse(provider: String, taskID: UUID, payload: Data, at: Date = Date()) -> AgentStatusEvent? {
        guard ["claude", "codex"].contains(provider), payload.count <= 1_048_576 else { return nil }
        var data = payload
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func text(_ key: String) -> String { root[key] as? String ?? "" }
        func subagentIdentifierPresent(_ key: String) -> Bool {
            guard let value = root[key], !(value is NSNull) else { return false }
            if let text = value as? String { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return true
        }
        guard !subagentIdentifierPresent("agent_id"), !subagentIdentifierPresent("subagent_id") else { return nil }
        var name = text("hook_event_name")
        let session: String
        let turn: String
        if provider == "codex", name.isEmpty, text("type") == "agent-turn-complete" {
            name = "agent-turn-complete"
            session = text("thread-id").isEmpty ? text("thread_id") : text("thread-id")
            turn = text("turn-id").isEmpty ? text("turn_id") : text("turn-id")
        } else {
            session = text("session_id")
            turn = text("turn_id")
        }
        let state: AgentState
        let message: String
        switch name {
        case "SessionStart":
            guard text("source") != "compact" else { return nil }
            state = .unknown; message = "会话已连接，等待提交任务"
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "ElicitationResult":
            state = .running; message = "AI 正在执行"
        case "PermissionRequest", "Elicitation":
            state = .waiting; message = "需要你的确认或输入"
        case "Notification":
            guard ["permission_prompt", "elicitation_dialog"].contains(text("notification_type")) else { return nil }
            state = .waiting; message = "需要你的确认或输入"
        case "Stop", "agent-turn-complete":
            state = .ready; message = "本轮回复已结束，请查看结果"
        case "StopFailure":
            state = .error; message = "本轮执行发生错误，请查看终端"
        case "Interrupt":
            state = .unknown; message = "本轮已中断"
        case "SessionEnd":
            state = .unknown; message = "CLI 会话已结束"
        default: return nil
        }
        let event = AgentStatusEvent(taskID: taskID, state: state, message: message, at: at,
                                    provider: provider, sessionID: session, sessionEnded: name == "SessionEnd",
                                    eventName: name, turnID: turn)
        return event.isValid(at: at) ? event : nil
    }
}
