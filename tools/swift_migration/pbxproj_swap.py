#!/usr/bin/env python3
"""Replace an Objective-C .m (and optionally its .h) with a .swift file in an
Xcode project file, in place.

Part of the Objective-C to Swift migration (docs/swift-migration/lifecycle.md
section 3, "The project file"). A whole-class port deletes Foo.h and Foo.m
and adds Foo.swift beside them. This tool makes the matching project file
change, and nothing else:

  - the .m's PBXFileReference becomes a PBXFileReference for the .swift, in
    the same position, with the same attributes except lastKnownFileType
    (sourcecode.swift) and the file name in its comment, name and path;
  - the .m's group child line becomes the .swift's, in the same group and
    position;
  - each PBXBuildFile of the .m (one per target) becomes a PBXBuildFile of
    the .swift, and its entry in that target's Sources phase is replaced in
    place;
  - the .h's PBXFileReference, group child, PBXBuildFile lines and their
    Headers phase entries are removed.

Fresh 24-hex identifiers are chosen that occur nowhere in the file. Every old
line must match exactly once where it is expected, and every identifier must
occur exactly as often as those lines account for, or the tool refuses and
changes nothing. A .m in more than one target is refused unless
--all-targets is given. A PBXBuildFile of the .m with settings (compiler
flags) is refused: they would not apply to Swift. The new file reference's
attribute set must already be used by some Swift file in the project.

Usage:
  pbxproj_swap.py [--project PATH] [--check] [--all-targets]
                  --m sources/Dir/Foo.m [--h sources/Dir/Foo.h]
                  --swift sources/Dir/Foo.swift

Paths are relative to the repository root (the project file's grandparent
directory). The .swift must be in the same directory as the .m, since it
takes the .m's place in the same group. --check prints the unified diff and
writes nothing. Exit 0 on success, 1 on refusal, 2 on usage error.
"""

import argparse
import difflib
import os
import random
import re
import sys

ID = r'[0-9A-F]{24}'


class Refusal(Exception):
    pass


def object_isa(lines, index):
    """The isa of the object whose body contains lines[index]."""
    for i in range(index, -1, -1):
        if re.match(r'^\t\t' + ID + r'( /\*.*\*/)? = \{$', lines[i]):
            for j in range(i + 1, min(i + 4, len(lines))):
                m = re.match(r'^\t\t\tisa = (\w+);$', lines[j])
                if m:
                    return lines[i].split()[0].strip(), m.group(1)
            break
    return None, None


def target_names(lines, phase_id):
    """Names of native targets whose buildPhases list phase_id."""
    names = []
    current = None
    in_phases = False
    for line in lines:
        m = re.match(r'^\t\t' + ID + r' /\* (.*) \*/ = \{$', line)
        if m:
            current = m.group(1)
            continue
        if re.match(r'^\t\t\tbuildPhases = \($', line):
            in_phases = True
            continue
        if in_phases:
            if line.strip() == ');':
                in_phases = False
            elif line.strip().startswith(phase_id):
                names.append(current)
    return names


def find_exact(lines, regex, what):
    hits = [i for i, l in enumerate(lines) if re.match(regex, l)]
    if len(hits) != 1:
        raise Refusal('%s: expected exactly one line, found %d%s' % (
            what, len(hits), ''.join('\n  line %d: %s' % (i + 1, lines[i].strip()) for i in hits[:5])))
    return hits[0]


def file_ref_index(lines, name):
    esc = re.escape(name)
    return find_exact(
        lines,
        r'^\t\t' + ID + r' /\* ' + esc + r' \*/ = \{isa = PBXFileReference;.*\bpath = ("?)([^;"]*/)?' + esc + r'\1;',
        'PBXFileReference of %s' % name)


def count_id(text, ident):
    return len(re.findall(r'\b' + ident + r'\b', text))


def build_files(lines, ref_id, name):
    esc = re.escape(name)
    out = []
    for i, l in enumerate(lines):
        m = re.match(r'^\t\t(' + ID + r') /\* ' + esc + r' in (\w+) \*/ = \{isa = PBXBuildFile; fileRef = '
                     + ref_id + r' /\* ' + esc + r' \*/;(.*)\};$', l)
        if m:
            out.append((i, m.group(1), m.group(2), m.group(3).strip()))
        elif re.search(r'fileRef = ' + ref_id + r'\b', l):
            raise Refusal('unexpected build file line for %s at line %d: %s' % (name, i + 1, l.strip()))
    return out


def phase_entry(lines, bf_id, name, phase):
    i = find_exact(lines, r'^\t\t\t\t' + bf_id + r' /\* ' + re.escape(name) + ' in ' + phase + r' \*/,$',
                   'build phase entry %s of %s' % (bf_id, name))
    phase_id, isa = object_isa(lines, i)
    expected = 'PBX%sBuildPhase' % phase
    if isa != expected:
        raise Refusal('build phase entry of %s at line %d is in a %s, expected %s' % (name, i + 1, isa, expected))
    return i, phase_id


def fresh_id(text, taken, rng):
    while True:
        ident = ''.join(rng.choice('0123456789ABCDEF') for _ in range(24))
        if ident not in text and ident not in taken:
            taken.add(ident)
            return ident


def shape(line):
    """A file reference line reduced to its attribute set, for comparison."""
    body = line.split('= {', 1)[1]
    body = re.sub(r'path = [^;]*;', 'path = P;', body)
    body = re.sub(r'name = [^;]*;', 'name = N;', body)
    return body


def swap(text, m_path, h_path, swift_path, all_targets=False, rng=None):
    rng = rng or random.SystemRandom()
    if os.path.dirname(m_path) != os.path.dirname(swift_path):
        raise Refusal('the .swift must be in the same directory as the .m')
    if not m_path.endswith('.m') or not swift_path.endswith('.swift') or (h_path and not h_path.endswith('.h')):
        raise Refusal('expected a .m, an optional .h and a .swift')
    lines = text.split('\n')
    m_name, swift_name = os.path.basename(m_path), os.path.basename(swift_path)
    if re.search(r'[ /]' + re.escape(swift_name) + r'[ ;"]', text):
        raise Refusal('%s is already named in the project file' % swift_name)

    changes = {}  # index -> new line, or None to delete
    taken = set()

    # The .m.
    mi = file_ref_index(lines, m_name)
    m_ref = lines[mi].split()[0].strip()
    if 'lastKnownFileType = sourcecode.c.objc;' not in lines[mi]:
        raise Refusal('the .m file reference is not sourcecode.c.objc: %s' % lines[mi].strip())
    m_bfs = build_files(lines, m_ref, m_name)
    if not m_bfs:
        raise Refusal('%s is in no target' % m_name)
    phases = []
    for i, bf, phase, settings in m_bfs:
        if phase != 'Sources':
            raise Refusal('%s has a build file in %s, expected Sources' % (m_name, phase))
        if settings:
            raise Refusal('%s has build settings in a target (%s); they would not apply to Swift' % (m_name, settings))
        pi, phase_id = phase_entry(lines, bf, m_name, 'Sources')
        if count_id(text, bf) != 2:
            raise Refusal('build file %s of %s occurs %d times, expected 2' % (bf, m_name, count_id(text, bf)))
        phases.append((i, bf, pi, phase_id))
    if len(m_bfs) > 1 and not all_targets:
        names = [n for _, _, _, p in phases for n in target_names(lines, p)]
        raise Refusal('%s is in %d targets (%s); pass --all-targets to replace it in every one'
                      % (m_name, len(m_bfs), ', '.join(names)))
    gi = find_exact(lines, r'^\t\t\t\t' + m_ref + r' /\* ' + re.escape(m_name) + r' \*/,$',
                    'group child of %s' % m_name)
    if count_id(text, m_ref) != 2 + len(m_bfs):
        raise Refusal('file reference %s of %s occurs %d times, expected %d'
                      % (m_ref, m_name, count_id(text, m_ref), 2 + len(m_bfs)))

    new_ref = fresh_id(text, taken, rng)
    new_line = lines[mi].replace(m_ref, new_ref, 1)
    new_line = new_line.replace('/* %s */' % m_name, '/* %s */' % swift_name, 1)
    new_line = new_line.replace('lastKnownFileType = sourcecode.c.objc;', 'lastKnownFileType = sourcecode.swift;')
    new_line = re.sub(r'(\b(?:path|name) = "?(?:[^;"]*/)?)' + re.escape(m_name) + r'("?;)',
                      lambda mm: mm.group(1) + swift_name + mm.group(2), new_line)
    swift_shapes = {shape(l) for l in lines if 'isa = PBXFileReference;' in l and 'sourcecode.swift;' in l}
    if shape(new_line) not in swift_shapes:
        raise Refusal('the new file reference has attributes no Swift file in the project has: %s' % new_line.strip())
    changes[mi] = new_line
    changes[gi] = '\t\t\t\t%s /* %s */,' % (new_ref, swift_name)
    for i, bf, pi, _ in phases:
        new_bf = fresh_id(text, taken, rng)
        changes[i] = '\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (
            new_bf, swift_name, new_ref, swift_name)
        changes[pi] = '\t\t\t\t%s /* %s in Sources */,' % (new_bf, swift_name)

    # The .h.
    if h_path:
        h_name = os.path.basename(h_path)
        hi = file_ref_index(lines, h_name)
        h_ref = lines[hi].split()[0].strip()
        h_bfs = build_files(lines, h_ref, h_name)
        hgi = find_exact(lines, r'^\t\t\t\t' + h_ref + r' /\* ' + re.escape(h_name) + r' \*/,$',
                         'group child of %s' % h_name)
        if count_id(text, h_ref) != 2 + len(h_bfs):
            raise Refusal('file reference %s of %s occurs %d times, expected %d'
                          % (h_ref, h_name, count_id(text, h_ref), 2 + len(h_bfs)))
        changes[hi] = None
        changes[hgi] = None
        for i, bf, phase, _ in h_bfs:
            if phase != 'Headers':
                raise Refusal('%s has a build file in %s, expected Headers' % (h_name, phase))
            pi, _ = phase_entry(lines, bf, h_name, 'Headers')
            if count_id(text, bf) != 2:
                raise Refusal('build file %s of %s occurs %d times, expected 2' % (bf, h_name, count_id(text, bf)))
            changes[i] = None
            changes[pi] = None

    out = [changes.get(i, l) if i in changes else l for i, l in enumerate(lines)]
    return '\n'.join(l for l in out if l is not None)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--project', default=None)
    ap.add_argument('--m', required=True)
    ap.add_argument('--h')
    ap.add_argument('--swift', required=True)
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--all-targets', action='store_true')
    a = ap.parse_args(argv)
    project = a.project or os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)))), 'iTerm2.xcodeproj', 'project.pbxproj')
    try:
        with open(project, encoding='utf-8') as f:
            text = f.read()
    except OSError as e:
        print('cannot read %s: %s' % (project, e), file=sys.stderr)
        return 2
    try:
        new = swap(text, a.m, a.h, a.swift, all_targets=a.all_targets)
    except Refusal as e:
        print('refused: %s' % e, file=sys.stderr)
        return 1
    diff = difflib.unified_diff(text.splitlines(True), new.splitlines(True), project, project)
    sys.stdout.writelines(diff)
    if not a.check:
        tmp = project + '.pbxproj_swap.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write(new)
        os.replace(tmp, project)
    return 0


if __name__ == '__main__':
    sys.exit(main())
