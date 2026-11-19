#!/usr/bin/env python3
"""Entry-point census: every way a method or class can be entered.

Part of the Objective-C to Swift migration (docs/swift-migration/phase0.md,
section 2, and hidden-callers.md). Everything the compiler sees comes from
the code database (tools/swift_migration/codedb/codedb.py, phase0.md section
10); text and XML search remain only for what the compiler does not see:
xibs and storyboards, the sdef, property lists, Core Data models, other
resources, and names built at run time, for which the reflective-site
registry (docs/swift-migration/reflective-sites.md) is consulted.

Usage:

  entry_points.py [options] method CLASS SELECTOR   One method: ten sections.
  entry_points.py [options] class CLASS             Class-level facts and a
                                                    table of its methods.
  entry_points.py [options] class CLASS --unreached Its methods with no
                                                    caller found.
  entry_points.py [options] file PATH               The classes PATH
                                                    implements, each as class.

SELECTOR may be prefixed with + or - to choose the class or instance method
(no -- is needed before -selector).
Options: --json; --root (the repository, default: this tool's); --db, --cdb,
--fragments, --swift-work, --extractor, --swift-reader (as codedb.py takes
them); --registry (default: docs/swift-migration/reflective-sites.md);
--sdk-selectors FILE (an interim file of SDK declarations written by
sdk_selectors.py, read only when the database has no sdk_method table);
--runtime-methods FILE (the methods the frameworks implement at run time,
private ones included, written by sdk_selectors.py --runtime-methods on one
OS release or converted from dumped runtime headers by sdk_selectors.py
--runtime-methods-from-headers; give it once per release; a selector found in
any list counts; a list must say its kind, live or derived from dumped
headers, and end with its "# end: C=n M=n" trailer, or it is refused; the
run names every release consulted with the kind of its list, says which
releases had only dump-derived lists, which cannot show methods other images
add through categories, and that results are incomplete by nature for
releases not consulted); class: --exclude-generated
(the default with --unreached) and --no-exclude-generated.
ENTRY_POINTS_CODEDB_DIR names another directory to import codedb.py and
swiftdb.py from (the database must have the schema that copy expects).

"No caller found" means that every source that could show a caller was
consulted and found nothing; where a source is missing or cannot decide, the
method goes under another heading with the reason. class --unreached puts
each method that no source shows a caller of under one heading: possibly
called by the system (the SDK declares its selector, or it overrides an SDK
member; methods whose only such reason is an unrelated SDK class with the
same selector are a subgroup; so are overrides of methods that a runtime
method list shows the framework implementing, and methods of categories on
framework classes whose selector that class, an ancestor or a framework
subclass implements at run time); weak: no caller found, but a
framework class (any class, either kind) implements a method with this
selector in a runtime method list (the frameworks send many selectors to
objects of unrelated classes after respondsToSelector:); possibly called
through a Swift protocol requirement; referenced in code not compiled in this
configuration (inactive Swift #if clauses, Objective-C ranges every unit
skips, files no unit or captured module compiles, searched as text); defined
in Swift with a Swift USR (Swift callers of such declarations are not in the
code database); candidates not decided (a source is missing: no SDK
declarations, no Swift tables, no swift_protocol, swift_inactive or
pp_skipped table; or there is no runtime method list, which leaves every
candidate undecided whatever its name and its superclass (decisions.md,
2026-11-20: a leading underscore is evidence of nothing); or the class's
superclass chain cannot be followed to a framework class in a list); called
only from tests; declared here and defined elsewhere (a declaration with no
definition, of a class the repository does not define: a prebuilt framework
or private framework API); and no caller found, which only a selector that
no framework class implements in any list given can reach. Methods defined
only in generated files (sources/proto/, sources/CoreDataGeneratedFiles/, or a
first line saying the protocol buffer compiler wrote it) are left out and counted (--no-exclude-generated
keeps them).

Exit status, by the code database's rule: 0 when something was found and
every source is complete and current, 1 when nothing was found and every
source is complete and current, 3 when any source is incomplete or stale
(the answer is printed and marked INCOMPLETE; the interim SDK file and a
runtime method list always make it so, and so does a candidate left undecided
for want of a list), 2 on error. For class --unreached, "something" is a
method with no caller found, and the last line says in words what the status
means. So a class --unreached run that lists any method under no caller found
always exits 3: that heading needs a runtime method list.
"""

import argparse
import collections
import io
import json
import os
import plistlib
import re
import sqlite3
import sys
from xml.parsers import expat

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
CODEDB_DIR = os.environ.get('ENTRY_POINTS_CODEDB_DIR') or os.path.join(HERE, 'codedb')
if CODEDB_DIR not in sys.path:
    sys.path.insert(0, CODEDB_DIR)

import codedb  # noqa: E402
import swiftdb  # noqa: E402

REGISTRY_PATH = os.path.join('docs', 'swift-migration', 'reflective-sites.md')
MIGRATION_TOOLS_DIR = 'tools/swift_migration/'


class CensusError(Exception):
    """A usage or environment error: exit status 2."""


# --- The reflective-site registry -------------------------------------------

class RegistryError(CensusError):
    pass


NAMES_HEADING = '### Names that must be preserved'
NAMES_HEADER = '| Name | Resolves | Runtime name | Note | Sites |'
NAMES_RULE = '|---|---|---|---|---|'
CLASSIFICATIONS = ('CLOSED', 'OPEN-INTERNAL', 'OPEN-EXTERNAL', 'GENERIC', 'NOT-REFLECTIVE', 'UNRESOLVED')
OPEN_CLASSIFICATIONS = ('OPEN-INTERNAL', 'OPEN-EXTERNAL')
PERSISTED_SECTION = 6

NameRow = collections.namedtuple('NameRow', 'name resolves runtime note sites line')
Entry = collections.namedtuple('Entry', 'section heading sites classification text names line')
# A bullet's site: its file, its first line, the function it names (None when
# the bullet names none), and every location it lists: (None, line) for a
# line of its own file and (name, line) for an "also" location, which names a
# file by its path's last components.
Site = collections.namedtuple('Site', 'file line enclosing lines')

_SECTION = re.compile(r'^## (\d+)\. ')
_HEADING = re.compile(r'^#### `([^`]+)`\s*$')
_CLASSIFICATION = re.compile(r'^  \*\*([A-Z][A-Z-]*)\.\*\*\s*(.*)$')
_NAMES_LINE = re.compile(r'^  Names: (.*)$')
_BACKTICKED = re.compile(r'`([^`]+)`')
# The bullet forms of reflective-sites.md (each found in the document):
#   - `FILE:LINE` in `FN`: ...
#   - `FILE:LINE (also NAME:LINE, ...)`: in `FN`: ...
#   - `FILE:LINE, LINE, ... (also NAME:LINE, ...)`: ... (no function)
_BULLET = re.compile(r'^- `(?P<loc>[^`]+)`(?P<rest>.*)$')
_BULLET_LOC = re.compile(r'^(?P<file>[^\s:,()]+):(?P<lines>\d+(?:, \d+)*)(?: \(also (?P<also>[^()]+)\))?$')
_BULLET_ALSO = re.compile(r'^([^\s:,()]+):(\d+)$')
_BULLET_FN = re.compile(r'^:? in `([^`]+)`(?::|$)')


def parse_bullet(line):
    """The Site a registry bullet lists, or None if the bullet is not in one
    of the forms above."""
    m = _BULLET.match(line)
    if not m:
        return None
    lm = _BULLET_LOC.match(m.group('loc'))
    if not lm:
        return None
    numbers = [int(x) for x in lm.group('lines').split(', ')]
    locations = [(None, n) for n in numbers]
    if lm.group('also'):
        for part in lm.group('also').split(', '):
            am = _BULLET_ALSO.match(part.strip())
            if not am:
                return None
            locations.append((am.group(1), int(am.group(2))))
    rest = m.group('rest')
    fm = _BULLET_FN.match(rest)
    if fm:
        enclosing = fm.group(1)
    elif rest.startswith(':'):
        enclosing = None
    else:
        return None
    return Site(lm.group('file'), numbers[0], enclosing, tuple(locations))


class Registry:
    """The names table and the entries (sites with a classification and a
    Names line) of reflective-sites.md. unparsed: (line, text) of every
    bullet of an entry that is not in a form parse_bullet reads."""

    def __init__(self, names, entries, path, unparsed=()):
        self.names = names
        self.entries = entries
        self.path = path
        self.unparsed = list(unparsed)

    def covers(self, f, line, enclosing):
        """Whether an entry lists the call at f:line in the function
        enclosing: a bullet naming that function in that file, or a bullet
        listing that line of that file (directly or as an "also" location).
        Never a whole file."""
        for e in self.entries:
            for s in e.sites:
                if s.file is None:
                    continue
                if s.enclosing is not None and s.file == f and s.enclosing == enclosing:
                    return True
                for name, n in s.lines:
                    if n != line:
                        continue
                    if name is None and s.file == f:
                        return True
                    if name is not None and (f == name or f.endswith('/' + name)):
                        return True
        return False


def parse_registry(text, path=REGISTRY_PATH):
    """Parse the registry, failing loudly (RegistryError) if its shape is not
    the one this parser was written for."""
    lines = text.split('\n')
    try:
        start = lines.index(NAMES_HEADING)
    except ValueError:
        raise RegistryError('%s: no line %r; the registry\'s shape changed' % (path, NAMES_HEADING))
    header = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('|')), None)
    if header is None or lines[header].strip() != NAMES_HEADER:
        raise RegistryError('%s: the names table\'s header is not %r; the registry\'s shape changed' % (
            path, NAMES_HEADER))
    if header + 1 >= len(lines) or lines[header + 1].strip() != NAMES_RULE:
        raise RegistryError('%s:%d: the names table\'s header is not followed by %r' % (path, header + 2, NAMES_RULE))
    names = []
    i = header + 2
    while i < len(lines) and lines[i].startswith('|'):
        row = lines[i].strip()
        if not row.endswith('|'):
            raise RegistryError('%s:%d: a names table row that does not end with |' % (path, i + 1))
        cells = [c.strip() for c in row[1:-1].split('|')]
        if len(cells) != 5:
            raise RegistryError('%s:%d: a names table row with %d cells, not 5' % (path, i + 1, len(cells)))
        m = re.match(r'^`([^`]+)`$', cells[0])
        if not m:
            raise RegistryError('%s:%d: the Name cell %r is not one backticked name' % (path, i + 1, cells[0]))
        runtime = cells[2].strip('`') or None
        sites = [s.strip() for s in cells[4].split(', ') if s.strip()]
        names.append(NameRow(m.group(1), cells[1], runtime, cells[3], sites, i + 1))
        i += 1
    if not names:
        raise RegistryError('%s: the names table has no rows' % path)
    entries = []
    unparsed = []
    section = None
    heading = None
    bullets = []
    pending = None
    after_names = True
    for n, line in enumerate(lines, 1):
        m = _SECTION.match(line)
        if m:
            if pending:
                raise RegistryError('%s:%d: a classification with no Names line before the next section' % (
                    path, pending[2]))
            section, heading, bullets, after_names = int(m.group(1)), None, [], True
            continue
        if line.startswith('### '):
            heading, bullets, after_names = None, [], True
            continue
        m = _HEADING.match(line)
        if m:
            if pending:
                raise RegistryError('%s:%d: a classification with no Names line before the next heading' % (
                    path, pending[2]))
            heading, bullets, after_names = m.group(1), [], True
            continue
        if line.startswith('- `'):
            if pending:
                raise RegistryError('%s:%d: a classification with no Names line before the next site' % (
                    path, pending[2]))
            if after_names:
                bullets, after_names = [], False
            site = parse_bullet(line)
            bullets.append(site if site else Site(None, None, None, ((n, line),)))
            continue
        m = _CLASSIFICATION.match(line)
        if m and section is not None:
            if m.group(1) not in CLASSIFICATIONS:
                raise RegistryError('%s:%d: unknown classification %s' % (path, n, m.group(1)))
            if pending:
                raise RegistryError('%s:%d: two classifications with no Names line between them' % (path, n))
            pending = (m.group(1), m.group(2), n)
            continue
        m = _NAMES_LINE.match(line)
        if m:
            if not pending:
                raise RegistryError('%s:%d: a Names line with no classification before it' % (path, n))
            value = m.group(1).strip()
            found = _BACKTICKED.findall(value)
            if value.rstrip('.') == 'none':
                found = []
            elif not found:
                raise RegistryError('%s:%d: a Names line that is neither "none." nor backticked names' % (path, n))
            for s in bullets:
                if s.file is None:
                    unparsed.append(s.lines[0])
            entries.append(Entry(section, heading, [s for s in bullets if s.file is not None], pending[0], pending[1],
                                 found, pending[2]))
            pending, after_names = None, True
    if pending:
        raise RegistryError('%s:%d: a classification with no Names line' % (path, pending[2]))
    if not entries:
        raise RegistryError('%s: no entries (a classification followed by a Names line) found' % path)
    return Registry(names, entries, path, unparsed)


def name_matches_method(name, cls, selector):
    """How a registry name reaches -[cls selector] or +[cls selector], or None:
    by exact name, by a prefix pattern (prefix*), by a class method prefix
    pattern (Class +prefix*), or by a key-value coding key (Class.key)."""
    m = re.match(r'^(\w+) \+(\w*)\*$', name)
    if m:
        if m.group(1) == cls and selector.startswith(m.group(2)):
            return 'class method prefix pattern %s' % name
        return None
    m = re.match(r'^([^\s.*]+)\*$', name)
    if m:
        return 'selector prefix pattern %s' % name if selector.startswith(m.group(1)) else None
    m = re.match(r'^(\w+)\.(\w+)$', name)
    if m:
        if m.group(1) == cls and m.group(2) in codedb.kvc_keys(selector):
            return 'key-value coding key %s' % name
        return None
    return 'exact name' if name == selector else None


def name_matches_class(name, cls):
    """How a registry name names cls, or None."""
    if name == cls:
        return 'exact name'
    m = re.match(r'^(\w+)(?:\.\w+| \+\w*\*)$', name)
    if m and m.group(1) == cls:
        return 'names a member of the class: %s' % name
    return None


# --- Interface Builder, the sdef, plists, Core Data, other resources --------

def parse_xml(text):
    """[element dict] of an XML document, in document order: tag, attrs,
    line, col, parent (index), children (indexes), text. Raises ValueError
    if it is not well-formed."""
    parser = expat.ParserCreate()
    parser.buffer_text = True
    elements = []
    stack = []

    def start(tag, attrs):
        e = {'tag': tag, 'attrs': attrs, 'line': parser.CurrentLineNumber, 'col': parser.CurrentColumnNumber + 1,
             'parent': stack[-1] if stack else None, 'children': [], 'text': ''}
        if stack:
            elements[stack[-1]]['children'].append(len(elements))
        elements.append(e)
        stack.append(len(elements) - 1)

    def end(tag):
        stack.pop()

    def chars(data):
        if stack:
            elements[stack[-1]]['text'] += data

    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.CharacterDataHandler = chars
    try:
        parser.Parse(text, True)
    except expat.ExpatError as e:
        raise ValueError(str(e))
    return elements


# The AppKit class an IB element stands for when it names no custom class.
IB_DEFAULT_CLASSES = {'customObject': 'NSObject', 'customView': 'NSView', 'button': 'NSButton',
                      'menuItem': 'NSMenuItem', 'menu': 'NSMenu', 'textField': 'NSTextField',
                      'window': 'NSWindow', 'viewController': 'NSViewController',
                      'windowController': 'NSWindowController', 'tableView': 'NSTableView',
                      'outlineView': 'NSOutlineView', 'popUpButton': 'NSPopUpButton', 'view': 'NSView',
                      'imageView': 'NSImageView', 'scrollView': 'NSScrollView', 'slider': 'NSSlider',
                      'segmentedControl': 'NSSegmentedControl', 'searchField': 'NSSearchField',
                      'textView': 'NSTextView', 'panel': 'NSPanel', 'box': 'NSBox', 'matrix': 'NSMatrix',
                      'stepper': 'NSStepper', 'colorWell': 'NSColorWell', 'comboBox': 'NSComboBox',
                      'tabView': 'NSTabView', 'splitView': 'NSSplitView', 'stackView': 'NSStackView',
                      'toolbarItem': 'NSToolbarItem', 'arrayController': 'NSArrayController',
                      'userDefaultsController': 'NSUserDefaultsController',
                      'objectController': 'NSObjectController', 'treeController': 'NSTreeController'}

# kind: files-owner, first-responder, application, object
IBObject = collections.namedtuple('IBObject', 'kind cls desc')
IBAction = collections.namedtuple('IBAction', 'file line col selector target')
IBOutlet = collections.namedtuple('IBOutlet', 'file line col property owner destination collection dest')
IBCustomClass = collections.namedtuple('IBCustomClass', 'file line col cls module desc')
IBKeyed = collections.namedtuple('IBKeyed', 'file line col kind key_path name target')  # binding, runtime attribute


def ib_object(elements, by_id, oid):
    """The IBObject an id names in a xib or storyboard."""
    e = by_id.get(oid)
    attrs = e['attrs'] if e is not None else {}
    if oid == '-1' or attrs.get('placeholderIdentifier') == 'IBFirstResponder' or \
            attrs.get('sceneMemberID') == 'firstResponder' or attrs.get('customClass') == 'FirstResponder':
        return IBObject('first-responder', None, 'First Responder')
    if oid == '-2' or attrs.get('placeholderIdentifier') == 'IBFilesOwner':
        cls = attrs.get('customClass') or 'NSObject'
        return IBObject('files-owner', cls, "File's Owner (%s)" % cls)
    if oid == '-3' or (e is not None and e['tag'] == 'application'):
        return IBObject('application', None, 'Application (NSApp, of the principal class)')
    if e is None:
        return IBObject('object', None, 'unresolved id %s' % oid)
    cls = attrs.get('customClass')
    if cls:
        module = attrs.get('customModule')
        return IBObject('object', cls, '%s id=%s (%s%s)' % (e['tag'], oid, module + '.' if module else '', cls))
    default = IB_DEFAULT_CLASSES.get(e['tag'], 'NS' + e['tag'][:1].upper() + e['tag'][1:])
    return IBObject('object', default, '%s id=%s (%s, from the element)' % (e['tag'], oid, default))


def parse_ib(path, text):
    """(actions, outlets, custom classes, bindings and runtime attributes) of
    one xib or storyboard."""
    elements = parse_xml(text)
    by_id = {}
    for e in elements:
        if 'id' in e['attrs']:
            by_id.setdefault(e['attrs']['id'], e)
    actions, outlets, classes, keyed = [], [], [], []

    def owner_of(e):
        # connections and userDefinedRuntimeAttributes are children of the
        # object they belong to.
        if e['parent'] is None or elements[e['parent']]['parent'] is None:
            return IBObject('object', None, 'unknown')
        owner = elements[elements[e['parent']]['parent']]
        oid = owner['attrs'].get('id')
        return ib_object(elements, by_id, oid) if oid is not None else IBObject('object', None, owner['tag'])

    for e in elements:
        tag, attrs = e['tag'], e['attrs']
        if tag == 'action' and 'selector' in attrs:
            actions.append(IBAction(path, e['line'], e['col'], attrs['selector'],
                                    ib_object(elements, by_id, attrs.get('target', ''))))
        elif tag in ('outlet', 'outletCollection') and 'property' in attrs:
            dest = ib_object(elements, by_id, attrs.get('destination', ''))
            outlets.append(IBOutlet(path, e['line'], e['col'], attrs['property'], owner_of(e), dest.desc,
                                    tag == 'outletCollection', dest))
        elif tag == 'binding' and 'keyPath' in attrs:
            keyed.append(IBKeyed(path, e['line'], e['col'], 'binding', attrs['keyPath'], attrs.get('name'),
                                 ib_object(elements, by_id, attrs.get('destination', ''))))
        elif tag == 'userDefinedRuntimeAttribute' and 'keyPath' in attrs:
            keyed.append(IBKeyed(path, e['line'], e['col'], 'runtime attribute', attrs['keyPath'], None,
                                 owner_of(e)))
        if attrs.get('customClass') and attrs['customClass'] != 'FirstResponder':
            obj = ib_object(elements, by_id, attrs.get('id', '')) if 'id' in attrs else IBObject(
                'object', attrs['customClass'], tag)
            classes.append(IBCustomClass(path, e['line'], e['col'], attrs['customClass'], attrs.get('customModule'),
                                         obj.desc))
    return actions, outlets, classes, keyed


def camel_case(name):
    """An sdef name as a key, as the binding tests compute it."""
    words = name.split(' ')
    return ''.join([words[0].lower()] + [w[:1].upper() + w[1:] for w in words[1:]])


def capitalized(key):
    return key[:1].upper() + key[1:]


SdefItem = collections.namedtuple('SdefItem', 'file line kind sdef_class cocoa_class name key access')
# kind: class, property, element, responds-to (key = the method), command (cocoa_class = its class), value-type


def parse_sdef(path, text):
    """[SdefItem] of a scripting definition."""
    elements = parse_xml(text)
    by_name = {}
    for e in elements:
        if e['tag'] == 'class' and 'name' in e['attrs']:
            by_name[e['attrs']['name']] = e

    def cocoa(e, attr):
        for c in e['children']:
            if elements[c]['tag'] == 'cocoa' and attr in elements[c]['attrs']:
                return elements[c]['attrs'][attr]
        return None

    out = []
    for e in elements:
        tag, attrs = e['tag'], e['attrs']
        if tag in ('class', 'class-extension'):
            sdef_name = attrs.get('name') or attrs.get('extends') or '?'
            class_element = e if tag == 'class' else by_name.get(attrs.get('extends', ''))
            cocoa_class = (cocoa(class_element, 'class') if class_element is not None else None) or \
                capitalized(camel_case(sdef_name))
            out.append(SdefItem(path, e['line'], tag, sdef_name, cocoa_class, sdef_name, None, None))
            for c in e['children']:
                child = elements[c]
                ca = child['attrs']
                if child['tag'] == 'property':
                    key = cocoa(child, 'key') or camel_case(ca.get('name', '?'))
                    out.append(SdefItem(path, child['line'], 'property', sdef_name, cocoa_class, ca.get('name'), key,
                                        ca.get('access', 'rw')))
                elif child['tag'] == 'element':
                    t = ca.get('type', '?')
                    plural = by_name[t]['attrs'].get('plural') if t in by_name else None
                    key = cocoa(child, 'key') or camel_case(plural or t + 's')
                    out.append(SdefItem(path, child['line'], 'element', sdef_name, cocoa_class, t, key,
                                        ca.get('access', 'rw')))
                elif child['tag'] == 'responds-to':
                    method = cocoa(child, 'method')
                    if method:
                        out.append(SdefItem(path, child['line'], 'responds-to', sdef_name, cocoa_class,
                                            ca.get('command') or ca.get('name'), method, None))
        elif tag in ('command', 'value-type', 'record-type'):
            cls = cocoa(e, 'class')
            if cls:
                out.append(SdefItem(path, e['line'], tag, None, cls, attrs.get('name'), None, None))
    return out


def sdef_accessors(item):
    """The selectors through which scripting reaches an sdef property or
    element: key-value coding accessors of its key, and for an element the
    scripting element accessors."""
    key, cap = item.key, capitalized(item.key)
    out = [key]
    writable = 'w' in (item.access or 'rw')
    if item.kind == 'element':
        # Every accessor Cocoa Scripting and key-value coding look up by name
        # for a to-many key (NSScriptKeyValueCoding among them), whatever
        # the element's access says: that its access="r" keeps the mutators
        # from being called is not established, and a method wrongly listed
        # as having no caller costs more than one listed as reached.
        out += ['countOf%s' % cap, 'objectIn%sAtIndex:' % cap, 'valueIn%sAtIndex:' % cap,
                'valueIn%sWithUniqueID:' % cap, 'valueIn%sWithName:' % cap, 'set%s:' % cap,
                'insertObject:in%sAtIndex:' % cap, 'insert%s:atIndexes:' % cap, 'removeObjectFrom%sAtIndex:' % cap,
                'remove%sAtIndexes:' % cap, 'replaceObjectIn%sAtIndex:withObject:' % cap, 'insertInto%s:' % cap,
                'insertIn%s:atIndex:' % cap, 'insertIn%s:' % cap, 'removeFrom%sAtIndex:' % cap,
                'replaceIn%s:atIndex:' % cap]
    elif writable:
        out.append('set%s:' % cap)
    return out


SERVICES_SUFFIX = ':userData:error:'
PlistFact = collections.namedtuple('PlistFact', 'file line kind value')
# kind: principal class, services message (value: the selector), document class, Info.plist build setting


def line_of(text, needle, default=0):
    i = text.find(needle)
    return text.count('\n', 0, i) + 1 if i >= 0 else default


def parse_plist(path, data):
    """[PlistFact] of a property list: NSPrincipalClass, the selector each
    NSServices entry's NSMessage reaches, and NSDocumentClass. Raises
    ValueError if it is not a property list."""
    try:
        plist = plistlib.loads(data)
    except Exception as e:  # plistlib raises several unrelated types for bad input
        raise ValueError(str(e))
    text = data.decode('utf-8', 'replace') if not data.startswith(b'bplist') else ''
    out = []
    if not isinstance(plist, dict):
        return out
    principal = plist.get('NSPrincipalClass')
    if isinstance(principal, str):
        out.append(PlistFact(path, line_of(text, '>%s<' % principal), 'principal class', principal))
    for service in plist.get('NSServices') or []:
        if isinstance(service, dict) and isinstance(service.get('NSMessage'), str):
            message = service['NSMessage']
            out.append(PlistFact(path, line_of(text, '>%s<' % message), 'services message',
                                 message + SERVICES_SUFFIX))
    for doc in plist.get('CFBundleDocumentTypes') or []:
        if isinstance(doc, dict) and isinstance(doc.get('NSDocumentClass'), str):
            out.append(PlistFact(path, line_of(text, '>%s<' % doc['NSDocumentClass']), 'document class',
                                 doc['NSDocumentClass']))
    return out


_INFOPLIST_PRINCIPAL = re.compile(r'^[ \t]*INFOPLIST_KEY_NSPrincipalClass[ \t]*=[ \t]*"?([A-Za-z_][\w.]*)"?;',
                                  re.M)


def parse_pbxproj(path, text):
    """[PlistFact]: the NSPrincipalClass of each generated Info.plist (an
    INFOPLIST_KEY_NSPrincipalClass build setting). Text search."""
    return [PlistFact(path, text.count('\n', 0, m.start(1)) + 1, 'Info.plist build setting', m.group(1))
            for m in _INFOPLIST_PRINCIPAL.finditer(text)]


CoreDataFact = collections.namedtuple('CoreDataFact', 'file line kind entity cls name')  # kind: entity, attribute,
# relationship


def parse_coredata(path, text):
    elements = parse_xml(text)
    out = []
    for e in elements:
        if e['tag'] != 'entity':
            continue
        entity, cls = e['attrs'].get('name'), e['attrs'].get('representedClassName')
        out.append(CoreDataFact(path, e['line'], 'entity', entity, cls, entity))
        for c in e['children']:
            child = elements[c]
            if child['tag'] in ('attribute', 'relationship', 'fetchedProperty'):
                out.append(CoreDataFact(path, child['line'], child['tag'], entity, cls, child['attrs'].get('name')))
    return out


TEXT_EXTENSIONS = ('.plist', '.json', '.strings', '.js', '.py', '.applescript', '.proto', '.xcconfig')
_TOKEN = re.compile(r'[A-Za-z0-9_:]+')
TextHit = collections.namedtuple('TextHit', 'file line token')
TEST_DIRS = ('ModernTests/', 'tests/', 'iTerm2XCTests/', 'PerformanceTests/', 'UITests/')
SOURCE_EXTENSIONS = ('.m', '.mm', '.h', '.c', '.cc', '.cpp', '.swift')


def is_resource_searched(path):
    """Whether the text search of resources reads this file."""
    if path.startswith(('submodules/', MIGRATION_TOOLS_DIR, 'docs/')) or '.framework/' in path or \
            '.dSYM/' in path:
        return False
    return path.endswith(TEXT_EXTENSIONS)


class Resources:
    """What the files the compiler does not see say, parsed once: xibs and
    storyboards, sdefs, property lists, Core Data models, project files, and
    a token index of other resources for the names asked about."""

    def __init__(self, root, files):
        self.root = root
        self.files = [f for f in files if not f.startswith(('submodules/', MIGRATION_TOOLS_DIR))]
        self.problems = []  # (file, reason): a file this tool could not read as it should
        self.notes = []  # (file, reason): the same, where the text search covers what is lost
        self.actions, self.outlets, self.classes, self.keyed = [], [], [], []
        self.sdef, self.plist, self.coredata = [], [], []
        self.counts = collections.Counter()
        for f in self.files:
            if f.endswith(('.xib', '.storyboard')):
                text = self.read_text(f)
                if text is None:
                    continue
                try:
                    a, o, c, k = parse_ib(f, text)
                except ValueError as e:
                    self.problems.append((f, 'not well-formed XML (%s); not read' % e))
                    continue
                self.counts['ib'] += 1
                self.actions += a
                self.outlets += o
                self.classes += c
                self.keyed += k
            elif f.endswith('.sdef'):
                text = self.read_text(f)
                if text is None:
                    continue
                try:
                    self.sdef += parse_sdef(f, text)
                    self.counts['sdef'] += 1
                except ValueError as e:
                    self.problems.append((f, 'not well-formed XML (%s); not read' % e))
            elif f.endswith('.plist') and '.framework/' not in f and '.dSYM/' not in f:
                data = self.read_bytes(f)
                if data is None:
                    continue
                try:
                    self.plist += parse_plist(f, data)
                    self.counts['plist'] += 1
                except ValueError as e:
                    # Not an incompleteness: the keys read from property
                    # lists are Info.plist keys, and the text search still
                    # reads the file.
                    self.notes.append((f, 'not a property list Python can read (%s); searched as text only' % e))
            elif f.endswith('.xcdatamodel/contents'):
                text = self.read_text(f)
                if text is None:
                    continue
                try:
                    self.coredata += parse_coredata(f, text)
                    self.counts['coredata'] += 1
                except ValueError as e:
                    self.problems.append((f, 'not well-formed XML (%s); not read' % e))
            elif f.endswith('.pbxproj'):
                text = self.read_text(f)
                if text is not None:
                    self.plist += parse_pbxproj(f, text)
                    self.counts['pbxproj'] += 1
        self.text_files = [f for f in self.files if is_resource_searched(f)]
        # {file: project}: xibs and storyboards under a directory that holds
        # another Xcode project or Swift package (a demo app, a framework):
        # not the app's own nibs.
        projects = codedb.other_projects(self.files)
        self.other_project = {}
        for f in set(a.file for a in self.actions) | set(o.file for o in self.outlets) | \
                set(c.file for c in self.classes) | set(k.file for k in self.keyed):
            d = os.path.dirname(f)
            while d and d not in projects:
                d = os.path.dirname(d)
            if d:
                self.other_project[f] = ', '.join(sorted(projects[d]))

    def ib_marks(self, f):
        p = self.other_project.get(f)
        return ['in a directory built by another Xcode project (%s)' % p] if p else []

    def read_bytes(self, f):
        try:
            with open(os.path.join(self.root, f), 'rb') as fh:
                return fh.read()
        except OSError as e:
            self.problems.append((f, 'cannot be read (%s)' % (e.strerror or e)))
            return None

    def read_text(self, f):
        data = self.read_bytes(f)
        if data is None:
            return None
        try:
            return data.decode('utf-8')
        except UnicodeDecodeError:
            self.problems.append((f, 'not UTF-8; not read'))
            return None

    def text_search(self, tokens):
        """{token: [TextHit]} of every whole token (a run of letters, digits,
        _ and :) in the searched resources that is one of tokens. Text
        search: one pass over the files, streaming each."""
        wanted = set(tokens)
        found = collections.defaultdict(list)
        if not wanted:
            return found
        for f in self.text_files:
            try:
                with open(os.path.join(self.root, f), 'r', encoding='utf-8', errors='replace') as fh:
                    for n, line in enumerate(fh, 1):
                        for m in _TOKEN.finditer(line):
                            if m.group(0) in wanted:
                                found[m.group(0)].append(TextHit(f, n, m.group(0)))
            except OSError as e:
                self.problems.append((f, 'cannot be read (%s)' % (e.strerror or e)))
        return found


# --- The code database --------------------------------------------------------

# What a selector passed to a call is for, by the call's selector or function.
SELECTOR_ROLES = [
    ('target-action', ('setAction:', 'setDoubleAction:', 'addTarget:action:', 'sendAction:to:from:', 'sendAction:to:',
                       'tryToPerform:with:', 'targetForAction:', 'targetForAction:to:from:')),
    ('menu item creation', ('initWithTitle:action:keyEquivalent:', 'addItemWithTitle:action:keyEquivalent:',
                            'insertItemWithTitle:action:keyEquivalent:atIndex:')),
    ('gesture recognizer or other target-action initializer', ('initWithTarget:action:',)),
    ('performSelector family', ('makeObjectsPerformSelector:', 'makeObjectsPerformSelector:withObject:',
                                'objc_msgSend', 'cancelPreviousPerformRequestsWithTarget:selector:object:',
                                'detachNewThreadSelector:toTarget:withObject:', 'initWithTarget:selector:object:')),
    ('responds-to check', ('respondsToSelector:', 'instancesRespondToSelector:')),
    ('notification registration', ('addObserver:selector:name:object:',
                                   'addObserver:selector:name:object:suspensionBehavior:')),
    ('timer', ('scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:',
               'timerWithTimeInterval:target:selector:userInfo:repeats:',
               'initWithFireDate:interval:target:selector:userInfo:repeats:')),
    ('NSInvocation or method lookup', ('setSelector:', 'methodSignatureForSelector:',
                                       'instanceMethodSignatureForSelector:', 'methodForSelector:',
                                       'instanceMethodForSelector:', 'class_getInstanceMethod',
                                       'class_getClassMethod', 'class_addMethod', 'class_replaceMethod',
                                       'protocol_getMethodDescription', 'doesNotRecognizeSelector:')),
    ('undo registration', ('registerUndoWithTarget:selector:object:',)),
    ('sorting', ('sortedArrayUsingSelector:', 'sortUsingSelector:', 'sortDescriptorWithKey:ascending:selector:',
                 'initWithKey:ascending:selector:')),
    ('sheet callback', ('beginSheetModalForWindow:modalDelegate:didEndSelector:contextInfo:',)),
    ('Apple event handler', ('setEventHandler:andSelector:forEventClass:andEventID:',)),
]
ROLE_OF = dict((name, role) for role, names in SELECTOR_ROLES for name in names)
# How far above a @selector the call it is passed to may start.
JOIN_LINES = 20


def selector_role(call):
    if call is None:
        return None
    if call.startswith('performSelector'):
        return 'performSelector family'
    return ROLE_OF.get(call)


# Selectors the runtime or AppKit sends by name to any class that has them,
# whether or not the database records an override.
CALLED_BY_NAME = ('load', 'initialize', 'dealloc', '.cxx_destruct', 'awakeFromNib', 'initWithCoder:',
                  'encodeWithCoder:', 'supportsSecureCoding', 'prepareForInterfaceBuilder',
                  'validateMenuItem:', 'validateUserInterfaceItem:', 'validateToolbarItem:')

# --- What the SDK declares ------------------------------------------------------
#
# A method that nothing in the repository calls may still be called by the
# system: an override of an AppKit member, a delegate or data source method,
# a services method, an action the Window menu sends through the responder
# chain. The only general answer is the SDK's own declarations: a method of a
# repository class whose selector (and class-or-instance kind) the SDK
# declares is never "no caller found". They come from the code database's
# sdk_method table, which another unit adds:
#
#   sdk_method(selector TEXT, container TEXT, container_kind TEXT,
#              is_class_method INTEGER, framework TEXT, is_optional INTEGER,
#              is_action INTEGER)
#
# one row per Objective-C method or property accessor declared in a header
# outside the repository; container_kind is class, protocol or category (a
# category's container is written Class(Category)); is_action is 1 when the
# declared result is IBAction; is_optional is 1 for an @optional protocol
# method. Until it exists, --sdk-selectors FILE reads the interim file that
# sdk_selectors.py writes from a text scan of the SDK's headers: lines of
# kind<TAB>container<TAB>+|-<TAB>selector<TAB>framework[<TAB>flags], flags a
# comma-separated list of optional and action, # for comments.

SDK_METHOD_COLUMNS = ('selector', 'container', 'container_kind', 'is_class_method', 'framework', 'is_optional',
                      'is_action')
SDK_CONTAINER_KINDS = ('class', 'protocol', 'category')
SDKDecl = collections.namedtuple('SDKDecl', 'container kind framework optional action')
NO_SDK_REASON = ('INCOMPLETE: the database has no SDK declarations (sdk_method table), so whether the system calls a '
                 'method that nothing in the repository calls is not decided; --sdk-selectors FILE (written by '
                 'tools/swift_migration/sdk_selectors.py) gives an interim answer.')
NO_SDK_HEADING = 'candidates, not decided: the database has no SDK declarations (sdk_method table)'
SDK_HEADING = 'selector declared by the SDK: the system may call it'


def interim_reason(path):
    return ('INCOMPLETE: SDK declarations are read from %s, from a text scan of SDK headers, interim until the code '
            'database records SDK declarations.' % path)


def load_sdk_selectors(path):
    """{(is_class_method, selector): [SDKDecl]} of an interim SDK selector
    file. Raises CensusError if it cannot be read or a line is malformed."""
    out = collections.defaultdict(list)
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for n, line in enumerate(f, 1):
                line = line.rstrip('\n')
                if not line or line.startswith('#'):
                    continue
                cells = line.split('\t')
                if len(cells) not in (5, 6) or cells[0] not in SDK_CONTAINER_KINDS or cells[2] not in ('+', '-') or \
                        not cells[1] or not cells[3]:
                    raise CensusError('%s:%d: not a line of kind, container, +|-, selector, framework[, flags]: %r' % (
                        path, n, line))
                flags = set(cells[5].split(',')) if len(cells) == 6 and cells[5] else set()
                if flags - {'optional', 'action'}:
                    raise CensusError('%s:%d: unknown flags %s' % (path, n, ','.join(sorted(flags))))
                out[(cells[2] == '+', cells[3])].append(SDKDecl(cells[1], cells[0], cells[4], 'optional' in flags,
                                                                'action' in flags))
    except OSError as e:
        raise CensusError('the SDK selector file %s cannot be read (%s)' % (path, e.strerror or e))
    except UnicodeDecodeError:
        raise CensusError('the SDK selector file %s is not UTF-8' % path)
    return out


def describe_sdk(decls):
    """The SDK containers that declare a selector: up to five, and a count."""
    seen = collections.OrderedDict()
    for d in sorted(decls, key=lambda d: (d.container, d.kind)):
        extra = [d.kind, d.framework]
        if d.optional:
            extra.append('optional')
        if d.action:
            extra.append('IBAction: menus and the responder chain send it')
        seen.setdefault('%s (%s)' % (d.container, ', '.join(extra)), None)
    names = list(seen)
    text = ', '.join(names[:5])
    if len(names) > 5:
        text += ', and %d more (%d in all)' % (len(names) - 5, len(names))
    return text


SDK_INHERITED = 'overrides or implements an inherited SDK member'
SDK_UNADOPTED = 'declared by an SDK protocol the class does not formally adopt'
SDK_INFORMAL_CATEGORY = 'declared by an SDK category of NSObject (an informal protocol)'
SDK_ACTION = ('same selector as an action of an SDK class (%s): menus and the responder chain send it to whatever object '
              'implements it')
SDK_UNRELATED = ("same selector as a method of an unrelated SDK class (%s): the system calls that class's method, not "
                 "necessarily this one")
SDK_SWIFT_UNDECIDED = ('not narrowed: the database does not record the conformances of Swift classes to Objective-C '
                       'protocols')
SDK_DECLARED_ONLY = 'not narrowed: no definition is recorded'
# The subgroups of the SDK heading of class --unreached: methods whose only
# reason is an unrelated SDK class with the same selector (what the
# conservative rule costs), and the rest.
SDK_UNRELATED_GROUP = 'only reason: the same selector as a method of an unrelated SDK class'
SDK_OTHER_GROUP = 'declared by an SDK protocol or superclass, an action, an override, or another reason'
PRIVATE_GROUP = ('not declared by the SDK: overrides a private method the framework implements at run time (from the '
                 'runtime method list)')
CATEGORY_GROUP = ('not declared by the SDK: a category on a framework class with the same selector as a method that '
                  'class, an ancestor or a framework subclass implements at run time (from the runtime method list)')
PREBUILT_GROUP = ('not declared by the SDK: the same selector as a method declared in a header of a prebuilt framework '
                  'in the repository (Sparkle, CoreParse and the others), which can send it')
PREBUILT_FLAG = 'declared by a prebuilt framework'


def sdk_label(inherited, objc_defined, swift_defined, decls=()):
    """How a method relates to the SDK's declaration of its selector, and
    whether that is only an unrelated SDK class with the same selector. The
    compiler records, for an Objective-C definition, every superclass and
    formally adopted protocol (of the class, its categories and superclasses)
    that declares the selector (objc_method_override), and, for a Swift
    member, what it overrides; it records no Swift conformance to an
    Objective-C protocol. Returns (label, unrelated)."""
    if inherited:
        return SDK_INHERITED, False
    if objc_defined:
        if any(d.kind == 'protocol' for d in decls):
            return SDK_UNADOPTED, False
        if any(d.kind == 'category' and d.container.startswith('NSObject(') for d in decls):
            return SDK_INFORMAL_CATEGORY, False
        names = ', '.join(sorted(set(d.container for d in decls)))
        if any(d.action for d in decls):
            return SDK_ACTION % names, False
        return SDK_UNRELATED % names, True
    if swift_defined:
        return SDK_SWIFT_UNDECIDED, False
    return SDK_DECLARED_ONLY, False


# --- Framework methods at run time ---------------------------------------------
#
# A method that overrides a private framework method is called by the
# framework, but no SDK header declares it, so neither the sdk_method table
# nor the interim header scan can name it (-[PTYScrollView allowedPocketEdges]:
# NSScrollView implements it on macOS 26). --runtime-methods FILE reads what
# the frameworks implement at run time, private methods included, written by
# sdk_selectors.py --runtime-methods on one machine (or converted from dumped
# headers by sdk_selectors.py --runtime-methods-from-headers): lines of
# C<TAB>class<TAB>superclass (empty for a root class) and
# M<TAB>class<TAB>+|-<TAB>selector, after # comment lines, among them
# "# os: NAME VERSION (BUILD)" and "# kind: live" or "# kind: dumped-headers"
# (a list with no kind line is live only if it has the live writer's
# "# frameworks:" line), ending with "# end: C=n M=n"; a list without a
# matching trailer was cut short and is refused. A dump-derived list has no
# methods that other images add to a class through categories, so every line
# that names a release names the kind of its list. A list is specific to that OS release: a
# private method present on one release may be absent on another. The option
# may be given once per release; a selector found in any list counts, and the
# run names every release consulted and says that releases not consulted are
# not covered, so results are incomplete by nature.
#
# Only the class graph (C lines) is kept in memory after loading; M lines are
# streamed from the file again, once per batch of selectors a run asks about,
# and only the lines for those selectors are kept (RuntimeMethods.prefetch).
#
# The rule (decisions.md, 2026-11-20): no method is "no caller found" without
# a runtime method list, whatever its name and whatever its superclass; a
# leading underscore is evidence of nothing in either direction. With the
# lists, for each candidate of class C (one that no source shows a caller
# of), the superclass chain is followed to the first class that is not a
# repository class (one with an @implementation or a Swift class declaration
# in the repository): S, the framework class. The chain comes from the code
# database's objc_class table (name, superclass) when it has one, else from a
# strict text match of the @interface line or of the Swift class
# declaration's inheritance clause (a text fallback). When S is in no list, or
# the chain cannot be followed, the candidate is not decided. Otherwise it is
# possibly called by the system when:
#   (a) S or an ancestor of S implements the selector with the same
#       class-or-instance kind (an override); or
#   (b) C is itself a framework class (the method is defined in a category
#       on it, such as NSTimer(iTerm)) and a framework subclass of C
#       implements the selector with the same kind (or, for an instance
#       method of a category on a root class, as a class method too, since a
#       root class's instance methods answer class messages): that
#       implementation shadows the category's and may reach it through super;
#       (a) for such a C is a category replacing C's own method or overriding
#       an ancestor's.
# Failing both, when any framework class implements the selector, with
# either kind, the candidate is weak (WEAK_HEADING): the frameworks send many
# selectors to objects of classes unrelated to the one that declares them,
# after respondsToSelector: (delegates, data sources, first responders,
# validation, accessibility, scripting, key-value coding). Only a selector no
# framework class implements in any list stays a candidate for no caller
# found.

RUNTIME_CLASS_LINE = 'C'
RUNTIME_METHOD_LINE = 'M'
_RUNTIME_OS = re.compile(r'^# os: (.+)$')
_RUNTIME_KIND = re.compile(r'^# kind: (.*)$')
_RUNTIME_FRAMEWORKS = re.compile(r'^# frameworks: (.*)$')
_RUNTIME_END = re.compile(r'^# end: C=(\d+) M=(\d+)$')
# The kinds of list, from the "# kind:" line: written from the live runtime
# by sdk_selectors.py --runtime-methods, or converted from dumped headers by
# --runtime-methods-from-headers. A list with no kind line is live only when
# it has the live writer's "# frameworks:" line.
RUNTIME_KIND_LIVE = 'live'
RUNTIME_KIND_DUMP = 'dumped-headers'
RUNTIME_KINDS = (RUNTIME_KIND_LIVE, RUNTIME_KIND_DUMP)
DUMP_CANNOT_SHOW = 'methods that other images add to a class through categories'
RUNTIME_HOW = ('produce one with `python3 tools/swift_migration/sdk_selectors.py --runtime-methods FILE` on each macOS '
               'release at hand (or convert dumped runtime headers with sdk_selectors.py '
               '--runtime-methods-from-headers DIR --os NAME FILE) and pass each with --runtime-methods FILE')
NO_RUNTIME_REASON = ('not decided: no runtime method list (--runtime-methods): cannot tell whether this overrides, '
                     'replaces or shares a selector with a framework method, public or private, whatever its name')
NO_RUNTIME_INCOMPLETE = ('INCOMPLETE: no runtime method list (--runtime-methods FILE, written by '
                         'tools/swift_migration/sdk_selectors.py --runtime-methods), so %d candidates are not decided: '
                         'whether each overrides, replaces or shares a selector with a framework method cannot be '
                         'checked; ' + RUNTIME_HOW + '.')
CHAIN_REASON = 'not decided: the superclass chain could not be followed to a framework class: %s'
CHAIN_INCOMPLETE = ('INCOMPLETE: the superclass chain of %s could not be followed to a framework class (%s), so '
                    'whether its methods override framework methods is not decided.')
RUNTIME_NOT_COVERED_LIVE = ('classes of frameworks the process that wrote a live runtime method list did not load (the '
                            'release names above say how many it loaded and which failed to load; a framework the app '
                            'loads lazily may be missing), and releases for which no list was given')
RUNTIME_NOT_COVERED_DUMP = ('in a list derived from dumped headers, ' + DUMP_CANNOT_SHOW + ' (even public ones such as '
                            '-[NSString sizeWithAttributes:]), and releases for which no list was given')
APP_FRAMEWORKS_NOT_COVERED = ('the app\'s own embedded frameworks (Sparkle, NMSSH, Highlightr, CoreParse, '
                              'BetterFontPicker, ColorPicker, SearchableComboListView, SwiftyMarkdown, the Swift '
                              'packages) are not in a runtime method list unless it was written with '
                              'sdk_selectors.py --runtime-methods --app-bundle, so a category they add to a framework '
                              'class is not seen')
ELSEWHERE_HEADING = 'declared here, defined elsewhere (a prebuilt framework or private framework API)'
ELSEWHERE_REASON = ('declared only, and its class %s is not defined in the repository: a prebuilt framework or private '
                    'framework API defines it; there is nothing in the tree to delete')
WEAK_HEADING = 'weak: no caller found, but a framework class implements a method with this selector'
WEAK_WHY = ('the frameworks send many selectors to objects of classes unrelated to the one that implements them, '
            'after respondsToSelector: (delegates, data sources, first responders, validation, accessibility, '
            'scripting, key-value coding)')
WEAK_CAP = 5


def runtime_reason(runtimes, duplicates=()):
    """The one INCOMPLETE line of a run with runtime method lists
    (RuntimeMethods, each once); duplicates: paths given more than once."""
    paths = ', '.join(r.path for r in runtimes)
    live = [r.os_version for r in runtimes if r.kind == RUNTIME_KIND_LIVE]
    dumps = [r.os_version for r in runtimes if r.kind == RUNTIME_KIND_DUMP]
    twice = (' %s given more than once and counted once.' % ', '.join(duplicates)) if duplicates else ''
    return ('INCOMPLETE: framework methods are read from runtime method lists (%s), each specific to the OS release '
            'it was written on: releases consulted: %s; releases not consulted are not covered (a method present on '
            'one release may be absent on another), so results from the lists are incomplete by nature. Checked with '
            'a live runtime list: %s; checked only with lists derived from dumped headers: %s.%s' % (
                paths, '; '.join(r.label() for r in runtimes), ', '.join(live) or 'none',
                (', '.join(dumps) + ', which cannot show ' + DUMP_CANNOT_SHOW) if dumps else 'none', twice))


def runtime_mark(releases):
    """releases: the labels of the lists that found it."""
    if len(releases) == 1:
        return ('; not declared in the SDK headers (private); from the runtime method list of %s, specific to that OS '
                'version' % releases[0])
    return ('; not declared in the SDK headers (private); from the runtime method lists of %s, specific to those OS '
            'versions' % '; '.join(releases))


def private_override_reason(framework_class, implementer, releases):
    if isinstance(releases, str):
        releases = [releases]
    where = framework_class if implementer == framework_class else '%s (through its ancestor %s)' % (
        framework_class, implementer)
    return "overrides a method that the framework's %s implements at run time%s" % (where, runtime_mark(releases))


def category_reason(framework_class, implementer, releases):
    if implementer == framework_class:
        text = ('category method on the framework class %s, which implements this selector itself at run time: the '
                'category replaces that implementation' % framework_class)
    else:
        text = ('category method on the framework class %s, whose ancestor %s implements this selector at run time: '
                'the category overrides it for %s and its subclasses' % (framework_class, implementer,
                                                                         framework_class))
    return text + runtime_mark(releases)


def category_subclass_reason(framework_class, subclasses, releases):
    shown = ', '.join(subclasses[:WEAK_CAP]) + (', and %d more' % (len(subclasses) - WEAK_CAP)
                                                 if len(subclasses) > WEAK_CAP else '')
    return ("category method on the framework class %s with the same selector as a method its framework subclass %s "
            "implements at run time (%d in all): that implementation shadows the category's for its instances and may "
            "reach it through super%s" % (framework_class, shown, len(subclasses), runtime_mark(releases)))


def weak_reason(implementers, releases):
    """implementers: sorted [(class, is_class_method)]."""
    names = ['%s (%s method)' % (c, 'class' if k else 'instance') for c, k in implementers]
    text = ', '.join(names[:WEAK_CAP])
    if len(names) > WEAK_CAP:
        text += ', and %d more (%d in all)' % (len(names) - WEAK_CAP, len(names))
    where = ('the runtime method list of %s' % releases[0] if len(releases) == 1 else
             'the runtime method lists of %s' % '; '.join(releases))
    return 'weak: no caller found, but a framework class implements a method with this selector: %s; %s; from %s' % (
        text, WEAK_WHY, where)


class RuntimeMethods:
    """What the frameworks implement at run time on one OS release: the
    superclass of every class, kept in memory, and the classes implementing
    each selector a run asks about, streamed from the file on demand."""

    def __init__(self, path, os_version, supers, kind=RUNTIME_KIND_LIVE, frameworks=()):
        self.path = path
        self.os_version = os_version
        self.kind = kind
        self.frameworks = list(frameworks)  # [(name, loaded)], from a live list's "# frameworks:" line
        self._supers = supers  # {class: superclass or None}
        self._by_selector = {}  # {selector: frozenset of (class, is_class_method)}, only selectors asked about

    def has_class(self, cls):
        return cls in self._supers

    def label(self):
        """The release and the kind of list, as every line that names a
        release says it."""
        if self.kind == RUNTIME_KIND_DUMP:
            return '%s [dumped headers: no %s]' % (self.os_version, 'methods added through categories by other images')
        missing = [n for n, ok in self.frameworks if not ok]
        if missing:
            return '%s [live runtime, %d of %d frameworks; not loaded: %s]' % (
                self.os_version, len(self.frameworks) - len(missing), len(self.frameworks), ', '.join(missing))
        return '%s [live runtime, %d frameworks]' % (self.os_version, len(self.frameworks))

    def superclass(self, cls):
        return self._supers.get(cls)

    def selectors_held(self):
        return len(self._by_selector)

    def prefetch(self, selectors):
        """Read, in one pass over the file, the implementers of every
        selector given that is not held yet."""
        wanted = set(selectors) - set(self._by_selector)
        if not wanted:
            return
        found = collections.defaultdict(set)
        intern = sys.intern
        try:
            with open(self.path, 'r', encoding='utf-8') as f:
                for line in f:
                    if not line.startswith('M\t'):
                        continue
                    cells = line.rstrip('\n').split('\t')
                    if len(cells) == 4 and cells[3] in wanted:
                        found[cells[3]].add((intern(cells[1]), cells[2] == '+'))
        except OSError as e:
            raise CensusError('the runtime method list %s cannot be read (%s)' % (self.path, e.strerror or e))
        for sel in wanted:
            self._by_selector[sel] = frozenset(found.get(sel, ()))

    def implementers(self, selector):
        """frozenset of (class, is_class_method) implementing selector."""
        if selector not in self._by_selector:
            self.prefetch([selector])
        return self._by_selector[selector]

    def implementer(self, cls, is_class, selector):
        """The class in cls's chain (cls first) that implements selector with
        that kind, or None. A class method lookup ends, as the runtime's does,
        in the root class's instance methods."""
        impls = self.implementers(selector)
        if not impls:
            return None
        seen = set()
        c = cls
        while c is not None and c in self._supers and c not in seen:
            seen.add(c)
            if (c, is_class) in impls:
                return c
            if is_class and self._supers[c] is None and (c, False) in impls:
                return c
            c = self._supers[c]
        return None

    def subclass_implementers(self, cls, is_class, selector):
        """Sorted framework classes below cls (cls excluded) that implement
        selector with that kind; for an instance method of a root class,
        class methods count too (a root class's instance methods answer
        class messages)."""
        root = cls in self._supers and self._supers[cls] is None
        out = set()
        for c, k in self.implementers(selector):
            if c == cls or not (k == is_class or (root and not is_class and k)):
                continue
            seen = set()
            p = self._supers.get(c)
            while p is not None and p not in seen:
                if p == cls:
                    out.add(c)
                    break
                seen.add(p)
                p = self._supers.get(p)
        return sorted(out)


def parse_frameworks(text):
    """[(name, loaded)] of a "# frameworks:" line's text."""
    out = []
    for part in text.split(','):
        part = part.strip()
        if part:
            loaded = not part.endswith(' (not loaded)')
            out.append((part[:-len(' (not loaded)')] if not loaded else part, loaded))
    return out


def load_runtime_methods(path):
    """The RuntimeMethods of a file written by sdk_selectors.py
    --runtime-methods or --runtime-methods-from-headers, read line by line;
    every line is checked, and only the class graph is kept. Raises
    CensusError if it cannot be read, has no "# os:" line, has no kind (a
    "# kind:" line, or a "# frameworks:" line for an older live list), does
    not end with a "# end: C=n M=n" line whose counts match (a list cut
    short), or a line is malformed."""
    os_version = kind = frameworks = end = None
    supers = {}
    n_classes = n_methods = 0
    intern = sys.intern
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for n, line in enumerate(f, 1):
                line = line.rstrip('\n')
                if not line:
                    continue
                if end is not None:
                    raise CensusError('%s:%d: a line after the "# end:" line: %r' % (path, n, line))
                if line.startswith('#'):
                    m = _RUNTIME_OS.match(line)
                    if m and os_version is None:
                        os_version = m.group(1).strip()
                    m = _RUNTIME_KIND.match(line)
                    if m:
                        kind = m.group(1).strip()
                        if kind not in RUNTIME_KINDS:
                            raise CensusError('%s:%d: unknown kind %r (not %s)' % (path, n, kind,
                                                                                  ' or '.join(RUNTIME_KINDS)))
                    m = _RUNTIME_FRAMEWORKS.match(line)
                    if m and frameworks is None:
                        frameworks = parse_frameworks(m.group(1))
                    if line.startswith('# end:'):
                        m = _RUNTIME_END.match(line)
                        if not m:
                            raise CensusError('%s:%d: a malformed "# end:" line: %r' % (path, n, line))
                        end = (int(m.group(1)), int(m.group(2)), n)
                    continue
                cells = line.split('\t')
                if cells[0] == RUNTIME_CLASS_LINE and len(cells) == 3 and cells[1]:
                    supers[intern(cells[1])] = intern(cells[2]) if cells[2] else None
                    n_classes += 1
                elif cells[0] == RUNTIME_METHOD_LINE and len(cells) == 4 and cells[1] and cells[2] in ('+', '-') and \
                        cells[3]:
                    n_methods += 1
                else:
                    raise CensusError('%s:%d: not a line of C, class, superclass or of M, class, +|-, selector: %r' % (
                        path, n, line))
    except OSError as e:
        raise CensusError('the runtime method list %s cannot be read (%s)' % (path, e.strerror or e))
    except UnicodeDecodeError:
        raise CensusError('the runtime method list %s is not UTF-8' % path)
    if os_version is None:
        raise CensusError('the runtime method list %s has no "# os:" line naming the OS version it was generated on' %
                          path)
    if kind is None:
        if frameworks is None:
            raise CensusError('the runtime method list %s has no "# kind:" line (live or dumped-headers) and no '
                              '"# frameworks:" line, so whether it comes from a live runtime is unknown' % path)
        kind = RUNTIME_KIND_LIVE
    if end is None:
        raise CensusError('the runtime method list %s does not end with a "# end: C=n M=n" line: it was cut short or '
                          'written by an older sdk_selectors.py; regenerate it' % path)
    if (end[0], end[1]) != (n_classes, n_methods):
        raise CensusError('%s:%d: the "# end:" line counts C=%d M=%d, but the list has C=%d M=%d' % (
            path, end[2], end[0], end[1], n_classes, n_methods))
    return RuntimeMethods(path, os_version, supers, kind, frameworks or ())


_OBJC_INTERFACE = re.compile(r'@interface\s+([A-Za-z_]\w*)\s*(?:<[^<>;{}]*>)?\s*:\s*([A-Za-z_]\w*)')
_OBJC_IMPLEMENTATION = re.compile(r'@implementation\s+([A-Za-z_]\w*)\b(?!\s*\()')
_SWIFT_CLASS = re.compile(r'(?:(?:@\w+(?:\([^()\n]*\))?|public|open|internal|private|fileprivate|final)\s+)*'
                          r'\bclass\s+([A-Za-z_]\w*)\s*(?:<[^<>{}]*>)?\s*:\s*([A-Za-z_][\w.]*)')
_SWIFT_OBJC_NAME = re.compile(r'@objc\(([A-Za-z_]\w*)\)')
_COMMENTS = re.compile(r'/\*.*?\*/|//[^\n]*', re.S)


def class_declarations(text, swift):
    """([(class, superclass)], [implemented class], [(Swift name, runtime name)])
    of a source file's text, by strict text match: @interface NAME : SUPER and
    @implementation NAME (not a category), or a Swift class declaration's
    first inherited name (with its @objc(Name), if any). Comments are
    removed first."""
    text = _COMMENTS.sub(' ', text)
    supers, impls, names = [], [], []
    if swift:
        for m in _SWIFT_CLASS.finditer(text):
            sup = m.group(2).split('.')[-1]
            objc = _SWIFT_OBJC_NAME.search(m.group(0))
            supers.append((m.group(1), sup))
            impls.append(m.group(1))
            if objc:
                supers.append((objc.group(1), sup))
                impls.append(objc.group(1))
                names.append((m.group(1), objc.group(1)))
    else:
        supers = [(m.group(1), m.group(2)) for m in _OBJC_INTERFACE.finditer(text)]
        impls = [m.group(1) for m in _OBJC_IMPLEMENTATION.finditer(text)]
    return supers, impls, names


# --- What decides "no caller found" ---------------------------------------------
#
# class --unreached puts every method that no source shows a caller of under
# exactly one heading, in this order of precedence: called (not listed);
# possibly called by the system (SDK_HEADING); possibly called through a
# Swift protocol requirement; referenced in code that is not compiled in
# this configuration; defined in Swift with a Swift USR (Swift callers of it
# are not in the database); not decided (a source is missing); called only
# from tests; and, when every source was consulted and found nothing, no
# caller found. A method that would be no caller found is then checked
# against what the frameworks implement (Private framework methods above): it
# goes under defined elsewhere, possibly called by the system, or not decided
# when that check says so.

SWIFT_DEFINED_HEADING = 'defined in Swift: calls from Swift to Swift declarations are not in the code database'
SWIFT_PROTOCOL_HEADING = 'possibly called through a Swift protocol requirement'
INACTIVE_HEADING = 'referenced in code not compiled in this configuration'
TESTS_HEADING = 'called only from tests: the app does not call it; tests do'
UNDECIDED_HEADING = 'candidates, not decided'
# Which Swift members' Swift callers the database has. The Swift reader
# records a reference only when the declaration it names has an Objective-C
# USR (c:objc(...), or c:@M@Module@objc(...) for a Swift @objc member of an
# NSObject subclass that is neither private nor nested); a Swift USR (s:...:
# a private or fileprivate member, a member of a nested class or of a class
# that is not an NSObject subclass) is dropped. So a Swift-defined member
# with an Objective-C USR is decided like an Objective-C method, and one
# with a Swift USR never is (SWIFT_DEFINED_HEADING).
SWIFT_USR_REASON = ('defined in Swift with a Swift USR (%s): the Swift reader records only references to declarations '
                    'with an Objective-C USR, so Swift callers of it are not in the database')
NO_SWIFT_REASON = ('not decided: the database has no Swift references (no Swift tables), so Swift callers are not '
                   'known')
NO_SWIFT_PROTOCOL_REASON = ('not decided: the database has no swift_protocol table (an older Swift schema), so calls '
                            'through Swift protocol requirements that a method witnesses cannot be found')
NO_SWIFT_INACTIVE_REASON = ('not decided: the database has no swift_inactive table, so Swift code in inactive #if '
                            'clauses cannot be searched')
NO_PP_SKIPPED_REASON = ('not decided: the database has no pp_skipped table (code database schema 10), so Objective-C '
                        'code in inactive #if branches cannot be searched')
# Generated code, out of the migration's scope (README.md section 2): the
# protocol buffer compiler's output and Core Data's generated classes.
GENERATED_DIRS = ('sources/proto/', 'sources/CoreDataGeneratedFiles/')
GENERATED_MARKER = '// Generated by the protocol buffer compiler'
_IDENTIFIER = re.compile(r'[A-Za-z_]\w*')
UNCOMPILED_HITS = 5


def search_tokens(selector):
    """The whole tokens that name selector in code: its first keyword, the
    properties a getter or setter shape stands for (swiftdb's rule: foo for
    setFoo:, foo for isFoo), and the Swift base name of a selector whose
    first keyword is a name followed by With (foo for fooWithBar:; not init,
    which every initializer shares)."""
    first = selector.split(':')[0]
    out = [first] if first else []
    for name, _ in swiftdb.property_candidates_by_name(selector):
        if name not in out:
            out.append(name)
    m = re.match(r'^([a-z]\w*?)With[A-Z]', first)
    if m and m.group(1) != 'init' and m.group(1) not in out:
        out.append(m.group(1))
    return out


def skipped_everywhere(q):
    """{file: [(start, end)]}: the lines of repository files that every unit
    reading the file skips (include guards left out), from pp_skipped and
    tu_input: the code database's own function when it has one, else the
    same computation."""
    own = getattr(codedb, 'skipped_everywhere', None)
    if own is not None:
        return own(q)
    by_file = collections.defaultdict(list)
    for f, view, start, end in q.con.execute(
            "SELECT DISTINCT file, coalesce(view, ''), start_line, end_line FROM pp_skipped WHERE include_guard = 0 "
            "ORDER BY file"):
        by_file[f].append((view, start, end))
    out = {}
    for f, ranges in by_file.items():
        views = set(v for (v,) in q.con.execute("SELECT DISTINCT coalesce(view, '') FROM tu_input WHERE path = ?",
                                                (f,))) or set(v for v, _, _ in ranges)
        lines = None
        for view in views:
            mine = set()
            for v, start, end in ranges:
                if v == view:
                    mine.update(range(start + 1, end))
            lines = mine if lines is None else lines & mine
        segs = []
        for n in sorted(lines or ()):
            if segs and segs[-1][1] == n - 1:
                segs[-1][1] = n
            else:
                segs.append([n, n])
        if segs:
            out[f] = [tuple(s) for s in segs]
    return out


# --- Scripting classes that forward ----------------------------------------------
#
# sdef class (its cocoa class) -> the repository classes that receive its keys
# and commands. Mirrors ModernTests/BindingTestTables.swift
# (sdefForwardingProtocols), which the tests compare with this table.
#
# iTermScriptingWindow (sources/API/iTermScriptingWindow.m) implements
# methodSignatureForSelector: and forwardInvocation: by sending them to
# _underlyingWindow, and forwards valueForKey:, setValue:forKey: and
# objectSpecifier explicitly. -[iTermApplication orderedScriptingWindows]
# (sources/AppKit/iTermApplication.m) wraps only windows that conform to
# PTYWindow, and sources/TerminalView/PTYWindow.h declares the four classes
# that conform to it; sources/Applescript/PTYWindow+Scripting.m defines the
# window's command handlers (iTermWindowScriptingImpl.m) on each of them.
SDEF_FORWARDING = {
    'iTermScriptingWindow': {
        'protocol': 'PTYWindow',
        'classes': ('iTermWindow', 'iTermPanel', 'iTermCompactWindow', 'iTermCompactPanel'),
    },
}
FORWARDING_SELECTORS = ('forwardInvocation:', 'forwardingTargetForSelector:', 'methodSignatureForSelector:')

# Resource text search: a name shorter than this, or a common word, is
# counted per file rather than listed line by line.
SHORT_NAME_LENGTH = 6
COMMON_WORDS = frozenset((
    'action', 'active', 'buffer', 'cancel', 'change', 'changed', 'children', 'client', 'column', 'command', 'commands',
    'config', 'content', 'contents', 'context', 'default', 'delegate', 'delete', 'description', 'display', 'element',
    'enabled', 'filter', 'format', 'handle', 'height', 'hidden', 'identifier', 'images', 'insert', 'layout', 'length',
    'location', 'message', 'number', 'object', 'option', 'options', 'output', 'parent', 'position', 'prefix',
    'profile', 'refresh', 'reload', 'remove', 'render', 'replace', 'request', 'result', 'response', 'search', 'select',
    'selected', 'selection', 'server', 'session', 'sessions', 'settings', 'source', 'status', 'string', 'suffix',
    'target', 'update', 'values', 'visible', 'window', 'windows'))


def is_noisy_name(name):
    """Whether a text search for name lists counts per file, not lines."""
    return len(name) < SHORT_NAME_LENGTH or name.lower() in COMMON_WORDS


def ib_key_parts(key_path):
    """The components of an Interface Builder key path, without a leading
    self (which names the object the binding or attribute is on)."""
    parts = key_path.split('.')
    while len(parts) > 1 and parts[0] == 'self':
        parts = parts[1:]
    return parts


SECTION_TITLES = collections.OrderedDict([
    (1, 'Objective-C callers'),
    (2, 'Swift callers'),
    (3, 'Selector references that are not calls'),
    (4, 'Reflective reach (the registry)'),
    (5, 'Interface Builder'),
    (6, 'Scripting, property lists and other resources'),
    (7, 'Protocols and overrides'),
    (8, 'Persisted and wire names (the registry, section 6)'),
    (9, 'Tests'),
    (10, 'Not covered'),
])


def new_section(number, source):
    return collections.OrderedDict([('number', number), ('title', SECTION_TITLES[number]), ('source', source),
                                    ('complete', True), ('incomplete', []), ('notes', []), ('rows', [])])


def row(file, line, col, what, marks=(), test=False, outside=False, group=None, informational=False):
    """One row of a section. An informational row (where a method is
    defined, a registry site that cannot be ruled out) is not an entry point
    and does not count as something found."""
    r = collections.OrderedDict([('file', file), ('line', line), ('col', col), ('what', what),
                                 ('marks', list(marks))])
    if group:
        r['group'] = group
    if informational:
        r['informational'] = True
    if test:
        r['test'] = True
    if outside:
        r['marks'].append("outside the migration's scope")
    return r


def receiver_class(rtype):
    """The class name a static receiver type names, or None (id, a protocol,
    unknown)."""
    if not rtype:
        return None
    t = re.sub(r'\b(_Nonnull|_Nullable|_Null_unspecified|__kindof|const|__strong|__weak|__unsafe_unretained)\b',
               '', rtype)
    t = t.replace('*', ' ').strip()
    t = re.sub(r'\s*<.*>$', '', t).strip()
    return t if re.match(r'^[A-Za-z_]\w*$', t) and t != 'id' else None


# --- Prebuilt frameworks ---------------------------------------------------------
#
# The app links frameworks that are checked into the repository as built
# bundles (ThirdParty/Sparkle.framework, ThirdParty/CoreParse.framework,
# ThirdParty/NMSSH.framework, the Swift ThirdParty/Highlightr.framework and
# SwiftyMarkdown.framework, and the bundles built from ColorPicker/,
# BetterFontPicker/ and SearchableComboListView/). Their code is not in the
# database and not in the runtime method lists, but it sends the methods
# of its delegate protocols and calls overrides of its classes. Their
# headers are in the repository: the code database records the
# declarations of those a unit reads (objc_method rows whose file is in a
# bundle), and the rest are read as text. A selector declared in any of
# them is never "no caller found", whatever the class or its language.

FRAMEWORK_IN_PATH = re.compile(r'^((?:[^/]+/)*?[^/]+\.framework)/')
# Directories never searched for framework bundles: build products (copies
# of the bundles), scratch, and code outside the app.
FRAMEWORK_SKIP_DIRS = ('.git', 'submodules', 'Build', 'build', 'DerivedData', 'tmp', 'node_modules')
# The migration's own tools and their fixtures, which hold small framework
# bundles of their own.
FRAMEWORK_SKIP_PREFIX = 'tools/swift_migration'


def prebuilt_frameworks(root):
    """Sorted repository-relative paths of the .framework bundles in the
    repository, outside FRAMEWORK_SKIP_DIRS and FRAMEWORK_SKIP_PREFIX."""
    out = []
    for d, dirs, _ in os.walk(root):
        if os.path.relpath(d, root).startswith(FRAMEWORK_SKIP_PREFIX):
            dirs[:] = []
            continue
        keep = []
        for name in dirs:
            if name in FRAMEWORK_SKIP_DIRS:
                continue
            if name.endswith('.framework'):
                out.append(os.path.relpath(os.path.join(d, name), root))
                continue
            keep.append(name)
        dirs[:] = keep
    return sorted(out)


_HEADER_COMMENTS = re.compile(r'/\*.*?\*/|//[^\n]*', re.S)
_HEADER_CONTAINER = re.compile(r'@(?:protocol|interface)\s+([A-Za-z_]\w*)')
_HEADER_MEMBER = re.compile(r'^[ \t]*([-+])[ \t]*\(|^[ \t]*@property\b', re.M)


def _strip_parens(text):
    """text with every parenthesized group removed (nested ones too)."""
    out, depth = [], 0
    for ch in text:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(ch)
    return ''.join(out)


def header_selectors(text):
    """[(selector, container)] of the Objective-C methods and properties a
    header declares, read as text: methods by their keywords, properties by
    their getter (and setter unless readonly, with getter= and setter=)."""
    text = _HEADER_COMMENTS.sub('', text)
    containers = [(m.start(), m.group(1)) for m in _HEADER_CONTAINER.finditer(text)]

    def container_at(pos):
        name = ''
        for start, c in containers:
            if start > pos:
                break
            name = c
        return name

    out = []
    for m in _HEADER_MEMBER.finditer(text):
        end = min([i for i in (text.find(';', m.start()), text.find('{', m.start())) if i >= 0] or [len(text)])
        decl = text[m.start():end]
        where = container_at(m.start())
        if m.group(1):
            body = _strip_parens(decl.split('(', 1)[1].split(')', 1)[1] if ')' in decl else '')
            keywords = re.findall(r'([A-Za-z_]\w*)\s*:', body)
            if keywords:
                out.append((''.join(k + ':' for k in keywords), where))
            else:
                first = re.match(r'\s*([A-Za-z_]\w*)', body)
                if first:
                    out.append((first.group(1), where))
            continue
        attrs = re.match(r'@property\s*\(([^)]*)\)', decl)
        attrs = attrs.group(1) if attrs else ''
        block = re.search(r'\(\s*\^\s*([A-Za-z_]\w*)\s*\)', decl)
        if block:
            name = block.group(1)
        else:
            words = [w for w in re.findall(r'[A-Za-z_]\w*', _strip_parens(decl[len('@property'):]))
                     if not re.match(r'^[A-Z0-9_]+$', w)]
            if not words:
                continue
            name = words[-1]
        getter = re.search(r'getter\s*=\s*([A-Za-z_]\w*)', attrs)
        out.append((getter.group(1) if getter else name, where))
        if not re.search(r'\breadonly\b', attrs):
            setter = re.search(r'setter\s*=\s*([A-Za-z_]\w*:)', attrs)
            out.append((setter.group(1) if setter else 'set%s%s:' % (name[:1].upper(), name[1:]), where))
    return out


def prebuilt_framework_selectors_from_text(root):
    """{selector: {(container, framework)}} from the headers (.h, read as
    text) of every prebuilt framework in the repository."""
    out = collections.defaultdict(set)
    for fw in prebuilt_frameworks(root):
        for d, _, files in os.walk(os.path.join(root, fw)):
            for name in files:
                if not name.endswith('.h'):
                    continue
                try:
                    with open(os.path.join(d, name), encoding='utf-8', errors='replace') as f:
                        text = f.read()
                except OSError:
                    continue
                for sel, container in header_selectors(text):
                    out[sel].add((container, fw))
    return out


class Census:
    """The code database (through codedb.QueryContext, which judges every
    unit and module), the registry and the resources, for any number of
    questions."""

    def __init__(self, paths, registry_path=None, sdk_selectors=None, runtime_methods=None):
        self.paths = paths
        self.root = paths.root
        self.q = codedb.QueryContext(paths, codedb.REACH_SPEC)
        self.con = self.q.con
        self.test_targets = set(self.q.coverage.test_targets) if self.q.coverage is not None else set()
        tables = codedb.table_names(self.con)
        self.swift_tables = 'swift_ref' in tables and 'swift_unit' in tables and 'swift_objc_decl' in tables
        self.swift_protocol = 'swift_protocol' in tables
        self.swift_inactive = 'swift_inactive' in tables
        self.pp_skipped = 'pp_skipped' in tables
        row_ = self.con.execute("SELECT value FROM swift_meta WHERE key='schema_version'").fetchone() if \
            'swift_meta' in tables else None
        self.swift_schema = row_[0] if row_ else None
        self.swift_unit_targets = dict(self.con.execute('SELECT id, target FROM swift_unit').fetchall()) if \
            self.swift_tables else {}
        self.swift_unit_modules = dict(self.con.execute('SELECT id, module FROM swift_unit').fetchall()) if \
            self.swift_tables else {}
        self.registry_path = registry_path or os.path.join(self.root, REGISTRY_PATH)
        self.registry, self.registry_error = None, None
        try:
            with open(self.registry_path, 'r', encoding='utf-8') as f:
                self.registry = parse_registry(f.read(), os.path.relpath(self.registry_path, self.root))
        except OSError as e:
            self.registry_error = 'the registry %s cannot be read (%s)' % (self.registry_path, e.strerror or e)
        except RegistryError as e:
            self.registry_error = str(e)
        self.registry_unlisted = self.unlisted_dynamic_sites() if self.registry else []
        self.sdk_path = sdk_selectors
        self._sdk_file = None
        if 'sdk_method' in tables:
            columns = [r[1] for r in self.con.execute('PRAGMA table_info(sdk_method)')]
            missing = [c for c in SDK_METHOD_COLUMNS if c not in columns]
            if missing:
                raise CensusError('the sdk_method table has no column %s; this tool reads (%s)' % (
                    ', '.join(missing), ', '.join(SDK_METHOD_COLUMNS)))
            self.sdk_kind = 'table'
        elif sdk_selectors:
            self._sdk_file = load_sdk_selectors(sdk_selectors)
            self.sdk_kind = 'file'
        else:
            self.sdk_kind = None
        if isinstance(runtime_methods, str):
            runtime_methods = [runtime_methods]
        # One RuntimeMethods per --runtime-methods FILE (one per OS release).
        self.runtimes = []
        self.runtime_duplicates = []
        seen = set()
        for p in runtime_methods or []:
            key = os.path.realpath(p)
            if key in seen:
                if p not in self.runtime_duplicates:
                    self.runtime_duplicates.append(p)
                continue
            seen.add(key)
            self.runtimes.append(load_runtime_methods(p))
        self.objc_class_table = 'objc_class' in tables
        if self.objc_class_table:
            columns = [r[1] for r in self.con.execute('PRAGMA table_info(objc_class)')]
            missing = [c for c in ('name', 'superclass') if c not in columns]
            if missing:
                raise CensusError('the objc_class table has no column %s; this tool reads (name, superclass)' %
                                  ', '.join(missing))
        self.objc_impl_table = 'objc_impl' in tables
        self._class_index = None
        self._repo_defined = {}
        self._ancestor = {}
        self._scripting_incomplete = None
        self._resources = None
        self._repo_files = None
        self._source_files = None
        self._outside_protocols = None
        self._uncompiled = None
        self._swift_requirements = None
        self._generated = {}
        self._prebuilt = None

    def close(self):
        self.q.close()

    @property
    def repo_files(self):
        if self._repo_files is None:
            self._repo_files = codedb.repository_files(self.root)
        return self._repo_files

    @property
    def resources(self):
        if self._resources is None:
            self._resources = Resources(self.root, self.repo_files)
        return self._resources

    @property
    def source_files(self):
        """The repository's C-family and Swift files, for the text search
        of string literals (submodules and the migration's tools left out)."""
        if self._source_files is None:
            self._source_files = [f for f in self.repo_files if f.endswith(SOURCE_EXTENSIONS) and
                                  not f.startswith(('submodules/', MIGRATION_TOOLS_DIR))]
        return self._source_files

    def string_literals(self, name):
        """[(file, line)] of every line of a C-family or Swift file that
        contains name as a whole string literal ("name", which @"name" also
        contains). Text search, streaming each file."""
        needle = '"%s"' % name
        out = []
        for f in self.source_files:
            try:
                with open(os.path.join(self.root, f), 'r', encoding='utf-8', errors='replace') as fh:
                    text = fh.read()
            except OSError:
                continue
            if needle not in text:
                continue
            for n, line in enumerate(text.split('\n'), 1):
                if needle in line:
                    out.append((f, n))
        return out

    def outside_protocols(self):
        """{selector: (protocol, class, file, line)}: requirements of protocols
        declared outside the repository that some method here satisfies (the
        first such method), from objc_method_override."""
        if self._outside_protocols is None:
            self._outside_protocols = {}
            for sel, proto, c, f, line in self.con.execute(
                    "SELECT m.selector, o.overridden_container, m.class_name, m.file, m.line FROM "
                    "objc_method_override o JOIN objc_method m ON m.id = o.method WHERE o.outside_repository = 1 AND "
                    "o.overridden_container_kind = 'protocol' AND m.is_definition = 1 ORDER BY m.file, m.line"):
                self._outside_protocols.setdefault(sel, (proto, c, f, line))
        return self._outside_protocols

    def delegations(self, cls):
        """[(stem, appkit class, file, line, col, how)]: where an object of cls is
        made the delegate or data source of an AppKit object: a setDelegate: or
        setDataSource: send in a method of cls, or a delegate or dataSource
        outlet in a xib whose destination is cls. The stem is the AppKit
        class's name without NS, first letter lowered, which its delegate
        methods begin with (comboBox for NSComboBox)."""
        out = []
        for rtype, f, line, col, enclosing, sel in self.con.execute(
                "SELECT DISTINCT receiver_type, file, line, col, enclosing_name, selector FROM send WHERE selector IN "
                "('setDelegate:', 'setDataSource:') AND (enclosing_name LIKE ? OR enclosing_name LIKE ? OR "
                "enclosing_name LIKE ? OR enclosing_name LIKE ?) ORDER BY file, line, col",
                ('-[%s %%' % cls, '+[%s %%' % cls, '-[%s(%%' % cls, '+[%s(%%' % cls)):
            rc = receiver_class(rtype)
            if rc and rc.startswith('NS') and len(rc) > 2:
                out.append((rc[2].lower() + rc[3:], rc, f, line, col, '%s makes this object the %s of a %s (%s)' % (
                    enclosing, 'delegate' if sel == 'setDelegate:' else 'data source', rc, sel)))
        for o in self.resources.outlets:
            if o.property in ('delegate', 'dataSource') and o.dest.cls == cls and o.owner.cls and \
                    o.owner.cls.startswith('NS') and o.file not in self.resources.other_project:
                rc = o.owner.cls
                out.append((rc[2].lower() + rc[3:], rc, o.file, o.line, o.col, 'this object is the %s of %s in a xib'
                            % (o.property, o.owner.desc)))
        return out

    # Completeness of each source.

    def objc_incomplete(self):
        return [line for line in self.q.incomplete_lines() if 'Swift' not in line and 'no rows, but' not in line]

    def swift_incomplete(self):
        out = [line for line in self.q.incomplete_lines() if 'Swift' in line]
        if self.q.swift_states is None:
            out.append('INCOMPLETE: the capture kept no Swift inputs, so Swift references are not in this database.')
        elif not self.swift_tables:
            out.append('INCOMPLETE: the database has no Swift tables.')
        elif self.swift_schema != str(swiftdb.SWIFT_SCHEMA_VERSION):
            out.append('INCOMPLETE: the Swift tables have schema version %s, not %d; their rows are read as they '
                       'are, and what the newer schema adds is missing.' % (self.swift_schema,
                                                                           swiftdb.SWIFT_SCHEMA_VERSION))
        return out

    def registry_incomplete(self):
        if self.registry_error:
            return ['INCOMPLETE: %s' % self.registry_error]
        out = []
        reg_file = os.path.relpath(self.registry_path, self.root)
        for n, text in self.registry.unparsed:
            out.append('INCOMPLETE: the registry\'s bullet at %s:%d is not in a form this tool reads, so the sites it '
                       'lists are not known: "%s"' % (reg_file, n, text))
        if self.registry_unlisted:
            f, line, enclosing, call = self.registry_unlisted[0]
            out.append('INCOMPLETE: %d dynamic reflective call sites in the migration\'s scope are in the database but '
                       'not in the registry (first: %s:%d in %s, %s); the registry is behind the code.' % (
                           len(self.registry_unlisted), f, line, enclosing or '(file scope)', call))
        return out

    def unlisted_dynamic_sites(self):
        """Dynamic reflective calls in the migration's scope that no registry
        entry lists, by function or by line (Registry.covers)."""
        out = []
        for f, line, enclosing, call in self.con.execute(
                "SELECT DISTINCT file, line, enclosing_name, function_or_selector FROM reflective_call WHERE "
                "argument_kind = 'dynamic' AND in_migration_scope = 1 ORDER BY file, line"):
            if not self.registry.covers(f, line, enclosing):
                out.append((f, line, enclosing, call))
        return out

    def sdk_incomplete(self):
        if self.sdk_kind == 'table':
            return []
        if self.sdk_kind == 'file':
            return [interim_reason(self.sdk_path)]
        return [NO_SDK_REASON]

    def runtime_incomplete(self):
        return [runtime_reason(self.runtimes, self.runtime_duplicates)] if self.runtimes else []

    def runtime_has_class(self, cls):
        return any(r.has_class(cls) for r in self.runtimes)

    def class_index(self):
        """({class: {superclass: set of files}}, set of classes implemented)
        of the repository's C-family and Swift files (prebuilt .framework
        directories left out), by strict text match (class_declarations),
        built once."""
        if self._class_index is None:
            supers = collections.defaultdict(lambda: collections.defaultdict(set))
            impls = set()
            for f in self.source_files:
                if '.framework/' in f:
                    continue
                try:
                    with open(os.path.join(self.root, f), 'r', encoding='utf-8', errors='replace') as fh:
                        text = fh.read()
                except OSError:
                    continue
                if 'class' not in text and '@interface' not in text and '@implementation' not in text:
                    continue
                s, i, _ = class_declarations(text, f.endswith('.swift'))
                for name, sup in s:
                    supers[name][sup].add(f)
                impls.update(i)
            self._class_index = (supers, impls)
        return self._class_index

    def repo_defined(self, cls):
        """Whether the repository defines cls: an @implementation of it (not a
        category) or a Swift class declaration, from the database (objc_impl,
        or a method defined in an implementation container) or by text."""
        if cls not in self._repo_defined:
            found = cls in self.class_index()[1]
            if not found and self.objc_impl_table:
                found = bool(self.con.execute("SELECT 1 FROM objc_impl WHERE class_name = ? AND (category IS NULL OR "
                                              "category = '') LIMIT 1", (cls,)).fetchone())
            if not found:
                found = bool(self.con.execute("SELECT 1 FROM objc_method WHERE class_name = ? AND container_kind = "
                                              "'implementation' LIMIT 1", (cls,)).fetchone())
            self._repo_defined[cls] = found
        return self._repo_defined[cls]

    def superclass_of(self, cls, files=()):
        """(superclass, None) or (None, why not): from the objc_class table
        when the database has one and it names one, else from the text
        index (a text fallback), preferring a declaration in files when the
        text names more than one."""
        if self.objc_class_table:
            found = sorted(set(s for (s,) in self.con.execute(
                'SELECT DISTINCT superclass FROM objc_class WHERE name = ?', (cls,)) if s))
            if len(found) == 1:
                return found[0], None
            if len(found) > 1:
                return None, '%s has more than one superclass in the objc_class table (%s)' % (cls, ', '.join(found))
        by_super = self.class_index()[0].get(cls, {})
        if not by_super:
            return None, ('no @interface line or Swift class declaration naming a superclass of %s was found (text '
                          'fallback)' % cls)
        if len(by_super) > 1:
            mine = [s for s, fs in by_super.items() if fs & set(files)]
            if len(mine) == 1:
                return mine[0], None
            return None, '%s is declared with different superclasses (%s) (text fallback)' % (cls, ', '.join(
                '%s in %s' % (s, ', '.join(sorted(fs)[:2])) for s, fs in sorted(by_super.items())))
        return next(iter(by_super)), None

    def framework_ancestor(self, cls, files=()):
        """(S, None): the first class in cls's superclass chain (cls itself
        included) that the repository does not define; or (None, why the
        chain could not be followed). With a runtime list, S must be in it."""
        if cls not in self._ancestor:
            name, seen, why = cls, set(), None
            while True:
                if name in seen:
                    name, why = None, 'the superclass chain of %s has a cycle at %s' % (cls, name)
                    break
                seen.add(name)
                if not self.repo_defined(name):
                    break
                sup, why = self.superclass_of(name, files if name == cls else ())
                if sup is None:
                    name = None
                    break
                name = sup
            if name is not None and self.runtimes and not self.runtime_has_class(name):
                name, why = None, '%s, the first class outside the repository, is not in the runtime method list' % (
                    name)
            self._ancestor[cls] = (name, why)
        return self._ancestor[cls]

    def sdk_declarations(self, selectors):
        """{(is_class_method, selector): [SDKDecl]} for the selectors given,
        from the sdk_method table or the interim file ({} without either)."""
        selectors = sorted(set(selectors))
        out = collections.defaultdict(list)
        if self.sdk_kind == 'file':
            for sel in selectors:
                for is_cls in (False, True):
                    if (is_cls, sel) in self._sdk_file:
                        out[(is_cls, sel)] = list(self._sdk_file[(is_cls, sel)])
        elif self.sdk_kind == 'table':
            for part in chunks(selectors):
                for sel, container, kind, is_cls, framework, optional, action in self.con.execute(
                        'SELECT DISTINCT selector, container, container_kind, is_class_method, framework, is_optional, '
                        'is_action FROM sdk_method WHERE selector IN (%s)' % ','.join('?' * len(part)), part):
                    out[(bool(is_cls), sel)].append(SDKDecl(container, kind, framework, bool(optional), bool(action)))
        return out

    def repository_usrs(self, usrs):
        """The USRs among usrs that name a declaration in the repository: an
        Objective-C method or property, or a Swift declaration visible to
        Objective-C."""
        usrs = sorted(set(u for u in usrs if u))
        found = set()
        for part in chunks(usrs):
            marks = ','.join('?' * len(part))
            for table in ('objc_method', 'objc_property'):
                found.update(u for (u,) in self.con.execute(
                    'SELECT DISTINCT usr FROM %s WHERE usr IN (%s)' % (table, marks), part))
            if self.swift_tables:
                found.update(u for (u,) in self.con.execute(
                    'SELECT DISTINCT usr FROM swift_objc_decl WHERE usr IN (%s)' % marks, part))
                found.update(u for (u,) in self.con.execute(
                    'SELECT DISTINCT property_usr FROM swift_objc_decl WHERE property_usr IN (%s)' % marks, part))
        return found

    def swift_outside_overrides(self, cls):
        """{(is_class_method, selector): overridden USR}: Swift members of cls
        that override a declaration outside the repository (the SDK)."""
        if not self.swift_tables:
            return {}
        rows_ = self.con.execute(
            'SELECT DISTINCT selector, is_class_member, overrides_usr FROM swift_objc_decl WHERE class_name = ? AND '
            'is_override = 1 AND overrides_usr IS NOT NULL AND selector IS NOT NULL', (cls,)).fetchall()
        repo = self.repository_usrs(r[2] for r in rows_)
        return dict(((bool(is_cls), sel), usr) for sel, is_cls, usr in rows_ if usr not in repo)

    def swift_requirements(self):
        """([(protocol, requirement, file, line)] of every Swift protocol
        requirement, [(protocol usr, protocol, class, members implemented
        in the extension, file, line)] of every recorded conformance of an
        Objective-C class to a Swift protocol, {protocol usr: [requirement]}),
        from swift_protocol; three empty values without that table."""
        if self._swift_requirements is None:
            reqs, confs, by_proto = [], [], collections.defaultdict(list)
            if self.swift_protocol:
                for usr, proto, member, f, line in self.con.execute(
                        "SELECT DISTINCT protocol_usr, protocol_name, member, file, line FROM swift_protocol WHERE "
                        "kind = 'requirement' AND member IS NOT NULL ORDER BY protocol_name, member, file, line"):
                    reqs.append((proto, member, f, line))
                    by_proto[usr].append(member)
                for usr, proto, cls, member, f, line in self.con.execute(
                        "SELECT DISTINCT protocol_usr, protocol_name, class_name, member, file, line FROM "
                        "swift_protocol WHERE kind = 'conformance' ORDER BY protocol_name, class_name, file, line"):
                    confs.append((usr, proto, cls, set((member or '').split()), f, line))
            self._swift_requirements = (reqs, confs, by_proto)
        return self._swift_requirements

    def swift_protocol_reasons(self, cls, selector, swift_class):
        """Why a Swift call through a requirement of a Swift protocol may reach
        -[cls selector]: the dump names the requirement, not the method that
        witnesses it, so such calls are not swift_ref rows. A recorded
        conformance of cls (or of another Objective-C class, which may be a
        superclass of cls: the database records no class hierarchy) to a
        protocol whose requirement, not implemented in the conforming
        extension, has a matching Swift base name (swiftdb's rule); and, since
        the conformances of Swift classes are not recorded at all, for a
        Swift class any requirement with a matching base name."""
        reqs, confs, by_proto = self.swift_requirements()
        out = []
        for usr, proto, c, implemented, f, line in confs:
            for req in sorted(set(by_proto.get(usr, ()))):
                if req in implemented or not swiftdb.swift_base_name_matches(selector, req):
                    continue
                if c == cls:
                    out.append('possibly called through the Swift protocol requirement %s.%s: %s conforms to %s '
                               '(%s:%d)' % (proto, req, cls, proto, f, line))
                else:
                    out.append('possibly called through the Swift protocol requirement %s.%s: %s conforms to %s '
                               '(%s:%d) and may be a superclass of %s (the database records no class hierarchy)' % (
                                   proto, req, c, proto, f, line, cls))
        if swift_class:
            for proto, req, f, line in reqs:
                if swiftdb.swift_base_name_matches(selector, req):
                    out.append('possibly called through the Swift protocol requirement %s.%s (%s:%d): the database '
                               'does not record which Swift protocols a Swift class conforms to' % (
                                   proto, req, f, line))
        return out

    def prebuilt_selectors(self):
        """{selector: [(container, framework, source)]}: the selectors
        declared in headers of prebuilt frameworks in the repository, from
        the code database (source 'code database': objc_method rows whose
        file is in a framework bundle, for headers a unit reads) and from
        the headers read as text ('header text'), the database's entry
        preferred for the same container and framework."""
        if self._prebuilt is None:
            found = collections.defaultdict(dict)
            for sel, container, f in self.con.execute(
                    "SELECT DISTINCT selector, container_name, file FROM objc_method WHERE file LIKE '%.framework/%'"):
                m = FRAMEWORK_IN_PATH.match(f or '')
                if not m or f.startswith('/') or f.split('/', 1)[0] in FRAMEWORK_SKIP_DIRS or \
                        f.startswith(FRAMEWORK_SKIP_PREFIX):
                    continue
                found[sel][(container or '', m.group(1))] = 'code database'
            for sel, pairs in prebuilt_framework_selectors_from_text(self.root).items():
                for pair in pairs:
                    found[sel].setdefault(pair, 'header text')
            self._prebuilt = dict((sel, sorted((c, fw, src) for (c, fw), src in d.items()))
                                  for sel, d in found.items())
        return self._prebuilt

    def is_generated(self, f):
        """Whether f is a generated file: under sources/proto/ (the protocol
        buffer compiler's output) or sources/CoreDataGeneratedFiles/ (Core
        Data's generated classes, whose accessors Core Data implements at
        run time), or a first line that says the protocol buffer compiler
        wrote it. The code database has no notion of
        generated files beyond its own Build/ outputs."""
        if f not in self._generated:
            generated = f.startswith(GENERATED_DIRS)
            if not generated:
                try:
                    with open(os.path.join(self.root, f), 'r', encoding='utf-8', errors='replace') as fh:
                        generated = fh.readline().startswith(GENERATED_MARKER)
                except OSError:
                    generated = False
            self._generated[f] = generated
        return self._generated[f]

    def uncompiled_regions(self):
        """{file: [(start, end, where)]}: code that is not compiled in the
        captured configuration, with what it is: the #if clauses of Swift
        files that produced no node of the dump (swift_inactive; a whole file
        where its clauses could not be determined), the Objective-C ranges
        every unit reading the file skips (pp_skipped, include guards left
        out), the C-family files of the project that no unit compiles and the
        files of no project (the code database's coverage), and the Swift
        files of the repository that no captured module compiles (submodules,
        other Xcode projects and the migration's tools left out)."""
        out = collections.defaultdict(list)
        if self.swift_inactive:
            for f, start, end, und in self.con.execute(
                    'SELECT DISTINCT file, start_line, end_line, undetermined FROM swift_inactive ORDER BY file, '
                    'start_line'):
                if und:
                    out[f].append((1, None, 'a Swift file whose #if regions could not be determined'))
                else:
                    out[f].append((start, end, 'a Swift #if clause that is not compiled (lines %d-%d)' % (start, end)))
        if self.pp_skipped:
            for f, ranges in skipped_everywhere(self.q).items():
                for start, end in ranges:
                    out[f].append((start, end, 'an Objective-C range no unit compiles (lines %d-%d)' % (start, end)))
        c = self.q.coverage
        if c is not None:
            for f, reason in c.not_parsed['main_project']:
                out[f].append((1, None, 'a file of the project that no unit compiles (%s)' % reason))
            for f in c.not_parsed['no_project']:
                out[f].append((1, None, 'a file of no project'))
        if self.q.swift_states is not None:
            compiled = set()
            for m in self.q.swift.modules + self.q.swift.excluded:
                for f in m.files:
                    compiled.add(swiftdb.stored_path(f, self.root))
            projects = codedb.other_projects(self.repo_files)
            for f in self.repo_files:
                if not f.endswith('.swift') or f in compiled or f.startswith(('submodules/', MIGRATION_TOOLS_DIR)):
                    continue
                d = os.path.dirname(f)
                while d and d not in projects:
                    d = os.path.dirname(d)
                if not d:
                    out[f].append((1, None, 'a Swift file no captured module compiles'))
        return out

    def uncompiled_missing(self):
        """Reasons the search of code that is not compiled cannot decide."""
        out = []
        if self.swift_tables and not self.swift_inactive:
            out.append(NO_SWIFT_INACTIVE_REASON)
        if not self.pp_skipped:
            out.append(NO_PP_SKIPPED_REASON)
        return out

    def uncompiled_index(self):
        """{token: [(file, line, where)]} (the first UNCOMPILED_HITS of each)
        of every identifier in uncompiled_regions, built once. Text search."""
        if self._uncompiled is None:
            index = {}
            for f, regions in sorted(self.uncompiled_regions().items()):
                try:
                    with open(os.path.join(self.root, f), 'r', encoding='utf-8', errors='replace') as fh:
                        lines = fh.read().split('\n')
                except OSError:
                    continue
                for start, end, where in regions:
                    for n in range(max(start, 1), min(end or len(lines), len(lines)) + 1):
                        for tok in set(_IDENTIFIER.findall(lines[n - 1])):
                            hits = index.setdefault(tok, [])
                            if len(hits) < UNCOMPILED_HITS:
                                hits.append((f, n, where))
            self._uncompiled = index
        return self._uncompiled

    def uncompiled_hits(self, selector, defined_at=()):
        """[(token, file, line, where)]: the selector's first keyword, or a
        Swift name it can take (search_tokens), as a whole token in code that
        is not compiled; lines in defined_at ((file, line)) left out."""
        index = self.uncompiled_index()
        out = []
        for tok in search_tokens(selector):
            for f, n, where in index.get(tok, ()):
                if (f, n) not in defined_at:
                    out.append((tok, f, n, where))
        return out

    def property_names(self, cls, selector):
        """[(property name, role)] a Swift property reference names when it
        calls selector as a getter or a setter: the names the selector's shape
        stands for (foo for foo and setFoo:, foo and isFoo for isFoo; swiftdb's
        rule), and the properties of cls whose accessor it is (a custom getter
        or setter), in Objective-C and Swift."""
        out = list(swiftdb.property_candidates_by_name(selector))
        for name, getter, setter in self.con.execute(
                'SELECT DISTINCT name, getter_selector, setter_selector FROM objc_property WHERE class_name = ? AND '
                '(getter_selector = ? OR setter_selector = ?)', (cls, selector, selector)):
            for role, sel in (('getter', getter), ('setter', setter)):
                if sel == selector and (name, role) not in out:
                    out.append((name, role))
        if self.swift_tables:
            for kind, name in self.con.execute(
                    "SELECT DISTINCT g.kind, p.swift_name FROM swift_objc_decl g JOIN swift_objc_decl p ON p.usr = "
                    "g.property_usr WHERE g.class_name = ? AND g.selector = ? AND g.kind IN ('getter', 'setter')",
                    (cls, selector)):
                if (name, kind) not in out:
                    out.append((name, kind))
        return out

    def sdef_receivers(self, cocoa_class):
        """The classes that receive the keys and commands of an sdef class
        whose cocoa class is cocoa_class: itself and, for a forwarding class,
        the classes in SDEF_FORWARDING."""
        entry = SDEF_FORWARDING.get(cocoa_class)
        return [cocoa_class] + list(entry['classes'] if entry else ())

    def scripting_incomplete(self):
        """Reasons section 6's sdef answer is incomplete for every class: an
        sdef class whose cocoa class forwards messages and has no forwarding
        entry, or a conformer of a forwarding entry's protocol that the entry
        does not list."""
        if self._scripting_incomplete is not None:
            return self._scripting_incomplete
        out = []
        seen = set()
        for item in self.resources.sdef:
            c = item.cocoa_class
            if item.kind not in ('class', 'class-extension') or c in seen:
                continue
            seen.add(c)
            if c in SDEF_FORWARDING:
                continue
            how = []
            sels = set(s for (s,) in self.con.execute(
                'SELECT DISTINCT selector FROM objc_method WHERE class_name = ? AND selector IN (%s) AND '
                '(is_definition = 1 OR container_kind IN (\'interface\', \'category\', \'extension\'))' % ','.join(
                    '?' * len(FORWARDING_SELECTORS)), (c,) + FORWARDING_SELECTORS))
            if self.swift_tables:
                sels.update(s for (s,) in self.con.execute(
                    'SELECT DISTINCT selector FROM swift_objc_decl WHERE class_name = ? AND selector IN (%s)' %
                    ','.join('?' * len(FORWARDING_SELECTORS)), (c,) + FORWARDING_SELECTORS))
            if sels:
                how.append('implements %s' % ', '.join(sorted(sels)))
            if self.con.execute(
                    "SELECT 1 FROM objc_method m JOIN objc_method_override o ON o.method = m.id WHERE m.class_name = ? "
                    "AND (o.overridden_class = 'NSProxy' OR (o.overridden_container = 'NSProxy' AND "
                    "o.overridden_container_kind != 'protocol')) LIMIT 1", (c,)).fetchone():
                how.append('is a subclass of NSProxy')
            if how:
                out.append('INCOMPLETE: the sdef class "%s" has cocoa class %s, which forwards messages (%s) and has '
                           'no entry in this tool\'s forwarding table, so the classes that receive its keys and '
                           'commands are not known.' % (item.sdef_class, c, '; '.join(how)))
        for c, entry in sorted(SDEF_FORWARDING.items()):
            if not entry.get('protocol') or c not in seen:
                continue
            conformers = set(x for (x,) in self.con.execute(
                "SELECT DISTINCT m.class_name FROM objc_method m JOIN objc_method_override o ON o.method = m.id WHERE "
                "o.overridden_container = ? AND o.overridden_container_kind = 'protocol' AND m.class_name IS NOT NULL",
                (entry['protocol'],)))
            extra = sorted(conformers - set(entry['classes']))
            if extra:
                out.append('INCOMPLETE: the database shows %s conforming to %s, which the forwarding entry of %s does '
                           'not list, so scripting may reach classes this tool does not name.' % (
                               ', '.join(extra), entry['protocol'], c))
        self._scripting_incomplete = out
        return out

    # Helpers.

    def marks(self, g):
        return self.q.marks(g['tus'])

    def is_test(self, targets):
        return bool(targets) and set(targets) <= self.test_targets

    def swift_row_marks(self, unit):
        marks = self.q.swift_marks(unit)
        if self.swift_schema != str(swiftdb.SWIFT_SCHEMA_VERSION):
            marks = marks + ['FROM SWIFT TABLES OF SCHEMA %s' % self.swift_schema]
        elif self.q.swift_states is not None and unit not in self.q.swift_by_unit:
            marks = marks + ['MODULE NOT CAPTURED']
        return marks

    def swift_is_test(self, unit):
        return self.swift_unit_targets.get(unit) in self.test_targets

    def class_methods(self, cls):
        """{(is_class_method, selector): {'objc': [(file, line, kind, container)], 'swift': [(file, line,
        kind, swift name, unit, usr)], 'property': bool}} of the methods cls declares or defines, in
        Objective-C and Swift."""
        out = collections.OrderedDict()
        for sel, is_cls, f, line, kind, container, prop, definition in self.con.execute(
                "SELECT DISTINCT selector, is_class_method, file, line, container_kind, container_name, "
                "property_usr IS NOT NULL, is_definition OR is_synthesized_accessor FROM objc_method WHERE "
                "class_name = ? AND container_kind "
                "!= 'protocol' ORDER BY selector, is_class_method, file, line", (cls,)):
            d = out.setdefault((is_cls, sel), {'objc': [], 'swift': [], 'property': False, 'defined': False})
            d['objc'].append((f, line, kind, container))
            d['property'] = d['property'] or bool(prop)
            d['defined'] = d['defined'] or bool(definition)
        if self.swift_tables:
            for sel, is_cls, f, line, kind, swift_name, unit, usr in self.con.execute(
                    'SELECT DISTINCT selector, is_class_member, file, line, kind, swift_name, unit, usr FROM '
                    'swift_objc_decl WHERE class_name = ? AND selector IS NOT NULL ORDER BY selector, '
                    'is_class_member, file, line', (cls,)):
                d = out.setdefault((is_cls, sel), {'objc': [], 'swift': [], 'property': False, 'defined': False})
                d['swift'].append((f, line, kind, swift_name, unit, usr))
                d['defined'] = True
                d['property'] = d['property'] or kind in ('getter', 'setter', 'property')
        return out

    def keys_of(self, cls, selector):
        """The key-value coding keys that reach selector: its shapes, and the
        properties of cls it is an accessor of."""
        keys = codedb.kvc_keys(selector)
        for (name,) in self.con.execute('SELECT DISTINCT name FROM objc_property WHERE class_name = ? AND '
                                        '(getter_selector = ? OR setter_selector = ?)', (cls, selector, selector)):
            if name not in keys:
                keys.append(name)
        return keys


# --- One method -------------------------------------------------------------------

def stem_matches(selector, stem):
    """Whether a selector begins with a delegate stem as a delegate method
    does (comboBoxSelectionDidChange: and comboBox:objectValueForItemAtIndex:
    for comboBox), taking an argument."""
    return (':' in selector and selector.startswith(stem) and len(selector) > len(stem) and
            (selector[len(stem)] == ':' or selector[len(stem)].isupper()))


def parse_selector(text):
    """(is_class_method or None for either, selector)."""
    if text[:1] in '+-' and len(text) > 1:
        return text[0] == '+', text[1:]
    return None, text


def method_dossier(census, cls, selector_text):
    want_class, selector = parse_selector(selector_text)
    if not re.match(r'^[A-Za-z_]\w*(:([A-Za-z_]\w*:)*)?$', selector) and not re.match(r'^(\w*:)+$', selector):
        raise CensusError('not a selector: %r' % selector_text)
    if not re.match(r'^[A-Za-z_]\w*$', cls):
        raise CensusError('not a class name: %r' % cls)
    methods = census.class_methods(cls)
    mine = [(k, v) for k, v in methods.items() if k[1] == selector and (want_class is None or k[0] == want_class)]
    sections = collections.OrderedDict((n, new_section(n, '')) for n in SECTION_TITLES)
    objc_lines = census.objc_incomplete()
    swift_lines = census.swift_incomplete()
    reg_lines = census.registry_incomplete()
    s1, s2, s3, s4, s5, s6, s7, s8, s9, s10 = [sections[n] for n in SECTION_TITLES]

    def incomplete(section, lines):
        if lines:
            section['complete'] = False
            for line in lines:
                if line not in section['incomplete']:
                    section['incomplete'].append(line)

    def add(section, r):
        if r.get('test'):
            r = collections.OrderedDict(r)
            r['group'] = '%d. %s' % (section['number'], section['title']) + (
                ': ' + r['group'] if r.get('group') else '')
            s9['rows'].append(r)
        else:
            section['rows'].append(r)

    # 1. Objective-C callers.
    s1['source'] = 'code database: send (Clang AST of every parsed unit)'
    s1['notes'].append('Message sends are matched by selector, not by receiver type: every send of %s is listed, '
                       'whatever its receiver; the static receiver type is given where the database records it, and '
                       'a send to another type reaches %s only if the object is one at run time.' % (selector, cls))
    incomplete(s1, objc_lines)
    by_receiver = collections.Counter()
    for key, g in codedb.group_rows(census.con.execute(codedb.SEND_ROW_SQL, (selector,)).fetchall(), 15):
        (f, line, col, enclosing, rkind, rtype, macro, mfile, mline, role, eline, ecol, implicit, in_block,
         migration) = key
        what = [enclosing or '(file scope)']
        rclass = receiver_class(rtype)
        if rkind in ('super', 'super_class'):
            what.append('super send (receiver %s)' % (rtype or '?'))
        else:
            what.append('receiver %s%s' % (rtype or '?', '' if rkind == 'instance' else ' (%s)' % rkind))
        if not census.is_test(g['targets']):
            by_receiver['this class' if rclass == cls else 'another or unknown type'] += 1
        if macro:
            what.append(codedb.macro_text(macro, role, mfile, mline, eline, ecol))
        if implicit == 1:
            what.append('dot-syntax accessor')
        elif implicit == 2:
            what.append('subscript accessor')
        if in_block:
            what.append('in block')
        what.append('targets ' + ','.join(sorted(g['targets'])))
        add(s1, row(f, line, col, '  '.join(what), census.marks(g), census.is_test(g['targets']), not migration))
    if by_receiver:
        s1['notes'].append('static receiver type %s: %d; another type, id, or a protocol: %d' % (
            cls, by_receiver['this class'], by_receiver['another or unknown type']))
    if census.pp_skipped:
        skipped = skipped_everywhere(census.q)
        s1['notes'].append('Objective-C code that is not compiled: %d ranges in %d files that every unit reading them '
                           'skips, searched as text for %s (text search, unverified)' % (
                               sum(len(v) for v in skipped.values()), len(skipped), ', '.join(search_tokens(selector))))
        for tok, f, n, where in census.uncompiled_hits(selector):
            if where.startswith('an Objective-C range'):
                add(s1, row(f, n, None, 'text match %s in %s' % (tok, where),
                            group='Objective-C code that is not compiled (text search)'))
    else:
        incomplete(s1, ['INCOMPLETE: ' + NO_PP_SKIPPED_REASON])

    # 2. Swift callers.
    s2['source'] = 'code database: swift_ref (the Swift compiler\'s AST dump of every captured module)'
    s2['notes'].append('Joined by selector, as in section 1; #selector expressions are listed in section 3. A '
                       'property access is listed when it calls this accessor (a read calls the getter, a write '
                       'the setter).')
    incomplete(s2, swift_lines)
    swift_usrs = sorted(set(s[5] for _, v in mine for s in v['swift'] if s[5] and s[5].startswith('s:')))
    if swift_usrs:
        incomplete(s2, ['INCOMPLETE: %s[%s %s] is defined in Swift with a Swift USR (%s): Swift callers of this Swift '
                        'declaration are not recorded (the Swift reader records only references to declarations with '
                        'an Objective-C USR).' % ('+' if mine[0][0][0] else '-', cls, selector, ', '.join(swift_usrs))])
    swift_selector_exprs = []
    if census.swift_tables:
        listed = set()
        for d in swiftdb.swift_refs_for(census.con, selector):
            if d['kind'] == 'selector-expr':
                swift_selector_exprs.append(d)
                continue
            listed.add((d['file'], d['line'], d['col'], d['kind'], d['usr'], d['module']))
            parts = swiftdb.describe_ref(d)
            add(s2, row(d['file'], d['line'], d['col'], '  '.join(parts[1:]), census.swift_row_marks(d['unit']),
                        census.swift_is_test(d['unit']), not d['in_migration_scope']))
        # Property references matched by the property's name in any
        # container (a reference through a protocol type names the
        # protocol's property), as the method table counts them.
        pairs = census.property_names(cls, selector)
        if pairs:
            keys = ('file', 'line', 'col', 'kind', 'usr', 'selector', 'property', 'class_name', 'container_kind',
                    'is_class_method', 'access', 'selector_kind', 'implicit', 'enclosing_name', 'in_closure',
                    'receiver_type', 'in_migration_scope', 'unit', 'module')
            names_ = sorted(set(n for n, _ in pairs))
            for r in census.con.execute(
                    'SELECT %s FROM swift_ref r JOIN swift_unit u ON u.id = r.unit WHERE r.property IN (%s) ORDER BY '
                    'r.file, r.line, r.col' % (swiftdb.SWIFT_REF_COLUMNS, ','.join('?' * len(names_))), names_):
                d = dict(zip(keys, r))
                key = (d['file'], d['line'], d['col'], d['kind'], d['usr'], d['module'])
                if key in listed or not any(n == d['property'] and property_access_reaches(d['kind'], d['access'],
                                                                                            role)
                                            for n, role in pairs):
                    continue
                listed.add(key)
                parts = swiftdb.describe_ref(d)
                add(s2, row(d['file'], d['line'], d['col'], '  '.join(parts[1:] + [
                    'matched by name: the reference is to %s.%s' % (d['class_name'] or '?', d['property'])]),
                    census.swift_row_marks(d['unit']), census.swift_is_test(d['unit']), not d['in_migration_scope']))
        if census.swift_protocol:
            for proto, req, c, f, line in swiftdb.protocol_witness_candidates(census.con, selector):
                add(s2, row(f, line, None, 'possible indirect caller: a Swift call through %s.%s, which %s '
                                           'conforms to, reaches the Objective-C method that witnesses it '
                                           '(the dump names the requirement, not the witness)' % (proto, req, c),
                            group='through a Swift protocol requirement'))
        else:
            incomplete(s2, ['INCOMPLETE: the database has no swift_protocol table, so calls through Swift protocol '
                            'requirements that an Objective-C method witnesses cannot be listed.'])
        if census.swift_inactive:
            count, files, undetermined, forms, matches = swiftdb.inactive_search(census.con, census.root, selector)
            s2['notes'].append('Swift code that is not compiled: %d #if clauses in %d files%s, searched as text for '
                               '%s (text search, unverified)' % (
                                   count, files, ' and %d files searched whole' % undetermined if undetermined
                                   else '', ', '.join(forms)))
            for f, n, form, start, end, und in matches:
                add(s2, row(f, n, None, 'text match %s in a #if clause at lines %d-%d that is not compiled' % (
                    form, start, end) if not und else 'text match %s in a file whose #if regions could not be '
                    'determined' % form, group='inactive #if regions (text search)'))
        else:
            incomplete(s2, ['INCOMPLETE: the database has no swift_inactive table, so Swift code in inactive #if '
                            'regions is not searched.'])

    # 3. Selector references that are not calls.
    s3['source'] = ('code database: selector_ref, reflective_call (resolved selectors and key-value coding keys) and '
                    'swift_ref (#selector)')
    incomplete(s3, objc_lines + swift_lines)
    reflective = collections.OrderedDict()
    for key, g in codedb.group_rows(census.con.execute(
            'SELECT %s FROM reflective_call c JOIN tu t ON t.id = c.tu WHERE c.resolved_selector = ? ORDER BY '
            'c.file, c.line, c.col, c.argument_index' % codedb.REFLECTIVE_COLUMNS, (selector,)).fetchall(),
            codedb.REFLECTIVE_KEY_LEN):
        reflective[key] = g
    used = set()
    for key, g in codedb.group_rows(census.con.execute(codedb.SELECTOR_REF_ROW_SQL, (selector,)).fetchall(), 13):
        (f, line, col, enclosing, sel, macro, mfile, mline, role, eline, ecol, in_block, migration) = key
        what = [enclosing or '(file scope)', '@selector(%s)' % sel]
        # The call a @selector is an argument of: a reflective row of the same
        # function whose argument is this selector expression, on this line
        # or, for a call written over several lines, up to JOIN_LINES above.
        passed = sorted((k for k in reflective if k[0] == f and k[3] == enclosing and k[7] == 'selector-expr' and
                         k[8] == sel and 0 <= line - k[1] <= JOIN_LINES and k not in used),
                        key=lambda k: (line - k[1], k[2]))
        if passed:
            k = passed[0]
            used.add(k)
            r = selector_role(k[4])
            what.append('passed to %s (argument %d)%s' % (k[4], k[5], ': ' + r if r else ''))
        else:
            near = census.con.execute(
                'SELECT selector, line, col FROM send WHERE file = ? AND enclosing_name IS ? AND line BETWEEN ? AND ? '
                'ORDER BY line DESC, col', (f, enclosing, line - JOIN_LINES, line)).fetchall()
            takes = [x for x in near if re.search(r'(^|:)\w*([Ss]elector|[Aa]ction)\w*:', x[0])]
            if takes:
                r = selector_role(takes[0][0])
                what.append('probably passed to %s (a send that takes a selector, in the same function, starting on '
                            'this line or up to %d lines above; the database records no argument link)%s' % (
                                takes[0][0], JOIN_LINES, ': ' + r if r else ''))
            else:
                what.append('not an argument of a recognized call (a comparison, a table, or a call this tool does '
                            'not classify)')
        if macro:
            what.append(codedb.macro_text(macro, role, mfile, mline, eline, ecol))
        if in_block:
            what.append('in block')
        what.append('targets ' + ','.join(sorted(g['targets'])))
        add(s3, row(f, line, col, '  '.join(what), census.marks(g), census.is_test(g['targets']), not migration,
                    group='@selector'))
    for key, g in reflective.items():
        if key in used:
            continue
        parts, migration = codedb.reflective_parts(key)
        r = selector_role(key[4])
        if r:
            parts.append(r)
        parts.append('targets ' + ','.join(sorted(g['targets'])))
        add(s3, row(key[0], key[1], key[2], '  '.join(parts[1:]), census.marks(g), census.is_test(g['targets']),
                    not migration, group='by name'))
    keys = census.keys_of(cls, selector)
    if keys:
        placeholders = ','.join('?' * len(keys))
        rows_ = [r for r in census.con.execute(
            "SELECT %s FROM reflective_call c JOIN tu t ON t.id = c.tu WHERE c.argument_kind IN ('selector-expr', "
            "'string-literal', 'constant') AND c.kind IN ('key', 'key-path', 'predicate-format') AND "
            "(c.argument_text IN (%s) OR c.kind != 'key') ORDER BY c.file, c.line, c.col, c.argument_index" % (
                codedb.REFLECTIVE_COLUMNS, placeholders), keys).fetchall() if codedb.key_matches(r[6], r[8], keys)]
        for key, g in codedb.group_rows(rows_, codedb.REFLECTIVE_KEY_LEN):
            parts, migration = codedb.reflective_parts(key)
            parts.append('targets ' + ','.join(sorted(g['targets'])))
            add(s3, row(key[0], key[1], key[2], '  '.join(parts[1:]), census.marks(g), census.is_test(g['targets']),
                        not migration, group='key-value coding key or key path (%s)' % ', '.join(keys)))
    explained = set((k[0], k[1]) for k in reflective)
    for f, n in census.string_literals(selector):
        if (f, n) in explained:
            continue
        add(s3, row(f, n, None, 'the selector as a string literal "%s" (text search, unverified)' % selector,
                    test=f.startswith(TEST_DIRS), group='string literals naming the selector (text search)'))
    if census.swift_tables:
        for d in swift_selector_exprs:
            parts = swiftdb.describe_ref(d)
            calls = census.con.execute(
                "SELECT DISTINCT selector FROM swift_ref WHERE file = ? AND line = ? AND kind IN ('call', 'init') AND "
                "selector IS NOT NULL AND selector != ? ORDER BY col", (d['file'], d['line'], selector)).fetchall()
            roles = [(s, selector_role(s)) for (s,) in calls if selector_role(s)]
            text = '  '.join(parts[1:])
            if roles:
                text += '  passed to %s: %s' % roles[0]
            else:
                text += '  not an argument of a recognized call on the same line'
            add(s3, row(d['file'], d['line'], d['col'], text, census.swift_row_marks(d['unit']),
                        census.swift_is_test(d['unit']), not d['in_migration_scope'], group='#selector'))

    # 4 and 8. The registry.
    s4['source'] = 'reflective-site registry (%s), parsed' % os.path.relpath(census.registry_path, census.root)
    s8['source'] = s4['source'] + ', section %d' % PERSISTED_SECTION
    incomplete(s4, reg_lines)
    incomplete(s8, reg_lines)
    if census.registry:
        reg = census.registry
        reg_file = os.path.relpath(census.registry_path, census.root)
        for nr in reg.names:
            how = name_matches_method(nr.name, cls, selector) or (
                'class name' if nr.name == cls else None)
            if how:
                s4['rows'].append(row(reg_file, nr.line, None, 'names table: %s (%s)  resolves: %s%s%s  sites: %s' % (
                    nr.name, how, nr.resolves, '  runtime name ' + nr.runtime if nr.runtime else '',
                    '  note: ' + nr.note if nr.note else '', ', '.join(nr.sites)), group='names table'))
        for e in reg.entries:
            hows = [h for h in (name_matches_method(n, cls, selector) or ('class name' if n == cls else None)
                                for n in e.names) if h]
            if not hows:
                continue
            target = s8 if e.section == PERSISTED_SECTION else s4
            target['rows'].append(row(reg_file, e.line, None, 'section %d entry %s: %s (%s)  site: %s' % (
                e.section, e.classification, first_sentence(e.text), hows[0], site_text(e)), group='entries'))
        for e in reg.entries:
            if e.classification in OPEN_CLASSIFICATIONS and not e.names:
                s4['rows'].append(row(reg_file, e.line, None, 'cannot be ruled out: %s site that can reach names '
                                      'the registry does not list: %s  site: %s' % (
                                          e.classification, first_sentence(e.text), site_text(e)),
                                      group='open sites (cannot be ruled out)', informational=True))

    # 5 and 6. Files the compiler does not see.
    res = census.resources
    s5['source'] = 'xibs and storyboards, parsed as XML (%d files)' % res.counts['ib']
    s6['source'] = ('the sdef, property lists and Core Data models, parsed; project files and other resources, '
                    'text search')
    ib_problems = [p for p in res.problems if p[0].endswith(('.xib', '.storyboard'))]
    other_problems = [p for p in res.problems if not p[0].endswith(('.xib', '.storyboard'))]
    incomplete(s5, ['INCOMPLETE: %s: %s' % p for p in ib_problems])
    incomplete(s6, ['INCOMPLETE: %s: %s' % p for p in other_problems])
    incomplete(s6, census.scripting_incomplete())
    for f, reason in res.notes:
        s6['notes'].append('%s: %s' % (f, reason))
    keys_all = census.keys_of(cls, selector)
    for a in res.actions:
        if a.selector != selector:
            continue
        t = a.target
        if t.kind == 'first-responder':
            note = ('any object in the responder chain that implements %s can receive it, not only %s' % (
                selector, cls))
        elif t.cls == cls:
            note = 'target is this class'
        elif t.kind == 'files-owner':
            note = ('File\'s Owner is %s in the xib; the real owner is the object the code passes when it loads '
                    'the nib' % t.cls)
        else:
            note = 'target is another class (%s)' % (t.cls or '?')
        s5['rows'].append(row(a.file, a.line, a.col, 'action %s, target %s: %s' % (a.selector, t.desc, note),
                              group='actions'))
    for o in res.outlets:
        if o.owner.cls == cls and selector in (o.property, 'set%s:' % capitalized(o.property)):
            s5['rows'].append(row(o.file, o.line, o.col, '%s %s on %s, destination %s: set with key-value coding '
                                  'when the nib loads; keep a settable property of that name' % (
                                      'outlet collection' if o.collection else 'outlet', o.property, o.owner.desc,
                                      o.destination), group='outlets'))
    for k in res.keyed:
        parts = ib_key_parts(k.key_path)
        if k.target.cls == cls and parts[0] in keys_all:
            s5['rows'].append(row(k.file, k.line, k.col, '%s %s%s on %s' % (
                k.kind, k.key_path, ' (binding %s)' % k.name if k.name else '', k.target.desc),
                group='bindings and runtime attributes'))
        elif any(p in keys_all for p in parts[1:]):
            s5['rows'].append(row(k.file, k.line, k.col, 'possible: %s %s names the key %s past its first component, '
                                  'on an object whose class is not known; on %s' % (
                                      k.kind, k.key_path, next(p for p in parts[1:] if p in keys_all), k.target.desc),
                                  group='bindings and runtime attributes'))
    for r in s5['rows']:
        r['marks'] += res.ib_marks(r['file'])
    for item in res.sdef:
        if cls not in census.sdef_receivers(item.cocoa_class):
            continue
        via = ('; the cocoa class %s forwards to %s' % (item.cocoa_class, cls)) if item.cocoa_class != cls else ''
        if item.kind in ('property', 'element') and selector in sdef_accessors(item):
            s6['rows'].append(row(item.file, item.line, None, 'sdef %s "%s" of class "%s", key %s (access %s): '
                                  'scripting reaches %s through key-value coding%s' % (
                                      item.kind, item.name, item.sdef_class, item.key, item.access, selector, via),
                                  group='sdef'))
        elif item.kind == 'responds-to' and item.key == selector:
            s6['rows'].append(row(item.file, item.line, None, 'sdef responds-to command "%s" of class "%s": method %s%s'
                                  % (item.name, item.sdef_class, selector, via), group='sdef'))
    for p in res.plist:
        if p.kind == 'services message' and p.value == selector:
            s6['rows'].append(row(p.file, p.line or None, None, 'NSServices message %s: sent to the services '
                                  'provider (the object passed to setServicesProvider: in code)' % p.value,
                                  group='property lists'))
    for c in res.coredata:
        if c.cls == cls and c.kind != 'entity' and c.name in keys_all:
            s6['rows'].append(row(c.file, c.line, None, 'Core Data %s %s of entity %s (class %s)' % (
                c.kind, c.name, c.entity, c.cls), group='Core Data'))
    hits = res.text_search([selector])
    if is_noisy_name(selector):
        per_file = collections.Counter(h.file for h in hits.get(selector, []))
        if per_file:
            s6['notes'].append('%s is shorter than %d characters or a common word, so the text search of other '
                               'resources gives a count per file, not each line.' % (selector, SHORT_NAME_LENGTH))
        for f in sorted(per_file):
            n = per_file[f]
            add(s6, row(f, None, None, 'text: the token %s, %d match%s in this file (a name shorter than %d characters '
                        'or a common word: the lines are not listed)' % (selector, n, '' if n == 1 else 'es',
                                                                         SHORT_NAME_LENGTH),
                        test=f.startswith(TEST_DIRS), group='other resources (text search, unverified)'))
    else:
        for h in hits.get(selector, []):
            add(s6, row(h.file, h.line, None, 'text: the token %s' % h.token, test=h.file.startswith(TEST_DIRS),
                        group='other resources (text search, unverified)'))

    # 7. Protocols and overrides.
    s7['source'] = 'code database: objc_method, objc_method_override, swift_objc_decl'
    incomplete(s7, objc_lines)
    defined = [(k, v) for k, v in mine]
    for (is_cls, sel), v in defined:
        for f, line, kind, container in v['objc']:
            if kind in ('implementation', 'category-implementation'):
                s7['rows'].append(row(f, line, None, '%s[%s %s] implemented here (%s)' % (
                    '+' if is_cls else '-', container, sel, kind), group='where it is defined', informational=True))
        for f, line, kind, swift_name, unit, _ in v['swift']:
            s7['rows'].append(row(f, line, None, 'Swift %s %s, module %s' % (
                kind, swift_name, census.swift_unit_modules.get(unit, '?')), census.swift_row_marks(unit),
                group='where it is defined', informational=True))
    if not defined:
        s7['notes'].append('%s has no recorded declaration or definition of %s in this database (it may inherit '
                           'it, or the selector is misspelled).' % (cls, selector))
    sdk_dirs = []
    for (p,) in census.con.execute('SELECT DISTINCT sdk_path FROM tu WHERE sdk_path IS NOT NULL'):
        for d in (p, os.path.realpath(p)):
            d = d.rstrip('/') + '/'
            if d not in sdk_dirs:
                sdk_dirs.append(d)
    outside_found = False
    for key, g in codedb.group_rows(census.con.execute(
            'SELECT m.file, m.line, m.col, m.is_class_method, m.container_name, m.selector, o.overridden_container, '
            'o.overridden_container_kind, o.is_optional_requirement, o.outside_repository, o.owner_parsed, '
            'o.overridden_file, o.overridden_line, o.overridden_class, o.overridden_class_parsed, '
            'm.in_migration_scope, m.tu, t.target FROM objc_method m JOIN objc_method_override o ON o.method = m.id '
            'JOIN tu t ON t.id = m.tu WHERE m.selector = ? AND m.class_name = ? AND (m.is_definition = 1 OR '
            'm.is_synthesized_accessor = 1) ORDER BY m.file, m.line, o.overridden_container',
            (selector, cls)).fetchall(), 16):
        (f, line, col, is_cls, container, sel, ocontainer, okind, optional, oout, oparsed, ofile, oline, ocls,
         ocls_parsed, migration) = key
        if want_class is not None and bool(is_cls) != want_class:
            continue
        text = codedb.override_description(is_cls, sel, ocontainer, okind, optional, oout, oparsed, ofile, oline,
                                           sdk_dirs, ocls, ocls_parsed)
        outside = bool(oout or not oparsed)
        outside_found = outside_found or outside
        if outside:
            text += ': code outside this database (AppKit, Foundation) calls it'
        elif okind == 'protocol':
            text += ': any holder of a %s reference is a caller, and the selector cannot change alone' % ocontainer
        s7['rows'].append(row(f, line, col, text, census.marks(g), outside=not migration,
                              group='outside the repository' if outside else 'in the repository'))
    informal = 'outside the repository (protocol not declared by this class)'
    impl = [(f, line) for _, v in mine for f, line, kind, _ in v['objc'] if kind in ('implementation',
                                                                                     'category-implementation')]
    known = census.outside_protocols().get(selector)
    if known and not outside_found and impl:
        proto, c, f0, line0 = known
        s7['rows'].append(row(impl[0][0], impl[0][1], None, '%s is a requirement of %s, a protocol declared outside '
                              'the repository that other classes here adopt (first: %s at %s:%d): AppKit calls it on '
                              'an object it uses as a %s, even if %s does not declare the protocol' % (
                                  selector, proto, c, f0, line0, proto, cls), group=informal))
        outside_found = True
    if impl:
        for stem, rc, f, line, col, how in census.delegations(cls):
            if stem_matches(selector, stem):
                s7['rows'].append(row(f, line, col, 'possible: %s, and %s begins with %s, as that class\'s delegate '
                                      'methods do: AppKit may call it' % (how, selector, stem), group=informal))
    for proto, f, line in census.con.execute(
            "SELECT DISTINCT container_name, file, line FROM objc_method WHERE selector = ? AND container_kind = "
            "'protocol' ORDER BY container_name, file, line", (selector,)):
        s7['rows'].append(row(f, line, None, 'protocol %s declares %s: a holder of a %s reference calls it through '
                              'the protocol, whether or not %s declares conformance' % (proto, selector, proto, cls),
                              group='protocols that declare the selector'))
    for key, g in codedb.group_rows(census.con.execute(
            'SELECT m.file, m.line, m.col, m.container_name, m.is_class_method, m.in_migration_scope, m.tu, t.target '
            'FROM objc_method m JOIN objc_method_override o ON o.method = m.id JOIN tu t ON t.id = m.tu WHERE '
            "m.selector = ? AND (o.overridden_container = ? OR o.overridden_class = ?) AND "
            "o.overridden_container_kind != 'protocol' AND m.class_name != ? AND m.is_definition = 1 ORDER BY "
            'm.file, m.line', (selector, cls, cls, cls)).fetchall(), 6):
        f, line, col, container, is_cls, migration = key
        s7['rows'].append(row(f, line, col, '%s[%s %s] overrides it' % ('+' if is_cls else '-', container, selector),
                              census.marks(g), outside=not migration, group='overrides in subclasses'))
    if census.swift_tables:
        for f, line, c, swift_name, unit in census.con.execute(
                'SELECT DISTINCT file, line, class_name, swift_name, unit FROM swift_objc_decl WHERE selector = ? AND '
                'is_override = 1 AND class_name != ? AND overrides_usr LIKE ? ORDER BY file, line',
                (selector, cls, '%(cs)' + cls + '(%')):
            s7['rows'].append(row(f, line, None, 'Swift %s.%s overrides it' % (c, swift_name),
                                  census.swift_row_marks(unit), group='overrides in subclasses'))
    overriders = set((r['file'], r['line']) for r in s7['rows'] if r.get('group') == 'overrides in subclasses')
    for f, line, container, is_cls in census.con.execute(
            "SELECT DISTINCT file, line, container_name, is_class_method FROM objc_method WHERE selector = ? AND "
            "is_definition = 1 AND (class_name IS NULL OR class_name != ?) ORDER BY file, line", (selector, cls)):
        if (f, line) in overriders or (want_class is not None and bool(is_cls) != want_class):
            continue
        s7['rows'].append(row(f, line, None, '%s[%s %s] also implements the selector: a send, #selector or xib '
                              'action matched by selector may reach it instead' % ('+' if is_cls else '-', container,
                                                                                  selector),
                              group='other implementers of the selector', informational=True))
    if census.swift_tables:
        for f, line, c, swift_name, unit in census.con.execute(
                'SELECT DISTINCT file, line, class_name, swift_name, unit FROM swift_objc_decl WHERE selector = ? AND '
                "(class_name IS NULL OR class_name != ?) AND NOT (is_override = 1 AND overrides_usr LIKE ?) "
                'ORDER BY file, line', (selector, cls, '%(cs)' + cls + '(%')):
            s7['rows'].append(row(f, line, None, 'Swift %s.%s also implements the selector: a send, #selector or xib '
                                  'action matched by selector may reach it instead' % (c, swift_name),
                                  census.swift_row_marks(unit), group='other implementers of the selector',
                                  informational=True))
    swift_outside = census.swift_outside_overrides(cls)
    for (is_cls, sel), v in mine:
        usr = swift_outside.get((is_cls, sel))
        if not usr:
            continue
        for f, line, kind, swift_name, unit, _ in v['swift']:
            s7['rows'].append(row(f, line, None, 'Swift %s %s overrides %s, declared outside the repository: code '
                                  'outside this database (AppKit, Foundation) calls it' % (kind, swift_name, usr),
                                  census.swift_row_marks(unit), group='outside the repository'))
            outside_found = True
    incomplete(s7, census.sdk_incomplete())
    sdk = census.sdk_declarations([selector])
    kinds = [k for k, _ in mine] or [(c, selector) for c in ((False, True) if want_class is None else (want_class,))]
    objc_outside = set(k for k, _ in mine if any(r.get('group') == 'outside the repository' for r in s7['rows']))
    for key in kinds:
        decls = sdk.get(key)
        if not decls:
            continue
        info = dict(mine).get(key, {'objc': [], 'swift': []})
        objc_defs = [(f, line) for f, line, kind, _ in info['objc']
                     if kind in ('implementation', 'category-implementation')]
        where = objc_defs[0] if objc_defs else ((info['swift'][0][0], info['swift'][0][1]) if info['swift'] else
                                                (None, None))
        label = sdk_label(key in objc_outside or key in swift_outside, bool(objc_defs), bool(info['swift']), decls)[0]
        s7['rows'].append(row(where[0], where[1], None, 'selector declared by the SDK: %s; %s: the system may call it' %
                              (describe_sdk(decls), label), group='declared by the SDK'))
    if selector in CALLED_BY_NAME and not outside_found:
        s7['rows'].append(row(None, None, None, '%s is sent by the runtime or AppKit by name to any class that has '
                              'it' % selector, group='outside the repository'))
    shapes = [p.pattern for p in codedb.KVC_SHAPES if p.match(selector)]
    if shapes:
        s7['notes'].append('Cocoa looks %s up by assembling a name (a key-value coding or observing shape: %s, key %s)'
                           % (selector, shapes[0], ', '.join(codedb.kvc_keys(selector))))

    # 9. Tests: filled by add().
    s9['source'] = 'the rows of sections 1, 2, 3 and 6 that are in test targets (%s) or test directories' % (
        ', '.join(sorted(census.test_targets)) or 'none recorded')
    s9['notes'].append('A port must keep these compiling, but they do not show that the app needs the name.')
    incomplete(s9, objc_lines + swift_lines)

    total = sum(1 for n in range(1, 10) for r in sections[n]['rows'] if not r.get('informational'))
    # 10. Not covered.
    fill_not_covered(census, s10, selector, total)
    status = finish(census, sections, total)
    signs = sorted(set('+' if k[0] else '-' for k, _ in mine)) if want_class is None else (
        ['+' if want_class else '-'])
    return dossier('method', '%s[%s %s]' % ('/'.join(signs) or '-', cls, selector), sections, status,
                   collections.OrderedDict([('class', cls), ('selector', selector), ('found', total)]))


def first_sentence(text):
    m = re.match(r'(.*?\.)(\s|$)', text)
    return (m.group(1) if m else text)[:300]


def site_text(e):
    if not e.sites:
        return e.heading or '?'
    s = e.sites[0]
    if s.file is None:
        return e.heading or '?'
    return '%s:%d%s' % (s.file, s.line, ' in ' + s.enclosing if s.enclosing else '')


NOT_COVERED_ALWAYS = [
    'strings built at run time beyond the registry: a name assembled from pieces (a format, a concatenation, '
    'token pasting) that no registry entry lists',
    'scripts outside the repository: AppleScript and Python API users call by sdef and API names, which a port '
    'keeps by keeping the sdef and the API',
    'other build configurations and architectures than the one the database was captured from (code in inactive '
    '#if branches is not in the database; the method table and sections 1 and 2 search it as text only)',
    'a target in a xib whose class is a subclass that inherits the method is listed as another class',
    'xib connections whose real owner is set by the code that loads the nib (File\'s Owner names only a class hint)',
    'requirements of private framework protocols and callbacks registered by name in private API are not detectable',
]


def fill_not_covered(census, s10, selector, total):
    q = census.q
    s10['source'] = 'the code database\'s coverage, its text search of files that are not parsed, and fixed limits'
    q.search_not_parsed(selector)
    q.search_forms_text = codedb.TEXT_SEARCH_FORMS
    q.rows_printed = total
    buf = io.StringIO()
    q.write_coverage(buf)
    for line in buf.getvalue().rstrip('\n').split('\n'):
        if line.strip():
            s10['notes'].append(line)
    for f, n, forms, text in q.matches:
        s10['rows'].append(row(f, n, None, 'text match (%s) in a file that is not parsed: %s' % (forms, text.strip()),
                               group='possible callers in files that are not parsed (text search, unverified)'))
    if q.swift_states is not None:
        groups = swiftdb.uncaptured_swift_files(census.root, q.swift.modules + q.swift.excluded,
                                                lambda: census.repo_files)
        s10['notes'].append('Swift files in the repository that no captured module compiles (not in this database): '
                            '%d%s' % (sum(groups.values()), ' (%s)' % ', '.join('%s %d' % kv for kv in
                                                                               sorted(groups.items()))
                                      if groups else ''))
    for item in NOT_COVERED_ALWAYS:
        s10['notes'].append('not covered: ' + item)


def finish(census, sections, total, last=None):
    """The exit status: 3 when any section is incomplete or the database
    says so, else 0 with rows and 1 without. A reason the database gives
    that no section states (no rows, but a file that is not parsed mentions
    the name) is added to the last section, Not covered."""
    census.q.rows_printed = total
    stated = set(line for s in sections.values() for line in s['incomplete'])
    last = last or list(sections.values())[-1]
    for line in census.q.incomplete_lines():
        if line not in stated:
            last['incomplete'].append(line)
            last['complete'] = False
    if any(not s['complete'] for s in sections.values()):
        return 3
    return 0 if total else 1


def dossier(kind, subject, sections, status, extra=None):
    d = collections.OrderedDict([('kind', kind), ('subject', subject), ('exit_status', status),
                                 ('complete', status in (0, 1))])
    reasons = []
    for s in sections.values():
        s['count'] = sum(1 for r in s['rows'] if not r.get('informational'))
        s['informational'] = len(s['rows']) - s['count']
        for line in s['incomplete']:
            if line not in reasons:
                reasons.append(line)
    d['incomplete'] = reasons
    if extra:
        d.update(extra)
    d['sections'] = list(sections.values())
    return d


# --- A class ---------------------------------------------------------------------

REACH_KEYS = ('system', 'weak', 'swift_protocol', 'inactive', 'swift_defined', 'undecided', 'tests', 'elsewhere')


def class_dossier(census, cls, unreached=False, exclude_generated=None):
    if not re.match(r'^[A-Za-z_]\w*$', cls):
        raise CensusError('not a class name: %r' % cls)
    facts = new_section_like('Class facts')
    objc_lines, swift_lines, reg_lines = census.objc_incomplete(), census.swift_incomplete(), \
        census.registry_incomplete()
    res = census.resources
    for line in objc_lines + swift_lines + reg_lines + ['INCOMPLETE: %s: %s' % p for p in res.problems] + \
            census.scripting_incomplete() + census.sdk_incomplete() + census.runtime_incomplete() + \
            ['INCOMPLETE: ' + r for r in missing_sources(census)]:
        if line not in facts['incomplete']:
            facts['incomplete'].append(line)
    facts['complete'] = not facts['incomplete']
    rows_ = facts['rows']
    for kind, container, f in census.con.execute(
            "SELECT DISTINCT container_kind, container_name, file FROM objc_method WHERE class_name = ? AND "
            "container_kind != 'protocol' ORDER BY file, container_kind, container_name", (cls,)):
        rows_.append(row(f, None, None, '%s %s' % (kind, container), group='declared and defined in Objective-C'))
    swift_files = []
    if census.swift_tables:
        for f, unit, n in census.con.execute(
                'SELECT file, unit, count(*) FROM swift_objc_decl WHERE class_name = ? GROUP BY file, unit ORDER BY '
                'file', (cls,)):
            swift_files.append(f)
            rows_.append(row(f, None, None, 'Swift declarations visible to Objective-C: %d (module %s)' % (
                n, census.swift_unit_modules.get(unit, '?')), census.swift_row_marks(unit),
                group='declared in Swift (Swift class, or a Swift extension of an Objective-C class)'))
    for f in swift_files:
        for line, text in swift_objc_names(census.root, f, cls):
            rows_.append(row(f, line, None, text, group='Swift @objc name (text search of the declaring file)'))
    for c in res.classes:
        if c.cls == cls:
            rows_.append(row(c.file, c.line, c.col, 'customClass on %s%s' % (
                c.desc, ', customModule ' + c.module if c.module else ''), group='Interface Builder custom class'))
    for o in res.outlets:
        if o.owner.cls == cls:
            rows_.append(row(o.file, o.line, o.col, 'outlet %s on %s, destination %s' % (o.property, o.owner.desc,
                                                                                        o.destination),
                             group='Interface Builder outlets owned by this class'))
    for a in res.actions:
        if a.target.cls == cls:
            rows_.append(row(a.file, a.line, a.col, 'action %s, target %s' % (a.selector, a.target.desc),
                             group='Interface Builder actions targeting this class'))
    for k in res.keyed:
        if k.target.cls == cls:
            rows_.append(row(k.file, k.line, k.col, '%s %s on %s' % (k.kind, k.key_path, k.target.desc),
                             group='Interface Builder bindings and runtime attributes'))
    for o in res.outlets:
        if o.property in ('delegate', 'dataSource') and o.dest.cls == cls:
            rows_.append(row(o.file, o.line, o.col, '%s of %s' % (o.property, o.owner.desc), res.ib_marks(o.file),
                             group='Interface Builder delegate and data source connections'))
    for item in res.sdef:
        if item.cocoa_class == cls and item.kind in ('class', 'class-extension', 'command', 'value-type',
                                                     'record-type'):
            rows_.append(row(item.file, item.line, None, 'sdef %s "%s"' % (item.kind, item.name), group='sdef'))
        elif item.kind in ('class', 'class-extension') and cls in census.sdef_receivers(item.cocoa_class):
            rows_.append(row(item.file, item.line, None, 'sdef %s "%s", through its cocoa class %s, which forwards to '
                             'this class' % (item.kind, item.name, item.cocoa_class), group='sdef'))
    for p in res.plist:
        if p.kind != 'services message' and p.value == cls:
            rows_.append(row(p.file, p.line or None, None, p.kind + (' (text search)' if p.kind ==
                                                                     'Info.plist build setting' else ''),
                             group='property lists'))
    for c in res.coredata:
        if c.kind == 'entity' and c.cls == cls:
            rows_.append(row(c.file, c.line, None, 'Core Data entity %s' % c.entity, group='Core Data'))
    if census.registry:
        reg_file = os.path.relpath(census.registry_path, census.root)
        for nr in census.registry.names:
            how = name_matches_class(nr.name, cls)
            if how:
                rows_.append(row(reg_file, nr.line, None, 'names table: %s (%s)%s  sites: %s' % (
                    nr.name, how, '  runtime name ' + nr.runtime if nr.runtime else '', ', '.join(nr.sites)),
                    group='registry'))
        for e in census.registry.entries:
            if any(name_matches_class(n, cls) for n in e.names):
                rows_.append(row(reg_file, e.line, None, 'section %d entry %s: %s  site: %s' % (
                    e.section, e.classification, first_sentence(e.text), site_text(e)), group='registry'))
    for key, g in codedb.group_rows(census.con.execute(
            "SELECT %s FROM reflective_call c JOIN tu t ON t.id = c.tu WHERE c.kind = 'class' AND "
            "(c.argument_text = ? OR c.resolved_class = ?) ORDER BY c.file, c.line, c.col" % codedb.REFLECTIVE_COLUMNS,
            (cls, cls)).fetchall(), codedb.REFLECTIVE_KEY_LEN):
        parts, migration = codedb.reflective_parts(key)
        rows_.append(row(key[0], key[1], key[2], '  '.join(parts[1:]), census.marks(g), outside=not migration,
                         group='class looked up by name (reflective calls)'))
    explained = set((r['file'], r['line']) for r in rows_ if r.get('group') == 'class looked up by name '
                    '(reflective calls)')
    for f, n in census.string_literals(cls):
        if (f, n) not in explained:
            rows_.append(row(f, n, None, 'the class name as a string literal "%s" (text search, unverified)' % cls,
                             test=f.startswith(TEST_DIRS), group='string literals naming the class (text search)'))
    for c, f in census.con.execute(
            "SELECT DISTINCT m.class_name, m.file FROM objc_method m JOIN objc_method_override o ON o.method = m.id "
            "WHERE (o.overridden_class = ? OR (o.overridden_container = ? AND o.overridden_container_kind IN "
            "('interface', 'implementation'))) AND m.class_name != ? AND m.is_definition = 1 ORDER BY m.class_name",
            (cls, cls, cls)):
        rows_.append(row(f, None, None, 'subclass %s, direct or indirect (overrides at least one method)' % c,
                         group='subclasses in the repository'))
    if census.swift_tables:
        for c, f in census.con.execute(
                'SELECT DISTINCT class_name, file FROM swift_objc_decl WHERE is_override = 1 AND class_name != ? AND '
                'overrides_usr LIKE ? ORDER BY class_name', (cls, '%(cs)' + cls + '(%')):
            rows_.append(row(f, None, None, 'Swift subclass %s (overrides at least one method)' % c,
                             group='subclasses in the repository'))
    facts['notes'].append('Subclasses are found only when they override a method of the class; a subclass that '
                          'overrides nothing is not listed.')
    for h in res.text_search([cls]).get(cls, []):
        rows_.append(row(h.file, h.line, None, 'text: the token %s' % cls, test=h.file.startswith(TEST_DIRS),
                         group='other resources (text search, unverified)'))
    table, table_complete, table_incomplete = method_table(census, cls)
    status_rows = len(rows_) + sum(1 for m in table if not m['no_caller'])
    not_covered = new_section(10, '')
    fill_not_covered(census, not_covered, cls, status_rows)
    if any(r.kind == RUNTIME_KIND_LIVE for r in census.runtimes):
        not_covered['notes'].append('not covered: ' + RUNTIME_NOT_COVERED_LIVE)
        not_covered['notes'].append('not covered: ' + APP_FRAMEWORKS_NOT_COVERED)
    if any(r.kind == RUNTIME_KIND_DUMP for r in census.runtimes):
        not_covered['notes'].append('not covered: ' + RUNTIME_NOT_COVERED_DUMP)
    for line in table_incomplete:
        if line not in facts['incomplete']:
            facts['incomplete'].append(line)
            facts['complete'] = False
    if exclude_generated is None:
        exclude_generated = unreached
    generated = [m for m in table if m['generated']] if exclude_generated else []
    kept = [m for m in table if not (exclude_generated and m['generated'])]
    by_reach = dict((k, [m for m in kept if m['reach'] == k]) for k in REACH_KEYS)
    if unreached:
        table = [m for m in kept if m['no_caller']]
        if by_reach['swift_defined']:
            facts['complete'] = False
            facts['incomplete'].append('INCOMPLETE: %d methods are defined in Swift with a Swift USR, and Swift '
                                       'callers of them are not in the database (listed under "%s").' % (
                                           len(by_reach['swift_defined']), SWIFT_DEFINED_HEADING))
    sections = collections.OrderedDict([('facts', facts), ('not covered', not_covered)])
    if not table_complete and facts['complete']:
        facts['complete'] = False
        facts['incomplete'].append('INCOMPLETE: the method table\'s sources are incomplete (see above)')
    status = finish(census, sections, len(table) if unreached else status_rows)
    extra = collections.OrderedDict([('methods', table), ('unreached', unreached)])
    if unreached:
        extra['label'] = 'no caller found (not "dead": see Not covered)'
        for k in REACH_KEYS:
            extra[k] = by_reach[k]
        extra['counts'] = collections.OrderedDict([('no_caller', len(table))] + [(k, len(by_reach[k]))
                                                                                  for k in REACH_KEYS])
        extra['generated_excluded'] = len(generated)
        extra['sdk_source'] = census.sdk_kind
    return dossier('class', cls, sections, status, extra)


def new_section_like(title):
    return collections.OrderedDict([('number', 0), ('title', title), ('source', 'all sources of the method census'),
                                    ('complete', True), ('incomplete', []), ('notes', []), ('rows', [])])


_OBJC_CLASS_DECL = re.compile(r'@objc\(([A-Za-z_]\w*)\)[^{]*?\bclass\s+([A-Za-z_]\w*)', re.S)


def swift_objc_names(root, f, cls):
    """[(line, text)]: @objc(Name) class declarations in a Swift file naming
    cls (text search)."""
    try:
        with open(os.path.join(root, f), 'r', encoding='utf-8', errors='replace') as fh:
            text = fh.read()
    except OSError:
        return []
    out = []
    for m in _OBJC_CLASS_DECL.finditer(text):
        if cls in (m.group(1), m.group(2)) and text[m.start():m.end()].count('\n') < 4:
            out.append((text.count('\n', 0, m.start()) + 1, 'Swift class %s with runtime name %s (@objc(%s))' % (
                m.group(2), m.group(1), m.group(1))))
    return out


def chunks(items, n=500):
    items = list(items)
    for i in range(0, len(items), n):
        yield items[i:i + n]


PRIVATE_FLAG = 'overrides a private framework method'
CATEGORY_FLAG = 'category on a framework class: same selector as a framework method of that class tree'


def runtime_verdict(runtimes, cls, framework_class, is_cls, sel):
    """(reach, reason or None, flag or None, later reasons) of a candidate
    of cls, whose first framework class is framework_class, by the rule
    under Framework methods at run time above."""
    category = framework_class == cls
    hits = [(rt.label(), rt.implementer(framework_class, is_cls, sel)) for rt in runtimes
            if rt.has_class(framework_class)]
    hits = [(v, i) for v, i in hits if i]
    if hits:
        releases = [v for v, _ in hits]
        if category:
            return 'system', category_reason(framework_class, hits[0][1], releases), CATEGORY_FLAG, []
        return 'system', private_override_reason(framework_class, hits[0][1], releases), PRIVATE_FLAG, []
    if category:
        below = [(rt.label(), rt.subclass_implementers(cls, is_cls, sel)) for rt in runtimes]
        below = [(v, subs) for v, subs in below if subs]
        if below:
            subs = sorted(set(c for _, cs in below for c in cs))
            return ('system', category_subclass_reason(cls, subs, [v for v, _ in below]), CATEGORY_FLAG, [])
    anywhere = [(rt.label(), rt.implementers(sel)) for rt in runtimes]
    anywhere = [(v, i) for v, i in anywhere if i]
    if anywhere:
        impls = sorted(set(x for _, i in anywhere for x in i))
        return 'weak', None, None, [weak_reason(impls, [v for v, _ in anywhere])]
    return 'none', None, None, []


def method_table(census, cls):
    """One summary per method of cls: counts per section and flags. Every
    count is an aggregate query; nothing is loaded whole."""
    methods = census.class_methods(cls)
    selectors = sorted(set(sel for _, sel in methods))
    con = census.con
    tests = sorted(census.test_targets)
    tmark = ','.join('?' * len(tests)) or "''"
    counts = collections.defaultdict(collections.Counter)

    def bump(sel, key, n=1):
        counts[sel][key] += n

    for part in chunks(selectors):
        marks = ','.join('?' * len(part))
        # A location is a test caller only when every unit that records it
        # is in a test target (a header send read by app and test units is
        # an app caller).
        for sel, is_test, n in con.execute(
                'SELECT selector, all_test, count(*) FROM (SELECT s.selector AS selector, min(t.target IN (%s)) AS '
                'all_test FROM send s JOIN tu t ON t.id = s.tu WHERE s.selector IN (%s) GROUP BY s.selector, s.file, '
                's.line, s.col) GROUP BY 1, 2' % (tmark, marks), tests + part):
            bump(sel, 'tests' if is_test else 'objc', n)
        for sel, n in con.execute('SELECT selector, count(DISTINCT file || \':\' || line || \':\' || col) FROM '
                                  'selector_ref WHERE selector IN (%s) GROUP BY 1' % marks, part):
            bump(sel, 'selref', n)
        for sel, n in con.execute('SELECT resolved_selector, count(DISTINCT file || \':\' || line) FROM '
                                  'reflective_call WHERE resolved_selector IN (%s) AND argument_kind != '
                                  "'selector-expr' GROUP BY 1" % marks, part):
            bump(sel, 'byname', n)
        if census.swift_tables:
            for sel, kind, unit, n in con.execute(
                    'SELECT selector, kind, unit, count(*) FROM swift_ref WHERE selector IN (%s) GROUP BY 1, 2, 3'
                    % marks, part):
                if census.swift_is_test(unit):
                    bump(sel, 'tests', n)
                elif kind == 'selector-expr':
                    bump(sel, 'swift_selector', n)
                else:
                    bump(sel, 'swift', n)
    # Swift property references, matched by the property's name in every
    # container (a reference through a protocol type names the protocol's
    # property), as Objective-C sends are matched by selector: a read reaches
    # a getter, a write a setter, a read-modify-write, an unknown access or
    # a key path both. And key-value coding by key.
    names = dict((sel, census.property_names(cls, sel)) for sel in selectors)
    by_name = collections.defaultdict(list)  # property name: [(selector, role)]
    for sel, pairs in names.items():
        for name, role in pairs:
            by_name[name].append((sel, role))
    if census.swift_tables and by_name:
        for part in chunks(sorted(by_name)):
            marks = ','.join('?' * len(part))
            for prop, access, kind, unit, n in con.execute(
                    'SELECT property, access, kind, unit, count(*) FROM swift_ref WHERE property IN (%s) GROUP BY 1, '
                    '2, 3, 4' % marks, part):
                for sel, role in set(by_name[prop]):
                    if property_access_reaches(kind, access, role):
                        bump(sel, 'tests' if census.swift_is_test(unit) else 'swift', n)
    props = con.execute('SELECT DISTINCT name, getter_selector, setter_selector FROM objc_property WHERE '
                        'class_name = ?', (cls,)).fetchall()
    for name, getter, setter in props:
        n = con.execute("SELECT count(DISTINCT file || ':' || line) FROM reflective_call WHERE argument_text = ? AND "
                        "kind IN ('key', 'key-path')", (name,)).fetchone()[0]
        if n:
            for sel in (getter, setter):
                if sel in counts or sel in selectors:
                    bump(sel, 'kvc', n)
    outside = collections.defaultdict(set)  # (is_class_method, selector): overridden containers
    for sel, is_cls, container in con.execute(
            'SELECT DISTINCT m.selector, m.is_class_method, o.overridden_container FROM objc_method m JOIN '
            'objc_method_override o ON o.method = m.id WHERE m.class_name = ? AND (m.is_definition = 1 OR '
            'm.is_synthesized_accessor = 1) AND (o.outside_repository = 1 OR o.owner_parsed = 0)', (cls,)):
        outside[(bool(is_cls), sel)].add(container)
    swift_outside = census.swift_outside_overrides(cls)
    sdk = census.sdk_declarations(selectors)
    in_protocol = set(sel for (sel,) in con.execute(
        "SELECT DISTINCT m.selector FROM objc_method m JOIN objc_method_override o ON o.method = m.id WHERE "
        "m.class_name = ? AND o.overridden_container_kind = 'protocol' AND o.outside_repository = 0", (cls,)))
    res = census.resources
    known = census.outside_protocols()
    delegations = census.delegations(cls)
    ib = collections.Counter()
    for a in res.actions:
        if (a.target.cls == cls or a.target.kind == 'first-responder') and a.file not in res.other_project:
            ib[a.selector] += 1
    for o in res.outlets:
        if o.owner.cls == cls and o.file not in res.other_project:
            ib[o.property] += 1
            ib['set%s:' % capitalized(o.property)] += 1
    for k in res.keyed:
        if k.target.cls == cls and k.file not in res.other_project:
            key = ib_key_parts(k.key_path)[0]
            ib[key] += 1
            ib['set%s:' % capitalized(key)] += 1
    sdef = collections.Counter()
    for item in res.sdef:
        if cls not in census.sdef_receivers(item.cocoa_class):
            continue
        if item.kind in ('property', 'element'):
            for s in sdef_accessors(item):
                sdef[s] += 1
        elif item.kind == 'responds-to':
            sdef[item.key] += 1
    for p in res.plist:
        if p.kind == 'services message':
            sdef[p.value] += 1
    text = res.text_search(selectors)
    missing = missing_sources(census)
    registry = collections.Counter()
    if census.registry:
        for nr in census.registry.names:
            for sel in selectors:
                if name_matches_method(nr.name, cls, sel):
                    registry[sel] += 1
    table = []
    # The files that declare cls (with the header of each implementation
    # file), where its @interface line is looked for first.
    class_files = set()
    for info in methods.values():
        for f in [x[0] for x in info['objc']] + [x[0] for x in info['swift']]:
            class_files.add(f)
            if f.endswith(('.m', '.mm')):
                class_files.add(os.path.splitext(f)[0] + '.h')
    ancestor = None
    chain_undecided = no_runtime = 0
    prefetched = False
    for (is_cls, sel), info in methods.items():
        c = counts[sel]
        t = text.get(sel, [])
        entry = collections.OrderedDict([
            ('method', '%s%s' % ('+' if is_cls else '-', sel)),
            ('objc', c['objc']), ('swift', c['swift']), ('selector_refs', c['selref'] + c['swift_selector']),
            ('by_name', c['byname']), ('kvc', c['kvc']), ('registry', registry[sel]), ('ib', ib[sel]),
            ('scripting', sdef[sel]), ('text', sum(1 for h in t if not h.file.startswith(TEST_DIRS))),
            ('tests', c['tests'] + sum(1 for h in t if h.file.startswith(TEST_DIRS))),
        ])
        flags = []
        # Why the system may call it: facts the compiler recorded first,
        # then the heuristics (which only ever add a reason), then the SDK.
        reasons = []
        key = (bool(is_cls), sel)
        if key in outside:
            reasons.append('overrides or implements a member declared outside the repository (%s)' % ', '.join(
                sorted(outside[key])))
        if key in swift_outside:
            reasons.append('overrides a member declared outside the repository (%s)' % swift_outside[key])
        if sel in CALLED_BY_NAME:
            reasons.append('sent by the runtime or AppKit by name to any class that has it')
        if sel in known and info['defined']:
            proto, c0, f0, line0 = known[sel]
            reasons.append('requirement of %s, a protocol declared outside the repository that other classes here '
                           'adopt (first: %s at %s:%d)' % (proto, c0, f0, line0))
        if info['defined']:
            for stem, rc, f, line, col, how in delegations:
                if stem_matches(sel, stem):
                    reasons.append('possible AppKit delegate method: %s (%s:%d)' % (how, f, line))
                    break
        if key in outside or key in swift_outside or sel in CALLED_BY_NAME:
            flags.append('outside-repository override')
        elif sel in known and info['defined']:
            flags.append('requirement of an outside-repository protocol (not declared by this class)')
        elif any(r.startswith('possible AppKit delegate method') for r in reasons):
            flags.append('possible AppKit delegate method')
        decls = sdk.get(key)
        unrelated_only = False
        if decls:
            objc_defined = any(kind in ('implementation', 'category-implementation') for _, _, kind, _ in info['objc'])
            label, unrelated = sdk_label(key in outside or key in swift_outside, objc_defined, bool(info['swift']),
                                         decls)
            unrelated_only = unrelated and not reasons
            reasons.append('selector declared by the SDK: %s; %s' % (describe_sdk(decls), label))
            flags.append('selector declared by the SDK')
        if not info['defined']:
            flags.append('declared only (no definition recorded)')
        if sel in in_protocol:
            flags.append('protocol requirement')
        if ib[sel]:
            flags.append('IB')
        if sdef[sel]:
            flags.append('scripting')
        if registry[sel]:
            flags.append('registry')
        if entry['selector_refs'] and not (c['objc'] or c['swift']):
            flags.append('selector referenced without a call')
        if info['property']:
            flags.append('property accessor')
        called = (c['objc'] or c['swift'] or entry['selector_refs'] or c['byname'] or c['kvc'] or registry[sel] or
                  ib[sel] or sdef[sel] or entry['text'] or sel in in_protocol)
        # Sources that cannot show a caller here: what the database leaves
        # out, and what a search of the code that is not compiled finds.
        swift_usrs = sorted(set(s[5] for s in info['swift'] if s[5] and s[5].startswith('s:')))
        protocol_reasons = (census.swift_protocol_reasons(cls, sel, bool(info['swift'])) if census.swift_protocol
                            else [])
        undecided_reasons = list(missing)
        if census.sdk_kind is None:
            undecided_reasons.append('not decided: no SDK declarations')
        later = []  # the reasons of the heading the method goes under
        if called:
            reach = 'called'
        elif reasons:
            reach = 'system'
        elif protocol_reasons:
            reach, later = 'swift_protocol', protocol_reasons
        else:
            defined_at = set((f, line) for f, line, _, _ in info['objc']) | set((s[0], s[1]) for s in info['swift'])
            hits = census.uncompiled_hits(sel, defined_at)
            if hits:
                reach = 'inactive'
                later = ['%s at %s:%d, in %s' % (tok, f, n, where) for tok, f, n, where in hits[:3]]
                if len(hits) > 3:
                    later.append('and %d more lines in code that is not compiled' % (len(hits) - 3))
            elif swift_usrs:
                reach, later = 'swift_defined', [SWIFT_USR_REASON % ', '.join(swift_usrs)]
            elif undecided_reasons:
                reach, later = 'undecided', undecided_reasons
            elif entry['tests']:
                reach = 'tests'
            else:
                reach = 'none'
        if reach == 'none':
            # A candidate: a declaration nothing here defines, a method the
            # runtime method lists show the frameworks may call, or one that
            # shares a selector with any framework method, is not "no caller
            # found" (Framework methods at run time, above).
            prebuilt = census.prebuilt_selectors().get(sel)
            if prebuilt:
                reach = 'system'
                reasons.append('selector declared by a prebuilt framework in the repository: %s' % ', '.join(
                    '%s in %s (%s)' % (c or '?', fw, src) for c, fw, src in prebuilt))
                flags.append(PREBUILT_FLAG)
            elif not info['defined'] and not census.repo_defined(cls):
                reach, later = 'elsewhere', [ELSEWHERE_REASON % cls]
            else:
                if ancestor is None:
                    ancestor = census.framework_ancestor(cls, class_files)
                framework_class, why = ancestor
                if framework_class is None:
                    reach, later = 'undecided', [CHAIN_REASON % why]
                    chain_undecided += 1
                elif not census.runtimes:
                    # decisions.md 2026-11-20: whatever its name and its
                    # superclass, a candidate is never "no caller found"
                    # without a runtime method list.
                    reach, later = 'undecided', [NO_RUNTIME_REASON]
                    no_runtime += 1
                else:
                    if not prefetched:
                        # One pass over each list for every selector of the
                        # class, so later lookups are in memory.
                        for rt in census.runtimes:
                            rt.prefetch(selectors)
                        prefetched = True
                    reach, why_system, flag, later = runtime_verdict(census.runtimes, cls, framework_class,
                                                                     bool(is_cls), sel)
                    if why_system:
                        reasons.append(why_system)
                        flags.append(flag)
        entry['reach'] = reach
        entry['no_caller'] = reach == 'none'
        if reach == 'undecided' and census.sdk_kind is None:
            flags.append('not decided: no SDK declarations')
        entry['generated'] = bool(info['objc'] or info['swift']) and all(
            census.is_generated(f) for f in [x[0] for x in info['objc']] + [x[0] for x in info['swift']])
        if reach == 'system':
            entry['system_group'] = SDK_UNRELATED_GROUP if unrelated_only else (
                PREBUILT_GROUP if PREBUILT_FLAG in flags else PRIVATE_GROUP if PRIVATE_FLAG in flags else
                CATEGORY_GROUP if CATEGORY_FLAG in flags else SDK_OTHER_GROUP)
        if entry['tests'] and reach in ('none', 'undecided', 'tests', 'swift_defined', 'inactive', 'swift_protocol',
                                        'weak'):
            flags.append('called only from tests')
        elif reach == 'none':
            flags.append('no caller found')
        elif reach == 'weak':
            flags.append('weak: a framework class implements a method with this selector')
        entry['flags'] = flags
        entry['reasons'] = reasons + later
        table.append(entry)
    extra = []
    if chain_undecided:
        extra.append(CHAIN_INCOMPLETE % (cls, ancestor[1]))
    if no_runtime:
        extra.append(NO_RUNTIME_INCOMPLETE % no_runtime)
    complete = not (census.objc_incomplete() or census.swift_incomplete() or census.registry_incomplete() or
                    census.sdk_incomplete() or census.scripting_incomplete() or census.runtime_incomplete() or
                    missing or extra)
    return table, complete, extra


def property_access_reaches(kind, access, role):
    """Whether a Swift property reference (kind, access) calls the accessor of
    role: a key path component or a dynamic lookup reaches both, a read the
    getter, a write the setter, a read-modify-write or an unknown access
    both."""
    if kind != 'property':
        return True
    return (role == 'getter' and access != 'set') or (role == 'setter' and access != 'get')


def missing_sources(census):
    """Reasons no method of any class can be decided: a source the database
    does not have."""
    out = []
    if not census.swift_tables:
        out.append(NO_SWIFT_REASON)
    elif not census.swift_protocol:
        out.append(NO_SWIFT_PROTOCOL_REASON)
    return out + census.uncompiled_missing()


def file_dossier(census, path):
    """The classes path implements (or declares, for a header), each as
    class_dossier."""
    rel = os.path.relpath(os.path.join(census.root, path), census.root) if os.path.isabs(path) else path
    kinds = ("'interface', 'category', 'extension'" if rel.endswith('.h') else
             "'implementation', 'category-implementation'")
    classes = [c for (c,) in census.con.execute(
        'SELECT DISTINCT class_name FROM objc_method WHERE file = ? AND container_kind IN (%s) AND class_name IS NOT '
        'NULL ORDER BY class_name' % kinds, (rel,))]
    if census.swift_tables and rel.endswith('.swift'):
        classes += [c for (c,) in census.con.execute(
            'SELECT DISTINCT class_name FROM swift_objc_decl WHERE file = ? AND class_name IS NOT NULL ORDER BY '
            'class_name', (rel,)) if c not in classes]
    if not classes:
        raise CensusError('no class is recorded as implemented in %s (is the path relative to the repository, and '
                          'is the file parsed?)' % rel)
    return [class_dossier(census, c) for c in classes]


# --- Output -----------------------------------------------------------------------

def loc(r):
    if r['file'] is None:
        return '(no location)'
    out = r['file']
    if r['line']:
        out += ':%d' % r['line']
        if r['col']:
            out += ':%d' % r['col']
    return out


def write_rows(out, rows_, indent='  '):
    group = None
    for r in rows_:
        if r.get('group') != group:
            group = r.get('group')
            if group:
                out.write('%s%s: %d\n' % (indent, group, sum(1 for x in rows_ if x.get('group') == group)))
        out.write('%s  %s  %s%s\n' % (indent, loc(r), r['what'], ''.join('  ' + m for m in r['marks'])))


def write_text(d, out):
    for line in d['incomplete']:
        out.write(line + '\n')
    if d['kind'] == 'method':
        out.write('Entry points of %s\n' % d['subject'])
    else:
        out.write('Entry points of class %s%s\n' % (d['subject'], ': methods with no caller found' if d.get('unreached')
                                                     else ''))
    for s in d['sections']:
        heading = ('%d. %s' % (s['number'], s['title'])) if s['number'] else s['title']
        out.write('\n%s: %d%s (%s; %s)\n' % (heading, s['count'], ' and %d informational' % s['informational']
                                             if s['informational'] else '', s['source'],
                                             'complete' if s['complete'] else 'INCOMPLETE'))
        for line in s['incomplete']:
            out.write('  %s\n' % line)
        for n in s['notes']:
            out.write('  note: %s\n' % n)
        write_rows(out, s['rows'])
    if d['kind'] == 'class':
        methods = d['methods']
        out.write('\n%s: %d\n' % ('Methods with no caller found (not "dead": see Not covered)' if d['unreached']
                                  else 'Methods', len(methods)))
        out.write('  columns: Objective-C sends, Swift references, selector references, by name, key-value coding, '
                  'registry, Interface Builder, scripting and plists, text, tests\n')
        for m in methods:
            write_method(out, m)
        if d['unreached']:
            out.write('\n%s: %d\n' % (SDK_HEADING, len(d['system'])))
            runtime_groups = tuple(g for g in (PREBUILT_GROUP, PRIVATE_GROUP, CATEGORY_GROUP) if any(
                m.get('system_group') == g for m in d['system']))
            for group in (SDK_OTHER_GROUP, SDK_UNRELATED_GROUP) + runtime_groups:
                members = [m for m in d['system'] if m.get('system_group') == group]
                out.write('  %s: %d\n' % (group, len(members)))
                for m in members:
                    write_method(out, m, '  ')
                    for r in m['reasons']:
                        out.write('        because: %s\n' % r)
            for key, heading in (('weak', WEAK_HEADING), ('swift_protocol', SWIFT_PROTOCOL_HEADING),
                                 ('inactive', INACTIVE_HEADING),
                                 ('swift_defined', SWIFT_DEFINED_HEADING),
                                 ('undecided', NO_SDK_HEADING if d['sdk_source'] is None else UNDECIDED_HEADING),
                                 ('tests', TESTS_HEADING), ('elsewhere', ELSEWHERE_HEADING)):
                out.write('\n%s: %d\n' % (heading, len(d[key])))
                for m in d[key]:
                    write_method(out, m)
                    for r in m['reasons']:
                        out.write('      because: %s\n' % r)
            out.write('\nmethods in generated files left out (--no-exclude-generated lists them): %d\n' %
                      d['generated_excluded'])
    out.write('\nexit status %d: 0 found and complete, 1 nothing found and complete (0 and 1 only when every source is '
              'complete and current), 3 INCOMPLETE, 2 error\n' % d['exit_status'])
    for line in d['incomplete']:
        out.write(line + '\n')
    if d['kind'] == 'class' and d['unreached']:
        out.write(unreached_status_words(d) + '\n')


def write_method(out, m, indent=''):
    out.write(indent + '  %s  objc %d  swift %d  selref %d  byname %d  kvc %d  registry %d  ib %d  scripting %d  text '
              '%d  tests %d%s\n' % (m['method'], m['objc'], m['swift'], m['selector_refs'], m['by_name'],
                                    m['kvc'], m['registry'], m['ib'], m['scripting'], m['text'], m['tests'],
                                    '  [' + ', '.join(m['flags']) + ']' if m['flags'] else ''))


def unreached_status_words(d):
    """What the exit status of a class --unreached run means for that run,
    with the number of methods under each heading."""
    status = d['exit_status']
    c = d['counts']
    counts = ('%d with no caller found, %d as possibly called by the system, %d as weak (no caller found, but a '
              'framework class implements a method with the selector), %d as possibly called through a Swift '
              'protocol requirement, %d as referenced in code not compiled in this configuration, %d as defined in '
              'Swift (Swift callers of them are not in the database), %d as candidates not decided, %d as called '
              'only from tests, and %d as declared here and defined elsewhere (%d methods in generated files left '
              'out)' % (c['no_caller'], c['system'], c['weak'], c['swift_protocol'], c['inactive'], c['swift_defined'],
                        c['undecided'], c['tests'], c['elsewhere'], d['generated_excluded']))
    if status == 0:
        return ('This run: exit status 0: methods with no caller found are listed above, and every source was '
                'consulted and is complete. Methods listed: %s.' % counts)
    if status == 1:
        return ('This run: exit status 1: no method of %s is without a caller (the other headings are listed '
                'separately), and every source was consulted and is complete. Methods listed: %s.' % (
                    d['subject'], counts))
    return ('This run: exit status 3: the answer is INCOMPLETE (the reasons are above): methods listed: %s; none of '
            'them is shown to be unreached.' % counts)


def build_parser():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--root', default=os.path.abspath(os.path.join(HERE, '..', '..')))
    for opt in ('--db', '--cdb', '--fragments', '--extractor', '--swift-work', '--swift-reader', '--registry'):
        p.add_argument(opt)
    p.add_argument('--sdk-selectors', metavar='FILE', help='an interim file of SDK declarations, written by '
                   'sdk_selectors.py from a text scan of SDK headers; read only when the database has no sdk_method '
                   'table')
    p.add_argument('--runtime-methods', metavar='FILE', action='append', help='a list of the methods the frameworks '
                   'implement at run time, private ones included, written by sdk_selectors.py --runtime-methods on '
                   'one OS release (or converted from dumped headers by sdk_selectors.py '
                   '--runtime-methods-from-headers); give it once per release; a selector found in any list counts. '
                   'Without it no candidate is "no caller found": every one is not decided and the run is INCOMPLETE')
    p.add_argument('--json', action='store_true')
    sub = p.add_subparsers(dest='command', required=True)
    m = sub.add_parser('method', help='every way one method is entered')
    m.add_argument('cls', metavar='CLASS')
    m.add_argument('selector', metavar='SELECTOR')
    c = sub.add_parser('class', help='class-level facts and a table of its methods')
    c.add_argument('cls', metavar='CLASS')
    c.add_argument('--unreached', action='store_true', help='only methods with no caller found')
    c.add_argument('--exclude-generated', dest='exclude_generated', action='store_true', default=None,
                   help='leave out methods defined only in generated files (sources/proto/, '
                   'sources/CoreDataGeneratedFiles/, or a first line saying the protocol buffer compiler wrote it); the default with --unreached')
    c.add_argument('--no-exclude-generated', dest='exclude_generated', action='store_false')
    f = sub.add_parser('file', help='the classes a file implements')
    f.add_argument('path', metavar='PATH')
    return p


_SIGNED_SELECTOR = re.compile(r'^[-+][A-Za-z_][\w:]*$')


def protect_selector(argv):
    """argv with -- inserted before a method command's SELECTOR that begins
    with - (which argparse would take for an option)."""
    out = list(argv)
    if 'method' not in out:
        return out
    j = out.index('method') + 1
    positional = 0
    while j < len(out):
        a = out[j]
        if a == '--':
            break
        if positional == 1 and _SIGNED_SELECTOR.match(a) and a != '-h':
            out.insert(j, '--')
            break
        if not a.startswith('-'):
            positional += 1
        j += 1
    return out


def main(argv=None, out=None):
    out = out or sys.stdout
    args = build_parser().parse_args(protect_selector(sys.argv[1:] if argv is None else argv))
    try:
        paths = codedb.Paths(args.root, db=args.db, cdb=args.cdb, fragments=args.fragments, extractor=args.extractor,
                             swift_reader=args.swift_reader, swift_work=args.swift_work)
        census = Census(paths, registry_path=args.registry, sdk_selectors=args.sdk_selectors,
                        runtime_methods=args.runtime_methods)
        try:
            if args.command == 'method':
                docs = [method_dossier(census, args.cls, args.selector)]
            elif args.command == 'class':
                docs = [class_dossier(census, args.cls, unreached=args.unreached,
                                      exclude_generated=args.exclude_generated)]
            else:
                docs = file_dossier(census, args.path)
        finally:
            census.close()
    except (CensusError, codedb.CodeDBError, sqlite3.Error, OSError) as e:
        print('entry_points: error: %s' % e, file=sys.stderr)
        return 2
    status = max(d['exit_status'] for d in docs) if any(d['exit_status'] == 3 for d in docs) else min(
        d['exit_status'] for d in docs)
    if args.json:
        json.dump(docs[0] if len(docs) == 1 else docs, out, indent=1)
        out.write('\n')
    else:
        for d in docs:
            write_text(d, out)
    return status


if __name__ == '__main__':
    sys.exit(main())
