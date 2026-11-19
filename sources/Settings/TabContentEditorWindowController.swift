//
//  TabContentEditorWindowController.swift
//  iTerm2SharedARC
//
//  A sheet for editing one profile's rich tab content: which lines tabs show
//  in windows created with it, in what order and size, and what each line
//  shows and how it looks. Whether they show rich content at all is a
//  checkbox in the Window pane, which only enables the button that opens
//  this while it's on. Built in code.
//  The caller applies changes to the profile as they're made (see
//  changeHandler and TabContentEditSession), and undoes them on Cancel.
//

import AppKit
import ColorPicker

@objc(iTermTabContentEditorWindowController)
final class TabContentEditorWindowController: NSWindowController {
    // The values as edited so far. changeHandler runs after they change.
    @objc var layoutPropertyList: [[String: Any]] { model.layout.propertyList }
    @objc var overrides: [String: Any] { model.overrides }
    @objc var subtitleFormat: String { model.subtitleFormat }
    @objc var layoutChanged: Bool { model.layoutChanged }
    // 0 for no limit.
    @objc var lineLimit: Int { model.lineLimit ?? 0 }
    @objc var lineLimitChanged: Bool { model.lineLimitChanged }

    // Runs after the values change, once for all the changes made while
    // handling an event, so they can be shown in open windows right away.
    // Not after the sheet ends.
    @objc var changeHandler: (() -> Void)?
    private var changeHandlerScheduled = false

    private let model: TabContentEditorModel
    @objc let profileGUID: String?

    let tableView = NSTableView()
    let addRemoveControl = NSSegmentedControl()
    // Expands into a larger editor for long interpolated strings.
    let textField = ExpandingTextField()
    private var textFieldDelegate: iTermFunctionCallTextFieldDelegate?
    let sizePopup = NSPopUpButton()
    let linesField = NumberStepperField(range: TabContentSlot.maximumLinesRange)
    let lineLimitCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let lineLimitField = NumberStepperField(range: 1...50)
    let boldCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let italicCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let colorPopup = NSPopUpButton()
    // Our color well, which opens our color picker.
    let colorWell: CPKColorWell = {
        guard let well = CPKColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 23),
                                      colorSpace: NSColorSpace.it_default()) else {
            it_fatalError("Couldn’t make a color well")
        }
        return well
    }()
    // With separate colors, colorWell is for light mode and this for dark.
    let darkColorWell: CPKColorWell = {
        guard let well = CPKColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 23),
                                      colorSpace: NSColorSpace.it_default()) else {
            it_fatalError("Couldn’t make a color well")
        }
        return well
    }()
    let separateColorsCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    // Name the wells while there are two.
    private let lightColorLabel = NSTextField(labelWithString: "")
    private let darkColorLabel = NSTextField(labelWithString: "")
    private let truncationPopup = NSPopUpButton()
    private let collapseCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let formatPopup = NSPopUpButton()
    let resetButton = NSButton(title: "", target: nil, action: nil)
    let cancelButton = NSButton(title: "", target: nil, action: nil)
    let previewView = TabContentPreviewView()
    // The line list and the selected line's settings, side by side.
    let lineEditor = NSStackView()

    private static let rowDragType = NSPasteboard.PasteboardType("com.googlecode.iterm2.tab-content-line")

    @objc init(profile: [AnyHashable: Any]) {
        let configuration = TabContentConfiguration(profile: profile)
        model = TabContentEditorModel(layout: configuration.layout,
                                      overrides: configuration.overrides,
                                      subtitleFormat: configuration.subtitleFormat,
                                      lineLimit: configuration.lineLimit)
        profileGUID = profile[KEY_GUID] as? String
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                             styleMask: [.titled, .resizable],
                             backing: .buffered,
                             defer: true)
        super.init(window: window)
        buildUI()
        reload(selecting: 0)
        fitWindowToContent(initialWidth: 720)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowDidResize(_:)),
                                               name: NSWindow.didResizeNotification,
                                               object: window)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowDidEndLiveResize(_:)),
                                               name: NSWindow.didEndLiveResizeNotification,
                                               object: window)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Building the UI

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let scopeNote = Self.noteLabel(String(localized: "TabContentEditor.ScopeNote",
                                              defaultValue: "These apply to every tab in windows created with this profile, including windows already open. Tabs get taller to fit the lines.",
                                              comment: "Note at the top of the tab content editor saying which tabs its settings affect"))

        buildLineEditor()

        lineLimitCheckbox.title = String(localized: "TabContentEditor.LineLimitCheckbox",
                                         defaultValue: "Limit lines per tab to:",
                                         comment: "Checkbox before a number field. When on, tabs are only tall enough for that many lines of rich content.")
        lineLimitCheckbox.target = self
        lineLimitCheckbox.action = #selector(lineLimitCheckboxDidChange(_:))
        lineLimitField.target = self
        lineLimitField.action = #selector(lineLimitFieldDidChange(_:))
        lineLimitCheckbox.state = model.lineLimit == nil ? .off : .on
        if let lineLimit = model.lineLimit {
            lineLimitField.value = lineLimit
        }
        let limitRow = Self.row([lineLimitCheckbox, lineLimitField])
        let lineLimitNote = Self.noteLabel(String(localized: "TabContentEditor.LineLimitNote",
                                                  defaultValue: "Lines past the limit are cut off.",
                                                  comment: "Note under the setting that limits how many lines of rich content tabs show"))

        let previewLabel = NSTextField(labelWithString: String(localized: "TabContentEditor.Preview",
                                                               defaultValue: "Preview:",
                                                               comment: "Label above a preview of a tab in the tab content editor"))
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.widthAnchor.constraint(equalToConstant: 240).isActive = true

        let cancel = cancelButton
        cancel.title = String(localized: "TabContentEditor.Cancel",
                              defaultValue: "Cancel",
                              comment: "Button that closes the tab content editor and undoes the changes made in it, which were showing in open windows")
        cancel.target = self
        cancel.action = #selector(cancel(_:))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: String(localized: "TabContentEditor.OK",
                                        defaultValue: "OK",
                                        comment: "Button that closes the tab content editor, keeping the changes made in it"),
                          target: self,
                          action: #selector(ok(_:)))
        ok.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, ok])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [scopeNote, lineEditor, limitRow, lineLimitNote,
                                        previewLabel, previewView, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(16, after: scopeNote)
        stack.setCustomSpacing(16, after: lineEditor)
        stack.setCustomSpacing(4, after: limitRow)
        stack.setCustomSpacing(16, after: lineLimitNote)
        stack.setCustomSpacing(16, after: previewView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // As short as its contents, not stretched to the window.
        stack.setHuggingPriority(.required, for: .vertical)
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            // At most this far from the bottom: the window catches up to a
            // change in height after the current event, and until then any
            // spare room goes below everything rather than between controls.
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            scopeNote.widthAnchor.constraint(equalTo: stack.widthAnchor),
            lineEditor.widthAnchor.constraint(equalTo: stack.widthAnchor),
            lineLimitNote.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private var fittingWindow = false

    // As big as the content needs, which depends on the language, the width
    // (notes rewrap), and the preview's height. Only the width can change;
    // nothing would use more height.
    private func fitWindowToContent(initialWidth: CGFloat? = nil) {
        guard !fittingWindow, let window, let contentView = window.contentView else {
            return
        }
        fittingWindow = true
        defer {
            fittingWindow = false
        }
        contentView.layoutSubtreeIfNeeded()
        let minimumWidth = contentView.fittingSize.width
        let current = window.contentRect(forFrameRect: window.frame).size
        let width = max(minimumWidth, initialWidth ?? current.width)
        // Apply the width first, so the height is measured with the notes
        // wrapped for it.
        if width != current.width {
            setContentSize(NSSize(width: width, height: current.height))
            contentView.layoutSubtreeIfNeeded()
        }
        let height = contentView.fittingSize.height
        window.contentMinSize = NSSize(width: minimumWidth, height: height)
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: height)
        if height != window.contentRect(forFrameRect: window.frame).height {
            setContentSize(NSSize(width: width, height: height))
        }
    }

    // Keeps the top edge where it is.
    private func setContentSize(_ size: NSSize) {
        guard let window else {
            return
        }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    // While the user drags, the height catches up when they let go, rather
    // than changing under the drag.
    @objc private func windowDidResize(_ notification: Notification) {
        guard window?.inLiveResize != true else {
            return
        }
        fitWindowToContent()
    }

    @objc private func windowDidEndLiveResize(_ notification: Notification) {
        fitWindowToContent()
    }

    private var windowFitScheduled = false

    // After the current event, so a click that commits an edit (resizing the
    // window) still lands where the user clicked.
    private func scheduleWindowFit() {
        guard !windowFitScheduled else {
            return
        }
        windowFitScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.windowFitScheduled = false
            self?.fitWindowToContent()
        }
    }

    // Labels sized to their text, aligned on their trailing edge, so a long
    // translation widens the column rather than being cut off.
    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private static func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        // As wide as its views. Otherwise its width would be ambiguous.
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        return stack
    }

    // A form: a column of trailing-aligned labels as wide as the widest one,
    // however long that is in this language, each beside its control on the
    // same baseline. A row whose label is nil has none. Views in `stretching`
    // take the rest of the form's width; others keep their natural width.
    private static func form(_ rows: [(label: NSTextField?, control: NSView)],
                             stretching: Set<NSView> = []) -> NSStackView {
        let labelWidth = ceil(rows.compactMap { $0.label?.fittingSize.width }.max() ?? 0)
        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 10
        for (label, control) in rows {
            let leading: NSView = label ?? NSView()
            leading.translatesAutoresizingMaskIntoConstraints = false
            leading.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
            let row = NSStackView(views: [leading, control])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 8
            form.addArrangedSubview(row)
            if stretching.contains(control) {
                row.distribution = .fill
                row.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
            } else {
                // As wide as its views. Otherwise its width would be
                // ambiguous.
                row.setHuggingPriority(.defaultHigh, for: .horizontal)
            }
        }
        return form
    }

    // The line list, and beside it the selected line's settings.
    private func buildLineEditor() {
        let lineList = buildLineList()
        // Wide enough for every line's name in this language.
        let names = TabContentEditorModel.builtInIdentifiers.map(TabContentEditorModel.displayName(for:)) +
            [TabContentEditorModel.displayName(for: TabContentSlot.customPrefix)]
        let widestName = names.map { ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width }.max() ?? 0
        lineList.widthAnchor.constraint(equalToConstant: max(200, ceil(widestName) + 60)).isActive = true

        let settings = buildLineSettings()
        lineEditor.setViews([lineList, settings], in: .leading)
        lineEditor.orientation = .horizontal
        lineEditor.alignment = .top
        lineEditor.spacing = 20
        // The settings take the rest of the width, so the text field and
        // notes use it.
        lineEditor.distribution = .fill
        settings.setContentHuggingPriority(.init(1), for: .horizontal)
        // The list is as tall as the settings beside it.
        lineList.heightAnchor.constraint(equalTo: settings.heightAnchor).isActive = true
    }

    // What the selected line shows, how big it is, and how it looks.
    private func buildLineSettings() -> NSView {
        // Keeps long text clear of the expand button.
        let cell = iTermStatusIndicatingTextFieldCell(textCell: "")
        cell.isEditable = true
        cell.isSelectable = true
        cell.isBezeled = true
        cell.bezelStyle = .squareBezel
        cell.drawsBackground = true
        cell.isScrollable = true
        cell.usesSingleLineMode = true
        cell.rightInset = 23
        textField.cell = cell
        textField.placeholderString = String(localized: "TabContentEditor.TextPlaceholder",
                                             defaultValue: "Interpolated string",
                                             comment: "Placeholder in the field for a tab content line’s text")
        textFieldDelegate = iTermFunctionCallTextFieldDelegate(pathSource: iTermVariableHistory.pathSource(for: .session),
                                                               passthrough: self,
                                                               functionsOnly: false)
        textField.delegate = textFieldDelegate
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Take whatever width the labels don't need.
        textField.setContentHuggingPriority(.init(1), for: .horizontal)

        boldCheckbox.title = String(localized: "TabContentEditor.Bold",
                                    defaultValue: "Bold",
                                    comment: "Checkbox that makes a tab content line bold")
        boldCheckbox.target = self
        boldCheckbox.action = #selector(boldDidChange(_:))
        italicCheckbox.title = String(localized: "TabContentEditor.Italic",
                                      defaultValue: "Italic",
                                      comment: "Checkbox that makes a tab content line italic")
        italicCheckbox.target = self
        italicCheckbox.action = #selector(italicDidChange(_:))

        colorPopup.addItems(withTitles: [
            String(localized: "TabContentEditor.ColorNormal",
                   defaultValue: "Normal",
                   comment: "Color menu item: draw the line in the tab bar’s normal text color"),
            String(localized: "TabContentEditor.ColorSecondary",
                   defaultValue: "Dimmed",
                   comment: "Color menu item: draw the line in the tab bar’s secondary (dimmer) text color"),
            String(localized: "TabContentEditor.ColorCustom",
                   defaultValue: "Custom",
                   comment: "Color menu item: draw the line in a color the user picks"),
        ])
        colorPopup.target = self
        colorPopup.action = #selector(colorChoiceDidChange(_:))
        colorWell.target = self
        colorWell.action = #selector(colorWellDidChange(_:))
        colorWell.isContinuous = true
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 23).isActive = true
        darkColorWell.target = self
        darkColorWell.action = #selector(darkColorWellDidChange(_:))
        darkColorWell.isContinuous = true
        darkColorWell.translatesAutoresizingMaskIntoConstraints = false
        darkColorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        darkColorWell.heightAnchor.constraint(equalToConstant: 23).isActive = true
        lightColorLabel.stringValue = String(localized: "TabContentEditor.LightColorLabel",
                                             defaultValue: "Light:",
                                             comment: "Label for the color well choosing a tab content line’s color in light mode")
        darkColorLabel.stringValue = String(localized: "TabContentEditor.DarkColorLabel",
                                            defaultValue: "Dark:",
                                            comment: "Label for the color well choosing a tab content line’s color in dark mode")
        separateColorsCheckbox.title = String(localized: "TabContentEditor.SeparateColors",
                                              defaultValue: "Separate light and dark colors",
                                              comment: "Checkbox for a tab content line with a custom color: pick one color for light mode and another for dark mode")
        separateColorsCheckbox.target = self
        separateColorsCheckbox.action = #selector(separateColorsDidChange(_:))

        truncationPopup.addItems(withTitles: TabContentTruncation.allCases.map(Self.title(for:)))
        truncationPopup.target = self
        truncationPopup.action = #selector(truncationDidChange(_:))

        formatPopup.addItems(withTitles: [
            String(localized: "TabContentEditor.FormatPlainText",
                   defaultValue: "Plain Text",
                   comment: "Format menu item: a tab content line’s text is shown as is"),
            String(localized: "TabContentEditor.FormatHTML",
                   defaultValue: "HTML",
                   comment: "Format menu item: a tab content line’s text is lightweight HTML, which can make parts bold, italic, underlined, or colored"),
        ])
        formatPopup.target = self
        formatPopup.action = #selector(formatDidChange(_:))
        let formatNote = Self.noteLabel(String(localized: "TabContentEditor.FormatNote",
                                               defaultValue: "HTML can use <b>, <i>, <u>, and <font color=#rrggbb>. Escape values with iterm2.escape_html(string: name?).",
                                               comment: "Note about the Format menu listing the HTML tags a tab content line can use, and the function that makes a value safe to use in HTML. Do not translate the tags or the function name."))

        collapseCheckbox.title = String(localized: "TabContentEditor.Collapse",
                                        defaultValue: "When empty, move the lines below up",
                                        comment: "Checkbox for a tab content line: if the line has no text, the lines after it take its place")
        collapseCheckbox.target = self
        collapseCheckbox.action = #selector(collapseDidChange(_:))

        sizePopup.addItems(withTitles: TabContentLineSize.allCases.map(Self.title(for:)))
        sizePopup.target = self
        sizePopup.action = #selector(sizeDidChange(_:))
        linesField.target = self
        linesField.action = #selector(linesDidChange(_:))

        resetButton.title = String(localized: "TabContentEditor.Reset",
                                   defaultValue: "Reset to Default",
                                   comment: "Button that puts a tab content line back the way it is when first added: its size, text, and style")
        resetButton.target = self
        resetButton.action = #selector(reset(_:))

        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        return Self.form([
            (Self.label(String(localized: "TabContentEditor.TextLabel",
                               defaultValue: "Text:",
                               comment: "Label for the field holding a tab content line’s interpolated string")), textField),
            (Self.label(String(localized: "TabContentEditor.FormatLabel",
                               defaultValue: "Format:",
                               comment: "Label for the menu choosing whether a tab content line is plain text or HTML")), formatPopup),
            (nil, formatNote),
            (Self.label(String(localized: "TabContentEditor.SizeLabel",
                               defaultValue: "Size:",
                               comment: "Label for the menu choosing a tab content line’s font size")), sizePopup),
            (Self.label(String(localized: "TabContentEditor.LinesLabel",
                               defaultValue: "Lines:",
                               comment: "Label for the number field choosing how many lines a tab content line’s text can wrap onto")), linesField),
            (Self.label(String(localized: "TabContentEditor.StyleLabel",
                               defaultValue: "Style:",
                               comment: "Label for the bold and italic checkboxes of a tab content line")), Self.row([boldCheckbox, italicCheckbox])),
            (Self.label(String(localized: "TabContentEditor.ColorLabel",
                               defaultValue: "Color:",
                               comment: "Label for the menu choosing a tab content line’s color")),
             Self.row([colorPopup, lightColorLabel, colorWell, darkColorLabel, darkColorWell])),
            (nil, separateColorsCheckbox),
            (Self.label(String(localized: "TabContentEditor.TruncationLabel",
                               defaultValue: "Truncate:",
                               comment: "Label for the menu choosing where a too-long tab content line is cut off")), truncationPopup),
            (nil, collapseCheckbox),
            (nil, resetButton),
        ], stretching: [textField, formatNote])
    }

    private static func noteLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        // Below the fitting size's priority, so notes wrap rather than set
        // the window's minimum width, however long a translation is.
        label.setContentCompressionResistancePriority(.init(NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1),
                                                      for: .horizontal)
        return label
    }

    private func buildLineList() -> NSView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("line"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.rowDragType])
        tableView.usesAutomaticRowHeights = false
        tableView.rowHeight = 34
        tableView.style = .inset
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        addRemoveControl.segmentCount = 2
        addRemoveControl.setImage(NSImage(systemSymbolName: SFSymbol.plus.rawValue,
                                          accessibilityDescription: String(localized: "TabContentEditor.AddLine",
                                                                           defaultValue: "Add Line",
                                                                           comment: "Accessibility label for the button that adds a tab content line")),
                                  forSegment: 0)
        addRemoveControl.setImage(NSImage(systemSymbolName: SFSymbol.minus.rawValue,
                                          accessibilityDescription: String(localized: "TabContentEditor.RemoveLine",
                                                                           defaultValue: "Remove Line",
                                                                           comment: "Accessibility label for the button that removes a tab content line")),
                                  forSegment: 1)
        addRemoveControl.trackingMode = .momentary
        addRemoveControl.segmentStyle = .smallSquare
        addRemoveControl.target = self
        addRemoveControl.action = #selector(addOrRemove(_:))

        let stack = NSStackView(views: [scrollView, addRemoveControl])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private static func title(for size: TabContentLineSize) -> String {
        switch size {
        case .large:
            return String(localized: "TabContentEditor.SizeLarge",
                          defaultValue: "Large",
                          comment: "Font size menu item for a tab content line")
        case .regular:
            return String(localized: "TabContentEditor.SizeRegular",
                          defaultValue: "Regular",
                          comment: "Font size menu item for a tab content line")
        case .small:
            return String(localized: "TabContentEditor.SizeSmall",
                          defaultValue: "Small",
                          comment: "Font size menu item for a tab content line")
        }
    }

    private static func title(for truncation: TabContentTruncation) -> String {
        switch truncation {
        case .end:
            return String(localized: "TabContentEditor.TruncateEnd",
                          defaultValue: "At End",
                          comment: "Truncation menu item: cut off a too-long line at its end")
        case .middle:
            return String(localized: "TabContentEditor.TruncateMiddle",
                          defaultValue: "In Middle",
                          comment: "Truncation menu item: cut off a too-long line in its middle")
        case .start:
            return String(localized: "TabContentEditor.TruncateStart",
                          defaultValue: "At Start",
                          comment: "Truncation menu item: cut off a too-long line at its start")
        }
    }

    // MARK: - Showing the model

    private var selectedIndex: Int? {
        let row = tableView.selectedRow
        return row >= 0 && row < model.layout.slots.count ? row : nil
    }

    private func reload(selecting index: Int?) {
        // The selected row may not change (removing a line selects the one
        // that took its place), so don't count on a selection change to stop
        // editing the old line's text.
        abortEditingLineFields()
        tableView.reloadData()
        if let index, index < model.layout.slots.count {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateEditor()
    }

    // The controls for the selected line.
    private var lineControls: [NSView] {
        return [textField, sizePopup, linesField, boldCheckbox, italicCheckbox, colorPopup, colorWell,
                darkColorWell, separateColorsCheckbox, formatPopup, truncationPopup, collapseCheckbox, resetButton]
    }

    private static func setEnabled(_ view: NSView, _ enabled: Bool) {
        if let control = view as? NSControl {
            control.isEnabled = enabled
        } else if let field = view as? NumberStepperField {
            field.isEnabled = enabled
        }
    }

    // Stops editing fields that show the selected line's values, so an edit
    // in progress can't land on another line.
    private func abortEditingLineFields() {
        textField.abortEditing()
        linesField.textField.abortEditing()
    }

    private func updateEditor() {
        addRemoveControl.setEnabled(selectedIndex != nil && model.canRemove, forSegment: 1)
        lineLimitField.isEnabled = model.lineLimit != nil
        if model.lineLimit == nil, lineLimitField.textField.currentEditor() == nil {
            // Start from how many lines the layout has now, so turning the
            // limit on cuts nothing until the number goes down.
            lineLimitField.value = model.layout.slots.reduce(0) { $0 + $1.maximumLines }
        }
        updatePreview()
        guard let index = selectedIndex else {
            lineControls.forEach { Self.setEnabled($0, false) }
            textField.stringValue = ""
            separateColorsCheckbox.state = .off
            showSeparateColors(false)
            return
        }
        lineControls.forEach { Self.setEnabled($0, true) }
        let line = model.lines[index]
        if textField.currentEditor() == nil {
            textField.stringValue = line.style.text
        }
        sizePopup.selectItem(at: TabContentLineSize.allCases.firstIndex(of: line.slot.size) ?? 0)
        // Don't overwrite a number being typed.
        if linesField.textField.currentEditor() == nil {
            linesField.value = line.slot.maximumLines
        }
        boldCheckbox.state = line.style.bold ? .on : .off
        italicCheckbox.state = line.style.italic ? .on : .off
        switch model.colorChoice(at: index) {
        case .normal:
            colorPopup.selectItem(at: 0)
            showColorInDisabledWell(.labelColor)
        case .secondary:
            colorPopup.selectItem(at: 1)
            showColorInDisabledWell(.secondaryLabelColor)
        case .custom(let color):
            colorPopup.selectItem(at: 2)
            colorWell.color = color
        }
        updateSeparateColorControls(at: index)
        truncationPopup.selectItem(at: TabContentTruncation.allCases.firstIndex(of: line.style.truncation) ?? 0)
        // Text that wraps is always cut off at its end.
        truncationPopup.isEnabled = line.slot.maximumLines == 1
        collapseCheckbox.state = line.style.collapsesWhenEmpty ? .on : .off
        formatPopup.selectItem(at: line.style.html ? 1 : 0)
        resetButton.isEnabled = model.isCustomized(at: index)
    }

    // Only a custom color can have a second color for dark mode.
    private func updateSeparateColorControls(at index: Int) {
        guard case .custom = model.colorChoice(at: index) else {
            separateColorsCheckbox.isEnabled = false
            separateColorsCheckbox.state = .off
            darkColorWell.isEnabled = false
            showSeparateColors(false)
            return
        }
        let separate = model.usesSeparateColors(at: index)
        separateColorsCheckbox.isEnabled = true
        separateColorsCheckbox.state = separate ? .on : .off
        if separate {
            // Without a readable dark color, the light one draws in both.
            darkColorWell.color = model.darkColor(at: index) ?? colorWell.color
        }
        darkColorWell.isEnabled = separate
        showSeparateColors(separate)
    }

    private func showSeparateColors(_ show: Bool) {
        lightColorLabel.isHidden = !show
        darkColorLabel.isHidden = !show
        darkColorWell.isHidden = !show
    }

    // The well shows the color the line has, but only Custom can change it.
    private func showColorInDisabledWell(_ color: NSColor) {
        var converted = color
        (window?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            converted = color.usingColorSpace(NSColorSpace.it_default()) ?? color
        }
        colorWell.color = converted
        colorWell.isEnabled = false
    }

    private func scheduleChangeHandler() {
        guard changeHandler != nil, !changeHandlerScheduled else {
            return
        }
        changeHandlerScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.changeHandlerScheduled = false
            self.changeHandler?()
        }
    }

    // Shows only the lines within the limit, cut the way tabs cut them. The
    // height alone wouldn't do: an empty line within the limit collapses, and
    // a line past the limit would move up into its place. Every change to the
    // model ends here, so this also reports changes.
    private func updatePreview() {
        scheduleChangeHandler()
        let slots = model.layout.slots(limitedToLines: model.lineLimit)
        previewView.lines = zip(model.lines, slots).map { line, slot in
            PSMTabRichLine(text: TabContentEditorModel.previewText(for: line.style.text),
                           scale: line.slot.size.scale,
                           bold: line.style.bold,
                           italic: line.style.italic,
                           color: line.style.color,
                           darkColor: line.style.darkColor,
                           secondary: line.style.secondary,
                           lineBreakMode: line.style.truncation.lineBreakMode,
                           collapsesWhenEmpty: line.style.collapsesWhenEmpty,
                           maximumLines: slot.maximumLines,
                           html: line.style.html,
                           spacingAfter: TabContentSlot.spacingAfter(identifier: line.slot.identifier))
        }
        let height = TabContentSettings.requiredHeight(layout: model.layout,
                                                       maximumLines: model.lineLimit,
                                                       baseFontSize: TabContentSettings.defaultFontSize)
        if previewView.height != height {
            previewView.height = height
            scheduleWindowFit()
        }
    }

    private func refreshSelectedRow() {
        guard let index = selectedIndex else {
            return
        }
        tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
    }

    // MARK: - Actions

    // Ends editing, committing a number being typed to the line it was typed
    // for, before something changes which line is selected.
    func commitPendingEdits() {
        // Only while a field is being edited, so the line list keeps its
        // focus otherwise.
        guard let window, window.firstResponder is NSText else {
            return
        }
        window.makeFirstResponder(nil)
    }

    @objc private func addOrRemove(_ sender: NSSegmentedControl) {
        commitPendingEdits()
        if sender.selectedSegment == 0 {
            showAddMenu(sender)
        } else if let index = selectedIndex {
            remove(at: index)
        }
    }

    private func showAddMenu(_ sender: NSSegmentedControl) {
        makeAddMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
    }

    // Every preset, in groups, then Custom Line. A preset already in the
    // layout is shown but turned off (see validateMenuItem).
    func makeAddMenu() -> NSMenu {
        let menu = NSMenu()
        for group in TabContentEditorModel.presetGroups {
            for identifier in group {
                let item = NSMenuItem(title: TabContentEditorModel.displayName(for: identifier),
                                      action: #selector(addBuiltIn(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = identifier
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let custom = NSMenuItem(title: String(localized: "TabContentEditor.AddCustom",
                                              defaultValue: "Custom Line",
                                              comment: "Menu item that adds a tab content line with text the user writes"),
                                action: #selector(addCustom(_:)),
                                keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)
        return menu
    }

    @objc private func addBuiltIn(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else {
            return
        }
        model.addBuiltIn(identifier)
        reload(selecting: model.layout.slots.count - 1)
    }

    @objc private func addCustom(_ sender: Any?) {
        let index = model.addCustom()
        reload(selecting: index)
        window?.makeFirstResponder(textField)
    }

    private func remove(at index: Int) {
        model.remove(at: index)
        reload(selecting: min(index, model.layout.slots.count - 1))
    }

    @objc private func sizeDidChange(_ sender: NSPopUpButton) {
        guard let index = selectedIndex, sender.indexOfSelectedItem >= 0 else {
            return
        }
        model.setSize(TabContentLineSize.allCases[sender.indexOfSelectedItem], at: index)
        updateEditor()
    }

    @objc private func linesDidChange(_ sender: NumberStepperField) {
        guard let index = selectedIndex else {
            return
        }
        model.setMaximumLines(sender.value, at: index)
        updateEditor()
    }

    @objc private func lineLimitCheckboxDidChange(_ sender: NSButton) {
        model.setLineLimit(sender.state == .on ? lineLimitField.value : nil)
        updateEditor()
    }

    @objc private func lineLimitFieldDidChange(_ sender: NumberStepperField) {
        guard lineLimitCheckbox.state == .on else {
            return
        }
        model.setLineLimit(sender.value)
        updateEditor()
    }

    @objc private func boldDidChange(_ sender: NSButton) {
        guard let index = selectedIndex else {
            return
        }
        model.setBold(sender.state == .on, at: index)
        updateEditor()
    }

    @objc private func italicDidChange(_ sender: NSButton) {
        guard let index = selectedIndex else {
            return
        }
        model.setItalic(sender.state == .on, at: index)
        updateEditor()
    }

    @objc private func colorChoiceDidChange(_ sender: NSPopUpButton) {
        guard let index = selectedIndex else {
            return
        }
        switch sender.indexOfSelectedItem {
        case 0:
            model.setColorChoice(.normal, at: index)
        case 1:
            model.setColorChoice(.secondary, at: index)
        default:
            // Start from the color the line has now.
            let style = model.lines[index].style
            let current = style.color ?? (style.secondary ? NSColor.secondaryLabelColor : NSColor.labelColor)
            // In the app's color space, which the picker then uses.
            var converted = current
            (window?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
                converted = current.usingColorSpace(NSColorSpace.it_default()) ?? current
            }
            colorWell.color = converted
            model.setColorChoice(.custom(converted), at: index)
        }
        updateEditor()
    }

    @objc private func colorWellDidChange(_ sender: CPKColorWell) {
        // A color dropped on a disabled well, or sent by a color panel left
        // open, must not turn the line Custom.
        guard let index = selectedIndex else {
            return
        }
        guard sender.isEnabled, case .custom = model.colorChoice(at: index), let color = sender.color else {
            // The well already shows the rejected color. Show the line's.
            updateEditor()
            return
        }
        model.setColorChoice(.custom(color), at: index)
        // Not updateEditor(), which would set the well's color back while its
        // picker is open, fighting the picker over the color space.
        resetButton.isEnabled = model.isCustomized(at: index)
        updatePreview()
        refreshSelectedRow()
    }

    @objc private func separateColorsDidChange(_ sender: NSButton) {
        guard let index = selectedIndex else {
            return
        }
        model.setUsesSeparateColors(sender.state == .on, at: index)
        updateEditor()
    }

    @objc private func darkColorWellDidChange(_ sender: CPKColorWell) {
        guard let index = selectedIndex else {
            return
        }
        // As for the light well: ignore a color sent while the well is off.
        guard sender.isEnabled, model.usesSeparateColors(at: index), let color = sender.color else {
            updateEditor()
            return
        }
        model.setDarkColor(color, at: index)
        // Not updateEditor(), for the same reason as colorWellDidChange.
        resetButton.isEnabled = model.isCustomized(at: index)
        updatePreview()
        refreshSelectedRow()
    }

    @objc private func truncationDidChange(_ sender: NSPopUpButton) {
        guard let index = selectedIndex, sender.indexOfSelectedItem >= 0 else {
            return
        }
        model.setTruncation(TabContentTruncation.allCases[sender.indexOfSelectedItem], at: index)
        updateEditor()
    }

    @objc private func formatDidChange(_ sender: NSPopUpButton) {
        guard let index = selectedIndex else {
            return
        }
        model.setHTML(sender.indexOfSelectedItem == 1, at: index)
        updateEditor()
    }

    @objc private func collapseDidChange(_ sender: NSButton) {
        guard let index = selectedIndex else {
            return
        }
        model.setCollapsesWhenEmpty(sender.state == .on, at: index)
        updateEditor()
    }

    @objc private func reset(_ sender: Any?) {
        guard let index = selectedIndex else {
            return
        }
        model.reset(at: index)
        abortEditingLineFields()
        updateEditor()
        refreshSelectedRow()
    }

    @objc private func ok(_ sender: Any?) {
        // Every keystroke is already in the model. This just ends editing.
        window?.makeFirstResponder(nil)
        end(.OK)
    }

    @objc private func cancel(_ sender: Any?) {
        end(.cancel)
    }

    private func end(_ response: NSApplication.ModalResponse) {
        guard let window else {
            return
        }
        // The owner takes it from here: it applies the values on OK and puts
        // the old ones back on Cancel.
        changeHandler = nil
        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: response)
        } else {
            window.close()
        }
    }
}

extension TabContentEditorWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(addBuiltIn(_:)), let identifier = menuItem.representedObject as? String {
            return model.availableBuiltIns.contains(identifier)
        }
        return true
    }
}

// MARK: - Text field

extension TabContentEditorWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let index = selectedIndex, (obj.object as? NSTextField) === textField else {
            return
        }
        model.setText(textField.stringValue, at: index)
        resetButton.isEnabled = model.isCustomized(at: index)
        updatePreview()
        refreshSelectedRow()
    }
}

// MARK: - Line list

extension TabContentEditorWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return model.layout.slots.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let line = model.lines[row]
        let title = NSTextField(labelWithString: TabContentEditorModel.displayName(for: line.slot.identifier))
        title.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: line.style.text)
        detail.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        for view in [title, detail] {
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        abortEditingLineFields()
        updateEditor()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowDragType)
        return item
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === tableView else {
            return []
        }
        if dropOperation == .on {
            tableView.setDropRow(row, dropOperation: .above)
        }
        return .move
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let string = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.rowDragType),
              let from = Int(string),
              from >= 0, from < model.layout.slots.count else {
            return false
        }
        // row is the gap to drop into, counted before the dragged row is removed.
        let to = from < row ? row - 1 : row
        guard to != from else {
            return false
        }
        model.move(from: from, to: to)
        reload(selecting: to)
        return true
    }
}

// Draws a mock tab showing the lines with sample values.
final class TabContentPreviewView: NSView {
    var lines = [PSMTabRichLine]() {
        didSet { needsDisplay = true }
    }
    var height: CGFloat = 0 {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        PSMTabRichContentRenderer.draw(lines: lines,
                                       in: bounds.insetBy(dx: 10, dy: 0),
                                       baseFont: NSFont.systemFont(ofSize: TabContentSettings.defaultFontSize),
                                       textColor: .labelColor,
                                       secondaryColor: .secondaryLabelColor,
                                       alignment: .left)
    }
}
