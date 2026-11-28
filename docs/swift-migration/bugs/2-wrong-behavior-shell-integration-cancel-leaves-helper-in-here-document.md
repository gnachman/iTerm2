# Canceling the Internet-Free shell integration install at the wrong moment leaves its helper shell stuck

**Where:** `sources/ShellIntegrationInstaller/iTermShellIntegrationWindowController.m`: `-amendDotFileWithExpectation:...` (the dotfile step, near line 1233) sets the helper state to unknown when it types its `if` line; `-helpersIdleExpectation` (near line 581) returns nil for that state, so `-exitHelperShellsWhenPossible` (near line 660) types nothing.

**What happens:** if the user clicks Cancel while the dotfile step is being typed, the step stops but the helper `sh` is left inside the `if` statement and its here-document, and no installer waits for it to exit. Starting the install again does not wait either: its discovery line goes into the here-document and gets no answer, so the new panel stays busy with no time limit. The same happens when a new install replaces a hidden installer that is in that step (switching tabs and choosing Install Shell Integration again sends the old one Cancel). The window for it is a few shell round trips long.

**Why:** the unknown state means “the helper may be in the middle of a multi-line statement”, and for that state the code knows of no safe text to type, so it types nothing and records nothing to wait for.

**How to see it:** start the Internet-Free install, click Cancel while the dotfile step is typing, then start the install again. Seen by reading the code; not run.

**Suggested fix:** not worked out. One possibility: give the dotfile step a state of its own whose idle text ends the here-document and the `if` (its terminator, then `fi`, then the idle command), as the receive step's state does for its loop.

**Found:** 2026-11-23, review of a change to the installer's lifetime in `PTYTextView`.

**Checked against the tree:** 2026-11-27. The unknown state is still set when the `if` line is sent, and `-helpersIdleExpectation` still returns nil for it.
