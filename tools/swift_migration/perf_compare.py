#!/usr/bin/env python3
"""Compare a candidate performance result against a baseline.

Usage:
    python3 -B tools/swift_migration/perf_compare.py BASELINE.json CANDIDATE.json
        [--json] [--allow-non-baseline] [--allow-different-machine]

Both files are written by perf_baseline.py. For every scenario and metric in
either file it prints the baseline and candidate medians, the change in the
bad direction, the noise, the threshold, and a verdict:

    regression           worse by more than the threshold
    improvement          better by more than the threshold
    no change            within the threshold
    inconclusive         too few samples, or too noisy to tell
    informational        a metric with no usable signal; shown, never compared
    failed in candidate  the scenario failed (crashed, timed out, test failed)
                         in the candidate; the row carries its recorded reason
    missing in candidate the scenario ran but no longer reports this metric
    skipped in candidate the scenario was skipped, with its recorded reason
                         (app scenarios are skipped while any iTerm2 runs);
                         not comparable for that metric
    not run in candidate the candidate run did not select the scenario
    no reference result  the candidate has results but the reference skipped,
                         failed or did not run the scenario
    missing in baseline  the reference scenario ran but lacks this metric

Every scenario named in either file gets at least one row. A scenario with
no metrics to list gets one row with metric "*". "failed in candidate"
applies whatever the reference holds; when the reference failed too the note
says "also failed in reference", so a before and after with the same failure
does not read as clean. Any status other than ok or skipped counts as failed.

THE RULE IS A PROPOSAL. performance.md section 1 says "a regression beyond
noise blocks the commit" without saying what noise is. Until the owner
decides, this script uses:

    noise      = the larger of the two runs' robust relative spread,
                 1.4826 * MAD / median, in percent (an estimate of the
                 standard deviation that one outlier cannot inflate)
    threshold  = max(5%, 3 * noise)
    regression = the candidate median is worse than the baseline median by
                 more than the threshold
    inconclusive when either side has fewer than 5 samples or the noise is
                 above 10% (rerun on a quiet machine)

Refuses (exit 2) to compare against a result that is not labeled a baseline,
or across different configurations, architectures, or machines, unless told
to. Different Xcode or macOS versions are a warning. A candidate measured on
a busy machine is compared but flagged.

Exit status:
    0  no regression and no failure
    1  at least one regression, "failed in candidate" or "missing in
       candidate" row: each blocks like a regression
    2  not comparable as a whole, or bad input (takes precedence)
Skipped and not-run scenarios, and scenarios with no reference result, are
listed in warnings naming each one and do not change the exit status: they were not compared, so a caller that needs a
scenario must make sure it ran. Inconclusive rows do not change the exit
status either; the caller decides whether to rerun.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import perf_lib  # noqa: E402

MIN_THRESHOLD_PERCENT = 5.0
NOISE_MULTIPLIER = 3.0
MAX_NOISE_PERCENT = 10.0
MIN_SAMPLES = 5

RULE = ('PROPOSAL, not yet approved by the owner: regression when the candidate median is worse than the '
        'baseline median by more than max(%.0f%%, %.0f x noise), noise being the larger robust relative '
        'spread (1.4826 x MAD / median); inconclusive below %d samples or above %.0f%% noise.'
        % (MIN_THRESHOLD_PERCENT, NOISE_MULTIPLIER, MIN_SAMPLES, MAX_NOISE_PERCENT))

IDENTITY_KEYS = ('model', 'chip', 'logical_cpus', 'memory_bytes', 'os_build')
SOFTWARE_KEYS = ('xcode', 'os_version')


BLOCKING_VERDICTS = ('regression', 'failed in candidate', 'missing in candidate')


def _is_failure(entry):
    """A scenario entry that ran and did not succeed. Any status other than
    ok or skipped, including one this script does not know, is a failure."""
    return entry is not None and entry.get('status') not in ('ok', 'skipped')


def _candidate_absent(b_entry, c_entry):
    """Verdict and note for a candidate scenario that has no ok result."""
    if c_entry is None:
        return {'verdict': 'not run in candidate'}
    if c_entry.get('status') == 'skipped':
        return {'verdict': 'skipped in candidate', 'note': c_entry.get('reason') or ''}
    note = c_entry.get('reason') or ('status %s' % c_entry.get('status'))
    if _is_failure(b_entry):
        note += '; also failed in reference'
    return {'verdict': 'failed in candidate', 'note': note}


def _median(data):
    return perf_lib.summarize(data.get('samples') or []).get('median')


def _scenario_rows(name, b_entry, c_entry):
    """Rows for one scenario, whatever either file holds for it."""
    b_ok = b_entry is not None and b_entry.get('status') == 'ok'
    c_ok = c_entry is not None and c_entry.get('status') == 'ok'
    b_metrics = (b_entry.get('metrics') or {}) if b_ok else {}
    c_metrics = (c_entry.get('metrics') or {}) if c_ok else {}
    rows = []
    if not c_ok:
        absent = _candidate_absent(b_entry, c_entry)
        for metric in sorted(b_metrics) or ['*']:
            unit = b_metrics[metric].get('unit') if metric in b_metrics else None
            rows.append(dict(absent, scenario=name, metric=metric, unit=unit))
        return rows
    if not b_ok:
        if b_entry is None:
            note = 'the reference did not run this scenario'
        else:
            note = 'the reference %s: %s' % ('skipped it' if b_entry.get('status') == 'skipped' else 'failed',
                                             b_entry.get('reason') or b_entry.get('status'))
        for metric in sorted(c_metrics) or ['*']:
            data = c_metrics.get(metric, {})
            rows.append({'scenario': name, 'metric': metric, 'verdict': 'no reference result', 'note': note,
                         'unit': data.get('unit'), 'candidate_median': _median(data) if data else None})
        return rows
    for metric in sorted(set(b_metrics) | set(c_metrics)):
        if metric not in b_metrics:
            row = {'verdict': 'missing in baseline', 'unit': c_metrics[metric].get('unit')}
        elif metric not in c_metrics:
            row = {'verdict': 'missing in candidate', 'unit': b_metrics[metric].get('unit'),
                   'note': 'the scenario ran but did not report this metric'}
        elif b_metrics[metric].get('informational') or c_metrics[metric].get('informational'):
            row = {'verdict': 'informational', 'unit': b_metrics[metric].get('unit'),
                   'baseline_median': _median(b_metrics[metric]),
                   'candidate_median': _median(c_metrics[metric])}
        else:
            row = compare_metric(b_metrics[metric], c_metrics[metric])
        row.update(scenario=name, metric=metric)
        rows.append(row)
    return rows


def compare_metric(base, cand):
    b = perf_lib.summarize(base['samples'])
    c = perf_lib.summarize(cand['samples'])
    row = {'unit': base.get('unit'), 'better': base.get('better'),
           'baseline_median': b.get('median'), 'candidate_median': c.get('median'),
           'baseline_n': b['n'], 'candidate_n': c['n']}
    if b['n'] == 0 or c['n'] == 0 or not b['median']:
        row.update(verdict='inconclusive', note='no samples')
        return row
    sign = 1.0 if base.get('better') == 'lower' else -1.0
    worse = sign * 100.0 * (c['median'] - b['median']) / abs(b['median'])
    noise = max(b['robust_rel_spread_percent'], c['robust_rel_spread_percent'])
    threshold = max(MIN_THRESHOLD_PERCENT, NOISE_MULTIPLIER * noise)
    row.update(change_percent=worse, noise_percent=noise, threshold_percent=threshold)
    if min(b['n'], c['n']) < MIN_SAMPLES:
        row.update(verdict='inconclusive', note='fewer than %d samples' % MIN_SAMPLES)
    elif noise > MAX_NOISE_PERCENT:
        row.update(verdict='inconclusive', note='noise %.1f%% above %.0f%%' % (noise, MAX_NOISE_PERCENT))
    elif worse > threshold:
        row.update(verdict='regression')
    elif -worse > threshold:
        row.update(verdict='improvement')
    else:
        row.update(verdict='no change')
    return row


def compare(baseline, candidate, allow_non_baseline=False, allow_different_machine=False):
    problems = []
    warnings = []
    for name, result in (('baseline', baseline), ('candidate', candidate)):
        if result.get('schema') != perf_lib.SCHEMA:
            problems.append('%s has schema %r, expected %r' % (name, result.get('schema'), perf_lib.SCHEMA))
    if not baseline.get('is_baseline'):
        message = 'the reference result is not a baseline (%s)' % baseline.get('label')
        (warnings if allow_non_baseline else problems).append(message)
    for key in ('configuration', 'arch'):
        if baseline.get(key) != candidate.get(key):
            problems.append('%s differs: %r vs %r' % (key, baseline.get(key), candidate.get(key)))
    bm, cm = baseline.get('machine') or {}, candidate.get('machine') or {}
    differing = [k for k in IDENTITY_KEYS if bm.get(k) != cm.get(k)]
    if differing:
        message = 'machine differs in %s' % ', '.join(differing)
        (warnings if allow_different_machine else problems).append(message)
    for key in SOFTWARE_KEYS:
        if bm.get(key) != cm.get(key):
            warnings.append('%s differs: %r vs %r; a change may come from the toolchain or the OS'
                            % (key, bm.get(key), cm.get(key)))
    states = candidate.get('machine_state') or {}
    if not all((states.get(w) or {}).get('quiet') for w in ('before', 'after')):
        warnings.append('the candidate was measured on a busy machine; treat its numbers with suspicion')

    base_scenarios = baseline.get('scenarios') or {}
    cand_scenarios = candidate.get('scenarios') or {}
    rows = []
    for name in sorted(set(base_scenarios) | set(cand_scenarios)):
        rows.extend(_scenario_rows(name, base_scenarios.get(name), cand_scenarios.get(name)))

    uncompared = sorted({r['scenario'] for r in rows
                         if r['verdict'] in ('skipped in candidate', 'not run in candidate')})
    if uncompared:
        warnings.append('not compared, because the candidate skipped or did not run them: %s'
                        % ', '.join(uncompared))
    unreferenced = sorted({r['scenario'] for r in rows if r['verdict'] == 'no reference result'})
    if unreferenced:
        warnings.append('not compared, no reference result (the reference skipped, failed or did not run '
                        'them): %s' % ', '.join(unreferenced))

    if problems:
        exit_code = 2
    elif any(r['verdict'] in BLOCKING_VERDICTS for r in rows):
        exit_code = 1
    else:
        exit_code = 0
    return {'rule': RULE, 'problems': problems, 'warnings': warnings, 'rows': rows, 'exit_code': exit_code,
            'baseline_label': baseline.get('label'), 'candidate_label': candidate.get('label')}


def _fmt(value, digits=4):
    if value is None:
        return '-'
    return '%.*g' % (digits, value)


def render(report):
    lines = ['Rule: ' + report['rule'],
             'Baseline: %s' % report['baseline_label'],
             'Candidate: %s' % report['candidate_label']]
    for p in report['problems']:
        lines.append('NOT COMPARABLE: ' + p)
    for w in report['warnings']:
        lines.append('WARNING: ' + w)
    lines.append('')
    header = '%-44s %-24s %10s %10s %8s %7s %7s  %s' % ('scenario', 'metric', 'baseline', 'candidate',
                                                       'worse%', 'noise%', 'thresh%', 'verdict')
    lines.append(header)
    lines.append('-' * len(header))
    for r in report['rows']:
        lines.append('%-44s %-24s %10s %10s %8s %7s %7s  %s%s' % (
            r['scenario'], r['metric'], _fmt(r.get('baseline_median')), _fmt(r.get('candidate_median')),
            _fmt(r.get('change_percent'), 3), _fmt(r.get('noise_percent'), 2),
            _fmt(r.get('threshold_percent'), 2), r['verdict'],
            (' (%s)' % r['note']) if r.get('note') else ''))
    return '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('baseline')
    parser.add_argument('candidate')
    parser.add_argument('--json', action='store_true', help='print the report as JSON')
    parser.add_argument('--allow-non-baseline', action='store_true',
                        help='compare against a reference that is not labeled a baseline')
    parser.add_argument('--allow-different-machine', action='store_true',
                        help='compare results from machines that differ')
    args = parser.parse_args(argv)
    try:
        with open(args.baseline, encoding='utf-8') as f:
            baseline = json.load(f)
        with open(args.candidate, encoding='utf-8') as f:
            candidate = json.load(f)
    except (OSError, ValueError) as e:
        print('perf_compare: %s' % e, file=sys.stderr)
        return 2
    report = compare(baseline, candidate, allow_non_baseline=args.allow_non_baseline,
                     allow_different_machine=args.allow_different_machine)
    print(json.dumps(report, indent=1, sort_keys=True) if args.json else render(report))
    return report['exit_code']


if __name__ == '__main__':
    sys.exit(main())
