//
//  iTermTabSwitcher.swift
//  iTerm2SharedARC
//
//  A ⌘-Tab-style overlay listing a window's tabs in most-recently-used order. It is purely
//  presentational: PTYTabView owns the selection and tells this object what to show.
//

import AppKit

private enum Metrics {
    static let panelWidth: CGFloat = 700
    static let rowHeight: CGFloat = 57
    static let maxVisibleRows = 8
    static let panelInset: CGFloat = 4
    static let panelCornerRadius: CGFloat = 8
    static let rowCornerRadius: CGFloat = 6
    static let textLeading: CGFloat = 20
    static let trailing: CGFloat = 16
    static let subtitleWidth: CGFloat = 220
    static let columnSpacing: CGFloat = 16
    // Quickly tapping and releasing the modifier switches tabs without flashing the overlay.
    static let showDelay: TimeInterval = 0.12
}

// Colors of Tab Finder’s tabs panel.
private extension NSColor {
    static func tabSwitcherDynamic(light: NSColor, dark: NSColor) -> NSColor {
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        }
    }

    static let tabSwitcherText = tabSwitcherDynamic(light: NSColor.black.withAlphaComponent(0.65),
                                                    dark: NSColor.white.withAlphaComponent(0.65))
    static let tabSwitcherSelectedText = tabSwitcherDynamic(light: .black, dark: .white)
    static let tabSwitcherSelectedBackground = tabSwitcherDynamic(light: NSColor.white.withAlphaComponent(0.5),
                                                                  dark: NSColor.white.withAlphaComponent(0.15))
}

private final class iTermTabSwitcherRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    var onHover: (() -> Void)?
    var onClick: (() -> Void)?

    var isSelected = false {
        didSet {
            if isSelected != oldValue {
                updateColors()
                needsDisplay = true
            }
        }
    }

    init(title: String, subtitle: String, frame: NSRect) {
        super.init(frame: frame)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 18)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.lineBreakMode = .byTruncatingHead
        subtitleLabel.usesSingleLineMode = true
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.alignment = .right
        addSubview(subtitleLabel)

        updateColors()
        layoutContents()

        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        return true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContents()
    }

    // The panel never becomes key, so the first click must not be swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func viewDidChangeEffectiveAppearance() {
        updateColors()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else {
            return
        }
        NSColor.tabSwitcherSelectedBackground.setFill()
        NSBezierPath(roundedRect: bounds,
                     xRadius: Metrics.rowCornerRadius,
                     yRadius: Metrics.rowCornerRadius).fill()
    }

    private func updateColors() {
        let color: NSColor = isSelected ? .tabSwitcherSelectedText : .tabSwitcherText
        titleLabel.textColor = color
        subtitleLabel.textColor = color
    }

    private func layoutContents() {
        let height = bounds.height
        let width = bounds.width
        let subtitleX = width - Metrics.trailing - Metrics.subtitleWidth
        let subtitleHeight = subtitleLabel.intrinsicContentSize.height
        subtitleLabel.frame = NSRect(x: subtitleX,
                                     y: (height - subtitleHeight) / 2,
                                     width: Metrics.subtitleWidth,
                                     height: subtitleHeight)

        let titleHeight = titleLabel.intrinsicContentSize.height
        let titleWidth = max(0, subtitleX - Metrics.columnSpacing - Metrics.textLeading)
        titleLabel.frame = NSRect(x: Metrics.textLeading,
                                  y: (height - titleHeight) / 2,
                                  width: titleWidth,
                                  height: titleHeight)
    }
}

@objc(iTermTabSwitcher)
final class iTermTabSwitcher: NSObject {
    private var panel: NSPanel?
    private var rows = [iTermTabSwitcherRowView]()
    private var scrollView: NSScrollView?
    private var selectedIndex = 0
    private var pendingShow: DispatchWorkItem?

    // Called with the row index when the pointer moves over a row.
    @objc var hoverHandler: ((Int) -> Void)?
    // Called with the row index when a row is clicked.
    @objc var clickHandler: ((Int) -> Void)?

    // Lays out the overlay for `tabViewItems` (in the order they should be listed) and shows it
    // shortly afterwards, centered over `window`.
    @objc(beginWithTabViewItems:selectedIndex:overWindow:)
    func begin(tabViewItems: [NSTabViewItem], selectedIndex: Int, over window: NSWindow?) {
        end()
        guard !tabViewItems.isEmpty else {
            return
        }
        let panel = makePanel(tabViewItems: tabViewItems)
        self.panel = panel
        select(index: selectedIndex)

        let workItem = DispatchWorkItem { [weak self, weak window] in
            self?.show(over: window)
        }
        pendingShow = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.showDelay, execute: workItem)
    }

    @objc(selectIndex:)
    func select(index: Int) {
        guard rows.indices.contains(index) else {
            return
        }
        selectedIndex = index
        for (i, row) in rows.enumerated() {
            row.isSelected = (i == index)
        }
        scrollView?.contentView.scrollToVisible(rows[index].frame)
    }

    @objc func end() {
        pendingShow?.cancel()
        pendingShow = nil
        panel?.orderOut(nil)
        panel = nil
        scrollView = nil
        rows = []
    }

    // MARK: - Private

    private func show(over window: NSWindow?) {
        pendingShow = nil
        guard let panel else {
            return
        }
        let anchorFrame = window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: anchorFrame.midX - panel.frame.width / 2,
                                     y: anchorFrame.midY - panel.frame.height / 2))
        panel.orderFrontRegardless()
    }

    private func makePanel(tabViewItems: [NSTabViewItem]) -> NSPanel {
        let visibleRows = min(tabViewItems.count, Metrics.maxVisibleRows)
        let listHeight = CGFloat(visibleRows) * Metrics.rowHeight
        let size = NSSize(width: Metrics.panelWidth,
                          height: listHeight + 2 * Metrics.panelInset)

        // Not key and not main, so the terminal window keeps receiving flagsChanged: events,
        // which is how PTYTabView learns that the modifier was released. PTYTabView also
        // handles the arrow and escape keys for the same reason.
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel],
                            backing: .buffered,
                            defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.cornerRadius = Metrics.panelCornerRadius
        root.layer?.masksToBounds = true
        panel.contentView = root

        let background = NSVisualEffectView(frame: root.bounds)
        background.autoresizingMask = [.width, .height]
        background.material = .sidebar
        background.blendingMode = .behindWindow
        background.state = .active
        // Also round the blur itself, in case the layer clip above doesn't cover it.
        background.maskImage = Self.roundedMask(radius: Metrics.panelCornerRadius)
        root.addSubview(background)

        let documentWidth = Metrics.panelWidth - 2 * Metrics.panelInset
        let documentView = FlippedDocumentView(frame: NSRect(x: 0,
                                                             y: 0,
                                                             width: documentWidth,
                                                             height: CGFloat(tabViewItems.count) * Metrics.rowHeight))
        rows = tabViewItems.enumerated().map { i, item in
            let row = iTermTabSwitcherRowView(title: Self.title(for: item),
                                              subtitle: Self.subtitle(for: item),
                                              frame: NSRect(x: 0,
                                                            y: CGFloat(i) * Metrics.rowHeight,
                                                            width: documentWidth,
                                                            height: Metrics.rowHeight))
            row.onHover = { [weak self] in
                self?.hoverHandler?(i)
            }
            row.onClick = { [weak self] in
                self?.clickHandler?(i)
            }
            documentView.addSubview(row)
            return row
        }

        let scrollView = NSScrollView(frame: NSRect(x: Metrics.panelInset,
                                                    y: Metrics.panelInset,
                                                    width: documentWidth,
                                                    height: listHeight))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = documentView
        background.addSubview(scrollView)
        self.scrollView = scrollView
        return panel
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let length = radius * 2 + 1
        let image = NSImage(size: NSSize(width: length, height: length), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // The first line of a string. A tab’s label is “title\nsubtitle”, and a line break in a text
    // field makes it two lines tall, which pushes its text off-center.
    private static func singleLine(_ string: String) -> String {
        let firstLine = string.components(separatedBy: .newlines).first ?? ""
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func title(for item: NSTabViewItem) -> String {
        let label = singleLine(item.label.removingHTMLFromTabTitleIfNeeded())
        if !label.isEmpty {
            return label
        }
        return singleLine((item.identifier as? PTYTab)?.activeSession?.name ?? "")
    }

    private static func subtitle(for item: NSTabViewItem) -> String {
        guard let directory = (item.identifier as? PTYTab)?.activeSession?.currentLocalWorkingDirectory else {
            return ""
        }
        return singleLine((directory as NSString).abbreviatingWithTildeInPath)
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool {
        return true
    }
}
