//
//  ChatManualStackView.swift
//  iTerm2
//
//  Manual-layout replacement for NSStackView used inside the chat UI.
//  No constraints. The container measures each arranged subview via a
//  caller-supplied size resolver (default: intrinsicContentSize falling
//  back to fittingSize), then walks them in order applying spacing and
//  alignment. Hidden subviews are skipped (no slot left behind).
//

import AppKit

@objc(iTermChatManualStackView)
final class ChatManualStackView: NSView {
    enum Orientation {
        case horizontal
        case vertical
    }

    enum Alignment {
        case leading
        case center
        case trailing
        // Stretch each child to fill the cross axis (height for horizontal,
        // width for vertical). Useful for full-width row separators.
        case fill
    }

    var orientation: Orientation { didSet { needsLayout = true } }
    var spacing: CGFloat { didSet { needsLayout = true } }
    var alignment: Alignment { didSet { needsLayout = true } }

    // Per-arranged-subview override of the resolved size. Returning nil
    // falls back to the default measurement (intrinsic, then fitting).
    // Width or height of -1 means "use measured value" so callers can pin
    // only one axis.
    var sizeOverride: ((NSView, CGFloat) -> NSSize?)?

    // Set of arranged subviews that should absorb the leftover main-axis
    // space after sibling sizes are deducted. If multiple flex subviews
    // exist, the leftover is split evenly.
    var flexSubviews = Set<ObjectIdentifier>()

    func setFlex(_ view: NSView, _ flex: Bool) {
        let key = ObjectIdentifier(view)
        if flex {
            flexSubviews.insert(key)
        } else {
            flexSubviews.remove(key)
        }
        needsLayout = true
    }

    private(set) var arrangedSubviews: [NSView] = []

    init(orientation: Orientation,
         spacing: CGFloat = 0,
         alignment: Alignment = .leading) {
        self.orientation = orientation
        self.spacing = spacing
        self.alignment = alignment
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    func addArrangedSubview(_ view: NSView) {
        arrangedSubviews.append(view)
        addSubview(view)
        needsLayout = true
    }

    func insertArrangedSubview(_ view: NSView, at index: Int) {
        arrangedSubviews.insert(view, at: index)
        addSubview(view)
        needsLayout = true
    }

    func removeArrangedSubview(_ view: NSView) {
        arrangedSubviews.removeAll(where: { $0 === view })
        needsLayout = true
    }

    func removeAllArrangedSubviews() {
        for view in arrangedSubviews {
            view.removeFromSuperview()
        }
        arrangedSubviews.removeAll()
        needsLayout = true
    }

    // Total size required to lay out all visible arranged subviews when
    // the cross axis is constrained to `crossAxisLimit`. Used by callers
    // that need to size the stack from outside (e.g., bubble cells deciding
    // their own height).
    func fittingSize(crossAxisLimit: CGFloat) -> NSSize {
        var main: CGFloat = 0
        var cross: CGFloat = 0
        var first = true
        for view in arrangedSubviews where !view.isHidden {
            let size = resolveSize(for: view, crossAxisLimit: crossAxisLimit)
            switch orientation {
            case .horizontal:
                if !first { main += spacing }
                main += size.width
                cross = max(cross, size.height)
            case .vertical:
                if !first { main += spacing }
                main += size.height
                cross = max(cross, size.width)
            }
            first = false
        }
        switch orientation {
        case .horizontal: return NSSize(width: main, height: cross)
        case .vertical: return NSSize(width: cross, height: main)
        }
    }

    override func layout() {
        super.layout()
        let crossLimit: CGFloat = (orientation == .horizontal) ? bounds.height : bounds.width

        // First pass: resolve each child's preferred size for the current
        // cross-axis bound.
        var sizes: [NSSize] = []
        sizes.reserveCapacity(arrangedSubviews.count)
        for view in arrangedSubviews {
            if view.isHidden {
                sizes.append(.zero)
                continue
            }
            sizes.append(resolveSize(for: view, crossAxisLimit: crossLimit))
        }

        // Distribute leftover main-axis space across flex children. The
        // resolved size for flex children is treated as a minimum (use the
        // larger of measurement or the per-flex share).
        let visibleIndices = arrangedSubviews.indices.filter { !arrangedSubviews[$0].isHidden }
        let flexIndices = visibleIndices.filter {
            flexSubviews.contains(ObjectIdentifier(arrangedSubviews[$0]))
        }
        if !flexIndices.isEmpty {
            let mainAxisBound: CGFloat = (orientation == .horizontal) ? bounds.width : bounds.height
            var nonFlexMain: CGFloat = 0
            for i in visibleIndices where !flexIndices.contains(i) {
                let s = sizes[i]
                nonFlexMain += (orientation == .horizontal) ? s.width : s.height
            }
            let totalSpacing = max(0, CGFloat(visibleIndices.count - 1)) * spacing
            let availableForFlex = max(0, mainAxisBound - nonFlexMain - totalSpacing)
            let perFlex = availableForFlex / CGFloat(flexIndices.count)
            for i in flexIndices {
                if orientation == .horizontal {
                    sizes[i].width = max(sizes[i].width, perFlex)
                } else {
                    sizes[i].height = max(sizes[i].height, perFlex)
                }
            }
        }

        // Second pass: walk and assign frames.
        var pos: CGFloat = 0
        var firstVisible = true
        for (i, view) in arrangedSubviews.enumerated() {
            if view.isHidden { continue }
            if !firstVisible { pos += spacing }
            firstVisible = false
            let size = sizes[i]
            switch orientation {
            case .horizontal:
                let height: CGFloat
                let y: CGFloat
                switch alignment {
                case .leading:
                    height = size.height
                    y = bounds.height - height
                case .center:
                    height = size.height
                    y = floor((bounds.height - height) / 2)
                case .trailing:
                    height = size.height
                    y = 0
                case .fill:
                    height = bounds.height
                    y = 0
                }
                view.frame = NSRect(x: pos, y: y, width: size.width, height: height)
                pos += size.width
            case .vertical:
                let width: CGFloat
                let x: CGFloat
                switch alignment {
                case .leading:
                    width = size.width
                    x = 0
                case .center:
                    width = size.width
                    x = floor((bounds.width - width) / 2)
                case .trailing:
                    width = size.width
                    x = bounds.width - width
                case .fill:
                    width = bounds.width
                    x = 0
                }
                // Vertical layout grows from top to bottom in flipped
                // coordinates. NSView is bottom-up by default; the
                // arranged-subview semantics here treat index 0 as
                // visually topmost.
                let y = bounds.height - pos - size.height
                view.frame = NSRect(x: x, y: y, width: width, height: size.height)
                pos += size.height
            }
        }
    }

    private func resolveSize(for view: NSView, crossAxisLimit: CGFloat) -> NSSize {
        if let overrideSize = sizeOverride?(view, crossAxisLimit) {
            let measured = measuredSize(for: view, crossAxisLimit: crossAxisLimit)
            let width = overrideSize.width >= 0 ? overrideSize.width : measured.width
            let height = overrideSize.height >= 0 ? overrideSize.height : measured.height
            return NSSize(width: width, height: height)
        }
        return measuredSize(for: view, crossAxisLimit: crossAxisLimit)
    }

    private func measuredSize(for view: NSView, crossAxisLimit: CGFloat) -> NSSize {
        let intrinsic = view.intrinsicContentSize
        if intrinsic.width != NSView.noIntrinsicMetric && intrinsic.height != NSView.noIntrinsicMetric {
            return intrinsic
        }
        // Fall back to fittingSize for views without intrinsic metrics.
        // For manual-layout views, fittingSize is .zero, in which case the
        // caller should provide a sizeOverride.
        let fitting = view.fittingSize
        let width = intrinsic.width != NSView.noIntrinsicMetric ? intrinsic.width : fitting.width
        let height = intrinsic.height != NSView.noIntrinsicMetric ? intrinsic.height : fitting.height
        return NSSize(width: width, height: height)
    }
}
