#!/usr/bin/env python3
"""Test times across several full-suite logs, and the fast test tier.

Part of the Objective-C to Swift migration (docs/swift-migration/test-speed.md
and test-tiers.md). It reads xcodebuild test logs with
tools/swift_migration/test_timing.py's parser and combines them.

Usage:
    test_tiers.py stats [--mode MODE] [--json] LOG ...
    test_tiers.py budget --slow-tier FILE [--mode MODE] [--json] LOG ...
    test_tiers.py propose --slow-tier FILE [--mode MODE] LOG ...
    test_tiers.py propose-removals --slow-tier FILE [--mode MODE] [--min-runs N] [--json] LOG ...
    test_tiers.py skip-args FILE
    test_tiers.py strip-env XCTESTRUN OUT

stats
    For each test, its time in every log of the mode: the maximum, the
    median (of an even number of runs, the mean of the middle two) and the
    number of runs it has a timing in. Lists the tests at or over 5 and 1
    seconds by maximum, slowest first, and per-class totals (the sum of the
    class's per-test medians and of its maxima), slowest first, and each
    log's serial total (the sum of all its result times). Skipped results
    are not timings and are left out; a test with only skipped results is
    listed apart. A failed result is a timing.

budget
    Splits each log's serial total between the slow tier (the tests the
    list FILE names) and the fast tier (all the others), gives the median of
    the fast tier's totals across the logs, counts the tests with timings in
    each tier, lists the fast tier's tests at or over 1 second by median
    (test-speed.md section 2 says each needs a reason or goes to the slow
    tier; the median, because the maximum of many runs on a shared machine
    is mostly load), and lists the entries of FILE that match no test in any log
    (stale entries). Staleness means something only for full-suite logs
    that ran the slow tier; in a fast-tier log every entry is skipped, so
    every entry looks stale.

propose
    Prints a slow-tier line for each of the fast tier's tests at or over 1
    second by median, with its numbers as the reason ("ceiling" at or over
    10 seconds, "one second" otherwise), ready to be added to FILE.

propose-removals
    The other direction: lists the entries of FILE that are there for their
    time (reason starting "one second" or "ceiling") whose median in the
    logs is under one second over at least N runs (--min-runs, default 3),
    entries with fewer runs apart, and per class how many of its entries
    listed for their time would go. The evidence must be runs that ran these
    tests: the default mode is fast-full (fast_tests.sh --no-skip, the whole
    suite as the fast tier runs it); "--mode fast-full,plain" adds plain
    runs (sanitizer_tests.sh plain, which keeps MallocStackLogging and so
    errs towards keeping entries). A fast-tier run skips these tests and is
    no evidence. Entries kept for another reason (the owner's decision, a
    failure, on screen) are never proposed.

skip-args
    Prints one xcodebuild -skip-testing:ModernTests/<entry> argument per
    line for the entries of FILE.

strip-env
    Copies the .xctestrun file XCTESTRUN (written by xcodebuild
    build-for-testing) to OUT without the MallocStackLogging variables
    (MallocStackLogging*, PrefersMallocStackLoggingLite) in any test
    target's EnvironmentVariables or TestingEnvironmentVariables. The
    ModernTests test plan sets them; the fast tier runs without them. Every
    other variable is kept. It fails (status 2) if there is no such
    variable to remove. OUT must be in the same directory as XCTESTRUN,
    since the paths in it (__TESTROOT__) are relative to the file.

--mode MODE
    Only logs of this mode are used (default asan; several modes may be
    given separated by commas). The mode is read from
    the log's "Command line invocation:" line: thread
    (-enableThreadSanitizer YES), ubsan (-fsanitize=<group>, the
    nullability and integer modes of sanitizer_tests.sh), fast
    (test-without-building with ModernTests_FastTier.xctestrun and
    -skip-testing arguments: fast_tests.sh), fast-full (the same with no
    -skip-testing: fast_tests.sh --no-skip), coverage
    (-fprofile-instr-generate, coverage_tests.sh), plain (-enableAddressSanitizer
    NO and none of those: sanitizer_tests.sh plain), asan (none of these:
    tools/run_tests.expect, where the ModernTests test plan turns the
    address sanitizer on), unknown (no invocation line). A log of another
    mode, or with the same content as an earlier one (a console copy of a
    run's test.log), is left out and the output says so.

A log the timing script calls incomplete (a run killed, a host crash) is
still used, and is marked so: the times it has are real.

The slow-tier file: one entry per line, "Class" or "Class/testMethod",
then white space, then the reason, which is required. Blank lines and
lines starting with # are ignored. An entry may appear once, and a method
may not be listed under a class that is listed whole.

Parallel logs interleave the results of several test hosts; test_timing.py
attributes each result to its test by name, so the interleaving does not
matter here.

Exit status: 0 success, 2 usage error, unreadable log or list, a log that is
not a test log, or no log of the mode.
Python 3 standard library only. Writes nothing to disk; run with python3 -B.
"""

import argparse
import hashlib
import json
import os
import plistlib
import re
import sys
from decimal import Decimal

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_timing  # noqa: E402

THRESHOLDS = (Decimal(5), Decimal(1))
MEDIAN_THRESHOLDS = (Decimal(10), Decimal(5), Decimal(1))
FAST_LIMIT = Decimal(1)
ENTRY = re.compile(r"^([A-Za-z_]\w*)(?:/([A-Za-z_]\w*))?$")
TARGET = "ModernTests"


class Error(Exception):
    pass


def log_mode(path):
    """The mode of the run that wrote the log, from its invocation line."""
    invocation = None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        previous = ""
        for line in f:
            if previous.startswith("Command line invocation:"):
                invocation = line
                break
            previous = line
    if invocation is None:
        return "unknown"
    if "test-without-building" in invocation and "ModernTests_FastTier.xctestrun" in invocation:
        return "fast" if "-skip-testing:" in invocation else "fast-full"
    if "-enableThreadSanitizer YES" in invocation:
        return "thread"
    if "-fsanitize=" in invocation:
        return "ubsan"
    if "-fprofile-instr-generate" in invocation:
        return "coverage"
    if "-enableAddressSanitizer NO" in invocation:
        return "plain"
    return "asan"


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def read_log(path):
    """(results, complete): results are (test id, status, Decimal seconds)."""
    try:
        with open(path, "rb") as f:
            text = f.read().decode("utf-8", errors="replace")
    except OSError as e:
        raise Error("cannot read %s: %s" % (path, e.strerror or e))
    try:
        parsed = test_timing.parse_log(text)
    except test_timing.LogFormatError as e:
        raise Error("%s: %s" % (path, e))
    del text
    report = test_timing.build_report(parsed, path, Decimal(5), 0)
    results = [(r["test"], r["status"], r["seconds"]) for r in parsed.results]
    return results, report["complete"]


def select_logs(paths, mode):
    """(used, left_out): used is [(path, results, complete)]. mode is one
    mode or several separated by commas."""
    modes = set(mode.split(","))
    used, left_out, seen = [], [], {}
    for path in paths:
        if not os.path.isfile(path):
            raise Error("cannot read %s: not a file" % path)
        m = log_mode(path)
        if m not in modes:
            left_out.append({"path": path, "reason": "mode %s, not %s" % (m, mode)})
            continue
        d = digest(path)
        if d in seen:
            left_out.append({"path": path, "reason": "same content as " + seen[d]})
            continue
        seen[d] = path
        results, complete = read_log(path)
        used.append((path, results, complete))
    if not used:
        raise Error("no log of mode %s among the %d given" % (mode, len(paths)))
    return used, left_out


def median(values):
    v = sorted(values)
    n = len(v)
    mid = n // 2
    return v[mid] if n % 2 else (v[mid - 1] + v[mid]) / 2


def num(d):
    return float(d)


def per_test(used):
    """test id -> [Decimal seconds per log it has a timing in]. A test with
    several timings in one log (a restart) counts its largest."""
    times, skipped = {}, set()
    for _, results, _ in used:
        in_log = {}
        for tid, status, seconds in results:
            if status == "skipped":
                skipped.add(tid)
                continue
            in_log[tid] = max(seconds, in_log.get(tid, seconds))
        for tid, s in in_log.items():
            times.setdefault(tid, []).append(s)
    return times, sorted(skipped - set(times))


def test_rows(times):
    rows = []
    for tid, values in times.items():
        rows.append({"test": tid, "class": tid.split("/", 1)[0], "max": max(values),
                     "median": median(values), "runs": len(values)})
    rows.sort(key=lambda r: (-r["max"], -r["median"], r["test"]))
    return rows


def json_row(r):
    return {"test": r["test"], "class": r["class"], "max": num(r["max"]), "median": num(r["median"]),
            "runs": r["runs"]}


def log_rows(used):
    return [{"path": p, "results": len(res), "complete": complete,
             "seconds": num(sum((s for _, _, s in res), Decimal(0)))} for p, res, complete in used]


def stats(used, left_out, mode):
    times, skipped_only = per_test(used)
    rows = test_rows(times)
    by_median = sorted(rows, key=lambda r: (-r["median"], -r["max"], r["test"]))
    classes = {}
    for r in rows:
        c = classes.setdefault(r["class"], {"class": r["class"], "tests": 0,
                                            "median_total": Decimal(0), "max_total": Decimal(0)})
        c["tests"] += 1
        c["median_total"] += r["median"]
        c["max_total"] += r["max"]
    class_rows = sorted(classes.values(), key=lambda c: (-c["median_total"], c["class"]))
    return {
        "mode": mode,
        "logs": log_rows(used),
        "left_out": left_out,
        "tests": [json_row(r) for r in rows],
        "skipped_only": skipped_only,
        "over": {str(t): [json_row(r) for r in rows if r["max"] >= t] for t in THRESHOLDS},
        "over_median": {str(t): [json_row(r) for r in by_median if r["median"] >= t] for t in MEDIAN_THRESHOLDS},
        "classes": [{"class": c["class"], "tests": c["tests"], "median_total": num(c["median_total"]),
                     "max_total": num(c["max_total"])} for c in class_rows],
    }


def read_slow_tier(path):
    entries, ids = [], set()
    try:
        f = open(path, "r", encoding="utf-8")
    except OSError as e:
        raise Error("cannot read %s: %s" % (path, e.strerror or e))
    with f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            where = "%s line %d" % (path, lineno)
            if len(parts) < 2 or not parts[1].strip():
                raise Error("%s: %s has no reason" % (where, parts[0]))
            m = ENTRY.match(parts[0])
            if not m:
                raise Error("%s: %r is not Class or Class/testMethod" % (where, parts[0]))
            if parts[0] in ids:
                raise Error("%s: %s is listed twice" % (where, parts[0]))
            ids.add(parts[0])
            entries.append({"id": parts[0], "class": m.group(1), "method": m.group(2),
                            "reason": parts[1].strip(), "line": lineno})
    whole = {e["class"] for e in entries if e["method"] is None}
    for e in entries:
        if e["method"] is not None and e["class"] in whole:
            raise Error("%s line %d: %s is under %s, which is listed whole"
                        % (path, e["line"], e["id"], e["class"]))
    return entries


def in_slow_tier(tid, entries_index):
    cls = tid.split("/", 1)[0]
    return cls in entries_index or tid in entries_index


def budget(used, left_out, mode, entries):
    index = {e["id"] for e in entries}
    logs = []
    for path, results, complete in used:
        fast = slow = Decimal(0)
        for tid, _, seconds in results:
            if in_slow_tier(tid, index):
                slow += seconds
            else:
                fast += seconds
        logs.append({"path": path, "complete": complete, "fast_seconds": num(fast), "slow_seconds": num(slow)})
    times, _ = per_test(used)
    rows = test_rows(times)
    fast_rows = [r for r in rows if not in_slow_tier(r["test"], index)]
    seen_ids = set()
    for path, results, _ in used:
        for tid, _, _ in results:
            seen_ids.add(tid)
            seen_ids.add(tid.split("/", 1)[0])
    return {
        "mode": mode,
        "logs": logs,
        "left_out": left_out,
        "fast_median": num(median([Decimal(str(l["fast_seconds"])) for l in logs])),
        "slow_median": num(median([Decimal(str(l["slow_seconds"])) for l in logs])),
        "fast_tests": len(fast_rows),
        "slow_tests": len(rows) - len(fast_rows),
        "fast_over_1": [json_row(r) for r in sorted(fast_rows, key=lambda r: (-r["median"], r["test"]))
                        if r["median"] >= FAST_LIMIT],
        "stale": [e["id"] for e in entries if e["id"] not in seen_ids],
    }


CEILING = Decimal(10)
ENV_KEYS = ("EnvironmentVariables", "TestingEnvironmentVariables")


def stripped_variable(name):
    return name.startswith("MallocStackLogging") or name == "PrefersMallocStackLoggingLite"


def strip_env(src, dst):
    """Copies the .xctestrun src to dst without the MallocStackLogging
    variables in any test target's environment. Returns (targets, removed
    names, number removed)."""
    try:
        with open(src, "rb") as f:
            data = plistlib.load(f)
    except (OSError, plistlib.InvalidFileException, ValueError) as e:
        raise Error("cannot read %s: %s" % (src, e))
    if not isinstance(data, dict):
        raise Error("%s: not an .xctestrun property list" % src)
    targets = []
    if "TestConfigurations" in data:
        # Format 2: the targets are in the test configurations; the other
        # top-level keys (ContainerInfo, TestPlan, ...) are not targets.
        for config in data.get("TestConfigurations") or []:
            targets.extend(t for t in config.get("TestTargets") or [] if isinstance(t, dict))
    else:
        # Format 1: every top-level key but the metadata names a target.
        targets = [v for k, v in data.items() if not k.startswith("__") and isinstance(v, dict)]
    if not targets:
        raise Error("%s: no test target found" % src)
    names, count = set(), 0
    for target in targets:
        for key in ENV_KEYS:
            env = target.get(key)
            if isinstance(env, dict):
                for name in [n for n in env if stripped_variable(n)]:
                    del env[name]
                    names.add(name)
                    count += 1
    if not count:
        raise Error("%s: no MallocStackLogging variable to remove; the fast tier would not differ from the "
                    "test plan's environment as intended (did the test plan change?)" % src)
    with open(dst, "wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_XML)
    return len(targets), sorted(names), count


def propose(r):
    """Slow-tier lines for the fast tier's tests at or over 1 second."""
    lines = []
    for t in r["fast_over_1"]:
        what = "ceiling" if Decimal(str(t["median"])) >= CEILING else "one second"
        lines.append("%s  %s: median %.3f s, max %.3f s in %d %s runs\n"
                     % (t["test"], what, t["median"], t["max"], t["runs"], r["mode"]))
    return "".join(lines)


TIMED_REASONS = ("one second", "ceiling")
MIN_RUNS_DEFAULT = 3


def propose_removals(used, mode, entries, min_runs):
    """Entries in the slow tier for their time (a reason starting "one
    second" or "ceiling", as propose writes them) whose median in these
    logs is under one second over at least min_runs runs."""
    times, _ = per_test(used)
    rows = {r["test"]: r for r in test_rows(times)}
    timed = [e for e in entries if e["method"] is not None and e["reason"].startswith(TIMED_REASONS)]
    remove, too_few, by_class = [], [], {}
    for e in timed:
        c = by_class.setdefault(e["class"], {"class": e["class"], "remove": 0, "listed": 0})
        c["listed"] += 1
        r = rows.get(e["id"])
        if r is None:
            continue
        row = dict(json_row(r), reason=e["reason"])
        if r["runs"] < min_runs:
            too_few.append(row)
        elif r["median"] < FAST_LIMIT:
            remove.append(row)
            c["remove"] += 1
    remove.sort(key=lambda t: (t["class"], t["test"]))
    classes = sorted((c for c in by_class.values() if c["remove"]),
                     key=lambda c: (-c["remove"], -c["listed"], c["class"]))
    return {"mode": mode, "min_runs": min_runs, "logs": [p for p, _, _ in used], "listed_for_time": len(timed),
            "remove": remove, "too_few_runs": too_few, "by_class": classes}


def print_removals(r, out):
    out.write("Logs of mode %s: %d. Entries listed for their time: %d.\n"
              % (r["mode"], len(r["logs"]), r["listed_for_time"]))
    out.write("\nProposed for removal (median under 1 second in at least %d runs): %d\n"
              % (r["min_runs"], len(r["remove"])))
    for t in r["remove"]:
        out.write("%s  median %.3f s, max %.3f s in %d %s runs (listed: %s)\n"
                  % (t["test"], t["median"], t["max"], t["runs"], r["mode"], t["reason"]))
    out.write("\nNot enough runs to judge (fewer than %d): %d\n" % (r["min_runs"], len(r["too_few_runs"])))
    out.write("\nBy class (entries proposed for removal of those listed for their time):\n")
    for c in r["by_class"]:
        out.write("  %6d of %6d  %s\n" % (c["remove"], c["listed"], c["class"]))


def fmt(x):
    return "%8.3f" % x


def print_logs(r, out):
    out.write("Logs of mode %s: %d\n" % (r["mode"], len(r["logs"])))
    for l in r["logs"]:
        extra = "" if l["complete"] else "  (incomplete; its times are used)"
        if "seconds" in l:
            out.write("  %s  %6d results  serial total %s s%s\n" % (l["path"], l["results"], fmt(l["seconds"]), extra))
        else:
            out.write("  %s  fast %s s  slow %s s%s\n" % (l["path"], fmt(l["fast_seconds"]),
                                                        fmt(l["slow_seconds"]), extra))
    for l in r["left_out"]:
        out.write("  left out: %s (%s)\n" % (l["path"], l["reason"]))


def print_rows(rows, out):
    out.write("       max   median  runs  test\n")
    for t in rows:
        out.write("  %s %s  %d  %s\n" % (fmt(t["max"]), fmt(t["median"]), t["runs"], t["test"]))


def print_stats(r, out):
    print_logs(r, out)
    for t in THRESHOLDS:
        rows = r["over"][str(t)]
        out.write("\nTests at or over %s seconds (by maximum): %d\n" % (t, len(rows)))
        print_rows(rows, out)
    for t in MEDIAN_THRESHOLDS:
        rows = r["over_median"][str(t)]
        out.write("\nTests at or over %s seconds (by median): %d\n" % (t, len(rows)))
        print_rows(rows, out)
    out.write("\nClasses by the sum of their tests' medians (top 40 of %d):\n" % len(r["classes"]))
    out.write("  median total  max total  tests  class\n")
    for c in r["classes"][:40]:
        out.write("  %s     %s  %5d  %s\n" % (fmt(c["median_total"]), fmt(c["max_total"]), c["tests"], c["class"]))
    out.write("\nTests with only skipped results: %d\n" % len(r["skipped_only"]))


def print_budget(r, out):
    print_logs(r, out)
    out.write("\nFast tier: %d tests with timings, median serial total %s s\n" % (r["fast_tests"], fmt(r["fast_median"]).strip()))
    out.write("Slow tier: %d tests with timings, median serial total %s s\n" % (r["slow_tests"], fmt(r["slow_median"]).strip()))
    out.write("\nFast-tier tests at or over 1 second (by median): %d\n" % len(r["fast_over_1"]))
    print_rows(r["fast_over_1"], out)
    out.write("\nSlow-tier entries matching no test in these logs (meaningful only for full-suite logs): %d\n"
              % len(r["stale"]))
    for s in r["stale"]:
        out.write("  %s\n" % s)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="test_tiers.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    s = sub.add_parser("stats")
    s.add_argument("logs", nargs="+")
    s.add_argument("--mode", default="asan")
    s.add_argument("--json", action="store_true")
    b = sub.add_parser("budget")
    b.add_argument("logs", nargs="+")
    b.add_argument("--slow-tier", required=True)
    b.add_argument("--mode", default="asan")
    b.add_argument("--json", action="store_true")
    p = sub.add_parser("propose")
    p.add_argument("logs", nargs="+")
    p.add_argument("--slow-tier", required=True)
    p.add_argument("--mode", default="asan")
    r_ = sub.add_parser("propose-removals")
    r_.add_argument("logs", nargs="+")
    r_.add_argument("--slow-tier", required=True)
    r_.add_argument("--mode", default="fast-full")
    r_.add_argument("--min-runs", type=int, default=MIN_RUNS_DEFAULT)
    r_.add_argument("--json", action="store_true")
    e = sub.add_parser("strip-env")
    e.add_argument("src")
    e.add_argument("dst")
    k = sub.add_parser("skip-args")
    k.add_argument("list")
    args = ap.parse_args(argv)
    try:
        if args.command == "strip-env":
            targets, names, count = strip_env(args.src, args.dst)
            sys.stdout.write("Removed %d variable(s) from %d test target(s): %s\n"
                             % (count, targets, ", ".join(names) or "none"))
            return 0
        if args.command == "skip-args":
            for e in read_slow_tier(args.list):
                sys.stdout.write("-skip-testing:%s/%s\n" % (TARGET, e["id"]))
            return 0
        entries = (read_slow_tier(args.slow_tier) if args.command in ("budget", "propose", "propose-removals")
                   else None)
        used, left_out = select_logs(args.logs, args.mode)
    except Error as e:
        sys.stderr.write("test_tiers.py: %s\n" % e)
        return 2
    if args.command == "propose":
        sys.stdout.write(propose(budget(used, left_out, args.mode, entries)))
        return 0
    if args.command == "propose-removals":
        r = propose_removals(used, args.mode, entries, args.min_runs)
        if args.json:
            json.dump(r, sys.stdout, indent=1)
            sys.stdout.write("\n")
        else:
            print_removals(r, sys.stdout)
        return 0
    if args.command == "stats":
        r = stats(used, left_out, args.mode)
        printer = print_stats
    else:
        r = budget(used, left_out, args.mode, entries)
        printer = print_budget
    if args.json:
        json.dump(r, sys.stdout, indent=1)
        sys.stdout.write("\n")
    else:
        printer(r, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
