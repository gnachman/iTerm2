"""Shared helpers for the tests of inventory.py and its subcommand modules.

The fixture tree in fixtures/minirepo is copied to a temporary directory and
made into a git repository, so that results never depend on the real
sources/. This file is not a test module; the test files import it.
"""

import io
import os
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(os.path.dirname(TOOL_DIR))
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
# The tool writes nothing to disk; importing it for the tests should not either.
sys.dont_write_bytecode = True

import inventory as inv  # noqa: E402

FIXTURE = os.path.join(HERE, 'fixtures', 'minirepo')


def git(cwd, *args):
    env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.com',
               GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@example.com',
               GIT_AUTHOR_DATE='2026-01-02T03:04:05Z', GIT_COMMITTER_DATE='2026-01-02T03:04:05Z')
    subprocess.run(['git'] + list(args), cwd=cwd, check=True, env=env,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)


TEMP_DIRS = []


def make_repo(mutate=None, commit=True):
    """Copies the fixture into a new temporary git repository, optionally changed by mutate(root)."""
    d = tempfile.mkdtemp(prefix='inventory-test-')
    TEMP_DIRS.append(d)
    root = os.path.join(d, 'repo')
    shutil.copytree(FIXTURE, root)
    if mutate:
        mutate(root)
    git(root, 'init', '-q')
    if commit:
        git(root, 'add', '-A')
        git(root, 'commit', '-q', '-m', 'Initial')
    return root


def run_cli(cwd, *args):
    proc = subprocess.run([sys.executable, os.path.join(TOOL_DIR, 'inventory.py')] + list(args), cwd=cwd,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return proc.returncode, proc.stdout.decode('utf-8'), proc.stderr.decode('utf-8')


class MiniRepo(object):
    """The fixture tree as a git repository in a temporary directory."""

    _root = None
    _inventories = {}

    @classmethod
    def path(cls):
        if cls._root is None:
            root = make_repo(commit=False)
            git(root, 'add', '-A')
            # A gitlink under sources/ stands in for a submodule.
            git(root, 'update-index', '--add', '--cacheinfo',
                '160000,1111111111111111111111111111111111111111,sources/vendored')
            git(root, 'commit', '-q', '-m', 'First\n\nSwift-Port: Foo kind=test')
            git(root, 'commit', '-q', '--allow-empty', '-m',
                'Second\n\nSwift-Port: Foo kind=port\nSwift-Port: Bar kind=bogus\nSwift-Port: nokind')
            git(root, 'commit', '-q', '--allow-empty', '-m',
                'Third\n\n  Swift-Port: Indented kind=test\nswift-port: Lower kind=test\n'
                'Swift-Port : Spaced kind=test')
            cls._root = root
        return cls._root

    @classmethod
    def inventory(cls, inventory_class=None):
        """An inventory of the fixture, of class inventory.Inventory unless another is given."""
        inventory_class = inventory_class or inv.Inventory
        if inventory_class not in cls._inventories:
            cls._inventories[inventory_class] = inventory_class(cls.path())
        return cls._inventories[inventory_class]

    @classmethod
    def cleanup(cls):
        for d in TEMP_DIRS:
            shutil.rmtree(d, ignore_errors=True)
        del TEMP_DIRS[:]
        cls._root = None
        cls._inventories = {}


SCOPE_OVERLAY = os.path.join(HERE, 'fixtures', 'scope_overlay')

# Lines added to the fixture's iTerm2.xcodeproj by add_scope_overlay: (text to find, text to put before it).
_SCOPE_OVERLAY_PROJECT_EDITS = (
    ('/* End PBXBuildFile section */',
     'B00000000000000000000SC1 /* PidLeaf.m in Sources */ = {isa = PBXBuildFile; fileRef = F00000000000000000000SC1; };\n'
     '\t\tB00000000000000000000SC2 /* PidHelper.m in Sources */ = {isa = PBXBuildFile; fileRef = F00000000000000000000SC2; };\n'
     '\t\tB00000000000000000000SC3 /* SharedWithTests.m in Sources */ = {isa = PBXBuildFile; fileRef = F00000000000000000000SC3; };\n'
     '\t\tB00000000000000000000SC4 /* SharedWithTests.m in Sources */ = {isa = PBXBuildFile; fileRef = F00000000000000000000SC3; };\n'),
    ('/* End PBXFileReference section */',
     'F00000000000000000000SC1 /* PidLeaf.m */ = {isa = PBXFileReference; path = pidinfo/PidLeaf.m; sourceTree = SOURCE_ROOT; };\n'
     '\t\tF00000000000000000000SC2 /* PidHelper.m */ = {isa = PBXFileReference; path = pidinfo/PidHelper.m; sourceTree = SOURCE_ROOT; };\n'
     '\t\tF00000000000000000000SC3 /* SharedWithTests.m */ = {isa = PBXFileReference; path = sources/SharedWithTests.m; sourceTree = SOURCE_ROOT; };\n'),
    # iTerm2SharedARC compiles PidLeaf.m; the pidinfo target (a tool of the main project) compiles PidHelper.m.
    # iTerm2SharedARC and the OverlayTests test bundle both compile sources/SharedWithTests.m.
    ('B0000000000000000000F002 /* Bar.m in Sources */,', 'B00000000000000000000SC1 /* PidLeaf.m in Sources */,\n\t\t\t\t'
                                                        'B00000000000000000000SC3 /* SharedWithTests.m in Sources */,\n\t\t\t\t'),
    ('B000000000000000000000K1 /* ServerMain.c in Sources */,', 'B00000000000000000000SC2 /* PidHelper.m in Sources */,\n\t\t\t\t'),
    ('/* End PBXNativeTarget section */',
     'T000000000000000000000SC /* OverlayTests */ = {\n\t\t\tisa = PBXNativeTarget;\n'
     '\t\t\tbuildConfigurationList = L00000000000000000000004;\n'
     '\t\t\tbuildPhases = (\n\t\t\t\tS000000000000000000000SC /* Sources */,\n\t\t\t);\n'
     '\t\t\tname = OverlayTests;\n\t\t\tproductType = "com.apple.product-type.bundle.unit-test";\n\t\t};\n'),
    ('T00000000000000000000003 /* pidinfo */,\n', 'T000000000000000000000SC /* OverlayTests */,\n\t\t\t\t'),
    ('/* End PBXSourcesBuildPhase section */',
     'S000000000000000000000SC /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n'
     '\t\t\tfiles = (\n\t\t\t\tB00000000000000000000SC4 /* SharedWithTests.m in Sources */,\n\t\t\t);\n\t\t};\n'),
)


def add_scope_overlay(root):
    """Copies fixtures/scope_overlay over a copy of the fixture tree, and adds its pidinfo and sources files to the
    fixture's iTerm2.xcodeproj: pidinfo/PidLeaf.m to iTerm2SharedARC, pidinfo/PidHelper.m to the pidinfo target, and
    sources/SharedWithTests.m to iTerm2SharedARC and to a new test bundle target, OverlayTests."""
    shutil.copytree(SCOPE_OVERLAY, root, dirs_exist_ok=True, ignore=shutil.ignore_patterns('README'))
    path = os.path.join(root, 'iTerm2.xcodeproj', 'project.pbxproj')
    with open(path, encoding='utf-8') as f:
        text = f.read()
    for anchor, before in _SCOPE_OVERLAY_PROJECT_EDITS:
        if text.count(anchor) != 1:
            raise AssertionError('the fixture project does not contain %r exactly once' % anchor)
        text = text.replace(anchor, before + anchor)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


class ScopeOverlayRepo(object):
    """The fixture tree with fixtures/scope_overlay added, as a git repository in a temporary directory."""

    _inventory = None

    @classmethod
    def path(cls):
        return cls.inventory().root

    @classmethod
    def inventory(cls):
        if cls._inventory is None:
            cls._inventory = inv.Inventory(make_repo(mutate=add_scope_overlay))
        return cls._inventory

    @classmethod
    def cleanup(cls):
        cls._inventory = None


def run_main(args):
    out = io.StringIO()
    with redirect_stdout(out):
        inv.main(args)
    return out.getvalue()


IVAR_SOURCE = '''
@interface Thing : NSObject {
    int _inHeaderInterface;
}
@property (nonatomic) int plain;
@property (nonatomic) int custom;
@property (atomic) int atomicOne;
@property (nonatomic, readonly) int computed;
@end

@interface Thing () {
    NSString *_inExtension, *_second;
}
@end

static int sShared = 0;
static NSString *const kName = @"x";
static void Helper(int x);
NS_INLINE int Inline(void) { return sShared; }
static const struct { int a; } kTable[] = { {1}, {2} };

static void Helper(int x) {
    sShared = x;
}

@implementation Thing {
    char _buf[8];
    void (^_handler)(int);
    unsigned _bit : 1;
    int _plain;
    int _custom;
    int _atomicOne;
}

- (int)custom {
    return _custom + 1;
}

- (void)work:(Thing *)other {
    _plain = 3;
    _custom += 1;
    Helper(_plain);
    take(&_buf);
    other->_plain = 2;
    self->_bit = 1;
    [self custom];
    [self setPlain:_plain];
    NSLog(@"%@", _inExtension);
}

@end
'''
