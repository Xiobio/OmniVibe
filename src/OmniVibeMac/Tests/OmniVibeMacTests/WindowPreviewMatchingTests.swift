import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class WindowPreviewMatchingTests: XCTestCase {
    private func descriptor(title: String = "Project — Terminal", frame: WindowFrame? = nil,
                            processID: Int32 = 120, started: Date? = Date(timeIntervalSince1970: 1)) -> WindowPreviewDescriptor {
        WindowPreviewDescriptor(window: WindowIdentity(processID: processID, processStartedAt: started,
            bundleIdentifier: "com.example.Terminal", applicationName: "Terminal", title: title),
            frame: frame ?? WindowFrame(x: -800, y: 40, width: 720, height: 480), title: title)
    }

    private func candidate(_ id: UInt32, title: String? = "Project — Terminal", frame: WindowFrame? = nil,
                           processID: Int32 = 120, bundle: String? = "com.example.Terminal") -> WindowPreviewCandidate {
        WindowPreviewCandidate(windowID: id, processID: processID, bundleIdentifier: bundle, title: title,
            frame: frame ?? WindowFrame(x: -800, y: 40, width: 720, height: 480))
    }

    func testMatchesExactMetadataIncludingNegativeScreenCoordinates() {
        XCTAssertEqual(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [candidate(80)]), 80)
    }

    func testSameTitleInSameApplicationNeedsDistinctGeometry() {
        let other = candidate(81, frame: WindowFrame(x: 100, y: 60, width: 720, height: 480))
        XCTAssertEqual(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [other, candidate(80)]), 80)
    }

    func testStackedSameTitleWindowsRemainAmbiguous() {
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [candidate(80), candidate(81)]))
    }

    func testDoesNotMatchAnotherProcessOrApplication() {
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [candidate(80, processID: 121)]))
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [candidate(80, bundle: "com.example.Other")]))
    }

    func testDoesNotGuessFromSimilarOrMissingTitles() {
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [candidate(80, title: "Project — Terminal (2)")]))
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [candidate(80, title: nil)]))
    }

    func testGeometryToleranceDoesNotBecomeFuzzyWindowSelection() {
        let smallRounding = candidate(80, frame: WindowFrame(x: -799, y: 41, width: 719, height: 481))
        XCTAssertEqual(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [smallRounding]), 80)
        let moved = candidate(81, frame: WindowFrame(x: -790, y: 40, width: 720, height: 480))
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [moved]))
    }

    func testInvalidTokensAndGeometryCannotSelectContent() {
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(started: nil), candidates: [candidate(80)]))
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(processID: 0), candidates: [candidate(80, processID: 0)]))
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [candidate(0)]))
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(frame: WindowFrame(x: .nan, y: 0, width: 1, height: 1)), candidates: [candidate(80)]))
        XCTAssertNil(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [candidate(80, frame: WindowFrame(x: -800, y: 40, width: 0, height: 480))]))
    }

    func testRepeatedMetadataForSameCGWindowIsNotASecondWindow() {
        XCTAssertEqual(WindowPreviewMatcher.uniqueWindowID(for: descriptor(), candidates: [candidate(80), candidate(80)]), 80)
    }
}
