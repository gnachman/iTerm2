#!/bin/bash
# Test script to reproduce Powerline glyph rendering issue (Issue 12745)
#
# The Powerline glyphs E0B0, E0B1, E0B2, E0B3 should render as chevrons (< and >)
# but in 3.6.7+ they incorrectly show a vertical bar on one edge, making them
# look like filled triangles.
#
# To use: Run this script in iTerm2 with "Use built-in Powerline glyphs" enabled
# in Profiles > Text.

# Powerline characters via printf (UTF-8 encoding)
RIGHT_SOLID=$(printf '\xee\x82\xb0')  # U+E0B0 - solid right arrow
RIGHT_LINE=$(printf '\xee\x82\xb1')   # U+E0B1 - line right arrow
LEFT_SOLID=$(printf '\xee\x82\xb2')   # U+E0B2 - solid left arrow
LEFT_LINE=$(printf '\xee\x82\xb3')    # U+E0B3 - line left arrow

# ANSI color codes
RESET=$(printf '\e[0m')
BG_BLUE=$(printf '\e[44m')
BG_GREEN=$(printf '\e[42m')
BG_RED=$(printf '\e[41m')
BG_DEFAULT=$(printf '\e[49m')
FG_BLUE=$(printf '\e[34m')
FG_GREEN=$(printf '\e[32m')
FG_RED=$(printf '\e[31m')
FG_YELLOW=$(printf '\e[33m')
FG_WHITE=$(printf '\e[37m')
FG_BLACK=$(printf '\e[30m')

echo "Powerline Glyph Test (Issue 12745)"
echo "==================================="
echo ""
echo "If you see a vertical bar on the left edge of > or right edge of <,"
echo "then the bug is present."
echo ""

echo "Individual glyphs on default background:"
echo "  E0B0 (solid >): ${RIGHT_SOLID}"
echo "  E0B1 (line >):  ${RIGHT_LINE}"
echo "  E0B2 (solid <): ${LEFT_SOLID}"
echo "  E0B3 (line <):  ${LEFT_LINE}"
echo ""

echo "Simulated Powerline status bar:"
echo "${BG_BLUE}${FG_WHITE} main ${FG_BLUE}${BG_GREEN}${RIGHT_SOLID}${FG_BLACK} branch ${FG_GREEN}${BG_RED}${RIGHT_SOLID}${FG_WHITE} error ${FG_RED}${BG_DEFAULT}${RIGHT_SOLID}${RESET}"
echo ""

echo "Reverse direction:"
echo "${FG_RED}${LEFT_SOLID}${BG_RED}${FG_WHITE} error ${FG_GREEN}${LEFT_SOLID}${BG_GREEN}${FG_BLACK} branch ${FG_BLUE}${LEFT_SOLID}${BG_BLUE}${FG_WHITE} main ${RESET}"
echo ""

echo "Line variants (thin arrows):"
echo "${BG_BLUE}${FG_WHITE} section ${FG_YELLOW}${RIGHT_LINE} subsection ${FG_YELLOW}${RIGHT_LINE} detail ${RESET}"
echo ""

echo "Side by side comparison (solid arrows):"
echo "  Right arrow: [${BG_BLUE} ${FG_BLUE}${BG_GREEN}${RIGHT_SOLID}${FG_GREEN}${BG_DEFAULT}${RIGHT_SOLID}${RESET}]"
echo "  Left arrow:  [${FG_GREEN}${LEFT_SOLID}${BG_GREEN}${FG_BLUE}${LEFT_SOLID}${BG_BLUE} ${RESET}]"
echo ""

echo "The vertical bar appears where the arrow meets the cell boundary."
echo "In 3.6.6, these are clean chevron shapes without any vertical line."
