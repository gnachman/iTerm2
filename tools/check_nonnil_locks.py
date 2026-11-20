#!/usr/bin/env python3
"""Pre-commit guard: block adding an @synchronized whose lock could be nil.

@synchronized(nil) runs its block with no lock and no error. The macro
ITNonnilLock(expr) in sources/Logging/DebugLogging.h evaluates the lock
expression once, fails a beta assertion if it is nil, and yields the same
object to lock (docs/swift-migration/concurrency.md, section 2). The owner
decided that new sites must use it and that a commit hook enforces this
(docs/swift-migration/decisions.md, 2026-11-20).

THE RULE

An added or changed @synchronized statement is reported unless its lock
expression is one of:

  self
  a class object: [self class], self.class, [Foo class], Foo.class,
    [Foo self], where Foo is a class name (an identifier that begins with an
    upper-case letter or with "iTerm"; a lower-case receiver such as
    [obj class] can be nil and is reported)
  ITNonnilLock(...)

Redundant parentheses around the whole expression are ignored. When the
expression has a comma outside parentheses ([NSArray arrayWithObjects:a,
b, nil]) the printed fix adds a pair, ITNonnilLock((expr)), because the
preprocessor would otherwise split it into several macro arguments. Everything
else must be wrapped, including statics, globals, locals and parameters:
some of those can be nil, and wrapping is always harmless.
object_getClass(...) and [super class] are not accepted forms.

Escape hatch: a line comment beginning "nonnil-lock-ok:" followed by a
non-empty reason, on the line that holds the @synchronized keyword, as in
    @synchronized(object) {  // nonnil-lock-ok: tests the nil path
suppresses the report. Without a reason it does not.

WHICH LINES COUNT AS ADDED

The diff is read with whitespace ignored (git diff -w) and with rename
detection on (-M). A statement is checked when any physical line from its
@synchronized keyword to the parenthesis that closes its lock expression is
an added line of that diff. So:
  - a line whose only change is whitespace (reindenting, a space before the
    parenthesis) does not count;
  - any other change to such a line counts, including a change to code after
    the lock expression on the same line (a one-line body);
  - lines moved within or between files count as added;
  - a rename with no content change adds nothing;
  - a new or copied file is all added lines.
The diff options are all given explicitly (see DIFF_OPTIONS), so a user's
diff configuration or attributes do not change which lines count. Gitlinks
and symbolic links are skipped. Paths come from git diff --raw -z, so any
file name works.
The full statement is read from the copy of the file being checked (the
staged blob, or the one at B with --range), so an expression that opens on an unchanged line and continues on a
changed one is read whole.

WHICH FILES

Objective-C sources (.m, .mm, .h) under sources/, ThirdParty/PSMTabBarControl/
and ModernTests/. Those are compiled into targets that link DebugLogging.m
(iTerm2SharedARC, iTerm2Shared, and the test bundle). Not checked:
  - pidinfo/, iTerm2SandboxedWorker/, ShellLauncher/, SignedArchive/,
    ColorPicker/, SearchableComboListView/, BetterFontPicker/, the rest of
    ThirdParty/, submodules/, and tools/ (their fixtures): the macro is not
    available there, or the code is not the owner's;
  - HELPER_SHARED_FILES below: files under sources/ that are also compiled
    into pidinfo or iTerm2SandboxedWorker, which do not link DebugLogging.m,
    so the prescribed fix would not link there;
  - C, C++ and Swift files.
Test code is checked: a nil lock in a test is also a bug. A new test that
means to lock on nil uses the escape hatch. ModernTests/NonnilLockTests.m
has two deliberate plain @synchronized(object) sites (lines 89 and 116)
without it; they are reported only if their lines change, and --all
reports them.

LIMITS

Comments, string literals (including @"..." and C++ raw strings) and
character literals are removed by a small lexer before matching, so text in
them never matches. Preprocessor conditionals are not evaluated: a site
inside #if 0 is still checked. A macro that expands to @synchronized is out
of reach of a text check: only the literal keyword is seen. Whether Foo in
[Foo class] is really a class is decided by its spelling, not by type.

MODES

  (default)        check the staged change (git diff --cached)
  --range A..B     check the change from A to B, reading files at B (HEAD if
                   B is empty); for the migration gate, which runs it
                   whether or not hooks are enabled
  --all            treat every line of every covered file in the index as
                   added: a report on the whole tree
  --summary        also print counts of sites by kind

Exit 0 = clean; 1 = findings; 2 = error (git failure, unreadable file). The
pre-commit hook blocks on 2 as well, so a broken checker cannot silently
pass a commit; bypass deliberately with git commit --no-verify and report
the failure.
"""

import argparse
import re
import subprocess
import sys

COVERED_PREFIXES = ("sources/", "ThirdParty/PSMTabBarControl/", "ModernTests/")
OBJC_SUFFIXES = (".m", ".mm", ".h")

# Files under sources/ that iTerm2.xcodeproj also compiles into pidinfo or
# iTerm2SandboxedWorker. Neither target compiles DebugLogging.m, and
# ITNonnilLock expands to ITBetaAssert, which calls LogForNextCrash from it.
# Checked against the project by test_check_nonnil_locks.py.
HELPER_SHARED_FILES = frozenset([
    "sources/Common/NSArray+CommonAdditions.m",
    "sources/Common/NSFileManager+CommonAdditions.m",
    "sources/Common/NSString+CommonAdditions.m",
    "sources/FixBrokenAppleCrap/iTermAutoMasterParser.m",
    "sources/InlineImages/iTermImage.m",
    "sources/Infrastructure/iTermCancelable.m",
    "sources/SemanticHistory/iTermPathCleaner.m",
    "sources/SemanticHistory/iTermPathFinder.m",
    "sources/StatusBar/Components/iTermGitState.m",
    "sources/System/iTermOpenDirectory.m",
    "sources/XPC/iTermSandboxedWorkerClient.m",
])

HATCH = "nonnil-lock-ok:"


class CheckError(Exception):
    pass


def is_covered(path):
    return (path.startswith(COVERED_PREFIXES)
            and path.endswith(OBJC_SUFFIXES)
            and path not in HELPER_SHARED_FILES)


_TOP = None


def _top():
    """The top of the working tree. Every git command runs there, because the
    paths git reports are relative to it and are passed back as pathspecs."""
    global _TOP
    if _TOP is None:
        try:
            r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True)
        except OSError as e:
            raise CheckError("cannot run git: %s" % e)
        top = r.stdout.decode("utf-8", "replace").rstrip("\n")
        if r.returncode != 0 or not top:
            raise CheckError("not in a git working tree: %s"
                             % r.stderr.decode("utf-8", "replace").strip())
        _TOP = top
    return _TOP


def git(args, binary=False):
    try:
        r = subprocess.run(["git", "--literal-pathspecs", "-c", "core.quotePath=false"] + args,
                           capture_output=True, cwd=_top())
    except OSError as e:
        raise CheckError("cannot run git: %s" % e)
    if r.returncode != 0:
        raise CheckError("git %s failed (exit %d): %s" % (
            " ".join(args), r.returncode,
            r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


# ---------------------------------------------------------------------------
# Lexer: blank comments and literals, keep offsets and newlines.

_START = re.compile(r'//|/\*|"|\'')
_LINE_COMMENT = re.compile(r'//(?:[^\\\n]|\\[\s\S])*')
_BLOCK_COMMENT = re.compile(r'/\*[\s\S]*?(?:\*/|\Z)')
_STRING = re.compile(r'"(?:[^"\\\n]|\\[\s\S])*"?')
_CHAR = re.compile(r"'(?:[^'\\\n]|\\[\s\S])*'?")
_RAW_PREFIX = re.compile(r'(?:u8|[LuU])?R$')


def _ident_before(text, index):
    """The identifier characters that end at index, at most four of them;
    longer runs are returned as four characters, enough to tell a literal
    prefix (L, u, U, u8, R, LR, uR, UR, u8R) from anything else."""
    begin = index
    while begin > 0 and index - begin < 5 and (text[begin - 1].isalnum() or text[begin - 1] == "_"):
        begin -= 1
    return text[begin:index]


def _blank(s):
    return re.sub(r'[^\n]', ' ', s)


def lex(text):
    """Return (code, uncommented, line_comments).

    code is text with every comment replaced by spaces and the inside of
    every string and character literal replaced by spaces (delimiters kept).
    uncommented is text with only the comments replaced by spaces. Both keep
    newlines, so offsets and line numbers are unchanged. line_comments is
    a list of (offset, text) for every // comment.
    """
    code = []
    plain = []
    comments = []
    pos = 0
    n = len(text)

    def keep(chunk):
        code.append(chunk)
        plain.append(chunk)

    while pos < n:
        m = _START.search(text, pos)
        if not m:
            keep(text[pos:])
            break
        start = m.start()
        tok = m.group(0)
        if tok in ("//", "/*"):
            keep(text[pos:start])
            end = (_LINE_COMMENT if tok == "//" else _BLOCK_COMMENT).match(text, start).end()
            if tok == "//":
                comments.append((start, text[start:end]))
            blank = _blank(text[start:end])
            code.append(blank)
            plain.append(blank)
            pos = end
            continue
        keep(text[pos:start])
        ident = _ident_before(text, start)
        if tok == "'" and ident and ident not in ("L", "u", "U", "u8"):
            # A digit separator (1'000) or other non-literal use.
            keep(tok)
            pos = start + 1
            continue
        end = None
        if tok == '"' and _RAW_PREFIX.search(ident):
            end = _raw_string_end(text, start)
        if end is None:
            end = start + len((_STRING if tok == '"' else _CHAR).match(text, start).group(0))
        lit = text[start:end]
        terminated = len(lit) > 1 and lit[-1] == tok
        inner = lit[1:-1] if terminated else lit[1:]
        code.append(tok + _blank(inner) + (tok if terminated else ""))
        plain.append(lit)
        pos = end
    return "".join(code), "".join(plain), comments


def _raw_string_end(text, quote):
    """For R"delim( ... )delim" with the quote at index quote, return the
    index after the closing quote, or None if it is not a raw string."""
    m = re.compile(r'"([^()\\\s]{0,16})\(').match(text, quote)
    if not m:
        return None
    terminator = ")" + m.group(1) + '"'
    end = text.find(terminator, m.end())
    if end < 0:
        return len(text)
    return end + len(terminator)


# ---------------------------------------------------------------------------
# Sites

_SYNC = re.compile(r'@synchronized\b')
_CLOSERS = {")": "(", "]": "[", "}": "{"}


class Site(object):
    def __init__(self, line, end_line, expr, kind, reason=None):
        self.line = line
        self.end_line = end_line
        self.expr = expr          # normalized original text, or None
        self.kind = kind          # self, class, wrapped, hatch, unparsed, unwrapped, emptyhatch
        self.reason = reason
        self.top_level_comma = False  # set when the expression has a comma outside parentheses


def _line_of(starts, offset):
    lo, hi = 0, len(starts)
    while lo + 1 < hi:
        mid = (lo + hi) // 2
        if starts[mid] <= offset:
            lo = mid
        else:
            hi = mid
    return lo + 1


def _matching_close(code, open_index):
    """Index of the bracket that closes the one at open_index, or None."""
    stack = []
    for i in range(open_index, len(code)):
        c = code[i]
        if c in "([{":
            stack.append(c)
        elif c in _CLOSERS:
            if not stack or stack[-1] != _CLOSERS[c]:
                return None
            stack.pop()
            if not stack:
                return i
    return None


_CLASS_NAME = r'(?:[A-Z][A-Za-z0-9_]*|iTerm[A-Za-z0-9_]*)'
_CLASS_FORMS = [re.compile(p + r'\Z') for p in (
    r'self',
    r'\[self class\]',
    r'self\.class',
    r'\[' + _CLASS_NAME + r' class\]',
    _CLASS_NAME + r'\.class',
    r'\[' + _CLASS_NAME + r' self\]',
)]


def _squeeze(s):
    s = re.sub(r'\s+', ' ', s).strip()
    return re.sub(r' ?([\[\]().]) ?', r'\1', s).replace("] ", "]")


def _strip_parens(s):
    while s.startswith("(") and _matching_close(s, 0) == len(s) - 1:
        s = s[1:-1].strip()
    return s


def classify(code_expr):
    """Kind of a lock expression, given its lexed text (literals blanked)."""
    s = _strip_parens(_squeeze(code_expr))
    if s == "self":
        return "self"
    for form in _CLASS_FORMS[1:]:
        if form.match(s):
            return "class"
    m = re.match(r'ITNonnilLock ?\(', s)
    if m:
        close = _matching_close(s, m.end() - 1)
        if close == len(s) - 1 and s[m.end():close].strip():
            return "wrapped"
    return "unwrapped"


def find_sites(text):
    code, plain, comment_list = lex(text)
    starts = [0] + [m.end() for m in re.finditer(r'\n', code)]
    comments = {}
    for offset, body in comment_list:
        comments.setdefault(_line_of(starts, offset), []).append(body)
    sites = []
    for m in _SYNC.finditer(code):
        line = _line_of(starts, m.start())
        reason = None
        for c in comments.get(line, []):
            body = c[2:].strip()
            if body.startswith(HATCH):
                reason = body[len(HATCH):].strip()
        p = m.end()
        while p < len(code) and code[p].isspace():
            p += 1
        close = _matching_close(code, p) if p < len(code) and code[p] == "(" else None
        if close is None:
            end_line = _line_of(starts, min(p, len(code) - 1)) if code else line
            kind, expr = "unparsed", None
        else:
            end_line = _line_of(starts, close)
            expr = re.sub(r'\s+', ' ', plain[p + 1:close]).strip()
            kind = classify(code[p + 1:close])
        if kind in ("unwrapped", "unparsed") and reason is not None:
            kind = "hatch" if reason else "emptyhatch"
        site = Site(line, end_line, expr, kind, reason)
        if close is not None:
            site.top_level_comma = _has_top_level_comma(code[p + 1:close])
        sites.append(site)
    return sites, plain


def _has_top_level_comma(code_expr):
    """True if the preprocessor would split the expression into several
    macro arguments: a comma outside every pair of parentheses (brackets and
    braces do not protect it)."""
    depth = 0
    for c in code_expr:
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif c == "," and depth == 0:
            return True
    return False


IMPORT_RE = re.compile(r'^\s*#\s*(?:import|include)\s*[<"](?:[^">]*/)?DebugLogging\.h[">]', re.M)


# ---------------------------------------------------------------------------
# Diffs

_HUNK = re.compile(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@')

# Every option a user's configuration or attributes could otherwise change,
# so that "added line" means the same thing in every checkout: no external
# diff, textconv or color; every file treated as text (a -diff attribute must
# not hide one); whitespace ignored; no context and no merging of nearby hunks
# (diff.context, diff.interHunkContext); rename detection on with no limit
# (diff.renames, diff.renameLimit); one algorithm (diff.algorithm); paths from
# the top (diff.relative); no order file (diff.orderFile); submodules not
# listed (diff.ignoreSubmodules). Paths are never parsed from patch text.
DIFF_OPTIONS = ["--no-color", "--no-ext-diff", "--no-textconv", "--text", "--no-relative",
                "-U0", "--inter-hunk-context=0", "-w", "-M", "-l0",
                "--diff-algorithm=myers", "--indent-heuristic", "-O/dev/null",
                "--ignore-submodules=all"]
BLOB_MODES = ("100644", "100755")


def changed_files(diff_args):
    """Yield (old path, new path, new blob id) for every added, copied,
    modified or renamed regular file, from git diff --raw -z."""
    # -U0 would add the patch to the --raw listing.
    options = [o for o in DIFF_OPTIONS if o != "-U0"]
    out = git(["diff", "--raw", "-z", "--no-abbrev", "--diff-filter=ACMRT"]
              + options + diff_args, binary=True)
    fields = out.split(b"\0")
    i = 0
    while i < len(fields):
        meta = fields[i].decode("utf-8", "replace")
        i += 1
        if not meta:
            continue
        if not meta.startswith(":"):
            raise CheckError("cannot read git diff --raw output near %r" % meta)
        _, new_mode, _, new_sha, status = meta[1:].split()
        old = fields[i].decode("utf-8", "replace")
        i += 1
        new = old
        if status[:1] in ("R", "C"):
            new = fields[i].decode("utf-8", "replace")
            i += 1
        if new_mode in BLOB_MODES and set(new_sha) != {"0"}:
            yield old, new, new_sha


def added_lines(diff_args, old, new):
    """Added line numbers in the new file of one file pair."""
    paths = [old] if old == new else [old, new]
    out = git(["diff"] + DIFF_OPTIONS + diff_args + ["--"] + paths)
    lines = set()
    for line in out.split("\n"):
        m = _HUNK.match(line)
        if m:
            first = int(m.group(1))
            count = 1 if m.group(2) is None else int(m.group(2))
            lines.update(range(first, first + count))
    return lines


def read_blob(sha):
    return git(["cat-file", "blob", sha], binary=True).decode("utf-8", "replace")


def index_blobs():
    """Yield (path, text) for every covered file in the index, one at a
    time, through a single git cat-file --batch process."""
    listing = git(["ls-files", "-z", "--cached", "--stage"], binary=True)
    entries = []
    for record in listing.split(b"\0"):
        if not record:
            continue
        meta, path = record.split(b"\t", 1)
        mode, sha, stage = meta.decode().split()
        path = path.decode("utf-8", "replace")
        if stage in ("0", "2") and mode.startswith("100") and is_covered(path):
            entries.append((path, sha))
    entries.sort()
    try:
        proc = subprocess.Popen(["git", "cat-file", "--batch"],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    except OSError as e:
        raise CheckError("cannot run git: %s" % e)
    try:
        for path, sha in entries:
            proc.stdin.write(sha.encode() + b"\n")
            proc.stdin.flush()
            header = proc.stdout.readline().split()
            if len(header) != 3:
                raise CheckError("git cat-file could not read %s (%s)" % (
                    path, b" ".join(header).decode("utf-8", "replace")))
            size = int(header[2])
            data = proc.stdout.read(size + 1)[:size]
            yield path, data.decode("utf-8", "replace")
    finally:
        proc.stdin.close()
        proc.stdout.close()
        if proc.wait() != 0:
            raise CheckError("git cat-file --batch failed (exit %d)" % proc.returncode)


# ---------------------------------------------------------------------------
# Report

def check_text(path, text, lines):
    """Findings and all sites for one file. lines is a set, or None for all."""
    findings = []
    sites, plain = find_sites(text)
    has_import = IMPORT_RE.search(plain) is not None
    for s in sites:
        touched = lines is None or any(l in lines for l in range(s.line, s.end_line + 1))
        s.touched = touched
        if touched and s.kind in ("unwrapped", "unparsed", "emptyhatch"):
            findings.append(_message(path, s, has_import))
    return findings, sites


def _message(path, s, has_import):
    loc = "%s:%d" % (path, s.line)
    if s.kind == "unparsed":
        return ("%s: cannot read the lock expression of this @synchronized (no balanced "
                "parenthesis after the keyword). Wrap it as @synchronized(ITNonnilLock(...)) "
                "or add // %s <reason>." % (loc, HATCH))
    lines = []
    if s.kind == "emptyhatch":
        lines.append("%s: \"// %s\" needs a reason after the colon; lock `%s`." % (loc, HATCH, s.expr))
    else:
        lines.append("%s: @synchronized(%s) locks on something that is not self, a class "
                     "object, or ITNonnilLock(...)." % (loc, s.expr))
    # A comma outside parentheses would split the macro's argument.
    wrapped = "(%s)" % s.expr if s.top_level_comma else s.expr
    lines.append("    Fix: @synchronized(ITNonnilLock(%s))" % wrapped)
    if not has_import:
        lines.append("    %s does not import DebugLogging.h directly: add #import \"DebugLogging.h\" "
                     "unless another header already brings it in." % path)
    return "\n".join(lines)


FOOTER = """\
@synchronized(nil) runs its block with no lock and no error. A new or changed
@synchronized must lock on self, a class object ([Foo class], Foo.class,
[self class], self.class, [Foo self]), or ITNonnilLock(expr). That includes
statics, globals, locals and parameters: some can be nil, and wrapping is
always harmless. If the lock is meant to be nil (a test of the nil path), add
a trailing comment on the @synchronized line: // nonnil-lock-ok: <reason>
See docs/swift-migration/concurrency.md, section 2."""


def _files(mode, rng):
    """Yield (path, text, added line numbers or None for all lines)."""
    if mode == "all":
        git(["rev-parse", "--git-dir"])
        for path, text in index_blobs():
            yield path, text, None
        return
    if mode == "range":
        if ".." not in rng or "..." in rng:
            raise CheckError("--range takes A..B, got %r" % rng)
        base, tip = rng.split("..", 1)
        tip = tip or "HEAD"
        for rev in (base, tip):
            git(["rev-parse", "--verify", "--quiet", rev + "^{commit}"])
        diff_args = [base, tip]
    else:
        git(["rev-parse", "--git-dir"])
        diff_args = ["--cached"]
    for old, new, sha in sorted(changed_files(diff_args)):
        if is_covered(new):
            yield new, read_blob(sha), added_lines(diff_args, old, new)


def run(mode, rng, summary, out, err):
    findings = []
    counts = {}
    try:
        for path, text, lines in _files(mode, rng):
            f, sites = check_text(path, text, lines)
            findings.extend(f)
            for site in sites:
                if site.touched:
                    counts[site.kind] = counts.get(site.kind, 0) + 1
    except CheckError as e:
        err.write("check_nonnil_locks: error: %s\n" % e)
        err.write("check_nonnil_locks: nothing was checked. If this blocks a commit, bypass it "
                  "deliberately with git commit --no-verify and report the failure.\n")
        return 2
    if summary:
        total = sum(counts.values())
        out.write("sites checked: %d\n" % total)
        for kind in ("self", "class", "wrapped", "hatch", "unwrapped", "emptyhatch", "unparsed"):
            out.write("  %-10s %d\n" % (kind, counts.get(kind, 0)))
    if findings:
        for f in findings:
            err.write(f + "\n")
        err.write("\n%d @synchronized site%s need%s ITNonnilLock.\n%s\n" % (
            len(findings), "" if len(findings) == 1 else "s",
            "s" if len(findings) == 1 else "", FOOTER))
        return 1
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--all", action="store_true", help="check every covered file in the index")
    g.add_argument("--range", metavar="A..B", help="check the change from A to B")
    ap.add_argument("--summary", action="store_true", help="print counts of sites by kind")
    args = ap.parse_args(argv)
    mode = "all" if args.all else ("range" if args.range else "staged")
    return run(mode, args.range, args.summary, sys.stdout, sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
