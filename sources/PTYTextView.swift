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
        addSubview(porthole.view)
        updatePortholeFrame(porthole)
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
    }

    @objc
    func removePorthole(_ porthole: ObjCPorthole) {
        if porthole.view.superview == self {
            porthole.view.removeFromSuperview()
        }
        portholes.remove(porthole)
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
    }

    @objc
    func updatePortholeFrames() {
        for porthole in portholes {
            updatePortholeFrame(porthole as! Porthole)
        }
    }

    private func updatePortholeFrame(_ porthole: ObjCPorthole) {
        guard let firstLine = dataSource?.totalScrollbackOverflow() else {
            return
        }
        guard porthole.mark != nil else {
            return
        }
        guard let gridCoordRange = dataSource?.coordRange(of: porthole),
              gridCoordRange != VT100GridCoordRangeInvalid else {
            return
        }
        let absRange = VT100GridAbsCoordRangeFromCoordRange(gridCoordRange, firstLine)
        let lineRange = absRange.start.y...absRange.end.y
        guard lineRange.upperBound >= firstLine else {
            return
        }
        let hmargin = CGFloat(iTermPreferences.integer(forKey: kPreferenceKeySideMargins))
        let size = NSSize(width: bounds.width - hmargin * 2,
                          height: CGFloat(lineRange.integerLength) * lineHeight)
        porthole.set(size: size)
        porthole.view.frame = NSRect(x: hmargin,
                                     y: CGFloat(lineRange.lowerBound) * lineHeight,
                                     width: size.width,
                                     height: size.height)
        updateAlphaValue()
    }

    @objc
    var hasPortholes: Bool {
        return portholes.count > 0
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
