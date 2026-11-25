#!/usr/bin/env python3
"""The dossier's length against its cap (docs/swift-migration/lifecycle.md
section 4, "Dossier length").

Usage:

  dossier_cap.py DOSSIER --path trivial|light|full [--implementation FILE...]

DOSSIER is docs/swift-migration/units/<name>.md; its evidence files,
units/<name>.*.md, count toward the cap with it. The cap: a trivial unit has
no dossier; a light unit's is at most 60 lines; a full unit's is at most one
line per line of its implementation files (--implementation, required), but
never less than 100 or more than 600. A dossier may go over the cap only
with a line "Over the cap: <reason>" among its first 10 lines; the reason is
printed.

Exit status: 0 within the cap (or over it with a stated reason), 1 over it,
2 on an error.
"""

import argparse
import glob
import os
import re
import sys

LIGHT_CAP = 60
FULL_FLOOR = 100
FULL_CEILING = 600
REASON_LINES = 10
_REASON = re.compile(r'^\s*Over the cap:\s*(\S.*)$')


def cap(path, implementation_lines):
    if path == 'trivial':
        return 0
    if path == 'light':
        return LIGHT_CAP
    return min(FULL_CEILING, max(FULL_FLOOR, implementation_lines))


def count_lines(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return sum(1 for _ in f)


def reason(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for i, line in enumerate(f):
            if i >= REASON_LINES:
                break
            m = _REASON.match(line)
            if m:
                return m.group(1).strip()
    return None


def main(argv=None, out=None):
    out = out or sys.stdout
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('dossier')
    p.add_argument('--path', required=True, choices=('trivial', 'light', 'full'))
    p.add_argument('--implementation', nargs='+', default=[])
    a = p.parse_args(argv)
    try:
        if a.path == 'full' and not a.implementation:
            print('dossier_cap: error: the full path\'s cap needs --implementation', file=sys.stderr)
            return 2
        impl = sum(count_lines(f) for f in a.implementation)
        stem = os.path.splitext(a.dossier)[0]
        files = [a.dossier] + sorted(glob.glob(glob.escape(stem) + '.*.md'))
        counts = [(f, count_lines(f)) for f in files]
        why = reason(a.dossier)
    except OSError as e:
        print('dossier_cap: error: %s' % e, file=sys.stderr)
        return 2
    total = sum(n for _, n in counts)
    limit = cap(a.path, impl)
    out.write('%s\n' % ', '.join('%s: %d lines' % (f, n) for f, n in counts))
    if a.path == 'trivial':
        out.write('over the cap: the trivial path has no dossier; its notes go in the commit message\n')
        return 1
    basis = 'light path' if a.path == 'light' else 'full path, %d implementation lines' % impl
    out.write('%d of %d lines (%s)\n' % (total, limit, basis))
    if total <= limit:
        return 0
    if why:
        out.write('over the cap with a stated reason: %s\n' % why)
        return 0
    out.write('over the cap by %d lines: shorten it to what was found, one line per check that found nothing, or '
              'state "Over the cap: <reason>" in its first %d lines\n' % (total - limit, REASON_LINES))
    return 1


if __name__ == '__main__':
    sys.exit(main())
