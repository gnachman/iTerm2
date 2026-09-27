# Adding a Translation to iTerm2

This guide is for translators adding a new UI language to iTerm2. It assumes you
can read the source competently and are fluent in English and your target
language. Everything here has been verified against the current build.

## How localization works

iTerm2 uses Apple **String Catalogs** (`.xcstrings` files). The source language
is **English (`en`)**. Any string you do not translate falls back to English
automatically, so a partial translation is safe to ship and safe to grow over
time.

There are two kinds of catalog, and you must translate **both** to fully
localize the app:

1. **Code strings** - one big catalog at `sources/Localizable.xcstrings`. Keys
   are symbolic (`PseudoTerminal.CloseTabsHeading`). This covers everything
   produced in code: alerts, menus built at runtime, status text, errors, etc.

2. **XIB strings** - about 70 per-window/per-view catalogs, each named after its
   XIB and living in a sibling `mul.lproj/` directory (e.g.
   `sources/MainMenu/mul.lproj/MainMenu.xcstrings`,
   `sources/Settings/mul.lproj/PreferencePanel.xcstrings`). Keys are the
   interface object's ID and property, e.g. `0A4-80-ghh.title`. Each key's
   `comment` tells you the class, the English text, and the object ID. There is
   also `sources/InfoPlist.xcstrings` for Info.plist strings (permission-prompt
   descriptions, app name); see `docs/info-plist-localization.md` for how those
   overlay onto the base Info.plist at runtime.

Every entry stores the English under `localizations.en`; you add a sibling
`localizations.<lang>` with your translation. A translated catalog compiles to
`<lang>.lproj/<name>.strings` (and `.stringsdict` for plurals) inside the app
bundle at build time, and the app applies it at launch.

## Prerequisites

- Xcode (matching the project's required version) and the ability to build:
  `tools/build.sh` produces a Development build.
- A working English build first, so you have something to compare against.

## Step 1 - Add your language to the project

In Xcode: select the **iTerm2** project → **Info** tab → **Localizations** → **+**
→ choose your language (use the Xcode/BCP-47 code, e.g. `fr`, `de`, `ja`,
`zh-Hant`, `pt-BR`). This makes Xcode's String Catalog editor show a new empty
column for your language in every catalog.

You do **not** need to touch `LOCALIZATION_PREFERS_STRING_CATALOGS` or the
`mul.lproj` wiring - that is already set up for extraction and is a developer
concern, not yours.

If you prefer to edit the JSON by hand instead of using Xcode's editor (the files
are plain JSON), you simply add a `"<lang>"` key under a string's
`"localizations"` object; see the shapes below. Either way, keep each file's
existing on-disk formatting.

## Step 2 - Translate a plain string

In the catalog editor, fill in the cell for your language. If editing JSON, add:

```json
"PseudoTerminal.CloseTabsHeading" : {
  "comment" : "Warning heading shown when closing multiple tabs",
  "extractionState" : "extracted_with_value",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "new", "value" : "Close Tabs" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Fermer les onglets" } }
  }
}
```

Rules for every string:

- **Read the `comment`.** It gives context and explains what each placeholder is
  ("%@ is the profile name", "%1$@ is the shortcut, %2$@ is its purpose").
- **Set `state` to `translated`.** (`new` means untranslated; the build treats it
  as English.)
- **Use your language's punctuation and quotation marks.** English uses curly
  quotes `“ ”` and `‘ ’`; use the correct marks for your language (e.g. « » or
  „ "). Do not "fix" the English source to straight quotes.
- **Preserve escape sequences** like `\n` (newline) exactly.
- **No em dashes.** This project avoids the em dash (—) in shipped text. Where the
  English would use one, use your language's normal punctuation instead (a comma,
  colon, parentheses, or a hyphen), whichever reads best.

## Step 3 - Format specifiers (`%@`, `%ld`, `%1$@`, …)

Placeholders are substituted at runtime with values (names, counts, paths). You
**must keep every specifier**, with the same type, and you must **not add or
remove** any.

- `%@` / `%1$@` - a string (a name, path, hostname, …).
- `%ld` / `%d` / `%lld` / `%lu` - an integer count.
- `%1$@`, `%2$@`, … - **positional** forms. This is the important one for
  translators: positional specifiers let you **reorder** the inserted values to
  fit your language's word order. If the English is

  ```
  "Plugin has version %1$@ but iTerm2 expects %2$@. Upgrade one or both."
  ```

  your translation may place `%2$@` before `%1$@` if that reads correctly - the
  numbers bind each slot to a specific value, so reordering is safe and correct.
  A non-positional `%@` binds to the next value in order and cannot be reordered.

- Never translate the letters inside a specifier, and never change `%ld` to
  `%@` (or vice-versa) - that mismatches the value type and can crash.
- A literal percent sign is written `%%`; leave those alone.

## Step 4 - Plurals

Some strings change wording based on a number ("1 file" vs "3 files"). English
has two plural categories, `one` and `other`. **Your language may have more**,
and you must supply every category it uses. The categories are defined by the
Unicode CLDR plural rules:

- Chinese, Japanese, Korean, Vietnamese, Thai: `other` only.
- English, German, Dutch, most Romance-ish "singular/plural" languages: `one`,
  `other`.
- Russian, Polish, Czech, Ukrainian, …: `one`, `few`, `many`, `other`.
- Arabic: `zero`, `one`, `two`, `few`, `many`, `other`.

Look up your language's categories in the CLDR "Language Plural Rules" tables.
In Xcode's editor a plural string shows the count argument with per-category
rows; add the categories your language needs. In JSON a plural string looks like:

```json
"PseudoTerminal.TabCount" : {
  "comment" : "A count of tabs; %lu is the number of tabs",
  "localizations" : {
    "en" : {
      "variations" : { "plural" : {
        "one" : { "stringUnit" : { "state" : "translated", "value" : "%lu tab" } },
        "other" : { "stringUnit" : { "state" : "translated", "value" : "%lu tabs" } }
      } }
    },
    "ru" : {
      "variations" : { "plural" : {
        "one"   : { "stringUnit" : { "state" : "translated", "value" : "%lu вкладка" } },
        "few"   : { "stringUnit" : { "state" : "translated", "value" : "%lu вкладки" } },
        "many"  : { "stringUnit" : { "state" : "translated", "value" : "%lu вкладок" } },
        "other" : { "stringUnit" : { "state" : "translated", "value" : "%lu вкладки" } }
      } }
    }
  }
}
```

Notes:

- Keep the count specifier (`%lu` here) in each category's value; it is what
  gets replaced by the number. It is formatted with your locale's digit grouping
  automatically.
- A category's value does not have to contain the digit - English `one` could be
  just "one tab" - but the runtime still selects it by the number.

### Plurals with an extra value (substitutions)

A few strings pluralize on a count **and** interpolate another value (a path, a
name). These use a *substitution*: a top-level value like `"%2$#@children@"`
plus a `substitutions` block. Example (English):

```json
"ApplyLayout.SplitterTooFewChildren" : {
  "comment" : "%1$@ is the path, %2$lld is the child count",
  "localizations" : {
    "en" : {
      "stringUnit" : { "state" : "translated", "value" : "Splitter at %1$@ has %2$#@children@; must have at least 2" },
      "substitutions" : {
        "children" : {
          "argNum" : 2, "formatSpecifier" : "lld",
          "variations" : { "plural" : {
            "one"   : { "stringUnit" : { "state" : "translated", "value" : "%arg child" } },
            "other" : { "stringUnit" : { "state" : "translated", "value" : "%arg children" } }
          } }
        }
      }
    }
  }
}
```

To translate: add your `"<lang>"` block with the same shape. Translate the
top-level value (you may reorder `%1$@` and the `%N$#@name@` token) and each
plural category value. Inside a substitution category value, `%arg` refers to
that substitution's own number; you may also reference other arguments
positionally (`%1$@`). Add the plural categories your language needs, exactly as
in the plain-plural case.

## Step 5 - What NOT to translate

- **Format specifiers** and the `%%` literal (Step 3).
- **Code operators inside a string.** A few help texts contain literal syntax in
  backticks or as bare tokens - e.g. the snippet search help lists `` `tag:` ``,
  `` `title:` ``, `` `text:` ``, the `-` prefix, and `|`. Translate the prose
  around them; leave the operators exactly as written. The comment says so.
- **URLs, file paths, escape sequences (`\n`).**
- **Product, tool, and protocol names.** Keep the app name (iTerm2) and
  third-party names untranslated: languages, shells, and tools (Python, tmux,
  Git, Zsh, Homebrew, 1Password, LastPass, …) and protocols/formats (SSH, JSON,
  UTF-8, OSC, …). Contrast these with iTerm2's own *feature* names, which are
  ordinary words and **should** be translated: see "Translate feature names" in
  the Practical tips below.
- **The English source** (`localizations.en`), the **keys**, the `comment`, and
  `extractionState`. Only add/edit your own language's `localizations.<lang>`.
- Strings that never reach the catalog are already excluded for you - anything a
  developer marked "Localization unneeded" (stable identifiers, sentinels used in
  comparisons, technical/debug output) is not extracted, so you will not see it.

## Step 6 - Verify

Before building the whole app, sanity-check the catalog compiles:

```
xcrun xcstringstool compile --output-directory /tmp/loc-check sources/Localizable.xcstrings
```

It must succeed. For a plural entry you can confirm the rule was produced:

```
plutil -p /tmp/loc-check/<lang>.lproj/Localizable.stringsdict
```

You should see `NSStringFormatSpecTypeKey => NSStringPluralRuleType` and your
categories. Do the same for any XIB catalog you edited.

## Step 7 - Build and test in your language

Build (`tools/build.sh`, or Build in Xcode), then run the app forced into your
language:

```
open Build/Development/iTerm2.app --args -AppleLanguages '(fr)'
```

(Replace `fr` with your code.) Verify:

- The menu bar renders in your language (the menus are the `MainMenu.xcstrings`
  catalog). Menu actions are matched internally by stable identifiers, not by
  their titles, so translating titles is safe.
- Open **Settings** (Cmd-,) and page through the tabs - those are the many
  `mul.lproj` catalogs.
- Trigger a few alerts (e.g. try to close a window with running jobs) to check
  code strings, plurals (with different counts), and word order.

Untranslated strings appear in English; that is expected while a translation is
in progress.

## Non-catalog resources (the Python REPL banner)

Almost everything is in the catalogs, with one exception worth knowing about: the
Python REPL banner (the welcome text shown by **Scripts > Manage > Python REPL**) is
a bundled text file, not a catalog string, because it embeds terminal styling codes,
a hyperlink, and a runnable code sample. To localize it, add a file named
`repl_banner-<localization>.txt` next to `sources/repl_banner.txt` (e.g.
`repl_banner-pt-BR.txt`, using the same localization code as your `.lproj`), and ask
the maintainer to add it to the app target's "Copy Bundle Resources" build phase (it
is a loose resource, so it cannot be wired up from the catalog). The app picks the
banner matching the current language and falls back to the English
`repl_banner.txt`. Translate the prose but leave the `import iterm2 …` code sample
and the documentation URL in English.

## Practical tips

- **Work catalog by catalog.** `Localizable.xcstrings` is the largest; the
  `mul.lproj` catalogs are small and map to one window/view each, so you can see
  the context of a whole screen at once.
- **Length matters.** Some strings live in narrow columns, buttons, or the
  timestamp margin. Prefer compact wording where the English is compact.
- **Some labels are deliberately short or arbitrary.** A few strings are terse
  code-names whose literal meaning does not matter. Keep your rendering as short as
  the English rather than translating it literally; substituting a different but
  shorter word is fine when the exact word is irrelevant. Honor any comment that
  says a string must stay short over a faithful-but-longer phrasing.
  - **Workgroup animal names** (`WorkgroupAnimalNames.*`) are the clearest case:
    they exist only to be short, distinct, one-word default names, so **choose for
    brevity, not fidelity**. The English is always a single short word (2 to 5
    letters). If the literal translation of an animal is long or multi-word (for
    example German *Fledermaus* for "Bat", or Russian *Летучая мышь*), do **not**
    use it. Pick a *different*, short, single-word animal in your language instead
    (a hedgehog, a lynx, whatever is short). Aim to keep every name to roughly the
    length of the English, and make sure the names stay **unique** within the set
    (no two keys sharing one translation), since they are used to tell sessions
    apart.
- **Right-to-left languages** (Arabic, Hebrew): AppKit mirrors layout
  automatically; focus on the text. Keep any leading/trailing spaces that a
  comment tells you to preserve.
- **Consistency: one English string, one translation.** The same English text
  should get the same translation everywhere it appears, and a given concept
  ("tab", "pane", "profile", "session") should use a single term across every
  catalog. Keep a glossary as you go. Before you finish, scan for any English
  string that maps to two different translations and reconcile them - the menu bar
  and the settings window, or a context menu and its main-menu twin, are common
  places to drift apart. A few divergences are legitimate and should be left: a
  word whose form changes with the grammatical gender or number of the noun it
  modifies, a term that is a verb in one place and a noun in another, or a common
  word used as an arbitrary name in one spot and literally in another. Unify
  everything else. If you revise a term after translating, re-check the article
  and adjective agreement everywhere it appears.
- **Translate feature names; do not leave them in English as "terms of art."**
  iTerm2's feature names (Triggers, Cockpit, Toolbelt, Snippets, Annotations,
  Composer, Codecierge, the individual Toolbelt tools, trigger and smart-selection
  rule names, …) are ordinary words, not brand names, and should be translated like
  any other UI text. Pick one translation per feature name and use it consistently
  everywhere it appears (menu, window title, tooltip, settings), so the same feature
  reads the same throughout. The only strings that stay English are the ones a
  comment explicitly says to keep (brand names like "Patreon"/"GitHub Sponsors",
  code operators, format specifiers) and anything a developer marked
  "Localization unneeded", which you will not see in the catalog.
- **Ask the maintainer** if a string is ambiguous even after reading its comment,
  rather than guessing - a wrong translation is worse than a missing one, which
  simply shows English.
