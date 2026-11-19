#!/usr/bin/env python3
"""Decide whether the nightly migration run may start another agent.

Part of the Objective-C to Swift migration tooling. Python 3 standard
library only (3.9 or later, for zoneinfo).

The rule, from docs/swift-migration/workflow.md section 4:

    "They stop when the owner's weekly Claude Code usage reaches the
    fraction of the week that the night represents. The quota resets on
    Saturday at noon, so the first midnight after a reset is Sunday's"
    ... "In general the cap is the number of midnights since the last
    reset, divided by seven. If the reset time changes, the table follows
    it." ... "If usage is already at or above the night's cap at midnight,
    no work is done that night."

and docs/swift-migration/orchestration.md section 1, step 2:

    "run `claude /usage`, read the "all models" line, and compute tonight's
    cap from the reset time. If usage is at or above the cap, or the line
    does not parse, write the report (section 8) and stop."

workflow.md also says: "The orchestrator runs that command and reads the
percentage and the reset time from the "all models" line" and "if the line
is missing or does not parse, the orchestrator treats usage as unknown and
stops."

How this script applies it:

- The input is the text of `claude /usage`. Only the line
  "Current week (all models): NN% used · resets <date>" is read. Lines for
  single models (Fable, Sonnet) and the session line are ignored.
- The printed reset is the next reset. The previous reset is 168 hours
  (one week) earlier, as an absolute instant, so a daylight saving change
  in the week moves its wall-clock time and nothing else.
- The ceiling is (local midnights in [previous reset, now]) / 7. "Local
  midnight" is the first instant of a calendar day in the local zone (on a
  day whose 00:00 is skipped by a clock change, the instant the day
  begins). A midnight at exactly "now" counts, since it starts the current
  night. A midnight at exactly the previous reset counts too, so that a
  reset at midnight still gives 1/7 on its first night and 7/7 on its last.
  The count is at most 7.
- "At or above": used * 7 >= midnights * 100, computed in integers, so 57%
  on a 4/7 night (57.14%) may start and 58% may not.
- Anything that cannot be read is exit status 2, never permission: no "all
  models" line, two that disagree, no reset time, a reset that is not in
  the future or is more than a week ahead, an unknown zone, a command that
  fails or times out, and output with a line that reports an error (a line
  that begins with "error" or "fatal", or that mentions a non-zero exit
  code or status), even when an "all models" line is also present.
- SIGTERM, SIGINT or SIGHUP during --run kills the `claude /usage` process
  group at once and exits 2.

Exit status: 0 = may start another agent; 1 = at or over the ceiling;
2 = could not determine.

Usage:
    claude /usage 2>&1 | usage_check.py
    usage_check.py --file usage.txt
    usage_check.py --run [--timeout SECONDS] [--claude PATH]
Testing and replay:
    --now 2026-11-19T01:00     the current time (local, or with an offset)
    --tz America/Los_Angeles   the local zone (default: TZ, else /etc/localtime)

--run starts `claude /usage` itself, with ANTHROPIC_API_KEY removed from its
environment as the owner's shell does, stdin closed, in its own process
group, and kills that group if it has not finished within the timeout.
"""

import argparse
import datetime as dt
import os
import re
import signal
import subprocess
import sys
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

EXIT_PERMITTED = 0
EXIT_AT_CEILING = 1
EXIT_UNKNOWN = 2

WEEK = dt.timedelta(hours=168)

MONTHS = {name: i + 1 for i, name in enumerate(
    ['jan', 'feb', 'mar', 'apr', 'may', 'jun',
     'jul', 'aug', 'sep', 'oct', 'nov', 'dec'])}

ANSI_RE = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')

# "Current week (all models): 54% used · resets Nov 21 at 12pm (Zone)".
# Claude Code writes the middle dot as U+00B7.
LINE_RE = re.compile(
    r'^\s*Current week \(all models\):\s*(?P<used>\d+)%\s*used'
    r'(?P<rest>.*)$', re.MULTILINE)
# A line that reports an error: it begins with "error" or "fatal" (any
# case), or mentions a non-zero exit code or status.
ERROR_RE = re.compile(
    r'^\s*(?:error|fatal)\b|\bexit(?:ed)?\s+(?:with\s+)?(?:code|status)\s+'
    r'(?:[1-9]\d*|-\d+)', re.IGNORECASE | re.MULTILINE)
RESETS_RE = re.compile(r'^\s*·\s*resets\s+(?P<when>.+?)\s*$')

# "Nov 21 at 12pm", "Nov 21 at 12:30pm", "Jan 2, 2027 at 12pm",
# "Nov 21, 12pm", "Jan 2, 2027, 12pm", each optionally followed by
# " (America/Los_Angeles)". \s also matches U+202F, which ICU puts before
# AM and PM.
WHEN_RE = re.compile(
    r'^(?P<mon>[A-Za-z]{3})\s+(?P<day>\d{1,2})'
    r'(?:,\s*(?P<year>\d{4}))?'
    r'(?:\s+at\s+|,\s*)'
    r'(?P<hour>\d{1,2})(?::(?P<minute>\d{2}))?\s*(?P<ampm>[AaPp][Mm])'
    r'(?:\s*\((?P<zone>[^()]+)\))?$')


class UsageError(Exception):
    """The usage could not be determined."""


class Reading:
    def __init__(self, used_percent, month, day, year, hour, minute, zone):
        self.used_percent = used_percent
        self.month = month
        self.day = day
        self.year = year
        self.hour = hour
        self.minute = minute
        self.zone = zone


def parse_usage(text):
    """Return the Reading from the "all models" line, or raise UsageError."""
    text = ANSI_RE.sub('', text)
    error = ERROR_RE.search(text)
    if error:
        line_start = text.rfind('\n', 0, error.start()) + 1
        line_end = text.find('\n', error.start())
        line = text[line_start:line_end if line_end >= 0 else None].strip()
        raise UsageError('the output reports an error: %r' % line)
    matches = list(LINE_RE.finditer(text))
    if not matches:
        raise UsageError('no "Current week (all models)" line in the output')
    lines = {m.group(0).strip() for m in matches}
    if len(lines) > 1:
        raise UsageError('more than one different "all models" line: %s'
                         % ' | '.join(sorted(lines)))
    m = matches[0]
    used = int(m.group('used'))
    rest = RESETS_RE.match(m.group('rest'))
    if not rest:
        raise UsageError('the "all models" line has no reset time: %r'
                         % m.group(0).strip())
    when = WHEN_RE.match(rest.group('when'))
    if not when:
        raise UsageError('cannot read the reset time %r' % rest.group('when'))
    month = MONTHS.get(when.group('mon').lower())
    if month is None:
        raise UsageError('unknown month %r' % when.group('mon'))
    hour12 = int(when.group('hour'))
    if not 1 <= hour12 <= 12:
        raise UsageError('hour %d is not a 12-hour clock hour' % hour12)
    minute = int(when.group('minute') or 0)
    if minute > 59:
        raise UsageError('minute %d is out of range' % minute)
    pm = when.group('ampm').lower() == 'pm'
    hour = (hour12 % 12) + (12 if pm else 0)
    year = int(when.group('year')) if when.group('year') else None
    zone = when.group('zone').strip() if when.group('zone') else None
    return Reading(used, month, int(when.group('day')), year, hour, minute,
                   zone)


def load_zone(name):
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError) as e:
        raise UsageError('unknown time zone %r (%s)' % (name, e))


def local_zone_name():
    tz = os.environ.get('TZ')
    if tz:
        return tz.lstrip(':')
    try:
        target = os.path.realpath('/etc/localtime')
    except OSError:
        target = ''
    marker = 'zoneinfo/'
    if marker in target:
        return target.split(marker, 1)[1]
    raise UsageError('cannot find the local time zone; pass --tz')


def resolve_reset(reading, now, reset_zone):
    """The next reset as an aware datetime, choosing the year if absent."""
    years = [reading.year] if reading.year else [now.year - 1, now.year,
                                                 now.year + 1]
    candidates = []
    for year in years:
        try:
            naive = dt.datetime(year, reading.month, reading.day,
                                reading.hour, reading.minute)
        except ValueError as e:
            raise UsageError('impossible reset date: %s' % e)
        candidates.append(naive.replace(tzinfo=reset_zone))
    if reading.year:
        return candidates[0]
    # The printed reset is the next one, so it is the candidate nearest to
    # now. Whether it is acceptable is checked by the caller.
    return min(candidates, key=lambda c: abs(
        (c.astimezone(dt.timezone.utc) - now).total_seconds()))


def day_start(date, zone):
    """The first instant of a local calendar day.

    For a day whose 00:00 is skipped by a clock change, zoneinfo resolves
    the missing 00:00 with the offset in force before the change, which is
    the instant of the change: the day's real start."""
    return dt.datetime(date.year, date.month, date.day,
                       tzinfo=zone).astimezone(dt.timezone.utc)


def count_midnights(previous_reset, now, local):
    """Local midnights m with previous_reset <= m <= now, at most 7.

    previous_reset and now are in UTC."""
    first = previous_reset.astimezone(local).date()
    last = now.astimezone(local).date()
    count = 0
    date = first
    while date <= last:
        start = day_start(date, local)
        if previous_reset <= start <= now:
            count += 1
        date += dt.timedelta(days=1)
    return min(count, 7)


class Verdict:
    def __init__(self, used, midnights, previous_reset, next_reset, notes):
        self.used = used
        self.midnights = midnights
        self.previous_reset = previous_reset
        self.next_reset = next_reset
        self.notes = notes

    @property
    def ceiling_percent(self):
        return self.midnights * 100.0 / 7

    @property
    def permitted(self):
        return self.used * 7 < self.midnights * 100


def evaluate(text, now, local):
    reading = parse_usage(text)
    notes = []
    if reading.zone:
        reset_zone = load_zone(reading.zone)
    else:
        reset_zone = local
        notes.append('the reset time has no zone; read it in %s' % local.key)
    # Aware datetimes that share a tzinfo add, subtract and compare by wall
    # clock in Python, which is wrong across a clock change. Everything is
    # done in UTC and converted only for display.
    now = now.astimezone(dt.timezone.utc)
    next_reset = resolve_reset(reading, now, reset_zone).astimezone(
        dt.timezone.utc)
    if next_reset <= now:
        raise UsageError('the reset time %s is not after now (%s); the output '
                         'describes a week that has ended'
                         % (fmt(next_reset, local), fmt(now, local)))
    if next_reset - now > WEEK:
        raise UsageError('the reset time %s is more than a week after now '
                         '(%s)' % (fmt(next_reset, local), fmt(now, local)))
    previous_reset = next_reset - WEEK
    midnights = count_midnights(previous_reset, now, local)
    return Verdict(reading.used_percent, midnights, previous_reset,
                   next_reset, notes)


def fmt(when, zone):
    return when.astimezone(zone).strftime('%Y-%m-%d %H:%M %Z')


def parse_now(value, local):
    if value is None:
        return dt.datetime.now(dt.timezone.utc)
    try:
        parsed = dt.datetime.fromisoformat(value)
    except ValueError:
        raise UsageError('cannot read --now %r; use YYYY-MM-DDTHH:MM' % value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=local)
    return parsed


def run_claude(claude, timeout):
    env = dict(os.environ)
    env.pop('ANTHROPIC_API_KEY', None)
    try:
        proc = subprocess.Popen([claude, '/usage'], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, env=env,
                                start_new_session=True)
    except OSError as e:
        raise UsageError('cannot run %s: %s' % (claude, e))

    def stop(signum, frame):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        raise UsageError('received signal %d while `%s /usage` ran; killed it'
                         % (signum, claude))

    previous = {sig: signal.signal(sig, stop)
                for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
    try:
        return _finish(proc, claude, timeout)
    except UsageError:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            proc.wait()
        raise
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def _finish(proc, claude, timeout):
    try:
        out, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        proc.communicate()
        raise UsageError('`%s /usage` timed out after %s seconds'
                         % (claude, timeout))
    text = out.decode('utf-8', errors='replace')
    if proc.returncode != 0:
        tail = text.strip().splitlines()[-3:]
        raise UsageError('`%s /usage` failed with exit status %d: %s'
                         % (claude, proc.returncode, ' / '.join(tail)))
    return text


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Compare weekly Claude Code usage with tonight\'s ceiling.')
    source = parser.add_mutually_exclusive_group()
    source.add_argument('--file', help='read the /usage text from this file')
    source.add_argument('--run', action='store_true',
                        help='run `claude /usage` and read its output')
    parser.add_argument('--claude', default=os.environ.get('CLAUDE_BIN',
                                                           'claude'),
                        help='the claude executable for --run')
    parser.add_argument('--timeout', type=float, default=120,
                        help='seconds to wait for --run (default 120)')
    parser.add_argument('--now', help='the current time, for tests')
    parser.add_argument('--tz', help='the local time zone')
    args = parser.parse_args(argv)

    try:
        local = load_zone(args.tz or local_zone_name())
        now = parse_now(args.now, local)
        if args.run:
            text = run_claude(args.claude, args.timeout)
        elif args.file:
            try:
                with open(args.file, encoding='utf-8',
                          errors='replace') as fh:
                    text = fh.read()
            except OSError as e:
                raise UsageError('cannot read %s: %s' % (args.file, e))
        else:
            text = sys.stdin.read()
        verdict = evaluate(text, now, local)
    except UsageError as e:
        print('used: unknown')
        print('ceiling: unknown')
        print('reason: %s' % e)
        print('verdict: could not determine (exit %d)' % EXIT_UNKNOWN)
        return EXIT_UNKNOWN

    print('used: %d%%' % verdict.used)
    print('ceiling: %.1f%% (%d of 7 local midnights since the reset at %s; '
          'next reset %s)' % (verdict.ceiling_percent, verdict.midnights,
                              fmt(verdict.previous_reset, local),
                              fmt(verdict.next_reset, local)))
    for note in verdict.notes:
        print('note: %s' % note)
    if verdict.permitted:
        print('verdict: may start another agent (exit %d)' % EXIT_PERMITTED)
        return EXIT_PERMITTED
    print('verdict: at or over the ceiling (exit %d)' % EXIT_AT_CEILING)
    return EXIT_AT_CEILING


if __name__ == '__main__':
    sys.exit(main())
