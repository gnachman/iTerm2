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

    // Peer-group members for the mode switcher (identifier + label +
    // optional configured shortcut), and which one is currently
    // active. The mode switcher renders the shortcut next to each
    // segment's label; when nil it falls back to the built-in
    // ⌥⇧⌘<digit> binding. Empty for non-peer toolbars.
    let peerGroupMembers: [(identifier: String,
                            label: String,
                            shortcut: WorkgroupToolbarShortcut?)]

    let activePeerIdentifier: String

    // Delegate assigned to the bundled Navigation item (back /
    // forward / reload). The peer port and workgroup instance both
    // conform; demux via the item's `ownerPeerID` tag.
    weak var navigationDelegate: WorkgroupNavigationToolbarItemDelegate?

    // Delegate for the changedFileSelector pop-up. Separate from
    // peerPort so non-peer toolbars (split/tab hosts) can route file
    // picks to the workgroup instance even though they have no port.
    weak var diffSelectorDelegate: CCDiffSelectorItemDelegate?

    // Delegate for the gitBaseSelector combo box. Same separation
    // rationale as diffSelectorDelegate — non-peer toolbars route
    // through the workgroup instance, peer toolbars through the port.
    weak var gitBaseSelectorDelegate: CCGitBaseSelectorItemDelegate?

    // Display name of the session this toolbar is being built for —
    // shown by the auto-injected `.name` item. Empty for peer-group
    // hosts that don't surface a label here (the modeSwitcher already
    // shows the active peer's name in that case).
    let displayName: String

    // Delegate for the .codeReview auto-send-clippings toggle. The peer
    // port sets itself here; it flips the owning session's runtime flag
    // and performs the idle-driven send. Non-peer toolbars leave it nil
    // (the toggle is only meaningful on peer-group code-review sessions,
    // which is the only shape the preset and settings UI produce).
    weak var autoSendClippingsDelegate: WorkgroupAutoSendClippingsToolbarItemDelegate? = nil

    // Initial on/off state for a freshly-built auto-send-clippings toggle,
    // read from the owning session's runtime flag (defaults off). Lets a
    // toolbar rebuilt mid-session show the toggle's current state.
    var autoSendClippingsInitiallyOn = false
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
    // configured toolbar list. Skip it entirely when a `.modeSwitcher`
    // is present — the switcher already surfaces the active peer's
    // name, so a separate label would be redundant. Otherwise
    // prepend the label. The user can never remove or reorder this
    // — it is not stored in the persisted config and is added every
    // time the toolbar is built. Pre-existing `.name` entries
    // (defensive: shouldn't happen since the settings UI doesn't
    // expose .name) are dropped first to keep ordering deterministic.
    //
    // Also drops `.navigation` items when the same set has no
    // `.changedFileSelector` — back/forward step through the diff
    // list, so without one they're no-op buttons. Mirrors the add-
    // menu guard in iTermWorkgroupSessionDetailViewController so
    // legacy configs that still carry a stranded `.navigation`
    // don't render dead buttons.
    static func injectAutoItems(into items: [iTermWorkgroupToolbarItem]) -> [iTermWorkgroupToolbarItem] {
        let hasChangedFileSelector = items.contains(where: {
            if case .changedFileSelector = $0 { return true }
            return false
        })
        var stripped = items.filter {
            switch $0 {
            case .name: return false
            case .navigation: return hasChangedFileSelector
            case .gitBaseSelector: return hasChangedFileSelector
            default: return true
            }
        }
        let hasModeSwitcher = stripped.contains(where: {
            if case .modeSwitcher = $0 { return true }
            return false
        })
        if !hasModeSwitcher {
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
        case .navigation(let shortcuts):
            let view = WorkgroupNavigationToolbarItem(identifier: id,
                                                      priority: 3,
                                                      shortcuts: shortcuts)
            view.navigationDelegate = context.navigationDelegate
            view.ownerPeerID = ownerPeerID
            return view
        case .reload(let shortcut):
            let view = WorkgroupReloadToolbarItem(identifier: id,
                                                  priority: 3,
                                                  shortcut: shortcut)
            view.navigationDelegate = context.navigationDelegate
            view.ownerPeerID = ownerPeerID
            return view
        case .spacer(let minW, let maxW):
            return SessionToolbarSpacer(identifier: id,
                                        priority: 1,
                                        minWidth: minW,
                                        maxWidth: maxW)
        case .gitBaseSelector:
            let view = CCGitBaseSelectorItem(identifier: id,
                                             priority: 2)
            view.gitBaseSelectorDelegate = context.gitBaseSelectorDelegate
            view.ownerPeerID = ownerPeerID
            return view
        case .autoSendClippingsWhenIdle:
            let view = WorkgroupAutoSendClippingsToolbarItem(
                identifier: id,
                priority: 1,
                isOn: context.autoSendClippingsInitiallyOn)
            view.autoSendDelegate = context.autoSendClippingsDelegate
            view.ownerPeerID = ownerPeerID
            return view
        case .name:
            return makeNameLabel(context: context)
        }
    }

    // Auto-injected per-session display label. Plain text field so it
    // matches the visual weight of the git-status label; the layout
    // builder lets it claim its fitting width and shrinks if needed.
    // The 22pt minimum keeps the label from collapsing to a bare
    // ellipsis under heavy contention — a lone "…" tells the user
    // nothing.
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
                                   textField: textField,
                                   minWidth: 22)
    }

}
