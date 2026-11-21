# Dossier: iTermCacheableImage

Pilot unit 1 of the migration ([lifecycle.md §1](../lifecycle.md), step 2).
Evidence, with every command and its output, is in
[iTermCacheableImage.evidence.md](iTermCacheableImage.evidence.md); "E7" means its section E7.

## Unit

`sources/SessionIcons/iTermCacheableImage.h` and `.m`: one class, 42 lines, target
`iTerm2SharedARC`, ARC. A one-entry cache of a custom tab icon: one method,
`-imageAtPath:ofSize:flipped:`, four private ivars.

## Claims the later steps rely on

| Claim | How established | Evidence |
|---|---|---|
| One caller: `-[PTYSession customIconImageForProfile:]`, `PTYSession.m:7351` (manual reference counting) | code database `reach` and the census, plus `git grep` of every tracked file | E0, E1 |
| No Swift user, no subclass, category or extension in either language | census, `inventory.py`, `git grep` | E1, E6 |
| Runs on the main thread only; asserted on one call path (profile change, through `performBlockWithJoinedThreads:`), not on the drawing, tab switcher, tmux and job-change paths | reading every call path | E8 |
| The return can be nil: it is `nullable` | probe of the load; `it_imageOfSize:` is `_Nullable`; every consumer is `nullable` and already gets nil for the default icon setting | E10, E12 |
| `path` can be nil and is tolerated by I1 once the `fix` commit stops passing it to AppKit | reading; caller passes `stringForKey:`, declared `_Nullable`; sanitizer report at line 32 before the fix | E12 |
| Owned only by its `PTYSession` (+1 at creation, released in `-dealloc`); holds `_path` (a copy) and `_image` strongly; no cycle, no teardown work | `ivarrefs`, `classstate`, runtime snapshot | E2, E9, E11 |
| No stored state | runtime snapshot (no protocols), no string literals, census persisted names 0 | E7 |

## Hazards found

| Hazard | What the work must do |
|---|---|
| The header claims `nonnull` for the return and for `path`; both can be nil | `annotate` both `nullable` before the Swift tests and the port |
| Line 32 passes a nil `path` to `-[NSImage initWithContentsOfFile:]`, whose parameter AppKit declares nonnull; the nullability sanitizer aborts there | `fix` commit: skip the call when `path` is nil (the result is nil either way) |
| A failed load stores nil, and nil never hits, so a missing icon file is read again on every call | preserve; pinned by tests |
| The key is compared with `isEqualToString:` (UTF-16 units); Swift `==` on `String` uses canonical equivalence | compare as `NSString` in the port; pinned by a Unicode test |
| The only caller is a manual-reference-counting file: `alloc`/`init` at +1, `release` in `-dealloc`; the image comes back at +0 | keep the class name and `-init`; an integration test through `PTYSession` |
| No test exercises the class or its `PTYSession` path today | characterization tests (step 3) |

## Checked and clear

| Check | Result | Evidence |
|---|---|---|
| xib custom class or File's Owner | 0 | E4 |
| First Responder actions | 0 | E4 |
| Reflective sites in the unit | 0 | E4 |
| Reflective sites elsewhere that can reach it | 0 (only hostile input to open class-from-string sites) | E4 |
| Persisted or scripted names | 0 | E1, E4 |
| Subclasses, Objective-C and Swift | 0, 0 | E6 |
| Categories and extensions | 0 | E6 |
| Protocols adopted or implemented undeclared | 0 | E6 |
| Stored state: `NSCoding`, user defaults keys, files written | 0, 0, 0 | E7 |
| Locks, queues, dispatched blocks | 0, 0, 0 | E8 |
| Strict-set warnings, arm64 and x86_64 | 0, 0 | E5 |
| Integer and float conversions; arithmetic sites | 0; 0 | E13 |
| Accessor name collisions (repository, SDK, six run-time lists) | 0 | E11 |
| Hot path | no | E15 |

## Plan

1. `fix`: `_image = path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;` in the `.m`. Objective-C test first (`ModernTests/iTermCacheableImageNilPathTests.m`).
2. `annotate`: return and `path` `nullable`; add the header to `sources/iTerm2SharedARC-Bridging-Header.h`. Swift then sees `image(atPath: String?, of: NSSize, flipped: Bool) -> NSImage?` (`of:`, not `ofSize:`).
3. `test`: Swift characterization tests against that interface, unchanged afterwards.
4. `port`: whole class in one commit; delete the `.h` and `.m`, drop the import from `PTYSession.m:99` (it already imports `iTerm2SharedARC-Swift.h`) and from the bridging header.

```swift
@objc(iTermCacheableImage) class iTermCacheableImage: NSObject {
    private var path: NSString?; private var image: NSImage?
    private var size = NSSize.zero; private var flipped = false
    @objc(imageAtPath:ofSize:flipped:)
    func image(atPath path: String?, of size: NSSize, flipped: Bool) -> NSImage?
}
```

As ported: the key is compared with `NSString` `-isEqual:` (literal, as `-isEqualToString:` is, and the `String` parameter bridges back to the caller's `NSString` unchanged, so the comparison sees its original UTF-16 units), stored as `key?.copy() as? NSString` (the key is always an `NSString` here, so the cast cannot drop it), `NSEqualSizes`, `image?.size ?? .zero`, and a main-thread `it_betaAssert` at entry (concurrency.md §9 and §10). The runtime snapshot must keep `-imageAtPath:ofSize:flipped:` with encoding `@44@0:8@16{CGSize=dd}24B40`.

Characterization tests (step 3), fixtures written to a temporary directory:

- Hit: same path, size and `flipped` returns the identical object (`===`).
- Miss on each of path, size and `flipped` changed alone; back to the first inputs misses again (one entry).
- A mutated `NSMutableString` key does not change the entry; an equal string object hits; precomposed and decomposed forms of a name miss.
- nil path returns nil; a good path loads afterwards.
- A failed load is never a hit: no file at P gives nil; create a valid image at P; the same call returns non-nil.
- A failed load replaces the entry: good A, then missing B (nil), then A again returns an object `!==` the first.
- Missing file, empty path, directory, text file, empty file, PNG cut to its 8-byte signature: each nil. (A PNG missing only `IEND` loads; not a failure case.)
- Natural size requested and a different size requested: the result has the requested size.
- Flipped: final size and top and bottom pixel colors only, which hold on 1x and 2x displays (the flip runs different branches on each).
- `NSZeroSize`: pin what the Objective-C returns.
- Through `PTYSession(synthetic: false)` with a custom icon profile: a 16x16 `tabGraphic`, the same instance twice, nil for a missing file.
- Optional: a weak reference to an old image becomes nil after a miss once the autorelease pool drains.

## Open questions and risks

- A NaN size is left out of the tests and was not probed: it reaches `lockFocus` through `it_imageOfSize:`; the app passes only 16x16.
- Resolved: in an x86_64 build the Swift method is encoded `@44@0:8@16{CGSize=dd}24c40`, the same `c` as Objective-C `BOOL` there (E19). Nothing was run for x86_64: no Rosetta.
- Thread confinement is by reading on four of five paths; the port's beta assertion will show any exception in nightly and beta builds.
- A non-string icon path in a hand-edited profile now raises in the Swift bridging thunk instead of inside AppKit; the app crashes on either (E19).

## Considered and rejected

- Filing `path` under I1 as the code stood: rejected in review, because line 32 handed nil to an AppKit nonnull parameter (E12). Hence the `fix` commit first.
