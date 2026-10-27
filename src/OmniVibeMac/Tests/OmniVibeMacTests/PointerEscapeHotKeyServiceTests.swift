import AppKit
import Carbon
import XCTest
@testable import OmniVibeMac

final class PointerEscapeHotKeyServiceTests: XCTestCase {
    @MainActor
    func testPlainEscapeWorksWithoutAnyWheelOrAimRegistration() throws {
        let carbon = FakePointerEscapeKeys()
        var cancelled = 0
        let service = PointerEscapeHotKeyService(onCancel: { cancelled += 1 }, registration: carbon.functions)
        try service.begin()
        XCTAssertEqual(carbon.codes, [kVK_Escape])
        XCTAssertEqual(carbon.modifiers, [0])
        XCTAssertEqual(service.registeredModifiers, [0])
        service.handle(Int(carbon.ids[0]), kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(cancelled, 1)
    }

    @MainActor
    func testCurrentModifiersAddOneExplicitEscapeCombination() throws {
        let carbon = FakePointerEscapeKeys()
        let service = PointerEscapeHotKeyService(onCancel: {}, registration: carbon.functions)
        let modifiers = UInt32(controlKey | shiftKey)
        try service.begin(modifiers: modifiers)
        XCTAssertEqual(carbon.codes, [kVK_Escape, kVK_Escape])
        XCTAssertEqual(carbon.modifiers, [0, modifiers])
        XCTAssertEqual(service.registeredModifiers, [0, modifiers])
    }

    @MainActor
    func testModifierConversionIgnoresCapsLockAndFunctionFlags() {
        XCTAssertEqual(PointerEscapeHotKeyService.carbonModifiers(for: [.control, .option, .command, .shift, .capsLock, .function]),
                       UInt32(controlKey | optionKey | cmdKey | shiftKey))
        XCTAssertEqual(PointerEscapeHotKeyService.carbonModifiers(for: [.capsLock, .function]), 0)
    }

    @MainActor
    func testOneConflictRetainsTheOtherCancellationCombination() throws {
        let carbon = FakePointerEscapeKeys()
        carbon.failingAttempts = [1]
        let service = PointerEscapeHotKeyService(onCancel: {}, registration: carbon.functions)
        try service.begin(modifiers: UInt32(optionKey))
        XCTAssertEqual(service.registeredModifiers, [UInt32(optionKey)])
        XCTAssertEqual(service.warnings.count, 1)
        XCTAssertTrue(carbon.removedIDs.isEmpty)
        service.end()
        XCTAssertEqual(carbon.removedIDs, [carbon.ids[1]])
    }

    @MainActor
    func testFailedRegistrationReferenceIsCleanedWithoutRemovingSuccessfulKeys() throws {
        let carbon = FakePointerEscapeKeys()
        carbon.failingAttempts = [1]
        carbon.referenceOnFailure = true
        let service = PointerEscapeHotKeyService(onCancel: {}, registration: carbon.functions)
        try service.begin(modifiers: UInt32(cmdKey))
        XCTAssertEqual(carbon.removedIDs, [carbon.ids[0]])
        XCTAssertEqual(service.registeredModifiers, [UInt32(cmdKey)])
        service.end()
        XCTAssertEqual(carbon.removedIDs, carbon.ids)
    }

    @MainActor
    func testSuccessfulStatusWithoutReferenceIsStillUnavailable() throws {
        let carbon = FakePointerEscapeKeys()
        carbon.nilReferenceAttempts = [1]
        let service = PointerEscapeHotKeyService(onCancel: {}, registration: carbon.functions)
        try service.begin()
        XCTAssertTrue(service.registeredModifiers.isEmpty)
        XCTAssertEqual(service.warnings.count, 1)
        service.end()
        XCTAssertTrue(carbon.removedIDs.isEmpty)
    }

    @MainActor
    func testHandlerFailureCleansPartialHandlerAndThrowsBeforeRegisteringKeys() {
        let carbon = FakePointerEscapeKeys()
        carbon.installStatus = OSStatus(eventNotHandledErr)
        carbon.handlerOnFailure = true
        let service = PointerEscapeHotKeyService(onCancel: {}, registration: carbon.functions)
        XCTAssertThrowsError(try service.begin())
        XCTAssertTrue(carbon.codes.isEmpty)
        XCTAssertEqual(carbon.removedHandlers, 1)
    }

    @MainActor
    func testOnlyRegisteredPressCancelsAndAutorepeatDoesNotCancelAgain() throws {
        let carbon = FakePointerEscapeKeys()
        var cancelled = 0
        let service = PointerEscapeHotKeyService(onCancel: { cancelled += 1 }, registration: carbon.functions)
        try service.begin()
        let identifier = Int(carbon.ids[0])
        service.handle(identifier, kind: UInt32(kEventHotKeyReleased))
        service.handle(Int.max, kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(cancelled, 0)
        service.handle(identifier, kind: UInt32(kEventHotKeyPressed))
        service.handle(identifier, kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(cancelled, 1)
    }

    @MainActor
    func testOldEscapeCannotCancelANewPointerGesture() throws {
        let carbon = FakePointerEscapeKeys()
        var cancelled = 0
        let service = PointerEscapeHotKeyService(onCancel: { cancelled += 1 }, registration: carbon.functions)
        try service.begin()
        let oldIdentifier = Int(carbon.ids[0])
        service.end()
        service.handle(oldIdentifier, kind: UInt32(kEventHotKeyPressed))
        try service.begin()
        XCTAssertEqual(carbon.ids.count, 2)
        XCTAssertTrue(carbon.ids[0] != carbon.ids[1])
        service.handle(oldIdentifier, kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(cancelled, 0)
        service.handle(Int(carbon.ids[1]), kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(cancelled, 1)
    }

    @MainActor
    func testBeginAndEndAreIdempotent() throws {
        let carbon = FakePointerEscapeKeys()
        let service = PointerEscapeHotKeyService(onCancel: {}, registration: carbon.functions)
        try service.begin()
        try service.begin()
        XCTAssertEqual(carbon.installedHandlers, 1)
        XCTAssertEqual(carbon.ids.count, 1)
        service.end()
        service.end()
        XCTAssertEqual(carbon.removedIDs, carbon.ids)
        XCTAssertEqual(carbon.removedHandlers, 1)
    }

    @MainActor
    func testSeparateServiceInstancesDoNotReusePendingEscapeIdentifiers() throws {
        let firstCarbon = FakePointerEscapeKeys(), secondCarbon = FakePointerEscapeKeys()
        var cancelled = 0
        let first = PointerEscapeHotKeyService(onCancel: {}, registration: firstCarbon.functions)
        try first.begin()
        let oldIdentifier = Int(firstCarbon.ids[0])
        first.end()
        let second = PointerEscapeHotKeyService(onCancel: { cancelled += 1 }, registration: secondCarbon.functions)
        try second.begin()
        second.handle(oldIdentifier, kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(cancelled, 0)
        second.handle(Int(secondCarbon.ids[0]), kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(cancelled, 1)
    }

    @MainActor
    func testWarningsResetForANewSuccessfulGesture() throws {
        let carbon = FakePointerEscapeKeys()
        carbon.failingAttempts = [1]
        let service = PointerEscapeHotKeyService(onCancel: {}, registration: carbon.functions)
        try service.begin()
        XCTAssertEqual(service.warnings.count, 1)
        service.end()
        carbon.failingAttempts = []
        try service.begin()
        XCTAssertTrue(service.warnings.isEmpty)
        XCTAssertEqual(service.registeredModifiers, [0])
    }

    @MainActor
    func testDeinitReleasesEveryTemporaryKeyAndHandler() throws {
        let carbon = FakePointerEscapeKeys()
        var service: PointerEscapeHotKeyService? = PointerEscapeHotKeyService(onCancel: {}, registration: carbon.functions)
        try service?.begin(modifiers: UInt32(optionKey))
        service = nil
        XCTAssertEqual(carbon.removedIDs, carbon.ids)
        XCTAssertEqual(carbon.removedHandlers, 1)
    }
}

@MainActor
private final class FakePointerEscapeKeys {
    var failingAttempts = Set<Int>()
    var nilReferenceAttempts = Set<Int>()
    var referenceOnFailure = false
    var handlerOnFailure = false
    var installStatus: OSStatus = noErr
    var installedHandlers = 0
    var removedHandlers = 0
    var codes: [Int] = []
    var modifiers: [UInt32] = []
    var ids: [UInt32] = []
    var removedIDs: [UInt32] = []

    var functions: PointerEscapeHotKeyService.RegistrationFunctions {
        .init(installHandler: { _, handler in
            self.installedHandlers += 1
            if self.installStatus == noErr || self.handlerOnFailure { handler = EventHandlerRef(bitPattern: 0xF000) }
            return self.installStatus
        }, removeHandler: { _ in self.removedHandlers += 1 }, registerKey: { code, modifiers, id in
            self.codes.append(code); self.modifiers.append(modifiers); self.ids.append(id)
            let reference = EventHotKeyRef(bitPattern: Int(id) + 100)
            if self.failingAttempts.contains(self.ids.count) { return (OSStatus(eventHotKeyExistsErr), self.referenceOnFailure ? reference : nil) }
            return (noErr, self.nilReferenceAttempts.contains(self.ids.count) ? nil : reference)
        }, unregisterKey: { reference in self.removedIDs.append(UInt32(Int(bitPattern: reference) - 100)) })
    }
}
