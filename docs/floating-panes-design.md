# Floating Panes: Design

Scope: Native sessions first. tmux integration is a second driver on the same model.
Primary files: PTYTab, SessionView, PTYSession, PseudoTerminal, MovePaneController, sources/tmux/

A floating pane is a terminal session that sits above a tab's tiled layout. It
is freely positioned, resizable, z-ordered, and overlaps the panes beneath it.
Floats are expected to be short-lived helpers, since they block the view of the
tiled panes, but they are full sessions and must survive an app relaunch.

This doc records the model, the product decisions made so far, the open
questions, and an inventory of existing features that need work. It is based on
a read-only audit of the code at commit dd65a6b9d and of the tmux source in
`~/git/tmux` (which reports version `next-3.9` and contains the 3.8 changes).
Nothing described here has been built or run. Line numbers are from that
commit and will drift; method names are the stable reference. Claims about
AppKit or tmux runtime behavior that were inferred from code are marked
"unverified".

## 0. Summary

The assumption being broken:

> A tab's sessions are exactly the leaves of the split tree rooted at
> `PTYTab.root_`, and those leaves tile the tab with no overlap, no gaps, and
> no z-order.

The main conclusions:

- Build native floats first. tmux 3.8 floats then map onto the same model with
  the server, rather than the user, owning geometry.
- Every tab, native or tmux, gets a container view above `root_`. Floats are
  siblings of `root_` in that container (section 3.5).
- Each float is a wrapper view that holds the outline, shadow and resize
  handles, with a one-child `PTYSplitView` inside it. The split view keeps the
  many `(NSSplitView *)view.superview` casts in PTYTab valid. Users cannot
  split a float.
- A float's invariant is its grid (columns by rows), not its pixel frame.
- A native tab always has at least one tiled session. A tmux tab may have
  none (section 12.5).
- The whole feature is released together. The phases in section 13 order the
  work; they are not separate releases.
- Floats are in-window views. A live Metal pane is expected to composite
  correctly over another; a spike confirms it (section 4).
- Two tmux fixes are independent of this feature and should ship first
  (section 12.2).

## 1. Decisions made

**Scope and release**

| Topic | Decision |
| --- | --- |
| Name | “Floating pane”. Reusing the adjective from “floating hotkey window” is fine. |
| Order of work | Native first, tmux second. The feature is not worth doing for tmux alone. |
| Release | Everything ships together. No intermediate state reaches users. |
| Refactor safety | During the container refactor `-[PTYTab sessions]` is renamed so that every caller must choose between all sessions and tiled sessions at compile time. It is renamed back afterward. |

**Model**

| Topic | Decision |
| --- | --- |
| Container | Floats are in-window views. Two Metal panes are assumed to composite correctly. If they do not, Metal is turned off for floats. |
| Metal pane cap | Floats count toward the six-session limit above which a tab stops using Metal. The limit is there for performance. |
| Older builds | Saved arrangements need not stay readable by older builds. Downgrading is not supported. |
| Splits inside a float | Not supported natively. Split commands are disabled when a native float is active. The container and schema leave room to add them later. |
| Split aimed at a float | A split that reaches a native float from a caller that cannot be disabled goes to the tab's most recently active tiled pane instead. |
| Tiled to float conversion | No direct command. “New float” and “dock to tiled” cover it, and swapping a tiled pane with a float exchanges their roles. |
| Swap | A tiled pane can be swapped with a float, and two floats can be swapped. Each takes the other's place, frame and z-order. |
| Session order | Tiled sessions come first and floats after, wherever sessions are numbered or indexed. |
| Last tiled pane leaves | Native tabs only. If the last tiled pane leaves the tab by any route (its session ends, it is docked into another tab, dragged to the tab bar or to empty space, moved with a Move Session item, or buried), the front float is promoted to be the tab's tiled pane. In a tmux tab nothing is promoted and the tab becomes floats-only, as tmux does. Other floats stay floating. Closing the float implicitly is not an option, since it may be doing something important. Promotion resizes the float's grid to fill the tab. |
| Undo after promotion | If closing the last tiled pane promotes a float and the close is then undone, the pane returns as a new tab. Not worth special handling. |

**Creation, size and position**

| Topic | Decision |
| --- | --- |
| Creation | The menu item “New Floating Pane with Current Profile” comes first. The other creation points (section 6.1) follow in step 9 of the plan. |
| Initial position | A new float is centered in the tab. |
| Initial size | 80% of the tab's size in each dimension. To be revisited after feedback; a setting may follow. |
| Minimum float size | 2x2 cells plus a fixed size in points for the chrome. It exists only to prevent disaster, not to guarantee a usable float. |
| Tab minimum size | Floats contribute to the tab's minimum size. Each contributes its minimum grid at its own font plus its chrome, not its current grid. A float with a larger font than the tiled panes can be what constrains it. |
| Maximize | Natively, floats stay visible over a maximized pane. Maximize never hides a float, so the hide toggle is the only way a float is hidden. tmux tabs follow the server (section 12.4). |
| Keyboard resize and move | The existing menu items that resize a split pane apply to a float. New menu items move a float. |
| Window escape sequences | From a native float, CSI t treats the pane as the window: resize and raise or lower act on the float, reports describe the float, and move and miniaturize are ignored (section 6.9). |

**Appearance**

| Topic | Decision |
| --- | --- |
| Chrome | A float always has a title bar, a one-point outline and a shadow. Its corners are square. |
| Translucent floats | A float whose session is translucent gets an `NSVisualEffectView` underlay with within-window blending, so it shows a blurred version of what is beneath it and stays legible. It does not show the desktop. |
| Shared background image | A float draws its slice of the shared image like any pane. The chrome separates it from the layout. |
| Dimming | Floats are dimmed like any split pane. With “dim inactive split panes” on, an inactive float is dimmed, and focusing a float dims the other panes in the tab. |
| Accessibility | VoiceOver reads tiled panes first and floats after, matching session order. Covered panes are still announced, since their sessions are running. |
| Covered cursor | A float may cover the active tiled pane's cursor. The user can hide the floats. |

**Focus and z-order**

| Topic | Decision |
| --- | --- |
| Raising | Only a click, “Bring to Front”, creating a float, and reveal change z-order. Focus follows mouse changes focus without restacking. Keyboard navigation changes focus without raising. |

**Hide and show**

| Topic | Decision |
| --- | --- |
| Hide and show | There is a toggle that hides all floats in a tab while their sessions keep running. |
| Focus when floats are hidden | If the active session is a float when floats are hidden, focus goes to the next most recently used session in the tab that is still visible. |
| Navigation to hidden floats | Next Pane, Previous Pane and cmd-opt-N can land on a hidden float. Focus entering a float unhides the floats. |
| Broadcast input to hidden floats | Same policy as a maximized tab, whose hidden panes still receive broadcast input today. Hidden floats receive it. |
| Hidden floats indicator | Hidden floats are shown with the existing indicators feature (`iTermIndicatorsHelper`), like the maximized-pane indicator. |
| Hidden float activity | The hidden-floats indicator is decorated the way a tab's icon is, with the dead, bell, new-output and idle states of the hidden floats. Nothing unhides. |
| Hidden float ends | A hidden float whose session ends follows its profile. With close on end it disappears without unhiding anything. |

**Docking and dragging**

| Topic | Decision |
| --- | --- |
| Dock | A float can be docked into the tiled layout by menu item or by drag. |
| Dock gesture | Dragging a float over a tab keeps it floating by default. Holding Control shows the split halves for docking. Control is not used by any existing drag-start gesture. |
| Float to an existing tab | The tab bar gains spring-loaded tab selection when a pane drag hovers over a tab. |

**Lifecycle**

| Topic | Decision |
| --- | --- |
| Session end | A float follows its profile's end-of-session setting, like any pane. |
| Relaunch | Floats come back as floats. Upgrading with Sparkle must not lose state, including running sessions in floats. |
| Duplicate Tab | High fidelity: floats are duplicated with their geometry and z-order. |

**tmux**

| Topic | Decision |
| --- | --- |
| tmux idioms | In tmux tabs, follow tmux's behavior where it differs from native, for example Split on a float creates another float. |
| tmux float position | A tmux float is positioned so its top-left cell lines up with the matching cell of the tiled pane it overlaps. |
| tmux float chrome | Chrome goes in the one-cell border tmux reserves around a float. The normal title bar is used, and if it does not fit it is clipped. A title bar never covers its own float's content. A float tmux draws without a border has an outline over its content's edge and a title bar that is shown and hidden with a toggle, like the stoplight hotbox, and appears above the float. Floats at negative offsets are clipped as in tmux. |
| tmux floats-only windows | Supported. A tmux tab may have no tiled panes. Native tabs keep the invariant through promotion. |
| tmux popups | No popup-specific work. tmux has removed popups; `display-popup` is now an undocumented compatibility command that opens a modal floating pane. A modal float is treated as an ordinary float. |
| tmux before 3.8 | No floats. “New Floating Pane” is disabled in tmux tabs on older servers. Native and tmux sessions cannot mix in a tab, so drags are unaffected. |

## 2. Open questions

None at present. Items that still need a look, rather than a decision, are
marked "unverified" where they appear.

## 3. Model

### 3.1 Container

`PTYTab` gains an ordered collection of floats, back to front. Each float is a
wrapper view containing a `PTYSplitView` with exactly one `SessionView` child.
The wrappers are siblings of `root_` in the tab's container view (section
3.5), above it. The float's frame and z-order belong to the wrapper.

The wrapper is needed because `NSSplitView` lays its subviews out to fill it,
and PTYTab's `splitView:resizeSubviewsWithOldSize:` (PTYTab.m:6595) does the
same. A split view has no room of its own for an outline, a shadow or resize
handles. The wrapper owns those (section 4.3) and insets the split view by the
outline width.

Why a one-child split view rather than a bare `SessionView`:

- The split, peer-swap, synthetic-swap and divider paths all cast
  `view.superview` to `NSSplitView` and then use generic calls
  (`replaceSubview:with:`, `adjustSubviews`). With a per-float split view those
  casts stay true, and Instant Replay, Filter and screenshot-mode swaps inherit
  the float's frame and z-order with no extra bookkeeping.
- Of 392 methods in PTYTab.m, 68 reference `root_` and 39 are already
  parameterized on a node (`_recursiveSize:`, `_recursiveMinSize:`,
  `adjustSubviewsOf:`, the `splitView:` delegate methods,
  `_recursiveEncodeArrangementForView:`, `_recursiveRestoreSplitters:`).
- The `root_` identity tests that must become "is a root" are few:
  `assert(parentSplit == root_)` in `splitVertically:newSession:before:targetSession:`
  (PTYTab.m:2499), three cases in `cleanupAfterRemove:` (2091, 2129, 2137),
  `_recursiveViewFrame:` (2162, which walks up superviews until it meets
  `root_` and would not terminate under another root), and the enumerators.

Float records must be keyed on the float's wrapper or on `viewId`, never on
the `SessionView` pointer. During a synthetic swap the live view is parked in
`hiddenLiveViews_` with no superview.

Known hazards for the floats in the container:

- `setRoot:` (PTYTab.m:5212) replaces `flexibleView_`'s subviews and re-adds
  only the root. It runs on maximize, unmaximize and tmux layout rebuilds, and
  would drop the floats.
- `iTermFlexibleView drawRect:` (iTermFlexibleView.m:48-52) punches a clear
  hole for every subview frame, so it would punch one for each float.
- `unmaximizeTemporarilyAndActivate:` (PTYTab.m:1187) and
  `setActiveSessionPreservingMaximization:` replace `root_.subviews[0]` with
  the target session's view while maximized. With a float as the target they
  would move the float into `root_`.
- Nothing on the tab content path sets `clipsToBounds`. Floats are clamped to
  the tab natively, so clipping matters mainly for tmux (section 12.4).

### 3.2 Invariants

- A native tab always has at least one tiled session. A tmux tab may have
  none, because tmux allows a window with only floats (section 12.5).
- A float holds exactly one session.
- Floats sit above all tiled panes. Among floats, order is explicit.

### 3.3 Enumeration

`-[PTYTab sessions]` (PTYTab.m:1668) walks `root_`, or returns `idMap_` values
while maximized. Nearly every feature in the app reaches panes through it or
through `-[PseudoTerminal allSessions]`.

Decision: `sessions` and `sessionViews` include floats, and a new
`tiledSessions` serves the callers that must not see them. Each existing call
site needs to be classified. To make that exhaustive, rename `sessions` for
the duration of the refactor so that every caller fails to compile until it
picks one, then rename it back. There are 33 `sessions.count` sites outside
PTYTab.m alone. Known callers that need `tiledSessions`:

- Pane title visibility, which uses `sessions.count > 1` in six places
  (PTYTab.m:612-627, 4386, 4483, 5434, 5748; PseudoTerminal.m:8183).
- "Last pane" logic: `closeSession:soft:` (PseudoTerminal.m:1813),
  `closeSessionWithConfirmation` (2755), `sessionRemoveSession:` (PTYTab.m:7541),
  `removeAndClearSession` (MovePaneController.m:173), `reallyDropTab:` (197),
  the tab-bar drop edge case (PseudoTerminal.m:8757), and "drop on self moves
  the window" (PTYTab.m:7437).
- Tab size: `size`, `currentSize`, `variableTmuxSize` (PTYTab.m:4718) and
  `sessionsAtTop/Left/Right/Bottom` (1400). `minSize` measures the tiled tree
  and then adds a term for floats (section 5).
- `apply_layout`: the resolver, environment and mutator
  (iTermLayoutResolver.swift:152-162, iTermLayoutEnvironment.swift:49-55,
  iTermLayoutMutator.swift:276-283).
- `recreateTab:` (PseudoTerminal.m:11271), which requires every live session to
  appear in a saved arrangement.
- `replaceViewHierarchyWithParseTree:` (PTYTab.m:5410), which terminates every
  session left in `sessions` after rebuilding the tiled tree.
- Menu validation: `hasMultipleSessions` (PTYTab.m:3048) counts `root_`
  subviews while other items use `sessions.count`; they must agree.

Callers that count sessions and still need a decision:

- `moveSessionToTab:` validation (PseudoTerminal.m:14070) and select-pane
  validation (14192).
- `restorableSessionForSession:` (PseudoTerminal.m:2507), which chooses
  between restoring a session and restoring a tab.
- The inline progress bar (PseudoTerminal.m:9279).
- `textViewEnclosingTabHasMultipleSessions` (PTYSession.m:21890), used by the
  context menu.
- `textViewSplitPaneWidthIsLocked:` (PTYSession.m:22050).
- The tmux deregister count (PTYSession.m:3970).
- The pane-move split (MovePaneController.m:281).
- `arrangeSplitPanesEvenly:` validation (iTermApplicationDelegate.m:569).

While a tab is maximized, `sessions` returns only `idMap_` values. Floats stay
outside `idMap_` and `savedArrangement_`, so both accessors need to add floats
in the maximized branch as well. Broadcast input relies on this: its domain is
`currentTab.sessions` (PseudoTerminal.m:16090), which is why hidden panes of a
maximized tab receive broadcast input today.

### 3.4 Geometry drivers

Enumeration, z-order, focus, chrome and clipping are shared. Geometry ownership
differs:

- **Native:** the user owns the frame. The grid is canonical and the frame is
  derived from it.
- **tmux:** the server owns a cell rectangle. iTerm2 derives a frame from it
  and sends commands to change it.

Build this seam first so tmux is a second driver, not a second implementation.

### 3.5 Tab container view

Today a native tab's `root_` is the tab view item's view: `setRoot:` sets
`tabView_ = newRoot` (PTYTab.m:5223-5227). Only tmux tabs interpose a view,
`flexibleView_`, so that the root can be smaller than the tab. Floats need a
common superview, so every tab gets the interposed container and `root_` is
always a child of it. The places that assume otherwise:

**Ownership of the tab view item's view** (PTYTab.m)

- `setRoot:` (5212-5227). The native branch makes the root the tab's view. The
  tmux branch wipes all of `flexibleView_`'s subviews.
- `enableFlexibleView` (3562-3574) and `notifyWindowChanged` (3577-3582),
  which create the container lazily and for tmux only.
- `setTabViewItem:` (1311) and `replaceWithContentsOfTab:` (3515), which moves
  `root_` subviews between tabs.

**`flexibleView_ != nil` used to mean "is a tmux tab"**

These must test `isTmuxTab` once every tab has a container:

- `copyWithZone:` (570), `updateFlexibleViewColors` (1247), `rootViewSize`
  (5270), `updatedTmuxLayoutRequiresAdjustment` (5614) and the comparisons of
  root and container size at 5619-5641.
- The `hasFlexibleView:` parameter chain: PTYTab.h:143, PTYTab.m:3636 and
  4473, PseudoTerminal.m:2848, 4403, 11335, 11378, 11402, 12244 and 14701.

**Sizing that treats `root_`'s frame as the tab's frame**

- `setSize:` (2817-2826). The native branch resizes `root_` directly and the
  tmux branch resizes `tabView_`. Native must size the container and have the
  root follow.
- The autoresizing mask set at 5224 is max-margin only. That works today
  because `NSTabView` sizes the item's view itself. Inside a container a native
  root will not track it.
- `currentSize` (2809), `recompact` (2980), `absoluteFrame` (727-732),
  `image:` (2898), and the reads at 4711, 4933, 5125 and 5703.

**Root identity tests and superview walks**

- The cases listed in section 3.1, plus the tests at 2061 and 2185.
- `replaceWithContentsOfTab:` (3533), which skips `root_` when moving
  delegates.
- `_ancestorsOfLockedSession` (6432-6440) and
  `textViewSplitPaneWidthIsLocked:` (PTYSession.m:22055-22057). Both stop on a
  nil superview, so they are safe, but from a float they never reach `root_`.

**Coordinates relative to `root_`**

- `rootRelativeOriginOfSession:` (1080), the `sessionsAtTop/Left/Right/Bottom`
  comparisons (1405-1439) and directional navigation (1492-1588). These still
  convert correctly for a float.
- `sessionContainerView:` (7630) returns `root_` and anchors the shared
  background image (section 4.2). It should return the container.
- In a tmux tab the root can be smaller than the container. Float frames are
  relative to the container, not the root.

**Outside PTYTab**

- The swipe handler reparents `realRootView` (PseudoTerminal.m:16456-16463 and
  16509-16510). It works if `realRootView` returns the container.
- iTermSplitTreeRebuilder.swift:146 sizes a new root from
  `realRootView.bounds`.
- `imageFromSelectedTabView:tabViewItem:` (PseudoTerminal.m:8062) uses the tab
  item's view and will start to include floats, which is the desired result.
- The window-arrangement encoder (PseudoTerminal.m:4689) and `beginDrag:`
  (MovePaneController.m:334) read `session.view.superview`.

This list covers the references that depend on where `root_` sits in the view
hierarchy. The 68 methods that reference `root_` were not all traced.

## 4. Rendering

### 4.1 Metal over Metal (confirmation spike)

Two live Metal panes have never overlapped. Splits tile, and maximize gives
Metal to the active session only (PTYTab.m:7321-7324). Pane chrome already
composites above the `CAMetalLayer`, which is encouraging but not proof.

Spike: put one opaque Metal `SessionView` over another and confirm both stay
live and composite in view order. Also check, by eye, a translucent float with
its blur underlay (section 4.2) over a live Metal pane during a float drag and
during a resize. The blur is sampled by the window server and needs no code,
but the per-resize bounce to the legacy renderer (below) could make the
blurred region lag or pop.

In-window views are the decision (section 1), and the spike is expected to
pass. If it fails, Metal is turned off for floats. `updateUseMetal` is
all-or-nothing per tab today, so that means either a tab uses the legacy
renderer while it has a float, as a tab with a browser pane already does
(`metalAllowed:` returns NotATerminal at PTYSession.m:9450), or Metal becomes
a per-session choice within a tab, which is new work.

Other Metal facts that apply either way:

- `updateUseMetal` (PTYTab.m:7247-7327) requires every session to pass
  `metalAllowed:`. A float with a zero or oversized frame, or with no window
  yet, turns Metal off for the tab (PTYSession.m:9463, 9486, 9554).
- Metal is disabled at six or more sessions (PTYTab.m:7271). Floats count.
- A drag that shows drop targets disables Metal (PTYSession.m:9498).
- `SessionView` bounces to legacy for a runloop turn on each size change
  (SessionView.m:1434). Quantizing float resizes to whole cells limits this.

### 4.2 Opacity and background images

Nothing opaque sits behind a pane (SessionView.m:559-578). Without an
underlay, a translucent float would show the tiled pane's glyphs and every
lower float through it.

**Blur underlay.** A float whose session is translucent gets an
`NSVisualEffectView` in its wrapper, beneath the split view.

- Blending is within-window, so the float shows a blurred version of the tiled
  panes, lower floats and shared image beneath it. Behind-window blending
  would punch through to the desktop instead.
- It lives in the wrapper, not in `SessionView`, so it survives Instant Replay
  and Filter swaps.
- It is installed only while the session is translucent, and updates when the
  profile's transparency changes or the window's “Use Transparency” toggle
  flips.
- Its appearance is forced from the profile's background color (dark
  background, dark appearance). The material is otherwise tinted by the system
  appearance and would wash out a dark terminal in light mode.
- Its state is always active, like the existing ones, so floats do not go flat
  when the window loses key.
- Precedent for a within-window effect view over terminal content: the hover
  URL view (SessionView.m:79-88), the minimal composer and announcements.

Consequences:

- A translucent float no longer shows the desktop.
- The profile's blur setting and blur radius do not apply to a float. The
  material's blur is fixed and is on even when the profile's blur is off.
- Tiled panes keep the window-level blur of the desktop, so the two kinds of
  pane look slightly different.
- “Reduce transparency” in System Settings makes the material opaque with no
  work on our side.
- Transparency adds no new Metal rule. A translucent session already forces
  its tab to the legacy renderer unless text is monochrome
  (PTYSession.m:9528-9541).

**Shared background image.** With per-pane background images off, one image
sits behind everything (PseudoTerminal.m:16020-16033) and each session draws
its own slice. The slice is computed from the pane's position, not from the
split tree: the Metal path passes the pane's frame as a fraction of the
window's content view plus a container rectangle (`textViewRelativeFrame` and
`textViewContainerRect`, PTYSession.m:13426-13450) to
`iTermBackgroundImageRenderer`, and the legacy path does the equivalent in
`iTermBackgroundDrawingHelper`. A float is another rectangle and draws its
slice the same way. What needs handling:

- `sessionContainerView:` must return the tab container rather than `root_`
  (section 3.5), or a float outside a small tmux root computes a slice outside
  the image.
- The legacy path redraws only when asked. A live move must invalidate the
  float at each step, or the image slides with the float and then snaps back.
  Metal recomputes the slice every frame.
- A float with a blur underlay skips its own slice. Otherwise it draws a sharp
  slice over a blurred copy of the same image.
- The shared image is the current session's (PseudoTerminal.m:15994-16000).
  Focusing a float whose profile has a different image swaps the image for the
  whole window, as it does for split panes today.

Also:

- Window blur is a window-level effect and does not blur the tiled pane behind
  a float.
- `blur` (PTYTab.m:3081) and the flexible view color (1242) read the active
  session only.

### 4.3 Chrome

**Title bar.** A float always shows a title bar, regardless of the pane-titles
setting. It is the grab handle. The existing `SessionTitleView` is reused. It
already has the close button, menu button, lock button, pane number, title
dimming, double-click handling and hosting for a per-pane status bar, and it
is inside `SessionView`, so the grid-to-frame arithmetic already accounts for
it. Changes:

- `_showTitle` is per `SessionView` (SessionView.m:139) but the tab sets it
  from `sessions.count > 1`. The rule becomes "is a float, or the tab has more
  than one tiled pane". It must also apply to the synthetic view during
  Instant Replay and Filter swaps.
- `mouseDragged:` (SessionTitleView.m:377) starts the pasteboard drag at once.
  A float needs the live move first (section 7).
- The menu button gains the float items from section 6.7.
- Double-click maximizes the float.

**Outline and shadow.** These belong to the wrapper (section 3.1).

- A one-point border and a shadow, with an explicit shadow path equal to the
  wrapper's bounds so it stays cheap during live moves.
- Corners are square. Rounded corners would require masking the Metal layer.
- The border color is the focus cue: the accent color when the float is
  active and a neutral separator color otherwise. Overlapping panes then have
  a focus indicator that does not depend on the dimming setting.
- `iTermActivePaneBorderView` stays off for floats. It is drawn for the active
  session only, inside the scroll view's frame, and rounds corners at window
  edges (SessionView.m:2508-2606).
- A float pushed into a rounded window corner has a square corner there, and
  the window clips a few pixels of its border. Accepted. The alternative is to
  inset the clamp by the window's corner radius.

**Resize handles.** An invisible band of about four points around the outline,
inside the wrapper, with cursor rects. It overlaps the shadow, so it costs no
visible space. Being outside the `SessionView` bounds keeps it clear of
mouse-reporting apps, selection starting at the edge, the scroller, and
browser panes that swallow mouse events. The terminal margins are not grab
zones. Clicks in the band go to the float, not to the pane beneath.

## 5. Sizing

Today geometry flows from the window to the split tree to each `SessionView`
frame to rows and columns. `sessionSizeForViewSize:` (PTYTab.m:2983) derives
the grid, and `-[SessionView compactFrame]` (SessionView.m:2354) is the exact
inverse. Only the ioctl is throttled, to one per 0.2 seconds
(WinSizeController.swift:179-246).

Rules for floats:

- **The grid is canonical.** The frame is `compactFrame` for the grid, which
  includes the title bar, plus the wrapper's outline inset. Only a
  user edge-drag goes from frame to grid, snapped to whole cells. Otherwise the
  many callers of `fitSessionToCurrentViewSize:` (font, margin, scrollbar,
  title and toolbar changes) would silently cost the float rows.
- **Window and tab resize.** Keep the grid. Clamp the position and preserve
  edge anchoring, so a float touching the right or bottom edge stays there.
  Shrink the grid only when the tab is smaller than the float, and remember the
  desired size so it returns when there is room. Proportional scaling would
  resize the PTY on every drag step. `fitTabsToWindow` runs for every tab, so
  the clamp must run for background tabs too.
- **Tab size.** Floats never contribute to `size` or `currentSize`. Otherwise
  they inflate window refits.
- **Tab minimum size.** Floats do contribute to `minSize`. A float with a
  larger font than the tiled panes can be the constraint. Each float
  contributes its minimum grid at its own font plus its chrome, not its
  current grid, so a large float does not block shrinking the window. The
  shrink-and-remember rule above covers the range in between.
  `windowWillResize:toSize:` enforces
  `minSize` for every tab (PseudoTerminal.m:5951), so hidden floats and floats
  in background tabs count.
- **Session-initiated resize.** `sessionInitiatedResize:` (PseudoTerminal.m:7220)
  locks the session and refits the window. It is reached from CSI 8 t, DECCOLM,
  the API `grid_size` setter, AppleScript, Instant Replay frames, the Companion
  app's resize, and the Increase/Decrease Height and Width actions. For a float
  it must set the grid, set the frame, and clamp, with no window change. The
  same profile gates apply, and it is allowed in full screen. The exception
  is the Increase/Decrease Height and Width actions, which are window
  commands: with a float active they resize the window through a tiled
  session (section 6.8). Section 6.9 lists the gates in this path that a
  float must bypass.
- **Font size change.** Under “adjust window when changing font size”, grow the
  float to keep its grid, clamped to the tab. With the setting off, keep the
  frame. `reallyChangeSessionFontSize:` (PTYTab.m:2240) refits the window today.
- **No overhang.** A native float is clamped inside the tab. Nothing native
  forces overhang, and the title bar must stay reachable.
- **Minimum and maximum.** Minimum is 2x2 cells plus a fixed size in points
  for the chrome. That is not a usable float; it only prevents a degenerate
  frame. tmux allows 1x1 and its floats are shown at whatever size the server
  gives. Maximum is the tab's bounds. The split view constrain callbacks do
  not apply to floats.
- **Initial size.** 80% of the tab's width and height, rounded down to whole
  cells of the float's font. Pass it explicitly to `setupSession:withSize:`.
  The profile's columns and rows are not used.
- **Initial position.** Centered in the tab.
- **Extra chrome.** `rightExtra` (100 points for adjacent timestamps, plus
  gutter panels) and the legacy scroller widen a `SessionView`. Natively the
  frame simply includes them.
- **Maximize.** Floats stay visible over a maximized tiled pane. Creating or
  revealing a float does not unmaximize. Maximizing a float sets its frame to
  the tab bounds and remembers the old frame, without the `idMap_` root swap
  or an arrangement round trip. A maximized float moves behind the other
  floats, which stay visible above it, as tmux does when a float is zoomed
  (section 12.1).

## 6. Interaction

### 6.1 Creation

First version: “New Floating Pane with Current Profile”.

Places that encode where a new session goes, for step 9 of the plan:

- `iTermOpenStyle` (SessionCreation/iTermOpenStyle.h)
- New-instance open style (`stylePreference <= 3`, iTermApplicationDelegate.m:871-885)
- Key actions 26-29 and their four synchronized lists
- Pointer actions (`kNew*SplitWithProfilePointerAction`)
- Profiles window (`HORIZONTAL_PANE`, `VERTICAL_PANE`) and the Toolbelt profiles tool
- Context menu split items, including the URL split items
- API `SplitPaneRequest`, AppleScript `split`, the orchestrator's `SpawnWindowChoice`
- Browser split actions

### 6.2 Moving and resizing

- A plain title-bar drag moves the float live, clamped to the tab. The grid is
  unchanged, so there is no PTY resize.
- Mouse-down on a float raises it. This needs its own code: a click makes a
  pane first responder on mouse-up, and a cmd-click never does
  (PTYMouseHandler.m:577-585). If raising only followed activation, a float
  would rise on release, and a drag-selection in a background float would
  happen while it was still behind.
- Edge and corner drags resize, snapped to cells, with a size readout. There is
  no size readout on divider drags today, only on window resize.
- The existing menu items that resize a split pane (the four Move Divider
  actions) apply to a float and resize it by one cell.
- New menu items move a float by keyboard (section 6.7).
- “Lock Layout” blocks float move, resize and docking. Window “Lock Size” does
  not.

### 6.3 Focus and z-order

- `setActiveSession:` (PTYTab.m:937) only makes the text view first responder.
  It stays that way: becoming active does not raise a float. A float is
  raised by a click (section 6.2), by “Bring to Front”, when it is created,
  and by reveal. Focus follows mouse and keyboard navigation change focus and
  leave the z-order alone, so the active float can be partly covered by
  another float.
- In a tmux tab the server owns z-order and raises a float when it becomes
  the active pane (section 12.4). iTerm2 follows the server there.
- `-[PTYSession reveal]` (PTYSession.m:16806) never raises anything and, when
  the tab is maximized, calls `setActiveSessionPreservingMaximization:`, which
  replaces `root_.subviews[0]` with the target view. Reveal must unhide floats
  if hidden, raise the target, and never move a float into `root_`.
- When the floats are hidden while a float is active, activate the next most
  recently used session in the tab that is still visible. Sessions already
  carry a per-tab `activityCounter` (PTYTab.m:944), which gives the order.
- A float may cover the active tiled pane's cursor. That is accepted; the
  user can hide the floats.
- When the active float closes, activate the next float in z-order, else the
  last active tiled session. `nearestNeighborOfSession:` (PTYTab.m:2261) uses
  the superview's subview index and returns nil for a lone float.

### 6.4 Navigation and numbering

- `orderedSessions` (PTYTab.m:1087) has two orderings. With
  `navigatePanesInReadingOrder` on it sorts by origin; floats then sort after
  the tiled panes, in z-order, because overlapping origins make reading order
  meaningless. With it off it sorts by `activityCounter`, and floats take
  part like any pane.
- While maximized, the reading-order branch builds the list from
  `_orderedSessionIDs`, which comes from `idMap_` (PTYTab.m:1089). Floats are
  not in `idMap_`, so with a float active `sessionInDirection:` finds no
  index and Next Pane silently does nothing. The list must add floats.
- Pane ordinals (cmd-opt-N, title bars, the Toolbelt status tool) follow that
  order.
- Next Pane, Previous Pane and cmd-opt-N include hidden floats. Landing on one
  unhides the floats.
- Directional select and swap (PTYTab.m:1489-1604) use a strict non-overlap
  test. Floats are excluded as candidates. From a float they do nothing.
- Menu validation for these items must count consistently (section 3.3).

### 6.5 Hide and show

A per-tab toggle hides all of the tab's floats. Sessions keep running.

- One rule covers unhiding: focus entering a float unhides. Reveal, keyboard
  navigation, creating a float, and dropping a float into the tab all do this.
- Hiding while a float is active moves focus (section 6.3).
- Hidden floats still receive broadcast input, as the hidden panes of a
  maximized tab do today (section 3.3).
- Hidden floats still count toward the tab's minimum size (section 5) and
  toward close confirmations.
- The hidden state is saved in arrangements (section 10.1).
- A hidden float whose session ends follows its profile. With close on end
  it disappears and nothing unhides.
- Output, a bell, or a session that ends and stays open never unhides. They
  decorate the indicator (below).

**Indicator.** Hidden floats use the existing indicators feature, the icons
drawn at the top right of a terminal by `iTermIndicatorsHelper`. The
maximized-pane indicator (`kiTermIndicatorMaximized`) is the model.

- Add an indicator identifier with an SF Symbol, an entry in
  `sequentialIndicatorIdentifiers` (iTermIndicatorsHelper.m:303) and help text
  (377). `configureIndicatorsHelperWithRightMargin:` (PTYTextView.m:2348)
  sets it from a new delegate query. The Metal renderer draws indicators from
  the same helper.
- It shows in every tiled pane of a tab that has hidden floats. Indicators
  are per session, and there is no tab-level place to draw one. Showing it
  only in the active pane would make it jump around.
- Indicators are images with no count. The hover help text can give the
  count, since `helpTextForIndicatorWithName:sessionID:` is computed per
  session. That string needs plural handling per `docs/localization.md`.
- Indicators are not clickable. Showing the floats is done from the menu or
  its shortcut.
- Toggling hide must redraw every tiled pane in the tab.
- The indicator is decorated the way a tab's icon is. `updateIcon`
  (PTYTab.m:798) picks one state by priority: status dot, dead, bell, new
  output, idle. The indicator shows the highest-priority state among the
  hidden floats, using the same images and the same “show new output
  indicator” setting. The state clears when the floats are shown.
- Indicators are single images today. The decoration needs either composed
  images or a small badge drawn by `iTermIndicatorsHelper`.
- Indicators are drawn by `PTYTextView`. A tab whose tiled panes are all
  browser panes has nowhere to show it.
- In a tmux tab the same indicator covers floats that the server hides under
  zoom. tmux has no count or flag for that, so iTerm2 derives it by comparing
  the unzoomed layout with the visible layout (section 12.4).

### 6.6 Split, close, dock

- Split items are disabled when a native float is active. The validation
  path (`canSplitPaneVertically:withBookmark:`) is called from one place and
  tests the current tab's active session, not the target session, so many
  callers reach a split without it. Section 6.9 lists every entry point,
  which ones are refused and which are redirected to a tiled pane.
- Split selection mode (`setSplitSelectionMode:excludingSession:move:`,
  PseudoTerminal.m:12350) puts an overlay on every session in `allSessions`.
  It drives the keyboard “Move Session to Split Pane” and swap flows. For a
  move, floats must not be offered as targets, and they must be hidden or
  faded while the mode is on so they do not cover real targets. For a swap,
  floats are valid targets and stay visible (section 6.9). The API's
  `iTermSessionPicker` uses the same overlays.
- Closing a float closes only the float. The "last session closes the tab"
  checks must not fire.
- “Dock Floating Pane” moves the float into the tiled layout.

### 6.7 Menu items

New: “New Floating Pane with Current Profile”, “Dock Floating Pane”,
“Show/Hide Floating Panes”, “Bring to Front”, “Send to Back”, and four items
that move the active float up, down, left and right. Strings follow
`docs/localization.md`.

Moving a float to another tab or window uses the existing Move Session items
(section 6.8). The float's title bar menu and the context menu are one menu
(`menuAtCoord:`, iTermTextViewContextMenuHelper.m:382) and offer the float
items too. That menu validates only pane and layout locks today and needs
float-aware validation for Split, Move, Swap and Bury.

### 6.8 Main menu audit

Every item in MainMenu.xib was considered. Items not listed act on the current
session or on the app and work unchanged in a float.

**Shell**

| Item | Effect |
| --- | --- |
| Duplicate Tab, Duplicate Window | Floats are duplicated with geometry and z-order (section 1). |
| Split Horizontally and Vertically, with and without the sheet | Disabled when a native float is active (section 6.6). Enabled on a float in a tmux tab, where the server creates another float. tmux tabs follow tmux's idioms. |
| Close | Closes only the float. Blocked by Lock Layout, like any pane (`closeSessionWithConfirmation:`). |
| Close All Panes in Tab, Close Terminal Window | Include floats, hidden ones too. Confirmation counts must include them. |
| Undo Close | Section 10.4. |
| Save Archive of Current Session | Uses the only-session arrangement, which omits floats (section 10.1). Unaffected. |
| Exit Workgroup | Disabled for floats, which cannot enter a workgroup. |
| Broadcast Input to All Panes in Current Tab | Includes floats, hidden ones too. |
| Show Background Pattern Indicator | Stripes composite the way background images do: each pane draws its own, and a float's cover what is beneath it. No work expected. |
| tmux > Pause Pane | Per pane. Works for a float once floats are tmux panes. |

**Edit**

| Item | Effect |
| --- | --- |
| Find Globally | Reveals its match, which unhides and raises (section 6.3). |
| Filter, Clear Instant Replay | Synthetic swaps inside the float (section 9). |
| Alert on Marks in Offscreen Sessions | "Offscreen" today means a pane hidden by maximize, or a window or tab that is not showing (`PTYSession.m:19278-19286`). The maximize test treats every non-active pane as offscreen, which is wrong for floats that stay visible over a maximized pane. Hidden floats must count as offscreen. |

**View**

| Item | Effect |
| --- | --- |
| Toggle Full Screen, Show Tabs in Fullscreen, Show Toolbelt | Change the tab's size. Floats are clamped (section 5). |
| Use Transparency, Disable Transparency for Active Window | Install or remove each float's blur underlay (section 4.2). |
| Zoom In on Selection, Zoom Out, Start Instant Replay | Synthetic swaps inside the float. |
| Find Cursor | Draws in its own overlay window at the cursor's screen position. If a float covers the cursor, the floats are hidden temporarily while Find Cursor is showing and restored afterward. This is not the hide toggle: it does not move focus, change the indicator, or get saved. |
| Show Timestamps | Widens the `SessionView`. The grid is canonical, so the float grows and is clamped. |
| Show Composer | The minimal composer needs about 217 points and behaves as in a narrow split. |
| Maximize Active Pane | Section 5. |
| Make Text Bigger, Normal Size, Smaller | Section 5, font size change. |
| Restore Text and Session Size | Also resets the grid, through `sessionInitiatedResize:`. For a float that sets the float's grid with no window change. |
| Open Quickly | Reveal. |

**Session**

| Item | Effect |
| --- | --- |
| Edit Session | A profile change can alter font, transparency and title. The float's frame, underlay and chrome must follow. |
| Open Autocomplete, Command History, Recent Directories, Paste History | Separate windows placed at the cursor. They ignore in-tab z-order (section 9). |
| Move Session to Window, Move Session to Tab | Work for a float; it becomes a tiled pane at the destination. There are no separate float-specific items. Their validation counts sessions (`PseudoTerminal.m:14070`) and must count correctly with floats. Moving the last tiled pane promotes a float natively and leaves a floats-only tab in tmux. |
| Move Session to Split Pane | For a float this is the keyboard way to dock: split selection mode picks the target pane. Floats must not be offered as targets (section 6.6). |
| Make Screenshot | Captures the window, so it includes floats. |
| Bury Session | Works for a float. Burying the last tiled pane promotes a float. Disabled for tmux floats (section 12.6). |
| Buried Sessions | Disinter goes through `recreateTab:` (section 10.4). |

**Window**

| Item | Effect |
| --- | --- |
| Zoom, Window Style, Arrange Windows Horizontally | Change the window's size. Floats are clamped. |
| Save and Restore Window Arrangement, Load Arrangement from File | Include floats (section 10). |
| Change Profile in Arrangement | Rewrites sessions in a saved arrangement and must reach float sessions (section 10.2). |
| Move Tab to New Window, Merge All Windows | The tab carries its floats. Clamp after the destination refits. |
| Select Pane Above, Below, Left, Right | Floats are not candidates. From a float they do nothing and should be disabled (section 6.4). |
| Next Pane, Previous Pane | Include floats, hidden ones too (section 6.4). |
| Previous Peer, Next Peer | Disabled for floats. |
| Move Divider Up, Down, Left, Right | Resize a float by one cell: right and left change the width, down and up change the height. `moveCurrentSessionDividerBy:horizontally:` (PTYTab.m:5848) casts the session view's superview and that view's superview to split views. For a float the second is the wrapper, so floats need their own branch. The titles say "divider"; consider changing them when a float is active. |
| Lock Split Pane Width | Meaningless for a float. Disabled. |
| Lock Size | Does not affect floats (section 6.2). |
| Lock Layout | Blocks float move, resize and dock (section 6.2). It already blocks closing a pane and splitting, so it also blocks closing a float and creating one. |
| Arrange Split Panes Evenly | Tiled panes only. |
| Resize Window > Decrease and Increase Height and Width | These resize the window, never a float. Today they call `sessionInitiatedResize:` on the current session (PseudoTerminal.m:12470-12497), which under section 5 would resize an active float. With a float active they must act on a tiled session's grid instead. |
| Cockpit | Lists a tab's sessions through `orderedSessions`, so floats appear. |

### 6.9 Other sources of activity

An audit of the other menus, key binding actions, pointer actions, the Python
API and client, `it2`, AppleScript, built-in functions, Open Quickly,
triggers, escape sequences, session lifecycle, the AI features, the Companion
app and the Toolbelt. Findings are grouped by cause. Anything not listed acts
on its own session and is unaffected.

**Splitting a float.** Splits enter through two methods in PseudoTerminal.m.

- `asyncSplitVertically:...` (11541) and
  `splitVertically:before:profile:targetSession:...` (11630) are used by the
  menus, the context menu and browser context menu, key actions 28 and 29,
  the pointer split actions, the API and AppleScript. The only check is
  `canSplitPaneVertically:`, which tests the tab's active session, not the
  target. A refusal for a native float target belongs here, after the tmux
  branch, and must follow the existing contract (`ready(nil, NO)` then
  `completion(nil, NO)`) or a suspended AppleScript command never resumes.
- `splitVertically:before:addingSession:targetSession:performSetup:` (11441)
  is called directly by `iTermSessionLauncher` (314, 430) with a session that
  already exists, and the launcher then launches a process in it
  unconditionally. A refusal here would leave a running session with no tab.
  The launcher is reached by the Dock-icon file drop, the split open styles,
  and the orchestrator's `start_session` with `window=current`
  (OrchestratorDispatcher.swift:3053). These callers cannot be refused; the
  target must be changed before the session is created.
- Callers with no validation that split the current session: the Toolbelt
  Profiles tool (ToolProfiles.m:156, 173), the Profiles window
  (iTermProfilesWindowController.m:230, 283), URL splits
  (iTermController.m:2110-2121, from PTYTextView.m:8057 and the context
  menu), and the browser's cmd-opt-click (PseudoTerminal.m:15012).
- Rule (decided): a split whose target is a native float is redirected to the tab's
  most recently active tiled pane. Menu items that name the float as the
  thing being split are disabled instead.

**Swapping.** A tiled pane can be swapped with a float, and a float with a
float. `swapSession:withSession:` (PTYTab.m:6041) exchanges frames and moves
each view into the other's split view. With a split view per float, that
already puts the tiled pane's view in the float's wrapper and the float's
view in the tree. tmux's `swap-pane` behaves the same way (section 12.1).

- Swap With Next and Previous Pane (key actions 67, 68) pick the partner from
  `orderedSessions` (PTYTab.m:1151), which includes floats.
- The context menu's “Swap With Session…” uses split selection mode. For a
  swap, floats are valid targets, unlike for a move (section 6.6).
- Swap Pane Left, Right, Above, Below (53-56) pick a geometric neighbor.
  Floats are not candidates and from a float they do nothing, as for
  directional selection.
- Each pane takes the other's frame, so both grids change. The pane that
  becomes a float gets the float's z-order, title bar and outline, and its
  blur underlay is recomputed from its own transparency. The float record is
  keyed on the wrapper, so it does not change.
- A swap is refused if it would make a workgroup member a float.
- The tab still has a tiled session afterward, so promotion is not involved.

**Session-initiated resize.** Beyond section 5:

- `screenSetSize:` (PTYSession.m:16071) and `sessionInitiatedResize:`
  (PseudoTerminal.m:7228) both return early in full screen, and DECCOLM has
  the same gate (VT100ScreenMutableState+TerminalDelegate.m:1018). A float
  can be resized in full screen, so the float path must bypass them.
- `safelySetSessionSize:` enforces at least 20 columns
  (PseudoTerminal.m:13641), which conflicts with the 2x2 float minimum.
- `sessionInitiatedResize:` sets the tab's locked session. The float path
  does not need it.
- A CSI 8 t parameter of 0 means the screen size, computed from the window
  and screen (PTYSession.m:16169). For a float it means the tab's bounds.
- CSI 4 t sets a pixel size by calling `setFrameSize:` on the window directly
  (PTYSession.m:16277). It is not routed through `sessionInitiatedResize:`.
- CSI 1, 2, 3, 5 and 6 t and SetWindowFrame move, miniaturize, raise or lower
  the window.
- CSI 14 t and 19 t report the window's size and room to grow. They are
  already inexact for split panes; a float's true maximum is the tab.
- What tmux does (`input_csi_dispatch_winops`, input.c:2122): it ignores
  every window operation that changes something (1 to 11, 13, 20, 21, 24),
  for every pane, floating or not. Its reports describe the pane alone: 14 t
  gives the pane's size in pixels, and 18 t and 19 t both give the pane's
  grid. So tmux treats the pane as the window for reporting and offers no
  model for resizing. In a tmux tab these sequences never reach iTerm2.
- Decided for a native float, following "the pane is the window":
  - 8 t and 4 t resize the float. 4 t rounds to whole cells.
  - 5 t and 6 t bring the float to the front or send it to the back.
  - 14 t, 18 t and 19 t report the float's pixel size, its grid, and the
    grid that fits the tab.
  - 1 t, 2 t, 3 t and SetWindowFrame are ignored. Miniaturizing one float
    has no meaning, and their coordinates are screen coordinates.
- The Companion app's resize is gated by `companionSessionCanResizeWindow`
  (PTYSession.m:16119), which refuses in full screen and for maximized
  window styles. Those gates are wrong for a float.
- Key actions 49-52 (increase and decrease height and width) pass the
  receiving session, and apply modes fan them out to every session in a tab
  or window. The redirect to a tiled session (section 6.8) is per receiver.

**Focus and raising.**

- Focus follows mouse makes a pane first responder on mouse entry. It
  changes focus and never restacks floats, which is standard for focus
  follows mouse. A click raises. Keyboard actions change focus and do not
  raise.
- After the floats are hidden no mouse-entered event fires for the pane now
  under the pointer, so focus goes to the most recently used session rather
  than the pane under the pointer (unverified).
- `focusNewSplitPaneWithFocusFollowsMouse` (PseudoTerminal.m:11492) decides
  whether a new split takes focus under focus follows mouse. A new float
  needs the same rule.
- A cmd-opt-shift drag in a pane's text goes straight to `beginDrag:`
  (PTYMouseHandler.m:212). In a float it starts the live move, like the
  title bar.
- The title bar's Option requirement (`requireOptionToDragSplitPaneTitleBar`)
  returns before `beginDrag:`. The live move must start before that gate.
- Pinch changes the font of the current session, not the pane under the
  pointer (PseudoTerminal.m:1758). That is existing behavior, more visible
  with floats.

**Counting and ordering.**

- AppleScript's `session N of tab` is positional in `sessions`
  (PTYTab+Scripting.m:26). Tiled sessions come first and floats after, so
  existing indexes keep their meaning.
- `session.termid` and `ITERM_SESSION_ID` take the pane number from
  `sessions.count` (PTYTab.m:7494). With the same order, floats do not
  renumber tiled panes.
- The Toolbelt status tool shows a pane shortcut when the tab has more than
  one session and uses the view's ordinal (ToolStatus.swift:997).
- “Lock All Panes in Tab” and “Unlock All” iterate `sessions`
  (PTYTab.m:5648) and include floats, hidden ones too. Tab Color sets every
  session in `sessions`.
- Apply modes for actions and snippets (PTYSession.m:12094) use `sessions`,
  `allSessions` and `broadcastSessions`, so they include hidden floats, in
  line with the broadcast decision.

**API and scripting.** See section 11.

**Lifecycle.**

- Promotion and undo. Closing or burying the last tiled pane saves an
  arrangement in which float F is a float; promotion then makes F tiled.
  Undo or disinter goes through `recreateTab:`, finds the live layout no
  longer matches, and brings the session back as a new tab. Accepted: it is
  a narrow case and special handling would risk bugs.
- A float whose tab or window is gone is revived as a tiled tab
  (iTermController.m:1704-1760).
- `sessionShouldAutoClose:` (PTYTab.m:7612) defers close-on-end while a split
  divider drag is in progress. A float move or resize drag must count too.
- The restart announcement after a session ends, Capture Output's
  announcement, RequestAttention's flash and the AI chat mention picker's
  highlight are all drawn inside the session view. In a hidden float they are
  invisible, and the hidden-floats indicator is the only signal.

**Menus outside the main menu.**

- The context menu and the title bar menu are the same menu
  (`menuAtCoord:`, iTermTextViewContextMenuHelper.m:382). The float items
  from section 6.7 go there. A float always has a title bar, so this is
  their main home.
- Bury is validated by `textViewCanBury` (PTYSession.m:15157), which must
  return NO for a tmux float.
- “Move Session to Window” on a tmux float calls `breakOutWindowPane:`
  (unverified what the server does).
- The Dock menu, the Profiles menu, Services and the tab-group menus have no
  pane items.

**Not audited.** The browser session's own key binding dispatch, and which
view AppKit picks as the drop destination when text or files are dropped
where a float overlaps a tiled pane.

## 7. Dragging

Today a title-bar drag, or a cmd-opt-shift drag in the text view, starts an
AppKit drag session (`MovePaneController beginDrag:`). The view stays put and a
drag image follows the pointer. The outcomes are: onto a pane (split halves,
`dropInSession:half:`), onto a tab bar (new tab, `unknownObjectWasDropped:`),
or onto nothing (new window, `moveSessionToNewWindow:`).

Behavior for a float:

| Drag | Behavior | Needs |
| --- | --- | --- |
| Within its tab | Live move, clamped to the tab. | A tracking loop on the title bar. |
| Leaving the tab area | Escalates to the existing drag session. | A handoff from the tracking loop to `beginDrag:`. |
| Onto a tab bar, between tabs | New tab with the float as its tiled pane. | `removeSession:` handling a float. |
| Onto a tab in the tab bar | Spring-loaded: that tab is selected after a delay. | New work in `PSMTabBarControl`; it has no spring-loading. |
| Onto nothing | New window sized from the float's grid. | `removeSession:` handling a float. |
| Onto another tab's or window's content | Stays a float at the drop point, clamped. The grid shrinks only if the destination is smaller. | A new tab-level drop target. |
| Control held over a pane | Split halves appear and the float docks there. | Reads live modifier state; nothing reads it today. |

Rules and complications:

- Holding Control during a live move escalates to the drag session at once, so
  the float can be docked into its own tab.
- Floats are never split targets. `SessionView` registers every pane as a drop
  target (SessionView.m:210), so floats opt out. A drop that lands on a float
  counts as a drop on its tab.
- Other floats can cover the pane you want to dock into. Fade or hide them
  while Control is held.
- Session-count checks must count tiled panes only (section 3.3).
- Dragging out the last tiled pane, to another tab, a tab bar or nothing,
  promotes the front float in the source tab. The tab-bar drop path
  special-cases `tab.sessions.count == 1` (PseudoTerminal.m:8757) and must
  count tiled sessions. In a tmux tab nothing is promoted (section 12.5).
- A tab dragged onto a pane merges as a split and is refused when the tab has
  more than one session (PTYTab.m:7410). A tab with floats must also be
  refused.
- A tab moved between windows carries its floats. Clamp them after the
  destination window refits.
- Entering a maximized tab mid-drag unmaximizes it (`sessionDraggingEntered:`),
  which runs `setRoot:`.
- `requireOptionToDragSplitPaneTitleBar` applies to the escalated drag, not to
  the live move.
- Layout lock and session lock gate the live move as they gate `beginDrag:`.
- Every drag has a menu equivalent (sections 6.7 and 6.8), for keyboard users
  and the API.

Order of work: live move plus drag-out to a tab bar, a new window and a split
reuse existing code and come first. The floating drop into another tab or
window and spring-loaded tabs follow.

## 8. Mouse and hit testing

- Click-to-activate works with default AppKit hit testing if the front float
  is the topmost subview.
- Each `SessionView` installs tracking areas over its bounds with
  `NSTrackingActiveAlways` (SessionView.m:1537-1562). They are not
  occlusion-aware (unverified AppKit behavior). The expected failures: a tiled
  pane under a float also gets `mouseEntered`, so focus-follows-mouse can steal
  focus; moving from a float back onto the pane it sits inside produces no
  `mouseEntered`; and `mouseMoved` reaches the covered pane, driving URL
  underlines, cursor changes and mouse-motion reporting. The fix is a
  window-level `hitTest` gate like the one at SessionView.m:1609.
- NSSplitView divider cursor rects under a float may still change the cursor
  (unverified).
- Mouse-report coordinates, scroll wheel routing and selection autoscroll are
  view-local and follow hit testing.

## 9. Existing features

| Feature | Required behavior or problem |
| --- | --- |
| Global Search, Open Quickly, notification click, AI chat, Cockpit, `FocusBuiltInFunction`, git status component | All call `reveal`. It must unhide and raise (section 6.3). Global Search also moves its panel away from the match rect and assumes the rect is visible. |
| Notification click-to-reveal | `sessionWithViewId:` (PTYTab.m:1073) walks `root_` only and misses floats. |
| Status bar | With per-pane status bars, a float has its own. With the shared window bar, the bar belongs to `currentSession` (PseudoTerminal.m:13010) and swaps when a float takes focus, taking any open search or filter component with it. If the float and the tiled pane differ on showing a bar, the tab height changes. |
| Workgroups | No entry path checks the session's kind. Entry is refused for floats in `enterDisposition` (iTermWorkgroupController.swift:179). Peer swap and split children are not needed. A swap that would make a workgroup member a float is refused (section 6.9). |
| Instant Replay, Filter, zoom on selection, screenshot mode | `replaceActiveSessionWithSyntheticSession:` (PTYTab.m:1772) works inside a float's split view. Replay saves and restores the window frame; a float needs the same for its own frame. Refuse dock and resize during replay. |
| Broadcast input | Domains use `currentTab.sessions` or `allSessions`, so floats are included, hidden ones too. The background stripes composite like background images and need no work. |
| Dimming | `setDimmingForSession:` (PseudoTerminal.m:12529) dims every non-active session. Floats are treated like any pane: with “dim inactive split panes” on, an inactive float is dimmed, and focusing a float dims the tab's other panes. The float's outline color shows focus either way. |
| Accessibility | AppKit derives the accessibility tree from the view hierarchy, so floats appear without work. VoiceOver reads tiled panes first and floats after, and still announces covered panes. Check the traversal order with VoiceOver on. |
| Tab title, color, icon, activity | They follow the active session, so they follow an active float. Acceptable natively. |
| Bury | Works per session natively. Disinter goes through `recreateTab:` (section 10.4). |
| Undo close | Section 10.4. |
| Tab drag image | `image:` (PTYTab.m:2893) walks `root_` and omits floats. |
| Size readout during window resize | Shows the current session's grid. With a float active it will not change. |
| Window resize snapping | `windowWillResize:toSize:` (PseudoTerminal.m:5868) uses the active session's cell size and chrome. It should use a tiled session. |
| Small-float overlays | The find bar (minimum 150 points), announcements, the minimal composer (minimum 217 points) and the hover URL view assume a reasonably large pane. They behave as in a narrow split today. |
| Child and separate windows | The find indicator, autocomplete and history popups, and completions are windows placed at the cursor. They ignore in-tab z-order and can appear for a cursor that is covered. |
| Per-session toolbar | Not needed for floats while workgroups are refused. |
| Session variables | Add `session.isFloating`. `session.termid` pane numbers come from `sessions`; with tiled sessions ordered first, floats do not renumber tiled panes. |
| Triggers | None create or move panes. Show Alert, Open Password Manager and Post Notification end in `reveal` or in the `sessionWithViewId:` lookup above. The password manager types into the window's current session, so `reveal` must make a float the active session, not only raise it. |
| Unaffected | Secure Keyboard Entry, Composer, Restart Session, tab groups, swipe between tabs, SSH integration, hotkey windows, Services, and Toolbelt tools other than Profiles and Status (section 6.9). The Companion app lists floats as ordinary panes; its resize gate is in section 6.9. |

Not audited in depth: portholes, annotations, multi-cursor, copy mode, the
badge and the cursor guide.

## 10. Persistence and restoration

### 10.1 Schema

Floats are an additive sibling of the tree, never a new node type inside it.
Old builds ignore an unknown top-level key.

```
"Root": { ... unchanged; at least one session in a native tab ... }
"Floating Panes Hidden": bool
"Floating Panes": [              // back to front
  { "frame": {x, y, width, height},    // points, relative to the tab container
    "Container Size": {width, height},
    "Desired Grid Size": {columns, rows},  // only if shrunk to fit the tab
    "Saved Frame": {x, y, width, height},  // only while the float is maximized
    "Node": { ... same shape as a node in the tiled tree ... } } ]
```

- The active session is not recorded on the float. Session nodes already
  carry `Is Active` (PTYTab.m:3242), and `Node` contains one. A second flag
  would be a second source of truth.
- `Desired Grid Size` backs the shrink-and-remember rule in section 5.
- `Node` holds a session node today. Using the tree's node shape leaves room
  for splits inside a float without a schema change.
- On restore, scale the origin by the ratio of the new container to the saved
  one, take the size from the session's saved columns and rows at the current
  font, then clamp. Split frames are saved in points and act as proportions
  because the split view rescales them; floats have no such scaling.
- Omit the key when `PTYTabArrangementOptionsOnlySessionID` is set (Duplicate
  Session and the archive path).

### 10.2 Walkers

These PTYTab class methods take only `arrangement[Root]` and need a floats
pass. One enumeration helper should replace the pattern:

- `registerSessionsInArrangement` (330)
- `arrangement:passesTest:` (3704)
- `modifiedArrangement` (3709)
- the four `repairedArrangement` variants (3718-3756)
- `arrangementForSessionWithGUID` (3758)
- `sessionMapWithArrangement` (4123)
- `drawArrangementPreview` (3494)
- `openPartialAttachmentsForArrangement` (3624)

`openPartialAttachmentsForArrangement` matters most. Unextended, a float's
process is not reattached; the float relaunches fresh and its old process is
adopted as a tab by `iTermOrphanServerAdopter`.

### 10.3 Trust gate

`RiskAnalyzer` in iTermArrangementTrustGate.swift (96-99, 177-190) walks
Tabs, Root, Subviews, Session. A quarantined arrangement could hide commands,
initial text and triggers in float sessions and be reported as zero risk.
Extend it in the same commit as the decoder.

### 10.4 Undo close and bury

Closing a pane stores the whole tab's arrangement (PTYTab.m:922-931).
`recreateTab:` builds a GUID map from the tree, requires every live session in
the tab to be in it, and otherwise re-adds the revived session as a new tab. On
success it calls `replaceWithContentsOfTab:` (PTYTab.m:3515), which moves only
`root_` subviews.

- `recreateTab:` should rebuild and check only the tiled tree and leave live
  floats alone.
- Undo-closing a float re-adds it from its saved frame with no rebuild.
- Bury and disinter use the same path (iTermBuriedSessions.m:66-75, 144).

### 10.5 Other paths

- **Maximize.** `maximize` snapshots the tab and `unmaximize` rebuilds from the
  snapshot. Floats stay out of `idMap_` and `savedArrangement_` and are encoded
  live in both branches of the encoder (PTYTab.m:3969-3997).
- **Duplicate Tab.** `arrangementForDuplication` then `tabWithArrangement:`.
  It works once the encoder and decoder handle floats.
- **Graph encoder.** Key floats by session GUID in an `encodeArrayWithKey:`
  array. Duplicate identifiers trip an assert (iTermGraphEncoder.m:221-223).
  Order gives z-order.
- **Saved window arrangements and hotkey-window arrangements** use the same
  encoder, so they include floats.
- **Older builds** are not a constraint. One reading a newer arrangement
  loses the floats, and may fail to restore a window that contains a
  floats-only tmux tab.
- **Settings sanitizer.** Redaction is by key name at any depth, so session
  dictionaries under the new key are covered. Avoid new sub-keys named `value`,
  `text`, `name`, `title`, `command` or `url`.

## 11. API and scripting

- **Proto.** Add `repeated FloatingPane floating_panes = 12` on `Tab`, with a
  `SplitTreeNode` (or session summary), frame and z-index. Never add a `oneof`
  case to `SplitTreeNode`: the Python client's `Splitter.from_node` treats any
  non-session link as a splitter (session.py:42-58).
- **Do not reuse `minimized_sessions`.** The client marks those sessions buried
  with no grid size. This happens by itself unless prevented:
  `minimizedSessions` (PTYTab.m:7490) is `sessions` minus the active session,
  so once `sessions` includes floats, every float in a maximized tab is
  reported as minimized while it is still visible. It must use
  `tiledSessions`.
- **Consistency.** Today the session list comes from `rootSplitTreeNode` while
  subscriptions, variable scopes, activate, close and split look sessions up
  through `allSessions`. Floats would produce notifications for sessions the
  client's tree has never seen. Old clients trigger an extra refresh and
  otherwise ignore them.
- **Notifications.** A float resize that changes the grid already fires
  LayoutChanged, through `PTYSessionDidResizeNotification`
  (iTermAPIHelper.m:950). Only window live resize and split divider drags are
  suppressed, so a float edge-drag would send a full ListSessions payload per
  grid step; it needs the same suppression. Float move, restack, hide and
  show, and a dock that keeps the grid fire nothing. Add a notification or
  reuse the layout-changed one.
- **Requests.** New: create float, dock, set frame, raise. A split of a native
  float is refused. `SetTabLayout` checks tree shape only and is unaffected in
  native tabs.
- **Python client.** Add `Tab.floating_sessions`; include floats in
  `all_sessions` and `get_session_by_id`; keep `Tab.sessions` tiled-only.
  `Tab.current_session` (tab.py:189) searches `sessions` and returns `None`
  when the active session is a float, in any tab; it must search all
  sessions. `Tab.sessions` can be empty for a floats-only tmux tab.
- **`apply_layout`** must see tiled sessions only, or existing scripts fail
  with `orphanedSession` on any tab that has a float.
- **AppleScript.** `sessions of tab` is `[self sessions]` and includes floats
  automatically, after the tiled sessions. There is no command to create,
  dock, move or raise a float; add them or leave AppleScript without.
- **Built-in functions.** `select_pane_in_direction` excludes floats.
  `move_session_to_new_tab` and `move_session_to_new_window` work for a float
  through `MovePaneController`.

Further items from the audit of every endpoint:

- `active_session_id` and the Focus response name a float that is not in
  `root`.
- `SplitPane` with `session == "all"` iterates `allSessions`. One refused
  float sets `CannotSplit` for the whole response although the tiled splits
  succeeded (iTermAPIHelper.m:2675).
- `Activate` with `select_session` on a maximized tab does unmaximize, set
  active, maximize (iTermAPIHelper.m:3130). With a float target the last
  step would maximize the float.
- `GetBroadcastDomains` lists float IDs that a client cannot resolve from the
  tree.
- In the Python client, `Tab.all_sessions` (tab.py:165) is what
  `get_window_and_tab_for_session`, `Session.tab`, `Session.window` and the
  layout-change merge go through. Floats must be in it, or `Session.tab` is
  `None` for a float. `Tab.update_session` and `Tab.update_from` must carry
  floats too.
- `Session.__init__` (session.py:250) has two modes, a tree link with frame
  and grid or a summary marked buried. Floats need a third, with a frame and
  grid.
- An old client that gets a focus change onto a float does one extra
  ListSessions and Focus round trip (app.py:423).
- `it2` resolves a missing session argument to the first leaf of the
  selected tab's tree, not to `active_session_id` (APIClient.swift:53). With
  a float focused every such command targets a tiled pane, and on a
  floats-only tab it fails. It should use the active session. `broadcast
  add` rejects a float ID because it validates against tree leaves
  (AppCommand.swift:404).
- `move_session` (MoveSessionBuiltInFunction.swift:45) accepts a float as
  the destination, which would split a float and must be refused, and as the
  source, which is a dock and is allowed. `apply_layout` resolves a float
  GUID as a leaf reference; it should be an error.

## 12. tmux integration

### 12.1 Protocol facts (verified in tmux source)

- Opt in with `refresh-client -f new-layouts`, control clients only. Layouts
  then arrive as JSON: `{"V":2,"L":cell}`. There are no spaces and no checksum.
- A float is a leaf with a `"z"` key, mixed in with tiled siblings. The root
  can be a floating leaf, and nodes can contain only floats.
- Layout x, y, w and h are the inner content rectangle. `move-pane -X/-Y`,
  `resize-pane -x/-y` and `new-pane` take outer coordinates when the float has
  a border. Sending layout values back unchanged drifts by one or two cells.
- Layout `w` includes reserved scrollbar columns. `pane_width` is the content
  width.
- `pane_z` is non-empty for tiled panes, so it cannot identify a float.
  `pane_floating_flag` cannot either while the window is zoomed: it tests the
  pane's layout cell (`window_pane_is_floating`, window.c:2969), and a float
  hidden by zoom has no cell, so it reports 0. Use the `"z"` key in the
  unzoomed `window_layout`, which still lists hidden floats.
- While a modal pane exists, tmux adds `O` to the window flags sent with
  `%layout-change` (window.c:1395, undocumented). `#{window_modal_pane}` gives
  the pane ID.
- After `break-pane -W` on every tiled child of a node, tmux appears to leave
  that node at 0x0, so the JSON would contain `"w":0`, which tmux's own parser
  rejects (unverified by running).
- These changes send no `%layout-change`: raising a float by focusing it (only
  `%window-pane-changed`), mouse move and resize by another client, and
  `rotate-window`. A `refresh-client -B` subscription on `#{window_layout}`,
  which always uses the JSON format, is required to stay in sync.
- `display-popup` and the buffer and customize editors are modal floating
  panes with pane IDs and `%output`. A control client's own `display-popup` is
  a silent no-op, but one opened by another client is visible.
- While a pane is modal, `select-pane` to another pane silently does nothing,
  and swap, join and break of the modal pane fail with "pane is modal".
  `send-keys` to other panes is not blocked (unverified by running).
- `split-window` on a float creates another float. `swap-pane` exchanges
  cells, so a tiled pane can become floating.
- `break-pane -W` makes a tiled pane floating. `join-pane` with a floating
  source and no destination, or the source as its own destination, tiles it
  (`cmd_join_pane_tile`, cmd-join-pane.c:386). Both fail while the window is
  zoomed, and tiling fails with "no space for a new pane" when the layout is
  full.
- Zoom (`window_zoom`, window.c:986) hides every float except those created
  with `-A` or as a modal with `-O`, which carry `PANE_FLOATOVERZOOM`. Those
  keep their geometry, and a move or resize made while zoomed is copied back
  on unzoom. A hidden float loses its layout cell until unzoom.
- A float can itself be zoomed. It fills the window and moves behind the
  floats in z-order, so over-zoom floats still show above it. It returns to
  the floating part of the z-order on unzoom.
- Zooming does not take the active pane away from an over-zoom float. A modal
  or `-A` float can be the active pane over a zoomed pane.
- Creating an `-A` or `-O` float in a zoomed window restores the zoom
  afterward (`restore_zoom`, cmd-split-window.c:146). Other commands that
  need the full layout unzoom first through `window_push_zoom`.
- On window resize tmux shrinks oversize floats and fixes right and bottom
  overflow only. Negative offsets persist. Clamping is per window, so a smaller
  client moves floats for everyone.
- A v1 layout string is still accepted by `select-layout` after opting in and
  leaves floats alone. Keep `iTermTmuxLayoutBuilder` on v1. A JSON layout would
  need quoting and would also apply active-pane and z-order state.
- Default bindings create floats: `*` runs `new-pane`, and Tab and BTab open
  process-less floats running a mode.
- Border lines, border styles, window style and popup title are per-pane
  options readable through `iTermTmuxOptionMonitor`.
- Test fixtures: `regress/layout-custom.sh` has 55 JSON layouts, including
  nested float-only nodes, reordered keys and rejects.

### 12.2 Fixes independent of this feature

- **Layout parse failure aborts the connection.** A client that has not opted
  in gets `0000,` for a window with only floats. `parsedLayoutFromString:`
  returns nil and TmuxWindowOpener.m (107, 159, 568) calls
  `abortWithErrorMessage:`. This affects shipping builds against tmux 3.8.
- **Commands sent without error tolerance abort the connection**
  (TmuxGateway.m:636-643). With floats and modals these can now fail:
  `swap-pane` (TmuxController.m:3311), `break-pane` (2731), `select-layout`
  (3354, "no panes" on a floats-only window), `resize-pane -L/R/U/D` (2323),
  `new-window` (2520) and the `list-panes` that starts a split (2371).

### 12.3 Opting in

Feature detection is better than a version gate. tmux 3.2 and later silently
skips unknown `-f` flags, and older versions fail on a command iTerm2 already
sends tolerantly. Confirm with `#{client_flags}` or a layout beginning with
`{`. The version parser accepts `next-3.9`, `3.8`, `3.8a` and `3.8-rc3` as at
least 3.8, the last by accident, and never accepts OpenBSD version strings.
Versions are also compared as decimal numbers
(`versionAtLeastDecimalNumberWithString:`), so a future tmux 3.10 would
compare as 3.1 and fail a 3.8 gate.

Opting in cannot ship before the UI exists, because floats would then appear
in layouts that nothing can display.

### 12.4 Mapping onto the model

- **Parser.** A new JSON parser emits the existing dictionary shape for tiled
  cells plus a separate float list, collapsing nodes left with one child.
  `depthFirstSearchParseTree:` callers in `openWindows:` and
  `decorateParseTree:` must see floats too, or floats get no history, state,
  user variables or tab-color decoration.
- **Zero-size cells.** The parser must accept a node with a zero width or
  height rather than abort the connection (sections 12.1 and 12.2).
- **Dropped output.** `didLearnLayout:forWindow:` (TmuxController.m:959)
  feeds `TmuxDroppedOutputScanner.didLearnPanes` from
  `windowPanesInParseTree:`. It must include float pane IDs, or a float's
  `%output` counts as dropped even after opting in.
- **Conversion.** `replaceViewHierarchyWithParseTree:` terminates sessions
  missing from the new tiled tree. A pane toggled between tiled and floating by
  the server must be moved, not terminated and recreated.
- **Cell-to-pixel mapping.** Each tiled pane adds margins, a scroller and
  optional title bar, and a divider is one point where tmux uses a cell
  (`_sessionSizeWithCellSize:`, PTYTab.m:2553). The pixel x of tmux column X
  drifts with the number of dividers to its left. So there is no global
  mapping. The rule is local:
  - Find the tiled pane that contains the float's top-left content cell in
    tmux coordinates. Place the float's top-left cell exactly over that cell
    of that pane.
  - The float moves in pixels when the tiled layout changes, because the pane
    it is anchored to moved. That is the correct result.
  - If the cell is not inside a tiled pane (a divider cell, a negative
    offset, or past the last pane), anchor to the nearest tiled pane and
    offset by whole cells.
  - In a floats-only window there is no tiled pane. Use a uniform grid from
    the container's origin.
- **Chrome.** The content rectangle is fixed by the server, so chrome cannot
  take space from it, and it cannot always go outside it either: a float can
  be as large as the pane or the window it covers. tmux has the same problem
  and solves it with the border. The layout gives a float's content
  rectangle, say column 10, row 5, 40 wide and 12 tall. If the float has a
  border, tmux draws it in the cells just outside that: the float occupies
  columns 9 to 50 and rows 4 to 17 on screen. That larger rectangle, the
  content plus a one-cell border on every side, is what the move and resize
  commands address (section 12.1). iTerm2 puts its chrome in that border.
  - **Bordered float.** The wrapper covers the content plus the border. The
    title bar goes in the border's top row, and the outline, resize band and
    session margins go in the sides and bottom. Content cells stay aligned,
    and a float as large as the window has its border inside the window.
  - **Title bar height.** The normal `SessionTitleView` is used, at its
    normal height, which is the status bar height plus one point
    (SessionView.m:53). That is taller than a cell at common font sizes. The
    excess extends upward, away from the content, and is clipped at the top
    of the tab. A title bar never covers its own float's content; being
    clipped is preferred. No compact variant is built.
  - **Borderless float** (`pane-border-lines` is none). tmux reserves no
    border and draws no chrome. iTerm2 draws a one-point outline over the
    edge of the content and hides the title bar. A toggle shows and hides
    it, following the stoplight hotbox, which slides in and out behind a
    narrow toggle button when it would cover a toolbar or status bar
    (`_stoplightHotboxToggle`, iTermRootTerminalView.m:175). While shown,
    the title bar sits above the content, outside the float, and covers
    whatever is there. It is clipped at the top of the tab, so for a
    borderless float in the top row it cannot be shown.
  - **Negative offsets.** tmux leaves floats partly outside the window, so
    iTerm2 must too. The wrapper is clipped at the tab's edge, and a float
    whose title bar is outside is reachable by keyboard and menu until it is
    moved.
  - The session's side margins plus the outline must fit in one cell width.
    The default margin does. A larger margin setting makes the chrome extend
    past the border and cover a little more than tmux would.
- **Border status.** Floats reserve no row for `pane-border-status`.
  `adjustLeavesInNode:` (TmuxLayoutParser.m:148) would wrongly shrink a float
  at y = 0.
- **Client size.** `variableTmuxSize` filters `sessionViews` by geometry and
  would count floats as stacked tiled panes. Floats must not contribute.
- **Raise.** `%window-pane-changed` to a float must bring that float to the
  front, since the server raises a float when it becomes active.
- **Move and resize.** Send `move-pane` and `resize-pane` with the outer
  coordinate conversion. `_isDraggingSplitInTmuxTab` forces legacy rendering
  during divider drags; a float drag needs an equivalent.
- **Split from a float.** tmux creates another float. iTerm2's split
  bookkeeping (`willSplitTmuxPane`, the senior and junior logic) assumes a tree
  change, and a popup appearing first would steal focus meant for the new pane.
- **Zoom.** `maximize` assumes the zoomed pane is the active session. With a
  modal or `-A` float active it would maximize the float.
- **Floats under zoom.** Native tabs keep every float visible over a
  maximized pane. In a tmux tab the server decides: while zoomed, show only
  the floats in the visible layout, which are the over-zoom ones. The others
  are hidden by the server, not by the hide toggle, and return on unzoom.
  They still exist, so they must not be terminated when they drop out of the
  visible layout (see Conversion above), and they are identified from the
  unzoomed `window_layout` (section 12.1).
- **Title bars.** A float appearing in a single-pane tab must not turn on the
  tiled pane's title bar and resize the client. The rule in section 4.3 counts
  tiled panes only.
- **Dragging.** Within-tab moves map to `move-pane -X -Y`. Dragging out maps to
  `break-pane`, which makes the pane tiled in a new window.
- **Dock.** “Dock Floating Pane” maps to `join-pane` on the float, which
  tiles it (section 12.1). The server chooses where it goes. It is refused
  while the window is zoomed.
- **Hazard.** `setTmuxLayout:` paths run `setRoot:` (section 3.1).

### 12.5 Floats-only windows

Killing the last tiled pane keeps the window, and tmux then shows only
floats. iTerm2 supports this: a tmux tab may have an empty tiled tree. Native
tabs never do, because promotion (section 1) keeps one tiled session.

iTerm2 does not promote in a tmux tab. It could, by sending `join-pane` to
tile the front float, but tmux itself leaves the window floats-only, another
client attached to the session would see a pane change state for no reason
it can observe, and the command fails while zoomed. The same holds when the
last tiled pane is moved out with `break-pane`.

The container refactor (section 3.5) makes this representable: `root_` is a
child of the container and can be a split view with no subviews, with the
floats beside it. The work, roughly in order of difficulty:

- **Client size.** `tmuxSizeForHeight:` (PTYTab.m:4589) measures the tiled
  tree and returns 0 when it is empty. In fixed-size mode `fitLayoutToWindows`
  (TmuxController.m:1094) then returns early, which freezes resizing for every
  window in the session. An empty tree must report a size derived from the
  container, as the code at PTYTab.m:7559 already does from the tab's frame.
  `variableTmuxSize` needs the same treatment.
- **Tab size.** `size` and `currentSize` come from `root_`, which is empty,
  and floats do not contribute. The tab must keep the size the server gave
  for the window, or the window refit collapses it.
- **Transitions.** `replaceViewHierarchyWithParseTree:` and the
  `setTmuxLayout:` paths must handle a tree becoming empty (last tiled pane
  killed) and becoming non-empty again (a float is tiled). Maximize and
  `root_.subviews[0]` uses must tolerate an empty root.
- **Callers of `tiledSessions`.** Any that take the first element or assume a
  count of at least one need a fallback, for example window resize snapping
  (section 9). The rename in section 3.3 forces a look at each; "may be empty
  in a tmux tab" is one of the things to check.
- **Parsing.** A window with only floats has a root that is a floating leaf
  or a node of floats. Without opting in it is `0000,` (section 12.2).
- **Close.** Closing the last pane of such a window sends `%window-close`
  with no preceding `%layout-change`.
- **Background.** The empty tiled area shows the container's background.

A floats-only tab still has sessions, because floats are sessions. `sessions`
and `activeSession` stay non-empty, so code that assumes a tab has a session
is unaffected. What becomes empty is the tiled tree, which narrows the risk to
two groups:

- Code that indexes into `root_`. In PTYTab.m there are eleven such sites.
  Most are guarded already: the maximize paths (1134, 1198, 5784) run only
  while maximized, the checks at 2070 and 2089 test for a count of one first,
  and 2276 handles an empty split view because
  `replaceViewHierarchyWithParseTree:` already empties the tree transiently.
  The ones to fix are `replaceWithContentsOfTab:` (3544, 3548) and the split
  assert at 2492.
- Callers moved to `tiledSessions` during the refactor. Each can now see an
  empty list in a tmux tab.

The tree is already empty for a moment today, between the last session being
removed and the tab closing, so the recursive walkers tolerate it. What is new
is staying empty. A test that builds a tmux tab with an empty tree and floats,
then calls each public PTYTab method, should be part of this work.

**Code outside PTYTab.m that reads the tree.** An audit of the callers of
PTYTab's tree, size and layout methods, and of the tmux parse-tree consumers.
Each item is something an empty tiled tree breaks or that must learn about
floats.

Sizes, where a zero from one tab spreads:

- `tmuxCompatibleSize` (PseudoTerminal.m:3978) takes the minimum of every
  tmux tab's `tmuxSize`. One floats-only tab reporting 0 makes the whole
  window's size 0. It feeds `setClientSize:` (PseudoTerminal.m:5266,
  TmuxController.m:1036).
- `tmuxSize` is also read at TmuxController.m:1058, 1069, 1090 and 1113 and
  sent to the server at PseudoTerminal.m:7669. The guard at 1094 hides the
  zero by doing nothing, which is the freeze described above.
- `fitWindowToTab:` (PseudoTerminal.m:10638) fits the window to `[tab size]`.
  The window sizing helper reads `currentSize` and `minSize`
  (PseudoTerminal.m:11803, 11812), as do `minWidth` (12237) and
  `windowWillResize:toSize:` (5953). Those take a maximum, so a zero is
  harmless there, but they must see the float contribution to `minSize`.

Tab construction and layout:

- `openTabWithArrangement:` (PseudoTerminal.m:12259) returns nil when
  `sessionViews` is empty. It stays correct only if `sessionViews` includes
  floats.
- `parsedLayoutFromString:` (TmuxLayoutParser.m:96-120) already returns nil
  for the empty v1 layout, with a comment about tmux 3.8, and wraps a lone
  leaf in a root splitter. The JSON parser must produce a root splitter with
  no children for a floats-only window.
- `TmuxWindowOpener` builds its per-pane requests with
  `depthFirstSearchParseTree:` (TmuxWindowOpener.m:112, 663) and its pane
  list with `windowPanesInParseTree:` (170, 607). Both must cover floats, or
  floats get no history and no state.
- `positionForWindowWithPanes:windowID:` (TmuxController.m:2915) restores a
  window's position by looking up its pane IDs. A floats-only window has no
  tiled pane IDs, so floats must be in the list.
- `didLearnLayout:forWindow:` (TmuxController.m:959), already listed in
  section 12.4.

API and scripting:

- `rootSplitTreeNode` (iTermAPIHelper.m:2403) sends a root with no links for
  a floats-only tab. The Python client builds an empty `Splitter`, so
  `Tab.sessions` is an empty list and scripts that index it raise.
- `apply_layout` already refuses tmux tabs (iTermLayoutResolver.swift:124),
  so the empty tree never reaches it.
- On a floats-only tab an empty `SetTabLayout` request passes the tree-shape
  check and sends a size and a layout built from an empty node
  (PTYTab.m:5104). What the layout builder produces for no children is
  unverified.

Not a problem, checked:

- `tab.sessions.firstObject.profile` (TmuxController.m:3889) and
  `[[tab sessions] objectAtIndex:0]` (MovePaneController.m:204,
  PseudoTerminal.m:4326) read `sessions`, which includes floats.
- cmd-opt-N (iTermApplication.m:465), the Cockpit and the AI chat mention
  picker read `orderedSessions`, which includes floats.
- `arrangeSplitPanesEvenly` and the split tree rebuilder act on the tiled
  tree and do nothing useful, but nothing harmful, when it is empty.

None of this is architectural once the container exists. The client-size and
tab-size items are the risky ones, because a mistake there affects every
window in the tmux session, not just the floats-only one.

### 12.6 Popups, modals and process-less panes

Decision: no popup-specific work. tmux removed popups and their overlay
machinery (commit 34cd5da4); `display-popup` remains as an undocumented
compatibility command that opens a modal floating pane. A modal float is
treated as an ordinary float, and the error tolerance from section 12.2 keeps
its failures from aborting the connection. The items below record what that
leaves imperfect. They are not planned work.

- **Races.** `display-popup -E true` opens and closes within milliseconds. The
  opener's queued commands fail, and iTerm2 reports "A tmux pane terminated
  immediately after creation" and drops the window's affinity
  (TmuxController.m:3947).
- **Tab identity.** `setActiveSession:` updates the tab and window title, the
  `tab.currentSession` variable and focus history, and closes Instant Replay on
  the previous pane. A popup becoming active makes the tab title flicker unless
  `set-titles` is on.
- **Profile side effects.** Popups use the shared tmux profile, so triggers,
  automatic profile switching, and bell and idle alerts apply. A font change
  from profile switching re-fonts every pane and refits the window.
- **Prompts.** A popup counts toward "confirm closing multiple sessions" and
  prompts on close under "prompt if jobs".
- **Modal detection.** iTerm2 learns that a window has a modal pane from the
  `O` window flag in `%layout-change`, and which pane from
  `#{window_modal_pane}` (section 12.1). `parseLayoutChangeCommand:`
  (TmuxGateway.m) reads only `Z` from the flags today.
- **Modal enforcement.** All input goes by pane ID and bypasses tmux's modal.
  iTerm2 must enforce it, or snap focus back. `setCurrentWindow`
  (TmuxController.m:4039) increments an ignore counter before `select-window`;
  if tmux refuses during a modal, the next real notification may be swallowed
  (unverified).
- **Dismissal.** A popup without `-E` leaves a dead pane waiting for a key.
  That dismissal is in tmux's client-key path, which `send-keys` bypasses.
  iTerm2 gets no notification that a pane died. Close with `kill-pane` or
  `display-popup -C`.
- **Process-less panes.** `new-pane -E` panes never send `%output`, and modes
  draw to a mode screen that `capture-pane` reads only with `-M`. They would
  render blank while keys still drive the mode. iTerm2 ignores
  `%pane-mode-changed` today, so tiled panes in copy mode already have this
  problem.
- **Monitors.** Each tmux session installs title, job and status-line
  monitors. Each popup adds pollers against a pane that may already be gone.
- **Bury.** `bury` on a tmux pane hides the whole tmux window. Disable it for
  floats.

### 12.7 Multiple clients

- A second control client that has not opted in gets v1 layouts without
  floats. It still receives `%output` for float pane IDs, which iTerm2 treats
  as dropped output.
- Layout format is per client; z-order and the active pane are per window.

## 13. Phased plan

Small, reviewable commits, each with tests. The steps order the work. The
feature is released as a whole, so no step has to be shippable on its own
except step 0.

0. **tmux fixes** from section 12.2. Independent; ship first.
1. **Metal spike** (throwaway). Confirms the in-window container. Includes
   the blur underlay check from section 4.1.
1a. **Test infrastructure.** Built before the feature so every later step can
   be checked without a person at the keyboard (section 14.1).
2. **Container refactor.** First, the tab container view for every tab
   (section 3.5), as its own commit with no floats. Then the float wrapper
   with its split view, `setRoot:` and `cleanupAfterRemove:` changes,
   `sessions` versus `tiledSessions` with the temporary rename, and the
   call-site classification. While classifying, mark each `tiledSessions`
   caller that cannot handle an empty list; those are fixed in step 10. Add
   tests for remove, maximize, enumeration and
   `replaceViewHierarchyWithParseTree:`; none exist today.
3. **Native float basics.** The menu items, sizing rules, title bar, outline,
   shadow, blur underlay, live move, edge resize, keyboard move and resize,
   raise on click, close, hide and show.
4. **Focus and mouse.** Occlusion-aware hit testing for focus-follows-mouse and
   hover, navigation order, numbering, maximize.
5. **Persistence.** Encoder, decoder, walkers, trust gate, partial attachment,
   undo close and bury, Duplicate Tab, with round-trip tests.
6. **Dragging.** Drag-out to tab bar, window and split with Control; then the
   floating drop target and spring-loaded tabs.
7. **Existing features.** Reveal, status bar, workgroup refusal, synthetic
   swaps, the rest of section 9, and from section 6.9 the split redirect,
   the swap rule, the resize gates and the focus rules.
8. **Automation.** Proto field, handlers, Python client, `it2`, AppleScript,
   built-in functions, and the consistency items in section 6.9.
9. **Remaining creation points** from section 6.1.
10. **tmux.** In this order:
    1. The JSON parser, with floats reaching every parse-tree consumer
       (section 12.5 audit).
    2. Opt-in and the server-owned geometry driver, with local cell
       alignment.
    3. Floats under zoom.
    4. Floats-only windows: tab and client size for an empty tree, then
       transitions, then the
       `tiledSessions` callers marked in step 2. The size work comes first
       because a zero from one tab reaches every window in the session.

Release notes go in docs/notes-3.7.txt per docs/release-notes-guidelines.md.

## 14. Verification

### 14.1 Test infrastructure

The feature is mostly about what the user sees and does with the mouse, and
neither unit tests nor the Python API cover that. These come first:

- **Window capture.** A debug-only way to capture the real, composited window
  to a PNG, Metal layers included, for example with ScreenCaptureKit. The
  Python API's screenshot renders one session's grid, not the window, and
  ordinary view snapshots omit Metal layers. The dev build needs Screen
  Recording permission once.
- **Event harness.** A helper in the test bundle that hosts a real terminal
  window and delivers synthesized mouse events to its views: down, dragged,
  up, moved, with modifiers. It covers live move, edge resize, click to
  raise, the title bar's double-click and the handoff to a pane drag.
- **Driving the dev instance.** The Python API can invoke menu items, send
  text and read layout and focus against the `-suite` instance. API
  connections from outside the app prompt for authorization, which must be
  pre-approved for the suite.
- **GUI automation of the dev instance.** For this project the author has
  permitted controlling the computer and using accessibility APIs, which the
  repository's general rules forbid. Real clicks and drags against the
  `-suite` instance cover what the in-process harness cannot: AppKit drag
  sessions between tabs and windows, and how the window server delivers
  pointer events to covered panes. Synthetic input must only ever go to the
  dev instance, never to the main iTerm2 where the tools run.
- **tmux.** tmux built from `~/git/tmux`, a plain second client run in a pty,
  and recorded control-mode transcripts fed to the parser and controller in
  unit tests.

Two constraints on the implementation follow from this:

- Float move and resize are written as mouse event handlers with explicit
  state, not as a modal `trackEventsMatchingMask:` loop, which a test cannot
  drive. This supersedes the "tracking loop" wording in section 7 and the
  appendix.
- Geometry lives in plain types with no views: clamping, cell snapping, edge
  anchoring, shrink-and-remember, minimum size, tmux cell alignment and
  promotion. They are unit-tested exhaustively.

What still needs a person: a final judgment on the Metal spike, since
flicker and lag in motion are hard to judge from captures; VoiceOver; and how
the feature feels.

### 14.2 Tests

- **Unit tests.** A tmux tab with an empty tiled tree and two floats, with
  every public PTYTab method called on it; `tmuxSize`, `size` and
  `tmuxCompatibleSize` for a window that mixes a floats-only tab with a
  normal one; the tree going empty and non-empty through
  `replaceViewHierarchyWithParseTree:`. PTYTab container operations (step
  2); arrangement round trips including old-format input; the trust gate with float sessions; the
  JSON layout parser against fixtures from `regress/layout-custom.sh` (tiled
  only matches v1, mixed, floats only, one tiled child plus floats, nested
  float-only nodes, negative offsets, malformed input).
- **Manual, native.** Create, move, resize, hide, dock and close floats;
  relaunch and upgrade with floats running jobs; Duplicate Tab; window resize,
  full screen and font changes; every drag in section 7; maximize; Global
  Search into a covered or hidden float.
- **Manual, tmux.** Build tmux from `~/git/tmux` and run `tmux -CC` with a
  second plain client: `new-pane` variants, `display-popup`, `break-pane -W`
  and `join-pane`, zoom with and without `-A`, modal `-O`, killing the last
  tiled pane, detach and reattach, and window resize. Add the recipe to
  tests/tmux_layout_smoke.md.
- **Regression.** tmux 3.7 and older must still get v1 layouts.

## Appendix: reuse candidates, checked against the code

| Need | Candidate | What it actually offers |
| --- | --- | --- |
| Move loop | Minimal composer (iTermMinimalComposerViewController.m:77-112) | A real `trackEventsMatchingMask:` loop, but vertical only and clamped to the superview. A pattern, not reusable code. |
| Edge resize | Split divider drag (PTYSplitView.m:144) | It defers to NSSplitView, which owns the tracking loop and cursor rects. Only the cell quantization idea (PTYTab.m:6967) carries over. |
| Grab handle | SessionTitleView.m:377 | `mouseDragged:` starts the pasteboard drag immediately. It needs a live-move mode. |
| Dock and drag-out | MovePaneController | Suitable. It has no notion of geometry, so "float here" needs a new drop target. |
| Title bar | SessionTitleView | Close, menu and lock buttons, pane number, dimming, double-click and per-pane status bar hosting. Reused as is, apart from the drag and the menu. |
| Border | iTermActivePaneBorderView | Active session only, inside the scroll view. Not a drop-in. The wrapper draws the float's outline instead. |
| Blur underlay | Hover URL view (SessionView.m:79-88) | A within-window `NSVisualEffectView` over terminal content. A pattern to copy. |
| Shadow | ContentNavigationShortcut.swift:89-92 | Four layer shadow properties. Trivial to copy. |
| Synthetic swap state | `replaceActiveSessionWithSyntheticSession:` | Works unchanged inside a per-float split view. |
| Legacy-renderer fallback | Browser panes in `metalAllowed:` | Precedent for forcing a whole tab to the legacy renderer. |
