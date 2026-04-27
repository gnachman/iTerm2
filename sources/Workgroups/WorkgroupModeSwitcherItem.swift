//
//  WorkgroupModeSwitcherItem.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import AppKit

protocol WorkgroupModeSwitcherItemDelegate: AnyObject {
    // The user picked a peer from the switcher; `identifier` is the
    // peer session's uniqueIdentifier.
    func workgroupModeSwitcher(_ item: WorkgroupModeSwitcherItem,
                               didSelect identifier: String)
}

// An NSSegmentedControl-backed toolbar item whose segments are a
// workgroup peer group's members. Segments carry the peers'
// uniqueIdentifiers; the visible label on each is the peer's
// configured displayName.
final class WorkgroupModeSwitcherItem: SessionToolbarControl {
    weak var modeSwitchDelegate: WorkgroupModeSwitcherItemDelegate?
    private let segmentedControl: NSSegmentedControl
    // Segment index → peer-session unique identifier.
    private var identifiers: [String]

    init(identifier: String,
         priority: Int,
         members: [(identifier: String, label: String)],
         activeIdentifier: String) {
        self.identifiers = members.map { $0.identifier }
        // Suffix each label with its activation shortcut: ⌥⇧⌘1..8
        // for the first eight segments; ⌥⇧⌘9 also appears on the
        // last segment when there are nine or more peers (so the
        // "always go to last" hint is visible). For ≤8 peers the
        // direct number wins on the last segment because it's how
        // the user thinks ("press 5 for the 5th peer").
        let labels = members.enumerated().map { (index, member) -> String in
            guard let suffix = Self.shortcutLabel(forSegmentIndex: index,
                                                  total: members.count) else {
                return member.label
            }
            // U+2003 EM SPACE — wider than a regular space so the
            // shortcut hint reads as a separate visual cluster from
            // the peer's name.
            return "\(member.label)\u{2003}\(suffix)"
        }
        segmentedControl = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: nil,
            action: #selector(modeChanged(_:)))
        segmentedControl.segmentStyle = .texturedRounded
        if let idx = identifiers.firstIndex(of: activeIdentifier) {
            segmentedControl.selectedSegment = idx
        }
        super.init(identifier: identifier,
                   priority: priority,
                   control: segmentedControl)
        segmentedControl.target = self
    }

    // Shortcut suffix for a segment label, or nil if no shortcut maps
    // to this segment. Modifier order matches macOS shortcut display:
    // ⌃⌥⇧⌘ (we have no ⌃, so ⌥⇧⌘).
    private static func shortcutLabel(forSegmentIndex i: Int,
                                      total: Int) -> String? {
        let n = i + 1
        if n <= 8 {
            return "⌥⇧⌘\(n)"
        }
        if n == total {
            return "⌥⇧⌘9"
        }
        return nil
    }


    func setActiveIdentifier(_ identifier: String) {
        if let idx = identifiers.firstIndex(of: identifier) {
            segmentedControl.selectedSegment = idx
        }
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        let natural = max(_view.fittingSize.width, 0)
        return (30.0 * CGFloat(segmentedControl.segmentCount))...natural
    }

    @objc
    private func modeChanged(_ sender: Any?) {
        let idx = segmentedControl.indexOfSelectedItem
        guard idx >= 0, idx < identifiers.count else { return }
        modeSwitchDelegate?.workgroupModeSwitcher(self,
                                                  didSelect: identifiers[idx])
    }
}
