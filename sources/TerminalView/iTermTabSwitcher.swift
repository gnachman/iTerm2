//
//  iTermTabSwitcher.swift
//  iTerm2SharedARC
//
//  A ⌘-Tab-style overlay listing a window's tabs in most-recently-used order, with a preview of
//  the highlighted tab beside it. It is purely presentational: PTYTabView owns the selection and
//  tells this object what to show. Enabled in Settings > Appearance > Tabs > Control-Tab Switcher.
//

import AppKit

private enum Metrics {
    static let preferredPanelWidth: CGFloat = 560
    static let rowHeight: CGFloat = 54
    static let maxVisibleRows = 8
    static let panelInset: CGFloat = 4
    static let panelCornerRadius: CGFloat = 8
    static let rowCornerRadius: CGFloat = 6
    static let leading: CGFloat = 12
    static let trailing: CGFloat = 12
    static let iconSize: CGFloat = 28
    static let iconSpacing: CGFloat = 10
    static let columnSpacing: CGFloat = 12
    static let lineSpacing: CGFloat = 2
    static let titleFontSize: CGFloat = 15
    static let secondaryFontSize: CGFloat = 12
    // The tab's new-output, bell, idle, or status indicator, and the tmux badge.
    static let badgeSize: CGFloat = 14
    static let badgeSpacing: CGFloat = 6
    // The tab color, drawn as a stripe along the row's leading edge.
    static let colorStripeX: CGFloat = 4
    static let colorStripeWidth: CGFloat = 4
    static let colorStripeVerticalInset: CGFloat = 9
    // How far a trackpad scroll moves before the highlight moves one row.
    static let scrollStep: CGFloat = 24
    // Keeps the panels off the edges of the screen.
    static let screenMargin: CGFloat = 20
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

// A snapshot of what the switcher shows for one tab, taken when the switcher opens.
@objc(iTermTabSwitcherItem)
final class iTermTabSwitcherItem: NSObject {
    let title: String
    let icon: NSImage?
    let statusText: String?
    let statusColor: NSColor?
    let detail: String?
    let directory: String?
    // The remote host the active session is on, or nil if it is this machine or unknown.
    let hostname: String?
    let tabColor: NSColor?
    // What the tab bar shows for new output, a bell, an idle tab, or a session status.
    let stateIcon: NSImage?
    let tmuxRole: TmuxRole
    // When the tab was last the selected tab, or nil if it is selected now or never was.
    let lastSeen: Date?
    // The tab the preview shows.
    weak var tab: PTYTab?

    enum TmuxRole {
        case none
        // The tab shows a tmux window.
        case client
        // A session in the tab is running tmux in control mode.
        case gateway
    }

    @objc(initWithTabViewItem:lastSeen:)
    init(tabViewItem: NSTabViewItem, lastSeen: Date?) {
        let tab = tabViewItem.identifier as? PTYTab
        let session = tab?.activeSession
        self.tab = tab

        let label = Self.singleLine(tabViewItem.label.removingHTMLFromTabTitleIfNeeded())
        title = label.isEmpty ? Self.singleLine(session?.name ?? "") : label
        icon = session?.tabGraphic

        if let status = tab?.aggregatedTabStatus, status.hasActiveStatus {
            statusText = SetTabStatusTrigger.localizedStatusForDisplay(status.statusText)
                .flatMap { Self.nonEmpty(Self.singleLine($0)) }
            if status.hasStatusTextColor {
                let c = status.statusTextColor
                statusColor = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
            } else {
                statusColor = nil
            }
            detail = status.detailText.flatMap { Self.nonEmpty(Self.singleLine($0)) }
        } else {
            statusText = nil
            statusColor = nil
            detail = nil
        }

        // The path variable is what shell integration or the last directory poll reported. Unlike
        // currentLocalWorkingDirectory it never blocks to ask the process.
        directory = (session?.genericScope.value(forVariableName: iTermVariableKeySessionPath) as? String)
            .flatMap { Self.nonEmpty(Self.singleLine(($0 as NSString).abbreviatingWithTildeInPath)) }
        if let host = session?.currentHost, !host.isLocalhost {
            hostname = host.hostname.flatMap { Self.nonEmpty(Self.singleLine($0)) }
        } else {
            hostname = nil
        }
        tabColor = session?.tabColor
        stateIcon = tab?.icon
        if tab?.sessions().contains(where: { $0.isTmuxGateway }) == true {
            tmuxRole = .gateway
        } else if tab?.isTmuxTab == true {
            tmuxRole = .client
        } else {
            tmuxRole = .none
        }
        self.lastSeen = lastSeen
        super.init()
    }

    // The first line of a string. A tab’s label is “title\nsubtitle”, and a line break in a text
    // field makes it two lines tall, which pushes its text off-center.
    private static func singleLine(_ string: String) -> String {
        let firstLine = string.components(separatedBy: .newlines).first ?? ""
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ string: String) -> String? {
        return string.isEmpty ? nil : string
    }

    func lastSeenDescription(now: Date) -> String? {
        guard let lastSeen else {
            return nil
        }
        let interval = max(0, now.timeIntervalSince(lastSeen))
        if interval < 60 {
            return String(localized: "TabSwitcher.LastSeenJustNow",
                          defaultValue: "Last seen just now",
                          comment: "Tab switcher: shown beside a tab that was selected less than a minute ago")
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        let duration = formatter.string(from: interval) ?? ""
        return String(localized: "TabSwitcher.LastSeenAgo",
                      defaultValue: "Last seen \(duration) ago",
                      comment: "Tab switcher: shown beside a tab to say how long ago it was last selected. The argument is a localized duration such as “2h 5m”.")
    }

    var tmuxBadge: NSImage? {
        switch tmuxRole {
        case .none:
            return nil
        case .client:
            return NSImage(systemSymbolName: SFSymbol.rectangleSplit2x2.rawValue,
                           accessibilityDescription: tmuxDescription)
        case .gateway:
            return NSImage(systemSymbolName: SFSymbol.rectangleConnectedToLineBelow.rawValue,
                           accessibilityDescription: tmuxDescription)
        }
    }

    var tmuxDescription: String? {
        switch tmuxRole {
        case .none:
            return nil
        case .client:
            return String(localized: "TabSwitcher.TmuxClient",
                          defaultValue: "tmux window",
                          comment: "Tab switcher: describes a tab that shows a tmux window, for the badge’s tooltip and VoiceOver")
        case .gateway:
            return String(localized: "TabSwitcher.TmuxGateway",
                          defaultValue: "tmux gateway",
                          comment: "Tab switcher: describes a tab whose session runs tmux in control mode, for the badge’s tooltip and VoiceOver")
        }
    }

    // Where the session is: the remote host and the directory, either, or nil.
    var location: String? {
        switch (hostname, directory) {
        case let (host?, dir?):
            // Localization unneeded: host:path notation, as in scp.
            return "\(host):\(dir)"
        case let (host?, nil):
            return host
        case let (nil, dir?):
            return dir
        case (nil, nil):
            return nil
        }
    }

    // Everything the row shows, for VoiceOver.
    func accessibilityDescription(now: Date) -> String {
        let parts = [title, statusText, detail, location, tmuxDescription, lastSeenDescription(now: now)]
        // Localization unneeded: a separator between self-contained values, read aloud.
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    // Status, detail, and location, in that order, for the row's second line.
    func secondaryLine(baseColor: NSColor, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func append(_ string: String, color: NSColor) {
            if result.length > 0 {
                // Localization unneeded: a separator between self-contained values.
                result.append(NSAttributedString(string: " · ",
                                                 attributes: [.font: font, .foregroundColor: baseColor]))
            }
            result.append(NSAttributedString(string: string,
                                             attributes: [.font: font, .foregroundColor: color]))
        }
        if let statusText {
            append(statusText, color: statusColor ?? baseColor)
        }
        if let detail {
            append(detail, color: baseColor)
        }
        if let location {
            append(location, color: baseColor)
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }
}

private final class iTermTabSwitcherRowView: NSView {
    private let item: iTermTabSwitcherItem
    private let showsIconColumn: Bool
    private let iconView = NSImageView()
    private let stateIconView = NSImageView()
    private let tmuxBadgeView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let lastSeenLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")

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

    init(item: iTermTabSwitcherItem, showsIconColumn: Bool, now: Date, frame: NSRect) {
        self.item = item
        self.showsIconColumn = showsIconColumn
        super.init(frame: frame)

        iconView.image = item.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isHidden = !showsIconColumn
        addSubview(iconView)

        stateIconView.image = item.stateIcon
        stateIconView.imageScaling = .scaleProportionallyUpOrDown
        stateIconView.isHidden = item.stateIcon == nil
        addSubview(stateIconView)

        tmuxBadgeView.image = item.tmuxBadge
        tmuxBadgeView.imageScaling = .scaleProportionallyUpOrDown
        tmuxBadgeView.isHidden = item.tmuxBadge == nil
        tmuxBadgeView.toolTip = item.tmuxDescription
        addSubview(tmuxBadgeView)

        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: Metrics.titleFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        lastSeenLabel.stringValue = item.lastSeenDescription(now: now) ?? ""
        lastSeenLabel.font = .systemFont(ofSize: Metrics.secondaryFontSize)
        lastSeenLabel.alignment = .right
        lastSeenLabel.usesSingleLineMode = true
        lastSeenLabel.maximumNumberOfLines = 1
        addSubview(lastSeenLabel)

        secondaryLabel.font = .systemFont(ofSize: Metrics.secondaryFontSize)
        secondaryLabel.lineBreakMode = .byTruncatingTail
        secondaryLabel.usesSingleLineMode = true
        secondaryLabel.maximumNumberOfLines = 1
        addSubview(secondaryLabel)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.accessibilityDescription(now: now))

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

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        updateColors()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            NSColor.tabSwitcherSelectedBackground.setFill()
            NSBezierPath(roundedRect: bounds,
                         xRadius: Metrics.rowCornerRadius,
                         yRadius: Metrics.rowCornerRadius).fill()
        }
        if let tabColor = item.tabColor {
            tabColor.setFill()
            let stripe = NSRect(x: Metrics.colorStripeX,
                                y: Metrics.colorStripeVerticalInset,
                                width: Metrics.colorStripeWidth,
                                height: max(0, bounds.height - 2 * Metrics.colorStripeVerticalInset))
            NSBezierPath(roundedRect: stripe,
                         xRadius: Metrics.colorStripeWidth / 2,
                         yRadius: Metrics.colorStripeWidth / 2).fill()
        }
    }

    private func updateColors() {
        let color: NSColor = isSelected ? .tabSwitcherSelectedText : .tabSwitcherText
        titleLabel.textColor = color
        lastSeenLabel.textColor = color
        tmuxBadgeView.contentTintColor = color
        secondaryLabel.attributedStringValue = item.secondaryLine(baseColor: color,
                                                                  font: .systemFont(ofSize: Metrics.secondaryFontSize))
    }

    private func layoutContents() {
        let height = bounds.height
        let width = bounds.width

        var textX = Metrics.leading
        if showsIconColumn {
            iconView.frame = NSRect(x: Metrics.leading,
                                    y: (height - Metrics.iconSize) / 2,
                                    width: Metrics.iconSize,
                                    height: Metrics.iconSize)
            textX += Metrics.iconSize + Metrics.iconSpacing
        }
        let textRight = width - Metrics.trailing

        let titleHeight = titleLabel.intrinsicContentSize.height
        let secondaryHeight = secondaryLabel.intrinsicContentSize.height
        let hasSecondary = secondaryLabel.attributedStringValue.length > 0
        let blockHeight = hasSecondary ? titleHeight + Metrics.lineSpacing + secondaryHeight : titleHeight
        let titleY = (height - blockHeight) / 2

        // Not intrinsicContentSize: for a label it leaves out the cell's padding, which truncates
        // the text.
        let lastSeenWidth = lastSeenLabel.stringValue.isEmpty ? 0 : ceil(lastSeenLabel.cell?.cellSize.width ?? 0)
        let lastSeenHeight = lastSeenLabel.intrinsicContentSize.height
        lastSeenLabel.frame = NSRect(x: textRight - lastSeenWidth,
                                     y: titleY + (titleHeight - lastSeenHeight) / 2,
                                     width: lastSeenWidth,
                                     height: lastSeenHeight)

        var titleRight = lastSeenWidth > 0 ? textRight - lastSeenWidth - Metrics.columnSpacing : textRight
        let badgeY = titleY + (titleHeight - Metrics.badgeSize) / 2
        if !tmuxBadgeView.isHidden {
            tmuxBadgeView.frame = NSRect(x: titleRight - Metrics.badgeSize,
                                         y: badgeY,
                                         width: Metrics.badgeSize,
                                         height: Metrics.badgeSize)
            titleRight -= Metrics.badgeSize + Metrics.badgeSpacing
        }
        var titleX = textX
        if !stateIconView.isHidden {
            stateIconView.frame = NSRect(x: textX,
                                         y: badgeY,
                                         width: Metrics.badgeSize,
                                         height: Metrics.badgeSize)
            titleX += Metrics.badgeSize + Metrics.badgeSpacing
        }
        titleLabel.frame = NSRect(x: titleX,
                                  y: titleY,
                                  width: max(0, titleRight - titleX),
                                  height: titleHeight)

        secondaryLabel.isHidden = !hasSecondary
        secondaryLabel.frame = NSRect(x: textX,
                                      y: titleY + titleHeight + Metrics.lineSpacing,
                                      width: max(0, textRight - textX),
                                      height: secondaryHeight)
    }
}

@objc(iTermTabSwitcher)
final class iTermTabSwitcher: NSObject {
    private var panel: NSPanel?
    private var items = [iTermTabSwitcherItem]()
    private var rows = [iTermTabSwitcherRowView]()
    private var scrollView: NSScrollView?
    private var selectedIndex = 0
    private var pendingShow: DispatchWorkItem?
    private weak var window: NSWindow?
    private let previewPanel = iTermSessionPreviewPanel()

    // The tab bar's frame in screen coordinates, which the switcher stays clear of when there is
    // room. Empty if there is nothing to avoid.
    @objc var avoidedScreenFrame = NSRect.zero

    // Called with the row index when the pointer moves over a row.
    @objc var hoverHandler: ((Int) -> Void)?
    // Called with the row index when a row is clicked.
    @objc var clickHandler: ((Int) -> Void)?
    // Called with YES to move the highlight down a row or NO to move it up, for the scroll wheel
    // or a trackpad.
    @objc var scrollHandler: ((Bool) -> Void)?

    // Called once the overlay is on screen. Until then a quick tap of Cycle Tabs shows nothing.
    @objc var didShowHandler: (() -> Void)?

    // Whether the overlay is on screen, which it is not during the short delay before it appears.
    @objc var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    // The tab VoiceOver was last told about, so it hears about each change once.
    private weak var lastAnnouncedTab: PTYTab?

    // Lays out the overlay for `items` (in the order they should be listed) and shows it
    // shortly afterwards, centered over `window`.
    @objc(beginWithItems:selectedIndex:overWindow:)
    func begin(items: [iTermTabSwitcherItem], selectedIndex: Int, over window: NSWindow?) {
        end()
        guard !items.isEmpty else {
            return
        }
        self.window = window
        panel = makePanel()
        install(items: items, selectedIndex: selectedIndex)

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingShow = nil
            self?.show()
        }
        pendingShow = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.showDelay, execute: workItem)
    }

    // Replaces the list while the switcher is open, such as when a tab is added or closed. The
    // panel stays where it is, and the preview is rendered again only if the highlighted tab
    // changed.
    @objc(updateWithItems:selectedIndex:)
    func update(items: [iTermTabSwitcherItem], selectedIndex: Int) {
        guard panel != nil, !items.isEmpty else {
            return
        }
        install(items: items, selectedIndex: selectedIndex)
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
        updatePreview()
        announceSelection()
    }

    // Only while the panel is up: a quick tap of Cycle Tabs switches without ever showing it, and
    // shouldn't make VoiceOver read a row nobody saw.
    private func announceSelection() {
        guard let panel, panel.isVisible, items.indices.contains(selectedIndex) else {
            return
        }
        let item = items[selectedIndex]
        if let tab = item.tab, tab === lastAnnouncedTab {
            return
        }
        lastAnnouncedTab = item.tab
        NSAccessibility.post(element: panel,
                             notification: .announcementRequested,
                             userInfo: [.announcement: item.accessibilityDescription(now: Date()),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    @objc func end() {
        pendingShow?.cancel()
        pendingShow = nil
        previewPanel.teardown()
        panel?.orderOut(nil)
        panel = nil
        scrollView = nil
        rows = []
        items = []
        lastAnnouncedTab = nil
    }

    // MARK: - Private

    // Fills the panel's list with rows for `items`, resizing the panel to fit them.
    private func install(items: [iTermTabSwitcherItem], selectedIndex: Int) {
        guard let panel, let scrollView else {
            return
        }
        self.items = items
        let documentWidth = panel.frame.width - 2 * Metrics.panelInset
        let listHeight = CGFloat(min(items.count, Metrics.maxVisibleRows)) * Metrics.rowHeight
        let panelHeight = listHeight + 2 * Metrics.panelInset
        if panel.frame.height != panelHeight {
            // Keep the top edge where it is so the list doesn't jump.
            var frame = panel.frame
            frame.origin.y = frame.maxY - panelHeight
            frame.size.height = panelHeight
            panel.setFrame(frame, display: panel.isVisible)
        }
        scrollView.frame = NSRect(x: Metrics.panelInset,
                                  y: Metrics.panelInset,
                                  width: documentWidth,
                                  height: listHeight)

        let documentView = iTermFlippedView(frame: NSRect(x: 0,
                                                          y: 0,
                                                          width: documentWidth,
                                                          height: CGFloat(items.count) * Metrics.rowHeight))
        // Line the titles up: either every row has an icon column or none does.
        let showsIconColumn = items.contains { $0.icon != nil }
        let now = Date()
        rows = items.enumerated().map { i, item in
            let row = iTermTabSwitcherRowView(item: item,
                                              showsIconColumn: showsIconColumn,
                                              now: now,
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
        scrollView.documentView = documentView
        select(index: min(max(0, selectedIndex), items.count - 1))
    }

    private var screen: NSScreen? {
        return window?.screen ?? NSScreen.main
    }

    // Whether the screen has room for the preview beside the list.
    private var showsPreview: Bool {
        guard let screen else {
            return false
        }
        let needed = Metrics.preferredPanelWidth + iTermSessionPreviewPanel.horizontalSpaceBesideParent
        return screen.visibleFrame.width - 2 * Metrics.screenMargin >= needed
    }

    private var panelWidth: CGFloat {
        guard let screen else {
            return Metrics.preferredPanelWidth
        }
        return min(Metrics.preferredPanelWidth, screen.visibleFrame.width - 2 * Metrics.screenMargin)
    }

    private func show() {
        guard let panel else {
            return
        }
        let visibleFrame = screen?.visibleFrame ?? .zero
        let anchorFrame = window?.frame ?? visibleFrame
        // The list and the preview are placed as a group with their tops aligned.
        let previewSpace = showsPreview ? iTermSessionPreviewPanel.horizontalSpaceBesideParent : 0
        let previewHeight = showsPreview ? iTermSessionPreviewPanel.height(forImageSize: expectedPreviewImageSize,
                                                                           screen: screen) : 0
        let groupSize = NSSize(width: panel.frame.width + previewSpace,
                               height: max(panel.frame.height, previewHeight))
        let groupOrigin = Self.groupOrigin(size: groupSize,
                                           anchor: anchorFrame,
                                           avoiding: avoidedScreenFrame,
                                           within: visibleFrame)
        // The panel's origin is its bottom left, and it hangs from the top of the group.
        panel.setFrameOrigin(NSPoint(x: groupOrigin.x,
                                     y: groupOrigin.y + groupSize.height - panel.frame.height))
        // Hotkey windows can float above .floating, and the switcher has to be above its window.
        let windowLevel = window?.level.rawValue ?? 0
        panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.floating.rawValue, windowLevel + 1))
        panel.orderFrontRegardless()
        updatePreview()
        announceSelection()
        didShowHandler?()
    }

    // The preview shows the whole tab, so its image has the shape of the tab's panes.
    private var expectedPreviewImageSize: NSSize {
        guard items.indices.contains(selectedIndex), let tab = items[selectedIndex].tab else {
            return .zero
        }
        return tab.rootView?.bounds.size ?? .zero
    }

    // Where to put a group of `size`: centered in the part of `anchor` not covered by `avoiding`,
    // kept on screen, and moved off `avoiding` if it still overlaps and there is room elsewhere
    // on screen.
    private static func groupOrigin(size: NSSize,
                                    anchor: NSRect,
                                    avoiding: NSRect,
                                    within visibleFrame: NSRect) -> NSPoint {
        let gap = Metrics.screenMargin
        func clamped(_ origin: NSPoint) -> NSPoint {
            guard !visibleFrame.isEmpty else {
                return origin
            }
            return NSPoint(x: min(max(origin.x, visibleFrame.minX + gap), visibleFrame.maxX - gap - size.width),
                           y: min(max(origin.y, visibleFrame.minY + gap), visibleFrame.maxY - gap - size.height))
        }
        func overlaps(_ origin: NSPoint) -> Bool {
            return !avoiding.isEmpty && NSRect(origin: origin, size: size).intersects(avoiding)
        }

        // The pieces of the anchor on each side of the avoided rect. The tab bar runs along one
        // edge of the window, so the biggest piece is the rest of the window.
        var region = anchor
        if !avoiding.isEmpty && anchor.intersects(avoiding) {
            let pieces = [
                NSRect(x: anchor.minX, y: anchor.minY, width: anchor.width, height: avoiding.minY - anchor.minY),
                NSRect(x: anchor.minX, y: avoiding.maxY, width: anchor.width, height: anchor.maxY - avoiding.maxY),
                NSRect(x: anchor.minX, y: anchor.minY, width: avoiding.minX - anchor.minX, height: anchor.height),
                NSRect(x: avoiding.maxX, y: anchor.minY, width: anchor.maxX - avoiding.maxX, height: anchor.height)
            ].filter { $0.width > 0 && $0.height > 0 }
            if let biggest = pieces.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                region = biggest
            }
        }
        let centered = clamped(NSPoint(x: region.midX - size.width / 2,
                                       y: region.midY - size.height / 2))
        guard overlaps(centered) else {
            return centered
        }
        // Too big for the rest of the window. Try putting it right next to the avoided rect,
        // which may extend past the window.
        let candidates = [
            NSPoint(x: centered.x, y: avoiding.minY - gap - size.height),
            NSPoint(x: centered.x, y: avoiding.maxY + gap),
            NSPoint(x: avoiding.maxX + gap, y: centered.y),
            NSPoint(x: avoiding.minX - gap - size.width, y: centered.y)
        ].map { clamped($0) }
        return candidates.first { !overlaps($0) } ?? centered
    }

    private func updatePreview() {
        guard let panel, panel.isVisible, showsPreview else {
            return
        }
        guard items.indices.contains(selectedIndex), let tab = items[selectedIndex].tab else {
            previewPanel.hide()
            return
        }
        let item = items[selectedIndex]
        previewPanel.show(for: tab,
                          title: item.title,
                          detail: item.location ?? "",
                          parentFrame: panel.frame,
                          parentWindow: panel)
    }

    // An empty panel with a list for install(items:selectedIndex:) to fill.
    private func makePanel() -> NSPanel {
        let size = NSSize(width: panelWidth, height: 2 * Metrics.panelInset)

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

        let scrollView = iTermTabSwitcherScrollView(frame: NSRect(x: Metrics.panelInset,
                                                                  y: Metrics.panelInset,
                                                                  width: size.width - 2 * Metrics.panelInset,
                                                                  height: 0))
        scrollView.onStep = { [weak self] forwards in
            self?.scrollHandler?(forwards)
        }
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
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
}

// Turns scrolling into moving the highlight one row at a time, instead of scrolling the list. The
// list follows the highlight on its own.
private final class iTermTabSwitcherScrollView: NSScrollView {
    // Called with true to move down a row and false to move up.
    var onStep: ((Bool) -> Void)?
    private var accumulated: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        // Momentum would keep moving the highlight after the fingers lift.
        guard event.momentumPhase.isEmpty else {
            return
        }
        if event.phase.contains(.began) {
            accumulated = 0
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else {
            return
        }
        // Negative means toward the end of the list, whichever way the user has scrolling set up.
        if !event.hasPreciseScrollingDeltas {
            onStep?(delta < 0)
            return
        }
        accumulated += delta
        while abs(accumulated) >= Metrics.scrollStep {
            let forwards = accumulated < 0
            accumulated += forwards ? Metrics.scrollStep : -Metrics.scrollStep
            onStep?(forwards)
        }
    }
}
