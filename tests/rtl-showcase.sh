#!/bin/bash
#
# Right-to-left (bidi) rendering showcase for iTerm2.
#
# Prints a labeled set of Persian/Arabic/Hebrew lines that exercise every
# bidi rendering behavior iTerm2 supports, so a developer (or a native
# reader) can eyeball how they render. Pair with the unit tests, which
# assert the same behaviors automatically:
#
#   ModernTests/BidiMirroringTests.m        - the Bidi_Mirroring pair table
#   ModernTests/BidiMirrorSelectionTests.swift - per-cell L4 mirror decision
#                                              (incl. brackets around English)
#   ModernTests/BidiTUIRepaintTests.swift   - RTL survives TUI scroll/repaint
#   tests/rtl-tui-repro.sh                  - visual repro of the scroll case
#
# Prerequisites (Settings the reader must enable first):
#   * General > Experimental: "Enable support for right-to-left scripts"
#   * Advanced (search "paragraph"): "Auto-detect paragraph writing
#     direction based on the first strong directional character" = Yes
#   * Profiles > Text: "Use a different font for non-ASCII text" with a
#     monospace Arabic-script font (e.g. Vazir Code) and "Use ligatures"
#     checked, so Arabic-script shaping is applied.
#
# Usage:
#   tests/rtl-showcase.sh

set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
data="$dir/rtl-showcase.txt"

if [ ! -f "$data" ]; then
    echo "Missing $data" >&2
    exit 1
fi

cat "$data"

cat <<'GUIDE'

────────────────────────────────────────────────────────────
What each section demonstrates (compare against a browser):
  1  Plain RTL text reads right-to-left, right-justified.
  2  Embedded English runs stay upright and in reading order.
  3  Brackets in pure RTL text mirror (UBA rule L4).
  4  Brackets take the paragraph direction. In a right-to-left
     paragraph both a Persian-content pair and an English-content
     pair mirror the same way (matching Safari/TextEdit). Section
     4b puts both kinds on one line so they can be compared.
  5  Guillemets mirror; plain quotes do not.
  6  Persian and Latin digit runs keep their order; a date keeps
     its slashes; percent and currency signs sit correctly.
  7  Paths and URLs stay intact and clickable.
  8  Half-space (ZWNJ) words stay joined; punctuation lands at
     the correct visual end.
  9  Arabic and Hebrew confirm the behavior is not Persian-only.
 9b  Lines that open with an English word or a bracket but are
     mostly right-to-left. The English opener sits as an island
     and the line still reads right-to-left.
 10  Controls that must always render perfectly.
────────────────────────────────────────────────────────────
GUIDE
