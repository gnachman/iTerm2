# Writing iTerm2 Release Notes

Release notes live in `docs/notes-<version>.txt` (cumulative, since the previous release) or `docs/notes-<version>beta<N>.txt` (per-beta diff, since the previous beta). They are **plain text, max 50 columns per line**.

## Audience

The reader is a **regular user or beta tester** who:

- Uses iTerm2 actively and reads release notes.
- Has **not** participated in development.
- Has **not** read the source code or commit history.
- Knows the names of features they already use, but not internal terminology.

Every entry must be self-explanatory to someone who only knows what iTerm2 looked like at the previous release.

## What to include

**Include:**

- Significant new features (a major UX change, a new panel, a new escape sequence, a new API).
- Improvements to existing features users will notice (faster, more options, better defaults, expanded scope).
- Bug fixes that affect features that **already shipped**.
- Performance, energy, and memory work that users will feel.

**Omit:**

- Implementation details (XPC re-org, internal symlinks, helper hooks, refactors, retain-cycle fixes that aren't user-visible).
- Advanced settings. These are off the beaten path and not release-note material.
- Developer-only features (env vars meant for switching between iTerm2 builds, etc.).
- Sub-features of a brand-new feature. If the parent is new, readers will discover the parts on their own.
- Bug fixes for features that are **also new in this release**. Readers have never seen the broken version; listing the fix just adds noise.

## Verify what's actually "new"

Before describing something as "improved", "now", "no longer", or "retuned", confirm the underlying feature existed in the previous release:

```sh
git ls-tree -r v<previous-tag> | grep -i <feature>
git grep -i <SymbolName> v<previous-tag>
```

If the feature itself shipped in this release, frame it as a brand-new capability — not as a refinement to something readers haven't seen.

This applies recursively: if `Workgroups` is new, then "the workgroup toolbar", "workgroup peers", "the Code Review prompt overlay", and any related concepts are also new — don't reference them as if they pre-existed.

## Section structure

Use these sections in order. Skip any that have no content.

1. **`Major New Features:`** — headline items. One short paragraph each: what it is and how to get to it. Don't enumerate every sub-feature.
2. **`New Features:`** — smaller new capabilities (a new escape sequence, a new panel, a new Python API, a new docking option). A new menu item that just exposes existing behavior is rarely a new feature.
3. **`Improvements:`** — tweaks to existing features (added options, better precision, broader scope). Energy, performance, and resource-usage wins also go here.
4. **`Bug Fixes:`** — fixes to behavior in features that pre-dated this release.

## Writing each entry

### Length

- One bullet, one idea. Aim for 1–3 lines.
- For a new feature, say **what it does** and **where to find it** (menu path, setting path, or escape sequence). Don't narrate the internal machinery or rationale.
- Don't paste the commit message. Rewrite from the reader's perspective.

### Voice

- Plain English. Avoid internal terminology. Examples of jargon to translate:
  - "right gutter" → "side panel" / "alongside the terminal"
  - "peer" → "companion session" / describe the relationship in prose
  - "in-session prompt overlay" → "the prompt panel that appears before…"
  - "cc-status hook", retain-cycle fixes, KVO refactors, XPC plumbing → omit
- Use **Title Case for feature names**: Smart Selection, Smart Selection Action, Workgroups, Code Review, Quick Look, Special Exceptions, Edit Session, Clippings, etc.
- Use **curly quotes** (`“ ”`, `‘ ’`) for user-visible quoted text. Use straight quotes only inside literal shell syntax (e.g. `$'…'`) or literal program output (e.g. `"unmatched '"`). Per CLAUDE.md, don't use `"` in user-visible strings except as the shorthand for inches.

### Order of introduction

If a bullet mentions feature X, X must already be familiar — either because it's pre-existing or because an earlier bullet introduced it. Put introductions before detail items.

For example, introduce the Clippings panel as a new feature **before** mentioning the `it2 add-clipping` subcommand that posts to it.

### Group like fixes

Collapse repetitive low-detail items:

- Multiple crash fixes → `- Fix various crashes.`
- Multiple memory leaks → `- Fix various memory leaks.`
- Multiple hangs → `- Fixed various hangs that could cause a beachball (X, Y, Z).`

## Format

- **50 columns** max. Hard-wrap.
- Bullets start with `- ` and continuation lines are indented two spaces.
- One blank line between sections.
- File names:
  - `notes-<version>.txt` — cumulative, relative to the previous stable.
  - `notes-<version>beta<N>.txt` — per-beta diff, relative to the previous beta.
- After creating a new notes file, `git add` it (per CLAUDE.md).

## Pre-commit checklist

- [ ] Each entry makes sense without reading the source or commits.
- [ ] No internal jargon ("right gutter", "peer", "in-session overlay", hook names, etc.).
- [ ] No advanced-setting bullets.
- [ ] No developer-only bullets.
- [ ] No bug-fix bullets for features that are themselves new in this release.
- [ ] Improvements are under `Improvements:`, not `Bug Fixes:`.
- [ ] Crashes / memory leaks / hangs are collapsed into single bullets.
- [ ] Feature names are Title Case.
- [ ] Curly quotes used everywhere except inside literal shell/error text.
- [ ] Every line ≤ 50 columns.
