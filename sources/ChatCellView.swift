//
//  ChatCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/18/25.
//

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
            snippet = "AI is typing…"
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
        DLog("Update for \(chatID) with typing=\(typing): \(update)")
        switch update {
        case let .typingStatus(typing, participant):
            if participant == .agent {
                if typing {
                    self.typing = true
                    DLog("set typing=true in \(chatID)")
                    snippet = "AI is typing…"
                } else {
                    self.typing = false
                    DLog("set typing=true in \(false)")
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
        dateLabel.textColor = NSColor.textColor
        dateLabel.alphaValue = 0.75
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
