import AppKit
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class WheelDragGeometryTests: XCTestCase {
    func testLauncherPreferenceChangesTheOrbitButKeepsTheCollapsedEntryAt54Points() {
        XCTAssertEqual(WheelDragGeometry.physicalExtent(configured: 360, expanded: true), 360)
        for extent in [280.0, 360, 450, 520, .nan] {
            XCTAssertEqual(WheelDragGeometry.physicalExtent(configured: extent, expanded: false), 54)
        }
    }

    func testLauncherExtentGuardsInvalidAndOutOfRangeValues() {
        XCTAssertEqual(WheelDragGeometry.physicalExtent(configured: 100, expanded: true), 280)
        XCTAssertEqual(WheelDragGeometry.physicalExtent(configured: 900, expanded: true), 520)
        XCTAssertEqual(WheelDragGeometry.physicalExtent(configured: .nan, expanded: true), 360)
    }

    func testExpandedCoreHitTargetKeeps54PhysicalPointsAtEveryOrbitScale() {
        let area = NSRect(x: 0, y: 0, width: 1470, height: 850)
        let anchor = NSPoint(x: 700, y: 400)
        for extent in [280.0, 360, 520] {
            let layout = WheelDragGeometry.layout(anchor: anchor, configured: extent, expanded: true, workArea: area)
            XCTAssertTrue(WheelDragGeometry.coreContains(NSPoint(x: anchor.x + 26, y: anchor.y), layout: layout))
            XCTAssertFalse(WheelDragGeometry.coreContains(NSPoint(x: anchor.x + 28, y: anchor.y), layout: layout))
            XCTAssertEqual(layout.coreLogicalExtent * layout.scale, 54, accuracy: 0.00001)
        }
    }

    func testCollapsedArtworkKeepsItsWholeLogicalCanvasWhenTheEntryShrinks() {
        let anchor = NSPoint(x: 700, y: 400)
        let layout = WheelDragGeometry.layout(anchor: anchor, configured: 520, expanded: false,
            workArea: NSRect(x: 0, y: 0, width: 1470, height: 850))
        XCTAssertEqual(layout.frame.size, NSSize(width: 54, height: 54))
        XCTAssertEqual(layout.logicalSize, NSSize(width: 116, height: 116))
        XCTAssertEqual(layout.coreCentre, NSPoint(x: 58, y: 58))
        XCTAssertEqual(layout.coreLogicalExtent, 116)
        XCTAssertTrue(WheelDragGeometry.coreContains(NSPoint(x: anchor.x + 26, y: anchor.y), layout: layout))
        XCTAssertFalse(WheelDragGeometry.coreContains(NSPoint(x: anchor.x + 28, y: anchor.y), layout: layout))
    }

    func testHoverSuppressionUsesTheAnchoredCoreInsteadOfTheOffsetPanelMidpoint() {
        let anchor = NSPoint(x: 1412, y: 400)
        let layout = WheelDragGeometry.layout(anchor: anchor, configured: 520, expanded: true,
            workArea: NSRect(x: 0, y: 24, width: 1470, height: 850))
        XCTAssertTrue(WheelDragGeometry.coreContains(NSPoint(x: anchor.x + 34, y: anchor.y), layout: layout, margin: 8))
        XCTAssertFalse(WheelDragGeometry.coreContains(NSPoint(x: anchor.x + 36, y: anchor.y), layout: layout, margin: 8))
        XCTAssertFalse(WheelDragGeometry.coreContains(NSPoint(x: layout.frame.midX, y: layout.frame.midY), layout: layout))
    }

    func testScaledLauncherStillFitsASmallerWorkArea() {
        let area = NSRect(x: 0, y: 20, width: 450, height: 400)
        let requested = WheelDragGeometry.physicalExtent(configured: 520, expanded: true)
        let layout = WheelDragGeometry.layout(anchor: NSPoint(x: 400, y: 300),
            configured: Double(requested), expanded: true, workArea: area)
        XCTAssertTrue(area.contains(layout.frame))
        XCTAssertTrue(layout.slotScreenFrames.allSatisfy { area.contains($0) })
    }

    func testExternalCoreDropChoosesFirstEmptyFixedSlot() {
        XCTAssertEqual(WheelDragGeometry.externalDropDestination(inCore: true, hoveredSlot: 7,
            occupiedSlots: [1, 3]), .slot(2))
    }

    func testFullCoreDropIsRejectedForPhysicalRestoration() {
        XCTAssertEqual(WheelDragGeometry.externalDropDestination(inCore: true, hoveredSlot: nil,
            occupiedSlots: Set(1...9)), .noEmptySlot)
    }

    func testExternalDropCanTargetAnExplicitEmptySlot() {
        XCTAssertEqual(WheelDragGeometry.externalDropDestination(inCore: false, hoveredSlot: 4,
            occupiedSlots: [1, 3]), .slot(4))
    }

    func testExternalOccupiedDropHasAnExplicitRejectionReason() {
        XCTAssertEqual(WheelDragGeometry.externalDropDestination(inCore: false, hoveredSlot: 3,
            occupiedSlots: [1, 3]), .occupied(3))
    }

    func testExternalDropInTransparentGapIsRejected() {
        XCTAssertEqual(WheelDragGeometry.externalDropDestination(inCore: false, hoveredSlot: nil,
            occupiedSlots: [1, 3]), .outsideSlots)
    }

    func testExternalDropCannotChooseAnInvalidSlotNumber() {
        XCTAssertEqual(WheelDragGeometry.externalDropDestination(inCore: false, hoveredSlot: 10,
            occupiedSlots: []), .outsideSlots)
    }

    func testPrePressOriginWinsOverAnAlreadyMovedFreshSample() {
        let id = UUID()
        let original = WheelDragGeometry.DragOrigin(windowID: id, frame: WindowFrame(x: 100, y: 100, width: 800, height: 600))
        let moved = WheelDragGeometry.DragOrigin(windowID: id, frame: WindowFrame(x: 120, y: 100, width: 800, height: 600))
        XCTAssertEqual(WheelDragGeometry.initialDragOrigin(pressPoint: NSPoint(x: 150, y: 880),
            samplePoint: NSPoint(x: 170, y: 880), cached: original, fresh: moved, primaryTop: 1000), original)
    }

    func testFirstStationarySampleCanSupportANewlyActivatedWindow() {
        let fresh = WheelDragGeometry.DragOrigin(windowID: UUID(), frame: WindowFrame(x: 100, y: 100, width: 800, height: 600))
        XCTAssertEqual(WheelDragGeometry.initialDragOrigin(pressPoint: NSPoint(x: 150, y: 880),
            samplePoint: NSPoint(x: 151, y: 879), cached: nil, fresh: fresh, primaryTop: 1000), fresh)
    }

    func testFirstSampleCannotBecomeAnOriginAfterPointerMoved() {
        let fresh = WheelDragGeometry.DragOrigin(windowID: UUID(), frame: WindowFrame(x: 100, y: 100, width: 800, height: 600))
        XCTAssertNil(WheelDragGeometry.initialDragOrigin(pressPoint: NSPoint(x: 150, y: 880),
            samplePoint: NSPoint(x: 154, y: 880), cached: nil, fresh: fresh, primaryTop: 1000))
    }

    func testCachedDifferentWindowCannotSupplyTheOriginalFrame() {
        let cached = WheelDragGeometry.DragOrigin(windowID: UUID(), frame: WindowFrame(x: 100, y: 100, width: 800, height: 600))
        let fresh = WheelDragGeometry.DragOrigin(windowID: UUID(), frame: cached.frame)
        XCTAssertNil(WheelDragGeometry.initialDragOrigin(pressPoint: NSPoint(x: 150, y: 880),
            samplePoint: NSPoint(x: 170, y: 880), cached: cached, fresh: fresh, primaryTop: 1000))
    }

    func testCachedExactWindowSurvivesATransientFreshReadFailure() {
        let cached = WheelDragGeometry.DragOrigin(windowID: UUID(), frame: WindowFrame(x: 100, y: 100, width: 800, height: 600))
        XCTAssertEqual(WheelDragGeometry.initialDragOrigin(pressPoint: NSPoint(x: 150, y: 880),
            samplePoint: NSPoint(x: 180, y: 880), cached: cached, fresh: nil, primaryTop: 1000), cached)
    }

    func testAWindowBodyPressCannotSupplyARestorationOrigin() {
        let cached = WheelDragGeometry.DragOrigin(windowID: UUID(), frame: WindowFrame(x: 100, y: 100, width: 800, height: 600))
        XCTAssertNil(WheelDragGeometry.initialDragOrigin(pressPoint: NSPoint(x: 150, y: 700),
            samplePoint: NSPoint(x: 150, y: 700), cached: cached, fresh: cached, primaryTop: 1000))
    }

    func testNewWindowUsesItsOwnStationaryFrameInsteadOfOldWindowCache() {
        let cached = WheelDragGeometry.DragOrigin(windowID: UUID(), frame: WindowFrame(x: 100, y: 100, width: 800, height: 600))
        let fresh = WheelDragGeometry.DragOrigin(windowID: UUID(), frame: WindowFrame(x: 120, y: 110, width: 800, height: 600))
        XCTAssertEqual(WheelDragGeometry.initialDragOrigin(pressPoint: NSPoint(x: 150, y: 880),
            samplePoint: NSPoint(x: 150, y: 880), cached: cached, fresh: fresh, primaryTop: 1000), fresh)
    }

    func testFirstSampleMotionToleranceHasAnInclusiveThreePointBoundary() {
        let fresh = WheelDragGeometry.DragOrigin(windowID: UUID(), frame: WindowFrame(x: 100, y: 100, width: 800, height: 600))
        XCTAssertEqual(WheelDragGeometry.initialDragOrigin(pressPoint: NSPoint(x: 150, y: 880),
            samplePoint: NSPoint(x: 153, y: 880), cached: nil, fresh: fresh, primaryTop: 1000), fresh)
        XCTAssertNil(WheelDragGeometry.initialDragOrigin(pressPoint: NSPoint(x: 150, y: 880),
            samplePoint: NSPoint(x: 153.1, y: 880), cached: nil, fresh: fresh, primaryTop: 1000))
    }

    func testHoverAtTheRightEdgeKeepsTheCoreAtExactlyItsCollapsedScreenPosition() {
        let area = NSRect(x: 0, y: 24, width: 1470, height: 850)
        let anchor = NSPoint(x: 1412, y: 400)
        let collapsed = WheelDragGeometry.layout(anchor: anchor, configured: 360, expanded: false, workArea: area)
        let expanded = WheelDragGeometry.layout(anchor: anchor, configured: 360, expanded: true, workArea: area)
        XCTAssertEqual(expanded.coreScreenFrame, collapsed.coreScreenFrame)
        XCTAssertEqual(expanded.coreScreenCenter, anchor)
        XCTAssertNotEqual(expanded.wheelCentre, expanded.coreCentre)
        XCTAssertTrue(area.contains(expanded.frame))
        XCTAssertEqual(expanded.wheelScreenFrame.size, NSSize(width: 360, height: 360))
    }

    func testEveryEdgeAndCornerKeepsNineVisibleTargetsClearOfTheFixedCore() {
        let area = NSRect(x: 0, y: 24, width: 1470, height: 850)
        for extent in [280.0, 360, 450, 520] {
            for anchor in [NSPoint(x: 27, y: 400), NSPoint(x: 1443, y: 400),
                           NSPoint(x: 700, y: 51), NSPoint(x: 700, y: 847),
                           NSPoint(x: 27, y: 51), NSPoint(x: 1443, y: 51),
                           NSPoint(x: 27, y: 847), NSPoint(x: 1443, y: 847)] {
                let layout = WheelDragGeometry.layout(anchor: anchor, configured: extent, expanded: true, workArea: area)
                XCTAssertEqual(layout.coreScreenCenter, anchor)
                XCTAssertTrue(area.contains(layout.frame), "\(anchor), \(extent)")
                XCTAssertEqual(layout.slotScreenFrames.count, 9)
                for target in layout.slotScreenFrames {
                    XCTAssertTrue(area.contains(target), "Every item and remove control must remain visible.")
                    XCTAssertFalse(target.intersects(layout.coreScreenFrame), "The core must not cover another target.")
                }
                let mapped = NSPoint(x: layout.frame.minX + layout.coreCentre.x * layout.scale,
                                     y: layout.frame.maxY - layout.coreCentre.y * layout.scale)
                XCTAssertEqual(mapped.x, anchor.x, accuracy: 0.00001)
                XCTAssertEqual(mapped.y, anchor.y, accuracy: 0.00001)
            }
        }
    }

    func testExpandedPanelKeepsItsCentreAwayFromScreenEdges() {
        let area = NSRect(x: 0, y: 24, width: 1470, height: 850)
        let layout = WheelDragGeometry.layout(anchor: NSPoint(x: 700, y: 400), configured: 360, expanded: true, workArea: area)
        XCTAssertEqual(layout.wheelCentre, layout.coreCentre)
        XCTAssertEqual(layout.frame, NSRect(x: 520, y: 220, width: 360, height: 360))
    }

    func testExpandedPanelFitsASecondaryDisplayWithNegativeCoordinates() {
        let area = NSRect(x: -1470, y: -900, width: 1470, height: 850)
        let anchor = NSPoint(x: -58, y: -108)
        let layout = WheelDragGeometry.layout(anchor: anchor, configured: 360, expanded: true, workArea: area)
        XCTAssertEqual(layout.coreScreenCenter, anchor)
        XCTAssertTrue(area.contains(layout.frame))
        XCTAssertTrue(layout.slotScreenFrames.allSatisfy { area.contains($0) && !$0.intersects(layout.coreScreenFrame) })
    }

    func testTinyWorkAreaCannotInvertClampBounds() {
        let area = NSRect(x: 10, y: 20, width: 280, height: 240)
        let anchor = NSPoint(x: 253, y: 233)
        let layout = WheelDragGeometry.layout(anchor: anchor, configured: 360, expanded: true, workArea: area)
        XCTAssertTrue(area.contains(layout.frame))
        XCTAssertEqual(layout.coreScreenCenter, anchor)
        XCTAssertTrue(layout.slotScreenFrames.allSatisfy { area.contains($0) && !$0.intersects(layout.coreScreenFrame) })
    }

    func testCoreDragAtAnEdgeStartsAtTheFixedCoreInsteadOfThePanelMidpoint() {
        let area = NSRect(x: 0, y: 24, width: 1470, height: 850)
        let anchor = NSPoint(x: 1412, y: 400)
        let expanded = WheelDragGeometry.layout(anchor: anchor, configured: 360, expanded: true, workArea: area)
        let displayed = expanded.coreScreenCenter
        let press = NSPoint(x: displayed.x + 20, y: displayed.y - 10)
        let initial = WheelDragGeometry.translatedAnchor(from: displayed, pressPoint: press, to: press)
        let collapsed = WheelDragGeometry.layout(anchor: initial, configured: 360, expanded: false, workArea: area)
        XCTAssertEqual(collapsed.coreScreenCenter, anchor)
        XCTAssertEqual(WheelDragGeometry.translatedAnchor(from: displayed, pressPoint: press,
            to: NSPoint(x: press.x + 40, y: press.y + 30)), NSPoint(x: displayed.x + 40, y: displayed.y + 30))
    }

    func testExternalCaptureUsesTheSameAnchoredCoreBeforeAndAfterExpansion() {
        let anchor = NSPoint(x: 1412, y: 400)
        let layout = WheelDragGeometry.layout(anchor: anchor, configured: 360, expanded: true,
            workArea: NSRect(x: 0, y: 24, width: 1470, height: 850))
        XCTAssertTrue(WheelDragGeometry.coreContains(anchor, layout: layout))
        XCTAssertFalse(WheelDragGeometry.coreContains(NSPoint(x: layout.frame.midX, y: layout.frame.midY), layout: layout))
    }

    func testDragPreservesOffCentreGrabPointWithoutAccumulatingDeltas() {
        let anchor = NSPoint(x: 400, y: 300), press = NSPoint(x: 425, y: 285)
        XCTAssertEqual(WheelDragGeometry.translatedAnchor(from: anchor, pressPoint: press,
            to: NSPoint(x: 455, y: 330)), NSPoint(x: 430, y: 345))
        XCTAssertEqual(WheelDragGeometry.translatedAnchor(from: anchor, pressPoint: press,
            to: NSPoint(x: 465, y: 340)), NSPoint(x: 440, y: 355))
    }

    func testDraggingAcrossNegativeScreenCoordinatesKeepsBothAxes() {
        XCTAssertEqual(WheelDragGeometry.translatedAnchor(from: NSPoint(x: 80, y: 200),
            pressPoint: NSPoint(x: 90, y: 210), to: NSPoint(x: -700, y: -100)), NSPoint(x: -710, y: -110))
    }

    func testTitleBarConvertsCocoaToAXCoordinatesOnAnOffsetDisplay() {
        let frame = WindowFrame(x: -800, y: -300, width: 720, height: 480)
        XCTAssertTrue(WheelDragGeometry.isTitleBar(NSPoint(x: -500, y: 1360), frame: frame, primaryTop: 1080))
        XCTAssertFalse(WheelDragGeometry.isTitleBar(NSPoint(x: -500, y: 1250), frame: frame, primaryTop: 1080))
        XCTAssertFalse(WheelDragGeometry.isTitleBar(NSPoint(x: 100, y: 1360), frame: frame, primaryTop: 1080))
    }

    func testWindowBodyAndBelowShortWindowAreNotTitleBarDrags() {
        let frame = WindowFrame(x: 100, y: 100, width: 200, height: 30)
        XCTAssertTrue(WheelDragGeometry.isTitleBar(NSPoint(x: 150, y: 890), frame: frame, primaryTop: 1000))
        XCTAssertFalse(WheelDragGeometry.isTitleBar(NSPoint(x: 150, y: 860), frame: frame, primaryTop: 1000))
    }

    func testTextSelectionAndSmallGeometryJitterCannotCaptureAWindow() {
        let original = WindowFrame(x: 100, y: 80, width: 800, height: 600)
        XCTAssertFalse(WheelDragGeometry.windowMoved(from: original, to: original))
        XCTAssertFalse(WheelDragGeometry.windowMoved(from: original,
            to: WindowFrame(x: 103, y: 78, width: 800, height: 600)))
    }

    func testActualWindowTranslationCanBeCaptured() {
        XCTAssertTrue(WheelDragGeometry.windowMoved(from: WindowFrame(x: 100, y: 80, width: 800, height: 600),
            to: WindowFrame(x: -200, y: 400, width: 801, height: 599)))
    }

    func testResizeDoesNotBecomeATitleBarDrop() {
        XCTAssertFalse(WheelDragGeometry.windowMoved(from: WindowFrame(x: 100, y: 80, width: 800, height: 600),
            to: WindowFrame(x: 50, y: 30, width: 850, height: 650)))
    }

    func testInvalidAXGeometryCannotCaptureAWindow() {
        let original = WindowFrame(x: 100, y: 80, width: 800, height: 600)
        XCTAssertFalse(WheelDragGeometry.windowMoved(from: original,
            to: WindowFrame(x: .infinity, y: 100, width: 800, height: 600)))
        XCTAssertFalse(WheelDragGeometry.isTitleBar(NSPoint(x: 150, y: 900),
            frame: WindowFrame(x: 100, y: 80, width: 0, height: 600), primaryTop: 1000))
    }
}
