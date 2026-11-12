import AppKit

final class iTermSidebarCellView: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyDown
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .labelColor
        addSubview(icon)
        addSubview(label)
        imageView = icon
        textField = label
    }

    required init?(coder: NSCoder) { it_fatalError("init(coder:) has not been implemented") }

    func configure(name: String, path: String, image: NSImage?, folder: Bool) {
        if label.stringValue != name { label.stringValue = name }
        if icon.image !== image { icon.image = image }
        let tint: NSColor = folder ? .controlAccentColor : .secondaryLabelColor
        if icon.contentTintColor != tint { icon.contentTintColor = tint }
        if toolTip != path { toolTip = path }
    }

    override func layout() {
        super.layout()
        let iconFrame = NSRect(x: 2, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let labelFrame = NSRect(x: 24, y: (bounds.height - 17) / 2, width: max(0, bounds.width - 28), height: 17)
        if icon.frame != iconFrame { icon.frame = iconFrame }
        if label.frame != labelFrame { label.frame = labelFrame }
    }
}
