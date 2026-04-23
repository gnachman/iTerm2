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

    @objc init(items: [SessionToolbarGenericView]) {
        self.items = items
        super.init(frame: .zero)
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
        subviews = result.map { $0.obj.view }
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
    func toolbarButtonSelected(identifier: String)
}

@objc(iTermCCModeButtonToolbarItem)
class CCModeButtonToolbarItem: SessionToolbarControl {
    @objc weak var buttonDelegate: CCModeButtonToolbarItemDelegate?
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
        buttonDelegate?.toolbarButtonSelected(identifier: identifier)
    }
}

@objc(iTermCCModeSwitchSessionToolbarItemDelegate)
protocol CCModeSwitchSessionToolbarItemDelegate: AnyObject {
    func ccModeDidChange(mode: iTermCCMode)
}

@objc(iTermCCModeSwitchSessionToolbarItem)
class CCModeSwitchSessionToolbarItem: SessionToolbarControl {
    @objc weak var modeSwitchDelegate: CCModeSwitchSessionToolbarItemDelegate?
    private let segmentedControl: NSSegmentedControl

    @objc
    init(identifier: String,
         priority: Int,
         mode: iTermCCMode) {
        segmentedControl = NSSegmentedControl(
            labels: ["Claude Code", "Diff", "Code Review"],
            trackingMode: .selectOne,
            target: nil,
            action: #selector(modeChanged(_:)))
        segmentedControl.segmentStyle = .texturedRounded
        segmentedControl.selectedSegment = mode.rawValue
        super.init(identifier: identifier,
                   priority: priority,
                   control: segmentedControl)
        segmentedControl.target = self
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        // Controls don't stretch past their natural size.
        let width = max(_view.fittingSize.width, 0)
        return (30.0 * CGFloat(segmentedControl.segmentCount))...width
    }
    
    @objc
    private func modeChanged(_ sender: Any?) {
        guard let mode = iTermCCMode(rawValue: segmentedControl.indexOfSelectedItem) else {
            return
        }
        modeSwitchDelegate?.ccModeDidChange(mode: mode)
    }
}

@objc(iTermCCDiffSelectorItemDelegate)
protocol CCDiffSelectorItemDelegate: AnyObject {
    func diffDidSelect(filename: String)
}

@objc(iTermCCDiffSelectorItem)
class CCDiffSelectorItem: SessionToolbarControl {
    @objc weak var diffSelectorDelegate: CCDiffSelectorItemDelegate?
    private let button: NSPopUpButton

    @objc
    init(identifier: String,
         priority: Int) {
        button = NSPopUpButton()

        // Use a minimal, borderless style
        button.isBordered = true
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        
        super.init(identifier: identifier, priority: priority, control: button)

        button.target = self
        button.action = #selector(selectionDidChange(_:))
    }

    func set(files: [String]) {
        let prefix = String(files.longestCommonPrefix)
        button.menu?.removeAllItems()
        for file in files {
            button.addItem(withTitle: String(file.removing(prefix: prefix)))
            button.lastItem?.representedObject = file
        }
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        return 30.0...button.fittingSize.width
    }
    
    @objc
    private func selectionDidChange(_ sender: Any?) {
        if let filename = button.selectedItem?.representedObject as? String {
            diffSelectorDelegate?.diffDidSelect(filename: filename)
        }
    }
}

@objc(iTermCCGitSessionToolbarItem)
class CCGitSessionToolbarItem: SessionToolbarLabel {
    var ags: iTermAutoGitString!
    private let scope: iTermVariableScope

    @objc
    init(identifier: String,
         priority: Int,
         scope: iTermVariableScope) {
        self.scope = scope
        
        let textField = NSTextField(frame: .zero)
        textField.drawsBackground = false
        textField.isBordered = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.lineBreakMode = .byTruncatingTail

        super.init(identifier: identifier, priority: priority, textField: textField)
        let gitPoller = iTermGitPoller(cadence: 2, update: { [weak self] in
            self?.update()
        })
        gitPoller.delegate = self
        gitPoller.includeDiffStats = true
        ags = iTermAutoGitString(
            stringMaker: iTermGitStringMaker(
                scope: scope,
                gitPoller: gitPoller))
        ags.delegate = self
        ags.maker.delegate = self
        update()
    }

    private func update() {
        textField.attributedStringValue = attributedString
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

extension CCGitSessionToolbarItem: iTermGitPollerDelegate {
    func gitPollerShouldPoll(_ poller: iTermGitPoller, after lastPoll: Date?) -> Bool {
        // The toolbar only exists while Claude Code mode is active; always poll.
        return view.window != nil
    }
}
