//
//  PSMTabGroupDragInvariantTests.swift
//  iTerm2XCTests
//
//  Table-driven checks for dragging a tab group. Each case builds a real tab
//  bar (a tab view, group membership and collapsed flags pushed the way the
//  window controller pushes them, laid out by the bar itself), starts a group
//  drag through the real entry point, and drives the real drag animation loop
//  tick by tick with a scripted mouse. Rules that don't depend on how
//  targeting works are checked along the way:
//
//    * Picking up a group moves nothing else in the bar.
//    * Holding the mouse still settles: the target and the open slots stop
//      changing.
//    * Every place the group may legally land can be reached by holding the
//      mouse somewhere, and no held position offers a place it may not land.
//    * Moving the mouse one way never moves the target the other way.
//    * An open slot is the size of the group.
//
//  Where the group may land comes from the layout description, not from the
//  drag code, so the tests don't just repeat what the code believes.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Layout description

// One item in a tab bar: a loose tab, or a group of items. Nesting is one
// level deep, so a group's items are tabs or sub-groups of tabs.
private indirect enum BarItem {
    case tab
    case group(String, collapsed: Bool, [BarItem])
}

private struct ModelTab {
    let label: String
    let group: String?
    let parent: String?

    var topLevelGroup: String? { parent ?? group }
}

private struct ModelGroup {
    let id: String
    let parent: String?
    let collapsed: Bool
}

private struct BarLayout: CustomStringConvertible {
    let items: [BarItem]
    private(set) var tabs: [ModelTab] = []
    private(set) var groups: [String: ModelGroup] = [:]
    // Groups in bar order.
    private(set) var groupOrder: [String] = []

    init(_ items: [BarItem]) {
        self.items = items
        var looseCount = 0
        func add(_ item: BarItem, group: String?, parent: String?) {
            switch item {
            case .tab:
                if let group {
                    let n = tabs.filter { $0.group == group }.count + 1
                    tabs.append(ModelTab(label: "\(group)\(n)", group: group, parent: parent))
                } else {
                    looseCount += 1
                    tabs.append(ModelTab(label: "t\(looseCount)", group: nil, parent: nil))
                }
            case let .group(id, collapsed, children):
                groups[id] = ModelGroup(id: id, parent: group, collapsed: collapsed)
                groupOrder.append(id)
                for child in children {
                    add(child, group: id, parent: group)
                }
            }
        }
        for item in items {
            add(item, group: nil, parent: nil)
        }
    }

    // Whether the tab is hidden: its group or its group's parent is collapsed.
    func isHidden(_ tab: ModelTab) -> Bool {
        return [tab.group, tab.parent].compactMap { $0 }.contains { groups[$0]!.collapsed }
    }

    func isHidden(group id: String) -> Bool {
        guard let parent = groups[id]?.parent else {
            return false
        }
        return groups[parent]!.collapsed
    }

    func members(of id: String) -> [ModelTab] {
        return tabs.filter { $0.group == id || $0.parent == id }
    }

    var description: String {
        func describe(_ item: BarItem, counter: inout Int, counts: inout [String: Int], group: String?) -> String {
            switch item {
            case .tab:
                if let group {
                    counts[group, default: 0] += 1
                    return "\(group)\(counts[group]!)"
                }
                counter += 1
                return "t\(counter)"
            case let .group(id, collapsed, children):
                let inner = children.map { describe($0, counter: &counter, counts: &counts, group: id) }
                return "[\(id)\(collapsed ? "*" : ""): \(inner.joined(separator: " "))]"
            }
        }
        var counter = 0
        var counts: [String: Int] = [:]
        return items.map { describe($0, counter: &counter, counts: &counts, group: nil) }.joined(separator: " ")
    }
}

// Where a dropped group lands: before `anchor` (nil for the end of the bar),
// as a sub-group of `parent` (nil for top level).
private struct GroupDropOutcome: Hashable, CustomStringConvertible, Comparable {
    let anchor: String?
    let parent: String?

    var description: String {
        return "before \(anchor ?? "end")" + (parent.map { " in \($0)" } ?? "")
    }

    static func < (lhs: GroupDropOutcome, rhs: GroupDropOutcome) -> Bool {
        return lhs.description < rhs.description
    }
}

// The places a group may land, from the rules of nesting alone:
//  * Anywhere between top-level items, at top level.
//  * Just inside the front or the end of an expanded top-level group, if the
//    dragged group can be nested (it has no sub-groups of its own).
//  * Anywhere between the items of an expanded top-level group, inside it, if
//    the dragged group can be nested. Never inside a sub-group or a collapsed
//    group.
//  * Where it already is.
private func legalOutcomes(dragging id: String, in layout: BarLayout) -> Set<GroupDropOutcome> {
    let memberLabels = Set(layout.members(of: id).map(\.label))
    let canNest = !layout.tabs.contains { $0.parent == id }
    let remaining = layout.tabs.filter { !memberLabels.contains($0.label) }
    var out = Set<GroupDropOutcome>()
    for i in 0...remaining.count {
        let before = i > 0 ? remaining[i - 1] : nil
        let after = i < remaining.count ? remaining[i] : nil
        let anchor = after?.label
        if let top = before?.topLevelGroup, top == after?.topLevelGroup {
            // Between two items of the same top-level group.
            if layout.groups[top]!.collapsed {
                continue
            }
            if let sub = before?.parent != nil ? before?.group : nil, sub == after?.group {
                // Inside one of its sub-groups.
                continue
            }
            if canNest {
                out.insert(GroupDropOutcome(anchor: anchor, parent: top))
            }
            continue
        }
        out.insert(GroupDropOutcome(anchor: anchor, parent: nil))
        if canNest {
            // Just inside the end of the group before, or the front of the
            // group after.
            for top in [before?.topLevelGroup, after?.topLevelGroup].compactMap({ $0 })
            where !layout.groups[top]!.collapsed {
                out.insert(GroupDropOutcome(anchor: anchor, parent: top))
            }
        }
    }
    // Where it is now. A sub-group that is its parent's only content leaves no
    // gap inside the parent above, but it can still stay put.
    let lastMember = layout.tabs.lastIndex { memberLabels.contains($0.label) }!
    let next = layout.tabs[(lastMember + 1)...].first { !memberLabels.contains($0.label) }
    out.insert(GroupDropOutcome(anchor: next?.label, parent: layout.groups[id]!.parent))
    return out
}

// Orders outcomes by where they put the group, left to right. Outcomes that
// share an anchor differ only in nesting: inside the end of the group before
// the gap comes first, then top level, then inside the front of the group
// after it.
private func rank(of outcome: GroupDropOutcome, dragging id: String, in layout: BarLayout) -> (Int, Int) {
    let memberLabels = Set(layout.members(of: id).map(\.label))
    let remaining = layout.tabs.filter { !memberLabels.contains($0.label) }
    let gap = outcome.anchor.flatMap { anchor in remaining.firstIndex { $0.label == anchor } } ?? remaining.count
    let groupBefore = gap > 0 ? remaining[gap - 1].topLevelGroup : nil
    let groupAfter = gap < remaining.count ? remaining[gap].topLevelGroup : nil
    guard let parent = outcome.parent, groupBefore != groupAfter else {
        return (gap, 1)
    }
    if parent == groupBefore {
        return (gap, 0)
    }
    if parent == groupAfter {
        return (gap, 2)
    }
    return (gap, 1)
}

// MARK: - Tab bar plumbing

private final class FakeTabGroup: NSObject, PSMTabGroup {
    let name: String
    let color: NSColor
    init(name: String) {
        self.name = name
        self.color = .systemBlue
    }
}

// Stands in for the app's tab object as a tab view item's identifier. Styles
// ask it for drawing details without checking that it answers.
private final class FakeTabIdentifier: NSObject {
    let label: String
    init(_ label: String) {
        self.label = label
    }
    @objc func psmTabGraphic() -> NSImage? { nil }
    @objc func icon() -> NSImage? { nil }
}

private final class FakeTabGroupDataSource: NSObject, PSMTabGroupDataSource {
    func tabGroup(withIdentifier identifier: String) -> PSMTabGroup? {
        return FakeTabGroup(name: identifier)
    }
}

// MARK: - Tests

final class PSMTabGroupDragInvariantTests: XCTestCase {
    private var window: NSWindow!
    private var tabView: NSTabView?
    private var control: PSMTabBarControl?
    private var dragDriver: FakeTabDragSessionDriver!
    private var savedDragDriver: PSMTabDragSessionDriver!
    private var savedScrollable = false
    private let dataSource = FakeTabGroupDataSource()

    private var assistant: PSMTabDragAssistant {
        return PSMTabDragAssistant.shared()
    }

    override func setUp() {
        super.setUp()
        // Never arm a real NSDraggingSession; see FakeTabDragSessionDriver.
        savedDragDriver = assistant.dragSessionDriver
        dragDriver = FakeTabDragSessionDriver()
        assistant.dragSessionDriver = dragDriver
        savedScrollable = iTermPreferences.bool(forKey: kPreferenceKeyScrollableSideTabBar)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyScrollableSideTabBar)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1007, height: 400),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        window.contentView?.wantsLayer = true
    }

    override func tearDown() {
        assistant.finishDrag()
        assistant.dragSessionDriver = savedDragDriver
        iTermPreferences.setBool(savedScrollable, forKey: kPreferenceKeyScrollableSideTabBar)
        removeBar()
        savedDragDriver = nil
        dragDriver = nil
        window = nil
        super.tearDown()
    }

    private func removeBar() {
        control?.removeFromSuperview()
        tabView?.removeFromSuperview()
        control = nil
        tabView = nil
    }

    // Builds the bar the way the app does: tab view items, then membership and
    // collapsed state pushed by tab view item, then a layout pass. The bar
    // matches the one in the field: scrollable, 1007pt wide, minimal style,
    // with the window buttons in the bar.
    private func makeBar(_ layout: BarLayout) -> PSMTabBarControl {
        removeBar()
        let tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 1007, height: 376))
        tabView.tabViewType = .noTabsNoBorder
        let control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 1007, height: 24))
        control.style = PSMYosemiteTabStyle()
        control.insets = NSEdgeInsets(top: 0, left: 136, bottom: 0, right: 0)
        control.tabView = tabView
        control.tabGroupDataSource = dataSource
        tabView.delegate = control
        window.contentView?.addSubview(tabView)
        window.contentView?.addSubview(control)
        var items: [NSTabViewItem] = []
        for tab in layout.tabs {
            let item = NSTabViewItem(identifier: FakeTabIdentifier(tab.label))
            item.label = tab.label
            item.view = NSView()
            tabView.addTabViewItem(item)
            items.append(item)
        }
        control.setTabGroupIdentifiers(layout.tabs.map { ($0.group as Any?) ?? NSNull() },
                                       parentIdentifiers: layout.tabs.map { ($0.parent as Any?) ?? NSNull() },
                                       for: items)
        control.setTabGroupCollapsedFlags(layout.tabs.map { NSNumber(value: layout.isHidden($0)) },
                                          parentCollapsedFlags: layout.tabs.map { tab in
                                              NSNumber(value: tab.parent.map { layout.groups[$0]!.collapsed } ?? false)
                                          },
                                          for: items)
        control.updateWithoutAnimation()
        self.tabView = tabView
        self.control = control
        return control
    }

    private func cells(_ control: PSMTabBarControl) -> [PSMTabBarCell] {
        return control.cells() as! [PSMTabBarCell]
    }

    private func label(_ cell: PSMTabBarCell) -> String? {
        return (cell.representedObject as? NSTabViewItem)?.label
    }

    private func chip(_ id: String, in control: PSMTabBarControl) -> PSMTabBarCell? {
        return cells(control).first { $0.isTabGroupChip && $0.tabGroupIdentifier == id }
    }

    // The cells the bar hands the drag when a chip is dragged: its run.
    private func members(ofChip chip: PSMTabBarCell, in control: PSMTabBarControl) -> [PSMTabBarCell] {
        let all = cells(control)
        let gid = chip.tabGroupIdentifier!
        var out: [PSMTabBarCell] = []
        for cell in all[(all.firstIndex { $0 === chip }! + 1)...] {
            if !cell.continuesRun(ofTabGroup: gid) {
                break
            }
            if !cell.isTabGroupChip {
                out.append(cell)
            }
        }
        return out
    }

    // Visible frames of everything but the dragged group, keyed by tab label
    // or "chip:<id>". Chips are re-created mid-drag, so identity can't be used.
    private func frames(in control: PSMTabBarControl, excluding dragged: Set<String>) -> [String: NSRect] {
        var out: [String: NSRect] = [:]
        for cell in cells(control) where !cell.isPlaceholder && cell.frame.width > 0 && cell.frame.height > 0 {
            if cell.isTabGroupChip {
                let gid = cell.tabGroupIdentifier!
                if !dragged.contains(gid) {
                    out["chip:\(gid)"] = cell.frame
                }
            } else if let label = label(cell), !dragged.contains(label) {
                out[label] = cell.frame
            }
        }
        return out
    }

    private func mouseDownEvent(at point: NSPoint, in control: PSMTabBarControl) -> NSEvent {
        return NSEvent.mouseEvent(with: .leftMouseDown,
                                  location: control.convert(point, to: nil),
                                  modifierFlags: [],
                                  timestamp: 0,
                                  windowNumber: window.windowNumber,
                                  context: nil,
                                  eventNumber: 0,
                                  clickCount: 1,
                                  pressure: 1)!
    }

    // Where the group would land if dropped now, read the way the drop reads
    // it: before the first remaining tab at or after the target, nested in
    // whatever group the target is inside.
    private func outcome(in control: PSMTabBarControl,
                         members: [PSMTabBarCell],
                         canNest: Bool) -> GroupDropOutcome? {
        guard let target = assistant.targetCell() else {
            return nil
        }
        let all = cells(control)
        guard let index = all.firstIndex(where: { $0 === target }) else {
            return nil
        }
        let anchor = all[index...].first { cell in
            !cell.isTabGroupChip && !cell.isPlaceholder && !members.contains { $0 === cell }
        }
        let parent = canNest ? assistant.parentGroupForGroupDrop(at: target, in: all, excluding: members) : nil
        return GroupDropOutcome(anchor: anchor.flatMap(label), parent: parent)
    }

    // Which slots are open and how far, plus the target's position: if this
    // changes while the mouse holds still, something in the bar is moving.
    private func fingerprint(_ control: PSMTabBarControl) -> String {
        let all = cells(control)
        let target = assistant.targetCell().flatMap { t in all.firstIndex { $0 === t } } ?? -1
        let open = all.enumerated()
            .filter { $0.element.isPlaceholder && $0.element.currentStep > 0 }
            .map { "\($0.offset):\($0.element.currentStep)" }
        return "target=\(target) open=[\(open.joined(separator: ","))]"
    }

    private func tick(_ control: PSMTabBarControl, x: CGFloat) {
        assistant.setCurrentMouseLoc(NSPoint(x: x, y: NSMidY(control.bounds)))
        assistant.calculateDragAnimation(forTabBar: control)
    }

    // Runs one drag of group `id` and returns every broken rule.
    private func check(_ layout: BarLayout, dragging id: String) -> [String] {
        let control = makeBar(layout)
        guard let chip = chip(id, in: control), chip.frame.width > 0 else {
            return ["\(layout): no visible chip for \(id)"]
        }
        let members = members(ofChip: chip, in: control)
        let canNest = !layout.tabs.contains { $0.parent == id }
        var dragged = Set(layout.members(of: id).map(\.label))
        dragged.insert(id)
        for (sub, group) in layout.groups where group.parent == id {
            dragged.insert(sub)
        }
        let before = frames(in: control, excluding: dragged)
        // The group's whole run, from its chip to its last tab.
        let allBefore = cells(control)
        let chipIndex = allBefore.firstIndex { $0 === chip }!
        let lastMemberIndex = allBefore.lastIndex { cell in members.contains { $0 === cell } }!
        let runFrame = allBefore[chipIndex...lastMemberIndex].map(\.frame).reduce(NSRect.zero) { NSUnionRect($0, $1) }
        let barEnd = cells(control).map(\.frame.maxX).max()!
        let grab = NSMidX(chip.frame)
        var failures: [String] = []
        func fail(_ message: String) {
            failures.append("\(layout), dragging \(id): \(message)")
        }

        assistant.startDraggingGroup(withChip: chip,
                                     members: members,
                                     fromTabBar: control,
                                     withMouseDownEvent: mouseDownEvent(at: NSPoint(x: grab, y: NSMidY(control.bounds)),
                                                                        in: control))

        // Rule: picking up the group moves nothing else. Wiggle near the grab
        // point without pausing, then hold.
        let wiggle: [CGFloat] = [-1, -3, -5, -3, -1, 1, 3, 5, 3, 1, -1, -3]
        let pickUp = wiggle.map { grab + $0 } + Array(repeating: grab, count: 12)
        var moved: [String] = []
        for (n, x) in pickUp.enumerated() {
            tick(control, x: x)
            let now = frames(in: control, excluding: dragged)
            for (key, frame) in before {
                guard let current = now[key] else {
                    moved.append("tick \(n): \(key) vanished")
                    continue
                }
                if abs(current.minX - frame.minX) > 2 || abs(current.width - frame.width) > 2 {
                    moved.append("tick \(n): \(key) \(Int(frame.minX))+\(Int(frame.width)) -> \(Int(current.minX))+\(Int(current.width))")
                }
            }
        }
        if !moved.isEmpty {
            fail("picking it up moved other cells: \(moved.prefix(6).joined(separator: "; "))")
        }

        // Sweep across the bar and back, holding at each position.
        let positions = Array(stride(from: control.insets.left - 8, through: barEnd + 40, by: 4))
        let holdTicks = 24
        var reached = Set<GroupDropOutcome>()
        var unsettled: [String] = []
        var misshapen: [String] = []
        var outOfOrder: [String] = []
        var previous: (x: CGFloat, outcome: GroupDropOutcome)?
        var lastX = grab
        for (n, x) in (positions + positions.reversed()).enumerated() {
            if n == positions.count {
                // Turning around.
                previous = nil
            }
            let forward = n < positions.count
            // Get there in two moving ticks, then hold.
            tick(control, x: (lastX + x) / 2)
            lastX = x
            var prints: [String] = []
            for _ in 0..<holdTicks {
                tick(control, x: x)
                prints.append(fingerprint(control))
            }
            let tail = prints.suffix(8)
            if Set(tail).count > 1 {
                unsettled.append("x=\(Int(x)): \(Array(tail))")
            }
            guard let target = assistant.targetCell(),
                  target.currentStep == Int32(kPSMTabDragAnimationSteps - 1),
                  let reachedOutcome = outcome(in: control, members: members, canNest: canNest) else {
                continue
            }
            reached.insert(reachedOutcome)

            // Rule: an open slot has room for the group.
            if abs(target.frame.width - runFrame.width) > 1 || abs(target.frame.height - runFrame.height) > 1 {
                misshapen.append("x=\(Int(x)): \(reachedOutcome) is \(Int(target.frame.width))x\(Int(target.frame.height)), "
                                 + "the group is \(Int(runFrame.width))x\(Int(runFrame.height))")
            }

            // Rule: moving the mouse one way never moves the target the other way.
            if let previous {
                let was = rank(of: previous.outcome, dragging: id, in: layout)
                let now = rank(of: reachedOutcome, dragging: id, in: layout)
                if forward ? now < was : now > was {
                    outOfOrder.append("x=\(Int(previous.x)): \(previous.outcome), then x=\(Int(x)): \(reachedOutcome)")
                }
            }
            previous = (x, reachedOutcome)
        }
        if !misshapen.isEmpty {
            fail("open slot the wrong size at \(misshapen.count) positions, e.g. \(misshapen.prefix(3).joined(separator: "; "))")
        }
        if !outOfOrder.isEmpty {
            fail("target moved against the mouse: \(outOfOrder.prefix(4).joined(separator: "; "))")
        }
        if !unsettled.isEmpty {
            fail("never settled at \(unsettled.count) held positions, e.g. \(unsettled.prefix(3).joined(separator: "; "))")
        }
        let legal = legalOutcomes(dragging: id, in: layout)
        let missing = legal.subtracting(reached).sorted()
        if !missing.isEmpty {
            fail("can't reach: \(missing.map(\.description).joined(separator: ", "))")
        }
        let illegal = reached.subtracting(legal).sorted()
        if !illegal.isEmpty {
            fail("offered illegal drops: \(illegal.map(\.description).joined(separator: ", "))")
        }
        assistant.finishDrag()
        return failures
    }

    // Every group that can be picked up in the layout: those with a visible chip.
    private func draggableGroups(_ layout: BarLayout) -> [String] {
        return layout.groupOrder.filter { !layout.isHidden(group: $0) }
    }

    private func checkAll(_ layouts: [BarLayout], file: StaticString = #filePath, line: UInt = #line) {
        var failures: [String] = []
        var cases = 0
        for layout in layouts {
            for id in draggableGroups(layout) {
                cases += 1
                // Free each drag's autoreleased objects before the next.
                autoreleasepool {
                    failures += check(layout, dragging: id)
                }
            }
        }
        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count) problems in \(cases) drags:\n\(failures.joined(separator: "\n"))",
                      file: file, line: line)
    }

    // MARK: - Layouts

    // The building blocks: a loose tab, a group, and a group with a sub-group,
    // in every collapsed/expanded combination. `id` names the group.
    private static func variants(_ id: String) -> [BarItem] {
        let sub = id.lowercased()
        return [
            .tab,
            .group(id, collapsed: false, [.tab, .tab]),
            .group(id, collapsed: true, [.tab, .tab]),
            .group(id, collapsed: false, [.tab, .group(sub, collapsed: false, [.tab, .tab])]),
            .group(id, collapsed: false, [.tab, .group(sub, collapsed: true, [.tab, .tab])]),
            .group(id, collapsed: false, [.group(sub, collapsed: false, [.tab, .tab]), .tab]),
            .group(id, collapsed: false, [.group(sub, collapsed: true, [.tab, .tab]), .tab]),
            .group(id, collapsed: true, [.tab, .group(sub, collapsed: false, [.tab, .tab])]),
        ]
    }

    // Every pair of building blocks.
    func testEveryPairOfItems() {
        var layouts: [BarLayout] = []
        for first in Self.variants("A") {
            for second in Self.variants("B") {
                layouts.append(BarLayout([first, second]))
            }
        }
        checkAll(layouts)
    }

    // The bars from field reports.
    func testFieldLayouts() {
        checkAll([
            // A collapsed group, then an expanded one.
            BarLayout([.group("S", collapsed: true, [.tab, .tab]),
                       .group("P", collapsed: false, [.tab, .tab, .tab])]),
            // A collapsed sub-group first in its parent, then more tabs.
            BarLayout([.group("P", collapsed: false, [.group("S", collapsed: true, [.tab, .tab]), .tab, .tab, .tab]),
                       .tab,
                       .group("Q", collapsed: true, [.tab])]),
            // A parent ending with a collapsed sub-group, then a tab or a pill:
            // the parent's end slot is still a drop target.
            BarLayout([.group("G", collapsed: false, [.tab]),
                       .group("P", collapsed: false, [.tab, .group("S", collapsed: true, [.tab, .tab])]),
                       .tab]),
            BarLayout([.group("G", collapsed: false, [.tab]),
                       .group("P", collapsed: false, [.tab, .group("S", collapsed: true, [.tab, .tab])]),
                       .group("Q", collapsed: true, [.tab])]),
        ])
    }
}
