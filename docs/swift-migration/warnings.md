# Compiler warnings: survey and strict set

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The app builds with `-Wall`. `-Wextra` is on in only some configurations,
`-Wno-sign-compare` and `-Wno-nullability-completeness` are set explicitly,
and treating warnings as errors is a build setting in only some
configurations. Many warnings that find exactly the patterns this migration
cares about are therefore off.

A test on the current toolchain, on one file containing a set of known-bad
patterns, shows what the defaults miss:

| Pattern | Flag that reports it | Reported under `-Wall -Wextra` |
|---|---|---|
| `long long` or `NSUInteger` stored into `int` | `-Wshorten-64-to-32` | No (it is a separate setting, on in most configurations) |
| `double` stored into `int` | `-Wfloat-conversion` | No |
| `double` stored into `float` | `-Wimplicit-float-conversion` | No |
| `int` stored into `unsigned` | `-Wsign-conversion` | No |
| Signed compared with unsigned | `-Wsign-compare` | Yes, but the project turns it off |
| `unsigned >= 0` loop condition | `-Wtautological-unsigned-zero-compare` | No |
| Integer stored into `BOOL` | `-Wobjc-signed-char-bool-implicit-int-conversion` | No, and only on the Intel slice |
| Object pointer passed as `BOOL` | `-Wint-conversion` | Error on the Intel slice. Silent on Apple silicon, where it means `!= nil` |
| Message sent to a bare `id` | `-Wobjc-messaging-id` | No |
| Property that is atomic by default | `-Wimplicit-atomic-properties` | No |
| `assign` property of object type | `-Wobjc-property-assign-on-object-type` | No |
| `switch` with no `default` | `-Wswitch-default`. Not used: by the owner's rule a `switch` over an enum has no `default` | No |
| `int` compared with `NSNotFound` | none, even with `-Weverything` | No |
| Case falling through to the next | none fired in Objective-C | No |

Two lessons from that table. Several hazards differ between the Intel and
Apple silicon slices, so the survey must build both. And two common hazards
have no warning at all, so they need a search or a lint of their own.

Procedure:

1. **Survey.** Build both architectures once with `-Weverything`, not as
   errors, and tabulate the hits per flag and per file. This is a measurement,
   not a setting. The table is regenerated on demand, not stored.
2. **Triage each flag** into one of three groups, recorded in `decisions.md`:
   - *Project-wide.* Few hits, high value. Fix the hits in `explicit` or `fix`
     commits, then turn the flag on for everyone so the pattern cannot return.
   - *Strict set.* Too many hits to fix everywhere now (`-Wsign-compare` is
     the obvious example). The flag is turned on one file at a time, as
     described below, so nobody is faced with thousands of warnings at once.
   - *Report only.* Too noisy to enforce. The dossier tool still runs it on
     the unit and the hits are read.
3. **Candidate strict set**, to be confirmed by the survey: `-Wconversion` and
   its parts (`-Wshorten-64-to-32`, `-Wsign-conversion`, `-Wfloat-conversion`,
   `-Wimplicit-float-conversion`, `-Wimplicit-int-conversion`),
   `-Wsign-compare`, `-Wobjc-signed-char-bool`, `-Wtautological-compare` and
   its parts, `-Wobjc-messaging-id`, `-Wstrict-selector-match`, `-Wselector`,
   `-Wimplicit-atomic-properties`, `-Wobjc-property-assign-on-object-type`,
   `-Wswitch-enum`, `-Wconditional-uninitialized`,
   `-Warc-repeated-use-of-weak`, `-Wnullable-to-nonnull-conversion`,
   `-Wformat-nonliteral`, `-Wcast-qual`, `-Wshadow`, `-Wassign-enum`,
   `-Wfloat-equal`, and the static analyzer.
4. **One file at a time.** A single header, `iTermStrictWarnings.h`, holds the
   strict set as `#pragma clang diagnostic error "-W..."` lines. A file opts
   in by importing that header as its last import. A diagnostic pragma stays
   in effect after the header that contains it ends, so the flags apply to the
   rest of the importing file and to nothing else. (Confirmed on a toy file:
   a signed and unsigned comparison became an error only in the file that
   imported the header.) This has three useful properties: the strict set is
   defined in one place, opting in is one visible line in the file with no
   project file changes, and progress is derived by counting the files that
   import it. A unit's files opt in during preparation (step 4 in [lifecycle.md §1](lifecycle.md)).
   Code from our own headers that is expanded inside the file, such as inline
   functions and macros, is diagnosed there too; how noisy that is will be
   seen in the pilot.
5. **`explicit` commits.** For the unit's files, each strict-set hit is
   resolved in Objective-C before the port:
   - An implicit conversion gets an explicit cast that does what the compiler
     was already doing. This changes no behavior, and that can be checked: the
     generated assembly for the file, compiled without debug information,
     should be identical before and after. The port then transliterates
     explicit casts instead of reconstructing invisible ones.
   - A hit that reveals a bug (a comparison that is always true, an integer
     truncated into a `BOOL`) is not fixed here. It is logged, and the
     existing behavior is preserved with a cast and a comment.
   - A message to a bare `id` gets a typed receiver where the type is known,
     so the compiler checks the selector and the argument types.

**Switches over enums.** In Objective-C a `switch` over an enum lists every
case and has no `default:`, so that the compiler warns when a value is added.
`-Wswitch-default` would force a `default:` into exactly those switches and
is not used. `-Wswitch`, which is part of `-Wall`, is the flag that reports a
missing case when there is no `default:`; the survey confirms it is in
effect in every configuration. `-Wswitch-enum` stays a candidate because it
reports a missing case even where a `default:` exists, which pushes code
toward listing every case.

Treating warnings as errors is turned on in every build configuration once
the project-wide group is clean (the owner's decision of 2026-11-19). Until
then the gate treats warnings as errors regardless
([README.md §5](README.md)).
