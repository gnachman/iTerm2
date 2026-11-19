#!/usr/bin/env python3
"""Checks a block of statements that is extracted into a new function, from
Clang's AST.

Part of the Objective-C to Swift migration (docs/swift-migration/large-code.md
section 2.2). pure_move.py checks that the lines of an extract commit moved
unchanged; this tool reports what text cannot show: the control flow that
leaves or enters the block, the variables the block reads and writes and
whether they are used after it, captures, self and ivars, values that depend
on where code is (__func__, __LINE__), macros, and other hazards. It also
compares a finished extraction with the facts of the original block, and the
compiled code of the enclosing function before and after.

The facts come from extraction_facts, a LibTooling program built from
extraction_facts.cpp by build.sh on upstream LLVM 22 (the same LLVM as the code
database). This script never parses C: it only formats facts and pairs them.

Subcommands:

  range PATH:FIRST-LAST [-- CLANG-ARGS...]
      The block of lines FIRST to LAST of PATH, about to be extracted. Reports,
      in categories, everything that must be handled. Each category ends in
      one of three verdicts: "none found", a list, or "unknown: <reason>".

  after (REV | --staged | OLD NEW | --before-file F --after-file F)
        --extract OLDPATH:A-B=NEWPATH:C-D [--allow-added PATH:N[-M]]...
        [--allow-removed PATH:N[-M]]... [-- CLANG-ARGS...]
      A completed extraction, declared exactly as for pure_move.py --extract:
      old lines A-B are the block, new lines C-D are where it now is (inside
      the new helper). OLDPATH and NEWPATH must be the same file. Runs the
      range analysis on the old block, then checks that the helper's
      parameters and results cover the variables that must go in and come
      back, that out-parameters of object type have the ownership of the
      variable they replace, and pairs every exit of the old block with what
      the caller does after the call. Each pairing is "matches a known safe
      pattern" or "needs review". With git revisions it also runs
      pure_move.py's extraction check (through its Python API) and includes
      the result. With --before-file and --after-file the two versions are
      read from those files and PATH names the file they are versions of (for
      the compile command and for includes).

  compiled (same inputs as after) [--clang PATH]
      Compiles the before and after versions at -O2 with the file's compile
      command, extracts the enclosing function's LLVM IR from each, normalizes
      it (see NORMALIZATION) and compares. "identical" is strong evidence that
      the extraction changed nothing; "different" is not proof of a bug; "not
      comparable" when the helper is not inlined into the enclosing function
      (for example an Objective-C method, which is called by message send).

Compile commands: with "-- CLANG-ARGS" the arguments are used as given (a
clang command line without the compiler, naming the main file). Otherwise the
file is looked up in the code database's compile database,
tmp/codedb/compile_commands.jsonl of this checkout or, in a git worktree, of
the main checkout (or --cdb FILE), and the entry's arguments are used with the
module cache replaced by tmp/extraction/modcache. The file is parsed at the
path the command names, with this checkout's contents, so that its includes
and the command's header maps resolve in one tree: in a worktree, headers are
read from the checkout the compile database was captured in. --target picks
the target when several compile the file.

Exit status:
  range:    0 every category was answered; 3 some category is unknown;
            2 an error.
  after:    0 every pairing matches a known safe pattern; 1 something needs
            review; 3 something is unknown; 2 an error.
  compiled: 0 identical; 1 different; 3 not comparable; 2 an error.

Writes only under tmp/extraction/ of the repository (the binary, the module
cache, scratch files that are removed). Python 3 standard library, git, and
the binary. Run with python3 -B.
"""

import argparse
import difflib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import pure_move  # noqa: E402

REQUIRED_LLVM_MAJOR = 22
FACTS_TIMEOUT = 900

NOT_CHECKED = [
    'The number and order of evaluations of the expressions passed as arguments to the new '
    'function (large-code.md section 2.2, "Evaluation count and order").',
    'Manual reference counting: whether an object the new function returns follows the '
    'ownership of the original expression.',
    'Exceptions thrown by calls: any call can throw an Objective-C or C++ exception. The tool '
    'lists explicit throws and the scopes around the range; an exception from a call passes '
    'through the helper to the same handlers unless the helper is declared not to throw.',
    'Liveness is lexical. A variable written in the range is listed as coming back when it is named '
    'later in the function, anywhere in an enclosing loop, after a backward goto, or in a block of a '
    '__block variable; when it is a reference (the write goes to its referent); and when its address '
    'was taken before the range. So the list can hold a variable that does not need to come back. It '
    'can miss one read later only through an alias it does not see: a pointer to it taken inside the '
    'range and stored (listed under captures, not outputs), or a reference held by another object.',
    'Other configurations: facts hold for the one compile command used. Code under a '
    'preprocessor conditional that is not compiled makes the affected categories unknown.',
    'Structured bindings: a range that names one makes the variable categories unknown.',
    '@available and __builtin_available checks in or around the range: a helper that lacks the guard '
    'is caught by the compiler\'s -Wunguarded-availability, not by this tool.',
    'A helper declared noexcept or nothrow: an explicit throw in the block is flagged in after mode; an '
    'exception from a call inside such a helper terminates the program and is not reported.',
    'Writes through a pointer the range receives are visible to the caller in both versions as long '
    'as the pointer itself is passed in; where else that pointer is used is not followed.',
]

NORMALIZATION = [
    'The function is compiled with its compile command, with -O0 replaced by -O2, debug '
    'information, profiling and coverage flags removed, and -fdiscard-value-names added, to '
    'LLVM IR (-S -emit-llvm). The before and after contents are presented at the file\'s own '
    'path through a VFS overlay, so includes and __FILE__ are unchanged.',
    'The enclosing function\'s definition is taken from "define" to its closing brace. When it is '
    'not emitted on its own (a static function inlined into its callers), every function in the '
    'file is compared instead, each normalized and hashed, and the ones that differ are named; '
    'the helper must then be referred to by no function.',
    'Comments, metadata attachments (!dbg, !tbaa, !llvm.loop and the like) and attribute '
    'group references (#N) are removed.',
    'Local values, arguments and basic block labels (all numbered, because of '
    '-fdiscard-value-names) are renumbered in the order they are defined; named types such as '
    '%struct.fd_set keep their names. The incoming [value, label] pairs of each phi instruction are then sorted, '
    'since their order has no meaning.',
    'Each reference to a private or internal global is replaced according to its kind. Compared by '
    'content (its initializer, canonicalized recursively): constants with unnamed_addr (string '
    'literals, switch and lookup tables), globals in the Objective-C runtime\'s sections (CFString '
    'literals in __cfstring, class, superclass, selector and protocol reference slots, method and '
    'class name strings), and global block literals and block descriptors, which the program never '
    'writes and whose addresses it has no guarantee about. Compared by name and content: other '
    'constants (a named static const array or pointer, whose address the program may compare). '
    'Compared by name only: globals the code may write (file statics, static locals, thread-local '
    'variables), so two different statics never compare equal. A static local whose declaration '
    'moved with the block into a C helper (@f.x becomes @helper.x) is renamed back; any other '
    'renaming shows as a difference. Function-name strings (__func__, __FUNCTION__, '
    '__PRETTY_FUNCTION__) are compared by content and tagged, and a difference only in them is '
    'reported as such. External globals (OBJC_IVAR_$_ offsets, OBJC_CLASS_$_ symbols, protocol '
    'references with weak linkage, other files\' globals) keep their names.',
    'Each reference to a private or internal function (a block\'s invoke function, a lambda, a '
    'static function that is not inlined) is replaced by the digest of its own normalized body, '
    'recursively, so a block literal moved into the helper compares equal when its body is equal and '
    'different when it is not. Two different static functions with equal bodies therefore compare '
    'equal, although their addresses differ.',
    'Not normalized: __LINE__ values that moved show as differences, correctly. Profile and coverage '
    'counters are not compared: those flags are removed. Metadata (llvm.used, debug information) is '
    'removed with the attachments.',
]


class ToolError(Exception):
    pass


# ---------------------------------------------------------------- repository and binary

def git_text(repo, args):
    r = subprocess.run(['git', '-C', repo] + args, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def repo_root(start):
    top = git_text(start, ['rev-parse', '--show-toplevel'])
    if not top:
        raise ToolError('not in a git work tree: %s' % start)
    return os.path.realpath(top)


def main_checkout(repo):
    """The main checkout of a git worktree (or repo itself)."""
    common = git_text(repo, ['rev-parse', '--path-format=absolute', '--git-common-dir'])
    if common and os.path.basename(common) == '.git':
        return os.path.dirname(common)
    return repo


def source_digest():
    lines = []
    for name in ('build.sh', 'extraction_facts.cpp'):
        with open(os.path.join(HERE, name), 'rb') as f:
            lines.append('%s  %s\n' % (hashlib.sha256(f.read()).hexdigest(), name))
    return hashlib.sha256(''.join(lines).encode()).hexdigest()


def default_binary(repo):
    return os.path.join(repo, 'tmp', 'extraction', 'bin', 'extraction_facts')


def ensure_binary(path, build=True):
    want = source_digest()
    try:
        out = subprocess.run([path, '--version'], capture_output=True, text=True, timeout=60).stdout
        if out.split()[1:2] == [want]:
            return path
    except (OSError, IndexError, subprocess.TimeoutExpired):
        pass
    if not build:
        raise ToolError('%s is missing or out of date; run %s' % (path, os.path.join(HERE, 'build.sh')))
    r = subprocess.run([os.path.join(HERE, 'build.sh'), path], capture_output=True, text=True)
    if r.returncode != 0:
        raise ToolError('building extraction_facts failed:\n%s%s' % (r.stdout, r.stderr))
    return path


def llvm_clang():
    prefixes = []
    if os.environ.get('CODEDB_LLVM_PREFIX'):
        prefixes.append(os.environ['CODEDB_LLVM_PREFIX'])
    else:
        prefixes += ['/opt/homebrew/opt/llvm@%d' % REQUIRED_LLVM_MAJOR,
                     '/usr/local/opt/llvm@%d' % REQUIRED_LLVM_MAJOR]
    for p in prefixes:
        c = os.path.join(p, 'bin', 'clang')
        if os.access(c, os.X_OK):
            return c
    raise ToolError('no upstream clang %d found (looked in %s); set CODEDB_LLVM_PREFIX or pass --clang'
                    % (REQUIRED_LLVM_MAJOR, ', '.join(prefixes)))


# ---------------------------------------------------------------- compile commands

def find_cdb(repo, explicit):
    if explicit:
        if not os.path.exists(explicit):
            raise ToolError('no compile database at %s' % explicit)
        return explicit
    for root in (repo, main_checkout(repo)):
        p = os.path.join(root, 'tmp', 'codedb', 'compile_commands.jsonl')
        if os.path.exists(p):
            return p
    raise ToolError('no compile database (tmp/codedb/compile_commands.jsonl here or in the main checkout); '
                    'capture one with tools/swift_migration/codedb/capture_compile_commands.sh, or give '
                    '--cdb FILE or -- CLANG-ARGS')


def compile_command(repo, relpath, cdb_path, target=None):
    """(args, main_abs, entry facts) for relpath, from the compile database."""
    entries, folded = [], []
    with open(cdb_path) as f:
        for line in f:
            if '"file"' not in line:
                continue
            e = json.loads(line)
            if e.get('meta') or not e.get('file'):
                continue
            if e['file'] == relpath:
                entries.append(e)
            elif e['file'].lower() == relpath.lower():
                folded.append(e)
    note = ''
    if not entries and folded:
        # The file system is case-insensitive; the build may name the file
        # with different case.
        entries = folded
        relpath = folded[0]['file']
        note = 'matched %s by case-insensitive comparison' % relpath
    if target:
        entries = [e for e in entries if e.get('target') == target]
    if not entries:
        raise ToolError('%s has no entry for %s%s' % (cdb_path, relpath, ' in target ' + target if target else ''))
    entries.sort(key=lambda e: (e.get('variant') != 'Variant-NoSanitizers', e.get('target', '')))
    e = entries[0]
    main_abs = None
    args = []
    for a in e['arguments']:
        if a.startswith('-fmodules-cache-path='):
            a = '-fmodules-cache-path=' + os.path.join(repo, 'tmp', 'extraction', 'modcache')
        elif main_abs is None and os.path.isabs(a) and a.lower().endswith('/' + relpath.lower()):
            main_abs = a
        args.append(a)
    if main_abs is None:
        raise ToolError('the compile command for %s does not name the file' % relpath)
    others = sorted(set(x.get('target', '?') for x in entries[1:]))
    # The file is parsed at the path the command names (in a worktree, the main
    # checkout's path), so that its own includes and the command's header maps
    # resolve in the same tree; the caller supplies this checkout's bytes.
    return args, main_abs, {'target': e.get('target'), 'configuration': e.get('configuration'),
                            'arch': e.get('arch'), 'other_targets': others,
                            'directory': e.get('directory') or os.path.dirname(main_abs), 'note': note,
            'cdb': cdb_path, 'cdb_file': relpath}


def clang_errors(facts, limit=3):
    """The first errors clang printed, each with the source line it showed."""
    lines = (facts.get('stderr') or '').splitlines()
    out = []
    for k, line in enumerate(lines):
        if ' error: ' in line or line.startswith('error: ') or ' fatal error: ' in line:
            snippet = lines[k + 1].strip() if k + 1 < len(lines) else ''
            out.append(line.strip() + (' [' + snippet + ']' if snippet else ''))
            if len(out) >= limit:
                break
    return out


def configuration_text(args, triple, entry):
    defines = []
    for i, a in enumerate(args):
        if a == '-D' and i + 1 < len(args):
            defines.append('-D' + args[i + 1])
        elif a.startswith('-D') and len(a) > 2:
            defines.append(a)
    parts = [triple or '?']
    if entry and entry.get('note'):
        parts.append(entry['note'])
    if entry and entry.get('target'):
        parts.append('target %s' % entry['target'])
    if entry and entry.get('configuration'):
        parts.append(entry['configuration'])
    if defines:
        parts.append(' '.join(defines))
    if entry and entry.get('cdb'):
        parts.append('compile command from %s (entry for %s)' % (entry['cdb'], entry.get('cdb_file')))
    return ', '.join(parts)


def run_facts(binary, main_abs, args, mode_args, contents=None, cwd=None):
    """Runs extraction_facts. `cwd` is the compile command's directory: relative
    paths in the command (such as -I ThirdParty) are relative to it."""
    cmd = [binary, '--main', main_abs]
    if contents is not None:
        cmd += ['--contents', contents]
    cmd += mode_args + ['--'] + args
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=FACTS_TIMEOUT, start_new_session=True,
                           cwd=cwd)
    except subprocess.TimeoutExpired:
        raise ToolError('extraction_facts timed out on %s' % main_abs)
    if r.returncode != 0:
        raise ToolError('extraction_facts failed on %s (exit %d):\n%s' % (main_abs, r.returncode, r.stderr[-4000:]))
    try:
        facts = json.loads(r.stdout)
    except ValueError:
        raise ToolError('extraction_facts printed no JSON for %s:\n%s' % (main_abs, r.stderr[-4000:]))
    facts['stderr'] = r.stderr[-4000:]
    return facts


# ---------------------------------------------------------------- range analysis

CHANGES_MEANING = ('return', 'break', 'continue', 'goto', 'co_return', 'rethrow', 'indirect-goto')
WRITE_USES = ('write', 'read-write', 'address-taken', 'by-reference')
READ_USES = ('read', 'read-write', 'address-taken', 'by-reference')

CATEGORIES = [
    ('exits', 'Control flow leaving the range'),
    ('entries', 'Control flow entering the range'),
    ('scopes', 'Scopes around and inside the range'),
    ('inputs', 'Variables that must be passed in'),
    ('outputs', 'Variables that must come back'),
    ('declared', 'Variables declared in the range and used after it'),
    ('captures', 'Captures, references and addresses'),
    ('ownership', 'Ownership of object variables crossing the boundary'),
    ('self', 'self, _cmd, super, ivars and this'),
    ('globals', 'Globals, file-scope statics and static data members'),
    ('positional', 'Values that depend on where the code is'),
    ('macros', 'Macro expansions in the range'),
    ('hazards', 'Other hazards'),
]


def lines_text(nums):
    nums = sorted(set(nums))
    return ', '.join(str(n) for n in nums)


def type_text(v):
    t = v.get('type', '?')
    if v.get('lifetime') and v.get('lifetime') not in t:
        t += ' ' + v['lifetime']
    if v.get('lifetime') and not v.get('lifetime_written'):
        t += ' (implicit)'
    if v.get('block_storage'):
        t = '__block ' + t
    return t


def macro_text(x):
    if not x.get('macros'):
        return ''
    chain = ' > '.join(x['macros'])
    return ' (in the %s of macro %s)' % ('body' if x.get('in_macro_body') else 'argument', chain)


def exit_text(x):
    k = x['kind']
    where = 'line %d: %s%s' % (x['line'], k, macro_text(x))
    if k == 'return' or k == 'co_return':
        tgt = 'leaves the %s%s' % (x['target'], ' at line %d' % x['target_line'] if x.get('target_line') else '')
        meaning = 'after extraction it leaves only the helper, and the caller carries on'
    elif k in ('break', 'continue'):
        tgt = 'binds to the %s at line %s' % (x['target'], x.get('target_line', '?'))
        meaning = 'after extraction it has no loop or switch to bind to in the helper'
    elif k == 'goto':
        tgt = 'jumps to %s at line %s' % (x['target'], x.get('target_line', '?'))
        meaning = 'after extraction the label is in another function'
    elif k == 'rethrow':
        tgt = x['target'] + (' at line %s' % x['target_line'] if x.get('target_line') else '')
        meaning = 'after extraction it is not inside that handler'
    elif k == 'throw':
        tgt = x['target'] + (' at line %s' % x['target_line'] if x.get('target_line') else '')
        meaning = 'passes through the helper to the same handlers, unless the helper is declared not to throw'
    elif k == 'noreturn-call':
        tgt = 'calls %s, which does not return' % (x.get('callee') or 'a noreturn function')
        meaning = 'unchanged by extraction'
    else:
        tgt = x.get('target', '?')
        meaning = 'cannot be determined'
    s = '%s %s, outside the range; %s' % (where, tgt, meaning)
    crossed = [c for c in x.get('crosses', []) if not c.get('inside')]
    if crossed and k in CHANGES_MEANING:
        s += '; on the way out it leaves ' + ', '.join('%s at line %d' % (c['kind'], c['line']) for c in crossed)
    return s


def category(items=None, unknown=None, extra=None):
    c = {'items': items or [], 'unknown': unknown or []}
    if c['unknown']:
        c['verdict'] = 'unknown'
    elif c['items']:
        c['verdict'] = 'list'
    else:
        c['verdict'] = 'none'
    if extra:
        c.update(extra)
    return c


def analyze_range(facts, config):
    """The categorized report for range-mode facts."""
    rep = {'tool': 'extract_check', 'mode': 'range', 'configuration': config,
           'function': facts.get('function'), 'selection': facts.get('selection'),
           'errors': facts.get('errors', 0), 'categories': {}}
    if facts.get('error'):
        raise ToolError(facts['error'])
    sel = facts.get('selection') or {}
    everywhere = []
    if facts.get('errors'):
        everywhere.append('clang reported %d error(s) parsing the file with this command: the AST may be '
                          'incomplete (%s)' % (facts['errors'], '; '.join(clang_errors(facts)) or 'no text captured'))
    if not sel.get('aligned'):
        everywhere.append('the range does not align with statement boundaries: %s' % sel.get('reason', '?'))
    skipped = facts.get('skipped_in_range') or []
    if skipped:
        everywhere.append('lines %s in the range are not compiled in this configuration (%s); what they '
                          'would contribute is not seen' % (
                              ', '.join('%d-%d' % (s['first'], s['last']) for s in skipped), config))
    if not sel.get('aligned'):
        for key, _ in CATEGORIES:
            rep['categories'][key] = category(unknown=list(everywhere))
        rep['exit_code'] = 3
        return rep

    fn = facts.get('function') or {}
    closure = fn.get('closure')
    exits = facts.get('exits', [])
    cats = rep['categories']

    # Exits.
    external = [x for x in exits if not x.get('target_inside')]
    internal = [x for x in exits if x.get('target_inside')]
    unk = []
    if facts.get('function_has_indirect_goto'):
        unk.append('the function has a computed goto (goto *p), whose target cannot be determined')
    cats['exits'] = category([exit_text(x) for x in external], everywhere + unk, {
        'internal': ['line %d: %s%s binds to the %s at line %s inside the range (unchanged)'
                     % (x['line'], x['kind'], macro_text(x), x['target'], x.get('target_line', '?'))
                     for x in internal],
        'facts': exits})

    # Entries.
    ent = []
    for e in facts.get('entries', []):
        if e['kind'] == 'goto':
            ent.append('line %d: label %s is the target of the goto at line %d, outside the range'
                       % (e['line'], e.get('label', '?'), e['from_line']))
        else:
            ent.append('line %d: %s label of the switch at line %d, outside the range'
                       % (e['line'], e['kind'], e['from_line']))
    cats['entries'] = category(ent, everywhere + unk)

    # Scopes.
    sc = ['encloses the range: %s at line %d%s' % (s['kind'], s['line'],
                                                    ' (outside the enclosing block)' if s.get('outside_function') else '')
          for s in facts.get('scopes_enclosing', [])]
    sc += ['inside the range: %s at line %d' % (s['kind'], s['line']) for s in facts.get('scopes_inside', [])]
    if closure:
        sc.insert(0, 'the range is inside the %s at line %d: that %s is the function the helper is extracted from'
                  % (closure['kind'], closure['line'], closure['kind']))
    cats['scopes'] = category(sc, list(everywhere))

    # Variables.
    after_unknown = []
    sk_after = facts.get('skipped_after_range') or []
    if sk_after:
        after_unknown.append('lines %s after the range are not compiled in this configuration (%s): uses there '
                             'are not seen' % (', '.join('%d-%d' % (s['first'], s['last']) for s in sk_after), config))
    if facts.get('function_has_indirect_goto'):
        after_unknown.append('the function has a computed goto: code after the range may jump back')
    inputs, outputs, not_needed, caps, own, hz = [], [], [], [], [], []
    not_needed_in = []
    in_unknown, out_unknown, cap_unknown = [], [], []
    var_rows = []
    for v in facts.get('variables', []):
        if v['kind'] == 'self':
            continue
        uses = v['uses']
        kinds = set(u['use'] for u in uses)
        reads = bool(kinds & set(READ_USES)) or any(u.get('capture') in ('block-copy', 'lambda-copy') for u in uses)
        writes = bool(kinds & set(WRITE_USES))
        unknown_uses = [u for u in uses if u['use'] == 'unknown']
        overwritten = bool(v.get('first_use_overwrites')) and not unknown_uses and reads
        reads = reads and not overwritten
        after = [u for u in v['uses_after'] if u['use'] != 'unevaluated']
        if v.get('is_reference') and writes:
            # A write through a reference goes to something outside the block.
            after.append({'use': 'write', 'line': min(u['line'] for u in uses if u['use'] in WRITE_USES),
                          'reason': 'reference'})
        early_alias = [n for n in v.get('address_taken_outside_range') or [] if n < (rep['selection'] or {}).get('first', 0)]
        if writes and early_alias and not after:
            after.append({'use': 'read', 'line': early_alias[0], 'reason': 'alias'})
        if v.get('loop_carried_line') and reads and writes:
            # The range reads it again in the next iteration of the loop.
            after.append({'use': 'read', 'line': min(u['line'] for u in uses if u['use'] in READ_USES)
                          if any(u['use'] in READ_USES for u in uses) else v['decl_line'],
                          'reason': 'self-loop', 'loop_line': v['loop_carried_line']})
        label = '%s (%s, %s declared at line %d)' % (v['name'], type_text(v), v['kind'], v['decl_line'])
        detail = '; '.join('%s at line %d%s' % (u['use'], u['line'], ' (' + u['why'] + ')' if u.get('why') else '')
                           for u in uses)
        row = {'name': v['name'], 'type': v.get('type'), 'kind': v['kind'], 'decl_line': v['decl_line'],
               'reads': reads, 'writes': writes, 'unknown': bool(unknown_uses), 'used_after': bool(after),
               'definite': definitely_assigned(v, uses, exits),
               'lifetime': v.get('lifetime'), 'lifetime_written': v.get('lifetime_written'),
               'is_object_pointer': v.get('is_object_pointer'), 'block_storage': v.get('block_storage'),
               'is_reference': v.get('is_reference')}
        var_rows.append(row)
        if v.get('static_local'):
            hz.append('%s: a static local declared outside the range; a helper cannot name it, so it must be '
                      'moved to file scope or passed by pointer' % label)
        if overwritten:
            not_needed_in.append('%s: its first use in the range is an assignment that overwrites it (%s), so '
                                 'the value it had before is not read' % (label, detail))
        elif reads or unknown_uses:
            inputs.append('%s: %s' % (label, detail))
        if unknown_uses:
            in_unknown.append('%s: use not classified at line %s (%s)' % (
                v['name'], lines_text(u['line'] for u in unknown_uses),
                '; '.join(sorted(set(u.get('why', '') for u in unknown_uses)))))
        if writes or unknown_uses:
            if after:
                reasons = []
                for u in after:
                    r = {'after': 'after the range', 'loop': 'in a later iteration of the enclosing loop',
                         'backward-goto': 'reached again by a backward goto', 'block': 'in a block that may run later',
                         'self-loop': 'by the range itself in the next iteration of the loop at line %s' % u.get('loop_line'),
                         'reference': 'through a reference: the referent is modified; it must be passed by reference '
                                      'or pointer',
                         'alias': 'may be read after the block through a pointer taken at line %d' % u['line']}[u['reason']]
                    if u['reason'] == 'reference':
                        reasons.append(r)
                    else:
                        reasons.append('%s at line %d (%s)' % (u['use'], u['line'], r))
                only_writes = all(u['use'] == 'write' and u['reason'] in ('after', 'loop', 'backward-goto', 'block')
                                  for u in after)
                outputs.append('%s: %s in the range (%s); %s%s' % (
                    label, 'written' if writes else 'possibly written (a use is not classified)',
                    ', '.join('%s at line %d' % (u['use'], u['line']) for u in uses if u['use'] in WRITE_USES + ('unknown',)),
                    ('written ' if after[0]['reason'] == 'reference' else 'used ') + '; '.join(reasons),
                    ' (every later use is a write: it may not need to come back; review)' if only_writes else ''))
            elif v.get('declared_outside_closure') and (v.get('block_storage') or any(u.get('capture') == 'lambda-byref' for u in uses)):
                out_unknown.append('%s: written in the range and declared outside the enclosing %s; uses in the '
                                   'enclosing function are not examined' % (v['name'], closure['kind'] if closure else 'block'))
            else:
                not_needed.append('%s: %s in the range, not used after it' % (
                    label, 'written' if writes else 'used in a way not classified'))
            if unknown_uses:
                out_unknown.append('%s: use not classified at line %s' % (
                    v['name'], lines_text(u['line'] for u in unknown_uses)))
        for u in uses:
            if u.get('capture') in ('block-byref', 'lambda-byref'):
                caps.append('%s: captured by reference by the %s at line %d (%s): in a helper it would capture '
                            'the helper\'s copy, and a %s that outlives the call would see a dead variable'
                            % (v['name'], 'block' if u['capture'].startswith('block') else 'lambda',
                               u.get('closure_line', 0), u['capture'],
                               'block' if u['capture'].startswith('block') else 'lambda'))
            elif u.get('capture') in ('block-copy', 'lambda-copy'):
                caps.append('%s: captured by copy by the %s at line %d: the value at the time the closure is created '
                            '(unchanged by extraction if the value passed in is the same)'
                            % (v['name'], 'block' if u['capture'].startswith('block') else 'lambda', u.get('closure_line', 0)))
            elif u.get('capture') == 'lambda-unknown':
                cap_unknown.append('%s: captured by the lambda at line %d, capture kind not found' % (v['name'], u.get('closure_line', 0)))
            if u.get('through') in WRITE_USES:
                caps.append('%s: writes through the pointer %s at line %d: the object it points to is modified; passing '
                            '%s (the pointer, by value) keeps that visible to the caller' % (
                                v['name'], v['name'], u['line'], v['name']))
            if u['use'] in ('address-taken', 'by-reference'):
                caps.append('%s: %s at line %d%s: in a helper this would be the address of the helper\'s copy, '
                            'unless the variable is passed by pointer' % (
                                v['name'], 'address taken' if u['use'] == 'address-taken' else 'bound to a reference',
                                u['line'], ' (' + u['why'] + ')' if u.get('why') else ''))
        if v.get('block_storage'):
            caps.append('%s: a __block variable; passing it to a helper by value or by pointer does not keep the '
                        'sharing with blocks that captured it' % v['name'])
        if v.get('address_taken_outside_range'):
            caps.append('%s: address taken outside the range at line %s: a pointer elsewhere sees the caller\'s '
                        'variable, not a helper\'s copy, until the value is written back'
                        % (v['name'], lines_text(v['address_taken_outside_range'])))
        if v.get('is_object_pointer'):
            if not fn.get('objc'):
                own.append('%s: a block pointer in C: no automatic reference counting; Block_copy and Block_release '
                           'are explicit in the code' % v['name'])
            elif fn.get('arc'):
                own.append('%s: %s%s' % (v['name'], v.get('lifetime') or 'no ownership',
                                          '' if v.get('lifetime_written') else ' (the default, not written)'))
                if v.get('lifetime') == '__weak':
                    own.append('%s: __weak: passed as a parameter it is loaded once, at the call; the block loads '
                               'it at each use' % v['name'])
            else:
                own.append('%s: manual reference counting; retains and releases are explicit in the code' % v['name'])
        if v.get('vla'):
            hz.append('%s: a variable-length array; a helper needs its length' % label)
        if v.get('va_list'):
            hz.append('%s: a va_list; it refers to the variadic arguments of the function' % label)
        if v.get('nontrivial_copy') and reads:
            hz.append('%s: passing it by value runs its copy constructor; pass it by reference' % label)
    bindings = [h for h in facts.get('hazards', []) if h['kind'] == 'structured-binding']
    for h in bindings:
        in_unknown.append('line %d: %s' % (h['line'], h['detail']))
        out_unknown.append('line %d: %s' % (h['line'], h['detail']))
    cats['inputs'] = category(inputs, everywhere + in_unknown, {'not_needed': not_needed_in})
    cats['outputs'] = category(outputs, everywhere + after_unknown + out_unknown, {'not_needed': not_needed})
    cats['captures'] = category(list(dict.fromkeys(caps)), everywhere + cap_unknown)
    rep['variables'] = var_rows

    decl = []
    for d in facts.get('declared_inside', []):
        label = '%s (%s) declared at line %d' % (d['name'], type_text(d), d['decl_line'])
        if d.get('uses_after'):
            decl.append('%s: used after the range at line %s' % (label, lines_text(u['line'] for u in d['uses_after'])))
        if d.get('nontrivial_destructor') and d.get('top_level'):
            hz.append('%s: its destructor runs when the helper returns instead of at the end of the enclosing scope' % label)
        if d.get('cleanup_attr') and d.get('top_level'):
            hz.append('%s: __attribute__((cleanup)) runs when the helper returns instead of at the end of the '
                      'enclosing scope' % label)
        if d.get('precise_lifetime') and d.get('top_level'):
            hz.append('%s: objc_precise_lifetime: released when the helper returns instead of at the end of the '
                      'enclosing scope' % label)
        if d.get('vla'):
            hz.append('%s: a variable-length array declared in the range' % label)
        if d.get('static_local'):
            hz.append('%s: a static local; moved into the helper it is still one variable' % label)
    cats['declared'] = category(decl, everywhere + after_unknown)
    cats['ownership'] = category(own, list(everywhere))

    # self and friends.
    selfs = []
    for s in facts.get('self_uses', []):
        if s['kind'] == 'self' and s['use'] in WRITE_USES:
            selfs.append('line %d: self (%s): a helper assigns only its own self; the new value must come back (the '
                         'helper returns it and the caller assigns it to self)' % (s['line'], s['use']))
            cats['outputs']['items'].append('self: assigned at line %d; it must come back' % s['line'])
            if cats['outputs']['verdict'] == 'none':
                cats['outputs']['verdict'] = 'list'
            continue
        if s['kind'] == 'self':
            selfs.append('line %d: self (%s): unchanged in a method of the same class; must be passed to a C function' % (s['line'], s['use']))
        elif s['kind'] == '_cmd':
            selfs.append('line %d: _cmd: its value is the selector of the method it is in; it changes in any helper' % s['line'])
        elif s['kind'] == 'super':
            selfs.append('line %d: super (%s): the superclass of the class whose method it is in; a C function cannot use it' % (s['line'], s['name']))
        elif s['kind'] == 'ivar':
            selfs.append('line %d: ivar %s (%s) through the implicit self' % (s['line'], s['name'], s['use']))
        elif s['kind'] == 'this':
            selfs.append('line %d: this (%s)' % (s['line'], s['name']))
    cats['self'] = category(selfs, list(everywhere))

    glob = []
    for g in facts.get('globals', []):
        glob.append('%s (%s, %s declared at %s:%d): %s: unaffected while the helper stays in this file; it must be '
                    'made visible if the helper moves to Swift or to another file' % (
                        g['name'], type_text(g), g['kind'], os.path.basename(g.get('decl_file') or '?'),
                        g.get('decl_line', 0), '; '.join('%s at line %d' % (u['use'], u['line']) for u in g['uses'])))
    cats['globals'] = category(glob, list(everywhere))

    pos = []
    for p in facts.get('positional', []):
        via = ' via macro %s' % ' > '.join(p['macros']) if p.get('macros') else ''
        k = p['kind']
        if k in ('__FILE__', '__FILE_NAME__', '__BASE_FILE__'):
            note = 'unchanged when the helper is in the same file'
        elif k == '__COUNTER__':
            note = ('its value depends on how many expansions come before it in the file; harmless when it only '
                    'makes unique names, as in MIN and MAX')
        elif k == '__LINE__' or k.startswith('__builtin_LINE') or k.startswith('__builtin_COLUMN'):
            note = 'changes when the line moves'
        else:
            note = 'names the function it is in: it changes in a helper'
        pos.append('line %d: %s%s: %s (a note, not a failure)' % (p['line'], k, via, note))
    cats['positional'] = category(pos, list(everywhere))

    exit_macros = {}
    for x in exits:
        for m in x.get('macros') or []:
            exit_macros.setdefault(m, []).append(x)
    mac = []
    for m in facts.get('macros', []):
        s = 'line %d: %s (defined at %s:%d)' % (m['line'], m['name'], os.path.basename(m['def_file'] or '?'), m['def_line'])
        hidden = [x for x in exit_macros.get(m['name'], []) if x['line'] == m['line']]
        if hidden:
            s += ': contains %s' % ', '.join('%s (%s)' % (x['kind'], 'inside the range' if x.get('target_inside')
                                                         else 'leaves the range') for x in hidden)
        mac.append(s)
    for c in facts.get('conditionals_in_range', []):
        mac.append('line %d: %s: the code compiled here depends on the configuration (%s)' % (c['line'], c['kind'], config))
    cats['macros'] = category(mac, list(everywhere))

    for h in facts.get('hazards', []):
        hz.append('line %d: %s: %s' % (h['line'], h['kind'], h['detail']))
    cats['hazards'] = category(list(dict.fromkeys(hz)), list(everywhere))

    rep['exit_code'] = 3 if any(c['verdict'] == 'unknown' for c in cats.values()) else 0
    return rep


def definitely_assigned(v, uses, exits):
    """Whether the block assigns the variable on every path before reading it:
    its first use is an unconditional top-level assignment that names it once
    (the facts' first_use_overwrites), and no exit of the block comes before
    that assignment. Conservative: anything else is not definite."""
    if not v.get('first_use_overwrites') or not uses or any(u['use'] == 'unknown' for u in uses):
        return False
    first = min(u['line'] for u in uses)
    return not any(not x.get('target_inside') and x['line'] < first for x in exits)


def verdict_text(c):
    if c['verdict'] == 'none':
        return 'none found'
    if c['verdict'] == 'list':
        return 'a list of %d' % len(c['items'])
    return 'unknown: ' + '; '.join(c['unknown'])


def format_range(rep):
    out = []
    fn = rep.get('function') or {}
    sel = rep.get('selection') or {}
    out.append('Extraction check of lines %s-%s in %s' % (sel.get('first'), sel.get('last'), fn.get('name', '?')))
    out.append('Configuration: %s' % rep.get('configuration'))
    out.append('How far to rely on this: reliable for exits, variables that must come back, and writes to self and '
               'ivars in ordinary Objective-C; read the categories marked unknown.')
    if fn:
        out.append('Function: %s, lines %s-%s, %s%s' % (fn.get('name'), fn.get('line'), fn.get('end_line'),
                                                       'ARC' if fn.get('arc') else 'not ARC' if fn.get('objc') else 'C',
                                                       ', C++' if fn.get('cplusplus') else ''))
    if sel.get('statements'):
        out.append('Statements in the range: %d (lines %d-%d)%s' % (
            len(sel['statements']), sel['statements'][0]['line'], sel['statements'][-1]['end_line'],
            '; falling off the end of the range ends the function' if sel.get('tail') else ''))
    for key, title in CATEGORIES:
        c = rep['categories'][key]
        out.append('')
        out.append('%s:' % title)
        for i in c['items']:
            out.append('  - ' + i)
        for i in c.get('internal', []):
            out.append('  . ' + i)
        for i in c.get('not_needed', []):
            out.append('  . ' + i)
        out.append('  Verdict: ' + verdict_text(c))
    out.append('')
    out.append('Not checked by this tool:')
    for n in NOT_CHECKED:
        out.append('  - ' + n)
    return '\n'.join(out) + '\n'


# ---------------------------------------------------------------- after mode

class Inputs(object):
    """The before and after contents of the file an extraction changed."""

    def __init__(self, path, before, after, a, b, c, d, pure=None):
        self.path, self.before, self.after = path, before, after
        self.a, self.b, self.c, self.d = a, b, c, d
        self.pure = pure


def read_inputs(args, repo):
    if len(args.extract) != 1:
        raise ToolError('give exactly one --extract OLDPATH:A-B=NEWPATH:C-D')
    try:
        op, a, b, np_, c, d = pure_move.parse_extraction(args.extract[0])
    except ValueError as e:
        raise ToolError(str(e))
    if op != np_:
        raise ToolError('the helper must be in the same file as the block (OLDPATH and NEWPATH differ)')
    if args.before_file or args.after_file:
        if not (args.before_file and args.after_file) or args.revs or args.staged:
            raise ToolError('--before-file and --after-file go together, without revisions')
        try:
            with open(args.before_file, 'rb') as f:
                before = f.read()
            with open(args.after_file, 'rb') as f:
                after = f.read()
        except OSError as e:
            raise ToolError('cannot read %s: %s' % (e.filename, e.strerror))
        try:
            allow_added = [pure_move.parse_declaration(x) for x in args.allow_added]
            allow_removed = [pure_move.parse_declaration(x) for x in args.allow_removed]
        except ValueError as e:
            raise ToolError(str(e))
        pure = pure_move_contents(op, before, after, (a, b, c, d), allow_added, allow_removed)
        return Inputs(os.path.abspath(op), before, after, a, b, c, d, pure)
    if args.staged:
        mode = 'staged'
    elif len(args.revs) == 1:
        mode = 'commit'
    elif len(args.revs) == 2:
        mode = 'range'
    else:
        raise ToolError('give one revision, two revisions, --staged, or --before-file and --after-file')
    git = pure_move.Git(repo)
    try:
        allow_added = [pure_move.parse_declaration(s) for s in args.allow_added]
        allow_removed = [pure_move.parse_declaration(s) for s in args.allow_removed]
        extractions = [pure_move.parse_extraction(s) for s in args.extract]
        old, new = pure_move.resolve(git, mode, args.revs)
        pure = pure_move.check_extract(git, mode, args.revs, extractions, allow_added, allow_removed)
        before = git.run(['cat-file', 'blob', '%s:%s' % (old, op)])
        after = git.run(['cat-file', 'blob', (':%s' % np_) if new == 'index' else '%s:%s' % (new, np_)])
    except (pure_move.ToolError, ValueError) as e:
        raise ToolError('pure_move: %s' % e)
    summary = {'pure_move': pure['pure_move'], 'counts': pure['counts'],
               'declared_added_lines': [(x['line'], x['text']) for x in pure['declared_added'] if x['path'] == np_],
               'declared_removed_lines': [(x['line'], x['text']) for x in pure['declared_removed'] if x['path'] == op]}
    return Inputs(os.path.join(repo, op), before, after, a, b, c, d, summary)


def pure_move_contents(path, before, after, rng, allow_added, allow_removed):
    """pure_move.py's extraction check (EXTRACT_RULES) on two contents of one
    file, with its own functions: the block must match its destination line by
    line ignoring indentation, and everything outside the block and the declared
    lines must be unchanged."""
    a, b, c, d = rng
    old, new = pure_move.split_lines(before), pure_move.split_lines(after)
    for label, lines, specs in (('--allow-removed', old, allow_removed), ('--allow-added', new, allow_added)):
        for p, s0, e0 in specs:
            if p != path:
                raise ToolError('%s %s:%d-%d names another file' % (label, p, s0, e0))
            if e0 > len(lines):
                raise ToolError('%s %s:%d-%d is outside the file' % (label, p, s0, e0))
    if b > len(old) or d > len(new):
        raise ToolError('the --extract ranges are outside the files')
    src, dst = old[a - 1:b], new[c - 1:d]
    mismatches = sum(1 for x, y in zip(src, dst) if pure_move.normalize(x) != pure_move.normalize(y))
    gone_old = set(range(a, b + 1)) | set(n for _, s0, e0 in allow_removed for n in range(s0, e0 + 1))
    gone_new = set(range(c, d + 1)) | set(n for _, s0, e0 in allow_added for n in range(s0, e0 + 1))
    r, ad = pure_move.diff_remainders(old, pure_move.kept(len(old), gone_old), new, pure_move.kept(len(new), gone_new))
    r, ad = list(r), list(ad)
    pure = not (mismatches or len(src) != len(dst) or r or ad)
    declared_added = sorted(gone_new - set(range(c, d + 1)))
    declared_removed = sorted(gone_old - set(range(a, b + 1)))
    return {'pure_move': pure, 'mode': 'contents',
            'declared_added_lines': [(n, new[n - 1].decode('utf-8', 'replace')) for n in declared_added],
            'declared_removed_lines': [(n, old[n - 1].decode('utf-8', 'replace')) for n in declared_removed],
            'counts': {'mismatches': mismatches, 'length_mismatches': int(len(src) != len(dst)),
                       'unaccounted_removed': len(r), 'unaccounted_added': len(ad),
                       'declared_removed': len(gone_old) - (b - a + 1), 'declared_added': len(gone_new) - (d - c + 1)}}


class Work(object):
    def __init__(self, repo):
        base = os.path.join(repo, 'tmp', 'extraction', 'work')
        os.makedirs(base, exist_ok=True)
        self.dir = tempfile.mkdtemp(dir=base)

    def write(self, name, data):
        p = os.path.join(self.dir, name)
        with open(p, 'wb') as f:
            f.write(data)
        return p

    def close(self):
        shutil.rmtree(self.dir, ignore_errors=True)


def setup(args):
    repo = repo_root(args.repo)
    binary = ensure_binary(args.binary or default_binary(repo), build=not args.no_build)
    return repo, binary


def command_for(args, repo, path):
    """The compile command for `path`, an absolute path."""
    main_abs = os.path.realpath(path)
    if args.clang_args:
        cargs = list(args.clang_args)
        if not any(os.path.realpath(x) == main_abs for x in cargs if not x.startswith('-')):
            raise ToolError('the clang arguments do not name %s' % main_abs)
        return cargs, main_abs, None
    rel = os.path.relpath(main_abs, repo)
    if rel.startswith('..'):
        raise ToolError('%s is not inside the repository %s' % (main_abs, repo))
    return compile_command(repo, rel, find_cdb(repo, args.cdb), args.target)


def same_type(a, b):
    def norm(t):
        t = (t or '').replace('__strong', '').replace('__autoreleasing', '').replace('__unsafe_unretained', '')
        t = re.sub(r'\b_Nonnull\b|\b_Nullable\b|\b_Null_unspecified\b|\bnonnull\b|\bnullable\b', '', t)
        t = t.replace('&', ' ')
        return ' '.join(t.split()).replace(' *', '*')
    return norm(a) == norm(b)


def taken(value, ctx):
    """Whether the call's if-statement branch is taken when the helper returns value."""
    negated = ctx.get('negated', False)
    cmp = ctx.get('compare')
    if cmp:
        m = re.match(r'^(==|!=) (.+)$', cmp)
        try:
            other = int(m.group(2).replace('YES', '1').replace('NO', '0').replace('true', '1').replace('false', '0'))
        except (ValueError, AttributeError):
            return None
        r = (value == other) if m.group(1) == '==' else (value != other)
    else:
        r = value != 0
    return r != negated


def analyze_after(before, helper, caller, inp, config):
    rep = {'tool': 'extract_check', 'mode': 'after', 'configuration': config,
           'block': {'path': inp.path, 'first': inp.a, 'last': inp.b},
           'helper_lines': {'first': inp.c, 'last': inp.d}, 'pure_move': inp.pure,
           'data': [], 'exits': [], 'other': [], 'unknown': [], 'patterns': []}
    rng = analyze_range(before, config)
    rep['range'] = rng
    for key, _ in CATEGORIES:
        c = rng['categories'][key]
        if c['verdict'] == 'unknown':
            rep['unknown'].append('%s: %s' % (key, '; '.join(c['unknown'])))
    if helper.get('error'):
        raise ToolError('after version: %s' % helper['error'])
    if caller.get('error'):
        raise ToolError('after version: %s' % caller['error'])
    h = helper['function']
    if not (h['body_line'] <= inp.c and inp.d <= h['body_end_line']):
        raise ToolError('new lines %d-%d are not inside one function body (the function at line %d spans %d-%d)'
                        % (inp.c, inp.d, h['line'], h['body_line'], h['body_end_line']))
    fn = before['function']
    if h['name'] == fn['name']:
        raise ToolError('new lines %d-%d are in %s itself, not in a new helper' % (inp.c, inp.d, h['name']))
    rep['helper'] = {'name': h['name'], 'kind': h['kind'], 'params': [p['name'] for p in h.get('params', [])],
                     'return_type': h.get('return_type')}
    calls = caller.get('calls', [])
    if len(calls) != 1:
        rep['unknown'].append('the caller %s calls %s %d times; one call is expected' % (fn['name'], h['name'], len(calls)))
    call = calls[0] if calls else None
    rep['call'] = call
    params = dict((p['name'], p) for p in h.get('params', []))
    args_by_index = call['args'] if call else []
    hparams = h.get('params', [])

    def arg_for(name):
        for i, p in enumerate(hparams):
            if p['name'] == name and i < len(args_by_index):
                return args_by_index[i]
        return None

    def add(kind, subject, status, text):
        rep['data'].append({'kind': kind, 'subject': subject, 'status': status, 'text': text})

    rows = dict((r['name'], r) for r in rng.get('variables', []))
    used = set()
    method_helper = h['kind'] == 'objc-method' and fn.get('kind') == 'objc-method' and h.get('class') == fn.get('class')
    for name, r in rows.items():
        must_in = r['reads'] or r['unknown']
        must_out = (r['writes'] or r['unknown']) and r['used_after']
        p = params.get(name)
        a = arg_for(name)
        if p:
            used.add(name)
        if must_out:
            ok_ret = call and call.get('context') in ('assigned', 'initializes') and call.get('assigned_to') == name
            if p and (p.get('is_pointer') or p.get('is_reference')):
                if p.get('is_pointer') and not (a and a.get('kind') == 'address-of' and a.get('var') == name):
                    add('out', name, 'needs review', '%s: the helper takes a pointer %s, but the call passes %s, not &%s'
                        % (name, p['type'], a['text'] if a else 'nothing', name))
                elif p.get('is_reference') and not (a and a.get('kind') == 'var' and a.get('var') == name):
                    add('out', name, 'needs review', '%s: the helper takes a reference, but the call passes %s'
                        % (name, a['text'] if a else 'nothing'))
                elif not same_type(p.get('pointee_type'), r['type']):
                    add('out', name, 'needs review', '%s: the parameter points to %s, the variable is %s'
                        % (name, p.get('pointee_type'), r['type']))
                else:
                    add('out', name, 'matches a known safe pattern', '%s: comes back through the parameter %s %s, '
                        'the call passes %s' % (name, p['type'], name, a['text'] if a else '?'))
                ownership_check(rep, name, p, r, before['function'])
            elif ok_ret and not p:
                # The return value replaces the variable's earlier value, so the
                # block must assign it on every path first. No caller form that
                # would keep the earlier value (x |= helper(), x = x || helper())
                # is accepted.
                if must_in:
                    add('out', name, 'needs review', '%s: comes back as the helper\'s return value (%s); it is '
                        'also read in the block but is not passed in' % (name, call['text']))
                elif not r.get('definite'):
                    add('out', name, 'needs review', '%s: comes back as the helper\'s return value (%s), but the '
                        'block writes it only on some paths: the value it had before the block is lost unless it '
                        'is passed in' % (name, call['text']))
                else:
                    rep['patterns'].append('retvar:' + name)
                    add('out', name, 'matches a known safe pattern', '%s: comes back as the helper\'s return value '
                        '(%s); the block assigns it on every path before reading it' % (name, call['text']))
            elif r.get('is_reference'):
                add('out', name, 'needs review', '%s: the block writes through the reference %s, but the helper does '
                    'not take it by reference or pointer: the referent is not modified' % (name, name))
            else:
                add('out', name, 'needs review', '%s: written in the block and used after it, but it does not come '
                    'back: no pointer or reference parameter named %s, and the call\'s result is not assigned to it'
                    % (name, name))
        elif must_in:
            if p and same_type(p['type'], r['type']) and a and a.get('kind') == 'var' and a.get('var') == name:
                add('in', name, 'matches a known safe pattern', '%s: passed in by value' % name)
            elif p and not p.get('is_pointer') and not p.get('is_reference'):
                if not same_type(p['type'], r['type']):
                    add('in', name, 'needs review', '%s: the parameter is %s, the variable is %s' % (name, p['type'], r['type']))
                elif a and a.get('kind') == 'var' and a.get('var') == name:
                    add('in', name, 'matches a known safe pattern', '%s: passed in by value' % name)
                else:
                    add('in', name, 'needs review', '%s: the call passes %s for the parameter %s' % (
                        name, a['text'] if a else 'nothing', name))
            elif p:
                if a and ((a.get('kind') == 'address-of' and a.get('var') == name) or
                          (a.get('kind') == 'var' and a.get('var') == name and p.get('is_reference'))):
                    add('in', name, 'matches a known safe pattern', '%s: passed in by %s (not used after the block, '
                        'so writing back does not matter)' % (name, 'pointer' if p.get('is_pointer') else 'reference'))
                    ownership_check(rep, name, p, r, before['function'])
                else:
                    add('in', name, 'needs review', '%s: the parameter is %s and the call passes %s' % (
                        name, p['type'], a['text'] if a else 'nothing'))
            else:
                add('in', name, 'needs review', '%s: read in the block but not passed in (no parameter named %s); '
                    'correct only if the helper writes it before reading it' % (name, name))
    for d in before.get('declared_inside', []):
        if d.get('uses_after') and d.get('top_level'):
            p = params.get(d['name'])
            if p and p.get('is_pointer'):
                used.add(d['name'])
                add('out', d['name'], 'needs review', '%s: declared in the block and used after it; it comes back '
                    'through a pointer parameter, and the declaration must have moved to the caller (review)' % d['name'])
            else:
                add('out', d['name'], 'needs review', '%s: declared in the block and used after it at line %s, and '
                    'no parameter named %s brings it back' % (d['name'], lines_text(u['line'] for u in d['uses_after']),
                                                              d['name']))
    for p in hparams:
        if p['name'] not in used and p['name'] not in rows:
            add('extra', p['name'], 'needs review', 'parameter %s (%s) does not correspond to a variable of the block'
                % (p['name'], p['type']))

    # self and friends.
    self_assigned = [s for s in before.get('self_uses', []) if s['kind'] == 'self' and s['use'] in WRITE_USES]
    if self_assigned:
        lines = ', '.join(str(s['line']) for s in self_assigned)
        stmts = h.get('statements') or []
        ends_with_self = bool(stmts) and stmts[-1]['kind'] == 'ReturnStmt' and stmts[-1].get('value') == 'self' \
            and stmts[-1]['line'] > inp.d
        if call and call.get('context') == 'assigned' and call.get('assigned_to') == 'self' and \
                h['kind'] == 'objc-method' and not h.get('returns_void') and ends_with_self:
            rep['data'].append({'kind': 'out', 'subject': 'self', 'status': 'matches a known safe pattern',
                                'text': 'self: assigned in the block (line %s); the helper returns it and the caller '
                                'assigns the result to self' % lines})
            rep['patterns'].append('self')
        else:
            rep['data'].append({'kind': 'out', 'subject': 'self', 'status': 'needs review',
                                'text': 'self: assigned in the block (line %s), but %s: the assignment changes only '
                                'the helper\'s self' % (lines, 'the helper does not end with return self' if call and
                                                         call.get('assigned_to') == 'self' else
                                                         'the caller does not assign the helper\'s result to self')})
    same_category = (h.get('category') or '') == (fn.get('category') or '')
    for s in before.get('self_uses', []):
        if s['kind'] == 'self' and s['use'] in WRITE_USES:
            continue
        if s['kind'] == 'super' and method_helper and not same_category:
            rep['other'].append({'status': 'needs review', 'text': 'line %d: %s: the helper is in %s, the block was '
                                 'in %s' % (s['line'], self_label(s), 'category ' + h['category'] if h.get('category')
                                            else 'the class\'s main implementation', 'category ' + fn['category']
                                            if fn.get('category') else 'the class\'s main implementation')})
            continue
        if s['kind'] == '_cmd':
            rep['other'].append({'status': 'needs review', 'text': 'line %d: _cmd is the helper\'s selector after '
                                 'extraction' % s['line']})
        elif s['kind'] in ('self', 'ivar', 'super'):
            if method_helper and call and call.get('receiver') in ('self', 'super' if s['kind'] == 'super' else 'self'):
                rep['other'].append({'status': 'matches a known safe pattern', 'text': 'line %d: %s: the helper is '
                                     'a method of the same class, called on self' % (s['line'], self_label(s))})
            else:
                rep['other'].append({'status': 'needs review', 'text': 'line %d: %s: the helper is %s' % (
                    s['line'], self_label(s), 'not a method of %s called on self' % fn.get('class', 'the class'))})
    for pnote in rng['categories']['positional']['items']:
        rep['other'].append({'status': 'note', 'text': pnote})
    for hz in rng['categories']['hazards']['items']:
        rep['other'].append({'status': 'needs review', 'text': hz})
    by_pointer = set(x['subject'] for x in rep['data'] if x['status'] == 'matches a known safe pattern' and
                     x['kind'] in ('out', 'in') and ('through the parameter' in x['text'] or 'passed in by pointer'
                                                     in x['text'] or 'passed in by reference' in x['text']))
    for cp in rng['categories']['captures']['items']:
        subject = cp.split(':', 1)[0]
        resolved = subject in by_pointer and (': address taken' in cp or ': bound to a reference' in cp)
        if ': writes through the pointer' in cp:
            # The pointer itself must reach the helper unchanged.
            resolved = any(x['subject'] == subject and x['status'] == 'matches a known safe pattern' and
                           'passed in by value' in x['text'] for x in rep['data'])
        if 'by copy' not in cp and not resolved:
            rep['other'].append({'status': 'needs review', 'text': cp})
        elif resolved:
            rep['other'].append({'status': 'matches a known safe pattern', 'text': cp + (
                ' (the pointer is passed in by value)' if ': writes through the pointer' in cp else
                ' (it is passed by pointer or reference, so the helper uses the caller\'s variable)')})
    for e in rng['categories']['entries']['items']:
        rep['other'].append({'status': 'needs review', 'text': e})

    # pure_move must confirm that the block's lines moved unchanged.
    if inp.pure is None:
        rep['other'].append({'status': 'needs review', 'text': 'pure_move was not run, so nothing confirms that the '
                             'block\'s lines moved unchanged'})
    elif not inp.pure['pure_move']:
        rep['other'].append({'status': 'needs review', 'text': 'pure_move cannot confirm that the block\'s lines '
                             'moved unchanged (%s): read every difference, or compare the compiled code' % ', '.join(
                                 '%s %d' % (k, v) for k, v in sorted(inp.pure['counts'].items())
                                 if v and k in PURE_MOVE_PROBLEMS)})

    # Exits.
    pair_exits(rep, before, h, call, inp)

    # Every statement the helper has outside the moved lines, and every declared line.
    account_statements(rep, inp, h)
    account_declared(rep, inp, h, call)
    check_placement(rep, inp, call)
    for facts, label in ((helper, 'the helper'), (caller, 'the caller')):
        if facts.get('errors'):
            rep['unknown'].append('clang reported %d error(s) on the after version (%s): %s' % (
                facts['errors'], label, '; '.join(clang_errors(facts)) or 'no text captured'))

    statuses = [x['status'] for x in rep['data'] + rep['exits'] + rep['other']]
    if rep['unknown']:
        rep['exit_code'] = 3
    elif any(s not in ('matches a known safe pattern', 'note') for s in statuses):
        rep['exit_code'] = 1
    else:
        rep['exit_code'] = 0
    return rep


def self_label(s):
    return s['kind'] if s['kind'] == s['name'] else '%s %s' % (s['kind'], s['name'])


def ownership_check(rep, name, p, r, fn):
    if not fn.get('arc') or not p.get('pointee_is_object_pointer'):
        return
    pl, vl = p.get('pointee_lifetime') or '', r.get('lifetime') or ''
    if pl == vl:
        rep['data'].append({'kind': 'ownership', 'subject': name, 'status': 'matches a known safe pattern',
                            'text': '%s: the out-parameter points to %s, as the variable is' % (name, pl)})
        return
    implicit = pl == '__autoreleasing' and not p.get('pointee_lifetime_written')
    rep['data'].append({'kind': 'ownership', 'subject': name, 'status': 'needs review', 'text': (
        '%s: the out-parameter points to %s%s, but the variable is %s. ARC passes &%s through a temporary and '
        'writes it back after the call; the value stored by the helper is autoreleased, and if the helper stores '
        'it inside an @autoreleasepool the object can be freed before the caller reads it. Declare the parameter '
        '%s to match' % (name, pl, ' (the ARC default for a pointer to an object pointer, not written)' if implicit
                         else '', vl or 'unqualified', name, '"%s *%s *"' % (r['type'], vl) if vl else 'with the same ownership'))})


def find_helper_exit(h, line, kinds):
    for x in h.get('exits', []):
        if x['line'] == line and x['kind'] in kinds:
            return x
    return None


def pair_exits(rep, before, h, call, inp):
    exits = [x for x in before.get('exits', []) if not x.get('target_inside')]
    if not exits:
        return
    same_length = (inp.b - inp.a) == (inp.d - inp.c)
    if not same_length:
        rep['unknown'].append('the block (%d lines) and its new place (%d lines) differ in length, so the exits '
                              'of the block cannot be paired with the helper\'s by line' % (inp.b - inp.a + 1, inp.d - inp.c + 1))
    fn = before['function']
    changing = [x for x in exits if x['kind'] in CHANGES_MEANING]
    kinds = set(x['kind'] for x in changing)
    hexits = h.get('exits', [])
    last = h.get('last_statement') or {}
    mapped = {}
    for x in changing:
        mapped[id(x)] = find_helper_exit(h, x['line'] - inp.a + inp.c, ('return', 'break', 'continue', 'goto')) if same_length else None
    mapped_ids = set(id(m) for m in mapped.values() if m)
    others = [y for y in hexits if id(y) not in mapped_ids and y['kind'] == 'return' and not y.get('target_inside')]

    def record(x, status, text):
        rep['exits'].append({'line': x['line'], 'kind': x['kind'], 'status': status, 'text': text})

    for x in exits:
        if x['kind'] == 'noreturn-call':
            record(x, 'matches a known safe pattern', 'line %d: %s does not return, in the block or in the helper'
                   % (x['line'], x.get('callee') or 'the call'))
            continue
        if x['kind'] == 'throw':
            if h.get('nothrow'):
                record(x, 'needs review', 'line %d: throw, but the helper is declared not to throw' % x['line'])
            else:
                record(x, 'matches a known safe pattern', 'line %d: throw: propagates through the helper to the '
                       'same handlers' % x['line'])
            continue
        if not call:
            record(x, 'needs review', 'line %d: %s; no single call to the helper to pair it with' % (x['line'], x['kind']))
            continue
        hx = mapped.get(id(x))
        after = describe_call(call)
        if x['kind'] == 'return' and not x.get('value') and fn.get('returns_void'):
            if call.get('tail') and h.get('returns_void') and hx and hx['kind'] == 'return' and \
                    before['selection'].get('tail') and body_is_block(h, inp):
                record(x, 'matches a known safe pattern', 'line %d: return; the call is the last thing the caller '
                       'does, so returning from the helper ends the caller too (%s)' % (x['line'], after))
                continue
            st = flag_pattern(call, hx, others, last, 'return', len(kinds) == 1)
            if st[0] == 'matches a known safe pattern':
                rep['patterns'].append('flag')
            record(x, st[0], 'line %d: return; %s; %s' % (x['line'], st[1], after))
            continue
        if x['kind'] == 'return':
            # Safe only when nothing followed the block in the original (so the
            # code the caller no longer runs is nothing) and the helper's body is
            # exactly the block (so its other returns and its end are the block's).
            why = None
            if not (call.get('context') == 'returned' and call.get('tail')):
                why = 'the caller does not return the helper\'s result as its last statement'
            elif not before['selection'].get('tail'):
                why = ('code followed the block in the original (%s); the caller no longer runs it, and the helper\'s '
                       'other paths are not compared with it' % ((before['selection'].get('next') or {}).get('text')
                                                                 or 'the rest of the function'))
            elif not body_is_block(h, inp):
                why = 'the helper\'s body holds statements outside the block'
            elif not (hx and hx['kind'] == 'return' and hx.get('value') == x.get('value')):
                why = 'the helper does not return the same expression at the same place'
            elif not same_type(h.get('return_type'), fn.get('return_type')):
                why = 'the helper\'s return type differs from the function\'s'
            if why is None:
                record(x, 'matches a known safe pattern', 'line %d: return %s; the block was the end of the function, '
                       'the helper\'s body is exactly the block and returns the same value there, and the caller returns '
                       'the helper\'s result' % (x['line'], x.get('value')))
            else:
                record(x, 'needs review', 'line %d: return %s; %s; after the call: %s' % (
                    x['line'], x.get('value', ''), why, after))
            continue
        if x['kind'] in ('break', 'continue'):
            st = after_call_pattern(x, call, hx, before)
            if st:
                rep['patterns'].append('after-call')
                record(x, 'matches a known safe pattern', 'line %d: %s; %s; %s' % (x['line'], x['kind'], st, after))
                continue
        if x['kind'] in ('break', 'continue', 'goto'):
            st = flag_pattern(call, hx, others, last, x['kind'], len(kinds) == 1,
                              label=x.get('target', '').replace('label ', '') if x['kind'] == 'goto' else None)
            if st[0] == 'matches a known safe pattern':
                rep['patterns'].append('flag')
            record(x, st[0], 'line %d: %s; %s; %s' % (x['line'], x['kind'], st[1], after))
            continue
        record(x, 'needs review', 'line %d: %s; after the call: %s' % (x['line'], x['kind'], after))


def after_call_pattern(x, call, hx, before):
    """The convention for a case body or loop body: the block's break (or
    continue) became a plain return of the helper, the call is a statement on
    its own followed by that same break (or continue), and in the original
    every path out of the block reached it too (the block ended with it, or it
    was the statement right after the block). Returns the explanation, or None."""
    kind = x['kind']
    stmt_kind = 'BreakStmt' if kind == 'break' else 'ContinueStmt'
    if call.get('context') != 'discarded' or (call.get('next') or {}).get('only') != kind:
        return None
    if not hx or hx['kind'] != 'return' or hx.get('value'):
        return None
    sel = before.get('selection') or {}
    last = (sel.get('statements') or [{}])[-1].get('kind')
    nxt = (sel.get('next') or {}).get('kind')
    if last != stmt_kind and nxt != stmt_kind:
        return None
    return ('the helper returns there, the call is followed by %s, and in the original every path out of the '
            'block reached a %s of the same statement (%s)' % (
                kind, kind, 'the block ended with it' if last == stmt_kind else 'it followed the block'))


PURE_MOVE_PROBLEMS = ('mismatches', 'length_mismatches', 'unaccounted_removed', 'unaccounted_added', 'file_problems')


def account_statements(rep, inp, h):
    """Each statement of the helper's body outside the moved lines C-D must be
    a form a pattern in use needs: the final `return self;` (self pattern), a
    final return of a constant (flag pattern; flag_pattern checks its value),
    a final `return x;` and a declaration of x before the moved lines (x comes
    back as the return value). Anything else needs review."""
    stmts = h.get('statements') or []
    pats = set(rep['patterns'])
    for k, st in enumerate(stmts):
        if inp.c <= st['line'] and st['end_line'] <= inp.d:
            continue
        where = 'line %d' % st['line'] if st['line'] == st['end_line'] else 'lines %d-%d' % (st['line'], st['end_line'])
        if st['line'] <= inp.d and st['end_line'] >= inp.c:
            rep['other'].append({'status': 'needs review', 'text': 'the helper\'s statement at %s (%s) straddles the '
                                 'moved lines %d-%d' % (where, st['text'], inp.c, inp.d)})
            continue
        why = None
        last = k == len(stmts) - 1
        if st['kind'] == 'ReturnStmt' and last and st['line'] > inp.d:
            v = st.get('value')
            if 'self' in pats and v == 'self':
                why = 'the self pattern returns self'
            elif 'flag' in pats and 'const_value' in st:
                why = 'the flag pattern returns this constant when the block falls through'
            elif v and 'retvar:' + v in pats:
                why = '%s comes back as the return value' % v
        elif st['kind'] == 'DeclStmt' and st['end_line'] < inp.c and st.get('declares') and \
                all('retvar:' + n in pats for n in st['declares']):
            why = 'it declares %s, which comes back as the return value' % ', '.join(st['declares'])
        if why:
            rep['other'].append({'status': 'matches a known safe pattern', 'text': 'the helper\'s statement at %s '
                                 '(%s) is outside the moved lines: %s' % (where, st['text'], why)})
        else:
            rep['other'].append({'status': 'needs review', 'text': 'the helper\'s statement at %s (%s) is outside '
                                 'the moved lines and no pattern accounts for it' % (where, st['text'])})


def account_declared(rep, inp, h, call):
    """Lists the declared lines and checks where they are: an added line must be
    in the helper (its statements are checked by account_statements; the rest
    is its signature and braces) or in the call statement; a removed line must
    be blank or a comment."""
    pure = inp.pure or {}
    added = pure.get('declared_added_lines') or []
    removed = pure.get('declared_removed_lines') or []
    rep['declared'] = {'added': [{'line': n, 'text': t} for n, t in added],
                       'removed': [{'line': n, 'text': t} for n, t in removed]}

    def trivial(t):
        t = t.strip()
        return not t or t.startswith('//') or t.startswith('/*') or t.startswith('*')
    for n, t in added:
        if h['line'] <= n <= h['end_line']:
            continue
        if call and call.get('stmt_line') and call['stmt_line'] <= n <= call['stmt_end_line']:
            continue
        nxt = (call or {}).get('next') or {}
        if 'after-call' in rep['patterns'] and nxt.get('only') in ('break', 'continue') and nxt.get('line') == n:
            # The break or continue that the after-call pattern needs right after the call.
            continue
        if trivial(t):
            continue
        rep['other'].append({'status': 'needs review', 'text': 'added line %d (%s) is neither in the helper nor in '
                             'the call statement' % (n, t.strip())})
    for n, t in removed:
        if not trivial(t):
            rep['other'].append({'status': 'needs review', 'text': 'removed line %d (%s): an extraction removes only '
                                 'the moved block' % (n, t.strip())})


def check_placement(rep, inp, call):
    """The call statement must occupy the gap the block left: with pure_move's
    line mapping (the unchanged lines of the two versions, paired in order),
    the nearest unchanged code lines before and after the call statement must
    be the code lines that came right before and after the block. Blank and
    comment lines are skipped on both sides. Braces are code lines, so the
    call cannot have moved into or out of a compound statement."""
    pure = inp.pure or {}
    if not call or not call.get('stmt_line') or not pure.get('pure_move'):
        return  # without pure_move's confirmation the result already needs review
    old = [x.decode('utf-8', 'replace') for x in pure_move.split_lines(inp.before)]
    new = [x.decode('utf-8', 'replace') for x in pure_move.split_lines(inp.after)]
    dec_old = set(n for n, _ in pure.get('declared_removed_lines') or [])
    dec_new = set(n for n, _ in pure.get('declared_added_lines') or [])
    old_keep = [n for n in range(1, len(old) + 1) if not inp.a <= n <= inp.b and n not in dec_old]
    new_keep = [n for n in range(1, len(new) + 1) if not inp.c <= n <= inp.d and n not in dec_new]

    def code(t):
        t = t.strip()
        return bool(t) and not t.startswith(('//', '/*', '*'))
    if len(old_keep) != len(new_keep):
        rep['other'].append({'status': 'needs review', 'text': 'the unchanged lines of the two versions do not pair '
                             'up, so where the call sits cannot be checked'})
        return
    mapping = dict(zip(new_keep, old_keep))
    s1, s2 = call['stmt_line'], call['stmt_end_line']
    prev_new = [n for n in new_keep if n < s1 and code(new[n - 1])]
    next_new = [n for n in new_keep if n > s2 and code(new[n - 1])]
    prev_old = [n for n in old_keep if n < inp.a and code(old[n - 1])]
    next_old = [n for n in old_keep if n > inp.b and code(old[n - 1])]
    got = (mapping[prev_new[-1]] if prev_new else None, mapping[next_new[0]] if next_new else None)
    want = (prev_old[-1] if prev_old else None, next_old[0] if next_old else None)
    if got == want:
        rep['other'].append({'status': 'matches a known safe pattern', 'text': 'the call statement (line %d) is where '
                             'the block was: between old lines %s and %s' % (s1, want[0], want[1])})
    else:
        rep['other'].append({'status': 'needs review', 'text': 'the call is not where the block was: the call '
                             'statement (line %d) comes after old line %s and before old line %s, but the block came '
                             'after old line %s and before old line %s' % (s1, got[0], got[1], want[0], want[1])})


def body_is_block(h, inp):
    """Whether every statement of the helper's body lies within the block's new
    lines C-D."""
    first = h.get('first_statement_line')
    last = (h.get('last_statement') or {}).get('end_line')
    return bool(first and last) and inp.c <= first and last <= inp.d


def describe_call(call):
    s = 'the call at line %d (%s) is %s' % (call['line'], call['text'], {
        'if-condition': 'the condition of an if', 'assigned': 'assigned to %s' % call.get('assigned_to'),
        'initializes': 'the initializer of %s' % call.get('assigned_to'), 'returned': 'returned',
        'discarded': 'a statement on its own'}.get(call.get('context'), 'used in another way'))
    if call.get('context') == 'if-condition' and call.get('then'):
        s += ' whose branch is: %s' % call['then'].get('text', '')
    elif call.get('next'):
        s += '; the next statement is: %s' % call['next'].get('text', '')
    return s


def flag_pattern(call, hx, others, last, kind, single_kind, label=None):
    """Whether the call site acts on a returned flag in the way that preserves an exit of `kind`."""
    if not single_kind:
        return 'needs review', 'the block has exits of more than one kind; one flag cannot tell them apart'
    if not hx or hx['kind'] != 'return' or 'const_value' not in hx:
        return 'needs review', 'the helper does not return a constant at the same place'
    if call.get('context') != 'if-condition' or not call.get('then'):
        return 'needs review', 'the call is not the condition of an if'
    then = call['then']
    if then.get('only') != kind or (kind == 'return' and then.get('value')) or (label and then.get('label') != label):
        return 'needs review', 'the if\'s branch is not just "%s"' % (kind + (' ' + label if label else ''))
    k = hx['const_value']
    t = taken(k, call)
    if t is not True:
        return 'needs review', 'the branch is not taken when the helper returns %d' % k
    # The helper's final return is checked on its own below.
    falls = [y for y in others if y['line'] != last.get('line')]
    if last.get('kind') == 'ReturnStmt' and 'const_value' in last:
        pass
    else:
        return 'needs review', 'the helper does not end with a return of a constant'
    for y in falls:
        if 'const_value' not in y:
            return 'needs review', 'another return in the helper (line %d) does not return a constant' % y['line']
        if taken(y['const_value'], call) is not False and y['line'] != hx['line']:
            # another exit of the same kind is fine only if it maps to an original exit
            return 'needs review', 'the return at line %d also takes the branch' % y['line']
    if taken(last['const_value'], call) is not False:
        return 'needs review', 'the helper\'s final return also takes the branch'
    return 'matches a known safe pattern', 'the helper returns %d there and the caller\'s if takes the branch on %d' % (k, k)


def format_after(rep):
    out = []
    out.append('Extraction check, after: block %s:%d-%d now at lines %d-%d in %s' % (
        rep['block']['path'], rep['block']['first'], rep['block']['last'], rep['helper_lines']['first'],
        rep['helper_lines']['last'], rep.get('helper', {}).get('name', '?')))
    out.append('Configuration: %s' % rep['configuration'])
    out.append('How far to rely on this: findings marked "needs review" are trustworthy. A clean result means '
               'that every pattern this tool knows was satisfied; a reviewer still reads the declared lines.')
    if rep.get('pure_move') is not None:
        out.append('pure_move.py --extract%s: %s' % (
            ' (on the two files)' if rep['pure_move'].get('mode') == 'contents' else '',
            'the lines moved unchanged' if rep['pure_move']['pure_move']
            else 'cannot confirm a pure move (%s)' % json.dumps(rep['pure_move']['counts'])))
    else:
        out.append('pure_move.py --extract: not run')
    if rep.get('call'):
        out.append('Call: %s' % describe_call(rep['call']))
    decl = rep.get('declared') or {}
    if decl.get('added') or decl.get('removed'):
        out.append('Declared lines (pure_move does not compare them; each is checked below):')
        for x in decl.get('added', []):
            out.append('  + %d: %s' % (x['line'], x['text']))
        for x in decl.get('removed', []):
            out.append('  - %d: %s' % (x['line'], x['text']))
    for title, key in (('Variables', 'data'), ('Exits of the block', 'exits'), ('Other', 'other')):
        out.append('')
        out.append(title + ':')
        if not rep[key]:
            out.append('  none')
        for x in rep[key]:
            out.append('  - [%s] %s' % (x['status'], x['text']))
    if rep['unknown']:
        out.append('')
        out.append('Unknown:')
        for u in rep['unknown']:
            out.append('  - ' + u)
    out.append('')
    out.append('Result: %s' % {0: 'every pairing matches a known safe pattern (notes aside)', 1: 'something needs review',
                               3: 'something is unknown'}[rep['exit_code']])
    out.append('A pairing that matches a known safe pattern is not a proof of equivalence; the reviewer still '
               'reads the diff. The range report for the block follows.')
    out.append('')
    out.append(format_range(rep['range']))
    return '\n'.join(out) + '\n'


def after_facts(args, repo, binary, inp, work):
    cargs, main_abs, entry = command_for(args, repo, inp.path)
    bfile = work.write('before', inp.before)
    afile = work.write('after', inp.after)
    cwd = entry['directory'] if entry else None
    before = run_facts(binary, main_abs, cargs, ['--range', str(inp.a), str(inp.b)], contents=bfile, cwd=cwd)
    if before.get('error'):
        raise ToolError('before version: %s' % before['error'])
    if not (before.get('selection') or {}).get('aligned'):
        return before, None, None, cargs, main_abs, entry, bfile, afile
    helper = run_facts(binary, main_abs, cargs, ['--function-at', str(inp.c)], contents=afile, cwd=cwd)
    if helper.get('error'):
        raise ToolError('after version: %s' % helper['error'])
    caller = run_facts(binary, main_abs, cargs, ['--function-named', before['function']['name'],
                                                 '--callee-named', helper['function']['name']], contents=afile,
                       cwd=cwd)
    return before, helper, caller, cargs, main_abs, entry, bfile, afile


def cmd_after(args):
    repo, binary = setup(args)
    inp = read_inputs(args, repo)
    work = Work(repo)
    try:
        before, helper, caller, cargs, main_abs, entry, _, _ = after_facts(args, repo, binary, inp, work)
    finally:
        work.close()
    config = configuration_text(cargs, before.get('triple'), entry)
    if helper is None:
        rep = analyze_range(before, config)
        rep.update({'mode': 'after', 'exit_code': 3})
        emit(args, rep, format_range)
        return 3
    rep = analyze_after(before, helper, caller, inp, config)
    emit(args, rep, format_after)
    return rep['exit_code']


# ---------------------------------------------------------------- compiled comparison

DROP_FLAGS = ('-fprofile-instr-generate', '-fcoverage-mapping', '-gmodules', '-fsyntax-only', '-c', '-S',
              '-emit-llvm', '-fno-discard-value-names')
DROP_PREFIXES = ('-O', '-g', '-fprofile-', '-fcoverage-', '-fdebug-prefix-map=', '-fsanitize')


def compile_args(cargs):
    out = []
    i = 0
    while i < len(cargs):
        a = cargs[i]
        if a == '-o':
            i += 2
            continue
        if a in DROP_FLAGS or (a.startswith(DROP_PREFIXES) and a not in ('-g0',)):
            i += 1
            continue
        out.append(a)
        i += 1
    return out + ['-O2', '-g0', '-fdiscard-value-names', '-S', '-emit-llvm', '-w']


def overlay(work, main_abs, contents, name):
    data = {'version': 0, 'case-sensitive': 'true', 'use-external-names': False,
            'roots': [{'type': 'file', 'name': main_abs, 'external-contents': contents}]}
    return work.write(name, json.dumps(data).encode())


def compile_ir(clang, cargs, main_abs, contents, work, name, cwd=None):
    ov = overlay(work, main_abs, contents, name + '.yaml')
    out = os.path.join(work.dir, name + '.ll')
    cmd = [clang] + compile_args(cargs) + ['-ivfsoverlay', ov, '-o', out]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=FACTS_TIMEOUT, start_new_session=True,
                           cwd=cwd)
    except subprocess.TimeoutExpired:
        raise ToolError('compiling the %s version timed out' % name)
    if r.returncode != 0:
        raise ToolError('compiling the %s version failed:\n%s' % (name, r.stderr[-4000:]))
    return out


GLOBAL_DEF_RE = re.compile(r'^(@(?:"(?:[^"\\]|\\.)*"|[-\w.$]+)) = (.*)$')
GLOBAL_REF_RE = re.compile(r'@(?:"(?:[^"\\]|\\.)*"|[-\w.$]+)')
# With -fdiscard-value-names every local value and label is numbered; a %name
# is a named type (%struct.fd_set) and is left alone.
LOCAL_RE = re.compile(r'%\d+\b')
DEFINE_RE = re.compile(r'^define [^@]*(@(?:"(?:[^"\\]|\\.)*"|[-\w.$]+))\(')
LABEL_DEF_RE = re.compile(r'^(\d+):')
METADATA_RE = re.compile(r',?\s*!(?:[A-Za-z_][\w.]*)\s+(?:!\d+|!\{[^}]*\})')
ATTR_RE = re.compile(r'\s#\d+\b')


def ir_symbol(name):
    """The IR spelling of a function's symbol name."""
    if name.startswith(('-[', '+[')):
        return '@"\\01%s"' % name
    if re.match(r'^[-\w.$]+$', name):
        return '@' + name
    return '@"%s"' % name


def read_ir(path, wanted):
    """(functions {symbol: [lines]}, private globals {symbol: definition}) streaming the file."""
    funcs, globs = {}, {}
    cur = None
    with open(path) as f:
        for line in f:
            line = line.rstrip('\n')
            if cur is not None:
                funcs[cur].append(line)
                if line == '}':
                    cur = None
                continue
            m = DEFINE_RE.match(line)
            if m:
                sym = m.group(1)
                if sym in wanted:
                    cur = sym
                    funcs[sym] = [line]
                else:
                    funcs.setdefault('__other__', []).append(sym)
                continue
            g = GLOBAL_DEF_RE.match(line)
            if g and re.match(r'(private|internal)\b', g.group(2)):
                globs[g.group(1)] = g.group(2)
    return funcs, globs


RUNTIME_SECTION_RE = re.compile(r'section "(__DATA,__(cfstring|objc_classrefs|objc_superrefs|objc_selrefs|'
                                r'objc_protorefs|objc_const)|__TEXT,__(objc_methname|objc_classname|objc_methtype|cstring))')
FUNCTION_NAME_RE = re.compile(r'^(__func__|__FUNCTION__|__PRETTY_FUNCTION__)\.')


def global_kind(sym, body):
    """How a reference to a private or internal global is compared (see
    NORMALIZATION): 'content', 'function-name', 'identity-content' or
    'identity'."""
    name = sym.lstrip('@').strip('"')
    if FUNCTION_NAME_RE.match(name):
        return 'function-name'
    if RUNTIME_SECTION_RE.search(body) or ('externally_initialized' in body and name.startswith('OBJC_')):
        return 'content'
    if name.startswith(('__block_literal_global', '__block_descriptor_tmp')):
        return 'content'
    head = body.split(' constant ', 1)[0] if ' constant ' in body else ''
    if re.search(r'(^|\s)constant\s', body):
        if re.search(r'(^|\s)unnamed_addr(\s|$)', head):
            return 'content'
        return 'identity-content'
    return 'identity'


def canonical_global(sym, globs, seen=None, funcs=None):
    """The form a reference to sym takes after normalization. A private or
    internal global is replaced according to global_kind: by its canonical
    initializer (content), by its name and initializer (identity-content), or
    left as its name (identity, for globals the code may write). A private or
    internal function is replaced by the digest of its normalized body."""
    seen = seen or set()
    if funcs is not None and sym in funcs.internal:
        return funcs.token(sym)
    if sym not in globs or sym in seen:
        return sym
    seen = seen | {sym}
    kind = global_kind(sym, globs[sym])
    if kind == 'identity':
        return sym
    inner = GLOBAL_REF_RE.sub(lambda m: canonical_global(m.group(0), globs, seen, funcs), globs[sym])
    if kind == 'content':
        return '@<%s>' % inner
    if kind == 'function-name':
        return '@<function-name string: %s>' % inner
    return '%s<%s>' % (sym, inner)


class IRModule(object):
    """One compiled file's LLVM IR, read by streaming: its private and internal
    globals, the names of its private and internal functions, and the bodies
    of those functions that a comparison needs."""

    MAX_PASSES = 8

    def __init__(self, path):
        self.path = path
        self.globs, self.internal, self.bodies, self.digests = {}, set(), {}, {}
        inside = False
        with open(path) as f:
            for line in f:
                line = line.rstrip('\n')
                if inside:
                    inside = line != '}'
                    continue
                m = DEFINE_RE.match(line)
                if m:
                    if re.match(r'^define (private|internal)\b', line):
                        self.internal.add(m.group(1))
                    inside = True
                    continue
                g = GLOBAL_DEF_RE.match(line)
                if g and re.match(r'(private|internal)\b', g.group(2)):
                    self.globs[g.group(1)] = g.group(2)

    def load(self, names):
        names = set(n for n in names if n not in self.bodies)
        if not names:
            return
        cur = None
        with open(self.path) as f:
            for line in f:
                line = line.rstrip('\n')
                if cur is not None:
                    self.bodies[cur].append(line)
                    if line == '}':
                        cur = None
                    continue
                m = DEFINE_RE.match(line)
                if m and m.group(1) in names:
                    cur = m.group(1)
                    self.bodies[cur] = [line]

    def prepare(self, lines):
        """Loads the bodies of the internal functions the lines refer to, and of
        those they refer to, in at most MAX_PASSES streaming passes."""
        todo = self._functions_in(lines)
        for _ in range(self.MAX_PASSES):
            todo -= set(self.bodies)
            if not todo:
                return
            self.load(todo)
            todo = set(f for name in todo for f in self._functions_in(self.bodies.get(name, [])))

    def _functions_in(self, lines):
        """The internal functions named in the lines or in the initializers of the
        globals they name, recursively (a block literal names its invoke function)."""
        found, seen = set(), set()
        stack = [sym for line in lines for sym in GLOBAL_REF_RE.findall(line)]
        while stack:
            sym = stack.pop()
            if sym in seen:
                continue
            seen.add(sym)
            if sym in self.internal:
                found.add(sym)
            elif sym in self.globs:
                stack.extend(GLOBAL_REF_RE.findall(self.globs[sym]))
        return found

    def token(self, sym, stack=()):
        if sym in self.digests:
            return self.digests[sym]
        if sym in stack or sym not in self.bodies:
            return sym
        text = '\n'.join(normalize_ir(self.bodies[sym][1:], self.globs, _FunctionTokens(self, stack + (sym,))))
        self.digests[sym] = '@<function %s>' % hashlib.sha256(text.encode()).hexdigest()[:16]
        return self.digests[sym]


class _FunctionTokens(object):
    def __init__(self, module, stack):
        self.module, self.stack, self.internal = module, stack, module.internal

    def token(self, sym):
        return self.module.token(sym, self.stack)


PHI_RE = re.compile(r'^(\s*%\S+ = phi [^\[]*?)(\[.*\])$')
PHI_PAIR_RE = re.compile(r'\[[^\[\]]*\]')


def sort_phi(line):
    m = PHI_RE.match(line)
    if not m:
        return line
    pairs = PHI_PAIR_RE.findall(m.group(2))
    if ', '.join(pairs) != m.group(2):
        return line  # not a plain list of pairs; leave it as it is
    return m.group(1) + ', '.join(sorted(pairs))


def strip_comment(line):
    """The line without a ';' comment; a ';' inside a string literal is kept."""
    quoted = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == '\\' and quoted:
            i += 2
            continue
        if ch == '"':
            quoted = not quoted
        elif ch == ';' and not quoted:
            return line[:i].rstrip()
        i += 1
    return line


DEF_RE = re.compile(r'^\s*(%\d+) = ')


def normalize_ir(lines, globs, funcs=None):
    # Locals are numbered in the order they are defined (the arguments, then
    # each "%x =" and each label in order), so that the order of a phi's
    # operands cannot change the numbering.
    names = {}

    def name(k):
        if k not in names:
            names[k] = '%%v%d' % len(names)
        return names[k]

    stripped = []
    for line in lines:
        line = strip_comment(line)
        line = METADATA_RE.sub('', line)
        line = ATTR_RE.sub('', line)
        stripped.append(line)
        if line.startswith('define'):
            for k in LOCAL_RE.findall(line):
                name(k)
            continue
        lm = LABEL_DEF_RE.match(line)
        if lm:
            name('%' + lm.group(1))
            continue
        dm = DEF_RE.match(line)
        if dm:
            name(dm.group(1))

    def local(m):
        return name(m.group(0))

    out = []
    for line in stripped:
        lm = LABEL_DEF_RE.match(line)
        if lm and not line.startswith('define'):
            line = name('%' + lm.group(1)) + ':' + line[len(lm.group(0)):]
        line = LOCAL_RE.sub(local, line)
        line = GLOBAL_REF_RE.sub(lambda m: canonical_global(m.group(0), globs, None, funcs), line)
        line = sort_phi(line.rstrip())
        if line:
            out.append(line)
    return out


def compare_compiled(args, repo, binary, inp, work):
    cargs, main_abs, entry = command_for(args, repo, inp.path)
    bfile = work.write('before', inp.before)
    afile = work.write('after', inp.after)
    cwd = entry['directory'] if entry else None
    before = run_facts(binary, main_abs, cargs, ['--range', str(inp.a), str(inp.b)], contents=bfile, cwd=cwd)
    if before.get('error'):
        raise ToolError('before version: %s' % before['error'])
    helper = run_facts(binary, main_abs, cargs, ['--function-at', str(inp.c)], contents=afile, cwd=cwd)
    if helper.get('error'):
        raise ToolError('after version: %s' % helper['error'])
    fn, h = before['function'], helper['function']
    rep = {'tool': 'extract_check', 'mode': 'compiled', 'function': fn['name'], 'helper': h['name'],
           'normalization': NORMALIZATION}
    if h['name'] == fn['name']:
        raise ToolError('new lines %d-%d are in %s itself, not in a new helper' % (inp.c, inp.d, h['name']))
    clang = args.clang or llvm_clang()
    fsym, hsym = ir_symbol(fn['ir_name']), ir_symbol(h['ir_name'])
    if h['kind'] == 'objc-method' and not h.get('direct'):
        rep['scope'] = 'nothing'
        rep.update({'result': 'not comparable', 'reason': 'the helper is an Objective-C method, called by message '
                    'send, which the optimizer does not inline', 'exit_code': 3})
        return rep
    bll = compile_ir(clang, cargs, main_abs, bfile, work, 'before', cwd)
    all_ = compile_ir(clang, cargs, main_abs, afile, work, 'after', cwd)
    bf, _ = read_ir(bll, {fsym})
    af, _ = read_ir(all_, {fsym, hsym})
    if fsym not in bf or fsym not in af:
        return compare_files(rep, bll, all_, fsym, hsym)
    bm, am = IRModule(bll), IRModule(all_)
    rep['scope'] = 'the enclosing function'
    body = '\n'.join(af[fsym])
    if refers_to(hsym, body):
        rep.update({'result': 'not comparable', 'reason': 'helper not inlined: the enclosing function still calls '
                    '%s at -O2' % hsym, 'exit_code': 3})
        return rep
    after_lines = rename_moved_statics(af[fsym], before, fn, h)
    bm.prepare(bf[fsym])
    am.prepare(after_lines)
    nb = normalize_ir(bf[fsym], bm.globs, _FunctionTokens(bm, (fsym,)))
    na = normalize_ir(after_lines, am.globs, _FunctionTokens(am, (fsym,)))
    rep['lines'] = {'before': len(nb), 'after': len(na)}
    if nb == na:
        rep.update({'result': 'identical', 'exit_code': 0})
    elif function_names_only(nb, na):
        diff = list(difflib.unified_diff(nb, na, 'before', 'after', lineterm='', n=2))
        rep.update({'result': 'different', 'exit_code': 1, 'diff': diff[:400], 'diff_lines': len(diff),
                    'reason': 'the code differs only in function-name strings (__func__ and the like), which name '
                    'the helper after extraction: a change the extraction makes by design (the range report lists '
                    'each use)'})
    else:
        diff = list(difflib.unified_diff(nb, na, 'before', 'after', lineterm='', n=2))
        rep.update({'result': 'different', 'exit_code': 1, 'diff': diff[:400], 'diff_lines': len(diff)})
    return rep


def refers_to(sym, text):
    """Whether text names the symbol sym itself (not @sym.x, a static local of it)."""
    if sym.endswith('"'):
        return sym in text
    return re.search(re.escape(sym) + r'(?![\w.$])', text) is not None


FN_TOKEN_RE = re.compile(r'@<function-name string: [^>]*>')


def function_names_only(nb, na):
    """Whether the two normalized bodies differ only in function-name strings."""
    def strip(lines):
        return [FN_TOKEN_RE.sub('@<function-name string>', x) for x in lines]
    return nb != na and strip(nb) == strip(na)


def function_digests(path, module, helper):
    """{symbol: digest of the normalized function} for every function defined
    in the IR file, streaming it; and whether any function other than the
    helper refers to the helper."""
    digests = {}
    refers = []
    cur, lines = None, []
    with open(path) as f:
        for line in f:
            line = line.rstrip('\n')
            if cur is None:
                m = DEFINE_RE.match(line)
                if m:
                    cur, lines = m.group(1), [line]
                continue
            lines.append(line)
            if line == '}':
                if cur != helper:
                    module.prepare(lines)
                    text = '\n'.join(normalize_ir(lines, module.globs, _FunctionTokens(module, (cur,))))
                    digests[cur] = hashlib.sha256(text.encode()).hexdigest()
                    if helper and refers_to(helper, '\n'.join(lines[1:])):
                        refers.append(cur)
                cur, lines = None, []
    return digests, refers


def rename_moved_statics(lines, before, fn, h):
    """In the after version's lines, a static local whose declaration moved with
    the block into the helper is named after the helper (@helper.x); rename it
    to the enclosing function's (@f.x). Only for plain C names; any other
    renaming is left, and shows as a difference."""
    plain = re.compile(r'^[A-Za-z_][\w$]*$')
    if not (plain.match(fn.get('ir_name') or '') and plain.match(h.get('ir_name') or '')):
        return lines
    moved = [d['name'] for d in before.get('declared_inside', []) if d.get('static_local')]
    out = lines
    for name in moved:
        old, new = '@%s.%s' % (h['ir_name'], name), '@%s.%s' % (fn['ir_name'], name)
        pat = re.compile(re.escape(old) + r'(?![\w.$])')
        out = [pat.sub(new, line) for line in out]
    return out


def compare_files(rep, bll, all_, fsym, hsym):
    """The enclosing function is not emitted on its own (a static function
    inlined into its callers): compare every function in the file instead."""
    bd, _ = function_digests(bll, IRModule(bll), None)
    ad, refers = function_digests(all_, IRModule(all_), hsym)
    rep['scope'] = ('every function in the file, because %s is not emitted on its own in the %s version (it is '
                    'inlined into its callers)' % (fsym, 'before' if fsym not in bd else 'after'))
    if refers:
        rep.update({'result': 'not comparable', 'reason': 'helper not inlined: %s still call %s at -O2'
                    % (', '.join(sorted(refers)[:10]), hsym), 'exit_code': 3})
        return rep
    differing = sorted(k for k in set(bd) | set(ad) if bd.get(k) != ad.get(k))
    rep['differing_functions'] = differing[:200]
    rep['functions_compared'] = len(set(bd) | set(ad))
    if differing:
        rep.update({'result': 'different', 'exit_code': 1, 'diff': ['functions that differ: ' + ', '.join(differing[:50])],
                    'diff_lines': 1})
    else:
        rep.update({'result': 'identical', 'exit_code': 0})
    return rep


def format_compiled(rep):
    out = ['Compiled comparison of %s (helper %s): %s' % (rep['function'], rep['helper'], rep['result'])]
    out.append('How far to rely on this: "identical" is strong evidence within the stated limits; Objective-C '
               'methods are never inlined, so on real code this usually says "not comparable".')
    if rep.get('reason'):
        out.append('Reason: ' + rep['reason'])
    if rep.get('scope'):
        out.append('Compared: ' + rep['scope'] + (' (%d functions)' % rep['functions_compared']
                                                  if rep.get('functions_compared') else ''))
    if rep['result'] == 'identical':
        out.append('With the helper inlined, the optimized code of the enclosing function is the same before and '
                   'after: strong evidence that the extraction changed nothing in this configuration.')
    elif rep['result'] == 'different':
        out.append('The normalized code differs. This is not proof of a bug: inlining and later passes do not '
                   'always produce the same code for equivalent sources. Read the difference:')
        out.extend('  ' + d for d in rep['diff'])
        if rep['diff_lines'] > len(rep['diff']):
            out.append('  ... %d more lines' % (rep['diff_lines'] - len(rep['diff'])))
    out.append('')
    out.append('Normalization:')
    for n in rep['normalization']:
        out.append('  - ' + n)
    return '\n'.join(out) + '\n'


def cmd_compiled(args):
    repo, binary = setup(args)
    inp = read_inputs(args, repo)
    work = Work(repo)
    try:
        rep = compare_compiled(args, repo, binary, inp, work)
    finally:
        work.close()
    emit(args, rep, format_compiled)
    return rep['exit_code']


# ---------------------------------------------------------------- range command

RANGE_RE = re.compile(r'^(.+):([1-9][0-9]*)-([1-9][0-9]*)$')


def cmd_range(args):
    repo, binary = setup(args)
    m = RANGE_RE.match(args.spec)
    if not m:
        raise ToolError('expected PATH:FIRST-LAST, got %r' % args.spec)
    path, first, last = m.group(1), int(m.group(2)), int(m.group(3))
    if last < first:
        raise ToolError('the range ends before it starts')
    local = os.path.realpath(os.path.abspath(path))
    cargs, main_abs, entry = command_for(args, repo, local)
    contents = os.path.abspath(args.contents) if args.contents else (local if local != main_abs else None)
    facts = run_facts(binary, main_abs, cargs, ['--range', str(first), str(last)], contents=contents,
                      cwd=entry['directory'] if entry else None)
    rep = analyze_range(facts, configuration_text(cargs, facts.get('triple'), entry))
    emit(args, rep, format_range)
    return rep['exit_code']


def emit(args, rep, fmt):
    if args.json:
        sys.stdout.write(json.dumps(rep, indent=2, sort_keys=True) + '\n')
    else:
        sys.stdout.write(fmt(rep))


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ToolError(message)


def build_parser():
    p = Parser(prog='extract_check.py', description=__doc__.split('\n\n')[0],
               formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    sub = p.add_subparsers(dest='command')

    def common(sp):
        sp.add_argument('--repo', default='.', help='the repository (default: current directory)')
        sp.add_argument('--cdb', help='the compile database (default: tmp/codedb/compile_commands.jsonl here or '
                        'in the main checkout)')
        sp.add_argument('--target', help='the target whose compile command to use')
        sp.add_argument('--binary', help='the extraction_facts binary (default: tmp/extraction/bin/extraction_facts, '
                        'built when missing or out of date)')
        sp.add_argument('--no-build', action='store_true', help='fail instead of building the binary')
        sp.add_argument('--json', action='store_true', help='machine-readable output')

    r = sub.add_parser('range', help='report on a block about to be extracted')
    r.add_argument('spec', metavar='PATH:FIRST-LAST')
    r.add_argument('--contents', help='analyze the bytes of this file as PATH')
    common(r)
    for name, helptext in (('after', 'check a completed extraction'),
                           ('compiled', 'compare the compiled code before and after')):
        a = sub.add_parser(name, help=helptext)
        a.add_argument('revs', nargs='*', metavar='REV')
        a.add_argument('--staged', action='store_true')
        a.add_argument('--extract', action='append', default=[], metavar='OLDPATH:A-B=NEWPATH:C-D')
        a.add_argument('--allow-added', action='append', default=[], metavar='PATH:N[-M]')
        a.add_argument('--allow-removed', action='append', default=[], metavar='PATH:N[-M]')
        a.add_argument('--before-file')
        a.add_argument('--after-file')
        if name == 'compiled':
            a.add_argument('--clang', help='the clang to compile with (default: upstream clang 22)')
        common(a)
    return p


def main(argv):
    clang_args = None
    if '--' in argv:
        k = argv.index('--')
        argv, clang_args = argv[:k], argv[k + 1:]
    try:
        args = build_parser().parse_args(argv)
        args.clang_args = clang_args
        if args.command == 'range':
            return cmd_range(args)
        if args.command == 'after':
            return cmd_after(args)
        if args.command == 'compiled':
            return cmd_compiled(args)
        raise ToolError('give a subcommand: range, after or compiled (see --help)')
    except ToolError as e:
        sys.stderr.write('extract_check.py: error: %s\n' % e)
        return 2
    except OSError as e:
        sys.stderr.write('extract_check.py: error: %s: %s\n' % (e.filename or '', e.strerror or e))
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
