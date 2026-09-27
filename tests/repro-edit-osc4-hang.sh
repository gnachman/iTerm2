#!/bin/bash
#
# repro-edit-osc4-hang.sh
#
# Reproduces the hang triggered by Microsoft `edit` (github.com/microsoft/edit)
# at startup on iTerm2 <= 3.7.1.
#
# Root cause: `edit` probes the palette with a SINGLE OSC 4 that batches every
# color index into one sequence:
#
#     ESC ] 4 ; 0 ; ? ; 1 ; ? ; 2 ; ? ; ... ; 7 ; ? BEL
#
# In 3.7.1 the report gate (terminalShouldSendReport:) has a single-shot
# "allowNextReport" flag and rolls the WHOLE token back to sync. The first "?"
# in the token is released; the second "?" rolls the token back and re-executes
# it from the top, so index 0 reports forever and the token never advances.
# The mutation thread spins forcing joined syncs and the whole app beachballs.
# Terminal.app just answers each query, which is why `edit` works there.
#
# The pure trigger is a single line:
#
#     printf '\033]4;0;?;1;?;2;?;3;?;4;?;5;?;6;?;7;?\007'
#
# This wrapper adds a safety warning and reads the replies back, so on a FIXED
# build you get a tidy PASS instead of escape codes dumped at your shell prompt.
#
# Usage:
#     tests/repro-edit-osc4-hang.sh          # batched OSC 4 (0-7), the minimal trigger
#     tests/repro-edit-osc4-hang.sh --full   # full `edit` startup handshake
#
# WARNING: On an affected build this FREEZES the window you run it in; you must
# force-quit iTerm2. Save work in other windows first. Fixed on master; the fix
# (issue 13013/13035 report coalescing) landed after the v3.7.1 tag.

set -u

full=0
[ "${1:-}" = "--full" ] && full=1

# OSC 4 queries are answered by whatever owns the tty. tmux/screen intercept
# them, so the app under test never sees the trigger. Refuse to run there.
if [ -n "${TMUX:-}" ] || [ "${TERM%%-*}" = "screen" ] || [ "${TERM%%-*}" = "tmux" ]; then
    echo "Refusing to run inside tmux/screen (they intercept OSC 4). Run directly in an iTerm2 session." >&2
    exit 2
fi
if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "stdin/stdout must be a terminal." >&2
    exit 2
fi

cat <<'BANNER'
============================================================
  Microsoft `edit` batched-OSC-4 hang reproducer
------------------------------------------------------------
  WARNING: on an AFFECTED iTerm2 (<= 3.7.1) this FREEZES
  this window and you must force-quit iTerm2. Save work in
  other windows first.

  On a FIXED build it prints the palette replies and exits 0.
============================================================
BANNER
printf 'Press Return to send the trigger, or Ctrl-C to abort... '
read -r _

save=$(stty -g)
restore() { stty "$save" 2>/dev/null; }
trap restore EXIT INT TERM

# No echo, non-canonical, non-blocking reads (perl's select() does the timing).
# Leave isig on so Ctrl-C still bails.
stty -echo -icanon min 0 time 0

EDIT_FULL=$full perl -e '
    use strict; use warnings;
    use IO::Select;

    open(my $tty, "+<", "/dev/tty") or die "cannot open /dev/tty: $!\n";
    $tty->autoflush(1);

    # Build exactly what `edit` writes.
    my $q = "\x1b]4";
    $q .= ";$_;?" for (0..7);
    $q .= "\x07";
    if ($ENV{EDIT_FULL}) {
        $q .= "\x1b]4";
        $q .= ";$_;?" for (8..15);
        $q .= "\x07";
        # fg + bg queries, cursor-position probe, Primary DA sentinel.
        $q .= "\x1b]10;?\x07\x1b]11;?\x07\x1b[6n\x1b[c";
    }

    syswrite($tty, $q);

    # Wait up to 2s for the first reply byte, then read until a 0.3s quiet gap.
    my $sel = IO::Select->new($tty);
    my $buf = "";
    my $t0  = time;
    if ($sel->can_read(2.0)) {
        while ($sel->can_read(0.3)) {
            my $chunk;
            my $n = sysread($tty, $chunk, 4096);
            last if !defined($n) || $n == 0;
            $buf .= $chunk;
        }
    }
    my $elapsed = time - $t0;

    my @colors;
    while ($buf =~ m{\x1b\]4;(\d+);rgb:([0-9a-fA-F/]+)}g) {
        push @colors, sprintf("index %-3d => rgb:%s", $1, $2);
    }

    print "\r\n";
    if (length($buf) == 0) {
        print "No reply within 2s.\r\n";
        print "  * iTerm2 UI frozen?   -> you reproduced the hang; force-quit iTerm2.\r\n";
        print "  * UI still responsive -> this terminal just does not answer OSC 4 (no bug).\r\n";
        exit 1;
    }
    printf "Got %d bytes in %ds; parsed %d palette reply(ies):\r\n",
        length($buf), $elapsed, scalar(@colors);
    print "  $_\r\n" for @colors;
    print "\r\n";
    if (@colors >= 8) {
        print "RESULT: terminal answered the batched OSC 4 -> NOT affected (fixed build).\r\n";
        exit 0;
    }
    print "RESULT: only a partial reply; inspect the bytes above.\r\n";
    exit 1;
'
status=$?
restore
trap - EXIT INT TERM
exit $status
