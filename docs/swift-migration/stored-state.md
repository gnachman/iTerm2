# Stored state

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Users have years of saved arrangements, profiles, preferences, and restorable
window state. New code must read old data, and old code should read new data,
because people downgrade.

- **Corpus.** Collect real stored state from several released versions:
  arrangements, restorable state, `NSCoding` archives, user defaults, profile
  JSON, and any file formats the app writes. It is committed at
  `tests/stored-state-corpus/`, with a `manifest.json` giving each file's
  origin; owner queue Q18 may move it. It was sanitized with
  `tools/swift_migration/stored_state_sanitize.py`, which replaces private
  values with placeholders of the same length and keeps the structure, and
  not with `tools/sanitize_iterm2_plist.py`, which removes keys and replaces
  whole values. `tools/swift_migration/build_stored_state_corpus.py` builds
  it from the raw collection and checks the result with
  `stored_state_scan.py` (no private value remains) and
  `stored_state_digest.py` (the structure is unchanged).
  This is a Phase 0 task, and agents produce the corpus themselves. For the
  current version, run the app with `-suite <name>` and drive it with
  AppleScript or the Python API to create the data; do not use
  accessibility APIs on the owner's Mac (`CLAUDE.md`). For older releases,
  use vm1, the VM assigned to the migration, following `docs/vm-qa.md`;
  downloading old release builds there is allowed. Old releases cannot be
  isolated on the owner's Mac, because `-suite` is a recent addition.
- **Round-trip tests.** For every type in a unit's stored-state list: decode
  the corpus with the new code and compare with what the old code produced;
  encode with the new code and decode with a build of the old code where
  practical; and compare encoded output for equality where the format is
  deterministic.
- **Archive class names.** A keyed archive records class names. `@objc(Name)`
  keeps them. Never rely on the Swift module-qualified name.
- **Keys and value types.** Dictionary keys, the exact `NSNumber` flavor
  written, and whether an absent key or an `NSNull` is written are all part of
  the format. Do not move a stored type to `Codable` in stage one; `Codable`
  produces a different format.
- **Decoding is defensive.** Everything read from storage is optional, is
  type-checked per element, and is range-checked before use as an integer,
  index, or enum raw value. This is the one place where the port may add
  tolerance, because a crash on launch from a corrupt arrangement cannot be
  recovered by the user. Record each such addition in the commit message.
- New or changed user defaults keys follow the `NoSync` and sanitizer rules in
  `CLAUDE.md`.
