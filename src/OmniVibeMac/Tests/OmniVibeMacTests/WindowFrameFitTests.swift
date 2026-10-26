import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class WindowFrameFitTests: XCTestCase {
    private let target = WindowFrame(x: 100, y: 80, width: 800, height: 600)

    func testExactFrameFits() {
        XCTAssertTrue(WindowFrameFit.accepts(target, target: target))
    }

    func testCharacterGridMayShrinkInsideCell() {
        XCTAssertTrue(WindowFrameFit.accepts(WindowFrame(x: 100, y: 80, width: 792, height: 584), target: target))
    }

    func testInwardShrinkHasABoundedTolerance() {
        XCTAssertTrue(WindowFrameFit.accepts(WindowFrame(x: 100, y: 80, width: 768, height: 568), target: target))
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: 100, y: 80, width: 767.9, height: 568), target: target))
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: 100, y: 80, width: 768, height: 567.9), target: target))
    }

    func testApplicationMinimumSizeCannotGrowBeyondCell() {
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: 100, y: 80, width: 820, height: 600), target: target))
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: 100, y: 80, width: 800, height: 620), target: target))
    }

    func testTwoPointPositionToleranceIsInclusive() {
        XCTAssertTrue(WindowFrameFit.accepts(WindowFrame(x: 102, y: 82, width: 798, height: 598), target: target))
        XCTAssertTrue(WindowFrameFit.accepts(WindowFrame(x: 98, y: 78, width: 800, height: 600), target: target))
    }

    func testPositionOutsideTwoPointsIsRejectedEvenWhenSizeFits() {
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: 102.1, y: 80, width: 790, height: 590), target: target))
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: 100, y: 77.9, width: 790, height: 590), target: target))
    }

    func testRightEdgeMustFitEvenIfPositionAndWidthIndividuallyMatchTolerance() {
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: 102, y: 80, width: 801, height: 600), target: target))
        XCTAssertTrue(WindowFrameFit.accepts(WindowFrame(x: 102, y: 80, width: 800, height: 600), target: target))
    }

    func testBottomEdgeMustFitEvenIfPositionAndHeightIndividuallyMatchTolerance() {
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: 100, y: 82, width: 800, height: 601), target: target))
        XCTAssertTrue(WindowFrameFit.accepts(WindowFrame(x: 100, y: 82, width: 800, height: 600), target: target))
    }

    func testOldThirtyTwoPointToleranceCouldOverlapTwelvePointGap() {
        let left = WindowFrame(x: 100, y: 80, width: 400, height: 600)
        let right = WindowFrame(x: 512, y: 80, width: 400, height: 600)
        let oversizedLeft = WindowFrame(x: 100, y: 80, width: 420, height: 600)
        XCTAssertTrue(oversizedLeft.x + oversizedLeft.width > right.x)
        XCTAssertFalse(WindowFrameFit.accepts(oversizedLeft, target: left))
    }

    func testAcceptedRoundingCannotConsumeTwelvePointGap() {
        let left = WindowFrame(x: 100, y: 80, width: 400, height: 600)
        let right = WindowFrame(x: 512, y: 80, width: 400, height: 600)
        let actualLeft = WindowFrame(x: 102, y: 80, width: 400, height: 600)
        let actualRight = WindowFrame(x: 510, y: 80, width: 400, height: 600)
        XCTAssertTrue(WindowFrameFit.accepts(actualLeft, target: left))
        XCTAssertTrue(WindowFrameFit.accepts(actualRight, target: right))
        XCTAssertEqual(actualRight.x - actualLeft.x - actualLeft.width, 8)
    }

    func testNegativeDisplayCoordinatesUseTheSameEdgeRules() {
        let negative = WindowFrame(x: -1200, y: -800, width: 800, height: 600)
        XCTAssertTrue(WindowFrameFit.accepts(WindowFrame(x: -1199, y: -799, width: 790, height: 590), target: negative))
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: -1197, y: -800, width: 790, height: 590), target: negative))
    }

    func testInvalidAndOverflowingGeometryIsRejected() {
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: .nan, y: 80, width: 800, height: 600), target: target))
        XCTAssertFalse(WindowFrameFit.accepts(WindowFrame(x: 100, y: 80, width: 0, height: 600), target: target))
        XCTAssertFalse(WindowFrameFit.accepts(target, target: WindowFrame(x: .greatestFiniteMagnitude,
            y: 80, width: .greatestFiniteMagnitude, height: 600)))
    }

    func testRollbackCannotHideAnotherCharacterGridShrink() {
        let smaller = WindowFrame(x: 100, y: 80, width: 792, height: 584)
        XCTAssertTrue(WindowFrameFit.accepts(smaller, target: target))
        XCTAssertFalse(WindowFrameFit.restored(smaller, before: target))
        XCTAssertTrue(WindowFrameFit.restored(target, before: target))
    }

    func testSizeFeedbackCompensatesObservedSixByFourDecorationOffset() throws {
        let requested = WindowFrame(x: 741, y: 33, width: 729, height: 415)
        let actual = WindowFrame(x: 741, y: 33, width: 735, height: 419)
        let correction = try XCTUnwrap(WindowFrameFit.correctedSizeRequest(target: requested, actual: actual))
        XCTAssertEqual(correction, WindowFrame(x: 741, y: 33, width: 723, height: 411))
        XCTAssertFalse(WindowFrameFit.accepts(actual, target: requested))
        XCTAssertFalse(WindowFrameFit.restored(actual, before: requested))
        XCTAssertTrue(WindowFrameFit.accepts(requested, target: requested))
    }

    func testSizeFeedbackDoesNotTreatApplicationMinimumClampAsSuccess() throws {
        let requested = WindowFrame(x: 494, y: 33, width: 482, height: 415)
        let minimum = WindowFrame(x: 494, y: 33, width: 500, height: 415)
        let correction = try XCTUnwrap(WindowFrameFit.correctedSizeRequest(target: requested, actual: minimum))
        XCTAssertEqual(correction.width, 464)
        XCTAssertEqual(correction.height, 415)
        // The app may clamp the corrective request to 500 again. Verification
        // must still use the original 482-point cell rather than the request.
        XCTAssertFalse(WindowFrameFit.accepts(minimum, target: requested))
        XCTAssertFalse(WindowFrameFit.restored(minimum, before: requested))
        XCTAssertNotNil(WindowFrameFit.constraint(minimum, target: requested))
    }

    func testSizeFeedbackRequiresAtLeastOneErrorAboveTwoPoints() {
        XCTAssertNil(WindowFrameFit.correctedSizeRequest(target: target, actual: target))
        XCTAssertNil(WindowFrameFit.correctedSizeRequest(target: target,
            actual: WindowFrame(x: 100, y: 80, width: 802, height: 598)))
        XCTAssertEqual(WindowFrameFit.correctedSizeRequest(target: target,
            actual: WindowFrame(x: 100, y: 80, width: 801, height: 604)),
            WindowFrame(x: 100, y: 80, width: 799, height: 596))
    }

    func testSizeFeedbackAllowsBothSignsAndInclusiveThirtyTwoPointBound() {
        XCTAssertEqual(WindowFrameFit.correctedSizeRequest(target: target,
            actual: WindowFrame(x: 100, y: 80, width: 768, height: 632)),
            WindowFrame(x: 100, y: 80, width: 832, height: 568))
        XCTAssertNil(WindowFrameFit.correctedSizeRequest(target: target,
            actual: WindowFrame(x: 100, y: 80, width: 767.9, height: 604)))
        XCTAssertNil(WindowFrameFit.correctedSizeRequest(target: target,
            actual: WindowFrame(x: 100, y: 80, width: 804, height: 632.1)))
    }

    func testSizeFeedbackAccumulatesFromLastRequestInsteadOfResettingCompensation() {
        let original = WindowFrame(x: 100, y: 80, width: 1018, height: 600)
        let last = WindowFrame(x: 100, y: 80, width: 1012, height: 596)
        let actual = WindowFrame(x: 100, y: 80, width: 1022, height: 598)
        XCTAssertEqual(WindowFrameFit.correctedSizeRequest(target: original, actual: actual, lastRequested: last),
            WindowFrame(x: 100, y: 80, width: 1008, height: 598))
    }

    func testSizeFeedbackRejectsCumulativeOffsetBeyondThirtyTwoPointsOnEitherAxis() {
        XCTAssertNil(WindowFrameFit.correctedSizeRequest(target: target,
            actual: WindowFrame(x: 100, y: 80, width: 804, height: 600),
            lastRequested: WindowFrame(x: 100, y: 80, width: 768, height: 600)))
        XCTAssertNil(WindowFrameFit.correctedSizeRequest(target: target,
            actual: WindowFrame(x: 100, y: 80, width: 800, height: 596),
            lastRequested: WindowFrame(x: 100, y: 80, width: 800, height: 632)))
        XCTAssertEqual(WindowFrameFit.correctedSizeRequest(target: target,
            actual: WindowFrame(x: 100, y: 80, width: 804, height: 600),
            lastRequested: WindowFrame(x: 100, y: 80, width: 772, height: 600)),
            WindowFrame(x: 100, y: 80, width: 768, height: 600))
    }

    func testSizeFeedbackRejectsNonFiniteAndNonPositiveGeometry() {
        for invalid in [WindowFrame(x: 100, y: 80, width: .nan, height: 600),
                        WindowFrame(x: 100, y: 80, width: .infinity, height: 600),
                        WindowFrame(x: 100, y: 80, width: -1, height: 600),
                        WindowFrame(x: 100, y: 80, width: 800, height: 0),
                        WindowFrame(x: .nan, y: 80, width: 804, height: 604)] {
            XCTAssertNil(WindowFrameFit.correctedSizeRequest(target: target, actual: invalid))
            XCTAssertNil(WindowFrameFit.correctedSizeRequest(target: invalid, actual: target))
        }
    }

    func testSizeFeedbackRejectsNonPositiveCorrectedRequestAndKeepsTargetPosition() {
        let small = WindowFrame(x: -200, y: 33, width: 10, height: 20)
        XCTAssertNil(WindowFrameFit.correctedSizeRequest(target: small,
            actual: WindowFrame(x: -200, y: 33, width: 42, height: 20)))
        XCTAssertEqual(WindowFrameFit.correctedSizeRequest(target: target,
            actual: WindowFrame(x: 101, y: 79, width: 806, height: 604)),
            WindowFrame(x: 100, y: 80, width: 794, height: 596))
    }

    func testRestrictionMessageIncludesRequiredAndActualSize() {
        let message = WindowFrameFit.restrictionDescription(target: target,
            actual: WindowFrame(x: 100, y: 80, width: 850, height: 620))
        XCTAssertTrue(message.contains("要求 800.0 × 600.0 pt"))
        XCTAssertTrue(message.contains("实际 850.0 × 620.0 pt"))
    }

    func testObservedMinimumWidthIsReportedAsAStructuredConstraint() throws {
        let requested = WindowFrame(x: 494, y: 33, width: 482, height: 851)
        let actual = WindowFrame(x: 494, y: 33, width: 500, height: 849)
        let error = try XCTUnwrap(WindowFrameFit.constraint(actual, target: requested))
        XCTAssertEqual(error.requested, requested)
        XCTAssertEqual(error.actual, actual)
        XCTAssertNil(error.recoveryFailure)
        XCTAssertTrue(error.localizedDescription.contains("要求 482.0 × 851.0 pt"))
        XCTAssertTrue(error.localizedDescription.contains("实际 500.0 × 849.0 pt"))
    }

    func testAcceptedCharacterGridShrinkDoesNotGenerateAConstraint() {
        XCTAssertNil(WindowFrameFit.constraint(WindowFrame(x: 100, y: 80, width: 792, height: 584), target: target))
    }

    func testRecoveryFailureKeepsRequestedAndActualFrameInformation() {
        let actual = WindowFrame(x: 100, y: 80, width: 850, height: 620)
        var error = WindowFrameConstraintError(requested: target, actual: actual)
        error.recoveryFailure = "读取原窗口超时"
        XCTAssertEqual(error.requested, target)
        XCTAssertEqual(error.actual, actual)
        XCTAssertEqual(error.recoveryFailure, "读取原窗口超时")
        XCTAssertTrue(error.localizedDescription.contains("原窗口状态未能完整恢复"))
    }
}
