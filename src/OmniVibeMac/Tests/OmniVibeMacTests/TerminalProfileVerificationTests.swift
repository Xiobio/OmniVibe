import OmniVibeCore
import XCTest
@testable import OmniVibeMac

final class TerminalProfileVerificationTests: XCTestCase {
    private let bounds = TerminalProfileWindowBounds(left: 586, top: 216, right: 1320, bottom: 657)

    func testSlowFirstMatchingReadMayConfirmWithASecondIdenticalRead() {
        XCTAssertEqual(TerminalProfileVerification.step(matches: true, previousBounds: nil,
            actualBounds: bounds, elapsed: 1.4, readCount: 1), .readAgain)
        XCTAssertEqual(TerminalProfileVerification.step(matches: true, previousBounds: bounds,
            actualBounds: bounds, elapsed: 2.8, readCount: 2), .complete)
    }

    func testExpiredNonmatchingReadTimesOutInsteadOfRequestingAnotherRead() {
        XCTAssertEqual(TerminalProfileVerification.step(matches: false, previousBounds: nil,
            actualBounds: bounds, elapsed: 0.71, readCount: 1), .timedOut)
        XCTAssertEqual(TerminalProfileVerification.step(matches: false, previousBounds: nil,
            actualBounds: bounds, elapsed: 0.2, readCount: 1), .readAgain)
    }

    func testFourUnstableReadsTimeOutEvenWhenTheLatestReadMatches() {
        var previous = bounds
        previous.right -= 1
        XCTAssertEqual(TerminalProfileVerification.step(matches: true, previousBounds: previous,
            actualBounds: bounds, elapsed: 0.1, readCount: 4), .timedOut)
        XCTAssertEqual(TerminalProfileVerification.step(matches: true, previousBounds: nil,
            actualBounds: bounds, elapsed: 4, readCount: 4), .timedOut)
    }

    func testSlowSecondReadThatNoLongerMatchesCannotUseTheFirstCandidateAsSuccess() {
        var changed = bounds
        changed.left += 20
        changed.right += 20
        XCTAssertEqual(TerminalProfileVerification.step(matches: false, previousBounds: bounds,
            actualBounds: changed, elapsed: 1.8, readCount: 2), .timedOut)
    }

    func testFourthReadMayCompleteAnAlreadyStableMatchingPair() {
        XCTAssertEqual(TerminalProfileVerification.step(matches: true, previousBounds: bounds,
            actualBounds: bounds, elapsed: 4, readCount: 4), .complete)
    }

    func testReadConfirmationPolicyKeepsExistingFrameFitAndRestorationLimits() {
        let target = WindowFrame(x: 586, y: 216, width: 734, height: 441)
        XCTAssertFalse(WindowFrameFit.accepts(.init(x: 589, y: 216, width: 734, height: 441), target: target))
        XCTAssertFalse(WindowFrameFit.accepts(.init(x: 586, y: 216, width: 701, height: 441), target: target))
        let gridAligned = WindowFrame(x: 586, y: 216, width: 703, height: 441)
        XCTAssertTrue(WindowFrameFit.accepts(gridAligned, target: target))
        XCTAssertFalse(WindowFrameFit.restored(gridAligned, before: target))
        XCTAssertTrue(WindowFrameFit.restored(target, before: target))
    }
}
