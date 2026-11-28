# Reserved paths

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The files under these path prefixes are not ported on any path, trivial,
light or full, until the row's end condition is met and the owner removes
the row. `tools/swift_migration/qualify_unit.py` reads this table: a unit
with a file its port would move under a prefix prints `Path: reserved` and
exits 15, and `--classify` and `--list` count and list it as reserved,
never among the units to port. `inventory.py leaf` does not offer such a
file either.

| Path prefix | Date | Reason | Ends |
|---|---|---|---|
| `sources/Settings/` | 2026-11-27 | Being reworked by another agent outside the migration. The owner said: “the settingspreferences UI code is being reworked by another agent. Don't port those files because the effort would be duplicated.” | When the owner says the rework is done. |

The scope of the row, the whole directory (65 units on 2026-11-27), is the
orchestrator's reading of the owner's words. A preferences view controller
outside these prefixes is queued in owner-queue.md and not ported until
the owner answers.

A commit of the migration does not port, restructure or fix a file under
a reserved prefix; a bug in `bugs/` whose fix would change one waits on
the owner ([README.md §5](README.md), “Fixing a bug in the app”). Touching one only as far as another unit's port forces,
such as removing an import of a deleted header, is allowed, and that
commit's message says so.

The format, which the tool checks (`tools/swift_migration/reserved_paths.py`):
the first table in this file, a header of four cells, its `|---|` line,
then one row per prefix with four cells, with no blank line inside the
table. A
prefix is relative to the repository root and matches whole path
components, so `sources/Settings/` does not match
`sources/SettingsExtra/Foo.m`. The date is written YYYY-MM-DD, and no cell
may contain a `|`. A malformed table stops the tool with an error rather
than reserving nothing. A missing file reserves nothing. A prefix that
matches no implementation file is printed as a WARN line by
`qualify_unit.py --classify`.
