#!/bin/sh
# Manual test: right-to-left text must look the same while a synchronized update
# (DECSET 2026) is open. Run it in a session with right-to-left support on. The
# three lines must not change during the one-second pause after the "x" appears.
# Before the fix they collapsed to the left margin until the update ended.
printf '\033[2J\033[H'
printf 'سلام دنیا، این یک آزمایش است\r\n'
printf 'The word سلام means hello\r\n'
printf 'کارهای کوچک بدون دسته\r\n'
sleep 1
# One write, so the change and the start of the update arrive together.
printf 'x\033[?2026h'
sleep 1
printf '\033[?2026l\r\n'
