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
    private let iconView = NSImageView()
    private var typing = false

    // Display size of the circular chat icon, in points.
    private static let iconDiameter: CGFloat = 32

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
        iconView.image = Self.iconImage(for: chat)
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
                    DLog("set typing=false in \(chatID)")
                    snippet = dataSource?.snippet(forChatID: chatID) ?? ""
                }
            }
        case let .delivery(message, _, _):
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

    // Chats without an icon (no AI-generated title yet, or icon
    // generation failed) get a default chat-bubble icon. The circular
    // clip happens in the view's layer, not the image.
    //
    // Decoded icons are cached: load() runs for every visible cell AND
    // for every row during height measurement on each reloadData, and
    // metadataDidChange-driven reloads happen on every message. Without
    // the cache that's on the order of N PNG decodes per incoming
    // message. Keyed by the PNG data itself, so a regenerated icon
    // misses the cache naturally and the stale entry ages out under
    // NSCache eviction.
    private static let iconCache = NSCache<NSData, NSImage>()

    private static func iconImage(for chat: Chat) -> NSImage {
        guard let data = chat.icon else {
            return defaultIcon
        }
        let key = data as NSData
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(data: data) else {
            return defaultIcon
        }
        iconCache.setObject(image, forKey: key)
        return image
    }

    // Drawn lazily by AppKit so the colors track appearance changes.
    private static let defaultIcon: NSImage = {
        let size = NSSize(width: iconDiameter, height: iconDiameter)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.systemGray.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: iconDiameter * 0.45,
                                                            weight: .medium)
            if let symbol = NSImage(systemSymbolName: SFSymbol.message.rawValue,
                                    accessibilityDescription: "Chat")?
                .withSymbolConfiguration(configuration)?
                .it_image(withTintColor: .white) {
                let symbolSize = symbol.size
                let origin = NSPoint(x: rect.midX - symbolSize.width / 2,
                                     y: rect.midY - symbolSize.height / 2)
                symbol.draw(at: origin,
                            from: .zero,
                            operation: .sourceOver,
                            fraction: 1)
            }
            return true
        }
    }()

    private func setupViews() {
        // Configure icon view. The layer clips the square generated
        // image to a circle.
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = Self.iconDiameter / 2
        iconView.layer?.masksToBounds = true
        iconView.image = Self.defaultIcon
        addSubview(iconView)

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
            // Icon at the leading edge, vertically centered. The
            // greater-than-or-equal top inset keeps the fitting height
            // from collapsing below the icon.
            iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 5),
            iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: self.topAnchor, constant: 5),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconDiameter),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconDiameter),

            // Top row: title and date
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 5),
            dateLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -5),
            dateLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -8),

            // Snippet below title/date, aligned with the title
            snippetLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            snippetLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -5),
            snippetLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            snippetLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -5)
        ])

        updateDateLabel()
    }
}
