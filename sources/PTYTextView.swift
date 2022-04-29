//
//  PTYTextView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import Foundation

extension VT100GridAbsCoordRange {
    func relativeRange(overflow: Int64) -> VT100GridCoordRange {
        return VT100GridCoordRangeFromAbsCoordRange(self, overflow)
    }
}

extension VT100GridCoordRange {
    var windowedWithDefaultWindow: VT100GridWindowedRange {
        return VT100GridWindowedRangeMake(self, 0, 0)
    }
}

extension PTYTextView {
    private var portholeWithSelection: Porthole? {
        return typedPortholes.first { $0.hasSelection }
    }

    @objc var anyPortholeHasSelection: Bool {
        return portholeWithSelection != nil
    }

    @objc func copyFromPortholeAsPlainText() {
        portholeWithSelection?.copy(as: .plainText)
    }

    @objc func copyFromPortholeAsAttributedString() {
        portholeWithSelection?.copy(as: .attributedString)
    }

    @objc func copyFromPortholeWithControlSequences() {
        portholeWithSelection?.copy(as: .controlSequences)
    }

    @objc(renderRange:type:filename:)
    func render(range originalRange: VT100GridAbsCoordRange,
                type: String?,
                filename: String?) {
        DLog("render(range:\(VT100GridAbsCoordRangeDescription(originalRange)), type:\(String(describing: type)), filename:\(String(describing: filename)))")
        guard let dataSource = dataSource else {
            DLog("nil datasource")
            return
        }
        var absRange = originalRange
        let overflow = dataSource.totalScrollbackOverflow()
        let width = dataSource.width()
        let relativeRange = absRange.relativeRange(overflow: overflow)
        absRange.start.x = 0
        if absRange.end.x > 0 {
            absRange.end.x = width
        }
        let text = self.text(inRange: absRange.relativeRange(overflow: overflow))
        let pwd = dataSource.workingDirectory(onLine: relativeRange.start.y)
        let baseDirectory = pwd.map { URL(fileURLWithPath: $0) }
        replaceWithPorthole(inRange: absRange,
                            text: text,
                            baseDirectory: baseDirectory,
                            type: type,
                            filename: filename)
    }

    func text(inRange range: VT100GridCoordRange) -> String {
        DLog("text(inRange:\(VT100GridCoordRangeDescription(range))")
        let extractor = iTermTextExtractor(dataSource: dataSource)
        let windowedRange = range.windowedWithDefaultWindow
        let text = extractor.content(in: windowedRange,
                                     attributeProvider: nil,
                                     nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                                     pad: false,
                                     includeLastNewline: false,
                                     trimTrailingWhitespace: false,
                                     cappedAtSize: -1,
                                     truncateTail: false,
                                     continuationChars: nil,
                                     coords: nil) as! String
        DLog("Return \(text)")
        return text
    }

    @objc(replaceWithPortholeInRange:havingText:baseDirectory:type:filename:)
    func replaceWithPorthole(inRange absRange: VT100GridAbsCoordRange,
                             text: String,
                             baseDirectory: URL?,
                             type: String?,
                             filename: String?) {
        DLog("replaceWithPorthole(inRange:\(VT100GridAbsCoordRangeDescription(absRange)), text:\(String(describing: text)), baseDirectory:\(String(describing: baseDirectory)), type:\(String(describing: type)), filename:\(String(describing: filename))")

        guard dataSource != nil else {
            DLog("nil dataSource")
            return
        }
        let config = PortholeConfig(text: text,
                                    colorMap: colorMap,
                                    baseDirectory: baseDirectory,
                                    font: font,
                                    type: type,
                                    filename: filename)
        let porthole = makePorthole(for: config)
        replace(range: absRange, withPorthole: porthole)
    }

    private func replace(range absRange: VT100GridAbsCoordRange,
                         withPorthole porthole: Porthole) {
        DLog("replace(range:\(VT100GridAbsCoordRangeDescription(absRange)), withPorthole:\(porthole))")
        let hmargin = CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins))
        let desiredHeight = porthole.desiredHeight(forWidth: bounds.width - hmargin * 2)
        let relativeRange = VT100GridCoordRangeFromAbsCoordRange(absRange, dataSource.totalScrollbackOverflow())
        porthole.savedLines = (relativeRange.start.y ... relativeRange.end.y).map { i in
            dataSource.screenCharArray(forLine: i).copy() as! ScreenCharArray
        }
        dataSource.replace(absRange, with: porthole, ofHeight: Int32(ceil(desiredHeight / lineHeight)))
    }

    private func makePorthole(for config: PortholeConfig) -> Porthole {
        DLog("makePorthole(for:\(config)")
        return configuredPorthole(PortholeFactory.textViewPorthole(config: config))
    }

    private func configuredPorthole(_ porthole: Porthole) -> Porthole {
        DLog("configurePorthole(\(porthole))")
        if let textPorthole = porthole as? TextViewPorthole {
            textPorthole.changeLanguageCallback = { [weak self] language, porthole in
                guard let self = self else {
                    return
                }
                self.layoutPorthole(porthole)
            }
        }
        return porthole
    }

    private func layoutPorthole(_ porthole: TextViewPorthole) {
        DLog("layoutPorthole(\(porthole))")
        guard let dataSource = dataSource else {
            return
        }
        let hmargin = CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins))
        let desiredHeight = porthole.desiredHeight(forWidth: bounds.width - hmargin * 2)
        dataSource.changeHeight(of: porthole.mark, to: Int32(ceil(desiredHeight / lineHeight)))
    }

    @objc
    func addPorthole(_ objcPorthole: ObjCPorthole) {
        DLog("addPorthole(\(objcPorthole))")
        let porthole = objcPorthole as! Porthole
        portholes.add(porthole)
        addPortholeView(porthole)
    }

    @objc func hydratePorthole(_ mark: PortholeMarkReading) -> ObjCPorthole? {
        DLog("hydratePorthole(\(mark))")
        guard let porthole = PortholeRegistry.instance.get(mark.uniqueIdentifier,
                                                           colorMap: colorMap,
                                                           font: font) as? Porthole else {
            return nil
        }
        return configuredPorthole(porthole)
    }

    private func addPortholeView(_ porthole: Porthole) {
        DLog("addPortholeView(\(porthole))")
        porthole.delegate = self
        // I'd rather add it to TextViewWrapper but doing so somehow causes TVW to be overreleased
        // and I can't figure out why.
        addSubview(porthole.view)
        updatePortholeFrame(porthole, force: true)
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
        setNeedsDisplay(true)
        porthole.view.needsDisplay = true
        self.delegate?.textViewDidAddOrRemovePorthole()
    }

    // Continue owning the porthole but remove it from view.
    @objc
    func hidePorthole(_ objcPorthole: ObjCPorthole) {
        DLog("hidePorthole(\(objcPorthole))")
        let porthole = objcPorthole as! Porthole
        willRemoveSubview(porthole.view)
        if porthole.delegate === self {
            porthole.delegate = nil
        }
        porthole.view.removeFromSuperview()
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
        self.delegate?.textViewDidAddOrRemovePorthole()
    }

    @objc
    func unhidePorthole(_ objcPorthole: ObjCPorthole) {
        DLog("unhidePorthole(\(objcPorthole))")
        let porthole = objcPorthole as! Porthole
        precondition(portholes.contains(porthole))
        precondition(porthole.view.superview != self)
        addPortholeView(porthole)
    }

    @objc
    func removePorthole(_ objcPorthole: ObjCPorthole) {
        DLog("removePorthole(\(objcPorthole))")
        let porthole = objcPorthole as! Porthole
        willRemoveSubview(porthole.view)
        if porthole.delegate === self {
            porthole.delegate = nil
        }
        portholes.remove(porthole)
        porthole.view.removeFromSuperview()
        if let mark = PortholeRegistry.instance.mark(for: porthole.uniqueIdentifier) {
            dataSource.replace(mark, withLines: porthole.savedLines)
        }
        NotificationCenter.default.post(name: NSNotification.Name.iTermPortholesDidChange, object: nil)
        self.delegate?.textViewDidAddOrRemovePorthole()
    }

    @objc
    func updatePortholeFrames() {
        DLog("Begin updatePortholeFrames")
        for porthole in portholes {
            updatePortholeFrame(porthole as! Porthole, force: false)
        }
        DLog("End updatePortholeFrames")
    }

    private func range(porthole: Porthole) -> VT100GridCoordRange? {
        DLog("range(porthole: \(porthole))")
        guard PortholeRegistry.instance.mark(for: porthole.uniqueIdentifier) != nil else {
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
        DLog("return \(VT100GridCoordRangeDescription(gridCoordRange))")
        return gridCoordRange
    }

    // If force is true, recalculate the height even if the textview's width hasn't changed since
    // the last time this method was called.
    private func updatePortholeFrame(_ objcPorthole: ObjCPorthole, force: Bool) {
        DLog("updatePortholeFrame(\(objcPorthole)")
        let porthole = objcPorthole as! Porthole
        guard let dataSource = dataSource else {
            DLog("nil datasource")
            return
        }
        guard let gridCoordRange = range(porthole: porthole) else {
            DLog("no range")
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
            let y = CGFloat(lineRange.lowerBound) * lineHeight + vmargin + innerMargin
            DLog("y=\(y) range=\(String(describing: VT100GridCoordRangeDescription(gridCoordRange ))) overflow=\(dataSource.scrollbackOverflow())")
            porthole.view.frame = NSRect(x: hmargin,
                                         y: y,
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
        DLog("removePortholeSelections")
        for porthole in typedPortholes {
            porthole.removeSelection()
        }
    }

    @objc
    func updatePortholeColors() {
        DLog("updatePortholeColors")
        for porthole in typedPortholes {
            porthole.updateColors()
        }
    }

    @objc
    func absRangeIntersectsPortholes(_ absRange: VT100GridAbsCoordRange) -> Bool {
        DLog("absRangeIntersectsPortholes(\(VT100GridAbsCoordRangeDescription(absRange)))")
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
        DLog("setNeedsPrunePortholes(\(needs))")
        if self.portholesNeedUpdatesJoiner == nil {
            self.portholesNeedUpdatesJoiner = IdempotentOperationJoiner.asyncJoiner(.main)
        }
        self.portholesNeedUpdatesJoiner.setNeedsUpdate { [weak self] in
            self?.prunePortholes()
        }
    }
    @objc
    func prunePortholes() {
        DLog("prunePortholes")
        let registry = PortholeRegistry.instance
        let indexes = typedPortholes.indexes { porthole in
            registry.mark(for: porthole.uniqueIdentifier) == nil
        }
        for i in indexes {
            typedPortholes[i].view.removeFromSuperview()
        }
        portholes.removeObjects(at: indexes)
        DLog("done")
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
        DLog("portholeDidAcquireSelection")
        selection.clear()
        for other in typedPortholes {
            if porthole === other {
                continue
            }
            other.removeSelection()
        }
    }

    func portholeRemove(_ porthole: Porthole) {
        DLog("portholeRemove")
        removePorthole(porthole)
    }
}

extension VT100GridCoordRange: Equatable {
    public static func == (lhs: VT100GridCoordRange, rhs: VT100GridCoordRange) -> Bool {
        return VT100GridCoordRangeEqualsCoordRange(lhs, rhs)
    }
}
