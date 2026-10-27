import Carbon
import XCTest
@testable import OmniVibeMac

final class TaskScrollSwitchServiceTests: XCTestCase {
    private func sample(_ y: Double, _ at: Double, continuous: Bool = false, momentum: Bool = false,
                        modifiers: UInt32 = UInt32(optionKey), x: Double = 0) -> TaskScrollSample {
        TaskScrollSample(deltaY: y, deltaX: x, continuous: continuous, momentum: momentum, modifiers: modifiers, at: at)
    }

    func testUnmatchedModifiersAndSuspensionNeverConsumeScroll() {
        var accumulator = ScrollSwitchAccumulator()
        XCTAssertEqual(accumulator.process(sample(3, 1), matches: false, suspended: false), .pass)
        XCTAssertEqual(accumulator.process(sample(3, 1), matches: true, suspended: true), .pass)
    }

    func testDiscreteWheelDirectionAndThrottle() {
        var accumulator = ScrollSwitchAccumulator()
        XCTAssertEqual(accumulator.process(sample(3, 1), matches: true, suspended: false), .consume(-1))
        XCTAssertEqual(accumulator.process(sample(-3, 1.1), matches: true, suspended: false), .consume(nil))
        XCTAssertEqual(accumulator.process(sample(-3, 1.3), matches: true, suspended: false), .consume(1))
    }

    func testTrackpadAccumulatesBeforeOneSwitch() {
        var accumulator = ScrollSwitchAccumulator()
        for at in [1.0, 1.05, 1.1] {
            XCTAssertEqual(accumulator.process(sample(6, at, continuous: true), matches: true, suspended: false), .consume(nil))
        }
        XCTAssertEqual(accumulator.process(sample(6, 1.15, continuous: true), matches: true, suspended: false), .consume(-1))
    }

    func testTrackpadGapsAndDirectionChangesDiscardPartialGesture() {
        var accumulator = ScrollSwitchAccumulator()
        _ = accumulator.process(sample(18, 1, continuous: true), matches: true, suspended: false)
        XCTAssertEqual(accumulator.process(sample(6, 1.4, continuous: true), matches: true, suspended: false), .consume(nil))
        XCTAssertEqual(accumulator.process(sample(-20, 1.45, continuous: true), matches: true, suspended: false), .consume(nil))
        XCTAssertEqual(accumulator.process(sample(-4, 1.5, continuous: true), matches: true, suspended: false), .consume(1))
    }

    func testMomentumCannotCycleTasksAndHorizontalScrollPasses() {
        var accumulator = ScrollSwitchAccumulator()
        XCTAssertEqual(accumulator.process(sample(80, 1, continuous: true, momentum: true), matches: true, suspended: false), .consume(nil))
        XCTAssertEqual(accumulator.process(sample(3, 1.1, x: 5), matches: true, suspended: false), .pass)
    }

    func testModifierReleaseClearsTrackpadAccumulation() {
        var accumulator = ScrollSwitchAccumulator()
        _ = accumulator.process(sample(18, 1, continuous: true), matches: true, suspended: false)
        _ = accumulator.process(sample(1, 1.02, continuous: true), matches: false, suspended: false)
        XCTAssertEqual(accumulator.process(sample(18, 1.04, continuous: true), matches: true, suspended: false), .consume(nil))
    }

    func testNonFiniteScrollInputIsNotConsumed() {
        var accumulator = ScrollSwitchAccumulator()
        XCTAssertEqual(accumulator.process(sample(.nan, 1), matches: true, suspended: false), .pass)
        XCTAssertEqual(accumulator.process(sample(3, .infinity), matches: true, suspended: false), .pass)
    }

    func testZeroDeltaPhaseEventDoesNotBypassThrottle() {
        var accumulator = ScrollSwitchAccumulator()
        _ = accumulator.process(sample(3, 1), matches: true, suspended: false)
        XCTAssertEqual(accumulator.process(sample(0, 1.05), matches: true, suspended: false), .pass)
        XCTAssertEqual(accumulator.process(sample(3, 1.1), matches: true, suspended: false), .consume(nil))
    }

    @MainActor
    func testConstructionDoesNotPreflightOrInstallAnEventTap() {
        let backend = FakeScrollBackend()
        _ = TaskScrollSwitchService(onSwitch: { _ in }, backend: backend)
        XCTAssertEqual(backend.permissionReads, 0)
        XCTAssertEqual(backend.startCount, 0)
    }

    @MainActor
    func testMissingPermissionsReportWarningsWithoutAttemptingRegistration() {
        let backend = FakeScrollBackend()
        backend.access = TaskScrollPermissions(accessibility: false, listenEvents: false)
        let service = TaskScrollSwitchService(onSwitch: { _ in }, backend: backend)
        XCTAssertEqual(service.start(modifiers: UInt32(optionKey)).count, 2)
        XCTAssertEqual(backend.startCount, 0)
        XCTAssertFalse(service.isRunning)
    }

    @MainActor
    func testNoModifierCannotReserveOrdinaryScroll() {
        let backend = FakeScrollBackend()
        let service = TaskScrollSwitchService(onSwitch: { _ in }, backend: backend)
        XCTAssertFalse(service.start(modifiers: 0).isEmpty)
        XCTAssertEqual(backend.startCount, 0)
    }

    @MainActor
    func testOnlyTheExactConfiguredCombinationConsumesAndCycles() async {
        let backend = FakeScrollBackend()
        var directions: [Int] = []
        let service = TaskScrollSwitchService(onSwitch: { directions.append($0) }, backend: backend)
        XCTAssertTrue(service.start(modifiers: UInt32(optionKey)).isEmpty)
        XCTAssertFalse(backend.emit(sample(3, 1, modifiers: 0)))
        XCTAssertFalse(backend.emit(sample(3, 1.1, modifiers: UInt32(optionKey | controlKey))))
        XCTAssertTrue(backend.emit(sample(3, 1.2)))
        await Task.yield()
        XCTAssertEqual(directions, [-1])
    }

    @MainActor
    func testFilteringCanRunOutsideTheMainActorWhileActivationIsDeferred() async {
        let backend = FakeScrollBackend()
        var directions: [Int] = []
        let service = TaskScrollSwitchService(onSwitch: { directions.append($0) }, backend: backend)
        service.start(modifiers: UInt32(optionKey))
        let consumed = await Task.detached {
            backend.emit(TaskScrollSample(deltaY: 3, modifiers: UInt32(optionKey), at: 1))
        }.value
        XCTAssertTrue(consumed)
        await Task.yield()
        XCTAssertEqual(directions, [-1])
    }

    @MainActor
    func testSuspendedServicePassesScrollAndCanResume() async {
        let backend = FakeScrollBackend()
        var count = 0
        let service = TaskScrollSwitchService(onSwitch: { _ in count += 1 }, backend: backend)
        service.start(modifiers: UInt32(optionKey))
        service.setSuspended(true)
        XCTAssertFalse(backend.emit(sample(3, 1)))
        service.setSuspended(false)
        XCTAssertTrue(backend.emit(sample(3, 2)))
        await Task.yield()
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testStopCancelsAQueuedCycleAndUnregistersTheTap() async {
        let backend = FakeScrollBackend()
        var count = 0
        let service = TaskScrollSwitchService(onSwitch: { _ in count += 1 }, backend: backend)
        service.start(modifiers: UInt32(optionKey))
        XCTAssertTrue(backend.emit(sample(3, 1)))
        service.stop()
        await Task.yield()
        XCTAssertEqual(count, 0)
        XCTAssertFalse(service.isRunning)
        XCTAssertFalse(backend.emit(sample(3, 2)))
    }

    @MainActor
    func testReconfigurationCannotRunAnOldQueuedCycle() async {
        let backend = FakeScrollBackend()
        var directions: [Int] = []
        let service = TaskScrollSwitchService(onSwitch: { directions.append($0) }, backend: backend)
        service.start(modifiers: UInt32(optionKey))
        _ = backend.emit(sample(3, 1))
        service.start(modifiers: UInt32(controlKey))
        XCTAssertTrue(backend.emit(sample(-3, 2, modifiers: UInt32(controlKey))))
        await Task.yield()
        XCTAssertEqual(directions, [1])
    }

    @MainActor
    func testTapFailureAndSystemDisableAreVisibleAndFailOpen() async {
        let backend = FakeScrollBackend()
        backend.canStart = false
        var warnings: [String] = []
        let service = TaskScrollSwitchService(onSwitch: { _ in }, onWarning: { warnings.append($0) }, backend: backend)
        XCTAssertFalse(service.start(modifiers: UInt32(optionKey)).isEmpty)
        XCTAssertFalse(service.isRunning)
        backend.canStart = true
        service.start(modifiers: UInt32(optionKey))
        backend.disable()
        await Task.yield()
        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertFalse(backend.emit(sample(3, 1)))
    }

    @MainActor
    func testSystemDisableStillReportsAfterSuspendingAndResumingTheSameTap() async {
        let backend = FakeScrollBackend()
        var warnings: [String] = []
        let service = TaskScrollSwitchService(onSwitch: { _ in }, onWarning: { warnings.append($0) }, backend: backend)
        service.start(modifiers: UInt32(optionKey))
        service.setSuspended(true)
        service.setSuspended(false)
        backend.disable()
        await Task.yield()
        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(warnings.count, 1)
    }
}

private final class FakeScrollBackend: TaskScrollSwitchBackend, @unchecked Sendable {
    var access = TaskScrollPermissions(accessibility: true, listenEvents: true)
    var permissionReads = 0
    var startCount = 0
    var canStart = true
    private var handler: (@Sendable (TaskScrollSample) -> Bool)?
    private var onDisabled: (@Sendable () -> Void)?
    var permissions: TaskScrollPermissions { permissionReads += 1; return access }
    func start(handler: @escaping @Sendable (TaskScrollSample) -> Bool, onDisabled: @escaping @Sendable () -> Void) -> Bool {
        startCount += 1
        if canStart { self.handler = handler; self.onDisabled = onDisabled }
        return canStart
    }
    func stop() { handler = nil; onDisabled = nil }
    func emit(_ sample: TaskScrollSample) -> Bool { handler?(sample) ?? false }
    func disable() { let callback = onDisabled; stop(); callback?() }
}
