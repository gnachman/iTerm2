//
//  iTermSplitTreeRebuilder.swift
//  iTerm2SharedARC
//
//  Builds NSSplitView/SessionView trees from arrangement dictionaries.
//  Originally lived as `+_recursiveRestoreSplitters:fromIdMap:sessionMap:
//  revivedSessions:` in PTYTab.m — extracted here to be the home for
//  tree-rebuild logic that subsequent phases will generalize for the
//  upcoming layout-application API.
//
//  The recursion is parameterized over a `LeafResolver` closure so the
//  same tree-build serves the existing tmux/maximize/arrangement-restore
//  callers and the upcoming layout-application API (which keys leaves by
//  session GUID instead of tmux pane number).
//
//  Behavior is intentionally identical to the original ObjC implementation
//  for the tmux/maximize/arrangement-restore call sites; characterization
//  tests in
//  ModernTests/iTermPTYTabRecursiveRestoreSplittersTests.swift act as a
//  regression safety net.
//

import AppKit

/// Resolves a leaf node arrangement to the SessionView that should
/// occupy that leaf in the rebuilt tree. The resolver is responsible for:
/// - Looking up an existing SessionView (from any map the caller maintains)
/// - Setting or restoring the SessionView's frame as appropriate
/// - Creating a fresh SessionView if no existing one matches
typealias iTermLeafResolver = (_ arrangement: [String: Any]) -> SessionView

/// A target layout for `iTermSplitTreeRebuilder.replaceViewHierarchy`.
/// Leaves identify a SessionView either by GUID (existing live session)
/// or by a pre-created SessionView (for sessions created by the
/// transaction coordinator before this call).
indirect enum LayoutTreeNode {
    case splitter(vertical: Bool, children: [LayoutTreeNode])
    case session(guid: String)
    case newSession(view: SessionView)
}

/// Errors thrown by the GUID-keyed replace entry. Validation in the
/// transaction coordinator should make these unreachable in practice;
/// they remain as a defensive backstop.
enum SplitTreeRebuilderError: Error {
    case maximizedTab
    case missingSession(guid: String)
    case emptyLayout
}

@objc(iTermSplitTreeRebuilder)
class iTermSplitTreeRebuilder: NSObject {

    /// Existing call sites entry point: tmux, maximize/unmaximize, and
    /// arrangement-restore all converge here. Internally constructs a
    /// leaf resolver that handles all three lookup styles.
    @objc(buildSplitterTreeForArrangement:idMap:sessionMap:revivedSessions:)
    static func buildSplitterTree(arrangement: [String: Any],
                                  idMap: [NSNumber: SessionView]?,
                                  sessionMap: [String: PTYSession]?,
                                  revivedSessions: NSMutableArray?) -> NSView {
        let resolver: iTermLeafResolver
        if idMap != nil || sessionMap != nil {
            resolver = { dict in
                Self.resolveLeafForLegacyCallers(arrangement: dict,
                                                 idMap: idMap,
                                                 sessionMap: sessionMap,
                                                 revivedSessions: revivedSessions)
            }
        } else {
            resolver = { dict in
                let frame = Self.frameFromDict(dict[TAB_ARRANGEMENT_SESSIONVIEW_FRAME])
                return SessionView(frame: frame)
            }
        }
        return buildSplitterTree(arrangement: arrangement, resolver: resolver)
    }

    /// Generic Swift entry point: parameterized over a leaf-resolver
    /// closure so the same recursion works for the existing tmux/
    /// maximize/arrangement-restore callers and for the upcoming
    /// layout-application API (which keys leaves by session GUID).
    static func buildSplitterTree(arrangement: [String: Any],
                                  resolver: iTermLeafResolver) -> NSView {
        let viewType = arrangement[TAB_ARRANGEMENT_VIEW_TYPE] as? String
        if viewType == VIEW_TYPE_SPLITTER {
            return buildSplitter(arrangement: arrangement, resolver: resolver)
        }
        return resolver(arrangement)
    }

    /// Generic Swift entry point: builds an NSSplitView/SessionView tree
    /// directly from a `LayoutTreeNode`, skipping the arrangement-dict
    /// representation. Used by the layout-application API.
    static func buildTree(layoutTree: LayoutTreeNode,
                          frame: NSRect,
                          idMap: [String: SessionView]) throws -> NSView {
        switch layoutTree {
        case .splitter(let vertical, let children):
            guard children.count >= 2 else {
                throw SplitTreeRebuilderError.emptyLayout
            }
            let splitter = PTYSplitView(frame: frame, uniqueIdentifier: UUID().uuidString)!
            if iTermSplitTreeRebuilder.useThinSplitters {
                splitter.dividerStyle = .thin
            }
            splitter.isVertical = vertical
            for child in children {
                let childView = try buildTree(layoutTree: child, frame: .zero, idMap: idMap)
                splitter.addSubview(childView)
            }
            return splitter
        case .session(let guid):
            guard let view = idMap[guid] else {
                throw SplitTreeRebuilderError.missingSession(guid: guid)
            }
            return view
        case .newSession(let view):
            return view
        }
    }

    /// Replaces a tab's view hierarchy with a new tree built from
    /// `layoutTree`. Sessions referenced by GUID are recycled from
    /// `idMap`; sessions in `keepAlive` are not terminated even if
    /// absent from the new tree (cross-tab move case). The caller is
    /// responsible for unmaximizing the tab beforehand and for managing
    /// `lockedSession`/`activeSession` re-targeting outside this method.
    ///
    /// On entry, sessions in `keepAlive` may still be parented in this
    /// tab's old tree or already detached — both are acceptable. On
    /// return, the tab's root is the freshly built tree, sized via
    /// `arrangeSplitPanesEvenlyInSplitView:`, and any sessions of this
    /// tab not in `keepAlive` and not referenced by the new tree have
    /// been terminated.
    @discardableResult
    static func replaceViewHierarchy(in tab: PTYTab,
                                     layoutTree: LayoutTreeNode,
                                     idMap: [String: SessionView],
                                     keepAlive: Set<String>,
                                     sessionsToAdopt: [String: PTYSession] = [:]) throws -> NSSplitView {
        if tab.isMaximized {
            throw SplitTreeRebuilderError.maximizedTab
        }

        let outerFrame = tab.realRootView.bounds
        let newRoot: NSSplitView
        let builtView = try buildTree(layoutTree: layoutTree, frame: outerFrame, idMap: idMap)
        if let asSplitView = builtView as? NSSplitView {
            newRoot = asSplitView
        } else {
            // A single-leaf layout still needs a wrapping splitter so the
            // tab always has an NSSplitView root.
            let wrapper = PTYSplitView(frame: outerFrame, uniqueIdentifier: UUID().uuidString)!
            if iTermSplitTreeRebuilder.useThinSplitters {
                wrapper.dividerStyle = .thin
            }
            wrapper.isVertical = true
            wrapper.addSubview(builtView)
            newRoot = wrapper
        }

        // Note on termination: sessions that were in this tab's old
        // tree but are NOT in the new tree are NOT terminated here.
        // The resolver's orphan check guarantees they are accounted
        // for in `close_sessions` / `close_tabs`, and the transaction
        // coordinator's close phase will terminate them after the
        // attach phase finishes. Terminating here would race with the
        // explicit close (double-termination → unknownSession).
        let referencedGuids = collectReferencedGuids(layoutTree)

        // Clear lockedSession if it points to a session that's no longer
        // in this tab and not being preserved elsewhere.
        if let locked = tab.lockedSession {
            let lockedGuid = locked.guid
            if !referencedGuids.contains(lockedGuid) && !keepAlive.contains(lockedGuid) {
                tab.lockedSession = nil
            }
        }

        tab.setRoot(newRoot)

        // Adopt cross-tab-moved sessions BEFORE numberOfSessionsDidChange
        // and active-session promotion: those steps consult
        // viewToSessionMap via PTYTab.sessions, and adopted sessions
        // wouldn't be visible until we register them here.
        for (_, session) in sessionsToAdopt {
            tab.adoptSession(session)
        }

        tab.fitSubviewsToRoot()
        tab.arrangeSplitPanesEvenly(in: newRoot)
        tab.numberOfSessionsDidChange()

        // Promote a sensible active session: keep the existing active if
        // it survived, otherwise pick the first session in the new tree.
        let surviving = tab.sessions() ?? []
        if let active = tab.activeSession, surviving.contains(where: { $0 === active }) {
            // Active session survived; nothing to do.
        } else if let first = surviving.first {
            tab.activeSession = first
        }

        return newRoot
    }

    private static func collectReferencedGuids(_ node: LayoutTreeNode) -> Set<String> {
        var result: Set<String> = []
        collectReferencedGuids(node, into: &result)
        return result
    }

    private static func collectReferencedGuids(_ node: LayoutTreeNode, into set: inout Set<String>) {
        switch node {
        case .splitter(_, let children):
            for child in children {
                collectReferencedGuids(child, into: &set)
            }
        case .session(let guid):
            set.insert(guid)
        case .newSession:
            break
        }
    }

    private static func buildSplitter(arrangement: [String: Any],
                                      resolver: iTermLeafResolver) -> NSSplitView {
        let frame = frameFromDict(arrangement[TAB_ARRANGEMENT_SPLITTER_FRAME])
        let identifier = (arrangement[TAB_ARRANGEMENT_SPLITTER_ID] as? String) ?? UUID().uuidString
        let splitter = PTYSplitView(frame: frame, uniqueIdentifier: identifier)!
        if iTermSplitTreeRebuilder.useThinSplitters {
            splitter.dividerStyle = .thin
        }
        let isVertical = (arrangement[SPLITTER_IS_VERTICAL] as? NSNumber)?.boolValue ?? false
        splitter.isVertical = isVertical

        let subviews = arrangement[SUBVIEWS] as? [[String: Any]] ?? []
        for subArrangement in subviews {
            let subView = buildSplitterTree(arrangement: subArrangement, resolver: resolver)
            splitter.addSubview(subView)
        }
        return splitter
    }

    /// Replicates the leaf-handling logic of the original
    /// `+_recursiveRestoreSplitters:fromIdMap:sessionMap:revivedSessions:`
    /// for the tmux / maximize-restore / arrangement-restore call sites.
    private static func resolveLeafForLegacyCallers(arrangement: [String: Any],
                                                    idMap: [NSNumber: SessionView]?,
                                                    sessionMap: [String: PTYSession]?,
                                                    revivedSessions: NSMutableArray?) -> SessionView {
        let frame = frameFromDict(arrangement[TAB_ARRANGEMENT_SESSIONVIEW_FRAME])

        // Maximize/unmaximize path: an arrangement-ID match preserves the
        // SessionView's restored frame size (does not overwrite from the
        // arrangement frame).
        if let arrId = arrangement[TAB_ARRANGEMENT_ID] as? NSNumber,
           let recycled = idMap?[arrId] {
            recycled.restoreFrameSize()
            return recycled
        }

        var sessionView: SessionView? = nil
        if let paneNumber = arrangement[TAB_ARRANGEMENT_TMUX_WINDOW_PANE] as? NSNumber,
           let recycled = idMap?[paneNumber] {
            sessionView = recycled
        } else if let sessionDict = arrangement[TAB_ARRANGEMENT_SESSION] as? [AnyHashable: Any],
                  let uniqueId = PTYSession.guid(inArrangement: sessionDict),
                  let session = sessionMap?[uniqueId] {
            revivedSessions?.add(session)
            sessionView = session.view
        }

        if let sessionView = sessionView {
            sessionView.frame = frame
            return sessionView
        }
        return SessionView(frame: frame)
    }

    private static let useThinSplitters = true

    static func frameFromDict(_ value: Any?) -> NSRect {
        guard let dict = value as? [String: Any] else {
            return .zero
        }
        let x = (dict[TAB_X] as? NSNumber)?.doubleValue ?? 0
        let y = (dict[TAB_Y] as? NSNumber)?.doubleValue ?? 0
        let w = (dict[TAB_WIDTH] as? NSNumber)?.doubleValue ?? 0
        let h = (dict[TAB_HEIGHT] as? NSNumber)?.doubleValue ?? 0
        return NSRect(x: x, y: y, width: w, height: h)
    }
}
