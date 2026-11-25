# Manual reference counting to ARC

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

210 files are compiled without ARC. Swift cannot express manual reference
counting, so every one of them moves to ARC as its own `arc` commit before it
is ported. This is one of the riskiest steps in the process because it changes
when objects die without changing any visible logic.

Procedure for one file:

1. **Lifetime witnesses first** (`test` commit). For the class in the file and
   for each object it owns that has an observable teardown, a test that the
   object deallocates when expected, using a weak reference and an explicit
   autorelease pool. For top-level objects (session, tab, window) these tests
   belong in Phase 0.
2. **Ownership table.** For every ivar and property: who retains it, who
   releases it, and whether the existing code is balanced. Imbalances are
   existing bugs (leaks or over-releases). A leak that the code depends on, in
   the sense that fixing it causes an earlier dealloc, must be preserved under
   ARC with an explicit strong reference and a comment, then logged as a bug.
3. **`dealloc` audit.** A manual `dealloc` releases in a written order and
   often does real work between releases (`PTYSession`'s posts a notification,
   removes an observer, clears delegates, stops logging). Under ARC, ivars are
   released after the `dealloc` body, in declaration order. Anything whose
   teardown order matters must be made explicit: set the ivar to nil at the
   right point in `dealloc`.
4. **Property and ivar semantics.**
   - `assign` or `__unsafe_unretained` object references stay
     `__unsafe_unretained` in this commit. Changing them to `weak` is a
     behavior change (a dangling pointer becomes nil) and is done separately,
     with the knowledge that code may have been reading a stale pointer. It
     is done in a `fix` commit with a lifetime test, before the class's
     state moves to Swift ([lifetimes.md](lifetimes.md)).
   - `retain` becomes `strong`, `copy` stays `copy`.
   - Bare ivars become strong. Any ivar that was deliberately not retained must
     be marked `__unsafe_unretained` or `__weak`.
5. **Core Foundation and `void *` crossings** get explicit `__bridge`,
   `__bridge_transfer`, or `__bridge_retained`. Each is a decision about
   ownership; record it in the commit message.
6. **Autorelease timing.** Under manual counting, an autoreleased object lives
   until the pool drains. Under ARC the optimizer often releases it at the end
   of the statement. Code that keeps an unretained pointer into an autoreleased
   object (the result of `UTF8String`, the `bytes` of an `NSData`, an inner
   pointer of any kind) can break. The dossier lists every inner pointer; each
   gets its owner held explicitly for the needed scope.
7. **Blocks.** Under manual counting `__block` variables are not retained and
   were used to avoid cycles; under ARC they are retained. Every `__block`
   object variable is re-examined and becomes `__weak` or
   `__unsafe_unretained` where it was avoiding a cycle.
8. **`[self retain]` / `[self autorelease]`** used to keep an object alive
   across a call that might release it: replace with a strong local, and make
   sure the extended lifetime is the same.
9. Move the file to `iTerm2SharedARC`, build, run the gate including the
   witnesses and the instance census ([lifetimes.md](lifetimes.md)). The
   move mode of `tools/swift_migration/pbxproj_swap.py` (`--m <path>.m
   --from-target iTerm2Shared --to-target iTerm2SharedARC`; its header is its
   manual) makes the project-file change.

Large files are not converted in one commit. `PTYSession.m` and
`PTYTextView.m` already show the pattern: an ARC category file
(`PTYSession+ARC.m`) receives methods moved a few at a time until the manual
file holds only ivars, `init` and `dealloc`.
