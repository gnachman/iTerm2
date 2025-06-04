//
//  SSHFilePanelFileList.swift
//  iTerm2
//
//  Created by George Nachman on 6/4/25.
//
import UniformTypeIdentifiers

@available(macOS 11, *)
class SSHFilePromiseProvider: NSFilePromiseProvider {

    struct UserInfoKeys {
        static let node = "node"
        static let endpoint = "endpoint"
        static let fullPath = "fullPath"
        static let tempURL = "tempURL"
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        types.append(contentsOf: [.fileURL, .string])
        return types
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard let userInfoDict = userInfo as? [String: Any] else { return nil }

        switch type {
        case .fileURL:
            if let tempURL = userInfoDict[UserInfoKeys.tempURL] as? NSURL {
                return tempURL.pasteboardPropertyList(forType: type)
            }
        case .string:
            if let tempURL = userInfoDict[UserInfoKeys.tempURL] as? NSURL {
                return tempURL.path
            }
        default:
            break
        }

        return super.pasteboardPropertyList(forType: type)
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        return super.writingOptions(forType: type, pasteboard: pasteboard)
    }
}

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

    // Tree node to represent files and directories
    class FileNode {
        let file: RemoteFile
        let path: String
        var children: [FileNode]?
        var isLoading = false
        var isExpanded = false
        weak var parent: FileNode?

        init(file: RemoteFile, path: String, parent: FileNode? = nil) {
            self.file = file
            self.path = path
            self.parent = parent
        }

        var isDirectory: Bool {
            return file.kind == .folder
        }

        var hasChildren: Bool {
            return isDirectory
        }

        var sortedChildren: [FileNode] {
            return children?.sorted(by: currentSortComparator) ?? []
        }

        private var currentSortComparator: (FileNode, FileNode) -> Bool = { _, _ in true }

        func setSortComparator(_ comparator: @escaping (FileNode, FileNode) -> Bool) {
            currentSortComparator = comparator
            // Recursively apply to all loaded children
            children?.forEach { $0.setSortComparator(comparator) }
        }

        func sortChildren() {
            if let children = children {
                self.children = children.sorted(by: currentSortComparator)
                // Recursively sort all children
                children.forEach { $0.sortChildren() }
            }
        }
    }

    private var fileOutlineView: SSHFilePanelFileListOutlineView!
    private var rootPath: String?
    private var endpoint: SSHEndpoint?
    private var rootNodes: [FileNode] = []
    private var isLoading = false
    private var currentSortColumn: ColumnID = .name
    private var sortAscending = true

    init() {
        fileOutlineView = SSHFilePanelFileListOutlineView()
        fileOutlineView.style = .fullWidth
        fileOutlineView.selectionHighlightStyle = .regular
        fileOutlineView.allowsMultipleSelection = true  // Enable multiple selection for dragging
        fileOutlineView.allowsEmptySelection = true
        fileOutlineView.usesAlternatingRowBackgroundColors = true
        fileOutlineView.gridStyleMask = [.solidHorizontalGridLineMask]
        fileOutlineView.intercellSpacing = NSSize(width: 0, height: 1)
        fileOutlineView.focusRingType = .none
        fileOutlineView.rowHeight = 20
        fileOutlineView.floatsGroupRows = false
        fileOutlineView.indentationPerLevel = 16
        fileOutlineView.autoresizesOutlineColumn = false

        // Set the dragging source operation mask for external drops
        fileOutlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        fileOutlineView.setDraggingSourceOperationMask(.copy, forLocal: true)

        super.init(frame: .zero)

        // Add columns using enum
        for columnID in ColumnID.allCases {
            addTableColumn(columnID: columnID)
        }

        // Set the outline column to the name column
        fileOutlineView.outlineTableColumn = fileOutlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(ColumnID.name.rawValue))

        // Set up outline view
        fileOutlineView.dataSource = self
        fileOutlineView.delegate = self

        fileOutlineView.onColumnWidthChange = { [weak self] column in
            self?.columnLiveResize(column)
        }

        // Configure header view colors to match system
        if let headerView = fileOutlineView.headerView {
            headerView.wantsLayer = true
            headerView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }

        // Add observer for column resize notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(columnDidResize(_:)),
            name: NSOutlineView.columnDidResizeNotification,
            object: fileOutlineView
        )

        // Call this after setting up the outline view to ensure headers are colored correctly
        DispatchQueue.main.async {
            self.updateAllColumnHeaders()
        }

        documentView = fileOutlineView
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
        let visibleRange = fileOutlineView.rows(in: fileOutlineView.visibleRect)
        if visibleRange.length > 0 {
            fileOutlineView.reloadData(forRowIndexes: IndexSet(integersIn: visibleRange.lowerBound..<visibleRange.upperBound),
                                      columnIndexes: IndexSet(integersIn: 0..<fileOutlineView.numberOfColumns))
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

        fileOutlineView.addTableColumn(column)

        headerCell.isActiveSort = (columnID == currentSortColumn)
    }

    private func updateAllColumnHeaders() {
        for column in fileOutlineView.tableColumns {
            if let columnID = ColumnID(rawValue: column.identifier.rawValue),
               let headerCell = column.headerCell as? CustomHeaderCell {
                headerCell.isActiveSort = (columnID == currentSortColumn)
            }
        }
        fileOutlineView.headerView?.needsDisplay = true
    }

    func clear() {
        rootNodes.removeAll()
        fileOutlineView.reloadData()
    }

    func set(path: String, endpoint: SSHEndpoint) {
        self.rootPath = path
        self.endpoint = endpoint
        loadRootFiles()
    }

    private func loadRootFiles() {
        guard let path = rootPath, let endpoint = endpoint, !isLoading else { return }

        isLoading = true

        Task { @MainActor in
            do {
                let remoteFiles = try await endpoint.listFiles(path, sort: .byName)
                self.rootNodes = remoteFiles.map { FileNode(file: $0, path: path) }
                self.applySortToAllNodes()
                self.fileOutlineView.reloadData()
            } catch {
                // Handle error - could show an alert or log
                print("Error loading files: \(error)")
            }
            self.isLoading = false
        }
    }

    private func loadChildren(for node: FileNode) async {
        guard node.isDirectory && node.children == nil && !node.isLoading else { return }
        node.isLoading = true
        do {
            let childPath = (node.path as NSString).appendingPathComponent(node.file.name)
            let remoteFiles = try await endpoint?.listFiles(childPath, sort: .byName) ?? []
            let childNodes = remoteFiles.map { FileNode(file: $0, path: childPath, parent: node) }
            await MainActor.run {
                node.children = childNodes
                node.isLoading = false
                // Apply current sort to the new children
                self.applySortComparator(to: node)
                node.sortChildren()
                // Reload the parent item to show its children
                let parentIndex = self.fileOutlineView.row(forItem: node)
                if parentIndex >= 0 {
                    self.fileOutlineView.reloadItem(node, reloadChildren: true)
                }
            }
        } catch {
            await MainActor.run {
                node.isLoading = false
                print("Error loading children for \(node.file.name): \(error)")
            }
        }
    }

    private func applySortToAllNodes() {
        let comparator = makeSortComparator()
        rootNodes = rootNodes.sorted(by: comparator)

        // Recursively apply to all nodes
        func applySortRecursively(to nodes: [FileNode]) {
            for node in nodes {
                node.setSortComparator(comparator)
                node.sortChildren()
                if let children = node.children {
                    applySortRecursively(to: children)
                }
            }
        }
        applySortRecursively(to: rootNodes)
    }

    private func applySortComparator(to node: FileNode) {
        node.setSortComparator(makeSortComparator())
    }

    private func makeSortComparator() -> (FileNode, FileNode) -> Bool {
        return { [weak self] node1, node2 in
            guard let self = self else { return true }

            let file1 = node1.file
            let file2 = node2.file

            let result: Bool
            switch self.currentSortColumn {
            case .name:
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
                result = self.kindDescription(for: file1).localizedCaseInsensitiveCompare(self.kindDescription(for: file2)) == .orderedAscending
            }
            return self.sortAscending ? result : !result
        }
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

// MARK: - NSOutlineViewDataSource
@available(macOS 11, *)
extension SSHFilePanelFileList: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootNodes.count
        } else if let node = item as? FileNode {
            return node.sortedChildren.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootNodes[index]
        } else if let node = item as? FileNode {
            return node.sortedChildren[index]
        }
        it_fatalError()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return node.hasChildren
    }
}

// MARK: - NSOutlineViewDelegate
@available(macOS 11, *)
extension SSHFilePanelFileList: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }

        let file = node.file
        let columnID = ColumnID(rawValue: tableColumn?.identifier.rawValue ?? "")

        var cellView = outlineView.makeView(withIdentifier: tableColumn?.identifier ?? NSUserInterfaceItemIdentifier(""), owner: self) as? NSTableCellView

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
            let columnWidth = outlineView.tableColumn(withIdentifier: tableColumn!.identifier)?.width ?? 160
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

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return node.hasChildren
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, canDragRowsWith rowIndexes: IndexSet, at mouseDownPoint: NSPoint) -> Bool {
        print("canDragRowsWith called for indexes: \(rowIndexes)")
        // Allow dragging of all items
        return true
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }

        // Load children if not already loaded
        if node.children == nil && !node.isLoading {
            Task {
                await loadChildren(for: node)
            }
        }
        node.isExpanded = true
    }

    func outlineViewItemWillCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        node.isExpanded = false
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let firstDescriptor = outlineView.sortDescriptors.first,
              let columnID = ColumnID(rawValue: firstDescriptor.key ?? "") else { return }

        currentSortColumn = columnID
        sortAscending = firstDescriptor.ascending

        updateAllColumnHeaders()
        applySortToAllNodes()
        fileOutlineView.reloadData()
    }

    func columnLiveResize(_ column: NSTableColumn) {
        if column.identifier == NSUserInterfaceItemIdentifier(ColumnID.dateCreated.rawValue),
           let columnIndex = fileOutlineView.tableColumns.firstIndex(of: column) {
            fileOutlineView.reloadData(forRowIndexes: IndexSet(0..<fileOutlineView.numberOfRows),
                                      columnIndexes: IndexSet(integer: columnIndex))
        }
    }

    // MARK: - Drag Support
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? FileNode else {
            print("pasteboardWriterForItem: item is not a FileNode")
            return nil
        }

        print("pasteboardWriterForItem called for: \(node.file.name)")

        // Create a temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(node.file.name)

        // Create the temporary file/directory
        do {
            if node.file.kind == .folder {
                try FileManager.default.createDirectory(at: tempFileURL, withIntermediateDirectories: true, attributes: nil)
                print("Created temp directory: \(tempFileURL)")
            } else {
                FileManager.default.createFile(atPath: tempFileURL.path, contents: Data(), attributes: nil)
                print("Created temp file: \(tempFileURL)")
            }
        } catch {
            print("Failed to create temp file: \(error)")
            return nil
        }

        // Determine the appropriate UTI for the file
        let fileUTI: String
        if node.file.kind == .folder {
            fileUTI = UTType.folder.identifier
        } else {
            let pathExtension = (node.file.name as NSString).pathExtension
            if let type = UTType(filenameExtension: pathExtension) {
                fileUTI = type.identifier
            } else {
                fileUTI = UTType.data.identifier
            }
        }

        print("Using UTI: \(fileUTI)")

        // Create our custom file promise provider
        let filePromise = SSHFilePromiseProvider(fileType: fileUTI, delegate: self)

        let fullPath = (node.path as NSString).appendingPathComponent(node.file.name)

        // Store all necessary info in userInfo
        filePromise.userInfo = [
            SSHFilePromiseProvider.UserInfoKeys.node: node,
            SSHFilePromiseProvider.UserInfoKeys.endpoint: endpoint as Any,
            SSHFilePromiseProvider.UserInfoKeys.fullPath: fullPath,
            SSHFilePromiseProvider.UserInfoKeys.tempURL: tempFileURL as NSURL
        ]

        print("Created SSHFilePromiseProvider with temp URL: \(tempFileURL)")
        return filePromise
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems items: [Any]) {
        print("draggingSession willBeginAt called with \(items.count) items")
        // Set up the dragging session
        session.draggingFormation = .pile

        // The system will automatically generate a drag image based on the selected rows
        // We don't need to manually set the drag image as NSDraggingSession doesn't expose that property
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        print("draggingSession endedAt called with operation: \(operation.rawValue)")

        if operation.contains(.copy) {
            print("Drag was successful!")
        } else {
            print("Drag was rejected or cancelled")
        }
    }

    // Specify what drag operations are allowed
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        print("sourceOperationMaskFor context: \(context.rawValue)")
        switch context {
        case .outsideApplication:
            print("Allowing copy operations outside application")
            // When dragging outside the app, allow copy operations
            // This enables dragging to Finder, other apps, etc.
            return [.copy]
        case .withinApplication:
            print("Allowing copy operations within application")
            // Within the app, we could support move operations if we implement drop targets
            return [.copy]
        @unknown default:
            print("Unknown drag context, allowing copy")
            return [.copy]
        }
    }
}

// MARK: - NSFilePromiseProviderDelegate
@available(macOS 11, *)
extension SSHFilePanelFileList: NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        print("filePromiseProvider fileNameForType called with: \(fileType)")

        guard let userInfo = filePromiseProvider.userInfo as? [String: Any],
              let node = userInfo["node"] as? FileNode else {
            print("Failed to get node from userInfo")
            return "unknown_file"
        }

        print("Returning filename: \(node.file.name)")
        // Return the full filename with extension
        return node.file.name
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        print("*** filePromiseProvider writePromiseTo called! ***")
        print("Writing promise to: \(url)")

        guard let userInfo = filePromiseProvider.userInfo as? [String: Any],
              let node = userInfo["node"] as? FileNode,
              let endpoint = userInfo["endpoint"] as? SSHEndpoint,
              let fullPath = userInfo["fullPath"] as? String else {
            print("Missing file information for promise")
            let error = NSError(domain: "SSHFilePanelError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing file information"])
            completionHandler(error)
            return
        }

        print("Downloading \(fullPath) to \(url)")

        // Download the file from the remote server
        Task { @MainActor in
            do {
                if node.file.kind == .folder {
                    print("Creating directory: \(url)")
                    // For directories, create the directory structure
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                    // Optionally, recursively download directory contents
                    await downloadDirectoryContents(from: fullPath, to: url, using: endpoint)
                    print("Directory download completed")
                    completionHandler(nil)
                } else {
                    print("Downloading file: \(fullPath)")
                    // For files, download the file content (download entire file by passing nil chunk)
                    let data = try await endpoint.download(fullPath, chunk: nil)
                    try data.write(to: url)
                    print("File download completed: \(data.count) bytes")
                    completionHandler(nil)
                }
            } catch {
                print("Download error: \(error)")
                completionHandler(error)
            }
        }
    }

    private func downloadDirectoryContents(from remotePath: String, to localURL: URL, using endpoint: SSHEndpoint) async {
        do {
            let files = try await endpoint.listFiles(remotePath, sort: .byName)
            for file in files {
                let remoteFilePath = (remotePath as NSString).appendingPathComponent(file.name)
                let localFileURL = localURL.appendingPathComponent(file.name)

                if file.kind == .folder {
                    try FileManager.default.createDirectory(at: localFileURL, withIntermediateDirectories: true, attributes: nil)
                    await downloadDirectoryContents(from: remoteFilePath, to: localFileURL, using: endpoint)
                } else {
                    if let data = try? await endpoint.download(remoteFilePath, chunk: nil) {
                        try? data.write(to: localFileURL)
                    }
                }
            }
        } catch {
            print("Error downloading directory contents: \(error)")
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        print("operationQueue called for file promise provider")
        // Return a background queue for file operations
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.name = "SSHFilePanel.FilePromise"
        return queue
    }
}

class SSHFilePanelFileListOutlineView: NSOutlineView {
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
