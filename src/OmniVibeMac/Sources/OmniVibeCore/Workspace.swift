import Foundation

public enum AgentState: String, Codable, CaseIterable, Sendable {
    case unknown, running, waiting, ready, error
}

/// The UUID names the application's live AX reference. A saved window may regain
/// that UUID only after its WindowServer number, login session and owning process
/// have all been verified. A title alone never authorizes reconnection.
public struct WindowIdentity: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var processID: Int32
    public var processStartedAt: Date?
    public var bundleIdentifier: String?
    public var applicationName: String
    public var title: String
    public var platformWindowNumber: UInt32?
    public var platformSessionID: String?

    public init(id: UUID = UUID(), processID: Int32, processStartedAt: Date? = nil,
                bundleIdentifier: String? = nil, applicationName: String, title: String,
                platformWindowNumber: UInt32? = nil, platformSessionID: String? = nil) {
        self.id = id
        self.processID = processID
        self.processStartedAt = processStartedAt
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.title = title
        self.platformWindowNumber = platformWindowNumber
        self.platformSessionID = platformSessionID
    }

    fileprivate func refersToSameProcess(as other: WindowIdentity) -> Bool {
        processID == other.processID && processStartedAt == other.processStartedAt &&
        bundleIdentifier == other.bundleIdentifier
    }

    /// Only complete platform tokens can establish a duplicate physical window.
    public func refersToSamePlatformWindow(as other: WindowIdentity) -> Bool {
        guard let number = platformWindowNumber, number != 0,
              let session = platformSessionID, !session.isEmpty,
              processStartedAt != nil else { return false }
        return number == other.platformWindowNumber && session == other.platformSessionID &&
            refersToSameProcess(as: other)
    }
}

public struct TaskSlot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var number: Int
    public var name: String
    public var window: WindowIdentity?
    public var agentState: AgentState
    public var unread: Bool
    public var message: String
    public var updatedAt: Date?
    public var agentProvider: String
    public var sessionID: String
    public var integrationConnected: Bool
    public var stateSource: String
    public var lastAgentTurnID: String
    public var lastAgentEventName: String

    public init(id: UUID = UUID(), number: Int, name: String = "", window: WindowIdentity? = nil,
                agentState: AgentState = .unknown, unread: Bool = false,
                message: String = "", updatedAt: Date? = nil,
                agentProvider: String = "", sessionID: String = "", integrationConnected: Bool = false,
                stateSource: String = "", lastAgentTurnID: String = "", lastAgentEventName: String = "") {
        self.id = id
        self.number = number
        self.name = name
        self.window = window
        self.agentState = agentState
        self.unread = unread
        self.message = message
        self.updatedAt = updatedAt
        self.agentProvider = agentProvider
        self.sessionID = sessionID
        self.integrationConnected = integrationConnected
        self.stateSource = stateSource
        self.lastAgentTurnID = lastAgentTurnID
        self.lastAgentEventName = lastAgentEventName
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, name, window, agentState, unread, message, updatedAt
        case agentProvider, sessionID, integrationConnected, stateSource, lastAgentTurnID, lastAgentEventName
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        number = try values.decode(Int.self, forKey: .number)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        window = try values.decodeIfPresent(WindowIdentity.self, forKey: .window)
        agentState = try values.decodeIfPresent(AgentState.self, forKey: .agentState) ?? .unknown
        unread = try values.decodeIfPresent(Bool.self, forKey: .unread) ?? false
        message = try values.decodeIfPresent(String.self, forKey: .message) ?? ""
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt)
        agentProvider = try values.decodeIfPresent(String.self, forKey: .agentProvider) ?? ""
        sessionID = try values.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        integrationConnected = try values.decodeIfPresent(Bool.self, forKey: .integrationConnected) ?? false
        stateSource = try values.decodeIfPresent(String.self, forKey: .stateSource) ?? ""
        lastAgentTurnID = try values.decodeIfPresent(String.self, forKey: .lastAgentTurnID) ?? ""
        lastAgentEventName = try values.decodeIfPresent(String.self, forKey: .lastAgentEventName) ?? ""
    }

    /// Hooks are events, not heartbeats. Old running/waiting events imply
    /// uncertainty, never proof of a failed or completed task.
    public func statusMayBeStaleAt(_ now: Date) -> Bool {
        window != nil && integrationConnected && stateSource != "手动标记" &&
            (agentState == .running || agentState == .waiting) &&
            updatedAt.map { now.timeIntervalSince($0) >= 600 } == true
    }

    public var statusMayBeStale: Bool { statusMayBeStaleAt(Date()) }

    public var displayName: String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        guard let window else { return "空槽位" }
        return window.title.isEmpty ? window.applicationName : window.title
    }
}

public enum WorkspaceError: Error, LocalizedError, Equatable {
    case invalidSlot(Int)
    case occupiedSlot(Int)
    case duplicateWindow(Int)
    case emptySlot(Int)
    case unsupportedSchema(Int)
    case invalidWorkspace

    public var errorDescription: String? {
        switch self {
        case .invalidSlot(let number): return "无效槽位 \(number)，请选择 1–9。"
        case .occupiedSlot(let number): return "槽位 \(number) 已有任务，请先解除绑定。"
        case .duplicateWindow(let number): return "这个窗口已绑定到槽位 \(number)。"
        case .emptySlot(let number): return "槽位 \(number) 尚未绑定窗口。"
        case .unsupportedSchema(let version): return "不支持的工作区版本：\(version)。"
        case .invalidWorkspace: return "工作区必须包含编号 1–9 的九个独立槽位。"
        }
    }
}

public struct WorkspaceState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var slots: [TaskSlot]

    public init(schemaVersion: Int = 1, slots: [TaskSlot]? = nil) {
        self.schemaVersion = schemaVersion
        self.slots = slots ?? (1...9).map { TaskSlot(number: $0) }
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw WorkspaceError.unsupportedSchema(schemaVersion) }
        guard slots.count == 9, Set(slots.map(\.number)) == Set(1...9),
              Set(slots.map(\.id)).count == 9 else { throw WorkspaceError.invalidWorkspace }
        let windows = slots.compactMap { $0.window?.id }
        guard Set(windows).count == windows.count else { throw WorkspaceError.invalidWorkspace }
        let occupied = slots.compactMap(\.window)
        for (index, window) in occupied.enumerated() {
            guard !occupied.dropFirst(index + 1).contains(where: { window.refersToSamePlatformWindow(as: $0) }) else {
                throw WorkspaceError.invalidWorkspace
            }
        }
    }

    public mutating func bind(_ window: WindowIdentity, to number: Int) throws {
        let index = try index(for: number)
        if let duplicate = slots.first(where: { slot in
            slot.number != number && slot.window.map { $0.id == window.id || $0.refersToSamePlatformWindow(as: window) } == true
        }) {
            throw WorkspaceError.duplicateWindow(duplicate.number)
        }
        if let existing = slots[index].window, existing.id != window.id {
            throw WorkspaceError.occupiedSlot(number)
        }
        if let existing = slots[index].window, !existing.refersToSameProcess(as: window) {
            // A reused process identifier must not inherit the prior task's events.
            slots[index] = TaskSlot(number: number)
        }
        if slots[index].window == nil {
            slots[index].agentState = .unknown
            slots[index].unread = false
            slots[index].message = ""
            slots[index].updatedAt = nil
            slots[index].agentProvider = ""
            slots[index].sessionID = ""
            slots[index].integrationConnected = false
            slots[index].stateSource = ""
            slots[index].lastAgentTurnID = ""
            slots[index].lastAgentEventName = ""
        }
        slots[index].window = window
    }

    /// Publishes metadata only after the platform has validated a live alias.
    /// The immutable task UUID, hook routing, name and status remain untouched.
    /// This method does not find windows or authorize a title-based match.
    @discardableResult
    public mutating func refreshWindowMetadata(_ identity: WindowIdentity, for taskID: UUID) throws -> Bool {
        guard let index = slots.firstIndex(where: { $0.id == taskID }),
              let previous = slots[index].window, previous.id == identity.id,
              previous.refersToSameProcess(as: identity),
              previous.platformWindowNumber == nil || previous.platformWindowNumber == identity.platformWindowNumber,
              previous.platformSessionID == nil || previous.platformSessionID == identity.platformSessionID else { return false }
        guard previous != identity else { return false }
        var updated = self
        updated.slots[index].window = identity
        try updated.validate()
        self = updated
        return true
    }

    public mutating func remove(slot number: Int) throws {
        let index = try index(for: number)
        slots[index] = TaskSlot(number: number)
    }

    /// Moves a task into an empty fixed slot. The task identity and all of its
    /// metadata travel together; the vacated slot receives a fresh empty task.
    /// An occupied destination is rejected rather than silently swapped.
    public mutating func move(from sourceNumber: Int, to targetNumber: Int) throws {
        let source = try index(for: sourceNumber)
        let target = try index(for: targetNumber)
        guard sourceNumber != targetNumber else { return }
        guard slots[source].window != nil else { throw WorkspaceError.emptySlot(sourceNumber) }
        guard slots[target].window == nil else { throw WorkspaceError.occupiedSlot(targetNumber) }
        try validate()

        var task = slots[source]
        task.number = targetNumber
        slots[target] = task
        slots[source] = TaskSlot(number: sourceNumber)
    }

    /// Inserts the task at the destination's original numbered position. Tasks
    /// in between shift by one; their identities, hooks, and task-keyed artwork
    /// remain attached to the same task. Both empty and occupied targets work.
    public mutating func reorder(from sourceNumber: Int, to targetNumber: Int) throws {
        let source = try index(for: sourceNumber)
        _ = try index(for: targetNumber)
        guard sourceNumber != targetNumber else { return }
        guard slots[source].window != nil else { throw WorkspaceError.emptySlot(sourceNumber) }
        try validate()

        var ordered = slots.sorted { $0.number < $1.number }
        let task = ordered.remove(at: sourceNumber - 1)
        ordered.insert(task, at: targetNumber - 1)
        for index in ordered.indices { ordered[index].number = index + 1 }
        slots = ordered
    }

    public mutating func rename(slot number: Int, to name: String) throws {
        let index = try index(for: number)
        guard slots[index].window != nil else { throw WorkspaceError.emptySlot(number) }
        slots[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func setStatus(slot number: Int, state: AgentState, message: String) throws {
        let index = try index(for: number)
        guard slots[index].window != nil else { throw WorkspaceError.emptySlot(number) }
        slots[index].agentState = state
        slots[index].unread = state == .waiting || state == .ready || state == .error
        slots[index].message = message
        slots[index].updatedAt = Date()
        slots[index].stateSource = "手动标记"
    }

    public mutating func markRead(slot number: Int) throws {
        let index = try index(for: number)
        guard slots[index].window != nil else { throw WorkspaceError.emptySlot(number) }
        slots[index].unread = false
    }

    /// Applies only immutable task identities. A slot number can be reused by a
    /// new task, but events from the removed task can never follow it there.
    @discardableResult
    public mutating func apply(_ event: AgentStatusEvent, now: Date = Date()) throws -> Bool {
        guard event.isValid(at: now),
              let index = slots.firstIndex(where: { $0.id == event.taskID && $0.window != nil }) else { return false }
        var slot = slots[index]
        if let last = slot.updatedAt, event.at <= last { return false }
        let beginsConversation = event.eventName == "SessionStart" || event.eventName == "UserPromptSubmit"
        let automated = event.provider == "claude" || event.provider == "codex"
        if automated {
            if event.eventName == "Transcript", slot.agentProvider == event.provider,
               sameSessionID(slot.sessionID, event.sessionID), !slot.lastAgentEventName.isEmpty,
               slot.lastAgentEventName != "Transcript" {
                // A late file append must not replace a live hook/notify source
                // or produce a second completion alert for the same CLI turn.
                return false
            }
            if !slot.agentProvider.isEmpty, slot.agentProvider != event.provider, !beginsConversation { return false }
            if !slot.sessionID.isEmpty, !sameSessionID(slot.sessionID, event.sessionID), !beginsConversation { return false }
            if slot.lastAgentEventName == "SessionEnd", !beginsConversation { return false }
            if !event.sessionID.isEmpty,
               slots.contains(where: { $0.id != slot.id && $0.window != nil && $0.agentProvider == event.provider && sameSessionID($0.sessionID, event.sessionID) }) {
                return false
            }
        }
        let newSession = automated && (slot.agentProvider != event.provider || !sameSessionID(slot.sessionID, event.sessionID))
        let newTurn = !event.turnID.isEmpty && (newSession || slot.lastAgentTurnID != event.turnID)
        let changed = slot.agentState != event.state || slot.message != event.message || newTurn
        slot.agentState = event.state
        slot.message = event.message
        slot.updatedAt = event.at
        slot.unread = (event.state == .waiting || event.state == .ready || event.state == .error) && (changed || slot.unread)
        slot.stateSource = event.provider == "manual" || (event.provider.isEmpty && event.eventName == "Manual")
            ? "手动标记" : event.provider.isEmpty ? "外部事件"
            : event.eventName == "Transcript" ? (event.provider == "claude" ? "Claude Code 会话记录" : "Codex 会话记录")
            : event.provider == "claude" ? "Claude Code hooks" : event.eventName == "agent-turn-complete" ? "Codex notify" : "Codex hooks"
        if automated {
            slot.agentProvider = event.provider
            slot.sessionID = event.sessionID
            slot.integrationConnected = !event.sessionEnded
            if newSession { slot.lastAgentTurnID = "" }
            if !event.turnID.isEmpty { slot.lastAgentTurnID = event.turnID }
            slot.lastAgentEventName = event.eventName
        }
        slots[index] = slot
        return true
    }

    private func index(for number: Int) throws -> Int {
        guard (1...9).contains(number), let index = slots.firstIndex(where: { $0.number == number }) else {
            throw WorkspaceError.invalidSlot(number)
        }
        return index
    }
}

private func sameSessionID(_ first: String, _ second: String) -> Bool {
    if let firstUUID = UUID(uuidString: first), let secondUUID = UUID(uuidString: second) { return firstUUID == secondUUID }
    return first == second
}
