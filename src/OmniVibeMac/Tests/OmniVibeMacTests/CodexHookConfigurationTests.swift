import Foundation
import XCTest
@testable import OmniVibeMac

final class CodexHookConfigurationTests: XCTestCase {
    func testReadsEffectiveHooksAndPreservesDynamicFieldsUsingOnlyConfigurationRPCs() throws {
        let root = try temporaryDirectory()
        let cwd = root.appendingPathComponent("项目 '工作区'", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        let transcript = root.appendingPathComponent("requests.jsonl")
        let forbiddenSideEffect = root.appendingPathComponent("hook-was-executed")
        let hooks: [String: Any] = [
            "Stop": [["matcher": "existing", "future_matcher_flag": true, "hooks": [[
                "type": "command", "command": "touch \(quote(forbiddenSideEffect.path))",
                "timeout": 12, "future_hook_field": ["nested": [1, 2, 3]]
            ]]]],
            "FutureEvent": [["hooks": [["type": "future_type", "payload": ["preserved": true]]]]]
        ]
        let actual = try read(script: service(config: ["hooks": hooks], transcript: transcript), directory: cwd.path)
        XCTAssertEqual(try canonical(actual), try canonical(hooks))
        XCTAssertFalse(FileManager.default.fileExists(atPath: forbiddenSideEffect.path))
        let requests = try String(contentsOf: transcript).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        XCTAssertEqual(requests.compactMap { $0["method"] as? String }, ["initialize", "initialized", "config/read"])
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0]["id"] as? Int, 1)
        XCTAssertNil(requests[1]["id"])
        let params = try XCTUnwrap(requests[2]["params"] as? [String: Any])
        XCTAssertEqual(params["includeLayers"] as? Bool, false)
        XCTAssertEqual(params["cwd"] as? String, cwd.standardizedFileURL.path)
    }

    func testMissingHooksIsAnEmptyConfiguration() throws {
        XCTAssertTrue(try read(script: service(config: ["model": "irrelevant"])).isEmpty)
        XCTAssertTrue(try read(script: service(config: ["hooks": NSNull()])).isEmpty)
    }

    func testUnsupportedHooksShapeThrowsInsteadOfTreatingItAsEmpty() throws {
        for value: Any in [[], "unexpected"] {
            XCTAssertThrowsError(try read(script: service(config: ["hooks": value])))
        }
    }

    func testRPCErrorDoesNotExposeServerConfigurationOrSecretText() throws {
        let sensitive = "SENSITIVE_CONFIGURATION_VALUE"
        let response: [String: Any] = ["id": 2, "error": ["code": -32603, "message": sensitive]]
        XCTAssertThrowsError(try read(script: service(response: response))) { error in
            XCTAssertFalse(error.localizedDescription.contains(sensitive))
        }
    }

    func testMalformedOrMissingConfigResponseFailsClosed() throws {
        let responses: [[String: Any]] = [
            ["id": 2, "result": [:]],
            ["id": 2, "result": ["config": []]],
            ["id": 2, "result": ["config": NSNull()]]
        ]
        for response in responses {
            XCTAssertThrowsError(try read(script: service(response: response)))
        }
        XCTAssertThrowsError(try read(script: "printf '%s\\n' 'not-json'"))
        XCTAssertThrowsError(try read(script: "exit 0"))
    }

    func testInitializationErrorStopsBeforeConfigRead() throws {
        let root = try temporaryDirectory()
        let transcript = root.appendingPathComponent("requests.jsonl")
        let script = """
        IFS= read -r request || exit 1
        printf '%s\\n' "$request" >> \(quote(transcript.path))
        printf '%s\\n' '{"id":1,"error":{"code":-32600,"message":"unsupported"}}'
        while IFS= read -r request; do
          printf '%s\\n' "$request" >> \(quote(transcript.path))
        done
        """
        XCTAssertThrowsError(try read(script: script))
        let lines = try String(contentsOf: transcript).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
    }

    func testPartialLinesAndNotificationsDoNotBreakResponseFraming() throws {
        let script = """
        IFS= read -r request || exit 1
        printf '%s' '{"id":1,'
        printf '%s\\n' '"result":{}}'
        IFS= read -r notification || exit 1
        IFS= read -r request || exit 1
        printf '%s\\n' '{"method":"unrelated/notification","params":{}}'
        printf '%s' '{"id":2,"result":{"config":'
        printf '%s\\n' '{"hooks":{"Stop":[]}}}}'
        while IFS= read -r ignored; do :; done
        """
        let result = try read(script: script)
        XCTAssertEqual(try canonical(result), try canonical(["Stop": []]))
    }

    func testTimeoutIsBoundedEvenWhenChildIgnoresTermination() throws {
        let start = Date()
        XCTAssertThrowsError(try read(script: "trap '' TERM\nwhile :; do :; done", timeout: 0.15)) { error in
            XCTAssertTrue(error.localizedDescription.contains("超时"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testMissingExecutableAndInvalidDirectoryFailBeforeAnyConfigurationIsReturned() throws {
        XCTAssertThrowsError(try CodexHookConfiguration.read(directory: nil,
            executable: URL(fileURLWithPath: "/nonexistent/omnivibe-fake-codex"), arguments: []))
        let missing = try temporaryDirectory().appendingPathComponent("missing")
        XCTAssertThrowsError(try read(script: service(config: [:]), directory: missing.path))
        XCTAssertThrowsError(try read(script: service(config: [:]), timeout: .nan))
    }

    private func read(script: String, directory: String? = nil, timeout: TimeInterval = 1) throws -> [String: Any] {
        try CodexHookConfiguration.read(directory: directory,
            executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], timeout: timeout)
    }

    private func service(config: [String: Any], transcript: URL? = nil) throws -> String {
        try service(response: ["id": 2, "result": ["config": config]], transcript: transcript)
    }

    private func service(response: [String: Any], transcript: URL? = nil) throws -> String {
        let reply = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        let record = transcript.map { "printf '%s\\n' \"$request\" >> \(quote($0.path))" } ?? ":"
        return """
        IFS= read -r request || exit 1
        \(record)
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r request || exit 1
        \(record)
        IFS= read -r request || exit 1
        \(record)
        printf '%s\\n' \(quote(reply))
        while IFS= read -r ignored; do :; done
        """
    }

    private func canonical(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("omnivibe-config-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
