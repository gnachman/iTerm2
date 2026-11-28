#!/usr/bin/env python3
"""Replace an Objective-C .m (and optionally its .h) with a .swift file in an
Xcode project file, in place, or move a .m from one target to another.

Part of the Objective-C to Swift migration (docs/swift-migration/lifecycle.md
section 3, "The project file"). A whole-class port deletes Foo.h and Foo.m
and adds Foo.swift beside them. This tool makes the matching project file
change, and nothing else:

  - the .m's PBXFileReference becomes a PBXFileReference for the .swift, in
    the same position, with the same attributes except lastKnownFileType
    (sourcecode.swift) and the file name in its comment, name and path.
    indentWidth and tabWidth are left out: they are settings of Xcode's
    editor, which the build does not read, and no Swift file reference in
    the project has them. When the .m's reference has either, the tool
    prints a note on standard error naming what it left out;
  - the .m's group child line becomes the .swift's, in the same group and
    position;
  - each PBXBuildFile of the .m (one per target) becomes a PBXBuildFile of
    the .swift, and its entry in that target's Sources phase is replaced in
    place;
  - the .h's PBXFileReference, group child, PBXBuildFile lines and their
    phase entries are removed. A header's build file is normally in a
    Headers phase. Some headers are listed in a Sources phase instead,
    where they compile nothing; such a build file and its entry are removed
    the same way, and the tool prints a note on standard error naming the
    header and the target.

Fresh 24-hex identifiers are chosen that occur nowhere in the file. Every old
line must match exactly once where it is expected, and every identifier must
occur exactly as often as those lines account for, or the tool refuses and
changes nothing. A .m in more than one target is refused unless
--all-targets is given. A PBXBuildFile of the .m with settings (compiler
flags) is refused: they would not apply to Swift. The new file reference's
attribute set, after the editor settings are left out, must already be
used by some Swift file in the project; any other attribute no Swift file
has, such as lineEnding, a language override or an unusual fileEncoding,
is refused.
A PBXBuildFile of the .h is refused when it has settings (such as the
Public or Private attribute, which make the header part of a framework's
interface), when it is in a phase other than Headers or Sources, and when it
is in the Sources phase of a target that does not compile the .m. A .h in
the Headers phase of any target is removed whichever targets compile the
.m, since a header without the Public or Private attribute is copied
nowhere and compiles nothing.

A second mode moves a .m from one native target to another, as an `arc`
commit does when it moves a file from iTerm2Shared (compiled without ARC) to
iTerm2SharedARC (docs/swift-migration/arc.md, step 9). It changes one thing:

  - the .m's entry in the from-target's Sources phase is removed, and the
    same line is appended to the end of the to-target's Sources phase, which
    is where Xcode adds a new member. The PBXBuildFile itself is kept,
    unchanged: each PBXBuildFile is listed by exactly one phase (one per
    target membership), so moving its one entry moves the membership.

The .h is left alone: its Headers phase entries do not affect how anything
is compiled here. Other targets that compile the .m are left alone. The move
refuses, changing nothing, when either target name names no native target
or more than one, when the two are the same, when either target has other
than one Sources phase or shares it with another target, when the .m is not
in the from-target's Sources phase, is in it more than once, or is already
in the to-target's, when the .m has a build file in a phase other than
Sources, when the .m's file name matches no PBXFileReference or more than
one (two files of the same name in different directories), when the moving
PBXBuildFile has settings (compiler flags such as -fno-objc-arc; the
refusal names them), when the to-target's Sources phase has no closed files
list, and when an identifier involved, or the .m's group child line, does
not occur exactly as often as expected.

Usage:
  pbxproj_swap.py [--project PATH] [--check] [--all-targets]
                  --m sources/Dir/Foo.m [--h sources/Dir/Foo.h]
                  --swift sources/Dir/Foo.swift
  pbxproj_swap.py [--project PATH] [--check]
                  --m sources/Dir/Foo.m --from-target iTerm2Shared
                  --to-target iTerm2SharedARC

--move-to-target is a synonym of --to-target. The two modes compose: after
a move, a swap of the same .m replaces it in the target it moved to.

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

# File reference attributes that hold settings of Xcode's source editor (the
# Indent Width and Tab Width of the File inspector's Text Settings). The build
# does not read them, and no Swift file reference in the project has them.
EDITOR_ONLY_KEYS = ('indentWidth', 'tabWidth')


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


def swap(text, m_path, h_path, swift_path, all_targets=False, rng=None, notes=None):
    """The project text with the swap made. When notes is a list, a sentence is appended
    to it for each change the caller should be told about beyond the usual ones."""
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
    derived_line = new_line
    dropped = [key for key in EDITOR_ONLY_KEYS if re.search(r' %s = [^;]*;' % key, new_line)]
    for key in dropped:
        new_line = re.sub(r' %s = [^;]*;' % key, '', new_line, count=1)
    swift_shapes = {shape(l) for l in lines if 'isa = PBXFileReference;' in l and 'sourcecode.swift;' in l}
    if shape(new_line) not in swift_shapes:
        # The message shows the reference as derived from the .m's, with any editor settings
        # still in it, so that it matches the .m's line the reader will look up.
        raise Refusal('the new file reference has attributes no Swift file in the project has: %s'
                      % derived_line.strip())
    if dropped and notes is not None:
        notes.append('the file reference of %s had %s, which only Xcode\'s editor reads; the file reference '
                     'of %s leaves %s out' % (m_name, ' and '.join(dropped), swift_name,
                                              'it' if len(dropped) == 1 else 'them'))
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
        m_phase_ids = {phase_id for _, _, _, phase_id in phases}
        for i, bf, phase, settings in h_bfs:
            if phase not in ('Headers', 'Sources'):
                raise Refusal('%s has a build file in %s, expected Headers or Sources' % (h_name, phase))
            if settings:
                raise Refusal('%s has build settings in a target (%s); this tool does not remove a header with '
                              'settings, such as the Public or Private attribute, which makes it part of the '
                              'target\'s interface' % (h_name, settings))
            pi, phase_id = phase_entry(lines, bf, h_name, phase)
            if phase == 'Sources':
                # A header listed in a Sources phase compiles nothing there. The tool removes it only
                # from a target that compiles the .m being replaced, and refuses otherwise, because
                # such a listing in an unrelated target suggests a setup this tool does not understand.
                names = ', '.join(target_names(lines, phase_id))
                if phase_id not in m_phase_ids:
                    raise Refusal('%s is listed in the Sources phase of %s, which does not compile %s'
                                  % (h_name, names, m_name))
                if notes is not None:
                    notes.append('%s was listed in the Sources phase of %s; this swap removes its build file '
                                 'and phase entry' % (h_name, names))
            if count_id(text, bf) != 2:
                raise Refusal('build file %s of %s occurs %d times, expected 2' % (bf, h_name, count_id(text, bf)))
            changes[i] = None
            changes[pi] = None

    out = [changes.get(i, l) if i in changes else l for i, l in enumerate(lines)]
    return '\n'.join(l for l in out if l is not None)


def unquote(value):
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return re.sub(r'\\(.)', r'\1', value[1:-1])
    return value


def native_targets(lines):
    """(name, [build phase ids]) of every PBXNativeTarget."""
    out = []
    i = 0
    while i < len(lines):
        if (re.match(r'^\t\t' + ID + r'( /\*.*\*/)? = \{$', lines[i]) and i + 1 < len(lines)
                and lines[i + 1] == '\t\t\tisa = PBXNativeTarget;'):
            name, phases, in_phases = None, [], False
            i += 1
            while i < len(lines) and lines[i] != '\t\t};':
                line = lines[i]
                if line == '\t\t\tbuildPhases = (':
                    in_phases = True
                elif in_phases:
                    if line == '\t\t\t);':
                        in_phases = False
                    else:
                        phases.append(line.split()[0].rstrip(','))
                else:
                    m = re.match(r'^\t\t\tname = (.*);$', line)
                    if m:
                        name = unquote(m.group(1))
                i += 1
            out.append((name, phases))
        i += 1
    return out


def sources_phase(lines, text, targets, name):
    """The id and definition index of the one Sources phase of the native target called name."""
    matches = [phases for n, phases in targets if n == name]
    if len(matches) != 1:
        raise Refusal('%d native targets are named %s, expected 1' % (len(matches), name))
    found = []
    for phase_id in matches[0]:
        di = find_exact(lines, r'^\t\t' + phase_id + r'( /\*.*\*/)? = \{$', 'build phase %s of %s' % (phase_id, name))
        _, isa = object_isa(lines, di + 1)
        if isa == 'PBXSourcesBuildPhase':
            found.append((phase_id, di))
    if len(found) != 1:
        raise Refusal('target %s has %d Sources phases, expected 1' % (name, len(found)))
    phase_id, di = found[0]
    if count_id(text, phase_id) != 2:
        raise Refusal('Sources phase %s of %s occurs %d times, expected 2'
                      % (phase_id, name, count_id(text, phase_id)))
    return phase_id, di


def files_end(lines, di, name):
    """The index of the line closing the files list of the phase defined at di."""
    i = di + 1
    while i < len(lines) and lines[i] not in ('\t\t\tfiles = (', '\t\t};'):
        i += 1
    if i >= len(lines) or lines[i] != '\t\t\tfiles = (':
        raise Refusal('the Sources phase of %s has no files list' % name)
    while i < len(lines) and lines[i] not in ('\t\t\t);', '\t\t};'):
        i += 1
    if i >= len(lines) or lines[i] != '\t\t\t);':
        raise Refusal('the files list of the Sources phase of %s is not closed' % name)
    return i


def move_to_target(text, m_path, from_target, to_target):
    if not m_path.endswith('.m'):
        raise Refusal('expected a .m')
    if from_target == to_target:
        raise Refusal('the from-target and the to-target are the same (%s)' % from_target)
    lines = text.split('\n')
    m_name = os.path.basename(m_path)
    targets = native_targets(lines)
    from_phase, _ = sources_phase(lines, text, targets, from_target)
    to_phase, to_di = sources_phase(lines, text, targets, to_target)

    mi = file_ref_index(lines, m_name)
    m_ref = lines[mi].split()[0].strip()
    m_bfs = build_files(lines, m_ref, m_name)
    in_from, in_to = [], []
    for i, bf, phase, settings in m_bfs:
        if phase != 'Sources':
            raise Refusal('%s has a build file in %s, expected Sources' % (m_name, phase))
        pi, phase_id = phase_entry(lines, bf, m_name, 'Sources')
        if count_id(text, bf) != 2:
            raise Refusal('build file %s of %s occurs %d times, expected 2' % (bf, m_name, count_id(text, bf)))
        if phase_id == from_phase:
            in_from.append((bf, pi, settings))
        elif phase_id == to_phase:
            in_to.append(bf)
    if in_to:
        raise Refusal('%s is already in the Sources phase of %s' % (m_name, to_target))
    if not in_from:
        raise Refusal('%s is not in the Sources phase of %s' % (m_name, from_target))
    if len(in_from) > 1:
        raise Refusal('%s is in the Sources phase of %s %d times, expected once'
                      % (m_name, from_target, len(in_from)))
    bf, pi, settings = in_from[0]
    if settings:
        raise Refusal('the build file of %s in %s has settings (%s); move it by hand or not at all'
                      % (m_name, from_target, settings))
    find_exact(lines, r'^\t\t\t\t' + m_ref + r' /\* ' + re.escape(m_name) + r' \*/,$', 'group child of %s' % m_name)
    if count_id(text, m_ref) != 2 + len(m_bfs):
        raise Refusal('file reference %s of %s occurs %d times, expected %d'
                      % (m_ref, m_name, count_id(text, m_ref), 2 + len(m_bfs)))

    end = files_end(lines, to_di, to_target)
    entry = lines[pi]
    out = lines[:end] + [entry] + lines[end:]
    del out[pi if pi < end else pi + 1]
    return '\n'.join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--project', default=None)
    ap.add_argument('--m', required=True)
    ap.add_argument('--h')
    ap.add_argument('--swift')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--all-targets', action='store_true')
    ap.add_argument('--from-target')
    ap.add_argument('--to-target', '--move-to-target', dest='to_target')
    a = ap.parse_args(argv)
    moving = a.from_target is not None or a.to_target is not None
    if moving:
        if a.from_target is None or a.to_target is None:
            ap.error('a move needs both --from-target and --to-target')
        if a.swift or a.h or a.all_targets:
            ap.error('--swift, --h and --all-targets do not apply to a move')
    elif not a.swift:
        ap.error('--swift is required, or --from-target and --to-target for a move')
    project = a.project or os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)))), 'iTerm2.xcodeproj', 'project.pbxproj')
    try:
        with open(project, encoding='utf-8') as f:
            text = f.read()
    except OSError as e:
        print('cannot read %s: %s' % (project, e), file=sys.stderr)
        return 2
    notes = []
    try:
        if moving:
            new = move_to_target(text, a.m, a.from_target, a.to_target)
        else:
            new = swap(text, a.m, a.h, a.swift, all_targets=a.all_targets, notes=notes)
    except Refusal as e:
        print('refused: %s' % e, file=sys.stderr)
        return 1
    for note in notes:
        print('note: %s' % note, file=sys.stderr)
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
