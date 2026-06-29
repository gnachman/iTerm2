# Session Restoration and Process Reattachment

This document explains how iTerm2 restores windows at launch and reconnects
restored sessions to the long-running child processes that survived across the
relaunch. The central mechanism is the *partial attachment*, which talks to the
multiserver daemon and obtains the surviving children's job managers up front,
before any session object exists.

## The problem

When iTerm2 quits and relaunches, the shells and programs it was running can
survive because they are owned by a separate daemon (the "multiserver"), not by
the iTerm2 process itself. On the next launch, iTerm2 wants to:

1. Recreate the windows, tabs, and split panes from the saved arrangement.
2. For each restored session, reconnect to its surviving process if it is still
   alive, or launch a fresh process if it is not.

Reconnecting requires contacting the daemon to learn which children are still
alive and to obtain a job manager for each. This has to happen *before* a
session's `PTYTask` can be created, because the restored session is then married
to the job manager the daemon handed back. So the daemon contact is necessarily
a prerequisite of building the sessions, not something done per-session as each
one is created.

The original implementation did this contact **synchronously**, blocking window
restoration on it. The problem (per commit `3dd3c5672`, "Implement partial
attachment"): "we used to block on attaching to the daemon. If the daemon is not
feeling well, it can take forever." A wedged or unhealthy daemon could hang the
entire restore. The partial-attachment design moves that contact out in front,
makes it asynchronous, and bounds it with a timeout: if the children do not come
back in time, restoration proceeds anyway and the stragglers are adopted as
orphans (commit `6692315a2`, "Restore children as orphans if it takes too long
to get them from the daemon").

## The two-phase attach

Attaching a session to a surviving process is split into two halves:

| Phase | When | What it does | Needs a `PTYSession`? |
|-------|------|--------------|-----------------------|
| **Partial attach** | Before any session exists | Connect to the daemon, ask whether the child PID is still alive, keep the connection and the answer | No |
| **Finish attach** | After the session is created | Register the process with the task system and wire up its file descriptors to the new session | Yes |

The split exists because the partial attach can be done *before* a `PTYSession`
exists, while the finish attach cannot (it needs the session's task to register
the process and wire up its file descriptors). Doing the daemon contact first,
asynchronously and under a timeout, means a slow or unhealthy daemon cannot hang
window restoration: it either completes in time or the children are adopted as
orphans.

### `iTermPartialAttachment`

The result of a partial attach is parked in an `iTermPartialAttachment`, a small
container holding everything the finish phase will need:

```objc
@protocol iTermPartialAttachment
@property (nonatomic, strong) id<iTermJobManagerPartialResult> partialResult;
@property (nonatomic, strong) id<iTermJobManager> jobManager;
@property (nonatomic, strong) dispatch_queue_t queue;
@end
```

- `jobManager` + `queue` - the live `iTermMultiServerJobManager` and its serial
  queue: the established connection to the daemon for that child.
- `partialResult` (an `iTermMultiServerJobManagerPartialAttachment`) - the facts
  learned by reaching the daemon: `attached` (did the child exist),
  `shouldRegister` (exists and has not terminated), `pid`, and a `brokenPipe`
  flag.

`iTermPartialAttachment` is **not** related to screen-content attachments
(images, URLs, ScreenChar arrays). It is purely about process reattachment.

**Key files:** `sources/Tasks/PTYTask.h` (protocol),
`sources/PTYSession/PTYSession+ARC.m` (implementation and creation),
`sources/Tasks/iTermMultiServerJobManager.m` (`partialResult` implementation,
`asyncPartialAttachToServer:`, `finishAttaching:task:`).

## The restoration flow

The window appears on screen **before** its sessions exist. Session objects are
not created until after the partial-attachment phase resolves, so by the time a
session exists, the attach-vs-launch decision is already determinate.

```
1. App launches.

2. bareTerminalWithArrangement:    ← empty window/frame, no tabs/panes/sessions.
   The window is handed back to AppKit here and becomes visible.

3. openPartialAttachmentsForArrangement:timeout:completion:
   Walks the arrangement DICTIONARIES only (no UI, no sessions). For each leaf
   session dict that has a SESSION_ARRANGEMENT_SERVER_DICT, kicks off an async
   partial attach to the daemon. Collects results into:
       { serverDict -> iTermPartialAttachment }

4. Wait for the daemon: all partial attaches complete, OR a timeout fires
   (advanced setting timeoutForDaemonAttachment, default 10 seconds).

5. completion(partialAttachments) -> loadArrangement:...partialAttachments:
   NOW the real UI and sessions are built, per tab:
     - tabWithArrangement: -> _recursiveRestoreSplitters: builds the skeleton
       of splitters and SessionViews (still no PTYSessions).
     - _recursiveRestoreSessions: -> sessionFromArrangement:...partialAttachments:
       instantiates each PTYSession into that skeleton and, on the spot, either
       finishes its partial attachment or launches a fresh process.
```

### Step 2: the window is created empty

`+[PseudoTerminal bareTerminalWithArrangement:forceOpeningHotKeyWindow:restoring:]`
lives up to its name: it builds the window/frame, geometry, and hotkey setup but
creates **zero** `PTYSession` objects. There are two callers:

- `PseudoTerminalRestorer.m` - the window-restoration entry point
  (`restoring:YES`). It builds the bare window and returns it through the
  restoration `completionHandler`, after which `asyncRestoreState:` drives the
  async partial-attachment phase. This is the path described here. (How this
  entry point is reached, and how it relates to Cocoa's own restoration, is
  covered in "Relationship to macOS state restoration" below.)
- `+[PseudoTerminal terminalWithArrangement:named:sessions:forceOpeningHotKeyWindow:]`
  (`restoring:NO`) - the synchronous "open a saved arrangement" path. It calls
  `loadArrangement:...partialAttachments:nil...` immediately, with no partial
  attachments (see "The synchronous path" below).

### Step 3: partial attachment walks dictionaries only

`openPartialAttachmentsForArrangement:` recurses through the saved arrangement as
plain dictionaries. `PTYTab`'s `_recursiveOpenPartialAttachments:` descends
`VIEW_TYPE_SPLITTER` -> `SUBVIEWS` and, at each leaf, calls
`+[PTYSession openPartialAttachmentsForArrangement:completion:]`, which extracts
the server dict, creates an `iTermMultiServerJobManager`, and calls
`asyncPartialAttachToServer:withProcessID:completion:`. **No view objects, tabs,
split panes, or sessions are created in this phase** - it produces only the
`{ serverDict -> iTermPartialAttachment }` dictionary.

The multiserver connection itself is established lazily here, on demand, via
`iTermMultiServerConnection.getOrCreatePrimaryConnectionWithCallback:`. The app
does not block on the daemon at launch; "before the daemon is connected to" is
the normal starting state of restoration, and this phase is exactly the
machinery that connects to it while the window is already up.

### Step 4: the timeout race

`-[PseudoTerminal openPartialAttachmentsForArrangement:timeout:completion:]`
races two things and calls back exactly once (guarded by a `haveNotified` flag):

- a `dispatch_group_notify` that fires when **all** tabs' partial attachments
  return, and
- a `dispatch_after` set to `iTermAdvancedSettingsModel.timeoutForDaemonAttachment`
  (default **10 seconds**).

Whichever wins calls `completion(result)` with whatever partial attachments
arrived so far. Any results that arrive **after** the timeout are routed to the
`timeout` block instead, which hands them to
`iTermOrphanServerAdopter.adoptPartialAttachments:`. Those late arrivals are
adopted into a new session rather than retrofitted onto the already-restored
session (see "Orphan adoption" below).

### Step 5: sessions are created, then attached or launched

Session creation happens inside the `completion` block, so `sessionFromArrangement:`
always runs with the partial-attachment dictionary already in hand. After it
computes `didAttach`:

- **`didAttach == YES`** (the session's `serverDict` was found and
  `tryToFinishAttachingToMultiserverWithPartialAttachment:` succeeded):
  `runCommand = NO`, and `startProgram:` is **never called**. The session adopts
  the surviving daemon child. The finish phase runs
  `iTermMultiServerJobManager.finishAttaching:task:`, which registers the process
  and wires up its file descriptors.
- **`didAttach == NO`** (no entry for this session, e.g. the daemon was too slow
  and the timeout fired): `runCommand` stays YES and `runCommandBlock(finish)`
  runs right there, building an `iTermSessionAttachOrLaunchRequest` and calling
  `[factory attachOrLaunchWithRequest:]`, which lands in
  `startProgramForRequest:` -> `startProgram:` and launches a fresh process.

There is no third "session exists but is parked waiting for a future attachment"
state. `PTYSession` does **not** defer `startProgram:`; the deferral is achieved
by not creating the session until the attach decision can be made synchronously.
`iTermSessionFactory.handleRealizedRequest:` has exactly three branches, all
synchronous: attach-to-server, finish-partial-attachment, or
`startProgramForRequest:`.

**Key files:** `sources/TerminalView/PseudoTerminal.m`
(`asyncRestoreArrangement:`, `openPartialAttachmentsForArrangement:timeout:completion:`,
`loadArrangement:`), `sources/TerminalView/PTYTab.m`
(`_recursiveOpenPartialAttachments:`, `tabWithArrangement:`,
`_recursiveRestoreSplitters:`, `_recursiveRestoreSessions:`),
`sources/PTYSession/PTYSession.m` (`sessionFromArrangement:`,
`tryToFinishAttachingToMultiserverWithPartialAttachment:`),
`sources/PTYSession/PTYSession+ARC.m`
(`+openPartialAttachmentsForArrangement:completion:`),
`sources/AppKit/iTermApplicationDelegate.m` (drives `asyncRestoreState:`),
`sources/Tasks/iTermOrphanServerAdopter.m` (late arrivals).

## Relationship to macOS state restoration

Everything above is the *session/process* layer. Sitting above it is the
question of who decides to restore a window in the first place. iTerm2 registers
with Cocoa's `NSWindowRestoration` machinery but, in its default configuration,
largely supplants it with its own controller. The OS's role is reduced to a GUID
handshake.

### Registration and encoding

Every terminal window opts into restoration and names `PseudoTerminalRestorer` as
its restoration class:

```objc
[[self window] setRestorable:YES];
[[self window] setRestorationClass:[PseudoTerminalRestorer class]];
```

On the encode side, `-[PseudoTerminal window:willEncodeRestorableState:]` runs
when macOS asks a window to serialize itself. With `storeStateInSqlite` (the
default) it writes only the window's GUID into the system coder
(`iTermWindowStateKeyGUID`) and keeps the real arrangement in iTerm2's own
database. Otherwise it stores the full arrangement into the coder under
`kTerminalWindowStateRestorationWindowArrangementKey` ("ptyarrangement", in
`iTermWindowImpl.m`'s `encodeRestorableStateWithCoder:`).

### Two restoration systems

- **macOS `NSWindowRestoration`** - at launch the system calls
  `+[PseudoTerminalRestorer restoreWindowWithIdentifier:state:completionHandler:]`
  for each window it remembers. That forwards internally to
  `...pseudoTerminalState:system:completionHandler:` with `system:YES`.
- **`iTermRestorableStateController`** - iTerm2's own SQLite-backed controller,
  on by default (`useRestorableStateController`). It holds the actual window
  state, including large scrollback via a `largeContentProvider`, and is what
  drives the async partial-attachment flow.

### How the system path is intercepted

At startup iTerm2 sets `ignoreSystemWindowRestoration` to mirror
`useRestorableStateController` (`iTermApplicationDelegate.m`). So when macOS calls
the restorer with `system:YES`, `PseudoTerminalRestorer` does **not** build a
window. It decodes the window GUID from the coder, parks macOS's
`completionHandler` in the controller keyed by that GUID
(`setSystemRestorationCallback:windowIdentifier:`), and returns
(`PseudoTerminalRestorer.m:154-169`). The system thus never restores a window
itself; it only hands iTerm2 a callback that must eventually be satisfied.

### How iTerm2 drives the real restoration

iTerm2's controller restores from its database and, per window, calls the same
restorer with `system:NO` (`iTermApplicationDelegate.m`). The `system:NO` call
skips the ignore short-circuit and runs the normal machinery: queue a block,
build a bare window, return it through the `completionHandler` early, then run
`asyncRestoreState:` for the slow daemon attach. As each window is produced, the
controller marries it to the parked macOS callback
(`iTermRestorableStateController.restoreWithSystemCallbacks:`) and invokes that
callback with the restored window, so the OS considers its restoration satisfied.
Any parked callbacks with no matching restored window are invoked with `nil`
(failure) via `invokeRemainingCompletionBlocksAsFailure`, so the OS is never left
waiting.

The net effect: macOS's coder-based restoration is reduced to a GUID handshake.
The GUID round-trips through the system coder so iTerm2 can match a system
callback to a window it restores from its own database; everything substantive
(the arrangement, the contents, the daemon reattachment) comes from iTerm2's
controller, not the `NSCoder`.

### Why calling the completion block correctly matters

Satisfying the `completionHandler(window, error)` is not just bookkeeping to
unblock the OS. The window object handed to that block is what macOS uses to
place the window: it puts it on the **Space** it was restored from and restores
its **fullscreen** state. If the block is never called, called with `nil`, or
called with the window before it is in the right state, the OS cannot do that
placement. So it is important to always call it, with the real restored window.

This is why fullscreen windows are a special case. For a non-fullscreen window
the restorer calls `completionHandler([term window], nil)` immediately. For a
window restoring into Lion fullscreen (`togglingLionFullScreen`), it instead
**defers** the call: it sets `gWaitingForFullScreen`, retains the handler, and
installs a `didEnterLionFullscreen` callback that calls
`completionHandler([theTerm window], nil)` only after the fullscreen transition
finishes, then resumes draining queued blocks (`PseudoTerminalRestorer.m:268-288`).
That ordering lets macOS see a window already in its fullscreen state and place
it on the correct Space.

### Batching and not blocking the OS

`PseudoTerminalRestorer` queues each window-creation block (`queuedBlocks`) and
drains them with `runQueuedBlocks`, pausing while a fullscreen transition is in
flight (`gWaitingForFullScreen`, as above). A post-restoration completion block
runs only once both the queued window blocks have all run and external
restoration has finished (`gExternalRestorationDidComplete` /
`runPostRestorationBlockIfNeeded`); that block restores buried sessions and kicks
off the orphan-server sweep (see "Orphan adoption"). Returning the window through
the `completionHandler` (early for normal windows, post-transition for fullscreen
ones) and doing the daemon attach asynchronously afterward is what keeps the slow
work from blocking the OS's restoration machinery.

### Precedence and opt-outs

Before any of the above, the restorer bails early in several cases
(`PseudoTerminalRestorer.m:138-204`):

- compare-rendering mode, the AppleScript test-app build, and unit tests complete
  with a `nil` window.
- `kPreferenceKeyOpenArrangementAtStartup`: restoration is aborted (complete
  `nil`), the arrangement's sessions are registered, and the saved default
  arrangement is opened instead (`iTermController.loadWindowArrangementWithName:`).
  The startup arrangement wins over restoration.
- `kPreferenceKeyOpenNoWindowsAtStartup`: abort and open nothing.

Above all of this, the OS-level "Close windows when quitting an app"
(`NSQuitAlwaysKeepsWindows`) still governs whether macOS attempts restoration at
all.

**Key files:** `sources/TerminalView/PseudoTerminalRestorer.m`
(`restoreWindowWithIdentifier:...system:completionHandler:`, `queuedBlocks`,
`runQueuedBlocks`, `runPostRestorationBlockIfNeeded`),
`sources/StateRestoration/iTermRestorableStateController.m`
(`setSystemRestorationCallback:windowIdentifier:`, `restoreWithSystemCallbacks:`,
`invokeRemainingCompletionBlocksAsFailure`),
`sources/TerminalView/PseudoTerminal.m` (`setRestorationClass:`,
`window:willEncodeRestorableState:`), `sources/TerminalView/iTermWindowImpl.m`
(`encodeRestorableStateWithCoder:`),
`sources/AppKit/iTermApplicationDelegate.m` (sets `ignoreSystemWindowRestoration`,
calls the restorer with `system:NO`, sets the post-restoration block).

## The `partialAttachments:nil` path is not daemon reconnection

`loadArrangement:` can also be called with `partialAttachments:nil`, via
`+[PseudoTerminal terminalWithArrangement:named:sessions:forceOpeningHotKeyWindow:]`.
It is tempting to think of this as "the synchronous restore path," but it is
**not** used for launch-time reconnection to surviving daemon children, and in
practice it does not marry a session to a preexisting process. Its callers are:

- **Undo close window/session** (`iTermApplicationDelegate.m`) - passes the
  closed window's *revived in-memory* `PTYSession` objects. The processes were
  terminated when the session closed.
- **Hotkey windows** (`iTermProfileHotKey.m`).
- **Loading a saved arrangement** from the menu (`iTermController.m`) - the
  arrangement was serialized to disk in an earlier run, so any daemon children
  it references are long gone.

In all of these, the `SESSION_ARRANGEMENT_SERVER_DICT` restoration identifiers do
not point at live daemon children, so the synchronous
`tryToAttachToMultiserverWithRestorationIdentifier:` attach fails and the session
relaunches (or is revived in-memory) instead of reconnecting. Launch-time
reconnection to a surviving process happens **only** through the partial-
attachment path; there is no synchronous reconnect path exercised during real
window restoration. (`-[PseudoTerminal restoreState:]`, which would call
`loadArrangement:...partialAttachments:nil`, has no callers and is dead.)

It is worth knowing that the job manager does expose a synchronous attach,
`attachToServer:withProcessID:task:`, but it merely wraps the same async partial
attach in a `dispatch_group_wait(..., DISPATCH_TIME_FOREVER)`. That blocking
behavior is exactly the "if the daemon is not feeling well, it can take forever"
hazard that the partial-attachment design was introduced to remove, which is why
the launch path no longer uses it.

Note also the subtle asymmetry within `sessionFromArrangement:`: the synchronous
attach branch only runs when `partialAttachments` is **entirely nil**. After a
timeout in the async path the dictionary is non-nil but missing the slow session,
so that session relaunches a fresh process rather than attempting a synchronous
attach.

## Orphan adoption

A surviving daemon child is *orphaned* when it is not claimed by any restored
session. Rather than leave such a process running with no window attached to it,
iTerm2 adopts it into a freshly created session so the user can get back to it.
There are two distinct paths into adoption, both handled by
`iTermOrphanServerAdopter` and both funneling through the same delegate hooks on
`iTermApplicationDelegate`.

### Path 1: late partial attachments (the restore timeout fallback)

This is the tail end of the flow described above. When the per-window restore
times out, any partial attachments that arrive *after* the deadline are routed
to the `timeout` block, which calls
`iTermOrphanServerAdopter.adoptPartialAttachments:`
(`iTermApplicationDelegate.m`, the `asyncRestoreState:timeout:` call site). Each
late `iTermPartialAttachment` is opened as a session via
`orphanServerAdopterOpenSessionForPartialAttachment:inWindow:`. The child is
real and its connection is already established; it simply missed the window that
was meant to host it, so it lands in an adopted session instead of its original
place in the arrangement.

### Path 2: the filesystem sweep for fully-orphaned servers

This catches processes whose owning session was never restored at all, for any
reason: the window was closed without saving, iTerm2 crashed, the arrangement
did not include the session, or a daemon outlived the app entirely.

At construction, `iTermOrphanServerAdopter` asynchronously scans the filesystem
for live server sockets:

- **Mono-servers** (the legacy one-process-per-server model) -
  `iTermOrphanServerAdopterFindMonoServers` looks in the file-descriptor
  directory for sockets matching the socket-name prefix.
- **Multi-servers** (the daemon model) -
  `iTermOrphanServerAdopterFindMultiServers` looks in Application Support for
  `iterm2-daemon-*.socket` (plus a transitional legacy glob).

After window restoration finishes, the post-restoration completion block calls
`openWindowWithOrphansWithCompletion:` (`iTermApplicationDelegate.m`). It waits
until either all window decodes are done (`numberOfDecodesPending == 0`) or the
`iTermDidDecodeWindowRestorableStateNotification` fires, so adoption never races
ahead of normal restoration and steals a child a window was about to claim. It
then connects to each discovered server and, for multi-servers, adopts the
connection's **`unattachedChildren`** - exactly the children no restored session
attached to - via `orphanServerAdopterOpenSessionForConnection:inWindow:`.

### What an adopted session looks like

Both paths open the process as a **new tab** under a default (`nil`) profile
through `iTermSessionLauncher` (`makeKey:NO`, `canActivate:NO`, so adoption is
non-intrusive), and then call `-[PTYSession showOrphanAnnouncement]` to tell the
user the session was adopted. An adopted session is **not** a restored session:
it reconnects to the live process but does not recover the arrangement's visual
state (scrollback contents, name, split-pane geometry), because that state lived
in the arrangement that timed out or was never saved.

The first adopted session creates a window (`iTermController.terminalWithSession:`)
and every later adoption joins that same `_window`, so all orphans from a launch
collect into one window rather than scattering.

**Key files:** `sources/Tasks/iTermOrphanServerAdopter.m`
(`adoptPartialAttachments:`, `openWindowWithOrphansWithCompletion:`,
`adoptMonoServerOrphanWithPath:`, `enqueueAdoptionsOfMultiServerOrphansWithPath:`,
`didEstablishMultiserverConnection:`), `sources/AppKit/iTermApplicationDelegate.m`
(`orphanServerAdopterOpenSessionForConnection:inWindow:completion:`,
`orphanServerAdopterOpenSessionForPartialAttachment:inWindow:completion:`, and
the post-restoration completion block that triggers the sweep).

## Is the partial attachment necessary?

For launch-time restoration, yes: reconnecting a restored `PTYSession` to a
surviving daemon child happens **only** through the partial-attachment path.
There is no synchronous path that does this during real window restoration (see
the section above), so this is not merely a faster way of doing something the
synchronous code also does.

What is genuinely optional is the *asynchronous, timed-out* shape of that path
rather than the reconnection itself. The job manager still contains a synchronous
attach that blocks on the daemon with `DISPATCH_TIME_FOREVER`; the old code used
it, and it would reconnect too - but it hangs window restoration whenever the
daemon is unhealthy. The partial-attachment design exists to get that
reconnection without the hang: do the daemon contact up front, asynchronously,
under a timeout, and fall back to orphan adoption when the children do not arrive
in time. That motivation is stated directly in commit `3dd3c5672`: blocking on
the daemon meant that "if the daemon is not feeling well, it can take forever."

So the honest framing is: the daemon contact must precede session creation (a
structural requirement), and doing it asynchronously under a timeout is what
keeps a sick daemon from wedging the launch - not a throughput optimization.

## Summary

| Question | Answer |
|----------|--------|
| Can a window be restored before the daemon is connected? | Yes, by design. The window appears empty first; the daemon connection happens during the partial-attachment phase. |
| When are session objects created? | After the partial-attachment phase resolves (or times out), inside `loadArrangement:`. Never at window creation. |
| Does `PTYSession` defer `startProgram:`? | No. Session creation itself is deferred; once a session exists, it attaches or launches synchronously. |
| What if the daemon is slower than the timeout? | The affected session relaunches a fresh process; the surviving process is later adopted into a separate orphan window. |
| Is `iTermPartialAttachment` necessary? | At launch, yes: it is the only path that reconnects a restored session to a surviving daemon child. What is optional is its async/timeout shape, which exists to keep an unhealthy daemon from hanging restoration. The synchronous `partialAttachments:nil` path is not used for launch reconnection and does not bind to a live process. |
| How does this interact with macOS state restoration? | iTerm2 registers `PseudoTerminalRestorer` as the windows' `NSWindowRestoration` class but, by default, intercepts the system path (`ignoreSystemWindowRestoration`) and parks the OS's callback. Its own SQLite-backed controller restores from its database, builds the windows, and satisfies the parked callbacks. The OS's coder role shrinks to a GUID handshake. |
