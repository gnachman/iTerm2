#!/usr/bin/env python3
"""The compiler warning survey of the Objective-C to Swift migration.

Part of the migration process (docs/swift-migration/warnings.md, and
orchestration.md section 9, "iTermStrictWarnings.h and the warning survey on
both architectures"). It answers three questions from the compile commands of
a real Development build, without building the app:

- How many diagnostics does each warning flag produce today, per file and per
  class, in the migration's scope and outside it?
- Which of them appear on one architecture only (arm64 or x86_64)? Those are
  where the Intel and Apple silicon slices may behave differently: BOOL is
  signed char on x86_64 and bool on arm64.
- What must be fixed in one file before it can import iTermStrictWarnings.h?

How it works. tools/swift_migration/codedb/capture_compile_commands.sh writes
one JSON fragment per compiled file (tmp/codedb/cdb-fragments; read only
here). For every C, Objective-C, C++ or Objective-C++ unit of the normal
variant (not the sanitizer variants) whose file is in the repository, the
survey runs Apple's clang (xcrun clang, the compiler that builds the app)
with the captured command, changed as follows:

- removed: -c, -o, dependency-file flags, --serialize-diagnostics, index
  store flags, -gen-cdb-fragment-path, -ivfsstatcache, the build session and
  module cache housekeeping flags, and the module cache path, which is
  replaced by this tool's own cache under the output directory;
- the -include of an Xcode precompiled-header copy is replaced by the prefix
  header source it was built from, so a header changed since the capture is
  read as it is now;
- added: -fsyntax-only -Qunused-arguments -fno-caret-diagnostics
  -fno-color-diagnostics -fdiagnostics-show-option;
- warning flags, by mode:
    baseline    the captured warning flags as they are, -Werror included:
                what the build reports today (it should report nothing);
    strict      every captured warning flag removed, then -Wno-everything
                and the flags of iTermStrictWarnings.h (read from the header,
                so the two cannot drift): exactly the strict set;
    everything  every captured warning flag removed, then -Weverything: the
                full table of warnings.md step 1.
- for x86_64: --target arm64-apple-... becomes x86_64-apple-..., -arch and
  per-architecture directory names likewise, and a virtual file system
  overlay (-ivfsoverlay, a standard clang flag) replaces each generated
  *-Swift.h under Build/ with a copy whose architecture guard also accepts
  x86_64. The capture is an arm64 build, and Xcode wraps a single-architecture
  generated header in "#elif defined(__arm64__)" ... "#else #error
  unsupported Swift architecture". The declarations inside do not depend on
  the architecture unless the Swift source uses #if arch(...), which no Swift
  file of the app targets does (only tests and WebExtensionsFramework, which
  the Objective-C does not import); run "shim-check" to recheck that. A
  universal build would make the overlay unnecessary.

Each unit's stderr is streamed to a file, parsed with a strict regular
expression (lines that do not parse are counted, never dropped silently), and
reduced to the unit's distinct diagnostics. The raw output is kept only for
units that failed or had lines that did not parse.

Diagnostics in headers appear in every unit that includes the header; the
summary keys every diagnostic by (file, line, column, flag) and counts it
once, under the file it is in. A diagnostic in a macro expansion is located
where the macro is expanded, which is also where iTermStrictWarnings.h
applies to it.

Scope comes from inventory.py (exclusion_reason), the single definition of
the migration's scope. A file every captured unit of which is in a test
target (ModernTests) is "test code", and a header takes the category of the
implementation file with its name.

Classes: a line of an implementation file is attributed to the
@implementation it is in. The class names of each file come from the code
database's objc_impl table when a copy is available (--db, default
tmp/warning-survey/codedb.sqlite), and their current lines from the file
itself (an @implementation line up to the next @end); without a database the
file is scanned alone.

Usage:
    warning_survey.py run [--arch arm64|x86_64] [--mode baseline|strict|everything]
                          [--jobs N] [--only SUBSTRING] [--fragments DIR] [--out DIR]
    warning_survey.py summary [--arch A] [--mode M] [--top N] [--json]
    warning_survey.py compare [--mode M] [--examples N] [--json]
    warning_survey.py file PATH [--json]
    warning_survey.py adopters
    warning_survey.py shim-check
    warning_survey.py flags

run writes tmp/warning-survey/<arch>/<mode>/ (units/, raw/ for failures,
run.json). Nothing there is meant to be committed: numbers are regenerated.
--jobs is at most 6 (default 6).

file prints what must be fixed before PATH can import iTermStrictWarnings.h:
the strict-set diagnostics located in PATH itself, from the strict runs of
both architectures (each marked with the architectures it appears on), and
any baseline diagnostic. Diagnostics in headers that PATH imports are not
listed: the header's pragmas apply only after the point where it is imported.

adopters lists the files that import iTermStrictWarnings.h and reports any
that import or include something after it (its pragmas would then apply to
that header too); exit 1 if one does.

Exit status: 0 success; 1 a unit failed to compile (run), units missing from
a summary, or a bad adopter; 2 usage error or missing input.
Python 3 standard library only.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import threading
import time
from collections import Counter, OrderedDict, defaultdict
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import inventory  # noqa: E402  (the scope definition)

DEFAULT_FRAGMENTS = os.path.join(ROOT, 'tmp', 'codedb', 'cdb-fragments')
DEFAULT_OUT = os.path.join(ROOT, 'tmp', 'warning-survey')
DEFAULT_DB = os.path.join(DEFAULT_OUT, 'codedb.sqlite')
STRICT_HEADER_NAME = 'iTermStrictWarnings.h'
STRICT_HEADER = os.path.join(ROOT, 'sources', 'Infrastructure', STRICT_HEADER_NAME)
ARCHES = ('arm64', 'x86_64')
MODES = ('baseline', 'strict', 'everything')
MAX_JOBS = 6
UNIT_TIMEOUT = 600
TEST_TARGETS = ('ModernTests',)
C_FAMILY = ('.m', '.mm', '.c', '.cc', '.cpp')

# Flags of the captured command that take a value and are dropped with it.
DROP_WITH_VALUE = {
    '-o', '-MF', '-MT', '-MQ', '--serialize-diagnostics', '-ivfsstatcache',
    '-index-store-path', '-index-unit-output-path', '-gen-cdb-fragment-path',
}
DROP_SINGLE = {'-c', '-MMD', '-MD', '-M', '-MM', '-fmodules-validate-once-per-build-session',
               '-fcolor-diagnostics', '-fdiagnostics-color'}
DROP_PREFIXES = ('-fbuild-session-file=', '-fmodules-prune-interval=', '-fmodules-prune-after=',
                 '-fmodules-cache-path=', '--serialize-diagnostics=', '-index-')
ADDED = ['-fsyntax-only', '-Qunused-arguments', '-fno-caret-diagnostics', '-fno-color-diagnostics',
         '-fdiagnostics-show-option']

PRAGMA_RE = re.compile(r'^\s*#\s*pragma\s+clang\s+diagnostic\s+error\s+"(-W[A-Za-z0-9_+=-]+)"')

# One diagnostic line of clang's text format with -fno-caret-diagnostics:
#   path:line:col: warning: message [-Wflag]
#   path:line:col: error: message [-Werror,-Wflag]
#   path:line:col: note: message
DIAG_RE = re.compile(
    r'^(?P<file>[^:\n]+(?::(?!\d+:\d+: )[^:\n]+)*):(?P<line>\d+):(?P<col>\d+): '
    r'(?P<level>warning|error|fatal error|note|remark): (?P<msg>.*?)'
    r'(?: \[(?P<opts>-W[A-Za-z0-9_+=#.,-]*(?:,-W[A-Za-z0-9_+=#.,-]*)*)\])?$')
# A diagnostic with no location, from the driver or the frontend.
NOLOC_RE = re.compile(r'^(?P<who>clang|clang\+\+|error|warning|fatal error)(?:: (?P<level>error|warning|fatal error))?: '
                      r'(?P<msg>.*?)(?: \[(?P<opts>-W[^\]]*)\])?$')
IGNORED_RES = (
    re.compile(r'^In file included from .+:\d+:$'),
    re.compile(r'^\s+from .+:\d+:$'),
    re.compile(r'^In module \'[^\']+\' imported from .+:\d+:$'),
    re.compile(r'^While building module \'[^\']+\'.*:$'),
    re.compile(r'^\d+ (warning|error)s? (and \d+ (warning|error)s? )?generated\.$'),
)


class SurveyError(Exception):
    pass


# ---------------------------------------------------------------------------
# The strict set

def strict_flags(header=STRICT_HEADER):
    """The -W flags of iTermStrictWarnings.h, in order."""
    try:
        with open(header, encoding='utf-8') as f:
            flags = [m.group(1) for m in (PRAGMA_RE.match(line) for line in f) if m]
    except OSError as e:
        raise SurveyError('cannot read %s: %s' % (header, e))
    if not flags:
        raise SurveyError('%s has no "#pragma clang diagnostic error" lines' % header)
    return flags


def mode_flags(mode, header=STRICT_HEADER):
    if mode == 'baseline':
        return []
    if mode == 'strict':
        return ['-Wno-everything'] + strict_flags(header)
    if mode == 'everything':
        return ['-Weverything']
    raise SurveyError('unknown mode %r' % mode)


# ---------------------------------------------------------------------------
# Fragments and commands

def read_fragment(path):
    with open(path, encoding='utf-8') as f:
        text = f.read().strip()
    if text.endswith(','):
        text = text[:-1]
    return json.loads(text)


def is_header_fragment(args):
    return any(a.startswith('-x') and a.endswith('-header') for a in args)


def is_sanitizer_output(output):
    return any(s in output for s in ('/Variant-ASan/', '/Variant-TSan/', '-asan/', '-tsan/'))


def target_of(output):
    """The target name from an object path .../T.build/Objects-normal/arm64/x.o, or None."""
    parts = output.split('/')
    for i, p in enumerate(parts):
        if p.startswith('Objects-') and i >= 1 and parts[i - 1].endswith('.build'):
            return parts[i - 1][:-len('.build')]
    return None


def relpath(path, root=ROOT):
    """Repository-relative path, or the absolute path for a file outside the repository."""
    real = os.path.realpath(path)
    r = os.path.realpath(root)
    if real.startswith(r + os.sep):
        return real[len(r) + 1:]
    return real


def unit_id(target, rel):
    return '%s__%s' % (target, rel.replace('/', '__'))


def load_units(fragments_dir, root=ROOT):
    """(units, pch_map, skipped): the units of the normal variant whose main file is in the repository
    and not under Build/, one per (target, file); the prefix header source of each precompiled-header
    copy; and counts of the fragments left out, by reason."""
    if not os.path.isdir(fragments_dir):
        raise SurveyError('no compile command fragments at %s; run '
                          'tools/swift_migration/codedb/capture_compile_commands.sh' % fragments_dir)
    names = sorted(n for n in os.listdir(fragments_dir) if n.endswith('.json'))
    if not names:
        raise SurveyError('no fragments in %s' % fragments_dir)
    frags = [read_fragment(os.path.join(fragments_dir, n)) for n in names]
    pch_map = {}
    for f in frags:
        out = f.get('output', '')
        if is_header_fragment(f['arguments']) and (out.endswith('.gch') or out.endswith('.pch')):
            pch_map[out[:-4] if out.endswith('.gch') else out] = f['file']
    units = OrderedDict()
    skipped = Counter()
    for f in frags:
        out = f.get('output', '')
        if is_header_fragment(f['arguments']):
            skipped['precompiled header'] += 1
            continue
        if is_sanitizer_output(out):
            skipped['sanitizer variant'] += 1
            continue
        target = target_of(out)
        if target is None:
            skipped['unknown output path'] += 1
            continue
        directory = f.get('directory', root)
        file_abs = f['file'] if os.path.isabs(f['file']) else os.path.join(directory, f['file'])
        rel = relpath(file_abs, root)
        if os.path.isabs(rel):
            skipped['outside the repository'] += 1
            continue
        if rel.startswith('Build/'):
            skipped['generated under Build/'] += 1
            continue
        units[(target, rel)] = {'id': unit_id(target, rel), 'target': target, 'file': rel,
                                'directory': directory, 'arguments': f['arguments']}
    return list(units.values()), pch_map, skipped


def is_warning_flag(arg):
    return arg.startswith('-W') and not arg.startswith(('-Wl,', '-Wa,', '-Wp,'))


def to_arch(arg, arch):
    """Rewrite an argument naming arm64 for another architecture."""
    if arch == 'arm64':
        return arg
    if arg.startswith('--target=arm64-'):
        return '--target=' + arch + arg[len('--target=arm64'):]
    if arg.startswith('arm64-apple-'):
        return arch + arg[len('arm64'):]
    if arg == 'arm64':
        return arch
    return re.sub(r'/arm64(?=/|$)', '/' + arch, arg)


def survey_command(unit, mode, arch, pch_map, module_cache, overlay=None, header=STRICT_HEADER,
                   compiler=('xcrun', 'clang')):
    """The argument list (compiler first) that checks one unit in one mode for one architecture."""
    a = list(unit['arguments'][1:])
    args = list(compiler)
    if overlay:
        args += ['-ivfsoverlay', overlay]
    i = 0
    while i < len(a):
        x = a[i]
        nxt = a[i + 1] if i + 1 < len(a) else None
        if x in DROP_WITH_VALUE:
            i += 2
            continue
        if x in DROP_SINGLE or x.startswith(DROP_PREFIXES):
            i += 1
            continue
        if x == '-Xclang' and nxt is not None:
            # A frontend argument travels with its -Xclang; never split the pair.
            if not (mode != 'baseline' and is_warning_flag(nxt)):
                args += [x, nxt]
            i += 2
            continue
        if mode != 'baseline' and is_warning_flag(x):
            i += 1
            continue
        if x == '-include' and nxt is not None and nxt in pch_map:
            args += ['-include', pch_map[nxt]]
            i += 2
            continue
        if x == '-include' and nxt is not None and nxt.endswith('.pch') and not os.path.exists(nxt):
            raise SurveyError('no prefix header source known for precompiled header %s' % nxt)
        if x in ('-arch', '-target') and nxt is not None:
            args += [x, to_arch(nxt, arch)]
            i += 2
            continue
        args.append(to_arch(x, arch))
        i += 1
    args += ADDED + ['-fmodules-cache-path=' + module_cache] + mode_flags(mode, header)
    return args


# ---------------------------------------------------------------------------
# The x86_64 overlay for generated Swift headers

ARM64_GUARD = '#elif defined(__arm64__) && __arm64__'


def generated_swift_headers(root=ROOT):
    """Every *-Swift.h of the normal variant under Build/ that has an arm64 guard and no x86_64 one."""
    base = os.path.join(root, 'Build', 'Intermediates.noindex', 'Variant-NoSanitizers')
    found = []
    for dirpath, dirnames, filenames in os.walk(base):
        for n in filenames:
            if n.endswith('-Swift.h'):
                p = os.path.join(dirpath, n)
                with open(p, encoding='utf-8', errors='replace') as f:
                    head = f.read(4096)
                if ARM64_GUARD in head and '__x86_64__' not in head:
                    found.append(p)
    return sorted(found)


def write_overlay(out_dir, headers):
    """Copies of the headers with the arm64 guard widened to x86_64, and the overlay that maps
    each original path to its copy. Returns the overlay path, or None if there is nothing to map."""
    if not headers:
        return None
    shim = os.path.join(out_dir, 'swift-header-shim')
    os.makedirs(shim, exist_ok=True)
    roots = []
    for p in headers:
        with open(p, encoding='utf-8', errors='surrogateescape') as f:
            text = f.read()
        text = text.replace(ARM64_GUARD, '#elif (defined(__arm64__) && __arm64__) || '
                                         '(defined(__x86_64__) && __x86_64__)', 1)
        copy = os.path.join(shim, hashlib.sha256(p.encode()).hexdigest()[:12] + '-' + os.path.basename(p))
        with open(copy, 'w', encoding='utf-8', errors='surrogateescape') as f:
            f.write(text)
        roots.append({'type': 'file', 'name': p, 'external-contents': copy})
    overlay = os.path.join(out_dir, 'swift-header-overlay.json')
    with open(overlay, 'w', encoding='utf-8') as f:
        json.dump({'version': 0, 'case-sensitive': 'false', 'roots': roots}, f, indent=1)
    return overlay


# ---------------------------------------------------------------------------
# Parsing

class UnitParse:
    def __init__(self):
        self.diags = OrderedDict()   # (file, line, col, flag) -> [level, message]
        self.unparsed = []
        self.notes = 0
        self.errors = 0
        self.first_error = None


def flag_of(opts, level):
    """The warning flag of a diagnostic: the last -W option that is not -Werror; 'error' for an error
    with none (a hard error); '' for a warning with none."""
    if opts:
        names = [o for o in opts.split(',') if o.startswith('-W') and not o.startswith('-Werror')]
        if names:
            return names[-1]
    return 'error' if level in ('error', 'fatal error') else ''


OPTS_TAIL_RE = re.compile(r'^(?P<msg>.*?) \[(?P<opts>-W[A-Za-z0-9_+=#.,-]*(?:,-W[A-Za-z0-9_+=#.,-]*)*)\]$')


def parse_lines(lines, directory, root=ROOT, _cache=None):
    """Parse clang's text diagnostics. Paths are made repository-relative (relative paths are
    resolved against the unit's directory).

    A message can span lines: clang prints a type such as typeof(({ ... })) from a MIN or MAX
    macro, or a macro name after a backslash-newline, verbatim, so the [-Wflag] is on the last
    line. A line that matches nothing else is taken as a continuation only while the message so
    far has an unclosed single quote; otherwise it is counted as unparsed."""
    cache = {} if _cache is None else _cache
    p = UnitParse()
    pending = None   # [level, path, line, col, msg, opts] of a diagnostic not yet recorded

    def finish():
        level, path, line, col, msg, opts = pending
        if level == 'note':
            p.notes += 1
            return
        if path is None:
            if level in ('clang', 'clang++'):
                level = 'warning'
            key_path, line, col = '<command line>', 0, 0
        else:
            key_path = cache.get((directory, path))
            if key_path is None:
                key_path = relpath(path if os.path.isabs(path) else os.path.join(directory, path), root)
                cache[(directory, path)] = key_path
        flag = flag_of(opts, level)
        if flag == 'error':
            p.errors += 1
            if p.first_error is None:
                p.first_error = '%s:%s:%s: %s: %s' % (key_path, line, col, level, msg)
        key = (key_path, int(line), int(col), flag)
        if key not in p.diags:
            p.diags[key] = [level, msg]

    for raw in lines:
        line = raw.rstrip('\n')
        m = DIAG_RE.match(line)
        n = None if m else NOLOC_RE.match(line)
        if m or n or any(r.match(line) for r in IGNORED_RES):
            if pending:
                finish()
                pending = None
            if m:
                pending = [m.group('level'), m.group('file'), m.group('line'), m.group('col'), m.group('msg'),
                           m.group('opts')]
            elif n:
                pending = [n.group('level') or n.group('who'), None, 0, 0, n.group('msg'), n.group('opts')]
            continue
        if pending and pending[5] is None and pending[4].count("'") % 2 == 1:
            t = OPTS_TAIL_RE.match(line)
            if t:
                pending[4] += '\n' + t.group('msg')
                pending[5] = t.group('opts')
            else:
                pending[4] += '\n' + line
            continue
        if not line.strip():
            continue
        p.unparsed.append(line)
    if pending:
        finish()
    return p


# ---------------------------------------------------------------------------
# Running

def kill_group(pid):
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def run_unit(unit, cmd, out_dir, timeout=UNIT_TIMEOUT):
    """Run one unit's check with its stderr streamed to a file, parse it, and write the unit record."""
    raw_dir = os.path.join(out_dir, 'raw')
    units_dir = os.path.join(out_dir, 'units')
    raw = os.path.join(raw_dir, unit['id'] + '.txt')
    start = time.time()
    with open(raw, 'wb') as err:
        proc = subprocess.Popen(cmd, cwd=unit['directory'], stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=err, start_new_session=True)
        timed_out = []
        timer = threading.Timer(timeout, lambda: (timed_out.append(True), kill_group(proc.pid)))
        timer.start()
        try:
            _, status, usage = os.wait4(proc.pid, 0)
        finally:
            timer.cancel()
        proc.returncode = os.waitstatus_to_exitcode(status)
        kill_group(proc.pid)   # nothing of the unit outlives it
    elapsed = time.time() - start
    with open(raw, encoding='utf-8', errors='replace') as f:
        parsed = parse_lines(f, unit['directory'])
    record = {'unit': unit['id'], 'target': unit['target'], 'file': unit['file'],
              'exit': proc.returncode, 'timed_out': bool(timed_out), 'seconds': round(elapsed, 3),
              'max_rss_mb': round(usage.ru_maxrss / (1024 * 1024), 1), 'errors': parsed.errors,
              'first_error': parsed.first_error, 'notes': parsed.notes,
              'unparsed': len(parsed.unparsed), 'unparsed_examples': parsed.unparsed[:5],
              'diagnostics': len(parsed.diags)}
    tmp = os.path.join(units_dir, unit['id'] + '.jsonl.tmp')
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(json.dumps(record) + '\n')
        for (path, line, col, flag), (level, msg) in parsed.diags.items():
            f.write(json.dumps([path, line, col, flag, level, msg]) + '\n')
    os.replace(tmp, os.path.join(units_dir, unit['id'] + '.jsonl'))
    if proc.returncode == 0 and not parsed.unparsed:
        os.unlink(raw)
    return record


def cmd_run(args):
    if args.jobs < 1 or args.jobs > MAX_JOBS:
        raise SurveyError('--jobs must be between 1 and %d' % MAX_JOBS)
    units, pch_map, skipped = load_units(args.fragments)
    if args.only:
        units = [u for u in units if args.only in u['file']]
    if not units:
        raise SurveyError('no units to check')
    arch_dir = os.path.join(args.out, args.arch)
    out_dir = os.path.join(arch_dir, args.mode)
    if os.path.isdir(out_dir) and not args.only:
        shutil.rmtree(out_dir)
    os.makedirs(os.path.join(out_dir, 'raw'), exist_ok=True)
    os.makedirs(os.path.join(out_dir, 'units'), exist_ok=True)
    module_cache = os.path.join(args.out, 'modcache', args.arch, args.mode)
    os.makedirs(module_cache, exist_ok=True)
    overlay = None
    shimmed = []
    if args.arch != 'arm64':
        shimmed = generated_swift_headers()
        overlay = write_overlay(arch_dir, shimmed)
    cmds = [(u, survey_command(u, args.mode, args.arch, pch_map, module_cache, overlay)) for u in units]
    print('warning survey: %d units, arch %s, mode %s, %d jobs -> %s'
          % (len(units), args.arch, args.mode, args.jobs, out_dir), flush=True)
    start = time.time()
    done = [0]
    lock = threading.Lock()
    records = []

    def one(item):
        rec = run_unit(item[0], item[1], out_dir)
        with lock:
            done[0] += 1
            records.append(rec)
            if rec['exit'] != 0 or rec['unparsed']:
                print('  %s: exit %d%s%s' % (rec['file'], rec['exit'], ' (timed out)' if rec['timed_out'] else '',
                                              ', %d unparsed lines' % rec['unparsed'] if rec['unparsed'] else ''),
                      flush=True)
            if done[0] % 100 == 0:
                print('  %d/%d units, %.0f s' % (done[0], len(cmds), time.time() - start), flush=True)
        return rec

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(one, cmds))
    wall = time.time() - start
    failed = [r for r in records if r['exit'] != 0]
    run = {'arch': args.arch, 'mode': args.mode, 'jobs': args.jobs, 'units': len(records),
           'failed': len(failed), 'unparsed_lines': sum(r['unparsed'] for r in records),
           'wall_seconds': round(wall, 1), 'cpu_seconds_sum': round(sum(r['seconds'] for r in records), 1),
           'max_rss_mb': max(r['max_rss_mb'] for r in records), 'skipped_fragments': dict(skipped),
           'fragments': args.fragments, 'only': args.only, 'shimmed_swift_headers': shimmed,
           'compiler': subprocess.run(['xcrun', 'clang', '--version'], capture_output=True,
                                      text=True).stdout.splitlines()[0],
           'strict_flags': strict_flags() if args.mode == 'strict' else None,
           'finished': time.strftime('%Y-%m-%dT%H:%M:%S')}
    with open(os.path.join(out_dir, 'run.json'), 'w', encoding='utf-8') as f:
        json.dump(run, f, indent=1)
    print('done: %d units in %.0f s wall (%.0f s summed), %d failed, %d unparsed lines, max RSS %.0f MB'
          % (len(records), wall, run['cpu_seconds_sum'], len(failed), run['unparsed_lines'], run['max_rss_mb']))
    return 1 if failed else 0


# ---------------------------------------------------------------------------
# Reading results

def read_results(out_dir):
    """(records, diags): every unit record, and every distinct diagnostic of the run keyed by
    (file, line, col, flag) -> [level, message, units containing it]. Streams one unit at a time."""
    units_dir = os.path.join(out_dir, 'units')
    if not os.path.isdir(units_dir):
        raise SurveyError('no survey at %s; run "warning_survey.py run" first' % out_dir)
    records = []
    diags = {}
    for n in sorted(os.listdir(units_dir)):
        if not n.endswith('.jsonl'):
            continue
        with open(os.path.join(units_dir, n), encoding='utf-8') as f:
            records.append(json.loads(f.readline()))
            for line in f:
                path, ln, col, flag, level, msg = json.loads(line)
                key = (path, ln, col, flag)
                d = diags.get(key)
                if d is None:
                    diags[key] = [level, msg, 1]
                else:
                    d[2] += 1
    return records, diags


class Scope:
    """Classifies repository files with inventory.exclusion_reason, plus test code from the units."""

    def __init__(self, records):
        targets = defaultdict(set)
        for r in records:
            targets[r['file']].add(r['target'])
        self.test_files = {f for f, ts in targets.items() if ts and ts <= set(TEST_TARGETS)}
        self.test_stems = {os.path.splitext(f)[0] for f in self.test_files}
        self._cache = {}

    def category(self, path):
        c = self._cache.get(path)
        if c is None:
            c = self._category(path)
            self._cache[path] = c
        return c

    def _category(self, path):
        if path == '<command line>':
            return 'command line'
        if os.path.isabs(path):
            return 'outside the repository (SDK)'
        if path.startswith('Build/'):
            return 'generated under Build/'
        if path in self.test_files or (path.endswith('.h') and os.path.splitext(path)[0] in self.test_stems):
            return 'test code'
        reason = inventory.exclusion_reason(path)
        if reason is None:
            return 'in scope'
        if reason == inventory.OUTSIDE_SCOPE:
            top = path.split('/')[0]
            return 'test code' if top in TEST_TARGETS else 'outside scope: %s/' % (
                '/'.join(path.split('/')[:2]) if top == 'ThirdParty' else top)
        return reason


IMPL_RE = re.compile(r'^\s*@implementation\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*\(\s*([A-Za-z_0-9]*)\s*\))?')
END_RE = re.compile(r'^\s*@end\b')


class Classes:
    """Maps (file, line) to the @implementation that contains it."""

    def __init__(self, db_path=None, root=ROOT):
        self.root = root
        self.names = None
        self.source = 'the files alone'
        if db_path and os.path.exists(db_path):
            try:
                con = sqlite3.connect('file:%s?mode=ro' % db_path, uri=True)
                self.names = defaultdict(set)
                for cls, cat, file in con.execute('SELECT DISTINCT class_name, category, file FROM objc_impl'):
                    self.names[relpath(file, root) if os.path.isabs(file) else file].add(
                        cls + ('(%s)' % cat if cat is not None else ''))
                con.close()
                self.source = 'objc_impl of %s, with current lines from the files' % db_path
            except sqlite3.Error as e:
                self.names = None
                self.source = 'the files alone (database unreadable: %s)' % e
        self._ranges = {}

    def ranges(self, path):
        r = self._ranges.get(path)
        if r is not None:
            return r
        r = []
        full = os.path.join(self.root, path)
        if not os.path.isabs(path) and path.endswith(('.m', '.mm')) and os.path.exists(full):
            wanted = self.names.get(path) if self.names is not None else None
            with open(full, encoding='utf-8', errors='replace') as f:
                lines = f.readlines()
            open_impl = None
            for i, line in enumerate(lines, 1):
                m = IMPL_RE.match(line)
                if m:
                    name = m.group(1) + ('(%s)' % m.group(2) if m.group(2) is not None else '')
                    if wanted is None or name in wanted or m.group(1) in {w.split('(')[0] for w in wanted}:
                        open_impl = (name, i)
                    continue
                if open_impl and END_RE.match(line):
                    r.append((open_impl[1], i, open_impl[0]))
                    open_impl = None
        self._ranges[path] = r
        return r

    def class_of(self, path, line):
        for start, end, name in self.ranges(path):
            if start <= line <= end:
                return name
        return None


def results_dir(out, arch, mode):
    return os.path.join(out, arch, mode)


def covered_files(fragments, records):
    """The files the capture covers (all of its units, not only those of a partial run)."""
    try:
        return {u['file'] for u in load_units(fragments)[0]}
    except (SurveyError, OSError, ValueError):
        return {r['file'] for r in records}


def summarize(out, arch, mode, db_path, top, fragments=DEFAULT_FRAGMENTS):
    d = results_dir(out, arch, mode)
    records, diags = read_results(d)
    run = {}
    if os.path.exists(os.path.join(d, 'run.json')):
        with open(os.path.join(d, 'run.json'), encoding='utf-8') as f:
            run = json.load(f)
    scope = Scope(records)
    classes = Classes(db_path)
    per_flag = defaultdict(Counter)
    per_file = defaultdict(Counter)
    per_class = defaultdict(Counter)
    categories = Counter()
    for (path, line, col, flag), (level, msg, n) in diags.items():
        if flag == 'error':
            continue
        cat = scope.category(path)
        categories[cat] += 1
        per_flag[flag][cat] += 1
        if cat == 'in scope':
            per_file[path][flag] += 1
            cls = classes.class_of(path, line)
            if cls:
                per_class[cls][flag] += 1
    failed = [r for r in records if r['exit'] != 0]
    flags = sorted(per_flag, key=lambda f: (-per_flag[f]['in scope'], -sum(per_flag[f].values()), f))
    return {
        'arch': arch, 'mode': mode, 'units': len(records), 'run': run,
        'failed_units': [{'file': r['file'], 'target': r['target'], 'exit': r['exit'],
                          'first_error': r['first_error']} for r in failed],
        'unparsed_lines': sum(r['unparsed'] for r in records),
        'unparsed_examples': [e for r in records for e in r['unparsed_examples']][:10],
        'distinct_diagnostics': sum(categories.values()),
        'units_with_diagnostics_by_target': dict(Counter(r['target'] for r in records if r['diagnostics']).most_common()),
        'units_by_target': dict(Counter(r['target'] for r in records).most_common()),
        'by_category': dict(categories.most_common()),
        'per_flag': [{'flag': f or '(no flag)', 'in_scope': per_flag[f]['in scope'],
                      'outside_scope': sum(v for k, v in per_flag[f].items() if k != 'in scope'),
                      'by_category': dict(per_flag[f].most_common())} for f in flags],
        'files_in_scope_with_hits': len(per_file),
        'top_files': [{'file': p, 'count': sum(c.values()), 'flags': dict(c.most_common(5))}
                      for p, c in sorted(per_file.items(), key=lambda kv: (-sum(kv[1].values()), kv[0]))[:top]],
        'classes_with_hits': len(per_class),
        'top_classes': [{'class': k, 'count': sum(c.values()), 'flags': dict(c.most_common(5))}
                        for k, c in sorted(per_class.items(), key=lambda kv: (-sum(kv[1].values()), kv[0]))[:top]],
        'class_source': classes.source,
        'not_surveyed': not_surveyed(covered_files(fragments, records)),
    }


def not_surveyed(covered, root=ROOT):
    """Implementation files tracked by git in the scope directories or ModernTests that no captured unit
    covers, grouped by why, and captured files that no longer exist."""
    roots = list(inventory.SCOPE_ROOTS) + list(TEST_TARGETS)
    try:
        listed = subprocess.run(['git', '-C', root, 'ls-files', '-z', '--'] + roots, capture_output=True,
                                check=True).stdout.decode('utf-8', 'surrogateescape').split('\0')
    except (OSError, subprocess.CalledProcessError):
        return {'error': 'git ls-files failed'}
    own_projects = {inventory.scope_root_of(p) for p in listed
                    if p.endswith('/project.pbxproj') and inventory.scope_root_of(p)}
    groups = defaultdict(list)
    for p in listed:
        if not p.endswith(C_FAMILY) or p in covered or not os.path.exists(os.path.join(root, p)):
            continue
        why = inventory.exclusion_reason(p)
        if why not in (None, inventory.OUTSIDE_SCOPE):
            continue
        sr = inventory.scope_root_of(p)
        if sr in own_projects:
            groups['built by the Xcode project in %s/ (not part of the capture)' % sr].append(p)
        else:
            groups['no captured command (added since the capture, or not compiled)'].append(p)
    gone = sorted(f for f in covered if not os.path.exists(os.path.join(root, f)))
    return {'groups': {k: sorted(v) for k, v in sorted(groups.items())}, 'captured_but_gone': gone}


def print_summary(s):
    run = s['run']
    print('Warning survey: arch %s, mode %s' % (s['arch'], s['mode']))
    if run:
        print('  %s; %d units in %.0f s wall with %d jobs (%.0f s summed); max RSS of one compile %.0f MB'
              % (run.get('compiler', '?'), run.get('units', 0), run.get('wall_seconds', 0), run.get('jobs', 0),
                 run.get('cpu_seconds_sum', 0), run.get('max_rss_mb', 0)))
        if run.get('only'):
            print('  PARTIAL RUN: only files containing %r' % run['only'])
    print('  units read: %d; failed to compile: %d; unparsed output lines: %d'
          % (s['units'], len(s['failed_units']), s['unparsed_lines']))
    for u in s['failed_units']:
        print('    FAILED %s [%s] exit %d: %s' % (u['file'], u['target'], u['exit'], u['first_error']))
    for e in s['unparsed_examples']:
        print('    unparsed: %s' % e)
    print('  units with any diagnostic, by target (units with a diagnostic / units):')
    for t, n in s['units_by_target'].items():
        print('    %-40s %d / %d' % (t, s['units_with_diagnostics_by_target'].get(t, 0), n))
    print('  distinct diagnostics (by file, line, column and flag): %d' % s['distinct_diagnostics'])
    for k, v in s['by_category'].items():
        print('    %-40s %d' % (k, v))
    print()
    print('Per flag (in scope / outside scope):')
    for f in s['per_flag']:
        print('  %-55s %7d %7d' % (f['flag'], f['in_scope'], f['outside_scope']))
    print()
    print('Top files in scope (%d files have hits):' % s['files_in_scope_with_hits'])
    for f in s['top_files']:
        print('  %6d  %s  %s' % (f['count'], f['file'], ', '.join('%s %d' % kv for kv in f['flags'].items())))
    print()
    print('Top classes in scope (%d classes have hits; classes from %s):' % (s['classes_with_hits'], s['class_source']))
    for c in s['top_classes']:
        print('  %6d  %s  %s' % (c['count'], c['class'], ', '.join('%s %d' % kv for kv in c['flags'].items())))
    ns = s['not_surveyed']
    print()
    if 'error' in ns:
        print('Not surveyed: %s' % ns['error'])
    else:
        for why, files in ns['groups'].items():
            print('Not surveyed, %s: %d' % (why, len(files)))
            if 'Xcode project' not in why:
                for p in files:
                    print('  %s' % p)
        if ns['captured_but_gone']:
            print('Captured but no longer in the tree: %d' % len(ns['captured_but_gone']))
            for p in ns['captured_but_gone']:
                print('  %s' % p)


def cmd_summary(args):
    s = summarize(args.out, args.arch, args.mode, args.db, args.top, args.fragments)
    if args.json:
        json.dump(s, sys.stdout, indent=1)
        print()
    else:
        print_summary(s)
    return 1 if s['failed_units'] else 0


def compare(out, mode, examples):
    """Diagnostics present on one architecture only, keyed by (file, line, col, flag)."""
    rec_a, diags_a = read_results(results_dir(out, 'arm64', mode))
    rec_b, diags_b = read_results(results_dir(out, 'x86_64', mode))
    scope = Scope(rec_a + rec_b)
    result = OrderedDict()
    for name, mine, other in (('arm64 only', diags_a, diags_b), ('x86_64 only', diags_b, diags_a)):
        by_flag = defaultdict(lambda: {'in_scope': 0, 'outside_scope': 0, 'examples': []})
        for key, (level, msg, n) in mine.items():
            if key in other or key[3] == 'error':
                continue
            path, line, col, flag = key
            e = by_flag[flag]
            cat = scope.category(path)
            if cat == 'in scope':
                e['in_scope'] += 1
                if len(e['examples']) < examples:
                    e['examples'].append('%s:%d:%d: %s' % (path, line, col, msg))
            else:
                e['outside_scope'] += 1
        result[name] = OrderedDict(sorted(by_flag.items(), key=lambda kv: (-kv[1]['in_scope'], kv[0])))
    failed = {'arm64': [r['file'] for r in rec_a if r['exit'] != 0],
              'x86_64': [r['file'] for r in rec_b if r['exit'] != 0]}
    return {'mode': mode, 'failed_units': failed, 'one_architecture_only': result}


def cmd_compare(args):
    c = compare(args.out, args.mode, args.examples)
    if args.json:
        json.dump(c, sys.stdout, indent=1)
        print()
        return 0
    print('Diagnostics on one architecture only (mode %s; keyed by file, line, column and flag):' % c['mode'])
    for arch, files in c['failed_units'].items():
        if files:
            print('  units that failed on %s (not compared): %s' % (arch, ', '.join(files)))
    for name, flags in c['one_architecture_only'].items():
        total_in = sum(e['in_scope'] for e in flags.values())
        total_out = sum(e['outside_scope'] for e in flags.values())
        print('\n%s: %d in scope, %d outside scope' % (name, total_in, total_out))
        for flag, e in flags.items():
            print('  %-50s %6d %6d' % (flag or '(no flag)', e['in_scope'], e['outside_scope']))
            for x in e['examples']:
                print('      %s' % x)
    return 0


def file_report(out, path, db_path):
    """What must be fixed in PATH before it can import iTermStrictWarnings.h."""
    rel = relpath(os.path.join(ROOT, path) if not os.path.isabs(path) else path)
    report = {'file': rel, 'strict': [], 'baseline': [], 'missing_runs': [], 'failed': [], 'units': 0}
    merged = OrderedDict()
    for arch in ARCHES:
        for mode in ('strict', 'baseline'):
            d = results_dir(out, arch, mode)
            units_dir = os.path.join(d, 'units')
            if not os.path.isdir(units_dir):
                report['missing_runs'].append('%s/%s' % (arch, mode))
                continue
            for n in os.listdir(units_dir):
                if not n.endswith('.jsonl'):
                    continue
                with open(os.path.join(units_dir, n), encoding='utf-8') as f:
                    rec = json.loads(f.readline())
                    is_unit = rec['file'] == rel
                    if is_unit and mode == 'strict':
                        report['units'] += 1
                    if is_unit and rec['exit'] != 0 and mode == 'baseline':
                        report['failed'].append('%s %s [%s]: %s' % (arch, mode, rec['target'], rec['first_error']))
                    if not is_unit and not rel.endswith('.h'):
                        continue
                    for line in f:
                        p, ln, col, flag, level, msg = json.loads(line)
                        if p != rel or flag == 'error':
                            continue
                        k = (mode, ln, col, flag)
                        e = merged.setdefault(k, {'line': ln, 'col': col, 'flag': flag, 'message': msg,
                                                  'arches': []})
                        if arch not in e['arches']:
                            e['arches'].append(arch)
    for (mode, ln, col, flag), e in sorted(merged.items(), key=lambda kv: (kv[0][1], kv[0][2], kv[0][3])):
        report[mode].append(e)
    classes = Classes(db_path)
    for e in report['strict']:
        e['class'] = classes.class_of(rel, e['line'])
    report['flag_counts'] = dict(Counter(e['flag'] for e in report['strict']).most_common())
    report['adoption'] = adoption_problem(os.path.join(ROOT, rel)) if os.path.exists(os.path.join(ROOT, rel)) else None
    return report


def cmd_file(args):
    r = file_report(args.out, args.path, args.db)
    if args.json:
        json.dump(r, sys.stdout, indent=1)
        print()
        return 0
    print('%s: %d strict-set diagnostics to resolve before it can import %s'
          % (r['file'], len(r['strict']), STRICT_HEADER_NAME))
    if r['file'].endswith('.h'):
        print('  (a header never imports %s; these are the hits located in the header, which an importing\n'
              '  file does not see, since the pragmas apply only after the import point)' % STRICT_HEADER_NAME)
    if r['missing_runs']:
        print('  runs not found (run them for a complete answer): %s' % ', '.join(r['missing_runs']))
    if not r['units'] and not r['file'].endswith('.h'):
        print('  WARNING: no unit compiles this file in the strict runs found (no captured command?)')
    for x in r['failed']:
        print('  FAILED TO COMPILE: %s' % x)
    for flag, n in r['flag_counts'].items():
        print('  %-50s %d' % (flag, n))
    for e in r['strict']:
        only = '' if len(e['arches']) == len(ARCHES) else '  [%s only]' % '+'.join(e['arches'])
        print('  %d:%d: [%s] %s%s%s' % (e['line'], e['col'], e['flag'], e['message'], only,
                                        '  (in %s)' % e['class'] if e.get('class') else ''))
    if r['baseline']:
        print('Diagnostics with the project\'s own flags (the build should have none):')
        for e in r['baseline']:
            print('  %d:%d: [%s] %s  [%s]' % (e['line'], e['col'], e['flag'], e['message'], '+'.join(e['arches'])))
    if r['adoption']:
        print('ADOPTION PROBLEM: %s' % r['adoption'])
    return 0


IMPORT_RE = re.compile(r'^\s*#\s*(import|include)\s*[<"]([^>"]+)[>"]')
MODULE_IMPORT_RE = re.compile(r'^\s*@import\s+[A-Za-z_]')


def adoption_problem(path):
    """None if the file does not import the strict header or imports it last; otherwise what is wrong."""
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
    except OSError as e:
        return 'unreadable: %s' % e
    seen = None
    for i, line in enumerate(lines, 1):
        m = IMPORT_RE.match(line)
        if m and os.path.basename(m.group(2)) == STRICT_HEADER_NAME:
            if path.endswith('.h'):
                return 'line %d: a header imports %s' % (i, STRICT_HEADER_NAME)
            seen = i
            continue
        if seen and (m or MODULE_IMPORT_RE.match(line)):
            return 'line %d imports %s after %s (line %d), so its pragmas apply to it' % (
                i, m.group(2) if m else line.strip(), STRICT_HEADER_NAME, seen)
    return None


def cmd_adopters(args):
    try:
        out = subprocess.run(['git', '-C', ROOT, 'grep', '-l', '-I', STRICT_HEADER_NAME, '--'] +
                             ['*' + e for e in C_FAMILY + ('.h',)], capture_output=True, text=True).stdout
    except OSError as e:
        raise SurveyError('git grep failed: %s' % e)
    files = []
    bad = 0
    for p in out.split():
        if os.path.basename(p) == STRICT_HEADER_NAME or p.startswith('tools/swift_migration/'):
            continue
        with open(os.path.join(ROOT, p), encoding='utf-8', errors='replace') as f:
            if not any(IMPORT_RE.match(l) and os.path.basename(IMPORT_RE.match(l).group(2)) == STRICT_HEADER_NAME
                       for l in f):
                continue
        problem = adoption_problem(os.path.join(ROOT, p))
        files.append(p)
        if problem:
            bad += 1
            print('%s: %s' % (p, problem))
    print('%d files import %s; %d with a problem' % (len(files), STRICT_HEADER_NAME, bad))
    return 1 if bad else 0


def cmd_shim_check(args):
    """Recheck the premise of the x86_64 overlay: no Swift file of a target whose generated header the
    Objective-C imports uses #if arch(...)."""
    out = subprocess.run(['git', '-C', ROOT, 'grep', '-n', '-E', r'#if.*[^A-Za-z0-9_]arch\(', '--', '*.swift'],
                         capture_output=True, text=True).stdout
    hits = [l for l in out.splitlines() if l]
    shimmed = generated_swift_headers()
    print('generated Swift headers that the x86_64 runs replace with a widened copy: %d' % len(shimmed))
    for p in shimmed:
        print('  %s' % relpath(p))
    print('Swift files with #if arch(...): %d' % len(hits))
    for h in hits:
        print('  %s' % h)
    print('The overlay is exact only if none of these is in sources/ (the app targets whose generated '
          'header Objective-C imports).')
    return 1 if any(h.startswith('sources/') for h in hits) else 0


def cmd_flags(args):
    for f in strict_flags(args.header):
        print(f)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=DEFAULT_OUT, help='survey directory (default tmp/warning-survey)')
    sub = ap.add_subparsers(dest='command', required=True)
    r = sub.add_parser('run')
    r.add_argument('--arch', choices=ARCHES, default='arm64')
    r.add_argument('--mode', choices=MODES, default='strict')
    r.add_argument('--jobs', type=int, default=MAX_JOBS)
    r.add_argument('--only', help='only units whose file path contains this text (a partial run)')
    r.add_argument('--fragments', default=DEFAULT_FRAGMENTS)
    s = sub.add_parser('summary')
    s.add_argument('--arch', choices=ARCHES, default='arm64')
    s.add_argument('--mode', choices=MODES, default='strict')
    s.add_argument('--top', type=int, default=30)
    s.add_argument('--db', default=DEFAULT_DB)
    s.add_argument('--json', action='store_true')
    s.add_argument('--fragments', default=DEFAULT_FRAGMENTS)
    c = sub.add_parser('compare')
    c.add_argument('--mode', choices=MODES, default='strict')
    c.add_argument('--examples', type=int, default=3)
    c.add_argument('--json', action='store_true')
    f = sub.add_parser('file')
    f.add_argument('path')
    f.add_argument('--db', default=DEFAULT_DB)
    f.add_argument('--json', action='store_true')
    sub.add_parser('adopters')
    sub.add_parser('shim-check')
    fl = sub.add_parser('flags')
    fl.add_argument('--header', default=STRICT_HEADER)
    args = ap.parse_args(argv)
    handlers = {'run': cmd_run, 'summary': cmd_summary, 'compare': cmd_compare, 'file': cmd_file,
                'adopters': cmd_adopters, 'shim-check': cmd_shim_check, 'flags': cmd_flags}
    try:
        return handlers[args.command](args)
    except SurveyError as e:
        print('warning_survey: %s' % e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    try:
        sys.exit(main())
    except BrokenPipeError:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
