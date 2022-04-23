//
//  PTYTextView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import Foundation

extension PTYTextView {
    @objc(replaceWithPortholeInRange:havingText:baseDirectory:)
    func replaceWithPorthole(inRange absRange: VT100GridAbsCoordRange, text: String, baseDirectory: URL?) {
        guard dataSource != nil else {
            return
        }
        let config = PortholeConfig(text: text, colorMap: colorMap, baseDirectory: baseDirectory)
        let porthole = makePorthole(for: config)
        replace(range: absRange, withPorthole: porthole)
    }

    private func replace(range absRange: VT100GridAbsCoordRange,
                         withPorthole porthole: Porthole) {
        let hmargin = CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins))
        let desiredHeight = porthole.desiredHeight(forWidth: bounds.width - hmargin * 2)
        let relativeRange = VT100GridCoordRangeFromAbsCoordRange(absRange, dataSource.totalScrollbackOverflow())
        porthole.savedLines = (relativeRange.start.y ... relativeRange.end.y).map { i in
            dataSource.screenCharArray(forLine: i).copy() as! ScreenCharArray
        }
        dataSource.replace(absRange, with: porthole, ofHeight: Int32(ceil(desiredHeight / lineHeight)))
    }

    private func makePorthole(for config: PortholeConfig) -> Porthole {
        if let jsonPorthole = PortholeFactory.jsonPorthole(config: config) {
            return jsonPorthole
        }
        return PortholeFactory.markdownPorthole(config: config)
    }

    @objc
    func addPorthole(_ objcPorthole: ObjCPorthole) {
        let porthole = objcPorthole as! Porthole
        portholes.add(porthole)
        porthole.delegate = self
        superview?.addSubview(porthole.view)
        updatePortholeFrame(porthole, force: true)
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
        setNeedsDisplay(true)
        porthole.view.needsDisplay = true
        self.delegate?.textViewDidAddOrRemovePorthole()
    }

    @objc
    func removePorthole(_ objcPorthole: ObjCPorthole) {
        let porthole = objcPorthole as! Porthole
        willRemoveSubview(porthole.view)
        if porthole.delegate === self {
            porthole.delegate = nil
        }
        portholes.remove(porthole)
        porthole.view.removeFromSuperview()
        if let mark = porthole.mark {
            dataSource.replace(mark, withLines: porthole.savedLines)
        }
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
        self.delegate?.textViewDidAddOrRemovePorthole()
    }

    @objc
    func updatePortholeFrames() {
        for porthole in portholes {
            updatePortholeFrame(porthole as! Porthole, force: false)
        }
    }

    private func range(porthole: Porthole) -> VT100GridCoordRange? {
        guard porthole.mark != nil else {
            return nil
        }
        guard let dataSource = dataSource else {
            return nil
        }
        let gridCoordRange = dataSource.coordRange(of: porthole)
        guard gridCoordRange != VT100GridCoordRangeInvalid else {
            return nil
        }
        guard gridCoordRange.start.y <= gridCoordRange.end.y else {
            return nil
        }
        return gridCoordRange
    }

    // If force is true, recalculate the height even if the textview's width hasn't changed since
    // the last time this method was called.
    private func updatePortholeFrame(_ objcPorthole: ObjCPorthole, force: Bool) {
        let porthole = objcPorthole as! Porthole
        guard let dataSource = dataSource else {
            return
        }
        guard let gridCoordRange = range(porthole: porthole) else {
            return
        }
        let lineRange = gridCoordRange.start.y...gridCoordRange.end.y
        DLog("Update porthole with line range \(lineRange)")
        let hmargin = CGFloat(iTermPreferences.integer(forKey: kPreferenceKeySideMargins))
        let vmargin = CGFloat(iTermPreferences.integer(forKey: kPreferenceKeyTopBottomMargins))
        let cellWidth = dataSource.width()
        let innerMargin = porthole.outerMargin
        if lastPortholeWidth == cellWidth && !force {
            // Calculating porthole size is very slow because NSView is a catastrophe so avoid doing
            // it if the width is unchanged.
            porthole.view.frame = NSRect(x: hmargin,
                                         y: CGFloat(lineRange.lowerBound) * lineHeight + vmargin + innerMargin,
                                         width: bounds.width - hmargin * 2,
                                         height: CGFloat(lineRange.count) * lineHeight - innerMargin * 2)
        } else {
            lastPortholeWidth = cellWidth
            porthole.view.frame = NSRect(x: hmargin,
                                         y: CGFloat(lineRange.lowerBound) * lineHeight + vmargin + innerMargin,
                                         width: bounds.width - hmargin * 2,
                                         height: CGFloat(lineRange.count) * lineHeight - innerMargin * 2)
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
    func portholeDidAcquireSelection(_ porthole: Porthole) {
        selection.clear()
    }

    func portholeRemove(_ porthole: Porthole) {
        removePorthole(porthole)
    }
}

extension VT100GridCoordRange: Equatable {
    public static func == (lhs: VT100GridCoordRange, rhs: VT100GridCoordRange) -> Bool {
        return VT100GridCoordRangeEqualsCoordRange(lhs, rhs)
    }
}
