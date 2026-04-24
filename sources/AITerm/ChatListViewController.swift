//
//  ChatListViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

import AppKit

protocol ChatListViewControllerDelegate: AnyObject, ChatSearchResultsViewControllerDelegate {
    func chatListViewControllerDidTapNewChat(_ viewController: ChatListViewController)
    func chatListViewController(_ chatListViewController: ChatListViewController,
                                didSelectChat chatID: String?)

}

class ChatListViewController: NSViewController {
    weak var dataSource: ChatListDataSource?
    weak var delegate: ChatListViewControllerDelegate?
    private let prototypeCell = ChatCellView(frame: .zero,
                                             chat: nil,
                                             dataSource: nil,
                                             autoupdateDate: false)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
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
        if #available(macOS 26.0, *) {
            button.controlSize = .large
            button.bezelStyle = .glass
            button.borderShape = .circle
            button.isBordered = true
        } else {
            button.isBordered = false
        }
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
            ignoreSelectionChange = true
            let chatID = self.selectedChatID
            self.tableView.reloadData()
            if let chatID, let i = dataSource?.chatListViewController(self, indexOfChatID: chatID) {
                tableView.selectRowIndexes(IndexSet(integer: i),
                                           byExtendingSelection: false)
            } else {
                tableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
            }
            ignoreSelectionChange = false
        }
    }
    private var ignoreSelectionChange = false
    var selectedChatID: String?

    private func setupTableView() {
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
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
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 else {
            return nil
        }
        return dataSource?.chatListViewController(self, chatAt: selectedRow).id
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if ignoreSelectionChange {
            return
        }
        let chatID = findSelectedChatID()
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
