"""What Swift imports through a bridging header, in the code database.

codedb.py imports this module; its commands are documented there. In short:

  update    `codedb.py update` (and `update --imports-only`) fills the
            swift_import tables (their schema is swift_interface.py's, with
            its own version in swift_import_meta) for each captured Swift
            module whose command has -import-objc-header (today only
            iTerm2SharedARC: ModernTests has no bridging header of its own
            and sees iTerm2SharedARC's through the module). The rows come
            from the compiler: swift_interface.py's import pipeline runs the
            module's separate emit-module job with -emit-symbol-graph, and
            every symbol of the graph that is not the module's own is one
            Objective-C or C declaration Swift can see through the bridging
            header, keyed by its Clang USR, with its Swift name, declaration
            and availability. The symbol graph (about 110 MB for the app) is
            streamed one symbol at a time and deleted afterwards.
  states    a module's rows are current while its translated command, the
            compiler, this code and swift_interface.py, and every header and
            module interface its dependency information names are
            unchanged. Its Swift files are not inputs: they do not change
            what it imports.
  query     `codedb.py swiftimports` joins the rows to the Objective-C
            declarations of the database by USR (objc_class, objc_method,
            objc_property, c_static; macro_def by the USR computed from the
            macro's location, c:<file name>@<byte offset>@macro@<name>) and
            gives, for each declaration that is absent, the reason a rule
            finds, or "reason unknown".

The rules for a declaration that is absent from the symbol graph, in order
(those marked "checked" are confirmed by a swiftc probe in
tests/test_codedb_swiftimports.py):

  - it is in an implementation file: Swift sees only headers;
  - its header is not one the bridging header reads (the module's
    dependency information);
  - it is inside a preprocessor range that the units of the module's target
    skip (pp_skipped), and no unit of that target records it;
  - it is an accessor method of a property: Swift imports the property
    (imported through it, or not imported for the property's reason);
  - its class or protocol (declared in the repository) is not imported;
  - its declaration's text (its lines up to ; or {, and the attribute lines
    just before it, read at its recorded location) carries NS_UNAVAILABLE,
    UNAVAILABLE_ATTRIBUTE or NS_SWIFT_UNAVAILABLE, or, for a method, a
    variadic list;
  - the type of a property, or the result type of a method, names a class
    of the repository that is not imported and none of whose headers the
    bridging header reads;
  - the type of a property (from the import facts of its backing ivar) or
    of a global (c_static.import_facts) is one classstate.importability()
    says Swift cannot import;
  - a macro: function-like, empty, or with a body that is not a constant
    (a message send, a block, self, a statement expression and the other
    facts in NOT_CONSTANT_FACTS; checked for a send);
  - a property or unary method with the Swift base name of an imported
    member of its class, a superclass or an adopted protocol: "ABSENT FROM
    THE SYMBOL GRAPH: probably usable through" that member (the graph
    leaves out such collisions although Swift can use them).

Anything else is "ABSENT FROM THE SYMBOL GRAPH: reason unknown; it may
still be usable from Swift", with the counts of the SDK macros that mark
declarations for Swift (SWIFT_MARK_MACROS) that the file uses: the
database does not record the types of parameters, so a method whose
parameter names a class Swift cannot see, and class factory methods Swift
makes initializers of, land there. Headers of a framework's Clang module
are "NOT IN THIS TABLE": Swift imports them as that module.

Limits: the database has no table of C functions, enums and their cases,
typedefs and records, so the header form does not list them; the name form
finds them in the symbol graph by their Objective-C name (a global
function's name(), a static one's USR c:<file>@F@name, an enum case's
Enum.case, a free function's Swift base name), with no file: the graph
gives no location for Clang declarations. A name nothing declares says so.
Protocols are listed through their members; methods only defined in an
@implementation, with no declaration, are not listed.
"""

import collections
import hashlib
import os
import re
import shutil
import sqlite3
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

import swiftdb  # noqa: E402

HEADER_EXTENSIONS = ('.h', '.hh', '.hpp', '.pch', '.inc', '.def')
NOT_CONSTANT_FACTS = ('send', 'selector', 'self', 'cmd', 'block', 'statement-expression', 'control-flow-keyword',
                      'method-definition', 'class-definition', 'file-line', 'stringify', 'paste', 'static',
                      'synchronized', 'autoreleasepool', 'try', 'method-family-attribute')
FACT_TEXT = {'send': 'it holds a message send', 'selector': 'it holds @selector', 'self': 'it uses self',
             'cmd': 'it uses _cmd', 'block': 'it holds a block', 'statement-expression': 'a statement expression',
             'control-flow-keyword': 'it holds return, break, continue or goto',
             'method-definition': 'it defines a method', 'class-definition': 'it holds @interface, @implementation '
             'or @protocol', 'file-line': 'it uses __FILE__, __LINE__ or __func__', 'stringify': 'it stringifies',
             'paste': 'it pastes tokens', 'static': 'it holds static', 'synchronized': 'it holds @synchronized',
             'autoreleasepool': 'it holds @autoreleasepool', 'try': 'it holds @try',
             'method-family-attribute': 'it holds a method family attribute'}
SWIFT_MARK_MACROS = ('API_UNAVAILABLE', 'NS_REFINED_FOR_SWIFT', 'NS_SWIFT_NAME', 'NS_SWIFT_UNAVAILABLE',
                     'NS_UNAVAILABLE', 'UNAVAILABLE_ATTRIBUTE', '__swift__')
UNKNOWN_FACTS = ('no rule explains the absence: the declaration\'s text carries no mark this tool reads, and the '
                 'database does not record the types of parameters')
ABSENT = 'ABSENT FROM THE SYMBOL GRAPH: '
ABSENT_UNKNOWN = ABSENT + 'reason unknown; it may still be usable from Swift (see below)'
ABSENT_NOTE = ('ABSENT FROM THE SYMBOL GRAPH: no rule explains why the declaration is not in the symbol graph. It may '
               'still be usable from Swift: the graph leaves out a member whose Swift name collides with another '
               'member\'s (the rule "probably usable through" catches the collisions it can see), and the database '
               'does not record the types of parameters or the attributes this tool does not read in the '
               'declaration\'s text.')
# Marks in a declaration's own text that make it unavailable in Swift.
UNAVAILABLE_MARK = re.compile(r'\b(NS_SWIFT_UNAVAILABLE|NS_UNAVAILABLE|UNAVAILABLE_ATTRIBUTE)\b')
VARIADIC = re.compile(r',\s*\.\.\.\s*(?:\)|[A-Z_]|;|$)')
IDENTIFIER = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
CHECKED = ' (checked)'
THROUGH_PROPERTY = 'imported through the property %s (Swift imports the property, not its accessor methods)'
UPDATE_HINT = 'run codedb.py update --imports-only'
# The compiler prints _ for a type it cannot import, in a declaration it
# keeps in the graph (a global of type _Atomic int, say).
UNUSABLE_TYPE = re.compile(r'(?::|->)\s*_(?![A-Za-z0-9_])')

LIMITS = [
    'C functions, enums and their cases, typedefs and records: the database has no table of them, so the header '
    'form does not list them; the name form finds them in the symbol graph, with no file',
    'protocols themselves: they are listed through their members',
    'methods only defined in an @implementation, with no declaration',
    'what a declaration Swift imports looks like in another module that imports this one (ModernTests sees the '
    'declarations of iTerm2SharedARC\'s bridging header through that module)',
    'parameter types: the database does not record them, so a method whose parameter names a class Swift cannot '
    'see says "reason unknown"; marks and variadic lists are read from the declaration\'s text at its recorded '
    'location (the first lines up to its ; or {, and the attribute lines just before it)',
]
EXIT_TEXT = ('exit status: 0 declarations printed, 1 none (0 and 1 only when the module\'s swift_import rows are '
             'current and every unit is current), 3 answered but incomplete, 2 error')


def _si():
    import swift_interface
    return swift_interface


def tool_digest():
    """The digest of the code that computes the rows: this file and
    swift_interface.py."""
    h = hashlib.sha256()
    for p in (os.path.abspath(__file__), os.path.join(TOOLS, 'swift_interface.py')):
        with open(p, 'rb') as f:
            h.update(hashlib.sha256(f.read()).hexdigest().encode('ascii'))
    return h.hexdigest()


def bridging_header(module):
    return swiftdb.option_value(module.driver_args, '-import-objc-header')


def bridging_modules(ctx):
    """[(module, bridging header)] of the captured modules that have one."""
    return [(m, bridging_header(m)) for m in ctx.modules if bridging_header(m)]


def import_tables_version(con):
    names = set(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'"))
    if 'swift_import_meta' not in names:
        return None
    row = con.execute("SELECT value FROM swift_import_meta WHERE key='schema_version'").fetchone()
    return row[0] if row else None


ImportState = collections.namedtuple('ImportState', 'module header state reason compiler')


def import_states(con, ctx, digests, tool=None):
    """{module: ImportState} for every captured module with a bridging header
    and every module in the tables. States: current, stale, incomplete,
    missing, failed, orphan."""
    si = _si()
    tool = tool or tool_digest()
    units, failures, changed = {}, {}, {}
    if import_tables_version(con) == str(si.IMPORT_SCHEMA_VERSION):
        for row in con.execute('SELECT module, compiler, incomplete, cmd_digest, tool_digest, bridging_header FROM '
                               'swift_import_unit'):
            units[row[0]] = row
        for module, reason in con.execute('SELECT module, reason FROM swift_import_failure'):
            failures[module] = reason
        for module, path, digest in con.execute('SELECT module, path, digest FROM swift_import_input ORDER BY '
                                                'module, path'):
            if module in changed:
                continue
            now = digests.digest(path)
            if now is None:
                changed[module] = 'input missing: ' + path
            elif now != digest:
                changed[module] = 'input changed: ' + path
    wanted = dict((m.name, (m, swiftdb.stored_path(h, ctx.paths.root))) for m, h in bridging_modules(ctx))
    states = {}
    for name in sorted(set(wanted) | set(units) | set(failures)):
        u = units.get(name)
        m, header = wanted.get(name, (None, u[5] if u else None))
        if m is not None and name in failures:
            state, reason = 'failed', failures[name]
        elif m is not None and u is None:
            state, reason = 'missing', 'not in the database'
        elif m is None:
            state, reason = 'orphan', 'not a captured module with a bridging header'
        elif u[3] != ctx.cmd_digest(m):
            state, reason = 'stale', 'command changed'
        elif ctx.compiler is None or u[1] != ctx.compiler:
            state, reason = 'stale', 'compiler changed'
        elif u[4] != tool:
            state, reason = 'stale', 'tool changed'
        elif name in changed:
            state, reason = 'stale', changed[name]
        elif u[2]:
            state, reason = 'incomplete', u[2]
        else:
            state, reason = 'current', None
        states[name] = ImportState(name, header, state, reason, u[1] if u else None)
    return states


def record_failure(db, module, reason):
    si = _si()
    con = sqlite3.connect(db)
    con.execute('PRAGMA busy_timeout=60000')
    try:
        with con:
            si.ensure_import_schema(con)
            con.execute('INSERT OR REPLACE INTO swift_import_failure(module, reason, failed_at) VALUES(?,?,?)',
                        (module, reason, time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())))
    finally:
        con.close()


def update_imports(paths, log=print, force=False, only=None, module_cache=None, sdk_path=None):
    """Bring the swift_import rows of each captured module with a bridging
    header up to date, one module at a time. Returns 0, or 1 if a module
    failed."""
    import codedb
    si = _si()
    if module_cache is not None:
        paths.swift_module_cache = module_cache
    started = time.time()
    ctx = swiftdb.SwiftContext(paths, codedb.MIGRATION_SCOPE_TEXT, sdk_path or codedb.current_sdk()[0],
                               project_swift=lambda: codedb.project_swift_sources(paths.root))
    if not ctx.captured:
        log('swift imports: the capture in %s kept no Swift inputs; nothing to do' % paths.fragments)
        return 0
    tool = tool_digest()
    digests = codedb.DigestCache(paths.root)
    os.makedirs(os.path.dirname(os.path.abspath(paths.db)), exist_ok=True)
    con = sqlite3.connect(paths.db)
    con.execute('PRAGMA busy_timeout=60000')
    try:
        states = import_states(con, ctx, digests, tool)
    finally:
        con.close()
    counts = collections.Counter()
    todo = []
    for m, header in bridging_modules(ctx):
        if only is not None and m.name not in only:
            continue
        s = states[m.name]
        if force or s.state != 'current':
            todo.append((m, header, 'forced' if force else '%s%s' % (s.state, ': ' + s.reason if s.reason else '')))
        else:
            counts['skipped'] += 1
    for n, (m, header, why) in enumerate(todo, 1):
        label = 'swift imports [%d/%d] %s' % (n, len(todo), m.name)
        log('%s (bridging header %s): %s' % (label, swiftdb.stored_path(header, paths.root), why))
        work = os.path.join(paths.swift_work, 'imports', m.name)
        os.makedirs(work, exist_ok=True)
        t0 = time.time()
        try:
            r = si.snapshot_module(paths, m.name, work, os.path.join(work, 'imports.snapshot'), sections=('import',),
                                   accept_stale=True, log=lambda line: log('%s: %s' % (label, line)),
                                   check_other_compilers=False, keep_raw=True,
                                   project_swift=lambda: codedb.project_swift_sources(paths.root))
        except si.InterfaceError as e:
            r = None
            why_failed = str(e)
        if r is None or r.sg_dir is None:
            if r is not None:
                why_failed = '; '.join(r.incomplete) or 'the compiler failed'
            record_failure(paths.db, m.name, why_failed)
            counts['failed'] += 1
            log('%s: FAILED: %s' % (label, why_failed))
            continue
        deps = si.input_digests(paths.root, si.Work(work).deps)
        inputs = dict((p, d) for p, d in deps.items() if swiftdb.input_kind(p) != 'swift')
        rows = si.write_imports(paths.db, m.name, r.sg_dir, inputs, ctx.compiler, r.incomplete,
                                cmd_digest=ctx.cmd_digest(m), tool_digest=tool,
                                bridging_header=swiftdb.stored_path(header, paths.root))
        for d in (r.sg_dir, r.private_sg_dir):
            if d:
                shutil.rmtree(d, ignore_errors=True)
        counts['extracted'] += 1
        log('%s: ok %.0fs: %d rows, %d inputs; compiler %.0fs, peak %s MB%s' % (
            label, time.time() - t0, rows, len(inputs), r.seconds, '?' if r.peak_kb is None else r.peak_kb // 1024,
            '; INCOMPLETE: ' + '; '.join(r.incomplete) if r.incomplete else ''))
    if only is None:
        wanted = set(m.name for m, _ in bridging_modules(ctx))
        con = sqlite3.connect(paths.db)
        con.execute('PRAGMA busy_timeout=60000')
        try:
            if import_tables_version(con) == str(si.IMPORT_SCHEMA_VERSION):
                with con:
                    for (name,) in list(con.execute('SELECT module FROM swift_import_unit UNION SELECT module FROM '
                                                    'swift_import_failure')):
                        if name not in wanted:
                            log('swift imports: removing module %s: not a captured module with a bridging header'
                                % name)
                            for t in ('swift_import', 'swift_import_input', 'swift_import_unit',
                                      'swift_import_failure'):
                                con.execute('DELETE FROM %s WHERE module=?' % t, (name,))
                            counts['removed'] += 1
        finally:
            con.close()
    import resource
    log('swift imports: extracted %d, failed %d, skipped as current %d, removed %d; %.0fs; peak memory of this '
        'process %d MB' % (counts['extracted'], counts['failed'], counts['skipped'], counts['removed'],
                           time.time() - started, resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // (1 << 20)))
    return 1 if counts['failed'] else 0


# --- The Objective-C declarations of the database ---------------------------------

Decl = collections.namedtuple('Decl', 'file line objc_name kind usr name selector container_usr container_name '
                                      'container_kind class_name property_usr ivar_usr type_class import_facts '
                                      'macro_kind macro_body macro_facts type_text')


def _byte_offset(root, path, line, col, cache):
    """The byte offset of (line, col) in a file, as the macro USR has it."""
    if path not in cache:
        try:
            with open(path if os.path.isabs(path) else os.path.join(root, path), 'rb') as f:
                starts = [0]
                for chunk in f.read().split(b'\n')[:-1]:
                    starts.append(starts[-1] + len(chunk) + 1)
            cache[path] = starts
        except OSError:
            cache[path] = None
    starts = cache[path]
    if starts is None or line - 1 >= len(starts):
        return None
    return starts[line - 1] + col - 1


def macro_usr(root, path, line, col, name, cache):
    offset = _byte_offset(root, path, line, col, cache)
    return None if offset is None else 'c:%s@%d@macro@%s' % (os.path.basename(path), offset, name)


def declarations(con, root, where, params=(), tables=('class', 'method', 'property', 'global', 'macro')):
    """The declarations of the database matching where, an SQL condition on
    the columns file, name (the class, selector, property, global or macro
    name), usr and container (a container_name or class_name) that each
    table's query provides. One Decl per declaration (USR or macro and
    location), whatever the number of units that record it."""
    out = {}
    cache = {}

    def add(d):
        key = (d.usr or d.objc_name, d.file, d.line)
        if key not in out:
            out[key] = d
    if 'class' in tables:
        for usr, name, file, line in con.execute(
                'SELECT DISTINCT usr, name, file, line FROM (SELECT usr, name, file, line, name AS container FROM '
                'objc_class) WHERE %s' % where, params):
            add(Decl(file, line, name, 'class', usr, name, None, None, None, None, name, None, None, None, None,
                     None, None, None, None))
    if 'method' in tables:
        for (usr, sel, is_class, cusr, cname, ckind, cls, pusr, file, line, rtype) in con.execute(
                'SELECT DISTINCT usr, selector, is_class_method, container_usr, container_name, container_kind, '
                'class_name, property_usr, file, line, return_type FROM (SELECT m.*, m.selector AS name, '
                "coalesce(m.class_name, m.container_name) AS container FROM objc_method m WHERE m.is_definition = 0 "
                "AND m.container_kind NOT IN ('implementation', 'category-implementation')) WHERE %s" % where,
                params):
            add(Decl(file, line, '%s[%s %s]' % ('+' if is_class else '-', cname, sel),
                     'class method' if is_class else 'method', usr, sel, sel, cusr, cname, ckind, cls, pusr, None,
                     None, None, None, None, None, rtype))
    if 'property' in tables:
        for (usr, name, is_class, cusr, cname, ckind, cls, file, line, ptype) in con.execute(
                'SELECT DISTINCT usr, name, is_class_property, container_usr, container_name, container_kind, '
                'class_name, file, line, type FROM (SELECT p.*, coalesce(p.class_name, p.container_name) AS container FROM '
                "objc_property p WHERE p.kind = 'declaration') WHERE %s" % where, params):
            ivar = con.execute("SELECT i.usr, i.type_class, i.import_facts FROM objc_property p JOIN objc_ivar i ON "
                               "i.usr = p.ivar_usr WHERE p.usr = ? AND p.kind = 'synthesize' LIMIT 1",
                               (usr,)).fetchone()
            add(Decl(file, line, '%s.%s' % (cname, name), 'class property' if is_class else 'property', usr, name,
                     None, cusr, cname, ckind, cls, None, ivar[0] if ivar else None, ivar[1] if ivar else None,
                     ivar[2] if ivar else None, None, None, None, ptype))
    if 'global' in tables:
        for usr, name, kind, type_class, facts, file, line in con.execute(
                'SELECT DISTINCT usr, name, kind, type_class, import_facts, file, line FROM (SELECT s.*, NULL AS '
                "container FROM c_static s WHERE s.kind IN ('extern', 'global', 'file-static')) WHERE %s" % where,
                params):
            add(Decl(file, line, name, 'global', usr, name, None, None, None, None, None, None, None, type_class,
                     facts, None, None, None, None))
    if 'macro' in tables:
        for name, kind, body, facts, file, line, col in con.execute(
                'SELECT DISTINCT name, kind, body, facts, file, line, col FROM (SELECT d.*, NULL AS usr, NULL AS '
                'container FROM macro_def d) WHERE %s' % where, params):
            add(Decl(file, line, name, 'function-like macro' if kind == 'function' else 'macro',
                     macro_usr(root, file, line, col, name, cache), name, None, None, None, None, None, None, None,
                     None, None, kind, body, facts, None))
    return sorted(out.values(), key=lambda d: (d.file, d.line, d.objc_name))


def database_usrs(db, root):
    """Every USR the database's declarations have, macros' computed ones
    included (for the check that the USR forms of the symbol graph and the
    database are the same)."""
    con = sqlite3.connect(db)
    try:
        names = set()
        for t in ('objc_class', 'objc_method', 'objc_property', 'c_static'):
            names |= set(r[0] for r in con.execute('SELECT DISTINCT usr FROM %s WHERE usr IS NOT NULL' % t))
        # Protocols, through their members.
        for t in ('objc_method', 'objc_property'):
            names |= set(r[0] for r in con.execute("SELECT DISTINCT container_usr FROM %s WHERE container_kind = "
                                                   "'protocol' AND container_usr IS NOT NULL" % t))
        return names | macro_usrs(con, root)
    finally:
        con.close()


def macro_usrs(con, root):
    cache = {}
    return set(macro_usr(root, f, line, col, name, cache) for name, f, line, col in con.execute(
        'SELECT DISTINCT name, file, line, col FROM macro_def'))


# --- Classification -------------------------------------------------------------

Import = collections.namedtuple('Import', 'usr objc_name swift_name kind declaration refined availability')


class Classifier:
    def __init__(self, con, root, module, importability, target=None):
        self.con = con
        self.target = target
        self.lines = {}
        self.class_files = collections.defaultdict(set)
        for name, file in con.execute('SELECT DISTINCT name, file FROM objc_class'):
            self.class_files[name].add(file)
        self.root = root
        self.module = module
        self.importability = importability
        self.imports = collections.defaultdict(list)
        for row in con.execute('SELECT usr, objc_name, swift_name, kind, declaration, refined, availability FROM '
                               'swift_import WHERE module = ? ORDER BY usr, swift_name', (module,)):
            self.imports[row[0]].append(Import(*row))
        self.reached = set(r[0] for r in con.execute('SELECT path FROM swift_import_input WHERE module = ?',
                                                     (module,)))
        self.repo_classes = set(r[0] for r in con.execute('SELECT DISTINCT usr FROM objc_class WHERE usr IS NOT '
                                                          'NULL'))
        self.repo_containers = self.repo_classes | set(r[0] for r in con.execute(
            "SELECT DISTINCT container_usr FROM objc_method WHERE container_kind = 'protocol' AND container_usr IS "
            "NOT NULL UNION SELECT DISTINCT container_usr FROM objc_property WHERE container_kind = 'protocol' AND "
            'container_usr IS NOT NULL'))
        self.property_names = {}
        self.hints = {}
        self.via_module = set(r[0] for r in con.execute('SELECT DISTINCT path FROM decl_source WHERE via_module = 1'))
        self.module_frameworks = {}

    def property_name(self, usr):
        if usr not in self.property_names:
            row = self.con.execute("SELECT container_name, name FROM objc_property WHERE usr = ? AND kind = "
                                   "'declaration' LIMIT 1", (usr,)).fetchone()
            self.property_names[usr] = '%s.%s' % row if row else usr
        return self.property_names[usr]

    def hint(self, path):
        if path not in self.hints:
            marks = ','.join('?' * len(SWIFT_MARK_MACROS))
            rows = self.con.execute('SELECT name, max(count) FROM macro_use_count WHERE file = ? AND name IN (%s) '
                                    'GROUP BY name ORDER BY name' % marks, [path] + list(SWIFT_MARK_MACROS)).fetchall()
            if rows:
                text = ' (%s uses %s; %s)' % (path, ', '.join('%s %d %s' % (n, c, 'time' if c == 1 else 'times')
                                                              for n, c in rows), UNKNOWN_FACTS)
            else:
                text = ' (%s)' % UNKNOWN_FACTS
            self.hints[path] = text
        return self.hints[path]

    def statuses(self, d):
        """[(imported?, text)] for a declaration: one per Swift row when it is
        imported, else one with the reason."""
        rows = self.imports.get(d.usr) if d.usr else None
        if rows:
            out = []
            for r in rows:
                text = 'as %s: %s' % (r.swift_name, r.declaration)
                if r.refined:
                    text += ' [NS_REFINED_FOR_SWIFT]'
                if r.availability:
                    text += ' ' + r.availability
                if UNUSABLE_TYPE.search(r.declaration):
                    why = ''
                    if d.type_class is not None:
                        verdict, reason = self.importability(d.type_class, d.import_facts)
                        why = '; the type: %s' % reason
                    out.append((False, 'IMPORTED WITHOUT A USABLE TYPE %s (_ is how the compiler prints a type it '
                                       'cannot import%s)' % (text, why)))
                else:
                    out.append((True, 'imported ' + text))
            return out
        if d.file.endswith(HEADER_EXTENSIONS) and self.framework_module(d.file):
            return [(None, 'NOT IN THIS TABLE: %s belongs to the Clang module of %s, which Swift imports as a module, '
                           'not through the bridging header; this table holds only what the bridging header itself '
                           'declares' % (d.file, self.framework_module(d.file)))]
        if self.through_property(d):
            return [(True, THROUGH_PROPERTY % self.property_name(d.property_usr))]
        why = self.reason(d)
        if why.startswith('reason unknown'):
            return [(False, ABSENT_UNKNOWN + why[len('reason unknown'):])]
        if why.startswith('probably usable'):
            return [(None, ABSENT + why)]
        return [(False, 'NOT IMPORTED: ' + why)]

    def file_lines(self, path):
        if path not in self.lines:
            try:
                with open(path if os.path.isabs(path) else os.path.join(self.root, path), 'r', encoding='utf-8',
                          errors='replace') as f:
                    self.lines[path] = f.read().split('\n')
            except OSError:
                self.lines[path] = None
        return self.lines[path]

    def declaration_text(self, d):
        """The declaration's text at its recorded location: the attribute
        lines just before it (lines that end no statement and are not a
        directive, a comment or another declaration), and its lines up to its
        ; or { (for a class, its @interface line). Comments are removed."""
        lines = self.file_lines(d.file)
        if not lines or d.line < 1 or d.line > len(lines):
            return ''
        i = d.line - 1
        before = []
        j = i - 1
        while j >= 0 and len(before) < 3:
            t = lines[j].strip()
            if not t or t.endswith((';', '}', '{', '*/')) or t.startswith(('#', '//', '@', '-', '+', '/*', '*')):
                break
            before.insert(0, lines[j])
            j -= 1
        own = []
        for k in range(i, min(i + 8, len(lines))):
            own.append(lines[k])
            if d.kind == 'class' or ';' in lines[k] or '{' in lines[k]:
                break
        text = '\n'.join(before + own)
        text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
        return re.sub(r'//[^\n]*', ' ', text)

    def declared_in_target(self, d):
        if not d.usr or not self.target:
            return False
        for t in ('objc_class', 'objc_method', 'objc_property', 'c_static'):
            if self.con.execute('SELECT 1 FROM %s x JOIN tu ON tu.id = x.tu WHERE x.usr = ? AND tu.target = ? LIMIT 1'
                                % t, (d.usr, self.target)).fetchone():
                return True
        return False

    def skipped(self, d):
        if not self.target:
            return None
        row = self.con.execute('SELECT p.directive, p.condition, p.start_line, p.end_line FROM pp_skipped p JOIN tu '
                               'ON tu.id = p.tu WHERE p.file = ? AND tu.target = ? AND ? BETWEEN p.start_line AND '
                               'p.end_line ORDER BY p.start_line LIMIT 1', (d.file, self.target, d.line)).fetchone()
        if row is None or self.declared_in_target(d):
            return None
        return ('inside #%s%s (%s lines %d-%d), which the units of target %s, compiled as the module is, skip%s' % (
            row[0], ' ' + row[1] if row[1] else '', d.file, row[2], row[3], self.target, CHECKED))

    def invisible_class(self, type_text):
        """(class, header) when type_text names a class of the repository
        that is not imported and none of whose declaring headers the
        bridging header reads."""
        for name in IDENTIFIER.findall(type_text or ''):
            files = self.class_files.get(name)
            if not files or self.imports.get('c:objc(cs)%s' % name):
                continue
            if not any(f in self.reached for f in files):
                return name, sorted(files)[0]
        return None

    def collision(self, d):
        """The imported member of the same class, a superclass or an adopted
        protocol whose Swift base name is the absent declaration's."""
        # The collisions the symbol graph drops: a property beside a method
        # of the same name with no arguments (or another property); a
        # method with arguments has argument labels that tell it apart.
        if d.kind not in ('property', 'class property', 'method', 'class method') or not d.class_name or \
                ':' in (d.selector or ''):
            return None
        base = d.name
        chain, cls, seen = [], d.class_name, set()
        while cls and cls not in seen and len(chain) < 64:
            seen.add(cls)
            chain.append(cls)
            row = self.con.execute('SELECT superclass FROM objc_class WHERE name = ? AND superclass IS NOT NULL LIMIT 1',
                                   (cls,)).fetchone()
            cls = row[0] if row else None
        protocols = [r[0] for r in self.con.execute(
            'SELECT DISTINCT protocol FROM objc_adoption WHERE class_or_category IN (%s)' % ','.join('?' * len(chain)),
            chain)]
        for container in chain + protocols:
            for usr, objc_name, swift_name in self.con.execute(
                    'SELECT usr, objc_name, swift_name FROM swift_import WHERE module = ? AND container = ? ORDER BY '
                    'objc_name', (self.module, container)):
                if usr == d.usr:
                    continue
                last = swift_name.split('.')[-1]
                if last.split('(')[0] == base and (last == base or last == base + '()'):
                    return objc_name, swift_name
        return None

    def framework_module(self, path):
        """The framework bundle (repository relative) whose Clang module
        holds path, when units read path only through a module or it is in
        a framework with a module map; else None."""
        m = re.match(r'^(.*?[^/]+\.framework)/', path)
        framework = m.group(1) if m else None
        if framework is not None and framework not in self.module_frameworks:
            self.module_frameworks[framework] = os.path.exists(os.path.join(
                framework if os.path.isabs(framework) else os.path.join(self.root, framework), 'Modules',
                'module.modulemap'))
        if framework is not None and self.module_frameworks[framework]:
            return framework
        if path in self.via_module:
            return framework or os.path.dirname(path)
        return None

    def through_property(self, d):
        return d.property_usr is not None and bool(self.imports.get(d.property_usr))

    def reason(self, d):
        if not d.file.endswith(HEADER_EXTENSIONS):
            return ('declared in an implementation file; Swift sees only the headers the bridging header reads')
        if d.file not in self.reached:
            return ('%s is not read by the bridging header of %s (directly or through the headers it includes)'
                    % (d.file, self.module))
        skipped = self.skipped(d)
        if skipped:
            return skipped
        if d.property_usr is not None:
            name = self.property_name(d.property_usr)
            props = [p for p in declarations(self.con, self.root, 'usr = ?', (d.property_usr,), tables=('property',))]
            why = self.reason(props[0]) if props else 'reason unknown' + self.hint(d.file)
            if why.startswith('reason unknown'):
                return 'reason unknown (its property %s is absent from the symbol graph)%s' % (
                    name, why[len('reason unknown'):])
            if why.startswith('probably usable'):
                return why
            return 'its property %s is not imported: %s' % (name, why)
        if d.container_kind in ('interface', 'protocol') and d.container_usr in self.repo_containers and \
                not self.imports.get(d.container_usr):
            return 'its %s %s is not imported' % ('class' if d.container_kind == 'interface' else 'protocol',
                                                  d.container_name)
        if d.container_kind in ('category', 'extension') and d.class_name:
            cls = 'c:objc(cs)%s' % d.class_name
            if cls in self.repo_classes and not self.imports.get(cls):
                return 'its class %s is not imported' % d.class_name
        text = self.declaration_text(d) if d.kind != 'function-like macro' and d.macro_kind is None else ''
        mark = UNAVAILABLE_MARK.search(text)
        if mark:
            return 'marked %s (by the declaration\'s text)%s' % (mark.group(1), CHECKED)
        if d.kind in ('method', 'class method') and VARIADIC.search(text):
            return 'a variadic method; Swift imports none (by the declaration\'s text)%s' % CHECKED
        if d.kind in ('property', 'class property', 'method', 'class method'):
            hidden = self.invisible_class(d.type_text)
            if hidden:
                return ('its %stype names the class %s, whose header %s the bridging header of %s does not read (Swift '
                        'drops a member whose type it cannot see)%s' % ('' if 'property' in d.kind else 'result ',
                                                                        hidden[0], hidden[1], self.module, CHECKED))
        if d.kind in ('property', 'class property', 'global') and d.type_class is not None:
            verdict, why = self.importability(d.type_class, d.import_facts)
            if verdict == 'no':
                return 'its type: %s%s' % (why, ' (from the import facts of its backing ivar)'
                                           if d.kind != 'global' else '')
        if d.macro_kind == 'function':
            return 'a function-like macro; Swift imports none (checked)'
        if d.macro_kind == 'object' and not (d.macro_body or '').strip():
            return 'an empty macro (checked)'
        if d.macro_kind == 'object':
            facts = [f for f in (d.macro_facts or '').split() if f in NOT_CONSTANT_FACTS]
            if facts:
                return 'its body is not a constant (%s) (checked%s)' % (
                    ', '.join(FACT_TEXT[f] for f in facts), '' if 'send' in facts else ' for a message send only')
        other = self.collision(d)
        if other:
            return ('probably usable through %s (%s): a member whose Swift name collides with another member\'s is left '
                    'out of the symbol graph although Swift can use it%s' % (other[0], other[1], CHECKED))
        return 'reason unknown' + self.hint(d.file)


def line_for(d, text):
    return '%s:%d  %s  %s  %s' % (d.file, d.line, d.objc_name, d.kind, text)


# --- The query ------------------------------------------------------------------

def check_tables(codedb, con, db):
    si = _si()
    version = import_tables_version(con)
    if version is None:
        raise codedb.CodeDBError('%s has no swift_import tables; %s' % (db, UPDATE_HINT))
    if version != str(si.IMPORT_SCHEMA_VERSION):
        raise codedb.CodeDBError('the swift_import tables in %s have schema version %s, not %d; %s' % (
            db, version, si.IMPORT_SCHEMA_VERSION, UPDATE_HINT))


def choose_module(codedb, con, q, module):
    captured = [m.name for m, _ in bridging_modules(q.swift)] if q.swift.captured else []
    in_db = [r[0] for r in con.execute('SELECT module FROM swift_import_unit ORDER BY module')]
    names = sorted(set(captured) | set(in_db))
    if module is not None:
        if module not in names:
            raise codedb.CodeDBError('%s is not a module with a bridging header (known: %s)' % (module, ', '.join(names)
                                                                                         or 'none'))
        return module
    if len(names) != 1:
        raise codedb.CodeDBError('give --module: the modules with a bridging header are %s' % (', '.join(names) or 'none'))
    return names[0]


def swiftimports(codedb, paths, name=None, header=None, not_importable=None, module=None, out=None):
    """Print how Swift imports declarations, by name or USR, by header, or
    the declarations of a class it does not import. Returns the exit
    status."""
    import classstate
    out = out or sys.stdout
    spec = codedb.QuerySpec('swiftimports', [], EXIT_TEXT, None, False)
    con = codedb.open_db(paths.db)
    try:
        check_tables(codedb, con, paths.db)
    finally:
        con.close()
    q = codedb.QueryContext(paths, spec)
    try:
        # The Swift references are not what this query answers.
        q.swift_states = None
        module = choose_module(codedb, q.con, q, module)
        digests = codedb.DigestCache(paths.root)
        states = import_states(q.con, q.swift, digests) if q.swift.captured else {}
        if module not in states:
            u = q.con.execute('SELECT bridging_header FROM swift_import_unit WHERE module = ?', (module,)).fetchone()
            states[module] = ImportState(module, u[0] if u else None, 'not checked',
                                         'the capture has no Swift inputs, so the rows cannot be checked', None)
        target = dict((m.name, m.target) for m, _ in bridging_modules(q.swift)).get(module) if q.swift.captured \
            else None
        c = Classifier(q.con, paths.root, module, classstate.importability, target=target)
        lines = []
        if header is not None:
            decls = declarations(q.con, paths.root, 'file = ?', (header,))
            lines.append('%s: the declarations the code database has for this header, and how Swift imports them '
                         'through the bridging header of %s' % (header, module))
            body = []
            for d in decls:
                for _, text in c.statuses(d):
                    body.append(line_for(d, text))
            rows = len(body)
            lines += body
        elif not_importable is not None:
            decls = declarations(q.con, paths.root, 'name = ?', (not_importable,), tables=('class',)) + declarations(
                q.con, paths.root, 'container = ?', (not_importable,), tables=('method', 'property'))
            decls = sorted(set(decls), key=lambda d: (d.file, d.line, d.objc_name))
            lines.append('%s: its declarations that Swift does not import through the bridging header of %s' % (
                not_importable, module))
            body = []
            for d in decls:
                for imported, text in c.statuses(d):
                    if imported is False:
                        body.append(line_for(d, text))
            rows = len(body)
            lines += body
        else:
            body, rows = by_name(q.con, paths.root, c, name)
            lines += body
        for line in lines:
            out.write(line + '\n')
        return write_status(q, out, rows, states, module)
    finally:
        q.close()


def by_name(con, root, c, name):
    """Lines for the declarations a name or USR denotes: the database's
    declarations with that USR, Objective-C name, selector, class, property,
    global or macro name, or whose Swift name it is; and the symbol graph's
    rows with that name that the database has no declaration for (C
    functions, enums, typedefs)."""
    # A global C function's objc_name is name(); a static one's is its USR,
    # c:<file>@F@name; an enum case's is Enum.name; a free function's
    # Swift name is name(...) when NS_SWIFT_NAME does not rename it.
    usrs = set(r[0] for r in con.execute(
        'SELECT DISTINCT usr FROM swift_import WHERE module = ? AND (usr = ? OR objc_name = ? OR swift_name = ? OR '
        'objc_name = ? OR selector = ? OR '
        "(usr NOT LIKE 'c:@F@%' AND substr(usr, length(usr) - length(?) - 2) = '@F@' || ?) OR "
        "(instr(objc_name, '.') > 0 AND substr(objc_name, length(objc_name) - length(?)) = '.' || ?) OR "
        "substr(swift_name, 1, length(?) + 1) = ? || '(')",
        (c.module, name, name, name, name + '()', name, name, name, name, name, name, name)))
    decls = []
    for d in declarations(con, root, 'name = ? OR usr = ?', (name, name)):
        decls.append(d)
    if usrs:
        marks = ','.join('?' * len(usrs))
        decls += declarations(con, root, 'usr IN (%s)' % marks, list(usrs))
    m = re.match(r'^([-+])\[(\S+) (\S+)\]$', name)
    if m:
        decls += [d for d in declarations(con, root, 'name = ?', (m.group(3),), tables=('method',))
                  if d.objc_name == name]
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)$', name)
    if m:
        decls += [d for d in declarations(con, root, 'name = ?', (m.group(2),), tables=('property',))
                  if d.objc_name == name]
    seen, unique = set(), []
    for d in sorted(decls, key=lambda d: (d.file, d.line, d.objc_name)):
        key = (d.usr or d.objc_name, d.file, d.line)
        if key not in seen:
            seen.add(key)
            unique.append(d)
    # A selector names its methods, not the accessors of a property with
    # that name: Probe.title is the property, title its getter.
    lines = []
    for d in unique:
        for _, text in c.statuses(d):
            lines.append(line_for(d, text))
    covered = set(d.usr for d in unique)
    for usr in sorted(usrs - covered):
        for r in c.imports.get(usr, ()):
            lines.append('(no declaration in the database)  %s  %s  imported as %s: %s' % (
                display_name(r.objc_name), r.kind, r.swift_name, r.declaration))
    if not lines:
        lines.append('%s: no declaration by this name in the swift_import table of %s or in the database' % (
            name, c.module))
        return lines, 0
    return lines, len(lines)


def display_name(objc_name):
    """The Objective-C name of a symbol graph row whose objc_name is only
    its USR: name() for a function, the name of a typedef, Record.field."""
    if not objc_name.startswith('c:'):
        return objc_name
    m = re.search(r'@F@([A-Za-z_][A-Za-z0-9_]*)$', objc_name)
    if m:
        return m.group(1) + '()'
    m = re.search(r'@(?:S|SA|U|UA)@([A-Za-z_][A-Za-z0-9_]*)@FI@([A-Za-z_][A-Za-z0-9_]*)$', objc_name)
    if m:
        return '%s.%s' % m.groups()
    m = re.search(r'@(?:T|S|SA|U|UA|E|EA)@([A-Za-z_][A-Za-z0-9_]*)$', objc_name)
    if m:
        return m.group(1)
    return objc_name


def write_status(q, out, rows, states, module):
    s = states[module]
    incomplete = [line for line in q.incomplete_lines() if 'Swift modules' not in line]
    if s.state != 'current':
        incomplete.append('INCOMPLETE: the swift_import table of 1 module is not current (%s: %s); %s.' % (
            module, s.state, UPDATE_HINT))
    out.write('\n--- status ---\n')
    for line in incomplete:
        out.write(line + '\n')
    label = {'current': 'current', 'stale': 'STALE', 'missing': 'MISSING', 'failed': 'FAILED', 'incomplete':
             'INCOMPLETE', 'orphan': 'NOT CAPTURED', 'not checked': 'NOT CHECKED'}[s.state]
    out.write('swift imports: module %s (bridging header %s): %s%s, compiler %s\n' % (
        module, s.header or '?', label, ' (%s)' % s.reason if s.reason else '', s.compiler or 'unknown'))
    out.write('database: %s\n' % q.paths.db)
    by_state, errors = q.counts()
    out.write('units: %d, of which not current %d (their declarations may be missing or wrong)\n' % (
        len(q.states), len(q.not_current())))
    out.write(ABSENT_NOTE + '\n')
    out.write('Not in this answer:\n')
    for item in LIMITS:
        out.write('  - %s\n' % item)
    out.write(EXIT_TEXT + '\n')
    for line in incomplete:
        out.write(line + '\n')
    if incomplete:
        return 3
    return 0 if rows else 1
