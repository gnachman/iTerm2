# Claims

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Units in progress, kept by the orchestrator so that a new orchestrator can
resume. One line of state per unit, with the date. An entry with no matching
commits for several days is stale. A unit whose commits landed stays, with
the state *landed, closing checks pending*, until the session's closing
checks pass over it (lifecycle.md section 5); then it is removed, and its
history is in the `Swift-Port:` commit trailers.

| Unit | Kind | Since | State |
|---|---|---|---|
| `phase0-entry-point-census` | tool | 2026-11-19 | On hold. A text-based version is staged (`tools/swift_migration/entry_points.py`); it is to be rebuilt as queries on the code database, keeping its XML parsing |
