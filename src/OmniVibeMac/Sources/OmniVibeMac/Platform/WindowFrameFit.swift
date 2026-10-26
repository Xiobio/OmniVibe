import Foundation
import OmniVibeCore

/// Terminal character grids may leave unused room inside a layout cell. They
/// must not borrow the neighbouring cell's gap or silently choose another size.
enum WindowFrameFit {
    static let edgeTolerance = 2.0
    static let maximumInwardShrink = 32.0

    static func accepts(_ actual: WindowFrame, target: WindowFrame) -> Bool {
        guard valid(actual), valid(target),
              abs(actual.x - target.x) <= edgeTolerance,
              abs(actual.y - target.y) <= edgeTolerance,
              actual.width >= target.width - maximumInwardShrink,
              actual.height >= target.height - maximumInwardShrink,
              actual.width <= target.width + edgeTolerance,
              actual.height <= target.height + edgeTolerance else { return false }
        return actual.x >= target.x - edgeTolerance && actual.y >= target.y - edgeTolerance &&
            actual.x + actual.width <= target.x + target.width + edgeTolerance &&
            actual.y + actual.height <= target.y + target.height + edgeTolerance
    }

    /// Some applications add a stable decoration offset to an AX size request.
    /// Feedback accumulates from the last request, with a bounded total offset.
    /// A corrective request is never evidence that a frame fits:
    /// the caller must read the real result and apply the original acceptance
    /// or restoration checks against the unchanged target.
    static func correctedSizeRequest(target: WindowFrame, actual: WindowFrame,
                                     lastRequested: WindowFrame? = nil) -> WindowFrame? {
        let base = lastRequested ?? target
        guard valid(target), valid(actual), valid(base) else { return nil }
        let widthError = target.width - actual.width
        let heightError = target.height - actual.height
        guard abs(widthError) <= maximumInwardShrink, abs(heightError) <= maximumInwardShrink,
              abs(widthError) > edgeTolerance || abs(heightError) > edgeTolerance else { return nil }
        let request = WindowFrame(x: target.x, y: target.y,
                                  width: base.width + widthError, height: base.height + heightError)
        guard valid(request), abs(request.width - target.width) <= maximumInwardShrink,
              abs(request.height - target.height) <= maximumInwardShrink else { return nil }
        return request
    }

    /// A rollback restores an observed real frame, so accepting another grid
    /// shrink here would hide a partial restoration.
    static func restored(_ actual: WindowFrame, before: WindowFrame) -> Bool {
        accepts(actual, target: before) &&
            abs(actual.width - before.width) <= edgeTolerance &&
            abs(actual.height - before.height) <= edgeTolerance
    }

    static func constraint(_ actual: WindowFrame, target: WindowFrame) -> WindowFrameConstraintError? {
        accepts(actual, target: target) ? nil : WindowFrameConstraintError(requested: target, actual: actual)
    }

    static func restrictionDescription(target: WindowFrame, actual: WindowFrame) -> String {
        String(format: "目标应用限制了窗口尺寸或位置：要求 %.1f × %.1f pt，实际 %.1f × %.1f pt；位置要求 (%.1f, %.1f)，实际 (%.1f, %.1f)。无法按当前布局排列。",
               target.width, target.height, actual.width, actual.height,
               target.x, target.y, actual.x, actual.y)
    }

    private static func valid(_ frame: WindowFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite && frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0 &&
            (frame.x + frame.width).isFinite && (frame.y + frame.height).isFinite
    }
}
