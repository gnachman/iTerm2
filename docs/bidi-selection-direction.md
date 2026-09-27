# Bidi (RTL) selection direction: discussion, open questions, next steps

Working notes from reviewing PR #709 ("Right-to-left (Persian/Arabic/Hebrew)
rendering, selection, and copy", author @nuved). Recorded 2026-08-06.

This file captures the design discussion so it is not lost while we wait on the
author. It is not a spec; it records where we are and why.

## Context

PR #709 adds RTL rendering (mirror pairs, guillemets as-typed on both the
CoreGraphics and Metal renderers), scrollback/scrollRect propagation of the
per-line RTL annotation, and a rework of selection and copy so that the
selection is stored and reasoned about in logical (source-cell) coordinates.
Everything is gated behind the existing Bidi preference and is a no-op with it
off.

The rendering and copy-order work is good and worth keeping. The open question
is the **mouse selection model**.

## The core question: visual vs logical mouse selection

The distinguishing characteristic of logical selection in mixed-direction text
is **discontiguousness**: a logical range can render as several disjoint
rectangles on screen, and its copy includes everything logically between the
endpoints. Visual selection follows the pointer, stays contiguous on screen,
and never goes discontiguous (word and line selection included, since each is a
single contiguous span).

We wanted to "match OS convention unless the OS is lazily doing the wrong
thing." The complication we discovered: macOS is **not internally consistent**,
so there is no single convention to defer to.

## What we tested (empirical, not assumed)

Test line: `سلام Hello دنیا` (on-screen order left to right: `donya Hello
salaam`). Probe: drag-select from the middle of `Hello` (starting at the second
`l`) rightward into the Persian word to its right, then copy.

- **TextEdit (native NSTextView): VISUAL selection + logical-order copy.**
  Highlight follows the pointer and stays contiguous. Copy serializes the
  glyphs actually swept into reading order, giving `سلام llo`. The `He` that was
  not dragged over is excluded.
- **Safari, Chrome, Firefox (all three tested): LOGICAL selection.**
  Selection is a logical range between the endpoints, highlight can jump and go
  discontiguous, and copy returns the whole logical interval, giving `سلام
  Hello` (includes the `He` that was not swept).

So the split is: native macOS text (TextEdit) on one side, the entire browser
platform on the other. **PR #709 currently implements the browser/logical
model.** Both are legitimate, deliberate conventions; the PR's choice is
defensible, not a bug.

Two earlier claims were corrected by testing: browsers do NOT do visual
selection (all three do logical), so any "every browser does X" framing was
wrong. Only assert what was tested.

## Where the maintainer (non-RTL) currently leans

Lean, held loosely: **visual for the mouse**, because iTerm is a native Mac app
whose selection has always been visual/column-based, its closest analog is the
native text view rather than a web document, and "what I dragged is what I get"
is least surprising for terminal use (commands, paths, output). Personal
reaction: the browser/logical behavior is hard to use because the highlight
stops tracking the mouse.

Important caveat: this is a non-expert opinion. The author reads and writes RTL;
we asked for their analysis rather than imposing a preference.

## copy mode as the home for logical selection

Regardless of the mouse decision: iTerm's **copy mode** is our keyboard-driven
selection and the natural analog of shift-arrow, where macOS itself does
logical, discontiguous selection even in native text views. So if we land on
visual for the mouse, logical selection still has a clean home in copy mode
rather than being lost.

## Open questions (posted to the author)

Posted at https://github.com/gnachman/iTerm2/pull/709 (issuecomment-5198952840):

1. How did they analyze the tradeoff? Was the browser/logical model chosen
   deliberately, or did it fall out of storing the selection logically for the
   copy fix?
2. As an RTL user, which do they reach for and expect day to day, and does it
   change by context (prose vs a command or path in a terminal)?
3. Is there something better about the browser/logical model for RTL
   specifically that a non-RTL user would miss?

## Implementation issues parked until direction is settled

These came out of the review and are independent of the visual-vs-logical
decision. Held back so we do not bury the author before aligning on direction.

- **Metal renderer selected fg/bg coordinate mismatch (real bug, fix
  regardless).** In `sources/MetalRenderer/Glue/iTermMetalPerFrameState.m` the
  selected background at line 1424 tests the logical cell index
  (`containsIndex:logicalX`, correct), but the selected foreground at line 1702
  still tests the visual column (`containsIndex:visualX`). On a reordered line
  these are different cells, so a glyph can get the selected background with the
  unselected foreground color and effectively disappear (observed on screen).
  Lines 1720 (annotations, `visualX`) and 1983 (`bgrle->origin`, visual) have
  the same mismatch. The CoreGraphics path is consistent (derives both from the
  same logical `run->selected`), so toggling off the GPU renderer makes the
  glyphs reappear, which confirms it is Metal-specific.
- **Missed visual-to-logical conversions feeding the logical mouse selection.**
  Several selection entry points still pass raw visual coordinates into the now
  logical selection model: shift-click-extend and three-finger drag in
  `PTYMouseHandler.m`, `findOnPageSelectRange:` in `PTYTextView.m` (stores a
  visual range via `visualRangeForLogical:` into a logical selection),
  context-menu copy of a smart-selection action in
  `iTermTextViewContextMenuHelper.m` (passes `action.visualRange` to the now
  logical extractor), Look Up / force-touch (`showDefinitionForWordAt:` in
  `PTYTextView+ARC.m`), and right-click / pointer-gesture smart selection in
  `iTermURLActionHelper.m`. **Most of these dissolve if the mouse path stays
  visual**, since they only exist to feed a logical mouse selection.
- **Supplementary-plane strong-RTL detection.** `firstStrongIsRTL` in
  `sources/Drawing/BidiDisplayInfo.swift` walks UTF-16 units and skips surrogate
  halves, so non-BMP strong-RTL characters (Adlam, Hanifi Rohingya, etc.) are
  ignored and paragraph direction is misdetected. Gated behind the default-off
  `detectParagraphDirection` advanced setting, so low impact, but a regression
  vs the `rangeOfCharacter(from:)` code it replaced.
- **Pre-existing typo (not introduced by this PR).**
  `iTermAttributedStringBuilder.m` has `bidiLUT[i - i]` (always index 0) where
  `bidiLUT[i - 1]` was intended, misplacing spacing combining marks on bidi
  lines. From the original GPU-RTL commit, worth a one-character fix while in
  the area.
- **Conventions.** The diff adds em dashes to comments and at least one
  user-visible string (the `stripZeroWidthFormatCharactersOnPaste` advanced
  setting description), which the em-dash rule prohibits.

## Next steps

1. Wait for the author's analysis on the mouse selection model.
2. Fix the Metal selected fg/bg coordinate mismatch regardless of direction (it
   is a bug under any model).
3. If we land on **visual** for the mouse: keep the reading-order copy
   serialization, revert the mouse selection/highlight to visual columns (where
   iTerm already was), and let copy mode be where logical selection lives. This
   also removes the need for most of the missed conversions above.
4. If we land on **logical** for the mouse: finish the conversions at every
   selection entry point so the model is consistent.
5. Keep regardless of direction: the mirror-pair rendering, guillemets as-typed,
   reading-order copy extraction, and scrollback/scrollRect RTL propagation.

## Manual test artifacts (local, not committed)

- `~/bidi-test.txt`: mixed-direction lines to `cat` in a terminal build with the
  Bidi pref on.
- `~/bidi-safari-test.html`: same lines in a browser with a live readout of what
  Cmd-C would copy (selection string plus code-point breakdown), used to compare
  TextEdit against the browsers.
