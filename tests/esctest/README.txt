esctest
Automatic unit tests for terminal emulation
George Nachman
georgen@google.com

esctest is a suite of unit tests that test a terminal emulator's similarity to a
theoretical ideal. That ideal is defined as "xterm, but without bugs in George's 
opinion."

The tested set of control sequences are documented somewhat tersely at this URL:
http://invisible-island.net/xterm/ctlseqs/ctlseqs.html

The official documentation for DEC-supported escape sequences is here:
http://www.vt100.net/docs/vt510-rm/.

All tests are automatic; no user interaction is required. As a consequence, some
control sequences cannot be tested. For example, it is impossible to examine the
color of a particular cell, so color-setting control sequences are not testable.
The character value of a cell is testable, as are various window attributes, and
cursor position; these form the bulk of the tests.


Usage
-----
The most basic usage is:
esctest.py --expected_terminal={iTerm2,xterm}

Flags are as follows:

--disable-xterm-checksum-bug
xterm's implementation of DECRQCRA (as of patch 314) contains a bug. DECRQCRA is
essential to these tests. By default, a workaround for the bug is used. If it is
fixed in the future, this flag should be given until the workaround is dropped.

--include=regex
Only tests whose name matches "regex" will be run.

--expected-terminal=terminal
This has two effects:

1. Each terminal has a different set of known bugs. It should be set to the name
of the terminal the test is running in. This allows any novel bug to be properly
identified, and any bugs that have been fixed can also be found.

2. There are minor implementation differences between terminals (for example the
character used for "blanks", such as when a character is erased). The assertions
and expectations of tests are changed to be appropriate for the current terminal
to avoid false or uninformative failures.

The legal values of "terminal" are "xterm" and "iTerm2".

--no-print-logs
Normally, the test logs are printed when the test finishes. Use this argument to
see what the screen looked like at the time the last-run test finished. Logs are
always written to /tmp/esctest.log.

--test-case-dir=path
If set text files are created in "path" for each test run. They contain the data
that were sent to the terminal. This can be helpful to debug a failing test.

--stop-on-failure
If set, tests stop running after the first failure encountered.

--force
If set, tests will run to completion even though an assertion may fail along the
way.

--options option1 option2 ...
Defines which optional features are enabled in the terminal being tested.

Currently, the only defined option is "xtermWinopsEnabled". Some xterm resources
must be set before this option is used:
  xterm*disallowedWindowOps:
  xterm*allowWindowOps: true
Setting the xtermWinopsEnabled option causes the winops tests to be run.

--max-vt-level=level
Tests are tagged with the VT level required for their execution. No test needing
features from a higher VT level will be run. The default value is 5.


Examples
--------
To test a vanilla xterm:
esctest.py --expected-terminal=xterm

To test xterm with winops enabled:
esctest.py --expected-terminal=xterm --options xtermWinopsEnabled

To test iTerm2:
esctest.py --expected-terminal=iTerm2

To debug a failing test:
esctest.py --test-case-dir=/tmp --stop-on-failure --no-print-logs

