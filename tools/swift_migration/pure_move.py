#!/usr/bin/env python3
"""Checks that a change only moves lines.

Part of the Objective-C to Swift migration (docs/swift-migration/large-code.md
section 2.2, and orchestration.md section 9). An `extract` commit moves a block
of an oversized function into a new function, verbatim, and a port of a large
file moves methods between files. This tool checks that the lines its check
covers were moved unchanged, apart from lines the author declares as new (the
new function's signature, its braces, and the call that replaces the moved
block), which it lists and does not check. Everything else is listed as
path:line. A pass means that the change is probably a pure move. A failure
does not mean that the change is wrong; it means that this tool cannot confirm
it and more analysis is needed.

It has two modes.

The extraction mode (--extract) is for extract commits. The author declares
each moved block by its old and new line ranges, and the tool checks, from
the file contents and not from a diff, that each block matches its
destination line by line and that everything outside the blocks and the
declared lines is unchanged. It does not depend on where git draws hunk
boundaries, so it judges an extraction into the same file correctly.

The pairing mode (no --extract) pairs every removed line of the diff with an
added line of the same text. It is for changes that move methods between
files without declaring ranges. It cannot judge an extraction whose
destination is in the same file: a diff may show part of the moved block as
unchanged lines, and a reordering inside the block is then invisible.

Usage:
    pure_move.py REV                  a commit against its parent
    pure_move.py --staged             HEAD against the index
    pure_move.py OLD NEW              one commit against another
  options:
    --extract OLDPATH:A-B=NEWPATH:C-D declare that old lines A-B of OLDPATH
                                      moved and are new lines C-D of NEWPATH
    --allow-added PATH:N[-M]          declare new-side lines as new code
    --allow-removed PATH:N[-M]        declare old-side lines as removed code
    --strict-runs                     pairing mode only: run notices are
                                      failures
    --show-lines                      list every changed file with the old and
                                      new line number of each line, to write
                                      declarations from; checks nothing
    --repo DIR                        the repository (default: current dir)
    --json                            machine-readable output

--extract, --allow-added and --allow-removed may be repeated. PATH is the path
in the repository as git prints it; line numbers are those of the old (or
new) content. A single line may be written N instead of N-N. A PATH that
begins with a dash must be written --allow-added=PATH:N (or
--allow-removed=PATH:N, --extract=OLDPATH:A-B=NEWPATH:C-D), or it is read as
an option. Declared lines are listed and are not checked: the reviewer
confirms that they are only the signature, braces, blank lines and the call
site. Take line numbers from --show-lines, which uses the same diff and the
same contents as the checks, so a declaration copied from it is valid.

Exit status: 0 the lines covered by the check were moved unchanged, and the
change is probably a pure move (or --show-lines listed it); 1 this tool cannot
confirm that the change is a pure move, and more analysis is needed (every
unaccounted line and problem is listed; with --extract, at most 2,000 lines are
listed and the rest are counted); 2 a usage error, a bad declaration, a merge
commit, an unmerged index, a change over a budget, a git failure, or an
unexpected error. Python 3 standard library and git. Writes nothing to disk and runs no
build; run with python3 -B.

The pairing mode and --show-lines need git 2.50 or later (for git
diff-pairs); the extraction mode (--extract) works with older git.

The exact rules are in RULES (pairing mode) and EXTRACT_RULES below and are
printed with every report, as is NOT_CHECKED (or NOT_CHECKED_EXTRACT), the
list of what this tool cannot establish.
"""

import argparse
import bisect
import difflib
import json
import os
import re
import subprocess
import sys
import textwrap
import threading
import unicodedata
from collections import Counter, deque, namedtuple

Line = namedtuple('Line', 'path line text')

REGULAR_MODES = ('100644', '100755')
MAX_BLOB_BYTES = 20 * 1024 * 1024
MAX_CHANGED_LINES = 500000
MAX_CHANGED_FILES = 10000
MAX_TOTAL_BYTES = 128 * 1024 * 1024
MAX_DIFF_PAIRS = 1000000
MAX_LISTED_DECLARATIONS = 20
MAX_LISTED_LINES = 2000


def _count(n):
    return '{:,}'.format(n)


def _mb(n):
    return '%d MB' % (n // (1024 * 1024))


_READING = (
    'Lines come from git objects only, never the working tree. Changed files are listed with '
    'git diff --raw -M (rename detection at git\'s default similarity; copies are not detected), '
    'and file contents are read through one git cat-file --batch process.')

_MATCHING = (
    'Two lines match when they are byte-for-byte equal after removing leading spaces and tabs. '
    'A line of only spaces and tabs matches an empty line. Nothing else is normalized: trailing '
    'whitespace after other text, whitespace inside a line, carriage returns, comments and blank '
    'lines all count.')

_REFUSED = (
    'Never accepted, and reported without their lines being read or compared: renames, type '
    'changes, mode changes, symbolic links, submodules, any mode other than 100644 and 100755, '
    'files over ' + _mb(MAX_BLOB_BYTES) + ', and binary files (a NUL byte in the first 8000 bytes). Also never '
    'accepted: an empty file added or deleted; a change in whether a modified file ends with a '
    'newline when its old and new content are both non-empty; an added or deleted file whose '
    'content does not end with a newline; a modified file whose old content is empty and whose '
    'new content does not end with a newline, or whose new content is empty and whose old '
    'content does not end with a newline; and, in a modified file whose old and new content both '
    'lack the final newline, a last line that is changed (in the pairing mode, a removed or added '
    'line of the diff; with --extract, a line in an extracted or declared range). Each of these '
    'is how a moved line gains or loses its newline.')

_BUDGET_FILES = (
    'The tool checks at most %s changed files (every file git diff --raw lists) and reads at '
    'most %s of file content (the distinct blobs of every changed file whose content is read: '
    'binary files count, and files refused before their content is read, such as renames and '
    'files over %s, do not). A larger change is an error (exit 2) and gets no report.'
    % (_count(MAX_CHANGED_FILES), _mb(MAX_TOTAL_BYTES), _mb(MAX_BLOB_BYTES)))

_BUDGET_LINES = (
    'The pairing mode checks at most %s changed lines: removed plus added lines of the files '
    'whose lines are compared, declared lines included.' % _count(MAX_CHANGED_LINES))

_ERRORS = (
    'An empty diff is not a pure move. A root commit is compared with the empty tree. A merge '
    'commit, an index with unmerged paths, and any git failure are errors (exit 2).')

_DISPLAY = (
    'Text is shown decoded as UTF-8 and escaped so that two different lines are never shown as '
    'the same text: a '
    'backslash as \\\\, an invalid byte as \\xNN (always 80 to ff, since a byte below 80 is '
    'valid), a carriage return as \\r, every other control character (category Cc) except tab '
    'as \\xNN below U+0080 and as \\uNNNN from U+0080 to U+009F, Unicode format characters '
    '(category Cf, such as bidirectional controls and zero-width characters) as \\uNNNN '
    '(\\UNNNNNNNN above U+FFFF), space separators other than U+0020 (category Zs, such as the '
    'no-break space) as \\uNNNN, and each space at the end of a line as \\x20 and each tab at '
    'the end of a line as \\t (a tab elsewhere is shown as itself). Paths in the text report are '
    'shown the same way, and every text field of --json is escaped the same way. Matching uses '
    'the raw bytes.')

_MEANING = (
    'What a result means: a pass means that the lines covered by the check were moved '
    'unchanged, and the change is probably a pure move. A failure does not mean that the '
    'change is wrong; it means that this tool cannot confirm it and more analysis is needed. For '
    'example, an extraction that turns a local variable into a parameter rewrites every use of '
    'it, and is reported as a failure.')

EXIT_STATUS = (
    'Exit status: 0 the lines covered by the check were moved unchanged, and the change is '
    'probably a pure move (or --show-lines listed it). 1 this tool cannot confirm that the change '
    'is a pure move, and more analysis is needed; every unaccounted line and problem is listed '
    '(with --extract, at most %s lines are listed and the rest are counted). 2 a usage error, a '
    'bad declaration, a merge commit, an unmerged index, a change over a budget, a git failure, '
    'or an unexpected error.' % _count(MAX_LISTED_LINES))

GIT_VERSION_NOTE = (
    'Checks that a change only moves lines. The pairing mode and --show-lines need git 2.50 or '
    'later (for git diff-pairs); the extraction mode (--extract) works with older git.')

RULES = [
    _MEANING + ' ' + _READING + ' For a modified file the removed and added lines are those of '
    'git diff-pairs -p -U0 --inter-hunk-context=0 --histogram --indent-heuristic --text '
    'between its old and new blobs, all files in one git process, with textconv filters and '
    'external diff drivers turned off. Each removed and added line must be that line of the old '
    'or new content, and the old content without the removed lines must equal the new content '
    'without the added lines, line for line; otherwise the tool exits 2. An added file '
    'contributes all its lines as added and a deleted file all its lines as removed.',
    _MATCHING,
    'Lines named with --allow-removed or --allow-added are left out of pairing and listed as '
    'declared; they are not checked. Each must be a removed (or added) line of a file whose lines '
    'are compared, or the tool exits 2 and lists up to 20 of the lines that are not. A path that '
    'begins with a dash must be written --allow-added=PATH:N (or --allow-removed=PATH:N).',
    'A run is a maximal sequence of consecutive line numbers, in one file, of removed (or added) '
    'lines that are not declared.',
    'Every removed line must be paired with one added line that matches it, in any file, and every '
    'added line with one removed line. A line is paired at most once, so a duplicated or dropped '
    'copy of a line is reported. For each text, the number of unpaired removed (or added) lines '
    'is how many more removed (or added) lines than added (or removed) lines have that text, '
    'whatever the pairing. Pairs are chosen in three steps. First, a removed line whose text '
    'occurs exactly once among the removed lines and exactly once among the added lines is an '
    'anchor, paired with that added line. Second, the anchors are taken in order of removed line '
    '(by path, then line number), and each grows, first backward and then forward, one line at a '
    'time, while the removed line and the added line next to it are in the same removed and added '
    'runs as the anchor, both unpaired, and match. Third, the lines still unpaired are paired by '
    'text: for each text, the remaining removed lines and the remaining added lines, each in order '
    'of path and line number, are paired first with first, second with second, and so on. A moved '
    'block is a maximal sequence of pairs whose removed lines are consecutive lines of one removed '
    'run and whose added lines are consecutive lines of one added run.',
    'If moved lines from one removed run land in one added run as more than one block, that is '
    'reported as reordered or interleaved, and is a failure. A reordering is reported only for the '
    'pairing chosen: identical lines elsewhere in the diff can make a reordered block look like '
    'two moves (a line of the block paired with an identical line somewhere else), and that is '
    'not reported as a reordering. A diff can also show part of a moved block as unchanged lines: '
    'a line of the block can be matched with an equal line near its new place (in an extraction '
    'into the same file, the old function\'s closing brace with the new function\'s), and a '
    'reordering inside the block then looks like a move of fewer lines, or of none. The pairing '
    'mode, with or without --strict-runs, therefore cannot judge an extraction whose destination '
    'is in the same file. --extract is the mode for extract commits (large-code.md section 2.2).',
    'The report lists every moved block with its source and destination, in order of removed line, '
    'and for each removed run the added runs its moved lines landed in. A removed run whose moved '
    'lines land in more than one added run, and an added run that receives moved lines from more '
    'than one removed run, are listed as run notices. Run notices are not failures unless '
    '--strict-runs is given, and then each one is (exit 1). --strict-runs does not make the '
    'pairing mode a check of an extraction; see the rule above.',
    _REFUSED,
    _BUDGET_LINES + ' ' + _BUDGET_FILES,
    _ERRORS + ' A diff in which no line is moved is not a pure move.',
    _DISPLAY,
]

EXTRACT_RULES = [
    _MEANING + ' ' + _READING + ' With --extract no line diff is used: every check below is '
    'made on the old and new content of the compared files directly. An added file has empty '
    'old content and a deleted file empty new content.',
    'Each --extract OLDPATH:A-B=NEWPATH:C-D declares that lines A to B of the old content of '
    'OLDPATH are a block that moved, and that they are lines C to D of the new content of NEWPATH. '
    'The two paths may name the same file. A single line may be written N instead of N-N. The '
    'first ":N=" or ":N-M=" in the argument ends OLDPATH.',
    'Each block and its destination must have the same number of lines and match line by line, '
    'in order. ' + _MATCHING + ' Every mismatched pair is listed with both lines (within the '
    'listing limit below), and a difference in the number of lines is a failure.',
    'Everything else must be unchanged or declared. For every compared file, its old content with '
    'the extracted source ranges and the --allow-removed lines deleted must equal its new content '
    'with the extracted destination ranges and the --allow-added lines deleted, line for line and '
    'byte for byte, indentation included. Every difference is listed as path:line (within the '
    'listing limit below): the two remainders are compared with a line diff (Python difflib) '
    'when the region between their common start and common end is at most %s line '
    'pairs, and otherwise every line of that region is listed.' % _count(MAX_DIFF_PAIRS),
    'At most %s lines are listed in all, mismatched lines and unaccounted lines together: '
    'first the mismatched lines, block by block in the order declared, then the unaccounted '
    'lines, file by file in path order, removed before added. The rest are counted, and the '
    'report says how many more there are in each list. The counts and the result do not depend '
    'on this limit.' % _count(MAX_LISTED_LINES),
    'Every range must lie within the content it names (the old content for an extracted source '
    'and --allow-removed, the new content for a destination and --allow-added) of a file whose '
    'lines are compared. Sources may not overlap one another or --allow-removed lines, and '
    'destinations may not overlap one another or --allow-added lines. Otherwise the tool exits '
    '2. In this mode --allow-removed and --allow-added lines need not be lines a diff shows as '
    'removed or added; they are listed as declared and are not checked.',
    'There is no pairing and no ambiguity: a reordering, a dropped or duplicated line, or an edit '
    'anywhere is a failure, whatever identical lines exist elsewhere.',
    '--extract cannot be combined with --strict-runs (exit 2). --show-lines lists every changed '
    'file with the old and new line number of each line, from which the ranges can be copied.',
    _REFUSED,
    _BUDGET_FILES,
    _ERRORS,
    _DISPLAY,
]

_NOT_CHECKED_MEANING = [
    'That moved code means the same in its new place: a different self or receiver, different '
    'locals, ivars, macros, #if conditions, or imports in scope.',
    'Control flow that leaves a moved block: return, break, continue, goto, fallthrough, throw '
    'and @throw now leave only the new function. large-code.md section 2.2 asks for these to be '
    'listed; this tool does not list them.',
    'Locals read or written by a moved block, which must become parameters, return values or '
    'out-parameters, and variables captured by reference (__block, inout, block literals).',
    'The number and order of evaluations of the expressions now passed as arguments to the new '
    'function.',
    'Manual reference counting: whether a value returned by the new function follows the '
    'ownership of the original expression.',
]

_NOT_CHECKED_DECLARED = (
    'Declared lines: the reviewer must confirm they are only the new signature, braces, blank '
    'lines and the call site.')

_NOT_CHECKED_TAIL = [
    'With --staged, unstaged changes and untracked files.',
    'Whether the change builds, and whether project file or target membership changes are right '
    '(a project file is checked only as lines).',
]

NOT_CHECKED = _NOT_CHECKED_MEANING + [
    'Where a moved block now sits relative to unchanged code. Moving a block to another place in '
    'the same function, which reorders statements, is reported as an ordinary move; read the '
    'moved blocks list.',
    'Every reordering. A reordering is reported only for the pairing chosen; identical lines '
    'elsewhere in the diff can make a reordered block look like two moves, which then shows only '
    'as run notices and in the moved blocks list, and a diff can show part of a moved block as '
    'unchanged lines. The pairing mode, with or without --strict-runs, cannot judge an extraction '
    'whose destination is in the same file; use --extract for extract commits.',
    _NOT_CHECKED_DECLARED,
    'Indentation: leading whitespace is ignored, so a change of indentation that matters (a Swift '
    'multi-line string literal, a makefile recipe, Python) is not reported.',
    'Which of several identical lines moved: identical lines are interchangeable, so the line '
    'numbers shown for them reflect the pairing order, not intent.',
] + _NOT_CHECKED_TAIL

NOT_CHECKED_EXTRACT = _NOT_CHECKED_MEANING + [
    _NOT_CHECKED_DECLARED,
    'Positions: where an extracted block sits within its new function, and where the declared '
    'lines (the call site) sit among unchanged lines, are whatever the author declared. A call '
    'placed somewhere other than where the block was removed is not reported; read the declared '
    'lines against the extracted source range.',
    'Indentation inside an extracted block: leading whitespace is ignored there, so a change of '
    'indentation that matters (a Swift multi-line string literal, a makefile recipe, Python) is '
    'not reported. Outside the blocks indentation is compared.',
] + _NOT_CHECKED_TAIL

HUNK_RE = re.compile(rb'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
HEADER_PREFIXES = (b'diff --git ', b'index ', b'--- ', b'+++ ')
DECLARATION_RE = re.compile(r'^(.+):([1-9][0-9]*)(?:-([1-9][0-9]*))?$')
EXTRACTION_RE = re.compile(r'^(.+?):([1-9][0-9]*)(?:-([1-9][0-9]*))?='
                           r'(.+):([1-9][0-9]*)(?:-([1-9][0-9]*))?$')


class ToolError(Exception):
    """A usage or environment error: exit status 2."""


def normalize(text):
    return text.lstrip(b' \t')


def split_lines(data):
    if not data:
        return []
    parts = data.split(b'\n')
    if data.endswith(b'\n'):
        parts.pop()
    return parts


def lacks_final_newline(data):
    return bool(data) and not data.endswith(b'\n')


def is_binary(data):
    return b'\0' in data[:8000]


def display(text):
    """The text shown for a line, path or message. See _DISPLAY."""
    decoded = text.decode('utf-8', 'surrogateescape')
    body = decoded.rstrip(' \t')
    out = []
    for ch in body:
        o = ord(ch)
        category = unicodedata.category(ch)
        if ch == '\\':
            out.append('\\\\')
        elif 0xdc80 <= o <= 0xdcff:
            out.append('\\x%02x' % (o - 0xdc00))  # an invalid byte, from surrogateescape
        elif ch == '\r':
            out.append('\\r')
        elif category == 'Cc' and ch != '\t':
            out.append('\\x%02x' % o if o < 0x80 else '\\u%04x' % o)
        elif category == 'Cf' or (category == 'Zs' and ch != ' '):
            out.append('\\u%04x' % o if o <= 0xffff else '\\U%08x' % o)
        else:
            out.append(ch)
    out.extend('\\x20' if ch == ' ' else '\\t' for ch in decoded[len(body):])
    return ''.join(out)


def parse_declaration(spec):
    m = DECLARATION_RE.match(spec)
    if not m:
        raise ValueError('expected PATH:N or PATH:N-M, got %r' % spec)
    start = int(m.group(2))
    end = int(m.group(3)) if m.group(3) else start
    if end < start:
        raise ValueError('range ends before it starts in %r' % spec)
    return m.group(1), start, end


def parse_extraction(spec):
    """Returns (old path, A, B, new path, C, D) from OLDPATH:A[-B]=NEWPATH:C[-D]."""
    m = EXTRACTION_RE.match(spec)
    bad = ValueError('--extract expects OLDPATH:A-B=NEWPATH:C-D, got %r' % spec)
    if not m:
        raise bad
    a = int(m.group(2))
    b = int(m.group(3)) if m.group(3) else a
    c = int(m.group(5))
    d = int(m.group(6)) if m.group(6) else c
    if b < a or d < c:
        raise bad
    return m.group(1), a, b, m.group(4), c, d


def parse_patch_lines(lines):
    """Returns ([(old line number, text)], [(new line number, text)]) from the lines of one
    file's git diff -U0 output."""
    removed, added = [], []
    i = 0
    while i < len(lines) and not lines[i].startswith(b'@@'):
        if not lines[i].startswith(HEADER_PREFIXES):
            raise ToolError('unexpected line in git diff output: %r' % lines[i][:100])
        i += 1
    while i < len(lines):
        m = HUNK_RE.match(lines[i])
        if not m:
            raise ToolError('unexpected line in git diff output: %r' % lines[i][:100])
        i += 1
        for sign, start, count, out in ((b'-', m.group(1), m.group(2), removed),
                                        (b'+', m.group(3), m.group(4), added)):
            start = int(start)
            count = 1 if count is None else int(count)
            for k in range(count):
                if i >= len(lines) or not lines[i].startswith(sign):
                    raise ToolError('git diff output does not match its hunk header')
                out.append((start + k, lines[i][1:]))
                i += 1
                while i < len(lines) and lines[i].startswith(b'\\'):
                    i += 1
    return removed, added


def parse_patch(patch):
    """Returns ([(old line number, text)], [(new line number, text)]) from git diff -U0 output."""
    return parse_patch_lines(split_lines(patch))


def split_batches(out, count):
    """Splits git diff-pairs output, one batch per file, each ended by a NUL, into count
    (removed, added) results. A NUL can appear inside a patch only after a line's first byte
    (content lines begin with +, - or a backslash), so a line that begins with NUL ends a batch."""
    batches = [[]]
    for line in out.split(b'\n'):
        while line.startswith(b'\0'):
            batches.append([])
            line = line[1:]
        if line:
            batches[-1].append(line)
    if len(batches) != count + 1 or batches[-1]:
        raise ToolError('git diff-pairs printed %d patches for %d files'
                        % (len(batches) - 1, count))
    return [parse_patch_lines(b) for b in batches[:-1]]


class Match(object):
    """Pairs removed lines with added lines. See RULES.

    Time and memory are linear in the number of lines, apart from sorting.
    """

    def __init__(self, removed, added):
        R = sorted(removed, key=lambda x: (x.path, x.line))
        A = sorted(added, key=lambda x: (x.path, x.line))
        self.R, self.A = R, A
        rk = [normalize(x.text) for x in R]
        ak = [normalize(x.text) for x in A]
        rseg = self.rseg = self._runs(R)
        aseg = self.aseg = self._runs(A)
        self.rend = self._run_ends(rseg)
        self.aend = self._run_ends(aseg)
        rcount = Counter(rk)
        acount = Counter(ak)
        rpair = [-1] * len(R)
        apair = [-1] * len(A)

        # Step 1 and 2: anchors, in order of removed line, each grown backward
        # and then forward over matching unpaired lines in the same runs.
        anchor_partner = {}
        for j, k in enumerate(ak):
            if acount[k] == 1:
                anchor_partner[k] = j
        for i, k in enumerate(rk):
            if rpair[i] >= 0 or rcount[k] != 1 or k not in anchor_partner:
                continue
            j = anchor_partner[k]
            # The text occurs once on each side and growth pairs only equal
            # lines, so nothing else can have taken j.
            assert apair[j] < 0
            rpair[i], apair[j] = j, i
            p, q = i - 1, j - 1
            while p >= 0 and q >= 0 and rseg[p] == rseg[i] and aseg[q] == aseg[j] \
                    and rpair[p] < 0 and apair[q] < 0 and rk[p] == ak[q]:
                rpair[p], apair[q] = q, p
                p -= 1
                q -= 1
            p, q = i + 1, j + 1
            while p < len(R) and q < len(A) and rseg[p] == rseg[i] and aseg[q] == aseg[j] \
                    and rpair[p] < 0 and apair[q] < 0 and rk[p] == ak[q]:
                rpair[p], apair[q] = q, p
                p += 1
                q += 1

        # Step 3: what is left pairs by text, first with first.
        waiting = {}
        for j, k in enumerate(ak):
            if apair[j] < 0:
                waiting.setdefault(k, deque()).append(j)
        for i, k in enumerate(rk):
            if rpair[i] < 0:
                d = waiting.get(k)
                if d:
                    j = d.popleft()
                    rpair[i], apair[j] = j, i

        blocks = []
        for i in range(len(R)):
            j = rpair[i]
            if j < 0:
                continue
            if blocks:
                bi, bj, n = blocks[-1]
                if bi + n == i and bj + n == j and rseg[bi] == rseg[i] and aseg[bj] == aseg[j]:
                    blocks[-1] = (bi, bj, n + 1)
                    continue
            blocks.append((i, j, 1))
        self.blocks = blocks
        self.unmatched_removed = [R[i] for i in range(len(R)) if rpair[i] < 0]
        self.unmatched_added = [A[j] for j in range(len(A)) if apair[j] < 0]
        self.moved_line_count = sum(n for _, _, n in blocks)

        groups = {}
        for b in blocks:
            groups.setdefault((rseg[b[0]], aseg[b[1]]), []).append(b)
        self.order_problems = []
        for key in sorted(groups):
            pieces = groups[key]
            if len(pieces) > 1:
                self.order_problems.append(((key[0], self.rend[key[0]]),
                                            (key[1], self.aend[key[1]]), pieces))

        # Which added runs each removed run's moved lines landed in, and the
        # reverse, each in order of first line.
        lands = dict((s, set()) for s in set(rseg))
        feeds = {}
        for i, j, _ in blocks:
            r, a = rseg[i], aseg[j]
            lands[r].add(a)
            feeds.setdefault(a, set()).add(r)
        self.lands = [(r, sorted(lands[r])) for r in sorted(lands)]
        self.split_runs = [(r, a) for r, a in self.lands if len(a) > 1]
        self.gathered_runs = [(a, sorted(feeds[a])) for a in sorted(feeds) if len(feeds[a]) > 1]

    @staticmethod
    def _runs(lines):
        seg = []
        for i, x in enumerate(lines):
            if i > 0 and lines[i - 1].path == x.path and lines[i - 1].line + 1 == x.line:
                seg.append(seg[-1])
            else:
                seg.append(i)
        return seg

    @staticmethod
    def _run_ends(seg):
        end = {}
        for i, s in enumerate(seg):
            end[s] = i
        return end

    def _range(self, lines, first, last):
        return {'path': lines[first].path, 'start': lines[first].line, 'end': lines[last].line}

    def _rrun(self, s):
        return self._range(self.R, s, self.rend[s])

    def _arun(self, s):
        return self._range(self.A, s, self.aend[s])

    def _block_json(self, b):
        i, j, n = b
        return {'removed': self._range(self.R, i, i + n - 1),
                'added': self._range(self.A, j, j + n - 1),
                'lines': n}

    def blocks_json(self):
        return [self._block_json(b) for b in self.blocks]

    def order_problems_json(self):
        return [{'removed': self._range(self.R, r[0], r[1]),
                 'added': self._range(self.A, a[0], a[1]),
                 'pieces': [self._block_json(b) for b in pieces]}
                for r, a, pieces in self.order_problems]

    def runs_json(self):
        return [{'removed': self._rrun(r), 'lands_in': [self._arun(a) for a in landed]}
                for r, landed in self.lands]

    def run_notices_json(self):
        return ([{'kind': 'split', 'run': self._rrun(r), 'runs': [self._arun(a) for a in landed]}
                 for r, landed in self.split_runs] +
                [{'kind': 'gathered', 'run': self._arun(a), 'runs': [self._rrun(r) for r in fed]}
                 for a, fed in self.gathered_runs])


def match_lines(removed, added):
    return Match(removed, added)


class Git(object):
    def __init__(self, repo):
        self.repo = repo
        self.env = dict(os.environ)
        for name in ('GIT_DIFF_OPTS', 'GIT_EXTERNAL_DIFF'):
            self.env.pop(name, None)

    def run(self, args, input=None, check=True):
        try:
            proc = subprocess.run(['git', '--no-pager', '-C', self.repo] + args, env=self.env,
                                  input=input, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except OSError as e:
            raise ToolError('cannot run git: %s' % e)
        if proc.returncode != 0:
            if not check:
                return None
            raise ToolError('git %s failed: %s' % (' '.join(args),
                                                   proc.stderr.decode('utf-8', 'replace').strip()))
        return proc.stdout

    def text(self, args, check=True):
        out = self.run(args, check=check)
        return None if out is None else out.decode('utf-8').strip()

    def commit(self, rev):
        sha = self.text(['rev-parse', '--verify', '--quiet', rev + '^{commit}'], check=False)
        if not sha:
            raise ToolError('not a commit: %s' % rev)
        return sha

    @staticmethod
    def _names(shas):
        return b''.join(sha.encode('ascii') + b'\n' for sha in shas)

    def sizes(self, shas):
        """Returns {sha: size} for blobs, from one git cat-file --batch-check process."""
        if not shas:
            return {}
        out = split_lines(self.run(['cat-file', '--batch-check'], input=self._names(shas)))
        if len(out) != len(shas):
            raise ToolError('git cat-file --batch-check printed %d lines for %d objects'
                            % (len(out), len(shas)))
        sizes = {}
        for sha, line in zip(shas, out):
            parts = line.split(b' ')
            if len(parts) != 3 or parts[0] != sha.encode('ascii') or parts[1] != b'blob' or \
                    not parts[2].isdigit():
                raise ToolError('cannot read blob %s: %r' % (sha, line[:100]))
            sizes[sha] = int(parts[2])
        return sizes

    def read_blobs(self, shas):
        """Returns {sha: content} for blobs, from one git cat-file --batch process. The output is
        read blob by blob as it arrives, so the content is held in memory once."""
        if not shas:
            return {}
        try:
            proc = subprocess.Popen(['git', '--no-pager', '-C', self.repo, 'cat-file', '--batch'],
                                    env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE)
        except OSError as e:
            raise ToolError('cannot run git: %s' % e)
        names = self._names(shas)
        errors = []

        def drain():
            # Read as git writes, so that a lot of stderr cannot block git before its stdout ends.
            errors.append(proc.stderr.read())

        def feed():
            try:
                proc.stdin.write(names)
                proc.stdin.close()
            except OSError:
                pass  # git exited early; its status and stderr say why

        writer = threading.Thread(target=feed)
        writer.start()
        reader = threading.Thread(target=drain)
        reader.start()
        blobs = {}
        failure = None
        try:
            for sha in shas:
                parts = proc.stdout.readline().rstrip(b'\n').split(b' ')
                if len(parts) != 3 or parts[0] != sha.encode('ascii') or parts[1] != b'blob' or \
                        not parts[2].isdigit():
                    failure = 'cannot read blob %s: %r' % (sha, b' '.join(parts)[:100])
                    break
                size = int(parts[2])
                content = proc.stdout.read(size)
                if len(content) != size or proc.stdout.read(1) != b'\n':
                    failure = 'git cat-file --batch output is malformed at blob %s' % sha
                    break
                blobs[sha] = content
            if failure is None and proc.stdout.read(1):
                failure = 'git cat-file --batch printed more than was asked for'
        finally:
            if failure is not None:
                proc.kill()
            writer.join()
            proc.stdout.close()
            reader.join()
            err = errors[0] if errors else b''
            proc.stderr.close()
            proc.wait()
        if proc.returncode != 0 and failure is None:
            failure = 'git cat-file --batch failed: %s' % err.decode('utf-8', 'replace').strip()
        if failure is not None:
            raise ToolError(failure)
        return blobs

    def patches(self, pairs):
        """Returns [(removed, added)] for [(mode, old sha, new sha)], from one git diff-pairs
        process. Each pair is given a neutral path and is flushed on its own, so each patch is
        delimited by a NUL in the output."""
        if not pairs:
            return []
        data = b''.join(b':%s %s %s %s M\0p%d\0\0' % (mode.encode('ascii'), mode.encode('ascii'),
                                                      old.encode('ascii'), new.encode('ascii'), k)
                        for k, (mode, old, new) in enumerate(pairs))
        try:
            out = self.run(['diff-pairs', '-z', '-p'] + PATCH_FLAGS + DIFF_FLAGS, input=data)
        except ToolError as e:
            raise ToolError('%s (the pairing mode and --show-lines need git 2.50 or later, for '
                            'git diff-pairs)' % e)
        return split_batches(out, len(pairs))


def verify_patch(pairs, lines, path):
    """Raises ToolError unless each (line number, text) from a patch is that line of lines."""
    for n, text in pairs:
        if n > len(lines) or lines[n - 1] != text:
            raise ToolError('git diff output does not match the content of %s' % path)


def check_complete(old_lines, new_lines, removed, added, path):
    """Raises ToolError unless the patch accounts for every difference: the old lines without
    the removed ones must equal the new lines without the added ones."""
    verify_patch(removed, old_lines, path)
    verify_patch(added, new_lines, path)
    gone = set(n for n, _ in removed)
    new = set(n for n, _ in added)
    kept_old = (t for n, t in enumerate(old_lines, 1) if n not in gone)
    kept_new = (t for n, t in enumerate(new_lines, 1) if n not in new)
    if len(gone) != len(removed) or len(new) != len(added) or \
            len(old_lines) - len(gone) != len(new_lines) - len(new) or \
            any(a != b for a, b in zip(kept_old, kept_new)):
        raise ToolError('git diff output does not account for every change to %s' % path)


Entry = namedtuple('Entry', 'status old_mode new_mode old_sha new_sha old_path path')


def parse_raw(data):
    if data and not data.endswith(b'\0'):
        raise ToolError('git diff --raw output is truncated: it does not end with a NUL')
    tokens = data.split(b'\0')
    if tokens[-1] == b'':
        tokens.pop()
    entries = []
    i = 0
    while i < len(tokens):
        fields = tokens[i][1:].split(b' ') if tokens[i].startswith(b':') else []
        if len(fields) != 5 or not all(re.fullmatch(rb'[0-9a-zA-Z]+', x) for x in fields):
            raise ToolError('unexpected git diff --raw output: %r' % tokens[i][:100])
        old_mode, new_mode, old_sha, new_sha, status = (x.decode('ascii') for x in fields)
        letter = status[0]
        if i + (3 if letter in 'RC' else 2) > len(tokens):
            raise ToolError('git diff --raw output is truncated: %r has no path' % tokens[i][:100])
        if letter in 'RC':
            old_path, path = os.fsdecode(tokens[i + 1]), os.fsdecode(tokens[i + 2])
            i += 3
        else:
            old_path = path = os.fsdecode(tokens[i + 1])
            i += 2
        entries.append(Entry(letter, old_mode, new_mode, old_sha, new_sha, old_path, path))
    return entries


DIFF_FLAGS = ['--no-color', '--no-ext-diff', '--no-textconv', '--no-relative']
PATCH_FLAGS = ['-U0', '--inter-hunk-context=0', '--histogram', '--indent-heuristic', '--text']


def line_count(data):
    if not data:
        return 0
    return data.count(b'\n') + (0 if data.endswith(b'\n') else 1)


# A file whose lines are compared. removed and added are [(line number, text)] in the pairing
# mode and None with --extract. For an added file old_lines is empty, for a deleted file
# new_lines. old_open and new_open say that the content is not empty and does not end with a
# newline.
FileData = namedtuple('FileData', 'path old_path status old_lines new_lines old_open new_open '
                                  'removed added')


def collect(git, mode, old, new, patches=True):
    """Reads the change. Returns (files, compared, problems): every changed file as listed, the
    FileData of each file whose lines are compared, and the file-level problems in path order.
    With patches, also reads each modified file's removed and added lines from one diff."""
    args = ['diff', '--raw', '-z', '--no-abbrev', '-M', '--ignore-submodules=none'] + DIFF_FLAGS
    if mode == 'staged':
        args += ['--cached', old]
    else:
        args += [old, new]
    entries = sorted(parse_raw(git.run(args)), key=lambda e: e.path)
    if len(entries) > MAX_CHANGED_FILES:
        raise ToolError('the change has more than %d changed files; this tool does not check a '
                        'change that large. Split it into smaller commits.' % MAX_CHANGED_FILES)
    files, problems, candidates = [], [], []

    def problem(index, e, text):
        problems.append((index, {'path': e.path, 'problem': text}))

    for index, e in enumerate(entries):
        if e.status == 'U':
            raise ToolError('the index has unmerged paths (%s); resolve them first' % e.path)
        if e.status not in 'AMDRT':
            raise ToolError('unexpected status %s for %s' % (e.status, e.path))
        old_mode = None if e.status == 'A' else e.old_mode
        new_mode = None if e.status == 'D' else e.new_mode
        files.append({'path': e.path, 'old_path': None if e.status == 'A' else e.old_path,
                      'status': e.status, 'old_mode': old_mode, 'new_mode': new_mode})
        # Change kinds that are never accepted are reported before any content is read.
        if e.status == 'R':
            problem(index, e, 'renamed from %s; not compared' % e.old_path)
            continue
        if e.status == 'T':
            problem(index, e, 'type changed (T); not compared')
            continue
        modes = [m for m in (old_mode, new_mode) if m is not None]
        if '160000' in modes:
            problem(index, e, 'submodule; not compared')
            continue
        if '120000' in modes:
            problem(index, e, 'symbolic link; not compared')
            continue
        odd = [m for m in modes if m not in REGULAR_MODES]
        if odd:
            problem(index, e, 'unexpected mode %s; not compared' % odd[0])
            continue
        if e.status == 'M' and old_mode != new_mode:
            problem(index, e, 'mode changed from %s to %s; not compared' % (old_mode, new_mode))
            continue
        shas = [sha for sha, m in ((e.old_sha, old_mode), (e.new_sha, new_mode)) if m]
        candidates.append((index, e, old_mode, new_mode, shas))

    sizes = git.sizes(sorted(set(sha for c in candidates for sha in c[4])))
    readable = []
    for c in candidates:
        if any(sizes[sha] > MAX_BLOB_BYTES for sha in c[4]):
            problem(c[0], c[1], 'file over 20 MB; not compared')
        else:
            readable.append(c)
    wanted = sorted(set(sha for c in readable for sha in c[4]))
    if sum(sizes[sha] for sha in wanted) > MAX_TOTAL_BYTES:
        raise ToolError('the change has more than %d bytes of file content to compare; this tool '
                        'does not check a change that large. Split it into smaller commits.'
                        % MAX_TOTAL_BYTES)
    blobs = git.read_blobs(wanted)
    uses = Counter(sha for c in readable for sha in c[4])

    def take(sha):
        # Each blob is dropped after its last use, so that the content and its lines are not
        # both held for every file at once.
        uses[sha] -= 1
        return blobs[sha] if uses[sha] else blobs.pop(sha)

    compared = []
    for index, e, old_mode, new_mode, _ in readable:
        old_data = take(e.old_sha) if old_mode else b''
        new_data = take(e.new_sha) if new_mode else b''
        if is_binary(old_data) or is_binary(new_data):
            problem(index, e, 'binary file; not compared')
            continue
        if e.status == 'A':
            if not new_data:
                problem(index, e, 'empty file added')
            elif lacks_final_newline(new_data):
                problem(index, e, 'no final newline in added file')
        if e.status == 'D':
            if not old_data:
                problem(index, e, 'empty file deleted')
            elif lacks_final_newline(old_data):
                problem(index, e, 'no final newline in deleted file')
        if e.status == 'M':
            if old_data and new_data and old_data.endswith(b'\n') != new_data.endswith(b'\n'):
                problem(index, e, 'final newline %s' % ('added' if new_data.endswith(b'\n')
                                                        else 'removed'))
            elif not old_data and lacks_final_newline(new_data):
                problem(index, e, 'no final newline in a file that was empty')
            elif not new_data and lacks_final_newline(old_data):
                problem(index, e, 'no final newline in a file that is now empty')
            if e.old_sha == e.new_sha:
                continue
        compared.append((index, e, old_mode, FileData(
            e.path, None if e.status == 'A' else e.old_path, e.status, split_lines(old_data),
            split_lines(new_data), lacks_final_newline(old_data), lacks_final_newline(new_data),
            None, None)))

    if patches:
        budget = [MAX_CHANGED_LINES]

        def spend(n):
            budget[0] -= n
            if budget[0] < 0:
                raise ToolError('the change has more than %d changed lines (removed plus added '
                                'lines of the files compared); this tool does not check a change '
                                'that large. Split it into smaller commits.' % MAX_CHANGED_LINES)

        for _, e, _, f in compared:
            if e.status != 'M':
                spend(len(f.old_lines) + len(f.new_lines))
        modified = [(old_mode, e.old_sha, e.new_sha) for _, e, old_mode, _ in compared
                    if e.status == 'M']
        results = iter(git.patches(modified))
        done = []
        for index, e, old_mode, f in compared:
            if e.status == 'M':
                r, a = next(results)
                spend(len(r) + len(a))
                check_complete(f.old_lines, f.new_lines, r, a, e.path)
                if f.old_open and f.new_open and \
                        (any(n == len(f.old_lines) for n, _ in r) or
                         any(n == len(f.new_lines) for n, _ in a)):
                    problem(index, e, LAST_LINE_PROBLEM)
            else:
                r = list(enumerate(f.old_lines, 1))
                a = list(enumerate(f.new_lines, 1))
            done.append((index, e, old_mode, f._replace(removed=r, added=a)))
        compared = done

    if not entries:
        problems.append((-1, {'path': None, 'problem': 'the diff is empty; nothing was moved'}))
    problems.sort(key=lambda p: p[0])
    return files, [c[3] for c in compared], [p[1] for p in problems]


LAST_LINE_PROBLEM = 'last line has no final newline and is changed'


def declared(lines, specs, option):
    """Returns the set of (path, line) the specs name. Raises ToolError, listing at most
    MAX_LISTED_DECLARATIONS of them, if any named line is not one of lines. A range is never
    expanded beyond the lines it actually contains."""
    present = {}
    for x in lines:
        present.setdefault(x.path, []).append(x.line)
    for numbers in present.values():
        numbers.sort()
    wanted = set()
    bad = []
    missing = 0
    for path, start, end in specs:
        numbers = present.get(path, [])
        lo = bisect.bisect_left(numbers, start)
        hi = bisect.bisect_right(numbers, end)
        wanted.update((path, n) for n in numbers[lo:hi])
        absent = (end - start + 1) - (hi - lo)
        missing += absent
        n, k = start, lo
        while absent and len(bad) < MAX_LISTED_DECLARATIONS and n <= end:
            if k < hi and numbers[k] == n:
                k += 1
            else:
                bad.append('%s:%d' % (path, n))
                absent -= 1
            n += 1
    if missing:
        kind = 'added' if option == '--allow-added' else 'removed'
        more = missing - len(bad)
        raise ToolError('%s names lines that are not %s lines of this diff: %s%s'
                        % (option, kind, ', '.join(bad), ' and %d more' % more if more else ''))
    return wanted


def resolve(git, mode, revs):
    """Returns (old, new): what the change is compared from and to."""
    if mode == 'staged':
        head = git.text(['rev-parse', '--verify', '--quiet', 'HEAD^{commit}'], check=False)
        return head or empty_tree(git), 'index'
    if mode == 'commit':
        new = git.commit(revs[0])
        parents = git.text(['rev-list', '--parents', '-n', '1', new]).split()[1:]
        if len(parents) > 1:
            raise ToolError('%s is a merge commit; there is no single diff to check. Compare it '
                            'with one parent instead: pure_move.py %s^1 %s' % (new, new, new))
        return parents[0] if parents else empty_tree(git), new
    return git.commit(revs[0]), git.commit(revs[1])


def lines_json(lines):
    return [{'path': x.path, 'line': x.line, 'text': display(x.text)}
            for x in sorted(lines, key=lambda x: (x.path, x.line))]


def check(git, mode, revs, allow_added, allow_removed, strict_runs=False, extractions=None):
    if extractions:
        if strict_runs:
            raise ToolError('--extract cannot be combined with --strict-runs; it replaces it')
        return check_extract(git, mode, revs, extractions, allow_added, allow_removed)
    old, new = resolve(git, mode, revs)
    files, compared, problems = collect(git, mode, old, new)
    removed = [Line(f.old_path, n, t) for f in compared for n, t in f.removed]
    added = [Line(f.path, n, t) for f in compared for n, t in f.added]
    declared_r = declared(removed, allow_removed, '--allow-removed')
    declared_a = declared(added, allow_added, '--allow-added')
    m = match_lines([x for x in removed if (x.path, x.line) not in declared_r],
                    [x for x in added if (x.path, x.line) not in declared_a])
    if files and m.moved_line_count == 0:
        problems.append({'path': None, 'problem': 'no line was moved'})

    decl_r = [x for x in removed if (x.path, x.line) in declared_r]
    decl_a = [x for x in added if (x.path, x.line) in declared_a]
    notices = m.run_notices_json()
    pure = not (m.unmatched_removed or m.unmatched_added or m.order_problems or problems or
                (strict_runs and notices))
    return {
        'tool': 'pure_move',
        'check': 'pairing',
        'pure_move': pure,
        'exit_code': 0 if pure else 1,
        'compared': {'mode': mode, 'old': old, 'new': new},
        'strict_runs': strict_runs,
        'files': files,
        'counts': {'removed': len(removed), 'added': len(added), 'moved': m.moved_line_count,
                   'declared_removed': len(decl_r), 'declared_added': len(decl_a),
                   'unaccounted_removed': len(m.unmatched_removed),
                   'unaccounted_added': len(m.unmatched_added),
                   'order_problems': len(m.order_problems), 'file_problems': len(problems),
                   'run_notices': len(notices)},
        'unaccounted_removed': lines_json(m.unmatched_removed),
        'unaccounted_added': lines_json(m.unmatched_added),
        'order_problems': m.order_problems_json(),
        'file_problems': problems,
        'declared_removed': lines_json(decl_r),
        'declared_added': lines_json(decl_a),
        'moved_blocks': m.blocks_json(),
        'runs': m.runs_json(),
        'run_notices': notices,
        'rules': RULES,
        'not_checked': NOT_CHECKED,
    }


def spec_text(path, start, end):
    return '%s:%d' % (path, start) if start == end else '%s:%d-%d' % (path, start, end)


def diff_remainders(old_lines, old_keep, new_lines, new_keep):
    """Compares the remainders: the old lines numbered in old_keep with the new lines numbered in
    new_keep (each a sorted list or range of line numbers). Returns (removed, added): the
    (line number, text) that a line diff of the two does not match, both empty exactly when
    the remainders are equal. Each is a list, or, for a region above MAX_DIFF_PAIRS, an iterator,
    so that the lines of a large region are not all built at once."""
    no, nn = len(old_keep), len(new_keep)
    i = 0
    while i < no and i < nn and old_lines[old_keep[i] - 1] == new_lines[new_keep[i] - 1]:
        i += 1
    j = 0
    while j < no - i and j < nn - i and \
            old_lines[old_keep[no - 1 - j] - 1] == new_lines[new_keep[nn - 1 - j] - 1]:
        j += 1
    if (no - j - i) * (nn - j - i) > MAX_DIFF_PAIRS:
        return (((n, old_lines[n - 1]) for n in old_keep[i:no - j]),
                ((n, new_lines[n - 1]) for n in new_keep[i:nn - j]))
    mid_old = [(n, old_lines[n - 1]) for n in old_keep[i:no - j]]
    mid_new = [(n, new_lines[n - 1]) for n in new_keep[i:nn - j]]
    removed, added = [], []
    sm = difflib.SequenceMatcher(None, [t for _, t in mid_old], [t for _, t in mid_new],
                                 autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag != 'equal':
            removed.extend(mid_old[i1:i2])
            added.extend(mid_new[j1:j2])
    return removed, added


def kept(count, gone):
    """The line numbers 1 to count that are not in gone, as a range when none is."""
    if not gone:
        return range(1, count + 1)
    return [n for n in range(1, count + 1) if n not in gone]


def check_extract(git, mode, revs, extractions, allow_added, allow_removed):
    old, new = resolve(git, mode, revs)
    files, compared, problems = collect(git, mode, old, new, patches=False)
    by_path = dict((f.path, f) for f in compared)

    # Every range on each side, labeled, after checking that it lies within its content.
    sides = {'old': {}, 'new': {}}

    def place(label, side, path, start, end, kind):
        f = by_path.get(path)
        if f is None:
            raise ToolError('%s %s: %s is not a file whose lines are compared in this change'
                            % (label, spec_text(path, start, end), path))
        n = len(f.old_lines if side == 'old' else f.new_lines)
        if end > n:
            raise ToolError('%s %s is outside the %s content of %s (%d lines)'
                            % (label, spec_text(path, start, end), side, path, n))
        sides[side].setdefault(path, []).append((start, end, kind, label))

    for op, a, b, np_, c, d in extractions:
        place('--extract source', 'old', op, a, b, 'block')
        place('--extract destination', 'new', np_, c, d, 'block')
    for path, a, b in allow_removed:
        place('--allow-removed', 'old', path, a, b, 'declared')
    for path, a, b in allow_added:
        place('--allow-added', 'new', path, a, b, 'declared')

    gone = {'old': {}, 'new': {}}
    for side in ('old', 'new'):
        for path, ranges in sides[side].items():
            ranges.sort(key=lambda r: (r[0], r[1]))
            for k, (s1, e1, kind1, label1) in enumerate(ranges):
                for s2, e2, kind2, label2 in ranges[k + 1:]:
                    if s2 > e1:
                        break
                    if kind1 == 'block' or kind2 == 'block':
                        raise ToolError('%s %s and %s %s overlap' % (
                            label1, spec_text(path, s1, e1), label2, spec_text(path, s2, e2)))
            numbers = gone[side].setdefault(path, set())
            for s, e, _, _ in ranges:
                numbers.update(range(s, e + 1))

    # At most MAX_LISTED_LINES mismatched and unaccounted lines are listed; all are counted.
    listed = [0]

    def room():
        if listed[0] >= MAX_LISTED_LINES:
            return False
        listed[0] += 1
        return True

    blocks = []
    mismatch_count = listed_mismatches = length_mismatches = extracted = 0
    for op, a, b, np_, c, d in extractions:
        src = by_path[op].old_lines[a - 1:b]
        dst = by_path[np_].new_lines[c - 1:d]
        mismatches = []
        for k in range(min(len(src), len(dst))):
            if normalize(src[k]) != normalize(dst[k]):
                mismatch_count += 1
                if room():
                    mismatches.append(
                        {'source': {'path': op, 'line': a + k, 'text': display(src[k])},
                         'destination': {'path': np_, 'line': c + k, 'text': display(dst[k])}})
        listed_mismatches += len(mismatches)
        length_mismatches += len(src) != len(dst)
        extracted += len(src)
        blocks.append({'source': {'path': op, 'start': a, 'end': b},
                       'destination': {'path': np_, 'start': c, 'end': d},
                       'lines': len(src), 'destination_lines': len(dst), 'mismatches': mismatches})

    unaccounted_r, unaccounted_a, decl_r, decl_a = [], [], [], []
    count_r = count_a = 0
    declared_old = dict((p, set(n for s, e, kind, _ in r if kind == 'declared'
                                for n in range(s, e + 1))) for p, r in sides['old'].items())
    declared_new = dict((p, set(n for s, e, kind, _ in r if kind == 'declared'
                                for n in range(s, e + 1))) for p, r in sides['new'].items())
    for f in compared:
        old_gone = gone['old'].get(f.path, set())
        new_gone = gone['new'].get(f.path, set())
        r, a = diff_remainders(f.old_lines, kept(len(f.old_lines), old_gone),
                               f.new_lines, kept(len(f.new_lines), new_gone))
        for n, t in r:
            count_r += 1
            if room():
                unaccounted_r.append(Line(f.path, n, t))
        for n, t in a:
            count_a += 1
            if room():
                unaccounted_a.append(Line(f.path, n, t))
        decl_r.extend(Line(f.path, n, f.old_lines[n - 1])
                      for n in sorted(declared_old.get(f.path, ())))
        decl_a.extend(Line(f.path, n, f.new_lines[n - 1])
                      for n in sorted(declared_new.get(f.path, ())))
        if f.status == 'M' and f.old_open and f.new_open and \
                (len(f.old_lines) in old_gone or len(f.new_lines) in new_gone):
            problems.append({'path': f.path, 'problem': LAST_LINE_PROBLEM})
    order = dict((x['path'], k) for k, x in enumerate(files))
    problems.sort(key=lambda p: order.get(p['path'], -1))

    pure = not (mismatch_count or length_mismatches or count_r or count_a or problems)
    return {
        'tool': 'pure_move',
        'check': 'extract',
        'pure_move': pure,
        'exit_code': 0 if pure else 1,
        'compared': {'mode': mode, 'old': old, 'new': new},
        'files': files,
        'counts': {'extractions': len(blocks), 'extracted_lines': extracted,
                   'mismatches': mismatch_count, 'length_mismatches': length_mismatches,
                   'unaccounted_removed': count_r, 'unaccounted_added': count_a,
                   'declared_removed': len(decl_r), 'declared_added': len(decl_a),
                   'file_problems': len(problems)},
        'not_listed': {'mismatches': mismatch_count - listed_mismatches,
                       'unaccounted_removed': count_r - len(unaccounted_r),
                       'unaccounted_added': count_a - len(unaccounted_a)},
        'extractions': blocks,
        'unaccounted_removed': lines_json(unaccounted_r),
        'unaccounted_added': lines_json(unaccounted_a),
        'file_problems': problems,
        'declared_removed': lines_json(decl_r),
        'declared_added': lines_json(decl_a),
        'rules': EXTRACT_RULES,
        'not_checked': NOT_CHECKED_EXTRACT,
    }


def number_runs(path, numbers):
    """['path:N-M', ...] for the runs of consecutive numbers in a sorted list."""
    runs = []
    for n in numbers:
        if runs and runs[-1][1] + 1 == n:
            runs[-1][1] = n
        else:
            runs.append([n, n])
    return [spec_text(path, s, e) for s, e in runs]


def show_lines(git, mode, revs):
    old, new = resolve(git, mode, revs)
    files, compared, problems = collect(git, mode, old, new)
    out = []
    for f in compared:
        gone = set(n for n, _ in f.removed)
        new_lines = set(n for n, _ in f.added)
        rows = []
        i = j = 1
        while i <= len(f.old_lines) or j <= len(f.new_lines):
            if i in gone:
                rows.append({'old': i, 'new': None, 'mark': '-',
                             'text': display(f.old_lines[i - 1])})
                i += 1
            elif j in new_lines:
                rows.append({'old': None, 'new': j, 'mark': '+',
                             'text': display(f.new_lines[j - 1])})
                j += 1
            else:
                rows.append({'old': i, 'new': j, 'mark': ' ', 'text': display(f.new_lines[j - 1])})
                i += 1
                j += 1
        out.append({'path': f.path, 'old_path': f.old_path, 'status': f.status,
                    'removed': number_runs(f.old_path or f.path, sorted(gone)),
                    'added': number_runs(f.path, sorted(new_lines)), 'lines': rows})
    return {'tool': 'pure_move', 'check': 'show_lines', 'exit_code': 0,
            'compared': {'mode': mode, 'old': old, 'new': new}, 'files': out,
            'file_problems': problems}


def empty_tree(git):
    return git.run(['hash-object', '-t', 'tree', '--stdin'], input=b'').decode('ascii').strip()


def esc(text):
    """A path or message for the text report, escaped as line text is."""
    return display(os.fsencode(text))


def fmt_range(r):
    return '%s:%d-%d' % (esc(r['path']), r['start'], r['end'])


def compared_text(c):
    if c['mode'] == 'commit':
        return 'Compared: commit %s with its parent %s' % (c['new'], c['old'])
    if c['mode'] == 'staged':
        return ('Compared: HEAD (%s) to the index (staged changes only; unstaged and untracked '
                'files are ignored)' % c['old'])
    return 'Compared: %s to %s' % (c['old'], c['new'])


class Report(object):
    def __init__(self):
        self.out = []

    def section(self, title, items, render, total=None):
        """total is the number of items when only some of them are listed."""
        total = len(items) if total is None else total
        self.out.append('')
        self.out.append('%s (%d):' % (title, total))
        if not total:
            self.out.append('  none')
        for item in items:
            self.out.extend(render(item))
        if total > len(items):
            self.out.append('  ... and %d more, not listed' % (total - len(items)))

    def text(self):
        return '\n'.join(self.out) + '\n'


def line_rows(x):
    return ['  %s:%d: %s' % (esc(x['path']), x['line'], x['text'])]


def problem_rows(p):
    return ['  %s: %s' % (esc(p['path']) if p['path'] is not None else '(diff)', esc(p['problem']))]


def changed_file_rows(f):
    if f['status'] == 'R':
        return ['  R %s -> %s' % (esc(f['old_path']), esc(f['path']))]
    return ['  %s %s' % (f['status'], esc(f['path']))]


def plural(n, word):
    return '%d %s%s' % (n, word, '' if n == 1 else 's')


def rules_rows(rep, j):
    rep.out.append('')
    rep.out.append('Rules applied:')
    rep.out.extend('  - ' + r for r in j['rules'])
    rep.out.append('')
    rep.out.append('Not checked by this tool:')
    rep.out.extend('  - ' + r for r in j['not_checked'])


def result_text(j):
    if j['pure_move']:
        meaning = ('the lines covered by the check were moved unchanged, and the change is '
                   'probably a pure move.')
    else:
        meaning = ('this does not mean that the change is wrong; it means that this tool cannot '
                   'confirm it and more analysis is needed.')
    return 'Result: %s (exit %d): %s' % ('PURE MOVE' if j['pure_move'] else 'NOT A PURE MOVE',
                                         j['exit_code'], meaning)


def format_text(j):
    if j['check'] == 'extract':
        return format_extract_text(j)
    if j['check'] == 'show_lines':
        return format_show_lines_text(j)
    rep = Report()
    out = rep.out
    out.append(compared_text(j['compared']))
    out.append('Check: pairing (removed and added lines of the diff, paired by text)')
    out.append(result_text(j))
    k = j['counts']
    out.append('Lines: %d removed, %d added, %d moved, %d declared removed, %d declared added'
               % (k['removed'], k['added'], k['moved'], k['declared_removed'], k['declared_added']))
    if k['run_notices'] and not j['strict_runs']:
        out.append('Note: %d run notice%s below; not failures without --strict-runs'
                   % (k['run_notices'], '' if k['run_notices'] == 1 else 's'))

    def order(p):
        rows = ['  %s lands in %s as %d pieces:' % (fmt_range(p['removed']), fmt_range(p['added']),
                                                     len(p['pieces']))]
        rows += ['    %s -> %s' % (fmt_range(b['removed']), fmt_range(b['added']))
                 for b in p['pieces']]
        return rows

    def notice(n):
        if n['kind'] == 'split':
            text = '%s is split across %d added runs: %s'
        else:
            text = '%s gathers lines from %d removed runs: %s'
        return ['  ' + text % (fmt_range(n['run']), len(n['runs']),
                               ', '.join(fmt_range(r) for r in n['runs']))]

    def run(r):
        return ['  %s -> %s' % (fmt_range(r['removed']),
                                ', '.join(fmt_range(a) for a in r['lands_in']) or
                                '(no moved lines)')]

    def moved(b):
        return ['  %s -> %s (%s)' % (fmt_range(b['removed']), fmt_range(b['added']),
                                     plural(b['lines'], 'line'))]

    rep.section('Files', j['files'], changed_file_rows)
    rep.section('Unaccounted removed lines', j['unaccounted_removed'], line_rows)
    rep.section('Unaccounted added lines', j['unaccounted_added'], line_rows)
    rep.section('Reordered or interleaved moved lines', j['order_problems'], order)
    rep.section('File-level problems', j['file_problems'], problem_rows)
    rep.section('Run notices, failures only with --strict-runs', j['run_notices'], notice)
    rep.section('Declared removed lines, not checked', j['declared_removed'], line_rows)
    rep.section('Declared added lines, not checked', j['declared_added'], line_rows)
    rep.section('Moved blocks', j['moved_blocks'], moved)
    rep.section('Where each removed run went', j['runs'], run)
    rules_rows(rep, j)
    return rep.text()


def format_extract_text(j):
    rep = Report()
    out = rep.out
    out.append(compared_text(j['compared']))
    out.append('Check: --extract (declared blocks, compared from the file contents)')
    out.append(result_text(j))
    k = j['counts']
    out.append('Lines: %d extracted in %s, %d declared removed, %d declared added'
               % (k['extracted_lines'], plural(k['extractions'], 'block'), k['declared_removed'],
                  k['declared_added']))

    def block(b):
        text = '  %s -> %s (%s' % (fmt_range(b['source']), fmt_range(b['destination']),
                                   plural(b['lines'], 'line'))
        if b['destination_lines'] != b['lines']:
            text += '; the destination has %d' % b['destination_lines']
        return [text + ')']

    def mismatch(m):
        s, d = m['source'], m['destination']
        return ['  %s:%d -> %s:%d:' % (esc(s['path']), s['line'], esc(d['path']), d['line']),
                '    old: %s' % s['text'], '    new: %s' % d['text']]

    mismatches = [m for b in j['extractions'] for m in b['mismatches']]
    rep.section('Files', j['files'], changed_file_rows)
    rep.section('Extracted blocks', j['extractions'], block)
    rep.section('Mismatched lines in extracted blocks', mismatches, mismatch, k['mismatches'])
    rep.section('Unaccounted removed lines', j['unaccounted_removed'], line_rows,
                k['unaccounted_removed'])
    rep.section('Unaccounted added lines', j['unaccounted_added'], line_rows,
                k['unaccounted_added'])
    rep.section('File-level problems', j['file_problems'], problem_rows)
    rep.section('Declared removed lines, not checked', j['declared_removed'], line_rows)
    rep.section('Declared added lines, not checked', j['declared_added'], line_rows)
    rules_rows(rep, j)
    return rep.text()


def format_show_lines_text(j):
    rep = Report()
    out = rep.out
    out.append(compared_text(j['compared']))
    out.append('Line numbers for --extract, --allow-removed and --allow-added, from the contents '
               'and the diff this tool uses (git diff-pairs --histogram). Each row is old line, '
               'new line, mark (- removed, + added), text.')
    for f in j['files']:
        out.append('')
        out.append('%s %s' % (f['status'], esc(f['path'])))
        out.append('  removed (old side): %s' % (', '.join(esc(r) for r in f['removed']) or 'none'))
        out.append('  added (new side): %s' % (', '.join(esc(r) for r in f['added']) or 'none'))
        out.append('%8s%8s' % ('old', 'new'))
        for r in f['lines']:
            out.append('%8s%8s %s %s' % ('' if r['old'] is None else r['old'],
                                         '' if r['new'] is None else r['new'], r['mark'],
                                         r['text']))
    rep.section('File-level problems', j['file_problems'], problem_rows)
    return rep.text()


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ToolError(message)


class HelpFormatter(argparse.HelpFormatter):
    """Wraps help text without breaking it at hyphens, so options are never split."""

    def _split_lines(self, text, width):
        return textwrap.wrap(' '.join(text.split()), width, break_on_hyphens=False,
                             break_long_words=False)

    def _fill_text(self, text, width, indent):
        return '\n\n'.join(textwrap.fill(' '.join(p.split()), width, initial_indent=indent,
                                         subsequent_indent=indent, break_on_hyphens=False,
                                         break_long_words=False) for p in text.split('\n\n'))


HELP_EPILOG = '\n\n'.join([
    EXIT_STATUS,
    'Budgets: ' + _BUDGET_LINES + ' ' + _BUDGET_FILES + ' Files over %s are refused (not '
    'compared).' % _mb(MAX_BLOB_BYTES),
])


def main(argv):
    try:
        return run_main(argv)
    except Exception as e:
        message = ' '.join(str(e).split())
        sys.stderr.write('pure_move.py: error: unexpected %s%s\n'
                         % (type(e).__name__, ': ' + message if message else ''))
        return 2


def run_main(argv):
    parser = Parser(prog='pure_move.py', description=GIT_VERSION_NOTE, epilog=HELP_EPILOG,
                    formatter_class=HelpFormatter)
    parser.add_argument('revs', nargs='*', metavar='REV',
                        help='a commit, checked against its parent, or two commits OLD NEW, the '
                        'first checked against the second')
    parser.add_argument('--staged', action='store_true', help='check HEAD against the index')
    parser.add_argument('--extract', action='append', default=[],
                        metavar='OLDPATH:A-B=NEWPATH:C-D',
                        help='declare that old lines A-B of OLDPATH moved and are new lines C-D '
                        'of NEWPATH; selects the extraction mode; may be repeated')
    parser.add_argument('--allow-added', action='append', default=[], metavar='PATH:N[-M]',
                        help='declare new-side lines as new code, listed and not checked; may be '
                        'repeated')
    parser.add_argument('--allow-removed', action='append', default=[], metavar='PATH:N[-M]',
                        help='declare old-side lines as removed code, listed and not checked; '
                        'may be repeated')
    parser.add_argument('--strict-runs', action='store_true',
                        help='pairing mode only: run notices are failures')
    parser.add_argument('--show-lines', action='store_true',
                        help='list every changed file with the old and new line number of each '
                        'line, to write declarations from; checks nothing')
    parser.add_argument('--repo', default='.',
                        help='the repository (default: the current directory)')
    parser.add_argument('--json', action='store_true', help='machine-readable output')
    try:
        args = parser.parse_args(argv)
        if args.staged and args.revs:
            raise ToolError('--staged takes no revisions')
        if args.staged:
            mode = 'staged'
        elif len(args.revs) == 1:
            mode = 'commit'
        elif len(args.revs) == 2:
            mode = 'range'
        else:
            raise ToolError('give one revision, two revisions, or --staged')
        if args.show_lines and (args.extract or args.allow_added or args.allow_removed or
                                args.strict_runs):
            raise ToolError('--show-lines takes no declarations and no --strict-runs')
        if args.extract and args.strict_runs:
            raise ToolError('--extract cannot be combined with --strict-runs; it replaces it')
        try:
            allow_added = [parse_declaration(s) for s in args.allow_added]
            allow_removed = [parse_declaration(s) for s in args.allow_removed]
            extractions = [parse_extraction(s) for s in args.extract]
        except ValueError as e:
            raise ToolError(str(e))
        git = Git(args.repo)
        top = git.text(['rev-parse', '--show-toplevel'], check=False)
        if not top:
            raise ToolError('not in a git work tree: %s' % args.repo)
        git = Git(top)
        if args.show_lines:
            result = show_lines(git, mode, args.revs)
        else:
            result = check(git, mode, args.revs, allow_added, allow_removed, args.strict_runs,
                           extractions)
    except ToolError as e:
        sys.stderr.write('pure_move.py: error: %s\n' % e)
        return 2
    if args.json:
        sys.stdout.write(json.dumps(result, indent=2, sort_keys=True) + '\n')
    else:
        sys.stdout.write(format_text(result))
    return result['exit_code']


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(errors='backslashreplace')
    sys.exit(main(sys.argv[1:]))
