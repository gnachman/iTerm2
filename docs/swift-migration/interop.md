# Swift and Objective-C dependency rules

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The two languages see each other asymmetrically, and the constraints determine
the order of work.

- Swift sees Objective-C through the bridging header. Objective-C sees Swift
  through the generated `iTerm2SharedARC-Swift.h`, which only exposes `@objc`
  classes, protocols, and integer-backed enums. Swift structs, generics, enums
  with payloads, and free functions are invisible to Objective-C.
- **The generated header is imported only from `.m` files, never from a `.h`.**
  A header that needs a Swift class forward-declares it with `@class`. A header
  that needs a Swift protocol forward-declares it with `@protocol`; conformance
  to a Swift protocol is declared in the class extension in the `.m`.
- **Types needed by both sides stay in Objective-C headers** until the last
  Objective-C user is gone: enums (`NS_ENUM`, `NS_OPTIONS`), structs such as
  `VT100GridCoord`, constants, and protocols with Objective-C conformers. They
  are the last things to move, not the first. This rule is what prevents a
  cycle where a header needs an enum that lives in the generated header that
  depends on that header.
- **Objective-C cannot subclass a Swift class.** A class with Objective-C
  subclasses (87 of them) is ported after all of its subclasses, or the tree
  moves together. Swift can subclass Objective-C, so leaf-first always works.
- **Objective-C categories on a Swift class** work for `@objc` classes but
  cannot see Swift-only members. A class with categories in other files has
  those categories ported first or in the same unit.
- A method a Swift class exposes to Objective-C can only use types that
  Objective-C can represent. This is the reason stage one keeps `NSObject`
  subclasses and Foundation classes: the alternative is a parallel set of
  wrapper types.
- No dependency cycles between classes. Use delegates or closures.

Port order follows: a type becomes eligible for stage one when its subclasses
and categories are done, and eligible for stage two when nothing in
Objective-C refers to it.
