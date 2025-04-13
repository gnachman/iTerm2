//
//  CompletionsWindow.swift
//  iTerm2
//
//  Created by George Nachman on 2/28/25.
//

import Carbon
import AppKit

@objc(iTermCompletionsWindow)
class CompletionsWindow: NSWindow, NSTableViewDataSource, NSTableViewDelegate {
    static func regularAttributes(font maybeFont: NSFont?) -> [NSAttributedString.Key: Any] {
        let font = maybeFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let regularFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingHead
        return [.font: regularFont,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle]
    }
    static func boldAttributes(font maybeFont: NSFont?) -> [NSAttributedString.Key: Any] {
        let font = maybeFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingHead
        return [.font: boldFont,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle]
    }
    static func attributedString(font: NSFont,
                                 prefix: String,
                                 suffix string: String) -> NSAttributedString {
        let attributedPrefix = NSAttributedString(string: prefix,
                                                  attributes: boldAttributes(font: font))
        let attributedString: NSMutableAttributedString = attributedPrefix.mutableCopy() as! NSMutableAttributedString
        attributedString.append(NSAttributedString(string: string,
                                                   attributes: regularAttributes(font: font)))
        return attributedString
    }
    static func attributedDetail(string: String, font: NSFont) -> NSAttributedString {
        return NSAttributedString(string: string,
                                  attributes: regularAttributes(font: font))
    }

    enum Mode {
        case indicator
        case completions(items: [Item])
    }

    struct Item {
        var suggestion: String
        var attributedString: NSAttributedString
        var detail: NSAttributedString
        var kind: CompletionItem.Kind
    }

    @objc
    class iTermCompletionItemBox: NSObject {
        fileprivate var item: Item
        init(item: Item) {
            self.item = item
        }
    }

    // MARK: - Mode and Subviews
    private var mode: Mode  // changed from let to var

    // Subviews for indicator mode.
    private var thinkingTextField: NSTextField?
    private var activityIndicator: NSProgressIndicator?
    private var closeOnResign = false

    // Subviews for completions mode.
    private var tableView: CompletionsTableView?
    private var _returnPressed: ((Item?) -> ())?
    var returnPressed: ((Item?) -> ())? {
        get {
            _returnPressed
        }
        set {
            _returnPressed = newValue
            tableView?.returnPressed = { [weak self] i in
                if let self {
                    if i < 0 {
                        _returnPressed?(nil)
                    } else {
                        _returnPressed?(items[i])
                    }
                }
            }
        }
    }
    private var scrollView: NSScrollView?
    private var detailView: NSView?
    private var detailContainer: NSView?
    private var detailTextField: NSTextField?
    private var dividerView: NSView?
    private var items: [Item] = []
    private var allItems: [Item] = []
    private var selectedRow: Int = -1
    private let visualEffectView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.wantsLayer = true
        view.blendingMode = .behindWindow
        view.material = .windowBackground
        view.state = .active
        return view
    }()
    private let placeholder: String  // What we show while progress indicator is visible

    @objc var selectionDidChange: ((CompletionsWindow, String) -> ())?
    private var topLeftPointForBelow: NSPoint
    private var bottomLeftPointForAbove: NSPoint
    private var searchField: NSSearchField?

    @objc
    static func create(parent: NSWindow,
                       location: NSRect,
                       items: [iTermCompletionItemBox]) -> CompletionsWindow {
        return CompletionsWindow(parent: parent,
                                 location: location,
                                 mode: .completions(items: items.map { $0.item }))
    }

    @objc
    static func makeItem(suggestion: String,
                         attributedString: NSAttributedString,
                         detail: NSAttributedString,
                         kind: CompletionItem.Kind) -> iTermCompletionItemBox {
        return iTermCompletionItemBox(item: Item(suggestion: suggestion,
                                                 attributedString: attributedString,
                                                 detail: detail,
                                                 kind: kind))
    }

    private class KeyCatchingContentView: NSView {
        override var acceptsFirstResponder: Bool { true }
        var canceled = false

        override func becomeFirstResponder() -> Bool {
            DLog("Content view became first responder")
            return true
        }

        override func keyDown(with event: NSEvent) {
            DLog("Content view keyDown: \(event.characters.d)")
            canceled = true
            window?.parent?.makeKeyAndOrderFront(nil)
        }
    }

    var canceled: Bool {
        (contentView as? KeyCatchingContentView)?.canceled ?? false
    }

    // MARK: - Initializer
    init(parent: NSWindow, location: NSRect, mode: Mode, placeholder: String = "Thinking…") {
        self.placeholder = placeholder
        self.mode = mode
        let rect = NSRect(x: 0, y: 0, width: 300, height: 200)
        var adjustedLocation = location.minXminY
        adjustedLocation.x -= 24
        topLeftPointForBelow = adjustedLocation

        adjustedLocation = location.minXmaxY
        adjustedLocation.x -= 24
        adjustedLocation.y += 2
        bottomLeftPointForAbove = adjustedLocation

        super.init(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: true)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .modalPanel
        parent.addChildWindow(self, ordered: .above)

        // Rounded corners.
        contentView = KeyCatchingContentView()
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 8
        contentView?.layer?.borderWidth = 1
        contentView?.addSubview(visualEffectView)

        // Configure mode-specific UI.
        configure(for: mode, animated: false)

        DLog("In init, set top left to \(adjustedLocation)")
        updateFrameOrigin()
    }

    private func updateFrameOrigin() {
        guard screen != nil else {
            return
        }
        setFrameOrigin(frame(forSize: frame.size).origin)
    }

    private func frame(forSize size: NSSize) -> NSRect {
        guard let screen else {
            return NSRect(origin: frame.origin, size: size)
        }
        if topLeftPointForBelow.y - size.height < screen.visibleFrame.minY {
            // Place above
            return NSRect(origin: bottomLeftPointForAbove, size: size)
        } else {
            // Place below
            return NSRect(x: topLeftPointForBelow.x,
                          y: topLeftPointForBelow.y - size.height,
                          width: size.width,
                          height: size.height)
        }
    }

    // MARK: - Dynamic Mode Configuration
    private func configure(for mode: Mode, animated: Bool) {
        // Remove all current subviews.
        contentView?.subviews.forEach {
            if $0 != visualEffectView {
                $0.removeFromSuperview()
            }
        }

        let rect = self.frame

        switch mode {
        case .indicator:
            visualEffectView.frame = rect
            visualEffectView.autoresizingMask = [.width, .height]

            // Setup thinking text field.
            let thinkingTextFieldLocal = NSTextField()
            thinkingTextFieldLocal.isEditable = false
            thinkingTextFieldLocal.isBordered = false
            thinkingTextFieldLocal.drawsBackground = false
            thinkingTextFieldLocal.stringValue = placeholder
            thinkingTextFieldLocal.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            thinkingTextFieldLocal.textColor = .controlTextColor
            thinkingTextFieldLocal.alignment = .center
            thinkingTextFieldLocal.sizeToFit()
            var thinkingTextFieldFrame = thinkingTextFieldLocal.frame
            thinkingTextFieldFrame.origin.x = 8
            thinkingTextFieldFrame.origin.y = 8
            thinkingTextFieldFrame.size.width = rect.width - 16
            thinkingTextFieldLocal.frame = thinkingTextFieldFrame
            thinkingTextFieldLocal.autoresizingMask = [.width, .maxYMargin]
            thinkingTextFieldLocal.lineBreakMode = .byTruncatingTail
            thinkingTextFieldLocal.maximumNumberOfLines = 1
            contentView?.addSubview(thinkingTextFieldLocal)
            thinkingTextField = thinkingTextFieldLocal

            // Setup activity indicator.
            let indicator = NSProgressIndicator()
            indicator.isIndeterminate = true
            indicator.style = .spinning
            indicator.controlSize = .regular
            let indicatorSize = 12.0
            indicator.frame = NSRect(x: rect.width - 8.0 - indicatorSize,
                                     y: (rect.height - indicatorSize) / 2,
                                     width: indicatorSize,
                                     height: indicatorSize)
            contentView?.addSubview(indicator)
            activityIndicator = indicator
            activityIndicator?.startAnimation(nil)

            adjustWindowHeightIndicator()

        case .completions(let completionItems):
            it_assert(!completionItems.isEmpty)
            allItems = completionItems
            items = completionItems
            let detailContainerHeight: CGFloat = 30.0

            if let contentView {
                visualEffectView.frame = contentView.bounds
            }
            visualEffectView.autoresizingMask = [.width, .height]
            contentView?.addSubview(visualEffectView)

            // Setup table view.
            let completionsTableView = CompletionsTableView()
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CompletionColumn"))
            column.resizingMask = .autoresizingMask
            completionsTableView.addTableColumn(column)
            completionsTableView.headerView = nil
            completionsTableView.rowHeight = 20
            completionsTableView.intercellSpacing = NSSize(width: 0, height: 2)
            completionsTableView.dataSource = self
            completionsTableView.delegate = self
            completionsTableView.selectionHighlightStyle = .none
            completionsTableView.backgroundColor = .clear
            completionsTableView.doubleAction = #selector(doubleClick(_:))

            let scrollViewLocal = NSScrollView()
            scrollViewLocal.documentView = completionsTableView
            scrollViewLocal.hasVerticalScroller = false
            scrollViewLocal.hasHorizontalScroller = false
            scrollViewLocal.frame = NSRect(x: 0, y: detailContainerHeight, width: rect.width, height: rect.height - detailContainerHeight)
            scrollViewLocal.autoresizingMask = [.width, .height]
            scrollViewLocal.drawsBackground = false
            scrollViewLocal.automaticallyAdjustsContentInsets = false
            scrollViewLocal.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
            contentView?.addSubview(scrollViewLocal)
            tableView = completionsTableView
            scrollView = scrollViewLocal

            let detailContainerView = SolidColorView()
            detailContainerView.color = NSColor.it_dynamicColor(forLightMode: .init(white: 1, alpha: 0.8),
                                                                darkMode: .init(white: 1, alpha: 0.2))
            detailContainerView.wantsLayer = true
            detailContainerView.frame = NSRect(x: 0, y: 0, width: rect.width, height: detailContainerHeight)
            detailContainer = detailContainerView
            contentView?.addSubview(detailContainerView)
            detailView = detailContainerView

            let detailTextFieldLocal = NSTextField()
            detailTextFieldLocal.isEditable = false
            detailTextFieldLocal.isBordered = false
            detailTextFieldLocal.drawsBackground = false
            detailTextFieldLocal.attributedStringValue = items[0].detail
            detailTextFieldLocal.sizeToFit()
            detailTextFieldLocal.frame = detailContainerView.bounds.insetBy(dx: 8, dy: (detailContainerHeight - detailTextFieldLocal.bounds.height) / 2)
            detailTextFieldLocal.autoresizingMask = [.width, .height]
            detailTextFieldLocal.lineBreakMode = .byTruncatingTail
            detailTextFieldLocal.maximumNumberOfLines = 1
            detailContainerView.addSubview(detailTextFieldLocal)
            detailTextField = detailTextFieldLocal

            let dividerLineView = SolidColorView()
            dividerLineView.wantsLayer = true
            dividerLineView.color = NSColor(white: 0.5, alpha: 1.0)
            dividerLineView.frame = NSRect(x: 0, y: detailContainerView.frame.height - 1, width: rect.width, height: 1)
            dividerLineView.autoresizingMask = [.width]
            detailContainerView.addSubview(dividerLineView)
            dividerView = dividerLineView

            adjustWindowHeightCompletions(animated: animated)
            completionsTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateColors()
    }

    func switchMode(to newMode: Mode) {
        if canceled {
            return
        }
        self.mode = newMode
        configure(for: newMode, animated: true)
    }

    @objc private func doubleClick(_ sender: Any) {
        tableView?.invokeReturnPressed()
    }

    func showSearchField(initialText: String) {
        // Only show the search field in completions mode.
        guard case .completions = mode else {
           return 
        }
        if searchField == nil {
            let searchField = NSSearchField(frame: .zero)
            searchField.focusRingType = .none
            searchField.placeholderString = "Search"
            searchField.delegate = self
            self.searchField = searchField
            contentView?.addSubview(searchField)
        }
        searchField?.stringValue = initialText
        filterItems(matching: initialText)
        adjustWindowHeightCompletions(animated: true)
        makeFirstResponder(searchField)

        // Move the insertion point to the end.
        if let editor = searchField?.currentEditor() {
            let endPos = (searchField?.stringValue as NSString?)?.length ?? 0
            editor.selectedRange = NSRange(location: endPos, length: 0)
        }
    }

    private func filterItems(matching paddedText: String) {
        let text = paddedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            items = allItems
        } else {
            items = allItems.filter {
                $0.suggestion.range(of: text,
                                    options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        tableView?.reloadData()
        if !items.isEmpty {
            selectRow(0)
        }
        adjustWindowHeightCompletions(animated: true)
    }

    // MARK: - Common Methods

    private func updateColors() {
        guard let contentView = self.contentView else { return }
        if contentView.effectiveAppearance.it_isDark {
            contentView.layer?.borderColor = NSColor(white: 1, alpha: 0.5).cgColor
        } else {
            contentView.layer?.borderColor = NSColor(white: 0.5, alpha: 0.8).cgColor
        }
    }

    private func adjustWindowHeightIndicator() {
        guard let thinkingTextField = thinkingTextField else { return }
        var frame = self.frame
        let contentHeight = thinkingTextField.frame.height
        frame.size.height = 16 + contentHeight
        let oldMaxY = self.frame.maxY
        frame.origin.y = oldMaxY - frame.size.height
        DLog("For indicator set frame to \(frame)")
        setFrame(self.frame(forSize: frame.size), display: true)

        if let activityIndicator = activityIndicator {
            var activityIndicatorFrame = activityIndicator.frame
            activityIndicatorFrame.origin.y = (frame.height - activityIndicatorFrame.height) / 2
            activityIndicator.frame = activityIndicatorFrame
        }
    }

    private func adjustWindowHeightCompletions(animated: Bool) {
        guard let completionsTableView = tableView,
              let scrollView = scrollView,
              let detailView = detailView else { return }
        completionsTableView.layoutSubtreeIfNeeded()

        let maxHeight: CGFloat = 200
        let tableHeight = completionsTableView.fittingSize.height
        let detailContainerHeight = detailView.frame.height
        // Use a fixed height (e.g. 22) if search field is visible.
        let searchFieldHeight: CGFloat = (searchField != nil) ? 22.0 : 0.0

        let desiredHeight = detailContainerHeight + searchFieldHeight + tableHeight + scrollView.contentInsets.bottom
        let finalHeight = min(maxHeight, desiredHeight)

        let maxWidth: CGFloat = 500
        var requiredWidth: CGFloat = 300 // Default width

        // Determine the required width dynamically
        let textWidth = items
            .map { $0.attributedString.size().width }
            .max() ?? requiredWidth

        if let column = completionsTableView.tableColumns.first, tableView != nil {
            let columnPadding: CGFloat = 28
            let iconWidth = CompletionCell.imageWidth + CGFloat(CompletionCell.imageToTextMargin)
            requiredWidth = min(maxWidth, max(requiredWidth, textWidth + columnPadding + iconWidth))
            let columnWidth = requiredWidth - 32
            if column.width < columnWidth {
                column.width = columnWidth
            }
        }

        if requiredWidth != frame.width {
            var frame = self.frame
            frame.size.width = requiredWidth
            setFrame(self.frame(forSize: frame.size), display: true, animate: false)
        }
        var frame = self.frame
        frame.size = NSSize(width: requiredWidth, height: finalHeight)
        let requiredFrame = self.frame(forSize: frame.size)
        setFrame(requiredFrame, display: true, animate: animated)

        // detailView (detail container) remains at the bottom.
        // Scroll view now sits above it and below the search field.
        scrollView.frame = NSRect(x: 0,
                                  y: detailContainerHeight,
                                  width: frame.width,
                                  height: finalHeight - detailContainerHeight - searchFieldHeight)
        // Position the search field above the scroll view.
        searchField?.frame = NSRect(x: 0,
                                    y: scrollView.frame.maxY,
                                    width: frame.width,
                                    height: searchFieldHeight)

        if let tableView {
            var temp = tableView.frame
            temp.size.width = frame.width
            tableView.frame = temp
        }
        if let detailContainer = detailContainer {
            var temp = detailContainer.frame
            temp.size.width = frame.width
            detailContainer.frame = temp
        }
    }

    // MARK: - NSTableViewDataSource / Delegate (for completions mode)
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return CompletionRowView()
    }

    private func makeNewCellView(_ cellId: NSUserInterfaceItemIdentifier) -> CompletionCell {
        return CompletionCell(identifier: cellId)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellId = NSUserInterfaceItemIdentifier("CompletionCell")
        let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? CompletionCell
        let cellView: CompletionCell = existing ?? makeNewCellView(cellId)
        cellView.textField?.attributedStringValue = items[row].attributedString
        cellView.iconImageView.image = icon(for: items[row])
        return cellView
    }

    private func icon(for item: Item) -> NSImage {
        switch item.kind {
        case .file:
            return NSImage.it_image(forSymbolName: "document",
                                    accessibilityDescription: "File",
                                    fallbackImageName: "document",
                                    for: CompletionsWindow.self)
        case .aiSuggestion:
            return NSImage.it_image(forSymbolName: "sparkles",
                                    accessibilityDescription: "AI",
                                    fallbackImageName: "sparkles",
                                    for: CompletionsWindow.self)
        case .history:
            return NSImage.it_image(forSymbolName: "clock",
                                    accessibilityDescription: "History",
                                    fallbackImageName: "clock",
                                    for: CompletionsWindow.self)
        case .command:
            return NSImage.it_image(forSymbolName: "command",
                                    accessibilityDescription: "Command",
                                    fallbackImageName: "command",
                                    for: CompletionsWindow.self)
        case .folder:
            return NSImage.it_image(forSymbolName: "folder",
                                    accessibilityDescription: "Folder",
                                    fallbackImageName: "folder",
                                    for: CompletionsWindow.self)
        }
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        rowView.wantsLayer = true
        rowView.layer?.cornerRadius = 6
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let completionsTableView = tableView, completionsTableView.selectedRow >= 0 else { return }
        let item = items[completionsTableView.selectedRow]
        detailTextField?.attributedStringValue = item.detail
        selectedRow = completionsTableView.selectedRow
        selectionDidChange?(self, item.suggestion)
    }

    // MARK: - Navigation (completions mode only)
    func up() {
        if case .completions = mode, selectedRow > 0 {
            selectRow(selectedRow - 1)
        }
    }

    func down() {
        if case .completions = mode, selectedRow + 1 < items.count {
            selectRow(selectedRow + 1)
        }
    }

    private func selectRow(_ row: Int) {
        let newRow = max(0, min(items.count - 1, row))
        selectedRow = newRow
        tableView?.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        tableView?.scrollRowToVisible(newRow)
        detailTextField?.attributedStringValue = items[newRow].detail
        selectionDidChange?(self, items[newRow].suggestion)
    }

    func setDetailAttributedString(_ attrString: NSAttributedString) {
        detailTextField?.attributedStringValue = attrString
    }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        return 0.05
    }

    override var canBecomeKey: Bool {
        switch mode {
        case .indicator:
            return closeOnResign
        case .completions:
            return true
        }
    }

    override var canBecomeMain: Bool { true }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        if canceled {
            return
        }
        closeOnResign = true
        super.makeKeyAndOrderFront(sender)
        if let tableView {
            makeFirstResponder(tableView)
        } else {
            if let contentView {
                DLog("Make content view first responder")
                makeFirstResponder(contentView)
            }
        }
    }

    override func resignKey() {
        if closeOnResign {
            self.parent?.removeChildWindow(self)
            orderOut(nil)
        }
        super.resignKey()
    }
}

extension CompletionsWindow: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let sf = obj.object as? NSSearchField {
            filterItems(matching: sf.stringValue)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control == searchField {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                up()
                return true
            case #selector(NSResponder.moveDown(_:)):
                down()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                tableView?.invokeReturnPressed()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                tableView?.invokeEscapePressed()
                return true
            default:
                break
            }
        }
        return false
    }
}

class CompletionRowView: NSTableRowView {
    private let backgroundLayer: CALayer = {
        let layer = CALayer()
        layer.cornerRadius = 4
        layer.shadowRadius = 8
        layer.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer.masksToBounds = false
        return layer
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(backgroundLayer)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(backgroundLayer)
        updateAppearance()
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds.insetBy(dx: 8, dy: 0)
    }

    override func viewDidChangeEffectiveAppearance() {
        updateAppearance()
    }

    private func updateAppearance() {
        CALayer.performWithoutAnimation {
            backgroundLayer.shadowOffset = CGSize(width: 0, height: 3)
            if isSelected {
                if effectiveAppearance.it_isDark {
                    backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
                } else {
                    backgroundLayer.backgroundColor = NSColor.white.cgColor
                }
                backgroundLayer.shadowOpacity = 0.35
            } else {
                backgroundLayer.backgroundColor = NSColor.clear.cgColor
                backgroundLayer.shadowOpacity = 0.0
            }
        }
    }
}

extension CALayer {
    static func performWithoutAnimation(_ closure: () -> ()) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        closure()
        CATransaction.commit()
    }
}

@objc
class CompletionCell: NSTableCellView {
    let cellTextField = {
        let textField = NSTextField(frame: .zero)
        textField.isBordered = false
        textField.isEditable = false
        textField.drawsBackground = false
        textField.lineBreakMode = .byTruncatingHead
        textField.maximumNumberOfLines = 1
        textField.isBezeled = false
        textField.isSelectable = false
        return textField
    }()
    let iconImageView: NSImageView = {
        let imageView = NSImageView(frame: .zero)
        // Optionally set a default image:
        // imageView.image = NSImage(named: "YourIconName")
        return imageView
    }()
    static let imageToTextMargin = 4
    static let imageWidth = 16.0

    init(identifier: NSUserInterfaceItemIdentifier) {
        cellTextField.identifier = identifier
        super.init(frame: .zero)
        self.textField = cellTextField
        addSubview(cellTextField)
        addSubview(iconImageView)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        cellTextField.sizeToFit()

        var x = CGFloat(0)
        var frame = iconImageView.frame
        frame.origin.x = x
        frame.origin.y = (bounds.height - Self.imageWidth) / 2
        frame.size.width = Self.imageWidth
        frame.size.height = Self.imageWidth
        iconImageView.frame = frame

        x += frame.width
        x += CGFloat(Self.imageToTextMargin)

        cellTextField.sizeToFit()
        frame = cellTextField.frame
        frame.origin.x = x
        frame.origin.y = (bounds.height - frame.height) / 2
        frame.size.width = bounds.width - x
        cellTextField.frame = frame

        DLog("cell width=\(bounds.width) textfield frame=\(frame)")
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}

class CompletionsTableView: NSTableView {
    override var acceptsFirstResponder: Bool { true }
    var returnPressed: ((Int) -> ())?

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
        return true
    }

    func invokeReturnPressed() {
        let i = selectedRow
        if i >= 0 {
            returnPressed?(i)
        }
    }

    func invokeEscapePressed() {
        returnPressed?(-1)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Escape {
            invokeEscapePressed()
        } else if event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter {
            invokeReturnPressed()
        } else if !event.modifierFlags.contains(.function) {
            // On any other typing key, show the search field.
            if let window = self.window as? CompletionsWindow,
               let chars = event.charactersIgnoringModifiers,
               !chars.isEmpty {
                window.showSearchField(initialText: chars)
                return
            }
        }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        DLog("Newline")
    }
}
