//
//  PTYTextView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import Foundation

extension PTYTextView {
    @objc
    func addPorthole(_ porthole: ObjCPorthole) {
        portholes.add(porthole)
        porthole.delegate = self
        addSubview(porthole.view)
        updatePortholeFrame(porthole, force: true)
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
        setNeedsDisplay(true)
        porthole.view.needsDisplay = true
    }

    @objc
    func removePorthole(_ porthole: ObjCPorthole) {
        if porthole.delegate === self {
            porthole.delegate = nil
        }
        if porthole.view.superview == self {
            porthole.view.removeFromSuperview()
        }
        portholes.remove(porthole)
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
    }

    @objc
    func updatePortholeFrames() {
        for porthole in portholes {
            updatePortholeFrame(porthole as! Porthole, force: false)
        }
    }

    // If force is true, recalculate the height even if the textview's width hasn't changed since
    // the last time this method was called.
    private func updatePortholeFrame(_ porthole: ObjCPorthole, force: Bool) {
        guard porthole.mark != nil else {
            return
        }
        guard let dataSource = dataSource else {
            return
        }
        let gridCoordRange = dataSource.coordRange(of: porthole)
        guard gridCoordRange != VT100GridCoordRangeInvalid else {
            return
        }
        let lineRange = gridCoordRange.start.y...gridCoordRange.end.y
        DLog("Update porthole with line range \(lineRange)")
        let hmargin = CGFloat(iTermPreferences.integer(forKey: kPreferenceKeySideMargins))
        let cellWidth = dataSource.width()
        if lastPortholeWidth == cellWidth && !force {
            let size = porthole.view.frame.size
            // Calculating porthole size is very slow because NSView is a catastrophe so avoid doing
            // it if the width is unchanged.
            porthole.view.frame = NSRect(x: hmargin,
                                         y: CGFloat(lineRange.lowerBound) * lineHeight,
                                         width: size.width,
                                         height: size.height)
        } else {
            lastPortholeWidth = cellWidth
            let size = NSSize(width: CGFloat(cellWidth) * charWidth,
                              height: CGFloat(lineRange.integerLength) * lineHeight)
            porthole.set(size: size)
            porthole.view.frame = NSRect(x: hmargin,
                                         y: CGFloat(lineRange.lowerBound) * lineHeight,
                                         width: size.width,
                                         height: size.height)
        }
        updateAlphaValue()
    }

    @objc
    var hasPortholes: Bool {
        return portholes.count > 0
    }

    // Because Swift can't cope with forward declarations and I don't want a dependency cycle.
    private var typedPortholes: [Porthole] {
        return portholes as! [Porthole]
    }

    @objc
    func removePortholeSelections() {
        for porthole in typedPortholes {
            porthole.removeSelection()
        }
    }

    @objc
    func updatePortholeColors() {
        for porthole in typedPortholes {
            porthole.updateColors()
        }
    }

    @objc
    func absRangeIntersectsPortholes(_ absRange: VT100GridAbsCoordRange) -> Bool {
        guard let dataSource = dataSource else {
            return false
        }
        let range = VT100GridCoordRangeFromAbsCoordRange(absRange, dataSource.totalScrollbackOverflow())
        for porthole in typedPortholes {
            let portholeRange = dataSource.coordRange(of: porthole)
            guard portholeRange != VT100GridCoordRangeInvalid else {
                continue
            }
            let lhs = portholeRange.start.y...portholeRange.end.y
            let rhs = range.start.y...range.end.y
            if lhs.overlaps(rhs) {
                return true
            }
        }
        return false
    }

    @objc(setNeedsPrunePortholes:)
    func setNeedsPrunePortholes(_ needs: Bool) {
        if self.portholesNeedUpdatesJoiner == nil {
            self.portholesNeedUpdatesJoiner = IdempotentOperationJoiner.asyncJoiner(.main)
        }
        self.portholesNeedUpdatesJoiner.setNeedsUpdate { [weak self] in
            self?.prunePortholes()
        }
    }
    @objc
    func prunePortholes() {
        let indexes = typedPortholes.indexes { porthole in
            porthole.mark == nil
        }
        for i in indexes {
            typedPortholes[i].view.removeFromSuperview()
        }
        portholes.removeObjects(at: indexes)
    }
}

extension Array {
    func indexes(where closure: (Element) throws -> Bool) rethrows -> IndexSet {
        var indexSet = IndexSet()
        for (i, element) in enumerated() {
            if try closure(element) {
                indexSet.insert(i)
            }
        }
        return indexSet
    }
}
extension PTYTextView: PortholeDelegate {
    func portholeDidAcquireSelection(_ porthole: ObjCPorthole) {
        selection.clear()
    }
}

extension ClosedRange where Bound: BinaryInteger {
    var integerLength: Bound {
        return upperBound - lowerBound + 1
    }
}

extension VT100GridCoordRange: Equatable {
    public static func == (lhs: VT100GridCoordRange, rhs: VT100GridCoordRange) -> Bool {
        return VT100GridCoordRangeEqualsCoordRange(lhs, rhs)
    }
}
