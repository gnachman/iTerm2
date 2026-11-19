# Stage two: improvement

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Begins for a type only when no Objective-C refers to it. Every change is its
own commit with a test first.

- **Integer widening.** Introduce distinct types for the things that are
  currently bare `int`: an absolute line number, a row on screen, a column, a
  pixel offset. Change one field or one signature at a time. Because Swift has
  no implicit conversions, the compiler lists every place that mixes them,
  which is precisely what could not be done in C.
- **Bug fixes** from the ledger.
- **Swift-native types**: `URL`, `String`-based APIs, value-type collections,
  `Codable` only for new formats.
- **Removing `@objc`**, adding `final` and `private`, converting classes to
  structs where identity is not needed.
- **Refactoring** the large classes into smaller ones, which is goal 2.
- **Concurrency annotations**, as a separate, deliberate project.
