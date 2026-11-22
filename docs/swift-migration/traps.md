# Traps

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The trap catalogue: patterns where a straightforward port changes behavior.
[translation-rules.md](translation-rules.md) is the seed and is not repeated
here. Every unit that finds a new trap adds it before closing. A reviewer is
given this file with every `port` commit.

Each entry says:

- **Pattern:** what the Objective-C does, with a short example.
- **Naive port:** what a direct translation does, and how the behavior
  differs.
- **Write instead:** the form to use.
- **Found in:** the unit and commit where it was first seen.

## Entries

### A readonly property ported as `@objc private(set) var`

- **Pattern:** a property that Objective-C callers can only read, written
  inside the class through its ivar:
  `@property (nonatomic, readonly) NSString *name;`
- **Naive port:** `@objc private(set) var name: NSString`. `@objc` exposes
  the setter to Objective-C too: the runtime gets `-setName:` and the
  property is readwrite, so Objective-C code, key-value coding and
  `respondsToSelector:` can now set it, although Swift code cannot.
- **Write instead:** a get-only `@objc` property over private storage
  (`private var nameStorage` and `@objc var name: NSString { nameStorage }`),
  or a `let` when the value never changes after `init`. The runtime
  snapshot comparison reports the added setter and the lost `readonly` as
  failures.
- **Found in:** phase0-runtime-snapshot-2, by experiment with the port
  fixtures in `ModernTests/RuntimeSnapshotFixtures/RuntimeSnapshotPortFixtures.swift`.

### A Swift convenience initializer that delegates to a designated initializer not exposed to Objective-C allocates twice

- **Pattern:** a class depends on the object that `+allocWithZone:` returned
  being the one that is initialized and later deallocated: an override of
  `+allocWithZone:` (a singleton, an instance counter, a pool), or
  `-dealloc` balancing work done in `+allocWithZone:`.
- **Naive port:** the class becomes Swift, and an initializer becomes a
  `convenience init` that delegates with `self.init(...)` to a designated
  initializer that is not `@objc`. From any caller, Objective-C
  (`[[X alloc] initWithFoo:]`) or Swift (`X(foo:)`), Swift then frees the
  first instance without sending it `-dealloc` (a weak reference to it
  reads nil afterwards), allocates a second instance through
  `+allocWithZone:`, and returns that one. So `+allocWithZone:` runs twice
  per instance, and one of the two never receives `-dealloc`. A convenience
  initializer that delegates to an `@objc` designated initializer allocates
  once and initializes in place. Shown by a probe built with Swift 6.4: an
  `NSObject` subclass with hooked `+allocWithZone:` and `-dealloc`, whose
  `@objc` convenience initializers delegate to an `@objc` `init()` (one
  allocation, initialized at the address `+alloc` returned) and to a
  designated initializer that is not `@objc` (two allocations and one
  `-dealloc`, whether called from Objective-C after `+alloc` or from
  Swift). `TokenExecutor` has this shape:
  `initWithTerminal:slownessDetector:queue:ownsQueue:` is a convenience
  initializer delegating to `init(_:slownessDetector:queue:ownsQueue:permits:)`,
  which is not `@objc`, and the instance census counted two allocations for
  each executor `VT100ScreenMutableState` makes.
- **Write instead:** have the convenience initializer delegate to an
  `@objc` designated initializer, or do not depend on `+allocWithZone:`
  and `-dealloc` pairing. A tool that counts instances must not rely on
  `-dealloc` alone; `ModernTests/InstanceCensus.swift` also holds a weak
  reference to each counted instance for this reason.
- **Found in:** `phase0-lifetime-witnesses`, while building the instance
  census.

### A parameter typed as a bridged class raises in the thunk for a wrong-typed object

- **Pattern:** an Objective-C method takes `NSString *` (or another class
  Swift bridges to a value type) and a caller can pass an object of another
  class, for example a value read from a profile or a plist.
- **Naive port:** the Swift parameter is `String` or `String?`. The `@objc`
  thunk bridges the argument before the body runs, and an object of the
  wrong class raises there. The Objective-C raised later, after changing
  state, or not at all.
- **Write instead:** probe each such boundary with a wrong-typed object and
  declare any difference in the commit message. Keep the Foundation type
  (`NSString`) where the difference matters.
- **Found in:** `iTermCacheableImage`, the port commit (a non-string icon
  path, reachable only from a hand-edited profile).

### `-init` marked `NS_UNAVAILABLE` becomes a trapping stub

- **Pattern:** the header marks `-init` (and so `+new`) `NS_UNAVAILABLE`.
  That is a compile-time check only: at run time `-init` is `NSObject`'s,
  and a reflective caller gets an object whose ivars are zero.
- **Naive port:** the Swift class declares only its designated
  initializer. Swift then registers an `-init` stub that traps when called.
- **Write instead:** nothing, when the census finds no caller; the runtime
  snapshot comparison lists `-init` under CHECK AGAINST THE SOURCE, and the
  commit message says that `-init` and `+new` now trap.
- **Found in:** `iTermColorSuggester`, the port commit.
