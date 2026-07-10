//
//  ClippingsView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/26.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftyMarkdown

@objc protocol iTermClippingsViewDelegate: AnyObject {
    func clippingsViewClippings(_ view: iTermClippingsView) -> [PTYSessionClipping]
    func clippingsView(_ view: iTermClippingsView,
                       didChangeClippings clippings: [PTYSessionClipping])
    func clippingsView(_ view: iTermClippingsView,
                       pasteText text: String)
    func clippingsView(_ view: iTermClippingsView,
                       presentAddSheetWithCompletion completion: @escaping (PTYSessionClipping?) -> Void)
    func clippingsViewDidRequestClose(_ view: iTermClippingsView)

    // History/archive support. The view layer asks the session-side adapter
    // for these so the same model backs the gutter UI and external callers
    // (it2 archive-clippings, archive_clipping built-in function).
    func clippingsViewDidRequestArchive(_ view: iTermClippingsView)
    func clippingsViewArchiveCount(_ view: iTermClippingsView) -> Int
    func clippingsViewSelectedHistoryIndex(_ view: iTermClippingsView) -> Int
    func clippingsView(_ view: iTermClippingsView,
                       setSelectedHistoryIndex index: Int)
}

private let kClippingsControlsTopPadding: CGFloat = 4
private let kClippingsControlsBottomPadding: CGFloat = 6
private let kClippingsPasteboardType = NSPasteboard.PasteboardType("com.iterm2.clipping.row")
private let kClippingsCellPadX: CGFloat = 10
private let kClippingsCellPadY: CGFloat = 6
private let kClippingsCellTitleHeight: CGFloat = 18
private let kClippingsCellTitleDetailGap: CGFloat = 2
private let kClippingsCellMaxDetailHeight: CGFloat = 100
private let kClippingsCellTitleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
private let kClippingsCellDetailFont = NSFont.systemFont(ofSize: 11)

@objc(iTermClippingsView)
class iTermClippingsView: NSView {
    @objc static let fixedWidth: CGFloat = 300

    @objc weak var delegate: iTermClippingsViewDelegate? {
        didSet { reload() }
    }

    private let backgroundView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let tableView = ClippingsTableView()
    private let editSegmentedControl = NSSegmentedControl()
    private let actionSegmentedControl = NSSegmentedControl()
    private let historySegmentedControl = NSSegmentedControl()
    private let historyStatusLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var previewPopover: NSPopover?
    private var previewRow: Int?

    @objc(initWithDelegate:)
    init(delegate: iTermClippingsViewDelegate?) {
        self.delegate = delegate
        super.init(frame: NSRect(x: 0, y: 0, width: Self.fixedWidth, height: 200))
        setup()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true

        backgroundView.material = .sidebar
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .followsWindowActiveState
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.frame = bounds
        addSubview(backgroundView)

        tableView.headerView = nil
        tableView.allowsMultipleSelection = true
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.deletePressedHandler = { [weak self] in self?.deleteSelected() }
        tableView.spacePressedHandler = { [weak self] in self?.toggleQuickLook() }
        tableView.registerForDraggedTypes([kClippingsPasteboardType])
        tableView.draggingDestinationFeedbackStyle = .gap

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipping"))
        column.width = Self.fixedWidth
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        editSegmentedControl.segmentCount = 3
        editSegmentedControl.segmentStyle = .smallSquare
        editSegmentedControl.trackingMode = .momentary
        if let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add clipping") {
            editSegmentedControl.setImage(plus, forSegment: 0)
        }
        if let minus = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove clipping") {
            editSegmentedControl.setImage(minus, forSegment: 1)
        }
        if let archive = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Archive clippings") {
            editSegmentedControl.setImage(archive, forSegment: 2)
        }
        editSegmentedControl.setToolTip("Add clipping", forSegment: 0)
        editSegmentedControl.setToolTip("Remove selected clipping", forSegment: 1)
        editSegmentedControl.setToolTip("Archive all clippings", forSegment: 2)
        editSegmentedControl.setEnabled(false, forSegment: 1)
        editSegmentedControl.setEnabled(false, forSegment: 2)
        editSegmentedControl.target = self
        editSegmentedControl.action = #selector(editSegmentClicked(_:))
        editSegmentedControl.autoresizingMask = [.maxXMargin, .maxYMargin]
        addSubview(editSegmentedControl)

        actionSegmentedControl.segmentCount = 2
        actionSegmentedControl.segmentStyle = .smallSquare
        actionSegmentedControl.trackingMode = .momentary
        if let send = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Send clipping") {
            actionSegmentedControl.setImage(send, forSegment: 0)
        }
        if let copy = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy clipping") {
            actionSegmentedControl.setImage(copy, forSegment: 1)
        }
        actionSegmentedControl.setToolTip("Send selected to terminal", forSegment: 0)
        actionSegmentedControl.setToolTip("Copy selected to pasteboard", forSegment: 1)
        actionSegmentedControl.setEnabled(false, forSegment: 0)
        actionSegmentedControl.setEnabled(false, forSegment: 1)
        actionSegmentedControl.target = self
        actionSegmentedControl.action = #selector(actionSegmentClicked(_:))
        actionSegmentedControl.autoresizingMask = [.maxXMargin, .maxYMargin]
        addSubview(actionSegmentedControl)

        historySegmentedControl.segmentCount = 2
        historySegmentedControl.segmentStyle = .smallSquare
        historySegmentedControl.trackingMode = .momentary
        if let back = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous archived clippings") {
            historySegmentedControl.setImage(back, forSegment: 0)
        }
        if let forward = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next archived clippings") {
            historySegmentedControl.setImage(forward, forSegment: 1)
        }
        historySegmentedControl.setToolTip("Show previous archived clippings", forSegment: 0)
        historySegmentedControl.setToolTip("Show next archived clippings", forSegment: 1)
        historySegmentedControl.setEnabled(false, forSegment: 0)
        historySegmentedControl.setEnabled(false, forSegment: 1)
        historySegmentedControl.target = self
        historySegmentedControl.action = #selector(historySegmentClicked(_:))
        historySegmentedControl.autoresizingMask = [.maxXMargin, .maxYMargin]
        addSubview(historySegmentedControl)

        historyStatusLabel.font = NSFont.systemFont(ofSize: 10)
        historyStatusLabel.textColor = .secondaryLabelColor
        historyStatusLabel.alignment = .right
        historyStatusLabel.lineBreakMode = .byTruncatingTail
        historyStatusLabel.maximumNumberOfLines = 1
        historyStatusLabel.isHidden = true
        historyStatusLabel.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(historyStatusLabel)

        if let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Hide clippings") {
            closeButton.image = xmark
        }
        closeButton.bezelStyle = .smallSquare
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))
        closeButton.toolTip = "Hide clippings"
        closeButton.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(closeButton)

        layoutFrames()
    }

    override func layout() {
        super.layout()
        layoutFrames()
    }

    private func layoutFrames() {
        editSegmentedControl.sizeToFit()
        actionSegmentedControl.sizeToFit()
        historySegmentedControl.sizeToFit()
        let editSize = editSegmentedControl.frame.size
        let actionSize = actionSegmentedControl.frame.size
        let historySize = historySegmentedControl.frame.size
        let stripHeight = editSize.height + kClippingsControlsTopPadding + kClippingsControlsBottomPadding
        scrollView.frame = NSRect(x: 0,
                                  y: stripHeight,
                                  width: bounds.width,
                                  height: max(0, bounds.height - stripHeight))
        editSegmentedControl.frame = NSRect(x: 6,
                                            y: kClippingsControlsBottomPadding,
                                            width: editSize.width,
                                            height: editSize.height)
        actionSegmentedControl.frame = NSRect(x: 6 + editSize.width + 8,
                                              y: kClippingsControlsBottomPadding,
                                              width: actionSize.width,
                                              height: actionSize.height)
        historySegmentedControl.frame = NSRect(x: 6 + editSize.width + 8 + actionSize.width + 8,
                                               y: kClippingsControlsBottomPadding,
                                               width: historySize.width,
                                               height: historySize.height)

        closeButton.sizeToFit()
        let closeSize = closeButton.frame.size
        let closeY = kClippingsControlsBottomPadding + (editSize.height - closeSize.height) / 2
        closeButton.frame = NSRect(x: bounds.width - closeSize.width - 6,
                                   y: closeY,
                                   width: closeSize.width,
                                   height: closeSize.height)

        let labelLeft = historySegmentedControl.frame.maxX + 6
        let labelRight = closeButton.frame.minX - 4
        let labelWidth = max(0, labelRight - labelLeft)
        let labelHeight: CGFloat = 14
        let labelY = kClippingsControlsBottomPadding + (editSize.height - labelHeight) / 2
        historyStatusLabel.frame = NSRect(x: labelLeft,
                                          y: labelY,
                                          width: labelWidth,
                                          height: labelHeight)
    }

    @objc func reload() {
        tableView.reloadData()
        updateSelectionDependentSegments()
    }

    private var historyIndex: Int {
        return delegate?.clippingsViewSelectedHistoryIndex(self) ?? -1
    }

    private var archiveCount: Int {
        return delegate?.clippingsViewArchiveCount(self) ?? 0
    }

    private var isViewingLive: Bool {
        let idx = historyIndex
        return idx < 0 || idx >= archiveCount
    }

    private func updateSelectionDependentSegments() {
        let hasSelection = tableView.selectedRowIndexes.count > 0
        let viewingLive = isViewingLive
        let viewedCount = currentClippings().count

        // Add/remove only act on the live list.
        editSegmentedControl.setEnabled(viewingLive, forSegment: 0)
        editSegmentedControl.setEnabled(viewingLive && hasSelection, forSegment: 1)
        // Archive only makes sense when viewing a non-empty live list — once
        // an entry is in the archive there's nothing to do, and the model's
        // archiveClippings() is a no-op anyway.
        editSegmentedControl.setEnabled(viewingLive && viewedCount > 0, forSegment: 2)

        actionSegmentedControl.setEnabled(hasSelection, forSegment: 0)
        actionSegmentedControl.setEnabled(hasSelection, forSegment: 1)

        let total = archiveCount
        let idx = viewingLive ? total : historyIndex
        historySegmentedControl.setEnabled(idx > 0, forSegment: 0)
        historySegmentedControl.setEnabled(idx < total, forSegment: 1)

        if !viewingLive {
            historyStatusLabel.stringValue = "\(historyIndex + 1)/\(total)"
            historyStatusLabel.toolTip = "Viewing archived clippings (\(historyIndex + 1) of \(total))"
            historyStatusLabel.isHidden = false
        } else {
            historyStatusLabel.stringValue = ""
            historyStatusLabel.toolTip = nil
            historyStatusLabel.isHidden = true
        }
    }

    private func selectedClippings() -> [PTYSessionClipping] {
        let items = currentClippings()
        return tableView.selectedRowIndexes.compactMap { i -> PTYSessionClipping? in
            i < items.count ? items[i] : nil
        }
    }

    private func joinedSelectedDetails() -> String? {
        let selected = selectedClippings()
        guard !selected.isEmpty else { return nil }
        return selected.joinedForSending()
    }

    private func currentClippings() -> [PTYSessionClipping] {
        return delegate?.clippingsViewClippings(self) ?? []
    }

    @objc private func doubleClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        let items = currentClippings()
        guard row < items.count else { return }
        delegate?.clippingsView(self, pasteText: items[row].detail)
    }

    @objc private func editSegmentClicked(_ sender: Any?) {
        switch editSegmentedControl.selectedSegment {
        case 0:
            promptForNew()
        case 1:
            deleteSelected()
        case 2:
            requestArchive()
        default:
            break
        }
    }

    @objc private func actionSegmentClicked(_ sender: Any?) {
        switch actionSegmentedControl.selectedSegment {
        case 0:
            sendSelected()
        case 1:
            copySelected()
        default:
            break
        }
    }

    @objc private func historySegmentClicked(_ sender: Any?) {
        let total = archiveCount
        let current = isViewingLive ? total : historyIndex
        let target: Int
        switch historySegmentedControl.selectedSegment {
        case 0:
            target = max(0, current - 1)
        case 1:
            target = min(total, current + 1)
        default:
            return
        }
        let nextIndex = target >= total ? -1 : target
        // Selection is per-row in the previously displayed list and is
        // meaningless against a different list. Drop it so the action
        // segments and any open preview reset.
        tableView.deselectAll(nil)
        previewPopover?.close()
        delegate?.clippingsView(self, setSelectedHistoryIndex: nextIndex)
    }

    private func requestArchive() {
        previewPopover?.close()
        delegate?.clippingsViewDidRequestArchive(self)
    }

    private func sendSelected() {
        guard let text = joinedSelectedDetails() else { return }
        delegate?.clippingsView(self, pasteText: text)
    }

    private func copySelected() {
        guard let text = joinedSelectedDetails() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func closeClicked(_ sender: Any?) {
        delegate?.clippingsViewDidRequestClose(self)
    }

    private func promptForNew() {
        delegate?.clippingsView(self, presentAddSheetWithCompletion: { [weak self] newClipping in
            guard let self, let newClipping else { return }
            var items = self.currentClippings()
            items.append(newClipping)
            self.delegate?.clippingsView(self, didChangeClippings: items)
            self.reload()
        })
    }

    private func deleteSelected() {
        let selected = tableView.selectedRowIndexes
        guard selected.count > 0 else { return }
        var items = currentClippings()
        for index in selected.reversed() where index < items.count {
            items.remove(at: index)
        }
        delegate?.clippingsView(self, didChangeClippings: items)
        reload()
    }

    fileprivate func toggleQuickLook(forRow specific: Int? = nil) {
        let openRow = previewRow
        if let popover = previewPopover {
            popover.close()
            previewPopover = nil
            previewRow = nil
            // Spacebar always toggles closed; an explicit button click on the
            // same row also closes. A click on a different row falls through
            // to switch the popover to that row.
            if specific == nil || specific == openRow {
                return
            }
        }
        let row: Int
        if let specific {
            row = specific
        } else {
            let selected = tableView.selectedRowIndexes
            guard selected.count == 1, let only = selected.first else { return }
            row = only
        }
        let items = currentClippings()
        guard row < items.count else { return }

        tableView.scrollRowToVisible(row)
        guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: true) else { return }
        let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ClippingsCellView
        let anchor: NSView = cell?.popoverAnchorView ?? rowView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let vc = ClippingsPreviewViewController(clipping: items[row])
        vc.onDismiss = { [weak popover] in popover?.close() }
        popover.contentViewController = vc
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minX)
        previewPopover = popover
        previewRow = row
    }
}

extension iTermClippingsView: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        if (notification.object as? NSPopover) === previewPopover {
            previewPopover = nil
            previewRow = nil
        }
    }
}

extension iTermClippingsView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return currentClippings().count
    }

    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        // Reordering the archived snapshot wouldn't write through anywhere
        // meaningful; refuse the drag at the source so the view stays
        // visibly read-only.
        guard isViewingLive else { return nil }
        let item = NSPasteboardItem()
        item.setPropertyList([row], forType: kClippingsPasteboardType)
        return item
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if (info.draggingSource as? NSTableView) !== tableView {
            return []
        }
        if !isViewingLive {
            return []
        }
        if dropOperation == .above {
            return .move
        }
        return []
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        var draggedRows = [Int]()
        info.enumerateDraggingItems(options: [],
                                    for: tableView,
                                    classes: [NSPasteboardItem.self],
                                    searchOptions: [:]) { item, _, _ in
            guard let pbItem = item.item as? NSPasteboardItem,
                  let rows = pbItem.propertyList(forType: kClippingsPasteboardType) as? [Int] else {
                return
            }
            draggedRows.append(contentsOf: rows)
        }
        guard !draggedRows.isEmpty else { return false }

        var items = currentClippings()
        let moving = draggedRows.compactMap { i -> PTYSessionClipping? in
            i < items.count ? items[i] : nil
        }
        for i in draggedRows.sorted(by: >) where i < items.count {
            items.remove(at: i)
        }
        var insertIndex = row
        for i in draggedRows where i < row {
            insertIndex -= 1
        }
        insertIndex = max(0, min(insertIndex, items.count))
        items.insert(contentsOf: moving, at: insertIndex)

        delegate?.clippingsView(self, didChangeClippings: items)
        reload()
        return true
    }
}

extension iTermClippingsView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("clippingCell")
        let cell: ClippingsCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? ClippingsCellView {
            cell = reused
        } else {
            cell = ClippingsCellView(frame: NSRect(x: 0, y: 0, width: Self.fixedWidth, height: 60))
            cell.identifier = identifier
        }
        let items = currentClippings()
        if row < items.count {
            cell.configure(with: items[row]) { [weak self, weak cell] in
                guard let self, let cell else { return }
                let liveRow = tableView.row(for: cell)
                guard liveRow >= 0 else { return }
                self.toggleQuickLook(forRow: liveRow)
            }
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let items = currentClippings()
        guard row < items.count else { return 30 }
        return ClippingsCellView.height(for: items[row], width: Self.fixedWidth)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionDependentSegments()
    }
}

private let kClippingsPreviewButtonSize: CGFloat = 18
private let kClippingsPreviewButtonRightPad: CGFloat = 6
private let kClippingsPreviewButtonTitleGap: CGFloat = 4

private class ClippingsCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let previewButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updatePreviewButtonVisibility() }
    }
    private var isSelected = false {
        didSet { updatePreviewButtonVisibility() }
    }
    private var onPreview: (() -> Void)?

    var popoverAnchorView: NSView { previewButton }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        titleLabel.font = kClippingsCellTitleFont
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.textColor = .labelColor
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(titleLabel)

        detailLabel.font = kClippingsCellDetailFont
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 0
        detailLabel.cell?.wraps = true
        detailLabel.cell?.usesSingleLineMode = false
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.drawsBackground = false
        detailLabel.isBordered = false
        detailLabel.isEditable = false
        detailLabel.isSelectable = false
        detailLabel.autoresizingMask = [.width, .height]
        addSubview(detailLabel)

        if let glass = NSImage(systemSymbolName: "magnifyingglass",
                               accessibilityDescription: "Preview clipping") {
            previewButton.image = glass
        }
        previewButton.bezelStyle = .smallSquare
        previewButton.isBordered = false
        previewButton.imagePosition = .imageOnly
        previewButton.contentTintColor = .secondaryLabelColor
        previewButton.toolTip = "Preview (Space)"
        previewButton.target = self
        previewButton.action = #selector(previewButtonClicked(_:))
        previewButton.autoresizingMask = [.minXMargin, .minYMargin]
        previewButton.isHidden = true
        addSubview(previewButton)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited,
                                            .activeInKeyWindow,
                                            .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            isSelected = (backgroundStyle != .normal)
        }
    }

    private func updatePreviewButtonVisibility() {
        previewButton.isHidden = !(isHovered || isSelected)
    }

    @objc private func previewButtonClicked(_ sender: Any?) {
        onPreview?()
    }

    override func layout() {
        super.layout()
        let buttonReserve = kClippingsPreviewButtonSize
            + kClippingsPreviewButtonRightPad
            + kClippingsPreviewButtonTitleGap
        let titleWidth = max(0, bounds.width - kClippingsCellPadX - buttonReserve)
        let detailWidth = max(0, bounds.width - kClippingsCellPadX * 2)
        titleLabel.frame = NSRect(x: kClippingsCellPadX,
                                  y: bounds.height - kClippingsCellTitleHeight - kClippingsCellPadY,
                                  width: titleWidth,
                                  height: kClippingsCellTitleHeight)
        let detailHeight = max(0, bounds.height - kClippingsCellTitleHeight
                                  - kClippingsCellPadY * 2
                                  - kClippingsCellTitleDetailGap)
        detailLabel.frame = NSRect(x: kClippingsCellPadX,
                                   y: kClippingsCellPadY,
                                   width: detailWidth,
                                   height: detailHeight)
        let buttonY = bounds.height
            - kClippingsCellPadY
            - kClippingsCellTitleHeight
            + (kClippingsCellTitleHeight - kClippingsPreviewButtonSize) / 2
        previewButton.frame = NSRect(x: bounds.width - kClippingsPreviewButtonRightPad - kClippingsPreviewButtonSize,
                                     y: buttonY,
                                     width: kClippingsPreviewButtonSize,
                                     height: kClippingsPreviewButtonSize)
    }

    func configure(with clipping: PTYSessionClipping, onPreview: (() -> Void)?) {
        self.onPreview = onPreview
        // Cell reuse: previous cursor-tracking state is meaningless for the new
        // row. The tracking area will fire mouseEntered if the cursor is still
        // over us.
        isHovered = false
        titleLabel.stringValue = clipping.title
        if clipping.detail.isEmpty {
            detailLabel.stringValue = ""
        } else {
            detailLabel.attributedStringValue = Self.attributedDetail(for: clipping.detail)
        }
    }

    fileprivate static func attributedMarkdown(_ markdown: String,
                                                baseSize: CGFloat,
                                                color: NSColor) -> NSAttributedString {
        let md = SwiftyMarkdown(string: markdown)
        if let fixedPitch = NSFont.userFixedPitchFont(ofSize: baseSize)?.fontName {
            md.code.fontName = fixedPitch
        }
        md.setFontSizeForAllStyles(with: baseSize)
        md.h1.fontSize = max(4, round(baseSize * 1.5))
        md.h2.fontSize = max(4, round(baseSize * 1.3))
        md.h3.fontSize = max(4, round(baseSize * 1.15))
        md.h4.fontSize = max(4, round(baseSize * 1.0))
        md.h5.fontSize = max(4, round(baseSize * 0.9))
        md.h6.fontSize = max(4, round(baseSize * 0.85))
        md.setFontColorForAllStyles(with: color)
        return md.attributedString().postprocessedSwiftyMarkdownAttributedString()
    }

    // SwiftyMarkdown parsing is non-trivial and detailHeight() is called once
    // per visible row on every layout pass, so cache the result keyed on the
    // markdown string. The cached NSColor remains dynamic across appearance
    // changes because NSColor is resolved at draw time.
    private static let detailCache = NSCache<NSString, NSAttributedString>()

    fileprivate static func attributedDetail(for markdown: String) -> NSAttributedString {
        let key = markdown as NSString
        if let cached = detailCache.object(forKey: key) {
            return cached
        }
        let attributed = attributedMarkdown(markdown,
                                            baseSize: kClippingsCellDetailFont.pointSize,
                                            color: .secondaryLabelColor)
        detailCache.setObject(attributed, forKey: key)
        return attributed
    }

    static func height(for clipping: PTYSessionClipping, width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - kClippingsCellPadX * 2)
        let detailH = detailHeight(for: clipping.detail, width: textWidth)
        return kClippingsCellPadY
            + kClippingsCellTitleHeight
            + kClippingsCellTitleDetailGap
            + detailH
            + kClippingsCellPadY
    }

    // Configured exactly like the rendered detailLabel so that
    // cellSize(forBounds:) returns the height NSTextField will actually use
    // when laying out, including its internal line spacing.
    private static let detailMeasuringLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.lineBreakMode = .byTruncatingTail
        l.maximumNumberOfLines = 0
        l.cell?.wraps = true
        l.cell?.usesSingleLineMode = false
        return l
    }()

    private static func detailHeight(for string: String, width: CGFloat) -> CGFloat {
        if string.isEmpty {
            return 0
        }
        detailMeasuringLabel.attributedStringValue = attributedDetail(for: string)
        guard let cell = detailMeasuringLabel.cell else { return 0 }
        let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        let natural = ceil(cell.cellSize(forBounds: bounds).height)
        return min(natural, kClippingsCellMaxDetailHeight)
    }
}

private class ClippingsTableView: NSTableView {
    var deletePressedHandler: (() -> Void)?
    var spacePressedHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let key = Int(event.keyCode)
        if key == kVK_Delete || key == kVK_ForwardDelete {
            deletePressedHandler?()
            return
        }
        if key == kVK_Space {
            spacePressedHandler?()
            return
        }
        super.keyDown(with: event)
    }
}

private let kClippingsPreviewWidth: CGFloat = 700
private let kClippingsPreviewMaxHeight: CGFloat = 480
private let kClippingsPreviewPad: CGFloat = 12
private let kClippingsPreviewTitleHeight: CGFloat = 22
private let kClippingsPreviewTitleDetailGap: CGFloat = 6
private let kClippingsPreviewMinDetailHeight: CGFloat = 16

private class ClippingsPreviewViewController: NSViewController {
    private let clipping: PTYSessionClipping
    var onDismiss: (() -> Void)?
    private var keyMonitor: Any?

    init(clipping: PTYSessionClipping) {
        self.clipping = clipping
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let width = kClippingsPreviewWidth
        let textWidth = width - kClippingsPreviewPad * 2

        let attributed: NSAttributedString
        if clipping.detail.isEmpty {
            attributed = NSAttributedString(string: "")
        } else {
            attributed = ClippingsCellView.attributedMarkdown(
                clipping.detail,
                baseSize: NSFont.systemFontSize,
                color: .labelColor)
        }
        let naturalTextHeight = ceil(attributed.boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        let chrome = kClippingsPreviewPad * 2 + kClippingsPreviewTitleHeight + kClippingsPreviewTitleDetailGap
        let availableForText = kClippingsPreviewMaxHeight - chrome
        let textHeight = min(max(naturalTextHeight, kClippingsPreviewMinDetailHeight), availableForText)
        let totalHeight = chrome + textHeight

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))

        let titleLabel = NSTextField(labelWithString: clipping.title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.frame = NSRect(x: kClippingsPreviewPad,
                                  y: totalHeight - kClippingsPreviewPad - kClippingsPreviewTitleHeight,
                                  width: textWidth,
                                  height: kClippingsPreviewTitleHeight)
        titleLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titleLabel)

        let scrollView = NSScrollView(frame: NSRect(x: kClippingsPreviewPad,
                                                    y: kClippingsPreviewPad,
                                                    width: textWidth,
                                                    height: textHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: textHeight))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: textWidth,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textStorage?.setAttributedString(attributed)

        scrollView.documentView = textView
        container.addSubview(scrollView)

        view = container
        preferredContentSize = NSSize(width: width, height: totalHeight)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // A local key monitor catches space/escape regardless of which subview
        // (text view, scroll view) holds first responder while the popover is up.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let key = Int(event.keyCode)
            if key == kVK_Space || key == kVK_Escape {
                self.onDismiss?()
                return nil
            }
            return event
        }
    }

    override func viewWillDisappear() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        super.viewWillDisappear()
    }
}
