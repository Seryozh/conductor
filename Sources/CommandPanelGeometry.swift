import AppKit

/// Presentation geometry only. The anchor is the center of the fixed bottom rail.
enum CommandPanelGeometry {
    static func frame(size: NSSize, anchor: NSPoint, visibleFrame: NSRect) -> NSRect {
        let margin: CGFloat = 8
        let width = min(max(1, size.width), max(1, visibleFrame.width - 2 * margin))
        let height = min(max(1, size.height), max(1, visibleFrame.height - 2 * margin))
        let x = min(max(visibleFrame.minX + margin, anchor.x - width / 2), visibleFrame.maxX - width - margin)
        let y = min(max(visibleFrame.minY + margin, anchor.y), visibleFrame.maxY - height - margin)
        return NSRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}
