#!/usr/bin/env bash
#
# osc133_kinds.sh — Smoke test for the OSC 133 `k=` (prompt kind) parser.
#
# Emits one OSC 133;A for each kind: initial (i, omitted, empty), secondary
# (s), continuation (c), right (r), and an unrecognized value (z) which
# must fold to .unknown. Between each it emits B/C/D so the parser sees a
# complete cycle and any logging code reports each kind once.
#
# WHAT TO CHECK (with iTermLog -t enabled, "OSC 133" filter):
#   * Five "kind=X" / "FTCS A k=X" log lines, one per kind label.
#   * No assertion crashes, no `it_fatalError`.
#   * The terminal cursor advances cleanly between rows (a kind=initial A
#     forces a fresh line; kind!=initial does not — verify by spotting
#     that the right-prompt line stays on the same row as its preceding B).
#
# Run from inside iTerm2: `bash tests/osc133_kinds.sh`

set -u

OSC="\033]"
ST="\033\\"

emit_initial() {
    local label=$1 attr=$2
    printf "${OSC}133;A${attr}${ST}"
    printf "$ "
    printf "${OSC}133;B${ST}"
    printf "echo %s\n" "${label}"
    printf "${OSC}133;C${ST}"
    printf "%s\n" "${label}"
    printf "${OSC}133;D;0${ST}"
}

# k missing → .initial
emit_initial "no-k" ""

# k=i → .initial (explicit)
emit_initial "k=i" ";k=i"

# k= (empty value) → .initial
emit_initial "k=empty" ";k="

# k=s → .secondary
emit_initial "k=s" ";k=s"

# k=c → .continuation
emit_initial "k=c" ";k=c"

# k=r → .right
emit_initial "k=r" ";k=r"

# k=z → .unknown
emit_initial "k=z" ";k=z"

printf "\nAll 7 kinds emitted. Run 'tail -F ~/Library/Application Support/iTerm2/iTerm2/iTermLog-*.log | grep -i prompt' to verify.\n"
