import AppKit
import Foundation
import OmniVibeCore

/// Exercises the real controller with disposable helper windows and isolated
/// persistence. It never requests permission or binds an existing user window.
@MainActor
enum ArrangementValidationRunner {
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

    private struct Snapshot {
        let window: WindowIdentity
        let placement: WindowPlacement
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func run(outputPath: String) async -> Int32 {
        let service = WindowService()
        let identifier = UUID().uuidString
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniVibeArrangementValidation-" + identifier, isDirectory: true)
        let suiteName = "OmniVibe.ArrangementValidation." + identifier
        let preferences = UserDefaults(suiteName: suiteName)
        let existingProcesses = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        var checks: [Check] = []
        var helpers: [NSRunningApplication] = []
        var originals: [Snapshot] = []
        var controller: ApplicationController?
        var stage = "Accessibility permission"
        var status = "failed"
        var exitCode: Int32 = 1

        func record(_ name: String, _ passed: Bool, _ detail: String = "") throws {
            checks.append(Check(name: name, passed: passed, detail: detail))
            if !passed { throw Failure(name + (detail.isEmpty ? "" : ": " + detail)) }
        }

        do {
            guard service.isTrusted else {
                throw Failure("Accessibility access is unavailable. Allow the built app in System Settings and rerun; this validation does not request permission or change any window without it.")
            }
            try record(stage, true)
            guard let preferences else { throw Failure("Cannot create isolated preferences suite.") }
            preferences.removePersistentDomain(forName: suiteName)
            try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

            stage = "Launch two new disposable helper processes"
            let helperRoot = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
            for name in ["OmniVibeFixture.app", "OmniVibeFocusFixture.app"] {
                let helper = helperRoot.appendingPathComponent(name, isDirectory: true)
                guard FileManager.default.isExecutableFile(atPath: helper.appendingPathComponent("Contents/MacOS/OmniVibeFixture").path) else {
                    throw Failure("Missing \(name); build the packaged app before running this validation.")
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                configuration.activates = false
                let process = try await NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
                guard !existingProcesses.contains(process.processIdentifier),
                      !helpers.contains(where: { $0.processIdentifier == process.processIdentifier }) else {
                    throw Failure("LaunchServices did not create a new disposable process; the existing process will not be manipulated or terminated.")
                }
                helpers.append(process)
            }
            try record(stage, helpers.count == 2 && helpers[0].processIdentifier != helpers[1].processIdentifier)

            stage = "Discover two windows in each disposable process"
            var windowsByProcess: [[WindowIdentity]] = []
            for helper in helpers {
                let windows = try await discoverWindows(process: helper, service: service)
                windowsByProcess.append(windows)
                for window in windows {
                    originals.append(Snapshot(window: window, placement: try service.capturePlacement(window)))
                }
            }
            try record(stage, windowsByProcess.allSatisfy { $0.count == 2 } && originals.count == 4)
            let bound = windowsByProcess[0] + [windowsByProcess[1][0]]
            let unbound = windowsByProcess[1][1]
            try record("Keep three distinct bound identities across two processes", Set(bound.map(\.id)).count == 3 &&
                       Set(bound.map(\.processID)).count == 2)

            // Put only our three test windows on one display to exercise the
            // three-window grid. These staggered starting frames differ
            // from the expected tiled frames.
            stage = "Prepare distinct fixture placements on one display"
            let area = service.workArea(for: bound[0])
            guard area.width >= 500, area.height >= 400 else {
                throw Failure("The fixture display is too small for this three-window validation (minimum 500 × 400 points).")
            }
            for (index, window) in bound.enumerated() {
                let target = WindowFrame(x: area.x + 20 + Double(index * 24), y: area.y + 20 + Double(index * 24),
                                         width: min(440, area.width - 100), height: min(280, area.height - 100))
                try service.restore(window, to: WindowPlacement(frame: target, minimized: false))
                _ = try await placement(of: window, service: service, label: stage) {
                    !$0.minimized && WindowFrameFit.restored($0.frame, before: target)
                }
            }
            let minimizedFrame = try service.capturePlacement(bound[1]).frame
            try service.restore(bound[1], to: WindowPlacement(frame: minimizedFrame, minimized: true))
            _ = try await placement(of: bound[1], service: service, label: "Prepare minimized fixture") { $0.minimized }
            let baseline = try bound.map { Snapshot(window: $0, placement: try service.capturePlacement($0)) }
            let baselineDisplays = bound.map { service.arrangementDisplay(for: $0) }
            let workAreas = baselineDisplays.map(\.workArea)
            try record("Prepare one minimized window and preserve each original display", baseline[1].placement.minimized &&
                       Set(baselineDisplays.map(\.id)).count == 1,
                       "Physical displays: " + baselineDisplays.map(\.id).joined(separator: ", "))
            let untouchedPlacement = try service.capturePlacement(unbound)

            stage = "Create isolated controller and three fixed bindings"
            var workspace = WorkspaceState()
            for (index, window) in bound.enumerated() { try workspace.bind(window, to: index + 1) }
            let store = WorkspaceStore(root: temporaryRoot)
            try store.save(workspace)
            let model = ApplicationController(windowService: service, store: store, startsMonitoring: false, preferences: preferences)
            controller = model
            model.arrangement = .balanced
            model.setShortcutScheme(.optionNumbers)
            try record(stage, model.workspace.slots.compactMap(\.window).map(\.id) == bound.map(\.id) &&
                       model.registeredTaskShortcuts.isEmpty && model.shortcutScheme == .optionNumbers,
                       "Temporary workspace and preferences only; no global shortcuts are registered.")
            stage = "Require complete unique WindowServer tokens for bound fixtures"
            let savedWindows = model.workspace.slots.compactMap(\.window)
            try record(stage, savedWindows.count == 3 &&
                       savedWindows.allSatisfy { ($0.platformWindowNumber ?? 0) != 0 && $0.platformSessionID?.isEmpty == false && $0.processStartedAt != nil } &&
                       Set(savedWindows.compactMap(\.platformWindowNumber)).count == 3 &&
                       Set(savedWindows.compactMap(\.platformSessionID)).count == 1,
                       "CG numbers: " + savedWindows.map { $0.platformWindowNumber.map(String.init) ?? "missing" }.joined(separator: ", ") +
                       ". Missing or ambiguous CG associations are a failure, never a skipped cold-start check.")
            var presentationRequests = 0
            model.onBeforeArrangement = { presentationRequests += 1 }

            // An unbound foreground window must not become the final focus
            // target. The controller should choose the first bound window.
            stage = "Focus the unbound disposable window before arrangement"
            try service.activate(unbound)
            try await service.confirmActivation(unbound)
            try record(stage, service.currentWindow()?.id == unbound.id)

            stage = "Arrange through ApplicationController.toggleArrangement"
            model.toggleArrangement()
            try await waitUntil(label: "Controller arrangement presentation", timeout: 15) { !model.isPresentingArrangement }
            try record(stage, model.isArranged && model.arrangementWarning == nil && presentationRequests == 1,
                       model.arrangementFailure ?? model.arrangementWarning ?? model.notice ?? "")
            guard let expectedArea = model.arrangementAreas[bound[0].id] else {
                throw Failure("Controller did not retain the first bound window's planned work area.")
            }
            // A display's visible work area may change while the Dock animates.
            // Validate geometry against the controller's sampled plan, and
            // validate display ownership separately by physical display ID.
            let targets = LayoutEngine.frames(count: bound.count, workArea: expectedArea, gap: 12, mode: .balanced)
            try record("Controller plans a two-row grid in one sampled display area", bound.indices.allSatisfy { index in
                model.arrangementAreas[bound[index].id] == expectedArea && model.arrangementTargets[bound[index].id] == targets[index]
            }, "Expected area: " + describe(expectedArea))
            var arranged: [WindowPlacement] = []
            for (index, window) in bound.enumerated() {
                stage = "Verify arranged fixture \(index + 1)"
                func diagnostics(_ observed: WindowPlacement?) -> String {
                    let baselineArea = workAreas[index]
                    let currentDisplay = service.arrangementDisplay(for: window)
                    let currentArea = currentDisplay.workArea
                    let contained = observed.map { String(inside($0.frame, area: baselineArea)) } ?? "unavailable"
                    let insidePlan = observed.map { String(inside($0.frame, area: expectedArea)) } ?? "unavailable"
                    let fits = observed.map { String(WindowFrameFit.accepts($0.frame, target: targets[index])) } ?? "unavailable"
                    return "baselineArea=\(describe(baselineArea)); currentArea=\(describe(currentArea)); " +
                        "inside=\(contained); areaEquality=\(currentArea == baselineArea); " +
                        "plannedArea=\(describe(expectedArea)); insidePlan=\(insidePlan); " +
                        "baselineDisplay=\(baselineDisplays[index].id); currentDisplay=\(currentDisplay.id); " +
                        "samePhysicalDisplay=\(currentDisplay.id == baselineDisplays[index].id); " +
                        "target=\(describe(targets[index])); fitsTarget=\(fits)"
                }
                let current = try await placement(of: window, service: service, label: stage, diagnostics: diagnostics) {
                    !$0.minimized && WindowFrameFit.accepts($0.frame, target: targets[index])
                }
                arranged.append(current)
                try record(stage, inside(current.frame, area: expectedArea) &&
                           service.arrangementDisplay(for: window).id == baselineDisplays[index].id,
                           describe(current) + "; " + diagnostics(current))
            }
            try record("Arranged fixture frames do not overlap", arranged.indices.allSatisfy { left in
                arranged.indices.allSatisfy { right in left >= right || !overlaps(arranged[left].frame, arranged[right].frame) }
            })
            let tolerance = WindowFrameFit.edgeTolerance
            let widths = arranged.map { $0.frame.width }
            let topGap = arranged[1].frame.x - arranged[0].frame.x - arranged[0].frame.width
            let rowGap = arranged[2].frame.y - arranged[0].frame.y - arranged[0].frame.height
            try record("Three windows form two upper cells and one full-width lower cell",
                       abs(widths[0] - widths[1]) <= tolerance &&
                       abs(widths[0] + widths[1] + 12 - expectedArea.width) <= tolerance &&
                       abs(widths[2] - expectedArea.width) <= tolerance &&
                       abs(topGap - 12) <= tolerance && abs(rowGap - 12) <= tolerance &&
                       abs(arranged[0].frame.x - expectedArea.x) <= tolerance &&
                       abs(arranged[1].frame.y - arranged[0].frame.y) <= tolerance &&
                       abs(arranged[2].frame.x - expectedArea.x) <= tolerance &&
                       abs(arranged[2].frame.x + arranged[2].frame.width - expectedArea.x - expectedArea.width) <= tolerance &&
                       abs(arranged[2].frame.y + arranged[2].frame.height - expectedArea.y - expectedArea.height) <= tolerance,
                       "Widths: \(widths); top gap: \(topGap); row gap: \(rowGap); sampled area: \(describe(expectedArea)).")
            stage = "Verify final foreground is the expected exact bound window"
            try await service.confirmActivation(bound[0])
            try record(stage, service.currentWindow()?.id == bound[0].id)
            let untouchedAfter = try service.capturePlacement(unbound)
            try record("Unbound fixture keeps its placement and minimized state",
                       WindowFrameFit.restored(untouchedAfter.frame, before: untouchedPlacement.frame) &&
                       untouchedAfter.minimized == untouchedPlacement.minimized)

            stage = "Restore through ApplicationController.toggleArrangement"
            model.toggleArrangement()
            try await waitUntil(label: "Controller restore completion", timeout: 5) { !model.isPresentingArrangement }
            try record(stage, !model.isArranged && model.arrangementWarning == nil, model.arrangementWarning ?? model.notice ?? "")
            for (index, snapshot) in baseline.enumerated() {
                stage = "Verify original placement and minimized state \(index + 1)"
                let restored = try await placement(of: snapshot.window, service: service, label: stage) {
                    $0.minimized == snapshot.placement.minimized && WindowFrameFit.restored($0.frame, before: snapshot.placement.frame)
                }
                try record(stage, true, describe(restored))
            }
            stage = "Capture a moved disposable window and restore its pre-drag position"
            var droppedFrame = untouchedPlacement.frame
            droppedFrame.x += 90
            droppedFrame.y += 40
            try service.setFrame(droppedFrame, for: unbound)
            let captured = model.captureDraggedWindow(unbound, originalFrame: untouchedPlacement.frame, to: 5)
            let afterCapture = try await placement(of: unbound, service: service, label: stage) {
                WindowFrameFit.restored($0.frame, before: untouchedPlacement.frame) && $0.minimized == model.windowBehavior.minimizeOnCapture
            }
            try record(stage, captured && model.workspace.slots[4].window?.id == unbound.id &&
                       WindowFrameFit.restored(afterCapture.frame, before: untouchedPlacement.frame) &&
                       afterCapture.minimized == model.windowBehavior.minimizeOnCapture,
                       model.taskOperationFailure ?? model.notice ?? "")
            let removed = model.remove(5, expectedTaskID: model.workspace.slots[4].id)
            let afterRemove = try await placement(of: unbound, service: service, label: "Restore captured fixture after removal") {
                $0.minimized == untouchedPlacement.minimized && WindowFrameFit.restored($0.frame, before: untouchedPlacement.frame)
            }
            try record("Removing the captured task leaves its exact window open at the restored position",
                       removed && service.isAvailable(unbound) && model.workspace.slots[4].window == nil &&
                       afterRemove.minimized == untouchedPlacement.minimized)

            // Leave a second arrangement journal on disk without a graceful
            // controller shutdown. Only the three already-verified helper
            // identities can enter this simulated cold-start recovery.
            let coldBaseline = try bound.map { Snapshot(window: $0, placement: try service.capturePlacement($0)) }
            let expectedTasks = model.workspace.slots
            let fixturePIDs = Set(helpers.map(\.processIdentifier))
            let journalStore = RecoveryJournalStore(root: temporaryRoot)
            stage = "Persist a fixture-only layout journal before simulated cold startup"
            model.toggleArrangement()
            try await waitUntil(label: "Arrange fixtures for cold-start recovery", timeout: 15) { !model.isPresentingArrangement }
            let journal = try journalStore.load()
            let expectedTaskIDs = Set(expectedTasks.filter { $0.window != nil }.map(\.id))
            try record(stage, model.isArranged && model.arrangementWarning == nil && journal.warning == nil &&
                       journal.records.count == 3 && Set(journal.records.compactMap(\.taskID)) == expectedTaskIDs &&
                       journal.records.allSatisfy { item in
                           item.kind == .layout && fixturePIDs.contains(item.window.processID) &&
                           coldBaseline.contains { $0.window.id == item.window.id && $0.placement.frame == item.frame && $0.placement.minimized == item.minimized }
                       }, model.arrangementFailure ?? model.arrangementWarning ?? model.notice ?? "")
            let journalBytes = try Data(contentsOf: journalStore.journalURL)

            stage = "Cold WindowService discovers fresh AX UUIDs for the same fixture CG windows"
            let coldService = WindowService()
            let freshWindows = helpers.flatMap { coldService.windows(for: $0.processIdentifier) }
            try record(stage, savedWindows.allSatisfy { saved in
                let matches = freshWindows.filter { $0.refersToSamePlatformWindow(as: saved) }
                return matches.count == 1 && matches[0].id != saved.id
            }, "A new WindowService must prove each saved CG token independently; no old AX cache is passed to it.")

            stage = "Cold controller reconnects original task IDs and metadata without global shortcuts"
            let coldModel = ApplicationController(windowService: coldService, store: store, startsMonitoring: false, preferences: preferences)
            controller = coldModel
            try record(stage, coldModel.workspace.slots == expectedTasks &&
                       coldModel.connectedWindows == Set(savedWindows.map(\.id)) && coldModel.registeredTaskShortcuts.isEmpty &&
                       savedWindows.allSatisfy { coldService.isAvailable($0) }, coldModel.notice ?? "")

            stage = "Cold startup retains pending layout records without changing their journal"
            try record(stage, coldModel.recoveryCount == 3 && coldModel.recoveryWarning != nil && !coldModel.isArranged &&
                       (try Data(contentsOf: journalStore.journalURL)) == journalBytes,
                       "The old controller was not asked to quit; recovery comes from the same persistent store and journal.")
            coldModel.restorePendingRecovery()
            for (index, snapshot) in coldBaseline.enumerated() {
                stage = "Recover cold-start original fixture placement \(index + 1)"
                let restored = try await placement(of: snapshot.window, service: coldService, label: stage) {
                    $0.minimized == snapshot.placement.minimized && WindowFrameFit.restored($0.frame, before: snapshot.placement.frame)
                }
                try record(stage, true, describe(restored))
            }
            stage = "Cold recovery clears the journal and preserves tasks and the unbound fixture"
            let untouchedAfterRecovery = try service.capturePlacement(unbound)
            try record(stage, coldModel.recoveryCount == 0 && coldModel.recoveryWarning == nil &&
                       !FileManager.default.fileExists(atPath: journalStore.journalURL.path) &&
                       (try journalStore.load()).records.isEmpty && coldModel.workspace.slots == expectedTasks &&
                       WindowFrameFit.restored(untouchedAfterRecovery.frame, before: untouchedPlacement.frame) &&
                       untouchedAfterRecovery.minimized == untouchedPlacement.minimized,
                       coldModel.recoveryWarning ?? coldModel.notice ?? "")
            status = "passed"
            exitCode = 0
        } catch {
            checks.append(Check(name: stage, passed: false, detail: error.localizedDescription))
            if !service.isTrusted { status = "requires-permission"; exitCode = 2 }
        }

        // Run cleanup before writing the report so its status includes recovery
        // failures, even when setup or the controller validation failed early.
        if let controller {
            let errors = controller.prepareToQuit()
            checks.append(Check(name: "Controller cleanup", passed: errors.isEmpty, detail: errors.joined(separator: "; ")))
            if !errors.isEmpty, exitCode == 0 { status = "failed"; exitCode = 1 }
        }
        controller = nil
        for (index, snapshot) in originals.enumerated() {
            do {
                try service.restore(snapshot.window, to: snapshot.placement)
                _ = try await placement(of: snapshot.window, service: service, label: "Final fixture recovery") {
                    $0.minimized == snapshot.placement.minimized && WindowFrameFit.restored($0.frame, before: snapshot.placement.frame)
                }
                checks.append(Check(name: "Recover initial fixture state \(index + 1)", passed: true, detail: ""))
            } catch {
                checks.append(Check(name: "Recover initial fixture state \(index + 1)", passed: false, detail: error.localizedDescription))
                if exitCode == 0 { status = service.isTrusted ? "failed" : "requires-permission"; exitCode = service.isTrusted ? 1 : 2 }
            }
        }
        for helper in helpers where !helper.isTerminated { helper.terminate() }
        try? await waitUntil(label: "Terminate disposable helpers", timeout: 3) { helpers.allSatisfy(\.isTerminated) }
        for helper in helpers where !helper.isTerminated { helper.forceTerminate() }
        try? await waitUntil(label: "Force terminate disposable helpers", timeout: 2) { helpers.allSatisfy(\.isTerminated) }
        let terminated = helpers.allSatisfy(\.isTerminated)
        if !helpers.isEmpty {
            checks.append(Check(name: "Terminate both disposable helper processes", passed: terminated, detail: ""))
            if !terminated, exitCode == 0 { status = "failed"; exitCode = 1 }
        }
        preferences?.removePersistentDomain(forName: suiteName)
        do {
            if FileManager.default.fileExists(atPath: temporaryRoot.path) { try FileManager.default.removeItem(at: temporaryRoot) }
            checks.append(Check(name: "Remove isolated workspace and preferences", passed: true, detail: ""))
        } catch {
            checks.append(Check(name: "Remove isolated workspace and preferences", passed: false, detail: error.localizedDescription))
            if exitCode == 0 { status = "failed"; exitCode = 1 }
        }

        let report = Report(timestamp: Date(), status: status, checks: checks,
            limitation: "Three disposable AppKit windows on one display, across two helper processes. Exercises the actual controller, a minimized window, presentation focus, capture parking, cold WindowService/Controller reconnection from persistent CG tokens, and pending-journal restoration. A simulated cold start discards access to the old AX cache without terminating this validation process. Does not validate third-party apps, multiple-display grouping, Spaces, full screen, UI occlusion, or physical Option-number input.")
        do {
            let url = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: url, options: .atomic)
            print("macOS controller arrangement validation: \(status). Report: \(url.path)")
            return exitCode
        } catch {
            fputs("Cannot write controller arrangement validation report: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func discoverWindows(process: NSRunningApplication, service: WindowService) async throws -> [WindowIdentity] {
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + 8
        var found: [WindowIdentity] = []
        var tokenCount = 0
        while !process.isTerminated && ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            found = service.windows(for: process.processIdentifier).sorted { $0.title < $1.title }
            tokenCount = found.filter {
                ($0.platformWindowNumber ?? 0) != 0 && $0.platformSessionID?.isEmpty == false &&
                    $0.processStartedAt?.timeIntervalSince1970.isFinite == true
            }.count
            if found.count == 2 && tokenCount == 2 { break }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(min(0.1, remaining) * 1_000_000_000)) }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        guard found.count == 2, tokenCount == 2, !process.isTerminated, elapsed <= 8 else {
            let detail = String(format: "pid=%d; fixture.terminated=%@; discoveredCount=%d; tokenCount=%d; elapsed=%.3fs",
                process.processIdentifier, String(process.isTerminated), found.count, tokenCount, elapsed)
            throw Failure("Discover fixture windows failed: " + detail)
        }
        return found
    }

    private static func placement(of window: WindowIdentity, service: WindowService, label: String,
                                  diagnostics: ((WindowPlacement?) -> String)? = nil,
                                  matches: (WindowPlacement) -> Bool) async throws -> WindowPlacement {
        var observed: WindowPlacement?
        var lastError: String?
        do {
            try await waitUntil(label: label, timeout: 4) {
                do { observed = try service.capturePlacement(window); return matches(observed!) }
                catch { lastError = error.localizedDescription; return false }
            }
        } catch {
            throw Failure(label + ": " + (observed.map(describe) ?? lastError ?? error.localizedDescription) +
                          (diagnostics.map { "; " + $0(observed) } ?? ""))
        }
        return observed!
    }

    private static func waitUntil(label: String, timeout: TimeInterval, condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            if condition(), ProcessInfo.processInfo.systemUptime <= deadline { return }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(min(0.1, remaining) * 1_000_000_000)) }
        }
        throw Failure(label + " timed out.")
    }

    private static func inside(_ frame: WindowFrame, area: WindowFrame) -> Bool {
        let tolerance = WindowFrameFit.edgeTolerance
        return frame.x >= area.x - tolerance && frame.y >= area.y - tolerance &&
            frame.x + frame.width <= area.x + area.width + tolerance && frame.y + frame.height <= area.y + area.height + tolerance
    }

    private static func overlaps(_ a: WindowFrame, _ b: WindowFrame) -> Bool {
        min(a.x + a.width, b.x + b.width) - max(a.x, b.x) > 0.5 &&
            min(a.y + a.height, b.y + b.height) - max(a.y, b.y) > 0.5
    }

    private static func describe(_ placement: WindowPlacement) -> String {
        describe(placement.frame) + "; minimized=\(placement.minimized)"
    }

    private static func describe(_ frame: WindowFrame) -> String {
        String(format: "(%.1f, %.1f) %.1f × %.1f pt", frame.x, frame.y, frame.width, frame.height)
    }
}
