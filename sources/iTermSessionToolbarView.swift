//
//  iTermSessionToolbarView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/26.
//

import Foundation

protocol SessionToolbarItemDelegate: AnyObject {
    func itemDidChange(sender: SessionToolbarGenericView)
}

@objc(iTermSessionToolbarItem)
class SessionToolbarGenericView: NSObject {
    weak var delegate: SessionToolbarItemDelegate?
    let _view: NSView
    private let wrapper: NSView
    @objc let identifier: String
    @objc let priority: Int
    @objc var enabled = true

    init(identifier: String,
         priority: Int,
         view: NSView) {
        self.identifier = identifier
        self.priority = priority
        self._view = view
        wrapper = NSView()
        wrapper.addSubview(_view)
    }

    @objc var view: NSView {
        wrapper
    }

    var desiredWidthRange: ClosedRange<CGFloat> {
        let width = view.fittingSize.width
        return width...CGFloat.infinity
    }

    func layoutSubviews() {
        let viewHeight = _view.fittingSize.height
        _view.frame = NSRect(x: 0,
                             y: (wrapper.bounds.height - viewHeight) / 2.0,
                             width: wrapper.bounds.width,
                             height: viewHeight)
    }

    override var debugDescription: String {
        "<\(identifier): priority=\(priority) desiredWidthRange=\(desiredWidthRange)>"
    }
}

@objc
class SessionToolbarControl: SessionToolbarGenericView {
    init(identifier: String,
         priority: Int,
         control: NSControl) {
        super.init(identifier: identifier,
                   priority: priority,
                   view: control)
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        // Controls don't stretch past their natural size.
        let width = max(_view.fittingSize.width, 0)
        return width...width
    }
}

@objc
class SessionToolbarLabel: SessionToolbarGenericView {
    let textField: NSTextField
    init(identifier: String,
         priority: Int,
         textField: NSTextField) {
        self.textField = textField
        super.init(identifier: identifier,
                   priority: priority,
                   view: textField)
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        // Labels want exactly their natural width: no stretching, no
        // unnecessary shrinking beyond ellipsis.
        let width = max(_view.fittingSize.width, 0)
        return 0...width
    }
}

// A flexible spacer that takes up whatever horizontal space the layout
// algorithm gives it. Put one at each end of the toolbar to center the real
// items.
@objc(iTermSessionToolbarSpacer)
class SessionToolbarSpacer: SessionToolbarGenericView {
    private let widthRange: ClosedRange<CGFloat>

    @objc
    init(identifier: String, priority: Int, minWidth: CGFloat, maxWidth: CGFloat) {
        self.widthRange = minWidth...maxWidth
        super.init(identifier: identifier, priority: priority, view: NSView())
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        return widthRange
    }
}

@objc(iTermSessionToolbarView)
class SessionToolbarView: NSView {
    private var items: [SessionToolbarGenericView] = []
    private let layoutJoiner = IdempotentOperationJoiner.asyncJoiner(.main)
    private let backgroundView: NSVisualEffectView = {
        let v = NSVisualEffectView()
        v.material = .titlebar
        v.blendingMode = .withinWindow
        v.state = .followsWindowActiveState
        v.autoresizingMask = [.width, .height]
        return v
    }()
    // 1pt system-colored divider at the bottom. NSBox.separator picks a color
    // that adapts to the effective appearance, so this reads correctly in
    // both light and dark mode without us naming a specific color.
    private let bottomDivider: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        box.autoresizingMask = [.width, .maxYMargin]
        return box
    }()

    @objc init(items: [SessionToolbarGenericView]) {
        self.items = items
        super.init(frame: .zero)
        backgroundView.frame = bounds
        addSubview(backgroundView)
        bottomDivider.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        addSubview(bottomDivider)
        doLayout()
    }

    @objc func setItems(_ newItems: [SessionToolbarGenericView]) {
        items = newItems
        doLayout()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        doLayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        doLayout()
    }

    @objc
    func requestLayout() {
        layoutJoiner.setNeedsUpdate { [weak self] in
            self?.doLayout()
        }
    }

    private func doLayout() {
        let builder = SessionToolbarLayoutBuilder(toolbarItems: items.filter({ $0.enabled }),
                                                  availableWidth: bounds.width)
        let result = builder.build()
        var x = 0.0
        let topBottomMargin = 2.0
        let height = bounds.height - topBottomMargin * 2
        for item in result {
            item.obj.delegate = self
            var frame = item.obj.view.frame
            frame.origin.x = x
            frame.origin.y = topBottomMargin
            frame.size.width = item.width
            frame.size.height = height
            item.obj.view.frame = frame
            x += item.width + builder.spacerWidth
            item.obj.layoutSubviews()
        }
        // Keep the visual-effect background at index 0 and the divider just
        // above it, with item views on top.
        subviews = [backgroundView, bottomDivider] + result.map { $0.obj.view }
    }
}

extension SessionToolbarView: SessionToolbarItemDelegate {
    func itemDidChange(sender: SessionToolbarGenericView) {
        requestLayout()
    }
}

private class SessionToolbarLayoutBuilder {
    struct Item: CustomDebugStringConvertible {
        var obj: SessionToolbarGenericView
        var width: CGFloat

        var debugDescription: String { "\(obj.debugDescription): \(width)"}
    }
    private let items: [Item]
    private var candidate = [Item]()
    private let availableWidth: CGFloat
    let spacerWidth = 4.0
    private var availableWidthExcludingSpacing: CGFloat {
        let numSpacers = max(0, candidate.count - 1)
        return availableWidth - CGFloat(numSpacers) * spacerWidth
    }
    init(toolbarItems: [SessionToolbarGenericView],
         availableWidth: CGFloat) {
        items = toolbarItems.map { Item(obj: $0, width: $0.desiredWidthRange.lowerBound )}
        self.availableWidth = availableWidth
    }
    
    func build() -> [Item] {
        candidate = items
        while usedWidth != availableWidthExcludingSpacing, !candidate.isEmpty {
            if usedWidth < availableWidthExcludingSpacing {
                if !relax(by: availableWidthExcludingSpacing - usedWidth) {
                    break
                }
            } else {
                if !prune() {
                    break
                }
            }
        }
        return candidate
    }
    
    private var usedWidth: CGFloat {
        return candidate.reduce(0) { $0 + $1.width }
    }
    
    private func relax(by growBy: CGFloat) -> Bool {
        let growableIndices = candidate.it_indices { item in
            item.width < item.obj.desiredWidthRange.upperBound
        }.sorted { lhs, rhs in
            return candidate[lhs].obj.priority < candidate[rhs].obj.priority
        }
        guard let highestPriorityIndex = growableIndices.first else {
            return false
        }
        let highestPriority = candidate[highestPriorityIndex].obj.priority
        var siblings = growableIndices.filter { candidate[$0].obj.priority == highestPriority }
        guard !siblings.isEmpty else {
            it_fatalError("Shouldn't happen \(candidate)")
        }
        var remainingDesiredGrowth = growBy
        var lastRemainingDesiredGrowth = CGFloat.infinity
        while (!siblings.isEmpty &&
               remainingDesiredGrowth > 0 &&
               remainingDesiredGrowth < lastRemainingDesiredGrowth) {
            lastRemainingDesiredGrowth = remainingDesiredGrowth
            let portion = floor(remainingDesiredGrowth / CGFloat(siblings.count))
            for i in siblings {
                let oldWidth = candidate[i].width
                candidate[i].width = min(candidate[i].obj.desiredWidthRange.upperBound,
                                         candidate[i].width + portion)
                let thisGrowth = candidate[i].width - oldWidth
                remainingDesiredGrowth -= thisGrowth
            }
            siblings.removeAll { i in
                candidate[i].width == candidate[i].obj.desiredWidthRange.upperBound
            }
        }
        return remainingDesiredGrowth < growBy
    }
    
    private func prune() -> Bool {
        guard let priorityToPrune = candidate.lazy.map({ $0.obj.priority }).max() else {
            return false
        }
        let prunableIndices = (0..<(candidate.count)).filter {
            candidate[$0].obj.priority == priorityToPrune
        }
        guard let indexToPrune = prunableIndices.max() else {
            return false
        }
        candidate.remove(at: indexToPrune)
        return true
    }
}

extension Array {
    @inlinable func it_indices(where predicate: (Element) throws -> Bool) rethrows -> IndexSet {
        var result = IndexSet()
        for i in 0..<count {
            if try predicate(self[i]) {
                result.insert(i)
            }
        }
        return result
    }
}

@objc(iTermCCModeButtonToolbarItemDelegate)
protocol CCModeButtonToolbarItemDelegate: AnyObject {
    func toolbarButtonSelected(identifier: String, sender: CCModeButtonToolbarItem)
}

@objc(iTermCCModeButtonToolbarItem)
class CCModeButtonToolbarItem: SessionToolbarControl {
    @objc weak var buttonDelegate: CCModeButtonToolbarItemDelegate?
    // Set by the workgroup builder so the delegate can demux which
    // peer's button was tapped (each peer gets its own instance).
    @objc var ownerPeerID: String?
    private let button: NSButton
    
    @objc
    init(identifier: String,
         priority: Int,
         image: NSImage) {
        button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.refusesFirstResponder = true
        button.setButtonType(.momentaryPushIn)

        super.init(identifier: identifier, priority: priority, control: button)
        
        button.target = self
        button.action = #selector(didSelectButton(_:))
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        button.fittingSize.width...button.fittingSize.width
    }
    
    @objc
    private func didSelectButton(_ sender: Any?) {
        buttonDelegate?.toolbarButtonSelected(identifier: identifier,
                                              sender: self)
    }
}

@objc(iTermCCDiffSelectorItemDelegate)
protocol CCDiffSelectorItemDelegate: AnyObject {
    func diffDidSelect(filename: String, sender: CCDiffSelectorItem)
}

@objc(iTermCCDiffSelectorItem)
class CCDiffSelectorItem: SessionToolbarControl {
    @objc weak var diffSelectorDelegate: CCDiffSelectorItemDelegate?
    // Set by the workgroup builder so the delegate can demux which
    // peer's selector fired.
    @objc var ownerPeerID: String?
    private let button: NSPopUpButton
    // Held so the item participates in keeping the shared poller alive.
    let poller: iTermGitPoller
    // Backing list mirroring the popup's items (display order). Kept
    // separately so back/forward can navigate even if the popup's
    // selectedItem is stale (e.g. currentFile fell out of the list).
    private var orderedFiles: [String] = []
    // Last file the user navigated to via popup or back/forward —
    // the anchor that survives changes to orderedFiles. Independent
    // of `button.selectedItem`: when `currentFile` is gone from the
    // list, the popup falls back to its first item visually but we
    // still know where the user was.
    private var currentFile: String?

    @objc
    init(identifier: String,
         priority: Int,
         poller: iTermGitPoller) {
        button = NSPopUpButton()

        // Use a minimal, borderless style
        button.isBordered = true
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        self.poller = poller

        super.init(identifier: identifier, priority: priority, control: button)

        button.target = self
        button.action = #selector(selectionDidChange(_:))
        DLog("CCDiffSelectorItem init \(identifier) — menu item count \(button.menu?.items.count ?? -1), fittingSize.width=\(button.fittingSize.width)")
    }

    @objc(setFiles:)
    func set(files: [String]) {
        DLog("CCDiffSelectorItem set(files:) called with \(files.count) files: \(files)")
        orderedFiles = files
        let segmentedFiles: [[String]] = files.map { ($0 as NSString).pathComponents }
        let dirs = segmentedFiles.map { $0.dropLast() }
        let prefixLength = dirs.longestCommonPrefix.count
        let previouslySelected = button.selectedItem?.representedObject as? String
        button.menu?.removeAllItems()
        for (fullFilename, pathComponents) in zip(files, segmentedFiles) {
            let file = pathComponents.dropFirst(prefixLength).joined(separator: "/")
            button.addItem(withTitle: String(file))
            button.lastItem?.representedObject = fullFilename
        }
        // Try to preserve the user's current selection across refreshes.
        if let previouslySelected,
           let match = button.menu?.items.first(where: { ($0.representedObject as? String) == previouslySelected }) {
            button.select(match)
        }
        DLog("CCDiffSelectorItem after set(files:): menu item count \(button.menu?.items.count ?? -1), fittingSize.width=\(button.fittingSize.width)")
        delegate?.itemDidChange(sender: self)
    }

    // Pick the next/previous file in the popup's display order,
    // wrapping at the ends. Anchor is the user's last navigation
    // (`currentFile`); if that's gone from the list, we land on the
    // file that would have come immediately after it (forward) or
    // before it (backward) by string comparison — which is the order
    // the popup itself displays since git status output is sorted.
    // Falls back to the popup's visible selection so a click before
    // the user has ever picked anything still advances visibly.
    // Returns the chosen filename (also fired through
    // diffSelectorDelegate) or nil when there's nothing to pick.
    @objc
    @discardableResult
    func selectNextFile() -> String? {
        return advanceFile(forward: true)
    }

    @objc
    @discardableResult
    func selectPreviousFile() -> String? {
        return advanceFile(forward: false)
    }

    private func advanceFile(forward: Bool) -> String? {
        guard !orderedFiles.isEmpty else { return nil }
        let anchor = currentFile ?? (button.selectedItem?.representedObject as? String)
        let chosen: String
        if let anchor, let idx = orderedFiles.firstIndex(of: anchor) {
            let count = orderedFiles.count
            let next = forward
                ? (idx + 1) % count
                : (idx - 1 + count) % count
            chosen = orderedFiles[next]
        } else if let anchor {
            // Anchor is gone — pick the neighbor that would come after
            // (or before) it in the list's natural order, with wrap.
            if forward {
                chosen = orderedFiles.first(where: { $0 > anchor })
                    ?? orderedFiles[0]
            } else {
                chosen = orderedFiles.last(where: { $0 < anchor })
                    ?? orderedFiles[orderedFiles.count - 1]
            }
        } else {
            chosen = forward ? orderedFiles[0] : orderedFiles[orderedFiles.count - 1]
        }
        currentFile = chosen
        if let match = button.menu?.items.first(where: {
            ($0.representedObject as? String) == chosen
        }) {
            button.select(match)
        }
        diffSelectorDelegate?.diffDidSelect(filename: chosen, sender: self)
        return chosen
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        DLog("CCDiffSelectorItem desiredWidthRange: fittingSize.width=\(button.fittingSize.width), menu items=\(button.menu?.items.count ?? -1)")
        return 30.0...button.fittingSize.width
    }

    @objc
    private func selectionDidChange(_ sender: Any?) {
        if let filename = button.selectedItem?.representedObject as? String {
            DLog("CCDiffSelectorItem selection changed to \(filename)")
            currentFile = filename
            diffSelectorDelegate?.diffDidSelect(filename: filename,
                                                sender: self)
        } else {
            DLog("CCDiffSelectorItem selectionDidChange but no representedObject; selectedItem=\(String(describing: button.selectedItem))")
        }
    }
}

@objc(iTermCCGitSessionToolbarItem)
class CCGitSessionToolbarItem: SessionToolbarLabel {
    var ags: iTermAutoGitString!
    private let scope: iTermVariableScope
    // Held so the item participates in keeping the shared poller alive.
    let poller: iTermGitPoller

    @objc
    init(identifier: String,
         priority: Int,
         scope: iTermVariableScope,
         poller: iTermGitPoller) {
        self.scope = scope
        self.poller = poller

        let textField = NSTextField(frame: .zero)
        textField.drawsBackground = false
        textField.isBordered = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.lineBreakMode = .byTruncatingTail

        super.init(identifier: identifier, priority: priority, textField: textField)
        ags = iTermAutoGitString(
            stringMaker: iTermGitStringMaker(
                scope: scope,
                gitPoller: poller))
        ags.delegate = self
        ags.maker.delegate = self
        update()
    }

    @objc
    func pollerDidUpdate() {
        update()
    }

    private func update() {
        textField.attributedStringValue = attributedString
        DLog("CCGitSessionToolbarItem.update attributedString=\(attributedString.string)")
        delegate?.itemDidChange(sender: self)
    }
    
    private var attributedString: NSAttributedString {
        return ags.maker.attributedStringVariants().first ?? NSAttributedString()
    }
}

extension CCGitSessionToolbarItem: iTermAutoGitStringDelegate {
    func gitStringDidChange() {
        delegate?.itemDidChange(sender: self)
    }
}

extension CCGitSessionToolbarItem: iTermGitStringMakerDelegate {
    var gitFont: NSFont? {
        NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    var gitTextColor: NSColor? {
        NSColor.textColor
    }
}

