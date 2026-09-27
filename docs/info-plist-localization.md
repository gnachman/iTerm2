# Info.plist localization

How the app's Info.plist strings (permission-prompt descriptions, app name,
copyright) are localized, and the one maintenance invariant the build's plist
structure imposes.

## What gets localized

macOS shows a handful of Info.plist values to the user: the `NS*UsageDescription`
strings in system permission dialogs ("iTerm2 wants to use the camera."),
`CFBundleName`, `CFBundleGetInfoString`, and `NSHumanReadableCopyright`. Those
localizable keys are collected in `sources/InfoPlist.xcstrings`, whose **keys are
the literal Info.plist key names** (not symbolic keys). Xcode recognizes the
`InfoPlist.xcstrings` filename and treats it as the Info.plist localization
source - it's the String Catalog successor to `InfoPlist.strings`.

Brand/version/license values (`CFBundleName` = "iTerm2", `CFBundleGetInfoString`,
`NSHumanReadableCopyright` = "GPL v2") are intentionally left untranslated in the
catalog; the OS falls back to the base plist value for those.

## How it works (no Info.plist edit required)

The localization is a purely additive overlay - no plist had to change to enable
it:

1. The **base plist supplies the keys and English values.** These keys are
   functionally required regardless of localization (the app cannot request
   camera access without `NSCameraUsageDescription`), so they already existed.
2. `InfoPlist.xcstrings` holds the **extracted English source plus translations**,
   keyed by the same plist keys.
3. At **build** time the catalog compiles to `<lang>.lproj/InfoPlist.strings` in
   the app bundle (one file per language).
4. At **runtime** macOS overlays those `InfoPlist.strings` values onto the plist
   **by key** for the current language, falling back to the base plist value for
   any key not translated. The app itself does nothing; the OS does the overlay
   when it renders permission dialogs and Finder metadata.

Adding the catalog therefore touched only `sources/InfoPlist.xcstrings`; the plist
was not modified, and no `CFBundleLocalizations` / `CFBundleAllowMixedLocalizations`
key was needed (the presence of the `.lproj/InfoPlist.strings` files is what the
OS keys off).

## The plist-flavor invariant (important)

There is **no single checked-in Info.plist.** `plists/iTerm2.plist` is a
**gitignored build artifact**: the Makefile copies the flavor-specific source
variant over it per build target -

| target | source variant |
|---|---|
| `make dev` (and the default backstop) | `plists/dev-iTerm2.plist` |
| `make Beta` | `plists/beta-iTerm2.plist` |
| `make Nightly` | `plists/nightly-iTerm2.plist` |
| `make Deployment` (release) | `plists/release-iTerm2.plist` |
| preview | `plists/preview-iTerm2.plist` |

The runtime overlay is **flavor-agnostic** - it keys off `NSCameraUsageDescription`
etc., not off which variant was copied - so localization works for whichever
flavor is built.

But because `InfoPlist.xcstrings` carries a **single English source per key**,
the localizable values must stay **identical across all five variants**. They are
today (e.g. every variant's `NSCameraUsageDescription` is
`"An application in iTerm2 wants to use the camera."`, matching the catalog).

Consequences if a flavor's wording ever diverges (e.g. a beta-only permission
message):

- The zh/other override still applies - it's keyed by the plist key, not the
  English - so the diverged flavor would show the translation of the *catalog's*
  English, which may no longer match that flavor's intended text.
- The catalog's English `source` would be stale relative to that one flavor, and
  a translator working from the catalog would never see the divergent wording.

**Rule of thumb:** keep the localizable Info.plist values (the usage descriptions
in particular) identical across `dev-`/`beta-`/`nightly-`/`release-`/`preview-iTerm2.plist`.
If a flavor genuinely needs different user-facing text for one of these keys, it
cannot be localized correctly through the shared catalog key - treat that as a
special case rather than silently diverging the wording.
