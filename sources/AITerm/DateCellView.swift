//
//  DateCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

class DateTextField: NSTextField {}

@objc
class DateCellView: NSView {
    private static let topInset: CGFloat = 8
    private static let bottomInset: CGFloat = 8
    private let bubbleView = BubbleView()
    private let textField = {
        let tf = DateTextField()
        tf.isEditable = false
        tf.isSelectable = false
        tf.drawsBackground = false
        tf.isBordered = false
        tf.translatesAutoresizingMaskIntoConstraints = false
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

        // Setup bubble
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubbleView)

        // Add the vertical stack inside the bubble
        bubbleView.addSubview(textField)
        updateBubbleColor()

        NSLayoutConstraint.activate([
            // textField inset within bubbleView
            bubbleView.leadingAnchor.constraint(equalTo: textField.leadingAnchor, constant: -8.0),
            bubbleView.trailingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8.0),
            bubbleView.topAnchor.constraint(equalTo: textField.topAnchor, constant: -Self.topInset),
            bubbleView.bottomAnchor.constraint(equalTo: textField.bottomAnchor, constant: Self.bottomInset),

            // bubbleView inset within cell and centered horizontally
            bubbleView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 0),
            bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset),
        ])
        bubbleView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        textField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
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
        textField.stringValue = humanReadableDate(from: components)
    }

    private func humanReadableDate(from components: DateComponents) -> String {
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
