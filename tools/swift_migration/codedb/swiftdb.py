"""The Swift side of the code database: Swift references to Objective-C
declarations, from the Swift compiler's JSON AST dump.

codedb.py imports this module; its commands are documented there. In short:

  capture        capture_compile_commands.sh calls `codedb.py swift-capture`
                 after a successful build: it keeps, in the fragments
                 directory (tmp/codedb/cdb-fragments/swift/), the build log's
                 SwiftDriver commands of the Variant-NoSanitizers variant
                 (drivers.jsonl, extracted by a streaming filter) and a copy
                 of each module's .SwiftFileList (filelists/).
  adoption       `codedb.py adopt-swift-capture` does the same once from what
                 an earlier capture left behind (tmp/codedb/capture-build.log
                 and the .SwiftFileList files under Build/), refusing when
                 they cannot be from that capture.
  commands       translate_swift_command() turns a captured driver command
                 into one that writes no build product and reads none of
                 Xcode's caches; the compiler's own driver
                 (-driver-print-jobs) then gives the frontend job, which
                 frontend_dump_job() turns into one process that dumps every
                 file of the module.
  extraction     update_swift() runs, one module at a time, under guard.sh,
                 the reader (swiftreader/swift_refs, built by
                 swiftreader/build.sh) that runs the compiler and streams its
                 output into the database, one transaction per module.
  states         swift_module_states(), shared by update and every query.

A module is the unit: a file's AST depends on its whole module. A module is
stale when its command, its file list, any input its dependency information
names (its Swift files, the bridging header and the headers it reads, the
.swiftmodule and .swiftinterface files it imports), the compiler or the
reader changed.
"""

import collections
import json
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
READER_DIR = os.path.join(HERE, 'swiftreader')
READER_BUILD_SCRIPT = os.path.join(READER_DIR, 'build.sh')
# The files whose digest is the reader's version, in the order build.sh lists
# them to shasum.
READER_SOURCE_NAMES = ('build.sh', 'swift_refs.cpp', 'dump_format.h')

# The version of the Swift tables (swift_meta.schema_version); the reader's
# kSwiftSchemaVersion. The Objective-C tables keep PRAGMA user_version, which
# the extractor owns, so the Swift tables are versioned on their own.
SWIFT_SCHEMA_VERSION = 3
SWIFT_TABLES = ('swift_ref', 'swift_objc_decl', 'swift_input', 'swift_inactive', 'swift_protocol', 'swift_unit',
                'swift_failure', 'swift_meta')
SWIFT_SCHEMA = [
    'CREATE TABLE IF NOT EXISTS swift_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    # One row per module. assertion_count: the compiler's assertion failures
    # (it runs with -Xllvm -assert-continue); error_count: its error
    # diagnostics; unresolved_count: references whose node has no type
    # (unresolved), which are not recorded; underivable_count: Swift
    # declarations visible to Objective-C whose selector is not known;
    # unknown_node_kinds: the node kinds of the dump in none of the reader's
    # tables (dump_format.h), "KIND COUNT, ..."; unknown_access_kinds: the
    # parents (KIND.KEY) that left a property access unknown, with counts.
    'CREATE TABLE IF NOT EXISTS swift_unit(id INTEGER PRIMARY KEY, module TEXT NOT NULL UNIQUE, '
    'target TEXT NOT NULL, cmd_digest TEXT NOT NULL, file_list_digest TEXT NOT NULL, '
    'compiler_version TEXT NOT NULL, reader_version TEXT NOT NULL, extracted_at TEXT NOT NULL, '
    'assertion_count INTEGER NOT NULL, file_count INTEGER NOT NULL, error_count INTEGER NOT NULL, '
    'unresolved_count INTEGER NOT NULL, underivable_count INTEGER NOT NULL, migration_scope TEXT NOT NULL, '
    "unknown_node_kinds TEXT NOT NULL DEFAULT '', unknown_access_kinds TEXT NOT NULL DEFAULT '')",
    # kind: swift (a file of the module), header, module (a .swiftmodule,
    # .swiftinterface or module map), file-list, other.
    'CREATE TABLE IF NOT EXISTS swift_input(unit INTEGER NOT NULL REFERENCES swift_unit(id), path TEXT NOT NULL, '
    'digest TEXT NOT NULL, kind TEXT NOT NULL, PRIMARY KEY(unit, path)) WITHOUT ROWID',
    # kind: call, init, property, selector-expr, keypath, dynamic.
    # selector: from the USR ((im) or (cm)), or for a #selector that names a
    # private Swift method, that method's selector; NULL for a property.
    # property: the property's name ((py), (cpy)). access (property refs):
    # get, set, getset or unknown (the use passes through a node the reader
    # does not classify: queries count it as both a read and a write).
    # selector_kind (selector-expr): method,
    # getter or setter. implicit: written by the compiler (an inherited
    # initializer's call of super.init).
    'CREATE TABLE IF NOT EXISTS swift_ref(id INTEGER PRIMARY KEY, unit INTEGER NOT NULL REFERENCES swift_unit(id), '
    'file TEXT NOT NULL, line INTEGER NOT NULL, col INTEGER NOT NULL, kind TEXT NOT NULL, usr TEXT NOT NULL, '
    'selector TEXT, property TEXT, class_name TEXT, container_kind TEXT, is_class_method INTEGER NOT NULL, '
    'access TEXT, selector_kind TEXT, implicit INTEGER NOT NULL, enclosing_usr TEXT, enclosing_name TEXT, '
    'in_closure INTEGER NOT NULL, in_macro INTEGER NOT NULL, receiver_type TEXT, '
    'in_migration_scope INTEGER NOT NULL)',
    # Swift declarations visible to Objective-C. kind: method, init,
    # property, getter, setter. selector_source: usr (the compiler's, from
    # the USR), objc_attr (the compiler's, recorded on the @objc attribute),
    # explicit (@objc(name)), derived (from the Swift name), underivable
    # (selector NULL). derived_selector: always the derivation from the
    # Swift name, for validation.
    'CREATE TABLE IF NOT EXISTS swift_objc_decl(id INTEGER PRIMARY KEY, '
    'unit INTEGER NOT NULL REFERENCES swift_unit(id), usr TEXT NOT NULL, selector TEXT, derived_selector TEXT, '
    'selector_source TEXT NOT NULL, swift_name TEXT NOT NULL, class_name TEXT, kind TEXT NOT NULL, '
    'is_class_member INTEGER NOT NULL, file TEXT NOT NULL, line INTEGER NOT NULL, access TEXT, '
    'is_private INTEGER NOT NULL, selector_derived INTEGER NOT NULL, explicit_name INTEGER NOT NULL, '
    'is_override INTEGER NOT NULL, overrides_usr TEXT, property_usr TEXT, implicit INTEGER NOT NULL, '
    'in_migration_scope INTEGER NOT NULL)',
    # #if clauses of a file that no node of the dump is in (the dump has
    # nothing of an inactive clause): found in the source text by the reader,
    # those that hold code; start_line..end_line is the clause's content.
    # undetermined = 1: the reader's lexer could not tell the file's #if
    # clauses (a line beginning with #if inside a comment or string literal
    # whose start it is not sure of, after a bare regex literal), and the
    # row is the whole file.
    'CREATE TABLE IF NOT EXISTS swift_inactive(unit INTEGER NOT NULL REFERENCES swift_unit(id), file TEXT NOT NULL, '
    'start_line INTEGER NOT NULL, end_line INTEGER NOT NULL, undetermined INTEGER NOT NULL DEFAULT 0)',
    # Swift protocols (not @objc) and the Objective-C classes that conform
    # to them. The dump names the requirement a Swift call goes through, not
    # the method that witnesses it, so a call through a requirement that an
    # Objective-C method or property witnesses is not a swift_ref row; these
    # rows let reach name the protocols as possible indirect callers. kind:
    # requirement (member: its base name), default (a member of an extension
    # of the protocol), conformance (an extension of the Objective-C class
    # class_name that declares the conformance; member: the base names of the
    # members that extension declares, space-separated, '' for none).
    'CREATE TABLE IF NOT EXISTS swift_protocol(unit INTEGER NOT NULL REFERENCES swift_unit(id), kind TEXT NOT NULL, '
    'protocol_usr TEXT NOT NULL, protocol_name TEXT NOT NULL, member TEXT, class_name TEXT, file TEXT NOT NULL, '
    'line INTEGER NOT NULL)',
    'CREATE TABLE IF NOT EXISTS swift_failure(module TEXT PRIMARY KEY, status INTEGER NOT NULL, '
    'reason TEXT NOT NULL, failed_at TEXT NOT NULL)',
    'CREATE INDEX IF NOT EXISTS swift_ref_selector ON swift_ref(selector)',
    'CREATE INDEX IF NOT EXISTS swift_ref_usr ON swift_ref(usr)',
    'CREATE INDEX IF NOT EXISTS swift_ref_property ON swift_ref(property)',
    'CREATE INDEX IF NOT EXISTS swift_ref_unit ON swift_ref(unit)',
    'CREATE INDEX IF NOT EXISTS swift_objc_decl_selector ON swift_objc_decl(selector)',
    'CREATE INDEX IF NOT EXISTS swift_objc_decl_usr ON swift_objc_decl(usr)',
    'CREATE INDEX IF NOT EXISTS swift_objc_decl_unit ON swift_objc_decl(unit)',
    'CREATE INDEX IF NOT EXISTS swift_protocol_protocol ON swift_protocol(protocol_usr)',
]

# The fragments directory's Swift capture.
CAPTURE_DIR = 'swift'
DRIVERS_FILE = 'drivers.jsonl'
FILELISTS_DIR = 'filelists'
VARIANT = 'Variant-NoSanitizers'
# The memory limit for one module's compiler and reader together.
GUARD_LIMIT_KB = 6000000
# The time limit for one module's extraction, all its steps together (the
# largest module takes a few minutes); the process group of the step that
# runs out of time is killed and the module is recorded as failed.
MODULE_TIMEOUT_SECONDS = 900

# --- Translation of a captured driver command ---------------------------------

# Driver flags without a value that are dropped: they write build products,
# drive incremental or explicit-module builds, or only affect code
# generation, warnings-as-errors or output formatting.
DROP_SWIFT_SINGLE = {
    '-c', '-enable-batch-mode', '-incremental', '-save-temps', '-explicit-module-build', '-emit-dependencies',
    '-emit-module', '-serialize-diagnostics', '-validate-clang-modules-once', '-emit-const-values',
    '-emit-localized-strings', '-emit-objc-header', '-experimental-emit-module-separately', '-disable-cmo',
    '-profile-coverage-mapping', '-profile-generate', '-warnings-as-errors', '-emit-library', '-emit-executable',
    '-whole-module-optimization', '-wmo', '-index-ignore-system-modules', '-use-frontend-parseable-output',
    '-parseable-output',
}
# Driver flags followed by one value that are dropped with it.
DROP_SWIFT_WITH_VALUE = {
    '-output-file-map', '-module-cache-path', '-clang-scanner-module-cache-path', '-sdk-module-cache-path',
    '-emit-module-path', '-dependency-scan-serialize-diagnostics-path', '-clang-build-session-file',
    '-const-gather-protocols-list', '-emit-localized-strings-path', '-emit-objc-header-path', '-index-store-path',
    '-o', '-emit-module-interface-path', '-emit-private-module-interface-path', '-pch-output-dir',
    '-index-unit-output-path', '-emit-abi-descriptor-path', '-emit-module-source-info-path', '-emit-module-doc-path',
}
# -Xcc values that are dropped (Xcode's module cache housekeeping), and those
# dropped with the -Xcc value that follows (-Xcc -ivfsstatcache -Xcc PATH: a
# cache of Xcode's).
DROP_XCC_PREFIXES = ('-fmodules-prune-interval', '-fmodules-prune-after')
DROP_XCC_WITH_VALUE = {'-ivfsstatcache'}
DROP_XFRONTEND = {'-serialize-debugging-options'}


def translate_swift_command(driver_args, module_cache, sdk_path, file_list=None):
    """Translate a captured `swiftc` driver command (argv[0] is swiftc) into
    one that type-checks the module without writing a build product or
    reading Xcode's caches.

    Returns (args, dropped): args keeps argv[0]; dropped lists every removed
    argument with its value, in order.

    Dropped: every flag in DROP_SWIFT_SINGLE and DROP_SWIFT_WITH_VALUE (with
    its value), -j<N>, -Xcc -fmodules-prune-*, -Xcc -ivfsstatcache -Xcc PATH,
    -Xfrontend -serialize-debugging-options. Replaced: -sdk (the SDK xcrun
    reports now), the @response file (the file list captured with the
    command, when file_list is given). Added: -module-cache-path
    module_cache (a private implicit-module cache).
    """
    a = list(driver_args)
    out = [a[0]]
    dropped = []
    i = 1
    while i < len(a):
        x = a[i]
        nxt = a[i + 1] if i + 1 < len(a) else None
        if x in DROP_SWIFT_SINGLE or (x.startswith('-j') and x[2:].isdigit()):
            dropped.append(x)
            i += 1
            continue
        if x in DROP_SWIFT_WITH_VALUE:
            dropped += [x] + ([nxt] if nxt is not None else [])
            i += 2
            continue
        if x == '-Xcc' and nxt is not None:
            if nxt.startswith(DROP_XCC_PREFIXES):
                dropped += [x, nxt]
                i += 2
                continue
            if nxt in DROP_XCC_WITH_VALUE:
                dropped += a[i:i + 4]
                i += 4
                continue
        if x == '-Xfrontend' and nxt in DROP_XFRONTEND:
            dropped += [x, nxt]
            i += 2
            continue
        if x == '-sdk' and nxt is not None:
            out += ['-sdk', sdk_path]
            i += 2
            continue
        if x.startswith('@') and file_list is not None:
            out.append('@' + file_list)
            i += 1
            continue
        out.append(x)
        i += 1
    out += ['-module-cache-path', module_cache]
    return out, dropped


def dropped_summary(dropped):
    """{flag: count} of a dropped list, values folded into their flag."""
    counts = collections.Counter()
    i = 0
    while i < len(dropped):
        x = dropped[i]
        if x in DROP_SWIFT_WITH_VALUE:
            counts[x] += 1
            i += 2
            continue
        if x == '-Xcc' and i + 1 < len(dropped):
            y = dropped[i + 1]
            if y in DROP_XCC_WITH_VALUE:
                counts['-Xcc %s -Xcc PATH' % y] += 1
                i += 4
                continue
            counts['-Xcc ' + y.split('=')[0]] += 1
            i += 2
            continue
        if x == '-Xfrontend' and i + 1 < len(dropped):
            counts['-Xfrontend ' + dropped[i + 1]] += 1
            i += 2
            continue
        counts['-j<N>' if x.startswith('-j') else x] += 1
        i += 1
    return dict(counts)


def option_value(args, flag):
    for i, x in enumerate(args[:-1]):
        if x == flag:
            return args[i + 1]
    return None


def parse_print_jobs(text):
    """The jobs -driver-print-jobs printed, as argument lists."""
    return [shlex.split(line) for line in text.splitlines() if line.strip()]


def frontend_dump_job(jobs, files, file_list_path, extra=()):
    """One frontend process that dumps every file of the module: the driver's
    first -dump-ast job with every file as a primary file and `-o -` for each
    (one JSON document per file on stdout), the bridging header instead of
    the driver's temporary precompiled header, and -Xllvm -assert-continue.

    jobs is parse_print_jobs() output; files the module's files; the module's
    files are passed with -filelist file_list_path. Raises ValueError when the
    jobs do not have the expected shape."""
    pch = [j for j in jobs if '-emit-pch' in j]
    dumps = [j for j in jobs if '-dump-ast' in j and '-frontend' in j]
    if not dumps:
        raise ValueError('the driver printed no -dump-ast frontend job')
    primaries = set()
    for j in dumps:
        for i, x in enumerate(j[:-1]):
            if x == '-primary-file':
                primaries.add(j[i + 1])
    if primaries != set(files):
        raise ValueError('the driver\'s frontend jobs have %d primary files; the file list has %d (%s)' % (
            len(primaries), len(files), ', '.join(sorted(set(files) ^ primaries)[:3])))
    header_for = {}
    for j in pch:
        if '-o' in j:
            header_for[j[j.index('-o') + 1]] = j[-1]
    template = dumps[0]
    fileset = set(files)
    out = []
    i = 0
    while i < len(template):
        x = template[i]
        if x in ('-primary-file', '-o', '-filelist', '-primary-filelist', '-supplementary-output-file-map'):
            i += 2
            continue
        if x == '-import-objc-header' and i + 1 < len(template):
            out += [x, header_for.get(template[i + 1], template[i + 1])]
            i += 2
            continue
        if x in fileset:
            i += 1
            continue
        out.append(x)
        i += 1
    out += ['-filelist', file_list_path]
    for f in files:
        out += ['-primary-file', f]
    for _ in files:
        out += ['-o', '-']
    out += ['-Xllvm', '-assert-continue'] + list(extra)
    return out


def dependency_job(dump_job, files, deps_path):
    """The same job as a type check of one file that writes the dependency
    information (-emit-dependencies-path), which -dump-ast does not write:
    the module's files, the bridging header, the headers it reads and the
    modules it imports."""
    out = []
    i = 0
    while i < len(dump_job):
        x = dump_job[i]
        if x == '-dump-ast':
            out.append('-typecheck')
            i += 1
            continue
        if x == '-dump-ast-format':
            i += 2
            continue
        if x in ('-primary-file', '-o'):
            i += 2
            continue
        if x == '-Xllvm' and i + 1 < len(dump_job) and dump_job[i + 1] == '-assert-continue':
            i += 2
            continue
        out.append(x)
        i += 1
    out += ['-primary-file', files[0], '-emit-dependencies-path', deps_path]
    return out


def parse_dependency_file(text):
    """The prerequisites of a make-style dependency file."""
    text = text.replace('\\\n', ' ')
    paths = []
    for line in text.splitlines():
        if ':' not in line:
            continue
        # The target is before the first ': '.
        rest = line.split(': ', 1)[1] if ': ' in line else line.split(':', 1)[1]
        cur = ''
        k = 0
        while k < len(rest):
            ch = rest[k]
            if ch == '\\' and k + 1 < len(rest):
                cur += rest[k + 1]
                k += 2
                continue
            if ch.isspace():
                if cur:
                    paths.append(cur)
                cur = ''
            else:
                cur += ch
            k += 1
        if cur:
            paths.append(cur)
    seen = set()
    return [p for p in paths if not (p in seen or seen.add(p))]


def input_kind(path):
    if path.endswith('.swift'):
        return 'swift'
    if path.endswith(('.h', '.hpp', '.hh', '.pch')):
        return 'header'
    if path.endswith(('.swiftmodule', '.swiftinterface', '.modulemap', '.pcm', '.swiftdoc', '.swiftsourceinfo')):
        return 'module'
    return 'other'


# --- Capture ------------------------------------------------------------------

def driver_lines(log_path):
    """[(target, header line, command line)] of the build log's SwiftDriver
    commands for the Variant-NoSanitizers variant, read one line at a time:
    a `SwiftDriver <target> ...` line, then, before the next such line, the
    `builtin-SwiftDriver -- .../swiftc ...` line whose command is that
    variant's."""
    found = []
    header = None
    with open(log_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if line.startswith('SwiftDriver '):
                header = line.rstrip('\n')
                continue
            if header is not None and 'builtin-SwiftDriver -- ' in line:
                command = line.strip()
                if '/%s/' % VARIANT in command:
                    found.append((header.split()[1], header, command))
                header = None
    return found


def command_args(command_line):
    """The swiftc argument list of a builtin-SwiftDriver line."""
    return shlex.split(command_line.split('builtin-SwiftDriver -- ', 1)[1])


def response_file(args):
    for x in args:
        if x.startswith('@'):
            return x[1:]
    return None


def write_swift_capture(log_path, into, log=print, project_swift=None):
    """Keep what the Swift side needs from a capture's build: the driver
    commands (drivers.jsonl) and a copy of each module's file list
    (filelists/<target>.SwiftFileList). Returns the entries written.
    project_swift: {target: Swift files} the project compiles; when it lists
    any and the log has no driver command, the capture is refused (the log
    is not what the Swift side expects: another variant, or another format)."""
    entries = driver_lines(log_path)
    with_swift = dict((t, f) for t, f in (project_swift or {}).items() if f)
    if not entries and with_swift:
        raise CaptureError('the project compiles %d Swift files (target %s), but the build log %s has no SwiftDriver '
                           'command for %s; the Swift side cannot be captured from it' % (
                               sum(len(f) for f in with_swift.values()), ', '.join(sorted(with_swift)), log_path,
                               VARIANT))
    if not entries:
        # A build with no Swift: nothing is kept, and the queries say that
        # Swift is not in the database, as before the Swift side existed.
        log('swift capture: the build log %s has no SwiftDriver command for %s; the Swift side is not captured'
            % (log_path, VARIANT))
        return []
    os.makedirs(os.path.join(into, FILELISTS_DIR), exist_ok=True)
    written = []
    with open(os.path.join(into, DRIVERS_FILE + '.tmp'), 'w', encoding='utf-8') as out:
        for target, header, command in entries:
            rsp = response_file(command_args(command))
            if rsp is None:
                raise CaptureError('the SwiftDriver command of %s names no file list' % target)
            copy = os.path.join(into, FILELISTS_DIR, target + '.SwiftFileList')
            shutil.copyfile(rsp, copy)
            out.write(json.dumps({'target': target, 'header': header, 'command': command, 'file_list': rsp}) + '\n')
            written.append((target, rsp))
    os.replace(os.path.join(into, DRIVERS_FILE + '.tmp'), os.path.join(into, DRIVERS_FILE))
    log('swift capture: %d modules: %s' % (len(written), ', '.join(t for t, _ in written)))
    return written


class CaptureError(Exception):
    pass


def parse_utc(text):
    import calendar
    return calendar.timegm(time.strptime(text.strip(), '%Y-%m-%dT%H:%M:%SZ'))


def adopt_swift_capture(fragments, log_path, accept_edited=False, out=print):
    """One time only: adopt the Swift inputs that a capture made before
    captures kept them left behind: the build log, and the .SwiftFileList
    files under Build/ that its SwiftDriver commands name. Refuses when the
    capture did not finish, when the Swift inputs were already kept, when a
    file list was written outside the capture's build (before the log was
    created or after the .captured stamp), and, unless accept_edited, when a
    listed Swift file was modified after the capture finished."""
    stamp = os.path.join(fragments, '.captured')
    into = os.path.join(fragments, CAPTURE_DIR)
    if not os.path.exists(stamp):
        raise CaptureError('the capture in %s did not finish (no .captured stamp); nothing to adopt' % fragments)
    if os.path.exists(os.path.join(into, DRIVERS_FILE)):
        raise CaptureError('%s already has the Swift inputs (%s); adopt-swift-capture is only for captures made '
                           'before captures kept them' % (fragments, os.path.join(into, DRIVERS_FILE)))
    if not os.path.exists(log_path):
        raise CaptureError('no build log at %s' % log_path)
    with open(stamp, 'r', encoding='utf-8') as f:
        finished_text = f.read().strip()
    finished = parse_utc(finished_text)
    st = os.stat(log_path)
    started = getattr(st, 'st_birthtime', None)
    entries = driver_lines(log_path)
    if not entries:
        raise CaptureError('no SwiftDriver command for %s in %s' % (VARIANT, log_path))
    problems = []
    edited = []
    for target, _, command in entries:
        rsp = response_file(command_args(command))
        if rsp is None or not os.path.exists(rsp):
            problems.append('%s: its file list %s is gone' % (target, rsp))
            continue
        mtime = os.path.getmtime(rsp)
        if mtime > finished + 1:
            problems.append('%s: its file list %s was written at %s, after the capture finished (%s)' % (
                target, rsp, time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(mtime)), finished_text))
        if started is not None and mtime < started - 1:
            problems.append('%s: its file list %s was written at %s, before the capture\'s build log was created' % (
                target, rsp, time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(mtime))))
        with open(rsp, 'r', encoding='utf-8') as f:
            for line in f:
                p = line.strip()
                if p and os.path.exists(p) and os.path.getmtime(p) > finished + 1:
                    edited.append((target, p))
    if problems:
        raise CaptureError('refusing to adopt the Swift inputs:\n  ' + '\n  '.join(problems))
    if edited and not accept_edited:
        raise CaptureError('refusing to adopt the Swift inputs: %d listed Swift files were modified after the '
                           'capture finished (%s), so the file lists cannot be shown to describe the modules as '
                           'they are now:\n  %s\nPass --accept-edited-files to adopt them anyway: an edit to a '
                           'file\'s contents is detected by its digest, and a Swift file added to or removed from a '
                           'target of the project since the capture is reported by every query, which then exits 3.'
                           % (
                               len(edited), finished_text, '\n  '.join('%s (%s)' % (p, t) for t, p in edited)))
    written = write_swift_capture(log_path, into, log=lambda m: None)
    out('adopt-swift-capture: from %s, kept the SwiftDriver commands of %d modules (%s) and copies of their file '
        'lists in %s.' % (log_path, len(written), ', '.join(t for t, _ in written), into))
    out('adopt-swift-capture: checked: each file list was written between the creation of the build log (%s) and '
        'the end of the capture (%s).' % (
            time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(started)) if started else 'unknown', finished_text))
    if edited:
        out('adopt-swift-capture: you accepted that these %d listed files were modified after the capture (their '
            'contents are compared by digest at every update and query): %s' % (
                len(edited), ', '.join(p for _, p in edited)))
    else:
        out('adopt-swift-capture: no listed Swift file was modified after the capture.')
    out('adopt-swift-capture: you assert that these file lists and commands are the ones the capture\'s build used '
        'for these modules. Swift files added to or removed from a target of iTerm2.xcodeproj since then are '
        'detected by comparing the lists with the project; for modules built by other projects (Companion, '
        'WebExtensionsFramework) they are not.')
    out('adopt-swift-capture: if a file list does not describe its module, queries can exit 0 or 1 with Swift '
        'references missing. Capture again with capture_compile_commands.sh to replace this.')
    return written


# --- Modules ------------------------------------------------------------------

Module = collections.namedtuple('Module', 'name target driver_args file_list files outside')


def read_swift_capture(fragments, root):
    """(included, excluded): the captured modules, as Module tuples. A module
    is included when every one of its files is inside the repository (files
    generated under Build/ count as inside: they are compiled with the
    module, but no rows are recorded for them); a module with a file outside
    the repository (a Swift package checkout) is excluded, as the
    Objective-C side excludes units whose main file is outside it. Returns
    None when the capture kept no Swift inputs."""
    path = os.path.join(fragments, CAPTURE_DIR, DRIVERS_FILE)
    if not os.path.exists(path):
        return None
    root = os.path.realpath(root)
    included, excluded = [], []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            e = json.loads(line)
            args = command_args(e['command'])
            copy = os.path.join(fragments, CAPTURE_DIR, FILELISTS_DIR, e['target'] + '.SwiftFileList')
            with open(copy, 'r', encoding='utf-8') as fl:
                files = [x.strip() for x in fl if x.strip()]
            outside = [x for x in files if not os.path.realpath(x).startswith(root + os.sep)]
            m = Module(option_value(args, '-module-name') or e['target'], e['target'], args, copy, files, outside)
            (excluded if outside else included).append(m)
    return included, excluded


def stored_path(path, root):
    real = os.path.realpath(path)
    root = os.path.realpath(root)
    return real[len(root) + 1:] if real.startswith(root + os.sep) else real


def file_list_digest(module):
    with open(module.file_list, 'rb') as f:
        return _sha256(f.read())


def _sha256(data):
    import hashlib
    return hashlib.sha256(data).hexdigest()


# --- The reader and the compiler -------------------------------------------

def swift_reader_source_digest(directory=READER_DIR):
    import hashlib

    def file_digest(p):
        with open(p, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    listing = ''.join('%s  %s\n' % (file_digest(os.path.join(directory, n)), n) for n in READER_SOURCE_NAMES)
    return hashlib.sha256(listing.encode('utf-8')).hexdigest()


def reader_version(exe):
    """(source digest, dump format version written against) the reader
    reports, or (None, None)."""
    if not os.path.exists(exe):
        return None, None
    try:
        out = subprocess.run([exe, '--version'], capture_output=True, text=True, timeout=60).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return None, None
    if len(out) < 3 or out[0] != 'swift_refs':
        return None, None
    return out[1], out[2]


_COMPILER_VERSIONS = {}


def compiler_version(swiftc):
    """The first line of `swiftc -version` ("Apple Swift version 6.4
    (swiftlang-...)"), the same text as the dump's compiler_version.full,
    or None. Asked once per process."""
    if swiftc not in _COMPILER_VERSIONS:
        try:
            r = subprocess.run([swiftc, '-version'], capture_output=True, text=True, timeout=120)
            first = (r.stdout or r.stderr).splitlines()[0].strip() if (r.stdout or r.stderr) else None
        except (OSError, subprocess.SubprocessError, IndexError):
            first = None
        _COMPILER_VERSIONS[swiftc] = first
    return _COMPILER_VERSIONS[swiftc]


def major_minor(version_text):
    m = re.search(r'Swift version (\d+)\.(\d+)', version_text or '')
    return '%s.%s' % m.groups() if m else None


def ensure_schema(con):
    """Create the Swift tables, replacing them if they have another schema
    version. The Objective-C tables are not touched."""
    names = set(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'"))
    if 'swift_meta' in names:
        row = con.execute("SELECT value FROM swift_meta WHERE key='schema_version'").fetchone()
        if row is None or row[0] != str(SWIFT_SCHEMA_VERSION):
            with con:
                for t in SWIFT_TABLES:
                    con.execute('DROP TABLE IF EXISTS %s' % t)
    with con:
        for sql in SWIFT_SCHEMA:
            con.execute(sql)
        con.execute("INSERT OR REPLACE INTO swift_meta(key, value) VALUES('schema_version', ?)",
                    (str(SWIFT_SCHEMA_VERSION),))


def has_swift_tables(con):
    names = set(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'"))
    if 'swift_meta' not in names:
        return False
    row = con.execute("SELECT value FROM swift_meta WHERE key='schema_version'").fetchone()
    return row is not None and row[0] == str(SWIFT_SCHEMA_VERSION)


# --- Module states --------------------------------------------------------------

ModuleState = collections.namedtuple('ModuleState', 'module target unit state reason assertions')


# What stands for the module cache's path in a command's digest.
MODULE_CACHE_PLACEHOLDER = '@MODULE_CACHE@'


class SwiftContext:
    """What both update and the queries need to judge the Swift modules: the
    capture, the translated command of each module, the compiler and reader
    versions."""

    def __init__(self, paths, migration_scope_text, sdk_path, project_swift=None):
        """project_swift() returns {target: set of relative paths} of the
        Swift files each target of the main project compiles, or None."""
        self.paths = paths
        self.capture = read_swift_capture(paths.fragments, paths.root)
        self.migration_scope_text = migration_scope_text
        self.sdk_path = sdk_path
        self.modules = self.capture[0] if self.capture else []
        self.excluded = self.capture[1] if self.capture else []
        self.swiftc = self.modules[0].driver_args[0] if self.modules else None
        self.compiler = compiler_version(self.swiftc) if self.swiftc else None
        self.reader_digest = swift_reader_source_digest()
        # {module: (added, removed)}: the captured file lists compared with
        # the project, for the modules whose target is in it.
        self.project_mismatch = {}
        self.not_compared = []
        sources = project_swift() if (project_swift is not None and self.modules) else None
        for m in self.modules:
            if sources is None or m.target not in sources:
                self.not_compared.append(m.name)
                continue
            listed = set(stored_path(f, paths.root) for f in m.files)
            listed = set(f for f in listed if not f.startswith('Build/') and not os.path.isabs(f))
            added, removed = sorted(sources[m.target] - listed), sorted(listed - sources[m.target])
            if added or removed:
                self.project_mismatch[m.name] = (added, removed)

    @property
    def captured(self):
        return self.capture is not None

    def translated(self, module):
        return translate_swift_command(module.driver_args, self.paths.swift_module_cache, self.sdk_path,
                                       file_list=module.file_list)

    def cmd_digest(self, module):
        # Independent of the module cache's path, so that a copy of the
        # database updated with another work directory is current here.
        args, _ = translate_swift_command(module.driver_args, MODULE_CACHE_PLACEHOLDER, self.sdk_path,
                                          file_list=module.file_list)
        return _sha256(b'\0'.join(x.encode('utf-8') for x in args))


def module_states(con, ctx, digests):
    """{module name: ModuleState} for every captured module and every module
    in the database. States: current, stale (with the reason), missing,
    failed, orphan (in the database, no longer captured)."""
    units = {}
    failures = {}
    stale_inputs = {}
    if has_swift_tables(con):
        for row in con.execute('SELECT id, module, target, cmd_digest, file_list_digest, compiler_version, '
                               'reader_version, migration_scope, assertion_count FROM swift_unit'):
            units[row[1]] = row
        for module, reason in con.execute('SELECT module, reason FROM swift_failure'):
            failures[module] = reason
        for unit, path, digest in con.execute('SELECT unit, path, digest FROM swift_input ORDER BY unit, path'):
            if unit in stale_inputs:
                continue
            now = digests.digest(path)
            if now is None:
                stale_inputs[unit] = 'input missing: ' + path
            elif now != digest:
                stale_inputs[unit] = 'input changed: ' + path
    wanted = dict((m.name, m) for m in ctx.modules)
    states = {}
    for name in sorted(set(wanted) | set(units)):
        u = units.get(name)
        m = wanted.get(name)
        unit_id = u[0] if u else None
        assertions = u[8] if u else None
        target = m.target if m else u[2]
        if m is not None and name in failures:
            state, reason = 'failed', 'last extraction failed: ' + failures[name]
        elif m is not None and u is None:
            state, reason = 'missing', 'missing from the database'
        elif m is None:
            state, reason = 'orphan', 'not a captured module'
        elif u[3] != ctx.cmd_digest(m):
            state, reason = 'stale', 'command changed'
        elif u[4] != file_list_digest(m):
            state, reason = 'stale', 'file list changed'
        elif ctx.compiler is None:
            state, reason = 'stale', 'compiler unknown: %s cannot report its version' % ctx.swiftc
        elif u[5] != ctx.compiler:
            state, reason = 'stale', 'compiler changed'
        elif u[6] != ctx.reader_digest:
            state, reason = 'stale', 'reader changed'
        elif u[7] != ctx.migration_scope_text:
            state, reason = 'stale', 'migration scope changed'
        elif unit_id in stale_inputs:
            state, reason = 'stale', stale_inputs[unit_id]
        else:
            state, reason = 'current', None
        states[name] = ModuleState(name, target, unit_id, state, reason, assertions)
    return states


# --- Extraction -----------------------------------------------------------------

class SwiftError(Exception):
    pass


# codedb.run_in_group's status for a command that ran out of time.
TIMEOUT_STATUS = 124


def ensure_reader(paths, run_in_group, log=print, lock=None):
    want = swift_reader_source_digest()
    if getattr(paths, 'swift_reader_prebuilt', False):
        # Used as it is (a deliberately mutated build, say): never rebuilt.
        if not os.path.exists(paths.swift_reader):
            raise SwiftError('the prebuilt Swift reader %s does not exist; build it with swiftreader/build.sh PATH'
                             % paths.swift_reader)
        return
    have, _ = reader_version(paths.swift_reader)
    if have == want:
        return
    log('building the Swift reader (%s)' % ('none at %s' % paths.swift_reader if have is None
                                             else 'its sources changed'))
    status, err = run_in_group([paths.guard, '--', READER_BUILD_SCRIPT, paths.swift_reader], capture=True, lock=lock)
    if status != 0:
        raise SwiftError('the Swift reader build failed (status %d): %s' % (status, err.strip()[-2000:]))
    have, _ = reader_version(paths.swift_reader)
    if have != want:
        raise SwiftError('the Swift reader at %s reports source digest %s after a build; expected %s' % (
            paths.swift_reader, have, want))


def record_failure(db, module, failure):
    con = sqlite3.connect(db)
    con.execute('PRAGMA busy_timeout=60000')
    try:
        with con:
            if failure is None:
                con.execute('DELETE FROM swift_failure WHERE module=?', (module,))
            else:
                con.execute('INSERT OR REPLACE INTO swift_failure(module, status, reason, failed_at) VALUES(?,?,?,?)',
                            (module, failure[0], failure[1], time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())))
    finally:
        con.close()


def read_peak(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def extract_module(paths, ctx, module, run_in_group, scope_dirs, lock=None, log=print, accept_version=False):
    """Read one module into the database. Returns (ok, facts) where facts is
    a dict of what was measured; on failure the module is recorded as failed
    and its earlier rows, if any, are left as they were. The compiler runs
    in the repository's root, as Xcode runs it in the project's directory
    (the captured commands can have relative paths)."""
    work = os.path.join(paths.swift_work, module.name)
    os.makedirs(work, exist_ok=True)
    os.makedirs(paths.swift_module_cache, exist_ok=True)
    facts = {'module': module.name, 'files': len(module.files)}
    t0 = time.time()
    deadline = t0 + MODULE_TIMEOUT_SECONDS
    args, dropped = ctx.translated(module)
    facts['dropped'] = dropped_summary(dropped)

    def remaining():
        return max(1, deadline - time.time())

    def failed(status, why):
        if status == TIMEOUT_STATUS:
            why = 'timed out after %d s (the time limit of one module); %s' % (MODULE_TIMEOUT_SECONDS, why)
        record_failure(paths.db, module.name, (status, why))
        facts['failure'] = why
        return False, facts

    # 1. The frontend job, from the compiler's own driver.
    status, out, err = run_capture(run_in_group, args + ['-dump-ast', '-dump-ast-format', 'json',
                                                         '-driver-print-jobs'], lock=lock, timeout=remaining(),
                                   cwd=paths.root)
    if status != 0:
        return failed(status, 'the driver could not print the jobs: %s' % err.strip()[-1000:])
    files_path = os.path.join(work, 'files.txt')
    with open(files_path, 'w', encoding='utf-8') as f:
        f.write(''.join(x + '\n' for x in module.files))
    try:
        job = frontend_dump_job(parse_print_jobs(out), module.files, files_path)
    except ValueError as e:
        return failed(2, str(e))
    with open(os.path.join(work, 'frontend-job.txt'), 'w', encoding='utf-8') as f:
        f.write(' '.join(shlex.quote(x) for x in job) + '\n')
    # 2. The dependency information.
    deps_path = os.path.join(work, 'deps.d')
    if os.path.exists(deps_path):
        os.remove(deps_path)
    peak_deps = os.path.join(work, 'peak-deps')
    status, err = run_in_group([paths.guard, '--limit-kb', str(GUARD_LIMIT_KB), '--peak-file', peak_deps, '--']
                               + dependency_job(job, module.files, deps_path), capture=True, lock=lock,
                               timeout=remaining(), cwd=paths.root)
    facts['deps_seconds'] = time.time() - t0
    facts['deps_peak_kb'] = read_peak(peak_deps)
    if status != 0 or not os.path.exists(deps_path):
        return failed(status or 2, 'the dependency run failed (status %d): %s' % (status, err.strip()[-1000:]))
    with open(deps_path, 'r', encoding='utf-8', errors='replace') as f:
        deps = parse_dependency_file(f.read())
    inputs = collections.OrderedDict()
    for p in list(module.files) + deps:
        if p == '-':
            continue
        # The compiler ran in the repository: a relative path (a header
        # found through a relative -I) is relative to it.
        p = os.path.join(paths.root, p)
        sp = stored_path(p, paths.root)
        if sp in inputs:
            continue
        try:
            inputs[sp] = (_file_sha256(p), input_kind(p))
        except OSError:
            return failed(2, 'cannot read input %s' % p)
    inputs_path = os.path.join(work, 'inputs.tsv')
    with open(inputs_path, 'w', encoding='utf-8') as f:
        for sp, (digest, kind) in inputs.items():
            f.write('%s\t%s\t%s\n' % (sp, digest, kind))
    facts['inputs'] = len(inputs)
    # 3. The compiler and the reader.
    t1 = time.time()
    peak = os.path.join(work, 'peak-dump')
    stderr_file = os.path.join(work, 'compiler-stderr.txt')
    cmd = [paths.guard, '--limit-kb', str(GUARD_LIMIT_KB), '--peak-file', peak, '--', paths.swift_reader,
           '--db', paths.db, '--root', paths.root, '--module', module.name, '--target', module.target,
           '--cmd-digest', ctx.cmd_digest(module), '--file-list-digest', file_list_digest(module),
           '--files', files_path, '--inputs', inputs_path, '--compiler-version', ctx.compiler or '',
           '--stderr-file', stderr_file]
    if accept_version:
        cmd.append('--accept-compiler-version')
    for d in scope_dirs:
        cmd += ['--migration-scope', d]
    cmd += ['--'] + job
    status, out, err = run_capture(run_in_group, cmd, lock=lock, timeout=remaining(), cwd=paths.root)
    facts['dump_seconds'] = time.time() - t1
    facts['guard_peak_kb'] = read_peak(peak)
    if status != 0:
        why = 'killed by the memory watchdog' if status == 137 else (err.strip().splitlines() or ['status %d' % status])[-1]
        return failed(status, why)
    facts.update(reader_facts(out))
    record_failure(paths.db, module.name, None)
    facts['seconds'] = time.time() - t0
    return True, facts


UNKNOWN_KINDS_LINE = 'swift_refs: node kinds this reader does not know: '
UNKNOWN_ACCESS_LINE = 'swift_refs: property accesses left unknown, by the parent that is not classified: '


def reader_facts(out):
    """The counts the reader printed on its summary line, and the texts of
    its lines naming unknown node kinds (unknown_kinds_text) and the parents
    that left accesses unknown (unknown_access_text)."""
    facts = {}
    for line in out.splitlines():
        if line.startswith(UNKNOWN_KINDS_LINE):
            facts['unknown_kinds_text'] = line[len(UNKNOWN_KINDS_LINE):]
        elif line.startswith(UNKNOWN_ACCESS_LINE):
            facts['unknown_access_text'] = line[len(UNKNOWN_ACCESS_LINE):]
        elif line.startswith('swift_refs: documents '):
            words = line[len('swift_refs: '):].split()
            for k, v in zip(words[0::2], words[1::2]):
                facts[k] = int(v)
    return facts


def result_lines(prefix, facts):
    """What update prints for a module read successfully."""
    lines = ['%s: ok %.0fs: %d refs, %d declarations, %d assertions, %d errors, %d unresolved, %d underivable, '
             '%d property accesses unknown; compiler peak %s MB, reader peak %s MB, dependency run peak %s MB' % (
                 prefix, facts.get('seconds', 0), facts.get('refs', 0), facts.get('decls', 0),
                 facts.get('assertions', 0), facts.get('errors', 0), facts.get('unresolved', 0),
                 facts.get('underivable', 0), facts.get('unknown_access', 0), _mb(facts.get('compiler_peak_kb')),
                 _mb(facts.get('reader_peak_kb')), _mb(facts.get('deps_peak_kb')))]
    if facts.get('unknown_kinds_text'):
        lines.append('%s: WARNING: node kinds the reader does not know (classify them in swiftreader/dump_format.h): '
                     '%s' % (prefix, facts['unknown_kinds_text']))
    if facts.get('unknown_access_text'):
        lines.append('%s: property accesses left unknown, by the parent that is not classified: %s' % (
            prefix, facts['unknown_access_text']))
    if facts.get('undetermined_files'):
        lines.append('%s: %d files whose inactive #if regions could not be determined (searched whole by reach)' % (
            prefix, facts['undetermined_files']))
    return lines


def _file_sha256(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def run_capture(run_in_group, cmd, lock=None, timeout=None, cwd=None):
    """run_in_group with stdout and stderr kept: (status, stdout, stderr)."""
    with tempfile.TemporaryFile('w+') as out:
        status, err = run_in_group(cmd, capture=True, lock=lock, stdout=out, timeout=timeout, cwd=cwd)
        out.seek(0)
        return status, out.read(), err


def check_compiler(ctx, accept_version, written_against):
    if not ctx.compiler:
        raise SwiftError('cannot get the version of the Swift compiler %s' % ctx.swiftc)
    have = major_minor(ctx.compiler)
    if have != written_against and not accept_version:
        raise SwiftError('the Swift compiler is %s (Swift %s); the reader was written against the dump format of '
                         'Swift %s, and the format is not stable across versions. Check the reader against this '
                         'compiler\'s dump and update it: regenerate the fixture dump with '
                         'tests/swift_fixture/make_dump.py, run tests/test_codedb_swift.py and check its expected '
                         'rows, then classify the node kinds update reports as unknown in swiftreader/dump_format.h; '
                         'or pass --accept-compiler-version to read it anyway.' % (ctx.compiler, have,
                                                                                    written_against))


def update_swift(paths, ctx, run_in_group, digests, scope_dirs, lock=None, log=print, force=False,
                 accept_version=False, only=None):
    """Bring the Swift modules up to date, one at a time. Returns (counts,
    facts list)."""
    counts = {'extracted': 0, 'failed': 0, 'skipped': 0, 'removed': 0}
    facts_list = []
    if not ctx.captured:
        log('swift: the capture in %s kept no Swift inputs; run codedb.py adopt-swift-capture or capture again'
            % paths.fragments)
        return counts, facts_list
    ensure_reader(paths, run_in_group, log=log, lock=lock)
    _, written_against = reader_version(paths.swift_reader)
    check_compiler(ctx, accept_version, written_against)
    con = sqlite3.connect(paths.db)
    con.execute('PRAGMA busy_timeout=60000')
    try:
        ensure_schema(con)
        states = module_states(con, ctx, digests)
    finally:
        con.close()
    todo = []
    for m in ctx.modules:
        if only is not None and m.name not in only:
            continue
        s = states[m.name]
        if force or s.state != 'current':
            todo.append((m, 'forced' if force else s.reason))
        else:
            counts['skipped'] += 1
    for n, (m, reason) in enumerate(todo, 1):
        log('swift [%d/%d] %s (%d files): %s' % (n, len(todo), m.name, len(m.files), reason))
        ok, facts = extract_module(paths, ctx, m, run_in_group, scope_dirs, lock=lock, log=log,
                                   accept_version=accept_version)
        facts_list.append(facts)
        log('swift [%d/%d] %s: dropped from the driver command: %s' % (
            n, len(todo), m.name, ', '.join('%s x%d' % kv for kv in sorted(facts.get('dropped', {}).items()))))
        if ok:
            counts['extracted'] += 1
            for line in result_lines('swift [%d/%d] %s' % (n, len(todo), m.name), facts):
                log(line)
        else:
            counts['failed'] += 1
            log('swift [%d/%d] %s: FAILED: %s' % (n, len(todo), m.name, facts.get('failure')))
    # Modules in the database that are no longer captured.
    if only is None:
        con = sqlite3.connect(paths.db)
        con.execute('PRAGMA busy_timeout=60000')
        try:
            wanted = set(m.name for m in ctx.modules)
            with con:
                for unit, name in list(con.execute('SELECT id, module FROM swift_unit')):
                    if name not in wanted:
                        log('swift: removing module %s from the database: it is not a captured module' % name)
                        for t in ('swift_ref', 'swift_objc_decl', 'swift_input', 'swift_inactive', 'swift_protocol'):
                            con.execute('DELETE FROM %s WHERE unit=?' % t, (unit,))
                        con.execute('DELETE FROM swift_unit WHERE id=?', (unit,))
                        counts['removed'] += 1
                for (name,) in list(con.execute('SELECT module FROM swift_failure')):
                    if name not in wanted:
                        con.execute('DELETE FROM swift_failure WHERE module=?', (name,))
        finally:
            con.close()
    if ctx.excluded:
        log('swift: excluded (files outside the repository: Swift package checkouts): %s' % ', '.join(
            m.name for m in ctx.excluded))
    return counts, facts_list


def _mb(kb):
    return '?' if kb is None else str(kb // 1024)


# --- Swift files no captured module compiles --------------------------------

def uncaptured_swift_files(root, modules, list_files):
    """Swift files tracked in the repository that no captured module
    compiles, grouped by their first two path components: {group: count}.
    list_files() returns the repository's files (relative paths)."""
    compiled = set()
    for m in modules:
        for f in m.files:
            compiled.add(stored_path(f, root))
    groups = collections.Counter()
    for f in list_files():
        if f.endswith('.swift') and f not in compiled and not f.startswith('tools/swift_migration/'):
            parts = f.split('/')
            groups['/'.join(parts[:2]) if len(parts) > 2 else parts[0]] += 1
    return groups


# --- Queries --------------------------------------------------------------------

def property_candidates(con, selector):
    """(USR set, [(name, role)]) of the properties whose getter or setter is
    selector: from objc_property (Objective-C declarations in the
    repository) and swift_objc_decl (Swift getters and setters), and, for the
    shape of a setter or a unary selector, the property name it stands for
    (matched by name in the Swift references, for properties declared in
    the SDK)."""
    usrs = {}
    for usr, getter, setter in con.execute('SELECT DISTINCT usr, getter_selector, setter_selector FROM objc_property '
                                           'WHERE (getter_selector = ? OR setter_selector = ?) AND usr IS NOT NULL',
                                           (selector, selector)):
        roles = usrs.setdefault(usr, set())
        if getter == selector:
            roles.add('getter')
        if setter == selector:
            roles.add('setter')
    for usr, kind in con.execute("SELECT DISTINCT property_usr, kind FROM swift_objc_decl WHERE selector = ? AND "
                                 "kind IN ('getter', 'setter') AND property_usr IS NOT NULL", (selector,)):
        usrs.setdefault(usr, set()).add(kind)
    return usrs, property_candidates_by_name(selector)


SWIFT_REF_COLUMNS = ('r.file, r.line, r.col, r.kind, r.usr, r.selector, r.property, r.class_name, r.container_kind, '
                     'r.is_class_method, r.access, r.selector_kind, r.implicit, r.enclosing_name, r.in_closure, '
                     'r.receiver_type, r.in_migration_scope, r.unit, u.module')


def swift_refs_for(con, selector, sends_only=False):
    """The Swift references that reach selector, as dicts with a 'why' and,
    for property references, the role ('getter', 'setter' or both) by which
    they reach it. sends_only (for `sends`): only the references that send
    it: calls, initializers, dynamic lookups, property accesses by role (a
    read for a getter, a write for a setter, both for a read-modify-write or
    an unknown access) and key path components; not #selector expressions,
    which name a selector without sending it."""
    rows = []
    base = 'SELECT %s FROM swift_ref r JOIN swift_unit u ON u.id = r.unit ' % SWIFT_REF_COLUMNS
    keys = ('file', 'line', 'col', 'kind', 'usr', 'selector', 'property', 'class_name', 'container_kind',
            'is_class_method', 'access', 'selector_kind', 'implicit', 'enclosing_name', 'in_closure', 'receiver_type',
            'in_migration_scope', 'unit', 'module')
    kinds = ("'call'", "'init'", "'dynamic'") if sends_only else ("'call'", "'init'", "'dynamic'", "'selector-expr'",
                                                                   "'keypath'")
    for r in con.execute(base + 'WHERE r.selector = ? AND r.kind IN (%s)' % ','.join(kinds), (selector,)):
        d = dict(zip(keys, r))
        d['why'] = None
        rows.append(d)
    # Property references, by the role by which they reach selector: the
    # same in sends and reach (a property access sends its accessor).
    usrs, by_name = property_candidates(con, selector)
    if usrs:
        marks = ','.join('?' * len(usrs))
        for r in con.execute(base + "WHERE r.property IS NOT NULL AND r.usr IN (%s)" % marks, list(usrs)):
            d = dict(zip(keys, r))
            d['roles'] = usrs[d['usr']]
            d['why'] = 'declared'
            rows.append(d)
    for name, role in by_name:
        # Properties whose declaration is not in this database (the SDK):
        # matched by name, only where no declaration above matched.
        for r in con.execute(base + 'WHERE r.property = ? AND NOT EXISTS (SELECT 1 FROM objc_property p WHERE '
                             'p.usr = r.usr) AND NOT EXISTS (SELECT 1 FROM swift_objc_decl d WHERE '
                             'd.usr = r.usr)', (name,)):
            d = dict(zip(keys, r))
            d['roles'] = {role}
            d['why'] = 'name'
            rows.append(d)
    out = []
    seen = set()
    for d in rows:
        if d.get('roles') is not None:
            a = d['access']
            if d['kind'] != 'keypath':
                wanted = (('getter' in d['roles'] and a != 'set') or ('setter' in d['roles'] and a != 'get'))
                if not wanted:
                    continue
        key = (d['file'], d['line'], d['col'], d['kind'], d['usr'], d['module'])
        if key in seen:
            continue
        seen.add(key)
        out.append(d)
    out.sort(key=lambda d: (d['file'], d['line'], d['col'], d['kind']))
    return out


def describe_ref(d):
    """The text of one Swift reference row (without the trailing marks)."""
    parts = ['%s:%d:%d' % (d['file'], d['line'], d['col']), d['enclosing_name'] or '(file scope)']
    sign = '+' if d['is_class_method'] else '-'
    kind = d['kind']
    container = d['class_name'] or '?'
    if d['property'] is not None:
        what = 'property %s.%s%s' % (container, d['property'], ' (class property)' if d['is_class_method'] else '')
    else:
        what = '%s[%s %s]' % (sign, container, d['selector'] or '?')
    if d['container_kind'] == 'protocol':
        what += ' (protocol requirement)'
    if kind == 'call':
        text = 'call ' + what
    elif kind == 'init':
        text = 'initializer ' + what
    elif kind == 'selector-expr':
        text = '#selector (%s) %s' % (d['selector_kind'] or 'method', what)
    elif kind == 'keypath':
        text = 'key path component %s (read or written through the key path)' % what
    elif kind == 'dynamic':
        text = ('dynamic lookup %s: joined by selector only, any class that implements it can receive it' % what)
    else:
        access = d['access'] or 'unknown'
        text = 'property reference %s, access %s' % (what, access)
        if access == 'unknown':
            text += ' (counted as both getter and setter)'
    parts.append(text)
    if d.get('why') == 'name':
        parts.append('matched by the property\'s name: its declaration is not in this database')
    if d['receiver_type'] and kind in ('call', 'init'):
        parts.append('receiver ' + d['receiver_type'])
    if d['in_closure']:
        parts.append('in closure')
    if d['implicit']:
        parts.append('written by the compiler')
    parts.append('module ' + d['module'])
    return parts


def inactive_search(con, root, selector):
    """The #if clauses that produced no node of the dump (swift_inactive),
    searched as text for the forms selector can take in Swift: its first
    keyword, and for a setter-shaped, is-prefixed or unary selector the
    property it stands for. Files whose clauses the reader could not
    determine (undetermined = 1) are searched whole. Returns (clause count,
    file count, undetermined file count, forms, [(file, line, form, clause
    start, clause end, undetermined)])."""
    rows = con.execute('SELECT DISTINCT file, start_line, end_line, undetermined FROM swift_inactive ORDER BY file, '
                       'start_line').fetchall()
    clauses = [r for r in rows if not r[3]]
    undetermined = set(r[0] for r in rows if r[3])
    forms = [selector.split(':')[0]]
    for name, _ in property_candidates(con, selector)[1]:
        if (name[:1].islower() or name[1:2].isupper()) and name not in forms:
            forms.append(name)
    pattern = re.compile(r'(?<![A-Za-z0-9_])(%s)(?![A-Za-z0-9_])' % '|'.join(re.escape(f) for f in forms))
    matches = []
    by_file = collections.OrderedDict()
    for f, start, end, und in rows:
        if not und and f in undetermined:
            continue
        by_file.setdefault(f, []).append((start, end, und))
    for f, ranges in by_file.items():
        try:
            with open(os.path.join(root, f), 'r', encoding='utf-8', errors='replace') as fh:
                lines = fh.read().split('\n')
        except OSError:
            continue
        for start, end, und in ranges:
            if und:
                start, end = 1, len(lines)
            for n in range(start, min(end, len(lines)) + 1):
                m = pattern.search(lines[n - 1])
                if m:
                    matches.append((f, n, m.group(1), start, end, und))
    return len(clauses), len(set(r[0] for r in clauses)), len(undetermined), forms, matches


def write_inactive_search(con, root, selector, out, limit=50):
    """The section reach and swiftrefs print for the Swift code that is not
    compiled."""
    count, files, undetermined, forms, matches = inactive_search(con, root, selector)
    out.write('Swift code that is not compiled: %d #if clauses in %d files produced no node of the dump (inactive in '
              'this configuration, or with nothing the compiler keeps)%s; a text search of them for %s finds %d '
              'lines (possible references)%s\n' % (
                  count, files, ', and in %d files the #if regions could not be determined (searched whole)' %
                  undetermined if undetermined else '', ', '.join(forms), len(matches), ':' if matches else ''))
    for f, n, form, start, end, und in matches[:limit]:
        if und:
            out.write('  %s:%d  matched %s  in a file whose inactive #if regions could not be determined\n' % (
                f, n, form))
        else:
            out.write('  %s:%d  matched %s  in a #if clause at lines %d-%d that is not compiled\n' % (
                f, n, form, start, end))
    if len(matches) > limit:
        out.write('  ... and %d more\n' % (len(matches) - limit))


def swift_base_name_matches(selector, name):
    """Whether name, the Swift base name of a protocol requirement, can be the
    name of a Swift requirement that an Objective-C method or property with
    selector witnesses: the selector's first piece (takeFocus, doThing for
    doThing:with:), a prefix of it that ends before a capital (save for
    saveToPath:error:), or the property a getter or setter stands for
    (count for count and setCount:, enabled for isEnabled)."""
    first = selector.split(':')[0]
    if name == first or (first.startswith(name) and first[len(name):len(name) + 1].isupper()):
        return True
    return any(n == name for n, _ in property_candidates_by_name(selector))


def property_candidates_by_name(selector):
    """[(name, role)]: for the shape of a setter or a unary selector, the
    property name it stands for."""
    m = re.match(r'^set([A-Z][A-Za-z0-9_]*):$', selector)
    if m:
        name = m.group(1)
        return [(n, 'setter') for n in ([name] if name[1:2].isupper() else [name[0].lower() + name[1:], name])]
    out = []
    if selector and ':' not in selector:
        out.append((selector, 'getter'))
        m = re.match(r'^is([A-Z][A-Za-z0-9_]*)$', selector)
        if m:
            name = m.group(1)
            out.append((name[0].lower() + name[1:] if not name[1:2].isupper() else name, 'getter'))
    return out


def protocol_witness_candidates(con, selector):
    """[(protocol name, requirement, class, file, line)]: requirements of
    Swift protocols that an Objective-C class conforms to, whose base name
    matches selector, and that the conforming extension does not implement
    in Swift: Swift calls through them may reach the class's Objective-C
    method or property with selector."""
    out = []
    for proto_usr, proto, member, cls, file, line in con.execute(
            "SELECT DISTINCT c.protocol_usr, c.protocol_name, c.member, c.class_name, c.file, c.line FROM "
            "swift_protocol c WHERE c.kind = 'conformance' ORDER BY c.protocol_name, c.class_name, c.file, c.line"):
        implemented = set((member or '').split())
        for (req,) in con.execute("SELECT DISTINCT member FROM swift_protocol WHERE kind = 'requirement' AND "
                                  "protocol_usr = ? ORDER BY member", (proto_usr,)):
            if req not in implemented and swift_base_name_matches(selector, req):
                out.append((proto, req, cls, file, line))
    return out


PROTOCOL_WITNESS_HEADING = ('Swift protocols that an Objective-C class conforms to, with a requirement whose name '
                            'matches %s (possible indirect callers: a Swift call through the requirement reaches the '
                            'Objective-C method or property that witnesses it, and the dump does not name witnesses, '
                            'so those calls are not among the references above): %d')


def write_protocol_witnesses(con, selector, out, limit=50):
    """The section reach and swiftrefs print for the Swift protocols whose
    requirements selector may witness."""
    found = protocol_witness_candidates(con, selector)
    out.write(PROTOCOL_WITNESS_HEADING % (selector, len(found)) + '\n')
    for proto, req, cls, file, line in found[:limit]:
        out.write('  %s.%s  conformed to by %s at %s:%d\n' % (proto, req, cls, file, line))
    if len(found) > limit:
        out.write('  ... and %d more\n' % (len(found) - limit))


def swift_decls_for(con, selector):
    return [dict(zip(('file', 'line', 'class_name', 'swift_name', 'kind', 'is_class_member', 'selector_source',
                      'is_override', 'overrides_usr', 'implicit', 'in_migration_scope', 'unit', 'module'), r))
            for r in con.execute('SELECT d.file, d.line, d.class_name, d.swift_name, d.kind, d.is_class_member, '
                                 'd.selector_source, d.is_override, d.overrides_usr, d.implicit, '
                                 'd.in_migration_scope, d.unit, u.module FROM swift_objc_decl d JOIN swift_unit u ON '
                                 'u.id = d.unit WHERE d.selector = ? ORDER BY d.file, d.line', (selector,))]


def describe_decl(d, selector):
    sign = '+' if d['is_class_member'] else '-'
    parts = ['%s:%d' % (d['file'], d['line']), '%s[%s %s]' % (sign, d['class_name'] or '?', selector),
             'Swift %s %s' % (d['kind'], d['swift_name'])]
    if d['is_override']:
        parts.append('overrides %s' % (d['overrides_usr'] or 'a superclass method'))
    source = {'usr': 'selector from the compiler', 'objc_attr': 'selector from the compiler',
              'explicit': 'selector named with @objc(...)', 'derived': 'selector derived from the Swift name'}
    parts.append(source.get(d['selector_source'], d['selector_source']))
    if d['implicit']:
        parts.append('declared by the compiler')
    parts.append('module ' + d['module'])
    return parts


PROTOCOL_WITNESS_NOT_COVERED = (
    'calls through a Swift protocol requirement whose witness is an Objective-C method or property (an Objective-C '
    'class made to conform to a Swift protocol): the dump names the requirement, not the witness, so they are not '
    'among the Swift references; reach names the Swift protocols whose requirement has a matching name, as possible '
    'indirect callers')

SWIFT_NOT_COVERED = [
    'Swift code in inactive #if branches (searched as text only), and Swift built for other configurations and '
    'architectures',
    'the call of super.init() the compiler adds at the end of an initializer that calls none (not in the dump)',
    'selectors Swift builds from strings: Selector("..."), NSSelectorFromString, perform(_:) or similar with a '
    'selector held in a variable',
    'Swift dynamic lookups (AnyObject, optional protocol methods) are joined by selector only, whatever class '
    'receives them',
    PROTOCOL_WITNESS_NOT_COVERED,
]
