# Strings and localization (developer guide)

How user-visible text works in iTerm2: how to add a localizable string, what to
leave in English, and the rules that keep translations correct. For translating
the app into a new language see `docs/adding-a-translation.md`; for the Info.plist
mechanism see `docs/info-plist-localization.md`.

## Overview

iTerm2 localizes with Apple **String Catalogs** (`.xcstrings`). The source
language is **English**; any untranslated string falls back to English, so
partial translations are safe. There are three kinds of catalog:

- **Code strings** - `sources/Localizable.xcstrings`, keyed by symbolic keys
  (`Feature.Name`). This is what you edit when writing code.
- **XIB strings** - one `mul.lproj/<name>.xcstrings` per XIB, keyed by object ID.
  Populated automatically by the build's extraction step; you don't hand-write
  these.
- **Info.plist strings** - `sources/InfoPlist.xcstrings` (see the Info.plist doc).

## Adding a user-visible string

Wrap the English in a localized-string call with a **stable symbolic key**, an
English **default value**, and a **comment** that explains the context and every
placeholder. The key convention is `Feature.ShortName`.

- Swift:
  ```swift
  String(localized: "PseudoTerminal.CloseTabsHeading",
         defaultValue: "Close Tabs",
         comment: "Warning heading shown when closing multiple tabs")
  ```
- Objective-C:
  ```objc
  NSLocalizedStringWithDefaultValue(@"PseudoTerminal.CloseTabsHeading", nil,
      [NSBundle mainBundle], @"Close Tabs",
      @"Warning heading shown when closing multiple tabs")
  ```

The comment is the only context a translator gets - write it. Use
`[iTermUserDefaults userDefaults]`-style project conventions elsewhere, but for
strings always go through these calls so extraction picks them up.

## What to leave in English

Not every string should be localized. Mark such sites with a
`// Localization unneeded` comment (so a future reader knows it was considered)
and leave them as plain literals - they then never reach the catalog. Leave
English:

- **Stable identifiers and sentinels** - anything compared with `==`, used as a
  dictionary key, or persisted (a `NoSync…` user-defaults key, a Codable
  `rawValue`, a generated profile name that is looked up by that exact string).
  Localizing these forks identity across locales. If such a value is *also*
  displayed, keep the sentinel English and localize only at the display site.
- **Technical/debug output** - `DLog`/`RLog` and format skeletons. (Script-console
  diagnostics are localized, per commit c7f3e2d24, since users read them.)
- **Prompts sent to an AI model** (system/instruction prompts). These are tuned
  engineering artifacts; English maximizes instruction-following, and the user's
  language reaches the model through their query. Localize UI *about* the AI, not
  the instructions to it.
- **Scripting-API error reasons.** The `errorReason` returned through the Python
  scripting API (`ITMInvokeFunctionResponse.error.errorReason`, surfaced as
  `RPCException` messages) *is* shown to the user (in the Script Console and in
  error dialogs), so it **should** be localized. The built-in-function,
  function-call, and expression-parser error reasons are therefore localized like
  any other user-facing string. Do not add matching against these reason strings to
  tests or scripts; match on error codes/domains instead, which stay stable across
  locales.

## Write complete sentences, not injected fragments

Do **not** build a sentence by injecting a *translated word or phrase* into a
format frame:

```swift
// WRONG: "Clear"/"Reset" is a translated verb spliced into a frame.
String(localized: "…", defaultValue: "\(verb) all sessions?")
```

Word order, gender, case, and agreement differ by language, and a translator sees
the frame and the fragment separately, so the result is ungrammatical elsewhere.
Instead give each case its own **complete** localized sentence (one string per
verb/kind/state). Injecting **self-contained values** - names, counts, file
paths, hostnames, error text - is fine, because the value carries no grammar of
its own.

When a completed sentence still interpolates more than one value, use
**positional** specifiers (`%1$@`, `%2$@`) so translations can reorder them:

```
"Plugin has version %1$@ but iTerm2 expects %2$@."
```

A bare `%@` binds to the next argument in order and cannot be reordered; a
positional `%2$@` can move ahead of `%1$@`.

## Format specifiers

- `%@` / `%1$@` - a string; `%ld` / `%lld` / `%lu` / `%d` - an integer;
  `%%` - a literal percent.
- Keep count and type consistent with the English; never change `%ld` to `%@`.
- `String(localized:)` and `+[NSString localizedStringWithFormat:]` are
  locale-aware and apply the locale's digit grouping to integer specifiers
  ("10,001"), so you rarely need a `NumberFormatter`.
- Extraction quirk: `extractLocStrings` normalizes multi-specifier strings to
  positional form and **misreads a literal `%word`** (e.g. tmux's `%begin`) as a
  specifier. Move such literals out of the localized string and pass them as
  arguments; `tools/extract_strings.sh` has a guard that fails the build on a
  malformed positional specifier.

## Plurals

Wording that depends on a count ("1 file" vs "3 files") needs a String Catalog
plural, **not** a `count == 1 ? … : …` ternary - a ternary bakes in English's two
number forms, and other languages have more categories (CLDR: Chinese has one,
English two, Russian four, Arabic six).

**Source side** - pass the count as an argument:

- Swift: `String(localized: "Key", defaultValue: "… \(count) …", comment: …)`
- ObjC: `[NSString localizedStringWithFormat:NSLocalizedStringWithDefaultValue(@"Key", nil, [NSBundle mainBundle], @"… %ld …", @"…"), (long)count]`
  - you must use `localizedStringWithFormat:`, **not** `stringWithFormat:`, or the
  plural rule is never applied.

Keep the plural string to the **count argument alone**; append lists, names, or
other values *outside* it so the catalog entry stays a simple single-argument
plural rather than a multi-argument substitution.

**Catalog side** - after the key is extracted into `Localizable.xcstrings`,
replace its `en` `stringUnit` with a `variations.plural` block holding `one` and
`other` `stringUnit`s (state `new`). `xcstringstool sync` is a key-by-key merge,
not a regenerate, so it preserves those variations (and translations) across
future extractions. Verify with:

```
xcrun xcstringstool compile --output-directory <dir> sources/Localizable.xcstrings
```

The key's compiled `en.lproj/Localizable.stringsdict` entry should have
`NSStringFormatSpecTypeKey = NSStringPluralRuleType`.

Preservation is conditional - any of these **silently un-pluralizes** the site:

1. Renaming the key in code - the old plural entry goes stale and a fresh flat
   key appears, so a rename means re-authoring the plural.
2. Dropping the key's code reference - it goes stale and is eventually pruned.
3. Changing the English `defaultValue` without hand-updating the variations -
   sync can't tell which plural category the flat source maps to, so keep the
   `other` value identical to the `defaultValue`.

### Plurals that also carry a value (substitutions)

When a string pluralizes on a count *and* interpolates another value (a path, a
name), use a **substitution**: a top-level value like `"%2$#@children@"` plus a
`substitutions` block whose `argNum`/`formatSpecifier` point at the count and
whose `plural` variations spell out the categories. Inside a variation value,
`%arg` refers to that substitution's own number; you may also reference other
arguments positionally. Prefer restructuring to a single-argument plural when you
can (append the extra value outside the plural string); reach for a substitution
only when the value sits mid-sentence.

Worked references: `ScriptsMenu.BumpUpgradeIncompleteSentence` (ObjC `%ld`) and
`NonTextPaste.PasteManyFilesPrompt` (Swift `%lld`) for simple plurals;
`ApplyLayout.SplitterTooFewChildren` and `Workgroup.ExitOneWorkgroupCloseSessions`
for substitutions. A `// TODO(l10n): plural` marker flags a site still using the
ternary anti-pattern.

## Curly quotes and punctuation

In user-visible English use curly quotation marks (`“ ”`, `‘ ’`), never straight
quotes - `"` only as an inch shorthand. Do not "fix" existing curly quotes to
straight ones. Translators use their own language's marks.

## How strings reach the catalog

Swift emits `.stringsdata` during the build (`SWIFT_EMIT_LOC_STRINGS=YES`); ObjC
is scanned by `extractLocStrings`. `tools/extract_strings.sh` (run by the Beta and
Deployment targets, and standalone via `make extract-strings`) merges both into
`sources/Localizable.xcstrings` with `xcstringstool sync`. So a new code string
appears in the catalog after an extraction, not immediately.

## Testing a localization

Build, then launch forced into a language:

```
open Build/Development/iTerm2.app --args -AppleLanguages '(zh-Hans)'
```

Check the menu bar, Settings (Cmd-,), and a few alerts (with different counts to
exercise plurals). Menu actions are matched by stable identifiers, not titles, so
translating titles is safe.
