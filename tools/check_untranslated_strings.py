#!/usr/bin/env python3
"""Pre-commit guard: block committing a newly-added code string that isn't translated.

Every user-visible string in xcstrings/Localizable.xcstrings is expected to be
translated into all of the catalog's languages before it lands (translations are
done by Claude, so this is normally a no-op). This checks the STAGED catalog: for
each key that is new versus HEAD (and not stale), it verifies every non-English
language the catalog uses has a `translated` value, with the right plural
categories for plural strings. Pre-existing keys (including `needs_review`) and
the Xcode-managed XIB catalogs are not checked.

Exit 0 = ok; exit 1 = one or more new strings untranslated. Bypass: git commit --no-verify.
"""
import json, subprocess, sys

CATALOG = "xcstrings/Localizable.xcstrings"


def blob(rev):
    # rev="" -> ":<path>" (the staged/index copy); rev="HEAD" -> "HEAD:<path>".
    r = subprocess.run(["git", "show", f"{rev}:{CATALOG}"],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def shape(entry):
    if not entry:
        return None
    if "stringUnit" in entry:
        return "unit"
    if "variations" in entry:
        return "var"
    return None


def missing_langs(v, langs, cats):
    """Return the languages in which this entry is not fully translated."""
    en = v.get("localizations", {}).get("en")
    sh = shape(en)
    if sh is None:
        return []  # no English content to translate
    missing = []
    for L in sorted(langs):
        loc = v.get("localizations", {}).get(L)
        if loc is None:
            missing.append(L)
            continue
        if sh == "unit":
            if loc.get("stringUnit", {}).get("state") != "translated":
                missing.append(L)
        else:
            pv = loc.get("variations", {}).get("plural", {})
            need = cats[L]
            if not need.issubset(set(pv)) or any(
                    pv[c].get("stringUnit", {}).get("state") != "translated" for c in need):
                missing.append(L)
    return missing


def main():
    staged = blob("")
    if staged is None:
        return 0  # catalog not tracked/staged; nothing to check
    try:
        s = json.loads(staged)["strings"]
    except (ValueError, KeyError):
        return 0  # unparseable; let other checks handle it, don't block

    head_raw = blob("HEAD")
    h = {}
    if head_raw:
        try:
            h = json.loads(head_raw)["strings"]
        except (ValueError, KeyError):
            h = {}

    # Languages to require = every non-English language the catalog uses.
    langs = set()
    for v in s.values():
        langs |= set(v.get("localizations", {}).keys())
    langs.discard("en")
    if not langs:
        return 0

    # Required plural categories per language, derived from existing plurals
    # (fallback to a safe minimum). A new plural must cover these.
    cats = {L: set() for L in langs}
    for v in s.values():
        for L in langs:
            pv = v.get("localizations", {}).get(L, {}).get("variations", {}).get("plural", {})
            cats[L] |= set(pv.keys())
    for L in langs:
        if not cats[L]:
            cats[L] = {"other"}
        cats[L] |= {"other"}

    problems = []
    for k, v in s.items():
        if k in h:
            continue  # only newly-added keys
        if v.get("extractionState") == "stale":
            continue
        miss = missing_langs(v, langs, cats)
        if miss:
            en = v.get("localizations", {}).get("en", {})
            val = en.get("stringUnit", {}).get("value", "(plural)")
            problems.append((k, val, miss))

    if problems:
        sys.stderr.write("pre-commit: new localizable strings are missing translations:\n")
        for k, val, miss in problems:
            sys.stderr.write(f"  {k}  (en: {val!r})\n")
            sys.stderr.write(f"      missing: {', '.join(miss)}\n")
        sys.stderr.write(
            f"\n{len(problems)} untranslated new string(s) in {CATALOG}.\n"
            "Translate them (state \"translated\") before committing, "
            "or bypass with: git commit --no-verify\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
