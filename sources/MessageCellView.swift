//
//  MessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/13/25.
//

@objc
class MessageCellView: NSView {
    private let bubbleView = NSView()
    private let textLabel = AutoSizingTextView()
    private var backgroundColorPair: (NSColor, NSColor)?

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Bubble View Setup
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
        addSubview(bubbleView)

        // Text Label Setup
        textLabel.isEditable = false
        textLabel.isSelectable = true
        textLabel.drawsBackground = false
        textLabel.isVerticallyResizable = false
        textLabel.isHorizontallyResizable = false
        textLabel.textContainer?.lineFragmentPadding = 0
        textLabel.textContainerInset = .zero
        textLabel.textContainer?.widthTracksTextView = true
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bubbleView.addSubview(textLabel)
    }

    private func updateBackgroundColor() {
        guard let backgroundColorPair else {
            return
        }
        bubbleView.layer?.backgroundColor = (effectiveAppearance.it_isDark ? backgroundColorPair.1 : backgroundColorPair.0).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        updateBackgroundColor()
    }

    private static let topInset = 4.0
    private static let bottomInset = 4.0

    func configure(with message: Message, tableViewWidth: CGFloat) {
        textLabel.linkTextAttributes = [
            .foregroundColor: message.linkColor,
            .underlineColor: message.linkColor ]
        textLabel.textStorage?.setAttributedString(message.attributedStringValue)

        // Configure Bubble
        backgroundColorPair = message.participant == .user ?
            (NSColor.init(fromHexString: "p3#448bf7")!, NSColor.init(fromHexString: "p3#4a93f5")!)  :
            (NSColor.init(fromHexString: "p3#e9e9eb")!, NSColor.init(fromHexString: "p3#3b3b3d")!)
        updateBackgroundColor()

        // Layout Constraints
        let maxBubbleWidth = tableViewWidth * 0.7
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        NSLayoutConstraint.deactivate(constraints)

        let topInset = Self.topInset
        let bottomInset = Self.bottomInset

        if message.participant == .user {
            NSLayoutConstraint.activate([
                bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
                bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset),
                bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth),

                textLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
                textLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
                textLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: topInset),
                textLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -bottomInset)
            ])
        } else {
            NSLayoutConstraint.activate([
                bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
                bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset),
                bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth),

                textLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
                textLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
                textLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: topInset),
                textLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -bottomInset)
            ])
        }
        textLabel.textContainer?.widthTracksTextView = false
        textLabel.textContainer?.size = NSSize(width: maxBubbleWidth - 16,
                                               height: .greatestFiniteMagnitude)
    }

    static func height(for message: Message, tableViewWidth: CGFloat) -> CGFloat {
        let hpadding = 16.0
        let vpadding = (topInset + bottomInset) * 2
        let maxBubbleWidth = tableViewWidth * 0.7 - hpadding

        let attributedStringValue = message.attributedStringValue
        return measuredTextHeight(for: attributedStringValue,
                                  maxWidth: maxBubbleWidth,
                                  vpadding: vpadding)
    }

    private static func measuredTextHeight(for attributedString: NSAttributedString,
                                           maxWidth: CGFloat,
                                           vpadding: CGFloat) -> CGFloat {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))

        textContainer.lineFragmentPadding = 0  // Ensure consistent width measurement
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        layoutManager.ensureLayout(for: textContainer)

        let rect = layoutManager.usedRect(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                  in: textContainer)
        let size = NSSize(width: ceil(rect.maxX), height: ceil(bounding.maxY))

        DLog("Measured height for \(attributedString.string) is \(size.height) with \(vpadding) vertical padding")
        return size.height + vpadding
    }
}
