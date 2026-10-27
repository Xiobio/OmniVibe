import XCTest
@testable import OmniVibeCore

final class LayoutTests: XCTestCase {
    private let area = WindowFrame(x: -1600, y: 35, width: 1440, height: 865)

    func testAllLayoutsStayInsideWorkAreaAndDoNotOverlap() {
        for mode in ArrangementMode.allCases {
            for count in 1...9 {
                let frames = LayoutEngine.frames(count: count, workArea: area, gap: 12, mode: mode)
                XCTAssertEqual(frames.count, count)
                for frame in frames {
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                    XCTAssertGreaterThanOrEqual(frame.x, area.x - 0.0001)
                    XCTAssertGreaterThanOrEqual(frame.y, area.y - 0.0001)
                    XCTAssertLessThanOrEqual(frame.x + frame.width, area.x + area.width + 0.0001)
                    XCTAssertLessThanOrEqual(frame.y + frame.height, area.y + area.height + 0.0001)
                }
                for left in frames.indices {
                    for right in frames.indices where right > left {
                        XCTAssertFalse(overlaps(frames[left], frames[right]), "\(mode) count=\(count)")
                    }
                }
            }
        }
    }

    func testColumnsRespectRequestedGapAndRowsFillHeight() {
        let columns = LayoutEngine.frames(count: 3, workArea: area, gap: 16, mode: .columns)
        XCTAssertEqual(columns[1].x - columns[0].x - columns[0].width, 16, accuracy: 0.0001)
        XCTAssertEqual(columns[0].height, area.height)
        let rows = LayoutEngine.frames(count: 4, workArea: area, gap: 12, mode: .rows)
        XCTAssertEqual(rows[3].y + rows[3].height, area.y + area.height, accuracy: 0.0001)
    }

    func testBalancedPartialLastRowsFillWidthWithoutOverlapping() {
        let gap = 12.0
        for count in [5, 7, 8] {
            let frames = LayoutEngine.frames(count: count, workArea: area, gap: gap, mode: .balanced)
            let columns = Int(ceil(sqrt(Double(count))))
            let lastRowCount = count % columns
            let lastRow = Array(frames.suffix(lastRowCount))

            XCTAssertEqual(lastRow.count, lastRowCount, "count=\(count)")
            XCTAssertEqual(lastRow.first!.x, area.x, accuracy: 0.0001, "count=\(count)")
            XCTAssertEqual(lastRow.last!.x + lastRow.last!.width, area.x + area.width,
                           accuracy: 0.0001, "count=\(count)")
            XCTAssertEqual(lastRow.reduce(0) { $0 + $1.width } + gap * Double(lastRowCount - 1),
                           area.width, accuracy: 0.0001, "count=\(count)")
            for (left, right) in zip(lastRow, lastRow.dropFirst()) {
                XCTAssertEqual(right.x - left.x - left.width, gap, accuracy: 0.0001, "count=\(count)")
            }
            for left in frames.indices {
                for right in frames.indices where right > left {
                    XCTAssertFalse(overlaps(frames[left], frames[right]), "count=\(count)")
                }
            }
        }
    }

    func testBalancedThreeWindowsUseTwoTopCellsAndOneFullWidthBottomCell() {
        let gap = 12.0
        let frames = LayoutEngine.frames(count: 3, workArea: area, gap: gap, mode: .balanced)
        XCTAssertEqual(frames.count, 3)
        let cellWidth = (area.width - gap) / 2
        let cellHeight = (area.height - gap) / 2
        XCTAssertEqual(frames[0], WindowFrame(x: area.x, y: area.y, width: cellWidth, height: cellHeight))
        XCTAssertEqual(frames[1], WindowFrame(x: area.x + cellWidth + gap, y: area.y, width: cellWidth, height: cellHeight))
        XCTAssertEqual(frames[2], WindowFrame(x: area.x, y: area.y + cellHeight + gap, width: area.width, height: cellHeight))
        XCTAssertEqual(frames[2].y + frames[2].height, area.y + area.height, accuracy: 0.0001)
        for frame in frames {
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertEqual(frame.height, cellHeight)
        }
        for first in frames.indices {
            for second in frames.indices where second > first { XCTAssertFalse(overlaps(frames[first], frames[second])) }
        }
    }

    func testMainLeftKeepsPrimaryWindowLargeAndStacksRemainingWindows() {
        let frames = LayoutEngine.frames(count: 4, workArea: area, gap: 10, mode: .mainLeft)
        XCTAssertGreaterThan(frames[0].width, frames[1].width)
        XCTAssertEqual(frames[0].height, area.height)
        XCTAssertEqual(frames[1].x, frames[2].x)
        XCTAssertEqual(frames[2].x, frames[3].x)
    }

    func testTinyScreensAndExcessiveGapsStillProducePositiveCells() {
        let tiny = WindowFrame(x: 0, y: 0, width: 4, height: 3)
        for mode in ArrangementMode.allCases {
            let frames = LayoutEngine.frames(count: 9, workArea: tiny, gap: 1000, mode: mode)
            XCTAssertEqual(frames.count, 9)
            XCTAssertTrue(frames.allSatisfy { $0.width > 0 && $0.height > 0 })
        }
    }

    func testInvalidInputDoesNotProduceInvalidWindowFrames() {
        XCTAssertTrue(LayoutEngine.frames(count: 0, workArea: area, mode: .balanced).isEmpty)
        XCTAssertTrue(LayoutEngine.frames(count: -2, workArea: area, mode: .rows).isEmpty)
        XCTAssertTrue(LayoutEngine.frames(count: 2, workArea: .init(x: 0, y: 0, width: .infinity, height: 10), mode: .columns).isEmpty)
        XCTAssertEqual(LayoutEngine.frames(count: 99, workArea: area, mode: .balanced).count, 9)
        let frames = LayoutEngine.frames(count: 3, workArea: area, gap: .nan, mode: .columns)
        XCTAssertTrue(frames.allSatisfy { $0.x.isFinite && $0.width.isFinite })
    }

    private func overlaps(_ a: WindowFrame, _ b: WindowFrame) -> Bool {
        min(a.x + a.width, b.x + b.width) - max(a.x, b.x) > 0.0001 &&
        min(a.y + a.height, b.y + b.height) - max(a.y, b.y) > 0.0001
    }
}
