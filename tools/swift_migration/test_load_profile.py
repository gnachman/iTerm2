#!/usr/bin/env python3
"""Per-test CPU, thread and load profile of a ModernTests run.

Part of the Objective-C to Swift migration tooling. Written for the unit
suite-load-causes (2026-11-23), after a sanitized suite run on a 16-core Mac
took the load average to 467: it tells which tests occupy many cores, spin,
or leave threads behind, so that they can be fixed (docs/swift-migration/
test-speed.md, docs/swift-migration/bugs.md). macOS only.

Usage:
  test_load_profile.py run [options] [TEST ...] [-- COMMAND ...]
  test_load_profile.py analyze RUN_DIR [--top N]

run starts a serial test run (one test host, so that one test runs at a
time) and samples the test host while it runs. With no COMMAND it runs, under
nice -n 15,

  xcodebuild test -project iTerm2.xcodeproj -scheme ModernTests
      -only-testing:TEST ... -parallel-testing-enabled NO
      -test-timeouts-enabled YES -default-test-execution-time-allowance 120
      -maximum-test-execution-time-allowance 120
      CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

(with -jobs N after -scheme when given --jobs N; the allowance, XCTest's
per-test time limit, from --test-allowance-seconds and
--max-test-allowance-seconds, 0 for none) from the repository root,
the same test command tools/run_tests.expect runs (address sanitizer and
all, as the ModernTests test plan has it) plus the allowance. TEST is an
-only-testing name such as ModernTests/TokenBudgetTests. With no TEST the
whole suite runs: do that only when nothing else is using the machine (at
night), never while the owner works. A whole-suite run (no TEST and no
COMMAND) holds the machine-wide whole-suite lock of suite_guard.py while it
runs, waiting for it unless --no-wait (then status 75 when it is held):
one whole suite at a time on the machine (docs/swift-migration/
orchestration.md section 3). With `-- COMMAND` no lock is taken here; a
whole-suite script given as COMMAND takes it itself. With `-- COMMAND ...` that command runs
instead, also under nice -n 15 (for example sanitizer_tests.sh plain
--no-build TEST, or xcodebuild test-without-building -xctestrun FILE); it
must run its tests serially, since attribution needs one test at a time, and
its test host must be under one of the --host-prefix directories.

The command runs on a pseudo-terminal, so that xcodebuild writes each line
as it happens, in its own session and process group. Each output line is
timestamped on arrival. These lines move the attribution:

  Test Suite 'Foo' started at ...          the class Foo is set up
  Test Case '-[ModernTests.Foo testBar]' started.
  Test Case '-[ModernTests.Foo testBar]' passed (1.234 seconds).
                                           (any status: failed, skipped, ...)

Every --interval seconds (default 0.1), and once more at each of those
lines, the sampler reads every test host with libproc (proc_pidinfo
PROC_PIDTASKINFO): CPU time (user plus system), number of threads, number
of threads running at that instant, and resident memory. It adds the CPU
time of the host's descendants (shells, tmux and other programs a test
starts), but not of a descendant that started and exited between two
samples. A test host is a process that did not exist when the run started,
whose executable path starts with one of the --host-prefix directories
(default: this checkout's Build/ and tmp/sanitizers/) and ends in
iTerm2.app/Contents/MacOS/iTerm2, and whose arguments contain
`-suite iterm2-tests`, the suite xcodebuild's test hosts run with (the
argument tools/run_tests.expect also goes by). A development build started
with `make run` is under Build/ too, but runs with `-suite <checkout name>`,
so it is never a test host; nor is a process whose arguments cannot be read.
The load average is recorded with each sample, for context only.

Priority: nice -n 15 reaches xcodebuild and the build it runs, but not the
test hosts, which launchd starts at normal priority. The tests measured run
as they do in any other test run.

A sample's CPU time goes to the test that was running when it was taken;
time outside any test goes to "Foo (outside tests)" for class Foo (its
+setUp, the time between tests) or to "(no test)". For each test:

  reported   the duration xcodebuild printed
  wall       seconds from its "started" line to its result line, as seen
  cpu        CPU seconds the test host and its descendants used meanwhile
  cores      cpu / wall: the average number of cores it kept busy; left
             empty for a test whose wall time is under 0.05 s, since a result
             line can arrive some milliseconds late and the ratio is then
             noise (CORES_MIN_WALL)
  peak%      the highest CPU percent over one sampling interval (100 = one
             core; intervals shorter than half of --interval are ignored)
  thr        the most threads the host had during the test
  run        the most threads running at one instant: the test's share of
             the load average
  thr+       threads at its end minus threads at its start: threads (or
             timers, animations, sessions) it left running
  rssMB      the largest resident memory, in MB

Output goes to RUN_DIR (default tmp/test-load/<time>/ in this checkout):
  command.txt   the command run
  output.log    the command's output, each line prefixed by its arrival time
                (seconds since the epoch, a tab)
  samples.jsonl one JSON object per sample: t, bucket, cpu (seconds, hosts
                and descendants), threads, running, rss (bytes), hosts (pids),
                load (1-minute load average)
  profile.tsv   one row per test and per bucket outside tests, by cpu
  summary.txt   the top --top rows by cpu, by peak running threads and by
                threads left behind, then the totals
analyze RUN_DIR rebuilds profile.tsv and summary.txt from output.log and
samples.jsonl, so a run can be re-read with other options.

Stopping. Interrupting run (INT, TERM, HUP), a run longer than --timeout
seconds, and no output for --stall-seconds seconds (default 600, behind the
per-test allowance; 0 turns it
off) each kill the command's process group with SIGKILL, and then the test
hosts seen during this run. Just before each signal the pid is checked
again: its path and arguments must still make it a test host, and it must
not have existed when the run started. After a normal end, the test hosts
seen during the run are killed too, as tools/run_tests.expect does. A
test host that another test run starts in the same checkout while this one
runs cannot be told apart from this run's own, so it would be sampled and
killed: run nothing else in the checkout meanwhile (the build-lane rule
already says so). Exit status: the command's, or 1 when it was killed, 2
for a usage error.

Memory: samples go to disk as they are taken; only per-test totals are kept.

Over the whole suite, at night, with nothing else running:
  python3 -B tools/swift_migration/test_load_profile.py run --top 40
Over a few classes:
  python3 -B tools/swift_migration/test_load_profile.py run \\
      ModernTests/TokenBudgetTests ModernTests/PathSnifferTests
Over the fast tier's build, no address sanitizer, after
tools/swift_migration/sanitizer_tests.sh plain --build-only:
  python3 -B tools/swift_migration/test_load_profile.py run -- \\
      tools/swift_migration/sanitizer_tests.sh plain --no-build \\
      ModernTests/TokenBudgetTests
"""

import argparse
import ctypes
import ctypes.util
import json
import os
import pty
import re
import select
import signal
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

HOST_SUFFIX = 'iTerm2.app/Contents/MacOS/iTerm2'
ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
SUITE_START = re.compile(r"^Test Suite '([^']+)' started at ")
SUITE_END = re.compile(r"^Test Suite '([^']+)' (?:passed|failed) at ")
CASE_START = re.compile(r"^Test Case '-\[(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*) "
                        r"([A-Za-z_][A-Za-z0-9_:]*)\]' started\.$")
CASE_END = re.compile(r"^Test Case '-\[(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*) "
                      r"([A-Za-z_][A-Za-z0-9_:]*)\]' (.+?) \(([0-9.]+) seconds\)\.?$")
# Suites that are not test classes.
NON_CLASS_SUITES = ('All tests', 'Selected tests')

NO_TEST = '(no test)'
# The arguments every xcodebuild test host is started with.
TEST_HOST_SUITE = ('-suite', 'iterm2-tests')
# Below this wall time a test's cores (cpu / wall) is not reported.
CORES_MIN_WALL = 0.05


# --- Parsing ----------------------------------------------------------------

def parse_event(raw):
    """The attribution event a line of xcodebuild output is, or None:
    ('suite_start', class), ('suite_end', class), ('test_start', class,
    method), ('test_end', class, method, status, seconds)."""
    line = ANSI.sub('', raw).rstrip('\r\n')
    m = CASE_START.match(line)
    if m:
        return ('test_start', m.group(1), m.group(2))
    m = CASE_END.match(line)
    if m:
        return ('test_end', m.group(1), m.group(2), m.group(3), float(m.group(4)))
    m = SUITE_START.match(line)
    if m and m.group(1) not in NON_CLASS_SUITES and not m.group(1).endswith('.xctest'):
        return ('suite_start', m.group(1))
    m = SUITE_END.match(line)
    if m and m.group(1) not in NON_CLASS_SUITES and not m.group(1).endswith('.xctest'):
        return ('suite_end', m.group(1))
    return None


def outside_bucket(cls):
    return '%s (outside tests)' % cls if cls else NO_TEST


class Attribution:
    """Which bucket samples belong to, moved by events."""

    def __init__(self):
        self.suite = None
        self.test = None

    def bucket(self):
        if self.test:
            return self.test
        return outside_bucket(self.suite)

    def apply(self, event):
        kind = event[0]
        if kind == 'suite_start':
            self.suite = event[1]
            self.test = None
        elif kind == 'suite_end':
            self.suite = None
            self.test = None
        elif kind == 'test_start':
            self.suite = event[1]
            self.test = '%s/%s' % (event[1], event[2])
        elif kind == 'test_end':
            self.test = None


# --- Aggregation ------------------------------------------------------------

class Stats:
    __slots__ = ('name', 'status', 'reported', 'start', 'end', 'cpu', 'peak_pct', 'peak_threads',
                 'peak_running', 'threads_start', 'threads_end', 'rss_peak', 'samples')

    def __init__(self, name):
        self.name = name
        self.status = ''
        self.reported = None
        self.start = None
        self.end = None
        self.cpu = 0.0
        self.peak_pct = 0.0
        self.peak_threads = 0
        self.peak_running = 0
        self.threads_start = None
        self.threads_end = None
        self.rss_peak = 0
        self.samples = 0

    def wall(self):
        if self.start is None or self.end is None:
            return None
        return max(0.0, self.end - self.start)

    def thread_delta(self):
        if self.threads_start is None or self.threads_end is None:
            return None
        return self.threads_end - self.threads_start


class Profile:
    """Per-bucket totals from a time-ordered stream of samples and events.

    feed_sample takes a sample dict (t, bucket, cpu, threads, running, rss,
    hosts); feed_event takes (t, event). A sample's bucket is the one in
    force when it was taken; the run loop takes a sample just before each
    event, so a test's first and last samples bracket it."""

    def __init__(self, interval):
        self.interval = interval
        self.stats = {}
        self.prev = None
        self.first_t = None
        self.last_t = None
        self.total_cpu = 0.0
        self.peak_load = 0.0

    def get(self, name):
        s = self.stats.get(name)
        if s is None:
            s = self.stats[name] = Stats(name)
        return s

    def feed_sample(self, sample):
        t = sample['t']
        if self.first_t is None:
            self.first_t = t
        self.last_t = t
        self.peak_load = max(self.peak_load, sample.get('load') or 0.0)
        s = self.get(sample['bucket'])
        s.samples += 1
        s.peak_threads = max(s.peak_threads, sample['threads'])
        s.peak_running = max(s.peak_running, sample['running'])
        s.rss_peak = max(s.rss_peak, sample['rss'])
        prev = self.prev
        self.prev = sample
        if prev is None:
            return
        dt = t - prev['t']
        # CPU only counts between two samples of the same hosts: a host that
        # starts (or restarts after a crash) begins a new baseline.
        if set(prev['hosts']) != set(sample['hosts']) or not sample['hosts']:
            return
        dcpu = sample['cpu'] - prev['cpu']
        if dcpu < 0:
            # A descendant exited and took its CPU time with it.
            return
        s.cpu += dcpu
        self.total_cpu += dcpu
        if dt >= self.interval / 2:
            s.peak_pct = max(s.peak_pct, 100.0 * dcpu / dt)

    def feed_event(self, t, event, threads):
        """threads: the host's thread count in the sample taken just before
        the event, or None."""
        kind = event[0]
        if kind == 'test_start':
            s = self.get('%s/%s' % (event[1], event[2]))
            s.start = t
            s.threads_start = threads
        elif kind == 'test_end':
            s = self.get('%s/%s' % (event[1], event[2]))
            s.end = t
            s.status = event[3]
            s.reported = event[4]
            s.threads_end = threads

    def rows(self):
        return sorted(self.stats.values(), key=lambda s: (-s.cpu, s.name))


def fmt(value, spec):
    return '' if value is None else format(value, spec)


TSV_HEADER = ['test', 'status', 'reported', 'wall', 'cpu', 'cores', 'peak%', 'thr', 'run', 'thr+', 'rssMB', 'samples']


def row_fields(s):
    wall = s.wall()
    cores = s.cpu / wall if wall is not None and wall >= CORES_MIN_WALL else None
    return [s.name, s.status, fmt(s.reported, '.3f'), fmt(wall, '.3f'), '%.3f' % s.cpu, fmt(cores, '.2f'),
            '%.0f' % s.peak_pct, str(s.peak_threads), str(s.peak_running), fmt(s.thread_delta(), 'd'),
            '%.0f' % (s.rss_peak / 1048576.0), str(s.samples)]


def write_tsv(profile, path):
    with open(path, 'w') as f:
        f.write('\t'.join(TSV_HEADER) + '\n')
        for s in profile.rows():
            f.write('\t'.join(row_fields(s)) + '\n')


def table(rows):
    """Aligned text for a list of Stats."""
    lines = [TSV_HEADER] + [row_fields(s) for s in rows]
    widths = [max(len(line[i]) for line in lines) for i in range(len(TSV_HEADER))]
    out = []
    for line in lines:
        out.append('  '.join(line[i].ljust(widths[i]) if i == 0 else line[i].rjust(widths[i])
                             for i in range(len(line))))
    return '\n'.join(out)


def summary_text(profile, top):
    rows = profile.rows()
    tests = [s for s in rows if s.start is not None]
    out = []
    out.append('By CPU time (top %d of %d rows, tests and time outside tests):' % (top, len(rows)))
    out.append(table(rows[:top]))
    out.append('')
    out.append('By most threads running at one instant (tests):')
    out.append(table(sorted(tests, key=lambda s: (-s.peak_running, -s.cpu, s.name))[:top]))
    out.append('')
    leavers = [s for s in tests if (s.thread_delta() or 0) > 0]
    out.append('Tests that ended with more threads than they started with (%d):' % len(leavers))
    out.append(table(sorted(leavers, key=lambda s: (-s.thread_delta(), s.name))[:top]))
    out.append('')
    wall = (profile.last_t - profile.first_t) if profile.first_t is not None else 0.0
    out.append('Tests: %d. Sampled for %.1f s; CPU %.1f s in total (%.2f cores on average). '
               'Highest 1-minute load average seen (whole machine): %.1f.'
               % (len(tests), wall, profile.total_cpu, profile.total_cpu / wall if wall else 0.0,
                  profile.peak_load))
    return '\n'.join(out) + '\n'


def analyze(run_dir, interval=None, top=25):
    """Rebuilds the profile from a run directory's output.log and
    samples.jsonl, writes profile.tsv and summary.txt, returns the Profile."""
    meta = {}
    meta_path = os.path.join(run_dir, 'meta.json')
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
    if interval is None:
        interval = meta.get('interval', 0.1)
    profile = Profile(interval)
    events = []
    with open(os.path.join(run_dir, 'output.log'), errors='replace') as f:
        for line in f:
            t, _, text = line.partition('\t')
            event = parse_event(text)
            if event:
                events.append((float(t), event))
    # Merge by time; an event goes after the samples taken at or before it.
    ei = 0
    last_threads = None
    with open(os.path.join(run_dir, 'samples.jsonl')) as f:
        for line in f:
            sample = json.loads(line)
            while ei < len(events) and events[ei][0] < sample['t']:
                profile.feed_event(events[ei][0], events[ei][1], last_threads)
                ei += 1
            profile.feed_sample(sample)
            last_threads = sample['threads'] if sample['hosts'] else last_threads
    while ei < len(events):
        profile.feed_event(events[ei][0], events[ei][1], last_threads)
        ei += 1
    write_tsv(profile, os.path.join(run_dir, 'profile.tsv'))
    text = summary_text(profile, top)
    with open(os.path.join(run_dir, 'summary.txt'), 'w') as f:
        f.write(text)
    return profile, text


# --- Sampling with libproc ----------------------------------------------------

PROC_PIDTASKINFO = 4
PROC_PIDT_SHORTBSDINFO = 13
PROC_PIDPATHINFO_MAXSIZE = 4096


class ProcTaskInfo(ctypes.Structure):
    _fields_ = [('pti_virtual_size', ctypes.c_uint64), ('pti_resident_size', ctypes.c_uint64),
                ('pti_total_user', ctypes.c_uint64), ('pti_total_system', ctypes.c_uint64),
                ('pti_threads_user', ctypes.c_uint64), ('pti_threads_system', ctypes.c_uint64),
                ('pti_policy', ctypes.c_int32), ('pti_faults', ctypes.c_int32),
                ('pti_pageins', ctypes.c_int32), ('pti_cow_faults', ctypes.c_int32),
                ('pti_messages_sent', ctypes.c_int32), ('pti_messages_received', ctypes.c_int32),
                ('pti_syscalls_mach', ctypes.c_int32), ('pti_syscalls_unix', ctypes.c_int32),
                ('pti_csw', ctypes.c_int32), ('pti_threadnum', ctypes.c_int32),
                ('pti_numrunning', ctypes.c_int32), ('pti_priority', ctypes.c_int32)]


class ProcBSDShortInfo(ctypes.Structure):
    _fields_ = [('pbsi_pid', ctypes.c_uint32), ('pbsi_ppid', ctypes.c_uint32),
                ('pbsi_pgid', ctypes.c_uint32), ('pbsi_status', ctypes.c_uint32),
                ('pbsi_comm', ctypes.c_char * 16), ('pbsi_flags', ctypes.c_uint32),
                ('pbsi_uid', ctypes.c_uint32), ('pbsi_gid', ctypes.c_uint32),
                ('pbsi_ruid', ctypes.c_uint32), ('pbsi_rgid', ctypes.c_uint32),
                ('pbsi_svuid', ctypes.c_uint32), ('pbsi_svgid', ctypes.c_uint32),
                ('pbsi_rfu', ctypes.c_uint32)]


class MachTimebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]


class Libproc:
    def __init__(self):
        lib = ctypes.CDLL(ctypes.util.find_library('proc') or '/usr/lib/libproc.dylib', use_errno=True)
        self.lib = lib
        lib.proc_listallpids.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.proc_listallpids.restype = ctypes.c_int
        lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
        lib.proc_pidinfo.restype = ctypes.c_int
        lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        lib.proc_pidpath.restype = ctypes.c_int
        system = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
        self.libc = system
        system.sysctl.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_void_p, ctypes.c_void_p,
                                  ctypes.c_void_p, ctypes.c_size_t]
        system.sysctl.restype = ctypes.c_int
        argmax = ctypes.c_int(0)
        argmax_size = ctypes.c_size_t(ctypes.sizeof(argmax))
        mib = (ctypes.c_int * 2)(1, 8)  # CTL_KERN, KERN_ARGMAX
        if system.sysctl(mib, 2, ctypes.byref(argmax), ctypes.byref(argmax_size), None, 0) != 0:
            argmax.value = 1 << 20
        self.argmax = argmax.value
        tb = MachTimebase()
        system.mach_timebase_info(ctypes.byref(tb))
        # proc_taskinfo times are in Mach absolute time units on Apple
        # silicon (nanoseconds on Intel, where the ratio is 1).
        self.ticks_to_seconds = tb.numer / tb.denom / 1e9

    def pids(self):
        n = self.lib.proc_listallpids(None, 0)
        if n <= 0:
            return []
        buf = (ctypes.c_int * (n + 256))()
        n = self.lib.proc_listallpids(buf, ctypes.sizeof(buf))
        return [buf[i] for i in range(max(0, n))]

    def path(self, pid):
        buf = ctypes.create_string_buffer(PROC_PIDPATHINFO_MAXSIZE)
        n = self.lib.proc_pidpath(pid, buf, PROC_PIDPATHINFO_MAXSIZE)
        return buf.raw[:n].decode('utf-8', 'replace') if n > 0 else None

    def args(self, pid):
        """The process's arguments (argv) from sysctl KERN_PROCARGS2, or None
        if they cannot be read."""
        mib = (ctypes.c_int * 3)(1, 49, pid)  # CTL_KERN, KERN_PROCARGS2
        size = ctypes.c_size_t(self.argmax)
        buf = ctypes.create_string_buffer(self.argmax)
        if self.libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0) != 0 or size.value < 4:
            return None
        return parse_procargs2(buf.raw[:size.value])

    def ppid(self, pid):
        info = ProcBSDShortInfo()
        n = self.lib.proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, ctypes.byref(info), ctypes.sizeof(info))
        return info.pbsi_ppid if n == ctypes.sizeof(info) else None

    def task(self, pid):
        info = ProcTaskInfo()
        n = self.lib.proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ctypes.byref(info), ctypes.sizeof(info))
        if n != ctypes.sizeof(info):
            return None
        cpu = (info.pti_total_user + info.pti_total_system) * self.ticks_to_seconds
        return cpu, info.pti_threadnum, info.pti_numrunning, info.pti_resident_size


def parse_procargs2(raw):
    """argv from a KERN_PROCARGS2 buffer: a 32-bit argc, the executable path,
    NUL padding, then argc NUL-terminated arguments. None if malformed."""
    if len(raw) < 4:
        return None
    argc = int.from_bytes(raw[:4], sys.byteorder)
    rest = raw[4:]
    end = rest.find(b'\0')
    if end < 0:
        return None
    i = end
    while i < len(rest) and rest[i] == 0:
        i += 1
    parts = rest[i:].split(b'\0')
    if argc < 0 or len(parts) < argc:
        return None
    return [p.decode('utf-8', 'replace') for p in parts[:argc]]


def has_test_host_suite(args):
    if not args:
        return False
    return any(tuple(args[i:i + 2]) == TEST_HOST_SUITE for i in range(len(args) - 1))


def is_test_host_path(path, prefixes):
    if not path or not path.endswith('/' + HOST_SUFFIX):
        return False
    return any(path.startswith(p) for p in prefixes)


class Sampler:
    """Reads the test hosts and their descendants. Never signals anything."""

    # launchd starts a test host as xpcproxy, which execs the app under the
    # same pid, so a process that is not a test host is looked at again
    # after this long.
    PATH_RECHECK_SECONDS = 0.5

    def __init__(self, prefixes, proc=None):
        self.prefixes = [os.path.join(os.path.realpath(p), '') for p in prefixes]
        self.proc = proc or Libproc()
        self.verdicts = {}  # pid -> (is a test host, when decided)
        self.clock = time.monotonic
        # Pids that existed before the run: never sampled, never signalled.
        self.excluded = set()

    def exclude_existing(self):
        self.excluded = set(self.proc.pids())

    def is_test_host(self, pid):
        """Read afresh: path under a prefix, the test host executable, and
        -suite iterm2-tests among readable arguments; never a pid that
        existed before the run."""
        if pid in self.excluded:
            return False
        if not is_test_host_path(self.proc.path(pid), self.prefixes):
            return False
        return has_test_host_suite(self.proc.args(pid))

    def host_pids(self, pids):
        hosts = []
        now = self.clock()
        for pid in pids:
            if pid in self.excluded:
                continue
            cached = self.verdicts.get(pid)
            if cached is None or (not cached[0] and now - cached[1] >= self.PATH_RECHECK_SECONDS):
                cached = (self.is_test_host(pid), now)
                self.verdicts[pid] = cached
            if cached[0]:
                hosts.append(pid)
        return hosts

    def sample(self):
        pids = self.proc.pids()
        live = set(pids)
        for pid in list(self.verdicts):
            if pid not in live:
                del self.verdicts[pid]
        hosts = self.host_pids(pids)
        cpu = 0.0
        threads = running = rss = 0
        found = []
        for pid in hosts:
            info = self.proc.task(pid)
            if info is None:
                continue
            found.append(pid)
            cpu += info[0]
            threads += info[1]
            running += info[2]
            rss += info[3]
        if found:
            children = {}
            for pid in pids:
                ppid = self.proc.ppid(pid)
                if ppid:
                    children.setdefault(ppid, []).append(pid)
            stack = [c for h in found for c in children.get(h, [])]
            seen = set(found)
            while stack:
                pid = stack.pop()
                if pid in seen:
                    continue
                seen.add(pid)
                info = self.proc.task(pid)
                if info is not None:
                    cpu += info[0]
                    running += info[2]
                stack.extend(children.get(pid, []))
        return {'cpu': cpu, 'threads': threads, 'running': running, 'rss': rss, 'hosts': sorted(found)}


# --- Running -----------------------------------------------------------------

# XCTest's per-test time allowance for the default command (seconds; XCTest
# rounds up to whole minutes), so that a hung test fails and its host is
# replaced instead of the run waiting for ever (2026-11-24). No test that
# passed took over 13.1 s in the night's sanitized runs (orchestration.md
# section 3 has the evidence and the margins).
DEFAULT_TEST_ALLOWANCE = 120


def allowance_args(allowance, maximum=None):
    if not allowance:
        return []
    return ['-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', str(allowance),
            '-maximum-test-execution-time-allowance', str(maximum or allowance)]


def default_command(tests, jobs=None, allowance=DEFAULT_TEST_ALLOWANCE, maximum=None):
    cmd = ['xcodebuild', 'test', '-project', 'iTerm2.xcodeproj', '-scheme', 'ModernTests']
    if jobs:
        cmd += ['-jobs', str(jobs)]
    cmd += ['-only-testing:%s' % t for t in tests]
    cmd += ['-parallel-testing-enabled', 'NO']
    cmd += allowance_args(allowance, maximum)
    if os.environ.get('SIGNED') != '1':
        cmd += ['CODE_SIGN_IDENTITY=', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGNING_ALLOWED=NO']
    return cmd


class Runner:
    def __init__(self, args, sampler, out_dir):
        self.args = args
        self.sampler = sampler
        self.out_dir = out_dir
        self.lock = threading.Lock()
        self.attribution = Attribution()
        self.samples_file = open(os.path.join(out_dir, 'samples.jsonl'), 'w')
        self.log_file = open(os.path.join(out_dir, 'output.log'), 'w', errors='replace')
        self.stop = threading.Event()
        self.seen_hosts = set()
        self.proc = None

    def take_sample(self):
        """Takes one sample, attributed to the current bucket, writes it and
        returns it. Call with self.lock held."""
        s = self.sampler.sample()
        s['t'] = time.time()
        s['bucket'] = self.attribution.bucket()
        s['load'] = os.getloadavg()[0]
        self.seen_hosts.update(s['hosts'])
        self.samples_file.write(json.dumps(s, separators=(',', ':')) + '\n')
        return s

    def sampler_loop(self):
        while not self.stop.wait(self.args.interval):
            with self.lock:
                self.take_sample()

    def handle_line(self, text):
        event = parse_event(text)
        if not event:
            self.log_file.write('%.6f\t%s\n' % (time.time(), text))
            return
        with self.lock:
            # The event's time is its sample's, so that analyze puts the
            # sample (taken in the old bucket) just before the event.
            sample = self.take_sample()
            self.log_file.write('%.6f\t%s\n' % (sample['t'], text))
            self.attribution.apply(event)

    def kill_everything(self):
        if self.proc is not None and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        self.kill_our_hosts()

    def kill_our_hosts(self):
        """SIGKILL to the test hosts seen during this run, each checked again
        just before (path, arguments, and not older than the run)."""
        for pid in sorted(self.seen_hosts):
            if self.sampler.is_test_host(pid):
                try:
                    os.kill(pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass

    def run(self, cmd):
        self.sampler.exclude_existing()
        master, slave = pty.openpty()
        self.proc = subprocess.Popen(cmd, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=slave, stderr=slave,
                                     start_new_session=True)
        os.close(slave)
        thread = threading.Thread(target=self.sampler_loop, daemon=True)
        thread.start()
        start = time.time()
        last_output = start
        killed = None
        buf = b''

        def on_signal(signum, frame):
            raise KeyboardInterrupt()
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, on_signal)
        try:
            while True:
                now = time.time()
                if self.args.timeout and now - start > self.args.timeout:
                    killed = 'ran longer than --timeout %d s' % self.args.timeout
                    break
                if self.args.stall_seconds and now - last_output > self.args.stall_seconds:
                    killed = 'no output for %d s' % self.args.stall_seconds
                    break
                r, _, _ = select.select([master], [], [], 1.0)
                if not r:
                    if self.proc.poll() is not None:
                        break
                    continue
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    chunk = b''
                if not chunk:
                    break
                last_output = time.time()
                buf += chunk
                while b'\n' in buf:
                    line, buf = buf.split(b'\n', 1)
                    self.handle_line(line.decode('utf-8', 'replace').rstrip('\r'))
                if len(buf) > 1 << 20:
                    self.handle_line(buf.decode('utf-8', 'replace'))
                    buf = b''
        except KeyboardInterrupt:
            killed = 'interrupted'
        finally:
            if buf:
                self.handle_line(buf.decode('utf-8', 'replace').rstrip('\r'))
            if killed:
                self.kill_everything()
            status = self.proc.wait()
            self.stop.set()
            thread.join()
            with self.lock:
                self.take_sample()
            self.kill_our_hosts()
            os.close(master)
            self.samples_file.close()
            self.log_file.close()
        if killed:
            print('test_load_profile.py: %s; killed the command and its test hosts' % killed, file=sys.stderr)
            return 1
        return status


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    command = None
    if '--' in argv:
        i = argv.index('--')
        command = argv[i + 1:]
        argv = argv[:i]
    parser = argparse.ArgumentParser(description='Per-test CPU, thread and load profile of a ModernTests run.',
                                     epilog='See the top of the file for details.')
    sub = parser.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('run', help='run tests serially and profile them')
    r.add_argument('tests', nargs='*', help='-only-testing names; none means the whole suite')
    r.add_argument('--out', help='run directory (default tmp/test-load/<time>)')
    r.add_argument('--interval', type=float, default=0.1, help='seconds between samples (default 0.1)')
    r.add_argument('--host-prefix', action='append',
                   help='directory a test host executable is under (repeatable; default Build/ and '
                        'tmp/sanitizers/ of this checkout)')
    r.add_argument('--timeout', type=int, default=0, help='kill the run after this many seconds (default none)')
    r.add_argument('--stall-seconds', type=int, default=600,
                   help='kill the run after this long with no output (default 600, 0 for never)')
    r.add_argument('--test-allowance-seconds', type=int, default=DEFAULT_TEST_ALLOWANCE,
                   help="default command: XCTest's per-test time allowance (default %d; 0 turns it off)"
                        % DEFAULT_TEST_ALLOWANCE)
    r.add_argument('--max-test-allowance-seconds', type=int,
                   help='default command: the most a test may ask for (default: the allowance)')
    r.add_argument('--jobs', type=int,
                   help='xcodebuild -jobs for the build step of the default command (default: '
                        "xcodebuild's own, one per core)")
    r.add_argument('--top', type=int, default=25)
    r.add_argument('--no-wait', action='store_true',
                   help='whole suite: fail (status 75) instead of waiting when another whole-suite run '
                        'holds the whole-suite lock')
    a = sub.add_parser('analyze', help='rebuild profile.tsv and summary.txt from a run directory')
    a.add_argument('run_dir')
    a.add_argument('--interval', type=float)
    a.add_argument('--top', type=int, default=25)
    args = parser.parse_args(argv)

    if args.cmd == 'analyze':
        if command:
            parser.error('analyze takes no command')
        _, text = analyze(args.run_dir, args.interval, args.top)
        sys.stdout.write(text)
        return 0

    if command is not None and args.tests:
        parser.error('give TEST names or a COMMAND after --, not both')
    if command is not None and args.jobs:
        parser.error('--jobs applies to the default command only')
    if command is not None and not command:
        parser.error('-- must be followed by a command')
    if (args.test_allowance_seconds and args.max_test_allowance_seconds is not None
            and args.max_test_allowance_seconds < args.test_allowance_seconds):
        parser.error('--max-test-allowance-seconds is below --test-allowance-seconds')
    if args.interval < 0.02:
        parser.error('--interval must be at least 0.02')
    cmd = ['nice', '-n', '15'] + (command if command else default_command(
        args.tests, args.jobs, args.test_allowance_seconds, args.max_test_allowance_seconds))
    prefixes = args.host_prefix or [os.path.join(ROOT, 'Build'), os.path.join(ROOT, 'tmp', 'sanitizers')]
    out_dir = args.out or os.path.join(ROOT, 'tmp', 'test-load', time.strftime('%Y%m%d-%H%M%S'))
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'command.txt'), 'w') as f:
        f.write(' '.join(cmd) + '\n')
    with open(os.path.join(out_dir, 'meta.json'), 'w') as f:
        json.dump({'interval': args.interval, 'prefixes': prefixes}, f)
    # The default command with no TEST is the whole suite: it holds the
    # machine-wide whole-suite lock (suite_guard.py) while it runs.
    lock = None
    if command is None and not args.tests:
        import suite_guard
        lock = suite_guard.SuiteLock()
        if not lock.acquire('test_load_profile.py run (whole suite) in %s' % ROOT, cmd, wait=not args.no_wait):
            return suite_guard.EXIT_LOCK_BUSY
    print('test_load_profile.py: running %s\n  output in %s' % (' '.join(cmd), out_dir), file=sys.stderr)
    try:
        runner = Runner(args, Sampler(prefixes), out_dir)
        status = runner.run(cmd)
    finally:
        if lock is not None:
            lock.release()
    _, text = analyze(out_dir, args.interval, args.top)
    sys.stdout.write(text)
    print('test_load_profile.py: command exit status %s; profile in %s' % (status, out_dir), file=sys.stderr)
    return status


if __name__ == '__main__':
    sys.exit(main())
