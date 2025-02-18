//
//  ChatListViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

import AppKit

protocol ChatListViewControllerDelegate: AnyObject {
    func chatListViewControllerDidTapNewChat(_ viewController: ChatListViewController)
    func chatListViewController(_ chatListViewController: ChatListViewController,
                                didSelectChat chatID: String)

}

class ChatListViewController: NSViewController {
    weak var dataSource: ChatListDataSource?
    weak var delegate: ChatListViewControllerDelegate?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    
    // Header UI
    private let headerView = NSView()
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Chats")
        label.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private let newChatButton: NSButton = {
        let button: NSButton
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil) {
            button = NSButton(image: image, target: nil, action: nil)
            button.isBordered = false
        } else {
            button = NSButton(title: "New Chat", target: nil, action: nil)
        }
        button.refusesFirstResponder = true
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        // Setup header view
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(newChatButton)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            newChatButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            newChatButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])

        // Setup table view
        setupTableView()
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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

    func selectMostRecent() {
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        selectedChatID = findSelectedChatID()
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
        selectedChatID = chatID
        tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
    }
}

extension ChatListViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return dataSource?.numberOfChats(in: self) ?? 0
    }
}

extension ChatListViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ChatCell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ChatCellView

        let chat = dataSource?.chatListViewController(self, chatAt: row)

        if cell == nil {
            let rect = NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
            cell = ChatCellView(frame: rect, date: chat?.lastModifiedDate)
            cell?.identifier = identifier
        } else {
            cell?.date = chat?.lastModifiedDate
        }

        cell?.titleLabel.stringValue = chat?.title ?? ""

        return cell
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
        if let chatID = findSelectedChatID() {
            selectedChatID = chatID
            delegate?.chatListViewController(self, didSelectChat: chatID)
        }
    }
}

class ChatCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let dateLabel = NSTextField(labelWithString: "")
    var date: Date? {
        didSet {
            updateDateLabel()
        }
    }
    private var timer: Timer?

    init(frame frameRect: NSRect, date: Date?) {
        self.date = date
        super.init(frame: frameRect)
        setupViews()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true, block: { [weak self] _ in
            self?.updateDateLabel()
        })
    }

    required init?(coder: NSCoder) {
        it_fatalError()
    }

    deinit {
        timer?.invalidate()
    }

    private func updateDateLabel(){
        if let date {
            dateLabel.stringValue = DateFormatter.compactDateDifferenceString(from: date)
        } else {
            dateLabel.stringValue = ""
        }
    }

    private func setupViews() {
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        addSubview(titleLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.textColor = NSColor.textColor.withAlphaComponent(0.75)
        dateLabel.isEditable = false
        dateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(dateLabel)

        // Layout: titleLabel left, dateLabel right, both vertically centered.
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 5),
            titleLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            dateLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -5),
            dateLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -8)
        ])

        updateDateLabel()
    }
}
