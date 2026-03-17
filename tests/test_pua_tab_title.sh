#!/bin/bash
# Test script for PUA font rendering in tab titles
# Sets the icon title to a mix of ASCII, non-ASCII, and PUA (nerd font) characters

# Nerd font PUA characters:
#   U+E0A0 = Powerline branch symbol
#   U+E0B0 = Powerline arrow right
#   U+F015 = Font Awesome home icon
#   U+F121 = Font Awesome code icon
#   U+E711 = Material Design terminal icon

# Set icon title (OSC 1) with mixed characters:
# "  Home » Tëst  Code"
# Contains: nerd font icons, ASCII, non-ASCII (ë), and more nerd font icons

# U+E0A0 = \xee\x82\xa0, U+E0B0 = \xee\x82\xb0, U+F121 = \xef\x84\xa1
TITLE=$(printf '\xee\x82\xa0 Home \xee\x82\xb0 T\xc3\xabst \xef\x84\xa1 Code')

echo "Title string (should display correctly in terminal if font is configured):"
echo "  $TITLE"
echo ""

printf '\033]1;%s\007' "$TITLE"

echo "Tab title set to a mix of:"
echo "  - Powerline branch symbol (U+E0A0)"
echo "  - ASCII text 'Home'"
echo "  - Powerline arrow (U+E0B0)"
echo "  - Non-ASCII text 'Tëst' (with e-umlaut)"
echo "  - Font Awesome code icon (U+F121)"
echo "  - ASCII text 'Code'"
echo ""
echo "If PUA font fallback is working, you should see the nerd font"
echo "glyphs in the tab title instead of boxes/squares."
echo ""
echo "Press Enter to reset the title, or Ctrl-C to keep it."
read -r
printf '\033]1;\007'
echo "Title reset."
