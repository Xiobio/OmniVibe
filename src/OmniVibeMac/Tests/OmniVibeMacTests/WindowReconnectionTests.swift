import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class WindowReconnectionTests: XCTestCase {
    private let frame = WindowFrame(x: -800, y: 40, width: 720, height: 480)

    func testInvalidProxyWithUnavailableServerInventoryDoesNotProveClosure() {
        XCTAssertFalse(WindowReconnectionMatcher.isClosedAfterInvalidProxy(windowNumber: 80, processID: 120, server: nil))
        XCTAssertFalse(WindowReconnectionMatcher.isClosedAfterInvalidProxy(windowNumber: 80, processID: 120, server: [cg()]))
        XCTAssertTrue(WindowReconnectionMatcher.isClosedAfterInvalidProxy(windowNumber: 80, processID: 120, server: []))
        XCTAssertTrue(WindowReconnectionMatcher.isClosedAfterInvalidProxy(windowNumber: 80, processID: 120, server: [cg(pid: 121)]))
    }

    private func ax(_ index: Int = 0, pid: Int32 = 120, title: String = "Project", frame: WindowFrame? = nil) -> AccessibilityWindowCandidate {
        AccessibilityWindowCandidate(index: index, processID: pid, title: title, frame: frame ?? self.frame)
    }

    private func cg(_ number: UInt32 = 80, pid: Int32 = 120, title: String? = "Project", frame: WindowFrame? = nil, layer: Int = 0) -> WindowServerCandidate {
        WindowServerCandidate(number: number, processID: pid, title: title, frame: frame ?? self.frame, layer: layer)
    }

    private func identity(number: UInt32? = 80, session: String? = "user:boot:login", pid: Int32 = 120,
                          started: Date? = Date(timeIntervalSince1970: 10), bundle: String? = "com.example.Terminal",
                          title: String = "Project") -> WindowIdentity {
        WindowIdentity(processID: pid, processStartedAt: started, bundleIdentifier: bundle,
            applicationName: "Terminal", title: title, platformWindowNumber: number, platformSessionID: session)
    }

    func testUniqueCurrentAXToWindowServerAssociationIncludesNegativeCoordinates() {
        XCTAssertEqual(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg()]), 80)
        let other = WindowFrame(x: 100, y: 80, width: 720, height: 480)
        XCTAssertEqual(WindowReconnectionMatcher.uniqueWindowNumber(for: 0,
            accessibility: [ax(), ax(1, frame: other)], server: [cg(81, frame: other), cg()]), 80)
    }

    func testRedactedTitleStillNeedsUniqueGeometryAndVisibleTitleMustMatchExactly() {
        XCTAssertEqual(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg(title: nil)]), 80)
        XCTAssertEqual(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg(title: "")]), 80)
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg(title: "Project (2)")]))
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg(title: "project")]))
    }

    func testSameGeometryMultipleCGWindowsIsAmbiguousEvenWithDifferentTitles() {
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0,
            accessibility: [ax()], server: [cg(), cg(81, title: "Other")]))
    }

    func testSameGeometryMultipleAXWindowsIsAmbiguousEvenWithDifferentTitles() {
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0,
            accessibility: [ax(), ax(1, title: "Other")], server: [cg()]))
    }

    func testRoundingNeedsUniqueReverseAssociationAndCannotExceedTwoPoints() {
        let rounded = WindowFrame(x: -799, y: 41, width: 719, height: 481)
        XCTAssertEqual(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg(frame: rounded)]), 80)
        let opposite = WindowFrame(x: -797, y: 40, width: 720, height: 480)
        let middle = WindowFrame(x: -798, y: 40, width: 720, height: 480)
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0,
            accessibility: [ax(), ax(1, frame: opposite)], server: [cg(frame: middle)]))
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg()], tolerance: 3))
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg()], tolerance: .nan))
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg()], tolerance: -1))
    }

    func testOtherOwnersLayersInvalidNumbersAndMissingIndicesCannotMatch() {
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg(pid: 121)]))
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg(layer: 3)]))
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg(0)]))
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 1, accessibility: [ax()], server: [cg()]))
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax(), ax()], server: [cg()]))
        let invalid = WindowFrame(x: .infinity, y: 0, width: 720, height: 480)
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax(frame: invalid)], server: [cg()]))
        XCTAssertNil(WindowReconnectionMatcher.uniqueWindowNumber(for: 0, accessibility: [ax()], server: [cg(frame: invalid)]))
    }

    func testAliasPreservesSavedUUIDButUsesFreshTitleWithoutMatchingTheOldTitle() throws {
        let saved = identity(title: "Old title")
        let current = identity(title: "Renamed while OmniVibe was closed")
        let restored = try XCTUnwrap(WindowReconnectionMatcher.alias(saved: saved, current: current, sessionID: "user:boot:login"))
        XCTAssertEqual(restored.id, saved.id)
        XCTAssertEqual(restored.title, current.title)
        XCTAssertEqual(restored.platformWindowNumber, 80)
        XCTAssertNotEqual(current.id, saved.id)
    }

    func testAliasRejectsLegacyWorkspaceOrDifferentWindowDespiteSameTitle() {
        let current = identity()
        XCTAssertNil(WindowReconnectionMatcher.alias(saved: identity(number: nil), current: current, sessionID: "user:boot:login"))
        XCTAssertNil(WindowReconnectionMatcher.alias(saved: identity(session: nil), current: current, sessionID: "user:boot:login"))
        XCTAssertNil(WindowReconnectionMatcher.alias(saved: identity(number: 81), current: current, sessionID: "user:boot:login"))
        XCTAssertNil(WindowReconnectionMatcher.alias(saved: identity(), current: identity(number: nil), sessionID: "user:boot:login"))
    }

    func testAliasRejectsLoginSessionBootChangeAndReusedProcess() {
        let saved = identity()
        for current in [identity(session: "user:newboot:login"), identity(pid: 121),
                        identity(started: Date(timeIntervalSince1970: 11)), identity(started: nil),
                        identity(bundle: "com.example.Other")] {
            XCTAssertNil(WindowReconnectionMatcher.alias(saved: saved, current: current, sessionID: "user:boot:login"))
        }
        XCTAssertNil(WindowReconnectionMatcher.alias(saved: saved, current: identity(), sessionID: nil))
        XCTAssertNil(WindowReconnectionMatcher.alias(saved: saved, current: identity(), sessionID: "differentLogin"))
    }
}
