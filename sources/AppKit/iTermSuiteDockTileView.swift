import Cocoa

// When the app is launched with a -suite argument (used to run a second,
// isolated instance without clobbering the main install's preferences or
// sockets), overlay the suite name onto the dock icon so it's obvious at a
// glance which instance a dock icon belongs to. The name is drawn in the
// lower third of the icon in a distinctive green.
@objc(iTermSuiteDockTileView)
class iTermSuiteDockTileView: NSView {
    private let suiteName: String
    private static let textColor = NSColor(srgbRed: 0.126, green: 0.810, blue: 0.174, alpha: 1.0)

    // Installs a suite-name overlay on the app's dock tile if the app was
    // launched with -suite. A no-op otherwise. Safe to call once at launch.
    @objc(configureDockTileIfNeeded)
    static func configureDockTileIfNeeded() {
        guard iTermAdvancedSettingsModel.showSuiteNameInDockIcon() else {
            return
        }
        guard let suiteName = iTermUserDefaults.customSuiteName(), !suiteName.isEmpty else {
            return
        }
        let tile = NSApp.dockTile
        let view = iTermSuiteDockTileView(suiteName: suiteName)
        view.frame = NSRect(origin: .zero, size: tile.size)
        view.autoresizingMask = [.width, .height]
        tile.contentView = view
        tile.display()
    }

    private init(suiteName: String) {
        self.suiteName = suiteName
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // The base is the real app icon; the dock replaces its default drawing
        // with this content view, so we have to render the icon ourselves.
        NSApp.applicationIconImage?.draw(in: bounds)
        drawSuiteName()
    }

    private func drawSuiteName() {
        let band = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height / 3.0)
        let horizontalPadding = bounds.width * 0.08
        let availableWidth = max(1, band.width - horizontalPadding * 2)

        // A dark shadow keeps the text legible over any icon.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = bounds.height * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -bounds.height * 0.01)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        // Shrink the font until the name fits within the band's width.
        var attributes: [NSAttributedString.Key: Any] = [:]
        var textSize = NSSize.zero
        var fontSize = band.height * 0.9
        while fontSize > 4 {
            attributes = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: Self.textColor,
                .shadow: shadow,
                .paragraphStyle: paragraph
            ]
            textSize = (suiteName as NSString).size(withAttributes: attributes)
            if textSize.width <= availableWidth && textSize.height <= band.height {
                break
            }
            fontSize -= 1
        }

        let textRect = NSRect(x: band.minX + horizontalPadding,
                              y: band.midY - textSize.height / 2.0,
                              width: band.width - horizontalPadding * 2,
                              height: textSize.height)
        (suiteName as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
