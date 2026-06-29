//
//  iTermLayoutSpecValidator.swift
//  iTerm2SharedARC
//
//  Structural validation of a parsed `LayoutSpec`. Runs after
//  `LayoutSpec.parse` and before live-state resolution. Catches:
//
//  - Splitters with fewer than 2 children
//  - Same-orientation nesting (V inside V, H inside H)
//  - Excessive tree depth
//  - Duplicate session GUIDs anywhere in the spec
//
//  These rules apply to pure data and require no PTYTab / PTYSession
//  state. Live-state checks (orphan sessions, missing tabs, tmux
//  rejection, etc.) live in the resolver, not here.
//

import Foundation

enum LayoutSpecValidator {

    /// Maximum allowed tree depth. Generous, but prevents pathological
    /// recursion and keeps memory bounded.
    static let maxDepth = 32

    /// Validates structural rules. Throws `LayoutSpecError` on the first
    /// violation, with a tree-path-prefixed message.
    static func validate(_ spec: LayoutSpec) throws {
        var seenSessions = Set<String>()

        for (i, tab) in spec.tabs.enumerated() {
            try walk(tab.root,
                    path: "tabs[\(i)].root",
                    parentVertical: nil,
                    depth: 0,
                    seenSessions: &seenSessions)
        }
        for (i, newTab) in spec.newTabs.enumerated() {
            try walk(newTab.root,
                    path: "new_tabs[\(i)].root",
                    parentVertical: nil,
                    depth: 0,
                    seenSessions: &seenSessions)
        }
        for (i, newWindow) in spec.newWindows.enumerated() {
            try walk(newWindow.root,
                    path: "new_windows[\(i)].root",
                    parentVertical: nil,
                    depth: 0,
                    seenSessions: &seenSessions)
        }
    }

    private static func walk(_ node: LayoutNode,
                             path: String,
                             parentVertical: Bool?,
                             depth: Int,
                             seenSessions: inout Set<String>) throws {
        if depth > maxDepth {
            throw LayoutSpecError.treeTooDeep(path: path, depth: depth)
        }

        switch node {
        case .splitter(let vertical, let children):
            if children.count < 2 {
                throw LayoutSpecError.splitterTooFewChildren(path: path, count: children.count)
            }
            if let parent = parentVertical, parent == vertical {
                throw LayoutSpecError.nestedSameOrientation(path: path)
            }
            for (i, child) in children.enumerated() {
                try walk(child,
                        path: "\(path).children[\(i)]",
                        parentVertical: vertical,
                        depth: depth + 1,
                        seenSessions: &seenSessions)
            }

        case .session(let guid):
            if !seenSessions.insert(guid).inserted {
                throw LayoutSpecError.duplicateSessionID(guid: guid)
            }

        case .newSession:
            // New sessions don't have an existing-session GUID to check
            // for duplication; the resolver will assign their identity.
            break
        }
    }
}
