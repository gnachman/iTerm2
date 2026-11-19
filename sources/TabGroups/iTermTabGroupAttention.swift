//
//  iTermTabGroupAttention.swift
//  iTerm2SharedARC
//
//  A collapsed tab group hides its member tabs, and with them each tab's
//  icon (status dot, dead, bell, new output). So the group's chip shows the
//  icon of its most urgent member instead. This file holds the ranking.
//

import Foundation

// Which icon a tab shows. -[PTYTab iconKind] decides this using the same
// precedence -[PTYTab updateIcon] uses, so a collapsed chip and an expanded
// tab always agree.
@objc(iTermTabIconKind)
enum TabIconKind: Int {
    case none
    case idle
    case newOutput
    case bell
    case dead
    case status
}

@objc(iTermTabAttentionCandidate)
final class TabAttentionCandidate: NSObject {
    // The icon the tab shows.
    @objc let kind: TabIconKind
    // From iTermStatusPrioritySettings, where lower is more urgent. Only
    // meaningful when kind is .status.
    @objc let statusPriority: Int
    // The tab's session ended, whatever icon it shows.
    @objc let isDead: Bool
    // The tab rang the bell, whatever icon it shows.
    @objc let ringingBell: Bool

    @objc init(kind: TabIconKind, statusPriority: Int, isDead: Bool, ringingBell: Bool) {
        self.kind = kind
        self.statusPriority = statusPriority
        self.isDead = isDead
        self.ringingBell = ringingBell
    }

    override var description: String {
        return "<TabAttentionCandidate kind=\(kind.rawValue) statusPriority=\(statusPriority) isDead=\(isDead) ringingBell=\(ringingBell)>"
    }
}

@objc(iTermTabGroupAttentionResult)
final class TabGroupAttentionResult: NSObject {
    // The member that decided the result.
    @objc let index: Int
    // What the chip shows. It can differ from that member's own icon: a dead
    // member that rang the bell shows the dead icon but makes the chip show a
    // bell.
    @objc let kind: TabIconKind

    init(index: Int, kind: TabIconKind) {
        self.index = index
        self.kind = kind
    }
}

@objc(iTermTabGroupAttention)
final class TabGroupAttention: NSObject {
    // What a collapsed group's chip should show, or nil when no member needs
    // attention. In order of urgency:
    //   status: any member's status dot, ranked by status priority.
    //   dead: only when every member is dead. One finished job among running
    //     ones isn't worth flagging the group.
    //   bell: any member that rang the bell, even one whose own icon shows
    //     something else.
    //   new output, including "idle" (new output that has stopped arriving,
    //     shown with the same icon).
    // Ties go to the earliest member so the chip doesn't flip between equally
    // urgent tabs.
    @objc(mostUrgent:)
    static func mostUrgent(_ candidates: [TabAttentionCandidate]) -> TabGroupAttentionResult? {
        let allDead = !candidates.isEmpty && candidates.allSatisfy { $0.isDead }
        var best: (index: Int, rank: Rank)?
        for (i, candidate) in candidates.enumerated() {
            guard let rank = Rank(candidate, allDead: allDead) else {
                continue
            }
            if best == nil || rank < best!.rank {
                best = (i, rank)
            }
        }
        guard let best else {
            return nil
        }
        return TabGroupAttentionResult(index: best.index, kind: best.rank.kind)
    }

    // Smaller is more urgent.
    private struct Rank: Comparable {
        let kind: TabIconKind
        private let tier: Int
        private let statusPriority: Int

        init?(_ candidate: TabAttentionCandidate, allDead: Bool) {
            if candidate.kind == .status {
                kind = .status
                tier = 0
                statusPriority = candidate.statusPriority
            } else if allDead && candidate.isDead {
                kind = .dead
                tier = 1
                statusPriority = 0
            } else if candidate.ringingBell {
                kind = .bell
                tier = 2
                statusPriority = 0
            } else if candidate.kind == .newOutput || candidate.kind == .idle {
                // Idle is new output that has stopped arriving: still unseen,
                // and drawn with the same icon.
                kind = candidate.kind
                tier = 3
                statusPriority = 0
            } else {
                return nil
            }
        }

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            if lhs.tier != rhs.tier {
                return lhs.tier < rhs.tier
            }
            return lhs.statusPriority < rhs.statusPriority
        }

        static func == (lhs: Rank, rhs: Rank) -> Bool {
            return lhs.tier == rhs.tier && lhs.statusPriority == rhs.statusPriority
        }
    }
}
