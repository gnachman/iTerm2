//
//  WorkgroupToolbarBuilder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import AppKit

// Runtime dependencies needed to construct the concrete
// SessionToolbarGenericView for a single iTermWorkgroupToolbarItem.
// Anything the Phase-1 settings UI can't know about lives here.
struct WorkgroupToolbarContext {
    // The peer port responsible for this toolbar. The mode-switcher
    // item hands peer-switch taps to it, and the changed-file selector
    // forwards file clicks. Nil for non-peer toolbars (split/tab).
    weak var peerPort: iTermWorkgroupPeerPort?
    // Shared git poller if at least one item in the set needs one
    // (gitStatus, changedFileSelector). Built once per workgroup
    // instance; nil if nothing asked for it.
    let gitPoller: iTermGitPoller?
    // Variable scope used by the git-status label's template engine
    // to resolve variables like `\(session.cwd)`.
    let scope: iTermVariableScope
    // Peer-group members for the mode switcher (identifier + label),
    // and which one is currently active. Empty for non-peer toolbars.
    let peerGroupMembers: [(identifier: String, label: String)]
    let activePeerIdentifier: String
    // Invoked when the user taps a back/forward/reload/settings button.
    // The registry kind string is passed back so the caller can tell
    // them apart.
    let onButtonTapped: ((String) -> Void)?
}

// Does an item in a given peer-group need the shared git poller to be
// constructed?
extension iTermWorkgroupToolbarItem {
    var needsGitPoller: Bool {
        switch self {
        case .gitStatus, .changedFileSelector: return true
        default: return false
        }
    }
}

// Constructs SessionToolbarGenericView instances for a workgroup.
enum WorkgroupToolbarBuilder {
    // Build the union of items across every session in `sessions`,
    // deduping repeats (e.g. multiple peers that each declare a
    // mode-switcher get one shared instance). Returned order follows
    // first-appearance order across the inputs. Items that need the
    // git poller but whose context has no poller are dropped.
    static func buildUnion(
        fromSessions sessions: [iTermWorkgroupSession],
        context: WorkgroupToolbarContext
    ) -> [(item: iTermWorkgroupToolbarItem, view: SessionToolbarGenericView)] {
        var seen = Set<iTermWorkgroupToolbarItem>()
        var ordered: [iTermWorkgroupToolbarItem] = []
        for session in sessions {
            for item in session.toolbarItems {
                if seen.insert(item).inserted {
                    ordered.append(item)
                }
            }
        }
        return ordered.compactMap { item in
            guard let view = build(item: item, context: context) else {
                return nil
            }
            return (item: item, view: view)
        }
    }

    // Build a single item. Returns nil when the item can't be
    // realized in this context (e.g. needs git poller but none was
    // provided).
    static func build(item: iTermWorkgroupToolbarItem,
                      context: WorkgroupToolbarContext) -> SessionToolbarGenericView? {
        switch item {
        case .gitStatus:
            guard let poller = context.gitPoller else { return nil }
            return CCGitSessionToolbarItem(identifier: item.kind,
                                           priority: 2,
                                           scope: context.scope,
                                           poller: poller)
        case .changedFileSelector:
            guard let poller = context.gitPoller else { return nil }
            let view = CCDiffSelectorItem(identifier: item.kind,
                                          priority: 2,
                                          poller: poller)
            view.diffSelectorDelegate = context.peerPort
            return view
        case .modeSwitcher:
            let view = WorkgroupModeSwitcherItem(
                identifier: item.kind,
                priority: 1,
                members: context.peerGroupMembers,
                activeIdentifier: context.activePeerIdentifier)
            view.modeSwitchDelegate = context.peerPort
            return view
        case .back:
            return makeButton(item: item, symbol: .chevronLeft, context: context)
        case .forward:
            return makeButton(item: item, symbol: .chevronRight, context: context)
        case .reload:
            return makeButton(item: item, symbol: .arrowClockwise, context: context)
        case .settings:
            return makeButton(item: item, symbol: .gearshape, context: context)
        case .spacer(let minW, let maxW):
            return SessionToolbarSpacer(identifier: item.kind,
                                        priority: 1,
                                        minWidth: minW,
                                        maxWidth: maxW)
        }
    }

    private static func makeButton(item: iTermWorkgroupToolbarItem,
                                   symbol: SFSymbol,
                                   context: WorkgroupToolbarContext) -> SessionToolbarGenericView? {
        let image = NSImage(systemSymbolName: symbol.rawValue,
                            accessibilityDescription: nil) ?? NSImage()
        let view = CCModeButtonToolbarItem(identifier: item.kind,
                                           priority: 3,
                                           image: image)
        let handler = context.onButtonTapped
        view.buttonDelegate = ButtonForwarder(kind: item.kind,
                                              handler: handler)
        // Retain the forwarder on the view so it stays alive.
        objc_setAssociatedObject(view._view,
                                 &ButtonForwarderKey,
                                 view.buttonDelegate,
                                 .OBJC_ASSOCIATION_RETAIN)
        return view
    }
}

// Small trampoline that lets the builder attach a closure to each
// back/forward/reload/settings button without needing every caller to
// subclass the item class.
private var ButtonForwarderKey: UInt8 = 0

private final class ButtonForwarder: NSObject, CCModeButtonToolbarItemDelegate {
    let kind: String
    let handler: ((String) -> Void)?
    init(kind: String, handler: ((String) -> Void)?) {
        self.kind = kind
        self.handler = handler
    }
    func toolbarButtonSelected(identifier: String) {
        handler?(kind)
    }
}
