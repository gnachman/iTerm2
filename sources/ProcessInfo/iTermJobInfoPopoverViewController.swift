//
//  iTermJobInfoPopoverViewController.swift
//  iTerm2SharedARC
//
//  Content for the popover shown when the user presses space (or clicks the
//  inspect button) on a job. Shows the full (untruncated) command plus whatever
//  else we can glean about the process: pid, start time, current working
//  directory (fetched asynchronously), environment variables, and open files
//  and sockets.
//

import AppKit

// The popover's flipped content view. The popover owns its frame, so children
// are re-laid-out from the view's actual bounds whenever it resizes; otherwise
// they end up pinned to a corner when preferredContentSize changes.
private class iTermJobInfoContentView: iTermFlippedView {
    weak var controller: iTermJobInfoPopoverViewController?

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        controller?.relayout(forWidth: bounds.width)
    }
}

@objc(iTermJobInfoPopoverViewController)
class iTermJobInfoPopoverViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let pid: pid_t
    private let fullCommand: String

    private var topFields: [NSTextField] = []
    private var commandValue: NSTextField!
    private var directoryValue: NSTextField!
    private var pidValue: NSTextField!
    private var startedValue: NSTextField!
    private var copyCommandButton: NSButton!
    private var copyDirectoryButton: NSButton!
    private var copyPidButton: NSButton!
    private var workingDirectory: String?
    private var startTime: Date?
    private var startTimeFetched = false
    private var clockTimer: Timer?
    private var environmentHeader: NSTextField!
    private var environmentScrollView: NSScrollView!
    private var environmentTableView: NSTableView!
    private var environment: [(key: String, value: String)] = []
    private var fileDescriptorHeader: NSTextField!
    private var fileDescriptorScrollView: NSScrollView!
    private var fileDescriptorTableView: NSTableView!
    private var fileDescriptors: [iTermProcessFileDescriptor] = []
    private let pwdQueue = DispatchQueue(label: "com.iterm2.jobinfo.pwd")

    private let popoverWidth: CGFloat = 460
    private let inset: CGFloat = 14
    private let sectionGap: CGFloat = 12
    private let headerGap: CGFloat = 2
    private let tableHeight: CGFloat = 170

    @objc init(pid: pid_t, fullCommand: String) {
        self.pid = pid
        self.fullCommand = fullCommand
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func loadView() {
        let view = iTermJobInfoContentView(frame: NSRect(x: 0, y: 0, width: popoverWidth, height: 100))
        view.controller = self
        view.autoresizingMask = [.width, .height]

        let commandHeader = Self.headerLabel("Command")
        commandValue = Self.valueLabel(fullCommand, wrapping: true)

        let directoryHeader = Self.headerLabel("Working Directory")
        directoryValue = Self.valueLabel("Loading…", wrapping: true)

        let pidHeader = Self.headerLabel("Process ID")
        pidValue = Self.valueLabel("\(pid)", wrapping: false)

        let startedHeader = Self.headerLabel("Started")
        startedValue = Self.valueLabel(startedDescription(), wrapping: false)

        topFields = [commandHeader, commandValue, directoryHeader, directoryValue,
                     pidHeader, pidValue, startedHeader, startedValue]
        for field in topFields {
            view.addSubview(field)
        }

        copyCommandButton = copyButton(action: #selector(copyCommand(_:)))
        view.addSubview(copyCommandButton)
        copyDirectoryButton = copyButton(action: #selector(copyDirectory(_:)))
        copyDirectoryButton.isEnabled = false
        view.addSubview(copyDirectoryButton)
        copyPidButton = copyButton(action: #selector(copyPid(_:)))
        view.addSubview(copyPidButton)

        loadEnvironment()
        loadFileDescriptors()

        environmentHeader = Self.headerLabel("Environment")
        view.addSubview(environmentHeader)
        (environmentScrollView, environmentTableView) =
            makeTableScrollView(columns: [(identifier: "key", title: "Variable", width: 130),
                                          (identifier: "value", title: "Value", width: 0)])
        view.addSubview(environmentScrollView)

        fileDescriptorHeader = Self.headerLabel("Open Files & Sockets")
        view.addSubview(fileDescriptorHeader)
        (fileDescriptorScrollView, fileDescriptorTableView) =
            makeTableScrollView(columns: [(identifier: "fd", title: "FD", width: 36),
                                          (identifier: "type", title: "Type", width: 58),
                                          (identifier: "detail", title: "Detail", width: 0)])
        view.addSubview(fileDescriptorScrollView)

        self.view = view
        environmentTableView.reloadData()
        fileDescriptorTableView.reloadData()
        relayout(forWidth: popoverWidth)
        fetchWorkingDirectory()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Keep the relative "Started" time current while the popover is open.
        if clockTimer == nil {
            clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateStartedValue()
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        clockTimer?.invalidate()
        clockTimer = nil
    }

    private func updateStartedValue() {
        startedValue.stringValue = startedDescription()
    }

    // MARK: - Subview factories

    private static func headerLabel(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string.uppercased())
        label.font = .boldSystemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func valueLabel(_ string: String, wrapping: Bool) -> NSTextField {
        let value = wrapping ? NSTextField(wrappingLabelWithString: string)
                             : NSTextField(labelWithString: string)
        value.font = .systemFont(ofSize: 12)
        value.isSelectable = true
        return value
    }

    private func copyButton(action: Selector) -> NSButton {
        let image = NSImage.it_image(forSymbolName: SFSymbol.docOnDoc.rawValue,
                                     accessibilityDescription: "Copy") ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Copy"
        // Clicking the button should not steal first responder (the popover
        // stays keyed off the outline view / space bar).
        button.refusesFirstResponder = true
        button.focusRingType = .none
        return button
    }

    // Builds a bordered scroll view wrapping a view-based table. A column width
    // of 0 means the column autoresizes to fill remaining space (it must be the
    // last column).
    private func makeTableScrollView(columns: [(identifier: String, title: String, width: CGFloat)]) -> (NSScrollView, NSTableView) {
        let tableView = NSTableView(frame: .zero)
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 16
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.identifier))
            tableColumn.title = column.title
            tableColumn.minWidth = 36
            if column.width > 0 {
                tableColumn.width = column.width
                tableColumn.maxWidth = column.width
            }
            tableView.addTableColumn(tableColumn)
        }

        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        return (scrollView, tableView)
    }

    // MARK: - Data

    private func loadFileDescriptors() {
        fileDescriptors = iTermLSOF.fileDescriptors(forProcess: pid) ?? []
    }

    private func loadEnvironment() {
        let entries = iTermLSOF.environment(forProcess: pid) ?? []
        var pairs: [(key: String, value: String)] = []
        for entry in entries {
            if let range = entry.range(of: "=") {
                pairs.append((key: String(entry[..<range.lowerBound]),
                              value: String(entry[range.upperBound...])))
            } else {
                pairs.append((key: entry, value: ""))
            }
        }
        pairs.sort { $0.key.caseInsensitiveCompare($1.key) == .orderedAscending }
        environment = pairs
    }

    private func startedDescription() -> String {
        if !startTimeFetched {
            startTime = iTermLSOF.startTime(forProcess: pid)
            startTimeFetched = true
        }
        guard let start = startTime else {
            return "Unknown"
        }
        let absolute = DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        if let elapsed = formatter.string(from: max(0, -start.timeIntervalSinceNow)), !elapsed.isEmpty {
            return "\(absolute) (\(elapsed) ago)"
        }
        return absolute
    }

    private func fetchWorkingDirectory() {
        iTermLSOF.asyncWorkingDirectory(ofProcess: pid, queue: pwdQueue) { [weak self] pwd in
            DispatchQueue.main.async {
                self?.setWorkingDirectory(pwd)
            }
        }
    }

    private func setWorkingDirectory(_ pwd: String?) {
        let hasValue = (pwd?.isEmpty == false)
        workingDirectory = hasValue ? pwd : nil
        directoryValue.stringValue = hasValue ? pwd! : "Unknown"
        copyDirectoryButton.isEnabled = (workingDirectory != nil)
        // Re-layout to accommodate a possibly multi-line directory.
        relayout(forWidth: view.bounds.width)
    }

    // MARK: - Copy actions

    @objc private func copyCommand(_ sender: Any) {
        copyToPasteboard(fullCommand, from: sender as? NSButton)
    }

    @objc private func copyDirectory(_ sender: Any) {
        copyToPasteboard(workingDirectory, from: sender as? NSButton)
    }

    @objc private func copyPid(_ sender: Any) {
        copyToPasteboard("\(pid)", from: sender as? NSButton)
    }

    private func copyToPasteboard(_ string: String?, from button: NSButton?) {
        guard let string, !string.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)

        guard let button, let window = button.window else {
            return
        }
        let rectInScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        let topLeft = NSPoint(x: rectInScreen.maxX + 6, y: rectInScreen.maxY)
        ToastWindowController.showToast(withMessage: "Copied",
                                        duration: 1,
                                        topLeftScreenCoordinate: topLeft,
                                        pointSize: 12)
    }

    // MARK: - Layout

    // Lays the popover out top-to-bottom in its flipped content view using the
    // view's actual width (the popover owns the frame). The top fields alternate
    // header/value (each sized from its own fittingSize so the frame matches the
    // text field's rendered metrics, which a raw string bounding rect does not),
    // followed by the Environment and Open Files & Sockets tables. The computed
    // height is published via preferredContentSize so the popover grows to fit.
    func relayout(forWidth widthIn: CGFloat) {
        let width = widthIn < 2 * inset ? popoverWidth : widthIn
        let contentWidth = width - 2 * inset
        let buttonSide: CGFloat = 14
        let buttonGap: CGFloat = 4
        var y = inset
        for (i, field) in topFields.enumerated() {
            let isHeader = (i % 2 == 0)
            // The Command (i==1), Working Directory (i==3), and Process ID (i==5)
            // values carry a copy button immediately after the text.
            let copyButton: NSButton? = (i == 1) ? copyCommandButton : (i == 3) ? copyDirectoryButton : (i == 5) ? copyPidButton : nil
            // Constrain the width so wrapping values report a multi-line height,
            // leaving room for the trailing copy button when there is one.
            let maxFieldWidth = copyButton != nil ? contentWidth - buttonSide - buttonGap : contentWidth
            field.preferredMaxLayoutWidth = maxFieldWidth
            let height = ceil(field.fittingSize.height)
            let fieldWidth = copyButton != nil ? min(maxFieldWidth, ceil(field.fittingSize.width)) : contentWidth
            field.frame = NSRect(x: inset, y: y, width: fieldWidth, height: height)
            if let copyButton {
                // Vertically center the button on the value's first line.
                let font = field.font ?? .systemFont(ofSize: 12)
                let lineHeight = ceil(("Ag" as NSString).size(withAttributes: [.font: font]).height)
                copyButton.frame = NSRect(x: inset + fieldWidth + buttonGap,
                                          y: (field.frame.minY + (lineHeight - buttonSide) / 2).rounded(),
                                          width: buttonSide,
                                          height: buttonSide)
            }
            y += height + (isHeader ? headerGap : sectionGap)
        }

        y = layoutTableSection(header: environmentHeader, scrollView: environmentScrollView, contentWidth: contentWidth, top: y)
        y = layoutTableSection(header: fileDescriptorHeader, scrollView: fileDescriptorScrollView, contentWidth: contentWidth, top: y)

        let size = NSSize(width: width, height: y)
        if size != preferredContentSize {
            preferredContentSize = size
        }
    }

    private func layoutTableSection(header: NSTextField, scrollView: NSScrollView, contentWidth: CGFloat, top: CGFloat) -> CGFloat {
        header.preferredMaxLayoutWidth = contentWidth
        let headerHeight = ceil(header.fittingSize.height)
        header.frame = NSRect(x: inset, y: top, width: contentWidth, height: headerHeight)
        let y = top + headerHeight + headerGap
        scrollView.frame = NSRect(x: inset, y: y, width: contentWidth, height: tableHeight)
        return y + tableHeight + inset
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return tableView == fileDescriptorTableView ? fileDescriptors.count : environment.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else {
            return nil
        }
        let identifier = tableColumn.identifier
        let field: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            field = reused
        } else {
            field = NSTextField(labelWithString: "")
            field.identifier = identifier
            field.font = .systemFont(ofSize: 11)
            field.isSelectable = true
            field.lineBreakMode = .byTruncatingTail
        }
        let string = self.string(table: tableView, column: identifier.rawValue, row: row)
        field.stringValue = string
        field.toolTip = string
        return field
    }

    private func string(table: NSTableView, column: String, row: Int) -> String {
        if table == fileDescriptorTableView {
            let descriptor = fileDescriptors[row]
            switch column {
            case "fd": return "\(descriptor.fd)"
            case "type": return descriptor.type
            default: return descriptor.detail
            }
        }
        let pair = environment[row]
        return column == "key" ? pair.key : pair.value
    }
}
