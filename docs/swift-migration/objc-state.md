# Objective-C state that Swift must reach

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

## 1. State that Swift cannot reach

Incremental porting depends on Swift methods reading and writing the state of
a class that is still Objective-C. Swift's view of that state is much narrower
than Objective-C's, and this is the main practical limit on what can move and
when. The facts below were checked on the current toolchain with a test
header; "not imported" means the member simply does not exist as far as Swift
is concerned, usually with no diagnostic until something tries to use it.

**Swift does not import ivars. Any of them.** An ivar declared in the
`@interface` in a header, marked `@public` or `@package`, or declared in a
class extension in a header, is invisible to Swift in every case. Moving an
ivar from the `.m` into a class extension or into the header does not by
itself make it usable. What Swift can use is a **property or a method**
declared somewhere the bridging header imports.

The scale of this: about 4,200 ivars are declared in `@implementation` blocks
in `.m` files, against about 300 declared anywhere in a header. Almost all
state in the Objective-C code is invisible to Swift today.

**Members whose types Swift cannot import are dropped.**

| Declaration | What Swift sees |
|---|---|
| Any ivar | Nothing |
| A property or method whose type is only forward-declared (`@class Foo;` or `@protocol Foo;` with no definition visible to the bridging header) | Nothing. The compiler reports the member as unavailable only when Swift code tries to use it |
| A property of a struct type that contains a strong object pointer | Nothing; the struct type is not imported either |
| A property of `_Atomic` type, or `__int128` | Nothing |
| A variadic method or function | Nothing |
| A function-like macro | Nothing |
| A macro whose value is an expression such as `(1 << 4 | 3)` | Nothing. Simple literal macros, string macros, and casts of literals are imported |
| A header containing C++ | Cannot be put in the bridging header at all |

`PTYSession.genericScope` exists for this reason. `variablesScope` is declared
as `iTermVariableScope<iTermSessionScope> *`, and `iTermSessionScope` is only
forward-declared in `PTYSession.h`, which matches the forward-declaration row
above. The fix that was used, a second accessor with a type Swift can import,
is one of the standard remedies below.

**Members that are imported, but in a degraded form:**

| Declaration | What Swift sees | Consequence |
|---|---|---|
| A C array in a struct (`char buf[8]`) | A tuple of 8 elements | No indexing by a variable without unsafe pointers |
| A flexible array member | The struct without the member | The tail is unreachable |
| A plain C `enum` | A struct with a raw value | No exhaustive `switch`; convert to `NS_ENUM` in preparation |
| `__unsafe_unretained id` inside a struct | `Unmanaged<AnyObject>` | Manual retain semantics at every use |
| Nested lightweight generics on mutable collections | Untyped `NSMutableArray` | Element types are lost |
| An Objective-C generic class `Foo<NSString *>` | `Foo<NSString>`, not `Foo<String>` | No bridging of the parameter |
| `long double` | `Double` on Apple silicon | Differs on Intel |
| A struct-typed property | A value copy | `obj.rect.size.width = 1` in Swift is a get, a modify, and a call to the setter, not an in-place write |

**Things that exist only inside the `.m`** and are therefore invisible:
ivars, properties and methods in a class extension written in the `.m`,
file-scope `static` variables (about 1,070), `static` functions (about 370),
private enums, typedefs, structs, constants, protocols, and macros.

**Semantic problems even when access is possible:**

- **A property is not the ivar.** Objective-C code that writes `_foo = x`
  bypasses the setter, often on purpose. About 1,280 custom setters exist.
  Swift code that writes `self.foo = x` runs the setter, with whatever it
  does: redraws, notifications, key-value observing, invalidation. The same
  applies to custom getters, including lazy ones that create the object on
  first read where the Objective-C checked the ivar for nil.
- **Address of an ivar.** Objective-C passes `&_ivar` to functions and methods
  that write through the pointer (about 220 places;
  `reallyExecuteToken:` passes `&_defaultChar` to its delegate). A property
  has no address.
- **Reaching into another object.** `obj->_ivar` appears about 1,400 times,
  mostly for speed, for example `token->type`. Swift cannot do this at all.
- **Locking.** An ivar that must only be touched while holding a lock or
  inside `@synchronized` becomes, as a property, something that can be
  touched without it. The accessor either takes the lock itself or has a name
  that says the caller must.
- **Thread confinement.** The same applies to state that belongs to one queue.
- **Cost.** A property access from Swift is a message send where Objective-C
  had a direct load. In ordinary code this does not matter. In a loop it does;
  read into a local once.
- **Ownership under manual reference counting.** A bare ivar has whatever
  ownership the code gives it by hand. A property declares one. This is one
  reason a file must be under ARC before any of its state is exposed.

**Remedies, in order of preference.** The order is a starting point, not a
rule. Each ivar is decided individually (section 2), and the dossier records
which remedy is used and why. In particular, the cost of reaching an ivar
through a property can be too high for some code, and the natural name for an
accessor is often already taken by something that does not simply return the
ivar.

1. **Move the state into a Swift state object** owned by the class, as
   `PTYSessionSwiftState` does. The class holds one strong reference; Swift
   extensions read and write `swiftState.foo` freely, with any Swift type.
   This is the best destination, because it is where the state ends up after
   the flip anyway. Limits: the remaining Objective-C code that uses the state
   must now go through the object, so each such member needs to be `@objc`
   with a type Objective-C can represent (a tuple, a Swift struct, or an enum
   with payloads cannot be seen from Objective-C); and the state's lifetime
   and teardown order now follow the state object, which must be checked
   against the `dealloc` audit in [arc.md](arc.md). Best suited to state whose users
   are all moving together.
2. **Expose the ivar as a property in a class extension** in a private header
   that the bridging header imports (the existing `+Private.h` pattern). The
   ivar stays where it is. Only valid when the type imports cleanly, there is
   no custom accessor with side effects (or the side effects are wanted), the
   ownership attribute matches reality, and no lock is being bypassed.
3. **Add a purpose-built accessor** for Swift, as `genericScope` does. Used
   when the natural property cannot be imported or has the wrong semantics:
   - a second accessor with an importable type;
   - a raw getter and setter that read and write the ivar directly, bypassing
     a custom setter, named to say so;
   - a method that performs the whole operation on the ivar in Objective-C
     (mutate a struct in place, take the lock, call a function with the
     ivar's address) so that Swift never holds the state at all;
   - an accessor that returns a pointer, only where nothing else works.
   Each such accessor is temporary scaffolding and is marked with the comment
   `// SWIFT-MIGRATION-SHIM: <reason>` so that all of them can be listed and
   removed after the flip. Raw accessors follow the naming scheme in
   section 2.
4. **Fix the visibility of the type.** Import the header that defines a
   forward-declared class or protocol into the bridging header, convert a
   plain `enum` to `NS_ENUM`, replace a function-like macro with a
   `static inline` function, give a file-scope constant an `extern`
   declaration. These are preparation commits and often remove the need for
   remedy 3.
5. **Leave the method in Objective-C.** Some methods are almost entirely
   manipulation of state that Swift cannot reach. They stay until the flip,
   when the state becomes Swift stored properties and the problem disappears.
   Moving them early buys nothing and costs scaffolding.

**Cases where none of the first four is enough**, so the method waits for the
flip or the state gets a deliberate redesign:

- State of a C++ type, or in a `.mm` file whose header cannot be imported.
- C array and bitfield ivars that the code indexes or packs directly.
- State shared by pointer with C code that retains the pointer.
- Structs containing strong object pointers.
- State whose every access is paired with a lock in ways too varied to wrap.
- File-scope `static` variables shared by many functions in the file. These
  are effectively private globals; they move together with every function
  that uses them, or they get accessor functions.

**Consequences for planning a large file:**

- Before choosing what to move, the ivar table produces, for the file,
  a table of every ivar, static variable and static function against the
  methods that use it, with each one's type classified as importable,
  degraded, or not importable. Methods are grouped by the state they share.
  The table is the query `codedb.py classstate CLASS` (or `--all`;
  [phase0.md §10](phase0.md)); it lists ivars and statics with their users,
  not static functions, and does not group the methods.
- A group whose state is all remedy 1 or 2 moves early. A group that needs
  several remedy 3 shims is a candidate to stay until the flip.
- The count of `SWIFT-MIGRATION-SHIM` markers in a file is a cost measure. If
  a move would add more shims than it removes Objective-C methods, it is the
  wrong move.
- The pilot must include one class with awkward state, to find out how often
  the hard cases occur before the estimate for the giant classes is trusted.

## 2. Deciding each ivar, and naming the accessors

There is no rule that settles how Swift reaches an ivar. Every ivar that a
moved method uses gets its own decision, recorded in the dossier, because the
right answer depends on what already has that name, how the ivar is used, and
how often.

**The problem with names.** Consider:

```objc
@implementation MyClass {
    int _foo;
}

- (int)foo { return _foo * 2; }
- (void)bar { _foo = _foo + 1; }
@end
```

To move `bar` to Swift, Swift needs the value of `_foo`. A property named
`foo` cannot be added, because a method named `foo` already exists and returns
something else. Worse, it already exists, so Swift code can call it today, and
a porter who translates `_foo` to `foo` out of habit produces code that
compiles, looks right, and is wrong.

The same trap exists in milder forms whenever an accessor with the ivar's name
is not a plain read or write of it: a lazy getter, a setter with side effects,
a getter that returns a copy, an atomic property, a getter overridden in a
subclass, or a key that something observes. In all of these, `_foo` and
`self.foo` are different operations in the Objective-C, and they must stay
different in the Swift.

**Translation rule.** In a port, the two are never interchanged:

- Objective-C `_foo` becomes the raw accessor defined below.
- Objective-C `self.foo` or `[self foo]` becomes Swift `foo`.

The independent reviewer checks every ivar access in the diff against this
rule, using the dossier's ivar table.

**Naming scheme.** A raw accessor for the ivar `_foo` is always named with the
prefix `ivar_`:

| Form | Name for ivar `_foo` of class `MyClass` | Use |
|---|---|---|
| Property | `ivar_foo` (setter `setIvar_foo:`) | The default |
| Direct property | `ivar_foo`, declared with the `direct` attribute | Warm code; see below |
| Inline C functions | `MyClass_ivar_foo(obj)` and `MyClass_ivar_set_foo(obj, value)` | Hot code |
| Inline C function returning a pointer | `MyClass_ivar_ptr_foo(obj)` | Address-of and in-place mutation of a struct |

The reasons for this exact scheme:

- The prefix is used nowhere in the codebase today, so a search for `ivar_`
  finds every raw accessor and nothing else.
- It reads as what it is. Nobody mistakes `ivar_foo` for public API, and its
  odd shape for Swift is deliberate: it marks scaffolding.
- It never collides with an existing accessor, because it is derived from the
  ivar's name and not from the property's.
- It is removed mechanically. At the flip the ivar becomes a Swift stored
  property, and every `ivar_foo` is replaced by the stored property's name.
- **It is used even when the natural name is free.** Adding a property named
  `foo` for the migration would create something that looks like public API,
  becomes a key-value coding key, and can be picked up by a binding or a
  subclass. One scheme with no judgment calls is safer than deciding case by
  case whether a name is taken.

The single exception: when a property already exists and is proven trivial
(next paragraph), Swift simply uses it and no accessor is added.

**When an existing property is trivial.** An existing accessor may stand in
for the ivar only if all of these hold, and the dossier says so:

- The getter and setter are synthesized, or do nothing but read and assign.
- The property is `nonatomic`.
- No subclass, in either language, overrides the getter or setter.
- Nothing observes the key, binds to it, or reaches it through key-value
  coding in a way that a setter call would trigger and an ivar write would
  not.

Otherwise the name is treated as taken and misleading, and the ivar table
flags it. The ivar table tool (`codedb.py classstate`) computes the first
three conditions and lists the accessors it could not prove trivial.

**Declaration.** In the class's private header, inside a class extension:

```objc
@interface MyClass ()
// SWIFT-MIGRATION-SHIM: raw access to _foo. -foo returns _foo * 2.
@property (nonatomic) int ivar_foo;
@end
```

and in the implementation, bound to the existing ivar so that no storage
moves and the remaining Objective-C keeps using `_foo`:

```objc
@synthesize ivar_foo = _foo;
```

The comment says why the accessor exists and, where there is a misleading
neighbor, names it. The ownership attribute matches how the ivar is really
held (section 1).

**The cost of each form**, confirmed by compiling a test class and inspecting
what the Swift compiler emitted:

| Form | What Swift emits | Appears in the runtime method list | Needs the ivar declared in a header |
|---|---|---|---|
| Property | A message send | Yes: two new methods | No |
| Direct property | A direct function call, no dispatch | No | No |
| Inline C function | A load or store at the ivar's offset, inlined, the same as Objective-C | No | Yes, in a class extension in the private header, with `@package` visibility |

So a plain property is the default; it costs a message send per access where
Objective-C had a load, which is irrelevant in most code. Where it is not
irrelevant, the choices are, in order:

1. Read the value into a local once at the top of the Swift method, if the
   method does not depend on seeing changes made during the call.
2. A direct property. It has the further advantage of leaving the runtime
   snapshot ([phase0.md §9](phase0.md)) unchanged, since direct methods are not in the
   method list. It cannot be used if anything needs to reach the accessor
   dynamically, which for scaffolding nothing should.
3. Inline C functions, after moving the ivar's declaration into a class
   extension in the private header. This is the case where the ivar itself
   has to move, and it gives access exactly as cheap as the original.
4. Move the ivar into the Swift state object, if most of its users are Swift.
   A stored property of a final Swift class is read directly from Swift, and
   the message send moves to the Objective-C side. Choose by where the
   frequent users are.
5. Leave the method in Objective-C. When the access is in a loop that runs
   per character, cell, or token, the method is a hot path and waits
   ([performance.md §2](performance.md)).

A plain-property shim adds two methods to the class, so the runtime snapshot
for that preparation commit differs by exactly those methods, and the commit
message lists them.

**What goes in the per-ivar table.** One row per ivar a moved method uses.
The ivar table tool (`codedb.py classstate`) fills in everything except
Frequency and the last three columns, and Guard only for `@synchronized`.

| Column | Content |
|---|---|
| Ivar | Name and type |
| Importable | Yes, degraded, or no (section 1) |
| Same-named accessor | None; trivial; or what it does differently |
| Declared | In the `.m`, a class extension in a header, or the header |
| Users | Which methods read it, write it, take its address, mutate it in place; how many are staying in Objective-C |
| Reached from outside | Whether other objects use `obj->_foo` |
| Ownership | Strong, weak, unretained, copied; who releases it |
| Guard | The lock, queue, or thread that protects it, if any |
| Frequency | Cold, warm, or hot, from the dossier and the perf harness |
| Decision | Which remedy from section 1 and which accessor form |
| Name | The accessor's exact name |
| Reason | One line, mandatory when the decision is not the default |

**After the flip.** The stored property in Swift takes the ivar's name without
the underscore where that is free, or keeps a distinct name where the old
misleading accessor still exists. Every `ivar_` use and every
`SWIFT-MIGRATION-SHIM` is removed in the commits that follow, and a file is
not counted as finished while either remains in it.
