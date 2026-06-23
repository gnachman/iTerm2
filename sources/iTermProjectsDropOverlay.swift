// iTermProjectsDropOverlay.swift
// iTerm2
//
// A translucent drop-zone overlay shown over a Window Projects pane *during a drag*.
// The overlay is installed on the destination pane when a drag of a matching payload
// begins (see iTermProjectsSplitViewController.dragDidBegin) and removed when the drag
// ends. It divides the pane into one or two labeled zones (e.g. Archive / Detach, or a
// single Restore); the zone under the cursor highlights, and dropping on it invokes the
// delegate with the chosen zone.
//
// Driving the zones off the live NSDraggingInfo (rather than click/mouse tracking) keeps
// this much simpler than SplitSelectionView, which solves a similar visual problem for
// session splitting.

import AppKit

/// One labeled drop zone. Zones stack top→bottom in declaration order, each taking
/// `fraction` of the overlay's height (fractions should sum to 1).
struct iTermProjectsDropZone {
    let id: String                 // action identifier, e.g. "archive", "detach", "restore"
    let title: String
    let symbol: String             // SF Symbol name
    let fraction: CGFloat          // share of the overlay height
    let operation: NSDragOperation
}

protocol iTermProjectsDropOverlayDelegate: AnyObject {
    /// Execute the drop for `zone`. Return true if the drop was accepted.
    func dropOverlay(_ overlay: iTermProjectsDropOverlay,
                     didDropZone zone: iTermProjectsDropZone,
                     info: NSDraggingInfo) -> Bool
}

final class iTermProjectsDropOverlay: NSView {
    weak var delegate: iTermProjectsDropOverlayDelegate?

    private let zones: [iTermProjectsDropZone]
    private var hoveredZoneIndex = -1

    init(zones: [iTermProjectsDropZone],
         dragTypes: [NSPasteboard.PasteboardType]) {
        self.zones = zones
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        registerForDraggedTypes(dragTypes)
    }

    required init?(coder: NSCoder) { it_fatalError("not implemented") }

    // MARK: Geometry

    /// Rects for each zone, stacked top→bottom (zones[0] is at the top).
    private func zoneRects() -> [NSRect] {
        let h = bounds.height
        var rects: [NSRect] = []
        var y = bounds.maxY
        for z in zones {
            let zh = h * z.fraction
            y -= zh
            rects.append(NSRect(x: bounds.minX, y: y, width: bounds.width, height: zh))
        }
        return rects
    }

    private func zoneIndex(at point: NSPoint) -> Int {
        let rects = zoneRects()
        for (i, r) in rects.enumerated() where r.contains(point) { return i }
        // A single-zone overlay swallows the whole pane.
        return zones.count == 1 ? 0 : -1
    }

    private func location(_ sender: NSDraggingInfo) -> NSPoint {
        convert(sender.draggingLocation, from: nil)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.55).setFill()
        bounds.fill()

        let rects = zoneRects()
        for (i, zone) in zones.enumerated() {
            let hovered = (i == hoveredZoneIndex)
            let card = rects[i].insetBy(dx: 12, dy: 8)
            let path = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
            let fill = hovered ? NSColor.controlAccentColor : NSColor.white
            fill.withAlphaComponent(hovered ? 0.9 : 0.16).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(hovered ? 1.0 : 0.55).setStroke()
            path.lineWidth = hovered ? 3 : 1.5
            path.stroke()
            drawContents(of: zone, in: card, hovered: hovered)
        }
    }

    private func drawContents(of zone: iTermProjectsDropZone, in rect: NSRect, hovered: Bool) {
        let tint = NSColor.white
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 26, weight: hovered ? .bold : .regular)
        let image = NSImage(systemSymbolName: zone.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: hovered ? .semibold : .regular),
            .foregroundColor: tint,
        ]
        let titleSize = (zone.title as NSString).size(withAttributes: attrs)

        let imageHeight: CGFloat = image != nil ? 30 : 0
        let gap: CGFloat = image != nil ? 6 : 0
        let blockHeight = imageHeight + gap + titleSize.height
        var y = rect.midY + blockHeight / 2

        if let image = image {
            y -= imageHeight
            let imgRect = NSRect(x: rect.midX - 15, y: y, width: 30, height: imageHeight)
            // Composite the tint over the (template) symbol so it renders solid `tint`
            // on the dark overlay regardless of the symbol's own colors.
            let tinted = NSImage(size: imgRect.size, flipped: false) { drawRect in
                image.draw(in: drawRect)
                tint.set()
                drawRect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: imgRect)
            y -= gap
        }
        y -= titleSize.height
        (zone.title as NSString).draw(
            at: NSPoint(x: rect.midX - titleSize.width / 2, y: y),
            withAttributes: attrs)
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateHover(sender)
        return currentOperation(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateHover(sender)
        return currentOperation(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if hoveredZoneIndex != -1 {
            hoveredZoneIndex = -1
            needsDisplay = true
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let idx = zoneIndex(at: location(sender))
        guard idx >= 0, idx < zones.count else { return false }
        return delegate?.dropOverlay(self, didDropZone: zones[idx], info: sender) ?? false
    }

    private func updateHover(_ sender: NSDraggingInfo) {
        let idx = zoneIndex(at: location(sender))
        if idx != hoveredZoneIndex {
            hoveredZoneIndex = idx
            needsDisplay = true
        }
    }

    private func currentOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        let idx = zoneIndex(at: location(sender))
        return (idx >= 0 && idx < zones.count) ? zones[idx].operation : []
    }
}
