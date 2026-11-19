"""Tests for tools/swift_migration/test_timing.py, the test-log timing script.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests

The fixtures in fixtures/test_timing are small excerpts of real xcodebuild
test logs from tools/run_tests.expect, with the home directory replaced by
/Users/example and the suite summaries edited to describe the excerpt:

- serial_complete.log: a serial run that finished (from a run on 2026-07-16).
- serial_restart.log: a serial run whose test host crashed in the middle of a
  test and was restarted, ending with TEST FAILED (2026-06-14).
- parallel_complete.log: a -parallel run that finished (2026-11-12).
- parallel_failed.log: a -parallel run with two failures (2026-11-18).
- parallel_killed.log: a -parallel run killed by the stall watchdog
  (2026-11-19).
- build_only.log: the start of a build log, with no test output.
- swift_testing.log: a Swift package test run (2026-07-16) whose XCTest
  output is followed by Swift Testing's own lines, with their SF Symbol
  bytes kept as they were.

The parallel fixtures keep the run's "Testing started" line at the top,
since every real parallel log has one before its first result.

Every expected value below was worked out by hand from the fixture text.
Edge cases with no real example are written as small logs in a temporary
directory.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
TOOL = os.path.join(TOOL_DIR, 'test_timing.py')
FIXTURES = os.path.join(HERE, 'fixtures', 'test_timing')
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
sys.dont_write_bytecode = True

import test_timing as tt  # noqa: E402


def fixture(name):
    return os.path.join(FIXTURES, name)


def run_main(args):
    out = io.StringIO()
    err = io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        try:
            code = tt.main(args)
        except SystemExit as e:  # argparse exits on usage errors
            code = e.code
    return code, out.getvalue(), err.getvalue()


def run_json(path, *extra):
    code, out, err = run_main([path, '--json'] + list(extra))
    return code, json.loads(out) if out else None, err


class TempLogs:
    """Writes small synthetic logs to a temporary directory."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix='test_timing_')

    def write(self, text, name='log.txt'):
        path = os.path.join(self.dir, name)
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        return path

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


SERIAL_HEAD = ("Test Suite 'All tests' started at 2026-07-16 12:59:32.537.\n"
               "Test Suite 'ModernTests.xctest' started at 2026-07-16 12:59:32.538.\n"
               "Test Suite 'FooTests' started at 2026-07-16 12:59:32.538.\n")
SERIAL_TAIL = ("Test Suite 'FooTests' passed at 2026-07-16 12:59:33.000.\n"
               "\t Executed {n} {tests}, with 0 failures (0 unexpected) in {s} ({s}) seconds\n"
               "Test Suite 'ModernTests.xctest' passed at 2026-07-16 12:59:33.000.\n"
               "\t Executed {n} {tests}, with 0 failures (0 unexpected) in {s} ({s}) seconds\n"
               "Test Suite 'All tests' passed at 2026-07-16 12:59:33.000.\n"
               "\t Executed {n} {tests}, with 0 failures (0 unexpected) in {s} ({s}) seconds\n"
               "** TEST SUCCEEDED ** [10.000 sec]\n")


def serial_log(cases, n=None, s=None):
    """cases: list of (method, seconds) for class FooTests, all passing."""
    body = ''
    total = 0
    for method, secs in cases:
        body += "Test Case '-[ModernTests.FooTests %s]' started.\n" % method
        body += "Test Case '-[ModernTests.FooTests %s]' passed (%s seconds).\n" % (method, secs)
        total += int(secs.replace('.', ''))
    if n is None:
        n = len(cases)
    if s is None:
        s = '%d.%03d' % (total // 1000, total % 1000)
    return SERIAL_HEAD + body + SERIAL_TAIL.format(n=n, s=s, tests='test' if n == 1 else 'tests')


def parallel_line(name, status='passed', secs='0.010', pid='100'):
    return "Test case '%s' %s on 'My Mac - iTerm2 (%s)' (%s seconds)\n" % (name, status, pid, secs)


PARALLEL_END = "** TEST SUCCEEDED ** [9.000 sec]\n"


class NameTests(unittest.TestCase):
    def test_objc_name_with_module(self):
        self.assertEqual(tt.split_name('-[ModernTests.FooTests testA]'), ('FooTests', 'testA'))

    def test_objc_name_without_module(self):
        self.assertEqual(tt.split_name('-[iTermGitClientTests testAheadAndBehindBothCount]'),
                         ('iTermGitClientTests', 'testAheadAndBehindBothCount'))

    def test_swift_name(self):
        self.assertEqual(tt.split_name('LineBlockTests.testAppendAfterRemoveLastRawLine()'),
                         ('LineBlockTests', 'testAppendAfterRemoveLastRawLine'))

    def test_swift_name_with_module(self):
        self.assertEqual(tt.split_name('ModernTests.FooTests.testA()'), ('FooTests', 'testA'))

    def test_unrecognized_names(self):
        for name in ['FooTests testA', '-[FooTests]', 'FooTests.testA', '', 'a.b.c.d()', '-[A.B.C t]',
                     'FooTests.testA()x', '-[FooTests testA]x']:
            self.assertIsNone(tt.split_name(name), name)


class SerialCompleteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code, cls.j, cls.err = run_json(fixture('serial_complete.log'))

    def test_exit_code_and_format(self):
        self.assertEqual(self.code, 0)
        self.assertEqual(self.j['format'], 'serial')
        self.assertEqual(self.err, '')

    def test_counts_and_total(self):
        self.assertEqual(self.j['results'], {'total': 7, 'passed': 5, 'failed': 0, 'skipped': 2, 'other': 0})
        self.assertEqual(self.j['total_seconds'], 6.387)

    def test_complete(self):
        self.assertTrue(self.j['complete'])
        self.assertEqual(self.j['incomplete_reasons'], [])
        self.assertTrue(self.j['completed_summary'])
        self.assertEqual(self.j['end_marker'], {'line': 42, 'text': '** TEST SUCCEEDED ** [166.728 sec]'})
        self.assertEqual(self.j['started_without_result'], [])
        self.assertEqual(self.j['unparsed_lines'], [])
        self.assertEqual(self.j['restarts'], [])
        self.assertIsNone(self.j['suites_started_without_results'])

    def test_each_test_in_log_order(self):
        tests = self.j['tests']
        self.assertEqual(len(tests), 7)
        self.assertEqual(tests[0], {'test': 'AIBackslashEscapesTests/test_bmpUnicode_decodes',
                                    'class': 'AIBackslashEscapesTests', 'method': 'test_bmpUnicode_decodes',
                                    'status': 'passed', 'seconds': 0.002, 'line': 7, 'destination': None})
        self.assertEqual(tests[4], {'test': 'AILiveHarness/test_anthropic_chatReload_orphan_streaming',
                                    'class': 'AILiveHarness', 'method': 'test_anthropic_chatReload_orphan_streaming',
                                    'status': 'skipped', 'seconds': 0.002, 'line': 20, 'destination': None})
        self.assertEqual([t['line'] for t in tests], [7, 9, 11, 17, 20, 26, 28])

    def test_classes(self):
        self.assertEqual(self.j['classes'], [
            {'class': 'AIBackslashEscapesTests', 'tests': 3, 'seconds': 0.004},
            {'class': 'AILiveHarness', 'tests': 2, 'seconds': 0.005},
            {'class': 'AISafetyRefusalParserTests', 'tests': 2, 'seconds': 6.378},
        ])
        self.assertEqual([c['class'] for c in self.j['slowest_classes']],
                         ['AISafetyRefusalParserTests', 'AILiveHarness', 'AIBackslashEscapesTests'])

    def test_over_threshold(self):
        over = self.j['over_threshold']
        self.assertEqual(self.j['threshold_seconds'], 5.0)
        self.assertEqual(over['count'], 1)
        self.assertEqual(over['seconds'], 6.36)
        self.assertEqual(over['tests'][0]['test'],
                         'AISafetyRefusalParserTests/testEachStreamingFixtureProducesNonEmptyMessage')

    def test_slowest_order_breaks_ties_by_name(self):
        names = [t['test'] for t in self.j['slowest_tests']]
        self.assertEqual(names, [
            'AISafetyRefusalParserTests/testEachStreamingFixtureProducesNonEmptyMessage',
            'AISafetyRefusalParserTests/testEachNonStreamingFixtureProducesNonEmptyMessage',
            'AILiveHarness/test_anthropic_chatReload_orphan_nonStreaming',
            'AIBackslashEscapesTests/test_bmpUnicode_decodes',
            'AILiveHarness/test_anthropic_chatReload_orphan_streaming',
            'AIBackslashEscapesTests/test_bmpUnicode_nonHex_throws',
            'AIBackslashEscapesTests/test_bmpUnicode_truncated_throws',
        ])

    def test_log_totals(self):
        self.assertEqual(self.j['log_totals'], [{
            'launch': 1, 'suite': 'All tests', 'line': 33,
            'log_tests': 7, 'log_skipped': 2, 'log_failures': 0, 'log_seconds': 6.389,
            'parsed_tests': 7, 'parsed_seconds': 6.387,
            'count_agrees': True, 'seconds_difference': 0.002, 'tolerance': 0.0035, 'seconds_agree': True,
        }])
        self.assertEqual(self.j['suite_mismatches'], [])
        self.assertEqual(self.j['launches'], [{'launch': 1, 'suite': 'All tests', 'line': 3, 'summary': True}])

    def test_fail_over_with_exactly_one_test_over(self):
        code, out, err = run_main([fixture('serial_complete.log'), '--fail-over'])
        self.assertEqual(code, 1)
        self.assertEqual(err, '')

    def test_no_failing_list(self):
        self.assertEqual(self.j['failing_list'], {'present': False, 'names': [], 'without_failed_result': []})
        self.assertEqual(self.j['repeated_tests'], [])

    def test_text_output(self):
        code, out, err = run_main([fixture('serial_complete.log')])
        self.assertEqual(code, 0)
        self.assertIn('Format: serial', out)
        self.assertIn('Test-case results parsed: 7 (passed 5, failed 0, skipped 2)', out)
        self.assertIn('Started with no result: 0', out)
        self.assertIn('Lines that look like test output but could not be parsed: 0', out)
        self.assertIn('Completed-suite summary: yes', out)
        self.assertIn("Log totals, launch 1 ('All tests', line 33): log 7 tests in 6.389 s; "
                      "parsed 7 tests in 6.387 s; count agrees; time differs by 0.002 s, "
                      "within the tolerance of 0.0035 s (half a millisecond per test)", out)
        self.assertNotIn('rounding', out)
        self.assertIn('Total test time: 6.387 s over 7 results', out)
        self.assertIn('At or over 5.000 s: 1 tests, 6.360 s', out)
        self.assertIn('   6.360  passed   AISafetyRefusalParserTests/testEachStreamingFixtureProducesNonEmptyMessage',
                      out)
        self.assertNotIn('WARNING', out)


class SerialRestartTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code, cls.j, cls.err = run_json(fixture('serial_restart.log'))

    def test_counts_and_total(self):
        self.assertEqual(self.code, 0)
        self.assertEqual(self.j['results'], {'total': 8, 'passed': 7, 'failed': 1, 'skipped': 0, 'other': 0})
        self.assertEqual(self.j['total_seconds'], 144.381)

    def test_crashed_test_is_reported(self):
        self.assertEqual(self.j['started_without_result'], [
            {'test': 'AILiveHarness/test_chat_orphanToolResponseAfterStop_doesNotOrphanQueuedMessage', 'line': 15}])
        self.assertEqual(self.j['restarts'], [24])

    def test_incomplete(self):
        self.assertFalse(self.j['complete'])
        self.assertEqual(self.j['incomplete_reasons'], [
            '1 test(s) started with no result (crashed or interrupted)',
            'the test runner restarted 1 time(s) after a crash or timeout',
            '1 test(s) listed under Failing tests have no failed result line',
        ])
        self.assertTrue(self.j['completed_summary'])

    def test_launches_and_totals(self):
        self.assertEqual(self.j['launches'], [
            {'launch': 1, 'suite': 'All tests', 'line': 1, 'summary': False},
            {'launch': 2, 'suite': 'Selected tests', 'line': 26, 'summary': True},
        ])
        self.assertEqual(self.j['log_totals'], [{
            'launch': 2, 'suite': 'Selected tests', 'line': 52,
            'log_tests': 5, 'log_skipped': 0, 'log_failures': 2, 'log_seconds': 143.036,
            'parsed_tests': 5, 'parsed_seconds': 143.036,
            'count_agrees': True, 'seconds_difference': 0.0, 'tolerance': 0.0025, 'seconds_agree': True,
        }])
        self.assertEqual(self.j['suite_mismatches'], [])

    def test_failing_list(self):
        self.assertEqual(self.j['failing_list'], {
            'present': True,
            'names': ['AILiveHarness/test_chat_orphanToolResponseAfterStop_doesNotOrphanQueuedMessage',
                      'AILiveHarness/test_gemini_smoke_streaming',
                      'AILiveHarness/test_gemini_smoke_streaming'],
            'without_failed_result': ['AILiveHarness/test_chat_orphanToolResponseAfterStop_doesNotOrphanQueuedMessage'],
        })

    def test_performance_metric_line_is_not_unparsed(self):
        self.assertEqual(self.j['unparsed_lines'], [])

    def test_objc_class_without_module(self):
        cls = {c['class']: c for c in self.j['classes']}
        self.assertEqual(cls['iTermGitClientTests'], {'class': 'iTermGitClientTests', 'tests': 2, 'seconds': 2.504})
        self.assertEqual(cls['AILiveHarness'], {'class': 'AILiveHarness', 'tests': 3, 'seconds': 141.551})

    def test_over_threshold_includes_failed(self):
        over = self.j['over_threshold']
        self.assertEqual(over['count'], 2)
        self.assertEqual(over['seconds'], 140.209)
        self.assertEqual([(t['test'], t['status']) for t in over['tests']], [
            ('AILiveHarness/test_gemini_smoke_streaming', 'failed'),
            ('AILiveHarness/test_chat_stopThenSend_secondMessageStillDispatches', 'passed'),
        ])

    def test_text_warns(self):
        code, out, err = run_main([fixture('serial_restart.log')])
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith('WARNING: this report is incomplete.'), out[:200])
        self.assertIn('Started with no result: 1', out)
        self.assertIn('  line 15: AILiveHarness/test_chat_orphanToolResponseAfterStop_doesNotOrphanQueuedMessage', out)
        self.assertIn("Log totals, launch 1 ('All tests', line 1): none (the launch ended without a summary)", out)

    def test_fail_over_on_an_incomplete_log_exits_2(self):
        for extra in ([], ['--threshold', '1000']):
            code, out, err = run_main([fixture('serial_restart.log'), '--fail-over'] + extra)
            self.assertEqual(code, 2, extra)
            self.assertTrue(out.startswith('WARNING: this report is incomplete.'), out[:200])
            self.assertEqual(err, 'test_timing.py: %s: the report is incomplete, so --fail-over cannot pass it\n'
                             % fixture('serial_restart.log'))


class ParallelCompleteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code, cls.j, cls.err = run_json(fixture('parallel_complete.log'))

    def test_counts_and_total(self):
        self.assertEqual(self.code, 0)
        self.assertEqual(self.j['format'], 'parallel')
        self.assertEqual(self.j['results'], {'total': 13, 'passed': 11, 'failed': 0, 'skipped': 2, 'other': 0})
        self.assertEqual(self.j['total_seconds'], 432.27)

    def test_complete(self):
        self.assertTrue(self.j['complete'])
        self.assertTrue(self.j['completed_summary'])
        self.assertEqual(self.j['end_marker'], {'line': 29, 'text': '** TEST SUCCEEDED ** [607.604 sec]'})
        self.assertIsNone(self.j['started_without_result'])
        self.assertEqual(self.j['suites_started_without_results'], [])
        self.assertEqual(self.j['results_outside_started_suite'], [])
        self.assertEqual(self.j['log_totals'], [])
        self.assertEqual(self.j['launches'], [])

    def test_rows(self):
        t = self.j['tests']
        self.assertEqual(t[2], {'test': 'LegacyManualAIModelHeadersTests/testLegacyModelCarriesGlobalHeaders',
                                'class': 'LegacyManualAIModelHeadersTests',
                                'method': 'testLegacyModelCarriesGlobalHeaders', 'status': 'passed',
                                'seconds': 0.014, 'line': 8, 'destination': 'My Mac - iTerm2 (15892)'})
        self.assertEqual(t[4]['status'], 'skipped')
        self.assertEqual(t[4]['line'], 11)

    def test_slowest_and_threshold(self):
        self.assertEqual([(r['test'], r['seconds']) for r in self.j['slowest_tests'][:3]], [
            ('FramerFlowTwoHopSimulationTests/testANestedFloodRecoversWhenAJitteryOuterHopSpeedsUp', 249.212),
            ('FramerFlowTwoHopSimulationTests/testANestedFloodRecoversWhenTheOuterHopSpeedsUpAtAnyMoment', 114.301),
            ('ProcessCollectionTests/testProcessTableSnapshotMatchesPerPidLookupForSelf', 32.978),
        ])
        self.assertEqual(self.j['over_threshold']['count'], 5)
        self.assertEqual(self.j['over_threshold']['seconds'], 427.306)

    def test_classes(self):
        self.assertEqual(self.j['slowest_classes'], [
            {'class': 'FramerFlowTwoHopSimulationTests', 'tests': 6, 'seconds': 399.266},
            {'class': 'ProcessCollectionTests', 'tests': 1, 'seconds': 32.978},
            {'class': 'LegacyManualAIModelHeadersTests', 'tests': 2, 'seconds': 0.018},
            {'class': 'LineBlockTests', 'tests': 2, 'seconds': 0.005},
            {'class': 'UvProvisionerLiveTests', 'tests': 2, 'seconds': 0.003},
        ])

    def test_top_and_threshold_options(self):
        code, j, err = run_json(fixture('parallel_complete.log'), '--top', '2', '--threshold', '20.214')
        self.assertEqual(code, 0)
        self.assertEqual(len(j['slowest_tests']), 2)
        self.assertEqual(len(j['slowest_classes']), 2)
        self.assertEqual(len(j['tests']), 13)
        self.assertEqual(j['threshold_seconds'], 20.214)
        self.assertEqual(j['over_threshold']['count'], 4)
        self.assertEqual(j['over_threshold']['seconds'], 416.705)

    def test_fail_over(self):
        code, out, err = run_main([fixture('parallel_complete.log'), '--fail-over'])
        self.assertEqual(code, 1)
        code, out, err = run_main([fixture('parallel_complete.log'), '--fail-over', '--threshold', '250'])
        self.assertEqual(code, 0)

    def test_text_output(self):
        code, out, err = run_main([fixture('parallel_complete.log')])
        self.assertIn('Format: parallel', out)
        self.assertIn('Started with no result: not determinable per test in a parallel log; '
                      'suites started with no results: 0', out)
        self.assertIn('Log totals: none (a parallel log has no per-suite summaries)', out)
        self.assertIn('Completed-suite summary: yes (line 29: ** TEST SUCCEEDED ** [607.604 sec])', out)
        self.assertIn(' 249.212  passed   FramerFlowTwoHopSimulationTests/'
                      'testANestedFloodRecoversWhenAJitteryOuterHopSpeedsUp', out)
        self.assertIn(' 399.266      6  FramerFlowTwoHopSimulationTests', out)
        self.assertNotIn('All tests:', out)

    def test_all_lists_every_test_and_class(self):
        code, out, err = run_main([fixture('parallel_complete.log'), '--all', '--top', '1'])
        self.assertIn('All tests (13, in log order):', out)
        self.assertIn('All classes (5, by name):', out)
        self.assertIn('   0.001  skipped  UvProvisionerLiveTests/testProvisionFullEnvironmentEndToEnd', out)


class TestWithoutBuildingMarkerTests(unittest.TestCase):
    """xcodebuild test-without-building (tools/swift_migration/fast_tests.sh)
    ends its log with "** TEST EXECUTE SUCCEEDED **" or "** TEST EXECUTE
    FAILED **" instead of "** TEST SUCCEEDED **" or "** TEST FAILED **".
    The fixture is parallel_complete.log with the marker changed."""

    def setUp(self):
        self.logs = TempLogs()
        self.addCleanup(self.logs.cleanup)
        with open(fixture('parallel_complete.log'), encoding='utf-8') as f:
            self.text = f.read()

    def test_execute_succeeded_is_complete(self):
        path = self.logs.write(self.text.replace('** TEST SUCCEEDED ** [607.604 sec]',
                                                 '** TEST EXECUTE SUCCEEDED ** [607.604 sec]'))
        code, j, err = run_json(path)
        self.assertEqual(code, 0, err)
        self.assertTrue(j['complete'], j.get('incomplete_reasons'))

    def test_execute_failed_is_complete(self):
        path = self.logs.write(self.text.replace('** TEST SUCCEEDED ** [607.604 sec]', '** TEST EXECUTE FAILED **'))
        code, j, err = run_json(path)
        self.assertTrue(j['complete'], j.get('incomplete_reasons'))

    def test_other_markers_are_still_incomplete(self):
        path = self.logs.write(self.text.replace('** TEST SUCCEEDED ** [607.604 sec]', '** BUILD SUCCEEDED **'))
        code, j, err = run_json(path)
        self.assertFalse(j['complete'])


class ParallelFailedTests(unittest.TestCase):
    def test_failures(self):
        code, j, err = run_json(fixture('parallel_failed.log'))
        self.assertEqual(code, 0)
        self.assertEqual(j['results'], {'total': 5, 'passed': 3, 'failed': 2, 'skipped': 0, 'other': 0})
        self.assertEqual(j['total_seconds'], 0.371)
        self.assertEqual(j['failing_list'], {
            'present': True,
            'names': ['PTYSessionEndedMessageTests/testShortOutputMovesToTheBottomOfTheScreen',
                      'AsyncFilterTemporaryLineTests/testOnCompleteCallback'],
            'without_failed_result': [],
        })
        self.assertEqual(j['end_marker'], {'line': 19, 'text': '** TEST FAILED **'})
        self.assertTrue(j['complete'])


class ParallelKilledTests(unittest.TestCase):
    def test_killed_run(self):
        code, j, err = run_json(fixture('parallel_killed.log'))
        self.assertEqual(code, 0)
        self.assertEqual(j['results'], {'total': 3, 'passed': 3, 'failed': 0, 'skipped': 0, 'other': 0})
        self.assertEqual(j['total_seconds'], 0.041)
        self.assertFalse(j['complete'])
        self.assertFalse(j['completed_summary'])
        self.assertIsNone(j['end_marker'])
        self.assertEqual(j['suites_started_without_results'], [
            {'suite': 'WorkgroupModelThreadSafetyTests', 'destination': 'My Mac - iTerm2 (98945)', 'line': 6}])
        self.assertEqual(j['incomplete_reasons'], [
            'the log does not end with a completed-suite summary',
            '1 suite(s) started with no test results (crashed, hung or interrupted)',
        ])


class FormatErrorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TempLogs()

    def tearDown(self):
        self.tmp.cleanup()

    def test_build_log_is_unrecognized(self):
        code, out, err = run_main([fixture('build_only.log')])
        self.assertEqual(code, 2)
        self.assertEqual(out, '')
        self.assertIn('unrecognized log format', err)

    def test_empty_file(self):
        code, out, err = run_main([self.tmp.write('')])
        self.assertEqual(code, 2)
        self.assertIn('unrecognized log format', err)

    def test_suite_lines_only_is_unrecognized(self):
        code, out, err = run_main([self.tmp.write(SERIAL_HEAD)])
        self.assertEqual(code, 2)
        self.assertIn('unrecognized log format', err)

    def test_only_unparsable_test_lines_is_unrecognized(self):
        code, out, err = run_main([self.tmp.write("Test Case '-[ModernTests.FooTests testA]' passed (x seconds).\n")])
        self.assertEqual(code, 2)

    def test_mixed_formats(self):
        text = serial_log([('testA', '0.100')]) + parallel_line('BarTests.testB()')
        code, out, err = run_main([self.tmp.write(text)])
        self.assertEqual(code, 2)
        self.assertEqual(out, '')
        self.assertIn('both serial and parallel', err)

    def test_help_says_fail_over_rejects_an_incomplete_log(self):
        code, out, err = run_main(['--help'])
        self.assertEqual(code, 0)
        self.assertIn('exit 2 if the report is incomplete', ' '.join(out.split()))

    def test_missing_file(self):
        code, out, err = run_main([os.path.join(self.tmp.dir, 'nope.log')])
        self.assertEqual(code, 2)
        self.assertIn('cannot read', err)

    def test_bad_arguments(self):
        for args in (['--top', '-1'], ['--threshold', 'abc'], ['--threshold', '-1'], ['--bogus'], []):
            code, out, err = run_main(([fixture('serial_complete.log')] if args else []) + args)
            self.assertEqual(code, 2, args)


class SerialEdgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TempLogs()

    def tearDown(self):
        self.tmp.cleanup()

    def json_for(self, text, *extra):
        code, j, err = run_json(self.tmp.write(text), *extra)
        self.assertEqual(code, 0, err)
        return j

    def test_singular_summary(self):
        j = self.json_for(serial_log([('testA', '0.100')]))
        self.assertTrue(j['complete'], j['incomplete_reasons'])
        self.assertEqual(j['log_totals'][0]['log_tests'], 1)

    def test_singular_skip_and_failure(self):
        text = (SERIAL_HEAD
                + "Test Case '-[ModernTests.FooTests testA]' started.\n"
                + "Test Case '-[ModernTests.FooTests testA]' failed (0.200 seconds).\n"
                + "Test Case '-[ModernTests.FooTests testB]' started.\n"
                + "Test Case '-[ModernTests.FooTests testB]' skipped (0.001 seconds).\n"
                + "Test Suite 'FooTests' failed at 2026-07-16 12:59:33.000.\n"
                + "\t Executed 2 tests, with 1 test skipped and 1 failure (0 unexpected) in 0.201 (0.300) seconds\n"
                + "Test Suite 'ModernTests.xctest' failed at 2026-07-16 12:59:33.000.\n"
                + "\t Executed 2 tests, with 1 test skipped and 1 failure (0 unexpected) in 0.201 (0.300) seconds\n"
                + "Test Suite 'All tests' failed at 2026-07-16 12:59:33.000.\n"
                + "\t Executed 2 tests, with 1 test skipped and 1 failure (0 unexpected) in 0.201 (0.300) seconds\n"
                + "** TEST FAILED **\n")
        j = self.json_for(text)
        self.assertEqual(j['log_totals'][0]['log_skipped'], 1)
        self.assertEqual(j['log_totals'][0]['log_failures'], 1)
        self.assertEqual(j['results'], {'total': 2, 'passed': 0, 'failed': 1, 'skipped': 1, 'other': 0})
        self.assertTrue(j['complete'], j['incomplete_reasons'])

    def test_threshold_is_inclusive(self):
        j = self.json_for(serial_log([('testA', '5.000'), ('testB', '4.999')]))
        self.assertEqual(j['over_threshold']['count'], 1)
        self.assertEqual(j['over_threshold']['tests'][0]['test'], 'FooTests/testA')

    def test_count_mismatch(self):
        j = self.json_for(serial_log([('testA', '0.100')], n=2, s='0.100'))
        self.assertFalse(j['complete'])
        self.assertFalse(j['log_totals'][0]['count_agrees'])
        self.assertIn('the log\'s own totals disagree with the parsed results', j['incomplete_reasons'])
        self.assertEqual(len(j['suite_mismatches']), 2)
        self.assertEqual(j['suite_mismatches'][0], {'suite': 'FooTests', 'line': 6, 'log_tests': 2, 'parsed_tests': 1})

    def test_time_outside_rounding(self):
        j = self.json_for(serial_log([('testA', '0.100'), ('testB', '0.100')], s='0.202'))
        tot = j['log_totals'][0]
        self.assertTrue(tot['count_agrees'])
        self.assertEqual(tot['seconds_difference'], 0.002)
        self.assertEqual(tot['tolerance'], 0.001)
        self.assertFalse(tot['seconds_agree'])
        self.assertFalse(j['complete'])
        code, out, err = run_main([self.tmp.write(serial_log([('testA', '0.100'), ('testB', '0.100')], s='0.202'))])
        self.assertIn('time differs by 0.002 s, OUTSIDE THE TOLERANCE of 0.0010 s (half a millisecond per test)', out)
        self.assertNotIn('rounding', out)

    def test_time_at_rounding_bound_agrees(self):
        j = self.json_for(serial_log([('testA', '0.100'), ('testB', '0.100')], s='0.201'))
        self.assertTrue(j['log_totals'][0]['seconds_agree'])
        self.assertTrue(j['complete'])

    def test_unparsable_result_line(self):
        text = serial_log([('testA', '0.100')]).replace(
            "Test Suite 'FooTests' passed",
            "Test Case '-[ModernTests.FooTests testB]' passed (abc seconds).\nTest Suite 'FooTests' passed")
        j = self.json_for(text)
        self.assertEqual(j['unparsed_lines'],
                         [{'line': 6, 'text': "Test Case '-[ModernTests.FooTests testB]' passed (abc seconds)."}])
        self.assertFalse(j['complete'])
        self.assertIn('1 line(s) look like test output but could not be parsed', j['incomplete_reasons'])

    def test_result_embedded_after_other_output_is_unparsed(self):
        text = serial_log([('testA', '0.100'), ('testB', '0.100')]).replace(
            "Test Case '-[ModernTests.FooTests testA]' passed",
            "malloc: freedTest Case '-[ModernTests.FooTests testA]' passed")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [5])
        self.assertEqual(j['started_without_result'], [{'test': 'FooTests/testA', 'line': 4}])

    def test_unrecognized_test_name(self):
        text = serial_log([('testA', '0.100'), ('testB', '0.100')]).replace('-[ModernTests.FooTests testB]',
                                                                             'weird name')
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [6, 7])
        self.assertEqual(j['results']['total'], 1)

    def test_result_without_start(self):
        text = serial_log([('testA', '0.100')]).replace(
            "Test Case '-[ModernTests.FooTests testA]' started.\n", '')
        j = self.json_for(text)
        self.assertEqual(j['results_without_start'], [{'test': 'FooTests/testA', 'line': 4}])
        self.assertFalse(j['complete'])
        self.assertIn('1 result(s) without a matching start', j['incomplete_reasons'])

    def test_result_for_other_test_than_started(self):
        text = serial_log([('testA', '0.100')]).replace(
            "Test Case '-[ModernTests.FooTests testA]' passed", "Test Case '-[ModernTests.FooTests testZ]' passed")
        j = self.json_for(text)
        self.assertEqual(j['started_without_result'], [{'test': 'FooTests/testA', 'line': 4}])
        self.assertEqual(j['results_without_start'], [{'test': 'FooTests/testZ', 'line': 5}])

    def test_summary_without_suite_end_is_unparsed(self):
        text = serial_log([('testA', '0.100')]).replace(
            "** TEST SUCCEEDED **",
            "\t Executed 1 test, with 0 failures (0 unexpected) in 0.100 (0.100) seconds\n** TEST SUCCEEDED **")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [12])

    def test_bad_summary_line_is_unparsed(self):
        text = serial_log([('testA', '0.100')]).replace(
            "\t Executed 1 test, with 0 failures (0 unexpected) in 0.100 (0.100) seconds\nTest Suite 'ModernTests",
            "\t Executed one test, somehow\nTest Suite 'ModernTests")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [7])

    def test_unknown_suite_line_is_unparsed(self):
        text = serial_log([('testA', '0.100')]).replace(
            "Test Suite 'FooTests' passed at 2026-07-16 12:59:33.000.",
            "Test Suite 'FooTests' exploded at 2026-07-16 12:59:33.000.")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [6, 7])

    def test_missing_end_marker(self):
        text = serial_log([('testA', '0.100')]).replace('** TEST SUCCEEDED ** [10.000 sec]\n', '')
        j = self.json_for(text)
        self.assertFalse(j['completed_summary'])
        self.assertFalse(j['complete'])

    def test_missing_top_level_summary(self):
        text = serial_log([('testA', '0.100')])
        text = text[:text.index("Test Suite 'All tests' passed")] + '** TEST SUCCEEDED ** [1.000 sec]\n'
        j = self.json_for(text)
        self.assertFalse(j['completed_summary'])
        self.assertEqual(j['launches'][0]['summary'], False)
        self.assertFalse(j['complete'])
        self.assertEqual(j['incomplete_reasons'], ['the log does not end with a completed-suite summary'])

    def test_interrupted_marker_is_not_completion(self):
        text = serial_log([('testA', '0.100')]).replace('** TEST SUCCEEDED ** [10.000 sec]', '** TEST INTERRUPTED **')
        j = self.json_for(text)
        self.assertEqual(j['end_marker'], {'line': 12, 'text': '** TEST INTERRUPTED **'})
        self.assertFalse(j['completed_summary'])

    def test_build_interrupted_marker_is_recorded(self):
        # The end of tmp/ai_live_full.log (2026-07-15), a run stopped by hand.
        text = serial_log([('testA', '0.100')]).replace('** TEST SUCCEEDED ** [10.000 sec]', '** BUILD INTERRUPTED **')
        j = self.json_for(text)
        self.assertEqual(j['end_marker'], {'line': 12, 'text': '** BUILD INTERRUPTED **'})
        self.assertFalse(j['completed_summary'])

    def test_banner_line_is_not_a_marker(self):
        text = serial_log([('testA', '0.100')]) + '**' + ' ' * 64 + '**\n'
        j = self.json_for(text)
        self.assertEqual(j['end_marker']['text'], '** TEST SUCCEEDED ** [10.000 sec]')

    def test_repeated_test(self):
        text = serial_log([('testA', '0.100'), ('testA', '0.300')])
        j = self.json_for(text)
        self.assertEqual(j['repeated_tests'], [{'test': 'FooTests/testA', 'results': 2}])
        self.assertEqual(j['classes'], [{'class': 'FooTests', 'tests': 2, 'seconds': 0.4}])
        self.assertFalse(j['complete'])
        self.assertEqual(j['incomplete_reasons'], [
            '1 test(s) have more than one result with no restart between them '
            '(first: FooTests/testA, lines 5 and 7)'])
        self.assertEqual(j['repeated_without_restart'], [{'test': 'FooTests/testA', 'first_line': 5, 'line': 7}])

    def test_crlf_and_ansi(self):
        text = serial_log([('testA', '0.100')]).replace('\n', '\r\r\n').replace(
            '** TEST SUCCEEDED **', '\x1b[1m\x1b[31m** TEST SUCCEEDED **')
        j = self.json_for(text)
        self.assertTrue(j['complete'], j['incomplete_reasons'])
        self.assertEqual(j['end_marker']['text'], '** TEST SUCCEEDED ** [10.000 sec]')
        self.assertEqual(j['tests'][0]['line'], 5)

    def test_swift_testing_output_is_unparsed(self):
        text = serial_log([('testA', '0.100')]).replace(
            '** TEST SUCCEEDED **', '✔ Test example() passed after 0.001 seconds.\n** TEST SUCCEEDED **')
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [12])

    def test_swift_testing_lines_with_two_spaces_are_unparsed(self):
        code, j, err = run_json(fixture('swift_testing.log'))
        self.assertEqual(code, 0, err)
        self.assertEqual(j['results']['total'], 4)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [18, 19, 20, 21])
        self.assertEqual(j['unparsed_lines'][0]['text'], '\U001007c8  Test run started.')
        self.assertEqual(j['incomplete_reasons'], ['the log does not end with a completed-suite summary',
                                                   '4 line(s) look like test output but could not be parsed'])

    def test_unparsable_failing_list_entry(self):
        text = serial_log([('testA', '0.100')]) + 'Failing tests:\n\tsomething odd\n\n'
        j = self.json_for(text)
        self.assertEqual(j['unparsed_lines'], [{'line': 14, 'text': '\tsomething odd'}])

    def test_unparsed_lines_listed_in_text(self):
        text = serial_log([('testA', '0.100')]).replace(
            '** TEST SUCCEEDED **', "Test Case 'zzz' frobbed.\n** TEST SUCCEEDED **")
        code, out, err = run_main([self.tmp.write(text)])
        self.assertEqual(code, 0)
        self.assertIn("  line 12: Test Case 'zzz' frobbed.", out)

    # Added in the mutation pass: each pins a behavior a mutant got past.

    def test_result_line_needs_its_final_period(self):
        text = serial_log([('testA', '0.100'), ('testB', '0.100')]).replace(
            "testB]' passed (0.100 seconds).", "testB]' passed (0.100 seconds)")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [7])

    def test_start_line_with_trailing_text_is_unparsed(self):
        text = serial_log([('testA', '0.100')]).replace("testA]' started.", "testA]' started. then more")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [4])

    def test_summary_with_trailing_text_is_unparsed(self):
        text = serial_log([('testA', '0.100')]).replace(
            "in 0.100 (0.100) seconds\nTest Suite 'ModernTests", "in 0.100 (0.100) seconds and more\nTest Suite 'ModernTests")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [7])

    def test_new_top_level_suite_without_restart_line_starts_a_launch(self):
        # Two runs in one file: the first stops in the middle of a test.
        first = (SERIAL_HEAD + "Test Case '-[ModernTests.FooTests testA]' started.\n")
        second = serial_log([('testB', '0.200')]).replace("'All tests'", "'Selected tests'")
        j = self.json_for(first + second)
        self.assertEqual(j['launches'], [{'launch': 1, 'suite': 'All tests', 'line': 1, 'summary': False},
                                         {'launch': 2, 'suite': 'Selected tests', 'line': 5, 'summary': True}])
        self.assertEqual(j['started_without_result'], [{'test': 'FooTests/testA', 'line': 4}])
        self.assertEqual(j['log_totals'][0]['parsed_tests'], 1)
        self.assertEqual(j['suite_mismatches'], [])

    def test_suite_end_from_an_earlier_launch_is_unparsed(self):
        first = SERIAL_HEAD.replace('FooTests', 'OldTests')
        second = serial_log([('testB', '0.200')]).replace("'All tests'", "'Selected tests'").replace(
            "Test Suite 'FooTests' passed", "Test Suite 'OldTests' passed at 2026-07-16 12:59:33.000.\n"
            "Test Suite 'FooTests' passed")
        j = self.json_for(first + second)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [9])

    def test_outermost_suite_with_another_name_is_a_launch(self):
        text = serial_log([('testA', '0.100')])
        text = '\n'.join(l for l in text.split('\n')[:-1] if 'All tests' not in l) + '\n'
        text = text.replace("\t Executed 1 test, with 0 failures (0 unexpected) in 0.100 (0.100) seconds\n** TEST",
                            "** TEST")
        j = self.json_for(text)
        self.assertEqual(j['launches'], [{'launch': 1, 'suite': 'ModernTests.xctest', 'line': 1, 'summary': True}])
        self.assertTrue(j['complete'], j['incomplete_reasons'])

    def test_suite_end_closes_the_innermost_suite_of_that_name(self):
        text = serial_log([('testA', '0.100')]).replace(
            "Test Suite 'FooTests' started at 2026-07-16 12:59:32.538.\n",
            "Test Suite 'FooTests' started at 2026-07-16 12:59:32.538.\n"
            "Test Suite 'FooTests' started at 2026-07-16 12:59:32.538.\n").replace(
            "Test Suite 'FooTests' passed at 2026-07-16 12:59:33.000.\n\t Executed 1 test, with 0 failures (0 unexpected) "
            "in 0.100 (0.100) seconds\n",
            "Test Suite 'FooTests' passed at 2026-07-16 12:59:33.000.\n\t Executed 1 test, with 0 failures (0 unexpected) "
            "in 0.100 (0.100) seconds\n" * 2)
        j = self.json_for(text)
        self.assertEqual(j['unparsed_lines'], [])
        self.assertTrue(j['complete'], j['incomplete_reasons'])

    def test_ending_an_outer_suite_closes_the_inner_ones(self):
        text = serial_log([('testA', '0.100')]).replace(
            "Test Suite 'FooTests' passed at 2026-07-16 12:59:33.000.\n\t Executed 1 test, with 0 failures (0 unexpected) "
            "in 0.100 (0.100) seconds\n", '').replace(
            '** TEST SUCCEEDED **', "Test Suite 'FooTests' passed at 2026-07-16 12:59:33.000.\n** TEST SUCCEEDED **")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [10])

    def test_suite_end_that_never_started_is_unparsed(self):
        text = serial_log([('testA', '0.100')]).replace(
            '** TEST SUCCEEDED **', "Test Suite 'NeverTests' passed at 2026-07-16 12:59:33.000.\n** TEST SUCCEEDED **")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [12])

    def test_log_ending_inside_a_test(self):
        # Like the end of tmp/ai_live_full.log (2026-07-15), stopped during a test.
        text = SERIAL_HEAD + "Test Case '-[ModernTests.FooTests testA]' started.\n" \
            "Test Case '-[ModernTests.FooTests testA]' passed (0.100 seconds).\n" \
            "Test Case '-[ModernTests.FooTests testB]' started.\nsome output\n** BUILD INTERRUPTED **\n"
        j = self.json_for(text)
        self.assertEqual(j['started_without_result'], [{'test': 'FooTests/testB', 'line': 6}])

    def test_only_result_has_an_unrecognized_name(self):
        text = serial_log([('testA', '0.100')]).replace('-[ModernTests.FooTests testA]', 'weird name')
        code, out, err = run_main([self.tmp.write(text)])
        self.assertEqual(code, 2)
        self.assertIn('no test-case result line could be parsed', err)

    def test_equal_times_are_ordered_by_name(self):
        j = self.json_for(serial_log([('testB', '0.100'), ('testA', '0.100')]))
        self.assertEqual([t['test'] for t in j['slowest_tests']], ['FooTests/testA', 'FooTests/testB'])

    def test_log_total_below_parsed_beyond_rounding(self):
        j = self.json_for(serial_log([('testA', '0.100'), ('testB', '0.100')], s='0.198'))
        tot = j['log_totals'][0]
        self.assertEqual(tot['seconds_difference'], -0.002)
        self.assertFalse(tot['seconds_agree'])

    def test_failing_list_names_a_passed_test_and_repeats(self):
        text = serial_log([('testA', '0.100')]) + 'Failing tests:\n\tFooTests.testA()\n\tFooTests.testZ()\n' \
            '\tFooTests.testZ()\n\n'
        j = self.json_for(text)
        self.assertEqual(j['failing_list']['without_failed_result'], ['FooTests/testA', 'FooTests/testZ'])

    def test_unindented_line_after_failing_header_is_unparsed(self):
        text = serial_log([('testA', '0.100')]) + 'Failing tests:\nFooTests.testA()\n\n'
        j = self.json_for(text)
        self.assertEqual(j['unparsed_lines'], [{'line': 14, 'text': 'FooTests.testA()'}])
        self.assertEqual(j['failing_list']['names'], [])

    def test_last_marker_wins(self):
        text = '** BUILD SUCCEEDED **\n' + serial_log([('testA', '0.100')])
        j = self.json_for(text)
        self.assertEqual(j['end_marker'], {'line': 13, 'text': '** TEST SUCCEEDED ** [10.000 sec]'})

    def test_ansi_with_parameters(self):
        text = serial_log([('testA', '0.100')]).replace('** TEST SUCCEEDED **', '\x1b[1;31m** TEST SUCCEEDED **')
        j = self.json_for(text)
        self.assertTrue(j['completed_summary'])

    def test_restart_then_unnamed_outer_suite_is_a_new_launch(self):
        text = (SERIAL_HEAD + "Test Case '-[ModernTests.FooTests testA]' started.\n"
                + 'Restarting after unexpected exit, crash, or test timeout; summary will include totals from '
                  'previous launches.\n'
                + "Test Suite 'ModernTests.xctest' started at 2026-07-16 12:59:32.538.\n"
                + "Test Case '-[ModernTests.FooTests testB]' started.\n"
                + "Test Case '-[ModernTests.FooTests testB]' passed (0.100 seconds).\n")
        j = self.json_for(text)
        self.assertEqual([l['suite'] for l in j['launches']], ['All tests', 'ModernTests.xctest'])

    def test_summary_after_a_test_start_is_unparsed(self):
        text = serial_log([('testA', '0.100'), ('testB', '0.100')]).replace(
            "Test Case '-[ModernTests.FooTests testB]' started.\n",
            "Test Case '-[ModernTests.FooTests testB]' started.\n"
            "\t Executed 1 test, with 0 failures (0 unexpected) in 0.100 (0.100) seconds\n")
        text = text.replace("Test Case '-[ModernTests.FooTests testA]' passed (0.100 seconds).\n",
                            "Test Case '-[ModernTests.FooTests testA]' passed (0.100 seconds).\n"
                            "Test Suite 'InnerTests' started at 2026-07-16 12:59:32.538.\n"
                            "Test Suite 'InnerTests' passed at 2026-07-16 12:59:32.538.\n")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [9])

    def test_inner_suite_summary_that_disagrees_is_the_only_reason(self):
        text = serial_log([('testA', '0.100')]).replace('Executed 1 test,', 'Executed 2 tests,', 1)
        j = self.json_for(text)
        self.assertEqual(j['suite_mismatches'], [{'suite': 'FooTests', 'line': 6, 'log_tests': 2, 'parsed_tests': 1}])
        self.assertFalse(j['complete'])
        self.assertEqual(j['incomplete_reasons'], ['1 suite summaries disagree with the parsed results'])

    def test_result_after_a_suite_end_takes_the_summary_position(self):
        text = serial_log([('testA', '0.100')]).replace(
            "Test Suite 'FooTests' passed at 2026-07-16 12:59:33.000.\n",
            "Test Suite 'FooTests' passed at 2026-07-16 12:59:33.000.\n"
            "Test Case '-[ModernTests.FooTests testB]' passed (0.100 seconds).\n")
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [8])

    def test_indented_failing_header_is_not_a_header(self):
        text = serial_log([('testA', '0.100')]) + ' Failing tests:\n\tFooTests.testZ()\n\n'
        j = self.json_for(text)
        self.assertEqual(j['failing_list'], {'present': False, 'names': [], 'without_failed_result': []})
        self.assertTrue(j['complete'], j['incomplete_reasons'])


PARALLEL_HEAD = 'Testing started\n'


def parallel_suite(name, pid='100'):
    return "Test suite '%s' started on 'My Mac - iTerm2 (%s)'\n" % (name, pid)


class WholeRunTests(unittest.TestCase):
    """A log must hold exactly one whole run to be reported complete."""

    def setUp(self):
        self.tmp = TempLogs()

    def tearDown(self):
        self.tmp.cleanup()

    def json_for(self, text):
        code, j, err = run_json(self.tmp.write(text))
        self.assertEqual(code, 0, err)
        return j

    # B1: output after the end marker.

    def test_parallel_output_after_the_end_marker(self):
        text = (PARALLEL_HEAD + parallel_suite('FooTests') + parallel_line('FooTests.testA()') + PARALLEL_END
                + parallel_suite('BarTests') + parallel_line('BarTests.testB()'))
        j = self.json_for(text)
        self.assertFalse(j['complete'])
        self.assertFalse(j['completed_summary'])
        self.assertEqual(j['incomplete_reasons'], [
            'the log does not end with a completed-suite summary',
            "2 line(s) of test output follow the test end marker on line 4; the first is line 5: "
            "Test suite 'BarTests' started on 'My Mac - iTerm2 (100)'"])
        self.assertEqual(j['output_after_end_marker'], [
            {'line': 5, 'text': "Test suite 'BarTests' started on 'My Mac - iTerm2 (100)'"},
            {'line': 6, 'text': "Test case 'BarTests.testB()' passed on 'My Mac - iTerm2 (100)' (0.010 seconds)"}])
        code, out, err = run_main([self.tmp.write(text)])
        self.assertIn('Completed-suite summary: no (last marker, line 4: ** TEST SUCCEEDED ** [9.000 sec])', out)

    def test_serial_output_after_the_end_marker(self):
        text = (serial_log([('testA', '0.100')]) + "Test Case '-[ModernTests.FooTests testB]' started.\n"
                + "Test Case '-[ModernTests.FooTests testB]' passed (0.100 seconds).\n")
        j = self.json_for(text)
        self.assertFalse(j['complete'])
        self.assertFalse(j['completed_summary'])
        self.assertEqual(j['incomplete_reasons'], [
            'the log does not end with a completed-suite summary',
            "2 line(s) of test output follow the test end marker on line 12; the first is line 13: "
            "Test Case '-[ModernTests.FooTests testB]' started."])

    def test_one_result_right_after_the_end_marker(self):
        text = (PARALLEL_HEAD + parallel_suite('FooTests') + parallel_line('FooTests.testA()') + PARALLEL_END
                + parallel_line('FooTests.testB()'))
        j = self.json_for(text)
        self.assertFalse(j['completed_summary'])
        self.assertEqual(j['incomplete_reasons'], [
            'the log does not end with a completed-suite summary',
            "1 line(s) of test output follow the test end marker on line 4; the first is line 5: "
            "Test case 'FooTests.testB()' passed on 'My Mac - iTerm2 (100)' (0.010 seconds)"])

    def test_serial_suite_start_after_the_end_marker(self):
        text = serial_log([('testA', '0.100')]) + "Test Suite 'BarTests' started at 2026-07-16 12:59:33.000.\n"
        j = self.json_for(text)
        self.assertEqual(j['output_after_end_marker'],
                         [{'line': 13, 'text': "Test Suite 'BarTests' started at 2026-07-16 12:59:33.000."}])
        self.assertEqual(j['launches_without_restart'], [13])

    def test_other_output_after_the_end_marker_is_fine(self):
        j = self.json_for(serial_log([('testA', '0.100')]) + '*** Tests failed. ***\nexit=0\n')
        self.assertTrue(j['complete'], j['incomplete_reasons'])
        self.assertEqual(j['output_after_end_marker'], [])

    # B2: more than one run in one file.

    def test_two_test_end_markers(self):
        j = self.json_for(serial_log([('testA', '0.100')]) + '** TEST SUCCEEDED ** [1.000 sec]\n')
        self.assertFalse(j['complete'])
        self.assertEqual(j['incomplete_reasons'], ['the log has 2 test end markers (lines 12, 13); '
                                                   'it holds more than one run'])
        self.assertEqual(j['test_end_markers'], [{'line': 12, 'text': '** TEST SUCCEEDED ** [10.000 sec]'},
                                                 {'line': 13, 'text': '** TEST SUCCEEDED ** [1.000 sec]'}])

    def test_build_marker_before_the_test_marker_is_not_a_second_run(self):
        j = self.json_for('** BUILD SUCCEEDED **\n' + serial_log([('testA', '0.100')]))
        self.assertTrue(j['complete'], j['incomplete_reasons'])

    def test_serial_second_launch_without_a_restart_line(self):
        first = serial_log([('testA', '0.100')]).replace('** TEST SUCCEEDED ** [10.000 sec]\n', '')
        j = self.json_for(first + serial_log([('testB', '0.200')]))
        self.assertFalse(j['complete'])
        self.assertEqual(j['incomplete_reasons'], [
            '1 test launch(es) begin with no restart line before them (first on line 12); '
            'the log holds more than one run'])
        self.assertEqual(j['launches_without_restart'], [12])

    def test_serial_launch_after_a_restart_line_is_not_flagged(self):
        text = (SERIAL_HEAD + "Test Case '-[ModernTests.FooTests testA]' started.\n"
                + 'Restarting after unexpected exit, crash, or test timeout; summary will include totals from '
                  'previous launches.\n'
                + serial_log([('testB', '0.200')]).replace("'All tests'", "'Selected tests'"))
        j = self.json_for(text)
        self.assertEqual(j['launches_without_restart'], [])
        self.assertEqual(j['incomplete_reasons'], [
            '1 test(s) started with no result (crashed or interrupted)',
            'the test runner restarted 1 time(s) after a crash or timeout'])

    def test_launch_after_an_excused_launch_still_needs_its_own_restart(self):
        restart = ('Restarting after unexpected exit, crash, or test timeout; summary will include totals from '
                   'previous launches.\n')
        text = (PARALLEL_HEAD + parallel_suite('FooTests') + parallel_line('FooTests.testA()') + restart
                + PARALLEL_HEAD + parallel_suite('BarTests') + parallel_line('BarTests.testB()')
                + PARALLEL_HEAD + parallel_suite('BazTests') + parallel_line('BazTests.testC()') + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual(j['testing_started'], [1, 5, 8])
        self.assertEqual(j['launches_without_restart'], [8])

    def test_serial_log_with_testing_started_is_complete(self):
        j = self.json_for(PARALLEL_HEAD + serial_log([('testA', '0.100')]))
        self.assertTrue(j['complete'], j['incomplete_reasons'])
        self.assertEqual(j['testing_started'], [1])
        self.assertEqual(j['launches_without_restart'], [])

    def test_parallel_second_testing_started_without_a_restart_line(self):
        text = (PARALLEL_HEAD + parallel_suite('FooTests') + parallel_line('FooTests.testA()')
                + PARALLEL_HEAD + parallel_suite('BarTests') + parallel_line('BarTests.testB()') + PARALLEL_END)
        j = self.json_for(text)
        self.assertFalse(j['complete'])
        self.assertEqual(j['incomplete_reasons'], [
            '1 test launch(es) begin with no restart line before them (first on line 4); '
            'the log holds more than one run'])

    def test_two_whole_parallel_runs(self):
        run = PARALLEL_HEAD + parallel_suite('FooTests') + parallel_line('FooTests.testA()') + PARALLEL_END
        j = self.json_for(run + run)
        self.assertEqual(j['results']['total'], 2)
        self.assertFalse(j['complete'])
        self.assertEqual(j['incomplete_reasons'], [
            "2 line(s) of test output follow the test end marker on line 4; the first is line 6: "
            "Test suite 'FooTests' started on 'My Mac - iTerm2 (100)'",
            'the log has 2 test end markers (lines 4, 8); it holds more than one run',
            '1 test launch(es) begin with no restart line before them (first on line 5); '
            'the log holds more than one run',
            '1 test(s) have more than one result with no restart between them '
            '(first: FooTests/testA, lines 3 and 7)'])

    def test_parallel_duplicated_result_line(self):
        text = (PARALLEL_HEAD + parallel_suite('FooTests') + parallel_line('FooTests.testA()')
                + parallel_line('FooTests.testA()') + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual(j['incomplete_reasons'], [
            '1 test(s) have more than one result with no restart between them '
            '(first: FooTests/testA, lines 3 and 4)'])

    def test_repeat_across_a_restart_is_not_flagged_as_a_second_run(self):
        text = (PARALLEL_HEAD + parallel_suite('FooTests') + parallel_line('FooTests.testA()')
                + 'Restarting after unexpected exit, crash, or test timeout; summary will include totals from '
                  'previous launches.\n'
                + parallel_suite('FooTests') + parallel_line('FooTests.testA()') + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual(j['repeated_tests'], [{'test': 'FooTests/testA', 'results': 2}])
        self.assertEqual(j['repeated_without_restart'], [])
        self.assertEqual(j['incomplete_reasons'], ['the test runner restarted 1 time(s) after a crash or timeout'])

    # B3: a parallel log missing its head.

    def test_parallel_log_without_testing_started(self):
        j = self.json_for(parallel_suite('FooTests') + parallel_line('FooTests.testA()') + PARALLEL_END)
        self.assertFalse(j['complete'])
        self.assertEqual(j['incomplete_reasons'], [
            "no 'Testing started' line before the first result (line 2); the start of the log may be missing"])

    def test_testing_started_after_the_first_result_does_not_count(self):
        text = (parallel_suite('FooTests') + parallel_line('FooTests.testA()') + PARALLEL_HEAD
                + parallel_line('FooTests.testB()') + PARALLEL_END)
        j = self.json_for(text)
        self.assertIn("no 'Testing started' line before the first result (line 2); the start of the log may be "
                      "missing", j['incomplete_reasons'])

    def test_testing_started_must_be_the_whole_line(self):
        text = ('Testing started later\n' + parallel_suite('FooTests') + parallel_line('FooTests.testA()')
                + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual(j['testing_started'], [])
        self.assertEqual(j['incomplete_reasons'], [
            "no 'Testing started' line before the first result (line 3); the start of the log may be missing"])

    def test_results_before_any_suite_started_are_outside(self):
        text = (PARALLEL_HEAD + parallel_line('FooTests.testA()') + parallel_suite('FooTests')
                + parallel_line('FooTests.testB()') + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual(j['results_outside_started_suite'], [{'test': 'FooTests/testA', 'line': 2}])
        self.assertEqual(j['incomplete_reasons'], ['1 result(s) outside the suite started on their destination'])

    def test_result_on_a_host_with_no_suite_started(self):
        text = (PARALLEL_HEAD + parallel_suite('FooTests', '100') + parallel_line('FooTests.testA()', pid='100')
                + parallel_line('FooTests.testB()', pid='200') + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual(j['results_outside_started_suite'], [{'test': 'FooTests/testB', 'line': 4}])
        self.assertFalse(j['complete'])

    def test_whole_parallel_run_is_complete(self):
        text = (PARALLEL_HEAD + parallel_suite('FooTests', '100') + parallel_suite('BarTests', '200')
                + parallel_line('FooTests.testA()', pid='100') + parallel_line('BarTests.testB()', pid='200')
                + PARALLEL_END)
        j = self.json_for(text)
        self.assertTrue(j['complete'], j['incomplete_reasons'])
        self.assertEqual(j['testing_started'], [1])


class ParallelEdgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TempLogs()

    def tearDown(self):
        self.tmp.cleanup()

    def json_for(self, text):
        code, j, err = run_json(self.tmp.write(text))
        self.assertEqual(code, 0, err)
        return j

    def test_result_outside_started_suite(self):
        text = ("Test suite 'FooTests' started on 'My Mac - iTerm2 (100)'\n"
                + parallel_line('FooTests.testA()')
                + parallel_line('BarTests.testB()')
                + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual(j['results_outside_started_suite'], [{'test': 'BarTests/testB', 'line': 3}])
        self.assertFalse(j['complete'])
        self.assertIn('1 result(s) outside the suite started on their destination', j['incomplete_reasons'])

    def test_no_suite_lines_means_every_result_is_outside(self):
        j = self.json_for(PARALLEL_HEAD + parallel_line('FooTests.testA()') + PARALLEL_END)
        self.assertEqual(j['results_outside_started_suite'], [{'test': 'FooTests/testA', 'line': 2}])
        self.assertFalse(j['complete'])

    def test_suite_without_results_followed_by_another(self):
        text = ("Test suite 'FooTests' started on 'My Mac - iTerm2 (100)'\n"
                "Test suite 'BarTests' started on 'My Mac - iTerm2 (100)'\n"
                + parallel_line('BarTests.testB()')
                + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual(j['suites_started_without_results'],
                         [{'suite': 'FooTests', 'destination': 'My Mac - iTerm2 (100)', 'line': 1}])

    def test_unknown_suite_line_is_unparsed(self):
        text = (parallel_line('FooTests.testA()')
                + "Test suite 'FooTests' finished on 'My Mac - iTerm2 (100)'\n" + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [2])

    def test_restart(self):
        text = (parallel_line('FooTests.testA()')
                + 'Restarting after unexpected exit, crash, or test timeout; summary will include totals from '
                  'previous launches.\n'
                + parallel_line('FooTests.testB()') + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual(j['restarts'], [2])
        self.assertFalse(j['complete'])

    def test_failing_list_without_result(self):
        text = (parallel_line('FooTests.testA()') + 'Failing tests:\n\tFooTests.testB()\n\t-[BarTests testC]\n\n'
                + '** TEST FAILED **\n')
        j = self.json_for(text)
        self.assertEqual(j['failing_list']['without_failed_result'], ['FooTests/testB', 'BarTests/testC'])
        self.assertIn('2 test(s) listed under Failing tests have no failed result line', j['incomplete_reasons'])

    def test_suite_line_with_trailing_text_is_unparsed(self):
        text = ("Test suite 'FooTests' started on 'My Mac - iTerm2 (100)' again\n"
                + parallel_line('FooTests.testA()') + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [1])

    def test_unknown_lowercase_case_line_is_unparsed(self):
        text = (parallel_line('FooTests.testA()')
                + "Test case 'FooTests.testB()' crashed on 'My Mac - iTerm2 (100)'\n" + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual([u['line'] for u in j['unparsed_lines']], [2])

    def test_suites_without_results_are_in_line_order(self):
        text = ("Test suite 'YTests' started on 'My Mac - iTerm2 (200)'\n"
                "Test suite 'XTests' started on 'My Mac - iTerm2 (100)'\n"
                "Test suite 'ZTests' started on 'My Mac - iTerm2 (100)'\n"
                + parallel_line('ZTests.testA()') + PARALLEL_END)
        j = self.json_for(text)
        self.assertEqual([s['line'] for s in j['suites_started_without_results']], [1, 2])


class HygieneTests(unittest.TestCase):
    def test_deterministic_and_writes_nothing(self):
        work = tempfile.mkdtemp(prefix='test_timing_cwd_')
        try:
            log = os.path.join(work, 'run.log')
            shutil.copy(fixture('serial_restart.log'), log)
            before = sorted(os.listdir(work))
            outs = []
            for args in ([], ['--json'], ['--all']):
                for _ in range(2):
                    p = subprocess.run([sys.executable, '-B', TOOL, log] + args, cwd=work,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    self.assertEqual(p.returncode, 0, p.stderr)
                    outs.append(p.stdout)
            self.assertEqual(outs[0], outs[1])
            self.assertEqual(outs[2], outs[3])
            self.assertEqual(outs[4], outs[5])
            self.assertEqual(sorted(os.listdir(work)), before)
        finally:
            shutil.rmtree(work, ignore_errors=True)

    def test_subprocess_exit_code_for_unrecognized(self):
        p = subprocess.run([sys.executable, '-B', TOOL, fixture('build_only.log')],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, b'')


class OtherResultWordingTests(unittest.TestCase):
    """XCTest prints "recorded an expected failure" for a test whose failures
    were all expected (XCTExpectFailure); it is an executed, passing test.
    Any other wording with a time is an executed test with status "other",
    so a new wording cannot make a run look empty. The parallel lines are
    from the fast-tier run of 2026-11-20."""

    def setUp(self):
        self.logs = TempLogs()
        self.addCleanup(self.logs.cleanup)

    def test_parallel_expected_failure_is_passed(self):
        text = (PARALLEL_HEAD + parallel_suite('SwiftMigrationBetaAssertionFailsTestTests', '25466')
                + "Test case 'SwiftMigrationBetaAssertionFailsTestTests.testBetaAssertFailsTheRunningTest()' "
                  "recorded an expected failure on 'My Mac - iTerm2 (25466)' (7.495 seconds)\n"
                + parallel_line('SwiftMigrationBetaAssertionFailsTestTests.testOther()', pid='25466')
                + PARALLEL_END)
        code, j, err = run_json(self.logs.write(text))
        self.assertEqual(code, 0, err)
        self.assertEqual(j['results'], {'total': 2, 'passed': 2, 'failed': 0, 'skipped': 0, 'other': 0})
        self.assertEqual(j['unparsed_lines'], [])
        self.assertTrue(j['complete'], j['incomplete_reasons'])

    def test_serial_expected_failure_is_passed(self):
        text = (SERIAL_HEAD
                + "Test Case '-[ModernTests.FooTests testA]' started.\n"
                + "Test Case '-[ModernTests.FooTests testA]' recorded an expected failure (0.010 seconds).\n"
                + SERIAL_TAIL.format(n=1, s='0.010', tests='test'))
        code, j, err = run_json(self.logs.write(text))
        self.assertEqual(j['results'], {'total': 1, 'passed': 1, 'failed': 0, 'skipped': 0, 'other': 0})
        self.assertEqual(j['unparsed_lines'], [])
        self.assertTrue(j['complete'], j['incomplete_reasons'])

    def test_unknown_wording_is_other(self):
        text = (PARALLEL_HEAD + parallel_suite('FooTests')
                + parallel_line('FooTests.testA()', status='was quarantined')
                + PARALLEL_END)
        code, j, err = run_json(self.logs.write(text))
        self.assertEqual(code, 0, err)
        self.assertEqual(j['results'], {'total': 1, 'passed': 0, 'failed': 0, 'skipped': 0, 'other': 1})
        self.assertEqual(j['unparsed_lines'], [])
        code, out, err = run_main([self.logs.write(text, 'b.txt')])
        self.assertIn('Test-case results parsed: 1 (passed 0, failed 0, skipped 0, other 1)', out)


class SkipListTests(unittest.TestCase):
    """--skip-list FILE (the slow_tier.txt format): xcodebuild still starts a
    suite whose every test -skip-testing removed, and prints no result for
    it. Such a suite does not make the report incomplete when FILE lists the
    class, or one of its methods."""

    def setUp(self):
        self.logs = TempLogs()
        self.addCleanup(self.logs.cleanup)
        self.text = (PARALLEL_HEAD + parallel_suite('GermanFormalAddressTests', '7')
                     + parallel_suite('FooTests') + parallel_line('FooTests.testA()')
                     + parallel_suite('WholeTests', '8')
                     + parallel_suite('BarTests', '7') + parallel_line('BarTests.testB()', pid='7')
                     + parallel_suite('BazTests', '8') + parallel_line('BazTests.testC()', pid='8')
                     + PARALLEL_END)

    def test_without_skip_list_the_empty_suites_are_reported(self):
        code, j, err = run_json(self.logs.write(self.text))
        self.assertFalse(j['complete'])
        self.assertEqual([s['suite'] for s in j['suites_started_without_results']],
                         ['GermanFormalAddressTests', 'WholeTests'])

    def test_listed_suites_are_exempt(self):
        listing = self.logs.write("# comment\n\nWholeTests  reason\n"
                                  "GermanFormalAddressTests/testGermanDoesNotUseInformalAddress  one second\n",
                                  'slow.txt')
        code, j, err = run_json(self.logs.write(self.text), '--skip-list', listing)
        self.assertEqual(code, 0, err)
        self.assertTrue(j['complete'], j['incomplete_reasons'])
        self.assertEqual(j['suites_started_without_results'], [])
        self.assertEqual(j['suites_skipped_by_list'], ['GermanFormalAddressTests', 'WholeTests'])

    def test_unlisted_empty_suite_still_counts(self):
        listing = self.logs.write("WholeTests  reason\n", 'slow.txt')
        code, j, err = run_json(self.logs.write(self.text), '--skip-list', listing)
        self.assertFalse(j['complete'])
        self.assertEqual([s['suite'] for s in j['suites_started_without_results']], ['GermanFormalAddressTests'])

    def test_unreadable_skip_list_is_an_error(self):
        code, out, err = run_main([self.logs.write(self.text), '--skip-list', '/nonexistent/slow.txt'])
        self.assertEqual(code, 2)
        self.assertIn('cannot read', err)


if __name__ == '__main__':
    unittest.main()
