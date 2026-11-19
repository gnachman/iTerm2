#!/usr/bin/env python3
"""Per-test and per-class times from an xcodebuild test log.

Part of the Objective-C to Swift migration (docs/swift-migration/test-speed.md
and orchestration.md section 9, "Test-log timing script"). It reads the log
of a run of tools/run_tests.expect, which is xcodebuild's own console output,
and reports the time of each test and each test class, the slowest N, the
tests at or over a threshold (default 5 seconds, the "5 seconds or more" of
test-speed.md section 1), and the total, so that slow tests can be found and
a fast tier defined. run_tests.expect does not save its output; save it
yourself, for example:

    tools/run_tests.expect -parallel 2>&1 | tee tmp/full-tests.log
    python3 -B tools/swift_migration/test_timing.py tmp/full-tests.log

Usage:
    test_timing.py LOG [--top N] [--threshold SECONDS] [--all] [--json] [--fail-over]
                       [--skip-list FILE]

    --top N            how many of the slowest tests and classes to list (20)
    --threshold S      list tests taking S seconds or more (5)
    --all              also list every test (in log order) and every class
                       (by name) in the text output; JSON always has them
    --json             machine-readable output
    --fail-over        exit 1 if any test is at or over the threshold, and
                       exit 2 if the report is incomplete (a gate must not
                       pass a log that cannot be trusted)
    --skip-list FILE   a list in the format of tools/swift_migration/slow_tier.txt.
                       xcodebuild -skip-testing still starts a suite whose
                       every test it skips, and that suite prints no result;
                       a suite with no results whose class FILE names, whole
                       or by one of its methods, is then not counted as
                       damage. It is listed apart (suites_skipped_by_list).

Exit status: 0 success, 1 tests at or over the threshold with --fail-over,
2 usage error, unreadable file, a log that is not in a recognized format, or
an incomplete report with --fail-over.
Python 3 standard library only. Writes nothing to disk; run with python3 -B.

Two log formats are recognized, by their test-case result lines:

- serial (run_tests.expect without -parallel):
      Test Case '-[ModernTests.FooTests testBar]' started.
      Test Case '-[ModernTests.FooTests testBar]' passed (0.012 seconds).
  with "failed" and "skipped" as the other results ("recorded an expected
  failure" counts as passed, and any other wording before the time as an
  executed test with status "other"), nested
  "Test Suite 'X' started at ..." / "passed|failed at ..." lines, each end
  followed by "Executed N tests, with [S tests skipped and] F failures (U
  unexpected) in A (B) seconds". After a test-host crash xcodebuild prints
  "Restarting after unexpected exit ..." and begins a new launch with a
  'Selected tests' suite; the summaries then count only that launch, so the
  log's totals are compared with each launch separately.
- parallel (-parallel):
      Test suite 'FooTests' started on 'My Mac - iTerm2 (123)'
      Test case 'FooTests.testBar()' passed on 'My Mac - iTerm2 (123)' (0.012 seconds)
  ("-[FooTests testBar]" for Objective-C test classes). There are no
  per-test start lines and no suite summaries. Every real parallel log has a
  "Testing started" line before its first result, and every result must come
  from the suite most recently started on its test host.

A log with no result line in either format, or with result lines in both,
is an error (exit 2), never an empty table.

The report is marked incomplete for every kind of damage listed below. One
limit remains: a parallel log carries no totals, so result lines or whole
suites lost from the middle of a parallel log cannot be detected. It states how many result
lines were parsed; which tests started and have no result (serial; in a
parallel log this cannot be known per test, so it lists suites that started
on a test host and produced no results); every line that looks like test
output but matches no known form; restarts after a crash; whether the log
ends with a completed-suite summary ("** TEST SUCCEEDED **" or
"** TEST FAILED **", or from xcodebuild test-without-building
"** TEST EXECUTE SUCCEEDED **" or "** TEST EXECUTE FAILED **", with no test
output after it, and for serial logs the
summary of the last launch's top-level suite); the log's own totals next to
the parsed ones; and tests named under "Failing tests:" that have no failed
result line. Any of these makes the report incomplete: the text output then
starts with a WARNING and the JSON has "complete": false with the reasons.

A log must also hold exactly one run. run_tests.expect never repeats a test;
only a restart after a crash re-runs anything, and a restart is already
reported. So these also make the report incomplete: test output (a result,
a test start or a suite start) after a "** TEST ... **" marker; more than one
such marker; a second launch (a top-level suite in a serial log, a "Testing
started" line in a parallel one) with no restart line before it; and a test
with more than one result and no restart line between them. A parallel log
with no "Testing started" line before its first result has lost its start.

Times are summed exactly (decimal arithmetic). The log's total for a launch
is accepted if it is within half a millisecond per test of the parsed total;
that tolerance is printed with the comparison.

A test that has more than one result is listed once per result, and its
class total includes each; such tests are listed separately. Test ids are
Class/method with any module prefix removed.
"""

import argparse
import json
import re
import sys
from decimal import Decimal

sys.dont_write_bytecode = True

THRESHOLD_DEFAULT = Decimal('5')
TOP_DEFAULT = 20

SECONDS = r'([0-9]+(?:\.[0-9]+)?)'
# The result word is "passed", "failed" or "skipped", or another wording
# such as "recorded an expected failure" (see status_of).
RESULT_WORDS = r"([a-z][a-z ]*?)"
SERIAL_RESULT = re.compile(r"^Test Case '([^']*)' " + RESULT_WORDS + r" \(" + SECONDS + r" seconds\)\.$")
SERIAL_START = re.compile(r"^Test Case '([^']*)' started\.$")
SERIAL_SUITE_START = re.compile(r"^Test Suite '([^']*)' started at [0-9-]+ [0-9:.]+\.$")
SERIAL_SUITE_END = re.compile(r"^Test Suite '([^']*)' (passed|failed) at [0-9-]+ [0-9:.]+\.$")
SERIAL_SUMMARY = re.compile(r"^\s*Executed ([0-9]+) tests?, with (?:([0-9]+) tests? skipped and )?"
                            r"([0-9]+) failures? \(([0-9]+) unexpected\) in " + SECONDS + r" \(" + SECONDS
                            + r"\) seconds$")
PARALLEL_RESULT = re.compile(r"^Test case '([^']*)' " + RESULT_WORDS + r" on '([^']*)' \(" + SECONDS
                             + r" seconds\)$")
PARALLEL_SUITE_START = re.compile(r"^Test suite '([^']*)' started on '([^']*)'$")
# A performance test's measurement line, e.g.
# ".../CharsetTests.swift:809: Test Case '-[...]' measured [Time, seconds] average: ..."
MEASURED = re.compile(r"^\S.*:[0-9]+: Test Case '[^']*' measured \[")
END_MARKER = re.compile(r"^\*\* (?:TEST|BUILD) [A-Z ]+ \*\*")
TEST_END_MARKER = re.compile(r"^\*\* TEST ")
TESTING_STARTED = 'Testing started'
RESTART = re.compile(r"^Restarting after unexpected exit, crash, or test timeout")
FAILING_HEADER = 'Failing tests:'
TOP_LEVEL_SUITES = ('All tests', 'Selected tests')

# Lines that look like test output. One that matches no known form is
# reported as unparsed rather than skipped.
LOOKS_LIKE_TEST = re.compile(r"Test (?:Case|case|Suite|suite) '")
LOOKS_LIKE_SUMMARY = re.compile(r"^\s*Executed ")
# Swift Testing (the @Test framework) prints lines such as
# "<symbol>  Test foo() passed after 0.001 seconds.", where the symbol is an
# SF Symbol (a private-use character) followed by two spaces, and headers
# such as "<symbol>  Testing Library Version: ..." and
# "<symbol>  Target Platform: ...". It is not supported.
LOOKS_LIKE_SWIFT_TESTING = re.compile(r"^[^\x00-\x7f]{1,2} +(?:Test|Suite|Target Platform)")

ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')

IDENT = r'[^\W\d]\w*'
OBJC_NAME = re.compile(r'^-\[(?:(' + IDENT + r')\.)?(' + IDENT + r') (' + IDENT + r')\]$')
SWIFT_NAME = re.compile(r'^(?:(' + IDENT + r')\.)?(' + IDENT + r')\.(' + IDENT + r')\(\)$')


class LogFormatError(Exception):
    pass


STATUSES = ('passed', 'failed', 'skipped')


def status_of(words):
    """The status of a result line's wording: passed, failed or skipped as
    printed; "recorded an expected failure" (every failure was expected,
    XCTExpectFailure) is passed; any other wording is "other", an executed
    test, so that a new wording cannot make a run look empty."""
    if words in STATUSES:
        return words
    if words == 'recorded an expected failure':
        return 'passed'
    return 'other'


def split_name(name):
    """(class, method) from a test name as xcodebuild prints it, or None."""
    m = OBJC_NAME.match(name) or SWIFT_NAME.match(name)
    if not m:
        return None
    return m.group(2), m.group(3)


def clean(raw):
    return ANSI.sub('', raw).rstrip('\r')


class Suite:
    def __init__(self, name, line):
        self.name = name
        self.line = line
        self.count = 0
        self.seconds = Decimal(0)
        self.end_line = None
        self.summary = None


class Launch:
    def __init__(self, index, suite):
        self.index = index
        self.suite = suite


class Parsed:
    def __init__(self):
        self.format = None
        self.results = []
        self.started_without_result = []
        self.results_without_start = []
        self.suites_without_results = []
        self.suites_skipped_by_list = []
        self.outside_suite = []
        self.unparsed = []
        self.restarts = []
        self.end_marker = None
        self.test_markers = []          # (line, text) of every "** TEST ... **" marker
        self.after_test_marker = []     # (line, text) of test output after the first of them
        self.last_output_line = 0       # line of the last result, test start or suite start
        self.testing_started = []       # lines of "Testing started"
        self.first_result_line = None
        self.launches_without_restart = []
        self.repeated_without_restart = []   # (test id, earlier line, line)
        self.launches = []
        self.suites = []
        self.failing_present = False
        self.failing_names = []


def parse_log(text, skipped_classes=frozenset()):
    """Parse a whole log. Raises LogFormatError if the format is not recognized.
    A suite with no results whose class is in skipped_classes (the classes of
    a --skip-list) is not counted as a suite without results."""
    lines = [clean(l) for l in text.split('\n')]
    serial_hits = sum(1 for l in lines if SERIAL_RESULT.match(l))
    parallel_hits = sum(1 for l in lines if PARALLEL_RESULT.match(l))
    if serial_hits and parallel_hits:
        raise LogFormatError('the log has both serial and parallel test-case result lines (%d and %d); '
                             'it is not one xcodebuild run' % (serial_hits, parallel_hits))
    p = Parsed()
    if serial_hits:
        p.format = 'serial'
    elif parallel_hits:
        p.format = 'parallel'
    else:
        raise LogFormatError('unrecognized log format: no xcodebuild test-case result lines '
                             "(\"Test Case '...' passed (N seconds).\" or "
                             "\"Test case '...' passed on '...' (N seconds)\")")

    stack = []
    pending = None          # serial: (test id, line) of the test started and not finished
    awaiting = None         # serial: the suite whose "Executed" line comes next
    dest_suite = {}         # parallel: destination -> [suite name, line, result count]
    in_failing = False
    restart_since_launch = False
    launched = False
    last_result = {}        # test id -> (line, number of restarts before it)

    def output(number, line):
        """Records a result, test start or suite start line."""
        p.last_output_line = number
        if p.test_markers:
            p.after_test_marker.append((number, line))

    def launch(number):
        """Records the start of a launch; a second one needs a restart before it."""
        nonlocal launched, restart_since_launch
        if launched and not restart_since_launch:
            p.launches_without_restart.append(number)
        launched = True
        restart_since_launch = False

    def result(tid, number):
        if p.first_result_line is None:
            p.first_result_line = number
        prev = last_result.get(tid)
        if prev is not None and prev[1] == len(p.restarts):
            p.repeated_without_restart.append((tid, prev[0], number))
        last_result[tid] = (number, len(p.restarts))

    for number, line in enumerate(lines, 1):
        if in_failing:
            if line.strip() == '':
                in_failing = False
                continue
            name = line.strip()
            parts = split_name(name) if line[:1].isspace() else None
            if parts is None:
                p.unparsed.append((number, line))
            else:
                p.failing_names.append('%s/%s' % parts)
            continue
        if line == FAILING_HEADER:
            p.failing_present = True
            in_failing = True
            continue
        if END_MARKER.match(line.strip()):
            p.end_marker = (number, line.strip())
            if TEST_END_MARKER.match(line.strip()):
                p.test_markers.append(p.end_marker)
            continue
        if RESTART.match(line):
            p.restarts.append(number)
            restart_since_launch = True
            stack = []
            awaiting = None
            continue
        if line == TESTING_STARTED:
            p.testing_started.append(number)
            if p.format == 'parallel':
                launch(number)
            continue

        if p.format == 'serial':
            m = SERIAL_RESULT.match(line)
            if m:
                parts = split_name(m.group(1))
                if parts is None:
                    p.unparsed.append((number, line))
                    continue
                awaiting = None
                tid = '%s/%s' % parts
                output(number, line)
                result(tid, number)
                if pending is None or pending[0] != tid:
                    if pending is not None:
                        p.started_without_result.append(pending)
                    p.results_without_start.append((tid, number))
                pending = None
                secs = Decimal(m.group(3))
                p.results.append(dict(test=tid, cls=parts[0], method=parts[1], status=status_of(m.group(2)),
                                      seconds=secs, line=number, destination=None))
                for s in stack:
                    s.count += 1
                    s.seconds += secs
                continue
            m = SERIAL_START.match(line)
            if m:
                parts = split_name(m.group(1))
                if parts is None:
                    p.unparsed.append((number, line))
                    continue
                awaiting = None
                output(number, line)
                if pending is not None:
                    p.started_without_result.append(pending)
                pending = ('%s/%s' % parts, number)
                continue
            m = SERIAL_SUITE_START.match(line)
            if m:
                awaiting = None
                output(number, line)
                name = m.group(1)
                if not stack or name in TOP_LEVEL_SUITES:
                    launch(number)
                    stack = []
                    suite = Suite(name, number)
                    p.launches.append(Launch(len(p.launches) + 1, suite))
                else:
                    suite = Suite(name, number)
                p.suites.append(suite)
                stack.append(suite)
                continue
            m = SERIAL_SUITE_END.match(line)
            if m:
                name = m.group(1)
                idx = None
                for i in range(len(stack) - 1, -1, -1):
                    if stack[i].name == name:
                        idx = i
                        break
                if idx is None:
                    p.unparsed.append((number, line))
                    awaiting = None
                    continue
                suite = stack[idx]
                del stack[idx:]
                suite.end_line = number
                awaiting = suite
                continue
            m = SERIAL_SUMMARY.match(line)
            if m and awaiting is not None:
                awaiting.summary = dict(tests=int(m.group(1)), skipped=int(m.group(2) or 0),
                                        failures=int(m.group(3)), seconds=Decimal(m.group(5)))
                awaiting = None
                continue
            if LOOKS_LIKE_SUMMARY.match(line) or LOOKS_LIKE_TEST.search(line) \
                    or LOOKS_LIKE_SWIFT_TESTING.match(line):
                if not MEASURED.match(line):
                    p.unparsed.append((number, line))
            continue

        # parallel
        m = PARALLEL_RESULT.match(line)
        if m:
            parts = split_name(m.group(1))
            if parts is None:
                p.unparsed.append((number, line))
                continue
            tid = '%s/%s' % parts
            dest = m.group(3)
            output(number, line)
            result(tid, number)
            p.results.append(dict(test=tid, cls=parts[0], method=parts[1], status=status_of(m.group(2)),
                                  seconds=Decimal(m.group(4)), line=number, destination=dest))
            cur = dest_suite.get(dest)
            if cur is None or cur[0] != parts[0]:
                p.outside_suite.append((tid, number))
            else:
                cur[2] += 1
            continue
        m = PARALLEL_SUITE_START.match(line)
        if m:
            output(number, line)
            dest = m.group(2)
            prev = dest_suite.get(dest)
            if prev is not None and prev[2] == 0:
                p.suites_without_results.append((prev[0], dest, prev[1]))
            dest_suite[dest] = [m.group(1), number, 0]
            continue
        if LOOKS_LIKE_SUMMARY.match(line) or LOOKS_LIKE_TEST.search(line) or LOOKS_LIKE_SWIFT_TESTING.match(line):
            if not MEASURED.match(line):
                p.unparsed.append((number, line))

    if pending is not None:
        p.started_without_result.append(pending)
    for dest in sorted(dest_suite, key=lambda d: dest_suite[d][1]):
        name, line, count = dest_suite[dest]
        if count == 0:
            p.suites_without_results.append((name, dest, line))
    p.suites_without_results.sort(key=lambda s: s[2])
    p.suites_skipped_by_list = sorted(set(s[0] for s in p.suites_without_results if s[0] in skipped_classes))
    p.suites_without_results = [s for s in p.suites_without_results if s[0] not in skipped_classes]
    if not p.results:
        raise LogFormatError('unrecognized log format: no test-case result line could be parsed')
    return p


def num(d):
    """A Decimal as a JSON number."""
    return float(d)


def row(r):
    return {'test': r['test'], 'class': r['cls'], 'method': r['method'], 'status': r['status'],
            'seconds': num(r['seconds']), 'line': r['line'], 'destination': r['destination']}


def build_report(p, path, threshold, top):
    results = p.results
    counts = {'total': len(results), 'passed': 0, 'failed': 0, 'skipped': 0, 'other': 0}
    for r in results:
        counts[r['status']] += 1
    total = sum((r['seconds'] for r in results), Decimal(0))

    by_class = {}
    for r in results:
        c = by_class.setdefault(r['cls'], [0, Decimal(0)])
        c[0] += 1
        c[1] += r['seconds']
    classes = [{'class': k, 'tests': v[0], 'seconds': num(v[1])} for k, v in sorted(by_class.items())]
    class_order = sorted(by_class.items(), key=lambda kv: (-kv[1][1], kv[0]))
    slowest_classes = [{'class': k, 'tests': v[0], 'seconds': num(v[1])} for k, v in class_order[:top]]

    ranked = sorted(results, key=lambda r: (-r['seconds'], r['test'], r['line']))
    over = [r for r in ranked if r['seconds'] >= threshold]

    per_test = {}
    for r in results:
        per_test[r['test']] = per_test.get(r['test'], 0) + 1
    repeated = [{'test': t, 'results': n} for t, n in sorted(per_test.items()) if n > 1]

    serial = p.format == 'serial'
    launches = []
    log_totals = []
    mismatches = []
    if serial:
        for launch in p.launches:
            s = launch.suite
            launches.append({'launch': launch.index, 'suite': s.name, 'line': s.line,
                             'summary': s.summary is not None})
            if s.summary is None:
                continue
            tolerance = Decimal('0.0005') * s.count
            diff = s.summary['seconds'] - s.seconds
            log_totals.append({
                'launch': launch.index, 'suite': s.name, 'line': s.end_line,
                'log_tests': s.summary['tests'], 'log_skipped': s.summary['skipped'],
                'log_failures': s.summary['failures'], 'log_seconds': num(s.summary['seconds']),
                'parsed_tests': s.count, 'parsed_seconds': num(s.seconds),
                'count_agrees': s.summary['tests'] == s.count,
                'seconds_difference': num(diff), 'tolerance': num(tolerance),
                'seconds_agree': abs(diff) <= tolerance,
            })
        top_level = set(id(l.suite) for l in p.launches)
        for s in p.suites:
            if id(s) in top_level or s.summary is None:
                continue
            if s.summary['tests'] != s.count:
                mismatches.append({'suite': s.name, 'line': s.end_line, 'log_tests': s.summary['tests'],
                                   'parsed_tests': s.count})
        mismatches.sort(key=lambda m: m['line'])

    if serial:
        last = p.launches[-1] if p.launches else None
        summary_ok = last is not None and last.suite.summary is not None
    else:
        summary_ok = True
    marker_ok = (p.end_marker is not None
                 and p.end_marker[1].startswith(('** TEST SUCCEEDED **', '** TEST FAILED **',
                                                 '** TEST EXECUTE SUCCEEDED **', '** TEST EXECUTE FAILED **'))
                 and p.last_output_line < p.end_marker[0])
    completed_summary = summary_ok and marker_ok
    missing_start = not serial and (not p.testing_started or p.testing_started[0] > p.first_result_line)

    failed_ids = set(r['test'] for r in results if r['status'] == 'failed')
    without_failed = []
    for n in p.failing_names:
        if n not in failed_ids and n not in without_failed:
            without_failed.append(n)

    reasons = []
    if not completed_summary:
        reasons.append('the log does not end with a completed-suite summary')
    if p.after_test_marker:
        first = p.after_test_marker[0]
        reasons.append('%d line(s) of test output follow the test end marker on line %d; the first is line %d: %s'
                       % (len(p.after_test_marker), p.test_markers[0][0], first[0], first[1]))
    if len(p.test_markers) > 1:
        reasons.append('the log has %d test end markers (lines %s); it holds more than one run'
                       % (len(p.test_markers), ', '.join(str(n) for n, _ in p.test_markers)))
    if p.launches_without_restart:
        reasons.append('%d test launch(es) begin with no restart line before them (first on line %d); '
                       'the log holds more than one run'
                       % (len(p.launches_without_restart), p.launches_without_restart[0]))
    if p.repeated_without_restart:
        t, a, b = p.repeated_without_restart[0]
        reasons.append('%d test(s) have more than one result with no restart between them (first: %s, lines %d and %d)'
                       % (len(set(r[0] for r in p.repeated_without_restart)), t, a, b))
    if missing_start:
        reasons.append("no 'Testing started' line before the first result (line %d); "
                       "the start of the log may be missing" % p.first_result_line)
    if p.started_without_result:
        reasons.append('%d test(s) started with no result (crashed or interrupted)' % len(p.started_without_result))
    if p.suites_without_results:
        reasons.append('%d suite(s) started with no test results (crashed, hung or interrupted)'
                       % len(p.suites_without_results))
    if p.restarts:
        reasons.append('the test runner restarted %d time(s) after a crash or timeout' % len(p.restarts))
    if p.unparsed:
        reasons.append('%d line(s) look like test output but could not be parsed' % len(p.unparsed))
    if p.results_without_start:
        reasons.append('%d result(s) without a matching start' % len(p.results_without_start))
    if p.outside_suite:
        reasons.append('%d result(s) outside the suite started on their destination' % len(p.outside_suite))
    if any(not (t['count_agrees'] and t['seconds_agree']) for t in log_totals):
        reasons.append("the log's own totals disagree with the parsed results")
    if mismatches:
        reasons.append('%d suite summaries disagree with the parsed results' % len(mismatches))
    if without_failed:
        reasons.append('%d test(s) listed under Failing tests have no failed result line' % len(without_failed))

    return {
        'log': path,
        'format': p.format,
        'complete': not reasons,
        'incomplete_reasons': reasons,
        'results': counts,
        'total_seconds': num(total),
        'threshold_seconds': num(threshold),
        'over_threshold': {'count': len(over), 'seconds': num(sum((r['seconds'] for r in over), Decimal(0))),
                           'tests': [row(r) for r in over]},
        'slowest_tests': [row(r) for r in ranked[:top]],
        'slowest_classes': slowest_classes,
        'tests': [row(r) for r in results],
        'classes': classes,
        'completed_summary': completed_summary,
        'end_marker': {'line': p.end_marker[0], 'text': p.end_marker[1]} if p.end_marker else None,
        'test_end_markers': [{'line': n, 'text': t} for n, t in p.test_markers],
        'output_after_end_marker': [{'line': n, 'text': t} for n, t in p.after_test_marker],
        'testing_started': list(p.testing_started),
        'launches_without_restart': list(p.launches_without_restart),
        'repeated_without_restart': [{'test': t, 'first_line': a, 'line': b}
                                     for t, a, b in p.repeated_without_restart],
        'started_without_result': ([{'test': t, 'line': n} for t, n in p.started_without_result]
                                   if serial else None),
        'results_without_start': [{'test': t, 'line': n} for t, n in p.results_without_start] if serial else None,
        'suites_started_without_results': (None if serial else
                                           [{'suite': s, 'destination': d, 'line': n}
                                            for s, d, n in p.suites_without_results]),
        'suites_skipped_by_list': list(p.suites_skipped_by_list),
        'results_outside_started_suite': None if serial else [{'test': t, 'line': n} for t, n in p.outside_suite],
        'unparsed_lines': [{'line': n, 'text': t} for n, t in p.unparsed],
        'restarts': list(p.restarts),
        'launches': launches,
        'log_totals': log_totals,
        'suite_mismatches': mismatches,
        'failing_list': {'present': p.failing_present, 'names': list(p.failing_names),
                         'without_failed_result': without_failed},
        'repeated_tests': repeated,
    }


def fmt(x):
    return '%.3f' % x


def test_row_text(r):
    return '%8.3f  %-7s  %s' % (r['seconds'], r['status'], r['test'])


def class_row_text(c):
    return '%8.3f  %5d  %s' % (c['seconds'], c['tests'], c['class'])


def render_text(rep, show_all):
    out = []
    w = out.append
    if not rep['complete']:
        w('WARNING: this report is incomplete.')
        for reason in rep['incomplete_reasons']:
            w('  - ' + reason)
        w('')
    w('Log: %s' % rep['log'])
    if rep['format'] == 'serial':
        w("Format: serial (\"Test Case '...' started.\" and \"Test Case '...' passed (N seconds).\" lines)")
    else:
        w("Format: parallel (\"Test case '...' passed on '<destination>' (N seconds)\" lines)")
    c = rep['results']
    w('Test-case results parsed: %d (passed %d, failed %d, skipped %d%s)'
      % (c['total'], c['passed'], c['failed'], c['skipped'], ', other %d' % c['other'] if c['other'] else ''))
    if rep['format'] == 'serial':
        w('Started with no result: %d' % len(rep['started_without_result']))
        for s in rep['started_without_result']:
            w('  line %d: %s' % (s['line'], s['test']))
        if rep['results_without_start']:
            w('Results with no matching start: %d' % len(rep['results_without_start']))
            for s in rep['results_without_start']:
                w('  line %d: %s' % (s['line'], s['test']))
    else:
        w('Started with no result: not determinable per test in a parallel log; '
          'suites started with no results: %d' % len(rep['suites_started_without_results']))
        for s in rep['suites_started_without_results']:
            w("  line %d: %s on '%s'" % (s['line'], s['suite'], s['destination']))
        if rep['results_outside_started_suite']:
            w('Results outside the suite started on their destination: %d'
              % len(rep['results_outside_started_suite']))
            for s in rep['results_outside_started_suite']:
                w('  line %d: %s' % (s['line'], s['test']))
    w('Lines that look like test output but could not be parsed: %d' % len(rep['unparsed_lines']))
    for u in rep['unparsed_lines']:
        w('  line %d: %s' % (u['line'], u['text']))
    w('Restarts after a crash or timeout: %d%s' % (
        len(rep['restarts']), (' (lines %s)' % ', '.join(str(n) for n in rep['restarts'])) if rep['restarts'] else ''))
    marker = rep['end_marker']
    if rep['completed_summary']:
        w('Completed-suite summary: yes (line %d: %s)' % (marker['line'], marker['text']))
    else:
        w('Completed-suite summary: no%s' % (' (last marker, line %d: %s)' % (marker['line'], marker['text'])
                                              if marker else ''))
    if rep['output_after_end_marker']:
        w('Test output after the test end marker: %d line(s)' % len(rep['output_after_end_marker']))
        for o in rep['output_after_end_marker'][:5]:
            w('  line %d: %s' % (o['line'], o['text']))
    if len(rep['test_end_markers']) > 1:
        w('Test end markers: %d (lines %s)' % (len(rep['test_end_markers']),
                                              ', '.join(str(m['line']) for m in rep['test_end_markers'])))
    if rep['launches_without_restart']:
        w('Launches with no restart line before them: %d (lines %s)'
          % (len(rep['launches_without_restart']), ', '.join(str(n) for n in rep['launches_without_restart'])))
    if rep['format'] == 'serial':
        totals = {t['launch']: t for t in rep['log_totals']}
        for launch in rep['launches']:
            t = totals.get(launch['launch'])
            if t is None:
                w("Log totals, launch %d ('%s', line %d): none (the launch ended without a summary)"
                  % (launch['launch'], launch['suite'], launch['line']))
                continue
            w("Log totals, launch %d ('%s', line %d): log %d tests in %s s; parsed %d tests in %s s; %s; "
              "time differs by %s s, %s of %.4f s (half a millisecond per test)"
              % (t['launch'], t['suite'], t['line'], t['log_tests'], fmt(t['log_seconds']), t['parsed_tests'],
                 fmt(t['parsed_seconds']), 'count agrees' if t['count_agrees'] else 'COUNT DIFFERS',
                 fmt(t['seconds_difference']),
                 'within the tolerance' if t['seconds_agree'] else 'OUTSIDE THE TOLERANCE', t['tolerance']))
        if rep['suite_mismatches']:
            w('Suite summaries that disagree: %d' % len(rep['suite_mismatches']))
            for s in rep['suite_mismatches']:
                w("  line %d: '%s' log %d tests, parsed %d" % (s['line'], s['suite'], s['log_tests'],
                                                              s['parsed_tests']))
    else:
        w('Log totals: none (a parallel log has no per-suite summaries)')
    fl = rep['failing_list']
    if fl['present']:
        w('Failing tests listed by xcodebuild: %d; with no failed result line: %d'
          % (len(fl['names']), len(fl['without_failed_result'])))
        for n in fl['without_failed_result']:
            w('  ' + n)
    if rep['repeated_tests']:
        w('Tests with more than one result: %d; repeated with no restart between: %d'
          % (len(rep['repeated_tests']), len(rep['repeated_without_restart'])))
        for t in rep['repeated_tests']:
            w('  %s (%d results)' % (t['test'], t['results']))
    w('')
    w('Total test time: %s s over %d results' % (fmt(rep['total_seconds']), c['total']))
    ov = rep['over_threshold']
    w('At or over %s s: %d tests, %s s' % (fmt(rep['threshold_seconds']), ov['count'], fmt(ov['seconds'])))
    for r in ov['tests']:
        w(test_row_text(r))
    w('')
    w('Slowest %d tests:' % len(rep['slowest_tests']))
    w(' seconds  status   test')
    for r in rep['slowest_tests']:
        w(test_row_text(r))
    w('')
    w('Slowest %d classes:' % len(rep['slowest_classes']))
    w(' seconds  tests  class')
    for cl in rep['slowest_classes']:
        w(class_row_text(cl))
    if show_all:
        w('')
        w('All tests (%d, in log order):' % len(rep['tests']))
        w(' seconds  status   test')
        for r in rep['tests']:
            w(test_row_text(r))
        w('')
        w('All classes (%d, by name):' % len(rep['classes']))
        w(' seconds  tests  class')
        for cl in rep['classes']:
            w(class_row_text(cl))
    return '\n'.join(out) + '\n'


def nonnegative_int(s):
    try:
        v = int(s)
    except ValueError:
        raise argparse.ArgumentTypeError('not an integer: %r' % s)
    if v < 0:
        raise argparse.ArgumentTypeError('must not be negative: %r' % s)
    return v


def nonnegative_seconds(s):
    try:
        v = Decimal(s)
    except Exception:
        raise argparse.ArgumentTypeError('not a number: %r' % s)
    if not v.is_finite() or v < 0:
        raise argparse.ArgumentTypeError('must be a non-negative number: %r' % s)
    return v


def read_skip_list_classes(path):
    """The classes a slow_tier.txt-style list names: the first word of each
    line that is not blank or a comment, up to a "/"."""
    classes = set()
    with open(path, 'r', encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if line and not line.startswith('#'):
                classes.add(line.split(None, 1)[0].split('/', 1)[0])
    return frozenset(classes)


def main(argv=None):
    ap = argparse.ArgumentParser(prog='test_timing.py',
                                 description='Per-test and per-class times from an xcodebuild test log.')
    ap.add_argument('log', help='the log file')
    ap.add_argument('--top', type=nonnegative_int, default=TOP_DEFAULT,
                    help='how many of the slowest tests and classes to list (default %d)' % TOP_DEFAULT)
    ap.add_argument('--threshold', type=nonnegative_seconds, default=THRESHOLD_DEFAULT,
                    help='list tests taking this many seconds or more (default 5)')
    ap.add_argument('--all', action='store_true', help='list every test and class in the text output')
    ap.add_argument('--json', action='store_true', help='JSON output')
    ap.add_argument('--fail-over', action='store_true',
                    help='exit 1 if any test is at or over the threshold, and exit 2 if the report is incomplete')
    ap.add_argument('--skip-list', metavar='FILE',
                    help='a list in the format of tools/swift_migration/slow_tier.txt; a suite with no results '
                         'whose class FILE names, whole or by one of its methods, is not a suite without results')
    args = ap.parse_args(argv)
    skipped_classes = frozenset()
    if args.skip_list:
        try:
            skipped_classes = read_skip_list_classes(args.skip_list)
        except OSError as e:
            print('test_timing.py: cannot read %s: %s' % (args.skip_list, e.strerror or e), file=sys.stderr)
            return 2
    try:
        with open(args.log, 'rb') as f:
            data = f.read()
    except OSError as e:
        print('test_timing.py: cannot read %s: %s' % (args.log, e.strerror or e), file=sys.stderr)
        return 2
    text = data.decode('utf-8', errors='replace')
    try:
        parsed = parse_log(text, skipped_classes)
    except LogFormatError as e:
        print('test_timing.py: %s: %s' % (args.log, e), file=sys.stderr)
        return 2
    rep = build_report(parsed, args.log, args.threshold, args.top)
    if args.json:
        sys.stdout.write(json.dumps(rep, indent=2, sort_keys=True) + '\n')
    else:
        sys.stdout.write(render_text(rep, args.all))
    if args.fail_over and not rep['complete']:
        print('test_timing.py: %s: the report is incomplete, so --fail-over cannot pass it' % args.log,
              file=sys.stderr)
        return 2
    if args.fail_over and rep['over_threshold']['count']:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
