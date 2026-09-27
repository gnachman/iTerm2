# Floating Panes: Design

Status: Draft for review
Scope: Native first, tmux deferred
Primary files: PTYTab, SessionView, PTYSession, PseudoTerminal

A floating pane is a terminal session that sits above the normal tiled
layout: freely positioned, resizable, z-ordered, and able to overlap its
neighbors (even to hang partly off the tab). Today every pane is a leaf of one
strictly tiled `NSSplitView` tree. Adding floats is feasible, but it is one of
the largest structural changes short of rewriting the view layer, because a
single assumption is wired into dozens of call sites.

This doc describes what a native implementation would take, grounded in a
survey of PTYTab, SessionView, PTYSession, PseudoTerminal, the API layer, and
the tmux upstream threads. The tmux integration is deliberately out of scope
for v1 and is covered in the appendix.

## 0. Summary

The one assumption we are breaking:

> A tab's sessions are exactly the leaves of the split tree rooted at
> `PTYTab.root_`, and those leaves tile the tab with no overlap, no gaps, and
> no z-order.

Everything below is a consequence of relaxing that.

There is exactly one unknown that should be settled before any real design
work: **how a floating pane renders over a Metal-backed pane.** That answer
forks the whole architecture (see section 3). The rest is mostly assembly,
because iTerm2 already owns most of the parts: a mechanism that reparents a
live `SessionView` without killing its PTY, a drag-and-drop system that
reparents sessions across windows, a movable and resizable overlay with
chrome, and a rounded-border view.

## 1. Where we are today

A tab's view tree is `NSTabViewItem.view`, then an optional `flexibleView_`
(tmux only), then `root_` (a `PTYSplitView`), then nested split views, then
`SessionView` leaves. Sessions are enumerated by walking that tree:
`_recursiveSessions:atNode:` (PTYTab.m:1641) and `_recursiveSessionViews:`
(PTYTab.m:1665). The split view owns every frame; children partition their
parent's rectangle with only divider gaps between them.

```
  Today (exact tiling)            With a float (overlap + z-order)
  +----------+----------+         +----------+----------+
  |    A     |    B     |         |    A     |    B     |
  |          |          |         |     +---------+     |
  +----------+----------+         +-----|  float  |-----+
  |         C          |          |     +---------+     |
  |                    |          |         C           |
  +--------------------+          +---------------------+
```

Three invariants enforce the tiling, and floats violate all three:

- **Tree normal form** (`checkInvariants:` PTYTab.m:1981): non-root splits
  have two or more children, orientation alternates by depth, and a single
  root child must be a `SessionView`. `cleanupAfterRemove:` (PTYTab.m:2008)
  actively rewrites the tree to preserve this.
- **Exact partition** (`resizeSubviewsOfSplitView:` PTYTab.m:6413,
  `_recursiveSize:` PTYTab.m:2542, `setSize:` PTYTab.m:2725): frames are
  derived, never arbitrary; children fill the parent with no overlap.
- **Geometry-derived ordering** (`orderedSessions` PTYTab.m:1044, the neighbor
  engine PTYTab.m:1446-1600): reading order and directional navigation assume
  non-overlapping rectangles and have no concept of a stacking order.

## 2. What floating breaks

- **Enumeration.** `-sessions` and `-sessionViews` only see the tree. A float
  that is not in the tree is invisible to broadcast, close-all, arrangements,
  and the API. Fortunately these accessors already fork on the maximize stash
  (`idMap_`), which is the natural hook for a second population.
- **Sizing.** A pane's grid is derived from a tab-imposed frame. A float
  inverts this: the user picks a frame and the grid follows (see section 5).
- **Focus and hit-testing.** Activation assumes one `SessionView` covers any
  given point (`textViewDidBecomeFirstResponder` PTYSession.m:13226,
  focus-follows-mouse PTYSession.m:19946). Overlap needs topmost-wins
  resolution.
- **Navigation.** Directional select and swap (PTYTab.m:1446-1600) reason
  about tiled adjacency with an activity-counter tiebreak; overlap has no
  defined neighbor and no z-tiebreak.
- **Serialization.** Arrangements, restorable state, and the Python or gRPC
  API all encode a strict splitter-or-session binary tree with no slot for a
  third kind of node (see section 8).
- **tmux.** The layout grammar cannot represent a float; tmux tabs must
  exclude or forbid floats until the upstream format lands (see appendix).

## 3. The decision that gates everything

**How does a float render over a Metal pane?**

Two live Metal panes never overlap today. Splits tile, and maximize
deliberately forces every non-active pane to the legacy renderer
(PTYTab.m:7138). So "a live Metal terminal composited over another live Metal
terminal" is completely unexercised. The scary comments in the code
(PTYTab.m:7158, PTYSession.m:9092) are about `NSView`s parented inside the
alpha-hidden `PTYTextView`, not about Metal layers failing to z-compose. Every
piece of pane chrome already draws correctly above the `CAMetalLayer`, which is
encouraging but not proof for the overlapping-opaque-Metal case. The
deployment floor is macOS 12, so we can rely on modern layer behavior.

### Option A: in-window view overlay

A float is a real `SessionView` promoted out of the split tree into a floating
layer above `root_`.

- (+) One coordinate space; reuses SessionView's existing z-order compositor
  (`addSubviewBelowFindView:` SessionView.m:1095).
- (+) Clipped naturally to the tab content.
- (-) We own the Metal-over-Metal question directly.
- (-) Cannot float above the tab bar or toolbelt (tab content is below them in
  z-order).

### Option B: child NSWindow per float

Each float is a borderless child window hosting a full `SessionView`, tracking
the parent.

- (+) Each float gets its own opaque surface: Metal, z-order, free
  positioning, and shadows just work.
- (+) Precedent exists (hotkey window `iTermProfileHotKey.m:284`, session
  preview, mention picker).
- (-) Real window bookkeeping: reposition on parent move, resize, and space
  change; fullscreen; key-window handoff; clipping to the tab.

### Recommendation

Prototype Option A's Metal question first as a throwaway spike: put one opaque
Metal `SessionView` over another and confirm it composites and stays live. If
clean, Option A is the more natural fit and keeps everything in one coordinate
space. If shaky, fall back to Option B, which sidesteps rendering at the cost
of window management. Do not design the rest until this is answered; it changes
the container model, hit-testing, and whether float geometry is tab-relative or
window-relative.

## 4. Data model

`PTYTab` gains a `floatingPanes` collection whose members live outside
`root_`. Each entry carries the session and its `SessionView`, a frame
(tab-relative or window-relative per section 3), and a z-index. The precedent
is already there: `-sessions` and `-sessionViews` fork on `idMap_` (the
maximize stash), so folding a floating collection into those same accessors
makes most enumerators pick floats up for free.

The tiling walks must learn to exempt floats: `checkInvariants:`,
`cleanupAfterRemove:`, `resizeSubviewsOfSplitView:`, `_recursiveSize:`, the
split-view constrain callbacks (PTYTab.m:6204 and 6224), and the split-gating
counts (`hasMultipleSessions`, `canSplitVertically:`).

Design hedge, downgraded: an earlier idea was to let a float host a whole
layout subtree (not just one pane). The tmux v2 format allows the floating flag
only on a leaf pane, never a container, so tmux floats are always single panes.
Keep the native float model to a single `SessionView` to match tmux. Native
split-inside-float can be added later as an iTerm-only differentiator without
fighting the tmux model.

## 5. The sizing inversion

For tiled panes geometry flows tab to session: the split view dictates a
`SessionView` frame and `PTYSession` derives rows and columns from it
(PTYSession.m:2619-2633, `setSize:` PTYSession.m:2719). A `PTYSession` stores
only rows and columns; it never owns an origin or frame. A float inverts this:
the user picks a frame and the grid follows, so the float owns its geometry.
This is why the arrangement schema, which today persists only `COLUMNS` and
`ROWS` (PTYSession.m:6932), needs new per-float geometry.

## 6. Interaction model

The stacking order is explicit: a float carries a z-index, front-most first,
and floats always sit above the tiled base.

```
  z 0 (front)  [ float: editor ]
  z 1          [ float: logs   ]
  bottom       [ tiled base (the split tree) ]
```

- **Move and resize.** Reuse the minimal composer's event loop: a working
  `trackEventsMatchingMask:` drag-to-move plus drag-handle resize with rounded
  chrome (`iTermMinimalComposerViewController.m:72-123`).
- **Grab handle.** `SessionTitleView` already turns a title-bar drag into "move
  this pane" (`SessionTitleView.m:382`); extend from drag-out-to-window to
  drag-within-tab.
- **Create and convert.** Reuse `MovePaneController`, which already reparents a
  live session and lights up drop targets across windows; add a "float here"
  target and a float-to-tile and tile-to-float conversion.
- **Border and shadow.** Reuse `iTermActivePaneBorderView` (rounded per-corner
  border) and the shadow pattern from `ContentNavigationShortcut.swift:85`.

## 7. Focus, hit-testing, activation

Click-to-activate works with default AppKit hit-testing if the front-most float
is the topmost subview, since `SessionView` does not override `hitTest:`.
Focus-follows-mouse and "which session is under the mouse" become
z-order-dependent rather than a partition of the plane, so `setActiveSession:`
and the FFM path must respect stacking. Directional navigation (section 1)
needs an explicit policy: either exclude floats and give them a dedicated
cycle, or extend the neighbor engine with a z-tiebreak. Recommendation: exclude
floats from directional tiled navigation in v1 and add a separate "cycle
floating panes" action.

## 8. Serialization and automation

Arrangements, restorable state, and the API all encode a strict
splitter-or-session binary tree. Both the Swift rebuilder and the vendored
Python client treat "not a session" as "must be a nested node" (session.py:56,
iTermSplitTreeRebuilder.swift). That makes the safe path unambiguous.

**The additive-sibling rule:** add floats as an additive sibling field or key
carried alongside the tree, never as a new node type inside it. A new node type
would be missed by every recursive walker or, worse, silently mistaken for a
session, corrupting older readers and old Python clients.

| Surface | Today | Add |
| --- | --- | --- |
| Arrangement dict (PTYTab.m:78-103) | `Root` / `Subviews` / `View Type` tree | Top-level `"Floating Panes"` key, like the existing `"Maximized"` key |
| Restorable state (StateRestoration/) | Reuses the arrangement encoder | Inherits the new key for free; give floats stable IDs so the delta encoder does not churn |
| API proto (proto/api.proto) | `SplitTreeNode`; `Tab.root` | `repeated FloatingPane` on `Tab`, parallel to `minimized_sessions`. Never a new `oneof` case |
| Python client | `Splitter` / `Session` | `Tab.floating_panes` accessor; keep the old `from_node` else-branch safe |
| Notifications | Resends `ListSessionsResponse` | Ensure float create, move, resize, and close fire the observers at iTermAPIHelper.m:680-721 |

Old builds reading a new arrangement ignore an unknown top-level key, so floats
degrade gracefully (they vanish) rather than crashing. Regenerate
`Api.pbobjc.*` and `api_pb2.py` after any proto change.

## 9. Cross-cutting edge cases

- **Maximize.** Define the interaction: floats stay on top, hide, or maximize
  is disabled while floats exist. Needs a product call (section 11).
- **Whole-window background image.** `textViewRelativeFrame`
  (PTYSession.m:12848) assumes each pane owns a distinct non-overlapping slice;
  overlapping floats sample overlapping regions and need handling.
- **Tab thumbnail.** `_recursiveDrawSplit:` (PTYTab.m:2749) composites the
  tree; it must also draw floats in z-order.
- **Broadcast input.** Iterates by GUID, so floats are included automatically;
  only the broadcast-border drawing assumes tiled views.
- **Accessibility.** Essentially free: AppKit derives the a11y tree from the
  live view hierarchy. Consider setting `accessibilityChildren` order for
  predictable VoiceOver traversal of stacked panes.

## 10. Components to reuse

| Need | Reuse | What it lacks |
| --- | --- | --- |
| Live-view reparenting, save and restore state | Maximize stash (PTYTab.m:5509 / 5596, `idMap_`) | The visual half: nothing floats or z-orders. Reuse state, not the root swap |
| Move and resize loop with chrome | Minimal composer (iTermMinimalComposerViewController.m:72) | Hosts a text control, not a live session; only vertical drag |
| Drag out, drop to reparent live session | MovePaneController.m:313 | No "float within same tab" destination |
| Grab handle | SessionTitleView.m:382 | Means "extract to window" today; extend to reposition |
| Rounded border and shadow | iTermActivePaneBorderView, ContentNavigationShortcut.swift:85 | Nothing; drop-in |
| Float above the whole window | Hotkey window (iTermProfileHotKey.m:284) | Window bookkeeping (Option B only) |
| Metal visibility handshake | iTermMetalDisabling, `metalAllowed:` (PTYSession.m:9007) | Must extend for overlap regardless of A or B |

## 11. Blast radius

Highest-risk surfaces, most to least.

| Area | Anchor | Risk |
| --- | --- | --- |
| Neighbor and reading-order engine | PTYTab.m:1044-1600 | High |
| Tree walkers that define "the tab's sessions" | PTYTab.m:1641 / 1665 | High |
| Tiling, resize, and invariants | PTYTab.m:1981, 2542, 6413 | High |
| Metal over Metal (Option A) | PTYTab.m:7138, SessionView Metal path | High |
| Serialization: arrangement, proto, python | section 8 | Medium |
| Drag and drop, split-selection | MovePaneController.m, SessionView | Medium |
| Sizing inversion | PTYSession.m:2619-2633 | Medium |
| Background image, thumbnail, broadcast | section 9 | Low |
| tmux (excluded in v1) | sources/tmux/ | Low |
| Accessibility | view hierarchy derived | Low |

## 12. Phased plan

Small, reviewable commits, each with tests.

0. **Spike (throwaway).** Answer the Metal-over-Metal question. Decide Option A
   vs B. This gates everything else.
1. **Data model.** Add the `floatingPanes` collection, fork the enumeration
   accessors, exempt floats from the tiling and invariant walks. Get one static
   float on screen. Prove enumeration, close, and terminate lifecycle.
2. **Interaction.** Drag-to-move, edge resize, raise and lower z-order, create,
   and float-tile conversion. Reuse MovePaneController and SessionTitleView.
3. **Sizing and focus.** Float owns its frame; grid derives from it. Correct
   hit-testing and focus-follows-mouse for overlap.
4. **Persistence.** Arrangement key and restorable state, with round-trip tests
   and graceful degradation on old builds.
5. **Automation.** Proto field, handlers, Python client, and notifications.
6. **Edge cases.** Directional-nav policy, maximize interaction,
   background-image slicing, tab thumbnail, broadcast borders.
7. **tmux bolt-on.** Deferred until the upstream format lands (appendix).

## 13. Open decisions

Product calls needed before detailed design.

- **Scope of a float:** clipped to the tab content, or free to float over the
  tab bar, toolbelt, and title. This drives Option A vs B and the container
  model.
- **Navigation:** do directional pane navigation and "select pane N" include
  floats, or are floats reachable only via a dedicated cycle?
- **Maximize interaction:** when a tiled pane is maximized, do floats stay on
  top, hide, or is maximize disabled while floats exist?

## Appendix: tmux integration

Deferred. The upstream contract is still wet cement.

tmux is adding floating panes too, but the piece iTerm2 depends on, the
control-mode serialization, is the least settled. Current state (checked
against the tmux repo):

- **Core floats shipped in 3.7** (latest 3.7c), but minimal: mouse-only move
  and resize.
- **Full interaction landed on master, targeting 3.8** (unreleased):
  move-pane, resize-pane, split-in-float, break-pane and join-pane for convert,
  swap, modal panes.
- **The v2 wire format is not on master.** It lives on the
  `layout-custom-format` branch and has been redesigned to JSON, a change from
  the earlier compact grammar. It is behind an opt-in control-mode flag
  (`CLIENT_CONTROL_NEWLAYOUTS`). Until a client opts in, tmux emits the legacy
  format and renders floats as ordinary tiled panes, so old iTerm2 does not
  crash.
- **display-popup becomes a floating pane in 3.9** (branch `no_more_overlays`).

Watch item: revisit the tmux side only when the v2 format merges to master or
ships in 3.8. At that point read the authoritative format doc in the header of
`layout-custom.c` and the real flag name from shipped source, rather than
trusting branch comments. A tmux float maps to a single-pane native float.
