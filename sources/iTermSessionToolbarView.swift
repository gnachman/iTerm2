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

    // Symmetric horizontal inset so item content never butts up
    // against the session edge. Pure visual breathing room — the
    // layout builder sees a smaller availableWidth and items are
    // pushed in from the leading edge by the same amount.
    private static let horizontalInset = 4.0

    private func doLayout() {
        let inset = Self.horizontalInset
        let builder = SessionToolbarLayoutBuilder(toolbarItems: items.filter({ $0.enabled }),
                                                  availableWidth: max(0, bounds.width - inset * 2))
        let result = builder.build()
        var x = inset
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
    // The user picked the "All Files" row at the top of the popup —
    // intent is to run the workgroup's main command, NOT the
    // per-file command. Each implementation routes accordingly.
    func diffDidSelectAllFiles(sender: CCDiffSelectorItem)
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
        // The Staged/Unstaged/Untracked rows are header-only and set
        // isEnabled=false on themselves. NSMenu's default
        // auto-enable logic asks the responder chain whether each
        // item is enabled, ignoring isEnabled when the action is nil
        // and a target chain exists, so we have to opt out so our
        // explicit values stick.
        button.menu?.autoenablesItems = false
        DLog("CCDiffSelectorItem init \(identifier) — menu item count \(button.menu?.items.count ?? -1), fittingSize.width=\(button.fittingSize.width)")
    }

    // Non-path representedObject for the "All Files" row, distinct
    // from any path string the file list could carry.
    private static let allFilesMarker = "\u{0}__cc_diff_selector_all_files__"

    @objc(setFileStatuses:)
    func set(fileStatuses statuses: [iTermGitFileStatus]) {
        DLog("CCDiffSelectorItem set(fileStatuses:) called with \(statuses.count) entries")
        // Group like git status displays them. A file modified after
        // staging shows up in BOTH staged and unstaged groups (that's
        // how `git status` renders the MM case), so we filter the same
        // status list three different ways instead of partitioning.
        let staged = statuses.filter { $0.indexStatus != .none }
        let unstaged = statuses.filter {
            $0.workdirStatus != .none && $0.workdirStatus != .untracked
        }
        let untracked = statuses.filter { $0.workdirStatus == .untracked }

        // Use every reported file's path for prefix shortening, even
        // when groups overlap — picking a smaller subset would let the
        // shortened display vary based on which group a file lives in.
        let allPaths = statuses.map { $0.path }
        let segmentedAll = allPaths.map { ($0 as NSString).pathComponents }
        let prefixLength = segmentedAll.map { $0.dropLast() }
            .longestCommonPrefix.count

        let previouslySelected = button.selectedItem?.representedObject as? String
        button.menu?.removeAllItems()

        let allFilesItem = NSMenuItem(title: "All Files",
                                      action: nil,
                                      keyEquivalent: "")
        allFilesItem.representedObject = Self.allFilesMarker
        button.menu?.addItem(allFilesItem)

        var ordered: [String] = []
        addGroup(title: "Staged",
                 entries: staged,
                 prefixLength: prefixLength,
                 column: \.indexStatus,
                 letterColor: .systemGreen,
                 ordered: &ordered)
        addGroup(title: "Unstaged",
                 entries: unstaged,
                 prefixLength: prefixLength,
                 column: \.workdirStatus,
                 letterColor: .systemRed,
                 ordered: &ordered)
        addGroup(title: "Untracked",
                 entries: untracked,
                 prefixLength: prefixLength,
                 column: \.workdirStatus,
                 letterColor: .systemRed,
                 ordered: &ordered)
        // Dedupe by path (preserving first-occurrence order). A file
        // with both index and workdir changes (MM) lands in both the
        // Staged and Unstaged sections by design, but back/forward
        // navigates by anchor path: with two rows for one path,
        // firstIndex(of:) always returns the lower one and Next would
        // stick on it forever. Visiting the file once in the
        // navigation order is the right semantic.
        var seen = Set<String>()
        orderedFiles = ordered.filter { seen.insert($0).inserted }

        if let previouslySelected,
           let match = button.menu?.items.first(where: {
               ($0.representedObject as? String) == previouslySelected
           }) {
            button.select(match)
        } else {
            // Falls through here on first build and whenever the
            // previously visible row vanished (e.g. user staged a
            // file). All Files is a sensible default — they didn't
            // pick anything specific, so don't pretend they did.
            button.select(allFilesItem)
        }
        DLog("CCDiffSelectorItem after set(fileStatuses:): menu item count \(button.menu?.items.count ?? -1)")
        delegate?.itemDidChange(sender: self)
    }

    // Adds a separator + disabled header + one menu row per file in
    // `entries`. No-op when entries is empty (keeps the menu free of
    // empty-section separators). `letterColor` tints the porcelain
    // letter only — green for staged, red for unstaged/untracked,
    // matching `git status` defaults.
    private func addGroup(title: String,
                          entries: [iTermGitFileStatus],
                          prefixLength: Int,
                          column: KeyPath<iTermGitFileStatus, iTermGitFileChangeKind>,
                          letterColor: NSColor,
                          ordered: inout [String]) {
        guard !entries.isEmpty else { return }
        button.menu?.addItem(.separator())
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        button.menu?.addItem(header)
        let menuFont = NSFont.menuFont(ofSize: 0)
        for entry in entries {
            let kind = entry[keyPath: column]
            let letter = Self.letter(for: kind)
            let segments = (entry.path as NSString).pathComponents
            let shortened = segments.dropFirst(prefixLength).joined(separator: "/")
            // Two spaces between letter and path mirrors `git status
            // --short`. NSMenuItem strips leading whitespace, so the
            // letter has to come first; aligning visually with a
            // padded letter (e.g. "M ") is enough.
            let title = "\(letter)  \(shortened)"
            let attributed = NSMutableAttributedString(
                string: title,
                attributes: [.font: menuFont])
            // Color just the leading porcelain letter — keeps the
            // path readable in the system text color while making
            // the change kind pop at a glance. `letter` is a single
            // grapheme produced by `letter(for:)`, so range starts
            // at 0 with length matching `letter.utf16.count`.
            attributed.addAttribute(.foregroundColor,
                                    value: letterColor,
                                    range: NSRange(location: 0,
                                                   length: letter.utf16.count))
            let row = NSMenuItem(title: title,
                                 action: nil,
                                 keyEquivalent: "")
            row.attributedTitle = attributed
            row.representedObject = entry.path
            button.menu?.addItem(row)
            ordered.append(entry.path)
        }
    }

    // Letter shown next to a file in its group's section. Mirrors git
    // status --porcelain so the meaning is familiar (M, A, D, R, T,
    // ?, U for conflicts). Falls back to a space when the kind is
    // .none — the column we picked the file under shouldn't ever be
    // .none, but defensive default avoids a confusing empty cell if
    // it is.
    private static func letter(for kind: iTermGitFileChangeKind) -> String {
        switch kind {
        case .modified:    return "M"
        case .added:       return "A"
        case .deleted:     return "D"
        case .renamed:     return "R"
        case .typeChange:  return "T"
        case .untracked:   return "?"
        case .conflicted:  return "U"
        case .none:        return " "
        @unknown default:  return " "
        }
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
        // If the popup is on All Files (or anything that isn't a path
        // entry) treat the anchor as missing; the fallback below picks
        // the first/last file instead of trying to find a neighbor of
        // the marker string.
        let visible = button.selectedItem?.representedObject as? String
        let visibleAnchor = (visible != Self.allFilesMarker) ? visible : nil
        let anchor = currentFile ?? visibleAnchor
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
        guard let value = button.selectedItem?.representedObject as? String else {
            DLog("CCDiffSelectorItem selectionDidChange but no representedObject; selectedItem=\(String(describing: button.selectedItem))")
            return
        }
        if value == Self.allFilesMarker {
            DLog("CCDiffSelectorItem selection changed to All Files")
            // Clear the per-file anchor so a subsequent forward press
            // starts at the first file rather than wrapping past the
            // file the user happened to be on before picking All Files.
            currentFile = nil
            diffSelectorDelegate?.diffDidSelectAllFiles(sender: self)
            return
        }
        DLog("CCDiffSelectorItem selection changed to \(value)")
        currentFile = value
        diffSelectorDelegate?.diffDidSelect(filename: value, sender: self)
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

