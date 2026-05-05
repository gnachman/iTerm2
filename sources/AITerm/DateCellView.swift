//
//  DateCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

class DateTextField: NSTextField {}

@objc
class DateCellView: NSView {
    private static let cellTopInset: CGFloat = 8
    private static let cellBottomInset: CGFloat = 8
    private static let bubbleHorizontalPadding: CGFloat = 8
    private static let bubbleVerticalPadding: CGFloat = 8

    private let bubbleView = BubbleView()
    private let textField: DateTextField = {
        let tf = DateTextField()
        tf.isEditable = false
        tf.isSelectable = false
        tf.drawsBackground = false
        tf.isBordered = false
        return tf
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = false  // Allow subviews to be drawn outside the cell’s bounds.

        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
        addSubview(bubbleView)

        bubbleView.addSubview(textField)
        updateBubbleColor()
    }

    override func layout() {
        super.layout()
        textField.sizeToFit()
        let textSize = textField.frame.size
        let bubbleWidth = textSize.width + Self.bubbleHorizontalPadding * 2
        let bubbleHeight = textSize.height + Self.bubbleVerticalPadding * 2
        let bubbleX = floor((bounds.width - bubbleWidth) / 2)
        let bubbleY = Self.cellBottomInset
        bubbleView.frame = NSRect(x: bubbleX,
                                  y: bubbleY,
                                  width: bubbleWidth,
                                  height: bubbleHeight)
        textField.frame = NSRect(x: Self.bubbleHorizontalPadding,
                                 y: Self.bubbleVerticalPadding,
                                 width: textSize.width,
                                 height: textSize.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBubbleColor()
    }

    private func updateBubbleColor() {
        let (lightColor, darkColor) = (NSColor(fromHexString: "#e0e0e0")!,
                                       NSColor(fromHexString: "#505050")!)
        bubbleView.layer?.backgroundColor = (effectiveAppearance.it_isDark ? darkColor : lightColor).cgColor
    }

    func set(dateComponents components: DateComponents) {
        textField.stringValue = Self.humanReadableDate(from: components)
        needsLayout = true
    }

    static func cellHeight(for components: DateComponents) -> CGFloat {
        // Layout is dominated by a single line of system-font text. Match
        // the field's font metrics so static height equals the laid-out
        // height to within a pixel.
        let probe = DateTextField()
        probe.stringValue = humanReadableDate(from: components)
        probe.sizeToFit()
        return cellTopInset + bubbleVerticalPadding * 2 + probe.frame.height + cellBottomInset
    }

    private static func humanReadableDate(from components: DateComponents) -> String {
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            return "Invalid date"
        }

        let now = Date()
        let today = calendar.startOfDay(for: now)
        let dateStart = calendar.startOfDay(for: date)

        let formatter = DateFormatter()
        formatter.locale = Locale.current

        let daysDifference = calendar.dateComponents([.day], from: dateStart, to: today).day ?? 0

        if daysDifference == 0 {
            return "Today"
        } else if daysDifference == 1 {
            return "Yesterday"
        } else if daysDifference > 1 && daysDifference < 7 {
            formatter.dateFormat = "EEEE" // Full weekday name
        } else if daysDifference >= 7 && calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "MMM d" // "Mon DD"
        } else {
            formatter.dateFormat = "MMM d, yyyy" // "Mon DD, YYYY"
        }

        return formatter.string(from: date)
    }
}
