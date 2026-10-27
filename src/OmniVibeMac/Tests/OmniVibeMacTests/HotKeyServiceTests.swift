import Carbon
import XCTest
@testable import OmniVibeMac

final class HotKeyServiceTests: XCTestCase {
    @MainActor
    func testEffectiveCustomBindingsEnableActionsOutsideTheBasePresetAndKeepFixedRoutingIDs() throws {
        let carbon = FakeSlotHotKeys()
        carbon.expectedModifiers = UInt32(optionKey)
        carbon.expectedModifierOverrides[2] = UInt32(controlKey)
        let slot = try ShortcutBinding.recorded(action: .slot(2), physicalKeyCode: kVK_F1, modifiers: UInt32(controlKey), keyLabel: "F1")
        let arrange = try ShortcutBinding.recorded(action: .arrange, physicalKeyCode: kVK_ANSI_Grave, modifiers: UInt32(optionKey), keyLabel: "`")
        let config = try ShortcutConfiguration(base: .inventoryFirst).setting(slot).setting(arrange)
        var slots: [Int] = [], arrangements = 0
        let service = HotKeyService(configuration: config, onSlot: { slots.append($0) },
            onArrange: { arrangements += 1 }, registration: carbon.functions)
        try service.register()
        XCTAssertEqual(carbon.attemptedIDs, [2, 0])
        XCTAssertEqual(carbon.registeredCodes, [kVK_F1, kVK_ANSI_Grave])
        XCTAssertEqual(service.registeredSlots, [2])
        XCTAssertTrue(service.arrangementRegistered)
        service.handle(1)
        service.handle(2)
        service.handle(0)
        XCTAssertEqual(slots, [2])
        XCTAssertEqual(arrangements, 1)
    }

    @MainActor
    func testExplicitlyDisabledTaskKeysAreNeverRegisteredOrDispatched() throws {
        let carbon = FakeSlotHotKeys()
        carbon.expectedModifiers = UInt32(optionKey)
        let config = try ShortcutConfiguration(base: .optionNumbers).disabling(.slot(3)).disabling(.arrange)
        var callbacks = 0
        let service = HotKeyService(configuration: config, onSlot: { _ in callbacks += 1 },
            onArrange: { callbacks += 1 }, registration: carbon.functions)
        try service.register()
        XCTAssertFalse(carbon.attemptedIDs.contains(3))
        XCTAssertFalse(carbon.attemptedIDs.contains(0))
        XCTAssertFalse(service.arrangementRegistered)
        service.handle(3)
        service.handle(0)
        XCTAssertEqual(callbacks, 0)
    }

    @MainActor
    func testOptionArrangementUsesGraveAndLeavesOptionZeroUnregistered() throws {
        let carbon = FakeSlotHotKeys()
        carbon.expectedModifiers = UInt32(optionKey)
        var arranged = 0
        var selected: [Int] = []
        let service = HotKeyService(scheme: .optionNumbers, onSlot: { selected.append($0) },
            onArrange: { arranged += 1 }, registration: carbon.functions)
        try service.register()

        XCTAssertFalse(carbon.registeredCodes.contains(kVK_ANSI_0))
        XCTAssertEqual(carbon.registeredCodes.last, kVK_ANSI_Grave)
        XCTAssertEqual(carbon.attemptedIDs.last, 0, "The grave key must retain the arrangement callback identifier.")
        XCTAssertTrue(service.arrangementRegistered)
        service.handle(0)
        XCTAssertEqual(arranged, 1)
        XCTAssertTrue(selected.isEmpty)
    }

    @MainActor
    func testOptionSchemeUsesOnlyOptionAndReportsTheActualConflictingChord() throws {
        let carbon = FakeSlotHotKeys(failingIDs: [3])
        carbon.expectedModifiers = UInt32(optionKey)
        var selected: [Int] = []
        var arranged = 0
        let service = HotKeyService(scheme: .optionNumbers, onSlot: { selected.append($0) },
            onArrange: { arranged += 1 }, registration: carbon.functions)
        try service.register()

        XCTAssertEqual(service.registeredSlots, Set(1...9).subtracting([3]))
        XCTAssertTrue(service.arrangementRegistered)
        XCTAssertEqual(service.warnings.count, 1)
        XCTAssertTrue(service.warnings[0].contains("⌥3"))
        XCTAssertFalse(service.warnings[0].contains("⌃"))
        service.handle(3)
        service.handle(7)
        service.handle(0)
        XCTAssertEqual(selected, [7])
        XCTAssertEqual(arranged, 1)
    }

    @MainActor
    func testInventoryFirstDoesNotInstallOrRegisterAnyGlobalTaskShortcuts() throws {
        let carbon = FakeSlotHotKeys()
        var callbackCount = 0
        let service = HotKeyService(scheme: .inventoryFirst, onSlot: { _ in callbackCount += 1 },
            onArrange: { callbackCount += 1 }, registration: carbon.functions)
        try service.register()
        service.handle(1)
        service.handle(0)
        XCTAssertEqual(carbon.installCount, 0)
        XCTAssertTrue(carbon.attemptedIDs.isEmpty)
        XCTAssertTrue(service.registeredSlots.isEmpty)
        XCTAssertFalse(service.arrangementRegistered)
        XCTAssertTrue(service.warnings.isEmpty)
        XCTAssertEqual(callbackCount, 0)
        service.unregister()
        XCTAssertEqual(carbon.removedHandlerCount, 0)
    }

    @MainActor
    func testOneSlotConflictKeepsOtherSlotsAndArrangementAvailable() throws {
        let carbon = FakeSlotHotKeys(failingIDs: [3])
        var selected: [Int] = []
        var arranged = 0
        let service = HotKeyService(onSlot: { selected.append($0) }, onArrange: { arranged += 1 },
                                    registration: carbon.functions)
        try service.register()

        XCTAssertEqual(service.registeredSlots, Set(1...9).subtracting([3]))
        XCTAssertTrue(service.arrangementRegistered)
        XCTAssertEqual(service.warnings.count, 1)
        XCTAssertTrue(service.warnings[0].contains("⌃⌥3"))
        XCTAssertEqual(carbon.attemptedIDs, [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
        XCTAssertTrue(carbon.removedIDs.isEmpty, "A single conflict must not roll back successful shortcuts.")
        XCTAssertEqual(carbon.removedHandlerCount, 0)

        service.handle(3)
        service.handle(2)
        service.handle(0)
        service.handle(99)
        XCTAssertEqual(selected, [2])
        XCTAssertEqual(arranged, 1)
    }

    @MainActor
    func testArrangementConflictDoesNotDisableSlotKeys() throws {
        let carbon = FakeSlotHotKeys(failingIDs: [0])
        let service = makeService(carbon)
        try service.register()

        XCTAssertEqual(service.registeredSlots, Set(1...9))
        XCTAssertFalse(service.arrangementRegistered)
        XCTAssertEqual(service.warnings.count, 1)
        XCTAssertTrue(service.warnings[0].contains("⌃⌥0"))
        XCTAssertTrue(carbon.removedIDs.isEmpty)
    }

    @MainActor
    func testAllConflictsProduceWarningsWithoutThrowingOrClaimingAvailability() throws {
        let carbon = FakeSlotHotKeys(failingIDs: Set(0...9))
        let service = makeService(carbon)
        try service.register()

        XCTAssertTrue(service.registeredSlots.isEmpty)
        XCTAssertFalse(service.arrangementRegistered)
        XCTAssertEqual(service.warnings.count, 10)
        XCTAssertEqual(carbon.attemptedIDs.count, 10)
        XCTAssertTrue(carbon.removedIDs.isEmpty)
        service.unregister()
        XCTAssertEqual(carbon.removedHandlerCount, 1)
    }

    @MainActor
    func testRetryOnlyAttemptsMissingKeysAndClearsResolvedWarnings() throws {
        let carbon = FakeSlotHotKeys(failingIDs: [3, 7])
        let service = makeService(carbon)
        try service.register()
        carbon.failingIDs = [7]
        try service.register()

        XCTAssertEqual(carbon.installCount, 1)
        XCTAssertEqual(Array(carbon.attemptedIDs.suffix(2)), [3, 7])
        XCTAssertEqual(service.registeredSlots, Set(1...9).subtracting([7]))
        XCTAssertEqual(service.warnings.count, 1)
        XCTAssertTrue(service.warnings[0].contains("⌃⌥7"))
        XCTAssertTrue(carbon.removedIDs.isEmpty)

        carbon.failingIDs = []
        try service.register()
        XCTAssertEqual(carbon.attemptedIDs.last, 7)
        XCTAssertEqual(service.registeredSlots, Set(1...9))
        XCTAssertTrue(service.warnings.isEmpty)
        let attempts = carbon.attemptedIDs
        try service.register()
        XCTAssertEqual(carbon.attemptedIDs, attempts, "Active references must not be registered twice.")
    }

    @MainActor
    func testEventHandlerFailureThrowsBeforeRegisteringKeysAndCanRetry() throws {
        let carbon = FakeSlotHotKeys()
        carbon.installStatus = OSStatus(eventNotHandledErr)
        let service = makeService(carbon)
        XCTAssertThrowsError(try service.register())
        XCTAssertTrue(carbon.attemptedIDs.isEmpty)
        XCTAssertTrue(service.registeredSlots.isEmpty)

        carbon.installStatus = noErr
        try service.register()
        XCTAssertEqual(carbon.installCount, 2)
        XCTAssertEqual(service.registeredSlots, Set(1...9))
    }

    @MainActor
    func testMissingHandlerIsFailureAndPartialFailedHandlerIsReleased() {
        let carbon = FakeSlotHotKeys()
        carbon.omitHandler = true
        let service = makeService(carbon)
        XCTAssertThrowsError(try service.register())
        XCTAssertTrue(carbon.attemptedIDs.isEmpty)

        carbon.omitHandler = false
        carbon.installStatus = OSStatus(eventNotHandledErr)
        carbon.provideHandlerOnFailure = true
        XCTAssertThrowsError(try service.register())
        XCTAssertEqual(carbon.removedHandlerCount, 1)
        service.unregister()
        XCTAssertEqual(carbon.removedHandlerCount, 1, "A partial handler must only be released once.")
    }

    @MainActor
    func testMissingKeyHandleIsWarningAndPartialFailedKeyHandleIsReleased() throws {
        let carbon = FakeSlotHotKeys(failingIDs: [4])
        carbon.missingHandleIDs = [5]
        carbon.provideHandleOnFailure = true
        let service = makeService(carbon)
        try service.register()

        XCTAssertEqual(service.registeredSlots, Set(1...9).subtracting([4, 5]))
        XCTAssertTrue(service.arrangementRegistered)
        XCTAssertEqual(service.warnings.count, 2)
        XCTAssertEqual(carbon.removedIDs, [4])
        XCTAssertFalse(service.warnings.contains { $0.contains("系统错误 0") })
    }

    @MainActor
    func testUnregisterIsIdempotentAndIgnoresQueuedEvents() throws {
        let carbon = FakeSlotHotKeys(failingIDs: [6])
        var selected: [Int] = []
        var arranged = 0
        let service = HotKeyService(onSlot: { selected.append($0) }, onArrange: { arranged += 1 },
                                    registration: carbon.functions)
        try service.register()
        service.unregister()
        service.unregister()
        service.handle(1)
        service.handle(0)

        XCTAssertEqual(Set(carbon.removedIDs), Set(0...9).subtracting([6]))
        XCTAssertEqual(carbon.removedIDs.count, 9)
        XCTAssertEqual(carbon.removedHandlerCount, 1)
        XCTAssertTrue(service.registeredSlots.isEmpty)
        XCTAssertFalse(service.arrangementRegistered)
        XCTAssertTrue(service.warnings.isEmpty)
        XCTAssertTrue(selected.isEmpty)
        XCTAssertEqual(arranged, 0)
    }

    @MainActor
    func testDeinitReleasesRegisteredKeysAndHandler() throws {
        let carbon = FakeSlotHotKeys(failingIDs: [2])
        var service: HotKeyService? = makeService(carbon)
        try service?.register()
        service = nil

        XCTAssertEqual(Set(carbon.removedIDs), Set(0...9).subtracting([2]))
        XCTAssertEqual(carbon.removedIDs.count, 9)
        XCTAssertEqual(carbon.removedHandlerCount, 1)
    }

    @MainActor
    private func makeService(_ carbon: FakeSlotHotKeys) -> HotKeyService {
        HotKeyService(onSlot: { _ in }, onArrange: {}, registration: carbon.functions)
    }
}

@MainActor
private final class FakeSlotHotKeys {
    var failingIDs: Set<UInt32>
    var missingHandleIDs: Set<UInt32> = []
    var installStatus: OSStatus = noErr
    var omitHandler = false
    var provideHandlerOnFailure = false
    var provideHandleOnFailure = false
    var installCount = 0
    var attemptedIDs: [UInt32] = []
    var registeredCodes: [Int] = []
    var removedIDs: [UInt32] = []
    var removedHandlerCount = 0
    var expectedModifiers = UInt32(controlKey | optionKey)
    var expectedModifierOverrides: [UInt32: UInt32] = [:]

    init(failingIDs: Set<UInt32> = []) { self.failingIDs = failingIDs }

    var functions: HotKeyService.RegistrationFunctions {
        .init(installHandler: { _, handler in
            self.installCount += 1
            if !self.omitHandler && (self.installStatus == noErr || self.provideHandlerOnFailure) {
                handler = EventHandlerRef(bitPattern: 0xF100)
            }
            return self.installStatus
        }, removeHandler: { _ in
            self.removedHandlerCount += 1
        }, registerKey: { code, modifiers, id in
            XCTAssertEqual(modifiers, self.expectedModifierOverrides[id] ?? self.expectedModifiers)
            self.registeredCodes.append(code)
            self.attemptedIDs.append(id)
            let handle = EventHotKeyRef(bitPattern: Int(id) + 100)
            if self.failingIDs.contains(id) {
                return (OSStatus(eventHotKeyExistsErr), self.provideHandleOnFailure ? handle : nil)
            }
            return (noErr, self.missingHandleIDs.contains(id) ? nil : handle)
        }, unregisterKey: { reference in
            self.removedIDs.append(UInt32(Int(bitPattern: reference) - 100))
        })
    }
}
