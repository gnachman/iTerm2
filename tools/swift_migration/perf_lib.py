"""Shared code for the migration's performance and memory baselines.

Used by perf_baseline.py (the runner) and perf_compare.py (the comparison).
See docs/swift-migration/phase0.md section 8 and performance.md section 1.

What lives here, and is unit tested by tests/test_perf_baseline.py:

- The scenario list (SCENARIOS).
- Parsers for the output the scenarios produce: "[MigrationPerf] {json}"
  lines printed by PerformanceTests/MigrationBaselineTests.swift, XCTest's
  "measured [...]" lines, and tools/perf/run_stress_test.sh's summary.
- Parsers for the machine-state commands, and the rule that decides whether
  the machine is quiet enough for a baseline (QUIET_THRESHOLDS).
- Summary statistics, the result file layout (SCHEMA), and the .xctestrun
  patch that gives the test host its -suite argument.

Nothing here records the host name, the user name, or the home directory.
"""

import copy
import fnmatch
import json
import os
import re
import statistics
import subprocess
import time

SCHEMA = 'iterm2-migration-perf/1'

# A run may be labeled a baseline only when every one of these holds, both
# before the first scenario and after the last. Chosen for a desktop Mac that
# is otherwise idle apart from ordinary background processes:
# - load average: at most a quarter of the logical CPUs, for both the 1- and
#   5-minute figures, so nothing else is competing for cores and the recent
#   past was quiet too;
# - memory: at least 30 percent free by memory_pressure, so nothing is paged
#   out during the run;
# - no compiler or build processes running (other agents' builds are the usual
#   source of load on this machine);
# - on AC power, not in Low Power mode, and no thermal or CPU speed limit.
# Swap in use is recorded but not gated on: macOS keeps swapped pages after the
# pressure that caused them has gone, so a quiet machine can still show it.
QUIET_THRESHOLDS = {
    'max_load_per_cpu': 0.25,
    'min_memory_free_percent': 30,
    'build_process_names': ['xcodebuild', 'swift-frontend', 'swift-driver', 'clang', 'clang++', 'ld',
                            'swift-build', 'ibtool', 'actool'],
    'require_ac_power': True,
    # The after-run check: how long to wait, polling, for the 1-minute load
    # average to fall back under the limit once the last scenario is done.
    'after_settle_seconds': 180,
    'after_poll_seconds': 15,
}

AFTER_RULE = ('after the run: the 1-minute load average within after_settle_seconds (the 5-minute '
              'average is not used, since the run itself raises it); every other condition in '
              'every sample')

# Scenarios. "xctest" scenarios run one test of the PerformanceTests target in
# the release configuration, in a test host started with -suite. "stress"
# scenarios run tools/perf/run_stress_test.sh against the release app.
SCENARIOS = [
    {'name': 'parse.mixed_1mb', 'kind': 'xctest',
     'test': 'MigrationBaselineTests/testParseThroughput',
     'what': 'VT100Parser alone on 1 MB of mixed output (ASCII, SGR color, CJK and emoji, cursor moves)'},
    {'name': 'screen.parse_execute_mixed_1mb', 'kind': 'xctest',
     'test': 'MigrationBaselineTests/testParseAndExecuteThroughput',
     'what': 'The same bytes parsed and executed on a 120x50 VT100Screen with a full 10,000-line scrollback'},
    {'name': 'screen.gang_fast_path', 'kind': 'xctest',
     'test': 'PerformanceTests/testGang_fastPathPerformance',
     'what': 'Existing test: 10,000 lines of ASCII through the gang append fast path'},
    {'name': 'screen.char_at_a_time', 'kind': 'xctest',
     'test': 'PerformanceTests/testGang_charAtATimePerformance',
     'what': 'Existing test: the same lines appended a string at a time'},
    {'name': 'draw.attributed_strings_mono', 'kind': 'xctest',
     'test': 'MigrationBaselineTests/testDrawAttributedStringsMono',
     'what': 'Per-row attributed string build for text drawing, 250x80, default colors'},
    {'name': 'draw.attributed_strings_truecolor', 'kind': 'xctest',
     'test': 'MigrationBaselineTests/testDrawAttributedStringsTrueColor',
     'what': 'The same with a 24-bit color per cell'},
    {'name': 'draw.attributed_strings_truecolor_ligatures', 'kind': 'xctest',
     'test': 'MigrationBaselineTests/testDrawAttributedStringsTrueColorLigatures',
     'what': 'The same with ligatures on (CoreText shaping)'},
    {'name': 'memory.scrollback_fill_20k', 'kind': 'xctest',
     'test': 'MigrationBaselineTests/testMemoryScrollbackFill',
     'what': 'Scripted memory workload: fill a 20,000-line scrollback; footprint growth, peak, live allocations'},
    {'name': 'app.stress_normal_1tab', 'kind': 'stress', 'mode': 'normal', 'tabs': 1, 'fps': None,
     'what': 'run_stress_test.sh --mode=normal, 1 tab'},
    {'name': 'app.stress_buffer_1tab', 'kind': 'stress', 'mode': 'buffer', 'tabs': 1, 'fps': None,
     'what': 'run_stress_test.sh --mode=buffer (long lines), 1 tab'},
    {'name': 'app.stress_clearcodes_1tab', 'kind': 'stress', 'mode': 'clearcodes', 'tabs': 1, 'fps': None,
     'what': 'run_stress_test.sh --mode=clearcodes, 1 tab'},
    {'name': 'app.stress_flood_1tab', 'kind': 'stress', 'mode': 'flood', 'tabs': 1, 'fps': None,
     'rate': False, 'what': 'run_stress_test.sh --mode=flood (yes), 1 tab; no iteration rate, since '
     '`yes` writes no iteration counts and the script always reports 0'},
    {'name': 'app.stress_normal_10tabs', 'kind': 'stress', 'mode': 'normal', 'tabs': 10, 'fps': None,
     'what': 'run_stress_test.sh --mode=normal, 10 tabs (the script default)'},
    {'name': 'app.stress_htop_unthrottled_1tab', 'kind': 'stress', 'mode': 'htop', 'tabs': 1, 'fps': 0,
     'what': 'run_stress_test.sh --mode=htop --fps=0: scroll regions and partial updates, unthrottled'},
]


# Metrics that are recorded but not usable as a gate, so perf_compare.py shows
# them without comparing them. What each memory metric of
# memory.scrollback_fill_20k can detect, from the spreads measured on
# 2026-11-20 (a busy machine, 5 samples):
# - memory_peak_physical (XCTest, 0.1% spread): the usable memory gate.
# - process_peak_footprint: one sample per run, so always inconclusive.
# - footprint_growth and memory_physical (about 150 to 200% spread): no signal.
# - live_malloc_blocks (17% spread): would always be inconclusive, so the
#   allocation count is not effectively compared today.
# - live_malloc_bytes (0.0% spread, but a net change over a sample): a uniform
#   regression in what each screen allocates would be largely cancelled by the
#   previous sample's screen giving back the same amount.
# The explanation for the noise and the cancellation, that one sample's screen
# is freed lazily on its own queues while the next sample runs, is a
# hypothesis, not verified. Making the live allocation metrics deterministic
# (a fresh process per sample, or draining the previous screen before
# sampling) is an open point in performance.md section 3.
INFORMATIONAL_METRICS = {
    ('memory.scrollback_fill_20k', 'footprint_growth'),
    ('memory.scrollback_fill_20k', 'memory_physical'),
    ('memory.scrollback_fill_20k', 'live_malloc_blocks'),
    ('memory.scrollback_fill_20k', 'live_malloc_bytes'),
}


def scenario_named(name):
    for s in SCENARIOS:
        if s['name'] == name:
            return s
    raise KeyError(name)


def select_scenarios(patterns):
    """Scenarios matching any of the shell-style patterns, in SCENARIOS order.
    None selects all. A pattern that matches nothing is an error."""
    if not patterns:
        return list(SCENARIOS)
    chosen = []
    for pattern in patterns:
        matched = [s for s in SCENARIOS if fnmatch.fnmatchcase(s['name'], pattern)]
        if not matched:
            raise ValueError('no scenario matches %r' % pattern)
        chosen.extend(matched)
    names = {s['name'] for s in chosen}
    return [s for s in SCENARIOS if s['name'] in names]


# ---------------------------------------------------------------------------
# Output parsers

_MIGRATION_PERF = re.compile(r'^\[MigrationPerf\] (\{.*\})\s*$')


def parse_migration_perf_lines(text):
    """Metrics printed by MigrationBaselineTests: one JSON object per line."""
    found = []
    for line in text.splitlines():
        m = _MIGRATION_PERF.match(line.strip())
        if not m:
            continue
        try:
            obj = json.loads(m.group(1))
        except ValueError:
            continue
        if not isinstance(obj, dict):
            continue
        if obj.get('better') not in ('lower', 'higher'):
            continue
        values = obj.get('values')
        if not isinstance(values, list) or not all(isinstance(v, (int, float)) for v in values):
            continue
        if not all(isinstance(obj.get(k), str) and obj.get(k) for k in ('scenario', 'metric', 'unit')):
            continue
        found.append({'scenario': obj['scenario'], 'metric': obj['metric'], 'unit': obj['unit'],
                      'better': obj['better'], 'values': values})
    return found


_XCTEST_MEASURED = re.compile(
    r"Test Case '-\[(?:[\w.]+\.)?(\w+) (\w+)\]' measured \[([^,\]]+), ([^\]]+)\] .*?"
    r"values: \[([^\]]*)\](?:.*?polarity: prefers (smaller|larger))?")

_UNITS = {'seconds': 's', 's': 's', 'kB': 'kB', 'kb': 'kB'}


def _slug(name):
    return re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')


def parse_xctest_measurements(text):
    """XCTest's 'measured [Name, unit] ... values: [...]' lines."""
    found = []
    for line in text.splitlines():
        m = _XCTEST_MEASURED.search(line)
        if not m:
            continue
        cls, test, name, unit, values, polarity = m.groups()
        try:
            numbers = [float(v) for v in values.split(',') if v.strip()]
        except ValueError:
            continue
        metric = 'time' if name == 'Time' else _slug(name)
        found.append({'test': '%s/%s' % (cls, test), 'metric': metric,
                      'unit': _UNITS.get(unit.strip(), unit.strip()),
                      'better': 'higher' if polarity == 'larger' else 'lower',
                      'values': numbers})
    return found


def parse_xcresult_metrics(obj):
    """XCTest's measurements from `xcresulttool get test-results metrics`
    output (schema 0.4.0), in the same shape as parse_xctest_measurements.
    Xcode 27 prints neither test output nor 'measured' lines to the console,
    so the result bundle is where they are."""
    found = []
    if not isinstance(obj, list):
        return found
    for test in obj:
        if not isinstance(test, dict):
            continue
        ident = str(test.get('testIdentifier', ''))
        if ident.endswith('()'):
            ident = ident[:-2]
        for run in test.get('testRuns') or []:
            for metric in (run or {}).get('metrics') or []:
                name = metric.get('displayName')
                values = metric.get('measurements')
                if not name or not isinstance(values, list):
                    continue
                unit = str(metric.get('unitOfMeasurement', ''))
                found.append({'test': ident, 'metric': 'time' if name == 'Time' else _slug(name),
                              'unit': _UNITS.get(unit, unit),
                              'better': 'higher' if 'larger' in str(metric.get('polarity', '')).lower() else 'lower',
                              'values': [float(v) for v in values]})
    return found


def xctest_outcome(text, test):
    """'passed', 'failed', or None if the test case did not finish. Accepts
    both the older "Test Case '-[Module.Class test]' passed" lines and Xcode
    27's "Test case 'Class.test()' passed on ..." lines."""
    cls, name = test.split('/')
    pattern = re.compile(r"Test [Cc]ase '(?:-\[(?:[\w.]+\.)?%s %s\]|(?:\w+\.)?%s\.%s\(\))' (passed|failed)"
                         % (re.escape(cls), re.escape(name), re.escape(cls), re.escape(name)))
    outcome = None
    for line in text.splitlines():
        m = pattern.search(line)
        if m:
            outcome = m.group(1) if outcome != 'failed' else outcome
    return outcome


def parse_stress_output(text):
    def number(pattern):
        m = re.search(pattern, text, re.M)
        return int(m.group(1)) if m else None
    return {
        'pid': number(r'^Found iTerm2 PID: (\d+)'),
        'iterations_per_sec': number(r'^\s*Rate: (\d+) iterations/sec'),
        'total_iterations': number(r'^\s*Total iterations: (\d+)'),
    }


# ---------------------------------------------------------------------------
# Machine state

def parse_loadavg(text):
    return [float(x) for x in re.findall(r'[\d.]+', text)[:3]]


def parse_memory_free_percent(text):
    m = re.search(r'System-wide memory free percentage: (\d+)%', text)
    return int(m.group(1)) if m else None


def parse_swap_used_mb(text):
    m = re.search(r'used = ([\d.]+)([MG])', text)
    if not m:
        return None
    value = float(m.group(1))
    return value * 1024 if m.group(2) == 'G' else value


def parse_power_source(text):
    m = re.search(r"Now drawing from '([^']+)'", text)
    return m.group(1) if m else 'Unknown'


_POWERMODES = {'0': 'Automatic', '1': 'Low Power', '2': 'High Power'}


def parse_energy_mode(text, power_source):
    """(energy mode, low power mode) for the section of `pmset -g custom`
    that applies to the current power source."""
    section = None
    values = {}
    for line in text.splitlines():
        if line and not line[0].isspace():
            section = line.strip().rstrip(':')
            continue
        if section != power_source:
            continue
        parts = line.split()
        if len(parts) >= 2:
            values[parts[0]] = parts[-1]
    return _POWERMODES.get(values.get('powermode'), 'Unknown'), values.get('lowpowermode') == '1'


def parse_thermal(text):
    """(thermal warning, CPU speed limit or None) from `pmset -g therm`."""
    limit = None
    m = re.search(r'CPU_Speed_Limit\s*=\s*(\d+)', text)
    if m:
        limit = int(m.group(1))
    warned = bool(re.search(r'(thermal|performance) warning level set to', text, re.I))
    return warned or (limit is not None and limit < 100), limit


def _run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return ''


def process_may_be_running(name, run=subprocess.run):
    """False only when pgrep positively reports no process with this exact
    name (exit 1). Any other outcome, including pgrep failing, counts as
    "may be running", which is the safe answer for deciding whether to start
    something that would collide with it."""
    try:
        out = run(['/usr/bin/pgrep', '-x', name], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return True
    return out.returncode != 1


def executable_path(pid):
    """The path of the binary process `pid` is running, from proc_pidpath(3),
    or None if there is no such process or it cannot be read. Unlike `ps -o
    comm=`, which shows argv[0], this cannot be set by the process."""
    import ctypes
    try:
        libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    except OSError:
        return None
    size = 4 * 1024  # PROC_PIDPATHINFO_MAXSIZE
    buf = ctypes.create_string_buffer(size)
    length = libproc.proc_pidpath(ctypes.c_int(pid), buf, ctypes.c_uint32(size))
    if length <= 0:
        return None
    return buf.value.decode('utf-8', 'replace')


def all_pids():
    return [int(x) for x in _run(['/bin/ps', '-axo', 'pid=']).split() if x.isdigit()]


def pids_with_executable(pids, executable, path_of=executable_path):
    """The PIDs among `pids` whose binary is exactly `executable`, by
    proc_pidpath. Never matches by name, argv[0], or prefix."""
    return [pid for pid in pids if path_of(pid) == executable]


def executable_may_be_running(executable, pids=None, path_of=None):
    """False only when the process table was read and no process's binary
    is exactly `executable`, by proc_pidpath. Other copies of the same app
    (another checkout's build, the owner's release) do not count. An empty
    process table means ps failed, and counts as "may be running", the safe
    answer for deciding whether to start a second instance of this path."""
    if pids is None:
        pids = all_pids()
    if not pids:
        return True
    return bool(pids_with_executable(pids, executable, path_of=path_of or executable_path))


def dirty_paths(porcelain):
    """Paths from `git status --porcelain --untracked-files=no
    --ignore-submodules=dirty` that make a tree unfit for a baseline. Only
    docs/ is ignored. A changed submodule pointer counts: the shell
    integration submodule, for one, is copied into the app bundle."""
    paths = []
    for line in porcelain.splitlines():
        path = line[3:].strip()
        if path and not path.startswith('docs/'):
            paths.append(path)
    return paths


def count_processes(names):
    """How many processes have each exact name. Read only: pgrep -x."""
    counts = {}
    for name in names:
        out = _run(['/usr/bin/pgrep', '-x', name])
        n = len([line for line in out.splitlines() if line.strip()])
        if n:
            counts[name] = n
    return counts


def machine_state():
    power = parse_power_source(_run(['/usr/bin/pmset', '-g', 'batt']))
    energy, low_power = parse_energy_mode(_run(['/usr/bin/pmset', '-g', 'custom']), power)
    thermal, limit = parse_thermal(_run(['/usr/bin/pmset', '-g', 'therm']))
    return {
        'load_average': load_average(),
        'logical_cpus': int(_run(['/usr/sbin/sysctl', '-n', 'hw.logicalcpu']).strip() or 0),
        'memory_free_percent': parse_memory_free_percent(_run(['/usr/bin/memory_pressure'])),
        'swap_used_mb': parse_swap_used_mb(_run(['/usr/sbin/sysctl', '-n', 'vm.swapusage'])),
        'power_source': power,
        'energy_mode': energy,
        'low_power_mode': low_power,
        'thermal_warning': thermal,
        'cpu_speed_limit': limit,
        'build_processes': count_processes(QUIET_THRESHOLDS['build_process_names']),
    }


def load_average():
    return parse_loadavg(_run(['/usr/sbin/sysctl', '-n', 'vm.loadavg']))


def _load_limit(state, thresholds):
    cpus = state.get('logical_cpus') or 1
    return thresholds['max_load_per_cpu'] * cpus, cpus


def assess_quiet(state, thresholds=QUIET_THRESHOLDS):
    """(quiet, reasons). Each reason names one condition that failed. The
    strict rule, used before the run: the 1- and 5-minute averages."""
    reasons = []
    limit, cpus = _load_limit(state, thresholds)
    load = state.get('load_average') or []
    if len(load) < 2 or load[0] > limit or load[1] > limit:
        reasons.append('load average %s exceeds %.1f (%.2f per logical CPU, %d CPUs)'
                       % (load, limit, thresholds['max_load_per_cpu'], cpus))
    reasons += _non_load_reasons(state, thresholds)
    return not reasons, reasons


def _one_minute_settled(state, thresholds):
    limit, _ = _load_limit(state, thresholds)
    load = state.get('load_average') or []
    return bool(load) and load[0] <= limit


def judge_after(samples, thresholds=QUIET_THRESHOLDS):
    """The after-run verdict from the samples taken once the last scenario
    finished, in time order, each a machine state with 'elapsed_s'. Load the
    run made itself raises the 5-minute average for minutes, so only the
    1-minute average is used, and it passes if it is under the limit in the
    last sample (settle_after stops as soon as it is). Every other condition
    must hold in every sample, so a build or thermal limit seen while waiting
    still refuses."""
    reasons = []
    for state in samples:
        for reason in _non_load_reasons(state, thresholds):
            if reason not in reasons:
                reasons.append(reason)
    last = samples[-1] if samples else {}
    settled = bool(samples) and _one_minute_settled(last, thresholds)
    if not settled:
        limit, cpus = _load_limit(last, thresholds)
        reasons.append('1-minute load average did not fall to %.1f (%.2f per logical CPU, %d CPUs) within '
                       '%d s after the run; last %s'
                       % (limit, thresholds['max_load_per_cpu'], cpus, thresholds['after_settle_seconds'],
                          last.get('load_average')))
    return {
        'quiet': not reasons,
        'reasons': reasons,
        'rule': AFTER_RULE,
        'load_settled': settled,
        'settled_after_s': last.get('elapsed_s', 0) if settled else None,
        'samples': [{'elapsed_s': s.get('elapsed_s', 0), 'load_average': s.get('load_average'),
                     'reasons': _non_load_reasons(s, thresholds)} for s in samples],
    }


def settle_after(take_state, thresholds=QUIET_THRESHOLDS, monotonic=time.monotonic, sleep=time.sleep):
    """Samples the machine after the run until the after check passes, a
    non-load condition fails (waiting cannot help), or after_settle_seconds
    pass. Returns the samples, each with 'elapsed_s'."""
    start = monotonic()
    samples = []
    while True:
        state = dict(take_state())
        state['elapsed_s'] = round(monotonic() - start, 1)
        samples.append(state)
        verdict = judge_after(samples, thresholds)
        if verdict['quiet'] or verdict['load_settled'] or _non_load_reasons(state, thresholds):
            return samples
        remaining = thresholds['after_settle_seconds'] - (monotonic() - start)
        if remaining <= 0:
            return samples
        sleep(min(thresholds['after_poll_seconds'], remaining))


def _non_load_reasons(state, thresholds):
    reasons = []
    free = state.get('memory_free_percent')
    if free is None or free < thresholds['min_memory_free_percent']:
        reasons.append('memory free %s%% is below %d%%' % (free, thresholds['min_memory_free_percent']))
    builds = state.get('build_processes') or {}
    if builds:
        reasons.append('build processes running: %s'
                       % ', '.join('%s x%d' % (k, v) for k, v in sorted(builds.items())))
    power_problems = []
    if thresholds.get('require_ac_power') and state.get('power_source') != 'AC Power':
        power_problems.append('power source is %s' % state.get('power_source'))
    if state.get('low_power_mode') or state.get('energy_mode') == 'Low Power':
        power_problems.append('Low Power mode is on')
    if power_problems:
        reasons.append('; '.join(power_problems))
    if state.get('thermal_warning'):
        reasons.append('thermal or CPU speed limit in effect (CPU_Speed_Limit=%s)' % state.get('cpu_speed_limit'))
    return reasons


def run_label(baseline, quiet_before, quiet_after):
    """(is_baseline, label) for a finished run."""
    if baseline:
        if not quiet_before:
            return False, 'not a baseline: machine busy'
        if not quiet_after:
            return False, 'not a baseline: machine became busy during the run'
        return True, 'baseline'
    if quiet_before and quiet_after:
        return False, 'not a baseline: candidate'
    return False, 'not a baseline: candidate, machine busy'


# ---------------------------------------------------------------------------
# Machine identity: hardware and software, never the host or user.

def machine_identity():
    def sysctl(name):
        return _run(['/usr/sbin/sysctl', '-n', name]).strip()

    def as_int(text):
        try:
            return int(text)
        except ValueError:
            return None
    xcode = ' '.join(_run(['/usr/bin/xcodebuild', '-version']).split())
    return {
        'model': sysctl('hw.model'),
        'chip': sysctl('machdep.cpu.brand_string'),
        'logical_cpus': as_int(sysctl('hw.logicalcpu')),
        'performance_cores': as_int(sysctl('hw.perflevel0.physicalcpu')),
        'efficiency_cores': as_int(sysctl('hw.perflevel1.physicalcpu')),
        'memory_bytes': as_int(sysctl('hw.memsize')),
        'os_version': _run(['/usr/bin/sw_vers', '-productVersion']).strip(),
        'os_build': _run(['/usr/bin/sw_vers', '-buildVersion']).strip(),
        'xcode': xcode,
    }


def redact_path(path, checkout):
    """A path for a result file: relative to the checkout, or under ~."""
    checkout = os.path.abspath(checkout)
    path = os.path.abspath(path)
    if path == checkout or path.startswith(checkout + os.sep):
        return os.path.relpath(path, checkout)
    home = os.path.expanduser('~')
    if path.startswith(home + os.sep):
        return '~' + path[len(home):]
    return path


# ---------------------------------------------------------------------------
# Statistics

# Which statistic estimates a metric, decided by its unit and nowhere else.
# Units that measure speed (a duration, or a rate of work) are estimated by
# the best sample: the owner, 2026-11-22, "Given the variance you should take
# the fastest time, since that's our best estimate." Interference from the
# rest of the machine usually makes a run slower, so the fastest run is
# usually the closest to what the code itself costs; the app rates have
# fast outliers too, and a busy machine slows the fastest run as well
# (performance.md section 3, "Read with care"). Everything else (memory in
# kB, counts, and any unit not listed) keeps the median, a proposal the
# owner has not confirmed.
BEST_SAMPLE_UNITS = frozenset({'s', 'ms', 'us', 'ns', 'iterations/s'})


def statistic_for(unit):
    """'best' or 'median': the statistic perf_compare.py compares for a metric
    measured in `unit`."""
    return 'best' if unit in BEST_SAMPLE_UNITS else 'median'


def best_sample(values, better):
    """The best of `values`: the minimum when lower is better, otherwise the
    maximum. None when there are no values."""
    values = [float(v) for v in values]
    if not values:
        return None
    return min(values) if better == 'lower' else max(values)


def summarize(values):
    values = [float(v) for v in values]
    if not values:
        return {'n': 0}
    median = statistics.median(values)
    mad = statistics.median([abs(v - median) for v in values])
    spread = 100.0 * 1.4826 * mad / abs(median) if median else 0.0
    return {'n': len(values), 'median': median, 'min': min(values), 'max': max(values),
            'mean': statistics.fmean(values), 'mad': mad, 'robust_rel_spread_percent': spread}


def summarize_metric(unit, better, samples):
    """summarize() plus the best sample and the statistic compared for the
    metric. Older result files lack 'best' and 'statistic'; readers compute
    them from the samples, which every file has."""
    summary = summarize(samples)
    if summary['n']:
        summary['best'] = best_sample(samples, better)
        summary['statistic'] = statistic_for(unit)
    return summary


def metric_entry(unit, better, samples):
    return {'unit': unit, 'better': better, 'samples': list(samples),
            'summary': summarize_metric(unit, better, samples)}


# ---------------------------------------------------------------------------
# Turning output into scenario results

def collect_xctest_scenario(scenario, output, exit_code, perf_lines='', xcresult_metrics=None):
    """The result for one xctest scenario from its xcodebuild output, the
    MIGRATION_PERF_OUTPUT file's lines, and the result bundle's metrics.
    Custom lines are taken when they name this scenario; XCTest measurements
    when they come from this scenario's test."""
    metrics = {}
    for m in parse_xctest_measurements(output) + list(xcresult_metrics or []):
        if m['test'] == scenario['test']:
            metrics[m['metric']] = metric_entry(m['unit'], m['better'], m['values'])
    for m in parse_migration_perf_lines(output + '\n' + perf_lines):
        if m['scenario'] == scenario['name']:
            metrics[m['metric']] = metric_entry(m['unit'], m['better'], m['values'])
    for metric, entry in metrics.items():
        if (scenario['name'], metric) in INFORMATIONAL_METRICS:
            entry['informational'] = True
    outcome = xctest_outcome(output, scenario['test'])
    if exit_code != 0 or outcome != 'passed' or not metrics:
        reason = 'xcodebuild exited %s; test %s; %d metrics found' % (exit_code, outcome or 'did not finish',
                                                                      len(metrics))
        return {'status': 'failed', 'reason': reason, 'source': scenario['test'], 'metrics': metrics}
    return {'status': 'ok', 'reason': '', 'source': scenario['test'], 'metrics': metrics}


def stress_metrics(runs, rate=True):
    """Metrics for a stress scenario from its runs. Each run has
    'iterations_per_sec' and 'rss_kb', the app's resident size sampled once a
    second. Steady state is the median of the second half of a run's samples.
    rate=False leaves out the iteration rate, for a mode that counts none."""
    rates = [r['iterations_per_sec'] for r in runs if rate and r.get('iterations_per_sec') is not None]
    peaks = [max(r['rss_kb']) for r in runs if r.get('rss_kb')]
    steady = []
    for r in runs:
        samples = r.get('rss_kb') or []
        if samples:
            steady.append(statistics.median(samples[len(samples) // 2:]))
    metrics = {}
    if rates:
        metrics['iterations_per_sec'] = metric_entry('iterations/s', 'higher', rates)
    if peaks:
        metrics['rss_peak'] = metric_entry('kB', 'lower', peaks)
        metrics['rss_steady'] = metric_entry('kB', 'lower', steady)
    return metrics


def assemble_result(baseline_requested, state_before, state_after, commit, dirty, configuration, arch,
                    machine, scenarios, settings, after_samples=None):
    """after_samples: the states settle_after took, the last being
    state_after; without them state_after is judged alone by the after rule."""
    before = dict(state_before)
    after = dict(state_after)
    before['quiet'], before['reasons'] = assess_quiet(state_before)
    verdict = judge_after(list(after_samples) if after_samples else [dict(state_after)])
    after['quiet'], after['reasons'] = verdict['quiet'], verdict['reasons']
    for key in ('rule', 'settled_after_s', 'samples'):
        after[key] = verdict[key]
    is_baseline, label = run_label(baseline_requested, before['quiet'], after['quiet'])
    failed = sorted(name for name, entry in scenarios.items()
                    if (entry or {}).get('status') not in ('ok', 'skipped'))
    if is_baseline and failed:
        is_baseline, label = False, 'not a baseline: scenario failed: %s' % ', '.join(failed)
    elif failed:
        label += ', scenario failed: %s' % ', '.join(failed)
    if is_baseline and dirty:
        is_baseline, label = False, 'not a baseline: uncommitted changes'
    elif dirty:
        label += ', uncommitted changes'
    return {
        'schema': SCHEMA,
        'label': label,
        'is_baseline': is_baseline,
        'commit': commit,
        'commit_dirty': dirty,
        'configuration': configuration,
        'arch': arch,
        'machine': machine,
        'machine_state': {'before': before, 'after': after},
        'thresholds': copy.deepcopy(QUIET_THRESHOLDS),
        'settings': settings,
        'scenarios': scenarios,
    }


# ---------------------------------------------------------------------------
# .xctestrun

def _patch_target(target, suite, environment):
    args = list(target.get('CommandLineArguments', []))
    cleaned = []
    skip = False
    for a in args:
        if skip:
            skip = False
            continue
        if a == '-suite':
            skip = True
            continue
        cleaned.append(a)
    target['CommandLineArguments'] = cleaned + ['-suite', suite]
    env = dict(target.get('EnvironmentVariables', {}))
    env.update(environment)
    target['EnvironmentVariables'] = env


def _targets(plist):
    if 'TestConfigurations' in plist:
        found = []
        for configuration in plist['TestConfigurations']:
            found.extend(t for t in configuration.get('TestTargets', []) if isinstance(t, dict))
        return found
    return [v for k, v in plist.items() if not k.startswith('__') and isinstance(v, dict)]


def xctestrun_suite_problems(plist, suite):
    """One message per test target that would start without -suite SUITE."""
    problems = []
    targets = _targets(plist)
    if not targets:
        return ['no test targets found in the .xctestrun file (unknown layout)']
    for target in targets:
        args = target.get('CommandLineArguments', [])
        if not any(args[i] == '-suite' and args[i + 1] == suite for i in range(len(args) - 1)):
            problems.append('test target %s would start without -suite %s'
                            % (target.get('BlueprintName', '?'), suite))
    return problems


def patch_xctestrun(plist, suite, environment):
    """A copy of an .xctestrun plist whose test targets launch the test host
    with -suite SUITE and the extra environment. Handles format 1 (targets at
    the top level) and format 2 (TestConfigurations). Raises ValueError, so
    that nothing is launched, unless every test target of the copy carries
    -suite SUITE."""
    out = copy.deepcopy(plist)
    for target in _targets(out):
        _patch_target(target, suite, environment)
    problems = xctestrun_suite_problems(out, suite)
    if problems:
        raise ValueError('; '.join(problems))
    return out
