# Baseline measurements

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Measured 2026-11-18 by grep and a small script, so treat as approximate.
Covers `sources/` unless a row says otherwise, so it excludes `submodules/`
and does not yet include `ThirdParty/PSMTabBarControl` ([README.md §2](README.md)).
Three rows were remeasured on 2026-11-19 with the committed inventory
script, as each says; those cover `sources/` and
`ThirdParty/PSMTabBarControl`, because that was the scope the script counted
then.
All the figures predate the widening of scope on 2026-11-19 to
`SignedArchive/`, `pidinfo/`, `iTerm2SandboxedWorker/`, `ShellLauncher/`,
`ColorPicker/`, `SearchableComboListView/` and `BetterFontPicker/`, and
cover none of those directories.

| Measure | Value |
|---|---|
| Objective-C, C, C++ implementation files in `sources/` | 844 files, about 426K lines (14K generated) |
| Swift files in `sources/` | 944 files, about 288K lines, all in module `iTerm2SharedARC` |
| Files in the non-ARC target `iTerm2Shared` | 182 in scope, including files `#include`d by one, of which 117 contain explicit retain or release. From `python3 -B tools/swift_migration/inventory.py summary` on 2026-11-19. It replaces an earlier 210, which was not limited to files in scope |
| Explicit retain/release sites in the three largest offenders | `PTYSession.m` 488, `PseudoTerminal.m` 197, `PTYTextView.m` 112. From `python3 -B tools/swift_migration/inventory.py file <path>` on 2026-11-19, which counts nested sends such as `[[[Foo alloc] init] autorelease]`; counting the occurrences of `retain]`, `release]` and `autorelease]` with `git grep -o` gives the same figures. It replaces earlier figures of 303, 84 and 77 |
| Implementation files whose header is imported by 2 or fewer other files | 422 files, about 102K lines, counting the bridging header as an importer; 454 files not counting it. From `python3 -B tools/swift_migration/inventory.py summary` on 2026-11-19. It replaces an earlier 448 |
| Implementation files whose header has more than 50 importers | 19 |
| Objective-C classes with Objective-C subclasses | 87 of about 1,360 |
| Objective-C classes with Swift subclasses | 19 |
| Headers without `NS_ASSUME_NONNULL_BEGIN` | 465 of 929 |
| Headers imported by the bridging header without it | 123 of 302 |
| Existing uses of `null_unspecified` | 0 |
| `performSelector` / `NSSelectorFromString` / `NSClassFromString` | 80 / 14 / 16 |
| `respondsToSelector` | 162 |
| `NSStringFromSelector` in `sources/` | about 60: 20 on a literal `@selector`, 14 on `_cmd`, the rest on a variable |
| Files that edit or enumerate methods and classes through the runtime API | 14 |
| `forwardInvocation:` / `methodSignatureForSelector:` / `NSInvocation` | 6 / 11 / 9 |
| `sortedArrayUsingSelector:` / `makeObjectsPerformSelector:` | 67 / 5 |
| Files with macros that paste tokens into names | 5 (`iTermAdvancedSettingsModel.m` generates method names this way) |
| App xib files (under `sources/` and `Interfaces/`) | 70 |
| Action connections in app xibs | 976, of which 226 target First Responder (192 distinct selectors, all in `MainMenu.xib`) and 259 target File's Owner |
| Outlet connections, all xibs in the repository | about 1,800 (1,115 distinct names), including 206 `delegate` and 31 `dataSource` |
| xib bindings / user-defined runtime attributes | 4 / 21 |
| xib classes already resolved through a Swift module name | 23 attributes |
| Actions assigned to menu items and controls in code | about 545 sites |
| xib custom classes / xib selectors / AppleScript bindings | 235 / 570 / 141 |
| `initWithCoder` implementations | 68 |
| `(int)`-style casts / `intValue` / `NSNotFound` | about 3,300 / 673 / 525 |
| `@synchronized` | 268 by grep. The audit of 2026-11-20 counted 262 code sites in the whole scope, 257 of them in `sources/` and `ThirdParty/PSMTabBarControl` ([concurrency.md §1](concurrency.md)) |
| `@try` or `@catch` | 75 |
| Properties that are atomic by default | 269 of 5,815 |
| `+load` or `+initialize` | 9 |
| Test methods in `ModernTests` | about 11,700 |
| Whole test suite, `tools/run_tests.expect -parallel` | 608 seconds wall clock including the build, on 2026-11-12 ([test-speed.md §1](test-speed.md)) |
| Performance and memory baselines | Not taken yet. The harness exists; taking them needs a quiet machine and about an hour ([performance.md §3](performance.md)) |

The per-file version of this table is produced by the inventory script
([phase0.md](phase0.md)) and is never stored, because it would go stale.
