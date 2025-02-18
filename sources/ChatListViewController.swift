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
    private let prototypeCell = ChatCellView(frame: .zero,
                                             chat: nil,
                                             dataSource: nil,
                                             autoupdateDate: false)
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
        print("qqq row \(row) has title \(chat?.title) (label=\(cell!.titleLabel.stringValue)) and id \(chat?.id)")
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
        if let chatID = findSelectedChatID() {
            selectedChatID = chatID
            delegate?.chatListViewController(self, didSelectChat: chatID)
        }
    }
}

class ChatCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let dateLabel = NSTextField(labelWithString: "")
    let snippetLabel = NSTextField(labelWithString: "")
    private var typing = false

    var snippet: String? {
        didSet {
            snippetLabel.stringValue = snippet?.replacingOccurrences(of: "\n", with: " ") ?? ""
        }
    }

    private var date: Date? {
        didSet {
            updateDateLabel()
        }
    }
    private var timer: Timer?
    private var subscription: ChatBroker.Subscription?

    init(frame frameRect: NSRect, chat: Chat?, dataSource: ChatListDataSource?, autoupdateDate: Bool) {
        super.init(frame: frameRect)
        setupViews()
        if autoupdateDate {
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.updateDateLabel()
            }
        }
        if let chat, let dataSource {
            load(chat: chat, dataSource: dataSource)
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError()
    }

    deinit {
        timer?.invalidate()
        subscription?.unsubscribe()
    }

    func load(chat: Chat, dataSource: ChatListDataSource) {
        if TypingStatusModel.instance.isTyping(participant: .agent, chatID: chat.id) {
            snippet = "Agent is thinking…"
        } else {
            self.snippet = dataSource.snippet(forChatID: chat.id)
        }
        self.date = chat.lastModifiedDate
        titleLabel.stringValue = chat.title
        typing = false

        let chatID = chat.id
        subscription?.unsubscribe()
        subscription = ChatBroker.instance?.subscribe(
            chatID: chatID,
            registrationProvider: nil,
            closure: { [weak self, weak dataSource] update in
                self?.apply(update: update, chatID: chatID, dataSource: dataSource)
        })
    }

    private func apply(update: ChatBroker.Update,
                       chatID: String,
                       dataSource: ChatListDataSource?) {
        print("qqq Update for \(chatID) with typing=\(typing): \(update)")
        switch update {
        case let .typingStatus(typing, participant):
            if participant == .agent {
                if typing {
                    self.typing = true
                    print("qqq set typing=true in \(chatID)")
                    snippet = "Agent is thinking…"
                } else {
                    self.typing = false
                    print("qqq set typing=true in \(false)")
                    snippet = dataSource?.snippet(forChatID: chatID) ?? ""
                }
            }
        case let .delivery(message, _):
            if !typing, let snippet = message.snippetText {
                self.snippet = snippet
            }
        }
    }

    private func updateDateLabel() {
        if let date {
            dateLabel.stringValue = DateFormatter.compactDateDifferenceString(from: date)
        } else {
            dateLabel.stringValue = ""
        }
    }

    private func setupViews() {
        // Configure title label
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        if let cell = titleLabel.cell as? NSTextFieldCell {
            cell.lineBreakMode = .byTruncatingTail
            cell.truncatesLastVisibleLine = true
        }
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        // Configure date label
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.textColor = NSColor.textColor.withAlphaComponent(0.75)
        dateLabel.isEditable = false
        dateLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        addSubview(dateLabel)

        // Configure snippet label
        snippetLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        if let cell = snippetLabel.cell as? NSTextFieldCell {
            cell.lineBreakMode = .byTruncatingTail
            cell.truncatesLastVisibleLine = true
        }
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        snippetLabel.isEditable = false
        snippetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        snippetLabel.alphaValue = 0.75
        snippetLabel.maximumNumberOfLines = 1
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.usesSingleLineMode = true
        addSubview(snippetLabel)

        NSLayoutConstraint.activate([
            // Top row: title and date
            titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 5),
            titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 5),
            dateLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -5),
            dateLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -8),

            // Snippet below title/date, spanning full width with same insets
            snippetLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 5),
            snippetLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -5),
            snippetLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            snippetLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -5)
        ])

        updateDateLabel()
    }
}
