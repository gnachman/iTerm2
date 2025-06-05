//
//  SSHFilePanelSourceList.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

@available(macOS 11, *)
class SSHFilePanelSourceList: NSOutlineView {
    init() {
        super.init(frame: .zero)
        style = .sourceList
        floatsGroupRows = false
        rowHeight = 21
        headerView = nil
        focusRingType = .none
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
}

@available(macOS 11, *)
class SSHFilePanelSidebar: NSView {
    private(set) var sidebarOutlineView: SSHFilePanelSourceList!
    private var sidebarScrollView: NSScrollView!

    weak var delegate: SSHFilePanelSidebarDelegate?

    private var _connectedHosts: [SSHIdentity] = []
    var connectedHosts: [SSHIdentity] {
        get {
            _connectedHosts
        }
        set {
            _connectedHosts = newValue
            sidebarOutlineView.reloadData()
            selectedIdentity = self.selectedIdentity
        }
    }

    private var favorites: [(host: SSHIdentity, path: String)] = []
    private let favoritesKey = "SSHFilePanelFavorites"

    private enum FavoritesKeys: String {
        case host
        case hostname
        case username
        case port
        case path
    }

    // Data source items
    private enum SidebarSection: String, CaseIterable {
        case favorites = "Favorites"
        case connectedHosts = "Connected Hosts"
    }

    init() {
        super.init(frame: .zero)
        loadFavorites()
        setupOutlineView()
        setupScrollView()
        setupConstraints()
    }

    @MainActor
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    var selectedIdentity: SSHIdentity? {
        get {
            guard let selectedItem = sidebarOutlineView.item(atRow: sidebarOutlineView.selectedRow) else {
                return nil
            }

            if let favorite = selectedItem as? (host: SSHIdentity, path: String) {
                return favorite.host
            } else if let host = selectedItem as? SSHIdentity {
                return host
            }
            return nil
        }
        set {
            if let newValue, let i = _connectedHosts.firstIndex(of: newValue) {
                sidebarOutlineView.selectRowIndexes(IndexSet(integer: 1 + favorites.count + 1 + i),
                                                    byExtendingSelection: false)
            } else {
                sidebarOutlineView.selectRowIndexes(IndexSet(),
                                                    byExtendingSelection: false)
            }
        }
    }

    private func loadFavorites() {
        if let dicts = UserDefaults.standard.array(forKey: favoritesKey) as? [[String: String]] {
            for dict in dicts {
                let host = dict[FavoritesKeys.host.rawValue]
                let hostname = dict[FavoritesKeys.hostname.rawValue]
                let username = dict[FavoritesKeys.username.rawValue]
                let path = dict[FavoritesKeys.path.rawValue]
                let portString = dict[FavoritesKeys.port.rawValue]
                if let host, let hostname, let path, let portString, let port = Int(portString) {
                    favorites.append((host: SSHIdentity(host: host,
                                                        hostname: hostname,
                                                        username: username,
                                                        port: port),
                                      path: path))
                }
            }
        }
    }

    private func setupOutlineView() {
        // Create outline view
        sidebarOutlineView = SSHFilePanelSourceList()
        sidebarOutlineView.dataSource = self
        sidebarOutlineView.delegate = self

        // Add single column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.title = ""
        column.isEditable = false
        sidebarOutlineView.addTableColumn(column)
        sidebarOutlineView.outlineTableColumn = column

        // Expand sections by default
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for section in SidebarSection.allCases {
                self.sidebarOutlineView.expandItem(section)
            }
        }
    }

    private func setupScrollView() {
        // Create scroll view for outline view
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
            sidebarScrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            sidebarScrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            sidebarScrollView.topAnchor.constraint(equalTo: self.topAnchor),
            sidebarScrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
    }
}

// MARK: - NSOutlineViewDataSource
@available(macOS 11, *)
extension SSHFilePanelSidebar: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // Root level - return number of sections
            return SidebarSection.allCases.count
        }

        if let section = item as? SidebarSection {
            switch section {
            case .favorites:
                return favorites.count
            case .connectedHosts:
                return connectedHosts.count
            }
        }

        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            // Root level - return sections
            return SidebarSection.allCases[index]
        }

        if let section = item as? SidebarSection {
            switch section {
            case .favorites:
                return favorites[index]
            case .connectedHosts:
                return connectedHosts[index]
            }
        }

        it_fatalError("Unexpected item type")
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is SidebarSection
    }
}

// MARK: - NSOutlineViewDelegate
@available(macOS 11, *)
extension SSHFilePanelSidebar: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier: NSUserInterfaceItemIdentifier
        let text: String
        let image: NSImage?

        if let section = item as? SidebarSection {
            // Section header
            identifier = NSUserInterfaceItemIdentifier("HeaderCell")
            text = section.rawValue
            image = nil

            var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = identifier

                let textField = NSTextField()
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.isBordered = false
                textField.isEditable = false
                textField.backgroundColor = NSColor.clear
                textField.textColor = NSColor.controlTextColor
                textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
                textField.lineBreakMode = .byTruncatingTail
                textField.maximumNumberOfLines = 1
                textField.allowsDefaultTighteningForTruncation = false

                cell?.addSubview(textField)
                cell?.textField = textField

                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
                ])
            }

            cell?.textField?.stringValue = text
            return cell

        } else if let favorite = item as? (host: SSHIdentity, path: String) {
            // Favorite item
            identifier = NSUserInterfaceItemIdentifier("FavoriteCell")
            text = "\(favorite.host.displayName) - \(favorite.path)"
            image = NSImage.it_image(forSymbolName: "folder",
                                   accessibilityDescription: "Folder",
                                   fallbackImageName: "folder",
                                   for: SSHFilePanel.self)

        } else if let host = item as? SSHIdentity {
            // Connected host item
            identifier = NSUserInterfaceItemIdentifier("HostCell")
            text = host.displayName
            image = NSImage.it_image(forSymbolName: "desktopcomputer",
                                   accessibilityDescription: "desktopcomputer",
                                   fallbackImageName: "folder",
                                   for: SSHFilePanel.self)

        } else {
            return nil
        }

        // Create or reuse cell for non-header items
        var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
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
            textField.maximumNumberOfLines = 1
            textField.allowsDefaultTighteningForTruncation = false

            cell?.addSubview(imageView)
            cell?.addSubview(textField)
            cell?.imageView = imageView
            cell?.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 16),
                imageView.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }

        cell?.textField?.stringValue = text
        cell?.imageView?.image = image
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return item is SidebarSection
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        // Only allow selection of non-group items (favorites and hosts)
        return !(item is SidebarSection)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        // Handle expansion events if needed
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let selectedItem = sidebarOutlineView.item(atRow: sidebarOutlineView.selectedRow) else {
            return
        }

        if let favorite = selectedItem as? (host: SSHIdentity, path: String) {
            delegate?.sidebarDidSelectFavorite(self, host: favorite.host, path: favorite.path)
        } else if let host = selectedItem as? SSHIdentity {
            delegate?.sidebarDidSelectHost(self, host: host)
        }
    }
}
