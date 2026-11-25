"""Builds the fixture code database that test_entry_points.py queries.

The fixture repository is tests/fixtures/entry_points (a xib, a storyboard,
an sdef, plists, a Core Data model, a registry, Objective-C and Swift
sources). Its Objective-C files are extracted by the real extractor and its
Swift file is read by the real Swift reader from the captured dump in
tests/fixtures/entry_points_swift (regenerate it with
make_entry_points_dump.py), through the code database's own functions, as
the code database's tests do.

The binaries: CODEDB_TEST_EXTRACTOR and CODEDB_TEST_SWIFT_READER name
prebuilt ones (built with extractor/build.sh PATH and swiftreader/build.sh
PATH); without them they are built, when their sources changed, into a
directory under the system's temporary directory, never into tmp/codedb.
ENTRY_POINTS_CODEDB_DIR names another copy of the code database's tools, as
it does for entry_points.py.
"""

import gzip
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
MIGRATION_DIR = os.path.dirname(HERE)
CODEDB_DIR = os.environ.get('ENTRY_POINTS_CODEDB_DIR') or os.path.join(MIGRATION_DIR, 'codedb')
BIN_CACHE = os.path.join(tempfile.gettempdir(), 'swift-migration-entry-points-test-bin-%d' % os.getuid())
# The code database's test modules read these at import.
os.environ.setdefault('CODEDB_TEST_EXTRACTOR', os.path.join(BIN_CACHE, 'extract_sends'))
os.environ.setdefault('CODEDB_TEST_SWIFT_READER', os.path.join(BIN_CACHE, 'swift_refs'))
EXTRACTOR = os.environ['CODEDB_TEST_EXTRACTOR']
READER = os.environ['CODEDB_TEST_SWIFT_READER']
for _d in (CODEDB_DIR, os.path.join(CODEDB_DIR, 'tests'), os.path.join(CODEDB_DIR, 'tests', 'swift_fixture'),
           MIGRATION_DIR):
    if _d not in sys.path:
        sys.path.insert(0, _d)

import codedb  # noqa: E402
import swiftdb  # noqa: E402
import test_codedb as base  # noqa: E402
import test_codedb_swift as swift_base  # noqa: E402
import make_dump  # noqa: E402

FIXTURE = os.path.join(HERE, 'fixtures', 'entry_points')
SWIFT_DUMP_DIR = os.path.join(HERE, 'fixtures', 'entry_points_swift')
PLACEHOLDER = '@FIXTURE@'
APP_MAINS = ('sources/Widget.m', 'ThirdParty/Other/Other.m', 'ThirdParty/PSMTabBarControl/PSM.m', 'sources/SDKUsers.m',
             'sources/proto/Api.pbobjc.m')
TEST_MAINS = ('ModernTests/WidgetTests.m',)
SWIFT_FILES = ('sources/Panel.swift', 'sources/SDKUsers.swift')
BRIDGING_HEADER = 'sources/Fixture-Bridging-Header.h'
with open(os.path.join(SWIFT_DUMP_DIR, 'COMPILER_VERSION')) as _f:
    COMPILER = _f.read().strip()
TEMP_DIRS = []


def ensure_binaries():
    """Build the extractor and the reader into BIN_CACHE when their sources
    changed, unless the environment named prebuilt ones."""
    if EXTRACTOR.startswith(BIN_CACHE + os.sep):
        codedb.ensure_extractor(codedb.Paths(MIGRATION_DIR, extractor=EXTRACTOR), log=lambda m: None)
    if READER.startswith(BIN_CACHE + os.sep):
        swiftdb.ensure_reader(codedb.Paths(MIGRATION_DIR, swift_reader=READER), codedb.run_in_group,
                              log=lambda m: None)
    for exe in (EXTRACTOR, READER):
        if not os.path.exists(exe):
            raise RuntimeError('%s does not exist; build it or unset the variable that names it' % exe)


def cleanup():
    for d in TEMP_DIRS:
        shutil.rmtree(d, ignore_errors=True)
    del TEMP_DIRS[:]


def make_temp():
    d = os.path.realpath(tempfile.mkdtemp(prefix='entry-points-test-'))
    TEMP_DIRS.append(d)
    return d


def make_paths(d, root):
    return codedb.Paths(root, db=os.path.join(d, 'db.sqlite'), cdb=os.path.join(d, 'cdb.jsonl'),
                        fragments=os.path.join(d, 'fragments'), extractor=EXTRACTOR, swift_reader=READER,
                        swift_work=os.path.join(d, 'swiftwork'), swift_reader_prebuilt=True)


SDK_FIXTURE = os.path.join(HERE, 'fixtures', 'entry_points_sdk', 'sdk_selectors.tsv')
# A runtime method list in the format sdk_selectors.py --runtime-methods writes.
RUNTIME_FIXTURE = os.path.join(HERE, 'fixtures', 'entry_points_runtime', 'runtime_methods.tsv')
# A second list, as if written on another OS release.
RUNTIME_FIXTURE_OLDER = os.path.join(HERE, 'fixtures', 'entry_points_runtime', 'runtime_methods_older.tsv')
OBJC_CLASS_SCHEMA = 'CREATE TABLE IF NOT EXISTS objc_class(name TEXT NOT NULL, superclass TEXT)'


def add_objc_class_rows(db, rows):
    """Write objc_class rows (name, superclass), as the code database's
    schema 11 records every @interface of the repository; the table is
    created when the extractor did not write it."""
    con = sqlite3.connect(db)
    con.execute(OBJC_CLASS_SCHEMA)
    # The other columns of an extractor-written table get placeholders.
    info = [(r[1], (r[2] or '').upper(), r[5]) for r in con.execute('PRAGMA table_info(objc_class)')]
    columns = [name for name, _, pk in info if not pk]

    def value(column, kind, n, s):
        if column in ('name', 'superclass'):
            return n if column == 'name' else s
        return 0 if 'INT' in kind else ''
    con.executemany('INSERT INTO objc_class(%s) VALUES (%s)' % (', '.join(columns), ', '.join('?' * len(columns))),
                    [tuple(value(c, k, n, s) for c, k, pk in info if not pk) for n, s in rows])
    con.commit()
    con.close()
SDK_METHOD_SCHEMA = ('CREATE TABLE sdk_method(selector TEXT, container TEXT, container_kind TEXT, '
                     'is_class_method INTEGER, framework TEXT, is_optional INTEGER, is_action INTEGER)')


def sdk_fixture_rows():
    """The rows of the fixture's SDK declarations (fixtures/entry_points_sdk/
    sdk_selectors.tsv) in the shape of the sdk_method table."""
    out = []
    with open(SDK_FIXTURE, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            cells = line.split('\t')
            flags = cells[5].split(',') if len(cells) > 5 else []
            out.append((cells[3], cells[1], cells[0], 1 if cells[2] == '+' else 0, cells[4],
                        1 if 'optional' in flags else 0, 1 if 'action' in flags else 0))
    return out


def add_sdk_table(db, rows=None):
    """Write an sdk_method table, as the code database unit that records SDK
    declarations will, with the fixture's rows (or rows)."""
    con = sqlite3.connect(db)
    con.execute(SDK_METHOD_SCHEMA)
    con.executemany('INSERT INTO sdk_method VALUES (?, ?, ?, ?, ?, ?, ?)', sdk_fixture_rows() if rows is None else rows)
    con.commit()
    con.close()


# The ranges of Objective-C code that every unit skips, as the code
# database's extractor records them from schema 10 on (pp_skipped): the
# fixture's one inactive #if (sources/SDKUsers.m). The extractor these tests
# run may be older and record none, so the harness writes the table.
PP_SKIPPED_SCHEMA = ('CREATE TABLE IF NOT EXISTS pp_skipped(id INTEGER PRIMARY KEY, tu INTEGER NOT NULL, '
                     'start_line INTEGER NOT NULL, end_line INTEGER NOT NULL, directive TEXT NOT NULL, condition TEXT, '
                     'chain_line INTEGER NOT NULL, include_guard INTEGER NOT NULL, view TEXT, file TEXT NOT NULL, '
                     'in_migration_scope INTEGER NOT NULL)')
PP_SKIPPED_ROWS = [('sources/SDKUsers.m', 122, 124, '#if', '0')]


def add_pp_skipped(db, rows=None):
    """Write the pp_skipped rows of the fixture (or rows), unless the
    extractor recorded the table itself."""
    con = sqlite3.connect(db)
    exists = con.execute("SELECT 1 FROM sqlite_master WHERE name = 'pp_skipped'").fetchone()
    if not exists:
        con.execute(PP_SKIPPED_SCHEMA)
        for f, start, end, directive, condition in (PP_SKIPPED_ROWS if rows is None else rows):
            (tu,) = con.execute('SELECT id FROM tu WHERE main_file = ?', (f,)).fetchone()
            view = con.execute('SELECT view FROM tu_input WHERE tu = ? AND path = ?', (tu, f)).fetchone()
            con.execute('INSERT INTO pp_skipped(tu, start_line, end_line, directive, condition, chain_line, '
                        'include_guard, view, file, in_migration_scope) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, 1)',
                        (tu, start, end, directive, condition, start, view[0] if view else None, f))
    con.commit()
    con.close()


def build(swift=True, edit=None, sdk_table=True, pp_skipped=True, extra_mains=(), extra_test_mains=(),
          extra_args=None):
    """A scratch copy of the fixture with its database: (root, paths).
    edit(root), if given, changes the copy before anything is extracted.
    sdk_table: give the database an sdk_method table of the fixture's SDK
    declarations. pp_skipped: give it the skipped Objective-C ranges.
    extra_mains and extra_test_mains: more files (written by edit) that the
    app and the test target compile. extra_args: {main file: [clang
    arguments]} added to those files' compile commands (for example
    -fobjc-arc)."""
    ensure_binaries()
    d = make_temp()
    root = os.path.join(d, 'repo')
    shutil.copytree(FIXTURE, root)
    if edit:
        edit(root)
    paths = make_paths(d, root)
    app_mains = tuple(APP_MAINS) + tuple(extra_mains)
    test_mains = tuple(TEST_MAINS) + tuple(extra_test_mains)
    base.write_project(root, {'App': list(app_mains), 'ModernTests': list(test_mains), 'Fix': list(SWIFT_FILES)},
                       product_types={'ModernTests': codedb.TEST_PRODUCT_TYPES[0]})
    sdk = codedb.current_sdk()[0]
    with open(paths.cdb, 'w') as f:
        f.write(json.dumps({'meta': True, 'build_settings_sha256': codedb.build_settings_digest(root)}) + '\n')
        for m in app_mains + test_mains:
            target = 'ModernTests' if m in test_mains else 'App'
            args = base.clang_args(root, m, extra=('-isysroot', sdk) + tuple((extra_args or {}).get(m, ())))
            f.write(json.dumps({'target': target, 'file': m, 'directory': root, 'arguments': args}) + '\n')
    status = codedb.update(paths, log=lambda m: None, swift=False)
    if status != 0:
        raise RuntimeError('codedb.update of the fixture exited %s' % status)
    if swift:
        capture_swift(d, root, paths)
        read_swift(root, paths)
    # The extractor records SDK declarations itself from code database
    # the commit "Close the code database's gaps that the object-file cross-check found" on; these tests control the table, so it is replaced
    # by the fixture's rows (or dropped, for sdk_table=False).
    con = sqlite3.connect(paths.db)
    con.execute('DROP TABLE IF EXISTS sdk_method')
    # The extractor also writes pp_skipped and objc_class now. pp_skipped is
    # the harness's to give (pp_skipped=False tests a database without it),
    # and iTermMacroDeclared stands for a class whose superclass the
    # database does not know (the extractor now reads it through the macro).
    if not pp_skipped:
        con.execute('DROP TABLE IF EXISTS pp_skipped')
    if con.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'objc_class'").fetchone():
        con.execute("DELETE FROM objc_class WHERE name = 'iTermMacroDeclared'")
    con.commit()
    con.close()
    if sdk_table:
        add_sdk_table(paths.db)
    if pp_skipped:
        add_pp_skipped(paths.db)
    return root, paths


def capture_swift(d, root, paths):
    """A Swift capture of the module Fix whose driver command names a fake
    swiftc that reports the compiler the dump was written by."""
    swiftc = os.path.join(d, 'bin', 'swiftc')
    os.makedirs(os.path.dirname(swiftc))
    with open(swiftc, 'w') as f:
        f.write('#!/bin/sh\necho "%s"\necho "Target: arm64-apple-macosx27.0.0"\n' % COMPILER)
    os.chmod(swiftc, 0o755)
    file_list = os.path.join(d, 'Build', 'Variant-NoSanitizers', 'Fix.SwiftFileList')
    os.makedirs(os.path.dirname(file_list))
    with open(file_list, 'w') as f:
        f.write(''.join(os.path.join(root, x) + '\n' for x in SWIFT_FILES))
    args = make_dump.driver_command(swiftc, file_list, codedb.current_sdk()[0])
    args[args.index('-import-objc-header') + 1] = os.path.join(root, BRIDGING_HEADER)
    log = os.path.join(d, 'build.log')
    swift_base.write_log(log, [('Fix', 'Variant-NoSanitizers', args)])
    swiftdb.write_swift_capture(log, os.path.join(paths.fragments, 'swift'), log=lambda m: None)


def read_swift(root, paths):
    """Read the captured dump into the database as the module Fix, as update
    would, so that the module is current."""
    ctx = swiftdb.SwiftContext(paths, codedb.MIGRATION_SCOPE_TEXT, codedb.current_sdk()[0])
    con = sqlite3.connect(paths.db)
    swiftdb.ensure_schema(con)
    con.close()
    m = ctx.modules[0]
    with gzip.open(os.path.join(SWIFT_DUMP_DIR, 'module.json.gz'), 'rb') as f:
        data = f.read().decode('utf-8').replace(PLACEHOLDER, root).encode('utf-8')
    inputs = [(swiftdb.stored_path(f, root), swiftdb._file_sha256(f), 'swift') for f in m.files]
    db_dir = os.path.dirname(paths.db)
    files_path = os.path.join(db_dir, 'files.txt')
    with open(files_path, 'w') as f:
        f.write(''.join(x + '\n' for x in m.files))
    inputs_path = os.path.join(db_dir, 'inputs.tsv')
    with open(inputs_path, 'w') as f:
        f.write(''.join('%s\t%s\t%s\n' % i for i in inputs))
    cmd = [READER, '--db', paths.db, '--root', root, '--module', 'Fix', '--target', 'Fix', '--cmd-digest',
           ctx.cmd_digest(m), '--file-list-digest', swiftdb.file_list_digest(m), '--files', files_path,
           '--inputs', inputs_path, '--compiler-version', ctx.compiler]
    for s in codedb.MIGRATION_SCOPE_DIRS:
        cmd += ['--migration-scope', s]
    r = subprocess.run(cmd, input=data, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError('the Swift reader exited %d: %s' % (r.returncode, r.stderr.decode()))
    con = sqlite3.connect(paths.db)
    con.execute('UPDATE swift_unit SET reader_version = ?, migration_scope = ?',
                (swiftdb.swift_reader_source_digest(), codedb.MIGRATION_SCOPE_TEXT))
    con.commit()
    con.close()
