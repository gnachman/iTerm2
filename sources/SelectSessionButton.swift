@objc(iTermSelectSessionButton)
class SelectSessionButton: NSView {
    private let button = NSButton(title: "Select this Session", target: nil, action: nil)
    private let effectView = NSVisualEffectView()

    // New title label (using NSTextField configured for display only)
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Title")
        label.alignment = .center
        label.font = NSFont.boldSystemFont(ofSize: 14)
        return label
    }()

    @objc var onButtonClicked: (() -> Void)?

    // Configurable margins and gap between title and button
    @objc var horizontalMargin: CGFloat = 16.0 { didSet { needsLayout = true } }
    @objc var verticalMargin: CGFloat = 16.0 { didSet { needsLayout = true } }
    @objc var spacing: CGFloat = 16.0 { didSet { needsLayout = true } }  // Gap between title and button

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
        let width = max(titleSize.width, buttonSize.width) + 2 * horizontalMargin
        let height = verticalMargin + titleSize.height + spacing + buttonSize.height + verticalMargin

        self.frame.size = NSSize(width: width, height: height)
        needsLayout = true
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        onButtonClicked?()
    }
}
