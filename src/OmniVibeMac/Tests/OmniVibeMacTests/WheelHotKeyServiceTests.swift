import Carbon
import XCTest
@testable import OmniVibeMac

final class WheelHotKeyServiceTests: XCTestCase {
    @MainActor
    func testCustomWheelBindingsAndEscapeUseEffectiveConfigurationAndPreserveActionRouting() throws {
        let carbon = FakeHotKeys()
        let aimModifiers = UInt32(controlKey | shiftKey)
        let aim = try ShortcutBinding.recorded(action: .aim, physicalKeyCode: kVK_F2, modifiers: aimModifiers, keyLabel: "F2")
        let toggle = try ShortcutBinding.recorded(action: .toggleVisibility, physicalKeyCode: kVK_F3, modifiers: UInt32(optionKey), keyLabel: "F3")
        let inventory = try ShortcutBinding.recorded(action: .inventory, physicalKeyCode: kVK_Space, modifiers: UInt32(optionKey), keyLabel: "Space")
        let configuration = try ShortcutConfiguration(base: .optionNumbers).setting(aim).setting(toggle).setting(inventory)
        var pressed = 0, toggled = 0, cancelled = 0, opened = 0
        let service = WheelHotKeyService(configuration: configuration, onPress: { pressed += 1 }, onRelease: {},
            onToggle: { toggled += 1 }, onCancel: { cancelled += 1 }, registration: carbon.functions, onInventory: { opened += 1 })
        try service.register()
        try service.beginEscapeCapture()
        XCTAssertEqual(carbon.attemptedIDs, [1, 2, 5, 3, 4])
        XCTAssertEqual(carbon.registeredCodes, [kVK_F2, kVK_F3, kVK_Space, kVK_Escape, kVK_Escape])
        XCTAssertEqual(carbon.registeredModifiers, [aimModifiers, UInt32(optionKey), UInt32(optionKey), aimModifiers, 0])
        XCTAssertEqual(service.registeredShortcuts, ["⌃⇧F2", "⌥F3", "⌥Space"])
        service.handle(1, kind: UInt32(kEventHotKeyPressed))
        service.handle(2, kind: UInt32(kEventHotKeyPressed))
        service.handle(3, kind: UInt32(kEventHotKeyPressed))
        service.handle(5, kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(pressed, 1)
        XCTAssertEqual(toggled, 1)
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(opened, 1)
    }

    @MainActor
    func testDisablingAllWheelActionsDoesNotInstallHandlerOrCaptureEscape() throws {
        let carbon = FakeHotKeys()
        let config = try ShortcutConfiguration(base: .optionNumbers).disabling(.aim).disabling(.toggleVisibility)
        let service = WheelHotKeyService(configuration: config, onPress: {}, onRelease: {}, onToggle: {}, onCancel: {}, registration: carbon.functions)
        try service.register()
        try service.beginEscapeCapture()
        XCTAssertEqual(carbon.installCount, 0)
        XCTAssertTrue(carbon.attemptedIDs.isEmpty)
        XCTAssertTrue(service.registeredShortcuts.isEmpty)
    }

    @MainActor
    func testCustomSystemConflictKeepsOtherActionsAndUsesConfiguredWarningLabel() throws {
        let carbon = FakeHotKeys(failingIDs: [1])
        let aim = try ShortcutBinding.recorded(action: .aim, physicalKeyCode: kVK_F2, modifiers: UInt32(controlKey | shiftKey), keyLabel: "F2")
        let config = try ShortcutConfiguration(base: .optionNumbers).setting(aim)
        let service = WheelHotKeyService(configuration: config, onPress: {}, onRelease: {}, onToggle: {}, onCancel: {}, registration: carbon.functions)
        try service.register()
        XCTAssertFalse(service.canAim)
        XCTAssertTrue(service.canToggleVisibility)
        XCTAssertEqual(service.registeredShortcuts, ["⌥H"])
        XCTAssertTrue(service.warnings[0].contains("⌃⇧F2"))
        XCTAssertTrue(carbon.removedIDs.isEmpty)
    }

    @MainActor
    func testOptionWheelAndTemporaryEscapeUseTheSchemeModifiersAndExactCallbacks() throws {
        let carbon = FakeHotKeys()
        var pressed = 0, released = 0, toggled = 0, cancelled = 0, inventory = 0
        let service = WheelHotKeyService(scheme: .optionNumbers, onPress: { pressed += 1 },
            onRelease: { released += 1 }, onToggle: { toggled += 1 }, onCancel: { cancelled += 1 },
            registration: carbon.functions, onInventory: { inventory += 1 })
        try service.register()
        XCTAssertEqual(service.registeredShortcuts, ["⌥Q", "⌥H"])
        XCTAssertEqual(carbon.registeredCodes, [kVK_ANSI_Q, kVK_ANSI_H])
        XCTAssertFalse(carbon.registeredCodes.contains(kVK_ANSI_Grave), "The arrangement key belongs only to the task service.")
        XCTAssertFalse(carbon.registeredCodes.contains(kVK_ANSI_0))
        XCTAssertTrue(service.canAim)
        XCTAssertTrue(service.canToggleVisibility)
        XCTAssertFalse(service.canOpenInventory)
        try service.beginEscapeCapture()
        XCTAssertEqual(carbon.registeredModifiers, [UInt32(optionKey), UInt32(optionKey), UInt32(optionKey), 0])
        service.handle(1, kind: UInt32(kEventHotKeyPressed))
        service.handle(1, kind: UInt32(kEventHotKeyPressed))
        service.handle(3, kind: UInt32(kEventHotKeyPressed))
        service.handle(1, kind: UInt32(kEventHotKeyReleased))
        service.handle(1, kind: UInt32(kEventHotKeyReleased))
        service.handle(2, kind: UInt32(kEventHotKeyPressed))
        service.handle(5, kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(pressed, 1)
        XCTAssertEqual(released, 1)
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(toggled, 1)
        XCTAssertEqual(inventory, 0)
        service.unregister()
        service.handle(1, kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(pressed, 1, "Queued callbacks must be ignored after unregistering.")
    }

    @MainActor
    func testInventoryFirstRegistersOnlyOptionSpaceAndRoutesOnlyPressedEventToInventory() throws {
        let carbon = FakeHotKeys()
        var otherCallbacks = 0, inventory = 0
        let service = WheelHotKeyService(scheme: .inventoryFirst, onPress: { otherCallbacks += 1 },
            onRelease: { otherCallbacks += 1 }, onToggle: { otherCallbacks += 1 },
            onCancel: { otherCallbacks += 1 }, registration: carbon.functions, onInventory: { inventory += 1 })
        try service.register()
        try service.beginEscapeCapture()
        XCTAssertEqual(carbon.attemptedIDs, [5])
        XCTAssertEqual(carbon.registeredCodes, [kVK_Space])
        XCTAssertEqual(carbon.registeredModifiers, [UInt32(optionKey)])
        XCTAssertEqual(service.registeredShortcuts, ["⌥Space"])
        XCTAssertFalse(service.canAim)
        XCTAssertFalse(service.canToggleVisibility)
        XCTAssertTrue(service.canOpenInventory)
        for id in [1, 2, 3, 4] { service.handle(id, kind: UInt32(kEventHotKeyPressed)) }
        service.handle(5, kind: UInt32(kEventHotKeyPressed))
        service.handle(5, kind: UInt32(kEventHotKeyReleased))
        XCTAssertEqual(inventory, 1)
        XCTAssertEqual(otherCallbacks, 0)
        service.unregister()
        service.handle(5, kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(inventory, 1)
        XCTAssertEqual(carbon.removedIDs, [5])
    }

    @MainActor
    func testInventoryConflictReportsOptionSpaceAndNeverClaimsAvailabilityOrRoutesCallbacks() throws {
        let carbon = FakeHotKeys(failingIDs: [5])
        var inventory = 0
        let service = WheelHotKeyService(scheme: .inventoryFirst, onPress: {}, onRelease: {},
            onToggle: {}, onCancel: {}, registration: carbon.functions, onInventory: { inventory += 1 })
        try service.register()
        XCTAssertTrue(service.registeredShortcuts.isEmpty)
        XCTAssertFalse(service.canOpenInventory)
        XCTAssertEqual(service.warnings.count, 1)
        XCTAssertTrue(service.warnings[0].contains("⌥Space"))
        service.handle(5, kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(inventory, 0)
    }

    @MainActor
    func testOptionToggleConflictStillLeavesOptionAimAvailableWithCorrectWarningLabel() throws {
        let carbon = FakeHotKeys(failingIDs: [2])
        let service = WheelHotKeyService(scheme: .optionNumbers, onPress: {}, onRelease: {},
            onToggle: {}, onCancel: {}, registration: carbon.functions)
        try service.register()
        XCTAssertEqual(service.registeredShortcuts, ["⌥Q"])
        XCTAssertTrue(service.canAim)
        XCTAssertFalse(service.canToggleVisibility)
        XCTAssertTrue(carbon.removedIDs.isEmpty)
        XCTAssertTrue(service.warnings[0].contains("⌥H"))
        XCTAssertFalse(service.warnings[0].contains("⌃"))
    }

    @MainActor
    func testToggleConflictPreservesAimAndDoesNotUnregisterItsSuccessfulRegistration() throws {
        let carbon = FakeHotKeys(failingIDs: [2])
        let service = makeService(carbon)
        try service.register()

        XCTAssertTrue(service.canAim)
        XCTAssertFalse(service.canToggleVisibility)
        XCTAssertEqual(service.registeredShortcuts, ["⌃⌥Q"])
        XCTAssertEqual(service.warnings.count, 1)
        XCTAssertTrue(service.warnings[0].contains("⌃⌥H"))
        XCTAssertEqual(carbon.registeredCodes, [kVK_ANSI_Q, kVK_ANSI_H])
        XCTAssertFalse(carbon.registeredCodes.contains(kVK_Space), "The input-source system shortcut must stay available.")
        XCTAssertTrue(carbon.removedIDs.isEmpty, "A conflicting secondary shortcut must not roll back Q.")
        XCTAssertEqual(carbon.removedHandlerCount, 0)

        service.unregister()
        XCTAssertEqual(carbon.removedIDs, [1])
        XCTAssertEqual(carbon.removedHandlerCount, 1)
        XCTAssertTrue(service.registeredShortcuts.isEmpty)
    }

    @MainActor
    func testAimConflictStillAttemptsAndRetainsToggle() throws {
        let carbon = FakeHotKeys(failingIDs: [1])
        let service = makeService(carbon)
        try service.register()

        XCTAssertFalse(service.canAim)
        XCTAssertTrue(service.canToggleVisibility)
        XCTAssertEqual(service.registeredShortcuts, ["⌃⌥H"])
        XCTAssertEqual(carbon.attemptedIDs, [1, 2])
        XCTAssertEqual(service.warnings.count, 1)
        XCTAssertTrue(carbon.removedIDs.isEmpty)
        service.unregister()
        XCTAssertEqual(carbon.removedIDs, [2])
    }

    @MainActor
    func testAllConflictsAreReportedAsUnavailableWithoutPretendingRegistrationSucceeded() throws {
        let carbon = FakeHotKeys(failingIDs: [1, 2])
        let service = makeService(carbon)
        try service.register()

        XCTAssertFalse(service.canAim)
        XCTAssertFalse(service.canToggleVisibility)
        XCTAssertTrue(service.registeredShortcuts.isEmpty)
        XCTAssertEqual(service.warnings.count, 2)
        try service.beginEscapeCapture()
        XCTAssertEqual(carbon.attemptedIDs, [1, 2], "Without Q, temporary Esc captures are unnecessary.")
        service.unregister()
        XCTAssertTrue(carbon.removedIDs.isEmpty)
        XCTAssertEqual(carbon.removedHandlerCount, 1)
    }

    @MainActor
    func testOneEscapeConflictKeepsOtherEscapeAndPermanentShortcuts() throws {
        let carbon = FakeHotKeys(failingIDs: [4])
        let service = makeService(carbon)
        try service.register()
        try service.beginEscapeCapture()

        XCTAssertEqual(carbon.attemptedIDs, [1, 2, 3, 4])
        XCTAssertTrue(service.canAim)
        XCTAssertTrue(service.canToggleVisibility)
        XCTAssertTrue(carbon.removedIDs.isEmpty)
        XCTAssertEqual(service.warnings.count, 1)
        service.endEscapeCapture()
        XCTAssertEqual(carbon.removedIDs, [3])
        XCTAssertEqual(service.registeredShortcuts, ["⌃⌥Q", "⌃⌥H"])
        service.unregister()
        XCTAssertEqual(carbon.removedIDs, [3, 1, 2])
    }

    @MainActor
    func testRegistrationCanRetryAfterUnregisterAndClearsResolvedWarnings() throws {
        let carbon = FakeHotKeys(failingIDs: [2])
        let service = makeService(carbon)
        try service.register()
        try service.register()
        XCTAssertEqual(carbon.attemptedIDs, [1, 2], "Repeated registration must not duplicate active references.")
        service.unregister()
        service.unregister()
        XCTAssertEqual(carbon.removedIDs, [1], "Repeated cleanup must not unregister a reference twice.")

        carbon.failingIDs = []
        try service.register()
        XCTAssertTrue(service.canAim)
        XCTAssertTrue(service.canToggleVisibility)
        XCTAssertTrue(service.warnings.isEmpty)
        service.unregister()
    }

    @MainActor
    func testEventHandlerFailureThrowsBeforeAttemptingAnyShortcut() throws {
        let carbon = FakeHotKeys()
        carbon.installStatus = OSStatus(eventNotHandledErr)
        let service = makeService(carbon)
        XCTAssertThrowsError(try service.register())
        XCTAssertTrue(carbon.attemptedIDs.isEmpty)
        XCTAssertTrue(service.registeredShortcuts.isEmpty)
        XCTAssertFalse(service.canAim)
    }

    @MainActor
    private func makeService(_ carbon: FakeHotKeys) -> WheelHotKeyService {
        WheelHotKeyService(onPress: {}, onRelease: {}, onToggle: {}, onCancel: {}, registration: carbon.functions)
    }
}

@MainActor
private final class FakeHotKeys {
    var failingIDs: Set<UInt32>
    var installStatus: OSStatus = noErr
    var installCount = 0
    var attemptedIDs: [UInt32] = []
    var registeredCodes: [Int] = []
    var registeredModifiers: [UInt32] = []
    var removedIDs: [UInt32] = []
    var removedHandlerCount = 0

    init(failingIDs: Set<UInt32> = []) { self.failingIDs = failingIDs }

    var functions: WheelHotKeyService.RegistrationFunctions {
        .init(installHandler: { _, handler in
            self.installCount += 1
            if self.installStatus == noErr { handler = EventHandlerRef(bitPattern: 0xF000) }
            return self.installStatus
        }, removeHandler: { _ in
            self.removedHandlerCount += 1
        }, registerKey: { code, modifiers, id in
            self.registeredCodes.append(code)
            self.registeredModifiers.append(modifiers)
            self.attemptedIDs.append(id)
            if self.failingIDs.contains(id) { return (OSStatus(eventHotKeyExistsErr), nil) }
            return (noErr, EventHotKeyRef(bitPattern: Int(id) + 100))
        }, unregisterKey: { reference in
            self.removedIDs.append(UInt32(Int(bitPattern: reference) - 100))
        })
    }
}
