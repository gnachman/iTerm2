#!/usr/bin/env bash
# Manual test harness for tmux -CC modifyOtherKeys key delegation (issue 12928).
#
# Run this INSIDE a pane (plain iTerm2, normal tmux, or tmux -CC). It turns on
# xterm modifyOtherKeys=2 for the pane and prints the exact bytes each keypress
# delivers, so you can confirm what actually reaches the application.
#
#   ./tests/tmux_key_inspector.sh
#
# In a tmux -CC pane this makes tmux report pane_key_mode=Ext 2, which switches
# iTerm2 to the modifyOtherKeys mapper (the path under test). Requires the
# profile's "Applications may change how modifiers are reported" (modify other
# keys) to be allowed.
#
# Press Ctrl-] to quit. Compare a key's bytes between plain iTerm2, normal tmux,
# and tmux -CC: with extended-keys-format csi-u they should now all match.

# This loop uses `read -rsN1` and fractional `read -t`, which need bash 4+.
# Stock macOS ships bash 3.2, so re-exec under a newer bash if one is installed.
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  for alt in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [ -x "$alt" ] && exec "$alt" "$0" "$@"
  done
  echo "This harness needs bash 4+ (macOS ships 3.2). Install one:" >&2
  echo "  brew install bash   # then re-run, or: /opt/homebrew/bin/bash $0" >&2
  exit 1
fi

set -u
saved=$(stty -g)
cleanup() { printf '\033[>4m'; stty "$saved" 2>/dev/null; printf '\r\n'; }
trap cleanup EXIT INT TERM

printf '\033[>4;2m'   # request modifyOtherKeys=2
printf 'modifyOtherKeys=2. Press keys to see their bytes.\n'
printf 'Delegated (expect CSI-u under csi-u format):\n'
printf '  Ctrl-J, Ctrl-M, Shift-Enter, Shift-Tab, Ctrl-Shift-J,\n'
printf '  Ctrl-], Ctrl-semicolon, Ctrl-C.\n'
printf 'Text (must print the character, NOT an escape):\n'
printf '  Shift-1 (!), Shift-; (:), Shift-2 (@), plain letters.\n'
printf 'Press Ctrl-] to quit.\n\n'

stty raw -echo
while IFS= read -rsN1 c; do
  seq="$c"
  while IFS= read -rsN1 -t 0.01 d; do seq+="$d"; done
  [ "$seq" = $'\035' ] && break
  hex=$(printf '%s' "$seq" | od -An -tx1 | tr -s ' \n' ' ' | sed 's/^ //;s/ *$//')
  vis=$(printf '%s' "$seq" | cat -v)
  printf 'bytes: %-34s caret: %s\r\n' "$hex" "$vis"
done
