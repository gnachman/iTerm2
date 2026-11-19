#!/usr/bin/env python3
"""Coverage reports for the Objective-C to Swift migration.

Reads the profile of a run of tools/swift_migration/coverage_tests.sh (or any
profile and instrumented binaries given explicitly) with LLVM's own tools,
`xcrun llvm-cov` and `xcrun llvm-profdata`, and answers the question of
docs/swift-migration/large-code.md section 2.1: was every case label and
every branch of a function executed?

Usage:
  coverage_report.py function SPEC [--file PATH] [options]
      SPEC is one of:
        -[Class sel:] or +[Class sel:]   An Objective-C method. A category
                                         method may be named with its
                                         category, -[Class(Cat) sel:], or
                                         without it when the class itself
                                         does not define the selector.
        name                             A C function (or a C++ function by
                                         its mangled name).
        PATH:LINE                        The function whose body contains
                                         LINE of PATH: works for every
                                         language, Swift included.
        Swift.name(label:)               A Swift function by a part of its
                                         demangled name; needs --file.
      Prints the function's execution count, every line of its body with its
      count (uncovered lines marked <<<), every case label (including a
      switch's implicit default) with the number of times it was taken, every
      other branch (if, else, ?:, && and || operands, loop conditions) with
      its true and false counts, every code region that never ran (a block,
      lambda or closure never invoked is named as such), what could not be
      checked ("Not determinable"), a summary line and a verdict line.
      Blocks, lambdas and closures inside the function are part of it.
  coverage_report.py file PATH [options]
      The same summary for every function of a file, sorted by the number of
      unexercised branch outcomes and case labels, most first.
  coverage_report.py tests-for SPEC-or-PATH [options]
      Which test classes executed the function or file, and which branches
      each exercised. Needs per-class profiles: a run of
      coverage_tests.sh --per-class CLASS... or --observer. The run records
      which (per_class_route.txt). On a --per-class run (one process per
      class) the statements are exact. On an observer run, or one that does
      not record its route, per-class attribution is approximate (work a
      class leaves running is counted for the class that follows, and work
      the app's launch leaves running for whichever class is running when it
      happens): classes
      are listed as "may execute", the result says so, and the exit status
      is 3. The app's launch (_launch) is shown apart, not as a class.
  coverage_report.py scope [DIR ...] [--top N] [options]
      Line, region and branch coverage of the migration's scope directories
      (or the directories given) from `llvm-cov report`, and the N (20)
      functions with the most unexercised branch outcomes as llvm-cov counts
      them.
  coverage_report.py log-executed LOG | log-status LOG
      Helpers for coverage_tests.sh: the number of tests an xcodebuild log
      executed (exit 1 when none), or 0 or 1 for whether every test passed.

Options:
  --run DIR          A run directory of coverage_tests.sh (default
                     tmp/coverage/runs/latest). Gives the profile, the
                     instrumented binaries and the source digests.
  --profdata FILE    A merged profile, instead of the run's.
  --binary FILE      An instrumented binary; repeat for several. Instead of
                     the run's list.
  --codedb FILE      The code database used to resolve Objective-C methods to
                     their file (default tmp/codedb/codedb.sqlite when it
                     exists); --no-codedb to resolve from the profile alone.
  --json             JSON output.
  --max-lines N      text output of `function`: print at most N body lines
                     (default all).
  --ignore-macro M   Set aside the branches and regions inside expansions of
  --set-aside-macro M
                     macro M (at any depth): they are listed, grouped by
                     macro with a count per macro and each branch's location
                     and outcome counts (the first 10 of each macro in text
                     output unless --verbose; all in JSON), but not counted
                     in the summary or the verdict, whose line says how many
                     were set aside. Repeat for several. DLog
                     and DLogCyclic are always set aside (their
                     if (gDebugLogging) is never true with debug logging
                     off; ILog and ELog expand to DLog) unless
                     --no-default-ignores is given. In Swift the same names
                     are functions: the @autoclosure argument of a call to
                     one (an implicit closure lying wholly inside the call's
                     parentheses), the closures inside it and the constructs
                     inside it are set aside the same way. Assertion macros
                     are not set aside: an assertion's failure branch that
                     never ran goes in the dossier with its reason
                     (large-code.md 2.1).
  --verbose          List every set-aside branch.
  --accept-uncheckable
                     Accept constructs the coverage data cannot check: when
                     nothing else is missing, exit 0 with the verdict "every
                     checkable case label and branch was exercised; N
                     constructs could not be checked", listing them.

What counts: a case label is exercised when control was dispatched to it at
least once; a branch outcome (true or false) when it happened at least once.
Outcomes the compiler folded (the false side of while (1), the operand 0 of
x || 0) cannot happen and are not counted, as llvm-cov does not count them.
"Branches covered/total" counts outcomes of conditions other than case
labels; case labels are counted separately. Every code region must have
run; those that did not are listed. A function that never ran is not
exercised whatever its shape.

What the data cannot show, listed under "Not determinable" with file and
line (and making the answer incomplete, exit 3, unless --accept-uncheckable
is given and nothing else is missing):
  - Objective-C @catch bodies: clang gives @try/@catch/@finally one region,
    so a @catch body that never ran shows its enclosing count; branch false
    outcomes inside @try and @catch bodies, computed by subtraction from
    that region, are not determinable either. (C++ catch bodies have their
    own regions and are checked.)
  - A C++ lambda that was never called has no coverage record at all; a
    lambda found in the function's text with no record is listed.
  - A switch with no default label whose condition is a && or ||
    expression: clang records no branch for its implicit default.
  - Swift: its coverage data has no branch regions. For an if, guard,
    while or repeat condition the outcomes are derived from region counts
    where the counts needed exist and agree, and reported as "derived from
    region counts": an if's true count is its body's; its false count is
    its else body's, or the count of the if that follows its else, or the
    times it was reached less its true count (see Instance._swift_if_chain:
    Swift gives no region to an else that leads to else if let, else if
    var or else if case, so the counts are carried along the chain, never
    taken from an enclosing region); a guard passed as many times as the
    region after it ran, and (with no try in its condition) as it was
    reached less its failures, the two agreeing where both exist; a
    while's false count is its condition count less its body count. A
    condition with a try can throw, which is neither
    outcome, so a count found by subtraction is not used for it. What
    cannot be derived is listed as not determinable. So are the operands of
    &&, || and ??, optional chains, try?, where clauses (case, for-in,
    catch), for case patterns, case labels with several patterns, and
    which clause of a multi-clause if, guard or while failed. Code inside
    string interpolations is scanned as code. A repeat whose body can
    throw is not determinable: the region at its condition counts the
    iteration that threw. Counts assume that a call to a Never-returning
    function ends the process (pthread_exit does not, and makes the count
    of a later if, guard or repeat too high). A Swift function never gets
    the full verdict; every Swift report states this limit.
  - Text that clang marks skipped (an inactive #if block) is not scanned
    as code.

Exit status: 0 when every function reported had every case label and every
branch exercised (or every checkable one, with --accept-uncheckable); 1 when
not; 2 on an error (including a profile that this
toolchain's llvm-cov cannot read: profiles must be read by the llvm-cov of
the toolchain that built the binaries); 3 when the answer is incomplete: the
function was not found, its source changed since the coverage build, a
binary changed since the run, a header that gives the function lines or
macro definitions changed (it is named), something could not be checked
(above), per-class attribution is approximate (tests-for on an observer
run), the run's tests did not all pass or the run did not finish (its
status.txt is anything but 0), or the
function has several instances (several binaries, or a header
function compiled into several translation units) whose counts differ: each
instance is reported, and their union.

Large data is streamed: llvm-cov export lists every function of a binary
(about 140,000 for the app, 56 MB of JSON) whatever filter is given, so its
output is read one function object at a time and only the matching ones are
kept.
"""

import argparse
import bisect
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

DEFAULT_RUN = os.path.join(ROOT, "tmp", "coverage", "runs", "latest")
DEFAULT_CODEDB = os.path.join(ROOT, "tmp", "codedb", "codedb.sqlite")
# The migration's scope, as tools/swift_migration/codedb/codedb.py's
# MIGRATION_SCOPE_DIRS (docs/swift-migration/README.md section 2).
SCOPE_DIRS = ("sources/", "ThirdParty/PSMTabBarControl/", "SignedArchive/", "pidinfo/",
              "iTerm2SandboxedWorker/", "ShellLauncher/", "ColorPicker/", "SearchableComboListView/",
              "BetterFontPicker/")

FULL_VERDICT = "every case label and every branch was exercised"
# Printed instead when some construct cannot be checked from the data (and
# always for Swift); never with exit status 0 unless --accept-uncheckable.
CHECKABLE_VERDICT = "every checkable case label and branch was exercised"
# Macros whose own branches are set aside: DLog's if (gDebugLogging) is never
# true in a test run with debug logging off. ILog and ELog expand to DLog
# and are covered through it.
DEFAULT_IGNORED_MACROS = ("DLog", "DLogCyclic")
IDENTIFIER = re.compile(r"[A-Za-z_]\w*")
VERDICT_LIST_LIMIT = 30

# llvm-cov region kinds.
CODE, EXPANSION, SKIPPED, GAP, BRANCH = 0, 1, 2, 3, 4

TOOLCHAIN_HINT = ("profiles must be read by the llvm-cov and llvm-profdata of the same toolchain that built "
                  "the binaries (xcrun uses the selected Xcode); rebuild with coverage_tests.sh after an "
                  "Xcode update")


class ToolError(Exception):
    pass


# ---------------------------------------------------------------------------
# Streaming llvm-cov export


def stream_export(fp, on_file, on_function, chunk=1 << 20):
    """Reads llvm-cov export's JSON from the text stream fp and calls on_file
    with each object of data[0].files and on_function with each object of
    data[0].functions, one at a time, without holding the document."""
    dec = json.JSONDecoder()
    state = {"buf": "", "pos": 0, "chunk": chunk}

    def fill():
        data = fp.read(state["chunk"])
        if not data:
            return False
        state["buf"] = state["buf"][state["pos"]:] + data
        state["pos"] = 0
        return True

    def find(token):
        while True:
            i = state["buf"].find(token, state["pos"])
            if i >= 0:
                state["pos"] = i + len(token)
                return True
            state["pos"] = max(state["pos"], len(state["buf"]) - len(token))
            if not fill():
                return False

    def array(callback):
        while True:
            buf, pos = state["buf"], state["pos"]
            while pos < len(buf) and buf[pos] in " \t\r\n,":
                pos += 1
            state["pos"] = pos
            if pos >= len(buf):
                if not fill():
                    raise ToolError("llvm-cov export output ended early")
                continue
            if buf[pos] == "]":
                state["pos"] = pos + 1
                return
            while True:
                try:
                    obj, end = dec.raw_decode(state["buf"], state["pos"])
                    break
                except json.JSONDecodeError:
                    if not fill():
                        raise ToolError("llvm-cov export output ended inside an object")
                    state["chunk"] = min(state["chunk"] * 2, 64 << 20)
            state["pos"] = end
            state["chunk"] = chunk
            callback(obj)

    if not find('"files":['):
        raise ToolError("llvm-cov export output has no files array")
    array(on_file)
    if not find('"functions":['):
        return
    array(on_function)


def run_export(binary, profdata, sources, on_file, on_function, skip_functions=False):
    """Runs llvm-cov export on one binary. sources: a list of source paths to
    restrict the files array to, or None for no files at all. Functions are
    all listed, whatever the sources, unless skip_functions. A source the
    binary does not have restricts nothing: every file is listed."""
    cmd = ["xcrun", "llvm-cov", "export", binary, "-instr-profile=" + profdata, "-skip-expansions"]
    if skip_functions:
        cmd.append("-skip-functions")
    if sources is None:
        cmd.append("-ignore-filename-regex=.*")
    else:
        cmd += ["--"] + list(sources)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            encoding="utf-8", errors="replace")
    try:
        stream_export(proc.stdout, on_file, on_function)
    except ToolError:
        proc.kill()
        proc.wait()
        err = proc.stderr.read()
        raise ToolError(describe_llvm_error(err, binary, profdata))
    proc.stdout.read()
    err = proc.stderr.read()
    if proc.wait() != 0:
        raise ToolError(describe_llvm_error(err, binary, profdata))


def describe_llvm_error(err, binary, profdata):
    err = err.strip()
    return "llvm-cov failed on %s with %s: %s; %s" % (binary, profdata, err or "no message", TOOLCHAIN_HINT)


# ---------------------------------------------------------------------------
# Folded branch outcomes, from llvm-cov show (export does not say)

# "Branch (55:12): [True: 5, Folded]", "Branch (61:17): [Folded, False: 0]",
# "Branch (11:9): [True: 1, False: 0]".
SHOW_BRANCH = re.compile(r"Branch \((\d+):(\d+)\): \[([^\]]*)\]")


def show_outcome(text):
    text = text.strip()
    return "Folded" if text == "Folded" else text.split(":", 1)[-1].strip()


SHOW_SOURCE = re.compile(r"^\s*(\d+)\|[^|]*\|(.*)$")


def folded_branches(binary, profdata, source):
    """{(line, column): [(true_text, false_text, view), ...]} for every
    branch that llvm-cov show prints for the file, streamed. A text is a
    count or 'Folded'. view is None for a branch of the file itself and
    (line, text) of the first source line of the expansion view for one
    inside a macro expansion, whose coordinates are those of the file that
    defines the macro: llvm-cov show does not name that file, so a lookup
    compares the view's text with the file's line (fold_flags)."""
    cmd = ["xcrun", "llvm-cov", "show", binary, "-instr-profile=" + profdata, "-show-branches=count",
           "-show-expansions", "-use-color=false", "--", source]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            encoding="utf-8", errors="replace")
    result = {}
    # Views nest with "|" prefixes: the file's own source lines have none and
    # its branches one; an expansion's source lines have 2 and its branches
    # 3; one nested in it, 4 and 5. A branch belongs to the view whose
    # source lines have one bar fewer; the latest such line identifies it.
    views = {}
    for line in proc.stdout:
        lead = re.match(r"[ |]*", line).group(0)
        bars = lead.count("|")
        rest = line[len(lead):]
        if not rest.startswith("Branch ("):
            m = SHOW_SOURCE.match(rest)
            if m:
                views[bars] = (int(m.group(1)), m.group(2).rstrip("\n"))
            continue
        m = SHOW_BRANCH.search(rest)
        if m:
            parts = m.group(3).split(",")
            if len(parts) != 2:
                continue
            view = None if bars <= 1 else views.get(bars - 1)
            result.setdefault((int(m.group(1)), int(m.group(2))), []).append(
                (show_outcome(parts[0]), show_outcome(parts[1]), view))
    err = proc.stderr.read()
    if proc.wait() != 0:
        raise ToolError(describe_llvm_error(err, binary, profdata))
    return result


def llvm_format_count(n):
    """llvm-cov show's abbreviation of a count (formatCount)."""
    if n < 1000:
        return str(n)
    for unit, scale in (("E", 10 ** 18), ("P", 10 ** 15), ("T", 10 ** 12), ("G", 10 ** 9), ("M", 10 ** 6),
                        ("k", 10 ** 3)):
        if n >= scale:
            return "%.*f%s" % (2 if n < 10 * scale else 1 if n < 100 * scale else 0, n / scale, unit)
    return str(n)


def fold_flags(folds, path, file_id, line, col, true_count, false_count, sources):
    """(true folded, false folded) for the branch at line:col of path
    (file_id 0 is the function's own file, others macro definitions). A
    candidate from a macro expansion view matches only a branch of a macro
    whose file has the view's text at the view's line, so that a branch in
    a header's macro never takes the flags of a branch of the main file at
    the same coordinates, or the reverse."""
    cands = []
    for t, f, view in folds.get((line, col), []):
        if file_id == 0:
            if view is None:
                cands.append((t, f))
        elif view is not None and sources.line(path, view[0]).rstrip() == view[1].rstrip():
            cands.append((t, f))
    if not cands:
        return False, False
    pairs = {(t == "Folded", f == "Folded") for t, f in cands}
    if len(pairs) == 1:
        return pairs.pop()
    want_t, want_f = llvm_format_count(true_count), llvm_format_count(false_count)
    for t, f in cands:
        if t in (want_t, "Folded") and f in (want_f, "Folded"):
            return t == "Folded", f == "Folded"
    return cands[0][0] == "Folded", cands[0][1] == "Folded"


# ---------------------------------------------------------------------------
# Names

LOCAL_PREFIX = re.compile(r"^(.*\.(?:c|cc|cpp|cxx|m|mm|swift|h|hpp)):(.+)$")
OBJC_SPEC = re.compile(r"^([-+])\[([A-Za-z_]\w*)(?:\(([A-Za-z_]\w*)?\))? ([^\]\s]+)\]$")
FILE_LINE_SPEC = re.compile(r"^(.+):(\d+)$")


def base_name(name):
    """A function's name without the file prefix LLVM gives local symbols."""
    m = LOCAL_PREFIX.match(name)
    return m.group(2) if m else name


def category_pattern(sign, cls, sel):
    return re.compile(r"^" + re.escape(sign) + r"\[" + re.escape(cls) + r"(?:\([A-Za-z_]\w*\))? "
                      + re.escape(sel) + r"\]$")


def body_range(record):
    """(start_line, start_col, end_line, end_col) of the code regions of the
    function's own file."""
    regs = [r for r in record["regions"] if r[5] == 0 and r[7] in (CODE, GAP, EXPANSION)]
    if not regs:
        regs = [r for r in record["regions"] if r[5] == 0] or record["regions"]
    start = min((r[0], r[1]) for r in regs)
    end = max((r[2], r[3]) for r in regs)
    return start[0], start[1], end[0], end[1]


def same_path(a, b):
    return os.path.realpath(a) == os.path.realpath(b)


# ---------------------------------------------------------------------------
# Sources

class Sources:
    def __init__(self):
        self.cache = {}

    def lines(self, path):
        if path not in self.cache:
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    self.cache[path] = f.read().split("\n")
            except OSError:
                self.cache[path] = None
        return self.cache[path]

    def line(self, path, n):
        lines = self.lines(path)
        if lines is None or n < 1 or n > len(lines):
            return ""
        return lines[n - 1]

    def text(self, path, ls, cs, le, ce):
        line = self.line(path, ls)
        if ls == le and cs == ce:
            # No width: code inside a macro from a system header, which gets
            # no expansion region; clang puts it at the macro's name.
            m = IDENTIFIER.match(line[cs - 1:])
            return m.group(0) + "(...)" if m else ""
        if ls == le:
            return line[cs - 1:ce - 1]
        return line[cs - 1:].rstrip() + " ..."


    def code(self, path):
        """(flat text, line start offsets) of path with the contents of
        comments and string and character literals replaced by spaces, so
        that a textual scan for keywords and operators sees only code.
        Newlines are kept, so offsets map back to lines and columns."""
        key = ("code", path)
        if key not in self.cache:
            lines = self.lines(path)
            text = blank_code("\n".join(lines) if lines is not None else "", path.endswith(".swift"))
            starts = [0]
            for i, ch in enumerate(text):
                if ch == "\n":
                    starts.append(i + 1)
            self.cache[key] = (text, starts)
        return self.cache[key]


SWIFT_STRING_START = re.compile(r'#*"')
SWIFT_REGEX_START = re.compile(r"#+/")


def blank_code(text, swift):
    """text with comment and literal contents blanked (see Sources.code).

    Swift: the code of a string interpolation is code and is kept, at its
    own offsets: \\( ... ) in a string, \\#( ... ) in a raw string with one
    #, \\##( ... ) with two, and so on, with nested parentheses, comments,
    strings and interpolations inside it. Only the backslash and the #s of
    the interpolation are blanked; its parentheses are kept, so brackets
    stay balanced. In a raw string \\( is text. An extended regex literal
    #/ ... /# is blanked whole (it holds no code). A bare /regex/ literal is
    not recognized: the project does not enable bare slash regex literals.
    C and Objective-C: string and character literals and comments; they
    hold no code."""
    out = list(text)
    n = len(text)

    def blank(a, b):
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    def comment(i):
        """Blanks the comment at i; returns the offset after it, or None
        when there is none at i."""
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            return j
        if text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if swift and text.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif text.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            blank(i, j)
            return j
        return None

    def swift_code(i, in_interpolation):
        """Scans Swift code from i. In an interpolation, returns the offset
        of the ) that ends it; otherwise the end of the text."""
        depth = 0
        while i < n:
            j = comment(i)
            if j is not None:
                i = j
                continue
            c = text[i]
            if c == '"' or (c == "#" and SWIFT_STRING_START.match(text, i)):
                i = swift_string(i)
            elif c == "#" and SWIFT_REGEX_START.match(text, i):
                hashes = SWIFT_REGEX_START.match(text, i).end() - i - 1
                close = "/" + "#" * hashes
                j = text.find(close, i + hashes + 1)
                j = n if j < 0 else j
                blank(i + hashes + 1, j)
                i = j + len(close)
            elif in_interpolation and c == "(":
                depth += 1
                i += 1
            elif in_interpolation and c == ")":
                if depth == 0:
                    return i
                depth -= 1
                i += 1
            else:
                i += 1
        return n

    def swift_string(i):
        """Blanks the text of the string literal at i, keeping the code of
        its interpolations; returns the offset after the literal."""
        hashes = SWIFT_STRING_START.match(text, i).end() - i - 1
        q = i + hashes
        triple = text.startswith('"""', q)
        close = ('"""' if triple else '"') + "#" * hashes
        escape = "\\" + "#" * hashes
        j = q + (3 if triple else 1)
        start = j
        while j < n:
            if text.startswith(close, j):
                blank(start, j)
                return j + len(close)
            if text.startswith(escape, j):
                k = j + len(escape)
                if k < n and text[k] == "(":
                    blank(start, k)
                    end = swift_code(k + 1, True)
                    j = start = min(n, end + 1)
                    continue
                j = k + 1
                continue
            if text[j] == "\n" and not triple:
                break
            j += 1
        blank(start, j)
        return j

    if swift:
        swift_code(0, False)
        return "".join(out)
    i = 0
    while i < n:
        j = comment(i)
        if j is not None:
            i = j
            continue
        c = text[i]
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            blank(i + 1, j)
            i = j + 1
        else:
            i += 1
    return "".join(out)


CASE_TEXT = re.compile(r"^(case\b|default\b)")


# ---------------------------------------------------------------------------
# Textual scans of a function's code, for what coverage data cannot show

def offset_of(starts, line, col):
    return starts[line - 1] + col - 1 if 0 < line <= len(starts) else 0


def position_of(starts, off):
    line = bisect.bisect_right(starts, off)
    return line, off - starts[line - 1] + 1


def matching_close(text, open_off, limit=None):
    """Offset of the bracket that closes the one at open_off, counting (),
    [] and {} together; limit (exclusive) when unbalanced."""
    limit = len(text) if limit is None else limit
    depth = 0
    for k in range(open_off, limit):
        ch = text[k]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return k
    return limit


def next_at_depth0(text, start, limit, chars):
    """Offset of the first of chars at bracket depth 0 from start, or None."""
    depth = 0
    for k in range(start, limit):
        ch = text[k]
        if depth == 0 and ch in chars:
            return k
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth < 0:
                return None
    return None


def word_at_depth0(text, start, limit, word):
    depth = 0
    pat = re.compile(r"\b%s\b" % word)
    k = start
    while k < limit:
        ch = text[k]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth < 0:
                return None
        elif depth == 0 and pat.match(text, k) and (k == 0 or not (text[k - 1].isalnum() or text[k - 1] == "_")):
            return k
        k += 1
    return None


def top_level_commas(text, start, end):
    depth, n = 0, 0
    for k in range(start, end):
        ch = text[k]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            n += 1
    return n


def top_level_logical(expr):
    """Whether expr has a && or || outside any brackets."""
    depth = 0
    for k, ch in enumerate(expr):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and expr[k:k + 2] in ("&&", "||"):
            return True
    return False


def skip_space(text, k, limit=None):
    limit = len(text) if limit is None else limit
    while k < limit and text[k] in " \t\r\n":
        k += 1
    return k


# A C++ capture list item: =, &, this, *this, name, &name, name = expr,
# name... (a message send such as [obj msg] has two words and no comma).
CAPTURE_ITEM = re.compile(r"^\s*(?:=|&|this|\*this|&?\s*[A-Za-z_]\w*(?:\s*\.\.\.)?(?:\s*=\s*.+)?)\s*$")
LAMBDA_TAIL = re.compile(r"\s*(?:\((?P<params>[^()]*(?:\([^()]*\)[^()]*)*)\))?"
                         r"(?:\s*(?:mutable|constexpr|noexcept|->\s*[\w:<>,*&\s]+?))*\s*\{")


def find_lambdas(text, starts, start_off, end_off):
    """[(line, col of the lambda's {)] for the C++ lambda expressions in
    text[start_off:end_off]: a conservative textual detection of [captures]
    (params) specifiers { and [captures] {."""
    out = []
    for m in re.finditer(r"\[", text[start_off:end_off]):
        k = start_off + m.start()
        prev = text[:k].rstrip()[-1:] if k > start_off else ""
        if prev and (prev.isalnum() or prev in "_)]"):
            continue  # a subscript
        close = matching_close(text, k, end_off)
        if close >= end_off:
            continue
        inner = text[k + 1:close]
        if inner.strip() and not all(CAPTURE_ITEM.match(p) for p in inner.split(",")):
            continue
        t = LAMBDA_TAIL.match(text, close + 1, end_off)
        if not t:
            continue
        out.append(position_of(starts, t.end() - 1))
    return out


def find_objc_try(text, starts, start_off, end_off):
    """{"catches": [(line, col, end_line, end_col) of each @catch body],
    "zones": [(start, end) offset ranges of @try and @catch bodies]}."""
    catches, zones = [], []
    for m in re.finditer(r"@try\b", text[start_off:end_off]):
        k = next_at_depth0(text, start_off + m.end(), end_off, "{")
        if k is None:
            continue
        close = matching_close(text, k, end_off)
        zones.append((k, close))
        j = skip_space(text, close + 1, end_off)
        while text.startswith("@catch", j):
            ob = next_at_depth0(text, j + 6, end_off, "{")
            if ob is None:
                break
            cb = matching_close(text, ob, end_off)
            zones.append((ob, cb))
            catches.append(position_of(starts, j) + position_of(starts, cb))
            j = skip_space(text, cb + 1, end_off)
    return {"catches": catches, "zones": zones}


SWIFT_TOKENS = re.compile(r"(?<![\w#@])(if|guard|while|repeat|for|switch|catch)\b|(?<!\w)try\?|&&|\|\||\?\?"
                          r"|(?<=[\w)\]!])\?(?=[.\[])")
# A try that can throw out of a condition: not try? (gives nil) or try!
# (traps, which ends the process and its profile).
SWIFT_TRY = re.compile(r"(?<![\w#@])try\b(?![?!])")


def swift_constructs(text, starts, start_off, end_off):
    """The conditions in text[start_off:end_off] of Swift code, as dicts
    with "kind" and offsets of their parts; see Instance._swift."""
    out = []
    repeat_whiles = set()
    for m in SWIFT_TOKENS.finditer(text, start_off, end_off):
        tok = m.group(0)
        k = m.start()
        if tok in ("&&", "||", "??", "try?", "?"):
            out.append({"kind": {"?": "?."}.get(tok, tok), "at": k})
            continue
        if tok == "repeat":
            ob = next_at_depth0(text, m.end(), end_off, "{")
            if ob is None:
                continue
            cb = matching_close(text, ob, end_off)
            w = skip_space(text, cb + 1, end_off)
            if not text.startswith("while", w):
                continue
            repeat_whiles.add(w)
            cond = skip_space(text, w + 5, end_off)
            out.append({"kind": "repeat", "at": k, "body": ob, "body_end": cb, "cond": cond})
            continue
        if tok == "while" and k in repeat_whiles:
            continue
        cond = skip_space(text, m.end(), end_off)
        if tok == "guard":
            e = word_at_depth0(text, cond, end_off, "else")
            ob = None if e is None else next_at_depth0(text, e + 4, end_off, "{")
            if ob is None:
                continue
            out.append({"kind": "guard", "at": k, "cond": cond, "cond_end": e, "body": ob,
                        "body_end": matching_close(text, ob, end_off),
                        "clauses": top_level_commas(text, cond, e) + 1,
                        "has_try": SWIFT_TRY.search(text, cond, e) is not None})
            continue
        ob = next_at_depth0(text, cond, end_off, "{")
        if ob is None:
            continue
        item = {"kind": tok, "at": k, "cond": cond, "cond_end": ob, "body": ob,
                "clauses": top_level_commas(text, cond, ob) + 1}
        cb = matching_close(text, ob, end_off)
        item["body_end"] = cb
        item["has_try"] = SWIFT_TRY.search(text, cond, ob) is not None
        if tok == "if":
            j = skip_space(text, cb + 1, end_off)
            if re.match(r"else\b", text[j:j + 5]):
                j2 = skip_space(text, j + 4, end_off)
                if re.match(r"if\b", text[j2:j2 + 3]):
                    item["else_if"] = j2
                elif text.startswith("{", j2):
                    item["else_body"] = j2
        elif tok == "for":
            w = word_at_depth0(text, cond, ob, "where")
            item["filtered"] = w is not None or re.match(r"case\b", text[cond:cond + 5]) is not None
            item["where"] = w if w is not None else cond
        elif tok == "catch":
            item["where"] = word_at_depth0(text, cond, ob, "where")
        elif tok == "switch":
            item["cases"] = swift_cases(text, ob, cb)
        out.append(item)
    return out


def swift_cases(text, ob, cb):
    """[(offset, number of patterns, offset of where or None)] for the case
    labels directly inside a switch body."""
    out = []
    depth = 0
    k = ob + 1
    while k < cb:
        ch = text[k]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and re.match(r"case\b", text[k:k + 5]) and not (text[k - 1].isalnum() or text[k - 1] == "_"):
            before = text[ob + 1:k].rstrip()
            if not before or before[-1] in "{;:\n" or text[:k].rstrip("\t ").endswith("\n"):
                colon = next_at_depth0(text, k + 4, cb, ":")
                if colon is not None:
                    out.append((k, top_level_commas(text, k + 4, colon) + 1,
                                word_at_depth0(text, k + 4, colon, "where")))
                    k = colon
        k += 1
    return out


# ---------------------------------------------------------------------------
# Line counts from llvm-cov's segments (LineCoverageStats in LLVM)

def line_counts(segments, first, last):
    """[(line, count or None)] for first..last; None when the line is not
    mapped. segments: [line, col, count, has_count, is_region_entry,
    is_gap_region], sorted."""
    keys = [(s[0], s[1]) for s in segments]
    i = bisect.bisect_left(keys, (first, 0))
    wrapped = segments[i - 1] if i > 0 else None
    out = []
    for line in range(first, last + 1):
        line_segs = []
        while i < len(segments) and segments[i][0] == line:
            line_segs.append(segments[i])
            i += 1

        def start_of_region(s):
            return (not s[5]) and s[3] and s[4]
        min_region_count = sum(1 for s in line_segs if start_of_region(s))
        start_of_skipped = bool(line_segs) and (not line_segs[0][3]) and line_segs[0][4]
        mapped = (not start_of_skipped) and ((wrapped is not None and wrapped[3]) or min_region_count > 0)
        mapped = mapped or any(s[4] and s[3] for s in line_segs)
        count = None
        if mapped:
            count = wrapped[2] if wrapped is not None else 0
            if min_region_count:
                for s in line_segs:
                    if start_of_region(s):
                        count = max(count, s[2])
        out.append((line, count))
        if line_segs:
            wrapped = line_segs[-1]
    return out


# ---------------------------------------------------------------------------
# Analysis of one function instance

SWIFT_LIMIT = ("Swift's coverage data has no branch regions: an outcome is known only where the code it leads to "
               "has its own region. The outcomes of if, guard, while and repeat conditions are derived from region "
               "counts where the counts needed exist and agree (a condition with a try is never derived by "
               "subtraction, and the false count before an else if let, var or case is carried along the chain, "
               "never taken from an enclosing region); the rest, and the operands of &&, || and ??, optional "
               "chains, try?, where clauses, case labels with several patterns and which clause of a "
               "multi-clause condition failed, cannot be seen and are listed as not determinable.")

UNCHECKABLE_REASONS = {
    "&&": "the outcomes of the operands of && are not determinable from Swift coverage data",
    "||": "the outcomes of the operands of || are not determinable from Swift coverage data",
    "??": "whether the left side of ?? was ever non-nil is not determinable from Swift coverage data",
    "?.": "whether this optional chain met nil and non-nil is not determinable from Swift coverage data",
    "try?": "whether the call under try? threw and did not throw is not determinable from Swift coverage data",
}

SWIFT_MISS_TEXT = {
    ("if", "true"): "never true (its body never ran)",
    ("if", "false"): "never false",
    ("guard", "true"): "never passed",
    ("guard", "false"): "never failed",
    ("while", "true"): "never true (the loop body never ran)",
    ("while", "false"): "never false (the loop was left only by break, return or throw)",
    ("repeat", "true"): "never true (the loop body ran once each time)",
    ("repeat", "false"): "never false (the loop was left only by break, return or throw)",
}

ENTRY_TEXT = {"block": "block at line %d never invoked", "lambda": "lambda at line %d never called",
              "closure": "closure at line %d never called",
              "implicit closure": "implicit closure at line %d (an @autoclosure argument, or the right side of &&, || or ??) "
                                  "never evaluated"}


def include_kind(rec, swift):
    name = base_name(rec["name"])
    if swift:
        return "implicit closure" if re.search(r"fu\d*_$", name) else "closure"
    if "_block_invoke" in name:
        return "block"
    return "lambda"


def implicit_default_switch(sources, path, ls, cs, le, ce, code=None):
    """(line, col) of the switch keyword when the branch region
    [ls:cs, le:ce) is the one clang attaches to a switch statement that has
    no default label: its extent is the switch's whole condition, from just
    after switch ( to just before the matching ). A branch on an operand of
    ?:, && or || inside the condition covers only that operand. None
    otherwise. code: (text, line starts) to use instead of
    sources.code(path)."""
    text, starts = code or sources.code(path)
    if not text or ls > len(starts) or le > len(starts):
        return None
    a = offset_of(starts, ls, cs)
    b = offset_of(starts, le, ce)
    k = a - 1
    while k >= 0 and text[k] in " \t\r\n":
        k -= 1
    if k < 0 or text[k] != "(":
        return None
    open_off = k
    k -= 1
    while k >= 0 and text[k] in " \t\r\n":
        k -= 1
    if k < 5 or text[k - 5:k + 1] != "switch" or (k >= 6 and (text[k - 6].isalnum() or text[k - 6] == "_")):
        return None
    if matching_close(text, open_off) != skip_space(text, b):
        return None
    return position_of(starts, k - 5)


class Instance:
    """One function record in one binary, with its blocks and closures."""

    def __init__(self, binary, record, includes, segments, folds, sources, ignored_macros=()):
        self.binaries = [binary]
        self.llvm_names = [(binary, record["name"])]
        self.ignored_macros = set(ignored_macros)
        self.ignored = []
        self.record = record
        self.includes = includes
        self.name = base_name(record["name"])
        self.file = record["filenames"][0]
        self.start_line, self.start_col, self.end_line, self.end_col = body_range(record)
        self.count = record["count"]
        self.swift = self.file.endswith(".swift")
        self.lines = [] if segments is None else line_counts(segments, self.start_line, self.end_line)
        self.branches = []
        self.cases = []
        self.regions = []
        self.derived = []
        self.uncheckable = []
        self.claimed = set()
        self.try_zones = []
        self._code = None
        self.set_aside_records, self.set_aside_spans = {}, []
        if self.swift:
            self.set_aside_records, self.set_aside_spans = self._swift_set_aside(sources)
        if not self.swift:
            self._objc_try(sources)
            self._logical_switches(sources)
        for rec in [record] + includes:
            self._analyze(rec, folds, sources, rec is not record)
        if self.swift:
            self._swift(sources)
        elif self.file.endswith((".mm", ".cc", ".cpp", ".cxx", ".hpp", ".h")):
            self._lambdas(sources)
        self.branches.sort(key=lambda b: (b["line"], b["column"]))
        self.cases.sort(key=lambda c: (c["line"], c["column"]))
        self.regions.sort(key=lambda r: (r["line"], r["column"]))
        self.derived.sort(key=lambda d: (d["line"], d["column"]))
        self.uncheckable.sort(key=lambda u: (u["line"], u["column"]))

    def contributing_files(self):
        """The files named in the regions and expansions of the function and
        its blocks: its own file and every header that gives it lines or
        macro definitions."""
        out = []
        for rec in [self.record] + self.includes:
            for f in rec["filenames"]:
                if f not in out:
                    out.append(f)
        return out

    def code(self, sources):
        """(text, line starts) of the function's file as Sources.code gives
        it, with the regions clang marks skipped in the function and its
        blocks (inactive preprocessor blocks) blanked too: their text is
        not code, and brackets in it would mislead every scan."""
        if self._code is None:
            text, starts = sources.code(self.file)
            out = None
            for rec in [self.record] + self.includes:
                names = rec["filenames"]
                for r in rec["regions"]:
                    if r[7] != SKIPPED or r[5] >= len(names) or not same_path(names[r[5]], self.file):
                        continue
                    if out is None:
                        out = list(text)
                    for k in range(offset_of(starts, r[0], r[1]), min(len(out), offset_of(starts, r[2], r[3]))):
                        if out[k] != "\n":
                            out[k] = " "
            self._code = ("".join(out) if out is not None else text, starts)
        return self._code

    def _range_offsets(self, sources):
        text, starts = self.code(sources)
        if not text:
            return text, starts, 0, 0
        return (text, starts, offset_of(starts, self.start_line, self.start_col),
                offset_of(starts, self.end_line, self.end_col))

    def _uncheck(self, line, col, construct, reason):
        self.uncheckable.append({"line": line, "column": col, "construct": construct, "reason": reason})

    def _objc_try(self, sources):
        """@try/@catch: clang gives the whole statement one region, so a
        @catch body's lines and the outcomes it computes by subtraction show
        the enclosing count whether or not the body ran."""
        if not self.file.endswith((".m", ".mm", ".h")):
            return
        text, starts, a, b = self._range_offsets(sources)
        found = find_objc_try(text, starts, a, b)
        self.try_zones = found["zones"]
        self._try_starts = starts
        for ls, cs, _, _ in found["catches"]:
            self._uncheck(ls, cs, "@catch", "not determinable: clang does not record whether a @catch body ran")

    def _logical_switches(self, sources):
        """A switch with no default label whose condition is a && or ||
        expression: clang instruments only conditions that are not logical
        operators (isInstrumentedCondition), so it records no branch for
        the implicit default, and whether no case matched cannot be seen."""
        text, starts, a, b = self._range_offsets(sources)
        for m in re.finditer(r"(?<![\w#])switch\s*\(", text[a:b]):
            k = a + m.start()
            op = a + m.end() - 1
            cp = matching_close(text, op, b)
            cond = text[op + 1:cp].strip()
            while cond.startswith("(") and matching_close(cond, 0) == len(cond) - 1:
                cond = cond[1:-1].strip()
            if not top_level_logical(cond):
                continue
            ob = next_at_depth0(text, cp + 1, b, "{")
            if ob is None:
                continue
            cb = matching_close(text, ob, b)
            depth, has_default = 0, False
            for j in range(ob + 1, cb):
                ch = text[j]
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    depth -= 1
                elif depth == 0 and re.match(r"default\s*:", text[j:j + 20]) and not text[j - 1].isalnum():
                    has_default = True
                    break
            if not has_default:
                line, col = position_of(starts, k)
                self._uncheck(line, col, "implicit default",
                              "switch with no default label whose condition is a && or || expression: clang "
                              "records no branch for its implicit default, so whether no case matched is not "
                              "determinable")

    def _in_try_zone(self, line, col):
        if not self.try_zones:
            return False
        off = offset_of(self._try_starts, line, col)
        return any(a <= off <= b for a, b in self.try_zones)

    def _site(self, rec, file_id, line, col, sources):
        """(line, col, macros): the location in the function's own file of a
        position in file file_id, following expansion regions out of macros,
        and the names of the macros expanded on the way, innermost first."""
        exp = {r[6]: r for r in rec["regions"] if r[7] == EXPANSION}
        names = rec["filenames"]
        seen = set()
        macros = []
        while file_id != 0 and file_id in exp and file_id not in seen:
            seen.add(file_id)
            r = exp[file_id]
            file_id, line, col = r[5], r[0], r[1]
            path = names[file_id] if file_id < len(names) else self.file
            m = IDENTIFIER.match(sources.line(path, line)[col - 1:])
            macros.append(m.group(0) if m else "?")
        return line, col, macros

    def _ignored_macro(self, macros):
        for m in macros:
            if m in self.ignored_macros:
                return m
        return None

    def _analyze(self, rec, folds, sources, is_include):
        names = rec["filenames"]
        if is_include and id(rec) in self.set_aside_records:
            ls, cs, _, _ = body_range(rec)
            kind = include_kind(rec, self.swift)
            self.ignored.append({"line": ls, "column": cs, "macro": self.set_aside_records[id(rec)], "kind": kind,
                                 "text": kind, "count": rec["count"]})
            return
        for b in rec.get("branches", []):
            ls, cs, le, ce, t, f, fid = b[0], b[1], b[2], b[3], b[4], b[5], b[6]
            path = names[fid] if fid < len(names) else self.file
            text = sources.text(path, ls, cs, le, ce)
            line, col, macros = self._site(rec, fid, ls, cs, sources)
            ignored = self._ignored_macro(macros)
            if ignored:
                tf, ff = fold_flags(folds, path, fid, ls, cs, t, f, sources)
                self.ignored.append({"line": line, "column": col, "macro": ignored, "kind": "branch", "text": text,
                                     "true": t, "false": f, "true_folded": tf, "false_folded": ff})
                continue
            expansion = None
            if fid != 0:
                expansion = {"file": path, "line": ls, "column": cs}
            in_zone = self._in_try_zone(line, col)
            if CASE_TEXT.match(text):
                after = sources.line(path, le)[ce - 1:] if ls == le else ""
                label = text + (":" if after.lstrip().startswith(":") else "")
                self.cases.append({"line": line, "column": col, "label": label, "taken": t,
                                   "expansion": expansion})
                continue
            sw = implicit_default_switch(sources, path, ls, cs, le, ce,
                                         self.code(sources) if same_path(path, self.file) else None)
            if sw is not None:
                # The branch on a switch's condition when it has no default
                # label: true when some case matched, false when none did
                # and control went past the switch.
                sl, sc = sw if fid == 0 else (line, col)
                if in_zone and f > 0:
                    self._uncheck(sl, sc, "implicit default",
                                  "inside @try/@catch: clang computes this count by subtraction from the "
                                  "statement's single region, so it may count executions that never happened")
                    continue
                self.cases.append({"line": sl, "column": sc, "label": "implicit default", "taken": f,
                                   "expansion": expansion})
                continue
            tf, ff = fold_flags(folds, path, fid, ls, cs, t, f, sources)
            unexercised = []
            if not tf and t == 0:
                unexercised.append("true")
            if not ff and f == 0:
                unexercised.append("false")
            false_uncheckable = in_zone and not ff and f > 0
            if false_uncheckable:
                self._uncheck(line, col, "branch in @try/@catch",
                              "%s false: not determinable inside @try/@catch: clang computes the false count by "
                              "subtraction from the statement's single region" % text)
            self.branches.append({"line": line, "column": col, "text": text, "true": t, "false": f,
                                  "true_folded": tf, "false_folded": ff, "unexercised": unexercised,
                                  "false_uncheckable": false_uncheckable, "expansion": expansion})
        never_ran = is_include and rec["count"] == 0
        first = True
        for r in rec["regions"]:
            if r[7] != CODE:
                continue
            path = names[r[5]] if r[5] < len(names) else self.file
            line, col, macros = self._site(rec, r[5], r[0], r[1], sources)
            if self._ignored_macro(macros):
                continue
            text = sources.text(path, r[0], r[1], r[2], r[3]).strip()
            entry = {"line": line, "column": col, "count": r[4], "text": text[:60], "file_id": r[5],
                     "end": [r[2], r[3]]}
            if is_include and first:
                entry["entry"] = include_kind(rec, self.swift)
            elif never_ran:
                # Inside a block or closure that never ran: its entry
                # region says so once.
                entry["inside_never_run"] = True
            first = False
            if self.swift and CASE_TEXT.match(text):
                self.cases.append({"line": line, "column": col, "label": text.split(":")[0] + ":",
                                   "taken": r[4], "expansion": None})
            self.regions.append(entry)

    def _lambdas(self, sources):
        text, starts, a, b = self._range_offsets(sources)
        if not text:
            return
        have = {(body_range(r)[0], body_range(r)[1]) for r in self.includes}
        for line, col in find_lambdas(text, starts, a, b):
            if (line, col) not in have:
                self._uncheck(line, col, "lambda",
                              "lambda at line %d: no coverage record (never instantiated or never called): "
                              "not determinable" % line)

    def _swift_set_aside(self, sources):
        """The autoclosures of calls to set-aside functions (DLog by default,
        the same list as the macros set aside in C): an implicit closure
        whose region lies wholly inside the argument parentheses of a call
        to a function of that name is set aside, with every closure inside
        it, and so are the constructs inside it. {id(record): name} and
        [(start, end, name)] offsets of the set-aside implicit closures."""
        records, spans = {}, []
        text, starts, a, b = self._range_offsets(sources)
        if not text or not self.ignored_macros:
            return records, spans
        pattern = re.compile(r"(?<![\w$])(%s)\s*\(" % "|".join(re.escape(m) for m in sorted(self.ignored_macros)))
        calls = []
        for m in pattern.finditer(text, a, b):
            if re.search(r"\bfunc\s*$", text[max(0, m.start() - 20):m.start()]):
                continue
            open_off = m.end() - 1
            calls.append((open_off, matching_close(text, open_off, b), m.group(1)))

        def extent(rec):
            ls, cs, le, ce = body_range(rec)
            return offset_of(starts, ls, cs), offset_of(starts, le, ce)
        for rec in self.includes:
            if include_kind(rec, True) != "implicit closure":
                continue
            s, e = extent(rec)
            for open_off, close_off, name in calls:
                if open_off < s and e <= close_off:
                    records[id(rec)] = name
                    spans.append((s, e, name))
                    break
        for rec in self.includes:
            if id(rec) in records:
                continue
            s, e = extent(rec)
            for ss, se, name in spans:
                if ss <= s and e <= se:
                    records[id(rec)] = name
                    break
        return records, spans

    def _set_aside_span(self, off):
        for s, e, name in self.set_aside_spans:
            if s <= off < e:
                return name
        return None

    def _swift_if_chain(self, head, ifs, at, enclosing, derive):
        """The outcomes of an if and of the ifs chained to it by else if.

        Swift gives an if's body a region, an else body a region, and a
        condition a region only when its first clause is a boolean
        expression; it gives no region to an else that leads to another if.
        For the chain if_0 else if_1 ... else if_n-1 [else] the unknowns are
        E_i, the times control reached if_i, and F_i, the times its
        condition was false, with T_i its body's count. What holds:
          E_0 = the count of the region enclosing if_0's keyword;
          E_i = the count of the region at if_i's condition, when one
                starts there;
          F_i = E_i+1 (control reaches the next if only when this one was
                false);
          F_i = E_i - T_i, unless if_i's condition has a try (a throw is
                neither outcome);
          F_n-1 = the final else body's count, when there is one.
        Each is used where its values are known, until nothing changes;
        then every equation whose values are all known must hold. An
        outcome is reported only when it is known and the chain is
        consistent; otherwise not determinable. Nothing is ever taken from
        a region that merely encloses an else if."""
        chain = [head]
        while "else_if" in chain[-1] and chain[-1]["else_if"] in ifs and len(chain) <= len(ifs):
            chain.append(ifs[chain[-1]["else_if"]])
        n = len(chain)
        t = [at(c["body"]) for c in chain]
        known = {}
        conflict = []

        def put(var, value):
            if value is None:
                return False
            if var in known:
                if known[var] != value:
                    conflict.append(var)
                return False
            known[var] = value
            return True
        put(("E", 0), enclosing(head["at"]))
        for i, c in enumerate(chain):
            put(("E", i), at(c["cond"]))
        last = chain[-1]
        else_count = at(last["else_body"]) if "else_body" in last else None
        put(("F", n - 1), else_count)
        changed = True
        while changed and not conflict:
            changed = False
            for i in range(n):
                if i + 1 < n:
                    if ("F", i) in known:
                        changed |= put(("E", i + 1), known[("F", i)])
                    if ("E", i + 1) in known:
                        changed |= put(("F", i), known[("E", i + 1)])
                if t[i] is not None and not chain[i]["has_try"]:
                    if ("E", i) in known:
                        changed |= put(("F", i), known[("E", i)] - t[i])
                    if ("F", i) in known:
                        changed |= put(("E", i), known[("F", i)] + t[i])
                elif t[i] is not None and known.get(("E", i)) == t[i]:
                    # With a try, F_i is at most E_i - T_i: zero here.
                    changed |= put(("F", i), 0)
        # With a try in the condition, a throw is neither outcome: the
        # outcomes can only add up to fewer than the times it was reached.
        for i in range(n):
            e, f = known.get(("E", i)), known.get(("F", i))
            if e is not None and f is not None and t[i] is not None and t[i] + f > e:
                conflict.append(("E", i))
        for i, c in enumerate(chain):
            f = known.get(("F", i))
            if conflict:
                reason = "the region counts of its if/else if chain are inconsistent"
            elif t[i] is None:
                reason = "its body has no region"
            elif f is None and c["has_try"]:
                reason = ("its condition has a try: a throw is neither outcome, so the times it was reached less "
                          "its body's count is not the false count, and no other region gives it")
            elif f is None:
                reason = ("no region gives its false count: Swift emits none for an else that leads to else if "
                          "let, else if var or else if case, nor at such a condition")
            else:
                reason = None
            claim = [c["body"]]
            if c is last and "else_body" in c:
                claim.append(c["else_body"])
            f = derive(c, "if", None if reason else t[i], None if reason else f, claim, reason)
            if f and c["clauses"] > 1:
                line, col = position_of(self._starts, c["at"])
                self._uncheck(line, col, "if", "which of its %d clauses was false is not determinable"
                              % c["clauses"])

    def _swift(self, sources):
        text, starts, a, b = self._range_offsets(sources)
        self._starts = starts
        if not text:
            return
        own = [r for r in self.regions if r["file_id"] == 0]
        at_pos = {}
        for r in own:
            at_pos.setdefault((r["line"], r["column"]), set()).add((r["count"], tuple(r["end"])))

        def at(off):
            """The count of the region that starts exactly at off; None when
            no region starts there or the regions that do disagree. Never
            the count of an enclosing region."""
            found = at_pos.get(position_of(starts, off))
            counts = {c for c, _ in found} if found else set()
            return counts.pop() if len(counts) == 1 else None

        def end_at(off):
            found = at_pos.get(position_of(starts, off))
            if not found or len(found) != 1:
                return None
            (_, (line, col)), = found
            return offset_of(starts, line, col)

        def enclosing(off):
            """The count of the innermost region containing the statement
            keyword at off, taken as the number of times control reached the
            statement. Only used at the keyword of a statement that is not
            the target of an else. This assumes nothing left the code
            between the region's start and the keyword without Swift
            starting a new region: Swift does start one after return, throw,
            break, continue, a guard and a try (as the fixtures show), but
            not after a call to a Never-returning function, which is assumed
            to end the process (pthread_exit does not, and breaks this)."""
            pos = position_of(starts, off)
            best = None
            for r in own:
                s, e = (r["line"], r["column"]), tuple(r["end"])
                if s <= pos < e and (best is None or s > best[0] or (s == best[0] and e < best[1])):
                    best = (s, e, r["count"])
            return None if best is None else best[2]

        def text_of(c):
            cond = text[c["cond"]:c.get("cond_end", c["cond"])].strip() if "cond" in c else ""
            return " ".join(cond.split())[:60]

        def derive(c, kind, t, f, claim, reason=None):
            line, col = position_of(starts, c["at"])
            if t is None or f is None or t < 0 or f < 0:
                self._uncheck(line, col, kind, "%s at line %d: %s: not determinable" % (
                    kind, line, reason or "the region counts needed to derive its outcomes are missing or "
                                          "inconsistent"))
                return None
            for off in claim:
                self.claimed.add(position_of(starts, off))
            missed = [o for o, n in (("true", t), ("false", f)) if n == 0]
            self.derived.append({"line": line, "column": col, "construct": kind, "text": text_of(c),
                                 "true": t, "false": f, "unexercised": missed})
            return f

        constructs = []
        for c in swift_constructs(text, starts, a, b):
            name = self._set_aside_span(c["at"])
            if name is None:
                constructs.append(c)
                continue
            line, col = position_of(starts, c["at"])
            self.ignored.append({"line": line, "column": col, "macro": name, "kind": c["kind"],
                                 "text": c["kind"]})
        ifs = {c["at"]: c for c in constructs if c["kind"] == "if"}
        targets = {c["else_if"] for c in ifs.values() if "else_if" in c}
        for c in constructs:
            kind = c["kind"]
            line, col = position_of(starts, c["at"])
            if kind in UNCHECKABLE_REASONS:
                self._uncheck(line, col, kind, UNCHECKABLE_REASONS[kind])
                continue
            if kind == "if":
                if c["at"] not in targets:
                    self._swift_if_chain(c, ifs, at, enclosing, derive)
            elif kind == "guard":
                # Passed: the count of the region Swift starts after the
                # guard (its else always leaves), or the count reaching the
                # guard minus the failures when no try in the condition can
                # throw past both outcomes. Both, when both exist, must
                # agree.
                g = at(c["body"])
                after = at(c["body_end"] + 1)
                parent = enclosing(c["at"])
                by_parent = None if g is None or parent is None or c["has_try"] else parent - g
                candidates = {v for v in (after, by_parent) if v is not None}
                passed = next(iter(candidates)) if len(candidates) == 1 else None
                reason = None
                if len(candidates) > 1:
                    reason = "the count after it (%s) and the count reaching it less its failures (%s) disagree" % (
                        after, by_parent)
                elif after is None and c["has_try"]:
                    reason = ("no region follows it and its condition has a try: a throw is neither outcome, so the "
                              "count reaching it less its failures is not the count that passed")
                derive(c, "guard", passed, g, [c["body"]], reason)
                if g and c["clauses"] > 1:
                    self._uncheck(line, col, "guard", "which of its %d clauses failed is not determinable"
                                  % c["clauses"])
            elif kind == "while":
                cond_count = at(c["cond"])
                t = at(c["body"])
                if cond_count is None:
                    self._uncheck(line, col, "while", "while at line %d has no region for its condition (a while "
                                                      "let): whether it was false is not determinable" % line)
                    continue
                if c["has_try"] and t is not None and cond_count == t:
                    # A throw is neither outcome, so the false count is at
                    # most evaluations less the body's count: zero here.
                    derive(c, "while", t, 0, [c["body"]])
                    continue
                if c["has_try"]:
                    self._uncheck(line, col, "while", "while at line %d: its condition has a try: a throw is neither "
                                                      "outcome, so evaluations less the body's count is not the "
                                                      "false count: not determinable" % line)
                    continue
                derive(c, "while", t, None if t is None else cond_count - t, [c["body"]])
                if c["clauses"] > 1:
                    self._uncheck(line, col, "while", "which of its %d clauses was false is not determinable"
                                  % c["clauses"])
            elif kind == "repeat":
                cond_count = at(c["cond"])
                body = at(c["body"])
                parent = enclosing(c["at"])
                # The condition's extent: its region, and at least the rest
                # of its first line.
                cond_end = end_at(c["cond"]) or c["cond"]
                line_end = text.find("\n", c["cond"])
                cond_end = max(cond_end, b if line_end < 0 else line_end)
                if SWIFT_TRY.search(text, c["cond"], cond_end):
                    self._uncheck(line, col, "repeat", "repeat at line %d: its condition has a try: a throw is "
                                                       "neither outcome, so its false count is not determinable"
                                  % line)
                    continue
                # A throw out of the body is counted by the region at the
                # condition as an evaluation, so cond_count - t is too high:
                # a body that can throw (throw, or a try that is not try? or
                # try!, outside the closures and local functions declared in
                # it) is not determinable.
                body_text = list(text[c["body"]:c["body_end"]])
                for rec in self.includes:
                    if include_kind(rec, True) != "closure":
                        continue
                    ls, cs, le, ce = body_range(rec)
                    s0, e0 = offset_of(starts, ls, cs), offset_of(starts, le, ce)
                    if c["body"] < s0 and e0 <= c["body_end"]:
                        for k in range(s0 - c["body"], e0 - c["body"]):
                            body_text[k] = " "
                body_text = "".join(body_text)
                if SWIFT_TRY.search(body_text) or re.search(r"(?<![\w#@])throw\b", body_text):
                    self._uncheck(line, col, "repeat", "repeat at line %d: its body can throw, and the region at its "
                                                       "condition counts the iteration that threw as an evaluation: "
                                                       "its false count is not determinable" % line)
                    continue
                t = None if body is None or parent is None else body - parent
                f = None if t is None or cond_count is None else cond_count - t
                # The region after the loop counts the false outcomes and the
                # breaks: f can be no more, and equal when there is no break.
                cond_end_off = end_at(c["cond"])
                after = None if cond_end_off is None else at(cond_end_off)
                reason = None
                if f is not None and after is not None and (
                        f > after or (f != after and not re.search(r"\bbreak\b", body_text))):
                    reason = ("its false count by subtraction (%d) and the count after the loop (%d) disagree"
                              % (f, after))
                    f = None
                derive(c, "repeat", t, f, [c["body"]], reason)
            elif kind == "for":
                if c["filtered"]:
                    wl, wc = position_of(starts, c["where"])
                    self._uncheck(wl, wc, "for-in filter", "the where clause or case pattern of a for-in loop: "
                                                           "whether it was false is not determinable")
            elif kind == "catch":
                if c["where"] is not None:
                    wl, wc = position_of(starts, c["where"])
                    self._uncheck(wl, wc, "catch where", "whether the where clause of a catch was false is "
                                                         "not determinable")
            elif kind == "switch":
                for off, patterns, where in c["cases"]:
                    cl, cc = position_of(starts, off)
                    if patterns > 1:
                        self._uncheck(cl, cc, "case", "case label with %d patterns: which of them matched is not "
                                                      "determinable" % patterns)
                    if where is not None:
                        wl, wc = position_of(starts, where)
                        self._uncheck(wl, wc, "case where", "whether the where clause of a case was false is not "
                                                            "determinable")

    def executed(self):
        return self.count > 0 or any(r["count"] > 0 for r in self.includes)

    def unexercised_regions(self):
        """Code regions that never ran, other than case labels (reported as
        such), those a derived condition accounts for and those inside a
        block or closure whose entry region already says it never ran."""
        return [r for r in self.regions if r["count"] == 0 and not CASE_TEXT.match(r["text"])
                and (r["line"], r["column"]) not in self.claimed and not r.get("inside_never_run")]

    def region_text(self, r):
        if r.get("entry"):
            return ENTRY_TEXT[r["entry"]] % r["line"]
        return "region at line %d col %d" % (r["line"], r["column"])

    def unexercised_items(self):
        """[(category, text)] for what was not exercised."""
        items = []
        for c in self.cases:
            if c["taken"] == 0:
                items.append(("case", "%s at line %d" % (c["label"], c["line"])))
        for b in self.branches:
            for o in b["unexercised"]:
                items.append(("branch", "line %d col %d %s %s" % (b["line"], b["column"], b["text"], o)))
        for d in self.derived:
            for o in d["unexercised"]:
                items.append(("condition", "line %d col %d %s %s: %s (derived from region counts)"
                              % (d["line"], d["column"], d["construct"], d["text"],
                                 SWIFT_MISS_TEXT[(d["construct"], o)])))
        for r in self.unexercised_regions():
            items.append(("region", self.region_text(r)))
        return items

    def full(self):
        return self.executed() and not self.unexercised_items()

    def status(self, accept):
        if not self.full():
            return 1
        if self.uncheckable and not accept:
            return 3
        return 0

    def verdict(self, accept=False):
        if not self.executed():
            return "not exercised: the function was never executed"
        items = self.unexercised_items()
        if items:
            return verdict_from_items(items) + set_aside_note([self])
        if self.uncheckable or self.swift:
            return checkable_verdict(self.uncheckable, accept) + set_aside_note([self])
        return FULL_VERDICT + set_aside_note([self])

    def summary(self):
        mapped = [c for _, c in self.lines if c is not None]
        # An outcome that is not determinable is neither covered nor missed:
        # it is left out of the total and counted under not determinable.
        outcomes = sum((not b["true_folded"]) + (not b["false_folded"]) - b["false_uncheckable"]
                       for b in self.branches)
        missed = sum(len(b["unexercised"]) for b in self.branches)
        return {"lines_covered": sum(1 for c in mapped if c > 0), "lines_total": len(mapped),
                "regions_covered": sum(1 for r in self.regions if r["count"] > 0),
                "regions_total": len(self.regions),
                "branches_covered": outcomes - missed, "branches_total": outcomes,
                "cases_covered": sum(1 for c in self.cases if c["taken"] > 0),
                "cases_total": len(self.cases),
                "derived_covered": sum(2 - len(d["unexercised"]) for d in self.derived),
                "derived_total": 2 * len(self.derived),
                "not_determinable": len(self.uncheckable)}

    def signature(self):
        """What makes two instances the same function with the same counts."""
        def strip(rec):
            return (base_name(rec["name"]), rec["count"], json.dumps(rec["regions"]),
                    json.dumps(rec.get("branches", [])))
        return (self.file, self.start_line, strip(self.record), tuple(strip(r) for r in self.includes))

    def to_json(self, accept=False):
        d = {"name": self.name, "llvm_name": self.record["name"], "binary": self.binaries[0],
             "binaries": self.binaries, "file": self.file, "start_line": self.start_line,
             "end_line": self.end_line, "count": self.count,
             "includes": [r["name"] for r in self.includes],
             "lines": [{"line": l, "count": c} for l, c in self.lines],
             "cases": self.cases, "branches": self.branches, "ignored": self.ignored,
             "unexercised_regions": [dict(r, description=self.region_text(r)) for r in self.unexercised_regions()],
             "derived_conditions": self.derived, "not_determinable": self.uncheckable,
             "summary": self.summary(), "verdict": self.verdict(accept), "full": self.full(),
             "status": self.status(accept)}
        if self.swift:
            d["swift_limit"] = SWIFT_LIMIT
        return d


def set_aside_note(instances):
    """" (N set aside inside DLog: ...)" for the verdict line, or ""."""
    ignored = [i for inst in instances for i in inst.ignored]
    if not ignored:
        return ""
    return " (%d set aside inside %s: listed under Set aside, not counted)" % (
        len(ignored), " and ".join(sorted({i["macro"] for i in ignored})))


def checkable_verdict(uncheckable, accept):
    n = len(uncheckable)
    listed = "; ".join("line %d col %d %s" % (u["line"], u["column"], u["construct"])
                       for u in uncheckable[:VERDICT_LIST_LIMIT])
    if n > VERDICT_LIST_LIMIT:
        listed += "; and %d more" % (n - VERDICT_LIST_LIMIT)
    what = "%d construct%s could not be checked" % (n, "" if n == 1 else "s")
    if not n:
        return CHECKABLE_VERDICT + "; " + what
    if accept:
        return CHECKABLE_VERDICT + "; " + what + ": " + listed
    return ("incomplete: " + CHECKABLE_VERDICT + ", but " + what + " (listed under Not determinable; "
            "--accept-uncheckable accepts them): " + listed)


def verdict_from_items(items):
    counts = {}
    for cat, _ in items:
        counts[cat] = counts.get(cat, 0) + 1
    names = (("case", "case label"), ("branch", "branch outcome"), ("condition", "derived condition outcome"),
             ("region", "region"))
    parts = ["%d %s%s" % (counts[c], n, "" if counts[c] == 1 else "s") for c, n in names if counts.get(c)]
    texts = [t for _, t in items]
    shown = texts[:VERDICT_LIST_LIMIT]
    more = len(texts) - len(shown)
    return "not exercised: %s: %s%s" % (" and ".join(parts), "; ".join(shown),
                                         "; and %d more" % more if more else "")


# ---------------------------------------------------------------------------
# Inputs: run directory, binaries, staleness

class Inputs:
    def __init__(self, args):
        self.problems = []
        self.notes = []
        self.run = None
        self.ignored_macros = set(() if args.no_default_ignores else DEFAULT_IGNORED_MACROS)
        self.ignored_macros.update(args.ignore_macro or ())
        self.digests = None
        run = args.run
        if not args.profdata or not args.binary:
            run = run or DEFAULT_RUN
        if run:
            if not os.path.isdir(run):
                raise ToolError("no run directory %s; run tools/swift_migration/coverage_tests.sh first" % run)
            self.run = os.path.realpath(run)
        self.profdata = args.profdata or (os.path.join(self.run, "coverage.profdata") if self.run else None)
        if not self.profdata or not os.path.isfile(self.profdata):
            raise ToolError("no merged profile %s" % self.profdata)
        if args.binary:
            self.binaries = [os.path.abspath(b) for b in args.binary]
            for b in self.binaries:
                if not os.path.isfile(b):
                    raise ToolError("no binary %s" % b)
        else:
            self.binaries = self._run_binaries()
        if self.run and os.path.isfile(os.path.join(self.run, "sources.sha256")):
            self.digests = {}
            with open(os.path.join(self.run, "sources.sha256")) as f:
                for line in f:
                    digest, _, path = line.rstrip("\n").partition("  ")
                    self.digests[os.path.realpath(os.path.join(ROOT, path))] = digest
        # Which route produced the run's per-class profiles: "per-class"
        # (one xcodebuild invocation per class: exact) or "observer" (one
        # process, counters zeroed between classes: approximate). None when
        # the run did not record it, which is treated as approximate.
        # The run's exit status (status.txt): a run whose tests did not all
        # pass gives an incomplete answer.
        if self.run and not args.profdata:
            status_path = os.path.join(self.run, "status.txt")
            if not os.path.isfile(status_path):
                self.notes.append("the run %s does not record whether its tests passed (no status.txt; made by an "
                                  "older coverage_tests.sh)" % self.run)
            else:
                with open(status_path) as f:
                    recorded = f.read().strip()
                if recorded != "0":
                    self.problems.append("the run's tests did not all pass (coverage_tests.sh exited with status "
                                         "%s): its coverage is that of a failing net" % (recorded or "unknown"))
        self.route = None
        if self.run and os.path.isfile(os.path.join(self.run, "per_class_route.txt")):
            with open(os.path.join(self.run, "per_class_route.txt")) as f:
                self.route = f.read().strip() or None

    def _run_binaries(self):
        path = os.path.join(self.run, "binaries.txt")
        if not os.path.isfile(path):
            raise ToolError("no %s" % path)
        result, seen = [], set()
        with open(path) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 3:
                    continue
                b, size, mtime = parts[0], int(parts[1]), int(parts[2])
                if not os.path.isfile(b):
                    self.problems.append("%s is gone since the run" % b)
                    continue
                st = os.stat(b)
                if st.st_size != size or int(st.st_mtime) != mtime:
                    self.problems.append("%s changed since the run (rebuilt?); its counts are not used" % b)
                    continue
                # The build copies some products (iTermServer, pidinfo) to
                # two places; one copy is enough.
                key = (os.path.basename(b), size)
                if key in seen:
                    continue
                seen.add(key)
                result.append(b)
        return result

    def check_source(self, path, binary, function=None):
        """Adds a problem when path changed since the coverage build.
        function: the name of the function to which path, a header,
        contributes lines or macro definitions."""
        real = os.path.realpath(path)
        role = "" if function is None else " (it contributes lines or macro definitions to %s)" % function
        problem = None
        if self.digests is not None and real in self.digests:
            try:
                with open(real, "rb") as f:
                    now = hashlib.sha256(f.read()).hexdigest()
            except OSError:
                problem = "%s is gone since the coverage build%s" % (path, role)
            else:
                if now != self.digests[real]:
                    problem = "%s changed since the coverage build%s; line numbers may be wrong" % (path, role)
        else:
            try:
                if os.stat(real).st_mtime > os.stat(binary).st_mtime:
                    problem = "%s changed since the coverage build (newer than %s)%s" % (
                        path, os.path.basename(binary), role)
            except OSError:
                problem = "%s is gone since the coverage build%s" % (path, role)
        if problem and problem not in self.problems:
            self.problems.append(problem)

    def check_instance(self, inst, binary):
        """check_source for the function's file and every other file named
        in its regions and expansions (headers giving it code or macros)."""
        for f in inst.contributing_files():
            self.check_source(f, binary, None if same_path(f, inst.file) else inst.name)


def open_codedb(args):
    if args.no_codedb:
        return None
    path = args.codedb or (DEFAULT_CODEDB if os.path.isfile(DEFAULT_CODEDB) else None)
    if not path:
        return None
    try:
        return sqlite3.connect("file:%s?mode=ro" % path, uri=True)
    except sqlite3.Error:
        return None


def codedb_methods(db, sign, cls, cat, sel):
    """[(llvm_name, abs_file, line)] for the definitions of the method."""
    try:
        rows = db.execute(
            "SELECT DISTINCT container_name, container_kind, file, line FROM objc_method "
            "WHERE selector = ? AND is_class_method = ? AND class_name = ? AND is_definition = 1 "
            "AND container_kind IN ('implementation', 'category-implementation')",
            (sel, 1 if sign == "+" else 0, cls)).fetchall()
    except sqlite3.Error:
        return []
    out = []
    for container, kind, path, line in rows:
        if cat is not None and container != "%s(%s)" % (cls, cat):
            continue
        out.append(("%s[%s %s]" % (sign, container, sel), os.path.join(ROOT, path), line))
    return out


# ---------------------------------------------------------------------------
# Finding functions

class Spec:
    def __init__(self, text, file_arg):
        self.text = text
        self.file = os.path.abspath(file_arg) if file_arg else None
        self.line = None
        self.objc = OBJC_SPEC.match(text)
        m = FILE_LINE_SPEC.match(text)
        if not self.objc and m and os.path.isfile(m.group(1)):
            self.file = os.path.abspath(m.group(1))
            self.line = int(m.group(2))
        self.swift = (not self.objc and self.line is None and re.search(r"[.(]", text) is not None)
        if self.swift and not self.file:
            raise ToolError("a Swift name needs --file, or name the function as PATH:LINE")

    def exact(self, rec):
        name = base_name(rec["name"])
        if self.line is not None:
            return False
        return name == self.text

    def category_match(self, rec):
        if not self.objc or self.objc.group(3) is not None:
            return False
        sign, cls, sel = self.objc.group(1), self.objc.group(2), self.objc.group(4)
        return category_pattern(sign, cls, sel).match(base_name(rec["name"])) is not None


def swift_demangle(names):
    if not names:
        return {}
    proc = subprocess.run(["xcrun", "swift-demangle", "--simplified"], input="\n".join(names) + "\n",
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise ToolError("swift-demangle failed: %s" % proc.stderr.strip())
    out = proc.stdout.split("\n")
    return {n: out[i] if i < len(out) else n for i, n in enumerate(names)}


def is_nested(inner, outer):
    if inner is outer or inner["name"] == outer["name"]:
        return False
    a = body_range(inner)
    b = body_range(outer)
    return (a[0], a[1]) >= (b[0], b[1]) and (a[2], a[3]) <= (b[2], b[3]) and a != b


def records_in_file(binary, profdata, path):
    """(file_object or None, [function records whose own file is path])."""
    recs = []
    real = os.path.realpath(path)

    def on_function(rec):
        if rec["filenames"] and os.path.realpath(rec["filenames"][0]) == real:
            recs.append(rec)
    # First the functions alone; only a binary that has the file is asked
    # for its line data, since naming a file a binary lacks lists them all.
    run_export(binary, profdata, None, lambda f: None, on_function)
    if not recs:
        return None, []
    found = []

    def on_file(f):
        if same_path(f["filename"], path):
            found.append(f)
    run_export(binary, profdata, [recs[0]["filenames"][0]], on_file, lambda f: None, skip_functions=True)
    return (found[0] if found else None), recs


def group_with_includes(recs):
    """[(record, [nested records])] for the outermost records."""
    outer = []
    for r in recs:
        if not any(is_nested(r, o) for o in recs):
            outer.append(r)
    return [(o, [r for r in recs if is_nested(r, o)]) for o in outer]


def find_function(inputs, spec, codedb, sources):
    """[Instance] for the spec across the binaries."""
    want_names = None
    want_file = spec.file
    if spec.objc and codedb is not None:
        rows = codedb_methods(codedb, spec.objc.group(1), spec.objc.group(2), spec.objc.group(3),
                              spec.objc.group(4))
        exact = [r for r in rows if r[0] == spec.text]
        chosen = exact or rows
        if chosen:
            want_names = {r[0] for r in chosen}
            files = {r[1] for r in chosen}
            if len(files) == 1 and not want_file:
                want_file = files.pop()
    instances = []
    for binary in inputs.binaries:
        candidates = []
        if want_file is None:
            # Pass 1: names only, no files array.
            exact, cats = [], []

            def on_function(rec):
                if spec.exact(rec):
                    exact.append(rec)
                elif spec.category_match(rec):
                    cats.append(rec)
            run_export(binary, inputs.profdata, None, lambda f: None, on_function)
            chosen = exact or cats
            if not chosen:
                continue
            paths = sorted({r["filenames"][0] for r in chosen})
        else:
            paths = [want_file]
        for path in paths:
            fobj, recs = records_in_file(binary, inputs.profdata, path)
            if not recs:
                continue
            if spec.line is not None:
                targets = [r for r in recs if body_range(r)[0] <= spec.line <= body_range(r)[2]]
                # The innermost record that is not nested in another
                # candidate's block is reported with its blocks: take the
                # outermost function containing the line.
                targets = [r for r in targets if not any(is_nested(r, o) for o in targets)]
            elif spec.swift:
                swift_names = [r["name"] for r in recs]
                dem = swift_demangle([base_name(n) for n in swift_names])
                targets = [r for r in recs if spec.text in dem.get(base_name(r["name"]), "")]
                targets = [r for r in targets if not any(is_nested(r, o) for o in recs)]
            else:
                exact = [r for r in recs if spec.exact(r)]
                if want_names:
                    exact = exact or [r for r in recs if base_name(r["name"]) in want_names]
                targets = exact or [r for r in recs if spec.category_match(r)]
            if not targets:
                continue
            folds = folded_branches(binary, inputs.profdata, path)
            for t in targets:
                includes = [r for r in recs if is_nested(r, t)]
                inst = Instance(binary, t, includes, fobj["segments"] if fobj else None,
                                folds, sources, inputs.ignored_macros)
                candidates.append(inst)
                inputs.check_instance(inst, binary)
        instances.extend(candidates)
    return instances


def merge_identical(instances, inputs):
    """Instances with the same signature are one function with the same
    counts. Two cases: the same name and hash in several binaries, which
    the profile cannot separate (each shows their sum), and records with
    different names (a static function of a header compiled into two
    translation units) whose counts happen to be equal."""
    groups = {}
    order = []
    for inst in instances:
        sig = inst.signature()
        if sig in groups:
            groups[sig].binaries.extend(inst.binaries)
            groups[sig].llvm_names.extend(inst.llvm_names)
        else:
            groups[sig] = inst
            order.append(sig)
    merged = [groups[s] for s in order]
    for inst in merged:
        if len(inst.llvm_names) < 2:
            continue
        named = ", ".join("%s in %s" % (n, os.path.basename(b)) for b, n in inst.llvm_names)
        if len({n for _, n in inst.llvm_names}) == 1:
            inputs.notes.append("%s has %d instances with the same name and hash (%s), so the profile cannot "
                                "separate their counts: the counts shown are their sum"
                                % (inst.name, len(inst.llvm_names), named))
        else:
            inputs.notes.append("%s has %d instances with identical counts (%s): each has its own profile record; "
                                "they are shown once" % (inst.name, len(inst.llvm_names), named))
    return merged


def union_of(instances):
    """Union of several instances: an outcome, case or region is exercised
    when any instance exercised it."""
    outcomes = {}
    cases = {}
    regions = {}
    for inst in instances:
        for b in inst.branches:
            for o in ("true", "false"):
                if (o == "true" and b["true_folded"]) or (o == "false" and b["false_folded"]):
                    continue
                if o == "false" and b.get("false_uncheckable"):
                    continue  # not determinable: listed there, never exercised
                key = (b["line"], b["column"], o)
                outcomes[key] = outcomes.get(key, False) or (o not in b["unexercised"])
        for d in inst.derived:
            for o in ("true", "false"):
                key = (d["line"], d["column"], o)
                outcomes[key] = outcomes.get(key, False) or (o not in d["unexercised"])
        for c in inst.cases:
            key = (c["line"], c["column"], c["label"])
            cases[key] = cases.get(key, False) or c["taken"] > 0
        for r in inst.regions:
            key = (r["line"], r["column"])
            regions[key] = regions.get(key, False) or r["count"] > 0
    unexercised = sorted([list(k) for k, v in outcomes.items() if not v])
    cases_un = sorted([list(k) for k, v in cases.items() if not v])
    claimed = set().union(*[i.claimed for i in instances])
    regions_un = sorted([list(k) for k, v in regions.items() if not v and k not in claimed
                         and any((r["line"], r["column"]) == k for i in instances for r in i.unexercised_regions())])
    uncheckable = {}
    for inst in instances:
        for u in inst.uncheckable:
            uncheckable[(u["line"], u["column"], u["construct"])] = u
    return {"branches_covered": sum(1 for v in outcomes.values() if v), "branches_total": len(outcomes),
            "cases_covered": sum(1 for v in cases.values() if v), "cases_total": len(cases),
            "unexercised": unexercised, "unexercised_cases": cases_un, "unexercised_regions": regions_un,
            "not_determinable": [uncheckable[k] for k in sorted(uncheckable)],
            "executed": any(i.executed() for i in instances)}


# ---------------------------------------------------------------------------
# Commands

def summary_line(s):
    text = ("lines %d/%d covered, regions %d/%d, branches %d/%d (outcomes), case labels %d/%d"
            % (s["lines_covered"], s["lines_total"], s["regions_covered"], s["regions_total"],
               s["branches_covered"], s["branches_total"], s["cases_covered"], s["cases_total"]))
    if s.get("derived_total"):
        text += ", derived condition outcomes %d/%d" % (s["derived_covered"], s["derived_total"])
    if s.get("not_determinable"):
        text += ", not determinable %d" % s["not_determinable"]
    return text


SET_ASIDE_SHOWN = 10
IMPLICIT_DEFAULT_HINT = ("(control goes past the switch when no case matches: a test can pass a value no case lists, "
                         "by a cast when the cases list every enumerator; if no such value can reach it, list it in "
                         "the dossier with the reason, large-code.md section 2.1)")


def print_set_aside(inst, verbose, out):
    """The branches set aside by --ignore-macro (and the default set),
    grouped by macro, with their outcome counts."""
    by_macro = {}
    for b in inst.ignored:
        by_macro.setdefault(b["macro"], []).append(b)
    out.write("Set aside (inside set-aside macros and logging calls, not counted): %d\n" % len(inst.ignored))
    for macro in sorted(by_macro):
        group = sorted(by_macro[macro], key=lambda b: (b["line"], b["column"]))
        if all(b.get("kind", "branch") == "branch" for b in group):
            noun = "branch" if len(group) == 1 else "branches"
        else:
            noun = "item" if len(group) == 1 else "items"
        out.write("  %s: %d %s\n" % (macro, len(group), noun))
        shown = group if verbose else group[:SET_ASIDE_SHOWN]
        for b in shown:
            kind = b.get("kind", "branch")
            if kind == "branch":
                t = "folded" if b.get("true_folded") else str(b["true"])
                f = "folded" if b.get("false_folded") else str(b["false"])
                out.write("    line %d col %d: %s  true %s false %s\n" % (b["line"], b["column"], b["text"], t,
                                                                          f))
            elif "count" in b:
                out.write("    line %d col %d: %s, executed %d time%s\n" % (
                    b["line"], b["column"], kind, b["count"], "" if b["count"] == 1 else "s"))
            else:
                out.write("    line %d col %d: %s\n" % (b["line"], b["column"], kind))
        if len(shown) < len(group):
            out.write("    ... and %d more (--verbose lists them all)\n" % (len(group) - len(shown)))


def print_instance(inst, sources, max_lines, out, verbose=False):
    shown_name = inst.name
    if inst.swift and inst.name.startswith("$s"):
        try:
            shown_name = "%s  [%s]" % (swift_demangle([inst.name])[inst.name], inst.name)
        except ToolError:
            pass
    out.write("Function: %s  (%s:%d-%d)\n" % (shown_name, inst.file, inst.start_line, inst.end_line))
    out.write("Binary: %s\n" % ", ".join(inst.binaries))
    if inst.includes:
        out.write("Includes: %s\n" % ", ".join(r["name"] for r in inst.includes))
    out.write("Executed: %d time%s\n" % (inst.count, "" if inst.count == 1 else "s"))
    shown = inst.lines if max_lines is None else inst.lines[:max_lines]
    for line, count in shown:
        text = sources.line(inst.file, line)
        mark = "  <<<" if count == 0 else ""
        out.write("%6d %10s | %s%s\n" % (line, "" if count is None else count, text, mark))
    if len(shown) < len(inst.lines):
        out.write("       ... %d more lines\n" % (len(inst.lines) - len(shown)))
    if inst.cases:
        out.write("Case labels:\n")
        for c in inst.cases:
            out.write("  line %d: %-30s taken %d%s\n" % (c["line"], c["label"], c["taken"],
                                                         "  NOT EXERCISED" if c["taken"] == 0 else ""))
            if c["label"] == "implicit default" and c["taken"] == 0:
                out.write("    %s\n" % IMPLICIT_DEFAULT_HINT)
    if inst.branches:
        out.write("Branches:\n")
        for b in inst.branches:
            t = "folded" if b["true_folded"] else str(b["true"])
            f = "folded" if b["false_folded"] else str(b["false"])
            if b.get("false_uncheckable"):
                f += " (not determinable)"
            where = ""
            if b["expansion"]:
                where = " (expanded from %s:%d:%d)" % (os.path.basename(b["expansion"]["file"]),
                                                      b["expansion"]["line"], b["expansion"]["column"])
            miss = "  NOT EXERCISED: %s" % ", ".join(b["unexercised"]) if b["unexercised"] else ""
            out.write("  line %d col %d: %s  true %s false %s%s%s\n" % (b["line"], b["column"], b["text"], t,
                                                                      f, where, miss))
    if inst.derived:
        out.write("Conditions derived from region counts:\n")
        for d in inst.derived:
            miss = ""
            if d["unexercised"]:
                miss = "  NOT EXERCISED: " + ", ".join(SWIFT_MISS_TEXT[(d["construct"], o)] for o in d["unexercised"])
            out.write("  line %d col %d: %s %s  true %d false %d%s\n" % (d["line"], d["column"], d["construct"],
                                                                       d["text"], d["true"], d["false"], miss))
    if inst.ignored:
        print_set_aside(inst, verbose, out)
    un = inst.unexercised_regions()
    if un:
        out.write("Regions never run:\n")
        for r in un:
            out.write("  line %d col %d: %s%s\n" % (r["line"], r["column"], r["text"],
                                                    "  (%s)" % inst.region_text(r) if r.get("entry") else ""))
    if inst.uncheckable:
        out.write("Not determinable (%d):\n" % len(inst.uncheckable))
        for u in inst.uncheckable:
            out.write("  %s:%d col %d: %s: %s\n" % (os.path.basename(inst.file), u["line"], u["column"],
                                                    u["construct"], u["reason"]))
    if inst.swift:
        out.write("Swift limit: %s\n" % SWIFT_LIMIT)
    out.write("Summary: %s\n" % summary_line(inst.summary()))


def cmd_function(args):
    sources = Sources()
    inputs = Inputs(args)
    spec = Spec(args.spec, args.file)
    accept = args.accept_uncheckable
    instances = find_function(inputs, spec, open_codedb(args), sources)
    instances = merge_identical(instances, inputs)
    union = None
    if not instances:
        inputs.problems.append("%s was not found in the profile's binaries (%s)"
                               % (args.spec, ", ".join(os.path.basename(b) for b in inputs.binaries)))
        verdict = "incomplete: the function was not found"
    elif len(instances) == 1:
        verdict = instances[0].verdict(accept)
    else:
        nbin = len({b for i in instances for b in i.binaries})
        if nbin > 1:
            inputs.problems.append("%s has instances with different counts in %d binaries; each is reported, "
                                   "then their union" % (args.spec, nbin))
        else:
            inputs.problems.append("%s has %d instances with different counts (a function compiled into several "
                                   "translation units, or several functions by that name); each is reported, "
                                   "then their union" % (args.spec, len(instances)))
        union = union_of(instances)
        items = ["%s at line %d" % (c[2], c[0]) for c in union["unexercised_cases"]]
        items += ["line %d col %d %s" % tuple(o) for o in union["unexercised"]]
        items += ["region at line %d col %d" % tuple(r) for r in union["unexercised_regions"]]
        if not union["executed"]:
            verdict = "not exercised: the function was never executed"
        elif items:
            verdict = "not exercised (union): " + "; ".join(items[:VERDICT_LIST_LIMIT]) + (
                "; and %d more" % (len(items) - VERDICT_LIST_LIMIT) if len(items) > VERDICT_LIST_LIMIT else "")
        elif union["not_determinable"] or any(i.swift for i in instances):
            verdict = checkable_verdict(union["not_determinable"], accept) + " (union)"
        else:
            verdict = FULL_VERDICT + " (union)"
        verdict += set_aside_note(instances)
    if inputs.problems:
        status = 3
    else:
        statuses = [i.status(accept) for i in instances]
        status = 1 if 1 in statuses else 3 if 3 in statuses else 0
    if args.json:
        json.dump({"spec": args.spec, "profdata": inputs.profdata,
                   "instances": [i.to_json(accept) for i in instances], "union": union,
                   "problems": inputs.problems, "notes": inputs.notes, "verdict": verdict,
                   "status": status}, sys.stdout, indent=1)
        sys.stdout.write("\n")
        return status
    out = sys.stdout
    out.write("Profile: %s\n" % inputs.profdata)
    for n in inputs.notes:
        out.write("Note: %s\n" % n)
    for i, inst in enumerate(instances):
        if i:
            out.write("\n")
        print_instance(inst, sources, args.max_lines, out, args.verbose)
        if len(instances) > 1:
            out.write("Instance verdict: %s\n" % inst.verdict(accept))
    if union:
        out.write("\nUnion of %d instances: branches %d/%d (outcomes), case labels %d/%d\n"
                  % (len(instances), union["branches_covered"], union["branches_total"],
                     union["cases_covered"], union["cases_total"]))
    for p in inputs.problems:
        out.write("Incomplete: %s\n" % p)
    out.write("Verdict: %s\n" % verdict)
    return status


def file_rows(inputs, path, sources):
    rows = []
    found = False
    for binary in inputs.binaries:
        fobj, recs = records_in_file(binary, inputs.profdata, path)
        if not recs:
            continue
        found = True
        inputs.check_source(path, binary)
        folds = folded_branches(binary, inputs.profdata, path)
        for rec, includes in group_with_includes(recs):
            inst = Instance(binary, rec, includes, fobj["segments"] if fobj else None, folds, sources,
                            inputs.ignored_macros)
            inputs.check_instance(inst, binary)
            rows.append(inst)
    return found, rows


def cmd_file(args):
    sources = Sources()
    inputs = Inputs(args)
    accept = args.accept_uncheckable
    path = os.path.abspath(args.path)
    found, rows = file_rows(inputs, path, sources)
    rows = merge_identical(rows, inputs)
    if not found:
        inputs.problems.append("%s is in none of the profile's binaries" % path)
    if len({b for r in rows for b in r.binaries}) > 1:
        inputs.problems.append("%s is compiled into several binaries with different counts; rows are per binary"
                               % path)

    def missed(r):
        return sum(1 for cat, _ in r.unexercised_items() if cat != "region")

    def key(r):
        return (-missed(r), r.start_line, r.name)
    rows.sort(key=key)
    statuses = [r.status(accept) for r in rows]
    status = 3 if inputs.problems else 1 if 1 in statuses else 3 if 3 in statuses else 0
    data = []
    for r in rows:
        s = r.summary()
        s.update({"name": r.name, "binary": r.binaries[0], "start_line": r.start_line, "end_line": r.end_line,
                  "count": r.count,
                  "unexercised_branches": sum(len(b["unexercised"]) for b in r.branches),
                  "unexercised_cases": sum(1 for c in r.cases if c["taken"] == 0),
                  "unexercised_conditions": sum(len(d["unexercised"]) for d in r.derived),
                  "unexercised_regions": len(r.unexercised_regions()), "full": r.full(),
                  "status": r.status(accept)})
        data.append(s)
    if args.json:
        json.dump({"file": path, "functions": data, "problems": inputs.problems, "notes": inputs.notes,
                   "status": status}, sys.stdout, indent=1)
        sys.stdout.write("\n")
        return status
    out = sys.stdout
    out.write("%-8s %-8s %-11s %-11s %-11s %-9s %-7s %s\n" % ("missed", "count", "lines", "regions", "branches",
                                                              "cases", "unknown", "function (line)"))
    for s in data:
        out.write("%-8d %-8d %-11s %-11s %-11s %-9s %-7d %s (%d)\n" % (
            s["unexercised_branches"] + s["unexercised_cases"] + s["unexercised_conditions"], s["count"],
            "%d/%d" % (s["lines_covered"], s["lines_total"]),
            "%d/%d" % (s["regions_covered"], s["regions_total"]),
            "%d/%d" % (s["branches_covered"], s["branches_total"]),
            "%d/%d" % (s["cases_covered"], s["cases_total"]), s["not_determinable"], s["name"], s["start_line"]))
    for n in inputs.notes:
        out.write("Note: %s\n" % n)
    for p in inputs.problems:
        out.write("Incomplete: %s\n" % p)
    if any(r.swift for r in rows):
        out.write("Swift limit: %s\n" % SWIFT_LIMIT)
    full = sum(1 for s in data if s["status"] == 0)
    unknown = sum(1 for s in data if s["full"] and s["status"] == 3)
    out.write("%d of %d functions have every %scase label and branch exercised%s\n" % (
        full, len(data), "checkable " if accept or any(r.swift for r in rows) else "",
        "; %d more have constructs that could not be checked (column unknown)" % unknown if unknown else ""))
    return status


OBSERVER_CAVEAT = ("per-class attribution from an observer run is approximate: work a class leaves running is "
                   "counted for the class that follows, and work the app's launch leaves running is counted for "
                   "whichever class is running when it happens; use --per-class for a per-class verdict")
LAUNCH_PSEUDO_CLASS = "_launch"


def cmd_tests_for(args):
    sources = Sources()
    inputs = Inputs(args)
    if not inputs.run:
        raise ToolError("tests-for needs a run directory (--run) with per-class profiles")
    classes_dir = os.path.join(inputs.run, "classes")
    profiles = sorted(f for f in os.listdir(classes_dir) if f.endswith(".profdata")) \
        if os.path.isdir(classes_dir) else []
    if not profiles:
        raise ToolError("%s has no per-class profiles; run coverage_tests.sh --per-class CLASS... or --observer"
                        % classes_dir)
    exact = inputs.route == "per-class"
    if not exact:
        if inputs.route is None:
            inputs.problems.append("the run does not record how its per-class profiles were made (no "
                                   "per_class_route.txt); treated as an observer run")
        inputs.problems.append(OBSERVER_CAVEAT)
    is_file = os.path.isfile(args.target)
    codedb = open_codedb(args)
    spec = None if is_file else Spec(args.target, args.file)
    # Find where the target is with the whole-run profile, then read only
    # those binaries with each class's profile.
    if is_file:
        found, rows = file_rows(inputs, os.path.abspath(args.target), sources)
        binaries = sorted({b for r in rows for b in r.binaries})
    else:
        rows = find_function(inputs, spec, codedb, sources)
        binaries = sorted({b for r in rows for b in r.binaries})
    if not rows:
        raise ToolError("%s was not found in the profile's binaries" % args.target)
    result = {}
    for p in profiles:
        cls = p[:-len(".profdata")]
        sub = argparse.Namespace(**vars(args))
        sub.profdata = os.path.join(classes_dir, p)
        sub.binary = binaries
        sub_inputs = Inputs(sub)
        if is_file:
            _, insts = file_rows(sub_inputs, os.path.abspath(args.target), sources)
        else:
            insts = find_function(sub_inputs, spec, codedb, sources)
        exercised, cases, lines = set(), set(), 0
        executed = False
        for inst in insts:
            executed = executed or inst.executed()
            lines += sum(1 for _, c in inst.lines if c)
            for b in inst.branches:
                for o in ("true", "false"):
                    if (o == "true" and b["true_folded"]) or (o == "false" and b["false_folded"]):
                        continue
                    if o == "false" and b.get("false_uncheckable"):
                        continue
                    if o not in b["unexercised"]:
                        exercised.add((b["line"], b["column"], o))
            for c in inst.cases:
                if c["taken"] > 0:
                    cases.add((c["line"], c["label"]))
        result[cls] = {"executed": executed, "lines_executed": lines,
                       "exercised_outcomes": sorted([list(e) for e in exercised]),
                       "cases_taken": sorted([list(c) for c in cases])}
    launch = result.pop(LAUNCH_PSEUDO_CLASS, None)
    executing = sorted(c for c, r in result.items() if r["executed"])
    data = {"target": args.target, "route": inputs.route, "exact": exact,
            "executing" if exact else "may_execute": executing,
            "not_executing": sorted(c for c in result if c not in executing),
            "classes": result, "launch": launch, "problems": inputs.problems}
    status = 3 if inputs.problems else 0
    data["status"] = status
    if args.json:
        json.dump(data, sys.stdout, indent=1)
        sys.stdout.write("\n")
        return status
    out = sys.stdout
    if not exact:
        out.write("Approximate: %s\n" % OBSERVER_CAVEAT)
    out.write("%s %s %d of %d test classes with a profile\n" % (
        args.target, "is executed by" if exact else "may be executed by", len(executing), len(result)))
    for c in executing:
        r = result[c]
        out.write("  %s %s: %d lines, %d branch outcomes, %d case labels\n"
                  % ("executes" if exact else "may execute", c, r["lines_executed"], len(r["exercised_outcomes"]),
                     len(r["cases_taken"])))
    if data["not_executing"]:
        out.write("Not executed by: %s\n" % ", ".join(data["not_executing"]))
    if launch is not None:
        out.write("App launch, before the first class (%s, not a class): %s\n" % (
            LAUNCH_PSEUDO_CLASS, "executed: %d lines" % launch["lines_executed"] if launch["executed"]
            else "not executed"))
    for p in inputs.problems:
        out.write("Incomplete: %s\n" % p)
    return status


def parse_report_row(line, ncols):
    parts = line.split()
    if len(parts) < ncols + 1:
        return None
    return " ".join(parts[:-ncols]), parts[-ncols:]


def scope_files(dirs, inputs):
    """Source files under the directories, as llvm-cov names them: every
    file name in the binaries' coverage mapping that is under one of them."""
    roots = [os.path.join(ROOT, d).rstrip("/") + "/" for d in dirs]
    names = set()
    for binary in inputs.binaries:
        # The files array with -summary-only is small: one summary per file.
        cmd = ["xcrun", "llvm-cov", "export", binary, "-instr-profile=" + inputs.profdata, "-summary-only"]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        def on_file(f):
            if any(f["filename"].startswith(r) for r in roots):
                names.add(f["filename"])
        try:
            stream_export(proc.stdout, on_file, lambda f: None)
        except ToolError:
            pass
        proc.stdout.read()
        err = proc.stderr.read()
        if proc.wait() != 0:
            raise ToolError(describe_llvm_error(err, binary, inputs.profdata))
    return sorted(names)


# llvm-cov report's file table with -show-region-summary and
# -show-branch-summary: regions, missed regions, cover, functions, missed
# functions, executed, lines, missed lines, cover, branches, missed branches,
# cover.
REPORT_FILE_COLUMNS = 12


def report_total(objects, inputs, files):
    """{lines|regions|branches|functions: [covered, total]} from the TOTAL row
    of llvm-cov report on the files, streamed."""
    cmd = ["xcrun", "llvm-cov", "report"] + objects + ["-instr-profile=" + inputs.profdata,
                                                        "-show-region-summary", "-show-branch-summary",
                                                        "--"] + files
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    total = None
    for line in proc.stdout:
        if line.startswith("TOTAL"):
            vals = line.split()[1:]
            if len(vals) == REPORT_FILE_COLUMNS:
                n = [int(v) if v.isdigit() else 0 for v in vals]
                total = {"regions": [n[0] - n[1], n[0]], "functions": [n[3] - n[4], n[3]],
                         "lines": [n[6] - n[7], n[6]], "branches": [n[9] - n[10], n[9]]}
    err = proc.stderr.read()
    if proc.wait() != 0 or total is None:
        raise ToolError(describe_llvm_error(err or "no TOTAL row", " ".join(inputs.binaries), inputs.profdata))
    return total


def cmd_scope(args):
    inputs = Inputs(args)
    dirs = args.dirs or list(SCOPE_DIRS)
    files = scope_files(dirs, inputs)
    if not files:
        raise ToolError("no instrumented source files under %s" % ", ".join(dirs))
    objects = []
    for b in inputs.binaries:
        objects += ["-object", b] if objects else [b]
    # Totals per directory and overall: the TOTAL row of llvm-cov report on
    # each directory's files. (Its per-file rows name files relative to their
    # common directory, so rows are not mapped back to directories.)
    totals = {}
    groups = [(d, [f for f in files if os.path.relpath(f, ROOT).startswith(d)]) for d in dirs]
    groups.append(("TOTAL", files))
    for key, group in groups:
        if group:
            totals[key] = report_total(objects, inputs, group)
    # Functions with the most unexercised branch outcomes, from
    # llvm-cov report -show-functions, file by file in batches.
    top = []
    batch = 200
    for i in range(0, len(files), batch):
        cmd = ["xcrun", "llvm-cov", "report"] + objects + ["-instr-profile=" + inputs.profdata,
                                                            "-show-functions", "-show-branch-summary",
                                                            "-show-region-summary", "--"] + files[i:i + batch]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        cols = None
        current = None
        for line in proc.stdout:
            line = line.rstrip("\n")
            if line.startswith("File '"):
                current = line[6:line.rfind("'")]
                cols = None
                continue
            if line.startswith("Name ") and "Regions" in line:
                cols = line.split()[1:]
                continue
            if cols is None or not line.strip() or line.startswith("-") or line.startswith("TOTAL"):
                continue
            row = parse_report_row(line, len(cols))
            if row is None:
                continue
            name, vals = row
            idx = {c: j for j, c in enumerate(cols)}
            try:
                bt = int(vals[idx["Branches"]])
                bm = int(vals[idx["Branches"] + 1])
                lt = int(vals[idx["Lines"]])
            except (KeyError, ValueError, IndexError):
                continue
            if bm:
                top.append((bm, bt, lt, base_name(name), os.path.relpath(current, ROOT) if current else "?"))
                top.sort(key=lambda x: (-x[0], x[3]))
                del top[args.top * 3:]
        err = proc.stderr.read()
        if proc.wait() != 0:
            raise ToolError(describe_llvm_error(err, " ".join(inputs.binaries), inputs.profdata))
    # A function can appear once per binary; keep the first.
    seen, best = set(), []
    for t in top:
        if (t[3], t[4]) in seen:
            continue
        seen.add((t[3], t[4]))
        best.append(t)
    best = best[:args.top]
    if args.json:
        json.dump({"dirs": dirs, "files": len(files), "totals": totals,
                   "top": [{"missed_branches": t[0], "branches": t[1], "lines": t[2], "name": t[3], "file": t[4]}
                           for t in best], "problems": inputs.problems}, sys.stdout, indent=1)
        sys.stdout.write("\n")
        return 3 if inputs.problems else 0
    out = sys.stdout

    def pct(p):
        return "%5.1f%%" % (100.0 * p[0] / p[1]) if p[1] else "    -"
    out.write("Instrumented files in scope: %d\n" % len(files))
    out.write("%-32s %-22s %-22s %-22s\n" % ("directory", "lines", "regions", "branches"))
    for k in [d for d in dirs if d in totals] + ["TOTAL"]:
        t = totals[k]
        out.write("%-32s %-22s %-22s %-22s\n" % (
            k, "%d/%d %s" % (t["lines"][0], t["lines"][1], pct(t["lines"])),
            "%d/%d %s" % (t["regions"][0], t["regions"][1], pct(t["regions"])),
            "%d/%d %s" % (t["branches"][0], t["branches"][1], pct(t["branches"]))))
    out.write("\nTop %d functions by unexercised branch outcomes (llvm-cov's count: blocks are separate, a case "
              "label is two outcomes):\n" % args.top)
    for t in best:
        out.write("%6d of %-6d  %6d lines  %s  (%s)\n" % (t[0], t[1], t[2], t[3], t[4]))
    for p in inputs.problems:
        out.write("Incomplete: %s\n" % p)
    return 3 if inputs.problems else 0


def cmd_log_executed(args):
    import sanitizer_summary
    counts = sanitizer_summary.count_tests(args.log)
    print(counts["executed"])
    return 0 if counts["executed"] else 1


def cmd_log_status(args):
    import sanitizer_summary
    counts = sanitizer_summary.count_tests(args.log)
    print(1 if (counts["failed"] or counts["crashed"] or not counts["executed"]) else 0)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="coverage_report.py", description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=None)
    sub = ap.add_subparsers(dest="command", required=True)

    def common(p):
        p.add_argument("--run")
        p.add_argument("--profdata")
        p.add_argument("--binary", action="append")
        p.add_argument("--codedb")
        p.add_argument("--no-codedb", action="store_true")
        p.add_argument("--json", action="store_true")
        p.add_argument("--file")
        p.add_argument("--ignore-macro", action="append")
        p.add_argument("--set-aside-macro", action="append", dest="ignore_macro")
        p.add_argument("--no-default-ignores", action="store_true")
        p.add_argument("--accept-uncheckable", action="store_true")
        p.add_argument("--verbose", action="store_true")

    p = sub.add_parser("function")
    p.add_argument("spec")
    p.add_argument("--max-lines", type=int)
    common(p)
    p = sub.add_parser("file")
    p.add_argument("path")
    common(p)
    p = sub.add_parser("tests-for")
    p.add_argument("target")
    common(p)
    p = sub.add_parser("scope")
    p.add_argument("dirs", nargs="*")
    p.add_argument("--top", type=int, default=20)
    common(p)
    p = sub.add_parser("log-executed")
    p.add_argument("log")
    p = sub.add_parser("log-status")
    p.add_argument("log")
    if argv is None and len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    args = ap.parse_args(argv)
    try:
        return {"function": cmd_function, "file": cmd_file, "tests-for": cmd_tests_for, "scope": cmd_scope,
                "log-executed": cmd_log_executed, "log-status": cmd_log_status}[args.command](args)
    except ToolError as e:
        sys.stderr.write("coverage_report.py: error: %s\n" % e)
        return 2
    except BrokenPipeError:
        return 2


if __name__ == "__main__":
    sys.exit(main())
