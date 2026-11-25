#!/usr/bin/env python3
"""Compare a candidate performance result against a baseline, or confirm a
suspected regression from runs of both versions made back to back.

Usage:
    python3 -B tools/swift_migration/perf_compare.py BASELINE.json CANDIDATE.json
        [--json] [--allow-non-baseline] [--allow-different-machine]
    python3 -B tools/swift_migration/perf_compare.py --confirm
        --base B1.json B2.json [...] --candidate C1.json C2.json [...] [--json]

Every file is written by perf_baseline.py. For every scenario and metric in
any file it prints the statistic compared (best or median), the reference
and candidate values of it, both medians, the change in the bad direction,
and a verdict:

    suspected regression worse by more than 5% in a comparison of one
                         candidate against one reference; not yet a
                         regression: confirm it with --confirm (below)
    confirmed regression (--confirm only) worse by more than 5%, pooled, and
                         worse in every candidate run than in every base run
    not confirmed        (--confirm only) worse by more than 5%, pooled, but
                         not in every run: some candidate run is as good as
                         some base run
    improvement          better by more than 5% (with --confirm, also better
                         in every run)
    no change            within 5%
    inconclusive         fewer than 5 samples, or no relative change can be
                         computed
    informational        a metric with no usable signal; shown, never compared
    not compared (unsteady)
                         a metric listed in perf_lib.UNSTEADY_METRICS, which
                         gives very different results on identical code; its
                         numbers are shown and named in a warning, and it is
                         never judged: not a pass, a failure or a suspicion
    failed in candidate  the scenario failed (crashed, timed out, test failed)
                         in the candidate (with --confirm, in any candidate
                         run); the row carries its recorded reason
    missing in candidate the scenario ran but no longer reports this metric
                         (with --confirm, in any candidate run)
    skipped in candidate the scenario was skipped, with its recorded reason
                         (app scenarios are skipped while an instance of the
                         checkout's own app runs); not comparable
    not run in candidate the candidate run did not select the scenario
    no reference result  the candidate has results but the reference skipped,
                         failed or did not run the scenario
    missing in baseline  the reference scenario ran but lacks this metric

Every scenario named in any file gets at least one row. A scenario with no
metrics to list gets one row with metric "*". "failed in candidate" applies
whatever the reference holds; when the reference failed too the note says
"also failed in reference", so a before and after with the same failure
does not read as clean. Any status other than ok or skipped counts as failed.

THE RULE, decided by the owner. The statistic a metric is judged on comes
from its unit, in perf_lib.statistic_for:

    best    time and rate units (s, ms, us, ns, iterations/s): the minimum
            when lower is better, the maximum when higher is better
            (2026-11-22: "Given the variance you should take the fastest
            time, since that's our best estimate.")
    median  everything else: memory (kB), counts, unknown units
            (2026-11-23: "That's fine").

The best is computed from the samples, so result files written before the
summary carried a 'best' key compare the same way.

The threshold is a flat 5% of the reference's statistic for every compared
metric, with no measure of variation (2026-11-23, offered "Compare best time
against best time; more than 5% slower means check it and triggers a
back-to-back run; only a slowdown that survives the back-to-back run
counts", the owner answered "Sure simplicity is good"). Exactly 5% is no
change. Fewer than 5 samples on either side (with --confirm, in any run) is
inconclusive ("Sure"); a metric is never inconclusive because its samples
vary ("Just pick the best value for timing"). The metrics listed in
perf_lib.UNSTEADY_METRICS are not compared; that list is the migration's
decision, open to the owner.

One comparison (BASELINE CANDIDATE) can only suspect a regression: a busy
machine slows the best sample too, and nothing within one run sees that.
The output then says how to confirm it. --confirm takes at least two result
files a side (three are recommended) from runs of the two versions made
alternately, back to back, in one lane with the same settings. Per metric
it pools each side's samples and judges the pooled statistic against the
same flat 5%. The regression is confirmed only if, besides, every candidate
run's statistic (each run's own best, or median) is worse than every base
run's. Otherwise it is "not confirmed". An improvement must hold run by run
too.

Refuses (exit 2) to compare against a result that is not labeled a baseline,
or across different configurations, architectures, or machines, unless told
to. Different Xcode or macOS versions are a warning. A candidate measured on
a busy machine is compared but flagged. --confirm needs no baseline label;
it refuses (exit 2) fewer than two files a side, a file named on both sides
or twice on one side (compared by real path), and runs that differ in schema, configuration, architecture, machine, or
iterations and app runs and durations, with no option to allow it. It warns
when the runs were made in different lanes, when every run of one side came
before every run of the other (not interleaved), when both sides record
the same commit and uncommitted paths, and names every run measured on a
busy machine.

Exit status:
    0  no suspected or confirmed regression, and no failure
    1  at least one "suspected regression" (one comparison) or "confirmed
       regression" (--confirm), or a "failed in candidate" or "missing in
       candidate" row: each blocks. A suspected regression blocks until a
       --confirm run with no warnings says "no change", "not confirmed" or
       "improvement" for it; an "inconclusive" confirmation does not clear
       it, and it is never a pass by itself
    2  not comparable as a whole, or bad input (takes precedence)
Skipped and not-run scenarios, and scenarios with no reference result, are
listed in warnings naming each one and do not change the exit status: they
were not compared, so a caller that needs a scenario must make sure it ran.
Inconclusive and "not confirmed" rows do not change the exit status either;
the caller decides whether to rerun. "not confirmed" rows are also named in
a warning. "not compared (unsteady)" rows never change the exit status and
are named in a warning: they were not judged, which is not the same as
fine.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import perf_lib  # noqa: E402

THRESHOLD_PERCENT = 5.0
# A change counts only beyond THRESHOLD_PERCENT + EPSILON_PERCENT: a change of
# exactly 5% computed in floating point can come out a hair above it
# (2.93073 * 1.05 against 2.93073 gives 5.00000000000001), and 1e-9 percent
# is far below anything the harness can measure.
EPSILON_PERCENT = 1e-9
MIN_SAMPLES = 5
MIN_CONFIRM_FILES = 2

UNSTEADY = 'not compared (unsteady)'

RULE = ('Decided by the owner. Time and rate metrics (units %s) compare the best sample (2026-11-22: "Given '
        'the variance you should take the fastest time, since that\'s our best estimate."; 2026-11-23: "Just '
        'pick the best value for timing"); memory, counts and other units compare the median (2026-11-23: '
        '"That\'s fine"). The threshold is a flat %.0f%% for every compared metric (2026-11-23: "Sure '
        'simplicity is good"): worse by more than %.0f%% in one comparison is only a suspected regression, '
        'which counts when perf_compare.py --confirm finds it again in runs of both versions made back to '
        'back. Inconclusive with fewer than %d samples on either side, never because samples are spread. '
        'Metrics in perf_lib.UNSTEADY_METRICS are recorded and shown but not compared: the migration\'s '
        'decision, open to the owner.'
        % (', '.join(sorted(perf_lib.BEST_SAMPLE_UNITS)), THRESHOLD_PERCENT, THRESHOLD_PERCENT, MIN_SAMPLES))

CONFIRM_RULE = ('Confirmation: each side\'s samples are pooled over its runs and the pooled statistic compared '
                'against the same flat %.0f%%. A regression is confirmed only if, besides, every candidate '
                'run\'s statistic is worse than every base run\'s; otherwise it is not confirmed. An '
                'improvement must hold run by run too. Inconclusive when any run has fewer than %d samples.'
                % (THRESHOLD_PERCENT, MIN_SAMPLES))

ADVICE = ('A suspected regression is not yet a regression: a busier machine than the reference\'s slows the '
          'best sample too. Confirm it back to back: in one lane, build and measure the two versions '
          'alternately, at least three times each (for example base, candidate, candidate, base, base, '
          'candidate), each with perf_baseline.py run --scenarios <the flagged scenarios> --output <its own '
          'file>, then run perf_compare.py --confirm --base <the base files> --candidate <the candidate files>. '
          'It counts only if that reports a confirmed regression.')

IDENTITY_KEYS = ('model', 'chip', 'logical_cpus', 'memory_bytes', 'os_build')
SOFTWARE_KEYS = ('xcode', 'os_version')


BLOCKING_VERDICTS = ('suspected regression', 'failed in candidate', 'missing in candidate')
CONFIRM_BLOCKING_VERDICTS = ('confirmed regression', 'failed in candidate', 'missing in candidate')
SETTINGS_KEYS = ('iterations', 'app_runs', 'app_duration_s')


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


def _scenario_rows(name, b_entry, c_entry, compare_fn):
    """Rows for one scenario, whatever either side holds for it."""
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
            row = compare_fn(b_metrics[metric], c_metrics[metric])
            unsteady = perf_lib.UNSTEADY_METRICS.get((name, metric))
            if unsteady:
                # The numbers stay; the verdict and its note do not.
                row.update(verdict=UNSTEADY, note='listed as unsteady since %s: %s'
                           % (unsteady['since'], unsteady['reason']))
        row.update(scenario=name, metric=metric)
        rows.append(row)
    return rows


def _beyond_threshold(percent):
    """True when `percent` exceeds the flat threshold, allowing for rounding."""
    return percent > THRESHOLD_PERCENT + EPSILON_PERCENT


def _percent_worse(better, value, reference):
    """How much worse `value` is than `reference`, in percent of the
    reference; negative when it is better."""
    sign = 1.0 if better == 'lower' else -1.0
    return sign * 100.0 * (value - reference) / abs(reference)


def _numbers(base, cand):
    """The row's statistic, bests, medians and sample counts, computed from
    the samples, never read from a stored summary, so that files written
    before the summary carried 'best' compare the same. Returns the row and
    the two summaries."""
    better = base.get('better')
    unit = base.get('unit')
    statistic = perf_lib.statistic_for(unit)
    b = perf_lib.summarize_metric(unit, better, base['samples'])
    c = perf_lib.summarize_metric(unit, better, cand['samples'])
    row = {'unit': unit, 'better': better, 'statistic': statistic,
           'baseline_median': b.get('median'), 'candidate_median': c.get('median'),
           'baseline_best': b.get('best'), 'candidate_best': c.get('best'),
           'baseline_n': b['n'], 'candidate_n': c['n']}
    return row, b, c


def compare_metric(base, cand):
    """One reference metric against one candidate metric."""
    row, b, c = _numbers(base, cand)
    statistic = row['statistic']
    if b['n'] == 0 or c['n'] == 0:
        row.update(verdict='inconclusive', note='no samples')
        return row
    if not b[statistic]:
        row.update(verdict='inconclusive', note='baseline %s is zero, so no relative change' % statistic)
        return row
    worse = _percent_worse(row['better'], c[statistic], b[statistic])
    row.update(change_percent=worse)
    if min(b['n'], c['n']) < MIN_SAMPLES:
        row.update(verdict='inconclusive', note='fewer than %d samples' % MIN_SAMPLES)
    elif _beyond_threshold(worse):
        row.update(verdict='suspected regression', note='confirm back to back with --confirm')
    elif _beyond_threshold(-worse):
        row.update(verdict='improvement')
    else:
        row.update(verdict='no change')
    return row


def _run_statistic(statistic, better, samples):
    if statistic == 'best':
        return perf_lib.best_sample(samples, better)
    return perf_lib.summarize(samples).get('median')


def compare_runs(base, cand):
    """One metric over several runs a side (--confirm). `base` and `cand`
    carry 'runs', one sample list per result file, and 'samples', all of
    them pooled."""
    row, b, c = _numbers(base, cand)
    statistic, better = row['statistic'], row['better']
    if any(not run for run in base['runs'] + cand['runs']):
        row.update(verdict='inconclusive', note='no samples in a run')
        return row
    b_runs = [_run_statistic(statistic, better, run) for run in base['runs']]
    c_runs = [_run_statistic(statistic, better, run) for run in cand['runs']]
    row.update(baseline_runs=b_runs, candidate_runs=c_runs)
    if not b[statistic]:
        row.update(verdict='inconclusive', note='baseline %s is zero, so no relative change' % statistic)
        return row
    worse = _percent_worse(better, c[statistic], b[statistic])
    row.update(change_percent=worse)
    # Worse in every run: the best candidate run is worse than the worst base
    # run. Better in every run: the worst candidate run is better than the
    # best base run.
    if better == 'lower':
        worse_every_run = min(c_runs) > max(b_runs)
        better_every_run = max(c_runs) < min(b_runs)
    else:
        worse_every_run = max(c_runs) < min(b_runs)
        better_every_run = min(c_runs) > max(b_runs)
    if min(len(run) for run in base['runs'] + cand['runs']) < MIN_SAMPLES:
        row.update(verdict='inconclusive', note='fewer than %d samples in a run' % MIN_SAMPLES)
    elif _beyond_threshold(worse):
        if worse_every_run:
            row.update(verdict='confirmed regression')
        else:
            row.update(verdict='not confirmed',
                       note='worse pooled, but not run by run: a candidate run is as good as a base run')
    elif _beyond_threshold(-worse):
        if better_every_run:
            row.update(verdict='improvement')
        else:
            row.update(verdict='no change', note='better pooled, but not run by run')
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
        rows.extend(_scenario_rows(name, base_scenarios.get(name), cand_scenarios.get(name), compare_metric))
    _warn_uncompared(rows, warnings)
    suspected = sorted({'%s %s' % (r['scenario'], r['metric']) for r in rows
                        if r['verdict'] == 'suspected regression'})
    report = {'mode': 'single', 'rule': RULE, 'problems': problems, 'warnings': warnings, 'rows': rows,
              'exit_code': _exit_code(problems, rows, BLOCKING_VERDICTS),
              'baseline_label': baseline.get('label'), 'candidate_label': candidate.get('label')}
    if suspected:
        report['advice'] = ADVICE
        report['suspected'] = suspected
    return report


def _warn_uncompared(rows, warnings):
    unsteady = sorted({'%s %s' % (r['scenario'], r['metric']) for r in rows if r['verdict'] == UNSTEADY})
    if unsteady:
        warnings.append('%s, recorded and shown but not judged (perf_lib.UNSTEADY_METRICS, the migration\'s '
                        'decision, open to the owner): %s; "not compared" does not mean fine'
                        % (UNSTEADY, ', '.join(unsteady)))
    uncompared = sorted({r['scenario'] for r in rows
                         if r['verdict'] in ('skipped in candidate', 'not run in candidate')})
    if uncompared:
        warnings.append('not compared, because the candidate skipped or did not run them: %s'
                        % ', '.join(uncompared))
    unreferenced = sorted({r['scenario'] for r in rows if r['verdict'] == 'no reference result'})
    if unreferenced:
        warnings.append('not compared, no reference result (the reference skipped, failed or did not run '
                        'them): %s' % ', '.join(unreferenced))


def _exit_code(problems, rows, blocking):
    if problems:
        return 2
    if any(r['verdict'] in blocking for r in rows):
        return 1
    return 0


def merge_runs(results, name):
    """One scenario entry for several runs of one side: failed if any run
    failed, skipped if any skipped, absent if any did not run it, else ok
    with every metric that all runs report, each carrying 'runs' (one
    sample list per run) and 'samples' (pooled)."""
    entries = [(result.get('scenarios') or {}).get(name) for result in results]
    if all(e is None for e in entries):
        return None
    failed = [(i, e) for i, e in enumerate(entries) if _is_failure(e)]
    if failed:
        return {'status': 'failed', 'reason': '; '.join(
            'run %d: %s' % (i + 1, e.get('reason') or 'status %s' % e.get('status')) for i, e in failed)}
    skipped = [(i, e) for i, e in enumerate(entries) if e is not None and e.get('status') == 'skipped']
    if skipped:
        return {'status': 'skipped', 'reason': '; '.join(
            'run %d: %s' % (i + 1, e.get('reason') or 'skipped') for i, e in skipped)}
    if any(e is None for e in entries):
        return None
    per_run = [e.get('metrics') or {} for e in entries]
    metrics = {}
    for metric in set(per_run[0]).intersection(*per_run[1:]):
        datas = [m[metric] for m in per_run]
        runs = [list(d.get('samples') or []) for d in datas]
        metrics[metric] = {'unit': datas[0].get('unit'), 'better': datas[0].get('better'),
                           'informational': any(d.get('informational') for d in datas),
                           'runs': runs, 'samples': [x for run in runs for x in run]}
    return {'status': 'ok', 'metrics': metrics}


def _created(result):
    return (result.get('settings') or {}).get('created') or result.get('created')


def _tree(result):
    """What a result records of the tree it measured."""
    settings = result.get('settings') or {}
    return (result.get('commit'), tuple(sorted(settings.get('uncommitted_paths') or [])))


def compare_confirm(bases, candidates, base_names=None, candidate_names=None):
    """Several runs a side, made back to back on one machine (--confirm)."""
    problems = []
    warnings = []
    base_names = list(base_names or ['base run %d' % (i + 1) for i in range(len(bases))])
    candidate_names = list(candidate_names or ['candidate run %d' % (i + 1) for i in range(len(candidates))])
    report = {'mode': 'confirm', 'rule': RULE + ' ' + CONFIRM_RULE, 'problems': problems, 'warnings': warnings,
              'rows': [], 'base_files': base_names, 'candidate_files': candidate_names,
              'base_labels': [r.get('label') for r in bases],
              'candidate_labels': [r.get('label') for r in candidates]}
    if len(bases) < MIN_CONFIRM_FILES or len(candidates) < MIN_CONFIRM_FILES:
        problems.append('--confirm needs at least two result files a side, from runs of the two versions made '
                        'back to back (got %d base, %d candidate)' % (len(bases), len(candidates)))
    both = sorted(set(base_names) & set(candidate_names))
    if both:
        problems.append('named on both sides: %s' % ', '.join(both))
    for side, names in (('base', base_names), ('candidate', candidate_names)):
        repeated = sorted({n for n in names if names.count(n) > 1})
        if repeated:
            problems.append('named more than once on the %s side: %s' % (side, ', '.join(repeated)))
    everything = list(zip(base_names, bases)) + list(zip(candidate_names, candidates))
    if not everything:
        report['exit_code'] = 2
        return report
    first_name, first = everything[0]
    for name, result in everything:
        if result.get('schema') != perf_lib.SCHEMA:
            problems.append('%s has schema %r, expected %r' % (name, result.get('schema'), perf_lib.SCHEMA))
    for name, result in everything[1:]:
        for key in ('configuration', 'arch'):
            if result.get(key) != first.get(key):
                problems.append('%s differs: %r in %s vs %r in %s'
                                % (key, first.get(key), first_name, result.get(key), name))
        fm, m = first.get('machine') or {}, result.get('machine') or {}
        differing = [k for k in IDENTITY_KEYS if fm.get(k) != m.get(k)]
        if differing:
            problems.append('machine differs in %s between %s and %s; runs to confirm must be made on one '
                            'machine' % (', '.join(differing), first_name, name))
        fs, rs = first.get('settings') or {}, result.get('settings') or {}
        for key in SETTINGS_KEYS:
            if fs.get(key) != rs.get(key):
                problems.append('setting %s differs: %r in %s vs %r in %s'
                                % (key, fs.get(key), first_name, rs.get(key), name))
        for key in SOFTWARE_KEYS:
            if fm.get(key) != m.get(key):
                warnings.append('%s differs between %s and %s: %r vs %r'
                                % (key, first_name, name, fm.get(key), m.get(key)))
    busy = [name for name, r in everything
            if not all(((r.get('machine_state') or {}).get(w) or {}).get('quiet') for w in ('before', 'after'))]
    if busy:
        warnings.append('measured on a busy machine: %s; interleaved runs share the conditions, but a busy '
                        'moment in one run can still move it' % ', '.join(busy))
    lanes = sorted({str((r.get('settings') or {}).get('test_host_suite')) for _, r in everything})
    if len(lanes) > 1:
        warnings.append('the runs were made in different lanes or checkouts (%s); make them all in one lane'
                        % ', '.join(lanes))
    base_times = [_created(r) for r in bases]
    cand_times = [_created(r) for r in candidates]
    if bases and candidates and all(base_times + cand_times):
        if max(base_times) < min(cand_times) or max(cand_times) < min(base_times):
            warnings.append('the runs are not interleaved: every run of one side came before every run of the '
                            'other, so a drift of the machine over time reads as a change; alternate the two '
                            'versions')
    else:
        warnings.append('a result file records no start time, so whether the runs were interleaved is not known')
    base_trees = {_tree(r) for r in bases}
    cand_trees = {_tree(r) for r in candidates}
    if base_trees and base_trees == cand_trees and len(base_trees) == 1:
        warnings.append('both sides look like the same tree (the same commit and uncommitted paths); check that '
                        'the base and candidate files are of the two versions')
    for side, trees in (('base', base_trees), ('candidate', cand_trees)):
        if len(trees) > 1:
            warnings.append('the %s runs record more than one tree (commit or uncommitted paths)' % side)
    if problems:
        report['exit_code'] = 2
        return report

    names = set()
    for result in bases + candidates:
        names.update((result.get('scenarios') or {}).keys())
    rows = []
    for name in sorted(names):
        rows.extend(_scenario_rows(name, merge_runs(bases, name), merge_runs(candidates, name), compare_runs))
    _warn_uncompared(rows, warnings)
    unconfirmed = sorted({'%s %s' % (r['scenario'], r['metric']) for r in rows if r['verdict'] == 'not confirmed'})
    if unconfirmed:
        warnings.append('not confirmed (worse pooled, but not in every run): %s' % ', '.join(unconfirmed))
    report['rows'] = rows
    report['exit_code'] = _exit_code(problems, rows, CONFIRM_BLOCKING_VERDICTS)
    return report


def _fmt(value, digits=4):
    if value is None:
        return '-'
    return '%.*g' % (digits, value)


def render(report):
    lines = ['Rule: ' + report['rule']]
    if report.get('mode') == 'confirm':
        for side, files, labels in (('Base', report['base_files'], report['base_labels']),
                                    ('Candidate', report['candidate_files'], report['candidate_labels'])):
            for f, label in zip(files, labels):
                lines.append('%s run: %s (%s)' % (side, f, label))
    else:
        lines.append('Baseline: %s' % report['baseline_label'])
        lines.append('Candidate: %s' % report['candidate_label'])
    for p in report['problems']:
        lines.append('NOT COMPARABLE: ' + p)
    for w in report['warnings']:
        lines.append('WARNING: ' + w)
    lines.append('')
    # baseline and candidate are the compared statistic (stat); the two
    # median columns are always the medians.
    row_format = '%-44s %-24s %-6s %10s %10s %10s %10s %8s  %s%s'
    header = row_format % ('scenario', 'metric', 'stat', 'baseline', 'candidate', 'base med', 'cand med',
                           'worse%', 'verdict', '')
    lines.append(header)
    lines.append('-' * len(header))
    for r in report['rows']:
        stat = r.get('statistic')
        key = 'best' if stat == 'best' else 'median'
        notes = [r['note']] if r.get('note') else []
        if 'baseline_runs' in r:
            notes.append('runs: base %s, candidate %s' % (' '.join(_fmt(v) for v in r['baseline_runs']),
                                                          ' '.join(_fmt(v) for v in r['candidate_runs'])))
        lines.append(row_format % (
            r['scenario'], r['metric'], stat or '-',
            _fmt(r.get('baseline_' + key)), _fmt(r.get('candidate_' + key)),
            _fmt(r.get('baseline_median')), _fmt(r.get('candidate_median')),
            _fmt(r.get('change_percent'), 3), r['verdict'],
            (' (%s)' % '; '.join(notes)) if notes else ''))
    if report.get('advice'):
        lines.append('')
        lines.append('SUSPECTED REGRESSION in %s. %s' % (', '.join(report['suspected']), report['advice']))
    return '\n'.join(lines)


def _load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('baseline', nargs='?')
    parser.add_argument('candidate', nargs='?')
    parser.add_argument('--json', action='store_true', help='print the report as JSON')
    parser.add_argument('--allow-non-baseline', action='store_true',
                        help='compare against a reference that is not labeled a baseline (not with --confirm)')
    parser.add_argument('--allow-different-machine', action='store_true',
                        help='compare results from machines that differ (not with --confirm)')
    parser.add_argument('--confirm', action='store_true',
                        help='confirm a suspected regression from runs of both versions made back to back')
    parser.add_argument('--base', nargs='+', default=[], metavar='FILE',
                        help='with --confirm: the result files of the base version, at least two')
    parser.add_argument('--candidate', nargs='+', default=[], metavar='FILE', dest='candidates',
                        help='with --confirm: the result files of the candidate version, at least two')
    args = parser.parse_args(argv)
    if args.confirm:
        if args.baseline or args.candidate:
            parser.print_usage(sys.stderr)
            print('perf_compare: --confirm takes its files with --base and --candidate', file=sys.stderr)
            return 2
        if args.allow_non_baseline or args.allow_different_machine:
            print('perf_compare: --confirm takes no --allow-* option: its runs must come from one machine and '
                  'need no baseline label', file=sys.stderr)
            return 2
    elif args.base or args.candidates or not (args.baseline and args.candidate):
        parser.print_usage(sys.stderr)
        print('perf_compare: give BASELINE and CANDIDATE, or --confirm with --base and --candidate',
              file=sys.stderr)
        return 2
    try:
        if args.confirm:
            bases = [_load(p) for p in args.base]
            candidates = [_load(p) for p in args.candidates]
        else:
            baseline = _load(args.baseline)
            candidate = _load(args.candidate)
    except (OSError, ValueError) as e:
        print('perf_compare: %s' % e, file=sys.stderr)
        return 2
    if args.confirm:
        report = compare_confirm(bases, candidates, base_names=[os.path.realpath(p) for p in args.base],
                                 candidate_names=[os.path.realpath(p) for p in args.candidates])
    else:
        report = compare(baseline, candidate, allow_non_baseline=args.allow_non_baseline,
                         allow_different_machine=args.allow_different_machine)
    print(json.dumps(report, indent=1, sort_keys=True) if args.json else render(report))
    return report['exit_code']


if __name__ == '__main__':
    sys.exit(main())
