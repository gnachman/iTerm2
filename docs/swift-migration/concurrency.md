# Concurrency

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Concurrency bugs introduced by a port are the worst kind: they compile, pass
tests, and fail rarely on other people's machines. The approach is the same as
everywhere else in the process, applied strictly: in stage one the threading
model does not change, and wherever possible the port calls the **same
primitive** the Objective-C used, not an equivalent. The subtleties of a
primitive (re-entrancy, fairness, priority handling, behavior on misuse) are
then preserved without anyone needing to know all of them.

## 1. What is in the code

Counts for `sources/` and `ThirdParty/PSMTabBarControl`:

| Primitive | Objective-C and C | Swift |
|---|---|---|
| `@synchronized` (Swift: `objc_sync_enter`) | 262 in the whole scope of [README.md §2](README.md), 257 of them here (audited 2026-11-20) | 4, plus the helper `it_synchronized` |
| C atomics (`_Atomic`, `atomic_*`) | 139 | 1 |
| `volatile` | 8 | not applicable |
| `os_unfair_lock` (Swift includes `OSAllocatedUnfairLock`) | 64 | 25 |
| `pthread_mutex` and `pthread_rwlock` | 5 | 0 |
| `NSLock`, `NSRecursiveLock`, `NSCondition` | 11 | 24 |
| Dispatch semaphores | 33 | 8 |
| `dispatch_once` | 618 | none (not available in Swift) |
| `dispatch_sync` | 27 | about 164 |
| `dispatch_async` | 439 | about 301 |
| Private queues created | 36 | 37 |
| Dispatch groups and sources | 204 | 46 |
| `performSelector:...afterDelay:` and its cancel | 82 | 6 |
| Threads created or tested for main | 28 | 21 |
| `iTermGCD` assertions, mutation queue, joined threads | 232 | 11 |
| `iTermThread` and checked per-thread state | 102 | 0 |
| `__block` variables | 411 | not applicable |
| `@autoreleasepool` | 25 | 2 |
| Properties that are atomic, by default or explicitly | about 270 by default, 190 explicit | none (Swift has no atomic properties) |
| `await` | 0 | about 1,055 |
| `@MainActor` | 0 | about 714 |
| `MainActor.assumeIsolated` | 0 | about 100 |
| `Task` creation | 0 | about 262 |
| Actors | 0 | 8 |

Two things stand out. The Objective-C side has its own model for confining
state to threads (the main thread, the mutation queue, and joining the two),
with assertions. And the Swift side already uses Swift concurrency heavily, so
ported code will be called from actor-isolated Swift from its first day.

The test scheme already enables the undefined behavior sanitizer, and the app
scheme the address sanitizer. The thread sanitizer is not used when running
the app, because it reports a violation inside the Metal framework's own code
on every frame. It is fine for the tests, almost none of which touch Metal
(section 10).

## 2. `@synchronized`

Shape of the 262 code sites in scope, from the audit of 2026-11-20
(`git grep '@synchronized'` over the scope directories, less comments and
the macro's own string): 132 lock on `self` in an instance method, 6 on
`self` in a class method, 41 on a class object, 42 on an ivar, 10 on the
result of a call, 17 on a static or global, and 14 on a local or a
parameter. About half of the
blocks (119 of 252 examined) contain a `return`, `break`, `continue` or
`goto`, which leave the block and release the lock.

**Use the same primitive.** `@synchronized(x)` compiles to calls to
`objc_sync_enter(x)` and `objc_sync_exit(x)`. Swift can call those functions
directly. A test confirmed that a lock taken this way in Swift is recursive,
can be re-entered from an Objective-C `@synchronized` on the same object, and
excludes an Objective-C `@synchronized` on the same object held by another
thread. Whatever else that lock does (how it treats waiters of different
priority, what it costs when uncontended, how it finds the lock for an
object) is unchanged, because it is the same lock.

**Standard form in Swift:**

```swift
do {
    let lock: AnyObject = self          // evaluated once, as Objective-C does
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    // body, transliterated; return, break and continue work as before
}
```

This form is preferred over a helper that takes a closure, because half of
the existing blocks leave by `return`, `break` or `continue`. In a `do` scope
with `defer`, those statements mean what they meant in Objective-C and the
lock is released on every path. Inside a closure, `return` would return only
from the closure and `break` would not compile. A closure-taking helper is
acceptable for blocks with no control flow out of them. That helper is
`it_synchronized(lock) { ... }` in
`sources/Infrastructure/SwiftMigrationHelpers.swift` ([phase0.md §7](phase0.md)).
It calls the same two functions, with the exit in a `defer`. Its overload
that takes an optional lock fails a beta assertion when the lock is nil and
then runs the body with no lock, as `@synchronized(nil)` does.

**Rules**, each of which corresponds to a way this goes wrong:

- **Evaluate the lock expression once**, into a `let`. Objective-C does. If
  the expression is written twice (`objc_sync_enter(self.foo)` ...
  `objc_sync_exit(self.foo)`) and `foo` is reassigned inside the block, the
  exit unlocks a different object and the lock is never released.
- **The exit is in a `defer` on the line after the enter.** A lint checks the
  pairing: `sync-pairing` in `tools/swift_migration/swift_lints.py` requires
  the next line to be exactly `defer { objc_sync_exit(x) }` on the same
  constant, so the `defer` is written on one line. Code that uses
  `it_synchronized` has no `objc_sync_enter` of its own, so the lint has
  nothing to pair there.
- **The lock object must have a stable identity.** It must be a class
  instance, and the same instance every time. A Swift value used as a lock
  (an `Array`, `Dictionary`, `String`, or struct, converted with
  `as AnyObject`) is converted to an object at each use, and nothing
  guarantees it is the same object from one use to the next, particularly
  after the value has been mutated. The 41 blocks that lock on an ivar are the
  ones at risk: if `_items` is an `NSMutableArray` used as its own lock and
  the port turns it into a Swift array, the lock silently stops excluding
  anything. Rule: when an ivar is used as a lock, it stays a reference type
  with the same identity, or a dedicated lock object is introduced in a
  preparation commit while the code is still Objective-C. (A quick test did
  not demonstrate the failure, because freed objects were reallocated at the
  same address; the rule stands regardless.)
- **A nil lock locks nothing, and every port asserts it is not happening.**
  `@synchronized(nil)` runs the block with no lock and no error, so the code
  inside is silently unprotected. The port makes this impossible to miss:
  - The lock constant in the standard form is declared with the non-optional
    type `AnyObject`. If the lock expression cannot be nil (`self`, a class
    object, a `let` that is assigned once), that is the end of it, and the
    compiler enforces it.
  - If the expression is optional, or comes from an Objective-C declaration
    that is not yet proven `nonnull` ([nullability.md](nullability.md)), the port unwraps it and
    asserts:

    ```swift
    guard let lock: AnyObject = self.itemsLock else {
        it_betaAssert(false, "nil lock in MyClass.addItem; running unprotected")
        // The Objective-C ran the body with no lock. Reproduce that.
        return addItemUnlocked(item)
    }
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    ```

    The assertion follows [assertions.md](assertions.md): it crashes in nightly and beta builds
    and logs in release, where the code then does what the Objective-C did.
    Each such site is also entered in the bug ledger, because a lock that can
    be nil is a bug whether or not it has ever fired. Once a site has been
    through a beta cycle without firing and the nil path is understood, a
    `fix` commit removes the possibility.
  - A lint rejects passing an optional, an implicitly unwrapped value, or a
    forced unwrap to `objc_sync_enter`.
  - Of the 262 existing sites, 210 lock on `self`, a class object, a static
    or global, or a local or parameter, and are unlikely to be nil, though a
    local can be. The 42 that lock on an ivar and the 10 that lock on the
    result of a call are the ones to examine. They did not wait for the
    port: the macro `ITNonnilLock` in `sources/Logging/DebugLogging.h`
    wraps the lock expression, as in `@synchronized(ITNonnilLock(_lock))`.
    It evaluates the expression once, fails an `ITBetaAssert` if the result
    is nil, and yields that same object to lock. It is in place at the 50 of
    those sites that are in `sources/`, so nightly builds report nil locks
    now. The other two, ivar sites in `pidinfo/`, are not wrapped because
    that target has no beta assertion (owner queue Q18). Two sites among the
    rest whose lock can be nil are in [bugs.md](bugs.md).
  - A new `@synchronized` statement, by anyone and for any reason, locks on
    `self`, on a class object (`[Foo class]`, `Foo.class`, `[self class]`,
    `self.class`, `[Foo self]`), or on `ITNonnilLock(...)`. Statics,
    globals, locals and parameters are wrapped too: some can be nil, and
    wrapping is always harmless (decisions.md, 2026-11-20). The pre-commit
    hook enforces this on added and changed lines with
    `tools/check_nonnil_locks.py`, whose `--help` states the rule exactly,
    including the escape hatch `// nonnil-lock-ok: <reason>` for a lock
    that is meant to be nil. It checks Objective-C files under `sources/`,
    `ThirdParty/PSMTabBarControl/` and `ModernTests/`, except the files in
    `sources/` that are also compiled into `pidinfo` or
    `iTerm2SandboxedWorker`, which do not link the macro's assertion. The
    hook runs only in a checkout where `make install-hooks` has set
    `core.hooksPath`; the gate can run the same check on a range of commits
    with `tools/check_nonnil_locks.py --range A..B`. The existing unwrapped
    sites are reported only when their own lines change. On the whole tree
    (`--all`) it reports 30: 28 of the 31 statics, globals, locals and
    parameters above (the other 3 are in `pidinfo/` and `SignedArchive/`,
    which it does not check) and the two plain `@synchronized(object)`
    sites in `ModernTests/NonnilLockTests.m` that lock on nil deliberately.
- **Locks on a class object** (`@synchronized([Foo class])`) need the same
  class object from Swift: `Foo.self as AnyObject` for an `@objc` class. Check
  that it is the class and not the metaclass or a subclass (`[self class]` in
  a class method of a subclass is the subclass).
- **Exceptions.** Objective-C releases the lock if an `NSException` passes
  through the block. Swift cannot have exceptions pass through it at all
  ([translation-rules.md §3](translation-rules.md)). A block that relied on this goes through `ObjCTry` inside
  the lock.
- **Do not hold the lock across a suspension point.** No `await` between
  enter and exit, ever: the code may resume on a different thread, and this
  lock belongs to the thread that took it.
- **What is done while holding the lock does not change.** Calls out to
  delegates and callbacks made under the lock stay under the lock; calls made
  after releasing it stay after. Moving a callout across the boundary changes
  re-entrancy and deadlock behavior.
- **Replacing the primitive is a stage-two change.** `NSLock` and unfair locks
  are not recursive and will deadlock or trap where the old code re-entered.
  A dispatch queue used as a lock changes re-entrancy and priority behavior. A
  semaphore used as a lock has no owner, so the system cannot boost a
  low-priority holder that a high-priority thread is waiting for. Each
  replacement needs its own analysis and tests.

## 3. Atomic properties

Objective-C properties are atomic unless declared `nonatomic`. About 270 are
atomic by default and 190 more say so explicitly. The files with the most are
generated scripting headers, `PTYTask.h`, `iTermMetalFrameData.h`,
`iTermImageInfo.h`, and `VT100ScreenMutableState.h`.

What atomic provides: the getter and setter of an object property take an
internal lock, and the getter returns the object retained and autoreleased, so
a reader on one thread cannot be handed an object that a writer on another
thread is in the middle of releasing. A struct property is copied under a
lock. It provides nothing for compound operations (read, modify, write).

What Swift provides: nothing. A Swift property has no atomicity. A test
confirmed that a Swift `@objc var` appears in the generated header as
`nonatomic`. A strong reference read on one thread while another writes it is
a crash waiting to happen in Swift, as it is for a `nonatomic` property in
Objective-C.

So each atomic property is classified in the dossier:

- **Atomic by accident.** Someone omitted `nonatomic`. Every access is on one
  thread or already under another lock. Port as an ordinary property and say
  so. This is probably most of them, but it has to be shown per property,
  from the thread table in the dossier, not assumed.
- **Atomic and relied upon.** It is read and written from different threads.
  The port stores the value in a `MutableAtomicObject`
  (`sources/Infrastructure/Mutex.swift`) and makes the Swift property a
  computed one that reads and writes its `value`, so both accessors take a
  lock and the getter hands out a strong reference, which is what atomic did
  (the owner's decision of 2026-11-21, decisions.md). The setter is written
  `_ = storage.getAndSet(newValue)`, not `storage.value = newValue`: the
  first hands the old value out of the lock so it is released after the lock
  is dropped, as the Objective-C setter does; the second releases it while
  the lock is held, and the lock is not recursive, so a `deinit` of the old
  value that reads the same property would kill the process (shown by a
  probe on 2026-11-21). A `copy` property copies the new value before
  storing it. When in doubt about which class a property falls in, use this
  form.
- **Atomic but accessed directly.** The Objective-C also reads or writes the
  ivar (`_foo`) on some paths, bypassing the lock. That is an existing race;
  port it as it is and log it.

The runtime snapshot ([phase0.md §9](phase0.md)) records atomicity, so a property that
changes from atomic to nonatomic in a port is visible. The comparison lists
it as an item to check against the source: the reviewer confirms the
property is stored in a `MutableAtomicObject`, or that the dossier shows it
was atomic by accident.

## 4. C atomics, `volatile`, and thread-local variables

- **`_Atomic` variables cannot be used from Swift.** A test confirmed Swift
  rejects a reference to an `_Atomic` global, and [objc-state.md §1](objc-state.md) showed an
  `_Atomic` property is not imported. The C atomic operations are macros and
  compiler builtins, which Swift does not import either. Swift's own atomics
  in the standard library need a newer macOS than the deployment target.
- **Rule: atomics stay in C.** Each operation the Swift code needs is wrapped
  in an inline C function in the private header, named by the scheme in
  [objc-state.md §2](objc-state.md) (for example `MyClass_ivar_increment_count(obj)`), and Swift
  calls that. The memory ordering and the exact operation are then the same C
  code as before. A test confirmed an inline C function wrapping
  `atomic_fetch_add` is callable from Swift.
- **Do not replace an atomic with a lock, or a lock with an atomic,** in
  stage one. They differ in what they guarantee to readers that do not take
  the lock.
- **`volatile`** (8 uses) is imported by Swift as an ordinary variable, and
  the qualifier is lost. A flag that one thread sets and another polls in a
  loop can then be read once and never again, because the compiler assumes
  nothing else changes it. Flags like that stay in C behind accessor
  functions, or become real atomics in a `fix` commit.
- **Plain variables shared between threads without any protection** exist in
  C code and mostly work by luck. In Swift they are undefined behavior that
  the optimizer is entitled to exploit. The dossier's thread table is how they
  are found; each becomes a logged bug and gets an explicit decision.
- **Thread-local variables** (3 uses) stay in C.

## 5. Other locks and one-time initialization

- **`os_unfair_lock` and `pthread_mutex_t` must not be Swift stored
  properties.** These are C structs that must stay at a fixed address. Swift
  may move or copy a struct property, and passing `&lock` can pass the address
  of a temporary. The lock then appears to work and does not exclude. In
  Swift, use `OSAllocatedUnfairLock` (available on the deployment target), or
  leave the lock as an Objective-C ivar and lock it through inline C
  functions.
- **Unfair locks trap on misuse.** Locking one twice from the same thread, or
  unlocking from a thread that does not hold it, crashes. That is the existing
  behavior and should be preserved, not papered over.
- **`dispatch_once` does not exist in Swift.** The 618 uses fall into two
  groups. A function-level `static` token guarding a shared instance or a
  constant becomes a `static let`, which Swift initializes lazily and
  thread-safely. A token stored in an ivar or a struct (the fast accessor
  caches in `iTermPreferences.m`, for example) has no Swift equivalent; it
  stays in C or becomes an explicit lock.
- **A Swift `lazy var` is not thread-safe.** Two threads can both run the
  initializer. It is a faithful port of an unprotected Objective-C lazy
  getter and of nothing else. If the Objective-C getter was atomic, used
  `dispatch_once`, or was under a lock, `lazy var` is wrong.
- **`+initialize`** runs once, before the first message to a class, with other
  threads blocked from using the class until it finishes. Swift has no
  equivalent. Code that depended on that guarantee needs an explicit one.
- **Semaphores, groups, and conditions** port directly. Keep the same wait and
  signal structure, including timeouts.

## 6. Blocks become closures: what is captured

This is the least obvious change and it applies to every block in the code.

**An Objective-C block copies the value of each local it uses at the moment
the block is created.** Later changes to the local are not seen by the block.
Only variables marked `__block` (411 of them) are shared.

**A Swift closure captures the variable itself.** Later changes are seen, in
both directions, as if every captured variable were `__block`. A test
confirmed it: a closure created when `x` was 5 returned 6 after `x` was set to
6, while a closure with a capture list (`[x]`) returned 5.

Consequences:

- A block that is dispatched asynchronously and uses a local that the
  enclosing method changes afterwards behaves differently in Swift, and the
  access is now a data race between two threads.
- Rule: in a ported closure, every captured local that is a `var` and that was
  not `__block` in the Objective-C goes in a capture list, or is first copied
  into a `let`. Captured `let` constants need nothing.
- `__block` variables become captured `var`s, which matches. Under manual
  reference counting a `__block` object variable was also not retained;
  [arc.md](arc.md) covers that.
- Capturing `self` is covered in [lifetimes.md](lifetimes.md). For concurrency the additional
  point is where the last reference is dropped: a closure that holds the last
  strong reference and runs on a background queue causes the object to be
  deallocated on that queue. Changes in retain and release timing from the
  move to ARC and to Swift can change which thread that is. For objects that
  must be torn down on the main thread (views, window controllers, anything
  touching AppKit), the lifetime witness test asserts the thread in `deinit`.

## 7. Queues, the run loop, and timing

- **Same queue, same call, same order.** `dispatch_async` becomes
  `DispatchQueue.async` on the same queue object. `dispatch_sync` stays
  synchronous. Nothing is made asynchronous that was synchronous or the
  reverse; nothing gains or loses a hop through the main queue.
- **Queue attributes** are reproduced when a queue is created in Swift:
  serial or concurrent, quality of service, target queue, and autorelease
  frequency.
- **`performSelector:withObject:afterDelay:`** (82 uses) is not
  `asyncAfter`. It schedules on the current thread's run loop in the default
  mode only, so it does not fire while a menu is tracking, a modal panel is
  up, or a window is being resized, whereas work on the main dispatch queue
  does. It can also be cancelled with
  `cancelPreviousPerformRequestsWithTarget:`, and code relies on that for
  coalescing. Port these as the same calls on the same selectors.
- **Timers** keep their run loop modes for the same reason.
- **Autorelease pools.** Swift code on a background thread or queue that calls
  Foundation and AppKit still produces autoreleased objects. Every
  `@autoreleasepool` block (25) is ported as `autoreleasepool { }`, and loops
  that had one keep it.
- **Deadlock patterns are preserved, not fixed.** A synchronous dispatch to
  the main queue from a thread the main thread might be waiting on is an
  existing hazard; a port does not make it safer by making it asynchronous,
  because that changes ordering for every caller.

## 8. Swift-specific hazards

- **No Swift concurrency features in stage one.** No `async` functions, no
  `await`, no `Task`, no actors, no new `@MainActor`. Each of them changes
  when code runs: a suspension point lets other work on the same actor run in
  the middle of a function (re-entrancy that the Objective-C never had), a
  `Task` runs later and at a priority the caller did not choose, and an actor
  hop reorders operations relative to dispatch queues. The lint enforces
  this in migration files.
- **AppKit subclasses are main-actor isolated in Swift.** `NSView`,
  `NSWindow`, `NSViewController`, `NSResponder` and their relatives are
  declared main-actor in the SDK, and a Swift subclass inherits that. An
  Objective-C view class had no such constraint, and some of its methods may
  be called from other threads today (reading a cached value, say). After the
  port:
  - Objective-C callers are not checked and behave as before.
  - Swift callers outside the main actor get a compile error or warning. The
    tempting fixes are both wrong for a faithful port: wrapping the call in a
    dispatch to main changes timing, and `MainActor.assumeIsolated` crashes
    when the assumption is false (the codebase already has about 100 uses of
    it, all of which are assertions that the caller is on the main thread).
  - The faithful port of a method that really is called off the main thread
    is to mark it `nonisolated` and keep whatever protection it had. The
    dossier's thread table says which methods those are.
- **A later move to the Swift 6 language mode adds checks.** The main module
  builds in Swift 5 mode, where isolation is mostly not enforced at runtime.
  Under the newer mode, some calls that arrive on the wrong thread from code
  the compiler cannot see become runtime traps. That is desirable eventually
  and is a stage-two project of its own; the point here is that stage-one
  ports must not depend on, or be surprised by, the current leniency. The
  exact rules should be confirmed before that project starts.
- **Exclusive access.** [translation-rules.md §3](translation-rules.md) covers the runtime check for overlapping
  access on one thread. Across threads there is no check at all: a
  simultaneous read and write of a Swift property is simply a data race.
- **Swift collections are values, but a variable holding one is not
  protected.** Two threads may each hold their own copy safely. Two threads
  using the same property need a lock, exactly as `NSMutableArray` did. A port
  from `NSArray` handed out under a lock to a Swift array handed out under
  the same lock is fine; the lock must still cover the read of the property.
- **Reference counting is thread-safe; storage is not.** Retaining and
  releasing an object from several threads is safe. Reading a strong
  reference from a variable while another thread assigns to that variable is
  not.

## 9. The existing thread model

The terminal emulation state lives on a mutation queue, the UI on the main
thread, and specific code paths join the two so that both sets of state may be
touched. `iTermGCD` assertions (232 uses) and the `iTermThread` checked-state
classes (102 uses) record and enforce who may touch what.

- Every such assertion is ported, never dropped as noise. They are the
  documentation of the model.
- A ported method runs on the same thread or queue as before. The dossier's
  thread table lists, per method, where it runs and how that is known: an
  assertion in the code, the call sites, or the type of the state it uses.
  "Unknown" is a valid entry and means the method is ported with no new
  assumptions and no new isolation annotations.
- Where the table shows a method is confined to one thread or queue and
  nothing asserts it, add a beta assertion ([assertions.md](assertions.md)) saying so. This is
  one of the most valuable kinds of assertion the port can add, and the one
  addition [README.md §4](README.md) allows a translation. The owner,
  2026-11-22: “Add assertions generously because the code could change
  later.” He qualified it on 2026-11-24, asking of a port's main-thread
  assertion in `valueForUndefinedKey:`: “How do we know
  value(forUndefinedKe:)y is only called on the main thread?” Nobody did:
  any code may look up any key on the application object from any thread,
  and the body did not depend on the thread; the assertion was removed. So
  a thread assertion is added only where there is evidence that *every*
  entry to the method is on that thread. A method reachable by key-value
  coding, by selector name from outside the tree, or through an
  Objective-C protocol the system calls gets none on the strength of the
  callers found, unless its own body already requires that thread (it
  touches main-thread-only state), in which case the assertion documents
  an existing requirement. The commit message says which case applies and
  names what the code depends on (unsynchronized shared or instance state,
  AppKit, a process-wide facility such as `drand48`). A reviewer
  challenges every new assertion: what is the evidence that every caller
  is on this thread?
- State objects that are deliberately handed from one thread to another
  (copied, sanitized, or frozen first) keep exactly that discipline. Do not
  share where the Objective-C copied.
- Most of this machinery is in the hot paths and is deferred with them.

## 10. Detection

- **Thread sanitizer, in tests.** It finds data races directly, in both
  languages, including ones that happen not to misbehave. It is not usable
  when running the app: per the owner, it flags every Metal frame with a
  violation inside the Metal framework's own code. That does not matter for
  the test suite, where almost no test touches Metal. So a test configuration
  runs the suite under it. The few tests that do reach Metal are excluded
  from that configuration or covered by a suppression for the Metal
  libraries, whichever proves simpler.
- **When it runs.** It cannot be combined with the address sanitizer and it
  is slow, so it is a whole-suite run among each session's closing checks
  ([lifecycle.md §5](lifecycle.md)), not part of the per-commit gate.
- **Baseline first.** The existing code will report races of its own. They
  are triaged in Phase 0 into a list of known reports, each a bug-ledger
  entry, so that a port is judged on whether it adds any.
- **Its limit.** It only sees what the tests execute, and tests exercise far
  fewer interleavings than real use. Since it cannot run in the app, it will
  not see races that only occur with the real UI and renderer running.
- **Affinity assertions in nightly builds** cover that gap. A beta assertion
  that a method is on its expected thread or queue (section 9) fires in
  real use, with Metal running. They are added generously, outside hot
  paths, at the entry of every ported method whose thread is known by the
  evidence section 9 asks for.
- **The dossier's concurrency table.** For every class: each lock and what it
  protects; each piece of state touched from more than one thread; each
  atomic property with its classification; each atomic and volatile variable;
  each block that is dispatched elsewhere, with its captured mutable locals;
  each method with its thread. The inventory script finds the primitives; the
  thread assignments are worked out by reading.
- **Review.** The independent reviewer gets the concurrency table and checks
  three things in particular: that every lock region covers the same
  statements as before, that every dispatched closure captures what the block
  captured, and that nothing became asynchronous or synchronous.
- **Tests.** Concurrency tests are deterministic or they are not written.
  Tests that try to provoke a race by running threads and sleeping are flaky
  by construction and are not allowed by the project's rules. Use explicit
  barriers that force a chosen interleaving, test lock-protected logic
  single-threaded, and leave race detection to the sanitizer and to
  assertions.

## 11. What this section does not settle

- What lock backs `@synchronized` on current macOS, and therefore exactly how
  it treats waiters of different priority. An attempt to read this from the
  system library did not produce an answer. It does not affect stage one,
  which uses the same functions, but it must be known before any
  `@synchronized` is replaced in stage two.
- Whether lock identity really differs between uses of a converted Swift
  value. The rule in section 2 does not depend on the answer.
- The precise runtime checks that the Swift 6 language mode adds for calls
  arriving from Objective-C.
- How many of the 460 atomic properties are relied upon. That needs the
  per-class thread tables and cannot be estimated from counts.
