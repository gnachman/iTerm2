"""Tests for the migration's performance and memory baseline tools:
tools/swift_migration/perf_lib.py, perf_baseline.py and perf_compare.py.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_perf_baseline.py'

Nothing here builds, launches the app, or measures anything: every input is a
fixture under perf_fixtures/ or a literal in the test.
"""

import copy
import io
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
FIXTURES = os.path.join(HERE, 'perf_fixtures')
sys.path.insert(0, TOOL_DIR)

import perf_lib  # noqa: E402
import perf_compare  # noqa: E402
import perf_baseline  # noqa: E402


def fixture(name):
    with open(os.path.join(FIXTURES, name), encoding='utf-8') as f:
        return f.read()


def load_result(name):
    return json.loads(fixture(name))


QUIET = {
    'load_average': [1.0, 1.2, 1.5],
    'logical_cpus': 16,
    'memory_free_percent': 70,
    'swap_used_mb': 12000.0,
    'power_source': 'AC Power',
    'energy_mode': 'High Power',
    'low_power_mode': False,
    'thermal_warning': False,
    'cpu_speed_limit': None,
    'build_processes': {},
}


class ParseOutputTests(unittest.TestCase):
    def test_migration_perf_lines(self):
        metrics = perf_lib.parse_migration_perf_lines(fixture('xcodebuild_test_output.txt'))
        self.assertEqual([(m['scenario'], m['metric']) for m in metrics],
                         [('memory.scrollback_fill_20k', 'live_malloc_blocks'),
                          ('memory.scrollback_fill_20k', 'process_peak_footprint'),
                          ('parse.mixed_1mb', 'time')])
        self.assertEqual(metrics[0]['values'], [1000, 1010, 990])
        self.assertEqual(metrics[0]['unit'], 'count')
        self.assertEqual(metrics[0]['better'], 'lower')

    def test_migration_perf_line_with_bad_direction_is_rejected(self):
        text = '[MigrationPerf] {"better":"sideways","metric":"m","scenario":"s","unit":"u","values":[1]}\n'
        self.assertEqual(perf_lib.parse_migration_perf_lines(text), [])

    def test_xctest_measurements(self):
        found = perf_lib.parse_xctest_measurements(fixture('xcodebuild_test_output.txt'))
        self.assertEqual([(m['test'], m['metric'], m['unit'], m['better']) for m in found],
                         [('PerformanceTests/testGang_fastPathPerformance', 'time', 's', 'lower'),
                          ('MigrationBaselineTests/testMemoryScrollbackFill', 'memory_peak_physical', 'kB', 'lower'),
                          ('MigrationBaselineTests/testMemoryScrollbackFill', 'clock_monotonic_time', 's', 'lower')])
        self.assertEqual(len(found[0]['values']), 10)
        self.assertAlmostEqual(found[0]['values'][0], 0.11)
        self.assertEqual(found[1]['values'], [52000.0, 52100.0, 51900.0])

    def test_xctest_prefers_larger_maps_to_higher(self):
        line = ("Test Case '-[M.C testX]' measured [Throughput, items] average: 2, relative standard deviation: 0%, "
                "values: [2.0, 2.0], performanceMetricID:x, polarity: prefers larger, maxPercentRegression: 10%\n")
        found = perf_lib.parse_xctest_measurements(line)
        self.assertEqual(found[0]['better'], 'higher')
        self.assertEqual(found[0]['metric'], 'throughput')

    def test_xctest_passed_and_failed(self):
        text = fixture('xcodebuild_test_output.txt')
        self.assertEqual(perf_lib.xctest_outcome(text, 'PerformanceTests/testGang_fastPathPerformance'), 'passed')
        self.assertEqual(perf_lib.xctest_outcome(text, 'PerformanceTests/testNothing'), None)
        failed = "Test Case '-[PerformanceTests.PerformanceTests testX]' failed (0.1 seconds).\n"
        self.assertEqual(perf_lib.xctest_outcome(failed, 'PerformanceTests/testX'), 'failed')

    def test_xcode27_outcome_format(self):
        # Xcode 27 no longer prints test output or 'measured' lines to the console.
        text = fixture('xcodebuild27_output.txt')
        self.assertEqual(perf_lib.xctest_outcome(text, 'MigrationBaselineTests/testParseThroughput'), 'passed')
        self.assertEqual(perf_lib.xctest_outcome(text, 'PerformanceTests/testGang_fastPathPerformance'), 'failed')
        self.assertIsNone(perf_lib.xctest_outcome(text, 'MigrationBaselineTests/testParse'))

    def test_xcresult_metrics(self):
        found = perf_lib.parse_xcresult_metrics(json.loads(fixture('xcresult_metrics.json')))
        self.assertEqual([(m['test'], m['metric'], m['unit'], m['better']) for m in found],
                         [('PerformanceTests/testGang_fastPathPerformance', 'time', 's', 'lower'),
                          ('MigrationBaselineTests/testMemoryScrollbackFill', 'memory_peak_physical', 'kB', 'lower'),
                          ('MigrationBaselineTests/testMemoryScrollbackFill', 'throughput', 'items', 'higher')])
        self.assertEqual(found[0]['values'], [0.11, 0.1, 0.105])

    def test_xcresult_metrics_tolerates_garbage(self):
        self.assertEqual(perf_lib.parse_xcresult_metrics({'unexpected': True}), [])
        self.assertEqual(perf_lib.parse_xcresult_metrics([{'testIdentifier': 'A/b()', 'testRuns': [{}]}]), [])

    def test_stress_output(self):
        parsed = perf_lib.parse_stress_output(fixture('stress_output.txt'))
        self.assertEqual(parsed['pid'], 14927)
        self.assertEqual(parsed['iterations_per_sec'], 9273)
        self.assertEqual(parsed['total_iterations'], 185460)

    def test_stress_output_without_summary(self):
        parsed = perf_lib.parse_stress_output('Error: iTerm2 is already running.\n')
        self.assertIsNone(parsed['pid'])
        self.assertIsNone(parsed['iterations_per_sec'])


class MachineStateParsingTests(unittest.TestCase):
    def test_loadavg(self):
        self.assertEqual(perf_lib.parse_loadavg('{ 400.58 360.42 264.72 }\n'), [400.58, 360.42, 264.72])

    def test_memory_pressure(self):
        text = 'Pageouts: 44897 \n\nSystem-wide memory free percentage: 70%\n'
        self.assertEqual(perf_lib.parse_memory_free_percent(text), 70)
        self.assertIsNone(perf_lib.parse_memory_free_percent('nothing'))

    def test_swapusage(self):
        text = 'total = 39936.00M  used = 38493.75M  free = 1442.25M  (encrypted)\n'
        self.assertEqual(perf_lib.parse_swap_used_mb(text), 38493.75)
        self.assertEqual(perf_lib.parse_swap_used_mb('total = 1.00G  used = 0.50G  free = 0.50G'), 512.0)

    def test_power_source(self):
        text = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t80%; AC attached;\n"
        self.assertEqual(perf_lib.parse_power_source(text), 'AC Power')
        self.assertEqual(perf_lib.parse_power_source("Now drawing from 'Battery Power'\n"), 'Battery Power')

    def test_energy_mode(self):
        text = fixture('pmset_custom.txt')
        self.assertEqual(perf_lib.parse_energy_mode(text, 'AC Power'), ('High Power', False))
        self.assertEqual(perf_lib.parse_energy_mode(text, 'Battery Power'), ('Low Power', False))
        self.assertEqual(perf_lib.parse_energy_mode('', 'AC Power'), ('Unknown', False))
        low = 'AC Power:\n lowpowermode         1\n powermode            0\n'
        self.assertEqual(perf_lib.parse_energy_mode(low, 'AC Power'), ('Automatic', True))

    def test_thermal(self):
        calm = ('Note: No thermal warning level has been recorded\n'
                'Note: No performance warning level has been recorded\n')
        self.assertEqual(perf_lib.parse_thermal(calm), (False, None))
        hot = 'CPU_Scheduler_Limit \t= 100\nCPU_Available_CPUs \t= 16\nCPU_Speed_Limit \t= 70\n'
        self.assertEqual(perf_lib.parse_thermal(hot), (True, 70))
        cool = 'CPU_Speed_Limit \t= 100\n'
        self.assertEqual(perf_lib.parse_thermal(cool), (False, 100))
        warned = 'Thermal warning level set to 2.\n'
        self.assertEqual(perf_lib.parse_thermal(warned), (True, None))


class QuietTests(unittest.TestCase):
    def test_quiet_machine(self):
        quiet, reasons = perf_lib.assess_quiet(QUIET)
        self.assertTrue(quiet, reasons)
        self.assertEqual(reasons, [])

    def test_tonight(self):
        busy = dict(QUIET, load_average=[400.58, 360.42, 264.72], memory_free_percent=12,
                    build_processes={'xcodebuild': 10, 'swift-frontend': 40})
        quiet, reasons = perf_lib.assess_quiet(busy)
        self.assertFalse(quiet)
        joined = '\n'.join(reasons)
        self.assertIn('load average', joined)
        self.assertIn('memory free', joined)
        self.assertIn('xcodebuild', joined)

    def test_each_condition_alone_is_busy(self):
        cases = [
            dict(QUIET, load_average=[4.5, 1.0, 1.0]),
            dict(QUIET, load_average=[1.0, 4.5, 1.0]),
            dict(QUIET, memory_free_percent=29),
            dict(QUIET, memory_free_percent=None),
            dict(QUIET, build_processes={'clang': 1}),
            dict(QUIET, power_source='Battery Power'),
            dict(QUIET, low_power_mode=True),
            dict(QUIET, energy_mode='Low Power'),
            dict(QUIET, thermal_warning=True),
        ]
        for state in cases:
            quiet, reasons = perf_lib.assess_quiet(state)
            self.assertFalse(quiet, state)
            self.assertEqual(len(reasons), 1, (state, reasons))

    def test_swap_alone_is_recorded_not_gated(self):
        quiet, _ = perf_lib.assess_quiet(dict(QUIET, swap_used_mb=38000.0))
        self.assertTrue(quiet)

    def test_label(self):
        self.assertEqual(perf_lib.run_label(baseline=True, quiet_before=True, quiet_after=True),
                         (True, 'baseline'))
        self.assertEqual(perf_lib.run_label(baseline=True, quiet_before=False, quiet_after=True),
                         (False, 'not a baseline: machine busy'))
        self.assertEqual(perf_lib.run_label(baseline=True, quiet_before=True, quiet_after=False),
                         (False, 'not a baseline: machine became busy during the run'))
        self.assertEqual(perf_lib.run_label(baseline=False, quiet_before=True, quiet_after=True),
                         (False, 'not a baseline: candidate'))
        self.assertEqual(perf_lib.run_label(baseline=False, quiet_before=False, quiet_after=False),
                         (False, 'not a baseline: candidate, machine busy'))


class RefuseBaselineTests(unittest.TestCase):
    """The runner's gate before it builds or measures anything."""

    def test_refuses_baseline_on_busy_machine(self):
        busy = dict(QUIET, load_average=[400.0, 300.0, 200.0])
        decision = perf_baseline.preflight(busy, baseline=True, force=False)
        self.assertFalse(decision['proceed'])
        self.assertIn('refusing', decision['message'])
        self.assertIn('load average', decision['message'])

    def test_forced_baseline_on_busy_machine_proceeds_marked_busy(self):
        busy = dict(QUIET, load_average=[400.0, 300.0, 200.0])
        decision = perf_baseline.preflight(busy, baseline=True, force=True)
        self.assertTrue(decision['proceed'])
        self.assertIn('not a baseline: machine busy', decision['message'])

    def test_quiet_baseline_proceeds(self):
        decision = perf_baseline.preflight(QUIET, baseline=True, force=False)
        self.assertTrue(decision['proceed'])

    def test_candidate_on_busy_machine_proceeds(self):
        busy = dict(QUIET, memory_free_percent=10)
        self.assertTrue(perf_baseline.preflight(busy, baseline=False, force=False)['proceed'])

    def test_main_refuses_without_building(self):
        # The command line exits 3 before any build when the machine is busy.
        busy = dict(QUIET, load_average=[400.0, 300.0, 200.0])
        calls = []
        orig_state = perf_lib.machine_state
        orig_build = perf_baseline.build
        try:
            perf_lib.machine_state = lambda: dict(busy)
            perf_baseline.build = lambda *a, **k: calls.append('build')
            with redirect_stdout(io.StringIO()):
                code = perf_baseline.main(['run', '--baseline', '--output', os.devnull])
        finally:
            perf_lib.machine_state = orig_state
            perf_baseline.build = orig_build
        self.assertEqual(code, 3)
        self.assertEqual(calls, [])


class IdentityTests(unittest.TestCase):
    def test_identity_has_no_personal_data(self):
        identity = perf_lib.machine_identity()
        text = json.dumps(identity)
        for personal in {os.uname().nodename.split('.')[0], os.environ.get('USER', ''),
                         os.path.expanduser('~')}:
            if personal and len(personal) > 2:
                self.assertNotIn(personal, text)
        for key in ('model', 'chip', 'logical_cpus', 'memory_bytes', 'os_version', 'os_build'):
            self.assertIn(key, identity)

    def test_result_paths_are_relative_to_checkout(self):
        self.assertEqual(perf_lib.redact_path('/a/b/checkout/Build/x', '/a/b/checkout'), 'Build/x')
        home = os.path.expanduser('~')
        self.assertEqual(perf_lib.redact_path(home + '/y', '/elsewhere'), '~/y')


class StatsTests(unittest.TestCase):
    def test_summary(self):
        s = perf_lib.summarize([3.0, 1.0, 2.0, 4.0, 100.0])
        self.assertEqual(s['n'], 5)
        self.assertEqual(s['median'], 3.0)
        self.assertEqual(s['min'], 1.0)
        self.assertEqual(s['max'], 100.0)
        self.assertEqual(s['mad'], 1.0)
        self.assertAlmostEqual(s['robust_rel_spread_percent'], 100 * 1.4826 / 3.0)

    def test_even_median(self):
        self.assertEqual(perf_lib.summarize([1.0, 2.0, 3.0, 4.0])['median'], 2.5)

    def test_empty(self):
        self.assertEqual(perf_lib.summarize([])['n'], 0)


class XctestrunTests(unittest.TestCase):
    def test_v2_targets_get_suite_and_environment(self):
        plist = {
            'TestConfigurations': [{'Name': 'c', 'TestTargets': [
                {'BlueprintName': 'PerformanceTests', 'CommandLineArguments': ['-x'],
                 'EnvironmentVariables': {'A': '1'}}]}],
            '__xctestrun_metadata__': {'FormatVersion': 2},
        }
        out = perf_lib.patch_xctestrun(plist, suite='lane-3', environment={'MIGRATION_PERF_ITERATIONS': '7'})
        target = out['TestConfigurations'][0]['TestTargets'][0]
        self.assertEqual(target['CommandLineArguments'], ['-x', '-suite', 'lane-3'])
        self.assertEqual(target['EnvironmentVariables'], {'A': '1', 'MIGRATION_PERF_ITERATIONS': '7'})
        self.assertEqual(plist['TestConfigurations'][0]['TestTargets'][0]['CommandLineArguments'], ['-x'])

    def test_v1_targets(self):
        plist = {'PerformanceTests': {'TestHostPath': '/x'}, '__xctestrun_metadata__': {'FormatVersion': 1}}
        out = perf_lib.patch_xctestrun(plist, suite='s', environment={})
        self.assertEqual(out['PerformanceTests']['CommandLineArguments'], ['-suite', 's'])

    def test_existing_suite_is_replaced(self):
        plist = {'T': {'CommandLineArguments': ['-suite', 'old', '-y']}, '__xctestrun_metadata__': {}}
        out = perf_lib.patch_xctestrun(plist, suite='new', environment={})
        self.assertEqual(out['T']['CommandLineArguments'], ['-y', '-suite', 'new'])

    def test_round_trip_through_plistlib(self):
        plist = {'T': {'TestHostPath': '/x'}, '__xctestrun_metadata__': {'FormatVersion': 1}}
        data = plistlib.dumps(perf_lib.patch_xctestrun(plist, suite='s', environment={'K': 'v'}))
        self.assertEqual(plistlib.loads(data)['T']['EnvironmentVariables'], {'K': 'v'})


class ScenarioTests(unittest.TestCase):
    def test_names_are_unique_and_kinds_known(self):
        names = [s['name'] for s in perf_lib.SCENARIOS]
        self.assertEqual(len(names), len(set(names)))
        for s in perf_lib.SCENARIOS:
            self.assertIn(s['kind'], ('xctest', 'stress'))

    def test_select(self):
        chosen = perf_lib.select_scenarios(['parse.*', 'app.stress_flood_1tab'])
        self.assertEqual([s['name'] for s in chosen], ['parse.mixed_1mb', 'app.stress_flood_1tab'])
        self.assertEqual(len(perf_lib.select_scenarios(None)), len(perf_lib.SCENARIOS))
        with self.assertRaises(ValueError):
            perf_lib.select_scenarios(['nothing.matches'])

    def test_collect_xctest_scenario(self):
        scenario = perf_lib.scenario_named('memory.scrollback_fill_20k')
        result = perf_lib.collect_xctest_scenario(scenario, fixture('xcodebuild_test_output.txt'), exit_code=0)
        self.assertEqual(result['status'], 'ok')
        self.assertEqual(set(result['metrics']),
                         {'memory_peak_physical', 'clock_monotonic_time', 'live_malloc_blocks',
                          'process_peak_footprint'})
        self.assertEqual(result['metrics']['live_malloc_blocks']['samples'], [1000, 1010, 990])
        self.assertEqual(result['metrics']['live_malloc_blocks']['summary']['median'], 1000)

    def test_collect_xctest_scenario_from_side_files(self):
        # The Xcode 27 shape: nothing useful on the console but the outcome; the
        # custom lines come from the MIGRATION_PERF_OUTPUT file and XCTest's own
        # measurements from the result bundle.
        scenario = perf_lib.scenario_named('memory.scrollback_fill_20k')
        console = ("Test case 'MigrationBaselineTests.testMemoryScrollbackFill()' passed on "
                   "'My Mac - iTerm2 (1)' (5.0 seconds)\n")
        side = ('[MigrationPerf] {"better":"lower","metric":"live_malloc_blocks",'
                '"scenario":"memory.scrollback_fill_20k","unit":"count","values":[1,2,3]}\n'
                '[MigrationPerf] {"better":"lower","metric":"time","scenario":"parse.mixed_1mb",'
                '"unit":"s","values":[1]}\n')
        xcresult = perf_lib.parse_xcresult_metrics(json.loads(fixture('xcresult_metrics.json')))
        result = perf_lib.collect_xctest_scenario(scenario, console, exit_code=0, perf_lines=side,
                                                  xcresult_metrics=xcresult)
        self.assertEqual(result['status'], 'ok', result['reason'])
        self.assertEqual(set(result['metrics']), {'live_malloc_blocks', 'memory_peak_physical', 'throughput'})

    def test_collect_xctest_scenario_reads_only_its_own_metrics(self):
        scenario = perf_lib.scenario_named('screen.gang_fast_path')
        result = perf_lib.collect_xctest_scenario(scenario, fixture('xcodebuild_test_output.txt'), exit_code=0)
        self.assertEqual(set(result['metrics']), {'time'})

    def test_collect_xctest_scenario_failure(self):
        scenario = perf_lib.scenario_named('screen.char_at_a_time')
        result = perf_lib.collect_xctest_scenario(scenario, '** BUILD FAILED **\n', exit_code=65)
        self.assertEqual(result['status'], 'failed')
        self.assertIn('65', result['reason'])

    def test_stress_samples_to_metrics(self):
        runs = [{'iterations_per_sec': 9000, 'rss_kb': [100, 200, 300, 310, 305, 300]},
                {'iterations_per_sec': 9100, 'rss_kb': [100, 210, 320, 330, 300, 310]}]
        metrics = perf_lib.stress_metrics(runs)
        self.assertEqual(metrics['iterations_per_sec']['samples'], [9000, 9100])
        self.assertEqual(metrics['iterations_per_sec']['better'], 'higher')
        self.assertEqual(metrics['rss_peak']['samples'], [310, 330])
        # Steady state: the median of the second half of each run's samples.
        self.assertEqual(metrics['rss_steady']['samples'], [305, 310])


class CompareTests(unittest.TestCase):
    def setUp(self):
        self.base = load_result('result_baseline.json')
        self.cand = load_result('result_candidate.json')

    def rows(self, base=None, cand=None, **kwargs):
        report = perf_compare.compare(base or self.base, cand or self.cand, **kwargs)
        return report, {(r['scenario'], r['metric']): r for r in report['rows']}

    def test_verdicts(self):
        report, rows = self.rows()
        self.assertEqual(rows[('parse.mixed_1mb', 'time')]['verdict'], 'regression')
        self.assertAlmostEqual(rows[('parse.mixed_1mb', 'time')]['change_percent'], 20.0, places=6)
        self.assertEqual(rows[('app.stress_normal_1tab', 'iterations_per_sec')]['verdict'], 'no change')
        self.assertEqual(rows[('app.stress_normal_1tab', 'rss_peak')]['verdict'], 'improvement')
        self.assertEqual(rows[('memory.scrollback_fill_20k', 'process_peak_footprint')]['verdict'], 'inconclusive')
        self.assertEqual(rows[('draw.attributed_strings_mono', 'time_per_frame')]['verdict'], 'no change')
        self.assertEqual(rows[('screen.gang_fast_path', 'time')]['verdict'], 'no reference result')
        self.assertEqual(report['exit_code'], 1)

    def test_higher_is_better_drop_is_regression(self):
        cand = copy.deepcopy(self.base)
        m = cand['scenarios']['app.stress_normal_1tab']['metrics']['iterations_per_sec']
        m['samples'] = [x * 0.8 for x in m['samples']]
        _, rows = self.rows(cand=cand)
        row = rows[('app.stress_normal_1tab', 'iterations_per_sec')]
        self.assertEqual(row['verdict'], 'regression')
        self.assertAlmostEqual(row['change_percent'], 20.0, places=6)

    def test_change_within_threshold_is_no_change(self):
        cand = copy.deepcopy(self.base)
        m = cand['scenarios']['parse.mixed_1mb']['metrics']['time']
        m['samples'] = [x * 1.04 for x in m['samples']]
        report, rows = self.rows(cand=cand)
        self.assertEqual(rows[('parse.mixed_1mb', 'time')]['verdict'], 'no change')
        self.assertEqual(report['exit_code'], 0)

    def test_noise_widens_threshold(self):
        base = copy.deepcopy(self.base)
        cand = copy.deepcopy(self.base)
        noisy = [10.0, 10.4, 9.6, 10.3, 9.7, 10.2, 9.8, 10.0, 10.5, 9.5]
        base['scenarios']['parse.mixed_1mb']['metrics']['time']['samples'] = noisy
        cand['scenarios']['parse.mixed_1mb']['metrics']['time']['samples'] = [x * 1.07 for x in noisy]
        _, rows = self.rows(base=base, cand=cand)
        row = rows[('parse.mixed_1mb', 'time')]
        self.assertGreater(row['threshold_percent'], 7.0)
        self.assertEqual(row['verdict'], 'no change')

    def test_too_noisy_is_inconclusive(self):
        cand = copy.deepcopy(self.base)
        cand['scenarios']['parse.mixed_1mb']['metrics']['time']['samples'] = [
            0.05, 0.08, 0.03, 0.09, 0.02, 0.07, 0.04, 0.10, 0.05, 0.06]
        report, rows = self.rows(cand=cand)
        self.assertEqual(rows[('parse.mixed_1mb', 'time')]['verdict'], 'inconclusive')

    def test_too_few_samples_is_inconclusive(self):
        cand = copy.deepcopy(self.base)
        cand['scenarios']['parse.mixed_1mb']['metrics']['time']['samples'] = [0.2, 0.2]
        _, rows = self.rows(cand=cand)
        self.assertEqual(rows[('parse.mixed_1mb', 'time')]['verdict'], 'inconclusive')

    def test_missing_in_candidate(self):
        # A scenario absent from the candidate was not selected for that run.
        cand = copy.deepcopy(self.base)
        del cand['scenarios']['parse.mixed_1mb']
        _, rows = self.rows(cand=cand)
        self.assertEqual(rows[('parse.mixed_1mb', 'time')]['verdict'], 'not run in candidate')

    def test_refuses_non_baseline_reference(self):
        report, _ = self.rows(base=self.cand, cand=self.base)
        self.assertEqual(report['exit_code'], 2)
        self.assertTrue(any('not a baseline' in p for p in report['problems']))
        report, _ = self.rows(base=self.cand, cand=self.base, allow_non_baseline=True)
        self.assertEqual(report['problems'], [])
        self.assertTrue(any('not a baseline' in w for w in report['warnings']))

    def test_refuses_different_configuration_or_machine(self):
        cand = copy.deepcopy(self.cand)
        cand['configuration'] = 'Development'
        report, _ = self.rows(cand=cand)
        self.assertEqual(report['exit_code'], 2)
        cand = copy.deepcopy(self.cand)
        cand['machine']['chip'] = 'Apple M1'
        report, _ = self.rows(cand=cand)
        self.assertEqual(report['exit_code'], 2)
        report, _ = self.rows(cand=cand, allow_different_machine=True)
        self.assertEqual(report['exit_code'], 1)

    def test_busy_candidate_is_flagged(self):
        cand = copy.deepcopy(self.cand)
        cand['machine_state']['before']['quiet'] = False
        report, _ = self.rows(cand=cand)
        self.assertTrue(any('busy' in w for w in report['warnings']))

    def test_rule_is_marked_as_proposal(self):
        report, _ = self.rows()
        self.assertIn('proposal', report['rule'].lower())

    def test_command_line(self):
        out = subprocess.run([sys.executable, '-B', os.path.join(TOOL_DIR, 'perf_compare.py'),
                              os.path.join(FIXTURES, 'result_baseline.json'),
                              os.path.join(FIXTURES, 'result_candidate.json')],
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 1, out.stderr)
        self.assertIn('regression', out.stdout)
        self.assertIn('parse.mixed_1mb', out.stdout)
        out = subprocess.run([sys.executable, '-B', os.path.join(TOOL_DIR, 'perf_compare.py'), '--json',
                              os.path.join(FIXTURES, 'result_baseline.json'),
                              os.path.join(FIXTURES, 'result_candidate.json')],
                             capture_output=True, text=True)
        self.assertEqual(json.loads(out.stdout)['exit_code'], 1)


def _constant_result(samples_by_key, better='lower'):
    """A minimal baseline-labeled result with one metric per scenario."""
    base = load_result('result_baseline.json')
    base['scenarios'] = {}
    for (scenario, metric), samples in samples_by_key.items():
        base['scenarios'][scenario] = {'status': 'ok', 'reason': '', 'source': 'fixture',
                                       'metrics': {metric: {'unit': 'u', 'better': better,
                                                            'samples': list(samples)}}}
    return base


class CandidateFailureTests(unittest.TestCase):
    """Review B1: a scenario that fails in the candidate must not pass."""

    def setUp(self):
        self.base = load_result('result_baseline.json')

    def compare(self, cand):
        report = perf_compare.compare(self.base, cand)
        return report, {(r['scenario'], r['metric']): r for r in report['rows']}

    def test_failed_scenario_exits_1(self):
        cand = copy.deepcopy(self.base)
        cand['scenarios']['parse.mixed_1mb'].update(status='failed', reason='timed out after 1800 s', metrics={})
        report, rows = self.compare(cand)
        row = rows[('parse.mixed_1mb', 'time')]
        self.assertEqual(row['verdict'], 'failed in candidate')
        self.assertIn('timed out after 1800 s', row['note'])
        self.assertEqual(report['exit_code'], 1)

    def test_failed_scenario_that_kept_some_metrics_still_fails(self):
        cand = copy.deepcopy(self.base)
        cand['scenarios']['parse.mixed_1mb']['status'] = 'failed'
        cand['scenarios']['parse.mixed_1mb']['reason'] = 'test failed'
        report, rows = self.compare(cand)
        self.assertEqual(rows[('parse.mixed_1mb', 'time')]['verdict'], 'failed in candidate')
        self.assertEqual(report['exit_code'], 1)

    def test_metric_missing_from_an_ok_scenario_exits_1(self):
        cand = copy.deepcopy(self.base)
        del cand['scenarios']['app.stress_normal_1tab']['metrics']['rss_peak']
        report, rows = self.compare(cand)
        self.assertEqual(rows[('app.stress_normal_1tab', 'rss_peak')]['verdict'], 'missing in candidate')
        self.assertEqual(report['exit_code'], 1)

    def test_skipped_scenario_is_listed_but_does_not_fail(self):
        cand = copy.deepcopy(self.base)
        cand['scenarios']['app.stress_normal_1tab'].update(
            status='skipped', reason='a process named iTerm2 is running', metrics={})
        report, rows = self.compare(cand)
        row = rows[('app.stress_normal_1tab', 'iterations_per_sec')]
        self.assertEqual(row['verdict'], 'skipped in candidate')
        self.assertIn('iTerm2 is running', row['note'])
        self.assertEqual(report['exit_code'], 0)
        self.assertTrue(any('app.stress_normal_1tab' in w and 'not compared' in w for w in report['warnings']))

    def test_scenario_not_run_is_listed_but_does_not_fail(self):
        cand = copy.deepcopy(self.base)
        del cand['scenarios']['app.stress_normal_1tab']
        report, rows = self.compare(cand)
        self.assertEqual(rows[('app.stress_normal_1tab', 'rss_peak')]['verdict'], 'not run in candidate')
        self.assertEqual(report['exit_code'], 0)
        self.assertTrue(any('app.stress_normal_1tab' in w for w in report['warnings']))

    def test_failure_outranks_not_comparable(self):
        cand = copy.deepcopy(self.base)
        cand['configuration'] = 'Development'
        cand['scenarios']['parse.mixed_1mb'].update(status='failed', reason='crash', metrics={})
        report, _ = self.compare(cand)
        self.assertEqual(report['exit_code'], 2)

    def test_reviewer_all_failed_candidate(self):
        report, _ = self.compare(json.loads(fixture('result_baseline.json')) | {
            'scenarios': {k: dict(v, status='failed', reason='x', metrics={})
                          for k, v in self.base['scenarios'].items()}})
        self.assertEqual(report['exit_code'], 1)

    def test_command_line_exit_code_for_failed_scenario(self):
        cand = copy.deepcopy(self.base)
        cand['scenarios']['parse.mixed_1mb'].update(status='failed', reason='crash', metrics={})
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
            json.dump(cand, f)
        try:
            out = subprocess.run([sys.executable, '-B', os.path.join(TOOL_DIR, 'perf_compare.py'),
                                  os.path.join(FIXTURES, 'result_baseline.json'), f.name],
                                 capture_output=True, text=True)
        finally:
            os.unlink(f.name)
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn('failed in candidate', out.stdout)


class ScenarioUnionTests(unittest.TestCase):
    """Round 2 B1: every scenario in either file is accounted for."""

    S = 'memory.scrollback_fill_20k'

    def setUp(self):
        self.base = load_result('result_baseline.json')

    def pair(self, base_entry, cand_entry):
        b, c = copy.deepcopy(self.base), copy.deepcopy(self.base)
        for result, entry in ((b, base_entry), (c, cand_entry)):
            if entry is None:
                result['scenarios'].pop(self.S, None)
            elif entry != 'ok':
                result['scenarios'][self.S] = dict(entry, source='x', metrics={})
        report = perf_compare.compare(b, c)
        return report, [r for r in report['rows'] if r['scenario'] == self.S]

    FAILED = {'status': 'failed', 'reason': 'xcodebuild exited 65; test failed'}
    SKIPPED = {'status': 'skipped', 'reason': 'a process named iTerm2 is running'}

    def test_failed_in_both(self):
        report, rows = self.pair(self.FAILED, self.FAILED)
        self.assertEqual([r['verdict'] for r in rows], ['failed in candidate'])
        self.assertIn('xcodebuild exited 65', rows[0]['note'])
        self.assertIn('also failed in reference', rows[0]['note'])
        self.assertEqual(report['exit_code'], 1)

    def test_unknown_reference_status_counts_as_failed(self):
        report, rows = self.pair({'status': 'exploded', 'reason': 'r'}, self.FAILED)
        self.assertIn('also failed in reference', rows[0]['note'])
        report, rows = self.pair(self.SKIPPED, self.FAILED)
        self.assertNotIn('also failed in reference', rows[0]['note'])

    def test_failed_in_candidate_absent_from_reference(self):
        report, rows = self.pair(None, self.FAILED)
        self.assertEqual([r['verdict'] for r in rows], ['failed in candidate'])
        self.assertEqual(report['exit_code'], 1)

    def test_failed_in_candidate_skipped_in_reference(self):
        report, rows = self.pair(self.SKIPPED, self.FAILED)
        self.assertEqual([r['verdict'] for r in rows], ['failed in candidate'])
        self.assertEqual(report['exit_code'], 1)

    def test_unknown_candidate_status_is_failed(self):
        report, rows = self.pair('ok', {'status': 'exploded', 'reason': 'r'})
        self.assertTrue(rows and all(r['verdict'] == 'failed in candidate' for r in rows), rows)
        self.assertEqual(report['exit_code'], 1)
        report, rows = self.pair(None, {'status': 'exploded', 'reason': 'r'})
        self.assertEqual([r['verdict'] for r in rows], ['failed in candidate'])
        self.assertEqual(report['exit_code'], 1)

    def test_skipped_in_both(self):
        report, rows = self.pair(self.SKIPPED, self.SKIPPED)
        self.assertEqual([r['verdict'] for r in rows], ['skipped in candidate'])
        self.assertEqual(report['exit_code'], 0)
        self.assertTrue(any(self.S in w and 'not compared' in w for w in report['warnings']), report['warnings'])

    def test_skipped_in_candidate_failed_in_reference(self):
        report, rows = self.pair(self.FAILED, self.SKIPPED)
        self.assertEqual([r['verdict'] for r in rows], ['skipped in candidate'])
        self.assertEqual(report['exit_code'], 0)
        self.assertTrue(any(self.S in w for w in report['warnings']))

    def test_not_run_in_candidate_failed_in_reference(self):
        report, rows = self.pair(self.FAILED, None)
        self.assertEqual([r['verdict'] for r in rows], ['not run in candidate'])
        self.assertEqual(report['exit_code'], 0)
        self.assertTrue(any(self.S in w and 'not compared' in w for w in report['warnings']))

    def test_reference_failed_candidate_ok(self):
        report, rows = self.pair(self.FAILED, 'ok')
        self.assertTrue(rows)
        self.assertTrue(all(r['verdict'] == 'no reference result' for r in rows), rows)
        self.assertIn('failed', rows[0]['note'])
        self.assertEqual(report['exit_code'], 0)
        self.assertTrue(any(self.S in w and 'no reference result' in w for w in report['warnings']))

    def test_reference_absent_candidate_ok(self):
        report, rows = self.pair(None, 'ok')
        self.assertTrue(rows and all(r['verdict'] == 'no reference result' for r in rows))
        self.assertEqual(report['exit_code'], 0)
        self.assertTrue(any(self.S in w and 'no reference result' in w for w in report['warnings']))

    def test_reviewer_demo_both_failed_and_both_skipped_on_the_command_line(self):
        b, c = copy.deepcopy(self.base), copy.deepcopy(self.base)
        for r in (b, c):
            r['scenarios']['app.stress_normal_1tab'] = {'status': 'skipped', 'reason': 'iTerm2 running',
                                                        'source': 'x', 'metrics': {}}
            r['scenarios'][self.S] = {'status': 'failed', 'reason': 'xcodebuild exited 65', 'source': 'x',
                                      'metrics': {}}
        with tempfile.TemporaryDirectory() as d:
            for n, r in (('b', b), ('c', c)):
                with open(os.path.join(d, n + '.json'), 'w') as f:
                    json.dump(r, f)
            out = subprocess.run([sys.executable, '-B', os.path.join(TOOL_DIR, 'perf_compare.py'),
                                  '--allow-non-baseline', os.path.join(d, 'b.json'), os.path.join(d, 'c.json')],
                                 capture_output=True, text=True)
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertIn('failed in candidate', out.stdout)
        self.assertIn('also failed in reference', out.stdout)
        self.assertIn('not compared', out.stdout)
        self.assertIn('app.stress_normal_1tab', out.stdout)


class FailedScenarioLabelTests(unittest.TestCase):
    """Round 2 B1: a run with a failed scenario is not a baseline."""

    def assemble(self, scenarios, baseline=True):
        return perf_lib.assemble_result(
            baseline_requested=baseline, state_before=dict(QUIET), state_after=dict(QUIET),
            commit='abc', dirty=False, configuration='Deployment', arch='arm64',
            machine={}, scenarios=scenarios, settings={})

    def test_failed_scenario_refuses_the_baseline_label(self):
        result = self.assemble({'parse.mixed_1mb': {'status': 'ok', 'metrics': {}},
                                'draw.x': {'status': 'failed', 'metrics': {}},
                                'memory.y': {'status': 'failed', 'metrics': {}}})
        self.assertFalse(result['is_baseline'])
        self.assertEqual(result['label'], 'not a baseline: scenario failed: draw.x, memory.y')

    def test_unknown_status_refuses_the_baseline_label(self):
        result = self.assemble({'draw.x': {'status': 'exploded', 'metrics': {}}})
        self.assertFalse(result['is_baseline'])
        self.assertEqual(result['label'], 'not a baseline: scenario failed: draw.x')

    def test_skipped_scenario_keeps_the_label(self):
        result = self.assemble({'parse.mixed_1mb': {'status': 'ok', 'metrics': {}},
                                'app.z': {'status': 'skipped', 'metrics': {}}})
        self.assertTrue(result['is_baseline'])
        self.assertEqual(result['label'], 'baseline')

    def test_candidate_label_names_failed_scenarios(self):
        result = self.assemble({'draw.x': {'status': 'failed', 'metrics': {}}}, baseline=False)
        self.assertIn('scenario failed: draw.x', result['label'])


class InformationalMetricTests(unittest.TestCase):
    """Review N4: metrics with no signal are reported but never compared."""

    def test_informational_metric_is_not_compared(self):
        base = _constant_result({('memory.scrollback_fill_20k', 'footprint_growth'): [1.0] * 10})
        base['scenarios']['memory.scrollback_fill_20k']['metrics']['footprint_growth']['informational'] = True
        cand = copy.deepcopy(base)
        cand['scenarios']['memory.scrollback_fill_20k']['metrics']['footprint_growth']['samples'] = [9.0] * 10
        report = perf_compare.compare(base, cand)
        self.assertEqual(report['rows'][0]['verdict'], 'informational')
        self.assertEqual(report['exit_code'], 0)

    def test_collect_marks_known_noise_metrics(self):
        scenario = perf_lib.scenario_named('memory.scrollback_fill_20k')
        side = ('[MigrationPerf] {"better":"lower","metric":"footprint_growth",'
                '"scenario":"memory.scrollback_fill_20k","unit":"kB","values":[1,2,3]}\n'
                '[MigrationPerf] {"better":"lower","metric":"live_malloc_blocks",'
                '"scenario":"memory.scrollback_fill_20k","unit":"count","values":[1,2,3]}\n')
        xcresult = [{'test': scenario['test'], 'metric': 'memory_physical', 'unit': 'kB', 'better': 'lower',
                     'values': [1.0, 2.0]}]
        console = ("Test case 'MigrationBaselineTests.testMemoryScrollbackFill()' passed on 'x' (1 seconds)\n")
        result = perf_lib.collect_xctest_scenario(scenario, console, 0, perf_lines=side, xcresult_metrics=xcresult)
        self.assertTrue(result['metrics']['footprint_growth'].get('informational'))
        self.assertTrue(result['metrics']['memory_physical'].get('informational'))
        # Not deterministic yet (17% spread in the first runs); see performance.md.
        self.assertTrue(result['metrics']['live_malloc_blocks'].get('informational'))
        self.assertEqual(perf_lib.INFORMATIONAL_METRICS, {
            ('memory.scrollback_fill_20k', m) for m in
            ('footprint_growth', 'memory_physical', 'live_malloc_blocks', 'live_malloc_bytes')})


class ThresholdBoundaryTests(unittest.TestCase):
    """Review B2: pin threshold = max(5%, 3 x noise) on both sides, both directions."""

    KEY = ('parse.mixed_1mb', 'time')

    def verdict(self, base_samples, cand_samples, better):
        base = _constant_result({self.KEY: base_samples}, better=better)
        cand = _constant_result({self.KEY: cand_samples}, better=better)
        row = perf_compare.compare(base, cand)['rows'][0]
        return row['verdict'], row

    # No noise: the 5% floor decides.
    def test_floor_lower_is_better(self):
        self.assertEqual(self.verdict([1.0] * 10, [1.051] * 10, 'lower')[0], 'regression')
        self.assertEqual(self.verdict([1.0] * 10, [1.049] * 10, 'lower')[0], 'no change')
        self.assertEqual(self.verdict([1.0] * 10, [0.949] * 10, 'lower')[0], 'improvement')
        self.assertEqual(self.verdict([1.0] * 10, [0.951] * 10, 'lower')[0], 'no change')

    def test_floor_higher_is_better(self):
        self.assertEqual(self.verdict([100.0] * 10, [94.9] * 10, 'higher')[0], 'regression')
        self.assertEqual(self.verdict([100.0] * 10, [95.1] * 10, 'higher')[0], 'no change')
        self.assertEqual(self.verdict([100.0] * 10, [105.1] * 10, 'higher')[0], 'improvement')
        self.assertEqual(self.verdict([100.0] * 10, [104.9] * 10, 'higher')[0], 'no change')

    # Noise of 2.9652% (MAD 2 around a median of 100): 3 x noise = 8.8956% decides.
    NOISY = [98.0, 98.0, 98.0, 100.0, 100.0, 100.0, 100.0, 102.0, 102.0, 102.0]

    def scaled(self, k):
        return [x * k for x in self.NOISY]

    def test_noise_term_value(self):
        _, row = self.verdict(self.NOISY, self.NOISY, 'lower')
        self.assertAlmostEqual(row['noise_percent'], 2.9652, places=4)
        self.assertAlmostEqual(row['threshold_percent'], 8.8956, places=4)

    def test_noise_term_lower_is_better(self):
        self.assertEqual(self.verdict(self.NOISY, self.scaled(1.090), 'lower')[0], 'regression')
        self.assertEqual(self.verdict(self.NOISY, self.scaled(1.088), 'lower')[0], 'no change')
        self.assertEqual(self.verdict(self.NOISY, self.scaled(0.910), 'lower')[0], 'improvement')
        self.assertEqual(self.verdict(self.NOISY, self.scaled(0.912), 'lower')[0], 'no change')

    def test_noise_term_higher_is_better(self):
        self.assertEqual(self.verdict(self.NOISY, self.scaled(0.910), 'higher')[0], 'regression')
        self.assertEqual(self.verdict(self.NOISY, self.scaled(0.912), 'higher')[0], 'no change')
        self.assertEqual(self.verdict(self.NOISY, self.scaled(1.090), 'higher')[0], 'improvement')
        self.assertEqual(self.verdict(self.NOISY, self.scaled(1.088), 'higher')[0], 'no change')

    def test_sample_and_noise_limits(self):
        self.assertEqual(self.verdict([1.0] * 5, [2.0] * 5, 'lower')[0], 'regression')
        self.assertEqual(self.verdict([1.0] * 4, [2.0] * 5, 'lower')[0], 'inconclusive')
        # Noise just under and just over 10%: MAD 6.7 -> 9.93%; MAD 6.8 -> 10.08%.
        under = [93.3] * 3 + [100.0] * 4 + [106.7] * 3
        over = [93.2] * 3 + [100.0] * 4 + [106.8] * 3
        self.assertNotEqual(self.verdict(under, under, 'lower')[0], 'inconclusive')
        self.assertEqual(self.verdict(over, over, 'lower')[0], 'inconclusive')


class ComparabilityWarningTests(unittest.TestCase):
    """Review N6: Xcode and OS versions differ -> warning, not refusal."""

    def test_xcode_or_os_version_differs_is_a_warning(self):
        base = load_result('result_baseline.json')
        for key, value in (('xcode', 'Xcode 28.0'), ('os_version', '28.0')):
            cand = copy.deepcopy(base)
            cand['machine'][key] = value
            report = perf_compare.compare(base, cand)
            self.assertEqual(report['problems'], [])
            self.assertTrue(any(key in w for w in report['warnings']), report['warnings'])


class SafetyTests(unittest.TestCase):
    """Review N1, N2, N3, N6."""

    def test_patch_fails_closed_on_unknown_layout(self):
        plist = {'TestConfigurations': [{'Name': 'x', 'Targets': [{'BlueprintName': 'PerformanceTests'}]}]}
        with self.assertRaises(ValueError):
            perf_lib.patch_xctestrun(plist, suite='lane-3', environment={})

    def test_patch_fails_closed_with_no_targets(self):
        with self.assertRaises(ValueError):
            perf_lib.patch_xctestrun({'__xctestrun_metadata__': {'FormatVersion': 1}}, suite='s', environment={})

    def test_every_target_must_carry_the_suite(self):
        good = {'T': {'CommandLineArguments': ['-suite', 's']}, '__xctestrun_metadata__': {}}
        self.assertEqual(perf_lib.xctestrun_suite_problems(good, 's'), [])
        bad = {'T': {'CommandLineArguments': ['-suite', 's']}, 'U': {'CommandLineArguments': []},
               '__xctestrun_metadata__': {}}
        self.assertEqual(len(perf_lib.xctestrun_suite_problems(bad, 's')), 1)

    def test_pgrep_failure_means_maybe_running(self):
        class Out:
            def __init__(self, code):
                self.returncode = code
                self.stdout = ''

        self.assertTrue(perf_lib.process_may_be_running('iTerm2', run=lambda *a, **k: Out(0)))
        self.assertFalse(perf_lib.process_may_be_running('iTerm2', run=lambda *a, **k: Out(1)))
        self.assertTrue(perf_lib.process_may_be_running('iTerm2', run=lambda *a, **k: Out(2)))

        def boom(*a, **k):
            raise OSError('no pgrep')
        self.assertTrue(perf_lib.process_may_be_running('iTerm2', run=boom))

    def test_pids_with_exact_executable(self):
        paths = {101: '/x/lane-3/Build/Deployment/iTerm2.app/Contents/MacOS/iTerm2',
                 102: '/Applications/iTerm.app/Contents/MacOS/iTerm2',
                 103: '/x/lane-3/Build/Deployment/iTerm2.app/Contents/MacOS/iTerm2-helper',
                 104: '/x/lane-30/Build/Deployment/iTerm2.app/Contents/MacOS/iTerm2',
                 105: None}
        self.assertEqual(perf_lib.pids_with_executable(
            sorted(paths), '/x/lane-3/Build/Deployment/iTerm2.app/Contents/MacOS/iTerm2',
            path_of=paths.get), [101])

    def test_executable_path_is_the_real_binary_not_argv0(self):
        # A child whose argv[0] lies about what it is: `ps -o comm=` would show
        # the lie; proc_pidpath reports the binary.
        child = subprocess.Popen(['/x/lane-3/Build/Deployment/iTerm2.app/Contents/MacOS/iTerm2', '30'],
                                 executable='/bin/sleep')
        try:
            self.assertEqual(perf_lib.executable_path(child.pid), '/bin/sleep')
            self.assertEqual(perf_lib.pids_with_executable(
                [child.pid], '/x/lane-3/Build/Deployment/iTerm2.app/Contents/MacOS/iTerm2'), [])
            self.assertEqual(perf_lib.pids_with_executable([child.pid], '/bin/sleep'), [child.pid])
        finally:
            child.kill()
            child.wait()
        self.assertIsNone(perf_lib.executable_path(child.pid))

    def _run_baseline(self, dirty):
        """main(['run', '--baseline']) with the machine state, the tree's
        state, the build and the checkout all mocked: nothing here reads the
        real checkout, the real machine, or builds anything."""
        class Stop(Exception):
            pass

        calls = []

        def fake_build(*a, **k):
            calls.append('build')
            raise Stop()

        saved = (perf_lib.machine_state, perf_baseline.build, perf_baseline.dirty_paths, perf_baseline.REPO)
        with tempfile.TemporaryDirectory() as repo:
            try:
                perf_lib.machine_state = lambda: dict(QUIET)
                perf_baseline.build = fake_build
                perf_baseline.dirty_paths = lambda: list(dirty)
                perf_baseline.REPO = repo
                with redirect_stdout(io.StringIO()) as out:
                    try:
                        code = perf_baseline.main(['run', '--baseline', '--output', os.devnull])
                    except Stop:
                        code = 'built'
            finally:
                (perf_lib.machine_state, perf_baseline.build, perf_baseline.dirty_paths,
                 perf_baseline.REPO) = saved
        return code, calls, out.getvalue()

    def test_baseline_refused_up_front_on_dirty_tree(self):
        code, calls, out = self._run_baseline(['sources/Foo.m'])
        self.assertEqual(code, 3)
        self.assertEqual(calls, [])
        self.assertIn('uncommitted', out)
        self.assertIn('sources/Foo.m', out)

    def test_baseline_on_clean_tree_and_quiet_machine_goes_on_to_build(self):
        code, calls, _ = self._run_baseline([])
        self.assertEqual(code, 'built')
        self.assertEqual(calls, ['build'])

    def test_dirty_submodule_message_says_how_to_proceed(self):
        code, _, out = self._run_baseline(['submodules/iTerm2-shell-integration'])
        self.assertEqual(code, 3)
        self.assertIn('clean checkout', out)
        self.assertIn('git submodule update', out)

    def test_dirty_paths_ignore_docs_only(self):
        status = (' M docs/swift-migration/performance.md\n'
                  ' M submodules/iTerm2-shell-integration\n')
        self.assertEqual(perf_lib.dirty_paths(status), ['submodules/iTerm2-shell-integration'])
        self.assertEqual(perf_lib.dirty_paths(' M docs/a.md\n'), [])

    def test_every_run_option_has_help(self):
        parser_help = subprocess.run([sys.executable, '-B', os.path.join(TOOL_DIR, 'perf_baseline.py'),
                                      'run', '--help'], capture_output=True, text=True).stdout
        for option in ('--baseline', '--force', '--scenarios', '--iterations', '--app-runs', '--app-duration',
                       '--configuration', '--skip-build', '--settle-minutes', '--build-timeout',
                       '--test-timeout', '--output'):
            line = next((l for l in parser_help.splitlines() if l.strip().startswith(option)), None)
            self.assertIsNotNone(line, option)
            index = parser_help.index(line)
            following = parser_help[index:index + 400].splitlines()
            described = len(line.split()) > 2 or (len(following) > 1 and following[1].startswith(' ' * 10))
            self.assertTrue(described, option)


class ResultFileTests(unittest.TestCase):
    def test_assemble_result(self):
        result = perf_lib.assemble_result(
            baseline_requested=True,
            state_before=dict(QUIET), state_after=dict(QUIET),
            commit='abc', dirty=True, configuration='Deployment', arch='arm64',
            machine={'model': 'm'}, scenarios={'parse.mixed_1mb': {'status': 'ok', 'metrics': {}}},
            settings={'iterations': 10})
        self.assertEqual(result['schema'], perf_lib.SCHEMA)
        self.assertFalse(result['is_baseline'])
        self.assertIn('uncommitted', result['label'])
        self.assertTrue(result['machine_state']['before']['quiet'])
        self.assertEqual(result['thresholds'], perf_lib.QUIET_THRESHOLDS)

    def test_dirty_tree_is_not_a_baseline(self):
        result = perf_lib.assemble_result(
            baseline_requested=True, state_before=dict(QUIET), state_after=dict(QUIET),
            commit='abc', dirty=False, configuration='Deployment', arch='arm64',
            machine={}, scenarios={}, settings={})
        self.assertTrue(result['is_baseline'])
        self.assertEqual(result['label'], 'baseline')


if __name__ == '__main__':
    unittest.main()
