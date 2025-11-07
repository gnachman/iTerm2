import Cocoa

@objc
class MessageCellView: NSView {
    var textSelectable = true
    var customConstraints = [NSLayoutConstraint]()
    var rightClickMonitor: Any?
    var editable: Bool = false
    // store the messageUniqueID so that the edit button can pass it along.
    var messageUniqueID: UUID?
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 8
    // Callback for the edit button.
    var editButtonClicked: ((UUID) -> Void)?
    var forkButtonClicked: ((UUID) -> Void)?
    var maxWidthConstraint: NSLayoutConstraint?

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


    func add(constraint: NSLayoutConstraint) {
        customConstraints.append(constraint)
        constraint.isActive = true
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

    func maxBubbleWidth(tableViewWidth: CGFloat) -> CGFloat {
        return max(16, tableViewWidth * 0.7)
    }

    override var menu: NSMenu? {
        get {
            DLog("menu \(self)")
            guard editable else {
                DLog("Not editable so ignore right click")
                return nil
            }
            let menu = NSMenu(title: "Context Menu")
            let editItem = NSMenuItem(title: "Edit", action: #selector(editMenuItemClicked(_:)), keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)

            let copyItem = NSMenuItem(title: "Copy", action: #selector(copyMenuItemClicked(_:)), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)

            let forkItem = NSMenuItem(title: "Fork", action: #selector(forkMenuItemClicked(_:)), keyEquivalent: "")
            forkItem.target = self
            menu.addItem(forkItem)

            return menu
        }
        set {
            DLog("Unexpected call to set menu")
        }
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

    func configure(with rendition: MessageRendition,
                   tableViewWidth: CGFloat) {
        configure(with: rendition,
                  maxBubbleWidth: self.maxBubbleWidth(tableViewWidth: tableViewWidth))
    }

    func configure(with rendition: MessageRendition, maxBubbleWidth: CGFloat) {
        it_fatalError()
    }
}

