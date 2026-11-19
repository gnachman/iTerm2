# Lifetimes and reference cycles

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Two opposite failures: an object that never dies (a cycle, or a longer-lived
capture), and an object that dies sooner than before.

- **Ownership graph in the dossier.** Every strong reference in and out, every
  back-pointer, every block stored by the object or by something it owns.
- **Capture semantics are ported exactly.** A block that captured `self`
  strongly becomes a closure that captures `self` strongly, with a comment if
  that looks like a cycle. A `__weak` capture becomes `[weak self]`. Changing
  a capture is a `fix` commit, because it changes lifetime. Never use
  `unowned`.
- **Back-pointers.** `weak` stays `weak`. An `assign` or
  `__unsafe_unretained` object reference is changed to `weak` in
  Objective-C, in its own `fix` commit with a lifetime test, before the
  state of its class moves to Swift ([arc.md](arc.md)). `unowned` and
  `unowned(unsafe)` stay banned in migration Swift
  ([phase0.md §6](phase0.md)), so `weak` is the only form such a reference
  can take there. The test is for the one known behavior difference: while
  an object is being deallocated, a `weak` reference to it already reads
  nil, where an `assign` reference still pointed at it, so a message sent
  through the reference during the target's teardown is no longer
  delivered.
- **Timers, observers, and display links** retain their targets or blocks. The
  dossier lists each with where it is invalidated.
- **Lifetime witness tests.** For each class with meaningful teardown, a test
  that creates it, exercises it, drops it, and asserts that a weak reference
  becomes nil. For sessions, tabs, and windows, the test goes through the real
  close path.
- **Instance census.** A debug-only count of live instances per class (a
  Phase 0 tool; it must not use associated objects). The scripted workload in
  [phase0.md §8](phase0.md) opens and closes windows, tabs, and sessions, then compares
  counts with the baseline. A class whose count grows after a port has a leak.
- **Earlier death.** Moving from autorelease to ARC, and from Objective-C to
  Swift, tends to release objects sooner. The danger is a remaining unretained
  reference to the object. The `arc` step's inner-pointer audit and the
  sanitizer runs (address sanitizer on the suite, periodically) are the checks.
- **`deinit` side effects.** If `dealloc` did visible work, the witness test
  asserts that work happens, and at the same point relative to the close.

## Where the Phase 0 tools are

- The instance census is `ModernTests/InstanceCensus.swift`, tested by
  `InstanceCensusTests`. It counts live instances of chosen classes in the
  test host, not in the running app.
- The lifetime witness tests for sessions, tabs and windows are
  `SessionLifetimeWitnessTests`, `TabLifetimeWitnessTests` and
  `WindowLifetimeWitnessTests`, in `ModernTests/LifetimeWitnessTests.swift`.

Not covered by them yet:

- The side effects of `-[PseudoTerminal dealloc]`: terminating the sessions
  of tabs still in the window, and clearing
  `iTermController.currentTerminal` if it is the window being freed.
- tmux client sessions and buried sessions, which other paths keep alive by
  design.
- The census in the running app for the scripted workload of
  [phase0.md §8](phase0.md). That is tracked under the performance and
  memory baselines item of the Phase 0 checklist.

## Open question: a session closed before its first Metal frames

Found by reading and by timing experiments, not proven by a retain trace.

- `-[PTYSession renderMetalFramesAndShowMetalView:]` passes
  `-[iTermMetalDriver drawAsynchronouslyInView:completion:]` a completion
  block that reads `_useMetal` and `_exited`, so the block retains the
  session. The driver keeps the block in a `dispatch_group_notify` until the
  frame's group completes.
- So a session closed before its first asynchronous Metal frames complete
  stays alive until they do. The first Metal frame in a process is slow:
  about 2 seconds on an idle machine, and 11 seconds once under the thread
  sanitizer on a loaded machine.
- The experiments: closing a split pane 4 seconds after it was made freed
  the session 0.1 seconds after the close. With GPU rendering turned off
  (`kPreferenceKeyUseMetal`), the first close in a process freed the session
  in 0.016 seconds; with it on, in 1.4 seconds.
- `LifetimeWitnessSupport.warmUpOnce` absorbs this once per test process,
  so the witness tests do not depend on it.
- A port of either method must keep this lifetime or change it deliberately,
  in its own `fix` commit.
