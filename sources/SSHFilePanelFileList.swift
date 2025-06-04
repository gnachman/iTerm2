//
//  SSHFilePanelFileList.swift
//  iTerm2
//
//  Created by George Nachman on 6/4/25.
//
@available(macOS 11, *)
class SSHFilePanelFileList: NSScrollView {

    // Custom header cell to control text color
    class CustomHeaderCell: NSTableHeaderCell {
        var isActiveSort: Bool = false {
            didSet {
                if oldValue != isActiveSort {
                    controlView?.needsDisplay = true
                }
            }
        }

        var leftPadding: CGFloat = 0

        override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
            // Apply left padding only to text drawing
            var adjustedFrame = cellFrame
            adjustedFrame.origin.x += leftPadding
            adjustedFrame.size.width -= leftPadding
            super.drawInterior(withFrame: adjustedFrame, in: controlView)
        }

        override var textColor: NSColor? {
            get {
                return isActiveSort ? .labelColor : .secondaryLabelColor
            }
            set {
                super.textColor = newValue
            }
        }

        override var font: NSFont? {
            get {
                let font = super.font
                if isActiveSort, let font {
                    return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                } else {
                    return font
                }
            }
            set {
                super.font = newValue
            }
        }
    }

    enum ColumnID: String, CaseIterable {
        case name = "NameColumn"
        case dateCreated = "DateColumn"
        case size = "SizeColumn"
        case kind = "KindColumn"

        var title: String {
            switch self {
            case .name: return "Name"
            case .dateCreated: return "Date Created"
            case .size: return "Size"
            case .kind: return "Kind"
            }
        }

        var width: CGFloat {
            switch self {
            case .name: return 300
            case .dateCreated: return 160
            case .size: return 100
            case .kind: return 120
            }
        }

        var minWidth: CGFloat {
            switch self {
            case .name: return 245
            case .dateCreated: return 75
            case .size: return 80
            case .kind: return 100
            }
        }
    }

    private var fileTableView: SSHFilePanelFileListTableView!
    private var path: String?
    private var endpoint: SSHEndpoint?
    private var files: [RemoteFile] = []
    private var isLoading = false

    init() {
        fileTableView = SSHFilePanelFileListTableView()
        fileTableView.style = .fullWidth
        fileTableView.selectionHighlightStyle = .regular
        fileTableView.allowsMultipleSelection = false
        fileTableView.allowsEmptySelection = true
        fileTableView.usesAlternatingRowBackgroundColors = true
        fileTableView.gridStyleMask = [.solidHorizontalGridLineMask]
        fileTableView.intercellSpacing = NSSize(width: 0, height: 1)
        fileTableView.focusRingType = .none
        fileTableView.rowHeight = 20
        fileTableView.floatsGroupRows = false

        super.init(frame: .zero)

        // Add columns using enum
        for columnID in ColumnID.allCases {
            addTableColumn(columnID: columnID)
        }

        // Set up table view
        fileTableView.dataSource = self
        fileTableView.delegate = self

        fileTableView.onColumnWidthChange = { [weak self] column in
            self?.columnLiveResize(column)
        }

        // Configure header view colors to match system
        if let headerView = fileTableView.headerView {
            headerView.wantsLayer = true
            headerView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }

        // Add observer for column resize notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(columnDidResize(_:)),
            name: NSTableView.columnDidResizeNotification,
            object: fileTableView
        )

        // Call this after setting up the table to ensure headers are colored correctly
        DispatchQueue.main.async {
            self.updateAllColumnHeaders()
        }

        documentView = fileTableView
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func columnDidResize(_ notification: Notification) {
        // Reload visible cells to update date formatting for the resized column
        let visibleRange = fileTableView.rows(in: fileTableView.visibleRect)
        if visibleRange.length > 0 {
            fileTableView.reloadData(forRowIndexes: IndexSet(integersIn: visibleRange.lowerBound..<visibleRange.upperBound),
                                   columnIndexes: IndexSet(integersIn: 0..<fileTableView.numberOfColumns))
        }
    }

    private func addTableColumn(columnID: ColumnID) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnID.rawValue))
        column.title = columnID.title
        column.width = columnID.width
        column.minWidth = columnID.minWidth

        // Create sort descriptor for this column
        let sortDescriptor = NSSortDescriptor(key: columnID.rawValue, ascending: true)
        column.sortDescriptorPrototype = sortDescriptor

        // Use custom header cell
        let headerCell = CustomHeaderCell()
        headerCell.title = columnID.title

        // Align headers to match content alignment and add padding for Name column
        if columnID == .size {
            headerCell.alignment = .right
        } else {
            headerCell.alignment = .left
        }

        // Add left padding to Name header to align with filename text (not icons)
        if columnID == .name {
            headerCell.leftPadding = 24 // Same as filename text leading constraint
        }

        column.headerCell = headerCell

        fileTableView.addTableColumn(column)

        headerCell.isActiveSort = (columnID.rawValue == currentSortColumn.identifier.rawValue)
    }

    private func updateAllColumnHeaders() {
        for column in fileTableView.tableColumns {
            if let columnID = ColumnID(rawValue: column.identifier.rawValue),
               let headerCell = column.headerCell as? CustomHeaderCell {
                // Check if this column is in the current sort descriptors
                let isActiveSort = if let firstDescriptor = fileTableView.sortDescriptors.first {
                    firstDescriptor.key == columnID.rawValue
                } else {
                    column === fileTableView.tableColumns.first
                }
                headerCell.isActiveSort = isActiveSort
            }
        }
        fileTableView.headerView?.needsDisplay = true
    }

    func clear() {
        files.removeAll()
        fileTableView.reloadData()
    }

    func set(path: String, endpoint: SSHEndpoint) {
        self.path = path
        self.endpoint = endpoint
        loadFiles()
    }

    private func loadFiles() {
        guard let path = path, let endpoint = endpoint, !isLoading else { return }

        isLoading = true

        Task { @MainActor in
            do {
                let remoteFiles = try await endpoint.listFiles(path, sort: .byName)
                self.files = remoteFiles
                self.sortAndReloadFiles()
            } catch {
                // Handle error - could show an alert or log
                print("Error loading files: \(error)")
            }
            self.isLoading = false
        }
    }

    var currentSortColumn: NSTableColumn {
        let i = if let key = fileTableView.sortDescriptors.first?.key {
            fileTableView.column(withIdentifier: NSUserInterfaceItemIdentifier(key))
        } else {
            fileTableView.column(withIdentifier: NSUserInterfaceItemIdentifier(ColumnID.name.rawValue))
        }
        return fileTableView.tableColumns[i]
    }

    var sortAscending: Bool {
        return fileTableView.sortDescriptors.first?.ascending ?? true
    }

    private func sortAndReloadFiles() {
        DLog("Sort and reload. ascending=\(sortAscending) column=\(currentSortColumn.identifier.rawValue)")
        files.sort { file1, file2 in
            let result: Bool
            switch ColumnID(rawValue: currentSortColumn.identifier.rawValue) {
            case .name, .none:
                result = file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
            case .dateCreated:
                let date1 = file1.ctime ?? Date.distantPast
                let date2 = file2.ctime ?? Date.distantPast
                result = date1 < date2
            case .size:
                let size1 = file1.size ?? 0
                let size2 = file2.size ?? 0
                result = size1 < size2
            case .kind:
                result = kindDescription(for: file1).localizedCaseInsensitiveCompare(kindDescription(for: file2)) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
        fileTableView.reloadData()
    }

    // Helper method to get icon for file type
    private func iconForFile(_ file: RemoteFile) -> NSImage? {
        switch file.kind {
        case .folder:
            return NSImage(named: NSImage.folderName)
        case .file(let info):
            // Try to get icon based on file extension
            let pathExtension = (file.name as NSString).pathExtension.lowercased()
            if !pathExtension.isEmpty {
                let workspace = NSWorkspace.shared
                return workspace.icon(forFileType: pathExtension)
            }
            return NSImage(named: NSImage.multipleDocumentsName)
        case .symlink:
            // Use followLinkFreestandingTemplateName for symlinks/aliases
            return NSImage(named: NSImage.followLinkFreestandingTemplateName)
        case .host:
            return NSImage(named: NSImage.computerName)
        }
    }

    // Helper method to format file size
    private func formatFileSize(_ size: Int?) -> String {
        guard let size = size else { return "--" }

        if size == 0 {
            return "Zero bytes"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    // Helper method to format date with width-dependent format
    private func formatDate(_ date: Date?, columnWidth: CGFloat) -> String {
        guard let date = date else { return "--" }

        let formatter = DateFormatter()

        /*
         I tried every minute of 2025 on macOS 15.5 with 12-pt system font and got these results:

         Format: MMMM d, yyyy h:mm a
         Max width: 174.03515625 points
         Widest date/time: September 30, 2025 10:44 AM

         Format: MMM d, yyyy h:mm a
         Max width: 135.234375 points
         Widest date/time: May 30, 2025 10:44 AM

         Format: M/d/yy h:mm a
         Max width: 107.63671875 points
         Widest date/time: 10/30/25 10:44 AM

         Format: M/d/yy
         Max width: 50.1796875 points
         Widest date/time: 10/30/25
         */
        if columnWidth >= 186 {
            // Wide: "October 31, 2025 12:30 PM"
            formatter.dateFormat = "MMMM d, yyyy h:mm a"
        } else if columnWidth >= 147 {
            // Medium: "Oct 31, 2025 12:30 PM"
            formatter.dateFormat = "MMM d, yyyy h:mm a"
        } else if columnWidth >= 119 {
            // Narrow: "10/30/25 12:30 PM"
            formatter.dateFormat = "M/d/yy h:mm a"
        } else {
            // Very narrow: "10/30/25"
            formatter.dateFormat = "M/d/yy"
        }

        return formatter.string(from: date)
    }

    // Helper method to get detailed kind description
    private func kindDescription(for file: RemoteFile) -> String {
        switch file.kind {
        case .file:
            let pathExtension = (file.name as NSString).pathExtension.lowercased()
            switch pathExtension {
            case "png", "jpg", "jpeg", "gif", "bmp", "tiff":
                return "\(pathExtension.uppercased()) image"
            case "txt", "md", "rtf":
                return "Text document"
            case "pdf":
                return "PDF document"
            case "mp4", "mov", "avi", "mkv":
                return "Video"
            case "mp3", "wav", "aac", "flac":
                return "Audio"
            case "zip", "tar", "gz", "bz2":
                return "Archive"
            case "lua":
                return "Lua script"
            case "nvim":
                return "Neovim config"
            case "sh":
                return "Shell script"
            case "m":
                return "Objective-C source"
            case "":
                return "Document"
            default:
                return "Document"
            }
        case .folder:
            return "Folder"
        case .host:
            return "Host"
        case .symlink:
            return "Alias"
        }
    }
}

// MARK: - NSTableViewDataSource
@available(macOS 11, *)
extension SSHFilePanelFileList: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return files.count
    }
}

// MARK: - NSTableViewDelegate
@available(macOS 11, *)
extension SSHFilePanelFileList: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < files.count else { return nil }

        let file = files[row]
        let columnID = ColumnID(rawValue: tableColumn?.identifier.rawValue ?? "")

        var cellView = tableView.makeView(withIdentifier: tableColumn?.identifier ?? NSUserInterfaceItemIdentifier(""), owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = tableColumn?.identifier

            // Create image view for name column
            if columnID == .name {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                cellView?.addSubview(imageView)
                cellView?.imageView = imageView

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16)
                ])
            }

            let textField = NSTextField()
            textField.isBordered = false
            textField.isEditable = false
            textField.backgroundColor = .clear
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = NSFont.systemFont(ofSize: 12)

            // Set truncation for name column
            if columnID == .name {
                textField.cell?.truncatesLastVisibleLine = true
                textField.cell?.lineBreakMode = .byTruncatingTail
            }

            cellView?.addSubview(textField)
            cellView?.textField = textField

            // Set up constraints based on column
            if columnID == .name {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 24),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }

            // Right-align size column
            if columnID == .size {
                textField.alignment = .right
            }
        }

        // Set icon for name column
        if columnID == .name {
            cellView?.imageView?.image = iconForFile(file)
        }

        // Set text and color based on column
        switch columnID {
        case .name:
            cellView?.textField?.stringValue = file.name
            cellView?.textField?.textColor = .labelColor
        case .dateCreated:
            let columnWidth = tableView.tableColumn(withIdentifier: tableColumn!.identifier)?.width ?? 160
            cellView?.textField?.stringValue = formatDate(file.ctime, columnWidth: columnWidth)
            cellView?.textField?.textColor = .secondaryLabelColor
        case .size:
            cellView?.textField?.stringValue = formatFileSize(file.size)
            cellView?.textField?.textColor = .secondaryLabelColor
        case .kind:
            cellView?.textField?.stringValue = kindDescription(for: file)
            cellView?.textField?.textColor = .secondaryLabelColor
        case .none:
            cellView?.textField?.stringValue = ""
        }

        return cellView
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        updateAllColumnHeaders()
        sortAndReloadFiles()
    }
/*
    func tableView(_ tableView: NSTableView, didClick column: NSTableColumn) {
        guard let columnID = ColumnID(rawValue: column.identifier.rawValue) else { return }

        var descriptors = tableView.sortDescriptors
        let i = descriptors.firstIndex { $0.key == column.identifier.rawValue }
        if let i {
            let existing = descriptors[i]
            descriptors.remove(at: i)
            descriptors.insert(NSSortDescriptor(key: existing.key,
                                                ascending: !existing.ascending),
                               at: 0)
        } else {
            descriptors.insert(NSSortDescriptor(key: column.identifier.rawValue,
                                                ascending: true),
                               at: 0)
        }
        column.sortDescriptorPrototype = descriptors[0]
        tableView.sortDescriptors = descriptors
        updateAllColumnHeaders()
        sortAndReloadFiles()
    }
*/
    func columnLiveResize(_ column: NSTableColumn) {
        if column.identifier == NSUserInterfaceItemIdentifier(ColumnID.dateCreated.rawValue),
           let columnIndex = fileTableView.tableColumns.firstIndex(of: column) {
            fileTableView.reloadData(forRowIndexes: IndexSet(0..<files.count),
                                     columnIndexes: IndexSet(integer: columnIndex))
        }
    }
}

class SSHFilePanelFileListTableView: NSTableView {
    var onColumnWidthChange: ((NSTableColumn) -> Void)?

    init() {
        super.init(frame: .zero)
    }

    deinit {
        for column in tableColumns {
            column.removeObserver(self, forKeyPath: "width")
        }
    }

    override func addTableColumn(_ tableColumn: NSTableColumn) {
        super.addTableColumn(tableColumn)
        tableColumn.addObserver(self, forKeyPath: "width", options: [.new, .old], context: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "width", let column = object as? NSTableColumn {
            onColumnWidthChange?(column)
        }
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
}
