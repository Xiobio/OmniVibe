import Foundation
import Darwin

/// Reads Codex's effective configuration without creating a thread, changing
/// configuration, or executing any configured hook command.
enum CodexHookConfiguration {
    static func read(directory: String?,
                     executable: URL = URL(fileURLWithPath: "/usr/bin/env"),
                     arguments: [String] = ["codex", "app-server", "--listen", "stdio://"],
                     timeout: TimeInterval = 5) throws -> [String: Any] {
        guard timeout.isFinite, timeout > 0 else { throw ReadError.invalidTimeout }
        let cwd = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ReadError.invalidDirectory
        }
        let deadline = Date().addingTimeInterval(min(timeout, 5))
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let mailbox = ResponseMailbox()
        let exited = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A child that exits during the handshake must produce a thrown error,
        // rather than delivering SIGPIPE to the application.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.terminationHandler = { _ in exited.signal() }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { mailbox.close() } else { mailbox.receive(data) }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                if exited.wait(timeout: .now() + 0.2) == .timedOut, process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
            try? output.fileHandleForReading.close()
        }
        do { try process.run() } catch { throw ReadError.unavailable }

        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            do { try input.fileHandleForWriting.write(contentsOf: data) }
            catch { throw ReadError.protocolFailure }
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "omnivibe_hooks_reader", "version": "1.0.0"],
            "capabilities": ["experimentalApi": true]
        ]])
        let initialized = try mailbox.response(id: 1, deadline: deadline)
        guard initialized["error"] == nil, initialized["result"] is [String: Any] else {
            throw ReadError.protocolFailure
        }
        try send(["method": "initialized"])
        try send(["id": 2, "method": "config/read", "params": ["includeLayers": false, "cwd": cwd.path]])
        let response = try mailbox.response(id: 2, deadline: deadline)
        guard response["error"] == nil,
              let result = response["result"] as? [String: Any],
              let config = result["config"] as? [String: Any] else { throw ReadError.protocolFailure }
        guard let value = config["hooks"] else { return [:] }
        // Codex 0.162.1 serializes its absent optional hooks as JSON null.
        if value is NSNull { return [:] }
        guard let hooks = value as? [String: Any] else { throw ReadError.invalidHooks }
        return hooks
    }

    enum ReadError: LocalizedError {
        case unavailable, timedOut, protocolFailure, invalidHooks, outputTooLarge, invalidDirectory, invalidTimeout

        var errorDescription: String? {
            switch self {
            case .unavailable: return "无法启动 Codex 配置读取器，已停止接入以保留已有 hooks。"
            case .timedOut: return "读取 Codex 配置超时，已停止接入以保留已有 hooks。"
            case .invalidDirectory: return "Codex 任务目录不存在。"
            case .invalidTimeout: return "Codex 配置读取超时设置无效。"
            case .invalidHooks: return "Codex hooks 配置格式无法识别，已停止接入。"
            case .outputTooLarge: return "Codex 配置超过读取大小限制，已停止接入。"
            case .protocolFailure: return "无法确认 Codex 有效配置，已停止接入以保留已有 hooks。"
            }
        }
    }

    private final class ResponseMailbox: @unchecked Sendable {
        private let condition = NSCondition()
        private var buffer = Data()
        private var responses: [Int: [String: Any]] = [:]
        private var receivedBytes = 0
        private var failure: ReadError?
        private var closed = false
        private let maximumBytes = 16 * 1_024 * 1_024

        func receive(_ data: Data) {
            condition.lock()
            defer { condition.broadcast(); condition.unlock() }
            guard failure == nil else { return }
            receivedBytes += data.count
            guard receivedBytes <= maximumBytes else { failure = .outputTooLarge; return }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                guard let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                    failure = .protocolFailure
                    return
                }
                // Server notifications and requests are not responses to our reads.
                if message["method"] == nil, let id = message["id"] as? Int, id == 1 || id == 2 {
                    responses[id] = message
                }
            }
        }

        func close() {
            condition.lock()
            closed = true
            condition.broadcast()
            condition.unlock()
        }

        func response(id: Int, deadline: Date) throws -> [String: Any] {
            condition.lock()
            defer { condition.unlock() }
            while true {
                if let failure { throw failure }
                if let response = responses.removeValue(forKey: id) { return response }
                if closed { throw ReadError.protocolFailure }
                guard condition.wait(until: deadline) else { throw ReadError.timedOut }
            }
        }
    }
}
