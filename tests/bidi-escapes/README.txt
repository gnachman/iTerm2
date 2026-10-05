Manual tests for the BDSM and SCP escape sequences (issue 13102)

These files exercise BDSM (CSI 8 h / CSI 8 l, implicit vs explicit bidi mode)
and SCP (CSI Ps SP k, the base direction of reordered lines).

Setup:

1. Settings > General > Experimental: turn on right-to-left text support.
2. Settings > Advanced: “Let apps control right-to-left reordering with the
   BDSM and SCP escape sequences” must be Yes, which is the default.
3. For 4-scp-ltr.txt only, also turn on “Auto-detect paragraph writing
   direction based on the first strong directional character”.

Then cat each file in order. Each file says what you should see. The escapes
are embedded in the files, so cat is enough. 6-reset.txt puts the terminal
back to implicit mode and the default direction; a terminal reset
(Session > Reset) does the same.

To confirm the setting gate, set the advanced setting to No and cat
2-explicit-mode.txt again: the rows scramble like the baseline.

To see the mode report, run: printf '\e[8$p'; sleep 1; echo
With the setting on, the terminal answers ESC [ 8 ; 1 $ y in implicit mode
and ESC [ 8 ; 2 $ y in explicit mode. With the setting off it answers
ESC [ 8 ; 4 $ y.
