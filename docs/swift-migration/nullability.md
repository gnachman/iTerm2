# Nullability and other header claims

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

This section answers the question: a header can have hundreds of methods and
thousands of pointer positions, and one wrong annotation is a crash, so how do
we know the annotations are right?

The short answer has four parts:

1. Most positions are never claimed at all. They are marked
   `null_unspecified`, which is exactly the current behavior.
2. For positions that are claimed, the claim that can be wrong harmlessly is
   the default, and the dangerous claim requires a proof from a short list of
   accepted forms.
3. A tool, not a reader, establishes that every position was considered and
   that only the intended positions changed.
4. Claims are checked at runtime by the sanitizer for as long as the
   Objective-C exists.

## 1. What an annotation does and does not change

Annotations do not change how Objective-C code behaves at runtime. Objective-C
callers and implementations run exactly as before. The effects are:

- Swift sees `T?`, `T`, or `T!` and compiles different code for each.
- The compiler and analyzer can warn in Objective-C. A test on the current
  toolchain showed neither `-Wnullable-to-nonnull-conversion` nor the
  analyzer's nullability checker flagged a nil dictionary lookup returned from
  a `nonnull` method, so these warnings are not evidence of correctness.
- The nullability sanitizer can check the claim at runtime.

So the risk of a wrong annotation is carried entirely by Swift code that
consumes the declaration, today or after a later port.

## 2. Direction decides which mistake is dangerous

Every pointer position is a value flowing one of two ways.

**Out of the declaring code**: return values, property getters, out-parameters,
and the parameters of a block that the declaring code calls. The declaring
code produces the value.

- Wrongly `nonnull`: dangerous. Swift receives a non-optional that is nil. The
  result is undefined: sometimes an empty string or array, sometimes a crash
  far from the cause.
- Wrongly `nullable`: harmless at runtime. Swift callers handle a case that
  never happens.

**Into the declaring code**: method parameters, property setters, and the
return value of a block that the declaring code calls. The caller produces the
value.

- Wrongly `nullable`: dangerous. It promises the implementation copes with nil.
  A Swift caller may then pass nil where the implementation inserts it into a
  collection, invokes it as a block, or dereferences it.
- Wrongly `nonnull`: harmless while the implementation is Objective-C. Swift
  callers are forced by the compiler to supply a value; Objective-C callers
  that pass nil behave as they always did. It becomes dangerous at the moment
  the implementation is ported to Swift, because an Objective-C caller can
  still pass nil into a Swift parameter declared non-optional. Section 6
  covers that moment.

Safe defaults follow directly: unproven outward positions are `nullable`,
unproven inward positions are `nonnull` only if the implementation would
already fail on nil, and anything nobody needs yet is `null_unspecified`.

## 3. Step A: make the header complete without making any claim

This is a mechanical `annotate` commit for one header. It runs at the point
when a unit first needs a claim in that header, never as a sweep across
headers: a sweep would churn hundreds of files, including headers such as
`PTYSession.h` that feature work changes all the time.

1. Add `NS_ASSUME_NONNULL_BEGIN` and `NS_ASSUME_NONNULL_END` around the header.
2. Add an explicit `null_unspecified` (or `_Null_unspecified` where the keyword
   form is not allowed, such as inside block types and on C pointers) to every
   pointer position: return types, parameters, properties, block types
   themselves, pointers inside block signatures, C function parameters and
   returns, struct fields that are object or C pointers, globals, and both
   levels of `NSError **`.
3. Run the interface snapshot before and after. **The two snapshots must be
   identical.** If they differ, a position was missed or an annotation was
   placed on the wrong level of a type. This check is what guarantees
   completeness: an unannotated pointer inside the assume-nonnull region shows
   up as a `T!` that became `T`.
4. Build with no warnings.

After this commit the header behaves exactly as before, every position is
visibly accounted for, and the remaining work is countable:
`grep -c null_unspecified` on the header.

A consequence worth stating: from here on, a `nonnull` claim is made by
*deleting* a `null_unspecified`, and a `nullable` claim by *replacing* one.
Both are visible in a diff. Nothing becomes `nonnull` by being overlooked.

Headers that already have `NS_ASSUME_NONNULL_BEGIN` skip this step. Their
existing claims are treated as unverified and are checked by the sanitizer
([phase0.md §4](phase0.md)), not re-proven up front.

## 4. Step B: claim only what the port needs

For a unit about to be ported, two sets of positions must be resolved:

- Every position in the unit's own header, because those become the Swift
  signatures.
- In other headers, only the members the unit actually uses. The lint against
  touching implicitly unwrapped values ([phase0.md §6](phase0.md)) produces this list
  mechanically once the port is drafted, and the dossier predicts it. That
  lint is not implemented yet: it needs the compiler's importer, and
  `tools/swift_migration/swift_lints.py` lists it under "Not checked by this
  tool", so for now the list comes from the dossier.

Everything else in those other headers stays `null_unspecified`. A 300-method
header is not audited because one unit calls four of its methods.

Claims go in `annotate` commits of modest size (one header, or one header's
members needed by one unit). Each commit message lists every claim with the
rule that justifies it (section 5), in a form the reviewer can check line by
line:

```
-[Foo name]                      nonnull   O3  set in both designated inits; no other writes
-[Foo sessionForGUID:] return    nullable  O-default (dictionary lookup)
-[Foo sessionForGUID:] guid      nonnull   I2  used as dictionary key in -setObject:forKey:
-[Foo setDelegate:]              nullable  I1  stored to weak ivar only
```

The interface snapshot diff for the commit must match that list exactly: same
members, same directions, nothing extra.

## 5. Accepted proofs

Any position that does not meet one of these is given its safe default.
"It is obviously never nil" and "every caller I looked at passes a value" are
not proofs.

**Outward positions. Default: `nullable`.** `nonnull` requires one of:

- **O1. Every return path returns a locally non-nil expression.** Accepted
  expressions: an Objective-C literal (`@""`, `@[]`, `@{}`, `@1`); `self` in a
  method that is not an initializer; the result of a method already claimed
  `nonnull` by this process or annotated `nonnull` in the SDK and not on the
  distrust list in the trap catalogue; `x ?: y` where `y` qualifies; a local
  that was assigned only from qualifying expressions on every path. The method
  must be read in full, including early returns and returns inside blocks,
  `@try`, and `switch`.
- **O2. Lazy getter.** `if (!_x) { _x = <qualifying expression>; } return _x;`
  with no other write to `_x` that could be nil.
- **O3. Stored property with a complete write audit.** Every write to the
  backing ivar is listed (designated initializers, the setter, direct ivar
  writes including in categories and subclasses that can see it, key-value
  coding, decoding, and teardown) and every one assigns a qualifying
  expression. The property must be assigned in every designated initializer
  before `self` can escape.
- **O4. Singleton accessor** built on `dispatch_once` with a qualifying
  initializer.
- **O5. Initializers.** An initializer is `nonnull` only if it has no
  `return nil`, and its super or delegated initializer is `nonnull` by these
  rules or is plain `-[NSObject init]`.

Things that are always `nullable` for outward positions, with no exceptions:

- `weak` properties and anything read from a `weak` or `assign` reference.
- Delegates and data sources.
- Anything looked up: dictionary and cache lookups, `firstObject`,
  `lastObject`, searches, `viewWithTag:`, `objectForKey:` on defaults.
- Anything decoded from stored state or parsed from input.
- Anything a teardown path clears. Much of this codebase nils members when a
  session or window terminates, and callers still hold the object afterwards.
- `IBOutlet` properties.
- Failable construction: `stringWithUTF8String:`, `initWithData:encoding:`,
  `URLWithString:`, `imageNamed:`, file reads, and similar.
- The return of any method that is overridden or implemented by more than one
  class, unless every override and conformer is proven. For a protocol method
  that means every conforming class, in both languages.

One further fact to keep in mind when consuming a `nonnull` return: it is only
`nonnull` when the receiver is. `[self.delegate title]` is nil when the
delegate is nil no matter what the protocol says. In Swift the optional
receiver makes this visible. In remaining Objective-C it does not, and the
sanitizer does not report it either (confirmed by test).

**Inward positions.** Classify by reading every use of the parameter in the
implementation, following it into callees:

- **I1. Tolerant, so `nullable`.** With nil, the implementation only messages
  it, tests it, stores it in an ivar or property that is itself `nullable`, or
  passes it to positions already claimed `nullable`. Record what the method
  then does, because callers may rely on that silent no-op and the port must
  reproduce it.
- **I2. Intolerant, so `nonnull`.** With nil, the implementation would raise or
  crash: inserts into a collection or collection literal, uses it as a
  dictionary key, invokes it as a block, dereferences it, passes it to a C
  function that reads through it, or passes it to an SDK or audited parameter
  that is `nonnull` and known to fail on nil. No caller audit is needed,
  because passing nil is already a failure today. If the failure is an
  `NSException` inside a `@try`, it is tolerant in effect: classify as I1 and
  note it.
- **I3. Unknown, so it stays `null_unspecified`.** The value is passed to
  something not yet classified. Resolve the callee first, or leave it.

Block-typed parameters carry three kinds of position: the block pointer itself
(inward; invoking a nil block crashes, so it is I2 unless the implementation
checks), the block's parameters (outward from the declaring code; use the O
rules on every call of the block), and the block's return value (inward).

**Counter-evidence.** Before finalizing a `nonnull` outward claim, search the
Swift and Objective-C callers for nil checks on that member. An existing
`if let`, `guard let`, `?.`, `?? `, or `if (x)` on the result means someone
believed it could be nil. Treat that as disproof unless the O-rule evidence is
airtight and the check is demonstrably dead.

## 6. The ripple into Swift callers

Changing a member from `T!` changes how existing Swift compiles. The compiler
lists every affected site, which is the point. Rules for fixing them, in the
same commit:

- `T!` to `T?`: bind with `guard let` or `if let`, or use optional chaining.
  Never `!`. Before the change a nil here would have crashed or silently
  propagated; choose the form that matches what the code did when the value
  was propagated, and prefer an early exit with a `DLog` where it was
  force-used.
- `T!` to `T`: Swift code that tested the value for nil no longer compiles.
  That is the counter-evidence case in section 5. Do not delete the check to make
  the build pass; reconsider the claim.
- Parameters that become `nonnull`: a Swift caller holding an optional must
  decide what to do when it is nil. Under I2 the call would have failed with
  nil anyway, so skipping the call is no worse, but log it as a bug candidate
  rather than hiding it.
- Protocol methods: when an annotation changes a protocol requirement, every
  Swift conformer's signature must change to match. For a required method the
  compiler reports it. **For an `@optional` method a mismatched Swift signature
  is only a warning ("nearly matches"), and the method silently stops being
  called.** Warnings are errors in this project, which catches it, but check
  conformers explicitly from the census whenever a protocol header changes.
- Swift subclasses overriding the method must change in the same way.

**What a false `nonnull` return looks like in Swift today.** When an
Objective-C method that claims `nonnull` returns nil, Swift receives a
non-optional value that is really nil. What the Swift code then sees depends
on the type and, for class types, on how the optional is formed. Measured
with a probe on 2026-11-20 (swiftc and clang, `-Onone` and `-O`):

| Swift code | Class type | Bridged `String`, `Array`, `Dictionary`, `Data` |
|---|---|---|
| `let x: T? = obj.method()`, then `x == nil`, `if let`, `guard let`, `x?.member` | nil at both levels | present and empty at both |
| `Optional(obj.method())`, or assigned to `AnyObject?` | nil at `-Onone`, present at `-O` | not measured |
| `obj.method() as Any` | crashes at both levels | the empty value |
| Passed directly to an Objective-C parameter | nil | the empty value |
| Messaged or compared without an optional | does nothing; compares false | behaves as the empty value |

So a Development build and an optimized build can disagree about a
class-typed value, and a bridged value never looks absent. When such a claim
is corrected to `nullable`, each Swift site must be judged against this
table for what it did before, not against what the source seems to say.

When the unit itself is ported, its Swift signatures are written from the
audited header, with one addition for inward positions: any parameter that is
`nonnull` by I2 but that Objective-C callers still exist for is declared
optional in Swift and guarded at the top of the method with a clear failure
(`it_fatalError` with a message), because a nil arriving in a non-optional
Swift parameter is undefined behavior rather than a clean crash. When the last
Objective-C caller is gone, stage two makes it non-optional.

A light-path port ([lifecycle.md §3](lifecycle.md)) has no `annotate`
commit, since it deletes the header. Its Swift signatures keep the header's
claims or move in the safe direction: optional for a result, and for a
parameter whose nil the Objective-C tolerated. A nonnull claim the header
did not make needs the full path.

## 7. Runtime checking

The suite is run with `-fsanitize=nullability` ([phase0.md §4](phase0.md)). A test on the
current toolchain confirmed what it does and does not catch for Objective-C
methods:

| Case | Reported |
|---|---|
| A method declared `nonnull` returns nil | Yes, at the `return` |
| nil passed to a `nonnull` parameter, receiver statically typed | Yes, at the call |
| nil passed to a `nonnull` parameter, receiver typed `id` | Yes |
| nil assigned to a `nonnull` property with dot syntax | No |
| A `nonnull` method called on a nil receiver, yielding nil | No |

The sanitizer only checks code that runs. It finds mistakes in proofs; it does
not replace them. Its value is highest for the claims nobody proved: the 464
headers annotated before this process existed.

A report is handled as follows. If the annotation is wrong, change it to the
safe default and fix the Swift callers the compiler then lists. If the
annotation states the real intent and the code violates it, log a bug; do not
fix it in an `annotate` commit.

Once a class is ported, its own claims are enforced by the Swift compiler and
the sanitizer no longer matters for it. The exposure shrinks as the port
proceeds.

## 8. Review of an annotate commit

The reviewer receives the header diff, the claim list, the interface snapshot
diff, and the implementation. For each `nonnull` outward claim and each
`nullable` inward claim (the two dangerous kinds) the reviewer tries to
construct a counterexample: a path that returns nil, a write that stores nil,
a teardown that clears the ivar, an override that behaves differently, a use
of the parameter that fails on nil. A claim survives only if the reviewer
cannot. The safe-direction claims need only a check that they were not
mislabeled.

## 9. Summary of the guarantees

| Failure | What prevents it |
|---|---|
| A position is missed in a long header | Step A snapshot must be byte-identical |
| A position becomes `nonnull` by accident | Claims are visible deletions; snapshot diff must match the claim list |
| A wrong `nonnull` return | Default is `nullable`; O-rules; counter-evidence search; adversarial review; sanitizer |
| A wrong `nullable` parameter | I1 requires reading every use; adversarial review |
| A wrong `nonnull` parameter after the callee is ported | Optional-plus-guard at the Swift entry while Objective-C callers exist |
| Broken call chains in Swift | Compiler enumerates every site; fixed in the same commit; no `!` |
| An optional protocol method silently unhooked | Warnings are errors; census check of conformers |
| A claim that was true becomes false after a later edit | Sanitizer in the suite; exposure ends when the class is ported |

## 10. Other type claims in headers

Nullability is the largest case of a general problem: Swift trusts what the
header says. The same on-demand, safe-default approach applies to the others.

**Lightweight generics.** `NSArray<NSString *> *` imports as `[String]`. If an
element is not a string (an `NSNull` from JSON, a number from a property list),
Swift crashes when it reads that element. Add or keep a generic argument only
when every writer of the collection is known. Collections that come from stored
state, user defaults, JSON, or the API are imported as `[Any]` or
`[AnyHashable: Any]` and decoded element by element.

**Enums.** A value outside the declared cases is tolerated by Swift for an
`NS_ENUM` (a `switch` needs `@unknown default`) and is undefined for
`NS_CLOSED_ENUM`. Do not use `NS_CLOSED_ENUM` for any enum whose values are
stored, sent over a connection, or cast from an integer. When Swift receives a
stored integer, construct the enum with `init(rawValue:)` and handle failure.

**`NSError **` methods.** Swift imports these as `throws` and treats a nil or
`NO` return as an error. A method that returns nil for a reason other than an
error will throw spuriously in Swift. Check each one; mark with
`NS_SWIFT_NOTHROW` where the convention is not followed. There are few of
these in the codebase.

**`instancetype`, `id`, and `Class` parameters.** Leave as they are. Narrowing
them is a claim.

**`BOOL`.** On Intel `BOOL` is a signed char and assigning an integer truncates
to the low byte; on Apple silicon it is a real boolean. The app ships for both.
Where the dossier finds an integer stored into a `BOOL`, port the Apple silicon
behavior (non-zero is true) and log the Intel difference as a bug.
