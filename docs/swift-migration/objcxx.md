# Objective-C++ files

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

There are 14 `.mm` files in scope, all in `sources/`, as surveyed in the
review of 2026-11-18:

| File | Lines | C++ used | Hot path |
|---|---|---|---|
| `LineBuffer/LineBlock.mm` | 3,080 | Several standard library types | Yes |
| `MetalRenderer/Renderers/iTermTextRendererTransientState.mm` | 900 | Some | Yes |
| `Metrology/iTermHistogram.mm` | 691 | `vector`, `map`, `sort`, `shuffle`, `mt19937`, `random_device`, numeric algorithms | No |
| `MetalRenderer/Renderers/iTermTextRenderer.mm` | 594 | Little | Yes |
| `MetalRenderer/Infrastructure/iTermSubpixelModelBuilder.mm` | 348 | Some | Yes |
| `MetalRenderer/Renderers/iTermBackgroundColorRenderer.mm` | 285 | `iTerm2::PIUArray`, `static_cast` | Yes |
| `LineBuffer/iTermCumulativeSumCache.mm` | 203 | Some | Probably |
| `Infrastructure/iTermTaskQueue.mm` | 195 | `std::vector` | No |
| `ExternalSessionState/iTermColorVectorCache.mm` | 167 | `std::move`, `std::swap` | Check |
| `MetalRenderer/Glue/iTermRowOutputCache.mm` | 147 | Some | Yes |
| `MetalRenderer/Renderers/iTermHighlightRowRenderer.mm` | 131 | Little | Yes |
| `DataStructuresAlgorithms/iTermLegacyAtomicMutableArrayOfWeakObjects.mm` | 126 | `std::atomic` | No |
| `LineBuffer/LineBufferSorting.mm` | 68 | `std::sort`, `std::unordered_map` | Check |
| `MetalRenderer/Renderers/iTermTexturePageCollection.mm` | 26 | None in the `.mm`; its header and `iTermTexturePage.h` include C++ | Yes |

Two headers include C++ standard library headers
(`iTermTexturePageCollection.h` and `iTermTexturePage.h`), so they cannot be
put in the bridging header.

Most of these files are hot paths and wait under [performance.md §2](performance.md). For the rest:

**Classify each file.** The inventory script ([phase0.md §1](phase0.md)) puts each in one
of four classes: no C++ at all, incidental C++ (a container or algorithm used
privately), C++ in its header, or C++ that is essential to performance.

**No C++ at all.** A preparation commit renames the file to `.m` with
`git mv`. The build and the runtime snapshot must be unchanged. The file then
follows the normal path, including the hot-path rule. No confirmed example
exists yet: a check of their contents on 2026-11-19 found C++ in every file
in the table above.

**Incidental C++.** A `decxx` commit, in Objective-C, replaces the C++ with C
or Foundation, keeping behavior identical, then renames the file to `.m`.
This keeps the behavior change visible in a small Objective-C diff, by the
principle in [README.md §4](README.md). Points to watch:

- `std::sort` is not stable, and its order for equal elements is
  implementation-defined. Swift's `sort` happens to be stable today but does
  not promise it. Where elements can compare equal, the characterization
  tests pin the order the code depends on; if nothing depends on it, the
  dossier says so.
- `std::unordered_map` and `std::map` differ from `NSDictionary` in iteration
  order and in key equality and hashing. Check every iteration over the map.
- `std::vector` growth and iterator invalidation rules differ from
  `NSMutableArray` and from Swift arrays. Check any code that holds an
  iterator, pointer or reference into a vector across a mutation.
- Random number generation (`mt19937`, `random_device`, `shuffle`): if the
  sequence is ever seeded deterministically, by tests or otherwise, the
  replacement must give the same sequence, or the tests change in a separate
  `test` commit. If it is never seeded, any generator will do.
- `std::atomic` follows [concurrency.md §4](concurrency.md): it stays in C. Replace it with a C11
  `_Atomic` behind inline C functions, which Swift can call, and keep the
  same memory ordering. Before touching
  `iTermLegacyAtomicMutableArrayOfWeakObjects`, check whether its name means
  it is already being retired; if so, leave it alone.
- Destructors and RAII: for a C++ ivar in an Objective-C class, the
  destructor runs after the `dealloc` body, in reverse order of declaration.
  The `dealloc` audit in [arc.md](arc.md) covers these too.
- Exceptions: C++ code that can throw (`std::vector::at`, allocation failure)
  must not unwind through Objective-C or Swift frames. The dossier notes
  where the original could throw and what happened.

**C++ in a header.** Until the header is free of C++, nothing it declares is
visible to Swift. Either move the C++ out of the header (into the `.mm`, or
behind an opaque pointer or an Objective-C facade) in a preparation commit,
or wait with the hot path.

**C++ essential to performance.** In practice these are the hot paths, and
they are deferred under [performance.md §2](performance.md). When their turn comes, the options
include staying in C++ behind a C or Objective-C interface, rewriting in C,
or Swift's C++ interoperability. That interoperability has to be enabled for
the whole Swift module, which changes how every header is imported, so it is
an owner decision with its own evaluation and is not used in stage one.

**Do not port C++ directly to Swift in one step.** Removing the C++ first, in
Objective-C, and then porting the result keeps translation and behavior
change in separate commits, as with the other preparation kinds.
