//
//  SetWindowFrameRequest.swift
//  iTerm2
//
//  Validation for OSC 1337 SetWindowFrame=x;y;width;height. The payload comes
//  from whatever is printed to the terminal, so it is parsed strictly and the
//  resulting frame is clamped so the window cannot become invisible or land
//  somewhere it can't be reached.
//

import AppKit

@objc(iTermSetWindowFrameRequest)
class SetWindowFrameRequest: NSObject {
    /// How much of the window (in points, per dimension) must remain on a
    /// screen. Smaller windows must be entirely on it.
    static let minimumVisibleExtent: CGFloat = 40

    /// Parses "x;y;width;height". Returns nil unless there are exactly four
    /// fields and each is a finite number.
    @objc(parse:)
    static func parse(_ value: String) -> NSValue? {
        let parts = value.components(separatedBy: ";")
        guard parts.count == 4 else {
            DLog("Wrong number of fields in \(value)")
            return nil
        }
        var numbers = [CGFloat]()
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let number = Double(trimmed), number.isFinite else {
                DLog("Invalid field \(part) in \(value)")
                return nil
            }
            numbers.append(CGFloat(number))
        }
        return NSValue(rect: NSRect(x: numbers[0],
                                    y: numbers[1],
                                    width: numbers[2],
                                    height: numbers[3]))
    }

    /// The smallest frame size a user could drag the window to. `contentMinimum`
    /// is the largest tab minimum plus window decorations. A titled window
    /// also can't be dragged narrower than AppKit's minimum width for its
    /// title bar buttons, so a programmatic frame shouldn't be either.
    @objc(minimumFrameSizeForContentMinimum:windowMinSize:styleMask:)
    static func minimumFrameSize(contentMinimum: NSSize,
                                 windowMinSize: NSSize,
                                 styleMask: NSWindow.StyleMask) -> NSSize {
        var result = NSSize(width: max(contentMinimum.width, windowMinSize.width),
                            height: max(contentMinimum.height, windowMinSize.height))
        if styleMask.contains(.titled) {
            result.width = max(result.width,
                               NSWindow.minFrameWidth(withTitle: "", styleMask: styleMask))
        }
        return result
    }

    /// Clamps a requested frame (global AppKit coordinates) so its size is
    /// between `minSize` and the union of `screenFrames`, and its top edge plus
    /// at least `minimumVisibleExtent` points of it lie on one of the screens.
    /// `screenFrames` should be the screens' visible frames.
    @objc(clampedFrame:minSize:screenFrames:)
    static func clampedFrame(_ requested: NSRect,
                             minSize: NSSize,
                             screenFrames: [NSValue]) -> NSRect {
        let screens = screenFrames.map { $0.rectValue }.filter { $0.width > 0 && $0.height > 0 }
        // Use size directly: CGRect.width and .height return absolute values,
        // which would turn a negative size into a positive one.
        var frame = requested
        frame.size.width = max(requested.size.width, minSize.width, 1)
        frame.size.height = max(requested.size.height, minSize.height, 1)
        guard !screens.isEmpty else {
            DLog("No screens; only applying the minimum size")
            return frame
        }
        let union = screens.reduce(screens[0]) { $0.union($1) }
        frame.size.width = max(minSize.width, min(frame.width, union.width))
        frame.size.height = max(minSize.height, min(frame.height, union.height))

        let visibleWidth = min(frame.width, minimumVisibleExtent)
        let visibleHeight = min(frame.height, minimumVisibleExtent)
        func isReachable(on screen: NSRect) -> Bool {
            let overlap = frame.intersection(screen)
            return overlap.width >= visibleWidth &&
                frame.maxY <= screen.maxY &&
                frame.maxY >= screen.minY + visibleHeight
        }
        if screens.contains(where: isReachable(on:)) {
            return frame
        }

        let target = closestScreen(to: frame, among: screens)
        frame.origin.x = min(max(frame.minX, target.minX + visibleWidth - frame.width),
                             target.maxX - visibleWidth)
        frame.origin.y = min(max(frame.minY, target.minY + visibleHeight - frame.height),
                             target.maxY - frame.height)
        DLog("Moved \(requested) to \(frame) on screen \(target)")
        return frame
    }

    /// The screen that overlaps `frame` the most or, if none overlaps it, the
    /// one nearest to its center.
    private static func closestScreen(to frame: NSRect, among screens: [NSRect]) -> NSRect {
        func area(_ rect: NSRect) -> CGFloat {
            return rect.isNull ? 0 : rect.width * rect.height
        }
        if let best = screens.max(by: { area(frame.intersection($0)) < area(frame.intersection($1)) }),
           area(frame.intersection(best)) > 0 {
            return best
        }
        let center = NSPoint(x: frame.midX, y: frame.midY)
        func distance(_ screen: NSRect) -> CGFloat {
            let dx = max(screen.minX - center.x, 0, center.x - screen.maxX)
            let dy = max(screen.minY - center.y, 0, center.y - screen.maxY)
            // Not squared: that would overflow to infinity for huge offsets.
            return dx + dy
        }
        return screens.min(by: { distance($0) < distance($1) }) ?? screens[0]
    }
}
