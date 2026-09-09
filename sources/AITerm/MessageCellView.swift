import Cocoa

@objc
class MessageCellView: NSView {
    var textSelectable = true
    var rightClickMonitor: Any?
    var editable: Bool = false
    // store the messageUniqueID so that the edit button can pass it along.
    var messageUniqueID: UUID?
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 8
    static let horizontalEdgePadding: CGFloat = 8
    // Callback for the edit button.
    var editButtonClicked: ((UUID) -> Void)?
    var forkButtonClicked: ((UUID) -> Void)?
    var deleteButtonClicked: ((UUID) -> Void)?

    // Cached at configure-time so layout() and the static height helper
    // both see the same bubble width budget.
    var configuredMaxBubbleWidth: CGFloat = 0

    override var description: String {
        "<\(Self.self): \(it_addressString) editable=\(editable)>"
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    deinit {
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if textSelectable {
            return super.hitTest(point)
        }
        return self
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func setupViews() {
    }

    func updateColors() {
    }

    static func maxBubbleWidth(tableViewWidth: CGFloat) -> CGFloat {
        return max(16, tableViewWidth * 0.7)
    }

    func maxBubbleWidth(tableViewWidth: CGFloat) -> CGFloat {
        return Self.maxBubbleWidth(tableViewWidth: tableViewWidth)
    }

    override var menu: NSMenu? {
        get {
            DLog("menu \(self)")
            // Localization unneeded
            let menu = NSMenu(title: "Context Menu")
            if editable {
                menu.addItem(makeEditItem())
            }

            let copyItem = NSMenuItem(title: iTermLocalizedCopy(), action: #selector(copyMenuItemClicked(_:)), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)

            if editable {
                menu.addItem(makeForkItem())
                menu.addItem(makeDeleteItem())
            }

            return menu
        }
        set {
            RLog("Unexpected call to set menu")
        }
    }

    // Appends the message-level actions (Edit, Fork, Delete) to a menu that
    // already carries its own items, such as an NSTextView's default
    // right-click menu. Does nothing when the message isn't editable.
    func augmentTextViewMenu(_ menu: NSMenu) {
        guard editable else {
            return
        }
        menu.addItem(.separator())
        menu.addItem(makeEditItem())
        menu.addItem(makeForkItem())
        menu.addItem(makeDeleteItem())
    }

    private func makeEditItem() -> NSMenuItem {
        let item = NSMenuItem(title: iTermLocalizedEdit(), action: #selector(editMenuItemClicked(_:)), keyEquivalent: "")
        item.target = self
        return item
    }

    private func makeForkItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "MessageCell.Fork", defaultValue: "Fork", comment: "Menu item to fork the conversation at this message"), action: #selector(forkMenuItemClicked(_:)), keyEquivalent: "")
        item.target = self
        return item
    }

    private func makeDeleteItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "General.Delete", defaultValue: "Delete", comment: "Label for a Delete control"), action: #selector(deleteMenuItemClicked(_:)), keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func copyMenuItemClicked(_ sender: Any) {
        it_fatalError("Subclass must implement this")
    }
    @objc func forkMenuItemClicked(_ sender: Any) {
        if let id = messageUniqueID {
            forkButtonClicked?(id)
        }
    }
    @objc func editMenuItemClicked(_ sender: Any) {
        if let id = messageUniqueID {
            editButtonClicked?(id)
        }
    }
    @objc func deleteMenuItemClicked(_ sender: Any) {
        if let id = messageUniqueID {
            deleteButtonClicked?(id)
        }
    }

    func configure(with rendition: MessageRendition,
                   tableViewWidth: CGFloat) {
        configure(with: rendition,
                  maxBubbleWidth: self.maxBubbleWidth(tableViewWidth: tableViewWidth))
    }

    func configure(with rendition: MessageRendition, maxBubbleWidth: CGFloat) {
        it_fatalError()
    }
}
