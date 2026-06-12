#!/bin/bash
# Enables Touch ID for sudo by ensuring /etc/pam.d/sudo_local
# contains an uncommented pam_tid.so line. Re-execs itself
# under sudo if not already running as root.

set -e

if [ "$EUID" -ne 0 ]; then
    echo "iTerm2 will enable Touch ID for sudo by running:"
    echo "  sudo \"$0\""
    echo
    block_id="iterm2-touchid-install-$$"
    printf '\033]1337;Block=id=%s;attr=start\a' "$block_id"
    echo "Script contents (click to expand):"
    cat "$0"
    printf '\033]1337;Block=id=%s;attr=end\a' "$block_id"
    printf '\033]1337;UpdateBlock=id=%s;action=fold\a' "$block_id"
    echo
    exec sudo "$0"
fi

SUDO_LOCAL=/etc/pam.d/sudo_local
TEMPLATE=/etc/pam.d/sudo_local.template
PAM_LINE='auth       sufficient     pam_tid.so'

if [ -f "$SUDO_LOCAL" ]; then
    SRC=$SUDO_LOCAL
elif [ -f "$TEMPLATE" ]; then
    SRC=$TEMPLATE
else
    echo "$PAM_LINE" > "$SUDO_LOCAL"
    chmod 644 "$SUDO_LOCAL"
    echo "Touch ID for sudo enabled (created $SUDO_LOCAL)."
    exit 0
fi

T=$(mktemp)
trap 'rm -f "$T"' EXIT

sed "s/^#auth.*pam_tid.so/$PAM_LINE/" "$SRC" > "$T"
grep -q '^auth.*pam_tid.so' "$T" || echo "$PAM_LINE" >> "$T"

cp -f "$T" "$SUDO_LOCAL"
chmod 644 "$SUDO_LOCAL"
echo "Touch ID for sudo enabled. Test it with: sudo -k && sudo -v"
