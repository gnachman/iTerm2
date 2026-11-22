#!/usr/bin/env python3
"""Run the migration's performance and memory baseline scenarios.

docs/swift-migration/phase0.md section 8 and performance.md section 1. The
scenarios are listed by `perf_baseline.py list` and defined in perf_lib.py.

Usage, from the repository root:

    python3 -B tools/swift_migration/perf_baseline.py state
        Print the machine's load, memory, power and thermal state, and
        whether it is quiet enough for a baseline.

    python3 -B tools/swift_migration/perf_baseline.py list
        Print the scenarios.

    python3 -B tools/swift_migration/perf_baseline.py run [options]
        Build the release configuration (Deployment, unsigned, arm64, into
        Build/Deployment) with a direct xcodebuild call, run each selected
        scenario, and write a result file.

Options for run:
    --baseline            Label the result a baseline. Refused (exit 3) when
                          the machine is not quiet or the tree has
                          uncommitted changes outside docs/ (a changed
                          submodule pointer counts, because the shell
                          integration submodule is copied into the app),
                          unless --force, and then the result says
                          "not a baseline: ...".
    --force               Measure even though the machine is busy.
    --scenarios P,P       Shell-style patterns, for example 'parse.*,draw.*'.
    --iterations N        Samples per in-process metric (default 10).
    --app-runs N          Runs of each app scenario (default 5).
    --app-duration S      Seconds per app run (default 20).
    --skip-build          Use the existing Build/<configuration> products.
    --settle-minutes M    After building, wait up to M minutes for the machine
                          to become quiet before measuring (default 10).
    --output PATH         Result file (default tmp/perf-baseline/results/).

In-process scenarios run tests of the PerformanceTests target through
`xcodebuild test-without-building` with a copy of the .xctestrun file that
starts the test host with -suite <name of the checkout directory>, as
CLAUDE.md requires, and MIGRATION_PERF_ITERATIONS in its environment.

App scenarios run tools/perf/run_stress_test.sh against
Build/<configuration>/iTerm2.app with its own isolated suite,
com.iterm2.stress-test. That script launches a new instance with `open -n`
and addresses it by its path (AppleScript) and its PID (everything else), so
other iTerm2 instances, such as the owner's own or another checkout's build,
may keep running and are never sent anything. It refuses to start only while
an instance of the same app path is already running, so app scenarios are
skipped, with that reason, only then: a test host of this checkout or a
leftover stress run. It is not
given the checkout's name as its suite because it deletes the suite's
Application Support folder before each run. While each app run is in
progress this script samples the app's resident size once a second with ps.

Every subprocess runs in its own session under a timeout and its whole
process group is killed with SIGKILL when the timeout expires. The test host
and the stress test's app are not in that group (xcodebuild and `open` start
them), so on a timeout the runner also kills, with SIGKILL, the processes
whose executable path is exactly this checkout's
Build/<configuration>/iTerm2.app/Contents/MacOS/iTerm2 (for the stress test,
only the PID the script printed). Nothing is matched by name.

Exit status: 0 every selected scenario ran or was skipped with a reason;
1 a scenario failed; 2 bad arguments; 3 refused, for one of three reasons:
the machine is busy (with --baseline), the tree has uncommitted changes
(with --baseline), or the machine did not become quiet within
--settle-minutes after the build (with --baseline).
"""

import argparse
import datetime
import glob
import json
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import threading
import time

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOL_DIR)

import perf_lib  # noqa: E402

REPO = os.path.abspath(os.path.join(TOOL_DIR, '..', '..'))
ARCH = 'arm64'
STRESS_SUITE = 'com.iterm2.stress-test'
MIN_MEMORY_FREE_TO_BUILD = 15


def log(message):
    print('[perf_baseline] %s' % message, flush=True)


# ---------------------------------------------------------------------------
# Decisions that tests cover

def preflight(state, baseline, force):
    """Whether to go ahead, before anything is built or measured."""
    quiet, reasons = perf_lib.assess_quiet(state)
    if quiet or not baseline:
        note = '' if quiet else ' The machine is busy (%s); the result will not be a baseline.' % '; '.join(reasons)
        return {'proceed': True, 'quiet': quiet, 'message': 'Proceeding.' + note}
    if force:
        return {'proceed': True, 'quiet': False,
                'message': ('Forced: the machine is busy (%s). The result will be marked '
                            '"not a baseline: machine busy".' % '; '.join(reasons))}
    return {'proceed': False, 'quiet': False,
            'message': ('refusing to take a baseline: the machine is not quiet: %s. Wait for it to be quiet '
                        '(check with "perf_baseline.py state"), or pass --force to measure anyway, which '
                        'marks the result "not a baseline: machine busy".' % '; '.join(reasons))}


# ---------------------------------------------------------------------------
# Subprocesses

def run_bounded(args, timeout, log_path, cwd=REPO, on_line=None, env=None):
    """Runs args in its own session, writing output to log_path. Kills the
    whole process group with SIGKILL at the timeout. Returns (exit code or
    None on timeout, output)."""
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    chunks = []
    expired = threading.Event()

    def expire():
        expired.set()
        _kill_group(proc)

    with open(log_path, 'w', encoding='utf-8', errors='replace') as out:
        proc = subprocess.Popen(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                start_new_session=True, text=True, errors='replace', env=env)
        timer = threading.Timer(timeout, expire)
        timer.start()
        try:
            for line in proc.stdout:
                out.write(line)
                chunks.append(line)
                if on_line:
                    on_line(line)
            proc.wait()
        finally:
            timer.cancel()
            # Whatever the outcome, nothing the command started outlives it.
            _kill_group(proc)
            proc.wait()
    return (None if expired.is_set() else proc.returncode), ''.join(chunks)


def _kill_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def git(*args):
    return subprocess.run(['git'] + list(args), cwd=REPO, capture_output=True, text=True).stdout


def dirty_paths():
    return perf_lib.dirty_paths(git('status', '--porcelain', '--untracked-files=no', '--ignore-submodules=dirty'))


def commit_and_dirty():
    return git('rev-parse', 'HEAD').strip(), bool(dirty_paths())


# ---------------------------------------------------------------------------
# Build

def wait_for_memory(max_minutes=30):
    deadline = time.monotonic() + max_minutes * 60
    while True:
        free = perf_lib.parse_memory_free_percent(perf_lib._run(['/usr/bin/memory_pressure']))
        if free is not None and free >= MIN_MEMORY_FREE_TO_BUILD:
            return True
        if time.monotonic() > deadline:
            return False
        log('memory free %s%% is below %d%%; waiting before building' % (free, MIN_MEMORY_FREE_TO_BUILD))
        time.sleep(60)


def build_command(configuration):
    """The Makefile's flags for a release configuration, as a direct
    xcodebuild call: `make Deployment` would also run
    tools/extract_strings.sh, which rewrites the tracked string catalog."""
    build_dir = os.path.join(REPO, 'Build')
    return ['xcodebuild', 'build-for-testing', '-project', 'iTerm2.xcodeproj', '-scheme', 'PerformanceTests',
            '-configuration', configuration, '-destination', 'platform=macOS,arch=%s' % ARCH,
            '-skipPackagePluginValidation',
            'CODE_SIGN_IDENTITY=', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGNING_ALLOWED=NO',
            'ARCHS=%s' % ARCH, 'ONLY_ACTIVE_ARCH=YES',
            'SYMROOT=%s' % build_dir,
            'OBJROOT=%s' % os.path.join(build_dir, 'Intermediates-%s.noindex' % configuration),
            'ENABLE_ADDRESS_SANITIZER=NO']


def build(configuration, work_dir, timeout):
    if not wait_for_memory():
        return False, 'memory stayed below %d%% free' % MIN_MEMORY_FREE_TO_BUILD
    log_path = os.path.join(work_dir, 'build-%s.log' % configuration)
    log('building %s (log: %s)' % (configuration, perf_lib.redact_path(log_path, REPO)))
    started = time.monotonic()
    code, output = run_bounded(build_command(configuration), timeout, log_path)
    log('build finished with %s after %.0f s' % (code, time.monotonic() - started))
    if code != 0:
        return False, 'build exited %s; see %s' % (code, perf_lib.redact_path(log_path, REPO))
    return True, ''


def find_xctestrun(configuration):
    pattern = os.path.join(REPO, 'Build', 'PerformanceTests_*.xctestrun')
    candidates = [p for p in glob.glob(pattern) if configuration in open(p, 'rb').read().decode('utf-8', 'replace')]
    candidates.sort(key=os.path.getmtime, reverse=True)
    return candidates[0] if candidates else None


# ---------------------------------------------------------------------------
# Scenarios

def run_xctest_scenarios(scenarios, configuration, iterations, work_dir, timeout):
    results = {}
    xctestrun = find_xctestrun(configuration)
    if not xctestrun:
        for s in scenarios:
            results[s['name']] = {'status': 'failed', 'source': s['test'], 'metrics': {},
                                  'reason': 'no PerformanceTests .xctestrun for %s in Build/' % configuration}
        return results
    with open(xctestrun, 'rb') as f:
        plist = plistlib.load(f)
    suite = os.path.basename(REPO)
    # Xcode 27 does not echo the test's output on the console, so the tests
    # append their metric lines to this file too.
    perf_output = os.path.join(work_dir, 'metrics.jsonl')
    try:
        patched = perf_lib.patch_xctestrun(plist, suite=suite,
                                           environment={'MIGRATION_PERF_ITERATIONS': str(iterations),
                                                        'MIGRATION_PERF_OUTPUT': perf_output})
    except ValueError as e:
        # Fail closed: a test host started without -suite would share the owner's settings.
        reason = 'refusing to start test hosts: %s' % e
        log(reason)
        for s in scenarios:
            results[s['name']] = {'status': 'failed', 'source': s['test'], 'metrics': {}, 'reason': reason}
        return results
    # The copy must sit next to the original: its paths are relative to __TESTROOT__.
    patched_path = os.path.join(os.path.dirname(xctestrun), 'MigrationPerf-%s.xctestrun' % configuration)
    with open(patched_path, 'wb') as f:
        plistlib.dump(patched, f)
    try:
        for s in scenarios:
            log('scenario %s' % s['name'])
            bundle = os.path.join(work_dir, s['name'] + '.xcresult')
            shutil.rmtree(bundle, ignore_errors=True)
            args = ['xcodebuild', 'test-without-building', '-xctestrun', patched_path,
                    '-destination', 'platform=macOS,arch=%s' % ARCH,
                    '-only-testing:PerformanceTests/%s' % s['test'], '-resultBundlePath', bundle]
            code, output = run_bounded(args, timeout, os.path.join(work_dir, s['name'] + '.log'))
            perf_lines = ''
            if os.path.exists(perf_output):
                with open(perf_output, encoding='utf-8', errors='replace') as f:
                    perf_lines = f.read()
            result = perf_lib.collect_xctest_scenario(s, output, code if code is not None else -1,
                                                      perf_lines=perf_lines,
                                                      xcresult_metrics=xcresult_metrics(bundle))
            if code is None:
                result['status'] = 'failed'
                result['reason'] = 'timed out after %d s' % timeout
                # The test host is not in xcodebuild's process group.
                kill_exact_executable(test_host_executable(configuration))
            result['load_average_after'] = perf_lib.load_average()
            results[s['name']] = result
            log('  %s %s; load average %s' % (result['status'], result['reason'],
                                              result['load_average_after']))
    finally:
        os.remove(patched_path)
    return results


def xcresult_metrics(bundle):
    """XCTest's measurements from a result bundle, or [] if there are none."""
    if not os.path.isdir(bundle):
        return []
    try:
        out = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'metrics', '--path', bundle,
                              '--compact'], capture_output=True, text=True, timeout=300).stdout
        return perf_lib.parse_xcresult_metrics(json.loads(out))
    except (OSError, subprocess.SubprocessError, ValueError):
        return []


class RssSampler:
    """Samples one process's resident size (kB) once a second with ps."""

    def __init__(self, pid):
        self.pid = pid
        self.samples = []
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def _loop(self):
        while not self._stop.is_set():
            out = perf_lib._run(['/bin/ps', '-o', 'rss=', '-p', str(self.pid)]).strip()
            if not out:
                return
            try:
                self.samples.append(int(out))
            except ValueError:
                return
            self._stop.wait(1.0)

    def stop(self):
        self._stop.set()
        self._thread.join(timeout=5)


def test_host_executable(configuration):
    return os.path.join(REPO, 'Build', configuration, 'iTerm2.app', 'Contents', 'MacOS', 'iTerm2')


def app_under_test_running(configuration):
    """Whether an instance of this checkout's own build is running. Other
    iTerm2 instances do not matter: run_stress_test.sh addresses the app
    under test by its path and its PID."""
    return perf_lib.executable_may_be_running(test_host_executable(configuration))


def kill_exact_executable(executable, only_pid=None):
    """SIGKILL processes whose binary, by proc_pidpath, is exactly
    `executable` (this checkout's build), optionally only the one PID. Never
    matches by name or argv[0]."""
    pids = [only_pid] if only_pid is not None else perf_lib.all_pids()
    for pid in perf_lib.pids_with_executable(pids, executable):
        if only_pid is not None and pid != only_pid:
            continue
        log('killing leftover process %d (%s)' % (pid, perf_lib.redact_path(executable, REPO)))
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def run_stress_scenarios(scenarios, configuration, runs, duration, work_dir):
    results = {}
    app = os.path.join(REPO, 'Build', configuration, 'iTerm2.app')
    script = os.path.join(REPO, 'tools', 'perf', 'run_stress_test.sh')
    for s in scenarios:
        source = 'tools/perf/run_stress_test.sh --mode=%s --tabs=%d' % (s['mode'], s['tabs'])
        if not os.path.isdir(app):
            results[s['name']] = {'status': 'failed', 'source': source, 'metrics': {},
                                  'reason': 'no app at %s' % perf_lib.redact_path(app, REPO)}
            continue
        if app_under_test_running(configuration):
            results[s['name']] = {
                'status': 'skipped', 'source': source, 'metrics': {},
                'reason': ('an instance of %s is already running (a test host or an earlier stress '
                           'run); run_stress_test.sh refuses to start a second instance of the same '
                           'path' % perf_lib.redact_path(app, REPO))}
            log('scenario %s skipped: %s' % (s['name'], results[s['name']]['reason']))
            continue
        log('scenario %s' % s['name'])
        app_runs = []
        failure = ''
        for i in range(runs):
            args = [script, '--tabs=%d' % s['tabs'], '-t', str(duration), '--mode=%s' % s['mode'],
                    '--suite=%s' % STRESS_SUITE]
            if s.get('fps') is not None:
                args.append('--fps=%s' % s['fps'])
            args.append(app)
            sampler = {}

            def on_line(line, sampler=sampler):
                parsed = perf_lib.parse_stress_output(line)
                if parsed['pid'] and 'rss' not in sampler:
                    sampler['rss'] = RssSampler(parsed['pid'])

            code, output = run_bounded(args, duration * s['tabs'] + 600,
                                       os.path.join(work_dir, '%s-%d.log' % (s['name'], i + 1)),
                                       on_line=on_line)
            if 'rss' in sampler:
                sampler['rss'].stop()
            parsed = perf_lib.parse_stress_output(output)
            if code is None and parsed['pid']:
                # The app was started with `open`, outside the script's process
                # group, and the script's own cleanup did not run.
                kill_exact_executable(test_host_executable(configuration), only_pid=parsed['pid'])
            if code != 0 or parsed['iterations_per_sec'] is None:
                failure = 'run %d: exit %s, rate %s' % (i + 1, code, parsed['iterations_per_sec'])
                break
            app_runs.append({'iterations_per_sec': parsed['iterations_per_sec'],
                             'rss_kb': sampler['rss'].samples if 'rss' in sampler else []})
        metrics = perf_lib.stress_metrics(app_runs, rate=s.get('rate', True))
        load = perf_lib.load_average()
        results[s['name']] = {'status': 'failed' if failure else 'ok', 'reason': failure,
                              'source': source, 'metrics': metrics, 'load_average_after': load}
        log('  %s %s; load average %s' % (results[s['name']]['status'], failure, load))
    return results


# ---------------------------------------------------------------------------

def wait_until_quiet(minutes):
    deadline = time.monotonic() + minutes * 60
    while True:
        state = perf_lib.machine_state()
        quiet, reasons = perf_lib.assess_quiet(state)
        if quiet or time.monotonic() > deadline:
            return state
        log('waiting for the machine to settle: %s' % '; '.join(reasons))
        time.sleep(30)


def print_summary(result):
    log('label: %s' % result['label'])
    for name, entry in result['scenarios'].items():
        if entry['status'] != 'ok':
            log('%-44s %s: %s' % (name, entry['status'], entry['reason']))
            continue
        for metric, data in entry['metrics'].items():
            # Recomputed from the samples so that a summary written before
            # 'best' existed prints the same way.
            s = perf_lib.summarize_metric(data['unit'], data.get('better'), data['samples'])
            if not s['n']:
                log('%-44s %-24s no samples' % (name, metric))
                continue
            log('%-44s %-24s best %.6g median %.6g %s (n=%d, spread %.1f%%, compared on %s)' % (
                name, metric, s['best'], s['median'], data['unit'], s['n'], s['robust_rel_spread_percent'],
                s['statistic']))


def cmd_run(args):
    try:
        scenarios = perf_lib.select_scenarios([p for p in (args.scenarios or '').split(',') if p] or None)
    except ValueError as e:
        print('perf_baseline: %s' % e, file=sys.stderr)
        return 2
    state = perf_lib.machine_state()
    decision = preflight(state, baseline=args.baseline, force=args.force)
    log(decision['message'])
    if not decision['proceed']:
        return 3
    if args.baseline:
        dirty = dirty_paths()
        if dirty and not args.force:
            log('refusing to take a baseline: the tree has uncommitted changes outside docs/: %s. '
                'Commit or remove them, or take the baseline in a clean checkout or lane, or pass '
                '--force, which marks the result "not a baseline". A changed submodule pointer counts, '
                'because the shell integration submodule is copied into the app; if the pointer change '
                'is unwanted, `git submodule update` restores it, otherwise use a clean checkout.'
                % ', '.join(dirty))
            return 3

    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    work_dir = os.path.join(REPO, 'tmp', 'perf-baseline', 'run-' + stamp)
    os.makedirs(work_dir, exist_ok=True)
    xctests = [s for s in scenarios if s['kind'] == 'xctest']
    stresses = [s for s in scenarios if s['kind'] == 'stress']
    results = {}
    built = True
    if not args.skip_build:
        built, why = build(args.configuration, work_dir, args.build_timeout)
        if not built:
            for s in scenarios:
                results[s['name']] = {'status': 'failed', 'reason': why, 'source': s.get('test', ''),
                                      'metrics': {}}
        elif args.baseline:
            state = wait_until_quiet(args.settle_minutes)
            if not perf_lib.assess_quiet(state)[0] and not args.force:
                log('refusing to measure a baseline: the machine did not become quiet within %d minutes '
                    'of the build; rerun with --skip-build when it is' % args.settle_minutes)
                return 3
    state_before = perf_lib.machine_state()
    if built:
        results.update(run_xctest_scenarios(xctests, args.configuration, args.iterations, work_dir,
                                            args.test_timeout))
        results.update(run_stress_scenarios(stresses, args.configuration, args.app_runs, args.app_duration,
                                            work_dir))
    log('waiting up to %d s for the 1-minute load average to settle after the run'
        % perf_lib.QUIET_THRESHOLDS['after_settle_seconds'])
    after_samples = perf_lib.settle_after(perf_lib.machine_state)
    state_after = after_samples[-1]

    commit, dirty = commit_and_dirty()
    ordered = {s['name']: results[s['name']] for s in scenarios if s['name'] in results}
    result = perf_lib.assemble_result(
        baseline_requested=args.baseline, state_before=state_before, state_after=state_after,
        after_samples=after_samples,
        commit=commit, dirty=dirty, configuration=args.configuration, arch=ARCH,
        machine=perf_lib.machine_identity(), scenarios=ordered,
        settings={'iterations': args.iterations, 'app_runs': args.app_runs, 'app_duration_s': args.app_duration,
                  'test_host_suite': os.path.basename(REPO), 'stress_suite': STRESS_SUITE,
                  'created': stamp, 'logs': perf_lib.redact_path(work_dir, REPO),
                  'uncommitted_paths': dirty_paths()})
    output = args.output or os.path.join(REPO, 'tmp', 'perf-baseline', 'results', stamp + '.json')
    os.makedirs(os.path.dirname(os.path.abspath(output)), exist_ok=True)
    with open(output, 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=1, sort_keys=True)
        f.write('\n')
    print_summary(result)
    log('result: %s' % perf_lib.redact_path(output, REPO))
    return 1 if any(e['status'] == 'failed' for e in ordered.values()) else 0


def cmd_state(_args):
    state = perf_lib.machine_state()
    quiet, reasons = perf_lib.assess_quiet(state)
    print(json.dumps({'state': state, 'quiet': quiet, 'reasons': reasons,
                      'thresholds': perf_lib.QUIET_THRESHOLDS}, indent=1, sort_keys=True))
    return 0


def cmd_list(_args):
    for s in perf_lib.SCENARIOS:
        print('%-44s %-7s %s' % (s['name'], s['kind'], s['what']))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    run = sub.add_parser('run', help='build, measure, and write a result file')
    run.add_argument('--baseline', action='store_true',
                     help='label the result a baseline; refused on a busy machine or a dirty tree')
    run.add_argument('--force', action='store_true',
                     help='measure even when --baseline would be refused; the result is then not a baseline')
    run.add_argument('--scenarios', help="comma-separated shell patterns, e.g. 'parse.*,draw.*'")
    run.add_argument('--iterations', type=int, default=10, help='samples per in-process metric (default 10)')
    run.add_argument('--app-runs', type=int, default=5, help='runs of each app scenario (default 5)')
    run.add_argument('--app-duration', type=int, default=20, help='seconds per app run (default 20)')
    run.add_argument('--configuration', default='Deployment',
                     help='Xcode configuration to build and measure (default Deployment)')
    run.add_argument('--skip-build', action='store_true',
                     help='use the existing Build/<configuration> products')
    run.add_argument('--settle-minutes', type=int, default=10,
                     help='after building, minutes to wait for the machine to become quiet (default 10)')
    run.add_argument('--build-timeout', type=int, default=4 * 3600,
                     help='seconds before the build is killed (default 14400)')
    run.add_argument('--test-timeout', type=int, default=1800,
                     help='seconds before one in-process scenario is killed (default 1800)')
    run.add_argument('--output', help='result file (default tmp/perf-baseline/results/<time>.json)')
    sub.add_parser('state', help='print the machine state and whether it is quiet')
    sub.add_parser('list', help='print the scenarios')
    args = parser.parse_args(argv)
    return {'run': cmd_run, 'state': cmd_state, 'list': cmd_list}[args.command](args)


if __name__ == '__main__':
    sys.exit(main())
