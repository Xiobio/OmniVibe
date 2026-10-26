import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

@MainActor
final class WindowFrameSettlementTests: XCTestCase {
    private let target = WindowFrame(x: 741, y: 33, width: 729, height: 415)

    private final class Clock {
        var time: TimeInterval = 0
        var pauses: [TimeInterval] = []
        func pause(_ duration: TimeInterval) { pauses.append(duration); time += duration }
    }

    func testAlreadyMatchingFrameRequiresASecondObservationAfterTwentyMilliseconds() throws {
        let clock = Clock()
        var reads = 0
        var writes = 0
        let actual = try WindowFrameSettlement.settledFrame(target: target, strict: false, read: {
            reads += 1; return self.target
        }, retryPosition: { writes += 1 }, now: { clock.time }, pause: clock.pause)
        XCTAssertEqual(actual, target)
        XCTAssertEqual(reads, 2)
        XCTAssertGreaterThanOrEqual(clock.time, 0.02)
        XCTAssertEqual(writes, 0)
    }

    func testDelayedPositionIsRetriedWithoutChangingSizeAndMustSettle() throws {
        let clock = Clock()
        var retries: [TimeInterval] = []
        var current = WindowFrame(x: 323, y: 189, width: 729, height: 415)
        let actual = try WindowFrameSettlement.settledFrame(target: target, strict: false, read: { current }, retryPosition: {
            retries.append(clock.time)
            if retries.count == 2 { current.x = self.target.x; current.y = self.target.y }
        }, now: { clock.time }, pause: clock.pause)
        XCTAssertEqual(actual, target)
        XCTAssertEqual(retries.count, 2)
        XCTAssertEqual(retries[0], 0.12, accuracy: 0.0001)
        XCTAssertEqual(retries[1], 0.32, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(clock.time, 0.34 - 0.0001)
        XCTAssertLessThanOrEqual(clock.time, 0.6 + 0.0001)
    }

    func testLateSizeResponseIsObservedWithoutResendingSize() throws {
        let clock = Clock()
        var retries = 0
        let old = WindowFrame(x: 741, y: 33, width: 1000, height: 700)
        let actual = try WindowFrameSettlement.settledFrame(target: target, strict: false, read: {
            clock.time < 0.2 ? old : self.target
        }, retryPosition: { retries += 1 }, now: { clock.time }, pause: clock.pause)
        XCTAssertEqual(actual, target)
        XCTAssertEqual(retries, 1)
        XCTAssertGreaterThanOrEqual(clock.time, 0.22 - 0.0001)
    }

    func testPersistentMinimumSizeConstraintReturnsActualAfterBoundedRetries() throws {
        let clock = Clock()
        var reads = 0
        var retries = 0
        let constrained = WindowFrame(x: target.x, y: target.y, width: target.width + 18, height: target.height)
        let actual = try WindowFrameSettlement.settledFrame(target: target, strict: false, read: {
            reads += 1; return constrained
        }, retryPosition: { retries += 1 }, now: { clock.time }, pause: clock.pause)
        XCTAssertEqual(actual, constrained)
        XCTAssertFalse(WindowFrameFit.accepts(actual, target: target))
        XCTAssertEqual(retries, 2)
        XCTAssertLessThan(reads, 64)
        XCTAssertEqual(clock.time, 0.6, accuracy: 0.0001)
    }

    func testStrictRestorationNeverAcceptsAnInwardGridShrink() throws {
        let clock = Clock()
        let smaller = WindowFrame(x: target.x, y: target.y, width: target.width - 12, height: target.height - 10)
        let actual = try WindowFrameSettlement.settledFrame(target: target, strict: true, read: { smaller },
            retryPosition: {}, now: { clock.time }, pause: clock.pause)
        XCTAssertEqual(actual, smaller)
        XCTAssertFalse(WindowFrameFit.restored(actual, before: target))
        XCTAssertTrue(WindowFrameFit.accepts(actual, target: target))
        XCTAssertEqual(clock.time, 0.6, accuracy: 0.0001)
    }

    func testFrameThatMovesAgainDuringConfirmationNeedsAnotherStablePair() throws {
        let clock = Clock()
        var reads = 0
        let wrong = WindowFrame(x: 323, y: 189, width: target.width, height: target.height)
        let actual = try WindowFrameSettlement.settledFrame(target: target, strict: false, read: {
            reads += 1
            return reads == 2 ? wrong : self.target
        }, retryPosition: {}, now: { clock.time }, pause: clock.pause)
        XCTAssertEqual(actual, target)
        XCTAssertGreaterThanOrEqual(reads, 4)
        XCTAssertGreaterThanOrEqual(clock.time, 0.08 - 0.0001)
    }

    func testFrameArrivingOnlyAtDeadlineCannotBeReportedAsStableSuccess() throws {
        let clock = Clock()
        let wrong = WindowFrame(x: 323, y: 189, width: target.width, height: target.height)
        XCTAssertThrowsError(try WindowFrameSettlement.settledFrame(target: target, strict: false, read: {
            clock.time >= 0.6 - 0.0001 ? self.target : wrong
        }, retryPosition: {}, now: { clock.time }, pause: clock.pause)) {
            XCTAssertTrue($0 is WindowFrameSettlement.SettlementError)
        }
    }

    func testReadAndRetryErrorsPropagateWithoutBeingConvertedToSuccessfulGeometry() throws {
        enum Failure: Error { case read, write }
        let clock = Clock()
        XCTAssertThrowsError(try WindowFrameSettlement.settledFrame(target: target, strict: false,
            read: { throw Failure.read }, retryPosition: {}, now: { clock.time }, pause: clock.pause)) {
            XCTAssertEqual($0 as? Failure, .read)
        }
        let wrong = WindowFrame(x: 0, y: 0, width: target.width, height: target.height)
        XCTAssertThrowsError(try WindowFrameSettlement.settledFrame(target: target, strict: false,
            read: { wrong }, retryPosition: { throw Failure.write }, now: { clock.time }, pause: clock.pause)) {
            XCTAssertEqual($0 as? Failure, .write)
        }
    }

    func testFrozenClockStillTerminatesWithOnlyTwoPositionRetries() throws {
        var reads = 0
        var writes = 0
        var paused: TimeInterval = 0
        let wrong = WindowFrame(x: 0, y: 0, width: target.width, height: target.height)
        let actual = try WindowFrameSettlement.settledFrame(target: target, strict: false, read: {
            reads += 1; return wrong
        }, retryPosition: { writes += 1 }, now: { 100 }, pause: { paused += $0 })
        XCTAssertEqual(actual, wrong)
        XCTAssertLessThanOrEqual(reads, 64)
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(paused, 0.6, accuracy: 0.0001)
    }

    func testTemporarilyUnreadableGeometryMustRecoverAndConfirmAStablePair() throws {
        let clock = Clock()
        var readTimes: [TimeInterval] = []
        let actual = try WindowFrameSettlement.settledFrame(target: target, strict: true, read: {
            readTimes.append(clock.time)
            return clock.time < 0.2 ? nil : self.target
        }, retryPosition: {}, now: { clock.time }, pause: clock.pause)
        XCTAssertEqual(actual, target)
        XCTAssertGreaterThanOrEqual(clock.time, 0.22 - 0.0001)
        XCTAssertGreaterThanOrEqual(readTimes.suffix(2).last! - readTimes.suffix(2).first!, 0.02 - 0.0001)
    }

    func testContinuouslyUnreadableGeometryFailsWithoutInventingAnActualFrame() throws {
        let clock = Clock()
        var reads = 0
        XCTAssertThrowsError(try WindowFrameSettlement.settledFrame(target: target, strict: false, read: {
            reads += 1
            return nil
        }, retryPosition: {}, now: { clock.time }, pause: clock.pause)) {
            guard let error = $0 as? WindowFrameSettlement.SettlementError else {
                return XCTFail("Expected unreadableFrame, got \($0)")
            }
            if case .unreadableFrame = error {} else { XCTFail("Expected unreadableFrame") }
        }
        XCTAssertLessThanOrEqual(reads, 64)
        XCTAssertEqual(clock.time, 0.6, accuracy: 0.0001)
    }

    func testDelayedMinimizedFlagAndFalseTargetBothRequireConfirmation() throws {
        for target in [true, false] {
            let clock = Clock()
            var readTimes: [TimeInterval] = []
            let settled = try WindowFrameSettlement.settledMinimized(target: target, read: {
                readTimes.append(clock.time)
                return clock.time >= 0.2 ? target : !target
            }, now: { clock.time }, pause: clock.pause)
            XCTAssertTrue(settled)
            XCTAssertGreaterThanOrEqual(clock.time, 0.22 - 0.0001)
            XCTAssertGreaterThanOrEqual(readTimes.suffix(2).last! - readTimes.suffix(2).first!, 0.02 - 0.0001)
        }
    }

    func testMinimizedMismatchTimeoutAndFrozenClockReturnFalse() throws {
        let clock = Clock()
        XCTAssertFalse(try WindowFrameSettlement.settledMinimized(target: true, read: { false }, now: { clock.time }, pause: clock.pause))
        XCTAssertEqual(clock.time, 2, accuracy: 0.0001)
        var reads = 0
        var paused: TimeInterval = 0
        XCTAssertFalse(try WindowFrameSettlement.settledMinimized(target: true, read: {
            reads += 1; return false
        }, now: { 0 }, pause: { paused += $0 }))
        XCTAssertLessThanOrEqual(reads, 128)
        XCTAssertEqual(paused, 2, accuracy: 0.0001)
    }

    func testMinimizedAnimationCanFinishAfterGeometryDeadlineButBeforeItsOwnDeadline() throws {
        let clock = Clock()
        let settled = try WindowFrameSettlement.settledMinimized(target: true, read: {
            clock.time >= 1.2 ? true : nil
        }, now: { clock.time }, pause: clock.pause)
        XCTAssertTrue(settled)
        XCTAssertGreaterThanOrEqual(clock.time, 1.22 - 0.0001)
        XCTAssertLessThan(clock.time, 2)
    }

    func testUnavailableMinimizedFlagWaitsAndResetsAnEarlierMatchingSample() throws {
        let clock = Clock()
        let observations: [Bool?] = [nil, true, nil, true, true]
        var reads = 0
        let settled = try WindowFrameSettlement.settledMinimized(target: true, read: {
            let value = observations[min(reads, observations.count - 1)]
            reads += 1
            return value
        }, now: { clock.time }, pause: clock.pause)
        XCTAssertTrue(settled)
        XCTAssertEqual(reads, 5)
        XCTAssertGreaterThanOrEqual(clock.time, 0.12 - 0.0001)
    }

    func testContinuouslyUnavailableMinimizedFlagTimesOutWithoutInventingAState() throws {
        for target in [true, false] {
            let clock = Clock()
            var reads = 0
            let settled = try WindowFrameSettlement.settledMinimized(target: target, read: {
                reads += 1
                return nil
            }, now: { clock.time }, pause: clock.pause)
            XCTAssertFalse(settled)
            XCTAssertLessThanOrEqual(reads, 128)
            XCTAssertEqual(clock.time, 2, accuracy: 0.0001)
        }
    }

    func testMinimizedReadFailurePropagatesAndAFlagFirstSeenAtDeadlineIsUnconfirmed() throws {
        enum Failure: Error { case read }
        let clock = Clock()
        XCTAssertThrowsError(try WindowFrameSettlement.settledMinimized(target: false, read: { throw Failure.read },
            now: { clock.time }, pause: clock.pause)) {
            XCTAssertEqual($0 as? Failure, .read)
        }
        XCTAssertFalse(try WindowFrameSettlement.settledMinimized(target: true, read: {
            clock.time >= 2 - 0.0001
        }, now: { clock.time }, pause: clock.pause))
    }
}
