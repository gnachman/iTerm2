# Order of work and what the pilot must validate

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

## 1. Order of work

1. **Phase 0.** Everything in [phase0.md](phase0.md). The end of Phase 0 is
   an owner checkpoint. On 2026-11-21 the owner approved starting the pilot
   with some items unfinished; they continue alongside it
   ([decisions.md](decisions.md)), and each must be done before the tier
   that needs it: extraction analysis before the giant classes, the
   performance baseline before the hot paths.
2. **Pilot.** Five to ten units chosen to exercise different parts of the
   process end to end: a Foundation category, a file under manual reference
   counting, an `NSCoding` class, a view controller with a xib, a pure data
   structure, a class with a delegate protocol, and a class with Objective-C
   subclasses. Measure the time per step and the defects found by review and
   by crash reports. Revise the process files.
3. **Leaf tier.** The roughly 450 files with low fan-in.
4. **Middle tier.** Higher fan-in files and subclass trees, leaf-first.
5. **Widely imported foundations** (categories on `NSString`, `NSArray`,
   preferences, logging). These have hundreds of Objective-C importers and stay
   usable from Objective-C for a long time. Many callers are in Swift already,
   so they may be ported as `@objc` extensions early, but they are never
   eligible for stage two until the end.
6. **Giant classes**, by extraction, in parallel with tiers 3 to 5 once the
   pilot has proven the method.
7. **Hot paths.**

## 2. Things the pilot must validate

These are assumptions in the process files that have been checked only on a toy
example or not at all:

- That the interface snapshot tool works on real iTerm2 headers, which import
  many other headers, and that an identical snapshot really does mean no
  position was missed.
- That the nullability sanitizer can be enabled for the real test target, how
  noisy its first run is, and whether the Development-build reporting mode is
  practical.
- Whether the way the lints decide which files are migration files works on
  real ports. `tools/swift_migration/swift_lints.py` uses the trailer
  history ([phase0.md §6](phase0.md)).
- The cost of the gate per commit in wall-clock time, including the sanitizer
  run, and whether the full sanitizer suite should run on every commit or once
  per unit.
- That the runtime snapshot ([phase0.md §9](phase0.md)) is identical across a real incremental
  port, and identical in meaning across a real whole-class port, and what
  the list of expected differences is.
- The warning survey ([warnings.md](warnings.md)): hit counts per flag on both
  architectures, which flags go project-wide, and whether identical assembly
  is a workable check for `explicit` commits.
- That the fragment search in the census ([phase0.md §2](phase0.md)) is usable, meaning it
  finds the known reflective sites without burying them in noise.
- Which nibs can be instantiated in a test ([phase0.md §3](phase0.md)).
- How long hands-on QA on a VM takes per unit, and whether the line between
  the three kinds of runtime check ([lifecycle.md §1](lifecycle.md)) is drawn in the right place.
- Incremental porting ([lifecycle.md §2](lifecycle.md)) on a real class: moving methods into a
  Swift extension, overriding from an extension, exposing ivars through a
  private header, and detection of duplicate selectors.
- That the code database, which replaced searching preprocessed source
  ([decisions.md](decisions.md), 2026-11-19), finds the callers that macros
  hide in real files, and that its cross-check against the selectors in
  object files works ([hidden-callers.md §6](hidden-callers.md)).
- The fast test tier ([test-speed.md](test-speed.md)): its contents and its wall-clock time
  including the build, without the address sanitizer.
- [concurrency.md](concurrency.md): that the suite runs under the thread sanitizer, which tests
  reach Metal and must be excluded or suppressed, how many races the existing
  code reports, and the open questions in [concurrency.md §11](concurrency.md).
- [objc-state.md §1](objc-state.md) on a class with awkward state: how often each remedy is needed,
  how many shims a typical move costs, and how often nothing short of the
  flip works.
- [large-code.md §2](large-code.md) on one real oversized function: that a recording delegate gives
  a stable transcript, that per-function coverage can be reported, that the
  pure-move checker works, and whether comparing disassembly after an
  always-inline extraction is reliable enough to use.
