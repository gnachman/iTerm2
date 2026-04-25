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
        let labels = members.map { $0.label }
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
