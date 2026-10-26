import Foundation
import Carbon
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class ApplicationControllerTests: XCTestCase {
    @MainActor
    func testManualReconnectImmediatelyUpdatesConnectionCountWithoutChangingMetadata() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let before = context.controller.workspace
        let savedBytes = try Data(contentsOf: context.store.stateFile)
        context.service.temporarilyUnavailable.formUnion(context.boundWindows.map(\.id))
        context.controller.refreshConnections()
        XCTAssertEqual(context.controller.connectedCount, 0)
        context.service.reconnectAttempts = []
        for window in context.boundWindows { context.service.reconnectResults[window.id] = window }

        context.controller.reconnectExistingTasks()

        XCTAssertEqual(context.controller.connectedCount, 2,
                       "A successful AX reconnection must publish immediately even when metadata is unchanged.")
        XCTAssertEqual(context.controller.connectedWindows, Set(context.boundWindows.map(\.id)))
        XCTAssertEqual(context.service.reconnectAttempts, context.boundWindows.map(\.id))
        XCTAssertTrue(context.service.temporarilyUnavailable.isEmpty)
        XCTAssertEqual(context.controller.workspace, before)
        XCTAssertEqual(try Data(contentsOf: context.store.stateFile), savedBytes)
    }

    @MainActor
    func testPartialManualReconnectRetainsBothTasksAndTheirRecoveryAndLaunchRecords() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        context.controller.toggleArrangement()
        XCTAssertTrue(context.controller.isArranged)
        let before = context.controller.workspace
        let recovery = RecoveryJournalStore(root: context.root)
        let recoveryBytes = try Data(contentsOf: recovery.journalURL)
        let recoveryRecords = try recovery.load().records
        let launches = TaskLaunchRecordStore(root: context.root)
        for index in [1, 7] {
            try launches.save(launchConfiguration(context), for: before.slots[index].id)
        }
        let launchBytes = try Data(contentsOf: launches.fileURL)
        let workspaceBytes = try Data(contentsOf: context.store.stateFile)
        context.service.temporarilyUnavailable.formUnion(context.boundWindows.map(\.id))
        context.controller.refreshConnections()
        XCTAssertEqual(context.controller.connectedCount, 0)
        context.service.reconnectAttempts = []
        let recovered = context.boundWindows[0]
        let unavailable = context.boundWindows[1]
        context.service.reconnectResults[recovered.id] = recovered

        context.controller.reconnectExistingTasks()

        XCTAssertEqual(context.controller.connectedCount, 1)
        XCTAssertTrue(context.controller.isConnected(before.slots[1]))
        XCTAssertFalse(context.controller.isConnected(before.slots[7]))
        XCTAssertTrue(context.service.temporarilyUnavailable.contains(unavailable.id))
        XCTAssertEqual(context.service.reconnectAttempts, context.boundWindows.map(\.id))
        XCTAssertEqual(context.controller.workspace, before)
        XCTAssertEqual(try Data(contentsOf: context.store.stateFile), workspaceBytes)
        XCTAssertEqual(try recovery.load().records, recoveryRecords)
        XCTAssertEqual(try Data(contentsOf: recovery.journalURL), recoveryBytes)
        XCTAssertEqual(try Data(contentsOf: launches.fileURL), launchBytes)
        XCTAssertTrue(context.controller.recentTasks.isEmpty,
                      "A failed reconnection is not evidence that a task's original window closed.")
        XCTAssertTrue(context.controller.isArranged)
    }

    @MainActor
    func testManualReconnectWithoutPermissionNeverUsesQueuedResultsOrChangesTasks() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let before = context.controller.workspace
        let savedBytes = try Data(contentsOf: context.store.stateFile)
        context.service.temporarilyUnavailable.formUnion(context.boundWindows.map(\.id))
        context.service.isTrusted = false
        context.controller.refreshConnections()
        context.service.reconnectAttempts = []
        for window in context.boundWindows { context.service.reconnectResults[window.id] = window }

        context.controller.reconnectExistingTasks()

        XCTAssertTrue(context.service.reconnectAttempts.isEmpty)
        XCTAssertEqual(context.controller.connectedCount, 0)
        XCTAssertEqual(context.service.temporarilyUnavailable, Set(context.boundWindows.map(\.id)))
        XCTAssertEqual(context.controller.workspace, before)
        XCTAssertEqual(try Data(contentsOf: context.store.stateFile), savedBytes)
    }

    @MainActor
    func testUnavailableTaskReconnectsBeforeActivationAndConfirmsTheExactWindow() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let target = context.boundWindows[0]
        let before = context.controller.workspace
        context.service.temporarilyUnavailable.insert(target.id)
        context.controller.refreshConnections()
        XCTAssertEqual(context.controller.connectedCount, 1)
        context.service.asyncReconnect = { saved in
            XCTAssertEqual(saved, target)
            return target
        }

        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }

        XCTAssertEqual(context.service.asyncReconnectAttempts, [target.id])
        XCTAssertEqual(context.service.activationOrder, [target.id])
        XCTAssertEqual(context.service.confirmationAttempts, 1)
        XCTAssertEqual(context.service.focused?.id, target.id)
        XCTAssertEqual(context.controller.connectedCount, 2)
        XCTAssertEqual(context.controller.workspace, before)
        XCTAssertEqual(try context.store.load().state, before)
        XCTAssertNil(context.controller.activationFailure)
        XCTAssertNil(context.controller.pickerSlot)
    }

    @MainActor
    func testReorderingDuringReconnectCancelsTheOldActivationAndRetryFollowsTaskIdentity() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let target = context.boundWindows[0]
        let taskID = context.controller.workspace.slots[1].id
        context.service.temporarilyUnavailable.insert(target.id)
        context.service.pauseAsyncReconnect = true
        context.service.asyncReconnect = { _ in target }
        context.controller.toggleSlot(2)
        await waitUntil { context.service.asyncReconnectAttempts == [target.id] }
        XCTAssertTrue(context.service.activationOrder.isEmpty)

        XCTAssertTrue(context.controller.moveSlot(from: 2, to: 5, expectedTaskID: taskID))
        context.service.releaseAsyncReconnect()
        await waitUntil { context.service.asyncReconnectCompletions == [target.id] }

        XCTAssertNil(context.controller.activeSlot)
        XCTAssertTrue(context.service.activationOrder.isEmpty,
                      "A completion for an old slot position must never activate its replacement.")
        XCTAssertNil(context.controller.workspace.slots[1].window)
        XCTAssertEqual(context.controller.workspace.slots[4].id, taskID)
        context.controller.retryLastActivation()
        await waitUntil { context.controller.activeSlot == 5 }
        XCTAssertEqual(context.service.activationOrder, [target.id])
        XCTAssertEqual(context.service.focused?.id, target.id)
        XCTAssertEqual(try context.store.load().state.slots[4].id, taskID)
    }

    @MainActor
    func testChoosingAnotherTaskDuringReconnectPreventsLateActivation() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let delayed = context.boundWindows[0]
        let selected = context.boundWindows[1]
        context.service.temporarilyUnavailable.insert(delayed.id)
        context.service.pauseAsyncReconnect = true
        context.service.asyncReconnect = { _ in delayed }
        context.controller.toggleSlot(2)
        await waitUntil { context.service.asyncReconnectAttempts == [delayed.id] }

        context.controller.enterSlot(8)
        await waitUntil { context.controller.activeSlot == 8 }
        context.service.releaseAsyncReconnect()
        await waitUntil { context.service.asyncReconnectCompletions == [delayed.id] }

        XCTAssertEqual(context.controller.activeSlot, 8)
        XCTAssertEqual(context.service.focused?.id, selected.id)
        XCTAssertEqual(context.service.activationOrder, [selected.id],
                      "The backend deliberately completes after cancellation; the coordinator must reject it.")
        XCTAssertEqual(context.service.confirmationAttempts, 1)
        XCTAssertNil(context.controller.pickerSlot)
    }

    @MainActor
    func testReconnectErrorOffersThePickerWithoutReplacingOrRemovingTheOriginalTask() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let target = context.boundWindows[0]
        let before = context.controller.workspace
        let savedBytes = try Data(contentsOf: context.store.stateFile)
        context.service.temporarilyUnavailable.insert(target.id)
        context.controller.refreshConnections()
        context.service.asyncReconnect = { _ in throw FakeWindowError.temporary }

        context.controller.toggleSlot(2)
        await waitUntil { context.controller.pickerSlot == 2 }

        XCTAssertEqual(context.service.asyncReconnectAttempts, [target.id])
        XCTAssertTrue(context.service.activationOrder.isEmpty)
        XCTAssertEqual(context.service.confirmationAttempts, 0)
        XCTAssertNil(context.controller.activeSlot)
        XCTAssertNotNil(context.controller.activationFailure)
        XCTAssertEqual(context.controller.workspace, before)
        XCTAssertEqual(try Data(contentsOf: context.store.stateFile), savedBytes)
        XCTAssertEqual(context.controller.connectedCount, 1)
        XCTAssertTrue(context.controller.recentTasks.isEmpty)
        XCTAssertTrue(context.service.temporarilyUnavailable.contains(target.id))
    }

    @MainActor
    func testArrangementReconnectsTheUnavailableThirdWindowAndRestoresAllThree() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let third = context.service.addWindow(title: "Third task", number: 4)
        context.controller.openPicker(for: 3)
        XCTAssertTrue(context.controller.bind(third))
        let before = context.controller.workspace
        let original = context.service.placements
        let expected = Set((context.boundWindows + [third]).map(\.id))
        context.service.temporarilyUnavailable.insert(third.id)
        context.service.pauseAsyncReconnect = true
        context.service.asyncReconnect = { saved in
            XCTAssertEqual(saved.id, third.id)
            return third
        }

        context.controller.toggleArrangement()
        await waitUntil { context.service.asyncReconnectAttempts == [third.id] }
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertTrue(context.service.frameAttempts.isEmpty,
                      "The two available windows must wait until the third can join the same arrangement.")
        XCTAssertEqual(context.service.placements, original)
        context.service.releaseAsyncReconnect()
        await waitUntil { context.controller.isArranged }
        await waitUntil { !context.controller.isPresentingArrangement }

        XCTAssertEqual(Set(context.controller.arrangementTargets.keys), expected)
        XCTAssertEqual(Set(context.service.frameAttempts), expected)
        XCTAssertEqual(context.service.frameAttempts.count, 3)
        XCTAssertEqual(try RecoveryJournalStore(root: context.root).load().records.count, 3)
        XCTAssertEqual(context.controller.workspace, before)
        context.controller.toggleArrangement()
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertEqual(context.service.placements, original)
        XCTAssertEqual(Set(context.service.restoreAttempts), expected)
        XCTAssertEqual(try context.store.load().state, before)
        XCTAssertTrue(try RecoveryJournalStore(root: context.root).load().records.isEmpty)
    }

    @MainActor
    func testFailedArrangementWakeDoesNotResizeOtherWindowsOrChangeAnyBinding() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let third = context.service.addWindow(title: "Unavailable third task", number: 4)
        context.controller.openPicker(for: 3)
        XCTAssertTrue(context.controller.bind(third))
        let before = context.controller.workspace
        let savedBytes = try Data(contentsOf: context.store.stateFile)
        let original = context.service.placements
        context.service.temporarilyUnavailable.insert(third.id)
        context.service.asyncReconnect = { _ in throw FakeWindowError.temporary }

        context.controller.toggleArrangement()
        await waitUntil {
            context.service.asyncReconnectCompletions == [third.id] && context.controller.arrangementFailure != nil
        }

        XCTAssertFalse(context.controller.isArranged)
        XCTAssertTrue(context.controller.arrangementTargets.isEmpty)
        XCTAssertTrue(context.service.frameAttempts.isEmpty)
        XCTAssertTrue(context.service.restoreAttempts.isEmpty)
        XCTAssertEqual(context.service.placements, original)
        XCTAssertEqual(context.controller.workspace, before)
        XCTAssertEqual(try Data(contentsOf: context.store.stateFile), savedBytes)
        XCTAssertTrue(try RecoveryJournalStore(root: context.root).load().records.isEmpty)
        XCTAssertTrue(context.controller.recentTasks.isEmpty)
    }

    @MainActor
    func testFailedArrangementWakePreservesAnActiveToggleUntilTheUserRestoresIt() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let third = context.service.addWindow(title: "Unavailable third task", number: 4)
        context.controller.openPicker(for: 3)
        XCTAssertTrue(context.controller.bind(third))
        let target = context.boundWindows[0]
        let original = context.service.placements
        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        XCTAssertNotEqual(context.service.placements[target.id], original[target.id])
        let activated = context.service.placements
        let workspace = context.controller.workspace
        let journal = RecoveryJournalStore(root: context.root)
        let journalBytes = try Data(contentsOf: journal.journalURL)
        XCTAssertEqual(try journal.load().records.map(\.kind), [.toggle])
        context.service.temporarilyUnavailable.insert(third.id)
        context.service.asyncReconnect = { _ in throw FakeWindowError.temporary }

        context.controller.toggleArrangement()
        await waitUntil {
            context.service.asyncReconnectCompletions == [third.id] && context.controller.arrangementFailure != nil
        }

        XCTAssertFalse(context.controller.isArranged)
        XCTAssertEqual(context.service.placements, activated,
                       "A failed arrangement preflight must leave the already active task exactly as the user sees it.")
        XCTAssertTrue(context.service.restoreAttempts.isEmpty)
        XCTAssertTrue(context.service.frameAttempts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: journal.journalURL), journalBytes)
        XCTAssertEqual(context.controller.workspace, workspace)

        context.controller.toggleSlot(2)
        await waitUntil { context.service.confirmationAttempts == 2 }
        XCTAssertNil(context.controller.activeSlot)
        XCTAssertEqual(context.service.restoreAttempts, [target.id])
        XCTAssertEqual(context.service.placements, original,
                       "The original toggle shortcut must still restore the saved pre-activation placement.")
        XCTAssertTrue(try journal.load().records.isEmpty)
    }

    @MainActor
    func testChoosingAnotherTaskWhileArrangementWakesCannotResizeWindowsLater() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let third = context.service.addWindow(title: "Delayed third task", number: 4)
        context.controller.openPicker(for: 3)
        XCTAssertTrue(context.controller.bind(third))
        let before = context.controller.workspace
        let original = context.service.placements
        let selected = context.boundWindows[1]
        context.service.temporarilyUnavailable.insert(third.id)
        context.service.pauseAsyncReconnect = true
        context.service.asyncReconnect = { _ in third }
        context.controller.toggleArrangement()
        await waitUntil { context.service.asyncReconnectAttempts == [third.id] }

        context.controller.enterSlot(8)
        await waitUntil { context.controller.activeSlot == 8 }
        context.service.releaseAsyncReconnect()
        await waitUntil { context.service.asyncReconnectCompletions == [third.id] }

        XCTAssertEqual(context.controller.activeSlot, 8)
        XCTAssertEqual(context.service.focused?.id, selected.id)
        XCTAssertEqual(context.service.activationOrder, [selected.id])
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertTrue(context.controller.arrangementTargets.isEmpty)
        XCTAssertTrue(context.service.frameAttempts.isEmpty,
                      "A late wake completion must not arrange after the user chose another task.")
        XCTAssertEqual(context.service.placements, original)
        XCTAssertEqual(context.controller.workspace, before)
        let recovery = try RecoveryJournalStore(root: context.root).load().records
        XCTAssertEqual(recovery.map(\.kind), [.toggle])
        XCTAssertEqual(recovery.first?.window.id, selected.id)
    }

    @MainActor
    func testTemporaryAXFailureRetainsOnlyUnrestoredLayoutAndCanRetry() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let first = context.boundWindows[0]
        let second = context.boundWindows[1]
        let firstOriginal = context.service.placements[first.id]
        let secondOriginal = context.service.placements[second.id]

        context.controller.toggleArrangement()
        XCTAssertTrue(context.controller.isArranged)
        XCTAssertNotEqual(context.service.placements[first.id], firstOriginal)
        XCTAssertNotEqual(context.service.placements[second.id], secondOriginal)

        // An AX timeout is not evidence that the window was destroyed.
        context.service.temporarilyUnavailable.insert(first.id)
        XCTAssertFalse(context.service.isAvailable(first))
        XCTAssertFalse(context.service.isDefinitelyClosed(first))
        context.controller.toggleArrangement()
        XCTAssertTrue(context.controller.isArranged)
        XCTAssertNotNil(context.controller.notice)
        XCTAssertEqual(context.service.placements[second.id], secondOriginal)
        XCTAssertNotEqual(context.service.placements[first.id], firstOriginal)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == first.id }.count, 1)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == second.id }.count, 1)

        context.service.temporarilyUnavailable.remove(first.id)
        context.controller.toggleArrangement()
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertEqual(context.service.placements[first.id], firstOriginal)
        XCTAssertEqual(context.service.placements[second.id], secondOriginal)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == first.id }.count, 2)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == second.id }.count, 1,
                       "A successfully restored window must not be restored again.")
    }

    @MainActor
    func testConfirmedClosedWindowDoesNotKeepUnrecoverableLayoutSnapshot() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let first = context.boundWindows[0]
        let second = context.boundWindows[1]
        let secondOriginal = context.service.placements[second.id]
        context.controller.toggleArrangement()
        context.service.closed.insert(first.id)

        context.controller.toggleArrangement()
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertEqual(context.service.placements[second.id], secondOriginal)
        XCTAssertFalse(context.service.restoreAttempts.contains(first.id))
        XCTAssertTrue(context.controller.prepareToQuit().isEmpty)
    }

    @MainActor
    func testRevokedPermissionDoesNotDiscardOriginalMinimizedPlacement() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let first = context.boundWindows[0]
        let original = context.service.placements[first.id]
        XCTAssertEqual(original?.minimized, true)
        context.controller.toggleArrangement()
        XCTAssertEqual(context.service.placements[first.id]?.minimized, false)

        context.service.isTrusted = false
        context.controller.recheckPermissions()
        XCTAssertFalse(context.controller.canControlWindows)
        XCTAssertFalse(context.controller.prepareToQuit().isEmpty)
        XCTAssertTrue(context.controller.isArranged)

        context.service.isTrusted = true
        context.controller.recheckPermissions()
        context.controller.toggleArrangement()
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertEqual(context.service.placements[first.id], original)
        XCTAssertTrue(context.controller.prepareToQuit().isEmpty)
    }

    @MainActor
    func testRebindingFixedSlotPreservesUserNameAndEveryOtherSlot() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let before = context.controller.workspace
        let oldTaskID = before.slots[1].id
        let replacement = context.service.addWindow(title: "New terminal session", number: 50)
        context.service.closed.insert(context.boundWindows[0].id)
        context.controller.openPicker(for: 2)
        context.controller.bind(replacement)

        let after = context.controller.workspace
        XCTAssertEqual(after.slots[1].name, "Backend API")
        XCTAssertEqual(after.slots[1].window?.id, replacement.id)
        XCTAssertNotEqual(after.slots[1].id, oldTaskID)
        for index in after.slots.indices where index != 1 {
            XCTAssertEqual(after.slots[index], before.slots[index])
        }
        XCTAssertEqual(try context.store.load().state, after)
    }

    @MainActor
    func testFailedActivationConfirmationDoesNotMarkActiveAndRetainsRecoveryForRetry() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let target = context.boundWindows[0]
        let original = context.service.placements[target.id]
        context.service.confirmationFailure = .confirmation

        context.controller.toggleSlot(2)
        await waitUntil {
            context.service.confirmationAttempts == 1 &&
                context.controller.notice?.contains("focus_confirmation_failed") == true
        }
        XCTAssertNil(context.controller.activeSlot)
        XCTAssertEqual(context.service.placements[target.id]?.minimized, false,
                       "The fake models activation partially mutating the window before confirmation fails.")

        context.service.temporarilyUnavailable.insert(target.id)
        XCTAssertFalse(context.controller.prepareToQuit().isEmpty)
        XCTAssertNotEqual(context.service.placements[target.id], original)

        context.service.temporarilyUnavailable.remove(target.id)
        XCTAssertTrue(context.controller.prepareToQuit().isEmpty)
        XCTAssertEqual(context.service.placements[target.id], original,
                       "The original minimized placement must survive both failed confirmation and failed restore.")
    }

    @MainActor
    func testConfirmedToggleRestoresMinimizedWindowAndExactPriorFocus() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let target = context.boundWindows[0]
        let original = context.service.placements[target.id]
        let previous = context.service.focused

        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        XCTAssertEqual(context.service.focused?.id, target.id)
        XCTAssertEqual(context.service.placements[target.id]?.minimized, false)

        context.controller.toggleSlot(2)
        await waitUntil { context.service.confirmationAttempts == 2 }
        XCTAssertNil(context.controller.activeSlot)
        XCTAssertEqual(context.service.placements[target.id], original)
        XCTAssertEqual(context.service.focused?.id, previous?.id)
        XCTAssertTrue(context.controller.prepareToQuit().isEmpty)
    }

    @MainActor
    func testHookBatchPersistsBeforeAcknowledgingAndOnlyAlertsOnce() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let task = context.controller.workspace.slots[1]
        let start = Date().addingTimeInterval(-5)
        var sounds: [AudioCue] = []
        context.controller.onFeedback = { sounds.append($0) }
        for (offset, name, state) in [(0, "SessionStart", AgentState.unknown), (1, "UserPromptSubmit", .running),
                                      (2, "PermissionRequest", .waiting), (3, "PermissionRequest", .waiting)] {
            try StatusEventInbox.publish(AgentStatusEvent(taskID: task.id, state: state,
                message: name, at: start.addingTimeInterval(Double(offset)), provider: "codex",
                sessionID: "thread-a", eventName: name), root: context.root)
        }
        await context.controller.pollStatusEvents()
        let saved = try context.store.load().state
        XCTAssertEqual(saved, context.controller.workspace)
        XCTAssertEqual(saved.slots[1].agentState, .waiting)
        XCTAssertTrue(saved.slots[1].unread)
        XCTAssertTrue(saved.slots[1].integrationConnected)
        XCTAssertEqual(sounds, [.waiting])
        let pending = try await StatusEventInbox(root: context.root).read()
        XCTAssertTrue(pending.isEmpty)
        await context.controller.pollStatusEvents()
        XCTAssertEqual(sounds, [.waiting], "Polling must not replay the same alert.")
    }

    @MainActor
    func testFailedWorkspaceSaveRetainsHookForRetryWithoutFalseAlert() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let task = context.controller.workspace.slots[1]
        let originalBytes = try Data(contentsOf: context.store.stateFile)
        let event = AgentStatusEvent(taskID: task.id, state: .ready, message: "本轮已完成",
            provider: "claude", sessionID: "session-a", eventName: "Stop")
        try StatusEventInbox.publish(event, root: context.root)
        var sounds: [AudioCue] = []
        context.controller.onFeedback = { sounds.append($0) }
        try FileManager.default.removeItem(at: context.store.stateFile)
        try FileManager.default.createDirectory(at: context.store.stateFile, withIntermediateDirectories: false)
        await context.controller.pollStatusEvents()
        XCTAssertEqual(context.controller.workspace.slots[1].agentState, .unknown)
        XCTAssertNotNil(context.controller.notice)
        XCTAssertTrue(sounds.isEmpty)
        let beforeRetry = try await StatusEventInbox(root: context.root).read()
        XCTAssertEqual(beforeRetry.map(\.event.id), [event.id])
        try FileManager.default.removeItem(at: context.store.stateFile)
        try originalBytes.write(to: context.store.stateFile)
        await context.controller.pollStatusEvents()
        XCTAssertEqual(try context.store.load().state.slots[1].agentState, .ready)
        XCTAssertEqual(sounds, [.ready])
        let afterRetry = try await StatusEventInbox(root: context.root).read()
        XCTAssertTrue(afterRetry.isEmpty)
    }

    @MainActor
    func testRemovedTaskHookCannotChangeReplacementInSameSlot() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let previousID = context.controller.workspace.slots[1].id
        let replacement = context.service.addWindow(title: "Replacement", number: 60)
        context.controller.remove(2)
        context.controller.openPicker(for: 2)
        context.controller.bind(replacement)
        try StatusEventInbox.publish(AgentStatusEvent(taskID: previousID, state: .error,
            provider: "claude", sessionID: "old-session", eventName: "StopFailure"), root: context.root)
        await context.controller.pollStatusEvents()
        XCTAssertNotEqual(context.controller.workspace.slots[1].id, previousID)
        XCTAssertEqual(context.controller.workspace.slots[1].agentState, .unknown)
        XCTAssertFalse(context.controller.workspace.slots[1].unread)
        let pending = try await StatusEventInbox(root: context.root).read()
        XCTAssertTrue(pending.isEmpty)
    }

    @MainActor
    func testOnlyConfirmedTaskActivationMarksUnreadReadWithoutChangingStatus() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let taskID = context.controller.workspace.slots[1].id
        try StatusEventInbox.publish(AgentStatusEvent(taskID: taskID, state: .ready,
            provider: "claude", sessionID: "session-a", eventName: "Stop"), root: context.root)
        await context.controller.pollStatusEvents()
        context.service.confirmationFailure = .confirmation
        context.controller.toggleSlot(2)
        await waitUntil { context.controller.notice?.contains("focus_confirmation_failed") == true }
        XCTAssertTrue(context.controller.workspace.slots[1].unread)
        context.service.confirmationFailure = nil
        context.controller.toggleSlot(2) // restore the failed toggle's original placement
        await waitUntil { context.service.confirmationAttempts >= 2 }
        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        let saved = try context.store.load().state.slots[1]
        XCTAssertFalse(saved.unread)
        XCTAssertEqual(saved.agentState, .ready)
        XCTAssertTrue(saved.integrationConnected)
    }

    @MainActor
    func testDeniedWindowActionsOpenPermissionGuidanceWithoutChangingWindows() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let original = context.controller.workspace
        let placements = context.service.placements
        context.service.isTrusted = false
        context.controller.recheckPermissions()
        var permissionRequests = 0
        context.controller.onRequestPermission = { permissionRequests += 1 }
        context.controller.toggleSlot(2)
        XCTAssertEqual(permissionRequests, 1)
        XCTAssertTrue(context.controller.permissionSettingsRequested)
        XCTAssertTrue(context.controller.notice?.contains("辅助功能") == true)
        context.controller.toggleArrangement()
        XCTAssertEqual(permissionRequests, 2)
        XCTAssertEqual(context.controller.workspace, original)
        XCTAssertEqual(context.service.placements, placements)
        XCTAssertTrue(context.service.restoreAttempts.isEmpty)
    }

    @MainActor
    func testEmptySlotShortcutPresentsInventoryAndPickerInsteadOfRemainingHidden() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        var presentations = 0
        context.controller.onRequestInventory = { presentations += 1 }
        context.controller.toggleSlot(3)
        XCTAssertEqual(context.controller.pickerSlot, 3)
        XCTAssertEqual(presentations, 1)
        XCTAssertFalse(context.controller.candidates.isEmpty)
    }

    @MainActor
    func testArrangementFailureRollsBackEveryWindowAndReportsIt() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let before = context.service.placements
        context.service.frameFailures.insert(context.boundWindows[1].id)
        var dismissed = 0
        var presented = 0
        context.controller.onBeforeArrangement = { dismissed += 1 }
        context.controller.onRequestInventory = { presented += 1 }
        context.controller.toggleArrangement()
        XCTAssertEqual(context.service.placements, before)
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(presented, 1)
        XCTAssertTrue(context.controller.arrangementFailure?.contains("已恢复原布局") == true)
    }

    @MainActor
    func testFailedArrangementRollbackRetainsOnlyPendingRecovery() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let first = context.boundWindows[0]
        let second = context.boundWindows[1]
        let before = context.service.placements
        context.service.frameFailures.insert(second.id)
        context.service.restoreFailures.insert(first.id)
        context.controller.toggleArrangement()
        XCTAssertTrue(context.controller.isArranged)
        XCTAssertEqual(context.service.placements[second.id], before[second.id])
        XCTAssertNotEqual(context.service.placements[first.id], before[first.id])
        context.service.restoreFailures.removeAll()
        context.service.frameFailures.removeAll()
        context.controller.toggleArrangement()
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertEqual(context.service.placements, before)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == second.id }.count, 1)
    }

    @MainActor
    func testArrangementKeepsWindowsOnTheirOwnDisplays() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let first = context.boundWindows[0]
        let second = context.boundWindows[1]
        let left = WindowFrame(x: -1400, y: 25, width: 1400, height: 900)
        let right = WindowFrame(x: 0, y: -600, width: 1200, height: 600)
        context.service.workAreas[first.id] = left
        context.service.workAreas[second.id] = right
        context.controller.toggleArrangement()
        XCTAssertEqual(context.service.placements[first.id]?.frame, left)
        XCTAssertEqual(context.service.placements[second.id]?.frame, right)
    }

    @MainActor
    func testUnresizableWindowIsSkippedWithoutLeavingAnEmptyCell() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let first = context.boundWindows[0]
        let second = context.boundWindows[1]
        let original = context.service.placements[first.id]
        context.service.arrangementBlocks[first.id] = "不能缩放"
        context.controller.toggleArrangement()
        XCTAssertEqual(context.service.placements[first.id], original)
        XCTAssertEqual(context.service.placements[second.id]?.frame, context.service.workArea(for: second))
        XCTAssertTrue(context.controller.arrangementWarning?.contains("不能缩放") == true)
    }

    @MainActor
    func testArrangementPresentsEveryTargetAndEndsOnThePreferredBoundWindow() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        context.controller.toggleArrangement()
        await waitUntil { !context.controller.isPresentingArrangement }
        XCTAssertEqual(context.service.activationOrder, [context.boundWindows[1].id, context.boundWindows[0].id])
        XCTAssertEqual(context.service.focused?.id, context.boundWindows[0].id)
        XCTAssertEqual(context.service.confirmationAttempts, 2)
    }

    @MainActor
    func testShortcutSchemePersistsAndRebuildsBothShortcutGroups() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let suite = "OmniVibeShortcutTests-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let controller = ApplicationController(windowService: context.service, store: context.store,
            startsMonitoring: false, preferences: preferences)
        XCTAssertEqual(controller.shortcutScheme, .optionNumbers)
        var registrations = 0
        controller.onRetryWheelShortcuts = { registrations += 1 }
        controller.setShortcutScheme(.inventoryFirst)
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(preferences.string(forKey: "OmniVibe.ShortcutScheme.v1"), "inventoryFirst")
        let reloaded = ApplicationController(windowService: context.service, store: context.store,
            startsMonitoring: false, preferences: preferences)
        XCTAssertEqual(reloaded.shortcutScheme, .inventoryFirst)
        XCTAssertEqual(reloaded.shortcutLabel(.inventory), "⌥Space")
        XCTAssertTrue(reloaded.shortcutLabel(.arrange).isEmpty)
    }

    @MainActor
    func testMainLeftLayoutUsesTheFocusedBoundTaskAsPrimary() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let first = context.boundWindows[0]
        let second = context.boundWindows[1]
        context.service.focused = second
        context.controller.arrangement = .mainLeft
        context.controller.toggleArrangement()
        let primary = try XCTUnwrap(context.service.placements[second.id]?.frame)
        let secondary = try XCTUnwrap(context.service.placements[first.id]?.frame)
        XCTAssertLessThan(primary.x, secondary.x)
        XCTAssertGreaterThan(primary.width, secondary.width)
    }

    @MainActor
    func testRemovingTaskCancelsPendingArrangementPresentationBeforeItCanStealFocus() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        context.service.pauseConfirmation = true
        context.controller.toggleArrangement()
        await waitUntil { context.service.confirmationAttempts == 1 }
        context.controller.remove(2)
        context.service.pauseConfirmation = false
        try await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertFalse(context.controller.isPresentingArrangement)
        XCTAssertEqual(context.service.activationOrder, [context.boundWindows[1].id])
        XCTAssertNil(context.controller.workspace.slots[1].window)
    }

    @MainActor
    func testChangingVisibleAreaDoesNotSplitWindowsOnTheSamePhysicalDisplay() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let first = context.boundWindows[0]
        let second = context.boundWindows[1]
        let sampled = WindowFrame(x: 0, y: 33, width: 1470, height: 843)
        context.service.workAreas[first.id] = sampled
        context.service.workAreas[second.id] = WindowFrame(x: 0, y: 33, width: 1470, height: 849)
        context.service.displayIDs[first.id] = "physical-screen-1"
        context.service.displayIDs[second.id] = "physical-screen-1"
        context.controller.toggleArrangement()
        XCTAssertEqual(context.controller.arrangementAreas[first.id], sampled)
        XCTAssertEqual(context.controller.arrangementAreas[second.id], sampled)
        let left = try XCTUnwrap(context.service.placements[first.id]?.frame)
        let right = try XCTUnwrap(context.service.placements[second.id]?.frame)
        XCTAssertEqual(left.width, (sampled.width - 12) / 2)
        XCTAssertEqual(right.x - left.x - left.width, 12, accuracy: 0.001)
    }

    @MainActor
    func testDisconnectedTaskShortcutShowsReconnectPickerWithoutDroppingTheBinding() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let before = context.controller.workspace
        context.service.closed.insert(context.boundWindows[0].id)
        var presentations = 0
        context.controller.onRequestInventory = { presentations += 1 }
        context.controller.toggleSlot(2)
        XCTAssertEqual(context.controller.pickerSlot, 2)
        XCTAssertEqual(presentations, 1)
        XCTAssertEqual(context.controller.workspace, before)
        XCTAssertTrue(context.controller.notice?.contains("重新绑定") == true)
    }

    @MainActor
    func testCustomShortcutEditsAndDisabledActionsPersistAndResetIndependently() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let preferences = try isolatedShortcutPreferences()
        let controller = ApplicationController(windowService: context.service, store: context.store,
            startsMonitoring: false, preferences: preferences)
        var registrations = 0
        controller.onRetryWheelShortcuts = { registrations += 1 }
        let binding = try ShortcutBinding.recorded(action: .slot(2), physicalKeyCode: kVK_F2,
            modifiers: UInt32(controlKey), keyLabel: "F2")
        XCTAssertTrue(controller.setCustomShortcut(binding))
        XCTAssertTrue(controller.disableShortcut(.aim))
        XCTAssertEqual(registrations, 2)
        let reloaded = ApplicationController(windowService: context.service, store: context.store,
            startsMonitoring: false, preferences: preferences)
        XCTAssertEqual(reloaded.shortcutConfiguration, controller.shortcutConfiguration)
        XCTAssertEqual(reloaded.shortcutLabel(.slot(2)), "⌃F2")
        XCTAssertTrue(reloaded.shortcutLabel(.aim).isEmpty)
        XCTAssertEqual(preferences.string(forKey: "OmniVibe.ShortcutScheme.v1"), "optionNumbers")

        controller.resetShortcut(.slot(2))
        XCTAssertEqual(controller.shortcutLabel(.slot(2)), "⌥2")
        XCTAssertTrue(controller.shortcutLabel(.aim).isEmpty, "Resetting one action must preserve another action's explicit disable.")
        controller.resetAllCustomShortcuts()
        XCTAssertFalse(controller.shortcutConfiguration.isCustomized)
        XCTAssertEqual(controller.shortcutLabel(.aim), "⌥Q")
        XCTAssertEqual(registrations, 4)
    }

    @MainActor
    func testRejectedDuplicateShortcutDoesNotPersistOrRestartEitherGroup() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let preferences = try isolatedShortcutPreferences()
        let controller = ApplicationController(windowService: context.service, store: context.store,
            startsMonitoring: false, preferences: preferences)
        let first = try ShortcutBinding.recorded(action: .slot(2), physicalKeyCode: kVK_F2,
            modifiers: UInt32(controlKey), keyLabel: "F2")
        XCTAssertTrue(controller.setCustomShortcut(first))
        let before = controller.shortcutConfiguration
        let saved = try XCTUnwrap(preferences.data(forKey: "OmniVibe.ShortcutConfiguration.v1"))
        var registrations = 0
        controller.onRetryWheelShortcuts = { registrations += 1 }
        let duplicate = try ShortcutBinding.recorded(action: .inventory, physicalKeyCode: kVK_F2,
            modifiers: UInt32(controlKey), keyLabel: "F2")
        XCTAssertFalse(controller.setCustomShortcut(duplicate))
        XCTAssertNotNil(controller.shortcutEditError)
        XCTAssertEqual(controller.shortcutConfiguration, before)
        XCTAssertEqual(preferences.data(forKey: "OmniVibe.ShortcutConfiguration.v1"), saved)
        XCTAssertEqual(registrations, 0)
    }

    @MainActor
    func testShortcutRecordingPausesIdempotentlyAndDefersReactivationUntilRecordingEnds() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let preferences = try isolatedShortcutPreferences()
        let controller = ApplicationController(windowService: context.service, store: context.store,
            startsMonitoring: false, preferences: preferences)
        var suspensions = 0, resumptions = 0
        controller.onSuspendWheelShortcuts = { suspensions += 1 }
        controller.onRetryWheelShortcuts = { resumptions += 1 }
        controller.beginShortcutRecording()
        controller.beginShortcutRecording()
        XCTAssertTrue(controller.isRecordingShortcut)
        XCTAssertEqual(suspensions, 1)
        controller.retryShortcuts()
        controller.recheckPermissions()
        let binding = try ShortcutBinding.recorded(action: .inventory, physicalKeyCode: kVK_F3,
            modifiers: UInt32(optionKey), keyLabel: "F3")
        XCTAssertTrue(controller.setCustomShortcut(binding))
        XCTAssertEqual(resumptions, 0, "Saving or retrying while recording must not consume the next recorded key.")
        XCTAssertTrue(controller.registeredTaskShortcuts.isEmpty)
        let persisted = try JSONDecoder().decode(ShortcutConfiguration.self,
            from: XCTUnwrap(preferences.data(forKey: "OmniVibe.ShortcutConfiguration.v1")))
        XCTAssertEqual(persisted.binding(for: .inventory), binding)
        controller.endShortcutRecording()
        controller.endShortcutRecording()
        XCTAssertFalse(controller.isRecordingShortcut)
        XCTAssertEqual(resumptions, 1)
    }

    @MainActor
    func testEndingRecordingDuringQuitDoesNotRestartGlobalShortcuts() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let controller = context.controller
        var resumptions = 0
        controller.onRetryWheelShortcuts = { resumptions += 1 }
        controller.beginShortcutRecording()
        XCTAssertTrue(controller.prepareToQuit().isEmpty)
        controller.endShortcutRecording()
        XCTAssertFalse(controller.isRecordingShortcut)
        XCTAssertEqual(resumptions, 0)
    }

    @MainActor
    func testExpectedTaskIDRejectsStaleRemoveAfterAnotherTaskMovesIntoThatNumber() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let firstID = context.controller.workspace.slots[1].id
        let previouslyAtEight = context.controller.workspace.slots[7].id
        XCTAssertTrue(context.controller.reorderSlot(from: 2, to: 8, expectedTaskID: firstID))
        let before = context.controller.workspace
        let persisted = try Data(contentsOf: context.store.stateFile)
        let placements = context.service.placements
        XCTAssertFalse(context.controller.remove(8, expectedTaskID: previouslyAtEight))
        XCTAssertEqual(context.controller.workspace, before)
        XCTAssertEqual(context.controller.workspace.slots[7].id, firstID)
        XCTAssertEqual(try Data(contentsOf: context.store.stateFile), persisted)
        XCTAssertEqual(context.service.placements, placements)
        XCTAssertTrue(context.service.restoreAttempts.isEmpty)
        XCTAssertTrue(context.controller.taskOperationFailure?.contains("顺序已经变化") == true)
    }

    @MainActor
    func testReorderCarriesActiveAndModalReferencesAndToggleRecoveryWithTaskIdentity() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let controller = context.controller
        let original = try XCTUnwrap(context.service.placements[context.boundWindows[0].id])
        let previousFocus = context.service.focused
        let firstID = controller.workspace.slots[1].id
        let secondID = controller.workspace.slots[7].id
        controller.toggleSlot(2)
        await waitUntil { controller.activeSlot == 2 }
        controller.pickerSlot = 2
        controller.renameSlot = 8
        controller.renameText = "unfinished name"
        controller.integrationSlot = 2
        var preparedNumbers: [UUID: Int] = [:]
        controller.onPrepareSlotOrdering = { slots in
            preparedNumbers = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0.number) })
        }
        XCTAssertTrue(controller.reorderSlot(from: 2, to: 8, expectedTaskID: firstID))
        XCTAssertEqual(preparedNumbers[firstID], 2, "Appearance preparation must receive the original numbers.")
        XCTAssertEqual(preparedNumbers[secondID], 8)
        XCTAssertEqual(controller.activeSlot, 8)
        XCTAssertEqual(controller.pickerSlot, 8)
        XCTAssertEqual(controller.renameSlot, 7)
        XCTAssertEqual(controller.integrationSlot, 8)
        XCTAssertEqual(controller.renameText, "unfinished name")
        XCTAssertEqual(controller.workspace.slots[7].id, firstID)
        XCTAssertEqual(controller.workspace.slots[6].id, secondID)
        XCTAssertEqual(try context.store.load().state, controller.workspace)

        controller.toggleSlot(8)
        XCTAssertEqual(context.service.placements[context.boundWindows[0].id], original)
        XCTAssertEqual(context.service.focused?.id, previousFocus?.id)
        XCTAssertNil(controller.activeSlot)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == context.boundWindows[0].id }.count, 1)
    }

    @MainActor
    func testPendingActivationCannotPublishOldSlotAfterReorderAndToggleStillRestores() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let controller = context.controller
        let taskID = controller.workspace.slots[1].id
        let original = context.service.placements[context.boundWindows[0].id]
        context.service.pauseConfirmation = true
        controller.toggleSlot(2)
        await waitUntil { context.service.confirmationAttempts == 1 }
        XCTAssertTrue(controller.reorderSlot(from: 2, to: 8, expectedTaskID: taskID))
        context.service.pauseConfirmation = false
        try await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertNil(controller.activeSlot)
        XCTAssertEqual(controller.workspace.slots[7].id, taskID)
        controller.toggleSlot(8)
        XCTAssertEqual(context.service.placements[context.boundWindows[0].id], original)
    }

    @MainActor
    func testAppearancePreparationFailureLeavesOrderPersistenceAndRuntimeReferencesIntact() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let controller = context.controller
        controller.toggleSlot(2)
        await waitUntil { controller.activeSlot == 2 }
        controller.pickerSlot = 2
        controller.renameSlot = 8
        controller.integrationSlot = 2
        let before = controller.workspace
        let persisted = try Data(contentsOf: context.store.stateFile)
        controller.onPrepareSlotOrdering = { _ in throw FakeWindowError.temporary }
        XCTAssertFalse(controller.reorderSlot(from: 2, to: 8, expectedTaskID: before.slots[1].id))
        XCTAssertEqual(controller.workspace, before)
        XCTAssertEqual(try Data(contentsOf: context.store.stateFile), persisted)
        XCTAssertEqual(controller.activeSlot, 2)
        XCTAssertEqual(controller.pickerSlot, 2)
        XCTAssertEqual(controller.renameSlot, 8)
        XCTAssertEqual(controller.integrationSlot, 2)
        XCTAssertTrue(controller.taskOperationFailure?.contains("test_temporary_ax_failure") == true)
        controller.toggleSlot(2)
        XCTAssertEqual(context.service.placements[context.boundWindows[0].id]?.minimized, true)
    }

    @MainActor
    func testRemoveKeepsEveryTaskWhenLayoutRecoveryFailsAndCanRetryWithoutRestoringSuccessfulWindowsTwice() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let controller = context.controller
        let before = controller.workspace
        let originalPlacements = context.service.placements
        let first = context.boundWindows[0]
        let second = context.boundWindows[1]
        controller.toggleArrangement()
        controller.pickerSlot = 2
        controller.renameSlot = 2
        controller.integrationSlot = 8
        context.service.restoreFailures.insert(second.id)
        XCTAssertFalse(controller.remove(2, expectedTaskID: before.slots[1].id))
        XCTAssertEqual(controller.workspace, before)
        XCTAssertEqual(try context.store.load().state, before)
        XCTAssertTrue(controller.isArranged)
        XCTAssertEqual(controller.pickerSlot, 2)
        XCTAssertEqual(controller.renameSlot, 2)
        XCTAssertEqual(controller.integrationSlot, 8)
        XCTAssertTrue(controller.taskOperationFailure?.contains("任务仍保留") == true)
        XCTAssertEqual(context.service.placements[first.id], originalPlacements[first.id])

        context.service.restoreFailures.removeAll()
        XCTAssertTrue(controller.remove(2, expectedTaskID: before.slots[1].id))
        XCTAssertNil(controller.workspace.slots[1].window)
        XCTAssertEqual(controller.workspace.slots[7], before.slots[7])
        XCTAssertFalse(controller.isArranged)
        XCTAssertNil(controller.pickerSlot)
        XCTAssertNil(controller.renameSlot)
        XCTAssertEqual(controller.integrationSlot, 8)
        XCTAssertEqual(context.service.placements, originalPlacements)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == first.id }.count, 1)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == second.id }.count, 2)
        XCTAssertTrue(context.service.isAvailable(first), "Removing a task must leave its application window alive.")
        XCTAssertEqual(try context.store.load().state, controller.workspace)
    }

    @MainActor
    func testArrangeThenToggleThenRemoveSameTaskRestoresItsPreArrangementPlacement() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let original = context.service.placements
        let taskID = context.controller.workspace.slots[1].id
        context.controller.toggleArrangement()
        await waitUntil { !context.controller.isPresentingArrangement }
        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        XCTAssertNotEqual(context.service.placements[context.boundWindows[0].id], original[context.boundWindows[0].id])

        XCTAssertTrue(context.controller.remove(2, expectedTaskID: taskID))
        XCTAssertEqual(context.service.placements, original)
        XCTAssertNil(context.controller.workspace.slots[1].window)
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertNil(context.controller.activeSlot)
        XCTAssertTrue(context.controller.prepareToQuit().isEmpty)
        XCTAssertEqual(context.service.placements, original, "Quit must not replay a stale snapshot of the arranged frame.")
    }

    @MainActor
    func testArrangeThenToggleThenRemoveOtherTaskConsumesToggleWithoutReplayingArrangedFrame() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let original = context.service.placements
        let firstTask = context.controller.workspace.slots[1]
        let secondID = context.controller.workspace.slots[7].id
        context.controller.toggleArrangement()
        await waitUntil { !context.controller.isPresentingArrangement }
        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }

        XCTAssertTrue(context.controller.remove(8, expectedTaskID: secondID))
        XCTAssertEqual(context.controller.workspace.slots[1], firstTask)
        XCTAssertNil(context.controller.workspace.slots[7].window)
        XCTAssertEqual(context.service.placements, original)
        XCTAssertNil(context.controller.activeSlot, "The surviving task was restored, so it must not remain presented as toggled active.")
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertTrue(context.controller.prepareToQuit().isEmpty)
        XCTAssertEqual(context.service.placements, original)
    }

    @MainActor
    func testArrangeThenToggleThenMoveRestoresPreArrangementBeforeMovingTaskIdentity() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let original = context.service.placements
        let firstTask = context.controller.workspace.slots[1]
        context.controller.toggleArrangement()
        await waitUntil { !context.controller.isPresentingArrangement }
        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }

        XCTAssertTrue(context.controller.moveSlot(from: 2, to: 5, expectedTaskID: firstTask.id))
        XCTAssertNil(context.controller.workspace.slots[1].window)
        XCTAssertEqual(context.controller.workspace.slots[4].id, firstTask.id)
        XCTAssertEqual(context.controller.workspace.slots[4].name, firstTask.name)
        XCTAssertEqual(context.service.placements, original)
        XCTAssertNil(context.controller.activeSlot)
        XCTAssertFalse(context.controller.isArranged)
        XCTAssertTrue(context.controller.prepareToQuit().isEmpty)
        XCTAssertEqual(context.service.placements, original)
    }

    @MainActor
    func testToggleRecoveryFailureBeforeRemoveRetainsBothRecoveryLayersAndBindingForRetry() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let controller = context.controller
        let before = controller.workspace
        let original = context.service.placements
        let first = context.boundWindows[0]
        let second = context.boundWindows[1]
        controller.toggleArrangement()
        await waitUntil { !controller.isPresentingArrangement }
        controller.toggleSlot(2)
        await waitUntil { controller.activeSlot == 2 }
        let arranged = context.service.placements
        let persisted = try Data(contentsOf: context.store.stateFile)
        context.service.restoreFailures.insert(first.id)

        XCTAssertFalse(controller.remove(2, expectedTaskID: before.slots[1].id))
        XCTAssertEqual(controller.workspace, before)
        XCTAssertEqual(try Data(contentsOf: context.store.stateFile), persisted)
        XCTAssertEqual(context.service.placements, arranged)
        XCTAssertTrue(controller.isArranged)
        XCTAssertEqual(controller.activeSlot, 2)
        XCTAssertEqual(context.service.restoreAttempts, [first.id], "Layout restoration must wait until toggle recovery succeeds.")

        context.service.restoreFailures.removeAll()
        XCTAssertTrue(controller.remove(2, expectedTaskID: before.slots[1].id))
        XCTAssertNil(controller.workspace.slots[1].window)
        XCTAssertEqual(context.service.placements, original)
        XCTAssertFalse(controller.isArranged)
        XCTAssertNil(controller.activeSlot)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == first.id }.count, 3,
            "Retry restores the arranged toggle baseline, then the original pre-arrangement placement.")
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == second.id }.count, 1)
    }

    @MainActor
    func testSameTaskShortcutFromManagerReentersBeforeItCanRestorePriorWindow() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let original = context.service.placements[context.boundWindows[0].id]
        var dismissals = 0
        context.controller.onBeforeTaskActivation = { dismissals += 1 }
        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        context.service.focused = nil // OmniVibe's own windows are excluded.
        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        XCTAssertEqual(context.service.focused?.id, context.boundWindows[0].id)
        XCTAssertFalse(context.service.placements[context.boundWindows[0].id]!.minimized)
        XCTAssertTrue(context.service.restoreAttempts.isEmpty)
        XCTAssertEqual(dismissals, 2)
        context.controller.toggleSlot(2)
        XCTAssertEqual(context.service.placements[context.boundWindows[0].id], original)
    }

    @MainActor
    func testDraggingCaptureRestoresOriginalFrameBeforeSavingOnlyTheChosenBinding() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let window = try XCTUnwrap(context.service.focused)
        let original = try XCTUnwrap(context.service.placements[window.id])
        let before = context.controller.workspace
        context.service.placements[window.id]?.frame.x = 1300
        context.service.placements[window.id]?.frame.y = 420
        XCTAssertTrue(context.controller.captureDraggedWindow(window, originalFrame: original.frame, to: 3))
        XCTAssertEqual(context.service.placements[window.id], original)
        XCTAssertEqual(context.controller.workspace.slots[2].window?.id, window.id)
        XCTAssertEqual(context.controller.workspace.slots[1], before.slots[1])
        XCTAssertEqual(context.controller.workspace.slots[7], before.slots[7])
        XCTAssertEqual(try context.store.load().state, context.controller.workspace)
    }

    @MainActor
    func testExplicitInventoryEntryNeverTogglesTheTaskBackOut() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        context.controller.enterSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        context.controller.enterSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        XCTAssertTrue(context.service.restoreAttempts.isEmpty)
        XCTAssertEqual(context.service.activationOrder, [context.boundWindows[0].id, context.boundWindows[0].id])
        context.controller.managementWindowIsActive = { true }
        context.controller.toggleSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        XCTAssertTrue(context.service.restoreAttempts.isEmpty)
    }

    @MainActor
    func testDraggingCaptureRecoveryFailureDoesNotSaveAParkedWindow() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let window = try XCTUnwrap(context.service.focused)
        let original = try XCTUnwrap(context.service.placements[window.id])
        let before = context.controller.workspace
        context.service.restoreFailures.insert(window.id)
        XCTAssertFalse(context.controller.captureDraggedWindow(window, originalFrame: original.frame, to: 3))
        XCTAssertEqual(context.controller.workspace, before)
        XCTAssertEqual(try context.store.load().state, before)
        XCTAssertNotNil(context.controller.taskOperationFailure)
    }

    @MainActor
    func testActivationRetryFollowsTaskIdentityAfterReorder() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let taskID = context.controller.workspace.slots[1].id
        context.service.temporarilyUnavailable.insert(context.boundWindows[0].id)
        context.controller.toggleSlot(2)
        XCTAssertNotNil(context.controller.activationFailure)
        XCTAssertTrue(context.controller.reorderSlot(from: 2, to: 5, expectedTaskID: taskID))
        context.service.temporarilyUnavailable.removeAll()
        context.controller.retryLastActivation()
        await waitUntil { context.controller.activeSlot == 5 }
        XCTAssertNil(context.controller.activationFailure)
    }

    private func isolatedShortcutPreferences() throws -> UserDefaults {
        let suite = "OmniVibeControllerShortcutTests-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { preferences.removePersistentDomain(forName: suite) }
        return preferences
    }

    @MainActor
    func testCaptureParkingIsDurableAndRemovalRestoresThePreCaptureWindow() throws {
        let context = try ControllerContext(minimizeOnCapture: true)
        defer { context.removeFiles() }
        let window = try XCTUnwrap(context.service.focused)
        let original = try XCTUnwrap(context.service.placements[window.id])
        XCTAssertTrue(context.controller.captureDraggedWindow(window, originalFrame: original.frame, to: 3))
        XCTAssertEqual(context.service.placements[window.id]?.frame, original.frame)
        XCTAssertEqual(context.service.placements[window.id]?.minimized, true)
        let journal = RecoveryJournalStore(root: context.root)
        XCTAssertEqual(try journal.load().records.map(\.kind), [.parked])
        XCTAssertTrue(context.controller.remove(3, expectedTaskID: context.controller.workspace.slots[2].id))
        XCTAssertEqual(context.service.placements[window.id], original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.journalURL.path))
    }

    @MainActor
    func testNewCoordinatorRestoresNestedJournalInTheCorrectOrder() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let original = context.service.placements
        let ids = context.controller.workspace.slots.map(\.id)
        context.controller.toggleArrangement()
        context.controller.enterSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        let replacement = ApplicationController(windowService: context.service, store: context.store,
            startsMonitoring: false, preferences: context.preferences)
        XCTAssertEqual(replacement.recoveryCount, 3)
        XCTAssertEqual(replacement.workspace.slots.map(\.id), ids)
        replacement.restorePendingRecovery()
        XCTAssertEqual(replacement.recoveryCount, 0)
        XCTAssertNil(replacement.recoveryWarning)
        XCTAssertEqual(context.service.placements, original)
    }

    @MainActor
    func testRecoveryDoesNotRestoreLowerLayersBeforeAFailedToggleLayer() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let original = context.service.placements
        context.controller.toggleArrangement()
        context.controller.enterSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        let replacement = ApplicationController(windowService: context.service, store: context.store,
            startsMonitoring: false, preferences: context.preferences)
        let first = context.boundWindows[0].id
        context.service.restoreFailures.insert(first)
        context.service.restoreAttempts = []
        replacement.restorePendingRecovery()
        XCTAssertEqual(replacement.recoveryCount, 2)
        XCTAssertEqual(context.service.restoreAttempts.filter { $0 == first }.count, 1)
        context.service.restoreFailures.removeAll()
        replacement.restorePendingRecovery()
        XCTAssertEqual(replacement.recoveryCount, 0)
        XCTAssertEqual(context.service.placements, original)
    }

    @MainActor
    func testJournalWriteFailurePreventsEvenRepeatedActivationFromMutatingWindows() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let journal = RecoveryJournalStore(root: context.root)
        try FileManager.default.createDirectory(at: journal.journalURL, withIntermediateDirectories: true)
        let original = context.service.placements
        context.controller.enterSlot(2)
        context.controller.enterSlot(2)
        XCTAssertTrue(context.service.activationOrder.isEmpty)
        XCTAssertEqual(context.service.placements, original)
        try FileManager.default.removeItem(at: journal.journalURL)
        context.controller.enterSlot(2)
        await waitUntil { context.controller.activeSlot == 2 }
        XCTAssertEqual(try journal.load().records.count, 1)
    }

    @MainActor
    func testConfirmedClosureArchivesThenExplicitRebindRetainsTheTaskName() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let original = context.controller.workspace.slots[1]
        context.service.closed.insert(context.boundWindows[0].id)
        context.controller.refreshConnections()
        XCTAssertNil(context.controller.workspace.slots[1].window)
        XCTAssertEqual(context.controller.recentTasks.first?.task.id, original.id)
        XCTAssertTrue(context.controller.restoreRecentTask(original.id))
        XCTAssertNil(context.controller.workspace.slots[1].window)
        context.controller.presentRestoredRecentPickerIfNeeded()
        XCTAssertEqual(context.controller.pickerSlot, 1)
        let replacement = context.service.addWindow(title: "Recovered Backend", number: 4)
        XCTAssertTrue(context.controller.bind(replacement))
        XCTAssertEqual(context.controller.workspace.slots[0].name, original.displayName)
        XCTAssertFalse(context.controller.recentTasks.contains(where: { $0.id == original.id }))
    }

    @MainActor
    func testWheelCyclingSkipsEmptyTasksAndPauseLeavesTheCurrentWindowAlone() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        context.controller.cycleTask(direction: 1)
        await waitUntil { context.controller.activeSlot == 2 }
        context.controller.cycleTask(direction: 1)
        await waitUntil { context.controller.activeSlot == 8 }
        context.controller.setShortcutsPaused(true)
        let count = context.service.activationOrder.count
        context.controller.cycleTask(direction: 1)
        XCTAssertEqual(context.service.activationOrder.count, count)
        XCTAssertEqual(context.controller.activeSlot, 8)
    }

    @MainActor
    func testNewTaskOpensThenDurablyBindsTheExactWindowBeforeStartingItsAgent() async throws {
        let launcher = FakeTaskLauncher()
        let context = try ControllerContext(taskLauncher: launcher)
        defer { context.removeFiles() }
        launcher.root = context.root
        let previous = context.controller.workspace
        let taskID = previous.slots[0].id
        let configuration = launchConfiguration(context, provider: .codex)

        context.controller.beginLaunching(1)
        context.controller.launchTask(configuration)
        await waitUntil { !context.controller.taskLaunchBusy }

        let task = context.controller.workspace.slots[0]
        XCTAssertEqual(launcher.steps, ["open", "durable-binding", "start"])
        XCTAssertTrue(launcher.startWasDurablyBound)
        XCTAssertEqual(task.id, taskID)
        XCTAssertEqual(task.window?.id, launcher.opened.first?.window.id)
        XCTAssertEqual(task.agentProvider, "codex")
        XCTAssertEqual(task.sessionID, configuration.resumeSessionID)
        XCTAssertEqual(task.agentState, .unknown)
        XCTAssertFalse(task.integrationConnected)
        XCTAssertEqual(try context.store.load().state, context.controller.workspace)
        XCTAssertEqual(try TaskLaunchRecordStore(root: context.root).record(for: taskID)?.configuration, configuration)
        XCTAssertEqual(context.controller.workspace.slots[1], previous.slots[1])
        XCTAssertEqual(context.controller.workspace.slots[7], previous.slots[7])
        XCTAssertNil(context.controller.launchSlot)
    }

    @MainActor
    func testWorkspaceWriteFailureLeavesTheOpenedWindowButNeverStartsAnAgent() async throws {
        let launcher = FakeTaskLauncher()
        let context = try ControllerContext(taskLauncher: launcher)
        defer { context.removeFiles() }
        launcher.root = context.root
        let previous = context.controller.workspace
        context.controller.beginLaunching(1)
        try FileManager.default.removeItem(at: context.store.stateFile)
        try FileManager.default.createDirectory(at: context.store.stateFile, withIntermediateDirectories: false)

        context.controller.launchTask(launchConfiguration(context))
        await waitUntil { !context.controller.taskLaunchBusy }

        XCTAssertEqual(launcher.steps, ["open"])
        XCTAssertTrue(launcher.started.isEmpty)
        XCTAssertEqual(context.controller.workspace, previous)
        XCTAssertEqual(launcher.opened.count, 1)
        XCTAssertTrue(context.service.isAvailable(try XCTUnwrap(launcher.opened.first).window))
        XCTAssertNotNil(context.controller.taskOperationFailure)
    }

    @MainActor
    func testLiveTaskCanSaveLaunchSettingsButCannotCreateADuplicateWindow() throws {
        let launcher = FakeTaskLauncher()
        let context = try ControllerContext(taskLauncher: launcher)
        defer { context.removeFiles() }
        launcher.root = context.root
        let original = context.controller.workspace.slots[1]
        let configuration = launchConfiguration(context, provider: .claude)
        context.controller.beginLaunching(2)
        context.controller.saveLaunchConfiguration(configuration)

        XCTAssertEqual(try TaskLaunchRecordStore(root: context.root).record(for: original.id)?.configuration, configuration)
        XCTAssertTrue(launcher.steps.isEmpty)
        XCTAssertNil(context.controller.launchSlot)
        context.controller.beginLaunching(2)
        context.controller.launchTask(configuration)
        XCTAssertTrue(launcher.steps.isEmpty)
        XCTAssertEqual(context.controller.workspace.slots[1], original)
        XCTAssertNotNil(context.controller.taskOperationFailure)
    }

    @MainActor
    func testClosedRecentTaskUsesItsLaunchConfigurationAndMigratesGearToTheNewFixedSlot() async throws {
        let launcher = FakeTaskLauncher()
        let context = try ControllerContext(taskLauncher: launcher)
        defer { context.removeFiles() }
        launcher.root = context.root
        let original = context.controller.workspace.slots[1]
        let configuration = launchConfiguration(context, provider: .claude)
        let launches = TaskLaunchRecordStore(root: context.root)
        try launches.save(configuration, for: original.id)
        var equipment = [original.id: "custom-sword"]
        var migrations: [(UUID, UUID)] = []
        context.controller.onTaskIdentityReplaced = { old, new in
            migrations.append((old, new)); equipment[new] = equipment[old]
        }
        context.service.closed.insert(context.boundWindows[0].id)
        context.controller.refreshConnections()
        XCTAssertTrue(context.controller.recentTasks.contains { $0.id == original.id })
        XCTAssertTrue(context.controller.requestLaunchRecentTask(original.id))
        context.controller.presentRestoredRecentPickerIfNeeded()
        XCTAssertEqual(context.controller.launchSlot, 1)
        XCTAssertEqual(context.controller.launchConfiguration(for: 1), configuration)

        context.controller.launchTask(configuration)
        await waitUntil { !context.controller.taskLaunchBusy }

        let restored = context.controller.workspace.slots[0]
        XCTAssertEqual(restored.name, "Backend API")
        XCTAssertNotEqual(restored.id, original.id)
        XCTAssertEqual(restored.window?.id, launcher.opened.first?.window.id)
        XCTAssertEqual(restored.sessionID, configuration.resumeSessionID)
        XCTAssertEqual(equipment[restored.id], "custom-sword")
        XCTAssertEqual(migrations.count, 1)
        XCTAssertEqual(migrations.first?.0, original.id)
        XCTAssertEqual(migrations.first?.1, restored.id)
        XCTAssertEqual(try launches.record(for: restored.id)?.configuration, configuration)
        XCTAssertFalse(context.controller.recentTasks.contains { $0.id == original.id })
        XCTAssertTrue(launcher.startWasDurablyBound)
    }

    @MainActor
    func testExactExistingSessionAssociationResetsOldReadyStateAndRejectsADuplicateSession() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let taskID = context.controller.workspace.slots[1].id
        let priorID = UUID().uuidString
        let base = Date().addingTimeInterval(-4)
        try StatusEventInbox.publish(.init(taskID: taskID, state: .unknown, at: base, provider: "claude",
            sessionID: priorID, eventName: "SessionStart"), root: context.root)
        try StatusEventInbox.publish(.init(taskID: taskID, state: .ready, at: base.addingTimeInterval(1), provider: "claude",
            sessionID: priorID, eventName: "Stop"), root: context.root)
        await context.controller.pollStatusEvents()
        XCTAssertEqual(context.controller.workspace.slots[1].agentState, .ready)
        let session = discoveredSession(context, provider: "codex")

        context.controller.sessionDiscoverySlot = 2
        context.controller.attachExistingSession(session)
        let linked = context.controller.workspace.slots[1]
        XCTAssertEqual(linked.id, taskID)
        XCTAssertEqual(linked.agentProvider, "codex")
        XCTAssertEqual(linked.sessionID, session.sessionID)
        XCTAssertEqual(linked.agentState, .unknown)
        XCTAssertFalse(linked.unread)
        XCTAssertFalse(linked.integrationConnected)
        XCTAssertNil(linked.updatedAt)
        XCTAssertEqual(linked.lastAgentEventName, "")
        XCTAssertEqual(linked.stateSource, "Codex 会话记录")
        let other = context.controller.workspace.slots[7]
        var duplicate = session; duplicate.sessionID = session.sessionID.lowercased()
        context.controller.sessionDiscoverySlot = 8
        context.controller.attachExistingSession(duplicate)
        XCTAssertEqual(context.controller.workspace.slots[7], other)
        let associations = try SessionDiscoveryAssociationStore(root: context.root).load()
        XCTAssertEqual(associations.count, 1)
        XCTAssertEqual(associations[0].taskID, taskID)
        XCTAssertEqual(associations[0].windowID, linked.window?.id)
        XCTAssertEqual(associations[0].session.id, session.id)
    }

    @MainActor
    func testFailedAssociationWorkspaceWriteRestoresThePreviousExactAssociation() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let first = discoveredSession(context, provider: "codex")
        context.controller.sessionDiscoverySlot = 2
        context.controller.attachExistingSession(first)
        let workspace = context.controller.workspace
        let records = SessionDiscoveryAssociationStore(root: context.root)
        let previous = try records.load()
        let bytes = try Data(contentsOf: records.fileURL)
        let replacement = discoveredSession(context, provider: "claude")
        try FileManager.default.removeItem(at: context.store.stateFile)
        try FileManager.default.createDirectory(at: context.store.stateFile, withIntermediateDirectories: false)
        context.controller.sessionDiscoverySlot = 2

        context.controller.attachExistingSession(replacement)

        XCTAssertEqual(context.controller.workspace, workspace)
        let restored = try records.load()
        XCTAssertEqual(restored.count, previous.count)
        XCTAssertEqual(restored[0].taskID, previous[0].taskID)
        XCTAssertEqual(restored[0].session, previous[0].session)
        XCTAssertEqual(try Data(contentsOf: records.fileURL), bytes)
        XCTAssertNotNil(context.controller.taskOperationFailure)
    }

    @MainActor
    func testManualRemovalClearsLaunchAndSessionMetadataWithoutClosingTheWindow() throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let original = context.controller.workspace.slots[1]
        let launches = TaskLaunchRecordStore(root: context.root)
        try launches.save(launchConfiguration(context), for: original.id)
        context.controller.sessionDiscoverySlot = 2
        context.controller.attachExistingSession(discoveredSession(context))
        XCTAssertEqual(try SessionDiscoveryAssociationStore(root: context.root).load().count, 1)

        XCTAssertTrue(context.controller.remove(2, expectedTaskID: original.id))

        XCTAssertNil(try launches.record(for: original.id))
        XCTAssertFalse(try SessionDiscoveryAssociationStore(root: context.root).load().contains { $0.taskID == original.id })
        XCTAssertNil(context.controller.workspace.slots[1].window)
        XCTAssertTrue(context.service.isAvailable(context.boundWindows[0]))
        XCTAssertFalse(context.controller.recentTasks.contains { $0.id == original.id })
    }

    @MainActor
    func testTranscriptEventIsPersistedAsSessionRecordSourceRatherThanHooks() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let session = discoveredSession(context, provider: "claude")
        context.controller.sessionDiscoverySlot = 2
        context.controller.attachExistingSession(session)
        let task = context.controller.workspace.slots[1]
        try StatusEventInbox.publish(.init(taskID: task.id, state: .running, at: Date().addingTimeInterval(-1),
            provider: session.provider, sessionID: session.sessionID, eventName: "Transcript"), root: context.root)

        await context.controller.pollStatusEvents()

        let saved = try context.store.load().state.slots[1]
        XCTAssertEqual(saved.stateSource, "Claude Code 会话记录")
        XCTAssertFalse(saved.stateSource.contains("hooks"))
        XCTAssertEqual(saved.lastAgentEventName, "Transcript")
        XCTAssertEqual(saved.agentState, .running)
        XCTAssertEqual(saved.sessionID, session.sessionID)
    }

    @MainActor
    func testLateTranscriptCannotReplaceALiveHookSourceOrProduceAnotherReminder() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let task = context.controller.workspace.slots[1]
        let session = UUID().uuidString, base = Date().addingTimeInterval(-5)
        var reminders: [AudioCue] = []
        var readyTasks: [UUID] = []
        context.controller.onFeedback = { reminders.append($0) }
        context.controller.onTaskReady = { id, _ in readyTasks.append(id) }
        try StatusEventInbox.publish(.init(taskID: task.id, state: .unknown, at: base, provider: "codex",
            sessionID: session, eventName: "SessionStart"), root: context.root)
        try StatusEventInbox.publish(.init(taskID: task.id, state: .ready, at: base.addingTimeInterval(1), provider: "codex",
            sessionID: session, eventName: "agent-turn-complete"), root: context.root)
        await context.controller.pollStatusEvents()
        let hook = context.controller.workspace.slots[1]
        XCTAssertEqual(hook.stateSource, "Codex notify")
        try StatusEventInbox.publish(.init(taskID: task.id, state: .waiting, at: base.addingTimeInterval(2), provider: "codex",
            sessionID: session, eventName: "Transcript"), root: context.root)

        await context.controller.pollStatusEvents()

        XCTAssertEqual(context.controller.workspace.slots[1], hook)
        XCTAssertEqual(reminders, [.ready])
        XCTAssertEqual(readyTasks, [task.id])
        let pending = try await StatusEventInbox(root: context.root).read()
        XCTAssertTrue(pending.isEmpty)
    }

    @MainActor
    func testExplicitSessionReassociationLetsTheUserReturnFromHooksToRecordUpdates() async throws {
        let context = try ControllerContext()
        defer { context.removeFiles() }
        let task = context.controller.workspace.slots[1], session = discoveredSession(context)
        let base = Date().addingTimeInterval(-4)
        try StatusEventInbox.publish(.init(taskID: task.id, state: .unknown, at: base, provider: session.provider,
            sessionID: session.sessionID, eventName: "SessionStart"), root: context.root)
        try StatusEventInbox.publish(.init(taskID: task.id, state: .ready, at: base.addingTimeInterval(1), provider: session.provider,
            sessionID: session.sessionID, eventName: "Stop"), root: context.root)
        await context.controller.pollStatusEvents()
        XCTAssertEqual(context.controller.workspace.slots[1].lastAgentEventName, "Stop")
        context.controller.sessionDiscoverySlot = 2
        context.controller.attachExistingSession(session)
        XCTAssertEqual(context.controller.workspace.slots[1].lastAgentEventName, "")
        XCTAssertEqual(context.controller.workspace.slots[1].agentState, .unknown)
        try StatusEventInbox.publish(.init(taskID: task.id, state: .running, at: base.addingTimeInterval(2), provider: session.provider,
            sessionID: session.sessionID, eventName: "Transcript"), root: context.root)

        await context.controller.pollStatusEvents()

        XCTAssertEqual(context.controller.workspace.slots[1].lastAgentEventName, "Transcript")
        XCTAssertEqual(context.controller.workspace.slots[1].stateSource, "Codex 会话记录")
        XCTAssertEqual(context.controller.workspace.slots[1].agentState, .running)
    }

    @MainActor
    func testDispatchFailureRetainsThePersistedExactBindingForUserRecovery() async throws {
        let launcher = FakeTaskLauncher()
        let context = try ControllerContext(taskLauncher: launcher)
        defer { context.removeFiles() }
        launcher.root = context.root
        launcher.startFailure = .terminalBusy
        let originalID = context.controller.workspace.slots[0].id
        context.controller.beginLaunching(1)
        context.controller.launchTask(launchConfiguration(context))
        await waitUntil { !context.controller.taskLaunchBusy }

        XCTAssertEqual(launcher.started.count, 1)
        XCTAssertTrue(launcher.startWasDurablyBound)
        let saved = try context.store.load().state.slots[0]
        XCTAssertEqual(saved.id, originalID)
        XCTAssertEqual(saved.window?.id, launcher.opened.first?.window.id)
        XCTAssertTrue(context.service.isAvailable(try XCTUnwrap(saved.window)))
        XCTAssertNotNil(context.controller.taskOperationFailure)
    }

    @MainActor
    func testAUserBindingTheEmptySlotWhileItsWindowOpensCannotBeOverwrittenByLaunch() async throws {
        let launcher = FakeTaskLauncher()
        let context = try ControllerContext(taskLauncher: launcher)
        defer { context.removeFiles() }
        launcher.root = context.root
        let selected = context.service.addWindow(title: "User selected window", number: 900)
        let controller = context.controller
        launcher.onOpened = { [weak controller] _ in
            guard let controller else { return }
            controller.openPicker(for: 1)
            XCTAssertTrue(controller.bind(selected))
        }
        controller.beginLaunching(1)
        controller.launchTask(launchConfiguration(context))
        await waitUntil { !controller.taskLaunchBusy }

        XCTAssertEqual(controller.workspace.slots[0].window?.id, selected.id)
        XCTAssertEqual(try context.store.load().state.slots[0].window?.id, selected.id)
        XCTAssertTrue(launcher.started.isEmpty)
        XCTAssertEqual(launcher.steps, ["open"])
        XCTAssertNotNil(controller.taskOperationFailure)
    }

    @MainActor
    func testAConfirmedClosedBindingCanReopenUnderANewTaskIdentity() async throws {
        let launcher = FakeTaskLauncher()
        let context = try ControllerContext(taskLauncher: launcher)
        defer { context.removeFiles() }
        launcher.root = context.root
        let original = context.controller.workspace.slots[1]
        context.controller.beginLaunching(2)
        context.service.closed.insert(context.boundWindows[0].id)
        context.controller.launchTask(launchConfiguration(context, provider: .claude))
        await waitUntil { !context.controller.taskLaunchBusy }

        let restored = context.controller.workspace.slots[1]
        XCTAssertNotEqual(restored.id, original.id)
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.window?.id, launcher.opened.first?.window.id)
        XCTAssertEqual(restored.agentProvider, "claude")
        XCTAssertEqual(launcher.started.count, 1)
        XCTAssertTrue(launcher.startWasDurablyBound)
    }

    @MainActor
    func testTemporaryWindowUnavailabilityNeverAuthorizesAnotherAgentLaunch() async throws {
        let launcher = FakeTaskLauncher()
        let context = try ControllerContext(taskLauncher: launcher)
        defer { context.removeFiles() }
        launcher.root = context.root
        let original = context.controller.workspace.slots[1]
        context.service.temporarilyUnavailable.insert(context.boundWindows[0].id)
        context.controller.beginLaunching(2)

        context.controller.launchTask(launchConfiguration(context))
        await waitUntil { !context.controller.taskLaunchBusy }

        XCTAssertTrue(launcher.steps.isEmpty)
        XCTAssertEqual(context.controller.workspace.slots[1], original)
        XCTAssertNotNil(context.controller.taskOperationFailure)
    }

    @MainActor
    func testAnOriginalWindowReturningWhileItsReplacementOpensPreventsDuplicateStart() async throws {
        let launcher = FakeTaskLauncher()
        let context = try ControllerContext(taskLauncher: launcher)
        defer { context.removeFiles() }
        launcher.root = context.root
        let original = context.controller.workspace.slots[1]
        let oldWindow = context.boundWindows[0]
        context.controller.beginLaunching(2)
        context.service.closed.insert(oldWindow.id)
        launcher.onOpened = { [weak service = context.service] _ in service?.closed.remove(oldWindow.id) }

        context.controller.launchTask(launchConfiguration(context))
        await waitUntil { !context.controller.taskLaunchBusy }

        XCTAssertEqual(context.controller.workspace.slots[1], original)
        XCTAssertTrue(launcher.started.isEmpty)
        XCTAssertEqual(launcher.opened.count, 1)
        XCTAssertTrue(context.service.isAvailable(oldWindow))
        XCTAssertNotNil(context.controller.taskOperationFailure)
    }

    @MainActor
    private func launchConfiguration(_ context: ControllerContext, provider: TaskLaunchMode = .codex) -> TaskLaunchConfiguration {
        TaskLaunchConfiguration(mode: provider, projectDirectory: context.root.path, executablePath: "/bin/echo", resumeSessionID: UUID().uuidString)
    }

    @MainActor
    private func discoveredSession(_ context: ControllerContext, provider: String = "codex") -> DiscoveredAgentSession {
        DiscoveredAgentSession(provider: provider, sessionID: UUID().uuidString, projectDirectory: context.root.path,
            title: "Existing exact session", transcriptPath: context.root.appendingPathComponent("session.jsonl").path, modifiedAt: Date())
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for the coordinator's observable result.", file: file, line: line)
    }
}

@MainActor
private final class ControllerContext {
    let root: URL
    let store: WorkspaceStore
    let service: FakeWindowService
    let controller: ApplicationController
    let boundWindows: [WindowIdentity]
    let preferences: UserDefaults
    private let suite: String

    init(minimizeOnCapture: Bool = false, taskLauncher: (any TaskLaunching)? = nil) throws {
        let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeControllerTests-\(UUID())")
        let testStore = WorkspaceStore(root: testRoot)
        let fake = FakeWindowService()
        let first = fake.addWindow(title: "Backend", number: 1, minimized: true)
        let second = fake.addWindow(title: "Frontend", number: 2)
        let outside = fake.addWindow(title: "Prior work", number: 3)
        fake.focused = outside
        var workspace = WorkspaceState()
        try workspace.bind(first, to: 2)
        try workspace.rename(slot: 2, to: "Backend API")
        try workspace.bind(second, to: 8)
        try workspace.rename(slot: 8, to: "Frontend UI")
        try testStore.save(workspace)
        root = testRoot
        store = testStore
        service = fake
        boundWindows = [first, second]
        let suiteName = "OmniVibe.ControllerTests.\(UUID())"
        let isolated = UserDefaults(suiteName: suiteName)!
        var behavior = WindowBehaviorPreferences()
        behavior.minimizeOnCapture = minimizeOnCapture
        try WindowBehaviorPreferencesStore(preferences: isolated).save(behavior)
        preferences = isolated
        suite = suiteName
        controller = ApplicationController(windowService: fake, store: testStore, startsMonitoring: false,
            preferences: isolated, taskLauncher: taskLauncher)
    }

    func removeFiles() {
        preferences.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class FakeWindowService: WindowControlling {
    var isTrusted = true
    var temporarilyUnavailable = Set<UUID>()
    var reconnectResults: [UUID: WindowIdentity] = [:]
    var reconnectAttempts: [UUID] = []
    var asyncReconnect: ((WindowIdentity) async throws -> WindowIdentity?)?
    var asyncReconnectAttempts: [UUID] = []
    var asyncReconnectCompletions: [UUID] = []
    var pauseAsyncReconnect = false
    private var asyncReconnectWaiters: [CheckedContinuation<Void, Never>] = []
    var closed = Set<UUID>()
    var placements: [UUID: WindowPlacement] = [:]
    var focused: WindowIdentity?
    var restoreAttempts: [UUID] = []
    var confirmationAttempts = 0
    var confirmationFailure: FakeWindowError?
    var pauseConfirmation = false
    var frameFailures = Set<UUID>()
    var frameAttempts: [UUID] = []
    var restoreFailures = Set<UUID>()
    var arrangementBlocks: [UUID: String] = [:]
    var workAreas: [UUID: WindowFrame] = [:]
    var displayIDs: [UUID: String] = [:]
    var activationOrder: [UUID] = []
    private var identities: [WindowIdentity] = []

    func addWindow(title: String, number: Int, minimized: Bool = false, bundleIdentifier: String = "com.example.terminal",
                   platformWindowNumber: UInt32? = nil, platformSessionID: String? = nil) -> WindowIdentity {
        let identity = WindowIdentity(processID: Int32(number), processStartedAt: Date(timeIntervalSince1970: Double(number)),
            bundleIdentifier: bundleIdentifier, applicationName: "Terminal", title: title,
            platformWindowNumber: platformWindowNumber, platformSessionID: platformSessionID)
        identities.append(identity)
        placements[identity.id] = WindowPlacement(
            frame: WindowFrame(x: Double(40 + number * 30), y: Double(70 + number * 20), width: 640, height: 420),
            minimized: minimized)
        return identity
    }

    func requestAccess() {}
    func openAccessibilitySettings() {}
    func windows() -> [WindowIdentity] { identities.filter { isAvailable($0) } }
    func reconnect(_ saved: WindowIdentity) -> WindowIdentity? {
        reconnectAttempts.append(saved.id)
        guard isTrusted, let restored = reconnectResults[saved.id],
              placements[restored.id] != nil, !closed.contains(restored.id) else { return nil }
        temporarilyUnavailable.remove(restored.id)
        return restored
    }
    func reconnectForActivation(_ saved: WindowIdentity) async throws -> WindowIdentity? {
        asyncReconnectAttempts.append(saved.id)
        defer { asyncReconnectCompletions.append(saved.id) }
        // Deliberately ignore cancellation while gated so tests exercise the
        // coordinator's generation checks against a backend's late result.
        if pauseAsyncReconnect {
            await withCheckedContinuation { continuation in asyncReconnectWaiters.append(continuation) }
        }
        guard let asyncReconnect else { return nil }
        let restored = try await asyncReconnect(saved)
        if let restored { temporarilyUnavailable.remove(restored.id) }
        return restored
    }
    func releaseAsyncReconnect() {
        pauseAsyncReconnect = false
        let waiters = asyncReconnectWaiters
        asyncReconnectWaiters = []
        for waiter in waiters { waiter.resume() }
    }
    func isAvailable(_ window: WindowIdentity) -> Bool {
        isTrusted && placements[window.id] != nil && !closed.contains(window.id) && !temporarilyUnavailable.contains(window.id)
    }
    func isDefinitelyClosed(_ window: WindowIdentity) -> Bool { closed.contains(window.id) }
    func currentWindow() -> WindowIdentity? { focused }

    func activate(_ window: WindowIdentity) throws {
        try requireAvailable(window)
        placements[window.id]?.minimized = false
        focused = window
        activationOrder.append(window.id)
    }

    func confirmActivation(_ window: WindowIdentity) async throws {
        confirmationAttempts += 1
        while pauseConfirmation { try await Task.sleep(nanoseconds: 1_000_000) }
        if let confirmationFailure { throw confirmationFailure }
        try requireAvailable(window)
        guard focused?.id == window.id else { throw FakeWindowError.confirmation }
    }

    func capturePlacement(_ window: WindowIdentity) throws -> WindowPlacement {
        try requireAvailable(window)
        guard let placement = placements[window.id] else { throw FakeWindowError.closed }
        return placement
    }

    func restore(_ window: WindowIdentity, to placement: WindowPlacement) throws {
        restoreAttempts.append(window.id)
        try requireAvailable(window)
        if restoreFailures.contains(window.id) { throw FakeWindowError.temporary }
        placements[window.id] = placement
    }

    func setFrame(_ target: WindowFrame, for window: WindowIdentity) throws {
        frameAttempts.append(window.id)
        try requireAvailable(window)
        placements[window.id] = WindowPlacement(frame: target, minimized: false)
        if frameFailures.contains(window.id) { throw FakeWindowError.temporary }
    }

    func workArea(for window: WindowIdentity?) -> WindowFrame {
        if let window, let area = workAreas[window.id] { return area }
        return WindowFrame(x: 0, y: 25, width: 1440, height: 875)
    }

    func arrangementBlockReason(_ window: WindowIdentity) -> String? { arrangementBlocks[window.id] }

    func arrangementDisplay(for window: WindowIdentity) -> ArrangementDisplay {
        let area = workArea(for: window)
        return ArrangementDisplay(id: displayIDs[window.id] ?? "\(area.x):\(area.y):\(area.width):\(area.height)", workArea: area)
    }

    private func requireAvailable(_ window: WindowIdentity) throws {
        if !isTrusted { throw FakeWindowError.permission }
        if closed.contains(window.id) { throw FakeWindowError.closed }
        if temporarilyUnavailable.contains(window.id) { throw FakeWindowError.temporary }
        if placements[window.id] == nil { throw FakeWindowError.closed }
    }
}

private enum FakeWindowError: Error, LocalizedError {
    case permission, closed, temporary, confirmation
    var errorDescription: String? {
        switch self {
        case .permission: return "test_permission_revoked"
        case .closed: return "test_window_closed"
        case .temporary: return "test_temporary_ax_failure"
        case .confirmation: return "focus_confirmation_failed"
        }
    }
}

/// No Terminal, WindowServer, AppleEvents or CLI process is involved. `start`
/// independently reads the durable workspace to enforce the production launch
/// boundary rather than accepting the coordinator's in-memory state as proof.
@MainActor
private final class FakeTaskLauncher: TaskLaunching {
    var root: URL?
    var steps: [String] = []
    var opened: [TaskLaunchWindow] = []
    var started: [TaskLaunchWindow] = []
    var startWasDurablyBound = false
    var startFailure: TaskLaunchError?
    var openFailure: TaskLaunchError?
    var onOpened: ((TaskLaunchWindow) -> Void)?
    private var configurations: [UUID: TaskLaunchConfiguration] = [:]

    func openWindow(configuration: TaskLaunchConfiguration, taskID: UUID,
                    windows: any WindowControlling) async throws -> TaskLaunchWindow {
        steps.append("open")
        if let openFailure { throw openFailure }
        guard let service = windows as? FakeWindowService else { throw TaskLaunchError.windowNotIdentified }
        let number = 400 + opened.count
        let window = service.addWindow(title: "New exact launch window", number: number, bundleIdentifier: "com.apple.Terminal",
            platformWindowNumber: UInt32(number), platformSessionID: "fake-desktop-session")
        let target = TaskLaunchWindow(id: UUID(), taskID: taskID, window: window, openedAt: Date())
        configurations[target.id] = configuration
        opened.append(target)
        onOpened?(target)
        return target
    }

    func start(_ target: TaskLaunchWindow) async throws -> TaskLaunchReceipt {
        guard let root, let configuration = configurations[target.id] else { throw TaskLaunchError.expiredWindow }
        let durable = try WorkspaceStore(root: root).load().state
        let task = durable.slots.first { $0.id == target.taskID }
        startWasDurablyBound = task?.window?.id == target.window.id &&
            task?.window?.refersToSamePlatformWindow(as: target.window) == true &&
            task?.agentProvider == (configuration.mode.provider?.rawValue ?? "") &&
            task?.sessionID == configuration.resumeSessionID
        guard startWasDurablyBound else { throw TaskLaunchError.bindingNotSaved }
        steps.append("durable-binding")
        started.append(target)
        steps.append("start")
        try TaskLaunchRecordStore(root: root).save(configuration, for: target.taskID)
        if let startFailure { throw startFailure }
        return TaskLaunchReceipt(taskID: target.taskID, window: target.window, configuration: configuration)
    }
}
