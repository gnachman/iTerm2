# A “<” in a tip of the day would be shown as “&lt;”

**Where:** `sources/TIps/iTermTip.m`, `-attributedString` (near line 40).

**What happens:** the tip's title and body are escaped for HTML by replacing `<` with `&lt;` and then `&` with `&amp;`. The second replacement escapes the `&` that the first one introduced, so a `<` reaches the HTML as `&amp;lt;` and is displayed as the four characters `&lt;`. No tip contains `<` today, in English or in any translation in `xcstrings/Localizable.xcstrings`, so nobody sees it now; the first tip that mentions a shell redirection or a key like `<Tab>` would show it. An `&` alone is escaped correctly (tip 0101's title, “LastPass & 1Password”, displays as written).

**Why:**

```objc
return [[xml stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"]
        stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
```

**How to see it:** give a tip the body `a < b` and show it; it reads `a &lt; b`. Seen by reading the code; not run.

**Suggested fix:** replace `&` first, then `<`.

**Found:** 2026-11-27, while preparing to move `iTermTip` to Swift.

**Checked against the tree:** 2026-11-27. The order of the replacements is unchanged, and a search of every `Tip.*` string in `xcstrings/Localizable.xcstrings`, in every language, found no `<`.
