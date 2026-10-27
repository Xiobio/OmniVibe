import XCTest
@testable import OmniVibeMac

final class WindowEnhancedUIAdjustmentTests: XCTestCase {
    private enum Failure: Error, Equatable { case adjustment, disable, restore, verification }

    @MainActor
    func testEnabledModeIsRestoredBeforeFinalGeometryConfirmation() throws {
        var state = true
        var writes: [Bool] = []
        let result = try WindowEnhancedUIAdjustment.perform(read: { state }, isSettable: { true },
            write: { state = $0; writes.append($0) },
            adjustment: { XCTAssertFalse(state); return 17 },
            verifyRestored: { value in XCTAssertTrue(state); return value })
        XCTAssertEqual(result, 17)
        XCTAssertEqual(writes, [false, true])
        XCTAssertTrue(state)
    }

    @MainActor
    func testDisabledAndUnknownModesAreNeverEnabledOrWritten() throws {
        for original: Bool? in [false, nil] {
            var writes: [Bool] = []
            let result = try WindowEnhancedUIAdjustment.perform(read: { original }, isSettable: { true },
                write: { writes.append($0) }, adjustment: { 17 },
                verifyRestored: { _ in XCTFail("An untouched mode needs no restoration callback"); return 0 })
            XCTAssertEqual(result, 17)
            XCTAssertTrue(writes.isEmpty)
        }
    }

    @MainActor
    func testEnabledButReadonlyModeIsNotChanged() throws {
        var writes: [Bool] = []
        _ = try WindowEnhancedUIAdjustment.perform(read: { true }, isSettable: { false },
            write: { writes.append($0) }, adjustment: { 17 }, verifyRestored: { $0 })
        XCTAssertTrue(writes.isEmpty)
    }

    @MainActor
    func testThrowingAdjustmentStillRestoresOriginalEnabledState() {
        var state = true
        var writes: [Bool] = []
        XCTAssertThrowsError(try WindowEnhancedUIAdjustment.perform(read: { state }, isSettable: { true },
            write: { state = $0; writes.append($0) },
            adjustment: { () throws -> Int in throw Failure.adjustment }, verifyRestored: { $0 })) { error in
                XCTAssertEqual(error as? Failure, .adjustment)
            }
        XCTAssertEqual(writes, [false, true])
        XCTAssertTrue(state)
    }

    @MainActor
    func testUnconfirmedDisableStillRestoresAndDoesNotRunAdjustment() {
        var state = true
        var writes: [Bool] = []
        XCTAssertThrowsError(try WindowEnhancedUIAdjustment.perform(read: { state }, isSettable: { true },
            write: { enabled in
                writes.append(enabled); state = enabled
                if !enabled { throw WindowEnhancedUIAdjustment.UnconfirmedDisable(underlyingError: Failure.disable) }
            },
            adjustment: { XCTFail("Do not adjust after disabling failed"); return 17 }, verifyRestored: { $0 })) { error in
                XCTAssertEqual(error as? Failure, .disable)
            }
        XCTAssertEqual(writes, [false, true])
        XCTAssertTrue(state, "An accepted disable write still requires restoration when its confirmation fails.")
    }

    @MainActor
    func testUnsupportedDisableKeepsTheEnabledModeAndStillAdjustsGeometry() throws {
        var writes: [Bool] = []
        var adjustments = 0
        let result = try WindowEnhancedUIAdjustment.perform(read: { true }, isSettable: { true },
            write: { enabled in
                writes.append(enabled)
                throw WindowEnhancedUIAdjustment.UnsupportedDisable(underlyingError: Failure.disable)
            },
            adjustment: { adjustments += 1; return 17 },
            verifyRestored: { _ in XCTFail("The original mode was never changed"); return 0 })
        XCTAssertEqual(result, 17)
        XCTAssertEqual(adjustments, 1)
        XCTAssertEqual(writes, [false], "A rejected optional disable must not invent a restore write.")
    }

    @MainActor
    func testUnsupportedDisableNeverHidesARealGeometryFailure() {
        var writes: [Bool] = []
        XCTAssertThrowsError(try WindowEnhancedUIAdjustment.perform(read: { true }, isSettable: { true },
            write: { enabled in
                writes.append(enabled)
                throw WindowEnhancedUIAdjustment.UnsupportedDisable(underlyingError: Failure.disable)
            },
            adjustment: { () throws -> Int in throw Failure.adjustment },
            verifyRestored: { _ in XCTFail("The original mode was never changed"); return 0 })) { error in
                XCTAssertEqual(error as? Failure, .adjustment)
            }
        XCTAssertEqual(writes, [false])
    }

    @MainActor
    func testUnrelatedDisableFailureIsNotIgnoredOrTreatedAsASuccessfulWrite() {
        var writes: [Bool] = []
        XCTAssertThrowsError(try WindowEnhancedUIAdjustment.perform(read: { true }, isSettable: { true },
            write: { enabled in writes.append(enabled); throw Failure.disable },
            adjustment: { XCTFail("Only a rejected optional attribute may fall back"); return 17 },
            verifyRestored: { $0 })) { error in
                XCTAssertEqual(error as? Failure, .disable)
            }
        XCTAssertEqual(writes, [false])
    }

    @MainActor
    func testUnsupportedDisableRequiresConfirmationThatTheOriginalModeIsUnchanged() {
        var reads = 0
        XCTAssertThrowsError(try WindowEnhancedUIAdjustment.perform(
            read: { reads += 1; return reads == 1 ? true : nil }, isSettable: { true },
            write: { _ in throw WindowEnhancedUIAdjustment.UnsupportedDisable(underlyingError: Failure.disable) },
            adjustment: { XCTFail("Do not continue when the original mode cannot be verified"); return 17 },
            verifyRestored: { $0 })) { error in
                XCTAssertEqual(error as? Failure, .disable)
            }
    }

    @MainActor
    func testRestorationFailureCannotReportSuccessOrRunGeometryConfirmation() {
        var writes: [Bool] = []
        XCTAssertThrowsError(try WindowEnhancedUIAdjustment.perform(read: { true }, isSettable: { true },
            write: { enabled in writes.append(enabled); if enabled { throw Failure.restore } },
            adjustment: { 17 }, verifyRestored: { _ in XCTFail("Restoration failed"); return 0 })) { error in
                let failure = error as? WindowEnhancedUIAdjustment.RestorationFailure
                XCTAssertNil(failure?.adjustmentError)
                XCTAssertEqual(failure?.restorationError as? Failure, .restore)
            }
        XCTAssertEqual(writes, [false, true])
    }

    @MainActor
    func testAdjustmentAndRestorationFailuresAreBothRetained() {
        XCTAssertThrowsError(try WindowEnhancedUIAdjustment.perform(read: { true }, isSettable: { true },
            write: { if $0 { throw Failure.restore } },
            adjustment: { () throws -> Int in throw Failure.adjustment }, verifyRestored: { $0 })) { error in
                let failure = error as? WindowEnhancedUIAdjustment.RestorationFailure
                XCTAssertEqual(failure?.adjustmentError as? Failure, .adjustment)
                XCTAssertEqual(failure?.restorationError as? Failure, .restore)
            }
    }

    @MainActor
    func testFinalGeometryFailureIsReportedAfterModeHasAlreadyBeenRestored() {
        var state = true
        XCTAssertThrowsError(try WindowEnhancedUIAdjustment.perform(read: { state }, isSettable: { true },
            write: { state = $0 }, adjustment: { 17 },
            verifyRestored: { _ in XCTAssertTrue(state); throw Failure.verification })) { error in
                XCTAssertEqual(error as? Failure, .verification)
            }
        XCTAssertTrue(state)
    }
}
