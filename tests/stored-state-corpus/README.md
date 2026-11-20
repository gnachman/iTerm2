# Stored-state corpus

Files written by released iTerm2 versions, sanitized for committing. They are
the input for tests that prove ported code still reads what old versions
wrote ([docs/swift-migration/stored-state.md](../../docs/swift-migration/stored-state.md)).
`manifest.json` lists every file with its origin, how it was made, its SHA-256
and what was replaced.

It has **not** been shown that iTerm2 decodes the sanitized files. That is a
later item: decoding them with the app's own classes. What has been shown is
listed under "Proof".

## Where it came from

Collected on 2026-11-19 on vm1 (macOS 27.0.1, arm64) by running the released
builds 3.4.0 (the oldest with an arm64 slice), 3.5.0, 3.6.0 and 3.7.8 from
iterm2.com. All typed content is made up (Fake ..., fakehost.example,
fakeuser). The exact steps for each set are in `manifest.json` under
`sets.<set>.steps`.

| Set | What it is |
|---|---|
| `3.4.0`, `3.5.0`, `3.6.0`, `3.7.8` | Final state: configured profiles, globals, advanced settings, two arrangements, snippets, actions, pointer binding, paste, command, directory and search history, a custom settings folder, and the restorable state of one window at quit |
| `<version>-restore1` | The same version at its first quit, with a complex layout open: 2 tabs, 4 split panes with one maximized, a second window, a tmux integration gateway and windows, a hidden hotkey window |
| `upgraded-3.4.0-to-3.7.8`, `upgraded-3.5.0-to-3.7.8` | The old version's final state after 3.7.8 was launched once on it and quit |

Paths below each set are relative to the VM user's home directory, under
`home/`:

| File | Format |
|---|---|
| `Library/Preferences/com.googlecode.iterm2.plist` | Binary plist (user defaults: profiles, arrangements, settings) |
| `Library/Preferences/com.googlecode.iterm2.private.plist` | Binary plist (find history) |
| `Library/Application Support/iTerm2/SavedState/restorable-state.sqlite` | SQLite; table `Node`, each `data` an NSKeyedArchiver binary plist; terminal contents are `screen_char_t` arrays inside `NS.data` |
| `Library/Application Support/iTerm2/ShellHistory.sqlite` | Core Data SQLite store (commands, directories, hosts) |
| `Library/Application Support/iTerm2/chatdb.sqlite` | SQLite (AI chat, empty), 3.7.8 |
| `Library/Application Support/iTerm2/pbhistory.plist` | NSKeyedArchiver binary plist (paste history) |
| `Library/Application Support/iTerm2/snippets.plist` | XML plist, 3.5.0 and later (3.4.0 keeps snippets in user defaults) |
| `Library/Application Support/iTerm2/DynamicProfiles/fake-dynamic.json` | JSON (written by the collection script, not by the app) |
| `Library/Application Support/iTerm2/version.txt` | Text |
| `corpus-fake/fake-all-profiles.json` | JSON from Save All Profiles as JSON |
| `corpus-prefs/com.googlecode.iterm2.plist` | XML plist from the custom settings folder, with **raw U+0008 characters** (a hotkey's characters). Apple's parser accepts it; strict XML parsers, including Python's plistlib, do not |
| `corpus-prefs/Data/snippets.plist` | XML plist, written when syncing data files to the custom folder |

The SQLite files have no `-wal` or `-shm` file: the WAL was applied before
sanitizing. They are still in WAL journal mode, as the app left them, so
opening one creates `-shm` and `-wal` next to it. Copy a database to a
temporary directory before opening it in a test.

## How it was made

```
python3 tools/swift_migration/build_stored_state_corpus.py --values VALUES.json
```

reads the raw corpus in `tmp/stored-state-corpus/` (not committed, on the
collecting computer only), sanitizes the selected files with
`tools/swift_migration/stored_state_sanitize.py`, runs the proofs below,
writes `manifest.json`, and replaces this directory only if every proof
passes. `VALUES.json` holds the private values and is not committed; it lists
each with a kind and a placeholder.

Sanitizing replaces only known private values, in place, with placeholders of
**the same length** in the same encoding, so no file and no string changes
size. Same length was chosen everywhere: terminal contents are fixed-width
`screen_char_t` cells, binary plist strings are patched where they are, and a
uniform rule keeps every length the decoders see.

| Kind | Placeholder | Where it was |
|---|---|---|
| VM account name | `vmuser01` | home paths in profiles, arrangements (working directories, directory history, environment, log names), Core Data directory history, restorable state, terminal prompts, profile JSON |
| VM host name | `corpus-vm-hostname-0001` | arrangement and restorable-state host history, `Hostname to Shell` keys, terminal prompts |
| Host-side VM address | `203.0.113.10` (a documentation address) | one `Last login: ... from` line in 3.4.0's terminal contents |
| VM volume UUID | `00000000-0000-4000-8000-000000000001` | `NSOSPLastRootDirectory`, the AppKit open panel's bookmark |
| Installation identifier | `00000000-0000-4000-8000-00000000000N` | `NoSyncInstallationId`, one value per installation |

How each format is patched:

- Binary plists, including keyed archives: only the bytes of string objects
  change. Object order, integer and real widths (so the `NSNumber` flavor),
  references, the offset table and the trailer are byte-identical.
- XML plists: text inside `<key>` and `<string>`; `<data>` is decoded, patched
  and re-encoded in the same character positions. Control characters are
  left as they are.
- `Data` values: nested plists and JSON recursively; otherwise UTF-8, UTF-16
  and `screen_char_t` code units (2 bytes every 12, per
  `sources/ScreenChar/ScreenChar.h`).
- SQLite: every text and blob cell is patched by rowid on a copy with the WAL
  applied; then every table is copied into a fresh file **with its rowids**
  (not `VACUUM`, which renumbers rowids of a table without an
  `INTEGER PRIMARY KEY` after deletions; `Node.parent` holds rowids), so freed
  pages keep no old values. Page size, encoding, `user_version`,
  `application_id` and journal mode are kept.

A dictionary **key** that held a private value was renamed the same way: 59
`Hostname to Shell` keys (account name, an at sign, host name) in user
defaults and the custom folder plist, and the same keys inside
restorable-state archives (`NS.keys`).
Nothing else changed: key names, class names, types, array lengths, version
markers, made-up content, app-generated GUIDs, window frames, dates and tty
names are as the app wrote them.

## Proof

Run by the build script; results are in `manifest.json` under `proofs`.

1. **No private value remains.** `tools/swift_migration/stored_state_scan.py`
   shares no code with the sanitizer and knows no file format. It reads every
   file as raw bytes and searches every byte stride from 1 to 16 at every
   alignment (UTF-8, UTF-16 in both byte orders, `screen_char_t` cells),
   inside every zlib or gzip stream, every raw DEFLATE stream and every
   base64 run, for each private value, for every 5-character piece of the
   account and host names (a wrapped terminal line splits them across rows),
   and for IPv4 and MAC addresses, e-mail addresses, `/Users/<name>`,
   `Last login ... from` and token-shaped strings. Result: 0 findings in all
   83 files (the 81 data files, this README and `manifest.json`). On the raw
   corpus it reports about 23,000.
2. **Structure is unchanged.** `tools/swift_migration/stored_state_digest.py`
   digests each file with every value removed (key paths, types, binary plist
   object markers and trailer, string and data lengths, keyed-archive class
   tables, SQLite header fields, pragmas, schema, and every row's rowid and
   cell types) and compares it with the original's, with the original's
   dictionary keys mapped through the same substitutions. Result: 81 of 81
   identical. The same check on every file of the raw corpus that the
   sanitizer handles (199, including the ones not committed) is also
   identical.
3. **Everything parses.** Every plist passes `plutil -lint` (42 files), and
   every binary plist blob inside the SQLite files parses with `plistlib`
   (241).

## Left out

| What | Why |
|---|---|
| `corpus-fake/fake-export.itermexport` (3.5.0 and later) | gzip tar holding copies of the other files and the shell integration scripts, 0.5 to 1.1 MB each; the sanitizer does not rewrite gzip or tar containers. Adding that (rewrite each member, tar headers, recompress) is the work it would take |
| `restorable-state.sqlite` of 3.5.0, 3.5.0-restore1, 3.6.0, 3.6.0-restore1, 3.7.8-restore1, upgraded-3.5.0-to-3.7.8 | Size (0.6 to 1.5 MB each). They are sanitized and pass the same proofs. gzip shrinks the ten databases from 7.7 MB to about 1.4 MB |
| `corpus-prefs/com.googlecode.iterm2.plist` except 3.4.0's | Size (0.3 to 0.7 MB each); the same content as the set's main plist, in XML |
| `fake-all-profiles.json` of the restore1 and upgraded sets | Byte-identical to the final set of the same version |
| `chatdb.sqlite` except 3.7.8's | Empty, same schema |
| Parser caches (`parsers/<sha256>`) | CoreParse grammar caches, regenerated when missing; NSKeyedArchiver with classes `CPGrammar`, `CPGrammarSymbol`, `CPRule`, `CPShiftReduceAction`, `CPShiftReduceActionTable`, `CPShiftReduceGotoTable` |
| `Cache.db`, `httpstorages.sqlite` | Apple URL cache and HTTP storage, not iTerm2 state |
| `-wal`, `-shm`, lock files | Applied to the database, rebuilt by SQLite, or empty |
| `.config/iterm2/*` | Symbolic links into the app bundle the VM ran |
| Collection metadata (`changed-since-launch.txt`) | A listing of the VM's home directory; the collection steps are in `manifest.json` |

Nothing was found that could not be sanitized with confidence. There is no
encrypted data. Compressed data: the export archives left out above, and
`Z_MODELCACHE.Z_CONTENT` in each `ShellHistory.sqlite`, which is raw DEFLATE
of Core Data's compiled model (a binary plist). The sanitizer does not open
it; it holds no private value (the scan inflates it) and is kept unchanged.
