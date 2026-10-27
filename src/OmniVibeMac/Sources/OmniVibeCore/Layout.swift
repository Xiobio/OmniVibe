import Foundation

/// Screen coordinates use macOS accessibility's top-left origin, in logical points.
public struct WindowFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct WindowPlacement: Equatable, Sendable {
    public var frame: WindowFrame
    public var minimized: Bool

    public init(frame: WindowFrame, minimized: Bool) {
        self.frame = frame
        self.minimized = minimized
    }
}

public enum ArrangementMode: String, CaseIterable, Sendable {
    case balanced, columns, rows, mainLeft
}

public enum LayoutEngine {
    public static func frames(count: Int, workArea: WindowFrame, gap: Double = 12,
                              mode: ArrangementMode = .balanced) -> [WindowFrame] {
        guard count > 0, workArea.x.isFinite, workArea.y.isFinite,
              workArea.width.isFinite, workArea.height.isFinite,
              workArea.width > 0, workArea.height > 0 else { return [] }
        // Nine slots bound the supported workload and keep tiny screens well-defined.
        let count = min(count, 9)
        let requestedGap = gap.isFinite ? max(0, gap) : 0
        switch mode {
        case .columns:
            return grid(count: count, columns: count, rows: 1, area: workArea, gap: requestedGap)
        case .rows:
            return grid(count: count, columns: 1, rows: count, area: workArea, gap: requestedGap)
        case .balanced:
            let columns = count <= 2 ? count : Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(columns)))
            return grid(count: count, columns: columns, rows: rows, area: workArea, gap: requestedGap)
        case .mainLeft:
            guard count > 1 else { return [workArea] }
            let horizontalGap = min(requestedGap, workArea.width / 3)
            let leftWidth = (workArea.width - horizontalGap) * 0.6
            let right = WindowFrame(x: workArea.x + leftWidth + horizontalGap, y: workArea.y,
                                    width: workArea.width - leftWidth - horizontalGap,
                                    height: workArea.height)
            return [WindowFrame(x: workArea.x, y: workArea.y, width: leftWidth, height: workArea.height)] +
                grid(count: count - 1, columns: 1, rows: count - 1, area: right, gap: requestedGap)
        }
    }

    private static func grid(count: Int, columns: Int, rows: Int, area: WindowFrame,
                             gap: Double) -> [WindowFrame] {
        // Clamp gaps independently so even a very small work area has positive cells.
        let yGap = rows > 1 ? min(gap, area.height / Double(rows * 2)) : 0
        let height = (area.height - yGap * Double(rows - 1)) / Double(rows)
        return (0..<count).map { index in
            let row = index / columns
            // A partial last row uses all available width, as in the original
            // Windows layout, instead of leaving empty grid cells on the right.
            let rowColumns = min(columns, count - row * columns)
            let xGap = rowColumns > 1 ? min(gap, area.width / Double(rowColumns * 2)) : 0
            let width = (area.width - xGap * Double(rowColumns - 1)) / Double(rowColumns)
            return WindowFrame(x: area.x + Double(index % columns) * (width + xGap),
                               y: area.y + Double(row) * (height + yGap),
                               width: width, height: height)
        }
    }
}
