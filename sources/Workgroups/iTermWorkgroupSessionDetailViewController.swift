//
//  iTermWorkgroupSessionDetailViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import AppKit

// Deepest settings pane: configures one session within the selected
// workgroup.
//
// Every subview is created with translatesAutoresizingMaskIntoConstraints
// = false and no autoresizingMask. All frames are computed fresh in
// viewDidLayout from the current view.bounds — so nothing in here ever
// ends up as a stale NSAutoresizingMaskLayoutConstraint that could
// conflict with the container's auto layout.
//
// Sections: each logical group (profile, command/URL, kind-specific,
// toolbar items) is its own container NSView. Only the ones relevant to
// the selected session are shown, and refresh() stacks them top-down so
// hidden ones don't leave a band of dead space.
//
// The toolbar items area lists the items actually in the session's
// toolbar (duplicates allowed — two spacers, for example). An add menu
// picks from the registry, a remove button is blocked for the
// always-required mode switcher on a root with peers, and an inline
// parameter editor appears below when a parameterized item (today just
// spacer) is selected.
@objc(iTermWorkgroupSessionDetailViewController)
class iTermWorkgroupSessionDetailViewController: NSViewController {
    weak var parentDetail: iTermWorkgroupDetailViewController?

    private var session: iTermWorkgroupSessionConfig?
    private var workgroup: iTermWorkgroup?

    // Sections
    private var profileRow: NSView!
    private var modeRow: NSView!
    private var commandRow: NSView!
    private var perFileCommandRow: NSView!
    private var urlRow: NSView!
    private var peerRow: NSView!
    private var splitSection: NSView!
    private var toolbarSection: NSView!
    private var emptyLabel: NSTextField!

    // Controls
    private var profilePopup: NSPopUpButton!
    private var modePopup: NSPopUpButton!
    private var commandField: NSTextField!
    private var perFileCommandField: NSTextField!
    private var urlField: NSTextField!
    private var peerNameField: NSTextField!

    private var splitOrientationPicker: NSSegmentedControl!
    private var splitSidePicker: NSSegmentedControl!
    private var splitLocationSlider: NSSlider!
    private var splitLocationReadout: NSTextField!

    private var toolbarHeaderLabel: NSTextField!
    private var toolbarTable: NSTableView!
    private var toolbarScroll: NSScrollView!
    private var toolbarSegmented: NSSegmentedControl!
    private var toolbarParamContainer: NSView!

    private var spacerMinField: NSTextField!
    private var spacerMaxField: NSTextField!

    // Full-bleed layout — no left/right inset inside this controller's
    // views. The enclosing detail controller already provides whatever
    // margin is appropriate.
    private let margin: CGFloat = 0
    private let rowHeight: CGFloat = 22
    private let rowSpacing: CGFloat = 6
    private let labelGutter: CGFloat = 100

    private let splitLocationMin = 0.2
    private let splitLocationMax = 0.8

    // MARK: - loadView

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))

        emptyLabel = NSTextField(labelWithString: "No session selected.")
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        root.addSubview(emptyLabel)

        profileRow = makeLabeledRow(labelText: "Profile:",
                                    control: makeProfilePopup())
        modeRow = makeLabeledRow(labelText: "Mode:",
                                 control: makeModePopup())
        commandRow = makeLabeledRow(labelText: "Command:",
                                    control: makeCommandField())
        perFileCommandRow = makeLabeledRow(
            labelText: "File command:",
            control: makePerFileCommandField())
        urlRow = makeLabeledRow(labelText: "URL:", control: makeURLField())
        peerRow = makeLabeledRow(labelText: "Name:",
                                 control: makePeerNameField())
        splitSection = makeSplitSection()
        toolbarSection = makeToolbarSection()

        for section in [profileRow, modeRow, commandRow, perFileCommandRow,
                        urlRow, peerRow,
                        splitSection, toolbarSection] as [NSView] {
            root.addSubview(section)
        }

        self.view = root
        populateProfilePopup()
        load(session: nil, in: nil)
    }

    // MARK: - Section builders (no frames set here — all layout happens in
    // viewDidLayout / refresh).

    private func makeLabeledRow(labelText: String, control: NSView) -> NSView {
        let row = NSView(frame: .zero)

        let label = NSTextField(labelWithString: labelText)
        label.sizeToFit()
        row.addSubview(label)
        row.addSubview(control)

        // Tag for layout to know which is which.
        row.identifier = NSUserInterfaceItemIdentifier("labeledRow")
        // Remember the label on the row via its subviews order — first
        // label, second control — so laying it out later is easy.
        return row
    }

    private func makeProfilePopup() -> NSView {
        let popup = NSPopUpButton(frame: .zero)
        popup.target = self
        popup.action = #selector(profileChanged(_:))
        profilePopup = popup
        return popup
    }

    private func makeModePopup() -> NSView {
        let popup = NSPopUpButton(frame: .zero)
        for mode in iTermWorkgroupSessionMode.allCases {
            popup.addItem(withTitle: mode.localizedTitle)
            popup.lastItem?.representedObject = mode.rawValue
        }
        popup.target = self
        popup.action = #selector(modeChanged(_:))
        modePopup = popup
        return popup
    }

    private func makeCommandField() -> NSView {
        let field = NSTextField(frame: .zero)
        field.font = .userFixedPitchFont(ofSize: NSFont.systemFontSize)
        field.delegate = self
        commandField = field
        return field
    }

    // The per-file command runs when the user picks a file from the
    // changedFileSelector toolbar item. `\(file)` is substituted with
    // the picked path before the command runs.
    private func makePerFileCommandField() -> NSView {
        let field = NSTextField(frame: .zero)
        field.font = .userFixedPitchFont(ofSize: NSFont.systemFontSize)
        field.delegate = self
        field.placeholderString = "git diff HEAD '\\(file)'"
        perFileCommandField = field
        return field
    }

    private func makeURLField() -> NSView {
        let field = NSTextField(frame: .zero)
        field.delegate = self
        urlField = field
        return field
    }

    private func makePeerNameField() -> NSView {
        let field = NSTextField(frame: .zero)
        field.delegate = self
        peerNameField = field
        return field
    }

    private func makeSplitSection() -> NSView {
        let section = NSView(frame: .zero)

        let splitLabel = NSTextField(labelWithString: "Split:")
        splitLabel.sizeToFit()
        splitLabel.identifier = NSUserInterfaceItemIdentifier("splitLabel")
        section.addSubview(splitLabel)

        let orientation: NSSegmentedControl
        if let verticalImage = NSImage(systemSymbolName: "square.split.2x1",
                                       accessibilityDescription: "Vertical"),
           let horizontalImage = NSImage(systemSymbolName: "square.split.1x2",
                                         accessibilityDescription: "Horizontal") {
            orientation = NSSegmentedControl(
                images: [verticalImage, horizontalImage],
                trackingMode: .selectOne,
                target: self,
                action: #selector(splitOrientationChanged(_:)))
        } else {
            orientation = NSSegmentedControl(
                labels: ["􀏠 Vertical", "􀕰 Horizontal"],
                trackingMode: .selectOne,
                target: self,
                action: #selector(splitOrientationChanged(_:)))
        }
        orientation.sizeToFit()
        splitOrientationPicker = orientation
        section.addSubview(orientation)

        let side = NSSegmentedControl(
            labels: ["Left", "Right"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(splitSideChanged(_:)))
        side.sizeToFit()
        splitSidePicker = side
        section.addSubview(side)

        let locationLabel = NSTextField(labelWithString: "Location:")
        locationLabel.sizeToFit()
        locationLabel.identifier = NSUserInterfaceItemIdentifier("locationLabel")
        section.addSubview(locationLabel)

        splitLocationSlider = NSSlider(
            value: 0.5,
            minValue: splitLocationMin,
            maxValue: splitLocationMax,
            target: self,
            action: #selector(splitLocationChanged(_:)))
        section.addSubview(splitLocationSlider)

        splitLocationReadout = NSTextField(labelWithString: "50%")
        splitLocationReadout.alignment = .right
        section.addSubview(splitLocationReadout)

        return section
    }

    private func makeToolbarSection() -> NSView {
        let section = NSView(frame: .zero)

        toolbarHeaderLabel = NSTextField(labelWithString: "Toolbar Items:")
        toolbarHeaderLabel.sizeToFit()
        section.addSubview(toolbarHeaderLabel)

        toolbarParamContainer = makeToolbarParamContainer()
        toolbarParamContainer.isHidden = true
        section.addSubview(toolbarParamContainer)

        toolbarSegmented = NSSegmentedControl(
            images: [
                NSImage(named: NSImage.addTemplateName) ?? NSImage(),
                NSImage(named: NSImage.removeTemplateName) ?? NSImage(),
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(toolbarSegmentClicked(_:)))
        toolbarSegmented.segmentStyle = .smallSquare
        toolbarSegmented.setEnabled(false, forSegment: 1)
        section.addSubview(toolbarSegmented)

        toolbarScroll = NSScrollView(frame: .zero)
        toolbarScroll.hasVerticalScroller = true
        toolbarScroll.borderType = .bezelBorder

        toolbarTable = NSTableView(frame: .zero)
        toolbarTable.headerView = nil
        toolbarTable.rowSizeStyle = .default
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        col.resizingMask = .autoresizingMask
        toolbarTable.addTableColumn(col)
        toolbarTable.registerForDraggedTypes([Self.toolbarRowDragType])
        // Intra-table reorder only — explicitly mark .move for local
        // drags and disable other operations so dragging out of the
        // table doesn't pretend to copy.
        toolbarTable.setDraggingSourceOperationMask(.move, forLocal: true)
        toolbarTable.setDraggingSourceOperationMask([], forLocal: false)
        toolbarTable.draggingDestinationFeedbackStyle = .gap
        toolbarTable.dataSource = self
        toolbarTable.delegate = self
        toolbarScroll.documentView = toolbarTable
        section.addSubview(toolbarScroll)

        return section
    }

    private func makeToolbarParamContainer() -> NSView {
        let container = NSView(frame: .zero)

        let minLabel = NSTextField(labelWithString: "Min width:")
        minLabel.sizeToFit()
        minLabel.identifier = NSUserInterfaceItemIdentifier("minLabel")
        container.addSubview(minLabel)

        let minField = NSTextField(frame: .zero)
        minField.delegate = self
        spacerMinField = minField
        container.addSubview(minField)

        let maxLabel = NSTextField(labelWithString: "Max width:")
        maxLabel.sizeToFit()
        maxLabel.identifier = NSUserInterfaceItemIdentifier("maxLabel")
        container.addSubview(maxLabel)

        let maxField = NSTextField(frame: .zero)
        maxField.delegate = self
        spacerMaxField = maxField
        container.addSubview(maxField)

        return container
    }

    // MARK: - Layout

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutAll()
    }

    private func layoutAll() {
        let bounds = view.bounds

        // Empty state.
        let emptySize = emptyLabel.fittingSize
        emptyLabel.frame = NSRect(x: 0,
                                  y: bounds.midY - emptySize.height / 2,
                                  width: bounds.width,
                                  height: emptySize.height)
        if !emptyLabel.isHidden {
            return
        }

        // Lay out the sections based on their current visibility.
        var y = bounds.height

        func layoutSection(_ section: NSView, height: CGFloat) {
            guard !section.isHidden else { return }
            y -= height
            section.frame = NSRect(x: 0, y: y, width: bounds.width, height: height)
            y -= rowSpacing
        }

        layoutSection(profileRow, height: rowHeight)
        layoutSection(modeRow, height: rowHeight)
        layoutSection(commandRow, height: rowHeight)
        layoutSection(perFileCommandRow, height: rowHeight)
        layoutSection(urlRow, height: rowHeight)
        layoutSection(peerRow, height: rowHeight)
        layoutSection(splitSection, height: 2 * rowHeight + rowSpacing)

        // Toolbar section fills the remaining vertical space (down to the
        // bottom margin).
        let toolbarBottom: CGFloat = 0
        let toolbarHeight = max(120, y - toolbarBottom)
        toolbarSection.frame = NSRect(x: 0, y: toolbarBottom,
                                      width: bounds.width,
                                      height: toolbarHeight)

        // Inner layout of each section.
        layoutLabeledRow(profileRow)
        layoutLabeledRow(modeRow)
        layoutLabeledRow(commandRow)
        layoutLabeledRow(perFileCommandRow)
        layoutLabeledRow(urlRow)
        layoutLabeledRow(peerRow)
        layoutSplitSection()
        layoutToolbarSubsections()
    }

    // Labeled row: label on left, control on right.
    private func layoutLabeledRow(_ row: NSView) {
        guard !row.isHidden, row.subviews.count >= 2 else { return }
        let label = row.subviews[0] as? NSTextField
        let control = row.subviews[1]
        let h = row.bounds.height
        label?.frame.origin = NSPoint(x: margin, y: (h - (label?.frame.height ?? 17)) / 2)
        control.frame = NSRect(x: labelGutter,
                               y: 0,
                               width: max(0, row.bounds.width - labelGutter - margin),
                               height: h)
    }

    private func layoutSplitSection() {
        guard !splitSection.isHidden else { return }
        let h = splitSection.bounds.height
        let w = splitSection.bounds.width

        // Row 1 (top): Split: [orientation] [side]
        let row1Top = h
        let row1Bottom = row1Top - rowHeight

        guard let splitLabel = splitSection.subviews.first(where: {
            $0.identifier?.rawValue == "splitLabel"
        }) as? NSTextField else { return }
        splitLabel.frame.origin = NSPoint(
            x: margin,
            y: row1Bottom + (rowHeight - splitLabel.frame.height) / 2)

        splitOrientationPicker.frame = NSRect(
            x: labelGutter, y: row1Bottom,
            width: splitOrientationPicker.frame.width,
            height: rowHeight)

        splitSidePicker.frame = NSRect(
            x: splitOrientationPicker.frame.maxX + 8, y: row1Bottom,
            width: splitSidePicker.frame.width,
            height: rowHeight)

        // Row 2: Location: [slider] [readout]
        let row2Bottom = row1Bottom - rowSpacing - rowHeight
        guard let locationLabel = splitSection.subviews.first(where: {
            $0.identifier?.rawValue == "locationLabel"
        }) as? NSTextField else { return }
        locationLabel.frame.origin = NSPoint(
            x: margin,
            y: row2Bottom + (rowHeight - locationLabel.frame.height) / 2)

        let readoutWidth: CGFloat = 44
        splitLocationReadout.frame = NSRect(
            x: w - margin - readoutWidth,
            y: row2Bottom + (rowHeight - 17) / 2,
            width: readoutWidth, height: 17)
        splitLocationSlider.frame = NSRect(
            x: labelGutter, y: row2Bottom,
            width: max(0, w - labelGutter - margin - readoutWidth - 4),
            height: rowHeight)
    }

    private func layoutToolbarSubsections() {
        let w = toolbarSection.bounds.width
        let h = toolbarSection.bounds.height
        let headerH = toolbarHeaderLabel.fittingSize.height
        toolbarHeaderLabel.frame = NSRect(x: margin, y: h - headerH,
                                          width: max(0, w - 2 * margin),
                                          height: headerH)

        let paramVisible = !toolbarParamContainer.isHidden
        let paramH: CGFloat = paramVisible ? rowHeight : 0
        toolbarParamContainer.frame = NSRect(
            x: margin, y: 0, width: max(0, w - 2 * margin), height: paramH)

        let segH: CGFloat = 22
        let segSpacing: CGFloat = paramVisible ? rowSpacing : 0
        let segY = paramH + segSpacing
        toolbarSegmented.frame = NSRect(x: margin, y: segY,
                                        width: 60, height: segH)

        let tableBottom = segY + segH + 2
        let tableTop = (h - headerH) - 2
        toolbarScroll.frame = NSRect(x: margin, y: tableBottom,
                                     width: max(0, w - 2 * margin),
                                     height: max(40, tableTop - tableBottom))
        toolbarTable.tableColumns.first?.width =
            toolbarScroll.contentSize.width - 4

        layoutToolbarParamContainer()
    }

    private func layoutToolbarParamContainer() {
        guard !toolbarParamContainer.isHidden,
              let minLabel = toolbarParamContainer.subviews.first(where: {
                  $0.identifier?.rawValue == "minLabel"
              }) as? NSTextField,
              let maxLabel = toolbarParamContainer.subviews.first(where: {
                  $0.identifier?.rawValue == "maxLabel"
              }) as? NSTextField
        else { return }
        let h = toolbarParamContainer.bounds.height
        minLabel.frame.origin = NSPoint(x: 0, y: (h - minLabel.frame.height) / 2)
        spacerMinField.frame = NSRect(x: minLabel.frame.maxX + 4, y: 0,
                                      width: 60, height: h)
        maxLabel.frame.origin = NSPoint(x: spacerMinField.frame.maxX + 12,
                                        y: (h - maxLabel.frame.height) / 2)
        spacerMaxField.frame = NSRect(x: maxLabel.frame.maxX + 4, y: 0,
                                      width: 60, height: h)
    }

    // MARK: - Load

    func load(session: iTermWorkgroupSessionConfig?,
              in workgroup: iTermWorkgroup?) {
        if let current = self.session, let new = session,
           current == new,
           self.workgroup?.uniqueIdentifier == workgroup?.uniqueIdentifier {
            return
        }

        self.session = session
        self.workgroup = workgroup
        if session == nil || workgroup == nil {
            emptyLabel.isHidden = false
            [profileRow, modeRow, commandRow, perFileCommandRow, urlRow, peerRow,
             splitSection, toolbarSection].forEach { $0.isHidden = true }
            view.needsLayout = true
            return
        }
        emptyLabel.isHidden = true
        populateProfilePopup()
        refresh()
    }

    // MARK: - Refresh

    private func refresh() {
        guard let s = session else { return }

        syncProfilePopup(to: s)
        syncModePopup(to: s)
        commandField.stringValue = s.command
        perFileCommandField.stringValue = s.perFileCommand
        urlField.stringValue = s.urlString
        syncKindControls(to: s)

        // The main session already exists by the time the workgroup kicks
        // in, so it doesn't get a configurable profile or command/URL —
        // only its toolbar items are user-editable.
        let isRoot: Bool
        if case .root = s.kind { isRoot = true } else { isRoot = false }
        let isBrowser = resolvedProfileIsBrowser(for: s)
        profileRow.isHidden = isRoot
        // Browser sessions have no command, so the deferred-launch
        // / prompt-overlay path that .codeReview drives doesn't apply
        // — hide Mode there too.
        modeRow.isHidden = isRoot || isBrowser
        commandRow.isHidden = isRoot || isBrowser
        perFileCommandRow.isHidden = !shouldShowPerFileCommandRow(for: s)
        urlRow.isHidden = isRoot || !isBrowser
        // Every session is a potential peer-group leader (root and any
        // non-peer host can carry a peer group), so every kind gets an
        // editable display name. Required for .peer; for the others
        // it's the leader's own switcher label.
        peerRow.isHidden = false
        splitSection.isHidden = !(s.kind.isSplit)
        toolbarSection.isHidden = false

        view.needsLayout = true
        toolbarTable.reloadData()
        refreshToolbarParamUI()
        updateToolbarRemoveEnabled()
    }

    // MARK: - Value sync helpers

    private func syncProfilePopup(to s: iTermWorkgroupSessionConfig) {
        if let guid = s.profileGUID,
           let idx = profilePopup.itemArray.firstIndex(where: {
               ($0.representedObject as? String) == guid
           }) {
            profilePopup.selectItem(at: idx)
        } else {
            profilePopup.selectItem(at: 0)
        }
    }

    private func syncModePopup(to s: iTermWorkgroupSessionConfig) {
        let raw = s.mode.rawValue
        if let idx = modePopup.itemArray.firstIndex(where: {
            ($0.representedObject as? Int) == raw
        }) {
            modePopup.selectItem(at: idx)
        } else {
            modePopup.selectItem(at: 0)
        }
    }

    private func syncKindControls(to s: iTermWorkgroupSessionConfig) {
        // displayName drives the peer-group label regardless of kind, so
        // sync it whenever the row could be shown (peers and hosts).
        peerNameField.stringValue = s.displayName
        switch s.kind {
        case .root, .tab, .peer:
            break
        case .split(let settings):
            splitOrientationPicker.selectedSegment =
                settings.orientation == .vertical ? 0 : 1
            refreshSideLabels(for: settings.orientation)
            splitSidePicker.selectedSegment =
                settings.side == .leadingOrTop ? 0 : 1
            let clamped = min(max(settings.location, splitLocationMin),
                              splitLocationMax)
            splitLocationSlider.doubleValue = clamped
            updateLocationReadout(clamped)
        }
    }

    private func refreshSideLabels(for orientation: SplitSettings.Orientation) {
        if orientation == .vertical {
            splitSidePicker.setLabel("Left", forSegment: 0)
            splitSidePicker.setLabel("Right", forSegment: 1)
        } else {
            splitSidePicker.setLabel("Top", forSegment: 0)
            splitSidePicker.setLabel("Bottom", forSegment: 1)
        }
    }

    private func updateLocationReadout(_ value: Double) {
        let pct = Int((value * 100).rounded())
        splitLocationReadout.stringValue = "\(pct)%"
    }

    private func populateProfilePopup() {
        profilePopup.removeAllItems()
        profilePopup.addItem(withTitle: "Default")
        profilePopup.lastItem?.representedObject = NSNull()
        guard let model = ProfileModel.sharedInstance() else { return }
        for profile in model.bookmarks() {
            guard let dict = profile as? [String: Any],
                  let name = dict[KEY_NAME as String] as? String,
                  let guid = dict[KEY_GUID as String] as? String else { continue }
            profilePopup.addItem(withTitle: name)
            profilePopup.lastItem?.representedObject = guid
        }
    }

    private func resolvedProfileIsBrowser(for session: iTermWorkgroupSessionConfig) -> Bool {
        guard let model = ProfileModel.sharedInstance() else { return false }
        let profile: [AnyHashable: Any]?
        if let guid = session.profileGUID,
           let p = model.bookmark(withGuid: guid) {
            profile = p
        } else {
            profile = model.defaultBookmark()
        }
        guard let dict = profile,
              let customCommand = dict[KEY_CUSTOM_COMMAND as String] as? String
            else { return false }
        return customCommand == kProfilePreferenceCommandTypeBrowserValue
    }

    // MARK: - Control actions

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        guard var s = session else { return }
        s.profileGUID = sender.selectedItem?.representedObject as? String
        commitUpdate(s, actionName: "Change Profile") { [weak self] in
            self?.refresh()
        }
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard var s = session,
              let raw = sender.selectedItem?.representedObject as? Int,
              let mode = iTermWorkgroupSessionMode(rawValue: raw),
              s.mode != mode else { return }
        s.mode = mode
        commitUpdate(s, actionName: "Change Mode")
    }

    @objc private func splitOrientationChanged(_ sender: NSSegmentedControl) {
        guard var s = session,
              case .split(var settings) = s.kind else { return }
        settings.orientation = sender.selectedSegment == 0 ? .vertical : .horizontal
        refreshSideLabels(for: settings.orientation)
        s.kind = .split(settings)
        commitUpdate(s, actionName: "Change Orientation")
    }

    @objc private func splitSideChanged(_ sender: NSSegmentedControl) {
        guard var s = session,
              case .split(var settings) = s.kind else { return }
        settings.side = sender.selectedSegment == 0 ? .leadingOrTop : .trailingOrBottom
        s.kind = .split(settings)
        commitUpdate(s, actionName: "Change Side")
    }

    @objc private func splitLocationChanged(_ sender: NSSlider) {
        guard var s = session,
              case .split(var settings) = s.kind else { return }
        settings.location = min(max(sender.doubleValue, splitLocationMin),
                                splitLocationMax)
        updateLocationReadout(settings.location)
        s.kind = .split(settings)
        commitUpdate(s, actionName: "Change Split Location")
    }

    // Called by the detail VC while the user drags a divider in the
    // visual preview, so the slider + readout track the pointer without
    // committing to the model until mouseUp.
    func syncSplitLocation(_ location: Double, forSessionID sessionID: String) {
        guard let s = session,
              s.uniqueIdentifier == sessionID,
              case .split = s.kind else { return }
        splitLocationSlider.doubleValue = location
        updateLocationReadout(location)
    }

    // MARK: - Commit

    private func commitUpdate(_ updated: iTermWorkgroupSessionConfig,
                              actionName: String,
                              after: (() -> Void)? = nil) {
        session = updated
        parentDetail?.sessionDetail(self, didUpdate: updated,
                                    actionName: actionName)
        after?()
    }

    // MARK: - Toolbar items: data

    private var toolbarItems: [iTermWorkgroupToolbarItem] {
        return session?.toolbarItems ?? []
    }

    private var selectedToolbarRow: Int? {
        let r = toolbarTable.selectedRow
        return r >= 0 ? r : nil
    }

    private func refreshToolbarParamUI() {
        let wasHidden = toolbarParamContainer.isHidden
        defer {
            if wasHidden != toolbarParamContainer.isHidden {
                view.needsLayout = true
            }
        }
        guard let row = selectedToolbarRow,
              row < toolbarItems.count else {
            toolbarParamContainer.isHidden = true
            return
        }
        switch toolbarItems[row] {
        case .spacer(let minWidth, let maxWidth):
            toolbarParamContainer.isHidden = false
            spacerMinField.stringValue = formatWidth(minWidth)
            spacerMaxField.stringValue = formatWidth(maxWidth)
        default:
            toolbarParamContainer.isHidden = true
        }
    }

    private func formatWidth(_ value: CGFloat) -> String {
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", Double(value))
    }

    // MARK: - Toolbar items: actions

    @objc private func toolbarSegmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: showAddToolbarItemMenu()
        case 1: removeSelectedToolbarItem()
        default: break
        }
    }

    private func showAddToolbarItemMenu() {
        let menu = NSMenu()
        let hasChangedFileSelector = session?.toolbarItems.contains(where: {
            if case .changedFileSelector = $0 { return true }
            return false
        }) ?? false
        for metadata in iTermWorkgroupToolbarItemRegistry.all {
            // modeSwitcher is auto-managed by the peer-group invariant —
            // offering it in the add menu does nothing useful on a
            // session that has no peers, and it's already present on
            // ones that do.
            if metadata.kind == .modeSwitcher { continue }
            // Navigation buttons (back/forward/reload) only do
            // something useful when the session also has a changed-
            // file selector to step through; hide it from the picker
            // for sessions without one. Reload-on-its-own remains
            // available via the .reload item.
            if metadata.kind == .navigation && !hasChangedFileSelector {
                continue
            }
            let item = menu.addItem(withTitle: metadata.displayName,
                                    action: #selector(addToolbarItemMenuSelected(_:)),
                                    keyEquivalent: "")
            item.target = self
            item.representedObject = metadata.kind.rawValue
        }
        let origin = NSPoint(x: toolbarSegmented.frame.minX,
                             y: toolbarSegmented.frame.maxY + 2)
        menu.popUp(positioning: nil, at: origin, in: toolbarSegmented.superview)
    }

    @objc private func addToolbarItemMenuSelected(_ sender: NSMenuItem) {
        guard var s = session,
              let rawKind = sender.representedObject as? String,
              let kind = iTermWorkgroupToolbarItemKind(rawValue: rawKind),
              let metadata = iTermWorkgroupToolbarItemRegistry.metadata(forKind: kind)
            else { return }
        let insertAt = (selectedToolbarRow ?? (s.toolbarItems.count - 1)) + 1
        s.toolbarItems.insert(metadata.defaultValue, at: insertAt)
        commitUpdate(s, actionName: "Add Toolbar Item") { [weak self] in
            guard let self else { return }
            self.toolbarTable.reloadData()
            self.toolbarTable.selectRowIndexes(IndexSet(integer: insertAt),
                                               byExtendingSelection: false)
            self.refreshToolbarParamUI()
            self.refreshConditionalRowsVisibility()
        }
    }

    private func removeSelectedToolbarItem() {
        guard var s = session,
              let row = selectedToolbarRow,
              row < s.toolbarItems.count else { return }
        if isRequiredModeSwitcher(at: row, in: s) {
            NSSound.beep()
            return
        }
        s.toolbarItems.remove(at: row)
        commitUpdate(s, actionName: "Remove Toolbar Item") { [weak self] in
            guard let self else { return }
            self.toolbarTable.reloadData()
            self.refreshToolbarParamUI()
            self.refreshConditionalRowsVisibility()
        }
    }

    // Per-file command is only meaningful when the user actually has a
    // changedFileSelector in this session's toolbar — that's the only
    // thing that fires it. Browsers and the root never use it. Single
    // source of truth so toolbar mutations and the initial show()
    // don't drift apart.
    private func shouldShowPerFileCommandRow(for s: iTermWorkgroupSessionConfig) -> Bool {
        if case .root = s.kind { return false }
        if resolvedProfileIsBrowser(for: s) { return false }
        return s.toolbarItems.contains(where: {
            if case .changedFileSelector = $0 { return true }
            return false
        })
    }

    // Show/hide rows whose visibility depends on the current toolbar
    // contents. Cheaper than a full refresh() and doesn't clobber
    // other fields' in-progress edits.
    private func refreshConditionalRowsVisibility() {
        guard let s = session else { return }
        let shouldHide = !shouldShowPerFileCommandRow(for: s)
        if perFileCommandRow.isHidden != shouldHide {
            perFileCommandRow.isHidden = shouldHide
            view.needsLayout = true
        }
    }

    // A session is "in a peer group" if it's a peer itself, or if it
    // hosts peer children. Both cases need a display-name field so the
    // session has a label in the mode switcher.
    private func sessionIsInPeerGroup(_ s: iTermWorkgroupSessionConfig) -> Bool {
        if case .peer = s.kind { return true }
        guard let wg = workgroup else { return false }
        return wg.sessions.contains { child in
            guard child.parentID == s.uniqueIdentifier else { return false }
            if case .peer = child.kind { return true }
            return false
        }
    }

    private func isRequiredModeSwitcher(at row: Int,
                                        in s: iTermWorkgroupSessionConfig) -> Bool {
        guard row < s.toolbarItems.count,
              case .modeSwitcher = s.toolbarItems[row] else { return false }
        guard let wg = workgroup else { return false }
        // The "host" of the peer group is either this session (if it's a
        // non-peer that hosts peers) or its parent (if it's a peer itself).
        let hostID: String
        if case .peer = s.kind {
            guard let parentID = s.parentID else { return false }
            hostID = parentID
        } else {
            hostID = s.uniqueIdentifier
        }
        // Required iff host has at least one peer child.
        return wg.sessions.contains { child in
            guard child.parentID == hostID else { return false }
            if case .peer = child.kind { return true }
            return false
        }
    }
}

// MARK: - iTermWorkgroupSessionConfig.Kind introspection

extension iTermWorkgroupSessionConfig.Kind {
    var isPeer: Bool { if case .peer = self { return true } else { return false } }
    var isSplit: Bool { if case .split = self { return true } else { return false } }
}

// MARK: - Text-field delegate

extension iTermWorkgroupSessionDetailViewController: NSTextFieldDelegate {
    // Live updates: every keystroke in any of these fields is pushed to
    // the model so the user doesn't have to tab out to save. The
    // end-editing pass below still runs for finalization (e.g. peer
    // names get a non-empty default restored, spacer min/max get
    // applied as a pair).
    func controlTextDidChange(_ obj: Notification) {
        guard var s = session,
              let field = obj.object as? NSTextField else { return }
        switch field {
        case peerNameField:
            // Empty strings are allowed during typing — the end-editing
            // pass restores a default if the session is a peer.
            if s.displayName != field.stringValue {
                s.displayName = field.stringValue
                commitUpdate(s, actionName: "Rename Peer")
            }
        case commandField:
            if s.command != field.stringValue {
                s.command = field.stringValue
                commitUpdate(s, actionName: "Change Command")
            }
        case perFileCommandField:
            if s.perFileCommand != field.stringValue {
                s.perFileCommand = field.stringValue
                commitUpdate(s, actionName: "Change Per-File Command")
            }
        case urlField:
            if s.urlString != field.stringValue {
                s.urlString = field.stringValue
                commitUpdate(s, actionName: "Change URL")
            }
        default:
            break
        }
    }

    // End-editing handler runs the finalizers that don't make sense on
    // every keystroke: peer-name validation, spacer min/max coupling.
    // Commit-on-keystroke for command/url/perFileCommand happens in
    // controlTextDidChange above.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard var s = session,
              let field = obj.object as? NSTextField else { return }
        switch field {
        case peerNameField:
            let trimmed = field.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines)
            // For peer sessions, a blank name isn't allowed — restore a
            // unique default rather than let the group end up with an
            // unlabelled member.
            if trimmed.isEmpty, case .peer = s.kind {
                let replacement =
                    WorkgroupAnimalNames.pick(taken: takenNames(excluding: s))
                field.stringValue = replacement
                if s.displayName != replacement {
                    s.displayName = replacement
                    commitUpdate(s, actionName: "Rename Peer")
                }
                return
            }
            // Non-peer hosts may end with a blank name (falls back to
            // the kind-based default in the visual view).
            if s.displayName != trimmed {
                s.displayName = trimmed
                commitUpdate(s, actionName: "Rename Peer")
            }
        case spacerMinField, spacerMaxField:
            applySpacerEditIfNeeded()
        default:
            break
        }
    }

    // Every name currently used by a session in the workgroup other
    // than `ignoring` (so renaming-to-same doesn't count against us).
    private func takenNames(excluding ignoring: iTermWorkgroupSessionConfig) -> Set<String> {
        guard let wg = workgroup else { return [] }
        return Set(wg.sessions.compactMap { s -> String? in
            guard s.uniqueIdentifier != ignoring.uniqueIdentifier else {
                return nil
            }
            return s.displayName.isEmpty ? nil : s.displayName
        })
    }

    private func applySpacerEditIfNeeded() {
        guard var s = session,
              let row = selectedToolbarRow,
              row < s.toolbarItems.count,
              case .spacer(let currentMin, let currentMax) =
                s.toolbarItems[row] else { return }
        // Reject blank or non-numeric input — bounce the field back to
        // the previously-committed value instead of silently collapsing
        // to 0.
        guard let minValue = Double(spacerMinField.stringValue),
              let maxValue = Double(spacerMaxField.stringValue) else {
            spacerMinField.stringValue = formatWidth(currentMin)
            spacerMaxField.stringValue = formatWidth(currentMax)
            return
        }
        let minCG = CGFloat(minValue)
        let maxCG = max(minCG, CGFloat(maxValue))
        s.toolbarItems[row] = .spacer(minWidth: minCG, maxWidth: maxCG)
        commitUpdate(s, actionName: "Change Spacer Width") { [weak self] in
            guard let self else { return }
            self.toolbarTable.reloadData(
                forRowIndexes: IndexSet(integer: row),
                columnIndexes: IndexSet(integer: 0))
            self.refreshToolbarParamUI()
        }
    }
}

// MARK: - Toolbar items table

extension iTermWorkgroupSessionDetailViewController: NSTableViewDataSource, NSTableViewDelegate {
    // Pasteboard type for the toolbar table's intra-row reorder
    // drags. Internal-only — we do not advertise this to other apps.
    fileprivate static let toolbarRowDragType =
        NSPasteboard.PasteboardType("com.googlecode.iterm2.workgroupToolbarItem")

    func numberOfRows(in tableView: NSTableView) -> Int {
        guard tableView === toolbarTable else { return 0 }
        return toolbarItems.count
    }

    // MARK: - Drag-reorder

    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === toolbarTable else { return nil }
        let item = NSPasteboardItem()
        // We only need the source row index; the destination handler
        // reads it back below to perform the move on session.toolbarItems.
        item.setString(String(row), forType: Self.toolbarRowDragType)
        return item
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard tableView === toolbarTable,
              dropOperation == .above else {
            return []
        }
        return .move
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row destinationRow: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard tableView === toolbarTable,
              dropOperation == .above,
              var s = session else {
            return false
        }
        guard let sourceRow = info.draggingPasteboard.pasteboardItems?
                .compactMap({ $0.string(forType: Self.toolbarRowDragType) })
                .compactMap({ Int($0) })
                .first,
              sourceRow >= 0,
              sourceRow < s.toolbarItems.count else {
            return false
        }
        if sourceRow == destinationRow || sourceRow == destinationRow - 1 {
            // No-op moves: dropping a row onto its own current
            // location, or onto the gap immediately below itself.
            return false
        }
        let item = s.toolbarItems.remove(at: sourceRow)
        // After removal, an insertion index past the source row
        // shifts down by one.
        let insertAt = destinationRow > sourceRow ? destinationRow - 1 : destinationRow
        s.toolbarItems.insert(item, at: insertAt)
        commitUpdate(s, actionName: "Reorder Toolbar Item") { [weak self] in
            guard let self else { return }
            self.toolbarTable.reloadData()
            self.toolbarTable.selectRowIndexes(IndexSet(integer: insertAt),
                                               byExtendingSelection: false)
            self.refreshToolbarParamUI()
        }
        return true
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard tableView === toolbarTable,
              row < toolbarItems.count else { return nil }
        let item = toolbarItems[row]
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: displayName(for: item))
        text.translatesAutoresizingMaskIntoConstraints = true
        text.frame = NSRect(x: 4, y: 2, width: 200, height: 17)
        text.autoresizingMask = [.width]
        text.lineBreakMode = .byTruncatingTail
        cell.addSubview(text)
        cell.textField = text
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshToolbarParamUI()
        updateToolbarRemoveEnabled()
    }

    func updateToolbarRemoveEnabled() {
        toolbarSegmented.setEnabled(canRemoveSelectedToolbarItem, forSegment: 1)
    }

    // Match the guards inside removeSelectedToolbarItem so the button
    // stays disabled rather than beeping when pressed: nothing
    // selected, or the selected row is the required peer mode
    // switcher (peers need it to be reachable).
    private var canRemoveSelectedToolbarItem: Bool {
        guard let row = selectedToolbarRow,
              let s = session,
              row < s.toolbarItems.count else {
            return false
        }
        return !isRequiredModeSwitcher(at: row, in: s)
    }

    private func displayName(for item: iTermWorkgroupToolbarItem) -> String {
        let base = iTermWorkgroupToolbarItemRegistry.metadata(for: item)?.displayName
            ?? item.kind.rawValue
        switch item {
        case .spacer(let minWidth, let maxWidth):
            return "\(base) (\(formatWidth(minWidth))–\(formatWidth(maxWidth)) pt)"
        default:
            return base
        }
    }
}
