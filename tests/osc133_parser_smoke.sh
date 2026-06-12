#!/bin/bash
# tests/osc133_parser_smoke.sh
#
# Manual UI verification of the OSC 133 k= parser (PR 1 / PR 2).
#
# Run from a shell with NO shell integration sourced. Watch the gutter
# (left margin) for mark icons. Press Return between tests.

set -u

ESC=$'\e'
BEL=$'\a'

osc()    { printf '%s]133;%s%s' "$ESC" "$1" "$BEL"; }
say()    { printf '%s\n' "$1"; }
banner() { printf '\n========== %s ==========\n' "$1"; }

press() {
    printf '\n  >>> %s\n  >>> Press Return for next test... ' "$1"
    read -r _
    printf '\n'
}

banner "OSC 133 k= parser smoke tests"
say "Outer shell should have NO shell integration sourced."
say "Watch the gutter (left of each line) for mark icons."
press "Ready?"

# 2.1
banner "TEST 2.1  A;k=i  (expect ONE mark on PRIMARY line)"
osc "A;k=i"; say "[2.1 PRIMARY] echo hi"
osc "B"; osc "C"; say "hi"; osc "D;0"
press "Verify: ONE mark in gutter on the [2.1 PRIMARY] line."

# 2.2
banner "TEST 2.2  A;k=  empty value  (expect ONE mark; treated as initial)"
osc "A;k="; say "[2.2 PRIMARY] echo hi"
osc "B"; osc "C"; say "hi"; osc "D;0"
press "Verify: ONE mark in gutter on the [2.2 PRIMARY] line."

# 2.3
banner "TEST 2.3  A;k=x  unknown value  (expect ONE mark; treated as initial)"
osc "A;k=x"; say "[2.3 PRIMARY] echo hi"
osc "B"; osc "C"; say "hi"; osc "D;0"
press "Verify: ONE mark in gutter on the [2.3 PRIMARY] line."

# 2.4
banner "TEST 2.4  A;aid=foo;k=s  (expect mark on PRIMARY only)"
osc "A"; say "[2.4 PRIMARY]"
osc "B"
osc "A;aid=foo;k=s"; say "[2.4 SECONDARY]"
osc "B"
osc "C"; say "[2.4 output]"; osc "D;0"
press "Verify: mark on PRIMARY, NO mark on SECONDARY."

# 2.5
banner "TEST 2.5  A;k=s;cl=line  (expect mark on PRIMARY only)"
osc "A"; say "[2.5 PRIMARY]"
osc "B"
osc "A;k=s;cl=line"; say "[2.5 SECONDARY]"
osc "B"
osc "C"; say "[2.5 output]"; osc "D;0"
press "Verify: mark on PRIMARY, NO mark on SECONDARY."

# 2.6
banner "TEST 2.6  P;k=s  (expect mark on PRIMARY only; P dispatches like A)"
osc "A"; say "[2.6 PRIMARY]"
osc "B"
osc "P;k=s"; say "[2.6 SECONDARY]"
osc "B"
osc "C"; say "[2.6 output]"; osc "D;0"
press "Verify: mark on PRIMARY, NO mark on SECONDARY."

# 2.7
banner "TEST 2.7  N;k=s  (expect mark on PRIMARY only; N alias for A)"
osc "A"; say "[2.7 PRIMARY]"
osc "B"
osc "N;k=s"; say "[2.7 SECONDARY]"
osc "B"
osc "C"; say "[2.7 output]"; osc "D;0"
press "Verify: mark on PRIMARY, NO mark on SECONDARY."

banner "All parser smoke tests done."
