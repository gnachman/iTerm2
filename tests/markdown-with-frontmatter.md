---
title: Markdown Rendering Smoke Test
author: George Nachman
date: 2026-04-25
tags: portholes, markdown
---

# Front Matter + Thematic Breaks

This document opens with YAML front matter delimited by `---`. The
front matter block above should be consumed by SwiftyMarkdown and
**not** rendered as horizontal rules.

After the front matter, the body begins normally. The next `---`
below is a real thematic break (it has a blank line above it), and
should render as a horizontal rule.

---

## After the first thematic break

Some prose between rules. This paragraph should appear as body text
under an `h2` heading, not be silently swallowed or converted into
another heading.

---

## After the second thematic break

A few inline checks:

- `inline code` stays styled
- **bold** and *italic* render as expected
- A literal `===` line below should remain paragraph text since it
  has a blank line above it (it is not a setext H1 underline):

===

End of document.
