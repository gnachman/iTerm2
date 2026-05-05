import AppKit

// Two lines of text with an icon before the first.
@objc(iTermTwoTextFieldCell)
class TwoTextFieldCell: iTermTableCellView {
    @objc let topTextField: NSTextField
    @objc let bottomTextField: NSTextField
    @objc var iconImageView: NSImageView? = nil

    private static let iconSize: CGFloat = 10
    private static let iconTopInset: CGFloat = 2.5
    private static let iconTextSpacing: CGFloat = 2

    @objc(initWithIdentifier:font:)
    init(identifier: String, font: NSFont) {
        topTextField = Self.makeTextField(identifier: identifier, font: font)
        bottomTextField = Self.makeTextField(identifier: identifier, font: font)

        super.init(frame: .zero)
        addSubview(topTextField)
        addSubview(bottomTextField)
    }

    @objc(initWithIdentifier:font:icon:color:)
    convenience init(identifier: String, font: NSFont, icon: NSImage?, iconColor: NSColor?) {
        self.init(identifier: identifier, font: font)
        if let icon = icon {
            let imageView = NSImageView()
            icon.isTemplate = true
            imageView.contentTintColor = iconColor
            imageView.image = icon
            iconImageView = imageView
            addSubview(imageView)
            needsLayout = true
        }
    }

    required init(coder: NSCoder) {
        it_fatalError("Not implemented")
    }

    private static func makeTextField(identifier: String, font: NSFont) -> NSTextField {
        let tf = NSTextField.it_textFieldForTableView(withIdentifier: identifier)
        tf.font = font
        tf.lineBreakMode = .byTruncatingTail
        tf.usesSingleLineMode = false
        tf.maximumNumberOfLines = 1
        tf.cell?.truncatesLastVisibleLine = true
        return tf
    }

    override func layout() {
        super.layout()

        let bounds = self.bounds
        let topHeight = ceil(topTextField.intrinsicContentSize.height)
        let bottomHeight = ceil(bottomTextField.intrinsicContentSize.height)

        if let iconImageView = iconImageView {
            iconImageView.frame = NSRect(
                x: 0,
                y: bounds.maxY - Self.iconTopInset - Self.iconSize,
                width: Self.iconSize,
                height: Self.iconSize)

            let textX = Self.iconSize + Self.iconTextSpacing
            let textWidth = max(0, bounds.width - textX)
            let topY = bounds.maxY - Self.iconTopInset - topHeight
            topTextField.frame = NSRect(x: textX,
                                        y: topY,
                                        width: textWidth,
                                        height: topHeight)
            bottomTextField.frame = NSRect(x: textX,
                                           y: topY - bottomHeight,
                                           width: textWidth,
                                           height: bottomHeight)
        } else {
            let textBlockHeight = topHeight + bottomHeight
            let topY = bounds.midY + textBlockHeight / 2 - topHeight
            topTextField.frame = NSRect(x: 0,
                                        y: topY,
                                        width: bounds.width,
                                        height: topHeight)
            bottomTextField.frame = NSRect(x: 0,
                                           y: topY - bottomHeight,
                                           width: bounds.width,
                                           height: bottomHeight)
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateForegroundColor(textField: topTextField)
            updateForegroundColor(textField: bottomTextField)
        }
    }
}
