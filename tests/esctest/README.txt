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

Notes on xterm
--------------
You should build xterm yourself and configure it with --enable-dec-locator. Some
tests will fail unless it is provided. Most other configuration settings are not
tested and may or may not cause problems.

Usage
-----
The most basic usage is:
esctest.py --expected-terminal={iTerm2,xterm}

Flags are as follows:

--action={run,list-known-bugs}
Selects the action that the test framework performs.
* run
  Execute the tests. This is the default.
* list-known-bugs
  Do not run any tests; instead, print the list of matching tests (per --include
  and --expected-terminal) that have known bugs. This is useful when looking for
  looking for bugs to fix in your terminal.

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
see what the screen looked like at the time the last-run test finished.

--test-case-dir=path
If set text files are created in "path" for each test run. They contain the data
that were sent to the terminal. This can be helpful to debug a failing test.

--stop-on-failure
If set, tests stop running after the first failure encountered.

--force
If set, tests will run to completion even though an assertion may fail along the
way. Failing tests will appear to pass. This can be useful for debugging.

--options option1 option2 ...
Defines which optional features are enabled in the terminal being tested.

The following options are supported:
* xtermWinopsEnabled
  This option indicates that xterm is configured to allow all window operations,
  some of which are off by default. The following X resources must be set before
  this option is used:
    xterm*disallowedWindowOps:
    xterm*allowWindowOps: true

* disableWideChars
  This option indicates that wide character (that is, UTF-8) support is disabled.
  8-bit controls are tested when this option is enabled.

--max-vt-level=level
Tests are tagged with the VT level required for their execution. No test needing
features from a higher VT level will be run. The default value is 5. In order to
support VT level 5 in xterm, set the following resource:
  xterm*decTerminalID: 520

--logfile=file
The logs are written to "file", which defaults to "/tmp/esctest.log".

--timeout=timeout
The number of seconds to wait for a response from the terminal. Defaults to 1.

--v=verbosity
Verbosity level for logging. The following levels are defined:
* 1: Errors only.
* 2: Errors and informational messages (the default).
* 3: Errors, informational messages, and debug messages.


Examples
--------
To test a vanilla xterm:
esctest.py --expected-terminal=xterm --max-vt-level=4

To test xterm with winops enabled and emulating a VT 520:
esctest.py --expected-terminal=xterm --options xtermWinopsEnabled

To test iTerm2:
esctest.py --expected-terminal=iTerm2

To debug a failing test:
esctest.py --test-case-dir=/tmp --stop-on-failure --no-print-logs


Writing Tests
-------------
Tests are divided into classes. There's one class per file. Each class has tests
for one escape sequence, which may have multiple functions (for example, xterm's
winops).

Test methods must be of the form "test_" + escape sequence name + "_" + details.
Methods not beginning with test_ will not be run.

Every method should use one of the built-in assertion methods, or it will always
fail. The assertion methods are defined in escutil and are:

AssertGE(actual, minimum)
  Asserts that the first value is at least as large as the second value.

AssertEQ(actual, expected)
  Asserts that both values are equal.

AssertTrue(value, details)
  Asserts the value is true. The optional detail will be logged on failure.

AssertScreenCharsInRectEqual(rect, strings)
  Asserts that the characters on the screen within a given rectangle equal those
  passed in the second argument, which is a list of strings (one per row).

Test methods may be decorated with the following decorators, defined in escutil:

@vtLevel(minimum)
  The test will be run only in the --max-vt-level is at least "minimum".

@intentionalDeviationFromSpec(terminal, reason)
  This is for documentation purposes only. The given terminal has some quirk but
  it is intentional, as described in "reason".

@optionRequired(terminal, option, allowPassWithoutOption)
  If the given option is not provided for the given terminal, the test should be
  expected to fail. If it passes anyway, that is an error. The optional argument
  allowPassWithoutOption may be set to true to tolerate passage, which is useful
  for "flaky" tests which might pass by accident. Its use should be avoided.

@knownBug(terminal, reason, noop, shouldTry)
  Indicates that a test is known to fail for a given terminal. The nature of the
  problem should be described in reason. If the test passes when a terminal does
  nothing at all, then noop should be set to True. If the test should be skipped
  for this terminal then the optional shouldTry should be False (e.g., for crash
  bugs).

All test classes are in the "tests" directory. Each is explicitly linked to from
__init__.py.
