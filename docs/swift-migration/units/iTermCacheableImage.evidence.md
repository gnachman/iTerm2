# Evidence for the iTermCacheableImage dossier

The evidence behind [iTermCacheableImage.md](iTermCacheableImage.md), for a
reviewer or a tool; not meant to be read end to end. Sections are numbered
E0 to E18 so the dossier can point at them. Gathered on 2026-11-21 against
the main checkout's HEAD of that day, before the `fix` and `annotate`
commits of the plan; line numbers in `iTermCacheableImage.m` are those of
that tree (the `fix` commit moves line 32 onward down by two). "Section N"
inside this file means EN.

## E0. The unit

| | |
|---|---|
| Files | `sources/SessionIcons/iTermCacheableImage.h` (18 lines), `sources/SessionIcons/iTermCacheableImage.m` (42 lines) |
| Target | `iTerm2SharedARC`, ARC |
| Classes | one: `iTermCacheableImage : NSObject` |
| Methods | one: `-imageAtPath:ofSize:flipped:` (plus `-init` inherited from `NSObject` and the compiler's `.cxx_destruct`) |
| State | four ivars: `_path`, `_image`, `_size`, `_flipped` |
| Users | one: `-[PTYSession customIconImageForProfile:]` in `sources/PTYSession/PTYSession.m` (manual reference counting, target `iTerm2Shared`) |
| Visible to Swift today | no: the header is in no bridging header (section 5) |

What it does: a one-entry cache of a custom tab icon. On a call with the
same path (by `isEqualToString:`), the same size (by `NSEqualSizes`) and the
same `flipped` as the last call that loaded, and a non-nil cached image, it
returns the cached `NSImage` itself. Otherwise it records the three inputs,
loads the file with `-[NSImage initWithContentsOfFile:]`, flips it
vertically when asked (`-[NSImage it_verticallyFlippedImage]`), resizes it
when its size differs from the requested one (`-[NSImage it_imageOfSize:]`),
caches the result and returns it. A load that produced nil is cached as nil,
which never hits, so every later call loads again.

### How to re-run the commands in this file

The lane has no code database; every query reads the shared one in the main
checkout, read-only. The commands below are written for bash (zsh does not
split `$RM` into words). Set these first:

```bash
cd /Users/gnachman/git/iterm2-alt.lanes/lane-5 || exit 1
MAIN=/Users/gnachman/git/iterm2-alt
RM=(); for f in $MAIN/tmp/phase0-census-override-check/lists/*.tsv; do RM+=(--runtime-methods "$f"); done
cdb() { python3 -B tools/swift_migration/codedb/codedb.py --root $MAIN "$@"; }
census() { python3 -B tools/swift_migration/entry_points.py --root $MAIN "${RM[@]}" "$@"; }
```

**Status 3 on every database answer, and why it does not change them.**
Every `codedb.py` and `entry_points.py` answer below exited 3
(INCOMPLETE). The reasons it printed: the compile database does not cover
`ModernTests/VariablesIndexNullabilityTests.m` (added after the capture);
7 of 1099 units are stale (`ModernTests/RuntimeSnapshotFixtures/RuntimeSnapshotFixtures.m`,
`ModernTests/RuntimeSnapshotFixtures/RuntimeSnapshotPortFixtures.m`,
`sources/InlineImages/VT100InlineImageHelper.m`, `sources/VT100/VT100Grid.m`,
`sources/VT100/VT100Terminal.m` and two more the tool does not name: it
prints the first 5); the ModernTests Swift file list has 6 files added since
the capture and the ModernTests module is stale; and the runtime method lists
make every census incomplete by nature. Note that stale units do exist in
`sources/`, contrary to the expectation that only test files were affected.
None of this changes the answers for this unit:

- Every row printed came from a current unit (`rows printed: 1; from units
  that are not current: 0`).
- The only units that read `iTermCacheableImage.h` are
  `sources/PTYSession/PTYSession.m` and `sources/SessionIcons/iTermCacheableImage.m`,
  both current. Query (read-only SQLite):

  ```bash
  python3 - <<'EOF'
  import sqlite3
  c = sqlite3.connect('file:/Users/gnachman/git/iterm2-alt/tmp/codedb/codedb.sqlite?mode=ro', uri=True)
  for r in c.execute("select t.target, t.main_file from tu t join tu_input i on i.tu = t.id "
                     "where i.path like '%iTermCacheableImage.h'"):
      print(r)
  EOF
  ```
  ```
  ('iTerm2Shared', 'sources/PTYSession/PTYSession.m')
  ('iTerm2SharedARC', 'sources/SessionIcons/iTermCacheableImage.m')
  ```
  An Objective-C unit cannot send the selector with a typed receiver without
  reading the header, and the census's text search of unparsed code found
  nothing.
- A text search of the whole tree, in every file git tracks, finds the class
  name only in the unit's two files, `PTYSession.m` (lines 99, 769, 7347) and
  `iTerm2.xcodeproj/project.pbxproj`:
  `git grep -n 'iTermCacheableImage' -- . ':!docs'`. That covers the six new
  ModernTests Swift files and the uncovered `.m`, which the database cannot.

## E1. Public and private API, with the census for every selector

| Selector | Declared | Kind |
|---|---|---|
| `-imageAtPath:ofSize:flipped:` | `iTermCacheableImage.h:14` | public, the only one |
| `-init` | inherited from `NSObject` | used by `PTYSession.m:7347` |

There is no private API: no class extension, no category, no method in the
`.m` that is not in the header.

**Class census** (`census class iTermCacheableImage`, exit 3, 24 s, 237 MB
peak):

```
Class facts: 2 (all sources of the method census; INCOMPLETE)
  declared and defined in Objective-C: 2
    sources/SessionIcons/iTermCacheableImage.h  interface iTermCacheableImage
    sources/SessionIcons/iTermCacheableImage.m  implementation iTermCacheableImage
10. Not covered: 0 (... complete)
Methods: 1
  columns: Objective-C sends, Swift references, selector references, by name, key-value coding, registry, Interface Builder, scripting and plists, text, tests
  -imageAtPath:ofSize:flipped:  objc 1  swift 0  selref 0  byname 0  kvc 0  registry 0  ib 0  scripting 0  text 0  tests 0
```

Releases consulted (from the run): macOS 13.6, 14.6, 15.6, 26.7 and 27.0
from dumped headers, and macOS 27.0 (26A428) from a live runtime list of 44
frameworks.

**Method census** (`census method iTermCacheableImage -imageAtPath:ofSize:flipped:`,
exit 3), trimmed to its section headings and rows:

```
1. Objective-C callers: 1
    sources/PTYSession/PTYSession.m:7351:25  -[PTYSession customIconImageForProfile:]  receiver iTermCacheableImage *  targets iTerm2Shared
2. Swift callers: 0
3. Selector references that are not calls: 0
4. Reflective reach (the registry): 0 and 5 informational
5. Interface Builder: 0 (xibs and storyboards, parsed as XML (82 files); complete)
6. Scripting, property lists and other resources: 0 (complete)
7. Protocols and overrides: 0 and 1 informational
    sources/SessionIcons/iTermCacheableImage.m:18  implemented here
8. Persisted and wire names (the registry, section 6): 0 (complete)
9. Tests: 0
10. Not covered: 0
```

The five informational reflective sites are the generic open ones the census
lists for every selector; none can reach this method (section 4).

Also run, all exit 3 with the same single row or none:

- `cdb reach 'imageAtPath:ofSize:flipped:'`: 1 send (the one above), 0
  selector expressions, 0 key-value coding, 0 Swift references, 0 Swift
  declarations, 0 Swift protocols with a matching requirement.
- `cdb methods 'imageAtPath:ofSize:flipped:'`: declared at `iTermCacheableImage.h:14`,
  defined at `iTermCacheableImage.m:18`; no other class defines it.
- `cdb sdkmethods 'imageAtPath:ofSize:flipped:'`: 0 declarations outside
  the repository. `grep -c 'imageAtPath:ofSize:flipped:'` on the live
  macOS 27 runtime list: 0. No framework class implements the selector.

## E2. Runtime snapshot

`tools/swift_migration/runtime_snapshot.sh tmp/dossier-iTermCacheableImage/runtime-snapshot.txt iTermCacheableImage`
(exit 0; 2 min 9 s wall including the test build):

```
# Objective-C runtime snapshot, format 3
architecture arm64
build-configuration Development
build-variant ASan
class iTermCacheableImage
  language objc
  superclass NSObject
  image iTerm2.debug.dylib
  ivar-arc-flag set
  strong-ivar-layout 0200
  weak-ivar-layout
  ivar _flipped types=B ownership=scalar layout=
  ivar _image types=@"NSImage" ownership=strong layout=s
  ivar _path types=@"NSString" ownership=strong layout=s
  ivar _size types={CGSize="width"d"height"d} ownership=struct-or-cxx-object layout=
  instance-method -.cxx_destruct types=v16@0:8
  instance-method -imageAtPath:ofSize:flipped: types=@44@0:8@16{CGSize=dd}24B40
end class iTermCacheableImage
```

No protocols, no properties, no class methods, no duplicates, no selector
also implemented by a superclass. The ownership agrees with the compiler's
answer in `classstate` (section 11): `_path` and `_image` strong, `_size`
and `_flipped` not objects.

`tools/swift_migration/ivar_ownership_check.py`, which phase0.md §9 names
for this cross-check, could not run: "the database at
/Users/gnachman/git/iterm2-alt/tmp/codedb/codedb.sqlite has schema 12; this
tool reads schema 11" (exit 2). The comparison above was made by hand from
`classstate`.

`BOOL` is encoded `B` here (arm64). On x86_64 it is `c`; phase0.md §9 lists
whether swiftc encodes `Bool` as `c` there as untested.

## E3. Interface snapshot of the header

The class is not visible to Swift today. `iTermCacheableImage.h` is imported
by no bridging header (`grep -n iTermCacheableImage sources/*Bridging-Header.h`
finds nothing), and ModernTests reaches Objective-C through
`@testable import iTerm2SharedARC`, so through
`sources/iTerm2SharedARC-Bridging-Header.h` as well.

```bash
python3 -B $MAIN/tools/swift_migration/swift_interface.py snapshot --sections import \
    --work $PWD/tmp/dossier-iTermCacheableImage/swift-interface --accept-stale
```

(run with the main checkout's copy of the script, because the capture's
paths are the main checkout's; it wrote only under the lane's `tmp/`. Exit
0; 23 s; compiler peak 2282 MB.) The import section has 33,780
declarations and none for this class:
`grep -i 'cacheable\|imageAtPath' .../worktree.snapshot` finds only
`NSImage.it_cacheableImageNamed(_:for:)` and an unrelated variable. The two
dependencies the body calls are imported as:

```
import  NSImage.it_image(of:)          method  open  func it_image(of size: NSSize) -> NSImage? [extension]
import  NSImage.it_verticallyFlipped() method  open  func it_verticallyFlipped() -> NSImage [extension]
```

Consequence for the plan: an `annotate` commit on this header changes
nothing in the interface snapshot unless the header is also made visible to
Swift, which the `annotate` commit does (E18).

## E4. xibs, First Responder actions, and reflective sites

**xibs.** None. The census parsed 82 xib and storyboard files and found no
reference (section 5 of the method census: 0); `git grep` of the class
name finds none in any `.xib`, `.storyboard`, `.plist` or `.sdef` (see
section 0).

**First Responder actions.** None. The class implements one method, which
takes three arguments and is not an action shape; the census's Interface
Builder section is 0.

**Reflective sites in the unit.** None. `inventory.py file
sources/SessionIcons/iTermCacheableImage.m`: "In
sources/SessionIcons/iTermCacheableImage.m: 0" dynamic selector sites,
hazards "none detected".

**Reflective sites elsewhere that can reach the unit.**

- The registry (`docs/swift-migration/reflective-sites.md`) names neither
  the class nor the selector: `grep -c CacheableImage` gives 0. Census
  sections 4 and 8: 0.
- The binding tests' persisted-name list (`ModernTests/BindingTestTables.swift`,
  `persistedNames`): `grep -c CacheableImage` gives 0. The class does not
  adopt `NSCoding` and no archive allowlist names it.
- `NSClassFromString` and other class-from-string sites
  (reflective-sites.md section 3, "Class from a string"): the open ones read
  class names from stored or pasted data (interval-tree dictionaries, marks,
  status bar layouts and pasteboard data, triggers), each checking a
  protocol or superclass first except
  `-[iTermStatusBarBuiltInComponentFactory initWithCoder:]`, which checks
  only for non-nil. Only hostile input could name this class there, and the
  object would then fail at `-initWithConfiguration:scope:`, which it does
  not implement, before or after a port alike. No writer stores this class's
  name.
- The five open sites the method census lists (main-menu item dispatch from
  the API, `NSMenu` item selection by title, Open Quickly, the
  `iTermScriptingWindow` proxy, and the browser's broadcast replay) send
  menu-item actions, forward to a window, or replay to web views. None can
  name `-imageAtPath:ofSize:flipped:`: no menu item has it as an action (no
  `@selector` reference anywhere: census section 3 is 0, xibs 0) and it is
  not a window or web view method.

## E5. Strict-set warning report

The survey data in the main checkout is from 2026-11-20, so the unit was
surveyed afresh in all six modes. The lane's copy of `warning_survey.py`
finds no units (the capture's paths are the main checkout's, so every
fragment is "outside the repository" relative to the lane); the main
checkout's copy was run with `--out` in the lane:

```bash
W=$PWD/tmp/dossier-iTermCacheableImage/warning-survey
S=$MAIN/tools/swift_migration/warning_survey.py
for a in arm64 x86_64; do for m in baseline strict everything; do
  python3 -B $S --out $W run --arch $a --mode $m --jobs 1 --only SessionIcons/iTermCacheableImage.m
done; done
python3 -B $S --out $W file sources/SessionIcons/iTermCacheableImage.m
python3 -B $S --out $W file sources/SessionIcons/iTermCacheableImage.h
python3 -B $S --out $W summary --arch arm64 --mode everything
python3 -B $S --out $W summary --arch x86_64 --mode everything
```

```
sources/SessionIcons/iTermCacheableImage.m: 0 strict-set diagnostics to resolve before it can import iTermStrictWarnings.h
sources/SessionIcons/iTermCacheableImage.h: 0 strict-set diagnostics to resolve before it can import iTermStrictWarnings.h
```

Baseline: 0 on both architectures. `-Weverything`, both architectures
identical: 16 `-Wdirect-ivar-access` (every ivar use in the method; not a
hazard for the port) and 1 `-Wmissing-include-dirs` on the command line. No
diagnostic on one architecture only. So no `explicit` commit is needed.

## E6. Superclass, subclasses, categories, protocols

- Superclass: `NSObject`. `cdb classinfo iTermCacheableImage`: chain
  `iTermCacheableImage -> NSObject (SDK objc)`; protocols: `NSObject`, by
  `NSObject`; none inherited through protocols.
- Subclasses, Objective-C and Swift: none. `inventory.py file`: "Objective-C
  subclasses: none found; Swift subclasses: none found". The census finds
  subclasses only when they override something, so the evidence that holds
  is the text search in section 0: the name appears in no other source file.
- Categories and class extensions: none (`inventory.py file`: "class
  extensions: none found; categories: none found; Swift extensions in scope
  (0)").
- Protocols adopted: none. Protocols whose methods it implements without
  declaring them: none; the one selector is declared by nothing outside the
  repository (`sdkmethods`: 0) and by no protocol in it (`methods`: the class
  only; `reach`: no Swift protocol with a matching requirement).

## E7. Stored-state surfaces

None. Established by: no `NSCoding` or `NSSecureCoding` (runtime snapshot:
no protocols; no `encodeWithCoder:`/`initWithCoder:`); no user defaults key
(the unit has no string literal at all); no arrangement dictionary; it
writes no file. It reads one file, the image at the path it is given, in
whatever format `NSImage` decodes; that path is a profile value
(`KEY_ICON_PATH`, `"Custom Icon Path"`) read by `PTYSession`, not by the
unit. The census found no persisted or wire name (section 8: 0).
stored-state.md has nothing to apply.

## E8. Concurrency table

| Item | Entry |
|---|---|
| Locks | none (`classstate`: `synchronized 0` for every ivar; no lock calls in the file) |
| State touched from more than one thread | none known |
| Atomic properties | none (no properties) |
| Atomic or volatile variables | none |
| Blocks dispatched elsewhere | none (no blocks in the unit; `classstate`: `blocks 0`) |
| `-imageAtPath:ofSize:flipped:` | main thread, by its call sites; asserted on one path only (below) |
| `-init` | main thread, the same call site |

How the thread is known, by reading. The only caller is
`-[PTYSession customIconImageForProfile:]`, whose only callers are
`-[PTYSession tabGraphicForProfile:]` (`PTYSession.m:7334`) and
`-[PTYSession customIconImage]` (`PTYSession.m:7342`, which itself has no
caller: `cdb reach customIconImage` finds 0). `tabGraphicForProfile:` is
called from:

- `-[PTYSession tabGraphic]` (`PTYSession.m:7310`), the `nullable` property
  read by `-[PTYTab psmTabGraphic]` (tab bar drawing, `PTYTab.m:1490`),
  `-[PseudoTerminal rootTerminalViewCurrentTabIcon]` (`PseudoTerminal.m:14470`),
  `iTermTabSwitcherItem.init(tabViewItem:lastSeen:)` (`iTermTabSwitcher.swift:94`),
  and the delegate calls in `-setCurrentForegroundJobNameForTmux:` (from an
  `iTermTmuxOptionMonitor` block, `PTYSession.m:10919`) and `-jobPidDidChange`
  (from an `iTermVariableReference` change block, `PTYSession.m:1052`);
- `-[PTYSession reallySetPreferencesFromAddressBookEntry:terminal:]`
  (`PTYSession.m:6985`), run inside `-[VT100Screen performBlockWithJoinedThreads:]`,
  which runs its block synchronously on the calling thread with the
  mutation thread joined, and which asserts the main queue:
  `-[VT100ScreenMutableState performBlockWithJoinedThreads:]` calls
  `[iTermGCD assertMainQueueSafe]` (`VT100ScreenMutableState.m:7099`)
  (found by the dossier's reviewer).

All of these are AppKit drawing, UI construction, tmux gateway callbacks and
variable-change callbacks, which run on the main thread in this app. Only
the profile-change path asserts it; the drawing, tab switcher, tmux and
job-change paths do not. Confidence: high, not proven for those paths. Per
[concurrency.md §9](../concurrency.md) the port adds a beta assertion of the
main thread at the entry of the method (section 14).

The unit holds no state shared across threads, so the thread sanitizer run
at the close of the unit that [concurrency.md §10](../concurrency.md) asks
for "any unit whose dossier shows state shared across threads" does not
apply.

## E9. Ownership graph and lifetime

```
PTYSession --(_customIcon, manual retain: +1 from alloc/init at PTYSession.m:7347,
              released at PTYSession.m:1445 in -dealloc)--> iTermCacheableImage
iTermCacheableImage --(_path, strong, a copy of the argument)--> NSString
iTermCacheableImage --(_image, strong)--> NSImage
```

- Held strongly by exactly one object: its `PTYSession`, through the
  private ivar `_customIcon` (`cdb ivarrefs PTYSession _customIcon`: 4
  references, all in `PTYSession.m`: the `release` in `-dealloc` at 1445,
  the nil test at 7346, the assignment of the owned `alloc`/`init` result at
  7347, the send at 7351). Created lazily on the first call of
  `customIconImageForProfile:`, never replaced, freed when the session is
  deallocated.
- Holds `_path` (a copy) and `_image` strongly. Each miss replaces both;
  the previous `NSImage` is released then (once any autorelease pool holding
  the returned reference drains).
- No delegate, back-pointer, block, timer, observer, notification or display
  link. No cycle is possible: nothing it holds refers back.
- No `dealloc`; ARC's `.cxx_destruct` releases the two objects. Nothing
  visible happens at teardown, so no lifetime witness test is required
  ([lifetimes.md](../lifetimes.md): "for each class with meaningful
  teardown"); the dossier's plan has a cheap one anyway for the returned
  image.
- The returned image is returned at +0 (ARC `return _image` autoreleases for
  a non-ARC caller), and the cache keeps it alive until the next miss. The
  MRC caller does not retain it; neither do its callers before returning it
  onward. A Swift `@objc` method returns at +0 the same way.

## E10. Messaging nil

| Site | Receiver or argument that can be nil | Zero result and what it causes |
|---|---|---|
| line 19, `_image &&` | `_image` nil before the first load and after any failed load | no hit, so the file is loaded again on every call while the last load failed |
| line 20, `path &&` | `path` nil (see section 12) | no hit; then `_path = [nil copy]` is nil and the load returns nil |
| line 22, `[path isEqualToString:_path]` | not reached with nil, guarded on lines 20 and 21 | none |
| line 28, `[path copy]` | `path` nil | `_path` becomes nil |
| line 32, `initWithContentsOfFile:path` | `path` nil, empty, missing, a directory, not an image, empty file | returns nil, no exception (probe below). For nil this passes nil to a parameter AppKit declares nonnull (section 12); the `fix` commit stops that |
| line 34, `[_image it_verticallyFlippedImage]` | `_image` nil after a failed load | nil; `_image` stays nil |
| line 36, `_image.size` | `_image` nil | `NSZeroSize`, so `NSEqualSizes(size, _image.size)` is false for any non-zero `size` and line 37 runs |
| line 37, `[_image it_imageOfSize:size]` | `_image` nil | nil; also returns nil itself when `!self.isValid` |
| line 39, `return _image` | | nil is returned to `PTYSession`, whose `tabGraphic` is `nullable` and whose consumers handle nil (section 12) |

Probe of `-[NSImage initWithContentsOfFile:]` (scratch program
`tmp/dossier-iTermCacheableImage/probe.m`, built with
`xcrun clang -fobjc-arc -framework Cocoa probe.m -o probe` and run with its
directory as argument):

```
nil path:     image=0x0 valid=0 size={0, 0}
empty path:   image=0x0 valid=0 size={0, 0}
missing file: image=0x0 valid=0 size={0, 0}
text file:    image=0x0 valid=0 size={0, 0}
empty file:   image=0x0 valid=0 size={0, 0}
directory:    image=0x0 valid=0 size={0, 0}
real png:     image=0x76b3084960 valid=1 size={512, 512}
```

(the row labeled "real png" is an `.icns` file,
`/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns`.)
A nil path does not raise on macOS 27; that was measured on macOS 27 only,
and is moot once the `fix` commit stops passing nil to AppKit.

Truncated PNGs (the dossier reviewer's probe,
`tmp/review-dossier/probe.m`, fixtures under `tmp/review-dossier/fx/`):
"truncated" is not one case. The PNG signature alone (8 bytes), the
signature plus `IHDR` (33 bytes), and the first half of a 20x20 PNG all
give nil; a 16x16 PNG with only its last 12 bytes (`IEND`) removed loads
as a valid 16x16 image. A test of a truncated file must name its cut
point.

## E11. Ivar table

`cdb classstate "${RM[@]}" iTermCacheableImage` (exit 3): 4 ivars, 0
statics; importable: yes 4. For every ivar: declared in the
`@implementation` block of the `.m`, private; mode ARC; 0 references from
outside the class's own code; 0 in blocks, lambdas or `@synchronized`; all
users in `-imageAtPath:ofSize:flipped:`. Accessor names: for each of
`-path`/`-setPath:`, `-image`/`-setImage:`, `-size`/`-setSize:`,
`-flipped`/`-setFlipped:`, "none in the repository, the SDK headers and the
run-time lists" in all six lists above, so no collision with a private
framework method.

| Ivar | Importable | Same-named accessor | Declared | Users | Reached from outside | Ownership | Guard | Frequency | Decision | Name | Reason |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `NSString *_path` | yes | none | `.m` | reads 2 (21, 22), write 1 (28) | no | strong, a copy | main thread | cold | stored property of the Swift class | `path` (private) | whole-class port: state moves with the class; no `ivar_` shim |
| `NSImage *_image` | yes | none | `.m` | reads 6 (19, 25, 34, 36, 37, 39), writes 3 (32, 34, 37) | no | strong | main thread | cold | stored property | `image` (private) | as above |
| `NSSize _size` | yes | none | `.m` | read 1 (23), write 1 (29) | no | none (struct) | main thread | cold | stored property | `size` (private) | as above |
| `BOOL _flipped` | yes | none | `.m` | read 1 (24), write 1 (30) | no | none (scalar) | main thread | cold | stored property | `flipped` (private) | as above |

[objc-state.md §2](../objc-state.md) and its `ivar_` scheme apply to an
incremental port, where Swift must reach ivars of a class that stays
Objective-C. This unit moves whole in one commit, so its ivars become
Swift stored properties directly and no shim exists at any point. The
names are private and not `@objc`, so they add nothing to the runtime
surface and become no key-value coding keys (the trap in objc-state.md §2
about a new property looking like public API does not arise). Nothing
reaches the ivars by name: no key-value coding (the class has no
properties and the census section for key-value coding is 0), no
`obj->_ivar` from outside.

## E12. Nullability of every position

The header is under `NS_ASSUME_NONNULL`, so every pointer position below is
claimed `nonnull` today without proof
([nullability.md §3](../nullability.md): existing claims are treated as
unverified).

| Position | Direction | Claimed today | Evidence | Safe answer | Rule |
|---|---|---|---|---|---|
| return of `-imageAtPath:ofSize:flipped:` | outward | `nonnull` (implicit) | Returns nil for a nil, empty, missing, directory, non-image or empty-file path (probe, section 10), and `it_imageOfSize:` is `_Nullable` and returns nil for an invalid image. Failable construction from a file read is in the always-`nullable` list. Counter-evidence that callers expect nil: `-[PTYSession tabGraphic]` is declared `nullable` (`PTYSession.h:771`), `-sessionDidChangeGraphic:shouldShow:image:` takes a `nullable` image (`PTYSession.h:358`), `-psmTabGraphic` is `nullable` (`PSMTabBarControl.h:103`), and the Swift reader binds it optionally (`icon = session?.tabGraphic`, `iTermTabSwitcher.swift:94`) | `nullable` | O-default (no O rule applies; failable construction); the claim today is wrong in the dangerous direction |
| `path` | inward | `nonnull` (implicit) | Tested on line 20 and messaged with `copy` on line 28, both tolerant. But line 32 passes it to `-[NSImage initWithContentsOfFile:]`, whose parameter AppKit declares nonnull (`NSImage.h:108`, inside `NS_HEADER_AUDIT_BEGIN(nullability, sendability)` at line 25). That call returns nil for nil on macOS 27 (probe) but the nullability sanitizer reports it (below). So as the code stands the position is neither I1 (I1 does not allow passing nil to an SDK nonnull position) nor I2 (no known failure). The one caller passes `+[iTermProfilePreferences stringForKey:inProfile:]`, declared `NSString * _Nullable` (`iTermProfilePreferences.h:71`); in practice it is never nil, because the key's default is `@""` (`iTermProfilePreferences.m:961`) and `uncomputedObjectForKey:` falls back to it, but the profile value is untyped (`profile[key]`), so a hand-edited or API-written profile could hold a non-string there | `nullable`, only after the `fix` commit | After the fix (`_image = path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;`), I1: tested, messaged, never handed to a nonnull position. Recorded no-op for nil: no hit, `_path` and `_image` become nil, `_size` and `_flipped` take the new values, returns nil. Before the fix, the triage's `sdk-claim` category (nil handed to an Apple nonnull parameter that tolerates it) |
| `size` | inward | n/a (struct) | | | |
| `flipped` | inward | n/a (`BOOL`) | The caller passes the literal `NO` (`PTYSession.m:7350`) | | |
| `-init` return (inherited) | outward | `nonnull` (SDK) | `-[NSObject init]` | unchanged | O5 |

Counter-evidence that consumers tolerate nil (dossier reviewer):
`-[PTYSession tabGraphicForProfile:]` returns nil for
`iTermProfileIconNone` (`PTYSession.m:7316`), which is the default
(`iTermProfilePreferences.m:960`), so every session with default settings
already hands nil to every consumer of `tabGraphic`.

The sanitizer report for the nil path, from Step A's test before its fix
(`tools/swift_migration/sanitizer_tests.sh nullability ModernTests/iTermCacheableImageNilPathTests`,
run `tmp/sanitizers/runs/nullability-20261121-133649`):

```
3  invalid-null-argument  sources/SessionIcons/iTermCacheableImage.m:32:54
   null pointer passed as argument 1, which is declared to never be null
   in -[iTermCacheableImage imageAtPath:ofSize:flipped:]
```

The dossier reviewer reproduced the same report with a scratch program
mirroring line 32 under a `nullable` parameter (`tmp/review-dossier/san.m`),
which shows that annotating `path` alone would not stop it.

What the wrong claims do today: nothing, at run time, because no Swift sees
the header and the one caller is Objective-C. Under the nullability
sanitizer ([nullability.md §7](../nullability.md)) a nil return would be
reported at the `return` ("A method declared nonnull returns nil: Yes"), so
any test that drives a failed load through the current header fails in the
sanitizer configuration with `halt_on_error`. No such test exists, and the
suppression list has no entry for this file
(`grep -i cacheable tools/swift_migration/sanitizer_nullability_suppressions.txt`:
nothing). Both claims must be corrected before the port: the port's Swift
signature is written from the audited header, and a non-optional `path`
parameter in Swift would receive whatever `stringForKey:` returns
([nullability.md §6](../nullability.md)).

Ivars: `_path` and `_image` are nil in a new object and after a failed
load; both are optional in the port.

**Dependencies that are not yet annotated** (the on-demand list): none.
`NSImage+iTerm.h` is under `NS_ASSUME_NONNULL` with `it_imageOfSize:`
explicitly `_Nullable` and `it_verticallyFlippedImage` `nonnull`, which
holds (`it_imageScaledByX:y:` returns `self` or the result of
`+imageOfSize:drawBlock:`, which returns `[[NSImage alloc] initWithSize:]`).
The receiver of both can be nil here, which Swift's optional chaining shows.
The SDK's `-[NSImage initWithContentsOfFile:]` is a nullable failable
initializer whose `fileName` parameter is nonnull (above).

## E13. Integer and floating-point conversions; the arithmetic table

There is no implicit conversion and no arithmetic in the unit. The strict
set reports nothing on either architecture (section 5).

- `NSEqualSizes(size, _size)` (line 23) and `!NSEqualSizes(size, _image.size)`
  (line 36) compare two `CGFloat` pairs with `==`, no conversion. Exact
  equality: `-0.0` equals `0.0`, a NaN never equals anything, so a NaN size
  never hits and always resizes. The port calls `NSEqualSizes` itself, which
  Swift imports, rather than `==` on `CGSize`, so the comparison is the same
  function.
- `flipped == _flipped` (line 24) compares two `BOOL`s. On x86_64 a `BOOL`
  is a `signed char`, and a caller passing an integer other than 0 or 1
  would make `2 == 1` false where Swift `Bool` would compare true with true;
  the only caller passes the literal `NO`, so this cannot happen in the app
  ([nullability.md §10](../nullability.md)).
- The caller's `NSMakeSize(16, 16)` converts integer literals to `CGFloat`
  exactly.

Arithmetic table: no rows (no `+`, `-`, `*`, shift, division or integer
conversion in the unit).

## E14. Implicit assumptions that would make good assertions

- **Main thread at the entry of `-imageAtPath:ofSize:flipped:`** (section 8).
  Recommended as an `it_betaAssert(Thread.isMainThread, ...)` in the port,
  per [concurrency.md §9](../concurrency.md). Adding it in the port is an
  addition of an assertion, which the process asks for, not a behavior
  change in release builds ([assertions.md](../assertions.md)).
- Considered and not recommended: that a non-nil result has the requested
  size. It is true by construction (the no-resize path is taken only when
  the sizes are equal, and `it_imageOfSize:` builds the image with
  `initWithSize:size`), so it would assert nothing that can fail.

## E15. Hot-path status

Not hot. The method runs when the tab bar draws a tab with a custom icon,
when the tab switcher builds an item, when the window title icon is read,
when the profile changes, and when the foreground job changes. That is not
per character, per cell, per token, or per Metal frame. `inventory.py file`:
"hot-path directory: no". A hit costs two comparisons and one
`isEqualToString:`. One cost worth knowing: when the custom icon file is
missing or unreadable, every call reads the file system again, because a
nil image never hits (section 10). That is existing behavior, preserved.

## E16. Test coverage today

None, of the class or of the PTYSession path that uses it. Established by:

- Census section 9 (tests): 0; `-imageAtPath:ofSize:flipped:` has `tests 0`
  in the class census; `git grep -n -i 'CacheableImage\|customIcon\|KEY_ICON_PATH\|iTermProfileIconCustom\|"Custom Icon Path"' -- ModernTests sources/iTermTests PerformanceTests`
  finds nothing; `git grep -n 'KEY_ICON\|iTermProfileIcon\|"Icon"' -- ModernTests`
  finds nothing. The class is reachable only through
  `tabGraphicForProfile:` with a profile whose `KEY_ICON` is
  `iTermProfileIconCustom` (2), and the default is
  `iTermProfileIconNone` (`iTermProfilePreferences.m:960`), so no test that
  reads `tabGraphic` without setting the key can reach it. The one test
  double with `psmTabGraphic` (`PSMTabGroupDragInvariantTests.swift:224`)
  returns nil without a session.
- The per-function coverage tool was tried and cannot answer cheaply: no
  coverage run of the whole suite exists. The runs under
  `$MAIN/tmp/coverage/runs/` are small tool-validation runs, and the
  largest gave:

  ```bash
  python3 -B $MAIN/tools/swift_migration/coverage_report.py function \
      '-[iTermCacheableImage imageAtPath:ofSize:flipped:]' \
      --run $MAIN/tmp/coverage/runs/20261120-085947 --codedb $MAIN/tmp/codedb/codedb.sqlite
  ```
  ```
  Incomplete: .../iTerm2.debug.dylib changed since the run (rebuilt?); its counts are not used
  Incomplete: -[iTermCacheableImage imageAtPath:ofSize:flipped:] was not found in the profile's binaries
  Verdict: incomplete: the function was not found
  ```
  (exit 3). A new coverage run means a full suite run with coverage, which
  this step does not do. Step 3 should run `coverage_report.py function` on
  a coverage run of its own new tests to show every branch exercised.

## E17. Verifying runtime behavior

Everything the port changes is reachable from the test host, so the
lightest check is level 1, tests:

- The class itself, constructed directly with images written to a
  temporary directory.
- The wiring in the MRC caller (`alloc`/`init` from manual reference
  counting, the call, the `release` in `-dealloc`) through
  `PTYSession(synthetic: false)`, `session.profile = [KEY_ICON: 2,
  KEY_ICON_PATH: <file>]` and `session.tabGraphic`, as other tests already
  create sessions (`AITabTitleGeneratorTests.swift:1861`, which also sets
  `session.profile`). `tabGraphic` is declared in `PTYSession.h`, which the
  bridging header imports.

No temporary app change and no VM QA is needed: no xib, no First Responder
action, no responder chain, no drawing that a test cannot inspect (the test
reads the returned image's size and identity). What tests do not reach: the
pixels the tab bar draws with the image; the port does not touch drawing.

## E18. The `fix` and `annotate` commits: tests, sanitizer, snapshot, object code

Step A test, `ModernTests/iTermCacheableImageNilPathTests.m` (three tests: a
nil path gives nil twice; a good path loads after a nil path; good, nil,
good gives a new object). Before the fix it calls with nil through an
`NSInvocation`, so the sanitizer sees the method's own use of the path and
not this file's call against the header's nonnull claim (a direct call
was tried first and was reported at the test's own call sites, lines 70, 77
and 95, before the method ran).

| Run | Tree | Result |
|---|---|---|
| `tools/run_tests.expect ModernTests/iTermCacheableImageNilPathTests` | before fix | 3 passed |
| `tools/swift_migration/sanitizer_tests.sh nullability ModernTests/iTermCacheableImageNilPathTests` | before fix | status 65; 3 started with no result; 3 `invalid-null-argument` at `iTermCacheableImage.m:32:54` (run `nullability-20261121-133649`) |
| same | after fix | 3 passed, 0 reports (run `nullability-20261121-134018`) |
| `tools/run_tests.expect ...` | after fix | 3 passed |
| `tools/build.sh` | after fix | succeeded; only the `appintentsmetadataprocessor` notice, also in the baseline log |
| `tools/build.sh` | after annotate | succeeded; three Swift concurrency warnings in `CompanionMainThreadMonitor.swift:120` and `CompanionWizardWindowController.swift:606`, which the bridging header change made recompile; a build of the fix-only tree with those two files touched gives the same three (`tmp/dossier-iTermCacheableImage/build-baseline-A.log`), so they are not new |
| `tools/run_tests.expect ...` and the sanitizer | after annotate (test calls with a literal nil) | 3 passed; sanitizer 3 passed, 0 reports (run `nullability-20261121-135121`) |

Interface snapshot, before and after the annotate (`objc` and `import`
sections; the after run gives the changed header and bridging header to the
compiler through `--overlay`, a directory holding copies of the two files):

```bash
S=$MAIN/tools/swift_migration/swift_interface.py; D=$PWD/tmp/dossier-iTermCacheableImage
python3 -B $S snapshot --sections objc,import --work $D/swift-interface-B --accept-stale --out $D/iface-before.snapshot
python3 -B $S snapshot --sections objc,import --work $D/swift-interface-B --accept-stale --overlay $D/overlay-B --out $D/iface-after.snapshot
python3 -B $S diff $D/iface-before.snapshot $D/iface-after.snapshot
```
```
=== import: class (1 added)        iTermCacheableImage: open class iTermCacheableImage
=== import: conformance (6 added)  NSObjectProtocol, CVarArg, CustomDebugStringConvertible,
                                   CustomStringConvertible, Equatable, Hashable
=== import: inheritance (1 added)  iTermCacheableImage : ObjectiveC.NSObject
=== import: method (1 added)       iTermCacheableImage.image(atPath:of:flipped:)
      after:  open func image(atPath path: String?, of size: NSSize, flipped: Bool) -> NSImage?
--- 9 added, 0 removed, 0 changed
```

Swift drops `Size` from the second label because the parameter's type is
`NSSize`: the port must spell it `of size:` so the tests run unchanged. The
only member is the method, with both positions optional, as claimed; the
other eight lines are the class and what every `NSObject` subclass gets.
Nothing else in either section changed.

Object code: `iTermCacheableImage.o` from the build after the fix and from
the build after the annotate are byte-identical (`cmp` succeeds; `otool -t`
digests equal), so the annotation changed no generated code.
`iTermCacheableImage.m` is not under `NS_ASSUME_NONNULL` and its
implementation signature has no nullability, so it needs no change.


Full suite with both commits applied, `tools/run_tests.expect -parallel`
(10 min 40 s): 11,963 passed, 688 skipped, 1 failed:
`AsyncFilterDeliveryQueueTests.testDeliveriesQueuedDuringCatchUp`. It passed
when re-run alone and with its class without `-parallel`; it does not touch
this unit. Two sibling `AsyncFilter` tests are already disabled as flaky in
`bugs.md`.
