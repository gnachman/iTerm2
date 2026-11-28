# The mechanical port: translation rules

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The port reproduces behavior, in canonical Swift wherever that loses no
correctness ([README.md §4](README.md); the owner, 2026-11-25). Each rule
below names a place where a straightforward translation changes behavior,
and says what to write instead. A rule applies only where the code can reach
the difference it guards: where no input can show it, write the idiomatic
Swift, not the guarded form. Example: `isEqualToString:` against an ASCII
literal is `identifier == "en_US"`, not
`(identifier as NSString).isEqual(to: "en_US")`, because no other string is
canonically equivalent to that literal (section 4).
The trap catalogue (`docs/swift-migration/traps.md`) extends this section as
new cases are found.

## 1. Integers and floating point

**Widths are preserved in stage one.** C `int` is `Int32`, `unsigned` is
`UInt32`, `long long` is `Int64`, `NSInteger` is `Int`, `unichar` is `UInt16`.
Swift refuses to mix these without a conversion, so the port makes every
implicit C conversion explicit. That is the mechanism by which goal 7 becomes
achievable later: after the port, every conversion is a visible, searchable
expression.

**Every conversion states its intent**, chosen from what the C did:

| C behavior | Swift |
|---|---|
| Implicit widening | `numericCast(x)` |
| Narrowing or a sign change that the code relies on (a hash, a byte taken from a wider value, a bit pattern) | `init(truncatingIfNeeded:)` or `init(bitPattern:)`, with a comment saying what relies on it |
| Any other narrowing or sign change | `it_narrow`, which gives the C result and is a beta assertion when the value changes (table below). `init(clamping:)` gives a different result from C and is not a port of a C conversion |
| Float to integer | `it_floatToInteger`, which truncates as C does and clamps NaN and out-of-range values (below). Plain `Int(d)` traps on NaN, infinity and out-of-range values |
| Integer to float | A plain initializer, which the lint allows. Note precision loss above 2^53 for `Double` and 2^24 for `Float` |
| Float to float | A plain initializer. `Float(d)` rounds and gives infinity out of range, as C does |

**Arithmetic.** Swift traps on overflow where C wrapped, so every `+`, `-`,
`*`, negation, and shift on a fixed-width integer in ported code is a possible
new crash, in release builds as well as development ones. The owner's rule
(decisions.md, 2026-11-20): **in release builds the port does what the C did
in practice, and in Development, beta and nightly builds and in tests every
overflow, changed value, undefined shift and out-of-range float conversion is
a beta assertion.** A port then changes nothing for release users, good or
bad, while development builds and tests find the problems. This replaced a
rule under which overflow clamped in release, which was itself a behavior
change and could turn a loop that relied on wrapping into one that never
ends. Float-to-integer conversion is the one exception, because there what C
does is not one fixed result: `it_floatToInteger` clamps (below). Integer
wraparound, narrowing and shifts keep the C result (decisions.md,
2026-11-20).

The helpers in `sources/Infrastructure/SwiftMigrationHelpers.swift`
([phase0.md §7](phase0.md)) implement it. Each replaces one C expression whose
operands have type `T` and whose result is stored in a `T`:

| C expression | Swift | Result, in every build | Beta assertion when |
|---|---|---|---|
| `a + b` | `it_add(a, b)` | Wraps, as `a &+ b` | The sum does not fit in `T` |
| `a - b` | `it_subtract(a, b)` | Wraps, as `a &- b` | The difference does not fit; for unsigned `T`, `b > a` |
| `a * b` | `it_multiply(a, b)` | Wraps: the low bits of the product | The product does not fit |
| `-a`, signed `T` | `it_negate(a)` | Wraps: `-T.min` is `T.min` | `a` is `T.min` |
| `a << n` | `it_shiftLeft(a, n)` | The bits shifted out are dropped. C shifts at the promoted width, 32 bits for 8, 16 and 32 bit `T` and 64 bits for 64 bit `T`; both processors use only the low 5 bits of `n` for a 32 bit shift and the low 6 bits for a 64 bit shift, and for 8 and 16 bit `T` the store keeps the low bits | `n` is negative or at least the promoted width (C leaves both undefined), or the result is not `a * 2^n` because a set bit or the sign was lost. A negative `a` that loses nothing (`-3 << 2`) is not reported |
| `(T)x`, `x` an integer | `it_narrow(x, to: T.self)` | The low bits of `x`, sign-extended or zero-extended into a wider `T` | The value changes, including -1 converted to an unsigned type |
| `(T)f`, `f` a `float`, `double` or `CGFloat` | `it_floatToInteger(f, to: T.self)` | `f` truncated toward zero when that fits in `T`; otherwise clamped: `T.max` above the range and for +infinity, `T.min` below it and for -infinity (0 for an unsigned `T`), and 0 for NaN. The same on arm64 and x86_64 | `f` is NaN or its truncation does not fit in `T`. A dropped fraction is not reported: C drops it silently and constantly |

For 8 and 16 bit types C promotes the operands to `int`, computes there, and
the store truncates. The low bits are the same as wrapping in `T`, so the `T`
overload replaces `(T)(a + b)`. Where the C uses the promoted value at `int`
width (`int x = a + b` with `uint8_t a, b`), the port widens the operands
first ("Small-type promotion" below).

**Float to integer clamps.** A float converted to an integer type whose
range does not hold its truncation is undefined in C, and what clang's code
gives for it is not one fixed value: it differs between arm64 and x86_64,
between `-O0` and `-Os`, and between a result that is stored and one the
optimizer keeps in a register or folds from a constant. No single value
reproduces C, so `it_floatToInteger` clamps (decisions.md, 2026-11-20): a
value whose truncation is above `T.max` gives `T.max`, one whose truncation
is below `T.min` gives `T.min`, and NaN gives 0, on both processors, in every
build and at every optimization level. Code that worked by accident on such
values worked only sometimes, and the clamp is the result most likely to keep
it working. A value such as -0.5 truncates to 0 and is in range even for an
unsigned `T`. `Double(Int64.max)` is 2^63, which is out of range for `Int64`
and clamps back to `Int64.max`.

In a Deployment build `it_floatToInteger` is the conversion alone: on arm64
one `fcvtzs` or `fcvtzu` instruction for a 32 or 64 bit `T` (the instruction
saturates and gives 0 for NaN, which is the clamp), and that instruction
followed by a clamp for an 8 or 16 bit `T`. On x86_64, which has no
saturating conversion, it is two comparisons before the conversion. The
conversions are C functions in `sources/Logging/DebugLogging.h`, because
Swift's own initializers trap out of range and a C cast is undefined there.

**Float conversions in hot paths.** A float-to-integer conversion through
`it_floatToInteger` must not sit in a hot path (decisions.md, 2026-11-20).
With `BETA` it rounds and compares before converting, and reports, which
costs about ten instructions where the C had one. A hot path is code
[performance.md §2](performance.md) defines as one: the directories it names
(which the inventory's `HOT_PATH_DIRS` extends with `sources/CharacterSets`
and `sources/ScreenChar`), and any code a dossier finds running per
character, per cell, per token or per frame, which
[hot-paths.md](hot-paths.md) then lists. A port of such code
flags each float-to-integer conversion in the unit's dossier, and a cheaper
and less safe form is used only with the owner's sign-off, decided when that
code is ported. The cheaper form is `it_floatToIntegerUnchecked`, which gives
the same clamped result for every input with no check and no report in any
build: on arm64 in optimized builds it is one instruction for a 32 or 64 bit
result, plus a clamp for an 8 or 16 bit one. It never traps and is never
undefined behavior; what it gives up is the beta assertion that would have
found a NaN or an out-of-range value.

**Development, beta, nightly and tests.** Each event in the last column is a
beta assertion ([assertions.md](assertions.md)). Development, Beta and Nightly
builds crash on it. In ModernTests it fails the running test with the
assertion's message, and the helper returns its release result so the test
goes on.

**Release.** Deployment compiles each helper to its result alone, with no
check and no log: `it_add` on `Int32` is one add instruction, and
`it_floatToInteger` from `Double` to `Int` on arm64 is one `fcvtzs`.

**Intended wraps.** Code whose C relies on wrapping or truncating does not
use the helpers, which would assert every time the code does what it was
written to do. It uses `&+`, `&-`, `&*`, `&<<` and `init(truncatingIfNeeded:)`
or `init(bitPattern:)`, with a short comment saying what relies on the wrap.
[integer-findings.md](integer-findings.md) section 4 has examples from this
tree. `&<<` masks the count to the width of `T`, which matches C for 32 and 64
bit types only; for an 8 or 16 bit value whose count can reach 8 or 16, shift
in `Int32` and convert with `truncatingIfNeeded:`.

Signs that code relies on wrapping: unsigned arithmetic (wrapping is defined
behavior for unsigned types in C, so assume reliance until shown otherwise),
hashes and checksums, random number generators, counters compared by
difference, bit manipulation, and a mask or `%` applied right after.

**Each arithmetic site is classified individually**, and the classification
is a row in the dossier's arithmetic table that the reviewer checks.

| Class | When | What to write |
|---|---|---|
| Bounded by type | Overflow cannot happen whatever the values: for example the sum of two `Int32` values computed in `Int64` | The plain operator, with a `// bounded-by-type:` comment. The reviewer checks the reasoning |
| Bounded by argument | The operands are limited by a fact about the program: a loop index below a count, a column below the grid width | The helper, because the argument may be wrong: a plain operator would then trap in release where C wrapped, and the helper finds it in development. Plain operators are allowed here only in hot code, with the bound asserted outside the loop, and each such site is listed in the dossier |
| Intended wrap | The C relies on wrapping or truncating | The wrapping operator or `init(truncatingIfNeeded:)`, with the comment above |
| Possible overflow | Anything else | The helper |
| Widen | The value should never have been 32 bits | Stage two. In stage one pick one of the rows above and log it |

**The helper calls are scaffolding.** They make code hard to read, and they
exist only so that a port neither traps where C wrapped nor hides an overflow.
Every one is removed in stage two ([stage-two.md](stage-two.md)) by replacing it
with ordinary Swift once the question at that site has been answered: a plain
operator where overflow cannot happen, an explicit check, or a wrapping
operator. The inventory's summary counts the calls that remain
(`tools/swift_migration/inventory.py summary`).

Why 64-bit intermediates help: sums and differences of 32-bit values cannot
overflow 64 bits, and the product of two cannot either. Only chains of
products, and arithmetic on values that are already 64 bits, need the
helpers.

Further cases that need individual attention:

- **Unsigned subtraction** (`a - b` where `b` can exceed `a`, and `count - 1`
  on an empty collection) wraps to a huge value in C and traps in Swift. Each
  occurrence is examined individually. The usual C consequence is a loop that
  runs off the end, which is the out-of-bounds bug the owner accepts as a
  crash; port it so the failure is a clear assertion rather than a trap in
  range construction.
- **Division and modulo** by a non-constant get an explicit zero check. C's
  result is undefined (it is 0 on Apple silicon and a crash on Intel). The
  same policy as overflow applies: a beta assertion fires on a zero divisor,
  and in release the site returns the result the dossier chooses for it.
- **Mixed signed and unsigned comparison.** C converts the signed operand to
  unsigned, so `-1 < 1u` is false. Reproduce the C result and log it as a bug
  if it looks unintended.
- **Small-type promotion.** C promotes `char` and `short` operands to `int`
  before arithmetic, so `uint8_t + uint8_t` does not overflow at 255. In Swift
  it traps. Widen explicitly.
- **`NSNotFound`.** It is `NSIntegerMax`. Stored into an `int` it becomes -1
  and later comparisons with `NSNotFound` fail. Reproduce what the code
  actually does and log it. No compiler warning reports this, even with every
  warning enabled, so the dossier tool searches for it.
- **`BOOL` parameters and assignments.** See [nullability.md §10](nullability.md). The Intel slice
  truncates an integer to its low byte; an object pointer passed as `BOOL` is
  rejected on Intel and means `!= nil` on Apple silicon.

**Discovery runs.** Before porting units that do arithmetic on external data,
run the suite and the stress harness with the integer sanitizers in
[phase0.md §4](phase0.md) enabled on the Objective-C. The reports are a list of places where
truncation, sign change, overflow, or bad float casts actually occur with real
inputs. That is the evidence for "does the code depend on overflow", and it is
far more reliable than reading.

## 2. Messaging nil

In Objective-C a message to nil returns zero and does nothing. In Swift there
is no equivalent unless you write it.

- A receiver that the dossier or the header says can be nil is an optional, and
  the call is an optional chain. The zero result is written out: `?? 0`,
  `?? false`, `?? nil`, or an empty struct. Do not use `!`.
- A struct-returning call on nil gives a zeroed struct. Write that explicitly
  (`?? .zero` or the equivalent for the type).
- A chain `[[a b] c]` where `a` can be nil becomes `a?.b?.c` with one explicit
  default at the end.
- Where the nil case is plainly a bug (the method cannot do anything sensible
  afterwards), still port the no-op, and add an assertion per [assertions.md](assertions.md) so the
  case is detected.

## 3. Things that trap in Swift

Each of these needs a deliberate choice, recorded in the port commit or
covered by a lint:

- Array and string index out of range. Swift's own bounds check crashes in
  every build, which the owner accepts. Where a message would make the crash
  log more useful, add an `it_betaAssert` of the bound just before the
  subscript, with a message that identifies the site, but not in a loop that
  runs per character, per cell, or per token ([assertions.md](assertions.md)).
- Forming a range with `a..<b` or `a...b` where `a > b`.
- `removeFirst`, `removeLast`, `remove(at:)`, `first!` on an empty collection.
- `Dictionary(uniqueKeysWithValues:)` with duplicate keys. Use
  `init(_:uniquingKeysWith:)`.
- `stride` with a zero step.
- **Overlapping access.** Swift enforces exclusive access to a variable at
  runtime. A mutating method on a struct property, or an `inout` argument,
  that re-enters and touches the same property (a delegate callback that calls
  back in, for example) traps. Objective-C had no such rule. The dossier's
  re-entrancy notes drive this: where a method can be re-entered, do not hold
  `inout` or mutating access across the call that re-enters.
- `NSException` cannot be caught in Swift and must not unwind through Swift
  frames. Code that sat inside `@try` and calls something that raises
  (`NSKeyedUnarchiver`, `NSFileHandle`, `NSTask`, key-value coding with an
  unknown key) goes through `ObjCTry`.

## 4. Foundation types

In stage one, keep the Objective-C class wherever behavior could differ.
Switching to the Swift type is a stage-two change with its own tests.

- **`NSString` and string indexing.** Terminal code indexes strings by UTF-16
  unit and does `NSRange` arithmetic. Swift `String` counts grapheme clusters,
  `count` is linear, and its indices are not integers. Code that uses `length`,
  `characterAtIndex:`, `substringWithRange:`, or `NSRange` stays on `NSString`
  or uses the `utf16` view deliberately.
- **String equality and hashing.** `isEqualToString:` compares UTF-16 units.
  Swift `==` on `String` uses Unicode canonical equivalence, so precomposed
  and decomposed forms of the same text compare equal in Swift and unequal in
  Objective-C. This changes dictionary keys, set membership, and comparisons
  of file paths. Where the data can be non-ASCII and the distinction matters,
  compare as `NSString`. Where it cannot matter, as in a comparison with an
  ASCII literal, use `==` (the owner, 2026-11-25, of
  `(identifier as NSString).isEqual(to: "en_US")` in the `NSLocale(iTerm)`
  port: “The idiomatic port would be identifier == "en_US". Is there a good
  reason to call isEqual(to:)?” There was none).
- **Ordering.** `compare:` and Swift `<` do not sort the same way.
- **`NSURL`.** Keep `NSURL` in stage one. `URL` differs in parsing, in what it
  rejects, in bridging of file reference URLs, and in which properties are
  cached. Any switch is a stage-two change that needs tests with the URLs the
  feature really sees.
- **`NSNumber`.** Call `intValue`, `boolValue`, `doubleValue` and so on, as the
  Objective-C did. `as? Int` fails for a number holding 3.5 where `intValue`
  gave 3; `as? Bool` fails for 2 where `boolValue` gave true.
- **Collections from outside.** `as? [String: String]` succeeds or fails for
  the whole collection. Objective-C took the dictionary and failed, or did
  not, per element as each was used. Cast to `[AnyHashable: Any]` or
  `NSDictionary` and convert elements individually, reproducing what the
  Objective-C did with a wrong-typed element.
- **Mutable collections are references.** An `NSMutableArray` ivar that is
  handed to other objects, returned from a getter, or captured by a block is
  shared. A Swift `Array` is copied. If the dossier shows the instance
  escaping, it stays `NSMutableArray` in stage one.
- **`copy` properties** copy on assignment. A Swift `String` or `Array`
  property has value semantics already; an `NSMutableString` passed in from
  Objective-C must still be copied.
- **Bridging cost.** See [performance.md §1](performance.md).

## 5. Control flow and declarations

- C `switch` falls through unless there is a `break`. Check every case.
- A C `switch` without `default` silently does nothing for an unlisted value.
  The Swift version must do the same for values that can arrive from storage
  or from Objective-C (`@unknown default` with no action), unless it is an
  internal invariant, in which case assert. A Swift `switch` over an imported
  `NS_ENUM` needs `@unknown default` in any case; that is a Swift requirement
  and does not conflict with the rule that an Objective-C `switch` over an
  enum has no `default:`.
- Function-like macros are invisible to Swift. Provide a `static inline`
  function or a Swift equivalent with identical semantics, including argument
  evaluation count (a macro may evaluate an argument twice).
- `static` locals, and `static` and global variables, become static
  properties of a type (`static let` or `static var`). Migration Swift
  declares no file-scope `var`, stored or computed (decisions.md,
  2026-11-20); the lint `file-scope-var` in [phase0.md §6](phase0.md)
  reports one. A file-scope `let` constant is not reported until the owner
  confirms whether it is banned too.
- `+load` and `+initialize` have no Swift equivalent. Keep a small Objective-C
  shim or replace with an explicit call from a known startup point, as an
  `undynamic`-style prep commit.
- C structs with bitfields, unions, or packing (for example `screen_char_t`)
  stay in C headers.
- Atomic properties (about 270 are atomic by default, and about 190 more are
  declared atomic explicitly). Swift properties are not atomic. See
  [concurrency.md §3](concurrency.md). If the dossier shows the property is read and written on different
  threads, the port needs an explicit lock. If it is only used on one thread,
  note that and move on. A property relied upon across threads is stored in
  a private `MutableAtomicObject` (`sources/Infrastructure/Mutex.swift`) and
  exposed as an `@objc` computed property whose getter returns its `value`
  and whose setter is `_ = storage.getAndSet(newValue)`, so the old value is
  released after the lock is dropped ([concurrency.md §3](concurrency.md)).

## 6. Threads and locks

[concurrency.md](concurrency.md) covers concurrency in full and must be read before porting any code
that takes a lock, dispatches a block, or is called from more than one thread.
In brief:

- `@synchronized(obj)` is ported with the same runtime functions,
  `objc_sync_enter` and `objc_sync_exit`, not with a different lock.
- Queue and thread affinity is preserved exactly. No `async`/`await`, actors,
  or new `@MainActor` in stage one.
- A `dispatch_once` with a function-level `static` token becomes a
  `static let`. A token stored in an ivar or a struct has no Swift
  equivalent; see [concurrency.md §5](concurrency.md).
- A Swift closure captures variables, where an Objective-C block copied
  values; see [concurrency.md §6](concurrency.md).

## 7. Shape of a stage-one Swift class

- `@objc(OriginalName) class OriginalName: OriginalSuperclass`.
- Every member that was in the header is `@objc` with the same selector, set
  explicitly with `@objc(selector:name:)` where Swift's default spelling would
  differ.
- Members that are swizzled, observed with key-value observing, or used with
  key-value coding are `@objc dynamic`.
- Not `final`, not `private`, where Objective-C or a xib reaches it.
- Private Objective-C methods become `private` Swift methods only after the
  census shows no selector-based reference to them.
- Initializers keep their designated and convenience structure. Swift's
  two-phase initialization forbids calling methods on `self` before all stored
  properties are set, which Objective-C `init` methods do freely. Where that
  forces a property to be optional or implicitly unwrapped, prefer a default
  value; if an implicitly unwrapped property is unavoidable, list it in the
  commit message.
- An implicitly unwrapped type outside a property (a parameter type, a
  result type, a local or file-scope variable's declared type, `init!`) is
  allowed when it is the best way to proceed, for example to match an
  unannotated Objective-C signature, but not indefinitely
  (decisions.md, 2026-11-20). Each such site carries
  `// SWIFT-MIGRATION-IUO: <reason>`, with a non-empty reason, on the line
  above it or at the end of the same line, and is removed once it is no
  longer needed. A marker covers the one line it is on (at the end of a line)
  or the line below it (alone on its line), so declarations on consecutive
  lines need one marker each. The lint in [phase0.md §6](phase0.md) reports
  unmarked sites, `swift_lints.py --list-iuo` lists the marked ones, and the
  inventory counts the markers. A property, including one of a function-local
  type, is covered by the item above, not by this one.
- `deinit` reproduces the `dealloc` audit from [arc.md](arc.md) step 3.

## 8. Unsafe pointers

Goal 1 is to reduce unsafe code. A port of C code can easily turn into
`UnsafeMutablePointer` arithmetic, which keeps every out-of-bounds hazard of
the C. So unsafe pointers are used sparingly, and only for one of two
reasons:

- **A performance need in a hot path**, shown by a measurement.
- **A temporary need** until more of the port is done, after which the use is
  removed.

Each use carries a marker comment on the line above it, and the lint in
[phase0.md §6](phase0.md) rejects any use without one:

- `// SWIFT-MIGRATION-UNSAFE(hot): <reason>` for a performance need. The
  reason names the measurement that justified it. These may be permanent.
- `// SWIFT-MIGRATION-SHIM: <reason>` for a temporary need. This is the
  existing shim marker from [objc-state.md §1](objc-state.md), so these are removed along with the
  other shims and count against the file being finished.

Calling an existing Objective-C or C API whose imported signature takes a
pointer, such as an out-parameter, is not a new use of unsafe code. It still
gets a marker, so that the lint stays simple. The lint cannot detect such a
call when it names no unsafe pointer API (`&x` passed to a pointer looks the
same as `&x` passed to an `inout` parameter), so it does not enforce the
marker there.

A pointer type in the signature of an `override` (its parameter types,
result or property type, and where clause) needs no marker, because the
overridden declaration already contains it, as in `NSFormatter`'s
`isPartialStringValid(_:newEditingString:errorDescription:)`. A pointer in
the body, an accessor or a default argument value still needs one.

The pointer-returning ivar accessors in [objc-state.md §2](objc-state.md) fall under this rule, as
do `Unmanaged` conversions for C callback contexts.

Swift's own safety checks stay on in release builds ([performance.md §1](performance.md)).
