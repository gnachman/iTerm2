//
//  SSHFilePanelSourceList.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

fileprivate let favoriteReorderPasteboardType =
    NSPasteboard.PasteboardType("com.iterm2.ssh-favorite-reorder")

@available(macOS 11, *)
class SSHFilePanelSourceList: NSOutlineView {
    static let sshFileNodePasteboardType = NSPasteboard.PasteboardType("com.iterm2.ssh-file-node")
    static let sshFileNodeDirectoryPasteboardType = NSPasteboard.PasteboardType("com.iterm2.ssh-file-node-directory")

    init() {
        super.init(frame: .zero)
        style = .sourceList
        floatsGroupRows = false
        headerView = nil
        focusRingType = .none
        usesAutomaticRowHeights = true
        indentationPerLevel = 0

        registerForDraggedTypes([
            NSPasteboard.PasteboardType(kPasteboardTypeFileURLPromise),
            SSHFilePanelSourceList.sshFileNodePasteboardType,
            SSHFilePanelSourceList.sshFileNodeDirectoryPasteboardType,
            favoriteReorderPasteboardType
        ])
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        return false
    }
}


// MARK: - SSHFilePanelSidebarDelegate Protocol

@available(macOS 11, *)
protocol SSHFilePanelSidebarDelegate: AnyObject {
    func sidebarDidSelectHost(_ sidebar: SSHFilePanelSidebar, host: SSHIdentity)
    func sidebarDidSelectFavorite(_ sidebar: SSHFilePanelSidebar, host: SSHIdentity, path: String)
    func shortPath(sshIdentity: SSHIdentity, absolutePath: String) -> String?
    func sidebarHostIsValid(_ sidebar: SSHFilePanelSidebar, host: SSHIdentity) -> Bool
}


@available(macOS 11, *)
class SSHFilePanelSidebar: NSView {
    private(set) var sidebarOutlineView: SSHFilePanelSourceList!
    private var sidebarScrollView: NSScrollView!

    weak var delegate: SSHFilePanelSidebarDelegate?

    private var _connectedHosts: [SSHIdentity] = []
    var connectedHosts: [SSHIdentity] {
        get {
            return _connectedHosts
        }
        set {
            _connectedHosts = newValue
            filter()
            selectedIdentity = self.selectedIdentity
        }
    }

    struct Favorite: Equatable {
        var host: SSHIdentity
        var path: String
        var shortenedPath: String?

        var userDefaultsObject: [String: Any] {
            var result: [String: Any] = [
                FavoritesKeys.sshIdentity.rawValue: host.toUserDefaultsObject(),
                FavoritesKeys.path.rawValue: path,
            ]
            if let shortenedPath {
                result[FavoritesKeys.shortenedPath.rawValue] = shortenedPath
            }
            return result
        }

        init(host: SSHIdentity, path: String, shortenedPath: String?) {
            self.host = host
            self.path = path
            self.shortenedPath = shortenedPath
        }

        init?(_ dict: [AnyHashable: Any]) {
            if let sshIdentityObj = dict[FavoritesKeys.sshIdentity.rawValue],
               let sshIdentity = SSHIdentity(userDefaultsObject: sshIdentityObj),
               let path = dict[FavoritesKeys.path.rawValue] as? String {
                self.host = sshIdentity
                self.path = path
                self.shortenedPath = dict[FavoritesKeys.shortenedPath.rawValue] as? String
            } else {
                return nil
            }
        }
    }

    private var unfilteredFavorites: [Favorite] = [] {
        didSet {
            filter()
        }
    }
    private var filteredFavorites: [Favorite] = []
    private let favoritesKey = "NoSyncSSHFilePanelFavorites"

    private enum FavoritesKeys: String {
        case sshIdentity
        case path
        case shortenedPath
    }

    // MARK: – Private Pasteboard Type for Reordering

    // Data source items

    class SidebarSectionNode: NSObject {
        var name: String {
            switch identifier {
            case .favorites:
                return "Favorites"
            case .connectedHosts:
                return "Connected Hosts"
            }
        }

        enum Identifier: String {
            case favorites
            case connectedHosts
        }

        static let favorites = SidebarSectionNode(.favorites)
        static let connectedHosts = SidebarSectionNode(.connectedHosts)
        static let allCases = [favorites, connectedHosts]

        let identifier: Identifier

        init(_ identifier: Identifier) {
            self.identifier = identifier
        }

        override var description: String {
            return identifier.rawValue
        }
    }

    init() {
        super.init(frame: .zero)
        setupOutlineView()
        loadFavorites()
        setupScrollView()
        setupConstraints()
    }

    @MainActor
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    var selectedIdentity: SSHIdentity? {
        get {
            guard let selectedItem = sidebarOutlineView.item(
                atRow: sidebarOutlineView.selectedRow
            ) else {
                return nil
            }

            if let favorite = selectedItem as? Favorite {
                return favorite.host
            } else if let host = selectedItem as? SSHIdentity {
                return host
            }

            return nil
        }
        set {
            if let newValue {
                let selectedRow = sidebarOutlineView.selectedRow
                if selectedRow >= 0,
                   let item = sidebarOutlineView.item(atRow: selectedRow) {
                    // Don't change the selection if it's already correct (e.g., you're on a favorite)
                    switch item {
                    case let favorite as Favorite:
                        if favorite.host == newValue {
                            return
                        }
                    case let host as SSHIdentity:
                        if host == newValue {
                            return
                        }
                    default:
                        break
                    }
                }
                if let i = _connectedHosts.firstIndex(of: newValue) {
                    let row = 1 + filteredFavorites.count + 1 + i
                    sidebarOutlineView.selectRowIndexes(
                        IndexSet(integer: row),
                        byExtendingSelection: false
                    )
                    return
                }
            }

            sidebarOutlineView.selectRowIndexes(
                IndexSet(),
                byExtendingSelection: false
            )
        }
    }

    private func filter() {
        filteredFavorites = unfilteredFavorites.filter {
            (delegate?.sidebarHostIsValid(self, host: $0.host)) ?? false
        }
        sidebarOutlineView.reloadData()
    }

    private func loadFavorites() {
        if let dicts = UserDefaults.standard.array(
            forKey: favoritesKey
        ) as? [[String: Any]] {
            unfilteredFavorites = dicts.compactMap { Favorite($0) }
        } else {
            // Import favorites from finder one time.
            let path = NSHomeDirectory() + "/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl3"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                return
            }

            let allowedClasses: NSSet = [
                NSDictionary.self,
                NSArray.self,
                NSData.self,
                NSString.self,
                NSURL.self
            ]

            guard let plist = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses as! Set<AnyHashable>, from: data),
                  let rootDict = plist as? NSDictionary,
                  let items = rootDict["items"] as? [NSDictionary] else {
                return
            }

            for item in items {
                guard let bookmarkData = item["Bookmark"] as? Data else { continue }

                var isStale = false
                if let url = try? URL(resolvingBookmarkData: bookmarkData,
                                      options: [.withoutUI, .withoutMounting],
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &isStale) {
                    unfilteredFavorites.append(Favorite(host: .localhost,
                                                        path: url.path,
                                                        shortenedPath: url.path.lastPathComponent))
                }
            }
            saveFavorites()
        }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(unfilteredFavorites.map { $0.userDefaultsObject }, forKey: favoritesKey)
    }

    private func addFavorite(favorite: Favorite,
                             index: Int) {
        let exists = unfilteredFavorites.contains { existing in
            return existing.host == favorite.host && existing.path == favorite.path
        }

        if !exists {
            let unfilteredIndex = index < 0 ? unfilteredFavorites.count : unfilteredIndex(fromFilteredIndex: index)
            unfilteredFavorites.insert(favorite, at: unfilteredIndex)
            saveFavorites()
            sidebarOutlineView.reloadItem(
                SidebarSectionNode.favorites,
                reloadChildren: true
            )
        }
    }

    private func unfilteredIndex(fromFilteredIndex fi: Int) -> Int {
        if fi >= filteredFavorites.count {
            return filteredFavorites.count
        }
        let sucessor = filteredFavorites[fi]
        if let ui = unfilteredFavorites.firstIndex(of: sucessor) {
            return ui
        }
        return unfilteredFavorites.count
    }

    private func setupOutlineView() {
        sidebarOutlineView = SSHFilePanelSourceList()
        sidebarOutlineView.dataSource = self
        sidebarOutlineView.delegate = self

        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("SidebarColumn")
        )
        column.title = ""
        column.isEditable = false
        sidebarOutlineView.addTableColumn(column)
        sidebarOutlineView.outlineTableColumn = column

        sidebarOutlineView.draggingDestinationFeedbackStyle = .regular

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            for section in SidebarSectionNode.allCases {
                self.sidebarOutlineView.expandItem(section)
            }
        }
    }

    private func setupScrollView() {
        sidebarScrollView = NSScrollView()
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebarScrollView.documentView = sidebarOutlineView
        sidebarScrollView.hasVerticalScroller = true
        sidebarScrollView.hasHorizontalScroller = false
        sidebarScrollView.autohidesScrollers = true
        sidebarScrollView.backgroundColor = NSColor.controlBackgroundColor
        addSubview(sidebarScrollView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            sidebarScrollView.leadingAnchor.constraint(
                equalTo: self.leadingAnchor
            ),
            sidebarScrollView.trailingAnchor.constraint(
                equalTo: self.trailingAnchor
            ),
            sidebarScrollView.topAnchor.constraint(
                equalTo: self.topAnchor
            ),
            sidebarScrollView.bottomAnchor.constraint(
                equalTo: self.bottomAnchor
            )
        ])
    }
}


// MARK: - NSOutlineViewDataSource

@available(macOS 11, *)
extension SSHFilePanelSidebar: NSOutlineViewDataSource {
    func outlineView(
        _ outlineView: NSOutlineView,
        numberOfChildrenOfItem item: Any?
    ) -> Int {
        if item == nil {
            return SidebarSectionNode.allCases.count
        }

        if let section = item as? SidebarSectionNode {
            switch section.identifier {
            case .favorites:
                return filteredFavorites.count
            case .connectedHosts:
                return connectedHosts.count
            }
        }

        return 0
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        child index: Int,
        ofItem item: Any?
    ) -> Any {
        if item == nil {
            return SidebarSectionNode.allCases[index]
        }

        if let section = item as? SidebarSectionNode {
            switch section.identifier {
            case .favorites:
                return filteredFavorites[index]
            case .connectedHosts:
                return connectedHosts[index]
            }
        }

        it_fatalError("Unexpected item type")
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        isItemExpandable item: Any
    ) -> Bool {
        return item is SidebarSectionNode
    }

    // MARK: - Pasteboard Writer for Reordering

    func outlineView(_ outlineView: NSOutlineView,
                     pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        if let favorite = item as? Favorite {
            guard let index = filteredFavorites.firstIndex(where: { existing in
                return existing.host == favorite.host && existing.path == favorite.path
            }) else {
                return nil
            }

            let pbItem = NSPasteboardItem()
            pbItem.setString(
                String(index),
                forType: favoriteReorderPasteboardType
            )
            return pbItem
        }

        return nil
    }

    // MARK: - Drag and Drop Support

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard

        // Reordering existing favorite
        if let types = pasteboard.types,
           types.contains(favoriteReorderPasteboardType),
           let item = item as? SidebarSectionNode,
           item == .favorites {
            return .move
        }

        // Only accept drops on the Favorites section for new folder items or moving existing ones
        if let item = item as? SidebarSectionNode,
           item == .favorites {
            if pasteboard.types?.contains(SSHFilePanelSourceList.sshFileNodeDirectoryPasteboardType) == true ||
                pasteboard.types?.contains(NSPasteboard.PasteboardType(kPasteboardTypeFileURLPromise)) == true ||
                pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self],
                                         options: nil) {
                outlineView.setDropItem(
                    item,
                    dropChildIndex: NSOutlineViewDropOnItemIndex)
                return .copy
            }
        }

        // Check for Finder‐style file URLs and ensure they’re directories
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDir), isDir.boolValue {
                    continue
                } else {
                    return []
                }
            }
            outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }

        return []
    }

    func outlineView(_ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int) -> Bool {
        guard let section = item as? SidebarSectionNode,
              section == .favorites else {
            return false
        }

        let pasteboard = info.draggingPasteboard

        // Handle reordering
        if let indexString = pasteboard.string(forType: favoriteReorderPasteboardType),
           let filteredIndex = Int(indexString) {
            let sourceIndex = unfilteredIndex(fromFilteredIndex: filteredIndex)
            var destIndex = index
            if destIndex < 0 {
                destIndex = unfilteredFavorites.count - 1
            }

            var adjustedDest = destIndex
            if sourceIndex < destIndex {
                adjustedDest -= 1
            }

            let moved = unfilteredFavorites.remove(at: sourceIndex)
            unfilteredFavorites.insert(moved, at: adjustedDest)

            saveFavorites()
            sidebarOutlineView.reloadItem(
                SidebarSectionNode.favorites,
                reloadChildren: true
            )
            return true
        }

        // Handle adding a new favorite
        if let data = pasteboard.data(forType: SSHFilePanelSourceList.sshFileNodeDirectoryPasteboardType) {
            do {
                if let nodeInfo = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSDictionary.self,
                                                                         from: data) as? [AnyHashable: Any] {
                    guard let sshIdentityDict = nodeInfo["sshIdentity"] as? NSDictionary,
                          let fullPath = nodeInfo["fullPath"] as? String,
                          let hostString = sshIdentityDict["host"] as? String,
                          let hostname = sshIdentityDict["hostname"] as? String,
                          let port = sshIdentityDict["port"] as? Int else {
                        return false
                    }

                    let username = sshIdentityDict["username"] as? String
                    let sshIdentity = SSHIdentity(host: hostString,
                                                  hostname: hostname,
                                                  username: username,
                                                  port: port)

                    let insertIndex = index < 0 ? filteredFavorites.count : index
                    addFavorite(favorite: Favorite(
                        host: sshIdentity,
                        path: fullPath,
                        shortenedPath: delegate?.shortPath(sshIdentity: sshIdentity,
                                                           absolutePath: fullPath)),
                                index: insertIndex)
                    return true
                }
            } catch {
                DLog("Failed to decode SSH file node data: \(error)")
            }
        }

        // Check for Finder‐style file URLs and ensure they’re directories
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                let insertIndex = index < 0 ? filteredFavorites.count : index
                let shortenedPath = url.path.hasPrefix(NSHomeDirectory()) ? "~" + url.path.removing(prefix: NSHomeDirectory()) : url.path
                addFavorite(favorite: .init(host: .localhost,
                                            path: url.path,
                                            shortenedPath: shortenedPath),
                            index: insertIndex)
            }
            return true
        }


        return false
    }
}

enum Either<Left, Right> {
    case left(Left)
    case right(Right)

    func handle<T>(
        left: (Left) throws -> T,
        right: (Right) throws -> T
    ) rethrows -> T {
        switch self {
        case .left(let value):
            return try left(value)
        case .right(let value):
            return try right(value)
        }
    }
}

// MARK: - NSOutlineViewDelegate

@available(macOS 11, *)
extension SSHFilePanelSidebar: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any) -> NSView? {
        let identifier: NSUserInterfaceItemIdentifier
        let text: Either<String, NSAttributedString>
        let image: NSImage?

        if let section = item as? SidebarSectionNode {
            identifier = NSUserInterfaceItemIdentifier("HeaderCell")
            let text = section.name
            image = nil

            var cell = outlineView.makeView(
                withIdentifier: identifier,
                owner: self
            ) as? NSTableCellView

            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = identifier

                let textField = NSTextField()
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.isBordered = false
                textField.isEditable = false
                textField.backgroundColor = NSColor.clear
                textField.font = NSFont.systemFont(
                    ofSize: NSFont.smallSystemFontSize,
                    weight: .medium
                )
                textField.lineBreakMode = .byTruncatingTail
                textField.maximumNumberOfLines = 1
                textField.allowsDefaultTighteningForTruncation = false

                cell?.addSubview(textField)
                cell?.textField = textField

                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(
                        equalTo: cell!.leadingAnchor,
                        constant: 0
                    ),
                    textField.trailingAnchor.constraint(
                        equalTo: cell!.trailingAnchor,
                        constant: -8
                    ),
                    textField.centerYAnchor.constraint(
                        equalTo: cell!.centerYAnchor
                    )
                ])
            }

            cell?.textField?.stringValue = text
            return cell
        } else if let favorite = item as? Favorite {
            identifier = NSUserInterfaceItemIdentifier("FavoriteCell")
            let attributedString = NSMutableAttributedString()
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail
            let bigFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let smallFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            let path = NSAttributedString(string: favorite.shortenedPath ?? favorite.path,
                                          attributes: [ .font: bigFont,
                                                        .paragraphStyle: paragraphStyle,
                                                        .foregroundColor: NSColor.controlTextColor])
            let host = NSAttributedString(string: favorite.host.displayName,
                                          attributes: [ .font: smallFont,
                                                        .paragraphStyle: paragraphStyle,
                                                        .foregroundColor: NSColor.controlTextColor ])
            attributedString.append(path)
            attributedString.append(NSAttributedString(string: "\n"))
            attributedString.append(host)
            text = .right(attributedString)
            if favorite.host == .localhost {
                if let template = SystemFolderIconProvider.iconForFolder(
                    at: URL(fileURLWithPath: favorite.path)) {
                    image = template
                    image?.isTemplate = true
                } else {
                    image = NSImage.it_image(
                        forSymbolName: "folder",
                        accessibilityDescription: "Folder",
                        fallbackImageName: "folder",
                        for: SSHFilePanelSidebar.self)
                }
            } else {
                image = NSImage.it_image(
                    forSymbolName: "folder",
                    accessibilityDescription: "Folder",
                    fallbackImageName: "folder",
                    for: SSHFilePanel.self)
            }
        } else if let host = item as? SSHIdentity {
            identifier = NSUserInterfaceItemIdentifier("HostCell")
            text = .left(host.displayName)
            if let template = SystemFolderIconProvider.iconForUTI("com.apple.imac") {
                image = template
                image?.isTemplate = true
            } else {
                image = NSImage.it_image(
                    forSymbolName: "server.rack",
                    accessibilityDescription: "Server",
                    fallbackImageName: "rack",
                    for: SSHFilePanel.self
                )
            }
        } else {
            return nil
        }

        var cell = outlineView.makeView(
            withIdentifier: identifier,
            owner: self
        ) as? NSTableCellView

        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown

            let textField = NSTextField()
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isBordered = false
            textField.isEditable = false
            textField.backgroundColor = NSColor.clear
            textField.textColor = NSColor.labelColor
            textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 2
            textField.allowsDefaultTighteningForTruncation = false
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            cell?.addSubview(imageView)
            cell?.addSubview(textField)
            cell?.imageView = imageView
            cell?.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 3),
                imageView.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
                imageView.heightAnchor.constraint(equalToConstant: 14),
                imageView.widthAnchor.constraint(equalToConstant: 14),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell!.trailingAnchor),
                textField.topAnchor.constraint(equalTo: cell!.topAnchor, constant: 4),
                textField.bottomAnchor.constraint(equalTo: cell!.bottomAnchor, constant: -4)
            ])
        }

        text.handle { string in
            cell?.textField?.stringValue = string
        } right: { attributedString in
            cell?.textField?.attributedStringValue = attributedString
        }

        cell?.imageView?.image = image
        return cell
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        isGroupItem item: Any
    ) -> Bool {
        return item is SidebarSectionNode
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        shouldSelectItem item: Any
    ) -> Bool {
        switch item {
        case let favorite as Favorite:
            return (delegate?.sidebarHostIsValid(self, host: favorite.host)) ?? false
        case let host as SSHIdentity:
            return delegate?.sidebarHostIsValid(self, host: host) ?? false
        default:
            return false
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        // No-op
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let selectedItem = sidebarOutlineView.item(
            atRow: sidebarOutlineView.selectedRow
        ) else {
            return
        }

        if let favorite = selectedItem as? Favorite {
            delegate?.sidebarDidSelectFavorite(
                self,
                host: favorite.host,
                path: favorite.path
            )
        }
        else if let host = selectedItem as? SSHIdentity {
            delegate?.sidebarDidSelectHost(self, host: host)
        }
    }
}
