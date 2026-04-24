import AppKit

// Two lines of text with an icon before the first.
@objc(iTermTwoTextFieldCell)
class TwoTextFieldCell: iTermTableCellView {
    @objc let topTextField: NSTextField
    @objc let bottomTextField: NSTextField
    @objc var iconImageView: NSImageView? = nil

    @objc(initWithIdentifier:font:)
    init(identifier: String, font: NSFont) {
        topTextField = NSTextField.it_textFieldForTableView(withIdentifier: identifier)
        topTextField.font = font
        topTextField.lineBreakMode = .byTruncatingTail
        topTextField.usesSingleLineMode = false
        topTextField.maximumNumberOfLines = 1
        topTextField.cell?.truncatesLastVisibleLine = true

        bottomTextField = NSTextField.it_textFieldForTableView(withIdentifier: identifier)
        bottomTextField.font = font
        bottomTextField.lineBreakMode = .byTruncatingTail
        bottomTextField.usesSingleLineMode = false
        bottomTextField.maximumNumberOfLines = 1
        bottomTextField.cell?.truncatesLastVisibleLine = true

        super.init(frame: .zero)
        setupViews()
    }

    @objc(initWithIdentifier:font:icon:color:)
    convenience init(identifier: String, font: NSFont, icon: NSImage?, iconColor: NSColor?) {
        self.init(identifier: identifier, font: font)
        if let icon = icon {
            let imageView = NSImageView()
            icon.isTemplate = true
            imageView.contentTintColor = iconColor
            imageView.image = icon
            imageView.translatesAutoresizingMaskIntoConstraints = false
            self.iconImageView = imageView
            // Reconfigure layout to include the icon.
            setupViews()
        }
    }

    required init(coder: NSCoder) {
        it_fatalError("Not implemented")
    }

    private func setupViews() {
        // Remove previous subviews if reconfiguring.
        subviews.forEach { $0.removeFromSuperview() }

        let textStackView = NSStackView(views: [topTextField, bottomTextField])
        textStackView.orientation = .vertical
        textStackView.alignment = .leading
        textStackView.spacing = 0
        textStackView.translatesAutoresizingMaskIntoConstraints = false

        let containerView: NSView
        if let iconImageView = iconImageView {
            let horizontalStack = NSStackView(views: [iconImageView, textStackView])
            horizontalStack.orientation = .horizontal
            horizontalStack.alignment = .top
            horizontalStack.spacing = 2
            horizontalStack.translatesAutoresizingMaskIntoConstraints = false
            containerView = horizontalStack
            addSubview(containerView)

            NSLayoutConstraint.activate([
                iconImageView.heightAnchor.constraint(equalToConstant: 10.0),
                iconImageView.widthAnchor.constraint(equalToConstant: 10.0),
                iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 2.5)
            ])
        } else {
            containerView = textStackView
            addSubview(containerView)
        }


        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateForegroundColor(textField: topTextField)
            updateForegroundColor(textField: bottomTextField)
        }
    }
}
