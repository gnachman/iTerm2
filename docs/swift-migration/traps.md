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

### A window subclass loaded from a nib traps if it declares an initializer

- **Pattern:** an `NSWindow` or `NSPanel` subclass with no initializers of
  its own is named as a window's custom class in a xib. Nib loading creates
  the window with `-initWithContentRect:styleMask:backing:defer:`, not
  `-initWithCoder:` (which `NSWindow` marks `NS_UNAVAILABLE`).
- **Naive port:** the Swift class gains a designated initializer, or a
  stored property without a default. Swift then stops inheriting
  `init(contentRect:styleMask:backing:defer:)` and registers a stub in its
  place, and nib loading dies with "Use of unimplemented initializer". Left
  without `@objc(Name)`, the class is not found by its bare name and AppKit
  quietly makes a plain `NSWindow`, so code that relies on the subclass
  (for example an `NSPanel`-only message) raises later.
- **Write instead:** pin the name with `@objc(Name)`, declare no
  initializer and no stored property without a default, and test by
  loading the real nib with its real owner. The runtime snapshot then
  shows the inherited initializer as the class's one method, under CHECK
  AGAINST THE SOURCE.
- **Found in:** `iTermShellIntegrationPanel`, the dossier and the port.

### An override in an extension of an imported Objective-C class must be `public`

- **Pattern:** a category on an Objective-C class (one that stays in
  Objective-C) overrides a method the SDK declares on a superclass, for
  example `-valueForUndefinedKey:` from `NSObject`.
- **Naive port:** `override func value(forUndefinedKey key: String) -> Any?`
  in an `extension` of the class. It does not compile: “overriding
  instance method must be as accessible as the declaration it overrides”.
  Making it `@objc func` without `override` does not compile either
  (“conflicts with method ... from superclass”), and a parameter of another
  type than the SDK's (`Any?` for `NSString *`) is rejected the same way, so
  the bridged parameter type, and the raise in the thunk for a wrong-typed
  object (the entry above), cannot be avoided.
- **Write instead:** `public override func ...` (or `open`). The selector
  and encoding stay those of the SDK's declaration; check them with the
  runtime snapshot comparison.
- **Found in:** iTermApplication+Scripting, dossier E14 (toy probes) and
  the port.

### A non-ARC file cannot take a Swift replacement in its own target

- **Pattern:** a `.m` compiled in the non-ARC target `iTerm2Shared`.
- **Naive port:** `pbxproj_swap.py` replaces the `.m` with the `.swift` in
  the `.m`'s own target, so the Swift lands in `iTerm2Shared`, which compiles
  no Swift, has no bridging header and is set to `SWIFT_VERSION = 6.0`
  (`iTerm2SharedARC` is 5.0; Swift 6 thunks of `@MainActor` classes trap off
  the main thread).
- **Write instead:** first an `arc` commit that moves the `.m` to
  `iTerm2SharedARC` with `pbxproj_swap.py --m <path>.m --from-target
  iTerm2Shared --to-target iTerm2SharedARC`, then the port's swap.
- **Found in:** iTermApplication+Scripting, dossier E13.

### Casting a nonnull Objective-C string getter straight to `NSString` traps on nil

- **Pattern:** Objective-C that messages the result of a getter the SDK
  declares nonnull, such as `[[self localeIdentifier] isEqualToString:@"x"]`,
  where an unusual receiver (a subclass or a broken object) may still return
  nil. Messaging nil gives NO.
- **Naive port:** `(localeIdentifier as NSString).isEqual(to: "x")`. A probe
  with a receiver whose getter returns nil trapped with “Unexpectedly found
  nil while implicitly unwrapping” at `-Onone` and at `-O` (exit 133).
- **Write instead:** use the value as a `String`
  (`localeIdentifier == "x"`): a nil then bridges to an empty string at
  both optimization levels, which gives the Objective-C's NO. Pin it with a test whose receiver returns nil (a private subclass
  with the getter replaced through `class_replaceMethod`, since a Swift
  override cannot return nil). This matters only where reaching nil is
  plausible; nullability.md section 6 measured only the bound forms.
- **Found in:** NSLocale(iTerm), the author's bridging probe (2026-11-25).

### `self.class` is the receiver's class, not the class the code is written in

- **Pattern:** Objective-C that passes `self.class` or `[self class]`, for
  example to find a bundle or an image:
  `[NSImage it_imageNamed:@"NoColor" forClass:self.class]`. In a subclass
  that is the subclass.
- **Naive port:** naming the class, `for: iTermNoColorAccessoryButton.self`,
  often because a convenience initializer may not use `self` before
  `self.init` and `type(of: self)` is refused there. That gives the same
  answer today and the wrong one for a subclass, most visibly one in
  another bundle.
- **Write instead:** `Self.self`, which is the receiver's class and is
  allowed before `self.init` in a convenience initializer; elsewhere
  `type(of: self)`. Name the class only where the Objective-C did.
- **Found in:** iTermNoColorAccessoryButton (the owner, 2026-11-26: “In
  practice these are the same but the original code was robust to
  subclassing while this one is not.”).

### `NSRectFill` replaces pixels; `NSRect.fill()` blends

- **Pattern:** `[color set]; NSRectFill(rect);`. `NSRectFill` uses the copy
  operation.
- **Naive port:** `color.set(); rect.fill()`, which uses source-over. With
  an opaque color the pixels come out the same. With a clear or translucent
  color they do not: clear blended over anything changes nothing, so a view
  that erased itself to transparent stops doing so.
- **Write instead:** `rect.fill(using: .copy)` where the color can be
  anything but opaque, with a comment that says why in terms of the code
  as it stands. A plain `fill()` is right where the color is opaque.
- **Found in:** iTermTipRootView (2026-11-26); a test paints the view
  opaque red, draws, and expects transparent.

### A category that adopts a protocol loses clang's property copies in Swift

- **Pattern:** a category on a class that stays in Objective-C adopts a
  protocol that declares properties and inherits `NSObject`:
  `@interface iTermVariableScope (Global)<iTermGlobalScope>`, with the
  accessors written by hand in the category.
- **Naive port:** a Swift `@objc protocol` and an `extension` that declares
  the conformance. Clang copies the adopted protocol's properties into the
  category's property list, and also `NSObject`'s `description`,
  `debugDescription`, `hash` and `superclass`, once more for each such
  protocol list. A Swift extension makes none of these copies, so the
  class's runtime snapshot loses them.
- **Write instead:** the extension with the conformance declared and every
  accessor kept as an `@objc` instance method with the same selector and
  encoding; test that `conformsToProtocol:` still answers YES. The lost
  property entries are then an expected difference, behavior unchanged
  (the coordinator, 2026-11-26, accepted it for a class that stays in
  Objective-C; the comparison is to be taught this case).
- **Found in:** iTermVariableScope(Global), batch of 2026-11-26.
