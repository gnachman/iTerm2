import argparse

# To enable this option, add the following line to ~/.Xresources:
# xterm*disallowedWindowOps:
# Then run "xrdb -merge ~/.Xresources" and restart xterm.
XTERM_WINOPS_ENABLED = "xtermWinopsEnabled"
DISABLE_WIDE_CHARS = "disableWideChars"

ACTION_RUN="run"
ACTION_LIST_KNOWN_BUGS="list-known-bugs"

parser = argparse.ArgumentParser()
parser.add_argument("--disable-xterm-checksum-bug",
                    help="Don't use buggy parameter order for DECRQCRA",
                    action="store_true")
parser.add_argument("--include",
                    help="Regex for names of tests to run.",
                    default=".*")
parser.add_argument("--expected-terminal",
                    help="Terminal in use. Modifies tests for known differences.",
                    choices=("iTerm2", "xterm"),
                    default="iTerm2")
parser.add_argument("--no-print-logs",
                    help="Print logs after finishing?",
                    action="store_true")
parser.add_argument("--test-case-dir",
                     help="Create files with test cases in the specified directory",
                     default=None)
parser.add_argument("--stop-on-failure",
                    help="Stop running tests after a failure.",
                    action="store_true")
parser.add_argument("--force",
                    help="If set, assertions won't stop execution.",
                    action="store_true")
parser.add_argument("--options",
                    help="Space-separated options that are enabled.",
                    nargs="+",
                    choices=[ XTERM_WINOPS_ENABLED, DISABLE_WIDE_CHARS ])
parser.add_argument("--max-vt-level",
                    help="Do not run tests requiring a higher VT level than this.",
                    type=int,
                    default=5)
parser.add_argument("--logfile",
                    help="Log file to write output to",
                    default="/tmp/esctest.log")
parser.add_argument("--v",
                    help="Verbosity level. 1=errors, 2=errors and info, 3=debug, errors, and info",
                    default=2,
                    type=int)
parser.add_argument("--action",
                    help="Action to perform.",
                    default=ACTION_RUN,
                    choices=[ ACTION_RUN, ACTION_LIST_KNOWN_BUGS ])
parser.add_argument("--timeout",
                    help="Timeout for reading reports from terminal.",
                    default=1,
                    type=float)

