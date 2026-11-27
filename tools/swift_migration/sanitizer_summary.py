#!/usr/bin/env python3
"""Summarize UndefinedBehaviorSanitizer and ThreadSanitizer reports, and
compare ThreadSanitizer reports with the thread baseline.

Part of the Objective-C to Swift migration (docs/swift-migration/phase0.md
section 4). It reads the report files that a sanitizer run writes
(UBSAN_OPTIONS / TSAN_OPTIONS log_path=..., one file per process; see
tools/swift_migration/sanitizer_tests.sh and sanitizer_app.sh), groups the
reports by kind and by source location (file:line:column), counts each, and
prints the totals and the top locations, with the reports in the migration's
scope listed apart from those in other code.

Usage:
    sanitizer_summary.py [PATH ...] [--console LOG ...] [--test-log LOG]
                         [--top N] [--root DIR] [--mixed] [--json]
                         [--baseline FILE] [--fail-on-reports [--nullability-baseline FILE]]
                         [--collect] [--write-nullability-baseline FILE]
                         [--combined] [--symbolize DIR [--atos CMD]]

    PATH      a report file or a directory; a directory is searched
              recursively and every regular file in it is read
    --console LOG
              a console log (for example a run's test.log) that may hold
              some of the same reports as the PATHs: a process whose
              runtime could not write its log_path file prints to stderr
              instead. LOG is read as with --mixed, and for each kind and
              location the larger of the two counts (files, console) is
              taken, so a report that is in both places is counted once.
    --test-log LOG
              also count the tests the xcodebuild log LOG executed (with
              the line formats of tools/swift_migration/test_timing.py). A
              test with a result, skipped included, or one that started and
              has no result (the test host crashed) counts. If there is
              none, say so and exit 3.
    --top N   how many locations to list in each group (default 20)
    --root D  the repository root that absolute paths are made relative to
              (default: the root of the checkout this script is in)
    --mixed   the input is a console log with sanitizer output among other
              text (for example the test.log of a nullability run). Lines
              that are not sanitizer output are then counted as "other
              text" instead of "unparsed"; their number is still printed.
    --json    machine-readable output; each group's "all" lists every
              location, where "top" has the first N
    --baseline FILE
              compare the thread sanitizer reports with the baseline FILE
              (docs/swift-migration/thread-baseline.tsv; see "Thread
              reports" below) and exit 1 if any report is outside it or
              cannot be compared with it
    --fail-on-reports
              exit 1 if there is any UBSan report (outside the
              --nullability-baseline, when one is given), any incomplete
              report or any report file that does not parse, and list each
              location with the tests it came from (see "Failing on
              reports" below). For the nullability mode of
              sanitizer_tests.sh
    --nullability-baseline FILE
              with --fail-on-reports: reports that FILE (normally
              docs/swift-migration/nullability-baseline.tsv) accepts do not
              fail; see "The nullability baseline" below
    --write-nullability-baseline FILE
              write FILE as the baseline of every complete UBSan report
              read (from the reports directory of a whole-suite --collect
              run), keeping each existing entry's note and, unless
              --drop-unseen, the existing entries no report matched; print
              the counts and every entry added, kept unseen or removed, and
              warn about every incomplete report skipped. Exit 0, or 2 if
              the old FILE is malformed or an entry would name an absolute
              path under the home directory (nothing is written then).
              Nothing else is printed
    --drop-unseen
              with --write-nullability-baseline: remove the existing
              entries no report matched
    Root: --root defaults to the checkout the reports ran in when their
              path is <checkout>/tmp/sanitizers/runs/<run>/..., else to the
              checkout this script is in. A --root that disagrees with the
              reports' checkout is refused (exit 2): run with the same
              checkout's script, or pass --root
    --collect with --baseline or --fail-on-reports: print the comparison
              or the verdict but do not exit 1
    --combined
              the reports of the combined mode of sanitizer_tests.sh, which
              holds the nullability group's and the integer group's reports
              together: with --fail-on-reports only nullability reports, and
              any report of neither group, are judged (the verdict says
              "nullability report(s)"); the integer group's reports are
              summarized as informational findings, ending with the line
              "Integer verdict (informational, never fails the run): ...";
              with --write-nullability-baseline integer reports are not
              written. See "The combined mode" below. Needs one of the two
    --symbolize DIR
              before grouping, name the unnamed application frames of the
              thread reports with atos on the binaries of the same name
              under DIR (see "Thread reports")
    --atos CMD
              the atos to run (default: atos on PATH; the tests pass a
              stand-in)

Each location is listed with the message of its first report (which holds
the values) and the function of that report's first stack frame ("#0 ...
in FUNCTION"), with the runtime's +0x offset and its module or file and line
removed; "<unknown>" when the report has no frame or the frame names no
function. The text output prints it on a line of its own ("in FUNCTION").

The migration's scope, by path relative to the root: sources/,
ThirdParty/PSMTabBarControl/, SignedArchive/, pidinfo/,
iTerm2SandboxedWorker/, ShellLauncher/, ColorPicker/,
SearchableComboListView/ and BetterFontPicker/ (README.md section 2). A
report anywhere else, including the tests, an unknown location and a path
outside the root, is "other".

Recognized input:
- UBSan:   <file>:<line>:<col>: runtime error: <message>
           followed by stack frames ("    #0 ...") and "note:" lines, and
           "SUMMARY: UndefinedBehaviorSanitizer: <kind> <location> ...".
           The kind comes from the SUMMARY line; with UBSAN_OPTIONS
           report_error_type=1 it names the check (signed-integer-overflow,
           implicit-integer-truncation, nullability-arg, ...). Without it,
           or with no SUMMARY, the kind is "undefined-behavior". A SUMMARY
           line gives its kind to the open report only if its location is
           that report's; any other UBSan SUMMARY line (for example from
           two processes' output interleaved in one console log) is
           counted as unparsed.
- TSan:    "WARNING: ThreadSanitizer: <kind> (pid=N)", the report body, and
           "SUMMARY: ThreadSanitizer: <kind> <file>:<line>[:<col>] in <func>",
           which gives the location. A report with no SUMMARY line is
           counted at location "<unknown>". The TSan runtime on macOS
           prints only base names; a base name is looked up among the
           source files under the root, and one that matches several files
           is in scope only if all of them are.
- ASan:    "==N==ERROR: AddressSanitizer: <kind> ...", every line after it
           (stack frames, "READ of size ...", "freed by thread ... here:",
           the shadow byte map) up to "==N==ABORTING", the start of another
           report, or the end of the file; "SUMMARY: AddressSanitizer:
           <kind> <file>:<line> in <func>" gives the location. They reach a
           report file in the combined mode, whose UBSAN_OPTIONS log_path
           the address sanitizer runtime shares (its UBSan part reads
           UBSAN_OPTIONS after ASAN_OPTIONS, and log_path is common to
           both). They are counted apart from the UBSan reports and never
           judged here: the runtime ends the process at the first one, so
           the test that was running fails, as in the plain suite.
- Lines that sanitizer runtimes print between reports: blank lines, the
  "=====" separators, "==N==..." runtime messages, "ThreadSanitizer:
  reported N warnings" and "ThreadSanitizer: ..." notices.

Every other line is counted as unparsed and the first of them are shown with
their file and line number, so nothing is dropped silently. Each file is
read a line at a time; memory grows only with the number of distinct
locations.

Note that the UBSan runtime prints a given source location only once per
process, so a count is the number of processes (or report files) in which
that location fired, not the number of times it executed. The
ThreadSanitizer runtime suppresses a report whose stacks equal those of an
earlier report in the same process. The text output says so.

Thread reports (docs/swift-migration/thread-baseline.md section 3). Every
ThreadSanitizer report is also grouped by a key of four parts, printed
after the summary above and in the JSON under "thread":

- kind: from the WARNING line (data race, ...).
- access: the top application frames of the report's first stack (the
  first section with frames that is neither "Previous ..." nor
  "Location is ..."; for a data race the current access).
- previous: the same for the "Previous ..." stack, or "-" if there is none.
- location: the "Location is" line with addresses and thread numbers
  removed ("heap block of size 56", "global 'gFoo'"), or "-".

An application frame is one whose module is one of the app's own images:
iTerm2.debug.dylib, iTerm2, ModernTests, iTermServer, ShellLauncher, pidinfo,
iTerm2SandboxedWorker, iTerm2ImportStatus, and the in-scope frameworks the app
ships prebuilt, BetterFontPicker, ColorPicker and SearchableComboListView.
Every other frame is skipped: the sanitizer
runtime (libclang_rt.*), libdispatch, libsystem_*, libobjc, the Swift
runtime, and Apple's frameworks (Foundation, Metal, XCTest, ...). The key of
a stack is its first application frame, except that a block copy or dispose
helper (__copy_helper_block_..., __destroy_helper_block_...) is shared by
every block with the same capture layout, so for one the next two
application frames are added: "helper ; caller ; caller's caller". A block
invoke function's uniquing suffix, which the compiler renumbers when the
file changes, is removed: "__61-[A b:c:]_block_invoke_2.448" becomes
"__61-[A b:c:]_block_invoke_2". Nothing else in a name is changed. The
other blocks of the same method then share the name, so a baseline entry
for such a frame also needs the previous stack and the location to tell
them apart (thread-baseline.md section 3).

Every line of a report's body is indented; a report with no SUMMARY line
ends at the next unindented line (in a console log, xcodebuild's output) or
at the end of the file, and is counted. A frame the key needs that has no name (the runtime prints "<null>" for an
image without symbols) makes the report unmatchable: it is not compared
with the baseline, it fails the comparison, and the output says which frame
and why. A frame further down the stack may be unnamed without effect.

A group's count is its number of reports (the larger of the report files'
and the console logs' counts, as above) and the number of processes (pids)
they came from; the tests named on any of their frames are listed.

--symbolize DIR names unnamed application frames with
"atos -o BINARY -l 0x0 -arch ARCH OFFSET ..." (the offset in a report is
relative to the image's load address, which -l 0x0 turns into the file's
address), where BINARY is the one file named like the module under DIR,
not counting the copies inside .dSYM bundles.
The binary must be the one that ran: a rebuilt one gives other names at the
same offsets. So for every module whose binary is found, atos is run on the
offsets of the frames that already have names too, and if any name differs
nothing is changed and the output says "Symbolization refused" with the
first difference. Otherwise it says how many frames it named and how many
named frames it checked. If a module has no named frame to check against, the
names are used and the output says they are not verified. Use it on the
build directory of the run that wrote the reports, before anything rebuilds
it, as sanitizer_tests.sh thread does.

The baseline file has one header line, "entry kind access previous location
ledger" separated by tabs, then one accepted report per line in the same
columns, written as this script prints the key; "-" in location accepts any
location. Lines starting with # are comments. A report matches an entry if
kind, access and previous are equal and location is equal or "-". The
comparison prints the groups outside the baseline and the unmatchable ones
(both fail), the groups each entry accepted, the entries no report matched
(informational: after a full-suite run such an entry no longer occurs and
should be removed; after a targeted run it means nothing), and a verdict
line, "Verdict: PASS: ..." or "Verdict: FAIL: ...".

Failing on reports. With --fail-on-reports every UBSan report fails and is
listed with its kind, location, message, the pids of the report files it is
in (from a file name "ubsan.<pid>") and the tests it came from: a test named
on any frame of its stack ("-[FooTests testBar]", "-[ModernTests.FooTests
testBar]", "ModernTests.FooTests.testBar()"), and the test in the report
file's name when the file is named "ubsan.<Class>.<method>.<pid>" (the name a
test bundle that points the runtime's report path at the running test with
__sanitizer_set_report_path makes; sanitizer_tests.sh describes it). A
report with neither names no test. A report file (named "ubsan.<pid>" or
"ubsan.<Class>.<method>.<pid>") with lines that are not sanitizer output,
for example one cut short when a hung test host was killed, fails as well
and is named, since a report may be lost in it. So does an incomplete
report: one in a report file with no stack frame and no SUMMARY line (a
host killed while writing it); it is listed as "incomplete report", never
as a new location. Without a baseline the verdict line is "Verdict: PASS:
no report outside the suppressions." or "Verdict: FAIL: N report(s) at M
location(s) that no suppression hides." (with "; K incomplete report(s)"
and "; K report file(s) with lines that are not a report" added when there
are any). Reports whose declaring header is a generated Swift header
(*-Swift.h) are listed first and flagged as port-relevant.

The nullability baseline. A tab-separated file whose comment header
(NULLABILITY_BASELINE_PREAMBLE below, written into every baseline) gives the
columns, the matching rule and what still shares an entry. In short: kind,
file (relative to the root; an SDK or toolchain file from usr/include/,
usr/lib/ or System/Library/Frameworks/ on, so the Xcode and SDK versions do
not appear), function (a block as "block in <method>", without its index;
"@line N" when the first frame names no function), message, declared (the
base name of the header in the report's "note: ... specified here" line,
or -), note. The first five must be equal. The line is not in the key, so
an unrelated edit keeps the match, as the thread baseline keys on frames.
The report text has no declaration name: UBSan's messages name only the
argument number, and the note line gives the header's path, line and
column but no source text, so the header's base name is the most a stable
key can take from it. With a baseline, the verdict counts the reports it
accepted, lists the entries no report matched as candidates for removal,
and reads "Verdict: PASS: no report outside the baseline; N report(s)
accepted by it." or "Verdict: FAIL: N report(s) at M location(s) outside
the baseline; K report(s) accepted by it." (plus the incomplete and
unparsable counts).

The combined mode (--combined). Which group a UBSan report belongs to is
decided by its kind, the runtime's check name from the SUMMARY line
(NULLABILITY_KINDS and INTEGER_KINDS below; a nullability-arg report is
"invalid-null-argument", nullability-return "invalid-null-return",
nullability-assign "null-pointer-use"), and for a report with no kind by
its message. A report of neither group cannot come from the combined
build's checks as written; it is judged with the nullability reports, the
safe direction, and flagged. An incomplete report whose message is the
integer group's is an integer finding, not a failure. The nullability
baseline and the runtime suppressions apply as in the nullability mode.

Exit status: 0 success, 1 with --baseline (and without --collect) a thread
report outside the baseline or unmatchable, or with --fail-on-reports (and
without --collect) a UBSan report (with --combined, one the combined
verdict judges) outside the nullability baseline, an
incomplete report or an unparsable report file, 2 usage error, unreadable input
or a malformed baseline file, 3 --test-log names a log in which no test was
executed (this outranks 1).
Python 3 standard library only (and atos for --symbolize). Writes nothing to
disk except the file of --write-nullability-baseline; run with python3 -B.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_timing  # noqa: E402

SCOPE_PREFIXES = (
    "sources/",
    "ThirdParty/PSMTabBarControl/",
    "SignedArchive/",
    "pidinfo/",
    "iTerm2SandboxedWorker/",
    "ShellLauncher/",
    "ColorPicker/",
    "SearchableComboListView/",
    "BetterFontPicker/",
)

UNPARSED_SHOWN = 20

ANSI = re.compile(r"\x1b\[[0-9;]*m")
UBSAN_ERROR = re.compile(r"^(?P<loc>.*?): runtime error: (?P<msg>.*)$")
UBSAN_NOTE = re.compile(r"^.*?: note: ")
# "<path>:<line>:<col>: note: _Nonnull type annotation specified here": the
# declaration a nullability report is about.
UBSAN_NOTE_PATH = re.compile(r"^(?P<path>.*?):\d+:\d+: note: ")
UBSAN_SUMMARY = re.compile(r"^SUMMARY: UndefinedBehaviorSanitizer: (?P<kind>\S+)(?: (?P<loc>\S+))?")
TSAN_WARNING = re.compile(r"^WARNING: ThreadSanitizer: (?P<kind>.+?)(?: \(pid=\d+\))?\s*$")
TSAN_SUMMARY = re.compile(r"^SUMMARY: ThreadSanitizer: (?P<kind>.+?) (?P<loc>\S+:\d+(?::\d+)?) in (?P<func>.*)$")
TSAN_SUMMARY_NOLOC = re.compile(r"^SUMMARY: ThreadSanitizer: (?P<kind>.+?)(?: \(.*\))?(?: in .*)?$")
FRAME = re.compile(r"^\s+#\d+ ")
FRAME0 = re.compile(r"^\s+#0 0x[0-9a-fA-F]+ in (?P<rest>.+)$")
FRAME_ANY = re.compile(r"^\s+#\d+ 0x[0-9a-fA-F]+ in (?P<rest>.+)$")
# A report file's name: "ubsan.<pid>" as log_path writes it, or
# "ubsan.<Class>.<method>.<pid>" when the test bundle points the report path
# at the running test (__sanitizer_set_report_path; see sanitizer_tests.sh).
REPORT_FILE = re.compile(r"^ubsan(?:\.(?:[A-Za-z_]\w*\.)?(?P<cls>[A-Za-z_]\w*)\.(?P<method>[A-Za-z_]\w*))?"
                         r"\.(?P<pid>\d+)$")
# "-[Foo bar:]+0x24 (iTerm2.debug.dylib:arm64+0x6f0e88)": offset and module.
FRAME_MODULE = re.compile(r"^(?P<func>.*?)(?:\+0x[0-9a-fA-F]+)? \([^()]*\)$")
# "main SignProbe.m:11" or "@objc Foo.bar() /<compiler-generated>": file and line.
FRAME_FILE = re.compile(r"^(?P<func>.*?)(?:\+0x[0-9a-fA-F]+)? (?:\S+:\d+(?::\d+)?|/<compiler-generated>)$")
BETWEEN_REPORTS = re.compile(
    r"^(\s*|=+|==\d+==.*|ThreadSanitizer: reported \d+ warnings?|ThreadSanitizer: .*)$")
# An address sanitizer report: "==PID==ERROR: AddressSanitizer: <kind> ...",
# its body (unindented lines among them: "READ of size 4 ...", "freed by
# thread T0 here:", the shadow byte map), "SUMMARY: AddressSanitizer: <kind>
# <file>:<line> in <function>", and "==PID==ABORTING".
ASAN_ERROR = re.compile(r"^==(?P<pid>\d+)==ERROR: AddressSanitizer: (?P<kind>\S+)")
ASAN_SUMMARY = re.compile(r"^SUMMARY: AddressSanitizer: (?P<kind>\S+)(?: (?P<loc>\S+))?")
ASAN_END = re.compile(r"^==\d+==ABORTING")

# Which group of the combined mode a UBSan report belongs to. The kind is
# the SUMMARY line's (UBSAN_OPTIONS report_error_type=1), the runtime's
# name for the check: a nullability-arg report is "invalid-null-argument",
# nullability-return "invalid-null-return", nullability-assign
# "null-pointer-use" (each shared with a check of the undefined group,
# nonnull-attribute, returns-nonnull-attribute and null, that no mode of
# sanitizer_tests.sh compiles), and the integer group's checks have the
# kinds below (seen on 2026-11-26 in a program built with the combined
# mode's flags; the shift-* names are the flag names, accepted too). A
# report with no kind ("undefined-behavior": no SUMMARY line) is classified
# by its message.
NULLABILITY_KINDS = frozenset((
    "invalid-null-argument", "invalid-null-return", "null-pointer-use",
    "nullability-arg", "nullability-return", "nullability-assign"))
INTEGER_KINDS = frozenset((
    "signed-integer-overflow", "implicit-signed-integer-truncation", "implicit-unsigned-integer-truncation",
    "implicit-integer-sign-change", "implicit-signed-integer-truncation-or-sign-change",
    "float-cast-overflow", "integer-divide-by-zero", "invalid-shift-base", "invalid-shift-exponent",
    "shift-base", "shift-exponent", "out-of-bounds-index"))
NULLABILITY_MESSAGE = re.compile(
    r"^(?:null pointer passed as argument \d+, which is declared to never be null"
    r"|null pointer returned from function declared to never return null"
    r"|_Nonnull binding to null pointer)")
INTEGER_MESSAGE = re.compile(
    r"^(?:signed integer overflow:|implicit conversion from type |division by zero|shift exponent "
    r"|left shift of |index -?\d+ out of bounds |.* is outside the range of representable values of type )")


def ubsan_family(kind, message):
    """"nullability", "integer", or None when a UBSan report of this kind and
    message belongs to neither group."""
    if kind in NULLABILITY_KINDS:
        return "nullability"
    if kind in INTEGER_KINDS:
        return "integer"
    if NULLABILITY_MESSAGE.match(message or ""):
        return "nullability"
    if INTEGER_MESSAGE.match(message or ""):
        return "integer"
    return None


def frame_function(line, pattern=FRAME0):
    """The function named by a "#0" stack frame line (with pattern=FRAME_ANY,
    any UBSan stack frame line), or None."""
    m = pattern.match(line)
    if not m:
        return None
    rest = m.group("rest").strip()
    if rest[:2] in ("-[", "+[") and "]" in rest:
        return rest[:rest.index("]") + 1]
    for pattern in (FRAME_MODULE, FRAME_FILE):
        m = pattern.match(rest)
        if m:
            return m.group("func") or None
    return rest


def default_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


SOURCE_EXTENSIONS = (".m", ".mm", ".c", ".cc", ".cpp", ".h", ".hpp", ".swift")
INDEX_SKIP = {".git", "Build", "build", "tmp", "DerivedData", ".build", "node_modules"}
HEX = re.compile(r"0x[0-9a-fA-F]+")


class Locations:
    """Turns a report's file name into a path relative to the root.

    UBSan reports carry the absolute path the compiler was given. The
    ThreadSanitizer runtime on macOS prints only the file's base name
    (SanitizerProbeTests.m:103), so a base name is looked up in an index of
    the source files under the root, built the first time one is needed. A
    base name that matches more than one file is in scope only if every match
    is, and is shown with the number of candidates."""

    def __init__(self, root):
        self.root = root.rstrip("/") + "/"
        self.index = None

    def candidates(self, path):
        """Relative paths the file name may refer to (empty: outside root)."""
        if not path or path.startswith("<"):
            return []
        if os.path.isabs(path):
            return [path[len(self.root):]] if path.startswith(self.root) else []
        if "/" in path:
            return [path]
        if self.index is None:
            self.index = {}
            for dirpath, dirnames, filenames in os.walk(self.root):
                dirnames[:] = sorted(d for d in dirnames if d not in INDEX_SKIP)
                rel = os.path.relpath(dirpath, self.root)
                for name in filenames:
                    if name.endswith(SOURCE_EXTENSIONS):
                        self.index.setdefault(name, []).append(
                            name if rel == "." else os.path.join(rel, name))
        return self.index.get(path, [])

    def in_scope(self, location):
        found = self.candidates(location.split(":", 1)[0])
        return bool(found) and all(c.startswith(SCOPE_PREFIXES) for c in found)

    def display(self, location):
        if location.startswith("<"):
            return location
        path, sep, rest = location.partition(":")
        found = self.candidates(path)
        if len(found) == 1:
            return found[0] + sep + rest
        if len(found) > 1:
            return "%s%s%s (ambiguous: %d files have this name)" % (path, sep, rest, len(found))
        return location


class Summary:
    def __init__(self, root, mixed):
        self.locations = Locations(root)
        self.mixed = mixed
        self.files = 0
        self.lines = 0
        self.file_reports = Counter()     # (kind, location) -> count, from report files
        self.console_reports = Counter()  # the same, from --console logs
        self.current = self.file_reports  # where the file being read counts
        self.samples = {}               # (kind, location) -> first message
        self.functions = {}             # (kind, location) -> its first report's function
        self.unparsed = 0
        self.unparsed_shown = []        # (file, lineno, text)
        self.other_text = 0
        self.thread = ThreadParser()
        # (kind, location) of each UBSan report -> {"pids": set, "tests": set}:
        # the pids from the report files' names, and the tests named on the
        # reports' frames or in the files' names (--fail-on-reports).
        self.ubsan_info = {}
        self.file_pid = None
        self.file_test = None
        # Report files (named as REPORT_FILE) with lines that are not
        # sanitizer output: path -> number of such lines (--fail-on-reports).
        self.unparsed_report_files = Counter()
        # (kind, location) -> base name of the file of its first report's
        # "note:" line (the declaring header), for the nullability baseline.
        self.notes = {}
        # UBSan reports in report files cut off before their first frame
        # and with no SUMMARY line (a host killed while it wrote): (path,
        # location). Never matched against or written into a baseline.
        self.incomplete = []
        self.current_path = None
        # Address sanitizer reports, (kind, location) -> count, from the
        # report files and from the console logs (counted once as above),
        # and -> {"pids": set, "tests": set}. They are never UBSan reports.
        self.address_file = Counter()
        self.address_console = Counter()
        self.address_info = {}

    @property
    def reports(self):
        """Each (kind, location) counted once whether it came from the report
        files, the console logs or both: the larger of the two counts."""
        return self.file_reports | self.console_reports

    # One open report at a time: ("ubsan", location, message, kind, function)
    # or ("tsan", kind, message), where a TSan report's message is the first
    # line of its body with addresses blanked, and a UBSan report's function
    # comes from its "#0" frame (None until that line is read). It is
    # recorded when its SUMMARY line arrives, when the next report starts,
    # or at the end of the file.
    def read(self, path, console=False):
        self.files += 1
        m = None if console else REPORT_FILE.match(os.path.basename(path))
        self.file_pid = m.group("pid") if m else None
        self.file_test = "%s.%s" % (m.group("cls"), m.group("method")) if m and m.group("cls") else None
        self.current = self.console_reports if console else self.file_reports
        self.current_path = path
        mixed = self.mixed
        self.mixed = mixed or console
        try:
            self.read_lines(path)
        finally:
            self.mixed = mixed
            self.current = self.file_reports

    def read_lines(self, path):
        pending = None
        self.thread.start_file(self.current is self.console_reports)
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for lineno, raw in enumerate(f, 1):
                self.lines += 1
                # The runtimes color their output when it goes to a terminal
                # (or xcodebuild's pipe); the escapes are removed.
                line = ANSI.sub("", raw.rstrip("\n"))
                self.thread.line(line)
                pending = self.line(path, lineno, line, pending)
        self.finish(pending)
        self.thread.finish()

    def finish(self, pending, location=None, kind=None, summarized=False):
        if pending is None:
            return
        if pending[0] == "asan":
            _, akind, loc, tests, pid = pending
            key = (akind, loc)
            (self.address_console if self.current is self.console_reports else self.address_file)[key] += 1
            info = self.address_info.setdefault(key, {"pids": set(), "tests": set()})
            info["tests"] |= tests
            if self.file_test:
                info["tests"].add(self.file_test)
            if self.file_pid or pid:
                info["pids"].add(self.file_pid or pid)
            return
        if pending[0] == "ubsan":
            _, loc, msg, pkind, function, tests, note = pending
            self.add(kind or pkind, loc, msg, function)
            if (not summarized and function is None and self.current is self.file_reports
                    and REPORT_FILE.match(os.path.basename(self.current_path or ""))):
                self.incomplete.append((self.current_path, loc))
                return
            if note:
                self.notes.setdefault((kind or pkind, loc), note)
            info = self.ubsan_info.setdefault((kind or pkind, loc), {"pids": set(), "tests": set()})
            info["tests"] |= tests
            if self.file_test:
                info["tests"].add(self.file_test)
            if self.file_pid:
                info["pids"].add(self.file_pid)
        else:
            _, pkind, msg = pending
            self.add(kind or pkind, location or "<unknown>", msg or pkind)

    def add(self, kind, location, message, function=None):
        key = (kind, location)
        self.current[key] += 1
        self.samples.setdefault(key, message)
        self.functions.setdefault(key, function or "<unknown>")

    def line(self, path, lineno, line, pending):
        if pending is not None and pending[0] == "asan":
            # Every line of an address sanitizer report up to its ABORTING
            # line belongs to it; the start of another report ends it too.
            if ASAN_END.match(line):
                self.finish(pending)
                return None
            if not (UBSAN_ERROR.match(line) or TSAN_WARNING.match(line) or ASAN_ERROR.match(line)):
                m = ASAN_SUMMARY.match(line)
                if m:
                    return pending[:2] + (m.group("loc") or "<unknown>",) + pending[3:]
                if FRAME.match(line):
                    self.add_test_from_frame(line, pending[3])
                return pending
        m = ASAN_ERROR.match(line)
        if m:
            self.finish(pending)
            return ("asan", m.group("kind"), "<unknown>", set(), m.group("pid"))
        m = UBSAN_ERROR.match(line)
        if m:
            self.finish(pending)
            return ("ubsan", m.group("loc"), m.group("msg"), "undefined-behavior", None, set(), None)
        m = TSAN_WARNING.match(line)
        if m:
            self.finish(pending)
            return ("tsan", m.group("kind"), None)
        m = UBSAN_SUMMARY.match(line)
        if m:
            # A report at "<unknown>" has no location to compare with.
            if pending is not None and pending[0] == "ubsan" and (
                    m.group("loc") == pending[1] or pending[1].startswith("<")):
                kind = m.group("kind")
                self.finish(pending, kind=None if kind == "undefined-behavior" else kind, summarized=True)
                return None
            # Not the open report's SUMMARY (another process's, interleaved
            # with it, or one whose report line was lost): the open report
            # stays open and the line is counted as unparsed, even in a
            # console log, since it is sanitizer output.
            self.count_unparsed(path, lineno, line)
            return pending
        if line.startswith("SUMMARY: ThreadSanitizer:") and pending is not None and pending[0] == "tsan":
            m = TSAN_SUMMARY.match(line)
            if m:
                self.finish(pending, location=m.group("loc"), kind=m.group("kind"))
            else:
                self.finish(pending)
            return None
        if pending is not None:
            if pending[0] == "tsan":
                # Everything between a TSan WARNING and its SUMMARY is the
                # report body.
                if pending[2] is None and line.strip():
                    return ("tsan", pending[1], HEX.sub("0x...", line.strip()))
                return pending
            if FRAME.match(line):
                self.add_test_from_frame(line, pending[5])
                if pending[4] is None:
                    function = frame_function(line)
                    if function is not None or line.lstrip().startswith("#0 "):
                        return pending[:4] + (function or "<unknown>",) + pending[5:]
                return pending
            m = UBSAN_NOTE_PATH.match(line)
            if m:
                if pending[6] is None:
                    return pending[:6] + (os.path.basename(m.group("path")),)
                return pending
            if UBSAN_NOTE.match(line) or not line.strip():
                return pending
        if BETWEEN_REPORTS.match(line):
            return pending
        if self.mixed:
            self.other_text += 1
            return pending
        self.count_unparsed(path, lineno, line)
        return pending

    @staticmethod
    def add_test_from_frame(line, tests):
        """Adds to tests the test a UBSan or ASan stack frame line names."""
        name = frame_function(line, FRAME_ANY)
        if name:
            for pattern in TEST_FRAME:
                t = pattern.match(name)
                if t:
                    tests.add("%s.%s" % (t.group(1), t.group(2)))

    def count_unparsed(self, path, lineno, line):
        self.unparsed += 1
        if self.current is self.file_reports and REPORT_FILE.match(os.path.basename(path)):
            self.unparsed_report_files[path] += 1
        if len(self.unparsed_shown) < UNPARSED_SHOWN:
            self.unparsed_shown.append((path, lineno, line))

    def result(self, top):
        def rows(scope):
            items = [(count, kind, loc) for (kind, loc), count in self.reports.items()
                     if self.locations.in_scope(loc) == scope]
            items.sort(key=lambda r: (-r[0], r[1], r[2]))
            return items

        def by_kind(items):
            c = Counter()
            for count, kind, _ in items:
                c[kind] += count
            return sorted(c.items(), key=lambda kv: (-kv[1], kv[0]))

        def describe(items):
            listed = [{"count": n, "kind": k, "location": self.locations.display(loc),
                       "message": self.samples[(k, loc)],
                       "function": self.functions[(k, loc)]} for n, k, loc in items]
            return {
                "reports": sum(r[0] for r in items),
                "locations": len(items),
                "by_kind": [{"kind": k, "count": n} for k, n in by_kind(items)],
                "top": listed[:top],
                "not_shown": max(0, len(items) - top),
                "all": listed,
            }

        reports = self.reports
        scoped = rows(True)
        other = rows(False)
        return {
            "files": self.files,
            "lines": self.lines,
            "reports": sum(reports.values()),
            "locations": len(reports),
            "console_only": sum((self.console_reports - self.file_reports).values()),
            "in_both": sum((self.console_reports & self.file_reports).values()),
            "in_scope": describe(scoped),
            "other": describe(other),
            "unparsed": self.unparsed,
            "unparsed_shown": [{"file": p, "line": n, "text": t} for p, n, t in self.unparsed_shown],
            "other_text": self.other_text,
            "address": self.address_result(),
        }

    def address_result(self):
        counts = self.address_file | self.address_console
        groups = [{"count": n, "kind": kind, "location": self.locations.display(loc),
                   "tests": sorted(self.address_info[(kind, loc)]["tests"]),
                   "pids": sorted(self.address_info[(kind, loc)]["pids"], key=int)}
                  for (kind, loc), n in counts.items()]
        groups.sort(key=lambda g: (-g["count"], g["kind"], g["location"]))
        return {"reports": sum(counts.values()), "locations": len(counts), "groups": groups}

    def integer_result(self, top):
        """The integer findings of a combined run: every UBSan report of the
        integer group, informational."""
        items = [(n, kind, loc) for (kind, loc), n in self.reports.items()
                 if ubsan_family(kind, self.samples.get((kind, loc))) == "integer"]
        items.sort(key=lambda r: (-r[0], r[1], r[2]))
        by_kind = Counter()
        for n, kind, _ in items:
            by_kind[kind] += n
        return {"reports": sum(r[0] for r in items), "locations": len(items),
                "in_scope": sum(n for n, _, loc in items if self.locations.in_scope(loc)),
                "by_kind": [{"kind": k, "count": n} for k, n in sorted(by_kind.items(), key=lambda kv: (-kv[1], kv[0]))],
                "top": [{"count": n, "kind": k, "location": self.locations.display(loc),
                         "message": self.samples[(k, loc)]} for n, k, loc in items[:top]],
                "not_shown": max(0, len(items) - top)}


## Thread sanitizer reports by top application frames
#
# See "Thread reports" in the module docstring for the definitions.

APP_MODULES = frozenset((
    "iTerm2.debug.dylib", "iTerm2", "ModernTests",
    "iTermServer", "ShellLauncher", "pidinfo", "iTerm2SandboxedWorker", "iTerm2ImportStatus",
    # In scope, shipped prebuilt in Contents/Frameworks.
    "BetterFontPicker", "ColorPicker", "SearchableComboListView",
))
BLOCK_INVOKE_SUFFIX = re.compile(r"(_block_invoke(?:_\d+)?)\.\d+$")
BLOCK_HELPER = re.compile(r"^__(?:copy|destroy)_helper_block_")
HELPER_CONTEXT = 2
# ThreadSanitizer's frame form, "#N function location (module:arch+offset)";
# frame_function above reads UBSan's "#0 0x... in function ..." form.
TSAN_FRAME_LINE = re.compile(r"^\s+#(?P<n>\d+) (?P<rest>.*?)\s*$")
TSAN_FRAME_MODULE = re.compile(r"^(?P<head>.*?) ?\((?P<module>[^():+]+)(?::(?P<arch>[^+():]+))?\+(?P<off>0x[0-9a-fA-F]+)\)$")
UNNAMED = re.compile(r"^(?:<null>|<unknown>|0x[0-9a-fA-F]+|)$")
TSAN_PID = re.compile(r"\(pid=(\d+)\)")
TEST_FRAME = (re.compile(r"^(?:@objc )?(?:\w+\.)?(\w+)\.(test\w*)\(\)$"),
              re.compile(r"^-\[(?:\w+\.)?(\w+) (test\w*)\]$"))
CHAIN_SEPARATOR = " ; "
NO_PREVIOUS = "-"
ANY_LOCATION = "-"
NO_APP_FRAME = "<no application frame>"
BASELINE_COLUMNS = ["entry", "kind", "access", "previous", "location", "ledger"]


def normalize_function(name):
    """A frame's function name with the compiler's uniquing suffix of a block
    invoke function removed: "..._block_invoke_2.448" becomes
    "..._block_invoke_2". Nothing else is changed."""
    return BLOCK_INVOKE_SUFFIX.sub(r"\1", name)


class Frame:
    __slots__ = ("index", "function", "module", "arch", "offset")

    def __init__(self, index, function, module, arch, offset):
        self.index = index
        self.function = function  # None when the runtime printed no name
        self.module = module
        self.arch = arch
        self.offset = offset

    def address(self):
        if self.module is None:
            return "unknown module"
        return "%s:%s+%s" % (self.module, self.arch, self.offset) if self.arch else \
            "%s+%s" % (self.module, self.offset)


def parse_frame(line):
    """A ThreadSanitizer stack frame line, "#N function location (module:arch+offset)",
    as a Frame, or None if the line is not a frame. The location is one
    token (<null>, a file name with or without a line, /<compiler-generated>);
    the function may contain spaces."""
    m = TSAN_FRAME_LINE.match(line)
    if not m:
        return None
    rest = m.group("rest")
    module = arch = offset = None
    mm = TSAN_FRAME_MODULE.match(rest)
    if mm:
        rest = mm.group("head")
        module, arch, offset = mm.group("module"), mm.group("arch"), mm.group("off")
    function, sep, _location = rest.rpartition(" ")
    if not sep:
        function = rest
    function = function.strip()
    return Frame(int(m.group("n")), None if UNNAMED.match(function) else function, module, arch, offset)


def describe_location(text):
    """ "heap block of size 56 at 0x... allocated by thread T243:" becomes
    "heap block of size 56"; addresses and thread numbers are removed."""
    text = text.split(" at 0x", 1)[0]
    text = re.sub(r"\bT\d+\b", "T*", text)
    return text.rstrip(":. ")


class ThreadReport:
    __slots__ = ("kind", "pid", "sections", "location", "tests")

    def __init__(self, kind, pid):
        self.kind = kind
        self.pid = pid
        self.sections = []   # [header, [Frame, ...]]
        self.location = None
        self.tests = set()

    def first_stack(self):
        for header, frames in self.sections:
            if frames and not header.startswith(("Previous ", "Location is ")):
                return frames
        return []

    def previous_stack(self):
        for header, frames in self.sections:
            if header.startswith("Previous "):
                return frames
        return None


class ThreadParser:
    """Collects ThreadSanitizer reports, a line at a time, with the frames of
    each stack. Only the reports are kept, not the text."""

    def __init__(self):
        self.reports = {False: [], True: []}  # console? -> [ThreadReport]
        self.open = None
        self.console = False

    def start_file(self, console):
        self.finish()
        self.console = console

    def finish(self):
        if self.open is not None:
            self.reports[self.console].append(self.open)
            self.open = None

    def line(self, line):
        m = TSAN_WARNING.match(line)
        if m:
            self.finish()
            pid = TSAN_PID.search(line)
            self.open = ThreadReport(m.group("kind"), pid.group(1) if pid else None)
            return
        report = self.open
        if report is None:
            return
        if line.startswith("SUMMARY: ThreadSanitizer:"):
            self.finish()
            return
        frame = parse_frame(line)
        if frame is not None:
            if not report.sections:
                report.sections.append(["", []])
            report.sections[-1][1].append(frame)
            if frame.function:
                for pattern in TEST_FRAME:
                    t = pattern.match(frame.function)
                    if t:
                        report.tests.add("%s.%s" % (t.group(1), t.group(2)))
            return
        text = line.strip()
        if not text or text.startswith("==="):
            return
        if not line[:1].isspace():
            # Every line of a report body is indented. An unindented line
            # (xcodebuild's output in a console log) means the report ended
            # without its SUMMARY line.
            self.finish()
            return
        report.sections.append([text, []])
        if text.startswith("Location is ") and report.location is None:
            report.location = describe_location(text[len("Location is "):])


def stack_key(frames, which):
    """(the key text of a stack, the reason it cannot be matched or None).
    The key is the top application frame, extended for a block copy or
    dispose helper by the next HELPER_CONTEXT application frames."""
    app = [f for f in frames if f.module in APP_MODULES]
    if not app:
        return NO_APP_FRAME, None
    chain = app[:1 + HELPER_CONTEXT] if app[0].function and BLOCK_HELPER.match(app[0].function) else app[:1]
    for f in chain:
        if f.function is None:
            return ("<frame #%d: %s>" % (f.index, f.address()),
                    "frame #%d of the %s stack (%s) has no name" % (f.index, which, f.address()))
    return CHAIN_SEPARATOR.join(normalize_function(f.function) for f in chain), None


def report_key(report):
    """((kind, access, previous, location), reason or None)."""
    access, why_a = stack_key(report.first_stack(), "first")
    prev_frames = report.previous_stack()
    if prev_frames is None:
        previous, why_p = NO_PREVIOUS, None
    else:
        previous, why_p = stack_key(prev_frames, "previous")
    reasons = [w for w in (why_a, why_p) if w]
    return (report.kind, access, previous, report.location or ANY_LOCATION), "; ".join(reasons) or None


class BaselineError(Exception):
    pass


def read_baseline(path):
    entries = []
    seen = set()
    header = None
    with open(path, "r", encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.split("\t")
            where = "baseline %s line %d" % (path, lineno)
            if header is None:
                if fields != BASELINE_COLUMNS:
                    raise BaselineError("%s: the header must be the columns %s, tab-separated"
                                        % (where, " ".join(BASELINE_COLUMNS)))
                header = fields
                continue
            if len(fields) != len(BASELINE_COLUMNS):
                raise BaselineError("%s: %d columns, expected %d" % (where, len(fields), len(BASELINE_COLUMNS)))
            row = dict(zip(BASELINE_COLUMNS, (x.strip() for x in fields)))
            for column in BASELINE_COLUMNS:
                if not row[column]:
                    raise BaselineError("%s: the %s column is empty" % (where, column))
            if row["entry"] in seen:
                raise BaselineError("%s: entry %s appears twice" % (where, row["entry"]))
            seen.add(row["entry"])
            for column in ("access", "previous"):
                if column == "previous" and row[column] == NO_PREVIOUS:
                    continue
                for name in row[column].split(CHAIN_SEPARATOR):
                    if not name or name.startswith("<"):
                        raise BaselineError("%s: %s has an empty or placeholder frame" % (where, column))
                    if normalize_function(name) != name:
                        raise BaselineError("%s: %s frame %r still has its .N suffix; write %r"
                                            % (where, column, name, normalize_function(name)))
            entries.append(row)
    if header is None:
        raise BaselineError("baseline %s: no header line" % path)
    return entries


def baseline_entry(key, entries):
    kind, access, previous, location = key
    for e in entries:
        if (e["kind"] == kind and e["access"] == access and e["previous"] == previous
                and (e["location"] == ANY_LOCATION or e["location"] == location)):
            return e["entry"]
    return None


ATOS_LINE = re.compile(r"^(?P<name>.*?) \(in (?P<module>[^)]*)\)(?: \+ \d+| \(.*\))?$")


def find_binary(build_dir, module):
    found = {}
    for dirpath, dirnames, filenames in os.walk(build_dir):
        # dsymutil's output holds a copy of the binary's name (DWARF only).
        dirnames[:] = sorted(d for d in dirnames if not d.endswith(".dSYM"))
        if module in filenames:
            full = os.path.join(dirpath, module)
            if os.path.isfile(full):
                st = os.stat(full)
                found.setdefault((st.st_size, int(st.st_mtime)), full)
    return list(found.values())


def run_atos(atos, binary, arch, offsets):
    cmd = [atos, "-o", binary, "-l", "0x0"] + (["-arch", arch] if arch else []) + offsets
    out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         timeout=300, check=True).stdout.splitlines()
    names = {}
    for offset, line in zip(offsets, out):
        m = ATOS_LINE.match(line.strip())
        names[offset] = m.group("name") if m else None
    return names


def symbolize(reports, build_dir, atos):
    """Names the unnamed application frames of the reports with atos on the
    binaries under build_dir, after checking that each binary gives the
    report's own names at the offsets of its named frames. Returns a dict
    for the output; changes the frames only if nothing was refused."""
    result = {"directory": build_dir, "named": 0, "checked": 0, "refused": None, "unverified": []}
    frames = [f for r in reports for _, stack in r.sections for f in stack if f.module in APP_MODULES]
    need = {f.module for f in frames if f.function is None}
    resolved = {}  # (module, arch, offset) -> name
    # Every module is checked when its binary is there; a module with
    # frames to name must be there.
    for module in sorted({f.module for f in frames}):
        binaries = find_binary(build_dir, module)
        if not binaries:
            if module in need:
                result["refused"] = "no file named %s under %s" % (module, build_dir)
                return result
            continue
        if len(binaries) > 1:
            result["refused"] = "several different files named %s under %s: %s" % (
                module, build_dir, ", ".join(binaries))
            return result
        by_arch = {}
        for f in frames:
            if f.module == module:
                by_arch.setdefault(f.arch, set()).add(f.offset)
        checked = 0
        for arch, offsets in sorted(by_arch.items(), key=lambda kv: kv[0] or ""):
            try:
                names = run_atos(atos, binaries[0], arch, sorted(offsets))
            except Exception as e:  # noqa: BLE001: any failure refuses
                result["refused"] = "atos failed on %s: %s" % (binaries[0], e)
                return result
            for f in frames:
                if f.module != module or f.arch != arch:
                    continue
                name = names.get(f.offset)
                if f.function is not None and name is not None:
                    if name != f.function:
                        result["refused"] = (
                            "atos on %s gives %r at +%s where the report has %r: it is not the binary that ran"
                            % (binaries[0], name, f.offset, f.function))
                        return result
                    checked += 1
                    result["checked"] += 1
                resolved[(module, arch, f.offset)] = name
        if not checked and module in need:
            result["unverified"].append(module)
    for f in frames:
        if f.function is None:
            name = resolved.get((f.module, f.arch, f.offset))
            if name:
                f.function = name
                result["named"] += 1
    for r in reports:
        for _, stack in r.sections:
            for f in stack:
                for pattern in TEST_FRAME:
                    t = f.function and pattern.match(f.function)
                    if t:
                        r.tests.add("%s.%s" % (t.group(1), t.group(2)))
    return result


def thread_groups(parser, entries):
    """Groups of the reports by key: a list of dicts, sorted by key. For each
    key the larger of the two counts (report files, console logs) is taken,
    so a report found in both is counted once, as for the other reports."""
    counts = {False: Counter(), True: Counter()}
    info = {}
    for console, reports in parser.reports.items():
        for r in reports:
            key, why = report_key(r)
            counts[console][key] += 1
            g = info.setdefault(key, {"pids": set(), "tests": set(), "unmatchable": why})
            if r.pid:
                g["pids"].add(r.pid)
            g["tests"] |= r.tests
    total = counts[False] | counts[True]
    groups = []
    for key in sorted(total):
        kind, access, previous, location = key
        g = info[key]
        entry = None if (g["unmatchable"] or entries is None) else baseline_entry(key, entries)
        groups.append({"kind": kind, "access": access, "previous": previous, "location": location,
                       "reports": total[key], "processes": len(g["pids"]),
                       "tests": sorted(g["tests"]), "unmatchable": g["unmatchable"], "entry": entry})
    return groups


def compare_baseline(groups, entries, path, collect):
    accepted = [g for g in groups if g["entry"]]
    unmatchable = [g for g in groups if g["unmatchable"]]
    new = [g for g in groups if not g["entry"] and not g["unmatchable"]]
    seen = {g["entry"] for g in accepted}
    not_seen = [{"entry": e["entry"], "ledger": e["ledger"]} for e in entries if e["entry"] not in seen]
    n_new = sum(g["reports"] for g in new)
    n_unmatchable = sum(g["reports"] for g in unmatchable)
    verdict = "FAIL" if (new or unmatchable) else "PASS"
    return {"file": path, "entries": len(entries), "collect": collect, "verdict": verdict,
            "new": new, "unmatchable": unmatchable, "accepted": accepted, "not_seen": not_seen,
            "line": "%s: %d report(s) outside the baseline, %d unmatchable; %d accepted." % (
                verdict, n_new, n_unmatchable, sum(g["reports"] for g in accepted))}


def print_group(g, out, indent="  "):
    out.write("%s%6d report(s) in %d process(es)  %s\n" % (indent, g["reports"], g["processes"], g["kind"]))
    pad = indent + "        "
    out.write("%saccess:   %s\n" % (pad, g["access"]))
    out.write("%sprevious: %s\n" % (pad, g["previous"]))
    out.write("%slocation: %s\n" % (pad, g["location"]))
    if g["tests"]:
        out.write("%stests:    %s\n" % (pad, ", ".join(g["tests"])))
    if g["unmatchable"]:
        out.write("%scannot be matched: %s\n" % (pad, g["unmatchable"]))
    if g["entry"]:
        out.write("%sbaseline: entry %s\n" % (pad, g["entry"]))


def print_thread(r, out):
    groups = r["thread"]["groups"]
    sym = r.get("symbolize")
    if sym is not None:
        if sym["refused"]:
            out.write("\nSymbolization refused: %s. Frames are left as the runtime printed them.\n"
                      % sym["refused"])
        else:
            out.write("\nSymbolized %d frame(s) and checked %d named frame(s) with atos on the binaries under %s.\n"
                      % (sym["named"], sym["checked"], sym["directory"]))
            for module in sym["unverified"]:
                out.write("  Not verified: the reports have no named frame in %s to check the binary against;\n"
                          "  the names are right only if it is the binary that ran.\n" % module)
    if not groups and r.get("baseline") is None:
        return
    out.write("\nThread sanitizer reports by kind and top application frames: %d group(s), %d report(s)\n"
              % (len(groups), sum(g["reports"] for g in groups)))
    for g in groups:
        print_group(g, out)
    b = r.get("baseline")
    if b is None:
        return
    out.write("\nThread baseline: %s (%d entr%s)\n" % (b["file"], b["entries"], "y" if b["entries"] == 1 else "ies"))
    out.write("  Outside the baseline (these fail): %d group(s)\n" % len(b["new"]))
    for g in b["new"]:
        print_group(g, out, "    ")
    out.write("  Unmatchable (these fail): %d group(s)\n" % len(b["unmatchable"]))
    for g in b["unmatchable"]:
        print_group(g, out, "    ")
    if b["unmatchable"]:
        out.write("    A frame the key needs is an address, not a name, so the report cannot be compared\n"
                  "    with the baseline. Rerun with names: run dsymutil on the build's binaries, or pass\n"
                  "    --symbolize with the build directory of the run that wrote these reports.\n")
    out.write("  Accepted by the baseline: %d group(s)\n" % len(b["accepted"]))
    for g in b["accepted"]:
        out.write("    entry %s: %d report(s) in %d process(es)\n" % (g["entry"], g["reports"], g["processes"]))
    out.write("  Baseline entries not seen in this run: %d\n" % len(b["not_seen"]))
    for e in b["not_seen"]:
        out.write("    %s (%s)\n" % (e["entry"], e["ledger"]))
    if b["not_seen"]:
        out.write("    Informational. After a full-suite run this means the entry no longer occurs:\n"
                  "    remove it from the baseline file and the ledger. A targeted run proves nothing about it.\n")
    if b["collect"]:
        out.write("Verdict (--collect, does not fail the run): %s\n" % b["line"])
    else:
        out.write("Verdict: %s\n" % b["line"])


## The nullability baseline
#
# See "The nullability baseline" in the module docstring.

NULLABILITY_BASELINE_COLUMNS = ["kind", "file", "function", "message", "declared", "note"]
NEW_ENTRY_NOTE = "untriaged"
NO_DECLARATION = "-"
# A block invoke function, "__57-[A b:]_block_invoke_2.448": keyed as
# "block in -[A b:]", without the block's index (which a new block earlier in
# the method would change) or the compiler's uniquing suffix.
BLOCK_FUNCTION = re.compile(r"^__\d*(?P<owner>.+?)_block_invoke(?:_\d+)?(?:\.\d+)?$")
# Where an SDK or toolchain path stops depending on the Xcode and SDK version.
STABLE_SDK_MARKERS = ("/usr/include/", "/System/Library/Frameworks/", "/usr/lib/")
RUNS_MARKER = "/tmp/sanitizers/runs/"
ROOT_HINT = "run with the same checkout's script, or pass --root"
NULLABILITY_BASELINE_PREAMBLE = """\
# Nullability sanitizer baseline: the known, not yet triaged report
# locations that a nullability run of tools/swift_migration/sanitizer_tests.sh
# accepts. PROPOSED by the migration on 2026-11-23; judging gate step 7
# against it awaits the owner's confirmation (owner-queue.md Q26). Compared
# after the run by sanitizer_summary.py --nullability-baseline; nothing is
# hidden at run time (the runtime suppressions file is separate and stays
# empty).
#
# Written by sanitizer_summary.py --write-nullability-baseline from the
# reports directory of a whole-suite --collect run, with the script of the
# checkout that made the run (or --root naming it). A refresh keeps every
# entry's note, keeps entries not seen unless --drop-unseen, and prints each
# entry added, kept unseen or removed. The rules (docs/swift-migration/
# nullability.md section 7): the baseline shrinks as violations are fixed by
# guards or annotations; an entry not seen is a candidate for removal,
# removed when its fix is identified or after two whole-suite runs with no
# skips that do not see it; it never grows without an entry in
# docs/swift-migration/nullability-triage.md, and a refresh that adds entries
# is a reviewed change.
#
# Columns, separated by one tab:
#   kind      the check, from the report's SUMMARY line
#   file      the reporting file, relative to the checkout; an SDK or
#             toolchain file from usr/include/, usr/lib/ or
#             System/Library/Frameworks/ on
#   function  the function of the report's first stack frame; a block as
#             "block in <method>"; "@line N" when the frame names none (then
#             a moved line breaks the match)
#   message   the runtime's message, as is. For a nil argument or return it
#             names only the argument number, never the callee
#   declared  the base name of the header in the report's "note: ...
#             specified here" line (NSString.h, iTerm2SharedARC-Swift.h), or
#             - when there is none (a nil return has none)
#   note      untriaged, or where the entry is judged
# A report matches an entry when the first five are equal; the line is not
# compared, so an unrelated edit that moves it keeps the match.
#
# What still shares an entry: two violations in one function with the same
# check and argument number whose declarations are in headers of the same
# base name, for example a nil passed as argument 1 to two different
# NSString.h methods, or to two Swift methods of iTerm2SharedARC-Swift.h,
# from one Objective-C method. The second is accepted by the first's entry.
# Every Swift method of the main target that Objective-C can call is
# declared in the one generated header iTerm2SharedARC-Swift.h, so for Swift
# callees the declared column tells Swift from Objective-C and the SDK, not
# one Swift method from another: once a caller function has an entry for
# argument N declared there, a port that adds a nil passed as argument N
# from that same function to ANY other Swift method is accepted silently.
"""


def read_nullability_baseline(path):
    """The entries of a nullability baseline file, a list of dicts, in file
    order. Raises BaselineError for a malformed file."""
    entries = []
    seen = set()
    header = None
    with open(path, "r", encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.split("\t")
            where = "nullability baseline %s line %d" % (path, lineno)
            if header is None:
                if fields != NULLABILITY_BASELINE_COLUMNS:
                    raise BaselineError("%s: the header must be the columns %s, tab-separated"
                                        % (where, " ".join(NULLABILITY_BASELINE_COLUMNS)))
                header = fields
                continue
            if len(fields) != len(NULLABILITY_BASELINE_COLUMNS):
                raise BaselineError("%s: %d columns, expected %d"
                                    % (where, len(fields), len(NULLABILITY_BASELINE_COLUMNS)))
            row = dict(zip(NULLABILITY_BASELINE_COLUMNS, fields))
            for column in NULLABILITY_BASELINE_COLUMNS:
                if not row[column].strip():
                    raise BaselineError("%s: the %s column is empty" % (where, column))
            key = nullability_entry_key(row)
            if key in seen:
                raise BaselineError("%s: the entry %s appears twice" % (where, " / ".join(key)))
            seen.add(key)
            entries.append(row)
    if header is None:
        raise BaselineError("nullability baseline %s: no header line" % path)
    return entries


def nullability_entry_key(row):
    return tuple(row[c] for c in NULLABILITY_BASELINE_COLUMNS[:5])


def describe_entry(key):
    kind, path, function, _message, declared = key
    return "%s  %s  %s  %s" % (kind, path, function, declared)


def stable_file(summary, path):
    """The file column for a report's path: relative to the root when under
    it; from the first stable marker on for an SDK or toolchain path;
    otherwise the path as given."""
    found = summary.locations.candidates(path)
    if len(found) == 1:
        return found[0]
    if os.path.isabs(path):
        for marker in STABLE_SDK_MARKERS:
            i = path.find(marker)
            if i >= 0:
                return path[i + 1:]
    return path


def nullability_function(function, line):
    if not function or function == "<unknown>" or "+0x" in function or UNNAMED.match(function):
        return "@line %s" % line
    m = BLOCK_FUNCTION.match(function)
    if m:
        return "block in %s" % m.group("owner")
    return function


def nullability_key(summary, kind, loc):
    """The baseline key of the UBSan reports at (kind, loc): kind, file,
    function, message, declaring header."""
    path, _, rest = loc.partition(":")
    line = rest.split(":", 1)[0]
    return (kind, stable_file(summary, path), nullability_function(summary.functions.get((kind, loc)), line),
            summary.samples[(kind, loc)], summary.notes.get((kind, loc)) or NO_DECLARATION)


def infer_root(paths):
    """The checkout the reports under paths ran in, from their run directory
    (<checkout>/tmp/sanitizers/runs/<run>/...), or None. Raises
    BaselineError if they name more than one."""
    roots = set()
    for p in paths:
        p = os.path.abspath(p)
        i = p.find(RUNS_MARKER)
        if i > 0:
            roots.add(p[:i])
    if len(roots) > 1:
        raise BaselineError("the reports come from more than one checkout: %s" % ", ".join(sorted(roots)))
    return roots.pop() if roots else None


def write_nullability_baseline(summary, path, drop_unseen=False, combined=False):
    """Writes the baseline of every complete UBSan report read to path (with
    combined, of every one the combined verdict judges: not the integer
    group's), keeping the notes of entries already in the file and, unless
    drop_unseen, the entries not seen. Returns the lines to print. Raises
    BaselineError, writing nothing, when an entry would name an absolute
    path under the home directory (a checkout other than --root)."""
    old = {}
    if os.path.exists(path):
        old = {nullability_entry_key(e): e["note"] for e in read_nullability_baseline(path)}
    seen = {nullability_key(summary, kind, loc) for kind, loc in summary.ubsan_info
            if judged(summary, kind, loc, combined)}
    home = os.path.expanduser("~").rstrip("/") + "/"
    for k in sorted(seen):
        if os.path.isabs(k[1]) and k[1].startswith(home):
            raise BaselineError("a report is in %s, outside the checkout %s; the baseline would name a path "
                                "that exists only in one checkout. %s" % (k[1], summary.locations.root.rstrip("/"),
                                                                          ROOT_HINT))
    unseen = set(old) - seen
    keys = seen | (set() if drop_unseen else unseen)
    order = lambda k: (k[1], k[2], k[0], k[3], k[4])
    with open(path, "w", encoding="utf-8") as f:
        f.write(NULLABILITY_BASELINE_PREAMBLE)
        f.write("\t".join(NULLABILITY_BASELINE_COLUMNS) + "\n")
        for k in sorted(keys, key=order):
            f.write("\t".join(k + (old.get(k, NEW_ENTRY_NOTE),)) + "\n")
    added = sorted(seen - set(old), key=order)
    lines = ["Wrote %d entries to %s: %d seen and kept, %d not seen and kept, %d added, %d removed." % (
        len(keys), path, len(seen & set(old)), 0 if drop_unseen else len(unseen), len(added),
        len(unseen) if drop_unseen else 0)]
    lines += ["  added: %s" % describe_entry(k) for k in added]
    if drop_unseen:
        lines += ["  removed: %s" % describe_entry(k) for k in sorted(unseen, key=order)]
    else:
        lines += ["  not seen, kept: %s" % describe_entry(k) for k in sorted(unseen, key=order)]
        if unseen:
            lines.append("  Entries not seen are kept; pass --drop-unseen to remove them (nullability.md section 7).")
    if added:
        lines.append("  Each added entry needs a row in docs/swift-migration/nullability-triage.md; a refresh "
                     "that adds entries is a reviewed change.")
    return lines


def judged(summary, kind, loc, combined):
    """Whether --fail-on-reports judges the UBSan reports at (kind, loc):
    every one, except that in a combined run (--combined) the integer
    group's reports are informational findings. A report of neither group
    is judged with the nullability reports (the safe direction)."""
    return not combined or ubsan_family(kind, summary.samples.get((kind, loc))) != "integer"


def fail_on_reports(summary, collect, baseline=None, combined=False):
    """The verdict of --fail-on-reports: every UBSan report fails, except,
    with a nullability baseline, those it accepts, and with combined the
    integer group's reports; an incomplete report or an unparsable report
    file fails too. In the nullability and combined modes the runtime
    suppressions file (empty) is applied before any of this."""
    reports = summary.reports
    entries = {nullability_entry_key(e): e for e in baseline} if baseline is not None else None
    groups = []
    accepted = Counter()
    for (kind, loc), info in summary.ubsan_info.items():
        if not judged(summary, kind, loc, combined):
            continue
        declared = summary.notes.get((kind, loc)) or NO_DECLARATION
        if entries is not None:
            key = nullability_key(summary, kind, loc)
            if key in entries:
                accepted[key] += reports[(kind, loc)]
                continue
        groups.append({"kind": kind, "location": summary.locations.display(loc),
                       "reports": reports[(kind, loc)], "message": summary.samples[(kind, loc)],
                       "function": summary.functions[(kind, loc)], "declared": declared,
                       "swift_header": declared.endswith("-Swift.h"),
                       "unclassified": combined and ubsan_family(kind, summary.samples[(kind, loc)]) is None,
                       "pids": sorted(info["pids"], key=int), "tests": sorted(info["tests"])})
    groups.sort(key=lambda g: (not g["swift_header"], g["location"], g["kind"]))
    not_seen = [] if entries is None else [e for k, e in entries.items() if k not in accepted]
    # A report file with lines that are not a report, or a report cut off
    # before its stack (a hung host killed while writing), may hide a
    # report, and the verdict rests on parsing, so both fail too. In a
    # combined run an incomplete report whose message is the integer
    # group's is an integer finding instead.
    unparsed = [{"file": path, "lines": n} for path, n in sorted(summary.unparsed_report_files.items())]
    incomplete = [{"file": path, "location": summary.locations.display(loc)} for path, loc in summary.incomplete
                  if judged(summary, "undefined-behavior", loc, combined)]
    n = sum(g["reports"] for g in groups)
    verdict = "FAIL" if (groups or unparsed or incomplete) else "PASS"
    what = "nullability report" if combined else "report"
    if entries is None:
        outside = "that no suppression hides"
        accepted_text = ""
        passed = "PASS: no %s outside the suppressions." % what
    else:
        outside = "outside the baseline"
        accepted_text = "; %d report(s) accepted by it" % sum(accepted.values())
        passed = "PASS: no %s outside the baseline%s." % (what, accepted_text)
    if verdict == "PASS":
        line = passed
    else:
        line = "FAIL: %d %s(s) at %d location(s) %s%s" % (n, what, len(groups), outside, accepted_text)
        if incomplete:
            line += "; %d incomplete report(s)" % len(incomplete)
        if unparsed:
            line += "; %d report file(s) with lines that are not a report" % len(unparsed)
        line += "."
    return {"verdict": verdict, "collect": collect, "combined": combined, "groups": groups,
            "unparsed_files": unparsed,
            "incomplete": incomplete, "baseline": entries is not None, "accepted": sum(accepted.values()),
            "not_seen": [{"kind": e["kind"], "file": e["file"], "function": e["function"],
                          "declared": e["declared"], "note": e["note"]} for e in not_seen],
            "line": line}


def print_fail_on_reports(v, out):
    if v["combined"]:
        out.write("\nNullability reports that fail the run (--fail-on-reports --combined; integer reports are "
                  "listed above as findings): %d location(s)\n" % len(v["groups"]))
    else:
        out.write("\nUBSan reports that fail the run (--fail-on-reports): %d location(s)\n" % len(v["groups"]))
    swift = sum(1 for g in v["groups"] if g["swift_header"])
    if swift:
        out.write("  Of these, %d location(s) declared in a generated Swift header (port-relevant).\n" % swift)
    for g in v["groups"]:
        out.write("  %6d  %s  %s\n" % (g["reports"], g["kind"], g["location"]))
        out.write("          %s\n" % g["message"])
        if g["function"] != "<unknown>":
            out.write("          in %s\n" % g["function"])
        if g["swift_header"]:
            out.write("          declared in %s, a generated Swift header: port-relevant\n" % g["declared"])
        elif g["declared"] != NO_DECLARATION:
            out.write("          declared in %s\n" % g["declared"])
        if g.get("unclassified"):
            out.write("          cannot be classified as nullability or integer (kind %s): judged with the\n"
                      "          nullability reports, the safe direction\n" % g["kind"])
        out.write("          tests:    %s\n" % (", ".join(g["tests"]) or "none identified"))
        if g["pids"]:
            out.write("          pids:     %s\n" % ", ".join(g["pids"]))
    if v["groups"]:
        out.write("  A test is named when it is on the report's stack, or when the report file is\n"
                  "  named for it. A report from the test host's launch, or from work a test left\n"
                  "  running on another thread, names none. The runtime reports a location once\n"
                  "  per process, so a later test in the same host that hits it again is not named.\n")
    for r in v["incomplete"]:
        out.write("  incomplete report: %s (at %s; cut off before its stack, so it cannot be compared)\n"
                  % (r["file"], r["location"]))
    if v["baseline"]:
        out.write("  Baseline entries not seen in this run: %d\n" % len(v["not_seen"]))
        for e in v["not_seen"]:
            out.write("    %s  %s  %s  %s  (%s)\n" % (e["kind"], e["file"], e["function"], e["declared"], e["note"]))
        if v["not_seen"]:
            out.write("    Informational. Each is a candidate for removal: remove it when its violation's fix\n"
                      "    is identified, or after two whole-suite runs with no skips that do not see it\n"
                      "    (skipped tests, environment-gated tests and other threads can hide a violation;\n"
                      "    nullability.md section 7).\n")
    for f in v["unparsed_files"]:
        out.write("  not a report: %s (%d line(s)); see Unparsed lines above\n" % (f["file"], f["lines"]))
    if v["collect"]:
        out.write("Verdict (--collect, does not fail the run): %s\n" % v["line"])
    else:
        out.write("Verdict: %s\n" % v["line"])


def count_tests(path):
    """The tests an xcodebuild log executed, by outcome. A test counts once
    however many results it has (a restart after a crash may repeat it); its
    last result wins. A serial-format test that started and has no result
    was running when the test host crashed: "crashed". Parallel logs give a
    crashed test a "failed" result."""
    outcome = {}
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = test_timing.clean(raw.rstrip("\n"))
            m = test_timing.SERIAL_RESULT.match(line) or test_timing.PARALLEL_RESULT.match(line)
            if m:
                outcome[m.group(1)] = m.group(2)
                continue
            m = test_timing.SERIAL_START.match(line)
            if m:
                outcome.setdefault(m.group(1), "crashed")
    counts = Counter(outcome.values())
    return {"log": path, "executed": len(outcome),
            "passed": counts["passed"], "failed": counts["failed"],
            "skipped": counts["skipped"], "crashed": counts["crashed"]}


DEDUP_NOTE = ("Counts are after the runtimes' own deduplication: UBSan reports each source location\n"
              "once per process, and ThreadSanitizer suppresses a report whose stacks equal an\n"
              "earlier one's. A count is the number of processes in which a location fired.\n")


def print_text(r, out):
    tests = r.get("tests")
    if tests is not None:
        out.write("Tests executed: %d (passed %d, failed %d, skipped %d, started with no result %d) in %s\n"
                  % (tests["executed"], tests["passed"], tests["failed"], tests["skipped"],
                     tests["crashed"], tests["log"]))
        if not tests["executed"]:
            out.write("error: the run executed no tests (check the test names); its report count proves nothing\n")
    out.write("Read %d file(s), %d line(s).\n" % (r["files"], r["lines"]))
    out.write("Reports: %d at %d location(s): %d in scope, %d in other code.\n" % (
        r["reports"], r["locations"], r["in_scope"]["reports"], r["other"]["reports"]))
    if r["console_only"] or r["in_both"]:
        out.write("Of these, %d only in the console log and %d in both it and the report files "
                  "(counted once).\n" % (r["console_only"], r["in_both"]))
    out.write(DEDUP_NOTE)
    for title, group in (("In the migration's scope", r["in_scope"]), ("Other code", r["other"])):
        out.write("\n%s: %d report(s) at %d location(s)\n" % (title, group["reports"], group["locations"]))
        if group["by_kind"]:
            out.write("  By kind:\n")
            for row in group["by_kind"]:
                out.write("    %6d  %s\n" % (row["count"], row["kind"]))
            out.write("  Top locations:\n")
            for row in group["top"]:
                out.write("    %6d  %s  %s\n      %s\n" % (row["count"], row["kind"], row["location"], row["message"]))
                if row["function"] != "<unknown>":
                    out.write("      in %s\n" % row["function"])
            if group["not_shown"]:
                out.write("  ... %d more location(s) not shown; run sanitizer_summary.py again with --top %d,\n"
                          "  or with --json for every location\n" % (group["not_shown"], group["locations"]))
    address = r["address"]
    if address["reports"] or r.get("combined"):
        out.write("\nAddress sanitizer reports: %d at %d location(s)\n" % (address["reports"], address["locations"]))
        for g in address["groups"]:
            out.write("  %6d  %s  %s\n" % (g["count"], g["kind"], g["location"]))
            out.write("          tests:    %s\n" % (", ".join(g["tests"]) or "none identified"))
            if g["pids"]:
                out.write("          pids:     %s\n" % ", ".join(g["pids"]))
        if address["reports"]:
            out.write("  The address sanitizer ends the process at its first report, as in the plain suite, so\n"
                      "  the test that was running fails: these are judged by the tests' result, not here.\n")
    integer = r.get("integer")
    if integer is not None:
        out.write("\nInteger findings (informational: they never fail the run; integer-findings.md):\n")
        for row in integer["by_kind"]:
            out.write("    %6d  %s\n" % (row["count"], row["kind"]))
        for row in integer["top"]:
            out.write("    %6d  %s  %s\n      %s\n" % (row["count"], row["kind"], row["location"], row["message"]))
        if integer["not_shown"]:
            out.write("  ... %d more location(s) not shown (--top, or --json)\n" % integer["not_shown"])
        out.write("Integer verdict (informational, never fails the run): %d report(s) at %d location(s), "
                  "%d in the migration's scope.\n" % (integer["reports"], integer["locations"], integer["in_scope"]))
    if r["other_text"]:
        out.write("\nOther text (not sanitizer output, --mixed): %d line(s)\n" % r["other_text"])
    out.write("\nUnparsed lines: %d\n" % r["unparsed"])
    for row in r["unparsed_shown"]:
        out.write("  %s:%d: %s\n" % (row["file"], row["line"], row["text"]))
    if r["unparsed"] > len(r["unparsed_shown"]):
        out.write("  ... and %d more\n" % (r["unparsed"] - len(r["unparsed_shown"])))


def input_files(paths):
    for path in paths:
        if os.path.isdir(path):
            for dirpath, dirnames, filenames in os.walk(path):
                dirnames.sort()
                for name in sorted(filenames):
                    full = os.path.join(dirpath, name)
                    if os.path.isfile(full):
                        yield full
        else:
            yield path


def main(argv=None):
    parser = argparse.ArgumentParser(description="Summarize UBSan and TSan reports.")
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--console", action="append", default=[])
    parser.add_argument("--test-log")
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--root")
    parser.add_argument("--mixed", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--baseline")
    parser.add_argument("--fail-on-reports", action="store_true")
    parser.add_argument("--nullability-baseline")
    parser.add_argument("--write-nullability-baseline")
    parser.add_argument("--drop-unseen", action="store_true")
    parser.add_argument("--collect", action="store_true")
    parser.add_argument("--combined", action="store_true")
    parser.add_argument("--symbolize")
    parser.add_argument("--atos", default="atos")
    args = parser.parse_args(argv)
    if not args.paths and not args.console:
        parser.error("give at least one PATH or --console LOG")
    if args.combined and not (args.fail_on_reports or args.write_nullability_baseline):
        parser.error("--combined applies to --fail-on-reports and --write-nullability-baseline")
    if args.collect and not (args.baseline or args.fail_on_reports):
        parser.error("--collect applies to --baseline and --fail-on-reports")
    if args.nullability_baseline and not args.fail_on_reports:
        parser.error("--nullability-baseline applies to --fail-on-reports")
    if args.drop_unseen and not args.write_nullability_baseline:
        parser.error("--drop-unseen applies to --write-nullability-baseline")
    # The checkout the reports ran in, from their run directory, decides the
    # root; a --root that disagrees is refused (a baseline written against
    # the wrong root would name paths of one checkout only).
    try:
        ran_in = infer_root(args.paths)
    except BaselineError as e:
        sys.stderr.write("sanitizer_summary.py: %s; %s\n" % (e, ROOT_HINT))
        return 2
    if ran_in and args.root and os.path.realpath(args.root) != os.path.realpath(ran_in):
        sys.stderr.write("sanitizer_summary.py: the reports ran in the checkout %s, not --root %s; %s\n"
                         % (ran_in, args.root, ROOT_HINT))
        return 2
    root = args.root or ran_in or default_root()
    summary = Summary(os.path.abspath(root), args.mixed)
    inputs = [(p, False) for p in input_files(args.paths)] + [(p, True) for p in args.console]
    try:
        entries = read_baseline(args.baseline) if args.baseline else None
        null_entries = read_nullability_baseline(args.nullability_baseline) if args.nullability_baseline else None
        for path, console in inputs:
            summary.read(path, console=console)
        tests = count_tests(args.test_log) if args.test_log else None
    except BaselineError as e:
        sys.stderr.write("sanitizer_summary.py: %s\n" % e)
        return 2
    except OSError as e:
        sys.stderr.write("sanitizer_summary.py: cannot read %s: %s\n" % (e.filename, e))
        return 2
    result = summary.result(args.top)
    result["tests"] = tests
    if args.combined:
        result["combined"] = True
        result["integer"] = summary.integer_result(args.top)
    if args.symbolize:
        all_reports = summary.thread.reports[False] + summary.thread.reports[True]
        result["symbolize"] = symbolize(all_reports, args.symbolize, args.atos)
    groups = thread_groups(summary.thread, entries)
    result["thread"] = {"groups": groups}
    if entries is not None:
        result["baseline"] = compare_baseline(groups, entries, args.baseline, args.collect)
    if args.write_nullability_baseline:
        try:
            for line in write_nullability_baseline(summary, args.write_nullability_baseline, args.drop_unseen,
                                                   args.combined):
                print(line)
        except BaselineError as e:
            sys.stderr.write("sanitizer_summary.py: %s\n" % e)
            return 2
        if summary.incomplete:
            print("warning: skipped %d incomplete report(s), cut off before their stack; not written into "
                  "the baseline:" % len(summary.incomplete))
            for path, loc in summary.incomplete:
                print("  %s (at %s)" % (path, summary.locations.display(loc)))
        if summary.unparsed_report_files:
            print("warning: %d report file(s) have lines that are not a report; a report may be missing "
                  "from the baseline: %s" % (len(summary.unparsed_report_files),
                                             ", ".join(sorted(summary.unparsed_report_files))))
        return 0
    if args.fail_on_reports:
        result["fail_on_reports"] = fail_on_reports(summary, args.collect, null_entries, args.combined)
    if args.json:
        json.dump(result, sys.stdout, indent=1)
        sys.stdout.write("\n")
    else:
        print_text(result, sys.stdout)
        print_thread(result, sys.stdout)
        if args.fail_on_reports:
            print_fail_on_reports(result["fail_on_reports"], sys.stdout)
    if tests is not None and not tests["executed"]:
        return 3
    if entries is not None and result["baseline"]["verdict"] != "PASS" and not args.collect:
        return 1
    if args.fail_on_reports and result["fail_on_reports"]["verdict"] != "PASS" and not args.collect:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
