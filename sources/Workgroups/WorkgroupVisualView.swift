//
//  WorkgroupVisualView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import AppKit

protocol WorkgroupVisualViewDelegate: AnyObject {
    func visualView(_ view: WorkgroupVisualView,
                    didSelectSessionID sessionID: String)
    // Fires continuously during a divider drag so peer UI (the location
    // slider) can track the pointer without committing to the model.
    func visualView(_ view: WorkgroupVisualView,
                    didDragSplit sessionID: String,
                    location: Double)
    // Fires once on mouseUp — the point at which the change gets
    // committed to the model and an undo step registered.
    func visualView(_ view: WorkgroupVisualView,
                    didFinishDraggingSplit sessionID: String,
                    location: Double)
}

// Wireframe preview of a workgroup: shows a tab bar at the top (one tab
// per tab-kind direct child of the root, plus the root's own tab slot),
// and the active tab's content below — with a mode switcher above any
// container that has peer children, and recursive split-pane subdivision
// inside each container.
//
// Hit testing maps every clickable region back to a session ID so the
// host view controller can update its "selected session" when the user
// clicks a tab, a peer switch segment, or a pane.
final class WorkgroupVisualView: NSView {
    weak var delegate: WorkgroupVisualViewDelegate?

    private(set) var workgroup: iTermWorkgroup?
    private(set) var selectedSessionID: String?

    // Which tab is displayed in the content area. nil means "whatever is
    // current". Set lazily to the root's ID the first time we paint.
    private var activeTabSessionID: String?
    // Active peer per peer-group host. If a host has no entry, the host
    // itself is the active member.
    private var activePeerByHost: [String: String] = [:]

    private struct HitRegion {
        let rect: NSRect
        let sessionID: String
    }
    private var hitRegions: [HitRegion] = []

    // Draggable divider between a split and the rest of its parent's
    // area. Captured during drawing so mouseDown can pick it up.
    private struct DividerRegion {
        let rect: NSRect           // hit area (slightly inflated)
        let sessionID: String      // the split session being resized
        let parentRect: NSRect     // parent area the split is carved from
        let orientation: SplitSettings.Orientation
        let side: SplitSettings.Side
    }
    private var dividerRegions: [DividerRegion] = []

    // While the user drags a divider, render that split at this value
    // instead of its stored location — so the preview tracks the mouse
    // without committing to the model on every event. `moved` stays
    // false until mouseDragged fires at least once, so a bare click on
    // a divider (mouseDown + mouseUp with no drag) doesn't commit a
    // spurious location change.
    private var activeDrag: (region: DividerRegion,
                             pending: Double,
                             moved: Bool)?

    private let tabBarHeight: CGFloat = 22
    private let switcherHeight: CGFloat = 22
    private let paneInset: CGFloat = 2
    private let dividerHitSlop: CGFloat = 3
    private let cornerRadius: CGFloat = 4
    private let splitLocationMin = 0.2
    private let splitLocationMax = 0.8

    override var isFlipped: Bool { return false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { it_fatalError("not used") }

    func set(workgroup: iTermWorkgroup?, selectedSessionID: String?) {
        let newID = workgroup?.uniqueIdentifier
        let oldID = self.workgroup?.uniqueIdentifier
        self.workgroup = workgroup
        self.selectedSessionID = selectedSessionID
        if newID != oldID {
            activeTabSessionID = workgroup?.root?.uniqueIdentifier
            activePeerByHost.removeAll()
        }
        syncActiveStateToSelection()
        needsDisplay = true
    }

    // Make sure the active-tab and active-peer maps don't hide the
    // currently-selected session. If the user selects something inside a
    // non-active tab, flip to that tab; if the selection is a peer, make
    // it the active peer for its host.
    private func syncActiveStateToSelection() {
        guard let wg = workgroup,
              let sid = selectedSessionID,
              let selected = wg.session(withUniqueIdentifier: sid) else { return }
        if case .peer = selected.kind, let hostID = selected.parentID {
            activePeerByHost[hostID] = sid
        }
        // Walk up ancestors to find which tab the selection lives in.
        var cursor: iTermWorkgroupSessionConfig? = selected
        while let c = cursor {
            if case .tab = c.kind {
                activeTabSessionID = c.uniqueIdentifier
                return
            }
            if c.parentID == nil {
                activeTabSessionID = c.uniqueIdentifier
                return
            }
            cursor = c.parentID.flatMap { wg.session(withUniqueIdentifier: $0) }
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        hitRegions.removeAll()
        dividerRegions.removeAll()
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        guard let wg = workgroup, let root = wg.root else {
            drawEmptyLabel()
            return
        }

        // Tabs: root is always the first "tab"; tab-kind direct children
        // of root follow.
        let tabChildren = wg.sessions.filter { s -> Bool in
            guard s.parentID == root.uniqueIdentifier else { return false }
            if case .tab = s.kind { return true }
            return false
        }
        let tabs: [iTermWorkgroupSessionConfig] = [root] + tabChildren
        let activeTabID = activeTabSessionID ?? root.uniqueIdentifier

        // Only draw the tab bar when there are actually multiple tabs —
        // showing a single "Main" tab against an empty bar is just noise.
        let contentRect: NSRect
        if tabs.count > 1 {
            drawTabBar(tabs: tabs, activeID: activeTabID,
                       in: NSRect(x: 0, y: bounds.height - tabBarHeight,
                                  width: bounds.width, height: tabBarHeight))
            contentRect = NSRect(x: 0, y: 0,
                                 width: bounds.width,
                                 height: bounds.height - tabBarHeight)
        } else {
            contentRect = bounds
        }

        let tabSession = tabs.first { $0.uniqueIdentifier == activeTabID } ?? root
        drawContainer(tabSession, in: contentRect, wg: wg)
    }

    private func drawEmptyLabel() {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ]
        let text = "No workgroup" as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2,
                              y: bounds.midY - size.height / 2),
                  withAttributes: attrs)
    }

    private func drawTabBar(tabs: [iTermWorkgroupSessionConfig],
                            activeID: String, in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: rect.minX, y: rect.minY),
            to: NSPoint(x: rect.maxX, y: rect.minY))
        let count = max(1, tabs.count)
        let width = rect.width / CGFloat(count)
        for (idx, tab) in tabs.enumerated() {
            let tabRect = NSRect(x: rect.minX + CGFloat(idx) * width,
                                 y: rect.minY,
                                 width: width,
                                 height: rect.height)
            let isActive = tab.uniqueIdentifier == activeID
            let isSelected = tab.uniqueIdentifier == selectedSessionID
            drawSegment(in: tabRect.insetBy(dx: 2, dy: 2),
                        label: tabLabel(for: tab),
                        emphasis: isSelected ? .selected : (isActive ? .active : .normal))
            hitRegions.append(HitRegion(rect: tabRect, sessionID: tab.uniqueIdentifier))
        }
    }

    private func tabLabel(for s: iTermWorkgroupSessionConfig) -> String {
        if !s.displayName.isEmpty { return s.displayName }
        switch s.kind {
        case .root: return "Main"
        case .tab: return "Tab"
        default: return "?"
        }
    }

    // Container = any session rendered as a rectangle in the wireframe.
    //
    // Splits are carved from the CONTAINER's own area first — they live
    // alongside the peer group and must remain visible regardless of
    // which peer is currently active. Only the remaining (non-split)
    // "core" area is governed by the peer switcher, so swapping between
    // Main and its peer P doesn't make Main's splits disappear.
    private func drawContainer(_ container: iTermWorkgroupSessionConfig,
                               in rect: NSRect,
                               wg: iTermWorkgroup) {
        var remaining = rect

        // 1. Carve out this container's splits (always shown).
        let splits = wg.sessions.filter { c in
            guard c.parentID == container.uniqueIdentifier else { return false }
            if case .split = c.kind { return true }
            return false
        }
        for split in splits {
            guard case .split(let settings) = split.kind else { continue }
            let splitRect = carveSplitRect(split: split,
                                           from: &remaining,
                                           settings: settings)
            drawContainer(split, in: splitRect, wg: wg)
        }

        // 2. Handle the peer group (if any) in whatever remains.
        let peers = wg.sessions.filter { c in
            guard c.parentID == container.uniqueIdentifier else { return false }
            if case .peer = c.kind { return true }
            return false
        }
        guard !peers.isEmpty else {
            drawPane(container, in: remaining)
            return
        }
        let members = [container] + peers
        let activeID = activePeerByHost[container.uniqueIdentifier]
            ?? container.uniqueIdentifier
        let switcherRect = NSRect(x: remaining.minX,
                                  y: remaining.maxY - switcherHeight,
                                  width: remaining.width,
                                  height: switcherHeight)
        drawModeSwitcher(members: members, activeID: activeID,
                         in: switcherRect)
        remaining.size.height -= switcherHeight
        let activeMember = members.first { $0.uniqueIdentifier == activeID }
            ?? container
        if activeMember.uniqueIdentifier == container.uniqueIdentifier {
            drawPane(container, in: remaining)
        } else {
            // Active is a peer — recurse so it renders any splits it
            // might own (model allows this; UI currently blocks adding
            // but older data might already have it).
            drawContainer(activeMember, in: remaining, wg: wg)
        }
    }

    private func drawModeSwitcher(members: [iTermWorkgroupSessionConfig],
                                  activeID: String, in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        let count = max(1, members.count)
        let width = rect.width / CGFloat(count)
        for (idx, member) in members.enumerated() {
            let segRect = NSRect(x: rect.minX + CGFloat(idx) * width,
                                 y: rect.minY,
                                 width: width,
                                 height: rect.height)
            let isActive = member.uniqueIdentifier == activeID
            let isSelected = member.uniqueIdentifier == selectedSessionID
            drawSegment(in: segRect.insetBy(dx: 1, dy: 2),
                        label: peerLabel(for: member),
                        emphasis: isSelected ? .selected : (isActive ? .active : .normal))
            hitRegions.append(HitRegion(rect: segRect, sessionID: member.uniqueIdentifier))
        }
    }

    private func peerLabel(for s: iTermWorkgroupSessionConfig) -> String {
        if !s.displayName.isEmpty { return s.displayName }
        switch s.kind {
        case .root: return "Main"
        case .peer: return "Peer"
        case .tab: return "Tab"
        case .split: return "Split"
        }
    }

    // Returns the location to render this split at — the pending drag
    // value if one is in flight, else the clamped model value.
    private func effectiveLocation(for split: iTermWorkgroupSessionConfig,
                                   settings: SplitSettings) -> Double {
        if let drag = activeDrag,
           drag.region.sessionID == split.uniqueIdentifier {
            return drag.pending
        }
        return min(max(settings.location, splitLocationMin), splitLocationMax)
    }

    private func carveSplitRect(split: iTermWorkgroupSessionConfig,
                                from remaining: inout NSRect,
                                settings: SplitSettings) -> NSRect {
        let parent = remaining
        let location = effectiveLocation(for: split, settings: settings)
        let splitRect: NSRect
        let dividerRect: NSRect
        switch (settings.orientation, settings.side) {
        case (.vertical, .leadingOrTop):
            // New pane on the left, of width = parent.width * location.
            let w = parent.width * CGFloat(location)
            splitRect = NSRect(x: parent.minX, y: parent.minY,
                               width: w, height: parent.height)
            remaining = NSRect(x: parent.minX + w, y: parent.minY,
                               width: parent.width - w, height: parent.height)
            dividerRect = NSRect(
                x: parent.minX + w - dividerHitSlop,
                y: parent.minY,
                width: dividerHitSlop * 2,
                height: parent.height)
        case (.vertical, .trailingOrBottom):
            let w = parent.width * CGFloat(location)
            splitRect = NSRect(x: parent.maxX - w, y: parent.minY,
                               width: w, height: parent.height)
            remaining = NSRect(x: parent.minX, y: parent.minY,
                               width: parent.width - w, height: parent.height)
            dividerRect = NSRect(
                x: parent.maxX - w - dividerHitSlop,
                y: parent.minY,
                width: dividerHitSlop * 2,
                height: parent.height)
        case (.horizontal, .leadingOrTop):
            // leadingOrTop = top in a non-flipped view (max-Y side).
            let h = parent.height * CGFloat(location)
            splitRect = NSRect(x: parent.minX, y: parent.maxY - h,
                               width: parent.width, height: h)
            remaining = NSRect(x: parent.minX, y: parent.minY,
                               width: parent.width, height: parent.height - h)
            dividerRect = NSRect(
                x: parent.minX,
                y: parent.maxY - h - dividerHitSlop,
                width: parent.width,
                height: dividerHitSlop * 2)
        case (.horizontal, .trailingOrBottom):
            let h = parent.height * CGFloat(location)
            splitRect = NSRect(x: parent.minX, y: parent.minY,
                               width: parent.width, height: h)
            remaining = NSRect(x: parent.minX, y: parent.minY + h,
                               width: parent.width, height: parent.height - h)
            dividerRect = NSRect(
                x: parent.minX,
                y: parent.minY + h - dividerHitSlop,
                width: parent.width,
                height: dividerHitSlop * 2)
        }
        dividerRegions.append(DividerRegion(
            rect: dividerRect,
            sessionID: split.uniqueIdentifier,
            parentRect: parent,
            orientation: settings.orientation,
            side: settings.side))
        return splitRect
    }

    private func drawPane(_ session: iTermWorkgroupSessionConfig, in rect: NSRect) {
        let inset = rect.insetBy(dx: paneInset, dy: paneInset)
        let isSelected = session.uniqueIdentifier == selectedSessionID
        let fill: NSColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35)
            : NSColor.controlBackgroundColor
        let stroke: NSColor = isSelected
            ? NSColor.selectedContentBackgroundColor
            : NSColor.separatorColor
        let path = NSBezierPath(roundedRect: inset,
                                xRadius: cornerRadius, yRadius: cornerRadius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = isSelected ? 2 : 1
        path.stroke()

        // Label
        let label = paneLabel(for: session) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 11),
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: inset.midX - size.width / 2,
                               y: inset.midY - size.height / 2),
                   withAttributes: attrs)

        hitRegions.append(HitRegion(rect: rect, sessionID: session.uniqueIdentifier))
    }

    private func paneLabel(for s: iTermWorkgroupSessionConfig) -> String {
        if !s.displayName.isEmpty { return s.displayName }
        switch s.kind {
        case .root: return "Main"
        case .peer: return "Peer"
        case .split: return "Split"
        case .tab: return "Tab"
        }
    }

    // Draws a tab-bar-or-switcher segment: rounded rect with inset, with
    // an optional emphasis style.
    private enum SegmentEmphasis { case normal, active, selected }
    private func drawSegment(in rect: NSRect, label: String,
                             emphasis: SegmentEmphasis) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        let fill: NSColor
        let stroke: NSColor
        switch emphasis {
        case .selected:
            fill = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.5)
            stroke = NSColor.selectedContentBackgroundColor
        case .active:
            fill = NSColor.controlColor
            stroke = NSColor.separatorColor
        case .normal:
            fill = NSColor.windowBackgroundColor
            stroke = NSColor.separatorColor
        }
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = emphasis == .selected ? 2 : 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 11),
        ]
        let text = label as NSString
        let size = text.size(withAttributes: attrs)
        let p = NSPoint(x: rect.midX - size.width / 2,
                        y: rect.midY - size.height / 2)
        text.draw(at: p, withAttributes: attrs)
    }

    // MARK: - Hit testing

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Dividers take priority: a thin strip between panes that lets
        // the user drag to change the split location.
        for region in dividerRegions.reversed() {
            if region.rect.contains(point) {
                activeDrag = (region: region,
                              pending: locationFrom(point: point,
                                                    region: region),
                              moved: false)
                return
            }
        }

        for region in hitRegions.reversed() {
            if region.rect.contains(point) {
                selectSession(region.sessionID)
                return
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag = activeDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        drag.pending = locationFrom(point: point, region: drag.region)
        drag.moved = true
        activeDrag = drag
        needsDisplay = true
        delegate?.visualView(self,
                             didDragSplit: drag.region.sessionID,
                             location: drag.pending)
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag = activeDrag else { return }
        activeDrag = nil
        // A bare click (no drag) shouldn't commit — the location on
        // mouseDown was only computed for the initial pending preview.
        guard drag.moved else {
            needsDisplay = true
            return
        }
        delegate?.visualView(self,
                             didFinishDraggingSplit: drag.region.sessionID,
                             location: drag.pending)
    }

    // Convert a point in our coordinates into a split `location` value
    // (0...1) for the given divider's orientation/side.
    private func locationFrom(point: NSPoint,
                              region: DividerRegion) -> Double {
        let raw: CGFloat
        let parent = region.parentRect
        switch (region.orientation, region.side) {
        case (.vertical, .leadingOrTop):
            raw = (point.x - parent.minX) / max(1, parent.width)
        case (.vertical, .trailingOrBottom):
            raw = (parent.maxX - point.x) / max(1, parent.width)
        case (.horizontal, .leadingOrTop):
            // leadingOrTop in a non-flipped view = max-Y side.
            raw = (parent.maxY - point.y) / max(1, parent.height)
        case (.horizontal, .trailingOrBottom):
            raw = (point.y - parent.minY) / max(1, parent.height)
        }
        return min(max(Double(raw), splitLocationMin), splitLocationMax)
    }

    private func selectSession(_ id: String) {
        guard let wg = workgroup,
              let s = wg.session(withUniqueIdentifier: id) else { return }
        if case .tab = s.kind {
            activeTabSessionID = id
        } else if case .root = s.kind {
            activeTabSessionID = id
        }
        // Figure out the peer-group host for this click and record that
        // this session is now the group's active member. If it's a peer,
        // the host is its parent; if it's a non-peer that hosts peers,
        // it IS the host (so clicking "Main" swings the active member
        // back to Main).
        let hostID: String?
        if case .peer = s.kind {
            hostID = s.parentID
        } else {
            let hasPeerChildren = wg.sessions.contains { c in
                guard c.parentID == s.uniqueIdentifier else { return false }
                if case .peer = c.kind { return true }
                return false
            }
            hostID = hasPeerChildren ? s.uniqueIdentifier : nil
        }
        if let hostID {
            activePeerByHost[hostID] = id
        }
        selectedSessionID = id
        needsDisplay = true
        delegate?.visualView(self, didSelectSessionID: id)
    }
}
