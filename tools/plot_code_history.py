#!/usr/bin/env python3
"""
plot_code_history.py

Chart lines of hand-written source code added per month over the life of the
repo, with commits per month underneath. Requires matplotlib.

Usage:
    tools/plot_code_history.py [--ref master] [--output code_history.png]

What counts:
  * Lines added only. Deletions are ignored so that edits and moves are not
    double-counted and removals of vendored code don't show up as work.
  * Hand-written source extensions only (see SOURCE_EXTENSIONS).
  * Excludes vendored and generated code, localization, xibs, project files,
    docs and test fixtures (see EXCLUDED_PATHS and GENERATED_*).
  * Excludes merge commits, duplicated commits (same author, timestamp,
    subject and size; early history contains copies) and bulk imports.

The shaded bands mark when Claude Code took over writing code and commit
messages, as inferred from tests, comment density, em dashes, and commit
message bodies. Edit PHASES to change them.
"""

import argparse
import collections
import datetime as dt
import os
import re
import subprocess
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

SOURCE_EXTENSIONS = {
    ".m", ".h", ".swift", ".mm", ".c", ".cc", ".cpp",
    ".py", ".js", ".css", ".html", ".metal", ".sh",
}

EXCLUDED_PATHS = re.compile(
    r"(^|/)(iterm2env|ThirdParty|ply|RegexKitLite|UKCrashReporter|build|_build|"
    r"site-packages|node_modules|Pods|Carthage|venv|\.venv)(/|$)"
    r"|\.framework(\.dSYM)?/"
    r"|_pb2\.py$|\.pb(objc)?\.[hm]$|\.pbobjc\.[hm]$"
    r"|\.min\.(js|css)$"
    r"|(^|/)docs?/"
    r"|/Resources/|Test Resources/")

# Files that are always generated.
GENERATED_FILES = re.compile(
    r"(^|/)(generated\.py|NSCharacterSet\+iTerm\.m|iTermCharacterSets\.m|"
    r"BrowserExtensionAPIProtocols\.swift|BrowserExtensionDispatcher\.swift|"
    r"iTermBundledIt2\.swift|iTermLatestVersionByShell\.h)$")

# Files that were hand-written until a generator replaced them on this date.
GENERATED_SINCE = [
    (re.compile(r"api/library/python/iterm2/iterm2/profile\.py$"), "2021-06-18"),
    (re.compile(r"api/library/python/iterm2/iterm2/(mainmenu|binding)\.py$"), "2021-07-07"),
]

# Commits that import code wholesale rather than write it.
BULK_IMPORT_SHAS = ("732e2016a", "599ec03f7")
BULK_IMPORT_SUBJECTS = {"Initial fork of iTerm"}

# (start, end exclusive, color, label)
PHASES = [
    (dt.date(2025, 4, 1), dt.date(2025, 8, 1), "#e9e7e1",
     "Trial: Claude-assisted code (Apr–Jul 2025)"),
    (dt.date(2026, 1, 1), dt.date(2026, 4, 1), "#d6d4cc",
     "Claude writes code, George writes messages (Jan–Mar 2026)"),
    (dt.date(2026, 4, 1), None, "#bfbdb4",
     "Claude writes code and messages (Apr 2026 on)"),
]

INK = "#0b0b0b"
SECONDARY_INK = "#52514e"
MUTED_INK = "#898781"
GRID = "#e1e0d9"
BACKGROUND = "#fcfcfb"
BLUE = "#2a78d6"


def normalize_path(path):
    """Resolve numstat rename syntax ("a/{x => y}/b" or "x => y") to the new path."""
    m = re.match(r"(.*)\{(.*) => (.*)\}(.*)", path)
    if m:
        return m.group(1) + m.group(3) + m.group(4)
    if " => " in path:
        return path.split(" => ")[1]
    return path


def is_counted(path, date):
    if os.path.splitext(path)[1] not in SOURCE_EXTENSIONS:
        return False
    if EXCLUDED_PATHS.search(path) or GENERATED_FILES.search(path):
        return False
    for regex, since in GENERATED_SINCE:
        if regex.search(path) and date[:10] >= since:
            return False
    return True


def read_commits(ref):
    """Yield (sha, iso_date, author, subject, [(added, deleted, path)])."""
    out = subprocess.run(
        ["git", "log", "--no-merges", "--numstat", "--date=iso-strict",
         "--format=@%H|%ad|%an|%s", ref],
        check=True, capture_output=True, text=True, errors="replace").stdout
    current = None
    for line in out.splitlines():
        if line.startswith("@"):
            if current:
                yield current
            sha, date, author, subject = line[1:].split("|", 3)
            current = (sha, date, author, subject, [])
            continue
        parts = line.split("\t")
        if current and len(parts) == 3 and parts[0] != "-":
            current[4].append((int(parts[0]), int(parts[1]), normalize_path(parts[2])))
    if current:
        yield current


def monthly_totals(ref):
    lines_added = collections.Counter()
    commit_count = collections.Counter()
    seen = set()
    for sha, date, author, subject, files in read_commits(ref):
        key = (date, author, subject, sum(a + d for a, d, _ in files))
        if key in seen:
            continue
        seen.add(key)
        if sha.startswith(BULK_IMPORT_SHAS) or subject.strip() in BULK_IMPORT_SUBJECTS:
            continue
        month = date[:7]
        commit_count[month] += 1
        lines_added[month] += sum(a for a, _, p in files if is_counted(p, date))
    return lines_added, commit_count


def month_range(first, last):
    d = dt.date(int(first[:4]), int(first[5:]), 1)
    end = dt.date(int(last[:4]), int(last[5:]), 1)
    while d <= end:
        yield d
        d = dt.date(d.year + (d.month == 12), d.month % 12 + 1, 1)


def rolling_mean(values, window=12):
    return [sum(values[max(0, i - window + 1):i + 1]) / len(values[max(0, i - window + 1):i + 1])
            for i in range(len(values))]


def style_axis(ax):
    ax.set_facecolor(BACKGROUND)
    ax.grid(axis="y", color=GRID, lw=0.6)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(colors=MUTED_INK, length=0, labelsize=9)


def plot(lines_added, commit_count, output):
    months = sorted(set(lines_added) | set(commit_count))
    xs = list(month_range(months[0], months[-1]))
    keys = [x.strftime("%Y-%m") for x in xs]
    added = [lines_added[k] for k in keys]
    commits = [commit_count[k] for k in keys]
    x_end = dt.date(xs[-1].year + 1, 1, 1)

    fig, (top, bottom) = plt.subplots(
        2, 1, figsize=(13, 8.5), dpi=150, sharex=True,
        gridspec_kw={"height_ratios": [2.2, 1], "hspace": 0.12})
    fig.patch.set_facecolor(BACKGROUND)
    abbreviate = FuncFormatter(
        lambda v, _: f"{v / 1e6:g}M" if v >= 1e6 else f"{v / 1e3:g}K" if v >= 1e3 else f"{v:g}")

    for ax in (top, bottom):
        style_axis(ax)
        for start, end, color, _ in PHASES:
            ax.axvspan(start, end or x_end, color=color, zorder=0, lw=0)
        ax.set_xlim(dt.date(xs[0].year, 1, 1), x_end)

    top.bar(xs, [max(v, 1) for v in added], width=26, align="edge",
            color=BLUE, alpha=0.85, label="Lines added per month")
    top.plot(xs, rolling_mean(added), color=INK, lw=1.5, label="12-month average")
    top.set_yscale("log")
    top.yaxis.set_major_formatter(abbreviate)
    top.set_ylabel("Lines added (log scale)", color=SECONDARY_INK, fontsize=10)
    handles, labels = top.get_legend_handles_labels()
    handles += [mpatches.Patch(color=color) for _, _, color, _ in PHASES]
    labels += [label for _, _, _, label in PHASES]
    top.legend(handles, labels, frameon=False, labelcolor=SECONDARY_INK, fontsize=9,
               loc="upper left")
    top.set_title("iTerm2: lines of source code added per month",
                  loc="left", color=INK, fontsize=14, pad=44)
    top.text(0, 1.035,
             "Lines added (deletions not counted), hand-written source only "
             "(.m .h .swift .mm .c .py .js .css .html .metal .sh).\n"
             "Excludes vendored and generated code, localization, xibs, project files, docs, "
             "test fixtures, duplicated commits, and bulk imports.",
             transform=top.transAxes, color=SECONDARY_INK, fontsize=8.5)

    bottom.bar(xs, commits, width=26, align="edge", color=BLUE, alpha=0.85)
    bottom.plot(xs, rolling_mean(commits), color=INK, lw=1.5, label="12-month average")
    bottom.set_ylabel("Commits per month", color=SECONDARY_INK, fontsize=10)
    bottom.yaxis.set_major_formatter(abbreviate)
    bottom.legend(frameon=False, labelcolor=SECONDARY_INK, fontsize=9, loc="upper left")
    bottom.xaxis.set_major_locator(mdates.YearLocator(2))
    bottom.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))

    fig.subplots_adjust(left=0.07, right=0.98, top=0.87, bottom=0.05)
    fig.savefig(output, facecolor=BACKGROUND)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ref", default="master", help="branch or ref to analyze (default: master)")
    parser.add_argument("--output", default="code_history.png", help="output image path")
    args = parser.parse_args()

    lines_added, commit_count = monthly_totals(args.ref)
    plot(lines_added, commit_count, args.output)

    by_year = collections.defaultdict(lambda: [0, 0])
    for month in lines_added.keys() | commit_count.keys():
        by_year[month[:4]][0] += lines_added[month]
        by_year[month[:4]][1] += commit_count[month]
    print(f"{'year':4} {'added':>8} {'commits':>7}")
    for year in sorted(by_year):
        print(f"{year:4} {by_year[year][0]:>8} {by_year[year][1]:>7}")
    print(f"Wrote {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
