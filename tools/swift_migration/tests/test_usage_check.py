"""Tests for tools/swift_migration/usage_check.py, the nightly usage check.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_usage_check.py'

fixtures/usage_check/real_2026-11-20.txt is the verbatim output of
`claude /usage 2>&1` on the build machine on 2026-11-20 (Claude Code
2.1.329). Every other input is written in the test, in the shapes that
Claude Code's own formatter produces: "<title>: <N>% used" followed by
" · resets <date>" when a reset time is known, where the date is
"Mon D at H[:MM]am|pm", with ", YYYY" after the day when the reset falls
in another year than the current one, and " (<IANA zone>)" at the end.

Every "now" is injected with --now, and every expected ceiling is worked
out by hand in the comment next to it. The ceiling is the number of local
midnights in [previous reset, now], divided by 7, where the previous reset
is the printed reset minus 168 hours.

Reference week, unless a test says otherwise: the reset is Saturday
2026-11-21 at 12pm in America/Los_Angeles, so the previous reset was
Saturday 2026-11-14 at 12pm. Nov 15 2026 is a Sunday.
"""

import io
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
TOOL = os.path.join(TOOL_DIR, 'usage_check.py')
FIXTURES = os.path.join(HERE, 'fixtures', 'usage_check')
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
sys.dont_write_bytecode = True

import usage_check as uc  # noqa: E402

LA = 'America/Los_Angeles'


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def wait_for(predicate, bound=60.0):
    end = time.monotonic() + bound
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


def week_line(used, reset):
    return 'Current week (all models): %s%% used · resets %s\n' % (used, reset)


def run_main(args, stdin_text=None):
    out = io.StringIO()
    err = io.StringIO()
    old_stdin = sys.stdin
    if stdin_text is not None:
        sys.stdin = io.StringIO(stdin_text)
    try:
        with redirect_stdout(out), redirect_stderr(err):
            code = uc.main(args)
    finally:
        sys.stdin = old_stdin
    return code, out.getvalue(), err.getvalue()


class TempFileMixin:
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='usage_check_test.')

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, name, text):
        path = os.path.join(self.tmp, name)
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(text)
        return path


class CheckTextTest(TempFileMixin, unittest.TestCase):
    """Drives main() with --file and --now, as the nightly script does."""

    def check(self, text, now, tz=LA):
        path = self.write('usage.txt', text)
        return run_main(['--file', path, '--now', now, '--tz', tz])

    def assertVerdict(self, text, now, code, used, midnights, tz=LA):
        got_code, out, err = self.check(text, now, tz)
        self.assertEqual(got_code, code, out + err)
        self.assertIn('used: %d%%' % used, out)
        self.assertIn('%d of 7 local midnights' % midnights, out)
        return out

    # Each night of the reference week at 1am, with 54% used.

    def test_sunday(self):
        # Midnights in [Sat 11-14 12pm, Sun 11-15 1am]: Nov 15. 1/7 = 14.3%.
        out = self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                                 '2026-11-15T01:00', 1, 54, 1)
        self.assertIn('ceiling: 14.3%', out)
        self.assertIn('verdict: at or over the ceiling', out)

    def test_monday(self):
        # Nov 15, 16. 2/7 = 28.6%.
        out = self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                                 '2026-11-16T01:00', 1, 54, 2)
        self.assertIn('ceiling: 28.6%', out)

    def test_tuesday(self):
        # Nov 15, 16, 17. 3/7 = 42.9%.
        out = self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                                 '2026-11-17T01:00', 1, 54, 3)
        self.assertIn('ceiling: 42.9%', out)

    def test_wednesday(self):
        # Nov 15 to 18. 4/7 = 57.1%, and 54 < 57.1.
        out = self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                                 '2026-11-18T01:00', 0, 54, 4)
        self.assertIn('ceiling: 57.1%', out)
        self.assertIn('verdict: may start another agent', out)

    def test_thursday(self):
        # Nov 15 to 19. 5/7 = 71.4%.
        out = self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                                 '2026-11-19T01:00', 0, 54, 5)
        self.assertIn('ceiling: 71.4%', out)

    def test_friday(self):
        # Nov 15 to 20. 6/7 = 85.7%. This is the real reading of 2026-11-20.
        out = self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                                 '2026-11-20T01:00', 0, 54, 6)
        self.assertIn('ceiling: 85.7%', out)

    def test_saturday_before_the_reset(self):
        # Nov 15 to 21: the reset day itself, at 11:59am, before the reset.
        # 7/7 = 100%.
        out = self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                                 '2026-11-21T11:59', 0, 54, 7)
        self.assertIn('ceiling: 100.0%', out)

    def test_saturday_after_the_reset(self):
        # Sat 11-14 at 11pm, after that day's noon reset: the next reset is
        # Nov 21, the previous one was 11 hours ago, and no midnight has
        # passed since. 0/7 = 0%, so even 0% used is at the ceiling.
        self.assertVerdict(week_line(0, 'Nov 21 at 12pm (%s)' % LA),
                           '2026-11-14T23:00', 1, 0, 0)

    def test_reset_day_after_the_reset_hour_with_stale_output(self):
        # At 12:30pm on the reset day, output that still names the reset
        # that has just passed describes the week that ended. It cannot be
        # trusted, so the answer is "could not determine".
        code, out, err = self.check(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                                    '2026-11-21T12:30')
        self.assertEqual(code, 2, out + err)
        self.assertIn('verdict: could not determine', out)

    def test_reset_day_after_the_reset_hour_with_new_week(self):
        # 12:30pm on Sat 11-21, output already naming Nov 28: the previous
        # reset was 30 minutes ago; no midnight since. 0/7.
        self.assertVerdict(week_line(1, 'Nov 28 at 12pm (%s)' % LA),
                           '2026-11-21T12:30', 1, 1, 0)

    def test_exactly_at_the_ceiling_is_over(self):
        # Wednesday: ceiling 4/7 = 57.14%. 57 < 57.14 may start; 58 may not.
        self.assertVerdict(week_line(57, 'Nov 21 at 12pm (%s)' % LA),
                           '2026-11-18T03:00', 0, 57, 4)
        self.assertVerdict(week_line(58, 'Nov 21 at 12pm (%s)' % LA),
                           '2026-11-18T03:00', 1, 58, 4)
        # Saturday: 7/7 = 100%, and 100% used is at the ceiling.
        self.assertVerdict(week_line(100, 'Nov 21 at 12pm (%s)' % LA),
                           '2026-11-21T02:00', 1, 100, 7)

    def test_midnight_itself_counts(self):
        # At exactly 00:00 on Wednesday 11-18 that midnight has started the
        # night: Nov 15 to 18. 4/7.
        self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                           '2026-11-18T00:00', 0, 54, 4)
        # One minute earlier it has not: Nov 15 to 17. 3/7.
        self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                           '2026-11-17T23:59', 1, 54, 3)

    # Forms of the reset time.

    def test_twelve_am(self):
        # Reset Sunday 11-22 at 12am. The previous reset was Sunday 11-15 at
        # 00:00, which is itself a midnight; it counts, so the first night
        # after the reset is 1/7 and the last (Saturday) is 7/7.
        self.assertVerdict(week_line(5, 'Nov 22 at 12am (%s)' % LA),
                           '2026-11-15T00:30', 0, 5, 1)
        self.assertVerdict(week_line(90, 'Nov 22 at 12am (%s)' % LA),
                           '2026-11-21T23:00', 0, 90, 7)

    def test_minutes_in_the_time(self):
        # Reset Sat 11-21 at 12:30pm; previous reset Sat 11-14 at 12:30pm.
        # At 12:45pm on 11-14, no midnight yet: 0/7.
        self.assertVerdict(week_line(0, 'Nov 21 at 12:30pm (%s)' % LA),
                           '2026-11-14T12:45', 1, 0, 0)
        # At 1am Sunday 11-15: 1/7.
        self.assertVerdict(week_line(10, 'Nov 21 at 12:30pm (%s)' % LA),
                           '2026-11-15T01:00', 0, 10, 1)

    def test_pm_hour_other_than_twelve(self):
        # Reset Fri 11-20 at 5pm; previous Fri 11-13 at 5pm. At 2am Mon
        # 11-16: Nov 14, 15, 16. 3/7.
        self.assertVerdict(week_line(40, 'Nov 20 at 5pm (%s)' % LA),
                           '2026-11-16T02:00', 0, 40, 3)

    def test_year_printed(self):
        # Claude Code prints the year when the reset is in another year than
        # now. Reset Sat 2027-01-02 at 12pm; previous Sat 2026-12-26 at
        # 12pm. At 1am Thu 2026-12-31: Dec 27 to 31. 5/7 = 71.4%.
        out = self.assertVerdict(
            week_line(60, 'Jan 2, 2027 at 12pm (%s)' % LA),
            '2026-12-31T01:00', 0, 60, 5)
        self.assertIn('ceiling: 71.4%', out)

    def test_year_boundary_without_year(self):
        # The same reset without the year: it is inferred as the next
        # occurrence. At 00:00 Fri 2027-01-01: Dec 27 to Jan 1. 6/7.
        self.assertVerdict(week_line(60, 'Jan 2 at 12pm (%s)' % LA),
                           '2027-01-01T00:00', 0, 60, 6)
        # And from the other side, at 3am Sat 2027-01-02, before the
        # reset: Dec 27 to Jan 2. 7/7.
        self.assertVerdict(week_line(60, 'Jan 2 at 12pm (%s)' % LA),
                           '2027-01-02T03:00', 0, 60, 7)

    def test_year_boundary_previous_reset_in_old_year(self):
        # Reset Sat 2027-01-09; previous Sat 2027-01-02 at 12pm. Read on
        # Sun 2027-01-03 at 1am: Jan 3. 1/7. Nothing about the old year
        # leaks in.
        self.assertVerdict(week_line(3, 'Jan 9 at 12pm (%s)' % LA),
                           '2027-01-03T01:00', 0, 3, 1)

    def test_daylight_saving_ends_in_the_week(self):
        # US daylight saving ends Sun 2026-11-01 at 2am. Reset Sat 11-07 at
        # 12pm PST = 20:00 UTC; minus 168 hours is Sat 10-31 at 20:00 UTC =
        # 1pm PDT. Midnights after that: Nov 1 (Sunday) first.
        self.assertVerdict(week_line(10, 'Nov 7 at 12pm (%s)' % LA),
                           '2026-11-01T03:00', 0, 10, 1)
        # At 1am Sat 11-07: Nov 1 to 7. 7/7.
        self.assertVerdict(week_line(10, 'Nov 7 at 12pm (%s)' % LA),
                           '2026-11-07T01:00', 0, 10, 7)
        # At 12:30pm Sat 10-31 (PDT), before the previous reset at 1pm PDT,
        # the output would name Oct 31, not Nov 7: 168h + 30min is more
        # than a week ahead, which cannot be, so it is refused.
        code, out, err = self.check(week_line(10, 'Nov 7 at 12pm (%s)' % LA),
                                    '2026-10-31T12:30')
        self.assertEqual(code, 2, out + err)

    def test_daylight_saving_starts_in_the_week(self):
        # US daylight saving starts Sun 2027-03-14 at 2am. Reset Sat 03-20 at
        # 12pm PDT = 19:00 UTC; previous Sat 03-13 at 19:00 UTC = 11am PST.
        # At 3am PDT Sun 03-14: Mar 14. 1/7. At 1am Sat 03-20: Mar 14 to 20.
        self.assertVerdict(week_line(10, 'Mar 20 at 12pm (%s)' % LA),
                           '2027-03-14T03:00', 0, 10, 1)
        self.assertVerdict(week_line(10, 'Mar 20 at 12pm (%s)' % LA),
                           '2027-03-20T01:00', 0, 10, 7)

    def test_zone_where_midnight_does_not_exist(self):
        # America/Santiago moved its clocks from 00:00 to 01:00 on Sun
        # 2026-09-06, so that day has no 00:00; its first instant (01:00)
        # is its midnight. Reset Sat 09-12 at 12pm; previous Sat 09-05 at
        # 12pm. At 02:00 Sun 09-06: Sep 6. 1/7.
        self.assertVerdict(
            week_line(1, 'Sep 12 at 12pm (America/Santiago)'),
            '2026-09-06T02:00', 0, 1, 1, tz='America/Santiago')

    def test_missing_zone_uses_the_local_zone(self):
        # No "(zone)": the reset is read in the --tz zone, and the output
        # says so. Same as test_thursday.
        out = self.assertVerdict(week_line(54, 'Nov 21 at 12pm'),
                                 '2026-11-19T01:00', 0, 54, 5)
        self.assertIn('no zone', out)

    def test_zone_on_the_line_differs_from_local(self):
        # Reset printed in UTC: Sat 11-21 at 8pm UTC = 12pm PST. Midnights
        # are counted in the local zone (Los Angeles). Thu 11-19 at 1am
        # PST: Nov 15 to 19. 5/7.
        self.assertVerdict(week_line(54, 'Nov 21 at 8pm (UTC)'),
                           '2026-11-19T01:00', 0, 54, 5)

    def test_narrow_no_break_space_and_capital_meridiem(self):
        self.assertVerdict(week_line(54, 'Nov 21 at 12 PM (%s)' % LA),
                           '2026-11-19T01:00', 0, 54, 5)

    def test_comma_form_without_at(self):
        # Older ICU data prints "Nov 21, 12pm" instead of "Nov 21 at 12pm".
        self.assertVerdict(week_line(54, 'Nov 21, 12pm (%s)' % LA),
                           '2026-11-19T01:00', 0, 54, 5)
        self.assertVerdict(week_line(60, 'Jan 2, 2027, 12pm (%s)' % LA),
                           '2026-12-31T01:00', 0, 60, 5)

    def test_now_with_offset(self):
        # --now with an explicit offset: 09:00 UTC on Thu 11-19 is 1am PST.
        self.assertVerdict(week_line(54, 'Nov 21 at 12pm (%s)' % LA),
                           '2026-11-19T09:00+00:00', 0, 54, 5)

    def test_ansi_escapes_are_ignored(self):
        text = ('\x1b[1mCurrent week (all models)\x1b[0m: 54% used '
                + '· resets Nov 21 at 12pm (%s)\n' % LA)
        self.assertVerdict(text, '2026-11-19T01:00', 0, 54, 5)

    # Shapes that must never be read as permission.

    def assertUnknown(self, text, now='2026-11-19T01:00'):
        code, out, err = self.check(text, now)
        self.assertEqual(code, 2, out + err)
        self.assertIn('verdict: could not determine', out)
        return out

    def test_empty_output(self):
        self.assertUnknown('')

    def test_no_all_models_line(self):
        self.assertUnknown('You are currently using your subscription\n\n'
                           + 'Current week (Fable): 15% used · resets '
                           + 'Nov 21 at 12pm (%s)\n' % LA)

    def test_line_without_reset(self):
        # Claude Code omits " · resets ..." when it has no reset time. The
        # ceiling cannot be computed without it.
        self.assertUnknown('Current week (all models): 20% used\n')

    def test_time_only_reset(self):
        self.assertUnknown(week_line(20, '3pm (%s)' % LA))

    def test_unknown_zone(self):
        self.assertUnknown(week_line(20, 'Nov 21 at 12pm (Mars/Olympus_Mons)'))

    def test_bad_month(self):
        self.assertUnknown(week_line(20, 'Foo 21 at 12pm (%s)' % LA))

    def test_bad_hour(self):
        self.assertUnknown(week_line(20, 'Nov 21 at 13pm (%s)' % LA))

    def test_impossible_date(self):
        self.assertUnknown(week_line(20, 'Feb 30 at 12pm (%s)' % LA))

    def test_two_different_all_models_lines(self):
        self.assertUnknown(week_line(20, 'Nov 21 at 12pm (%s)' % LA)
                           + week_line(30, 'Nov 21 at 12pm (%s)' % LA))

    def test_identical_repeated_line_is_fine(self):
        line = week_line(20, 'Nov 21 at 12pm (%s)' % LA)
        self.assertVerdict(line + line, '2026-11-19T01:00', 0, 20, 5)

    def test_reset_more_than_a_week_ahead(self):
        # Sun 11-15 at 1am, reset named as Sat 11-28: 13 days ahead.
        self.assertUnknown(week_line(20, 'Nov 28 at 12pm (%s)' % LA),
                           now='2026-11-15T01:00')

    def test_error_text(self):
        self.assertUnknown('Error: failed to fetch usage\n')

    def test_error_line_with_a_valid_line(self):
        # Output that reports an error is not trusted even when it also
        # carries an "all models" line, which may be stale or partial.
        good = week_line(20, 'Nov 21 at 12pm (%s)' % LA)
        for bad in ('Error: failed to refresh usage\n',
                    'error: request timed out\n',
                    '  ERROR fetching limits\n',
                    'fatal: cannot read credentials\n',
                    'Request failed with exit code 1\n',
                    'process exited with status 2\n'):
            out = self.assertUnknown(good + bad)
            self.assertIn('error', out.lower())
            self.assertUnknown(bad + good)

    def test_words_that_are_not_errors(self):
        # The fixture's advice lines and ordinary words must not trip it.
        line = week_line(20, 'Nov 21 at 12pm (%s)' % LA)
        self.assertVerdict(line + 'No errors in the last 24h\n'
                           + 'exit code 0\n', '2026-11-19T01:00', 0, 20, 5)

    def test_api_key_output(self):
        self.assertUnknown('You are currently using an API key. /usage shows '
                           'subscription limits only.\n')

    def test_missing_file(self):
        code, out, err = run_main(['--file', os.path.join(self.tmp, 'nope'),
                                   '--now', '2026-11-19T01:00', '--tz', LA])
        self.assertEqual(code, 2)
        self.assertIn('verdict: could not determine', out)

    def test_bad_now(self):
        path = self.write('u.txt', week_line(20, 'Nov 21 at 12pm (%s)' % LA))
        code, out, err = run_main(['--file', path, '--now', 'yesterday',
                                   '--tz', LA])
        self.assertEqual(code, 2)

    def test_bad_tz(self):
        path = self.write('u.txt', week_line(20, 'Nov 21 at 12pm (%s)' % LA))
        code, out, err = run_main(['--file', path, '--now', '2026-11-19T01:00',
                                   '--tz', 'Nowhere/Nothing'])
        self.assertEqual(code, 2)


class RealFixtureTest(unittest.TestCase):
    def test_real_output_of_2026_11_20(self):
        # 54% used, resets Sat Nov 21 at 12pm. Read on Fri 11-20 at 1am:
        # Nov 15 to 20, 6/7 = 85.7%; 54 < 85.7.
        path = os.path.join(FIXTURES, 'real_2026-11-20.txt')
        code, out, err = run_main(['--file', path, '--now', '2026-11-20T01:00',
                                   '--tz', LA])
        self.assertEqual(code, 0, out + err)
        self.assertIn('used: 54%', out)
        self.assertIn('ceiling: 85.7%', out)
        self.assertIn('6 of 7 local midnights', out)

    def test_fable_line_is_ignored(self):
        # The fixture's Fable line (33%) must not be taken for the all
        # models line.
        with open(os.path.join(FIXTURES, 'real_2026-11-20.txt'),
                  encoding='utf-8') as fh:
            reading = uc.parse_usage(fh.read())
        self.assertEqual(reading.used_percent, 54)


class StdinTest(unittest.TestCase):
    def test_reads_stdin_by_default(self):
        code, out, err = run_main(
            ['--now', '2026-11-19T01:00', '--tz', LA],
            stdin_text=week_line(54, 'Nov 21 at 12pm (%s)' % LA))
        self.assertEqual(code, 0, out + err)
        self.assertIn('5 of 7 local midnights', out)


class RunCommandTest(TempFileMixin, unittest.TestCase):
    """--run starts the command itself. A stub stands in for claude."""

    def stub(self, body):
        path = os.path.join(self.tmp, 'claude')
        with open(path, 'w') as fh:
            fh.write('#!/bin/sh\n' + body)
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        return path

    def test_run_success_records_arguments_and_drops_api_key(self):
        record = os.path.join(self.tmp, 'args')
        stub = self.stub('echo "$@" > %s\n'
                         'echo "key=${ANTHROPIC_API_KEY-unset}" >> %s\n'
                         "printf 'Current week (all models): 54%%%% used "
                         "\\302\\267 resets Nov 21 at 12pm (%s)\\n'\n"
                         % (record, record, LA))
        old = os.environ.get('ANTHROPIC_API_KEY')
        os.environ['ANTHROPIC_API_KEY'] = 'should-not-reach-claude'
        try:
            code, out, err = run_main(['--run', '--claude', stub, '--now',
                                       '2026-11-19T01:00', '--tz', LA])
        finally:
            if old is None:
                del os.environ['ANTHROPIC_API_KEY']
            else:
                os.environ['ANTHROPIC_API_KEY'] = old
        self.assertEqual(code, 0, out + err)
        with open(record) as fh:
            self.assertEqual(fh.read(), '/usage\nkey=unset\n')

    def test_run_command_fails(self):
        stub = self.stub('echo "Current week (all models): 1% used"\nexit 3\n')
        code, out, err = run_main(['--run', '--claude', stub, '--now',
                                   '2026-11-19T01:00', '--tz', LA])
        self.assertEqual(code, 2)
        self.assertIn('exit status 3', out)

    def test_run_command_times_out(self):
        # The stub never finishes on its own; the check must give up after
        # its timeout and kill it. A pass does not depend on speed: a slow
        # machine only makes the stub later still.
        pidfile = os.path.join(self.tmp, 'pid')
        stub = self.stub('echo $$ > %s\nexec sleep 600\n' % pidfile)
        code, out, err = run_main(['--run', '--claude', stub, '--timeout',
                                   '1', '--now', '2026-11-19T01:00', '--tz',
                                   LA])
        self.assertEqual(code, 2)
        self.assertIn('timed out', out)
        with open(pidfile) as fh:
            pid = int(fh.read())
        # The killed process must be gone (reaped), not left running.
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_sigterm_kills_the_usage_child_at_once(self):
        # launchctl kill SIGTERM during the check must not leave `claude
        # /usage` running for the rest of its timeout.
        pidfile = os.path.join(self.tmp, 'pid')
        stub = self.stub('echo $$ > %s\nexec sleep 600\n' % pidfile)
        proc = subprocess.Popen([sys.executable, '-B', TOOL, '--run',
                                 '--claude', stub, '--timeout', '600',
                                 '--now', '2026-11-19T01:00', '--tz', LA],
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT,
                                universal_newlines=True)
        try:
            self.assertTrue(wait_for(lambda: os.path.exists(pidfile)
                                     and os.path.getsize(pidfile) > 0))
            with open(pidfile) as fh:
                pid = int(fh.read())
            started = time.monotonic()
            proc.terminate()
            out, _ = proc.communicate(timeout=120)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()
        self.assertEqual(proc.returncode, 2, out)
        self.assertIn('signal', out)
        self.assertTrue(wait_for(lambda: not alive(pid)), 'child %d left' % pid)
        # Far less than the 600-second timeout.
        self.assertLess(time.monotonic() - started, 60)

    def test_run_command_missing(self):
        code, out, err = run_main(['--run', '--claude',
                                   os.path.join(self.tmp, 'no-such-claude'),
                                   '--now', '2026-11-19T01:00', '--tz', LA])
        self.assertEqual(code, 2)


class ScriptEntryTest(unittest.TestCase):
    def test_runs_as_a_script(self):
        path = os.path.join(FIXTURES, 'real_2026-11-20.txt')
        proc = subprocess.run([sys.executable, '-B', TOOL, '--file', path,
                               '--now', '2026-11-20T01:00', '--tz', LA],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn('ceiling: 85.7%', proc.stdout)


if __name__ == '__main__':
    unittest.main()
