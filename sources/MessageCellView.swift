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
    var maxWidthConstraint: NSLayoutConstraint?

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // Add a local monitor for right mouse down events.
            rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self = self else {
                    return event
                }
                let pointInSelf = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(pointInSelf) {
                    self.handleRightClick(event)
                    return nil
                }
                return event
            }
        } else if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
    }

    @objc private func handleRightClick(_ event: NSEvent) {
        guard editable else { return }
        let menu = NSMenu(title: "Context Menu")
        let editItem = NSMenuItem(title: "Edit", action: #selector(editMenuItemClicked(_:)), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyMenuItemClicked(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func copyMenuItemClicked(_ sender: Any) {
        it_fatalError("Subclass must implement this")
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

