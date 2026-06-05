//
//  WorkgroupPeerSegmentedControl.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/4/26.
//

import AppKit

// NSSegmentedControl draws its segments through NSSegmentedCell rather
// than hosting per-segment subviews, so there's no view whose frame we
// can read to place an activity indicator. This cell captures the exact
// rect AppKit computes for each segment and hands it back to the
// control, which uses it to position a PSMProgressIndicator overlay.
final class WorkgroupPeerSegmentedCell: NSSegmentedCell {
    override func drawSegment(_ segment: Int,
                              inFrame frame: NSRect,
                              with controlView: NSView) {
        super.drawSegment(segment, inFrame: frame, with: controlView)
        (controlView as? WorkgroupPeerSegmentedControl)?
            .recordSegmentFrame(frame, forSegment: segment)
    }
}

// An NSSegmentedControl that can show a per-segment spinner on the
// segment's leading edge while a peer is busy. The label stays visible;
// a transparent "reserved" image is installed on the busy segment so the
// label shifts right and the spinner has a box to sit in rather than
// overlapping the text.
final class WorkgroupPeerSegmentedControl: NSSegmentedControl {
    // Side length of the spinner and of the transparent box reserved for
    // it on the segment's leading edge.
    private static let indicatorSide: CGFloat = 13
    // Leading inset from the captured segment frame to the reserved
    // image's left edge. texturedRounded leaves a few points of content
    // padding; this puts the spinner on top of the reserved box. Because
    // the owning toolbar item caps its width at the control's fitting
    // size, segments are never wider than their content, so the
    // image+label group always sits flush against this inset (no
    // centering slack to account for).
    private static let segmentLeadingInset: CGFloat = 3

    // Called when reserving or freeing a segment's indicator box changed
    // the control's fitting width, so the toolbar item can re-lay out.
    var onReservedWidthChanged: (() -> Void)?

    // Spinner overlays, keyed by segment index.
    private var indicators: [Int: PSMProgressIndicator] = [:]
    // Segments currently carrying the reserved transparent image.
    private var reservedSegments = Set<Int>()
    // Per-segment draw rects from the most recent completed draw pass.
    private var segmentFrames: [Int: NSRect] = [:]
    // Frames accumulated during the in-progress draw pass.
    private var pendingFrames: [Int: NSRect] = [:]
    private let reservedImage: NSImage

    // NSControl.init(frame:) builds its cell from cellClass; overriding
    // it makes the control use our frame-capturing cell without having to
    // reassign the (Any-typed, awkward-to-set) cell property afterward.
    override class var cellClass: AnyClass? {
        get { WorkgroupPeerSegmentedCell.self }
        set { _ = newValue }
    }

    init(labels: [String],
         trackingMode: NSSegmentedControl.SwitchTracking,
         target: AnyObject?,
         action: Selector?) {
        reservedImage = Self.makeReservedImage(side: Self.indicatorSide)
        super.init(frame: .zero)
        it_assert(cell is WorkgroupPeerSegmentedCell,
                  "Expected WorkgroupPeerSegmentedCell, got \(String(describing: cell))")
        self.trackingMode = trackingMode
        segmentCount = labels.count
        for (i, label) in labels.enumerated() {
            setLabel(label, forSegment: i)
        }
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Busy state

    func setBusy(_ busy: Bool, forSegment index: Int) {
        guard index >= 0, index < segmentCount else { return }
        if busy {
            showIndicator(forSegment: index)
        } else {
            hideIndicator(forSegment: index)
        }
    }

    private func showIndicator(forSegment index: Int) {
        let reservedChanged = reservedSegments.insert(index).inserted
        if reservedChanged {
            setImage(reservedImage, forSegment: index)
        }
        let indicator: PSMProgressIndicator
        if let existing = indicators[index] {
            indicator = existing
        } else {
            let side = Self.indicatorSide
            indicator = PSMProgressIndicator(
                frame: NSRect(x: 0, y: 0, width: side, height: side))
            indicators[index] = indicator
            addSubview(indicator)
        }
        indicator.light = inDarkMode
        indicator.isHidden = false
        indicator.animate = true
        needsLayout = true
        if reservedChanged {
            onReservedWidthChanged?()
        }
    }

    private func hideIndicator(forSegment index: Int) {
        if let indicator = indicators.removeValue(forKey: index) {
            indicator.animate = false
            indicator.removeFromSuperview()
        }
        if reservedSegments.remove(index) != nil {
            setImage(nil, forSegment: index)
            onReservedWidthChanged?()
        }
    }

    // MARK: - Frame capture

    fileprivate func recordSegmentFrame(_ frame: NSRect, forSegment index: Int) {
        pendingFrames[index] = frame
    }

    override func draw(_ dirtyRect: NSRect) {
        pendingFrames.removeAll(keepingCapacity: true)
        // super.draw drives the cell, which calls recordSegmentFrame for
        // each segment via WorkgroupPeerSegmentedCell.
        super.draw(dirtyRect)
        if pendingFrames != segmentFrames {
            segmentFrames = pendingFrames
            // Defer the geometry change to the next layout pass rather
            // than moving subviews mid-draw.
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        repositionIndicators()
    }

    private func repositionIndicators() {
        let side = Self.indicatorSide
        for (index, indicator) in indicators {
            guard let frame = segmentFrames[index] else {
                // No captured frame yet (segment never drawn) — keep the
                // spinner hidden until we know where it goes.
                indicator.isHidden = true
                continue
            }
            indicator.frame = NSRect(x: frame.minX + Self.segmentLeadingInset,
                                     y: frame.midY - side / 2,
                                     width: side,
                                     height: side)
            indicator.isHidden = false
            indicator.light = inDarkMode
        }
    }

    // MARK: - Helpers

    private var inDarkMode: Bool {
        let match = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua
    }

    // A transparent square image used only to reserve leading space on a
    // busy segment so the label shifts right and the spinner has a box to
    // occupy. Drawn with a real (clear) representation so the segmented
    // cell counts its width during layout.
    private static func makeReservedImage(side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
