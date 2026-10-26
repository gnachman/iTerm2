@objc(iTermSelectSessionButton)
class SelectSessionButton: NSView {
    private let button = NSButton(title: String(localized: "SelectSessionButton.SelectThisSession", defaultValue: "Select this Session", comment: "Button to select the current session"), target: nil, action: nil)
    // Optional second button, shown only when onRevealClicked is set, that
    // takes the user back to whatever asked them to pick a session.
    private let revealButton = NSButton(title: String(localized: "SelectSessionButton.RevealChat", defaultValue: "Reveal Chat", comment: "Button that shows the AI chat where the user is typing an @-mention of a session"), target: nil, action: nil)
    private let effectView = NSVisualEffectView()

    // New title label (using NSTextField configured for display only)
    private let titleLabel: NSTextField = {
        // Localization unneeded
        let label = NSTextField(labelWithString: "Title")
        label.alignment = .center
        label.font = NSFont.boldSystemFont(ofSize: 14)
        return label
    }()

    @objc var onButtonClicked: (() -> Void)?
    @objc var onRevealClicked: (() -> Void)? {
        didSet {
            revealButton.isHidden = (onRevealClicked == nil)
            needsLayout = true
        }
    }

    // Configurable margins and gap between title and button
    @objc var horizontalMargin: CGFloat = 16.0 { didSet { needsLayout = true } }
    @objc var verticalMargin: CGFloat = 16.0 { didSet { needsLayout = true } }
    @objc var spacing: CGFloat = 16.0 { didSet { needsLayout = true } }  // Gap between title and button
    @objc var buttonSpacing: CGFloat = 8.0 { didSet { needsLayout = true } }  // Gap between the two buttons

    // Expose a property to set the title text
    @objc var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue; needsLayout = true }
    }

    @objc
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        setupViews()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 10.0
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(white: 0.5, alpha: 1.0).cgColor
        layer?.masksToBounds = true

        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.material = .sheet
        addSubview(effectView)

        button.target = self
        button.action = #selector(buttonClicked(_:))
        addSubview(button)

        revealButton.target = self
        revealButton.action = #selector(revealClicked(_:))
        revealButton.isHidden = true
        addSubview(revealButton)

        addSubview(titleLabel)
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds

        titleLabel.sizeToFit()
        button.sizeToFit()

        let titleSize = titleLabel.frame.size
        let buttonSize = button.frame.size

        // Position the title label at the top with verticalMargin
        let titleX = (bounds.width - titleSize.width) / 2
        let titleY = bounds.height - verticalMargin - titleSize.height
        titleLabel.frame = NSRect(x: titleX, y: titleY, width: titleSize.width, height: titleSize.height)

        // Position the button directly below the title label with a gap of 'spacing'
        let buttonX = (bounds.width - buttonSize.width) / 2
        let buttonY = titleLabel.frame.minY - spacing - buttonSize.height
        button.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize.width, height: buttonSize.height)

        if !revealButton.isHidden {
            revealButton.sizeToFit()
            let revealSize = revealButton.frame.size
            revealButton.frame = NSRect(x: (bounds.width - revealSize.width) / 2,
                                        y: button.frame.minY - buttonSpacing - revealSize.height,
                                        width: revealSize.width,
                                        height: revealSize.height)
        }
    }

    @objc func sizeToFit() {
        // Update sizes for both the title and button.
        titleLabel.sizeToFit()
        button.sizeToFit()

        let titleSize = titleLabel.frame.size
        let buttonSize = button.frame.size

        // Compute the new size:
        // width = max(title, button) width + horizontal margins on both sides,
        // height = verticalMargin (top) + title height + spacing + button height + verticalMargin (bottom).
        var contentWidth = max(titleSize.width, buttonSize.width)
        var height = verticalMargin + titleSize.height + spacing + buttonSize.height + verticalMargin
        if !revealButton.isHidden {
            revealButton.sizeToFit()
            contentWidth = max(contentWidth, revealButton.frame.width)
            height += buttonSpacing + revealButton.frame.height
        }
        let width = contentWidth + 2 * horizontalMargin

        self.frame.size = NSSize(width: width, height: height)
        needsLayout = true
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        onButtonClicked?()
    }

    @objc private func revealClicked(_ sender: NSButton) {
        onRevealClicked?()
    }
}
