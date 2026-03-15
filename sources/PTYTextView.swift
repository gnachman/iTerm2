//
//  PTYTextView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import Foundation
import UniformTypeIdentifiers

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

extension PTYTextView: ExternalSearchResultsController {
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

    @objc(renderRange:type:filename:forceWide:)
    func render(range originalRange: VT100GridAbsCoordRange,
                type: String?,
                filename: String?,
                forceWide: Bool) {
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
                            filename: filename,
                            forceWide: forceWide)
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

    @objc(replaceWithPortholeInRange:havingText:baseDirectory:type:filename:forceWide:)
    func replaceWithPorthole(inRange absRange: VT100GridAbsCoordRange,
                             text: String,
                             baseDirectory: URL?,
                             type: String?,
                             filename: String?,
                             forceWide: Bool) {
        DLog("replaceWithPorthole(inRange:\(VT100GridAbsCoordRangeDescription(absRange)), text:\(String(describing: text)), baseDirectory:\(String(describing: baseDirectory)), type:\(String(describing: type)), filename:\(String(describing: filename))")

        guard dataSource != nil else {
            DLog("nil dataSource")
            return
        }
        let config = PortholeConfig(text: text,
                                    colorMap: colorMap,
                                    baseDirectory: baseDirectory,
                                    font: self.fontTable.asciiFont.font,
                                    type: type,
                                    filename: filename,
                                    useSelectedTextColor: delegate?.textViewShouldUseSelectedTextColor() ?? true,
                                    forceWide: iTermAdvancedSettingsModel.defaultWideMode() || forceWide)
        let porthole = makePorthole(for: config)
        replace(range: absRange, withPorthole: porthole)
    }

    private func replace(range absRange: VT100GridAbsCoordRange,
                         withPorthole porthole: Porthole) {
        DLog("replace(range:\(VT100GridAbsCoordRangeDescription(absRange)), withPorthole:\(porthole))")
        let hmargin = CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins))
        let desiredHeight = porthole.fit(toWidth: bounds.width - hmargin * 2)
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

    private func layoutPorthole(_ porthole: Porthole) {
        DLog("layoutPorthole(\(porthole))")
        guard let dataSource = dataSource else {
            return
        }
        let hmargin = CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins))
        let desiredHeight = porthole.fit(toWidth: bounds.width - hmargin * 2)
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
        guard let interval = mark.entry?.interval,
              let absRange = dataSource?.absCoordRange(for: interval) else {
            return nil
        }
        guard let porthole = PortholeRegistry.instance.get(mark.uniqueIdentifier,
                                                           colorMap: colorMap,
                                                           useSelectedTextColor: delegate?.textViewShouldUseSelectedTextColor() ?? true,
                                                           font: self.fontTable.asciiFont.font) as? Porthole else {
            return nil
        }
        // If there were any annotations, fix their delegate pointer up.
        dataSource?.add(porthole.savedITOs, baseLine: absRange.start.y)
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
        requestDelegateRedraw()
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
            dataSource?.replace(mark, withLines: porthole.savedLines, savedITOs: porthole.savedITOs)
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

    @objc(stringForPortholeInRange:)
    func stringForPorthole(range: VT100GridCoordRange) -> String? {
        for obj in portholes {
            let porthole = obj as! Porthole
            guard let gridCoordRange = self.range(porthole: porthole) else {
                continue
            }
            if range.start.y < gridCoordRange.end.y && range.end.y > gridCoordRange.start.y {
                return porthole.savedLines.map {
                    $0.stringValue
                }.joined(separator: "\n")
            }
        }
        return nil
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
            porthole.set(frame: NSRect(x: hmargin,
                                       y: y,
                                       width: bounds.width - hmargin * 2,
                                       height: CGFloat(lineRange.count) * lineHeight - innerMargin * 2))
        } else {
            lastPortholeWidth = cellWidth
            porthole.set(frame: NSRect(x: hmargin,
                                       y: CGFloat(lineRange.lowerBound) * lineHeight + vmargin + innerMargin,
                                       width: bounds.width - hmargin * 2,
                                       height: CGFloat(lineRange.count) * lineHeight - innerMargin * 2))
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
    func removePortholeHighlights() {
        for porthole in typedPortholes {
            porthole.removeHighlights()
        }
    }

    @objc(removePortholeHighlightsFrom:)
    func removePortholeHighlights(from externalSearchResult: ExternalSearchResult) {
        externalSearchResult.owner?.remove(externalSearchResult)
    }


    @objc
    func updatePortholeColors(useSelectedTextColor: Bool, deferUpdate: Bool) {
        DLog("updatePortholeColors(useSelectedTextColor: \(useSelectedTextColor))")
        for porthole in typedPortholes {
            porthole.updateColors(useSelectedTextColor: useSelectedTextColor,
                                  deferUpdate: deferUpdate)
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

    @objc
    func searchPortholes(for string: String, mode: iTermFindMode) -> [ExternalSearchResult] {
        var result = [ExternalSearchResult]()
        for porthole in typedPortholes {
            result.append(contentsOf: porthole.find(string, mode: mode))
        }
        return result
    }

    @objc(selectExternalSearchResult:multiple:scroll:)
    @discardableResult
    func select(externalSearchResult result: ExternalSearchResult,
                multiple: Bool,
                scroll: Bool) -> VT100GridCoordRange {
        let overflow = dataSource?.totalScrollbackOverflow() ?? 0
        let y = Int32(result.absLine - overflow)
        if let porthole = self.porthole(for: result),
           let rect = porthole.select(searchResult: result,
                                      multiple: multiple,
                                      returningRectRelativeTo: self,
                                      scroll: scroll) {
            if scroll {
                // This is necessary when there's a horizontally scrolling scrollview in the porthole
                // in order to make PTYScrollView move vertically.
                let line = Int32(rect.midY / lineHeight)
                self.scroll(toCenterLine: line)
                (enclosingScrollView?.verticalScroller as? PTYScroller)?.userScroll = true
            }
            return VT100GridCoordRange(
                start: VT100GridCoord(x: 0,
                                      y: y),
                end: VT100GridCoord(x: 0,
                                    y: y + Int32(floor(rect.height / lineHeight))))
        } else {
            return VT100GridCoordRange(start: VT100GridCoord(x: 0, y: y),
                                       end: VT100GridCoord(x: 0, y: y + result.numLines))
        }
    }

    @objc func externalSearchResults(for query: String, mode: iTermFindMode) -> [ExternalSearchResult] {
        return typedPortholes.flatMap { porthole in
            porthole.find(query, mode: mode)
        }
    }
    func snippet(from result: ExternalSearchResult,
                 matchAttributes: [NSAttributedString.Key : Any],
                 regularAttributes: [NSAttributedString.Key : Any]) -> NSAttributedString? {
        return porthole(for: result)?.snippet(for: result,
                                              matchAttributes: matchAttributes,
                                              regularAttributes: regularAttributes)
    }


    private func porthole(for result: ExternalSearchResult) -> Porthole? {
        guard let owner = result.owner else {
            return nil
        }
        guard let i = typedPortholes.firstIndex(where: { $0 === owner }) else {
            return nil
        }
        return typedPortholes[i]
    }

    // MARK: - Marks

    @objc(foldMarkAtWindowCoord:)
    func foldMark(at windowCoord: NSPoint) -> FoldMarkReading? {
        guard let dataSource = dataSource else {
            return nil
        }
        let locationInTextView = convert(windowCoord, from: nil)
        if Int(clamping: locationInTextView.x) >= iTermPreferences.int(forKey: kPreferenceKeySideMargins) + Int32(PTYTextViewMarginClickGraceWidth) {
            return nil
        }
        let coord = self.coord(for: locationInTextView, allowRightMarginOverflow: true)
        if coord.y < 0 {
            return nil
        }
        let marks = dataSource.foldMarks(in: VT100GridRange(location: coord.y, length: 1))
        return marks?.first
    }

    @objc(commandMarkAtWindowCoord:)
    func commandMark(at windowCoord: NSPoint) -> VT100ScreenMarkReading? {
        let locationInTextView = convert(windowCoord, from: nil)
        if Int(clamping: locationInTextView.x) >= iTermPreferences.int(forKey: kPreferenceKeySideMargins) {
            return nil
        }
        let coord = self.coord(for: locationInTextView, allowRightMarginOverflow: true)
        if coord.y < 0 {
            return nil
        }
        return dataSource?.commandMark(at: VT100GridCoord(x: 0, y: coord.y),
                                      mustHaveCommand: true,
                                      range: nil)
    }

    @objc(pathMarkAtWindowCoord:)
    func pathMark(at windowCoord: NSPoint) -> PathMarkReading? {
        let locationInTextView = convert(windowCoord, from: nil)
        if Int(clamping: locationInTextView.x) < iTermPreferences.int(forKey: kPreferenceKeySideMargins) {
            return nil
        }
        guard let dataSource = dataSource else {
            return nil
        }
        let coord = self.coord(for: locationInTextView, allowRightMarginOverflow: true)
        if coord.y < 0 {
            return nil
        }
        return dataSource.pathMark(at: coord)
    }

    // MARK: - Folding

    @objc(toggleFoldSelectionAbsoluteLines:)
    func toggleFold(nsrange: NSRange) {
        guard let range = Range<Int64>(nsrange) else {
            return
        }
        guard let dataSource else {
            return
        }
        // If we can remove folds in this range, do so and don't continue.
        if dataSource.removeFolds(in: nsrange) {
            requestDelegateRedraw()
            return
        }
        let promptLength = self.promptLength(at: range.lowerBound)
        fold(range: range, promptLength: Int(promptLength))
    }

    @objc(unfoldAbsoluteLineRange:)
    func unfold(nsrange: NSRange) {
        guard Range<Int64>(nsrange) != nil else {
            return
        }
        guard let dataSource else {
            return
        }
        // If we can remove folds in this range, do so and don't continue.
        if dataSource.removeFolds(in: nsrange) {
            requestDelegateRedraw()
            return
        }
    }

    @objc(foldRange:)
    func fold(nsrange: NSRange) {
        guard let range = Range<Int64>(nsrange) else {
            return
        }
        let promptLength = self.promptLength(at: range.lowerBound)
        fold(range: range, promptLength: Int(promptLength))
    }

    private func promptLength(at absY: Int64) -> Int32 {
        var result: Int32 = 0
        withRelativeCoord(VT100GridAbsCoord(x: 0, y: absY)) { coord in
            if let mark = dataSource?.commandMark(at: coord, mustHaveCommand: true, range: nil),
               mark.promptRange.start.y == absY {
                result = mark.promptRange.height
            }
        }
        return result

    }
    private func fold(range: Range<Int64>,
                      promptLength: Int) {
        guard let dataSource else {
            return
        }
        DLog("Fold")
        let overflow = dataSource.totalScrollbackOverflow()
        let absRange = VT100GridAbsCoordRange(start: VT100GridAbsCoord(x: 0,
                                                                       y: range.lowerBound),
                                              end: VT100GridAbsCoord(x: dataSource.width(),
                                                                     y: range.upperBound - 1))
        let firstLine = dataSource.screenCharArray(forLine: Int32(max(0, range.lowerBound - overflow)))
        let lastLine = dataSource.screenCharArray(forLine: Int32(max(0, range.upperBound - 1 - overflow)))
        let line = firstEllipsisLast(firstLine, lastLine, length: dataSource.width(), count: Int(absRange.end.y - absRange.start.y) - 1)

        let blockMarks = dataSource.blockMarkDictionary(onLine: absRange.start.y)
        dataSource.replace(absRange,
                           withLines: [line.clone()],
                           promptLength: promptLength,
                           blockMarks: blockMarks)
        requestDelegateRedraw()
        didFoldOrUnfold()
    }

    // Make a display line that summarizes a folded region as [first line prefix] [ellipsis] [last line prefix].
    private func firstEllipsisLast(_ first: ScreenCharArray,
                                   _ untrimmedLast: ScreenCharArray,
                                   length: Int32,
                                   count: Int) -> ScreenCharArray {
        if length <= 0 {
            return ScreenCharArray.emptyLine(ofLength: 0)
        }
        let n = untrimmedLast.number(ofLeadingEmptyCellsWhereSpaceIsEmpty: true)
        let last = untrimmedLast.subArray(from: n)
        let firstMaxLength = first.length - first.number(ofTrailingEmptyCellsWhereSpaceIsEmpty: true)
        let lastMaxLength = last.length - last.number(ofTrailingEmptyCellsWhereSpaceIsEmpty: true)

        var mid = " …\(count) line\(count > 1 ? "s" : "")… "
        if mid.utf16.count + 10 > length {
            mid = "…"
        }
        let midLength = Int32(mid.utf16.count)

        var firstLength = firstMaxLength
        var lastLength = lastMaxLength
        var overage = (firstLength + midLength + lastLength) - length
        while overage > 0 {
            if firstLength == lastLength {
                firstLength -= overage / 2
                lastLength -= (overage + 1) / 2  // round up if overage is odd so the total equals overage
            } else if firstLength > lastLength {
                firstLength -= min(firstLength - lastLength, overage)
            } else {
                lastLength -= (min(lastLength - firstLength, overage))
            }
            overage = (firstLength + midLength + lastLength) - length
        }
        let result = MutableScreenCharArray()

        // first
        result.append(first.paddedOrTruncated(toLength: UInt(firstLength)))

        // ellipsis
        result.append(mid, fg: screen_char_t(), bg: screen_char_t())

        // last
        result.append(last.paddedOrTruncated(toLength: UInt(lastLength)))

        // padding
        if overage < 0 {
            result.append(ScreenCharArray.emptyLine(ofLength: -overage))
        }

        var bg = screen_char_t()
        bg.backgroundColorMode = ColorModeAlternate.rawValue
        bg.backgroundColor = UInt32(ALTSEM_DEFAULT)
        result.setBackground(bg, in: NSRange(location: 0, length: Int(length)))

        var fg = screen_char_t()
        fg.foregroundColorMode = ColorModeAlternate.rawValue
        fg.foregroundColor = UInt32(ALTSEM_DEFAULT)
        fg.fgBlue = 0
        fg.fgGreen = 0
        fg.faint = 1
        fg.italic = 1
        result.setForeground(fg, in: NSRange(location: 0, length: Int(length)))
        result.setExternalAttributesIndex(first.eaIndex)

        var continuation = bg
        continuation.code = UInt16(EOL_HARD)
        result.continuation = continuation
        return result
    }

    @objc(unfoldMark:)
    func unfold(mark: FoldMarkReading) {
        guard let interval = mark.entry?.interval else {
            return
        }
        guard let dataSource = dataSource else {
            return
        }
        DLog("Unfold")
        let coord = dataSource.absCoordRange(for: interval)
        dataSource.removeFolds(in: NSRange(location: Int(coord.start.y), length: 1))
        requestDelegateRedraw()
        didFoldOrUnfold()
    }

    @objc(foldCommandMark:)
    func fold(commandMark: VT100ScreenMarkReading) {
        guard let dataSource = dataSource else {
            return
        }
        let range = dataSource.rangeOfCommandAndOutput(forMark: commandMark, includeSucessorDivider: false)
        fold(range: Range(range.start.y...range.end.y),
             promptLength: Int(commandMark.promptRange.height))
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

    func portholeResize(_ porthole: Porthole) {
        layoutPorthole(porthole)
    }

    func portholeAbsLine(_ porthole: Porthole) -> Int64 {
        guard let dataSource = dataSource else {
            return -1
        }
        let range = dataSource.coordRange(of: porthole)
        if range == VT100GridCoordRangeInvalid {
            return -1
        }
        let absRange = VT100GridAbsCoordRangeFromCoordRange(
            range,
            dataSource.totalScrollbackOverflow())
        return absRange.start.y
    }

    func portholeHeight(_ porthole: Porthole) -> Int32 {
        guard let dataSource = dataSource else {
            return -1
        }
        let range = dataSource.coordRange(of: porthole)
        if range == VT100GridCoordRangeInvalid {
            return -1
        }
        return range.end.y - range.start.y + 1
    }
}

extension VT100GridCoordRange: Equatable {
    public static func == (lhs: VT100GridCoordRange, rhs: VT100GridCoordRange) -> Bool {
        return VT100GridCoordRangeEqualsCoordRange(lhs, rhs)
    }
}

extension PTYTextView {
    @objc
    func copySelectedCommand() {
        guard let mark = delegate?.textViewSelectedCommandMark() else {
            return
        }
        let selection = selectionForCommandAndOutput(ofMark: mark)
        copySelection(selection)
    }

    @objc
    func copySelectedCommandWithStyles() {
        guard let mark = delegate?.textViewSelectedCommandMark() else {
            return
        }
        let selection = selectionForCommandAndOutput(ofMark: mark)
        copySelection(withStyles: selection)
    }

    @objc
    func copySelectedCommandWithControlSequences() {
        guard let mark = delegate?.textViewSelectedCommandMark() else {
            return
        }
        let selection = selectionForCommandAndOutput(ofMark: mark)
        copySelection(withControlSequences: selection)
    }
}

extension PTYTextView: NSViewContentSelectionInfo {
    func clampedRelativeCoord(_ absCoord: VT100GridAbsCoord) -> VT100GridCoord {
        var result = VT100GridCoordMake(0, 0)
        withRelativeCoord(absCoord) { relative in
            result = relative
        }
        return result
    }

    func rect(for range: VT100GridAbsCoordRange) -> NSRect {
        let width = dataSource?.width() ?? 1
        let relativeStart = clampedRelativeCoord(range.start)
        let relativeEnd = clampedRelativeCoord(range.end)
        var coords = [relativeStart, relativeEnd]
        if relativeStart.y != relativeEnd.y {
            coords.append(VT100GridCoord(x: width - 1, y: relativeStart.y))
            coords.append(VT100GridCoord(x: 0, y: relativeEnd.y))
        }
        let rects = coords.map { rect(for: $0) }
        return rects.reduce(into: rects.first!) { partialResult, rect in
            partialResult = partialResult.union(rect)
        }
    }

    public var selectionAnchorRect: NSRect {
        guard let dataSource else {
            return .null
        }
        let temp = rangeOfVisibleLines
        let offset = dataSource.totalScrollbackOverflow()
        let visibleAbsRange = VT100GridAbsCoordRangeMake(0,
                                                         Int64(temp.location) + offset,
                                                         0,
                                                         Int64(temp.location) + Int64(temp.length) + offset)
        let visibleAbsLines = (visibleAbsRange.start.y)..<(visibleAbsRange.end.y)
        for subselection in selection.allSubSelections {
            let absRange = subselection.absRange
            let selRange = absRange.coordRange.start.y..<(absRange.coordRange.end.y + 1)
            if visibleAbsLines.overlaps(selRange) {
                let visibleSelectedAbsRange = VT100GridAbsCoordRangeIntersection(absRange.coordRange,
                                                                                 visibleAbsRange,
                                                                                 dataSource.width())
                if visibleSelectedAbsRange.start.x >= 0 {
                    let hull = rect(for: visibleSelectedAbsRange)
                    if absRange.columnWindow.location >= 0 && absRange.columnWindow.length > 0 {
                        var columnRect = rect(
                            for: VT100GridAbsCoordRange(
                                start: VT100GridAbsCoord(
                                    x: absRange.columnWindow.location,
                                    y: offset),
                                end: VT100GridAbsCoord(
                                    x: absRange.columnWindow.location + absRange.columnWindow.length,
                                    y: offset)))
                        columnRect.origin.y = hull.origin.y
                        columnRect.size.height = hull.size.height
                        return columnRect.intersection(hull)
                    }
                    return hull
                }
            }
        }
        let cursorCoord = VT100GridCoord(x: dataSource.cursorX() - 1,
                                         y: dataSource.numberOfScrollbackLines() + dataSource.cursorY() - 1)
        let cursorAbsCoord = VT100GridAbsCoordFromCoord(cursorCoord, offset)
        if visibleAbsLines.contains(cursorAbsCoord.y) {
            return rect(for: cursorCoord)
        }
        return .null
     }
}

extension PTYTextView {
    @objc(swiftValidateMenuItem:)
    func swiftValidate(menuItem item: NSMenuItem) -> Bool {
        if item.action == #selector(downloadFiles(_:)) {
            if #available(macOS 11, *) {
                return !ConductorRegistry.instance.isEmpty
            } else {
                return false
            }
        } else if item.action == #selector(saveArchive(_:)) {
            return true
        } else if item.action == #selector(toggleBufferInput(_:)) {
            item.state = (delegate?.textViewIsBufferingInput() ?? false) ? .on : .off
            return true
        } else if item.action == #selector(foldAll(_:)) {
            guard let dataSource else { return false }
            if dataSource.terminalSoftAlternateScreenMode() {
                return false
            }
            let cursorLine = dataSource.lineNumberOfCursor()
            // Disabled if cursor on first visible line
            if cursorLine <= 0 {
                return false
            }
            // Disabled if all lines above cursor are already folds. But only
            // check for smallish ranges to avoid this taking too long. If you
            // want to fold 100 folds go for it I guess.
            if cursorLine < 100 {
                let rangeAbove = VT100GridRange(location: 0, length: cursorLine)
                if dataSource.folds(in: rangeAbove).count == cursorLine {
                    return false
                }
            }
            return true
        }
        return false
    }

    @IBAction func downloadFiles(_ sender: Any) {
        let panel = iTermOpenPanel()
        panel.includeLocalhost = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        let provider = AITermController.provider
        panel.isSelectable = { remoteFile in
            return provider?.fileTypeIsSupported(extension: remoteFile.name.pathExtension.lowercased()) == true
        }
        panel.beginSSH(window: window) { response in
            guard response == .OK else {
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting(panel.items.map { $0.urlPromise.maybeValue }.compactMap { $0 as? URL })
        }
    }
}

@objc
extension PTYTextView {
    @IBAction
    @objc(saveArchive:)
    func saveArchive(_ sender: Any) {
        if let window = self.window {
            let savePanel = iTermModernSavePanel()
            savePanel.defaultFilename = ((delegate?.textViewVariablesScope().value(forVariableName: iTermVariableKeySessionName) as? String) ?? "iTerm2 Session") + ".itermarchive"
            savePanel.preferredSSHIdentity = .localhost
            savePanel.allowedContentTypes = [ UTType(filenameExtension: "itermarchive")! ]
            Task {
                let response = await savePanel.beginSheetModal(for: window)
                if response == .OK,
                   let item = savePanel.item {
                    delegate?.textViewSaveArchive(item)
                }
            }
        }
    }
}

@objc
extension PTYTextView {
    @IBAction
    @objc(toggleBufferInput:)
    func toggleBufferInput(_ sender: Any) {
        delegate?.textViewToggleBufferInput()
    }
}

// MARK: - Accessibility Deletion Detection

extension PTYTextView {
    /// Returns a located string for the current cursor line.
    /// Each character's grid coordinate is tracked for proper position-based comparison.
    @objc
    func accessibilityLocatedStringForCursorLine() -> iTermLocatedString {
        let result = iTermLocatedString()
        guard let dataSource else {
            return result
        }

        let cursorY = dataSource.cursorY()  // 1-based
        let lineIndex = dataSource.numberOfScrollbackLines() + cursorY - 1
        let lines = dataSource.lines(in: NSRange(location: Int(lineIndex), length: 1))

        guard let screenCharArray = lines?.first else {
            return result
        }

        let line = screenCharArray.line
        let length = Int(screenCharArray.length)
        let privateRange = unichar(ITERM2_PRIVATE_BEGIN)...unichar(ITERM2_PRIVATE_END)

        for x in 0..<length {
            var theChar = line[x]
            let coord = VT100GridCoordMake(Int32(x), cursorY - 1)

            if theChar.code == 0 || privateRange.contains(theChar.code) {
                // Nulls and private chars become spaces
                result.appendString(" ", at: coord)
            } else if theChar.image != 0 {
                // Skip images
                continue
            } else {
                let string = ScreenCharToStr(&theChar) ?? " "
                result.appendString(string, at: coord)
            }
        }

        return result
    }

    /// Detects text deletion by comparing old and new cursor line content.
    /// Returns the deleted text to announce, or nil if no deletion detected.
    @objc
    func accessibilityDetectDeletion(oldCursorX: Int32,
                                     newCursorX: Int32,
                                     oldLocatedString: iTermLocatedString,
                                     newLocatedString: iTermLocatedString) -> String? {
        // Grid coordinates use 0-based x values
        let oldGridX = oldCursorX - 1
        let newGridX = newCursorX - 1

        let oldCoords = oldLocatedString.gridCoords
        let oldString = oldLocatedString.string
        let newCoords = newLocatedString.gridCoords
        let newString = newLocatedString.string

        if newCursorX < oldCursorX {
            // Case A: Cursor moved left (backspace, word-delete, Ctrl+U)
            // Find characters in the old string with x in [newGridX, oldGridX)
            let oldRange = oldCoords.rangeOfIndices(xFrom: newGridX, to: oldGridX)
            if oldRange.location != NSNotFound && oldRange.length > 0 {
                let oldSub = (oldString as NSString).substring(with: oldRange)
                // Check if the text at those positions actually changed
                let newRange = newCoords.rangeOfIndices(xFrom: newGridX, to: oldGridX)
                let newSub = (newRange.location != NSNotFound && newRange.length > 0)
                    ? (newString as NSString).substring(with: newRange)
                    : ""
                if oldSub != newSub {
                    return oldSub
                }
            }
        } else if newCursorX == oldCursorX && oldString != newString {
            // Case B: Cursor stayed, line content changed (forward-delete, Ctrl+K)
            // Find characters at and after cursor position in both strings
            let oldStartIdx = oldCoords.indexOfFirstCoord(xGreaterOrEqual: newGridX)
            let newStartIdx = newCoords.indexOfFirstCoord(xGreaterOrEqual: newGridX)

            let oldAfter: String
            if oldStartIdx != NSNotFound {
                oldAfter = (oldString as NSString).substring(from: oldStartIdx)
            } else {
                oldAfter = ""
            }

            let newAfter: String
            if newStartIdx != NSNotFound {
                newAfter = (newString as NSString).substring(from: newStartIdx)
            } else {
                newAfter = ""
            }

            let whitespace = CharacterSet.whitespaces
            let oldTrimmed = oldAfter.trimmingCharacters(in: whitespace)
            let newTrimmed = newAfter.trimmingCharacters(in: whitespace)

            if !oldTrimmed.isEmpty && newTrimmed.isEmpty {
                // Kill to end (Ctrl+K): all text after cursor gone
                return oldTrimmed
            } else if !oldTrimmed.isEmpty && !oldAfter.hasPrefix(newAfter) {
                // Forward delete or other deletion: find what was removed
                // For single character forward delete, announce the first character
                if oldStartIdx != NSNotFound && oldStartIdx < oldString.count {
                    // Get the character(s) at the cursor position from old string
                    let cursorCoord = oldCoords.coord(at: oldStartIdx)
                    let charRange = oldCoords.rangeOfIndices(xFrom: cursorCoord.x, to: cursorCoord.x + 1)
                    if charRange.location != NSNotFound && charRange.length > 0 {
                        return (oldString as NSString).substring(with: charRange)
                    }
                }
            }
        }

        return nil
    }
}

// MARK: - Fold All

extension PTYTextView {
    @IBAction
    @objc(foldAll:)
    func foldAll(_ sender: Any) {
        foldAllAboveCursor()
    }

    @objc
    func foldAllAboveCursor() {
        guard let dataSource else { return }

        let cursorLine = dataSource.lineNumberOfCursor()
        guard cursorLine > 0 else { return }

        // Skip consecutive folds starting at line 0
        var startLine: Int32 = 0
        while startLine < cursorLine {
            let lineRange = VT100GridRange(location: startLine, length: 1)
            if (dataSource.folds(in: lineRange)?.count ?? 0) == 0 {
                break
            }
            startLine += 1
        }

        // If all lines are folds, nothing to do
        guard startLine < cursorLine else { return }

        // Range is from first non-fold line to cursorLine - 1
        let overflow = dataSource.totalScrollbackOverflow()
        let absStart = Int64(startLine) + overflow
        let absEnd = Int64(cursorLine) + overflow
        let range = absStart..<absEnd

        let placeholder = createFoldAllPlaceholder(range: range, dataSource: dataSource)
        let promptLength = self.promptLength(at: absStart)

        foldAllWithPlaceholder(range: range, promptLength: Int(promptLength), placeholder: placeholder)
    }

    private func createFoldAllPlaceholder(range: Range<Int64>, dataSource: PTYTextViewDataSource) -> ScreenCharArray {
        let width = dataSource.width()

        // Find first and last command marks with commands
        let (firstMark, lastMark) = findFirstAndLastCommandMarks(in: range, dataSource: dataSource)

        // Build placeholder text
        var parts: [String] = []

        // Localized compact date from first command's start date
        if let startDate = firstMark?.startDate {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            parts.append(formatter.string(from: startDate))
            parts.append("—")  // em dash
        }

        // First command (truncated)
        if let cmd = firstMark?.command, !cmd.isEmpty {
            parts.append(String(cmd.prefix(20)))
        }

        // Line count
        let lineCount = Int(range.upperBound - range.lowerBound)
        parts.append("…\(lineCount) line\(lineCount > 1 ? "s" : "")…")

        // Last command if different
        if let lastCmd = lastMark?.command,
           !lastCmd.isEmpty,
           lastMark !== firstMark {
            parts.append(String(lastCmd.prefix(20)))
        }

        let text = parts.joined(separator: " ")
        return createStyledPlaceholderLine(text: text, width: width)
    }

    private func findFirstAndLastCommandMarks(
        in range: Range<Int64>,
        dataSource: PTYTextViewDataSource
    ) -> (first: VT100ScreenMarkReading?, last: VT100ScreenMarkReading?) {
        let absRange = NSRange(location: Int(range.lowerBound), length: Int(range.upperBound - range.lowerBound))
        return (dataSource.firstCommandMarkWithCommand(in: absRange),
                dataSource.lastCommandMarkWithCommand(in: absRange))
    }

    private func createStyledPlaceholderLine(text: String, width: Int32) -> ScreenCharArray {
        let result = MutableScreenCharArray()
        result.append(text, fg: screen_char_t(), bg: screen_char_t())

        // Pad to width
        let currentLength = Int32(result.lengthExcludingTrailingWhitespaceAndNulls)
        if currentLength < width {
            result.append(ScreenCharArray.emptyLine(ofLength: width - currentLength))
        }

        // Apply faint italic styling (same as existing fold style)
        var bg = screen_char_t()
        bg.backgroundColorMode = ColorModeAlternate.rawValue
        bg.backgroundColor = UInt32(ALTSEM_DEFAULT)
        result.setBackground(bg, in: NSRange(location: 0, length: Int(width)))

        var fg = screen_char_t()
        fg.foregroundColorMode = ColorModeAlternate.rawValue
        fg.foregroundColor = UInt32(ALTSEM_DEFAULT)
        fg.faint = 1
        fg.italic = 1
        result.setForeground(fg, in: NSRange(location: 0, length: Int(width)))

        var continuation = bg
        continuation.code = UInt16(EOL_HARD)
        result.continuation = continuation
        return result
    }

    private func foldAllWithPlaceholder(range: Range<Int64>, promptLength: Int, placeholder: ScreenCharArray) {
        guard let dataSource else { return }

        let absRange = VT100GridAbsCoordRange(
            start: VT100GridAbsCoord(x: 0, y: range.lowerBound),
            end: VT100GridAbsCoord(x: dataSource.width(), y: range.upperBound - 1)
        )

        let blockMarks = dataSource.blockMarkDictionary(onLine: range.lowerBound)
        dataSource.replace(absRange,
                           withLines: [placeholder.clone()],
                           promptLength: promptLength,
                           blockMarks: blockMarks)
        requestDelegateRedraw()
        didFoldOrUnfold()
    }
}
