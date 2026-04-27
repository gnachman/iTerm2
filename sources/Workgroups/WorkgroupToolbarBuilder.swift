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

    // Delegate assigned to every back/forward/reload/settings button
    // the builder produces. The peer port (or workgroup instance, for
    // non-peer toolbars) conforms to CCModeButtonToolbarItemDelegate
    // and demuxes using the item's `identifier` (which the builder
    // sets to the kind's rawValue) plus its `ownerPeerID` tag.
    weak var buttonDelegate: CCModeButtonToolbarItemDelegate?

    // Delegate for the changedFileSelector pop-up. Separate from
    // peerPort so non-peer toolbars (split/tab hosts) can route file
    // picks to the workgroup instance even though they have no port.
    weak var diffSelectorDelegate: CCDiffSelectorItemDelegate?

    // Display name of the session this toolbar is being built for —
    // shown by the auto-injected `.name` item. Empty for peer-group
    // hosts that don't surface a label here (the modeSwitcher already
    // shows the active peer's name in that case).
    let displayName: String
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
    // Inject the auto-managed `.name` item into a session's
    // configured toolbar list. Slot it in immediately after the first
    // `.modeSwitcher`; if no switcher is present, prepend it. The
    // user can never remove or reorder this — it is not stored in
    // the persisted config and is added every time the toolbar is
    // built. Pre-existing `.name` entries (defensive: shouldn't
    // happen since the settings UI doesn't expose .name) are
    // dropped first to keep ordering deterministic.
    static func injectAutoItems(into items: [iTermWorkgroupToolbarItem]) -> [iTermWorkgroupToolbarItem] {
        var stripped = items.filter {
            if case .name = $0 { return false }
            return true
        }
        if let switcherIndex = stripped.firstIndex(where: {
            if case .modeSwitcher = $0 { return true }
            return false
        }) {
            stripped.insert(.name, at: switcherIndex + 1)
        } else {
            stripped.insert(.name, at: 0)
        }
        return stripped
    }

    // Build the union of items across every session in `sessions`,
    // deduping repeats (e.g. multiple peers that each declare a
    // mode-switcher get one shared instance). Returned order follows
    // first-appearance order across the inputs. Items that need the
    // git poller but whose context has no poller are dropped.
    static func buildUnion(fromSessions sessions: [iTermWorkgroupSessionConfig],
                           context: WorkgroupToolbarContext) -> [(item: iTermWorkgroupToolbarItem, view: SessionToolbarGenericView)] {
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
    // provided). `ownerPeerID` tags the item with the peer it was
    // built for so per-peer delegate callbacks (button taps, file
    // picks) know which peer fired them; pass nil for non-peer
    // toolbars (split/tab hosts that don't participate in a peer
    // group at this level).
    static func build(item: iTermWorkgroupToolbarItem,
                      context: WorkgroupToolbarContext,
                      ownerPeerID: String? = nil) -> SessionToolbarGenericView? {
        let id = item.kind.rawValue
        switch item {
        case .gitStatus:
            guard let poller = context.gitPoller else { return nil }
            return CCGitSessionToolbarItem(identifier: id,
                                           priority: 2,
                                           scope: context.scope,
                                           poller: poller)
        case .changedFileSelector:
            guard let poller = context.gitPoller else { return nil }
            let view = CCDiffSelectorItem(identifier: id,
                                          priority: 2,
                                          poller: poller)
            view.diffSelectorDelegate = context.diffSelectorDelegate
            view.ownerPeerID = ownerPeerID
            return view
        case .modeSwitcher:
            let view = WorkgroupModeSwitcherItem(
                identifier: id,
                priority: 1,
                members: context.peerGroupMembers,
                activeIdentifier: context.activePeerIdentifier)
            view.modeSwitchDelegate = context.peerPort
            return view
        case .back:
            return makeButton(kind: .back, symbol: .chevronLeft, context: context, ownerPeerID: ownerPeerID)
        case .forward:
            return makeButton(kind: .forward, symbol: .chevronRight, context: context, ownerPeerID: ownerPeerID)
        case .reload:
            return makeButton(kind: .reload, symbol: .arrowClockwise, context: context, ownerPeerID: ownerPeerID)
        case .spacer(let minW, let maxW):
            return SessionToolbarSpacer(identifier: id,
                                        priority: 1,
                                        minWidth: minW,
                                        maxWidth: maxW)
        case .name:
            return makeNameLabel(context: context)
        }
    }

    // Auto-injected per-session display label. Plain text field so it
    // matches the visual weight of the git-status label; the layout
    // builder lets it claim its fitting width and shrinks if needed.
    private static func makeNameLabel(context: WorkgroupToolbarContext) -> SessionToolbarGenericView {
        let textField = NSTextField(labelWithString: context.displayName)
        textField.drawsBackground = false
        textField.isBordered = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.lineBreakMode = .byTruncatingTail
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return SessionToolbarLabel(identifier: iTermWorkgroupToolbarItemKind.name.rawValue,
                                   priority: 2,
                                   textField: textField)
    }

    private static func makeButton(kind: iTermWorkgroupToolbarItemKind,
                                   symbol: SFSymbol,
                                   context: WorkgroupToolbarContext,
                                   ownerPeerID: String?) -> SessionToolbarGenericView? {
        let image = NSImage(systemSymbolName: symbol.rawValue,
                            accessibilityDescription: nil) ?? NSImage()
        let view = CCModeButtonToolbarItem(identifier: kind.rawValue,
                                           priority: 3,
                                           image: image)
        view.buttonDelegate = context.buttonDelegate
        view.ownerPeerID = ownerPeerID
        return view
    }
}
