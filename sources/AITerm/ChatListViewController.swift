//
//  ChatListViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

import AppKit
import Carbon.HIToolbox

protocol ChatListViewControllerDelegate: AnyObject, ChatSearchResultsViewControllerDelegate {
    func chatListViewControllerDidTapNewChat(_ viewController: ChatListViewController)
    func chatListViewController(_ chatListViewController: ChatListViewController,
                                didSelectChat chatID: String?)
    func chatListViewController(_ chatListViewController: ChatListViewController,
                                renameChat chatID: String)
    func chatListViewController(_ chatListViewController: ChatListViewController,
                                deleteChats chatIDs: [String])
}

private protocol ChatListTableViewDelegate: AnyObject {
    func chatListTableView(_ tableView: ChatListTableView,
                           didReceiveMouseDown event: NSEvent) -> Bool
    func chatListTableViewDidRequestRenameSelectedChat(_ tableView: ChatListTableView)
    func chatListTableViewDidRequestDeleteSelectedChat(_ tableView: ChatListTableView)
    func chatListTableView(_ tableView: ChatListTableView, menuForRow row: Int) -> NSMenu?
}

private class ChatListTableView: NSTableView {
    weak var chatListTableViewDelegate: ChatListTableViewDelegate?

    override func mouseDown(with event: NSEvent) {
        if chatListTableViewDelegate?.chatListTableView(self, didReceiveMouseDown: event) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event) else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func keyDown(with event: NSEvent) {
        let key = Int(event.keyCode)
        if key == kVK_Delete || key == kVK_ForwardDelete {
            chatListTableViewDelegate?.chatListTableViewDidRequestDeleteSelectedChat(self)
            return
        }
        if key == kVK_Return || key == kVK_ANSI_KeypadEnter {
            chatListTableViewDelegate?.chatListTableViewDidRequestRenameSelectedChat(self)
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        let row = self.row(at: location)
        guard row >= 0 else {
            return nil
        }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return chatListTableViewDelegate?.chatListTableView(self, menuForRow: row)
    }
}

class ChatListViewController: NSViewController {
    weak var dataSource: ChatListDataSource?
    weak var delegate: ChatListViewControllerDelegate?
    private let prototypeCell = ChatCellView(frame: .zero,
                                             chat: nil,
                                             dataSource: nil,
                                             autoupdateDate: false)
    private let tableView = ChatListTableView()
    private let scrollView = NSScrollView()
    private var contextMenuEventMonitor: Any?
    private let searchField = {
        let field = NSSearchField()
        field.translatesAutoresizingMaskIntoConstraints = false
        // Configure the underlying text field cell for proper scrolling
        if let cell = field.cell as? NSSearchFieldCell {
            cell.isScrollable = true
            cell.wraps = false
            cell.lineBreakMode = .byClipping
        }
        return field
    }()

    // Header UI
    private let headerView = NSView()
    private let newChatButton: NSButton = {
        let image = NSImage(systemSymbolName: SFSymbol.plus.rawValue, accessibilityDescription: nil)!
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.refusesFirstResponder = true
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private var canExitSearchMode = true
    private var searchMode = false {
        didSet {
            if searchMode == oldValue {
                return
            }
            searchResultsViewController.view.isHidden = !searchMode
            if !searchMode, tableView.selectedRow != -1 {
                tableView.scrollRowToVisible(tableView.selectedRow)
            }
        }
    }

    private let searchResultsViewController: ChatSearchResultsViewController = {
        let vc = ChatSearchResultsViewController()
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        vc.view.isHidden = true
        return vc
    }()

    deinit {
        removeContextMenuEventMonitor()
    }

    override func loadView() {
        searchField.delegate = self
        
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        // Setup header view
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerView.addSubview(newChatButton)
        headerView.addSubview(searchField)

        if #available(macOS 26, *) {
            NSLayoutConstraint.activate([
                newChatButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
                newChatButton.heightAnchor.constraint(equalTo: searchField.heightAnchor),
                newChatButton.widthAnchor.constraint(equalTo: newChatButton.heightAnchor),

                searchField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
                searchField.topAnchor.constraint(equalTo: headerView.safeAreaLayoutGuide.topAnchor),
                searchField.trailingAnchor.constraint(equalTo: newChatButton.leadingAnchor, constant: -8),

                headerView.bottomAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            ])
        } else {
            NSLayoutConstraint.activate([
                newChatButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
                newChatButton.heightAnchor.constraint(equalTo: searchField.heightAnchor),
                newChatButton.widthAnchor.constraint(equalTo: newChatButton.heightAnchor),
                newChatButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor,
                                                        constant: -4),

                searchField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
                searchField.topAnchor.constraint(equalTo: headerView.safeAreaLayoutGuide.topAnchor),
                searchField.trailingAnchor.constraint(equalTo: newChatButton.leadingAnchor, constant: -4),

                headerView.bottomAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            ])
        }
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            newChatButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
        ])
        headerView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        newChatButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        // Setup table view
        setupTableView()
        view.addSubview(scrollView)
        searchResultsViewController.dataSource = self
        searchResultsViewController.delegate = self
        let srp = searchResultsViewController.view
        view.addSubview(srp)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NSLayoutConstraint.activate([
            srp.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            srp.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            srp.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            srp.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(forName: ChatListModel.metadataDidChange,
                                               object: nil,
                                               queue: nil) { [weak self] notification in
            guard let self else {
                return
            }
            // A change scoped to one chat (an icon arrival) carries its
            // ID and cannot affect row height, order, or selection;
            // reload just that row. A full reload here is expensive: it
            // re-measures every row via the prototype cell, refetching
            // snippets and resubscribing each one to the broker.
            if let changedID = notification.userInfo?[ChatListModel.chatIDUserInfoKey] as? String {
                if let i = dataSource?.chatListViewController(self, indexOfChatID: changedID) {
                    tableView.reloadData(forRowIndexes: IndexSet(integer: i),
                                         columnIndexes: IndexSet(integer: 0))
                }
                return
            }
            ignoreSelectionChange = true
            let activeChatID = self.selectedChatID
            let selectedChatIDs = self.selectedChatIDs()
            self.tableView.reloadData()
            var selectedRows = IndexSet()
            for chatID in selectedChatIDs {
                if let row = dataSource?.chatListViewController(self, indexOfChatID: chatID) {
                    selectedRows.insert(row)
                }
            }
            if selectedRows.isEmpty,
               let activeChatID,
               let row = dataSource?.chatListViewController(self, indexOfChatID: activeChatID) {
                selectedRows.insert(row)
            }
            tableView.selectRowIndexes(selectedRows, byExtendingSelection: false)
            selectionAnchorRow = selectedRows.first
            ignoreSelectionChange = false
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installContextMenuEventMonitor()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeContextMenuEventMonitor()
    }

    private var ignoreSelectionChange = false
    private var selectionAnchorRow: Int?
    var selectedChatID: String?

    private func setupTableView() {
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.chatListTableViewDelegate = self
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.menu = NSMenu()
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ChatColumn"))
        tableView.addTableColumn(column)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        newChatButton.target = self
        newChatButton.action = #selector(createNewChat)
    }

    var mostRecentChat: Chat? {
        dataSource?.chatListViewController(self, chatAt: 0)
    }

    func selectMostRecent(forGuid guid: String?) -> Bool {
        let index: Int
        let found: Bool
        if let guid, let i = dataSource?.firstIndex(forGuid: guid) {
            index = i
            found = true
        } else {
            index = 0
            found = false
        }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        selectionAnchorRow = index
        selectedChatID = findSelectedChatID()
        return found
    }

    @objc private func createNewChat() {
        delegate?.chatListViewControllerDidTapNewChat(self)
    }

    func reloadData() {
        tableView.reloadData()
    }

    func select(chatID: String) {
        guard let dataSource else {
            return
        }
        let i = (0..<dataSource.numberOfChats(in: self)).first { j in
            dataSource.chatListViewController(self, chatAt: j).id == chatID
        }
        guard let i else {
            return
        }
        if canExitSearchMode {
            searchField.stringValue = ""
            searchMode = false
            searchResultsViewController.query = ""
        }

        selectedChatID = chatID
        tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        selectionAnchorRow = i
    }

    @objc private func deleteSelectedChats(_ sender: Any?) {
        let chatIDs = selectedChatIDs()
        guard !chatIDs.isEmpty else {
            return
        }
        delegate?.chatListViewController(self, deleteChats: chatIDs)
    }

    @objc private func renameSelectedChat(_ sender: Any?) {
        let chatIDs = selectedChatIDs()
        guard chatIDs.count == 1,
              let chatID = chatIDs.first else {
            return
        }
        delegate?.chatListViewController(self, renameChat: chatID)
    }

    private func installContextMenuEventMonitor() {
        guard contextMenuEventMonitor == nil else {
            return
        }
        contextMenuEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown]) { [weak self] event in
                guard let self else {
                    return event
                }
                return self.handleContextMenuEvent(event)
            }
    }

    private func removeContextMenuEventMonitor() {
        if let contextMenuEventMonitor {
            NSEvent.removeMonitor(contextMenuEventMonitor)
            self.contextMenuEventMonitor = nil
        }
    }

    private func handleContextMenuEvent(_ event: NSEvent) -> NSEvent? {
        guard let window = view.window,
              event.window === window else {
            return event
        }
        let point = tableView.convert(event.locationInWindow, from: nil)
        guard tableView.bounds.contains(point) else {
            return event
        }
        let row = tableView.row(at: point)
        guard row >= 0,
              row < tableView.numberOfRows else {
            return event
        }
        if !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row),
                                       byExtendingSelection: false)
        }
        selectedChatID = dataSource?.chatListViewController(self, chatAt: row).id
        guard let menu = contextMenu(forRow: row) else {
            return event
        }
        menu.popUp(positioning: nil, at: point, in: tableView)
        return nil
    }

    private func contextMenu(forRow row: Int) -> NSMenu? {
        guard dataSource != nil,
              row >= 0,
              row < tableView.numberOfRows else {
            return nil
        }
        let menu = NSMenu()
        let count = max(1, selectedChatIDs().count)
        if count == 1 {
            menu.addItem(withTitle: "Rename Chat",
                         action: #selector(renameSelectedChat(_:)),
                         target: self)
            menu.addItem(.separator())
        }
        let title = count == 1 ? "Delete Chat" : "Delete \(count) Chats"
        menu.addItem(withTitle: title,
                     action: #selector(deleteSelectedChats(_:)),
                     target: self)
        return menu
    }
}

extension ChatListViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return dataSource?.numberOfChats(in: self) ?? 0
    }
}

// Custom row view that maintains selection appearance when not first responder
class ChatTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        // Keep blue selection when selected and window is key, even if table isn't first responder
        get {
            return isSelected && (window?.isKeyWindow == true || window == nil)
        }
        set {
            super.isEmphasized = newValue
        }
    }
}

extension ChatListViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return ChatTableRowView()
    }

    private func view(forRow row: Int) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("ChatCell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ChatCellView

        let chat = dataSource?.chatListViewController(self, chatAt: row)

        if cell == nil {
            let rect = NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
            cell = ChatCellView(frame: rect, chat: chat, dataSource: dataSource, autoupdateDate: true)
            cell?.identifier = identifier
        } else if let dataSource, let chat {
            cell?.load(chat: chat, dataSource: dataSource)
        }
        DLog("row \(row) has title \(String(describing: chat?.title)) (label=\(cell!.titleLabel.stringValue)) and id \(String(describing: chat?.id))")
        return cell!
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        return view(forRow: row)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let chat = dataSource?.chatListViewController(self, chatAt: row), let dataSource else {
            return 0
        }
        prototypeCell.load(chat: chat, dataSource: dataSource)

        prototypeCell.frame = NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 0)
        prototypeCell.layoutSubtreeIfNeeded()

        let height = prototypeCell.fittingSize.height
        return height
    }

    func findSelectedChatID() -> String? {
        guard let selectedRow = tableView.selectedRowIndexes.first else {
            return nil
        }
        return dataSource?.chatListViewController(self, chatAt: selectedRow).id
    }

    func selectedChatIDs() -> [String] {
        guard let dataSource else {
            return []
        }
        return tableView.selectedRowIndexes.compactMap { row in
            guard row >= 0, row < dataSource.numberOfChats(in: self) else {
                return nil
            }
            return dataSource.chatListViewController(self, chatAt: row).id
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if ignoreSelectionChange {
            return
        }
        let selectedIDs = selectedChatIDs()
        let chatID: String?
        if let selectedChatID,
           selectedIDs.contains(selectedChatID) {
            chatID = selectedChatID
        } else {
            chatID = selectedIDs.first
        }
        selectedChatID = chatID
        delegate?.chatListViewController(self, didSelectChat: chatID)
    }
}

extension ChatListViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        searchMode = !searchField.stringValue.isEmpty
        searchResultsViewController.query = searchField.stringValue
    }
}

extension ChatListViewController: ChatSearchResultsDataSource {
    func chatSearchResultsIterator(query: String) -> AnySequence<ChatSearchResult> {
        return dataSource?.chatSearchResultsIterator(query: query) ?? AnySequence([])
    }
}

extension ChatListViewController: ChatSearchResultsViewControllerDelegate {
    func chatSearchResultsDidSelect(_ result: ChatSearchResult) {
        canExitSearchMode = false
        delegate?.chatSearchResultsDidSelect(result)
        canExitSearchMode = true
    }
}

extension ChatListViewController: ChatListTableViewDelegate {
    fileprivate func chatListTableView(_ tableView: ChatListTableView,
                                       didReceiveMouseDown event: NSEvent) -> Bool {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: point)
        guard row >= 0 else {
            return false
        }
        tableView.window?.makeFirstResponder(tableView)

        var selectedRows = tableView.selectedRowIndexes
        let modifiers = event.modifierFlags.intersection([.command, .shift])
        if modifiers.contains(.shift) {
            let anchor = selectionAnchorRow ?? selectedRows.first ?? row
            let range = IndexSet(integersIn: min(anchor, row)...max(anchor, row))
            if modifiers.contains(.command) {
                selectedRows.formUnion(range)
                tableView.selectRowIndexes(selectedRows, byExtendingSelection: false)
            } else {
                tableView.selectRowIndexes(range, byExtendingSelection: false)
            }
        } else if modifiers.contains(.command) {
            if selectedRows.contains(row) {
                selectedRows.remove(row)
            } else {
                selectedRows.insert(row)
            }
            tableView.selectRowIndexes(selectedRows, byExtendingSelection: false)
            selectionAnchorRow = row
        } else {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            selectionAnchorRow = row
        }
        return true
    }

    fileprivate func chatListTableViewDidRequestDeleteSelectedChat(_ tableView: ChatListTableView) {
        deleteSelectedChats(tableView)
    }

    fileprivate func chatListTableViewDidRequestRenameSelectedChat(_ tableView: ChatListTableView) {
        renameSelectedChat(tableView)
    }

    fileprivate func chatListTableView(_ tableView: ChatListTableView, menuForRow row: Int) -> NSMenu? {
        contextMenu(forRow: row)
    }
}
