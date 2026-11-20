# Claims

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Units in progress, kept by the orchestrator so that a new orchestrator can
resume. One line of state per unit, with the date. An entry with no matching
commits for several days is stale. Finished units are removed; their history
is in the `Swift-Port:` commit trailers.

| Unit | Kind | Since | State |
|---|---|---|---|
| `phase0-entry-point-census` | tool | 2026-11-19 | On hold. A text-based version is staged (`tools/swift_migration/entry_points.py`); it is to be rebuilt as queries on the code database, keeping its XML parsing |
| `phase0-inventory-state` | tool | 2026-11-19 | Parked after four review rounds; to be rebuilt as a query on the code database. Patch at `tmp/parked/phase0-inventory-state-round4.patch`. Owner queue P1 |
| `phase0-inventory-verify` | tool | 2026-11-19 | Set aside unreviewed; depends on the ivar table. Patch at `tmp/parked/phase0-inventory-verify-unreviewed.patch` |
