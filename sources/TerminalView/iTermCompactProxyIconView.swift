@objc(iTermCompactProxyIconView)
class iTermCompactProxyIconView: NSView, NSDraggingSource {
    private let imageView: NSImageView
    private var isMouseDown = false
    private var mouseDownPoint = NSPoint.zero

    @objc var url: URL? {
        didSet {
            if let url {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = bounds.size
                imageView.image = icon
                isHidden = false
            } else {
                imageView.image = nil
                isHidden = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        imageView = NSImageView(frame: NSRect(origin: .zero, size: frameRect.size))
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        super.init(frame: frameRect)
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        imageView.alphaValue = 0.5
    }

    override func mouseUp(with event: NSEvent) {
        isMouseDown = false
        imageView.alphaValue = 1.0
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMouseDown, let url else { return }

        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        guard distance >= 3 else { return }

        isMouseDown = false
        imageView.alphaValue = 1.0

        let pbItem = NSPasteboardItem()
        pbItem.setString(url.absoluteString, forType: .fileURL)

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = bounds.size
        dragItem.setDraggingFrame(bounds, contents: icon)

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .link, .generic]
    }

    // MARK: - Context Menu

    override func rightMouseDown(with event: NSEvent) {
        guard var url else { return }

        let menu = NSMenu()
        while !url.path.isEmpty {
            let path = url.path
            let item = NSMenuItem(title: (path as NSString).lastPathComponent,
                                  action: #selector(proxyIconMenuItemSelected(_:)),
                                  keyEquivalent: "")
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            item.representedObject = url
            item.target = self
            menu.addItem(item)

            let parent = (path as NSString).deletingLastPathComponent
            if parent == path {
                break
            }
            url = URL(fileURLWithPath: parent)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func proxyIconMenuItemSelected(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }
}
