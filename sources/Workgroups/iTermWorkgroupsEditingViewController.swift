//
//  iTermWorkgroupsEditingViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import AppKit

// Left pane of the Workgroups settings tab: table of workgroups on the
// left, detail pane on the right. The root view is built programmatically
// (no xib) and inserted into the container view by
// defineControls(inContainerView:).
//
// Layout is fully manual: every subview we create has
// autoresizingMask, because this controller is embedded inside an
// auto-layout-hosting container (from the prefs xib). The old approach of
// letting AppKit translate autoresizingMask values into constraints
// produced conflicts whenever the initial frame we'd set in loadView
// didn't match the container's actual size. Instead, viewDidLayout
// recomputes frames every time the outer view resizes.
@objc(iTermWorkgroupsEditingViewController)
class iTermWorkgroupsEditingViewController: NSViewController {
    private let listColumnWidth: CGFloat = 180
    private let buttonStripHeight: CGFloat = 26
    private let margin: CGFloat = 8

    private var tableView: NSTableView!
    private var tableScroll: NSScrollView!
    private var segmented: NSSegmentedControl!
    private var presetPopup: NSPopUpButton!
    private var detailContainer: NSView!
    private var detailViewController: iTermWorkgroupDetailViewController!

    private var workgroups: [iTermWorkgroup] = []

    override var nibName: NSNib.Name? { return nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))

        tableScroll = NSScrollView(frame: .zero)
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder

        tableView = NSTableView(frame: .zero)
        tableView.headerView = nil
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.rowSizeStyle = .default
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Name"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        tableScroll.documentView = tableView
        root.addSubview(tableScroll)

        segmented = NSSegmentedControl(
            images: [
                NSImage(named: NSImage.addTemplateName) ?? NSImage(),
                NSImage(named: NSImage.removeTemplateName) ?? NSImage(),
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(segmentClicked(_:)))
        segmented.segmentStyle = .smallSquare
        segmented.setEnabled(false, forSegment: 1)
        root.addSubview(segmented)

        // "Add Preset" pull-down button. First menu item is the button's
        // title (pull-down convention); subsequent items are the presets.
        presetPopup = NSPopUpButton(frame: .zero, pullsDown: true)
        presetPopup.bezelStyle = .rounded
        presetPopup.controlSize = .regular
        let titleItem = NSMenuItem(title: "Add Preset",
                                   action: nil, keyEquivalent: "")
        presetPopup.menu?.addItem(titleItem)
        for preset in WorkgroupPresets.all {
            let item = NSMenuItem(title: preset.displayName,
                                  action: #selector(presetMenuSelected(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = preset.identifier
            presetPopup.menu?.addItem(item)
        }
        presetPopup.sizeToFit()
        root.addSubview(presetPopup)

        detailContainer = NSView(frame: .zero)
        root.addSubview(detailContainer)

        detailViewController = iTermWorkgroupDetailViewController()
        detailViewController.parentEditor = self
        detailContainer.addSubview(detailViewController.view)

        self.view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutAll()
    }

    private func layoutAll() {
        let bounds = view.bounds
        let segmentedWidth: CGFloat = 60
        let detailX = margin + listColumnWidth + margin

        // Left column: shift the whole column 3pt down so the table ends
        // up 3pt taller (its top stays at the top margin; its bottom and
        // the segmented strip below it both move 3pt closer to the
        // container's bottom edge).
        let leftColumnBottom = margin - 3
        let tableBottomGap: CGFloat = 2
        segmented.frame = NSRect(
            x: margin, y: leftColumnBottom,
            width: segmentedWidth, height: buttonStripHeight)
        let presetSize = presetPopup.fittingSize
        presetPopup.frame = NSRect(
            x: segmented.frame.maxX + 4,
            y: leftColumnBottom,
            width: presetSize.width,
            height: buttonStripHeight)
        let tableY = leftColumnBottom + buttonStripHeight + tableBottomGap
        tableScroll.frame = NSRect(
            x: margin,
            y: tableY,
            width: listColumnWidth,
            height: max(0, bounds.height - margin - tableY))

        detailContainer.frame = NSRect(
            x: detailX,
            y: margin,
            width: max(0, bounds.width - detailX - margin),
            height: max(0, bounds.height - 2 * margin))
        detailViewController.view.frame = detailContainer.bounds
        // Table column width follows the scroll view.
        tableView.tableColumns.first?.width =
            tableScroll.contentSize.width - 4
    }

    @objc(defineControlsInContainerView:)
    func defineControls(inContainerView containerView: NSView) {
        containerView.addSubview(view)
        view.frame = containerView.bounds
        view.autoresizingMask = [.width, .height]

        refreshFromModel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelDidChange(_:)),
            name: iTermWorkgroupModel.didChangeNotification,
            object: nil)
    }

    // MARK: - Model / selection

    @objc private func modelDidChange(_ note: Notification) {
        refreshFromModel()
    }

    private func refreshFromModel() {
        let previousSelected = selectedWorkgroupID
        workgroups = iTermWorkgroupModel.instance.workgroups
        tableView.reloadData()
        if let id = previousSelected,
           let idx = workgroups.firstIndex(where: { $0.uniqueIdentifier == id }) {
            tableView.selectRowIndexes(IndexSet(integer: idx),
                                       byExtendingSelection: false)
        }
        updateButtons()
        updateDetail()
    }

    private var selectedWorkgroupID: String? {
        let row = tableView.selectedRow
        guard row >= 0, row < workgroups.count else { return nil }
        return workgroups[row].uniqueIdentifier
    }

    private func updateButtons() {
        segmented.setEnabled(tableView.selectedRow >= 0, forSegment: 1)
    }

    private func updateDetail() {
        if let id = selectedWorkgroupID,
           let wg = iTermWorkgroupModel.instance.workgroup(uniqueIdentifier: id) {
            detailViewController.load(workgroup: wg)
        } else {
            detailViewController.load(workgroup: nil)
        }
    }

    @objc private func segmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: addWorkgroup()
        case 1: removeWorkgroup()
        default: break
        }
    }

    private func addWorkgroup() {
        pushUndo()
        let wg = iTermWorkgroup.newEmpty(name: "Untitled Workgroup")
        iTermWorkgroupModel.instance.add(wg)
        if let idx = iTermWorkgroupModel.instance.workgroups.firstIndex(where: {
            $0.uniqueIdentifier == wg.uniqueIdentifier
        }) {
            tableView.selectRowIndexes(IndexSet(integer: idx),
                                       byExtendingSelection: false)
        }
    }

    @objc private func presetMenuSelected(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = WorkgroupPresets.all.first(where: {
                  $0.identifier == id
              }) else { return }
        pushUndo()
        let wg = preset.build()
        iTermWorkgroupModel.instance.add(wg)
        if let idx = iTermWorkgroupModel.instance.workgroups.firstIndex(where: {
            $0.uniqueIdentifier == wg.uniqueIdentifier
        }) {
            tableView.selectRowIndexes(IndexSet(integer: idx),
                                       byExtendingSelection: false)
        }
    }

    private func removeWorkgroup() {
        guard let id = selectedWorkgroupID else { return }
        pushUndo()
        iTermWorkgroupModel.instance.remove(uniqueIdentifier: id)
    }

    func pushUndo() {
        let snapshot = iTermWorkgroupModel.instance.workgroups
        view.window?.undoManager?.registerUndo(withTarget: self) { target in
            target.pushUndo()
            iTermWorkgroupModel.instance.setAll(snapshot)
        }
        view.window?.undoManager?.setActionName("Change Workgroups")
    }

    func replaceSelectedWorkgroup(_ updated: iTermWorkgroup,
                                  actionName: String) {
        pushUndo()
        iTermWorkgroupModel.instance.replace(
            uniqueIdentifier: updated.uniqueIdentifier,
            with: updated)
        view.window?.undoManager?.setActionName(actionName)
    }
}

extension iTermWorkgroupsEditingViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return workgroups.count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("WorkgroupCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier,
                                           owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            cell.addSubview(text)
            cell.textField = text
            // Inside a table cell, AppKit positions via the cell's own
            // autoresizing — so we do need a frame here. It's fine
            // because the cell is a leaf we don't re-layout manually.
            text.frame = NSRect(x: 4, y: 2, width: 160, height: 17)
            text.autoresizingMask = [.width]
            text.translatesAutoresizingMaskIntoConstraints = true
            text.lineBreakMode = .byTruncatingTail
        }
        cell.textField?.stringValue = workgroups[row].name
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        updateDetail()
    }
}
