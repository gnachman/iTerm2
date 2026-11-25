# Assertions

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The owner wants preconditions and postconditions added liberally to validate
assumptions, without slowing release builds or adding crashes to them.
Ordinary assertions (`it_assert`, `ITAssertWithMessage`) are enabled in
release builds in this project, so they are not the default tool for this.

## 1. Which assertion to use

**`it_betaAssert` is the default for assumption checks.** It is the Swift
equivalent of the existing `ITBetaAssert` macro, to be added in Phase 0 with
the same behavior: in beta and nightly builds a failure logs and crashes; in
release builds it logs and continues. Release users get no new crashes, and
nightly and beta users find the violated assumptions.

Because the macro still evaluates its condition in release builds, a condition
that costs anything real (a search through a collection, a walk of a tree, a
comparison of two buffers) uses the conservative form, equivalent to
`ITConservativeBetaAssert`, which compiles to nothing in release. In Swift the
condition is passed as an autoclosure so that it is not evaluated at all when
the check is disabled.

**The arithmetic and conversion helpers** (`it_add`, `it_subtract`,
`it_multiply`, `it_negate`, `it_shiftLeft`, `it_narrow`, `it_floatToInteger`;
[translation-rules.md §1](translation-rules.md)) report every overflow,
changed value, undefined shift and out-of-range float conversion as a beta
assertion, through the same path as `it_betaAssert`, and then return what the
C returned, except that `it_floatToInteger` clamps a NaN or out-of-range
value, for which C has no fixed result. Unlike `it_betaAssert`, in release
builds they compile to the result alone, with no check and no log
(decisions.md, 2026-11-20). `it_floatToIntegerUnchecked` gives the same
clamped result and reports nothing in any build; it exists for hot paths,
where a port uses it only with the owner's sign-off
([translation-rules.md §1](translation-rules.md)).

**In tests** a failed beta assertion fails the running test with its message
instead of crashing the test host
(`ModernTests/iTermBetaAssertionTestObserver.swift`), and the code goes on as
it would in release. A failure outside any test case, such as during the
app's launch, still crashes.

**`it_assert` and `it_fatalError`** are for the cases where continuing is
worse than stopping in every build: the next statement would corrupt stored
user data, or the code has reached a state it has no way to handle. These are
used sparingly and each one is justified in the port commit. Swift already
stops on an out-of-bounds index by itself, so a hard assertion is not needed
for memory safety, though a beta assertion with a useful message just before
the subscript makes the eventual crash log readable.

No assertion of either kind goes in a loop that runs per character, per cell,
or per token.

## 2. What to assert

Assumptions the code makes and does not check:

- A value is within a range: an index below a count, a coordinate inside the
  grid, a length that is not negative, a width that is positive.
- An object belongs to a collection: the tab is in this window's tabs, the
  session is in this tab, the key is in the dictionary.
- Arguments relate to each other: lengths match, start does not exceed end,
  the range lies inside the string.
- State: not yet terminated, already attached, not re-entered.
- Thread or queue affinity (`dispatchPrecondition`), only with evidence
  that every entry to the method is on that thread
  ([concurrency.md §9](concurrency.md)).
- Postconditions on values the rest of the code relies on: a count that was
  preserved, a result inside the input's bounds.
- The bound stated for an arithmetic site classified as Bounded
  ([translation-rules.md §1](translation-rules.md)).

The dossier lists the assumptions found in each method. Finding them is part
of reading the code for the port, and the list is reviewed like the rest of
the dossier.

## 3. What not to assert

- **Nil that the Objective-C handled by messaging nil.** A great deal of code
  looks like this, and zero is the intended answer:

  ```objc
  SomeObject *o = ...;
  int count = [o count];  // 0 when o is nil, working as intended
  ```

  Port it as `o?.count ?? 0` and move on. Asserting that `o` is not nil would
  fire constantly on correct behavior.
- **Nil where the Swift type is not optional.** Swift cannot hold nil in a
  non-optional, so there is nothing to check. Getting the type right
  ([nullability.md](nullability.md)) replaces a whole class of assertions.
- Anything already enforced by the compiler or by a Swift runtime trap, unless
  a message would make the failure easier to diagnose.

When it is unclear whether a nil is intended or a bug, port the nil-messaging
behavior, do not assert, and add an entry to the bug ledger describing the
doubt.
