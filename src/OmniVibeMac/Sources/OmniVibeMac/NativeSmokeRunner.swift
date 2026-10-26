import AppKit
import Foundation
import OmniVibeCore

@MainActor
enum NativeSmokeRunner {
    struct Check: Encodable {
        let name: String
        let passed: Bool
        let detail: String
    }

    struct Report: Encodable {
        let timestamp: Date
        let status: String
        let checks: [Check]
        let limitation: String
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func run(outputPath: String) async -> Int32 {
        let service = WindowService()
        var checks: [Check] = []
        var stage = "Initialize desktop validation"
        var fixture: NSRunningApplication?
        var secondFixture: NSRunningApplication?
        var originals: [(WindowIdentity, WindowPlacement)] = []
        let previousFocus = service.currentWindow()
        let hotkeys = HotKeyService(onSlot: { _ in }, onArrange: {})
        defer {
            hotkeys.unregister()
            for (window, placement) in originals { try? service.restore(window, to: placement) }
            if let fixture, !fixture.isTerminated { fixture.terminate() }
            if let secondFixture, !secondFixture.isTerminated { secondFixture.terminate() }
            if let previousFocus { try? service.activate(previousFocus) }
        }

        func record(_ name: String, _ condition: Bool, _ detail: String = "") throws {
            checks.append(Check(name: name, passed: condition, detail: detail))
            if !condition { throw Failure(name + (detail.isEmpty ? "" : ": " + detail)) }
        }

        func write(_ status: String, code: Int32) -> Int32 {
            let report = Report(
                timestamp: Date(), status: status, checks: checks,
                limitation: "Disposable AppKit windows only. Finder-launched app permission, terminal applications, multiple displays, Spaces, full screen, and physical shortcut input require separate manual validation."
            )
            do {
                let url = URL(fileURLWithPath: outputPath)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(report).write(to: url, options: .atomic)
                print("macOS desktop validation: \(status). Report: \(url.path)")
                return code
            } catch {
                fputs("Cannot write desktop validation report: \(error.localizedDescription)\n", stderr)
                return 1
            }
        }

        do {
            try hotkeys.register()
            try record("Register all ten Control-Option shortcuts", hotkeys.registeredSlots.count == 9 && hotkeys.arrangementRegistered,
                       hotkeys.warnings.joined(separator: "; "))
            hotkeys.unregister()
            guard service.isTrusted else {
                checks.append(Check(name: "Accessibility permission", passed: false, detail: "Grant OmniVibe access in System Settings > Privacy & Security > Accessibility, then rerun. No desktop operations were attempted."))
                return write("requires-permission", code: 2)
            }
            try record("Accessibility permission", true)

            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OmniVibeFixture.app")
            guard FileManager.default.isExecutableFile(atPath: helper.appendingPathComponent("Contents/MacOS/OmniVibeFixture").path) else { throw Failure("Fixture helper missing; run scripts/macos/build.sh first.") }
            // LaunchServices supplies process launchDate, needed for PID-reuse protection.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.activates = false
            let process = try await NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
            fixture = process
            stage = "Discover two windows from the same fixture process"
            let discoveryStarted = ProcessInfo.processInfo.systemUptime
            let discoveryDeadline = discoveryStarted + 8
            var windows: [WindowIdentity] = []
            var tokenCount = 0
            while !process.isTerminated && ProcessInfo.processInfo.systemUptime < discoveryDeadline {
                try Task.checkCancellation()
                windows = service.windows(for: process.processIdentifier).sorted { $0.title < $1.title }
                tokenCount = windows.filter {
                    ($0.platformWindowNumber ?? 0) != 0 && $0.platformSessionID?.isEmpty == false &&
                        $0.processStartedAt?.timeIntervalSince1970.isFinite == true
                }.count
                if windows.count == 2 && tokenCount == 2 { break }
                let remaining = discoveryDeadline - ProcessInfo.processInfo.systemUptime
                if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(min(0.1, remaining) * 1_000_000_000)) }
            }
            let discoveryElapsed = ProcessInfo.processInfo.systemUptime - discoveryStarted
            let discoveryDetail = String(format: "pid=%d; fixture.terminated=%@; discoveredCount=%d; tokenCount=%d; elapsed=%.3fs",
                process.processIdentifier, String(process.isTerminated), windows.count, tokenCount, discoveryElapsed)
            try record(stage, windows.count == 2 && tokenCount == 2 && !process.isTerminated && discoveryElapsed <= 8, discoveryDetail)
            try record("Keep separate identities for same-app windows", windows[0].id != windows[1].id)
            for window in windows { originals.append((window, try service.capturePlacement(window))) }

            var workspace = WorkspaceState()
            try workspace.bind(windows[0], to: 1)
            try workspace.bind(windows[1], to: 2)
            try record("Bind same-app windows to separate fixed slots", workspace.slots[0].window?.id == windows[0].id && workspace.slots[1].window?.id == windows[1].id)
            for window in windows {
                stage = "Activate fixture window"
                try service.activate(window)
                try await service.confirmActivation(window)
                try record("Activate exact fixture window \(window == windows[0] ? 1 : 2)", service.currentWindow()?.id == window.id)
            }

            // A second independent process tests leaving the currently active app.
            let foregroundConfiguration = NSWorkspace.OpenConfiguration()
            foregroundConfiguration.createsNewApplicationInstance = true
            foregroundConfiguration.activates = true
            let focusHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OmniVibeFocusFixture.app")
            let another = try await NSWorkspace.shared.openApplication(at: focusHelper, configuration: foregroundConfiguration)
            secondFixture = another
            for _ in 0..<20 {
                await pause()
                if service.currentWindow()?.processID == another.processIdentifier { break }
            }
            try record("Start a separate foreground fixture process", another.processIdentifier != process.processIdentifier && service.currentWindow()?.processID == another.processIdentifier,
                       "Separate process: \(another.processIdentifier != process.processIdentifier); foreground target: \(service.currentWindow()?.processID == another.processIdentifier)")
            try service.activate(windows[0])
            try await service.confirmActivation(windows[0])
            try record("Switch from another process to the exact bound window", service.currentWindow()?.id == windows[0].id)

            let frames = LayoutEngine.frames(count: 2, workArea: service.workArea(for: windows[0]), gap: 12, mode: .columns)
            stage = "Arrange fixture windows"
            for (window, frame) in zip(windows, frames) { try service.setFrame(frame, for: window) }
            await pause()
            for (index, window) in windows.enumerated() {
                let current = try service.capturePlacement(window)
                try record("Arrange fixture window \(index + 1)", close(current.frame, frames[index]))
            }
            let firstOriginal = originals[0].1
            stage = "Restore and minimize selected fixture window"
            try service.restore(windows[0], to: WindowPlacement(frame: firstOriginal.frame, minimized: true))
            stage = "Read minimized fixture window after animation"
            let minimized = try await placement(of: windows[0], minimized: true, service: service)
            try record("Minimize only the selected fixture window", minimized.minimized && !service.capturePlacement(windows[1]).minimized)
            stage = "Activate minimized fixture window"
            try service.activate(windows[0])
            try await service.confirmActivation(windows[0])
            let restored = try await placement(of: windows[0], minimized: false, service: service)
            try record("Unminimize and focus the selected fixture window", !restored.minimized && service.currentWindow()?.id == windows[0].id)

            stage = "Restore original fixture placements"
            for (window, placement) in originals { try service.restore(window, to: placement) }
            await pause()
            for (index, entry) in originals.enumerated() {
                let current = try service.capturePlacement(entry.0)
                try record("Restore original placement \(index + 1)", close(current.frame, entry.1.frame) && current.minimized == entry.1.minimized)
            }
            originals.removeAll()
            process.terminate()
            for _ in 0..<20 {
                if process.isTerminated { break }
                await pause()
            }
            try record("Reject closed fixture windows", windows.allSatisfy { !service.isAvailable($0) })
            return write("passed", code: 0)
        } catch {
            checks.append(Check(name: stage, passed: false, detail: error.localizedDescription))
            return write("failed", code: 1)
        }
    }

    private static func close(_ first: WindowFrame, _ second: WindowFrame) -> Bool {
        abs(first.x - second.x) <= 4 && abs(first.y - second.y) <= 4 && abs(first.width - second.width) <= 4 && abs(first.height - second.height) <= 4
    }

    private static func pause() async { try? await Task.sleep(nanoseconds: 250_000_000) }

    private static func placement(of window: WindowIdentity, minimized: Bool, service: WindowService) async throws -> WindowPlacement {
        for _ in 0..<12 {
            await pause()
            if let placement = try? service.capturePlacement(window), placement.minimized == minimized { return placement }
        }
        throw Failure("Fixture did not reach its expected minimized state after the system animation.")
    }
}
