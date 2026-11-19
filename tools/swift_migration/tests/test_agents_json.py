"""Tests for tools/swift_migration/agents_json.py and the agent definitions.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_agents_json.py'

agents_json.py turns agent definition files (Markdown with YAML-style
frontmatter, the format Claude Code reads from .claude/agents/) into the
JSON object that `claude --agents` accepts, with the Markdown body as
"prompt". The definitions are tracked at .claude/agents/ (the owner chose to
track that directory on 2026-11-20; the rest of .claude/ stays ignored), where
an interactive session finds them by itself. The nightly start script uses
this tool only to check them (they must parse and pin Opus) before starting
the session.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOL_DIR))
AGENTS = os.path.join(REPO, '.claude', 'agents')
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
sys.dont_write_bytecode = True

import agents_json as aj  # noqa: E402


def run_main(args):
    out = io.StringIO()
    err = io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = aj.main(args)
    return code, out.getvalue(), err.getvalue()


class ConvertTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='agents_json_test.')

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, name, text):
        path = os.path.join(self.tmp, name)
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(text)
        return path

    def test_basic(self):
        path = self.write('a.md', '---\nname: alpha\ndescription: Does a\n'
                          'model: opus\ntools: Read, Bash,Write\n---\n\n'
                          'Body line one.\n\nBody line two.\n')
        code, out, err = run_main([path])
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out), {'alpha': {
            'description': 'Does a',
            'model': 'opus',
            'tools': ['Read', 'Bash', 'Write'],
            'prompt': 'Body line one.\n\nBody line two.\n',
        }})

    def test_two_files_and_output_file(self):
        a = self.write('a.md', '---\nname: a\ndescription: A\n---\nA body\n')
        b = self.write('b.md', '---\nname: b\ndescription: B\n'
                       'disallowedTools: Agent\nmaxTurns: 40\n---\nB body\n')
        dest = os.path.join(self.tmp, 'out.json')
        code, out, err = run_main(['--output', dest, a, b])
        self.assertEqual(code, 0, err)
        with open(dest) as fh:
            data = json.load(fh)
        self.assertEqual(data['b']['disallowedTools'], ['Agent'])
        self.assertEqual(data['b']['maxTurns'], 40)
        self.assertEqual(data['a']['prompt'], 'A body\n')

    def test_quoted_value(self):
        path = self.write('a.md', '---\nname: "alpha"\n'
                          "description: 'Says: hi'\n---\nx\n")
        code, out, err = run_main([path])
        self.assertEqual(json.loads(out)['alpha']['description'], 'Says: hi')

    def test_missing_frontmatter(self):
        path = self.write('a.md', 'no frontmatter\n')
        code, out, err = run_main([path])
        self.assertEqual(code, 1)
        self.assertIn('frontmatter', err)

    def test_missing_description(self):
        path = self.write('a.md', '---\nname: a\n---\nbody\n')
        code, out, err = run_main([path])
        self.assertEqual(code, 1)
        self.assertIn('description', err)

    def test_unknown_field_is_refused(self):
        # A field --agents does not document is refused rather than passed
        # through, so a typo cannot silently drop a setting such as model.
        path = self.write('a.md', '---\nname: a\ndescription: A\nmodle: opus\n'
                          '---\nbody\n')
        code, out, err = run_main([path])
        self.assertEqual(code, 1)
        self.assertIn('modle', err)

    def test_multiline_value_is_refused(self):
        path = self.write('a.md', '---\nname: a\ndescription: >\n  folded\n'
                          '---\nbody\n')
        code, out, err = run_main([path])
        self.assertEqual(code, 1)

    def test_duplicate_name(self):
        a = self.write('a.md', '---\nname: x\ndescription: A\n---\nA\n')
        b = self.write('b.md', '---\nname: x\ndescription: B\n---\nB\n')
        code, out, err = run_main([a, b])
        self.assertEqual(code, 1)
        self.assertIn('x', err)

    def test_require_model(self):
        a = self.write('a.md', '---\nname: a\ndescription: A\nmodel: sonnet\n'
                       '---\nA\n')
        code, out, err = run_main(['--require-model', 'opus', a])
        self.assertEqual(code, 1)
        self.assertIn('opus', err)


class RealDefinitionsTest(unittest.TestCase):
    """The checked-in author and reviewer definitions."""

    def load(self):
        paths = [os.path.join(AGENTS, n) for n in
                 ('migration-author.md', 'migration-reviewer.md')]
        code, out, err = run_main(['--require-model', 'opus'] + paths)
        self.assertEqual(code, 0, err)
        return json.loads(out)

    def test_both_pinned_to_opus(self):
        data = self.load()
        self.assertEqual(sorted(data), ['migration-author',
                                        'migration-reviewer'])
        for agent in data.values():
            self.assertEqual(agent['model'], 'opus')

    def test_reviewer_cannot_edit_and_neither_can_delegate(self):
        data = self.load()
        self.assertNotIn('Edit', data['migration-reviewer']['tools'])
        self.assertIn('Write', data['migration-reviewer']['tools'])
        self.assertIn('Bash', data['migration-reviewer']['tools'])
        self.assertIn('Edit', data['migration-author']['tools'])
        for agent in data.values():
            self.assertNotIn('Agent', agent['tools'])

    def test_no_paths_converts_the_default_directory(self):
        code, out, err = run_main(['--require-model', 'opus'])
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out), self.load())

    def test_bodies_point_at_the_process_files(self):
        data = self.load()
        for agent in data.values():
            self.assertIn('docs/swift-migration/README.md', agent['prompt'])
            self.assertIn('CLAUDE.md', agent['prompt'])

    def test_definitions_live_in_the_tracked_claude_agents_directory(self):
        # The documented project location, tracked by git while the rest of
        # .claude/ (settings.local.json) stays ignored.
        self.assertTrue(os.path.isdir(AGENTS), AGENTS)
        self.assertFalse(os.path.exists(os.path.join(TOOL_DIR, 'agents')))
        self.assertFalse(os.path.exists(os.path.join(
            REPO, 'docs', 'swift-migration', 'agents')))
        self.assertEqual(aj.DEFAULT_DEFINITIONS_DIR,
                         os.path.join('.claude', 'agents'))
        import subprocess
        for path, ignored in (('.claude/agents/migration-author.md', False),
                              ('.claude/settings.local.json', True)):
            code = subprocess.run(['git', '-C', REPO, 'check-ignore', '-q',
                                   path]).returncode
            self.assertEqual(code == 0, ignored, path)

    def test_author_may_write_records_but_not_rules(self):
        # The author may write the record files its unit calls for and must
        # not change the rules; "never edit the process files" was
        # ambiguous because the dossier and the registries are process
        # files too.
        prompt = self.load()['migration-author']['prompt']
        self.assertNotIn('the process files, because', prompt)
        for name in ('docs/swift-migration/units/<name>.md', 'traps.md',
                     'bugs.md', 'claims.md', 'hot-paths.md',
                     'reflective-sites.md', 'README.md', 'topic files',
                     'CLAUDE.md'):
            self.assertIn(name, prompt)
        self.assertIn('proposed in your report', prompt)

    def test_no_em_dashes(self):
        for name in os.listdir(AGENTS):
            with open(os.path.join(AGENTS, name), encoding='utf-8') as fh:
                self.assertNotIn(chr(0x2014), fh.read(), name)



class GitignoreTest(unittest.TestCase):
    """The repository's .gitignore tracks the top-level .claude/agents/ and
    ignores the rest of .claude/, and every nested .claude/ directory (such
    as ColorPicker/.claude/settings.local.json), at any depth. Checked in a
    throwaway repository holding a copy of the .gitignore, with no global
    or system configuration and no global excludes file, so that only the
    repository's own rules are tested."""

    IGNORED = ('.claude/settings.local.json', '.claude/settings.json',
               '.claude/worktrees/x', '.claude/foo/agents/x.md',
               'ColorPicker/.claude/settings.local.json',
               'a/b/.claude/agents/x.md')
    TRACKED = ('.claude/agents/x.md', '.claude/agents/sub/y.md',
               '.claude/agents/migration-author.md')

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='gitignore_test.')
        self.addCleanup(shutil.rmtree, self.tmp)
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null',
                        GIT_CONFIG_NOSYSTEM='1')
        subprocess.run(['git', 'init', '-q', self.tmp], check=True,
                       env=self.env)
        shutil.copy(os.path.join(REPO, '.gitignore'),
                    os.path.join(self.tmp, '.gitignore'))

    def ignored(self, path):
        proc = subprocess.run(['git', '-c', 'core.excludesFile=/dev/null',
                               'check-ignore', '-v', '--no-index', path],
                              cwd=self.tmp, env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        self.assertIn(proc.returncode, (0, 1), proc.stderr)
        return proc.returncode == 0

    def test_claude_directories_are_ignored_except_the_agents(self):
        for path in self.IGNORED:
            self.assertTrue(self.ignored(path), path)
        for path in self.TRACKED:
            self.assertFalse(self.ignored(path), path)


if __name__ == '__main__':
    unittest.main()
