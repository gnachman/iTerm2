//
//  ClippingsView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/26.
//

import AppKit
import Carbon.HIToolbox
import Foundation

@objc protocol iTermClippingsViewDelegate: AnyObject {
    func clippingsViewClippings(_ view: iTermClippingsView) -> [PTYSessionClipping]
    func clippingsView(_ view: iTermClippingsView,
                       didChangeClippings clippings: [PTYSessionClipping])
    func clippingsView(_ view: iTermClippingsView,
                       pasteText text: String)
    func clippingsView(_ view: iTermClippingsView,
                       presentAddSheetWithCompletion completion: @escaping (PTYSessionClipping?) -> Void)
    func clippingsViewDidRequestClose(_ view: iTermClippingsView)
}

private let kClippingsControlsTopPadding: CGFloat = 4
private let kClippingsControlsBottomPadding: CGFloat = 6
private let kClippingsPasteboardType = NSPasteboard.PasteboardType("com.iterm2.clipping.row")
private let kClippingsCellPadX: CGFloat = 10
private let kClippingsCellPadY: CGFloat = 6
private let kClippingsCellTitleHeight: CGFloat = 18
private let kClippingsCellTitleDetailGap: CGFloat = 2
private let kClippingsCellMaxDetailLines = 3
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
    private let closeButton = NSButton()

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

        editSegmentedControl.segmentCount = 2
        editSegmentedControl.segmentStyle = .smallSquare
        editSegmentedControl.trackingMode = .momentary
        if let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add clipping") {
            editSegmentedControl.setImage(plus, forSegment: 0)
        }
        if let minus = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove clipping") {
            editSegmentedControl.setImage(minus, forSegment: 1)
        }
        editSegmentedControl.setEnabled(false, forSegment: 1)
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
        actionSegmentedControl.setEnabled(false, forSegment: 0)
        actionSegmentedControl.setEnabled(false, forSegment: 1)
        actionSegmentedControl.target = self
        actionSegmentedControl.action = #selector(actionSegmentClicked(_:))
        actionSegmentedControl.autoresizingMask = [.maxXMargin, .maxYMargin]
        addSubview(actionSegmentedControl)

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
        let editSize = editSegmentedControl.frame.size
        let actionSize = actionSegmentedControl.frame.size
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

        closeButton.sizeToFit()
        let closeSize = closeButton.frame.size
        let closeY = kClippingsControlsBottomPadding + (editSize.height - closeSize.height) / 2
        closeButton.frame = NSRect(x: bounds.width - closeSize.width - 6,
                                   y: closeY,
                                   width: closeSize.width,
                                   height: closeSize.height)
    }

    @objc func reload() {
        tableView.reloadData()
        updateSelectionDependentSegments()
    }

    private func updateSelectionDependentSegments() {
        let hasSelection = tableView.selectedRowIndexes.count > 0
        editSegmentedControl.setEnabled(hasSelection, forSegment: 1)
        actionSegmentedControl.setEnabled(hasSelection, forSegment: 0)
        actionSegmentedControl.setEnabled(hasSelection, forSegment: 1)
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
        return selected.map { $0.detail }.joined(separator: "\n")
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
}

extension iTermClippingsView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return currentClippings().count
    }

    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
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
            cell.configure(with: items[row])
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

private class ClippingsCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

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
        detailLabel.maximumNumberOfLines = kClippingsCellMaxDetailLines
        detailLabel.cell?.wraps = true
        detailLabel.cell?.usesSingleLineMode = false
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.drawsBackground = false
        detailLabel.isBordered = false
        detailLabel.isEditable = false
        detailLabel.isSelectable = false
        detailLabel.autoresizingMask = [.width, .height]
        addSubview(detailLabel)
    }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width - kClippingsCellPadX * 2)
        titleLabel.frame = NSRect(x: kClippingsCellPadX,
                                  y: bounds.height - kClippingsCellTitleHeight - kClippingsCellPadY,
                                  width: width,
                                  height: kClippingsCellTitleHeight)
        let detailHeight = max(0, bounds.height - kClippingsCellTitleHeight
                                  - kClippingsCellPadY * 2
                                  - kClippingsCellTitleDetailGap)
        detailLabel.frame = NSRect(x: kClippingsCellPadX,
                                   y: kClippingsCellPadY,
                                   width: width,
                                   height: detailHeight)
    }

    func configure(with clipping: PTYSessionClipping) {
        titleLabel.stringValue = clipping.title
        detailLabel.stringValue = clipping.detail
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
        l.font = kClippingsCellDetailFont
        l.lineBreakMode = .byTruncatingTail
        l.maximumNumberOfLines = kClippingsCellMaxDetailLines
        l.cell?.wraps = true
        l.cell?.usesSingleLineMode = false
        return l
    }()

    private static func detailHeight(for string: String, width: CGFloat) -> CGFloat {
        if string.isEmpty {
            return 0
        }
        detailMeasuringLabel.stringValue = string
        guard let cell = detailMeasuringLabel.cell else { return 0 }
        let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        return ceil(cell.cellSize(forBounds: bounds).height)
    }
}

private class ClippingsTableView: NSTableView {
    var deletePressedHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let key = Int(event.keyCode)
        if key == kVK_Delete || key == kVK_ForwardDelete {
            deletePressedHandler?()
            return
        }
        super.keyDown(with: event)
    }
}
