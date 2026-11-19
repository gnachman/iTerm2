"""Tests for tools/swift_migration/pure_move.py, the pure-move checker.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests

The fixtures in fixtures/pure_move are small Objective-C files:

- widget_before.m: a class with -update and -reset.
- widget_extracted.m: the same with the body of the if in -update extracted,
  verbatim, into -updateField.
- widget_extracted_changed.m: widget_extracted.m with one moved line changed
  ("_count -= 1;" became "_count -= 2;").
- widget_no_reset.m: widget_before.m with -reset deleted.
- widget_reset_category.m: -reset alone in a category, a new file.

Every expected value below was worked out by hand from the fixture text and
the diff git prints for it. Each test builds its own small git repository in
a temporary directory.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
TOOL = os.path.join(TOOL_DIR, 'pure_move.py')
FIXTURES = os.path.join(HERE, 'fixtures', 'pure_move')
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
sys.dont_write_bytecode = True

import pure_move as pm  # noqa: E402

GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.com',
               GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@example.com',
               GIT_AUTHOR_DATE='2026-01-02T03:04:05Z', GIT_COMMITTER_DATE='2026-01-02T03:04:05Z',
               GIT_CONFIG_NOSYSTEM='1')


def fixture(name):
    with open(os.path.join(FIXTURES, name), 'rb') as f:
        return f.read()


class Repo(object):
    """A git repository in a temporary directory."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix='pure-move-test-')
        self.root = os.path.join(self.dir, 'repo')
        os.mkdir(self.root)
        self.git('init', '-q')

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def git(self, *args, **kwargs):
        proc = subprocess.run(['git'] + list(args), cwd=self.root, env=GIT_ENV,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              input=kwargs.get('input'))
        if proc.returncode != 0 and kwargs.get('check', True):
            raise AssertionError('git %s failed: %s' % (args, proc.stderr.decode()))
        return proc.stdout.decode('utf-8').strip()

    def write(self, path, content):
        full = os.path.join(self.root, path)
        d = os.path.dirname(full)
        if not os.path.isdir(d):
            os.makedirs(d)
        if isinstance(content, str):
            content = content.encode('utf-8')
        with open(full, 'wb') as f:
            f.write(content)

    def remove(self, path):
        os.remove(os.path.join(self.root, path))

    def commit(self, message='change'):
        self.git('add', '-A')
        self.git('commit', '-q', '--allow-empty', '-m', message)
        return self.git('rev-parse', 'HEAD')

    def run(self, *args):
        proc = subprocess.run([sys.executable, '-B', TOOL] + list(args), cwd=self.root,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return proc.returncode, proc.stdout.decode('utf-8'), proc.stderr.decode('utf-8')

    def run_json(self, *args):
        code, out, err = self.run('--json', *args)
        return code, (json.loads(out) if out else None), err


class RepoTestCase(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()

    def tearDown(self):
        self.repo.cleanup()

    def two_commits(self, files_before, files_after):
        """Commits files_before, then files_after (None deletes). Returns HEAD."""
        for path, content in files_before.items():
            self.repo.write(path, content)
        self.repo.commit('before')
        for path, content in files_after.items():
            if content is None:
                self.repo.remove(path)
            else:
                self.repo.write(path, content)
        return self.repo.commit('after')


def L(path, line, text):
    return pm.Line(path, line, text)


def block(rp, rs, re_, ap, as_, ae):
    return {'removed': {'path': rp, 'start': rs, 'end': re_},
            'added': {'path': ap, 'start': as_, 'end': ae},
            'lines': re_ - rs + 1}


# Unit tests of the matching code.

class NormalizeTests(unittest.TestCase):
    def test_strips_leading_spaces_and_tabs_only(self):
        self.assertEqual(pm.normalize(b'\t  foo  \t'), b'foo  \t')

    def test_keeps_other_leading_whitespace(self):
        self.assertEqual(pm.normalize(b'\x0bfoo'), b'\x0bfoo')
        self.assertEqual(pm.normalize(b'\rfoo'), b'\rfoo')

    def test_blank(self):
        self.assertEqual(pm.normalize(b'  \t '), b'')


class MatchTests(unittest.TestCase):
    def match(self, removed, added):
        return pm.match_lines(removed, added)

    def test_single_block_with_indentation_change(self):
        r = [L('a.m', 8, b'        x();'), L('a.m', 9, b'        y();')]
        a = [L('a.m', 6, b'    x();'), L('a.m', 7, b'    y();')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 8, 9, 'a.m', 6, 7)])
        self.assertEqual(m.unmatched_removed, [])
        self.assertEqual(m.unmatched_added, [])
        self.assertEqual(m.order_problems, [])

    def test_trailing_whitespace_differs(self):
        r = [L('a.m', 1, b'x();')]
        a = [L('a.m', 5, b'x(); ')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [])
        self.assertEqual(m.unmatched_removed, r)
        self.assertEqual(m.unmatched_added, a)

    def test_internal_whitespace_differs(self):
        m = self.match([L('a.m', 1, b'a = b;')], [L('a.m', 2, b'a  = b;')])
        self.assertEqual(len(m.unmatched_removed), 1)
        self.assertEqual(len(m.unmatched_added), 1)

    def test_line_used_once_dropped_duplicate(self):
        r = [L('a.m', 3, b'a();'), L('a.m', 4, b'a();')]
        a = [L('b.m', 7, b'a();')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 3, 3, 'b.m', 7, 7)])
        self.assertEqual(m.unmatched_removed, [L('a.m', 4, b'a();')])
        self.assertEqual(m.unmatched_added, [])

    def test_line_used_once_added_duplicate(self):
        r = [L('a.m', 3, b'a();')]
        a = [L('b.m', 7, b'a();'), L('b.m', 8, b'a();')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 3, 3, 'b.m', 7, 7)])
        self.assertEqual(m.unmatched_removed, [])
        self.assertEqual(m.unmatched_added, [L('b.m', 8, b'a();')])

    def test_reorder_within_block(self):
        r = [L('a.m', 10, b'a'), L('a.m', 11, b'b'), L('a.m', 12, b'c')]
        a = [L('a.m', 20, b'a'), L('a.m', 21, b'c'), L('a.m', 22, b'b')]
        m = self.match(r, a)
        self.assertEqual(m.unmatched_removed, [])
        self.assertEqual(m.unmatched_added, [])
        self.assertEqual(m.blocks_json(), [block('a.m', 10, 10, 'a.m', 20, 20),
                                           block('a.m', 11, 11, 'a.m', 22, 22),
                                           block('a.m', 12, 12, 'a.m', 21, 21)])
        self.assertEqual(m.order_problems_json(), [{
            'removed': {'path': 'a.m', 'start': 10, 'end': 12},
            'added': {'path': 'a.m', 'start': 20, 'end': 22},
            'pieces': [block('a.m', 10, 10, 'a.m', 20, 20),
                       block('a.m', 11, 11, 'a.m', 22, 22),
                       block('a.m', 12, 12, 'a.m', 21, 21)]}])

    def test_rotation_within_block(self):
        r = [L('a.m', 1, b'a'), L('a.m', 2, b'b'), L('a.m', 3, b'c')]
        a = [L('a.m', 9, b'b'), L('a.m', 10, b'c'), L('a.m', 11, b'a')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 1, 'a.m', 11, 11),
                                           block('a.m', 2, 3, 'a.m', 9, 10)])
        self.assertEqual(len(m.order_problems), 1)

    def test_foreign_line_interleaved_into_block(self):
        r = [L('a.m', 1, b'a'), L('a.m', 2, b'b'), L('a.m', 5, b'x')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'x'), L('b.m', 3, b'b')]
        m = self.match(r, a)
        self.assertEqual(m.unmatched_removed, [])
        self.assertEqual(m.order_problems_json(), [{
            'removed': {'path': 'a.m', 'start': 1, 'end': 2},
            'added': {'path': 'b.m', 'start': 1, 'end': 3},
            'pieces': [block('a.m', 1, 1, 'b.m', 1, 1),
                       block('a.m', 2, 2, 'b.m', 3, 3)]}])

    def test_pieces_in_different_added_runs_are_not_an_order_problem(self):
        r = [L('a.m', 1, b'a'), L('a.m', 2, b'b')]
        a = [L('a.m', 10, b'b'), L('a.m', 20, b'a')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 1, 'a.m', 20, 20),
                                           block('a.m', 2, 2, 'a.m', 10, 10)])
        self.assertEqual(m.order_problems, [])

    def test_pieces_in_different_files_are_not_an_order_problem(self):
        r = [L('a.m', 1, b'a'), L('a.m', 2, b'b')]
        a = [L('b.m', 1, b'b'), L('c.m', 1, b'a')]
        m = self.match(r, a)
        self.assertEqual(m.order_problems, [])

    def test_removed_runs_break_at_file_boundary(self):
        # a.m:5 and b.m:6 are not one run although the numbers are consecutive.
        r = [L('a.m', 5, b'a'), L('b.m', 6, b'b')]
        a = [L('c.m', 1, b'b'), L('c.m', 2, b'a')]
        m = self.match(r, a)
        self.assertEqual(m.order_problems, [])
        self.assertEqual(m.blocks_json(), [block('a.m', 5, 5, 'c.m', 2, 2),
                                           block('b.m', 6, 6, 'c.m', 1, 1)])

    def test_added_runs_break_at_file_boundary(self):
        r = [L('a.m', 5, b'a'), L('a.m', 6, b'b')]
        a = [L('b.m', 2, b'b'), L('c.m', 1, b'a')]
        m = self.match(r, a)
        self.assertEqual(m.order_problems, [])

    def test_added_runs_break_at_line_gap(self):
        r = [L('a.m', 5, b'a'), L('a.m', 6, b'b')]
        a = [L('b.m', 1, b'b'), L('b.m', 3, b'a')]
        m = self.match(r, a)
        self.assertEqual(m.order_problems, [])

    def test_removed_runs_break_at_line_gap(self):
        r = [L('a.m', 5, b'a'), L('a.m', 7, b'b')]
        a = [L('b.m', 1, b'b'), L('b.m', 2, b'a')]
        m = self.match(r, a)
        self.assertEqual(m.order_problems, [])

    def test_block_does_not_extend_across_file_boundary(self):
        r = [L('a.m', 5, b'a'), L('a.m', 6, b'b')]
        a = [L('b.m', 9, b'a'), L('c.m', 10, b'b')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 5, 5, 'b.m', 9, 9),
                                           block('a.m', 6, 6, 'c.m', 10, 10)])

    def test_block_does_not_extend_across_removed_file_boundary(self):
        r = [L('a.m', 5, b'a'), L('b.m', 6, b'b')]
        a = [L('c.m', 1, b'a'), L('c.m', 2, b'b')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 5, 5, 'c.m', 1, 1),
                                           block('b.m', 6, 6, 'c.m', 2, 2)])

    def test_block_does_not_extend_across_line_gap(self):
        r = [L('a.m', 5, b'a'), L('a.m', 6, b'b')]
        a = [L('b.m', 1, b'a'), L('b.m', 3, b'b')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 5, 5, 'b.m', 1, 1),
                                           block('a.m', 6, 6, 'b.m', 3, 3)])

    def test_longest_block_is_paired_first(self):
        # The lone x at a.m:1 could take the x inside the three-line block;
        # pairing longest first keeps the block whole.
        r = [L('a.m', 1, b'x'), L('a.m', 10, b'a'), L('a.m', 11, b'x'), L('a.m', 12, b'b')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'x'), L('b.m', 3, b'b'), L('b.m', 20, b'x')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 1, 'b.m', 20, 20),
                                           block('a.m', 10, 12, 'b.m', 1, 3)])
        self.assertEqual(m.order_problems, [])

    def test_longest_block_first_regardless_of_added_order(self):
        r = [L('a.m', 1, b'x'), L('a.m', 10, b'a'), L('a.m', 11, b'x'), L('a.m', 12, b'b')]
        a = [L('b.m', 1, b'x'), L('b.m', 5, b'a'), L('b.m', 6, b'x'), L('b.m', 7, b'b')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 1, 'b.m', 1, 1),
                                           block('a.m', 10, 12, 'b.m', 5, 7)])

    def test_partly_used_block_is_split_and_paired(self):
        # The four-line block is taken first; the two-line block a.m:20-21
        # shares its b.m:2 line, so only its second line pairs.
        r = [L('a.m', 1, b'p'), L('a.m', 2, b'q'), L('a.m', 3, b'r'), L('a.m', 4, b's'),
             L('a.m', 20, b'q'), L('a.m', 21, b'r')]
        a = [L('b.m', 1, b'p'), L('b.m', 2, b'q'), L('b.m', 3, b'r'), L('b.m', 4, b's'),
             L('b.m', 9, b'r')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 4, 'b.m', 1, 4),
                                           block('a.m', 21, 21, 'b.m', 9, 9)])
        self.assertEqual(m.unmatched_removed, [L('a.m', 20, b'q')])
        self.assertEqual(m.unmatched_added, [])

    def test_split_remainder_beats_shorter_block(self):
        # After a.m:1-5 takes b.m:1-5, the block a.m:10-14 vs b.m:1-5 and
        # b.m:20-22 remains; its remainder (a.m:10-12 vs b.m:20-22, three
        # lines) must be paired, not the single-line candidates.
        r = [L('a.m', 1, b'1'), L('a.m', 2, b'2'), L('a.m', 3, b'3'), L('a.m', 4, b'4'),
             L('a.m', 5, b'5'),
             L('a.m', 10, b'1'), L('a.m', 11, b'2'), L('a.m', 12, b'3')]
        a = [L('b.m', 1, b'1'), L('b.m', 2, b'2'), L('b.m', 3, b'3'), L('b.m', 4, b'4'),
             L('b.m', 5, b'5'),
             L('b.m', 20, b'1'), L('b.m', 21, b'2'), L('b.m', 22, b'3')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 5, 'b.m', 1, 5),
                                           block('a.m', 10, 12, 'b.m', 20, 22)])

    def test_identical_lines_in_block(self):
        r = [L('a.m', 1, b'}'), L('a.m', 2, b'}')]
        a = [L('b.m', 4, b'}'), L('b.m', 5, b'}')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 2, 'b.m', 4, 5)])
        self.assertEqual(m.order_problems, [])

    def test_unmatched_count_is_multiset_difference(self):
        r = [L('a.m', 1, b'a'), L('a.m', 2, b'b'), L('a.m', 3, b'a'), L('a.m', 4, b'c'),
             L('a.m', 5, b'a')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'c'), L('b.m', 3, b'c'), L('b.m', 4, b'b')]
        m = self.match(r, a)
        # a: 3 removed, 1 added. b: 1 and 1. c: 1 removed, 2 added.
        self.assertEqual([x.text for x in m.unmatched_removed], [b'a', b'a'])
        self.assertEqual([x.text for x in m.unmatched_added], [b'c'])

    def test_tie_broken_by_removed_then_added_position(self):
        r = [L('a.m', 1, b'a'), L('a.m', 3, b'a')]
        a = [L('b.m', 1, b'a'), L('b.m', 3, b'a')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 1, 'b.m', 1, 1),
                                           block('a.m', 3, 3, 'b.m', 3, 3)])

    def test_adjacent_pieces_are_reported_as_one_block(self):
        # Pairing finds a.m:1-2 vs b.m:1-2 (two lines) and the c.m copy of
        # "c"; nothing splits a contiguous move into two blocks.
        r = [L('a.m', 1, b'a'), L('a.m', 2, b'b'), L('a.m', 3, b'c')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'b'), L('b.m', 3, b'c')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 3, 'b.m', 1, 3)])

    def test_inputs_in_any_order(self):
        r = [L('a.m', 2, b'b'), L('a.m', 1, b'a')]
        a = [L('b.m', 2, b'b'), L('b.m', 1, b'a')]
        m = self.match(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 2, 'b.m', 1, 2)])

    def test_empty(self):
        m = self.match([], [])
        self.assertEqual(m.blocks_json(), [])
        self.assertEqual(m.order_problems, [])
        self.assertEqual(m.moved_line_count, 0)

    def test_moved_line_count(self):
        r = [L('a.m', 1, b'a'), L('a.m', 2, b'b'), L('a.m', 3, b'z')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'b')]
        self.assertEqual(self.match(r, a).moved_line_count, 2)


class MatchRemainderTests(unittest.TestCase):
    """A block partly taken by a longer one pairs its free pieces, which no other block covers."""

    def test_free_piece_at_start(self):
        r = [L('a.m', 1, b'b'), L('a.m', 2, b'c'), L('a.m', 3, b'd'), L('a.m', 4, b'e'),
             L('a.m', 5, b'f'),
             L('a.m', 10, b'a'), L('a.m', 11, b'b'), L('a.m', 12, b'c')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'b'), L('b.m', 3, b'c'), L('b.m', 4, b'd'),
             L('b.m', 5, b'e'), L('b.m', 6, b'f')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 5, 'b.m', 2, 6),
                                           block('a.m', 10, 10, 'b.m', 1, 1)])
        self.assertEqual(m.unmatched_removed, [L('a.m', 11, b'b'), L('a.m', 12, b'c')])
        self.assertEqual(m.order_problems, [])

    def test_free_piece_of_two_lines(self):
        r = [L('a.m', 1, b'c'), L('a.m', 2, b'd'), L('a.m', 3, b'e'), L('a.m', 4, b'x'),
             L('a.m', 5, b'y'), L('a.m', 6, b'z'),
             L('a.m', 10, b'a'), L('a.m', 11, b'b'), L('a.m', 12, b'c'), L('a.m', 13, b'd'),
             L('a.m', 14, b'e')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'b'), L('b.m', 3, b'c'), L('b.m', 4, b'd'),
             L('b.m', 5, b'e'), L('b.m', 6, b'x'), L('b.m', 7, b'y'), L('b.m', 8, b'z')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 6, 'b.m', 3, 8),
                                           block('a.m', 10, 11, 'b.m', 1, 2)])
        self.assertEqual(m.unmatched_removed, [L('a.m', 12, b'c'), L('a.m', 13, b'd'),
                                               L('a.m', 14, b'e')])

    def test_free_piece_at_end(self):
        r = [L('a.m', 1, b'p'), L('a.m', 2, b'q'), L('a.m', 3, b'r'), L('a.m', 4, b's'),
             L('a.m', 5, b'a'),
             L('a.m', 10, b's'), L('a.m', 11, b'a'), L('a.m', 12, b'b')]
        a = [L('b.m', 1, b'p'), L('b.m', 2, b'q'), L('b.m', 3, b'r'), L('b.m', 4, b's'),
             L('b.m', 5, b'a'), L('b.m', 6, b'b')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 5, 'b.m', 1, 5),
                                           block('a.m', 12, 12, 'b.m', 6, 6)])
        self.assertEqual(m.unmatched_removed, [L('a.m', 10, b's'), L('a.m', 11, b'a')])


class MatchRemainderAfterUsedLineTests(unittest.TestCase):
    def test_free_piece_right_after_one_used_line(self):
        r = [L('a.m', 1, b'p'), L('a.m', 2, b'q'), L('a.m', 3, b'r'), L('a.m', 4, b'a'),
             L('a.m', 10, b'a'), L('a.m', 11, b'b')]
        a = [L('b.m', 1, b'p'), L('b.m', 2, b'q'), L('b.m', 3, b'r'), L('b.m', 4, b'a'),
             L('b.m', 5, b'b')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 4, 'b.m', 1, 4),
                                           block('a.m', 11, 11, 'b.m', 5, 5)])
        self.assertEqual(m.unmatched_removed, [L('a.m', 10, b'a')])


class MatchBlockStartTests(unittest.TestCase):
    def test_pair_after_unequal_pair_starts_a_block_when_added_repeats(self):
        r = [L('a.m', 1, b'x'), L('a.m', 2, b'a'), L('a.m', 10, b'a')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'a')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.unmatched_removed, [L('a.m', 1, b'x')])
        self.assertEqual(m.unmatched_added, [])

    def test_pair_after_unequal_pair_starts_a_block_when_removed_repeats(self):
        r = [L('a.m', 1, b'a'), L('a.m', 2, b'a')]
        a = [L('b.m', 1, b'a'), L('b.m', 5, b'z'), L('b.m', 6, b'a')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.unmatched_removed, [])
        self.assertEqual(m.unmatched_added, [L('b.m', 5, b'z')])
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 1, 'b.m', 1, 1),
                                           block('a.m', 2, 2, 'b.m', 6, 6)])

    def test_needed_pair_after_unequal_pair_in_repeated_added_run(self):
        # a.m:1 takes b.m:1; a.m:6 can only take b.m:2, a pair whose
        # predecessor (a.m:5 "x", b.m:1 "a") differs, so it starts a block.
        r = [L('a.m', 1, b'a'), L('a.m', 5, b'x'), L('a.m', 6, b'a')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'a')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 1, 'b.m', 1, 1),
                                           block('a.m', 6, 6, 'b.m', 2, 2)])
        self.assertEqual(m.unmatched_removed, [L('a.m', 5, b'x')])
        self.assertEqual(m.unmatched_added, [])

    def test_order_problem_ranges_use_their_own_runs(self):
        r = [L('a.m', 1, b'z'), L('a.m', 5, b'a'), L('a.m', 6, b'b'), L('a.m', 7, b'c')]
        a = [L('b.m', 1, b'a'), L('b.m', 2, b'c'), L('b.m', 3, b'b'), L('c.m', 1, b'z')]
        m = pm.match_lines(r, a)
        self.assertEqual(len(m.order_problems), 1)
        p = m.order_problems_json()[0]
        self.assertEqual(p['removed'], {'path': 'a.m', 'start': 5, 'end': 7})
        self.assertEqual(p['added'], {'path': 'b.m', 'start': 1, 'end': 3})


class VerifyPatchTests(unittest.TestCase):
    def test_matches(self):
        pm.verify_patch([(1, b'a'), (3, b'c')], [b'a', b'b', b'c'], 'x.m')

    def test_wrong_text(self):
        with self.assertRaises(pm.ToolError):
            pm.verify_patch([(2, b'c')], [b'a', b'b', b'c'], 'x.m')

    def test_past_end(self):
        with self.assertRaises(pm.ToolError):
            pm.verify_patch([(4, b'c')], [b'a', b'b', b'c'], 'x.m')


class ParseRawTests(unittest.TestCase):
    Z = '0' * 40
    S = '1' * 40

    def test_entries(self):
        data = (':100644 100644 %s %s M\0a.m\0:100644 100644 %s %s R090\0old.m\0new.m\0'
                % (self.Z, self.S, self.Z, self.S)).encode()
        self.assertEqual(pm.parse_raw(data), [
            pm.Entry('M', '100644', '100644', self.Z, self.S, 'a.m', 'a.m'),
            pm.Entry('R', '100644', '100644', self.Z, self.S, 'old.m', 'new.m')])

    def test_empty(self):
        self.assertEqual(pm.parse_raw(b''), [])

    def test_garbage(self):
        with self.assertRaises(pm.ToolError):
            pm.parse_raw(b'a.m\0')


def collect4(git, mode, old, new):
    """pm.collect, flattened to (files, removed lines, added lines, problems)."""
    files, compared, problems = pm.collect(git, mode, old, new)
    removed = [pm.Line(f.old_path, n, t) for f in compared for n, t in f.removed]
    added = [pm.Line(f.path, n, t) for f in compared for n, t in f.added]
    return files, removed, added, problems


class FakeGit(object):
    """Answers collect()'s git calls from a canned --raw listing."""

    patches = pm.Git.patches

    def __init__(self, raw, blobs, patch=b''):
        self.raw = raw
        self.contents = blobs
        self.patch = patch

    def run(self, args, input=None, check=True):
        if args[0] == 'diff-pairs':
            # One batch, for one modified file; by default the blobs have the same lines.
            return self.patch + b'\0'
        assert args[:2] == ['diff', '--raw'], args
        return self.raw

    def sizes(self, shas):
        return dict((sha, len(self.contents[sha])) for sha in shas)

    def read_blobs(self, shas):
        return dict((sha, self.contents[sha]) for sha in shas)


class CollectStatusTests(unittest.TestCase):
    Z = '0' * 40
    S = '1' * 40
    T = '2' * 40

    def collect(self, line, paths):
        raw = (line + '\0' + '\0'.join(paths) + '\0').encode()
        return collect4(FakeGit(raw, {self.S: b'x\n', self.T: b'y\n'}), 'range', 'o', 'n')

    def test_copy_is_an_error(self):
        with self.assertRaises(pm.ToolError):
            self.collect(':100644 100644 %s %s C100' % (self.S, self.S), ['a.m', 'b.m'])

    def test_unknown_status_is_an_error(self):
        with self.assertRaises(pm.ToolError):
            self.collect(':100644 100644 %s %s X' % (self.S, self.T), ['a.m'])

    def test_unexpected_modes_name_the_old_one_and_later_files_are_still_read(self):
        raw = (':100664 100775 %s %s M\0a.m\0:000000 100644 %s %s A\0z.m\0'
               % (self.S, self.T, self.Z, self.T)).encode()
        files, removed, added, problems = collect4(
            FakeGit(raw, {self.S: b'x\n', self.T: b'y\n'}), 'range', 'o', 'n')
        self.assertEqual(problems, [{'path': 'a.m', 'problem': 'unexpected mode 100664; not compared'}])
        self.assertEqual(added, [pm.Line('z.m', 1, b'y')])

    def test_unexpected_mode(self):
        files, removed, added, problems = self.collect(
            ':100644 100664 %s %s M' % (self.S, self.T), ['a.m'])
        self.assertEqual(problems, [{'path': 'a.m', 'problem': 'unexpected mode 100664; not compared'}])
        self.assertEqual((removed, added), ([], []))


class SizeLimitTests(unittest.TestCase):
    S = '1' * 40
    T = '2' * 40

    def setUp(self):
        self.saved = pm.MAX_BLOB_BYTES

    def tearDown(self):
        pm.MAX_BLOB_BYTES = self.saved

    def test_limit_is_20_mb(self):
        self.assertEqual(pm.MAX_BLOB_BYTES, 20971520)

    def collect(self, old, new):
        raw = (':100644 100644 %s %s M\0a.m\0' % (self.S, self.T)).encode()
        return collect4(FakeGit(raw, {self.S: old, self.T: new}), 'range', 'o', 'n')[3]

    def test_at_limit_is_compared(self):
        pm.MAX_BLOB_BYTES = 4
        self.assertEqual(self.collect(b'abc\n', b'abc\n'), [])

    def test_old_over_limit(self):
        pm.MAX_BLOB_BYTES = 4
        self.assertEqual(self.collect(b'abcd\n', b'abc\n'),
                         [{'path': 'a.m', 'problem': 'file over 20 MB; not compared'}])

    def test_new_over_limit(self):
        pm.MAX_BLOB_BYTES = 4
        self.assertEqual(self.collect(b'abc\n', b'abcd\n'),
                         [{'path': 'a.m', 'problem': 'file over 20 MB; not compared'}])


class ParseDeclarationTests(unittest.TestCase):
    def test_single_line(self):
        self.assertEqual(pm.parse_declaration('sources/a.m:12'), ('sources/a.m', 12, 12))

    def test_range(self):
        self.assertEqual(pm.parse_declaration('a.m:3-5'), ('a.m', 3, 5))

    def test_path_with_colon(self):
        self.assertEqual(pm.parse_declaration('x:y.m:3'), ('x:y.m', 3, 3))

    def test_bad(self):
        for bad in ['a.m', 'a.m:', ':3', 'a.m:0', 'a.m:5-4', 'a.m:x', 'a.m:3-', 'a.m:-3',
                    'a.m:1-2-3', 'a.m: 3', 'a.m:+3']:
            with self.assertRaises(ValueError, msg=bad):
                pm.parse_declaration(bad)


class ParsePatchTests(unittest.TestCase):
    def test_hunks(self):
        patch = (b'diff --git a/x b/x\nindex 1..2\n--- a/x\n+++ b/x\n'
                 b'@@ -4,0 +5,2 @@\n+new one\n+--- dashes\n'
                 b'@@ -8,3 +11 @@\n-old a\n--- b\n-old c\n+call\n'
                 b'@@ -20 +18,0 @@\n-last\n\\ No newline at end of file\n')
        removed, added = pm.parse_patch(patch)
        self.assertEqual(removed, [(8, b'old a'), (9, b'-- b'), (10, b'old c'), (20, b'last')])
        self.assertEqual(added, [(5, b'new one'), (6, b'--- dashes'), (11, b'call')])

    def test_bad_patch(self):
        for bad in [b'@@ -1 +1 @@\n-a\n',            # missing added line
                    b'@@ -1 +1 @@\n+a\n-b\n',         # added before removed
                    b'@@ -1 +1 @@\n-a\n+b\n+c\n',     # extra line
                    b'@@ bogus @@\n',
                    b'@@ -1 +1 @@\n a\n+b\n',         # context line
                    b'diff --git a/x b/x\nBinary files a/x and b/x differ\n']:
            with self.assertRaises(pm.ToolError, msg=bad):
                pm.parse_patch(bad)

    def test_no_hunks(self):
        self.assertEqual(pm.parse_patch(b''), ([], []))


class SplitLinesTests(unittest.TestCase):
    def test_split(self):
        self.assertEqual(pm.split_lines(b'a\nb\n'), [b'a', b'b'])
        self.assertEqual(pm.split_lines(b'a\nb'), [b'a', b'b'])
        self.assertEqual(pm.split_lines(b''), [])
        self.assertEqual(pm.split_lines(b'\n'), [b''])
        self.assertEqual(pm.split_lines(b'a\r\n'), [b'a\r'])


class DisplayTests(unittest.TestCase):
    def test_escapes(self):
        self.assertEqual(pm.display(b'a\tb\r\x01\x1f \x7f\xff~'), 'a\tb\\r\\x01\\x1f \\x7f\\xff~')

    def test_utf8_kept(self):
        self.assertEqual(pm.display('café “x”'.encode('utf-8')), 'café “x”')


class BinaryTests(unittest.TestCase):
    def test_nul_in_first_8000_bytes(self):
        self.assertTrue(pm.is_binary(b'a' * 7999 + b'\0'))
        self.assertFalse(pm.is_binary(b'a' * 8000 + b'\0'))
        self.assertFalse(pm.is_binary(b'plain\n'))


# End-to-end tests in temporary repositories.

class PureMoveCommitTests(RepoTestCase):
    def extraction(self, after='widget_extracted.m'):
        return self.two_commits({'Widget.m': fixture('widget_before.m')},
                                {'Widget.m': fixture(after)})

    def test_extraction_with_declared_lines_is_pure(self):
        self.extraction()
        code, out, err = self.repo.run('HEAD', '--allow-added', 'Widget.m:5',
                                       '--allow-added', 'Widget.m:9-10',
                                       '--allow-added', 'Widget.m:14')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertIn('Result: PURE MOVE', out)
        self.assertIn('  Widget.m:8-10 -> Widget.m:6-8 (3 lines)', out)
        self.assertIn('  Widget.m:5: - (void)updateField {', out)
        self.assertIn('  Widget.m:14:         [self updateField];', out)

    def test_extraction_json(self):
        head = self.extraction()
        parent = self.repo.git('rev-parse', 'HEAD^')
        code, j, err = self.repo.run_json('HEAD', '--allow-added', 'Widget.m:5',
                                          '--allow-added', 'Widget.m:9-10',
                                          '--allow-added', 'Widget.m:14')
        self.assertEqual(code, 0)
        self.assertEqual(j['pure_move'], True)
        self.assertEqual(j['exit_code'], 0)
        self.assertEqual(j['compared'], {'mode': 'commit', 'old': parent, 'new': head})
        self.assertEqual(j['files'], [{'path': 'Widget.m', 'old_path': 'Widget.m', 'status': 'M',
                                       'old_mode': '100644', 'new_mode': '100644'}])
        self.assertEqual(j['moved_blocks'], [block('Widget.m', 8, 10, 'Widget.m', 6, 8)])
        self.assertEqual(j['declared_added'], [
            {'path': 'Widget.m', 'line': 5, 'text': '- (void)updateField {'},
            {'path': 'Widget.m', 'line': 9, 'text': '}'},
            {'path': 'Widget.m', 'line': 10, 'text': ''},
            {'path': 'Widget.m', 'line': 14, 'text': '        [self updateField];'}])
        self.assertEqual(j['declared_removed'], [])
        self.assertEqual(j['unaccounted_removed'], [])
        self.assertEqual(j['unaccounted_added'], [])
        self.assertEqual(j['order_problems'], [])
        self.assertEqual(j['file_problems'], [])
        self.assertEqual(j['counts'], {'removed': 3, 'added': 7, 'moved': 3,
                                       'declared_removed': 0, 'declared_added': 4,
                                       'unaccounted_removed': 0, 'unaccounted_added': 0,
                                       'order_problems': 0, 'file_problems': 0,
                                       'run_notices': 0})
        self.assertEqual(j['strict_runs'], False)
        self.assertEqual(j['run_notices'], [])
        self.assertEqual(j['runs'], [{'removed': {'path': 'Widget.m', 'start': 8, 'end': 10},
                                      'lands_in': [{'path': 'Widget.m', 'start': 6, 'end': 8}]}])
        self.assertEqual(j['rules'], pm.RULES)
        self.assertEqual(j['not_checked'], pm.NOT_CHECKED)

    def test_extraction_without_declarations_lists_new_lines(self):
        self.extraction()
        code, out, err = self.repo.run('HEAD')
        self.assertEqual(code, 1)
        self.assertIn('Result: NOT A PURE MOVE', out)
        self.assertIn('Unaccounted added lines (4):\n'
                      '  Widget.m:5: - (void)updateField {\n'
                      '  Widget.m:9: }\n'
                      '  Widget.m:10: \n'
                      '  Widget.m:14:         [self updateField];\n', out)
        self.assertIn('Unaccounted removed lines (0)', out)

    def test_changed_moved_line(self):
        self.extraction('widget_extracted_changed.m')
        code, j, err = self.repo.run_json('HEAD', '--allow-added', 'Widget.m:5',
                                          '--allow-added', 'Widget.m:9-10',
                                          '--allow-added', 'Widget.m:14')
        self.assertEqual(code, 1)
        self.assertEqual(j['pure_move'], False)
        self.assertEqual(j['unaccounted_removed'],
                         [{'path': 'Widget.m', 'line': 10, 'text': '        _count -= 1;'}])
        self.assertEqual(j['unaccounted_added'],
                         [{'path': 'Widget.m', 'line': 8, 'text': '    _count -= 2;'}])
        self.assertEqual(j['moved_blocks'], [block('Widget.m', 8, 9, 'Widget.m', 6, 7)])

    def test_changed_moved_line_text(self):
        self.extraction('widget_extracted_changed.m')
        code, out, err = self.repo.run('HEAD', '--allow-added', 'Widget.m:5',
                                       '--allow-added', 'Widget.m:9-10',
                                       '--allow-added', 'Widget.m:14')
        self.assertEqual(code, 1)
        self.assertIn('Unaccounted removed lines (1):\n  Widget.m:10:         _count -= 1;\n', out)
        self.assertIn('Unaccounted added lines (1):\n  Widget.m:8:     _count -= 2;\n', out)

    def test_method_moved_to_new_file(self):
        self.two_commits({'Widget.m': fixture('widget_before.m')},
                         {'Widget.m': fixture('widget_no_reset.m'),
                          'Widget+Reset.m': fixture('widget_reset_category.m')})
        code, j, err = self.repo.run_json('HEAD', '--allow-added', 'Widget+Reset.m:1-4',
                                          '--allow-added', 'Widget+Reset.m:10')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertEqual(j['moved_blocks'], [block('Widget.m', 15, 19, 'Widget+Reset.m', 5, 9)])
        self.assertEqual(j['files'], [
            {'path': 'Widget+Reset.m', 'old_path': None, 'status': 'A',
             'old_mode': None, 'new_mode': '100644'},
            {'path': 'Widget.m', 'old_path': 'Widget.m', 'status': 'M',
             'old_mode': '100644', 'new_mode': '100644'}])

    def test_method_moved_out_of_deleted_file(self):
        self.two_commits({'Widget.m': fixture('widget_no_reset.m'),
                          'Widget+Reset.m': fixture('widget_reset_category.m')},
                         {'Widget.m': fixture('widget_before.m'),
                          'Widget+Reset.m': None})
        code, j, err = self.repo.run_json('HEAD', '--allow-removed', 'Widget+Reset.m:1-4',
                                          '--allow-removed', 'Widget+Reset.m:10')
        self.assertEqual(code, 0)
        self.assertEqual(j['moved_blocks'], [block('Widget+Reset.m', 5, 9, 'Widget.m', 15, 19)])
        self.assertEqual(j['files'][0]['status'], 'D')
        self.assertEqual(j['files'][0]['new_mode'], None)
        self.assertEqual(j['declared_removed'][0],
                         {'path': 'Widget+Reset.m', 'line': 1, 'text': '#import "Widget.h"'})

    def test_indentation_only_change_is_pure(self):
        self.two_commits({'a.m': 'if (x) {\n    f();\n    g();\n}\n'},
                         {'a.m': 'if (x) {\n\tf();\n        g();\n}\n'})
        code, out, err = self.repo.run('HEAD')
        self.assertEqual(code, 0)
        self.assertIn('  a.m:2-3 -> a.m:2-3 (2 lines)', out)

    def test_trailing_whitespace_is_not_pure(self):
        self.two_commits({'a.m': 'f();\ng();\n'}, {'a.m': 'f(); \ng();\n'})
        code, out, err = self.repo.run('HEAD')
        self.assertEqual(code, 1)
        self.assertIn('  a.m:1: f();\n', out)
        self.assertIn('  a.m:1: f();\\x20\n', out)

    def test_crlf_is_not_pure(self):
        self.two_commits({'a.m': 'f();\ng();\n'}, {'a.m': 'f();\r\ng();\n'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        self.assertEqual(j['unaccounted_added'], [{'path': 'a.m', 'line': 1, 'text': 'f();\\r'}])

    def test_comment_change_is_not_pure(self):
        self.two_commits({'a.m': 'f();  // one\ng();\n'}, {'a.m': 'g();\nf();  // two\n'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        self.assertEqual(len(j['unaccounted_removed']), 1)

    def test_duplicated_line_is_caught(self):
        self.two_commits({'a.m': 'start\nf();\ng();\nend\n'},
                         {'a.m': 'start\nend\n', 'b.m': 'f();\nf();\ng();\n'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        # The two-line block a.m:2-3 pairs with b.m:2-3, leaving b.m:1.
        self.assertEqual(j['unaccounted_added'], [{'path': 'b.m', 'line': 1, 'text': 'f();'}])
        self.assertEqual(j['unaccounted_removed'], [])

    def test_dropped_one_of_identical_lines_is_caught(self):
        self.two_commits({'a.m': 'start\nf();\nf();\ng();\nend\n'},
                         {'a.m': 'start\nend\n', 'b.m': 'f();\ng();\n'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        # The two-line block a.m:3-4 pairs with b.m:1-2, leaving a.m:2.
        self.assertEqual(j['unaccounted_removed'], [{'path': 'a.m', 'line': 2, 'text': 'f();'}])
        self.assertEqual(j['unaccounted_added'], [])

    def test_reordered_moved_block_is_caught(self):
        self.two_commits({'a.m': 'start\na();\nb();\nc();\nend\n'},
                         {'a.m': 'start\nend\n', 'b.m': 'a();\nc();\nb();\n'})
        code, out, err = self.repo.run('HEAD')
        self.assertEqual(code, 1)
        self.assertIn('Reordered or interleaved moved lines (1):\n'
                      '  a.m:2-4 lands in b.m:1-3 as 3 pieces:\n'
                      '    a.m:2-2 -> b.m:1-1\n'
                      '    a.m:3-3 -> b.m:3-3\n'
                      '    a.m:4-4 -> b.m:2-2\n', out)

    def test_moved_block_split_by_declared_line_is_not_reordered(self):
        # Two extractions from adjacent code, the second placed first.
        self.two_commits({'a.m': 'start\na();\nb();\nend\n'},
                         {'a.m': 'start\nend\n',
                          'b.m': 'void B() {\nb();\n}\nvoid A() {\na();\n}\n'})
        code, j, err = self.repo.run_json('HEAD', '--allow-added', 'b.m:1',
                                          '--allow-added', 'b.m:3-4',
                                          '--allow-added', 'b.m:6')
        self.assertEqual(code, 0)
        self.assertEqual(j['moved_blocks'], [block('a.m', 2, 2, 'b.m', 5, 5),
                                             block('a.m', 3, 3, 'b.m', 2, 2)])

    def test_declared_removed_line_splits_removed_run(self):
        self.two_commits({'a.m': 'start\na();\nX\nb();\nend\n'},
                         {'a.m': 'start\nend\n', 'b.m': 'b();\na();\n'})
        code, j, err = self.repo.run_json('HEAD', '--allow-removed', 'a.m:3')
        self.assertEqual(code, 0)
        self.assertEqual(j['order_problems'], [])
        self.assertEqual(j['declared_removed'], [{'path': 'a.m', 'line': 3, 'text': 'X'}])

    def test_declared_line_is_not_paired(self):
        # Declaring b.m:1, which is a moved line, leaves a.m:2 unpaired.
        self.two_commits({'a.m': 'start\nf();\nend\n'}, {'a.m': 'start\nend\n', 'b.m': 'f();\n'})
        code, j, err = self.repo.run_json('HEAD', '--allow-added', 'b.m:1')
        self.assertEqual(code, 1)
        self.assertEqual(j['unaccounted_removed'], [{'path': 'a.m', 'line': 2, 'text': 'f();'}])

    def test_non_utf8_line_is_escaped(self):
        self.two_commits({'a.m': b'x\n'}, {'a.m': b'x\n\xff\xfe y\n'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        self.assertEqual(j['unaccounted_added'], [{'path': 'a.m', 'line': 2, 'text': '\\xff\\xfe y'}])

    def test_root_commit_is_all_added(self):
        self.repo.write('a.m', 'f();\n')
        self.repo.commit('root')
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        self.assertEqual(j['compared']['old'], self.repo.git('hash-object', '-t', 'tree', '/dev/null'))
        self.assertEqual(j['unaccounted_added'], [{'path': 'a.m', 'line': 1, 'text': 'f();'}])

    def test_default_text_sections(self):
        self.extraction()
        code, out, err = self.repo.run('HEAD')
        self.assertIn('Rules applied:\n', out)
        for rule in pm.RULES:
            self.assertIn(rule, out)
        self.assertIn('Not checked by this tool:\n', out)
        for item in pm.NOT_CHECKED:
            self.assertIn(item, out)

    def test_deterministic_and_writes_nothing(self):
        self.extraction()
        before = sorted(os.listdir(self.repo.root)) + [self.repo.git('status', '--porcelain', '--ignored')]
        first = self.repo.run('HEAD')
        second = self.repo.run('HEAD')
        self.assertEqual(first, second)
        after = sorted(os.listdir(self.repo.root)) + [self.repo.git('status', '--porcelain', '--ignored')]
        self.assertEqual(before, after)

    def test_user_diff_config_is_ignored(self):
        self.extraction()
        self.repo.git('config', 'diff.noprefix', 'true')
        self.repo.git('config', 'diff.algorithm', 'minimal')
        self.repo.git('config', 'color.diff', 'always')
        self.repo.git('config', 'diff.renames', 'false')
        code, out, err = self.repo.run('HEAD', '--allow-added', 'Widget.m:5',
                                       '--allow-added', 'Widget.m:9-10',
                                       '--allow-added', 'Widget.m:14')
        self.assertEqual(code, 0)


class FileProblemTests(RepoTestCase):
    def problems(self, *args):
        code, j, err = self.repo.run_json('HEAD', *args)
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['pure_move'], False)
        return j['file_problems']

    def test_empty_commit(self):
        self.repo.write('a.m', 'x\n')
        self.repo.commit()
        self.repo.commit('empty')
        code, out, err = self.repo.run('HEAD')
        self.assertEqual(code, 1)
        self.assertIn('Result: NOT A PURE MOVE', out)
        self.assertIn('  (diff): the diff is empty; nothing was moved\n', out)

    def test_empty_commit_json(self):
        self.repo.write('a.m', 'x\n')
        self.repo.commit()
        self.repo.commit('empty')
        self.assertEqual(self.problems(), [{'path': None, 'problem': 'the diff is empty; nothing was moved'}])

    def test_nothing_moved(self):
        self.two_commits({'a.m': 'x\n'}, {'a.m': 'x\ny\n'})
        self.assertEqual(self.problems('--allow-added', 'a.m:2'),
                         [{'path': None, 'problem': 'no line was moved'}])

    def test_binary_file(self):
        self.two_commits({'a.bin': b'\0\1\2'}, {'a.bin': b'\0\1\3'})
        self.assertEqual(self.problems(), [{'path': 'a.bin', 'problem': 'binary file; not compared'},
                                           {'path': None, 'problem': 'no line was moved'}])

    def test_binary_file_added(self):
        self.two_commits({'a.m': 'x\n'}, {'a.bin': b'\0'})
        self.assertEqual(self.problems(), [{'path': 'a.bin', 'problem': 'binary file; not compared'},
                                           {'path': None, 'problem': 'no line was moved'}])

    def test_binary_file_deleted_alongside_move(self):
        self.two_commits({'a.bin': b'\0', 'a.m': 'start\nf();\nend\n'},
                         {'a.bin': None, 'a.m': 'start\nend\nf();\n'})
        self.assertEqual(self.problems(), [{'path': 'a.bin', 'problem': 'binary file; not compared'}])

    def test_rename(self):
        content = ''.join('line %d\n' % i for i in range(20))
        self.two_commits({'a.m': content}, {'a.m': None, 'b.m': content})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        # A rename is refused before its lines are read, so nothing is paired.
        self.assertEqual(j['file_problems'], [
            {'path': 'b.m', 'problem': 'renamed from a.m; not compared'},
            {'path': None, 'problem': 'no line was moved'}])
        self.assertEqual(j['files'], [{'path': 'b.m', 'old_path': 'a.m', 'status': 'R',
                                       'old_mode': '100644', 'new_mode': '100644'}])
        self.assertEqual(j['unaccounted_removed'], [])
        self.assertEqual(j['moved_blocks'], [])
        self.assertEqual((j['counts']['removed'], j['counts']['added']), (0, 0))

    def test_rename_with_change(self):
        content = ''.join('line %d\n' % i for i in range(20))
        self.two_commits({'a.m': content}, {'a.m': None, 'b.m': content + 'extra\n'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [
            {'path': 'b.m', 'problem': 'renamed from a.m; not compared'},
            {'path': None, 'problem': 'no line was moved'}])
        self.assertEqual(j['unaccounted_added'], [])

    # In these tests z.m, which sorts after the file with the problem, also
    # moves one line, so a check that stopped at the problem would miss it.
    Z_BEFORE = 'start\nf();\nend\n'
    Z_AFTER = 'start\nend\nf();\n'
    Z_BLOCKS = [block('z.m', 2, 2, 'z.m', 3, 3)]

    def z_problems(self):
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['moved_blocks'], self.Z_BLOCKS)
        return j['file_problems']

    def test_mode_change(self):
        self.two_commits({'a.sh': 'echo\n'}, {})
        os.chmod(os.path.join(self.repo.root, 'a.sh'), 0o755)
        self.repo.commit()
        self.assertEqual(self.problems(), [
            {'path': 'a.sh', 'problem': 'mode changed from 100644 to 100755; not compared'},
            {'path': None, 'problem': 'no line was moved'}])

    def test_mode_change_alongside_move(self):
        self.two_commits({'a.sh': 'echo\n', 'z.m': self.Z_BEFORE}, {'z.m': self.Z_AFTER})
        os.chmod(os.path.join(self.repo.root, 'a.sh'), 0o755)
        self.repo.commit()
        self.repo.git('reset', '-q', '--soft', 'HEAD~2')
        self.repo.commit()
        self.assertEqual(self.z_problems(), [
            {'path': 'a.sh', 'problem': 'mode changed from 100644 to 100755; not compared'}])

    def test_symlink(self):
        self.repo.write('a.m', 'x\n')
        self.repo.write('z.m', self.Z_BEFORE)
        self.repo.commit()
        os.symlink('a.m', os.path.join(self.repo.root, 'link.m'))
        self.repo.write('z.m', self.Z_AFTER)
        self.repo.commit()
        self.assertEqual(self.z_problems(), [
            {'path': 'link.m', 'problem': 'symbolic link; not compared'}])

    def test_symlink_alone(self):
        self.repo.write('a.m', 'x\n')
        self.repo.commit()
        os.symlink('a.m', os.path.join(self.repo.root, 'link.m'))
        self.repo.commit()
        self.assertEqual(self.problems(), [
            {'path': 'link.m', 'problem': 'symbolic link; not compared'},
            {'path': None, 'problem': 'no line was moved'}])

    def test_type_change(self):
        self.repo.write('a.m', 'x\n')
        self.repo.write('b.m', 'a.m')
        self.repo.write('z.m', self.Z_BEFORE)
        self.repo.commit()
        self.repo.remove('b.m')
        os.symlink('a.m', os.path.join(self.repo.root, 'b.m'))
        self.repo.write('z.m', self.Z_AFTER)
        self.repo.commit()
        self.assertEqual(self.z_problems(),
                         [{'path': 'b.m', 'problem': 'type changed (T); not compared'}])

    def test_submodule(self):
        self.repo.write('a.m', 'x\n')
        self.repo.write('z.m', self.Z_BEFORE)
        self.repo.commit()
        self.repo.git('update-index', '--add', '--cacheinfo',
                      '160000,1111111111111111111111111111111111111111,sub')
        self.repo.write('z.m', self.Z_AFTER)
        self.repo.git('add', 'z.m')
        self.repo.git('commit', '-q', '-m', 'sub')
        self.assertEqual(self.z_problems(), [{'path': 'sub', 'problem': 'submodule; not compared'}])

    def test_submodule_ignore_config_does_not_hide_it(self):
        self.repo.write('a.m', 'x\n')
        self.repo.commit()
        self.repo.git('update-index', '--add', '--cacheinfo',
                      '160000,1111111111111111111111111111111111111111,sub')
        self.repo.git('commit', '-q', '-m', 'sub')
        self.repo.git('config', 'diff.ignoreSubmodules', 'all')
        self.assertEqual(self.problems(), [{'path': 'sub', 'problem': 'submodule; not compared'},
                                           {'path': None, 'problem': 'no line was moved'}])

    def test_binary_file_before_move(self):
        self.two_commits({'a.bin': b'\0\1\2', 'z.m': self.Z_BEFORE},
                         {'a.bin': b'\0\1\3', 'z.m': self.Z_AFTER})
        self.assertEqual(self.z_problems(), [{'path': 'a.bin', 'problem': 'binary file; not compared'}])

    def test_large_file(self):
        big = 'x\n' * (10 * 1024 * 1024 + 1)
        self.two_commits({'a.m': 'start\n', 'z.m': self.Z_BEFORE},
                         {'a.m': 'start\n' + big, 'z.m': self.Z_AFTER})
        self.assertEqual(self.z_problems(), [{'path': 'a.m', 'problem': 'file over 20 MB; not compared'}])

    def test_empty_file_added(self):
        self.two_commits({'a.m': 'x\n'}, {'b.m': ''})
        self.assertEqual(self.problems(), [
            {'path': 'b.m', 'problem': 'empty file added'},
            {'path': None, 'problem': 'no line was moved'}])

    def test_empty_file_deleted(self):
        self.two_commits({'a.m': 'x\n', 'b.m': ''}, {'b.m': None})
        self.assertEqual(self.problems(), [{'path': 'b.m', 'problem': 'empty file deleted'},
                                           {'path': None, 'problem': 'no line was moved'}])

    def test_final_newline_removed(self):
        self.two_commits({'a.m': 'start\nf();\nend\n'}, {'a.m': 'f();\nstart\nend'})
        self.assertEqual(self.problems(), [
            {'path': 'a.m', 'problem': 'final newline removed'}])

    def test_final_newline_added(self):
        self.two_commits({'a.m': 'start\nf();\nend'}, {'a.m': 'f();\nstart\nend\n'})
        self.assertEqual(self.problems(), [
            {'path': 'a.m', 'problem': 'final newline added'}])

    def test_text_lists_file_problems(self):
        self.two_commits({'a.bin': b'\0\1\2'}, {'a.bin': b'\0\1\3'})
        code, out, err = self.repo.run('HEAD')
        self.assertIn('File-level problems (2):\n  a.bin: binary file; not compared\n'
                      '  (diff): no line was moved\n', out)


class ModeTests(RepoTestCase):
    def test_staged(self):
        self.repo.write('a.m', 'start\nf();\nend\n')
        head = self.repo.commit()
        self.repo.write('a.m', 'start\nend\n')
        self.repo.write('b.m', 'f();\n')
        self.repo.git('add', '-A')
        self.repo.write('c.m', 'unstaged and untracked\n')
        self.repo.write('a.m', 'start\nend\nunstaged\n')
        code, j, err = self.repo.run_json('--staged')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertEqual(j['compared'], {'mode': 'staged', 'old': head, 'new': 'index'})
        self.assertEqual(j['moved_blocks'], [block('a.m', 2, 2, 'b.m', 1, 1)])

    def test_staged_text_says_what_is_compared(self):
        self.repo.write('a.m', 'start\nf();\nend\n')
        head = self.repo.commit()
        self.repo.write('a.m', 'start\nend\nf();\n')
        self.repo.git('add', '-A')
        code, out, err = self.repo.run('--staged')
        self.assertEqual(code, 0)
        self.assertIn('Compared: HEAD (%s) to the index (staged changes only; unstaged '
                      'and untracked files are ignored)\n' % head, out)

    def test_staged_unborn_head(self):
        self.repo.write('a.m', 'x\n')
        self.repo.git('add', '-A')
        code, j, err = self.repo.run_json('--staged')
        self.assertEqual(code, 1)
        self.assertEqual(j['compared']['old'], self.repo.git('hash-object', '-t', 'tree', '/dev/null'))
        self.assertEqual(j['unaccounted_added'], [{'path': 'a.m', 'line': 1, 'text': 'x'}])

    def test_staged_unmerged_is_error(self):
        self.repo.write('a.m', 'base\n')
        self.repo.commit()
        self.repo.git('checkout', '-q', '-b', 'other')
        self.repo.write('a.m', 'other\n')
        self.repo.commit()
        self.repo.git('checkout', '-q', '-')
        self.repo.write('a.m', 'main\n')
        self.repo.commit()
        self.repo.git('merge', '-q', 'other', check=False)
        code, out, err = self.repo.run('--staged')
        self.assertEqual(code, 2)
        self.assertIn('unmerged', err)
        self.assertEqual(out, '')

    def test_range(self):
        self.repo.write('a.m', 'start\nf();\nend\n')
        first = self.repo.commit()
        self.repo.write('a.m', 'start\nend\n')
        self.repo.commit()
        self.repo.write('b.m', 'f();\n')
        last = self.repo.commit()
        code, j, err = self.repo.run_json(first, last)
        self.assertEqual(code, 0)
        self.assertEqual(j['compared'], {'mode': 'range', 'old': first, 'new': last})
        code, out, err = self.repo.run(first, 'HEAD')
        self.assertIn('Compared: %s to %s\n' % (first, last), out)

    def test_commit_text_says_what_is_compared(self):
        self.repo.write('a.m', 'start\nf();\nend\n')
        first = self.repo.commit()
        self.repo.write('a.m', 'start\nend\nf();\n')
        second = self.repo.commit()
        code, out, err = self.repo.run('HEAD')
        self.assertIn('Compared: commit %s with its parent %s\n' % (second, first), out)

    def test_merge_commit_is_error(self):
        self.repo.write('a.m', 'base\n')
        self.repo.commit()
        self.repo.git('checkout', '-q', '-b', 'other')
        self.repo.write('b.m', 'other\n')
        self.repo.commit()
        self.repo.git('checkout', '-q', '-')
        self.repo.write('c.m', 'main\n')
        self.repo.commit()
        self.repo.git('merge', '-q', '--no-edit', 'other')
        code, out, err = self.repo.run('HEAD')
        self.assertEqual(code, 2)
        self.assertIn('merge commit', err)
        self.assertEqual(out, '')
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 2)
        self.assertEqual(j, None)

    def test_bad_revision(self):
        self.repo.write('a.m', 'x\n')
        self.repo.commit()
        code, out, err = self.repo.run('nosuchrev')
        self.assertEqual(code, 2)
        self.assertIn('nosuchrev', err)

    def test_tree_is_not_a_commit(self):
        self.repo.write('a.m', 'x\n')
        self.repo.commit()
        code, out, err = self.repo.run('HEAD^{tree}')
        self.assertEqual(code, 2)

    def test_no_arguments(self):
        code, out, err = self.repo.run()
        self.assertEqual(code, 2)

    def test_too_many_arguments(self):
        code, out, err = self.repo.run('a', 'b', 'c')
        self.assertEqual(code, 2)

    def test_staged_and_revision(self):
        code, out, err = self.repo.run('--staged', 'HEAD')
        self.assertEqual(code, 2)

    def test_not_a_repository(self):
        d = tempfile.mkdtemp(prefix='pure-move-norepo-')
        try:
            proc = subprocess.run([sys.executable, '-B', TOOL, '--repo', d, 'HEAD'],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  env=dict(GIT_ENV, GIT_CEILING_DIRECTORIES=os.path.dirname(d)))
            self.assertEqual(proc.returncode, 2)
        finally:
            shutil.rmtree(d)

    def test_repo_option(self):
        self.repo.write('a.m', 'start\nf();\nend\n')
        self.repo.commit()
        self.repo.write('a.m', 'start\nend\nf();\n')
        self.repo.commit()
        proc = subprocess.run([sys.executable, '-B', TOOL, '--repo', self.repo.root, 'HEAD'],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=self.repo.dir)
        self.assertEqual(proc.returncode, 0)

    def test_bad_declaration_syntax(self):
        self.repo.write('a.m', 'x\n')
        self.repo.commit()
        code, out, err = self.repo.run('HEAD', '--allow-added', 'a.m')
        self.assertEqual(code, 2)
        self.assertIn('a.m', err)

    def test_declared_line_that_is_not_added(self):
        self.repo.write('a.m', 'start\nf();\nend\n')
        self.repo.commit()
        self.repo.write('a.m', 'start\nend\nf();\n')
        self.repo.commit()
        code, out, err = self.repo.run('HEAD', '--allow-added', 'a.m:1-3')
        self.assertEqual(code, 2)
        self.assertIn('--allow-added names lines that are not added lines of this diff', err)
        self.assertIn('a.m:1', err)
        self.assertIn('a.m:2', err)
        self.assertNotIn('a.m:3 ', err)
        self.assertEqual(out, '')

    def test_declared_removed_line_that_is_not_removed(self):
        self.repo.write('a.m', 'start\nf();\nend\n')
        self.repo.commit()
        self.repo.write('a.m', 'start\nend\nf();\n')
        self.repo.commit()
        code, out, err = self.repo.run('HEAD', '--allow-removed', 'a.m:1')
        self.assertEqual(code, 2)
        self.assertIn('--allow-removed names lines that are not removed lines of this diff', err)
        self.assertIn('a.m:1', err)

    def test_declared_line_in_unknown_file(self):
        self.repo.write('a.m', 'start\nf();\nend\n')
        self.repo.commit()
        self.repo.write('a.m', 'start\nend\nf();\n')
        self.repo.commit()
        code, out, err = self.repo.run('HEAD', '--allow-added', 'zz.m:1')
        self.assertEqual(code, 2)
        self.assertIn('zz.m:1', err)

    def test_declared_line_in_renamed_file_is_an_error(self):
        # A renamed file is not compared, so it has no added lines to declare.
        content = ''.join('line %d\n' % i for i in range(20))
        self.repo.write('a.m', content)
        self.repo.commit()
        self.repo.remove('a.m')
        self.repo.write('b.m', content + 'extra\n')
        self.repo.commit()
        code, out, err = self.repo.run('HEAD', '--allow-added', 'b.m:21')
        self.assertEqual(code, 2)
        self.assertEqual(out, '')
        self.assertIn('--allow-added names lines that are not added lines of this diff: b.m:21', err)


# Tests added for the second review round.

class CollectRefusalTests(unittest.TestCase):
    """A change kind that is never accepted is reported without reading its content."""
    S = '1' * 40
    T = '2' * 40

    class NoContentGit(FakeGit):
        def sizes(self, shas):
            if shas:
                raise AssertionError('size read for %s' % shas)
            return {}

        def read_blobs(self, shas):
            if shas:
                raise AssertionError('content read for %s' % shas)
            return {}

    def collect(self, meta, paths):
        raw = (meta + '\0' + '\0'.join(paths) + '\0').encode()
        return collect4(self.NoContentGit(raw, {}), 'range', 'o', 'n')

    def test_rename_is_not_read(self):
        files, removed, added, problems = self.collect(
            ':100644 100644 %s %s R090' % (self.S, self.T), ['old.m', 'new.m'])
        self.assertEqual(problems, [{'path': 'new.m', 'problem': 'renamed from old.m; not compared'}])
        self.assertEqual((removed, added), ([], []))

    def test_mode_change_is_not_read(self):
        files, removed, added, problems = self.collect(
            ':100644 100755 %s %s M' % (self.S, self.T), ['a.sh'])
        self.assertEqual(problems, [{'path': 'a.sh',
                                     'problem': 'mode changed from 100644 to 100755; not compared'}])
        self.assertEqual((removed, added), ([], []))


class CompletenessTests(unittest.TestCase):
    """The patch must account for every difference between the old and new content."""
    S = '1' * 40
    T = '2' * 40

    def test_patch_that_hides_a_hunk_is_an_error(self):
        raw = (':100644 100644 %s %s M\0a.m\0' % (self.S, self.T)).encode()
        git = FakeGit(raw, {self.S: b'a\nb\nc\n', self.T: b'a\nB\nc\n'}, patch=b'')
        with self.assertRaises(pm.ToolError) as cm:
            collect4(git, 'range', 'o', 'n')
        self.assertIn('a.m', str(cm.exception))

    def test_patch_that_hides_one_of_two_hunks_is_an_error(self):
        raw = (':100644 100644 %s %s M\0a.m\0' % (self.S, self.T)).encode()
        git = FakeGit(raw, {self.S: b'a\nb\nc\nd\n', self.T: b'A\nb\nc\nD\n'},
                      patch=b'@@ -1 +1 @@\n-a\n+A\n')
        with self.assertRaises(pm.ToolError):
            collect4(git, 'range', 'o', 'n')

    def test_complete_patch_is_accepted(self):
        raw = (':100644 100644 %s %s M\0a.m\0' % (self.S, self.T)).encode()
        git = FakeGit(raw, {self.S: b'a\nb\nc\nd\n', self.T: b'A\nb\nc\nD\n'},
                      patch=b'@@ -1 +1 @@\n-a\n+A\n@@ -4 +4 @@\n-d\n+D\n')
        files, removed, added, problems = collect4(git, 'range', 'o', 'n')
        self.assertEqual(removed, [L('a.m', 1, b'a'), L('a.m', 4, b'd')])
        self.assertEqual(added, [L('a.m', 1, b'A'), L('a.m', 4, b'D')])

    def test_check_complete_function(self):
        pm.check_complete([b'a', b'b', b'c'], [b'a', b'c', b'x'], [(2, b'b')], [(3, b'x')], 'p')
        with self.assertRaises(pm.ToolError):
            pm.check_complete([b'a', b'b', b'c'], [b'a', b'c', b'x'], [(2, b'b')], [], 'p')
        with self.assertRaises(pm.ToolError):
            pm.check_complete([b'a', b'b'], [b'a', b'c'], [], [], 'p')


class AnchorMatchTests(unittest.TestCase):
    """Pairs grow from lines that occur once on each side; the rest pair in line order."""

    def test_repeated_lines_pair_in_line_order(self):
        # "}" occurs twice on each side and there is no anchor: the first
        # removed copy takes the first added copy.
        r = [L('a.m', 1, b'}'), L('a.m', 5, b'}')]
        a = [L('b.m', 3, b'}'), L('c.m', 1, b'}')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 1, 'b.m', 3, 3),
                                           block('a.m', 5, 5, 'c.m', 1, 1)])

    def test_anchor_extends_backward_over_repeated_lines(self):
        # Line order alone would give the first "}" of a.m to b.m:1. The
        # anchor "x" at a.m:11 grows backward over a.m:10 and takes b.m:5.
        r = [L('a.m', 2, b'}'), L('a.m', 10, b'}'), L('a.m', 11, b'x')]
        a = [L('b.m', 1, b'}'), L('b.m', 5, b'}'), L('b.m', 6, b'x')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 2, 2, 'b.m', 1, 1),
                                           block('a.m', 10, 11, 'b.m', 5, 6)])

    def test_anchor_extends_forward_over_repeated_lines(self):
        r = [L('a.m', 1, b'x'), L('a.m', 2, b'}'), L('a.m', 9, b'}')]
        a = [L('b.m', 1, b'}'), L('b.m', 7, b'x'), L('b.m', 8, b'}')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 2, 'b.m', 7, 8),
                                           block('a.m', 9, 9, 'b.m', 1, 1)])

    def test_earlier_anchor_claims_shared_line_first(self):
        # Anchors x (a.m:1) and y (a.m:11) could both grow over a "}" whose
        # only added copy is b.m:2; the anchor with the earlier removed line
        # takes it.
        r = [L('a.m', 1, b'x'), L('a.m', 2, b'}'), L('a.m', 10, b'}'), L('a.m', 11, b'y')]
        a = [L('b.m', 1, b'x'), L('b.m', 2, b'}'), L('b.m', 3, b'y')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 2, 'b.m', 1, 2),
                                           block('a.m', 11, 11, 'b.m', 3, 3)])
        self.assertEqual(m.unmatched_removed, [L('a.m', 10, b'}')])

    def test_line_unique_on_one_side_only_is_not_an_anchor(self):
        # "x" occurs once among removed lines and twice among added lines, so
        # it pairs in line order: a.m:5 takes b.m:1, not the b.m:9 next to "y".
        r = [L('a.m', 5, b'x'), L('a.m', 6, b'y')]
        a = [L('b.m', 1, b'x'), L('b.m', 9, b'x'), L('b.m', 10, b'y')]
        m = pm.match_lines(r, a)
        # y anchors at b.m:10 and grows backward over a.m:5 and b.m:9.
        self.assertEqual(m.blocks_json(), [block('a.m', 5, 6, 'b.m', 9, 10)])
        self.assertEqual(m.unmatched_added, [L('b.m', 1, b'x')])

    def test_blank_line_of_spaces_matches_empty_line(self):
        m = pm.match_lines([L('a.m', 1, b'  \t')], [L('b.m', 1, b'')])
        self.assertEqual(m.blocks_json(), [block('a.m', 1, 1, 'b.m', 1, 1)])


class MatchScaleTests(unittest.TestCase):
    def test_memory_does_not_grow_with_pairs_of_repeated_lines(self):
        # 600 copies of "}" on each side, each in its own run. Enumerating
        # every pair of equal lines would allocate 360,000 candidates.
        import tracemalloc
        r = [L('a.m', 2 * k + 1, b'}') for k in range(600)]
        a = [L('b.m', 2 * k + 1, b'}') for k in range(600)]
        tracemalloc.start()
        try:
            m = pm.match_lines(r, a)
            peak = tracemalloc.get_traced_memory()[1]
        finally:
            tracemalloc.stop()
        self.assertEqual(m.moved_line_count, 600)
        self.assertLess(peak, 2 * 1024 * 1024)


class RunNoticeTests(unittest.TestCase):
    def test_split_and_gathered_runs(self):
        # The c3 case from the review: a.m:2 is g's C(); a.m:5-7 is f's
        # A(); B(); C(). b.m:2-4 is C(); A(); B(); c.m:2 is C().
        r = [L('a.m', 2, b'C();'), L('a.m', 5, b'A();'), L('a.m', 6, b'B();'),
             L('a.m', 7, b'C();')]
        a = [L('b.m', 2, b'C();'), L('b.m', 3, b'A();'), L('b.m', 4, b'B();'),
             L('c.m', 2, b'C();')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.blocks_json(), [block('a.m', 2, 2, 'b.m', 2, 2),
                                           block('a.m', 5, 6, 'b.m', 3, 4),
                                           block('a.m', 7, 7, 'c.m', 2, 2)])
        self.assertEqual(m.order_problems, [])
        R = lambda p, s, e: {'path': p, 'start': s, 'end': e}
        self.assertEqual(m.runs_json(), [
            {'removed': R('a.m', 2, 2), 'lands_in': [R('b.m', 2, 4)]},
            {'removed': R('a.m', 5, 7), 'lands_in': [R('b.m', 2, 4), R('c.m', 2, 2)]}])
        self.assertEqual(m.run_notices_json(), [
            {'kind': 'split', 'run': R('a.m', 5, 7), 'runs': [R('b.m', 2, 4), R('c.m', 2, 2)]},
            {'kind': 'gathered', 'run': R('b.m', 2, 4), 'runs': [R('a.m', 2, 2), R('a.m', 5, 7)]}])

    def test_one_block_to_one_place_has_no_notice(self):
        r = [L('a.m', 2, b'a'), L('a.m', 3, b'b')]
        a = [L('b.m', 7, b'a'), L('b.m', 8, b'b')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.run_notices_json(), [])
        self.assertEqual(m.runs_json(), [
            {'removed': {'path': 'a.m', 'start': 2, 'end': 3},
             'lands_in': [{'path': 'b.m', 'start': 7, 'end': 8}]}])

    def test_removed_run_with_no_moved_line_lands_nowhere(self):
        m = pm.match_lines([L('a.m', 2, b'a')], [L('b.m', 1, b'z')])
        self.assertEqual(m.runs_json(), [
            {'removed': {'path': 'a.m', 'start': 2, 'end': 2}, 'lands_in': []}])
        self.assertEqual(m.run_notices_json(), [])


C3_BEFORE = {'a.m': 'void g() {\n    C();\n}\nvoid f() {\n    A();\n    B();\n    C();\n}\n'}
C3_AFTER = {'a.m': 'void g() {\n}\nvoid f() {\n}\n', 'b.m': 'void h() {\nC();\nA();\nB();\n}\n',
            'c.m': 'void k() {\nC();\n}\n'}
C3_DECL = ['--allow-added', 'b.m:1', '--allow-added', 'b.m:5', '--allow-added', 'c.m:1',
           '--allow-added', 'c.m:3']
C6_BEFORE = {'a.m': 'void f() {\n    a = 1;\n    P();\n    Q();\n}\nvoid g() {\n    a = 2;\n    R();\n}\n'}
C6_AFTER = {'a.m': 'void f() {\n    f2();\n}\nvoid g() {\n    g2();\n}\n',
            'b.m': 'void f2() {\na = 2;\nP();\nQ();\n}\nvoid g2() {\na = 1;\nR();\n}\n'}
C6_DECL = ['--allow-added', 'a.m:2', '--allow-added', 'a.m:5', '--allow-added', 'b.m:1',
           '--allow-added', 'b.m:5-6', '--allow-added', 'b.m:9']


class StrictRunsTests(RepoTestCase):
    def test_rotation_hidden_by_identical_line_is_a_notice(self):
        self.two_commits(C3_BEFORE, C3_AFTER)
        code, out, err = self.repo.run('HEAD', *C3_DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertIn('Moved blocks (3):\n'
                      '  a.m:2-2 -> b.m:2-2 (1 line)\n'
                      '  a.m:5-6 -> b.m:3-4 (2 lines)\n'
                      '  a.m:7-7 -> c.m:2-2 (1 line)\n', out)
        self.assertIn('Where each removed run went (2):\n'
                      '  a.m:2-2 -> b.m:2-4\n'
                      '  a.m:5-7 -> b.m:2-4, c.m:2-2\n', out)
        self.assertIn('Run notices, failures only with --strict-runs (2):\n'
                      '  a.m:5-7 is split across 2 added runs: b.m:2-4, c.m:2-2\n'
                      '  b.m:2-4 gathers lines from 2 removed runs: a.m:2-2, a.m:5-7\n', out)

    def test_rotation_hidden_by_identical_line_fails_with_strict_runs(self):
        self.two_commits(C3_BEFORE, C3_AFTER)
        code, j, err = self.repo.run_json('HEAD', '--strict-runs', *C3_DECL)
        self.assertEqual(code, 1)
        self.assertEqual(j['pure_move'], False)
        self.assertEqual(j['strict_runs'], True)
        self.assertEqual(j['counts']['run_notices'], 2)
        self.assertEqual([n['kind'] for n in j['run_notices']], ['split', 'gathered'])

    def test_swapped_first_lines_fail_with_strict_runs(self):
        self.two_commits(C6_BEFORE, C6_AFTER)
        code, j, err = self.repo.run_json('HEAD', *C6_DECL)
        self.assertEqual(code, 0)
        self.assertEqual(j['strict_runs'], False)
        self.assertEqual(j['moved_blocks'], [block('a.m', 2, 2, 'b.m', 7, 7),
                                             block('a.m', 3, 4, 'b.m', 3, 4),
                                             block('a.m', 7, 7, 'b.m', 2, 2),
                                             block('a.m', 8, 8, 'b.m', 8, 8)])
        code, j, err = self.repo.run_json('HEAD', '--strict-runs', *C6_DECL)
        self.assertEqual(code, 1)
        self.assertEqual(len(j['run_notices']), 4)

    def test_single_extraction_passes_with_strict_runs(self):
        self.two_commits({'Widget.m': fixture('widget_before.m')},
                         {'Widget.m': fixture('widget_extracted.m')})
        code, out, err = self.repo.run('HEAD', '--strict-runs', '--allow-added', 'Widget.m:5',
                                       '--allow-added', 'Widget.m:9-10',
                                       '--allow-added', 'Widget.m:14')
        self.assertEqual(code, 0)
        self.assertIn('Run notices, failures only with --strict-runs (0):\n  none\n', out)

    def test_rules_describe_the_limit_of_reorder_detection(self):
        text = ' '.join(pm.RULES)
        self.assertIn('A reordering is reported only for the pairing chosen', text)
        self.assertIn('identical lines elsewhere in the diff can make a reordered block look '
                      'like two moves', text)
        self.assertIn('--strict-runs', text)
        self.assertIn('A reordering is reported only for the pairing chosen',
                      ' '.join(pm.NOT_CHECKED))


class GitOptionTests(RepoTestCase):
    """Configuration and attributes that change git's patch must not change the verdict."""

    DECL = ['--allow-added', 'Widget.m:5', '--allow-added', 'Widget.m:9-10',
            '--allow-added', 'Widget.m:14']

    def extraction(self):
        return self.two_commits({'Widget.m': fixture('widget_before.m')},
                                {'Widget.m': fixture('widget_extracted.m')})

    def attributes(self, text):
        path = os.path.join(self.repo.root, '.git', 'info', 'attributes')
        if not os.path.isdir(os.path.dirname(path)):
            os.makedirs(os.path.dirname(path))
        with open(path, 'w') as f:
            f.write(text)

    def test_inter_hunk_context(self):
        self.extraction()
        self.repo.git('config', 'diff.interHunkContext', '10')
        code, out, err = self.repo.run('HEAD', *self.DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_binary_attribute(self):
        self.extraction()
        self.attributes('* binary\n')
        code, out, err = self.repo.run('HEAD', *self.DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_minus_diff_attribute_in_gitattributes(self):
        self.two_commits({'.gitattributes': '* -diff\n', 'Widget.m': fixture('widget_before.m')},
                         {'Widget.m': fixture('widget_extracted.m')})
        code, out, err = self.repo.run('HEAD', *self.DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_textconv_is_not_used(self):
        self.extraction()
        self.attributes('* diff=upper\n')
        self.repo.git('config', 'diff.upper.textconv', 'tr a-z A-Z <')
        code, out, err = self.repo.run('HEAD', *self.DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertIn('Widget.m:5: - (void)updateField {', out)

    def test_external_diff_is_not_used(self):
        self.extraction()
        self.repo.git('config', 'diff.external', 'false')
        code, out, err = self.repo.run('HEAD', *self.DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_nul_byte_is_still_binary(self):
        self.two_commits({'a.m': b'x\0y\n'}, {'a.m': b'x\0z\n'})
        self.attributes('* text diff\n')
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'][0], {'path': 'a.m', 'problem': 'binary file; not compared'})


class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.saved = getattr(pm, 'MAX_CHANGED_LINES', None)
        self.repo = Repo()

    def tearDown(self):
        pm.MAX_CHANGED_LINES = self.saved
        self.repo.cleanup()

    def change(self):
        self.repo.write('a.m', 'start\nf();\ng();\nend\n')
        self.repo.commit()
        self.repo.write('a.m', 'start\nend\n')
        self.repo.write('b.m', 'f();\ng();\n')
        self.repo.commit()
        return pm.Git(self.repo.root)

    def test_budget_value_and_rule(self):
        self.assertEqual(pm.MAX_CHANGED_LINES, 500000)
        self.assertIn('500,000', ' '.join(pm.RULES))

    def test_at_budget_is_checked(self):
        git = self.change()
        pm.MAX_CHANGED_LINES = 4
        j = pm.check(git, 'commit', ['HEAD'], [], [])
        self.assertEqual(j['exit_code'], 0)

    def test_over_budget_is_an_error(self):
        git = self.change()
        pm.MAX_CHANGED_LINES = 3
        with self.assertRaises(pm.ToolError) as cm:
            pm.check(git, 'commit', ['HEAD'], [], [])
        self.assertIn('more than 3 changed lines', str(cm.exception))


class DeclarationRangeTests(RepoTestCase):
    def change(self):
        self.two_commits({'a.m': 'start\nf();\nend\n'}, {'a.m': 'start\nend\n', 'b.m': 'f();\n'})

    def test_huge_range_lists_a_capped_error(self):
        self.change()
        code, out, err = self.repo.run('HEAD', '--allow-added', 'b.m:1-2000000')
        self.assertEqual(code, 2)
        self.assertIn('b.m:2, b.m:3', err)
        self.assertIn('and 1999979 more', err)
        self.assertLess(len(err), 2000)

    def test_enormous_range_is_not_materialized(self):
        self.change()
        code, out, err = self.repo.run('HEAD', '--allow-added', 'b.m:1-200000000')
        self.assertEqual(code, 2)
        self.assertIn('and 199999979 more', err)

    def test_path_beginning_with_dash(self):
        self.two_commits({'-a.m': 'start\nf();\nend\n'}, {'-a.m': 'start\nend\nnew\nf();\n'})
        code, j, err = self.repo.run_json('HEAD', '--allow-added=-a.m:3')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertEqual(j['declared_added'], [{'path': '-a.m', 'line': 3, 'text': 'new'}])

    def test_dash_form_is_documented(self):
        self.assertIn('--allow-added=PATH:N', pm.__doc__)
        self.assertIn('--allow-added=PATH:N', ' '.join(pm.RULES))


class TextEscapingTests(RepoTestCase):
    def test_newline_in_path_is_escaped(self):
        self.two_commits({'x\ny.m': 'start\nf();\nend\n'}, {'x\ny.m': 'start\nend\nf();\n'})
        code, out, err = self.repo.run('HEAD')
        self.assertEqual(code, 0)
        self.assertIn('  M x\\x0ay.m\n', out)
        self.assertIn('  x\\x0ay.m:2-2 -> x\\x0ay.m:3-3 (1 line)\n', out)
        self.assertNotIn('x\ny.m', out)

    def test_whitespace_only_line_rule(self):
        text = ' '.join(pm.RULES)
        self.assertIn('A line of only spaces and tabs matches an empty line.', text)


class GrowthStopsAtRunTests(unittest.TestCase):
    """Growth from an anchor never crosses into another run; the line beyond pairs in step 3."""

    def test_backward_stops_at_removed_run(self):
        # a.m:1 and a.m:3 are different removed runs, so x does not grow back
        # over a.m:1, and z pairs first with first: a.m:1 with a2.m:1.
        r = [L('a.m', 1, b'z'), L('a.m', 3, b'x')]
        a = [L('a2.m', 1, b'z'), L('b.m', 1, b'z'), L('b.m', 2, b'x')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.unmatched_added, [L('b.m', 1, b'z')])

    def test_backward_stops_at_added_run(self):
        r = [L('a.m', 1, b'z'), L('a.m', 2, b'x')]
        a = [L('a2.m', 1, b'z'), L('b.m', 1, b'z'), L('b.m', 5, b'x')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.unmatched_added, [L('b.m', 1, b'z')])

    def test_forward_stops_at_removed_run(self):
        r = [L('a.m', 1, b'x'), L('a.m', 3, b'z')]
        a = [L('a2.m', 1, b'z'), L('b.m', 1, b'x'), L('b.m', 2, b'z')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.unmatched_added, [L('b.m', 2, b'z')])

    def test_forward_stops_at_added_run(self):
        r = [L('a.m', 1, b'x'), L('a.m', 2, b'z')]
        a = [L('a2.m', 1, b'z'), L('b.m', 1, b'x'), L('b.m', 3, b'z')]
        m = pm.match_lines(r, a)
        self.assertEqual(m.unmatched_added, [L('b.m', 3, b'z')])


class LineCountTests(unittest.TestCase):
    def test_last_line_without_newline_counts(self):
        self.assertEqual(pm.line_count(b''), 0)
        self.assertEqual(pm.line_count(b'a\nb'), 2)
        self.assertEqual(pm.line_count(b'a\nb\n'), 2)
        self.assertEqual(pm.line_count(b'\n'), 1)


class TextEscapingMoreTests(RepoTestCase):
    def test_newline_in_path_of_line_and_problem(self):
        self.two_commits({'o\nld.m': ''.join('line %d\n' % i for i in range(20))},
                         {'o\nld.m': None, 'n.m': ''.join('line %d\n' % i for i in range(20)),
                          'x\ny.m': 'q\n'})
        code, out, err = self.repo.run('HEAD')
        self.assertEqual(code, 1)
        self.assertIn('  x\\x0ay.m:1: q\n', out)
        self.assertIn('  n.m: renamed from o\\x0ald.m; not compared\n', out)
        self.assertNotIn('o\nld.m', out)
        self.assertNotIn('x\ny.m', out)


# Tests added for the third review round: the --extract mode, --show-lines,
# final newlines of moved lines, and the cost of many files.

def lines_of(*rows):
    return ''.join(r + '\n' for r in rows)


# The reviewer's B1 case: the tail of -f moves into a new method -g placed
# right after it, in the same file. git keeps most of the block as unchanged
# context (the old method's closing brace matches the new method's).
B1_BEFORE = lines_of('- (void)f {', '    pre();', '    if (x) {', '        a();', '        b();',
                     '        c();', '    }', '}')
B1_AFTER = lines_of('- (void)f {', '    pre();', '    [self g];', '}', '', '- (void)g {',
                    '    if (x) {', '        a();', '        b();', '        c();', '    }', '}')
B1_SWAPPED = lines_of('- (void)f {', '    pre();', '    [self g];', '}', '', '- (void)g {',
                      '    if (x) {', '        a();', '        c();', '        b();', '    }', '}')
B1_DECL = ['--extract', 'a.m:3-7=a.m:7-11', '--allow-added=a.m:3-6']


def mline(path, line, text):
    return {'path': path, 'line': line, 'text': text}


class ExtractModeTests(RepoTestCase):
    def extract(self, before, after, *args):
        self.two_commits(before, after)
        code, j, err = self.repo.run_json('HEAD', *args)
        return code, j, err

    def test_reviewer_swapped_case_fails(self):
        code, j, err = self.extract({'a.m': B1_BEFORE}, {'a.m': B1_SWAPPED}, *B1_DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['check'], 'extract')
        self.assertEqual(j['pure_move'], False)
        self.assertEqual(j['extractions'][0]['mismatches'], [
            {'source': mline('a.m', 5, '        b();'), 'destination': mline('a.m', 9, '        c();')},
            {'source': mline('a.m', 6, '        c();'), 'destination': mline('a.m', 10, '        b();')}])
        self.assertEqual(j['unaccounted_removed'], [])
        self.assertEqual(j['unaccounted_added'], [])

    def test_reviewer_swapped_case_text(self):
        self.two_commits({'a.m': B1_BEFORE}, {'a.m': B1_SWAPPED})
        code, out, err = self.repo.run('HEAD', *B1_DECL)
        self.assertEqual(code, 1)
        self.assertIn('Result: NOT A PURE MOVE (exit 1)', out)
        self.assertIn('Mismatched lines in extracted blocks (2):\n'
                      '  a.m:5 -> a.m:9:\n'
                      '    old:         b();\n'
                      '    new:         c();\n', out)

    def test_same_file_extraction_passes(self):
        code, j, err = self.extract({'a.m': B1_BEFORE}, {'a.m': B1_AFTER}, *B1_DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertEqual(j['pure_move'], True)
        self.assertEqual(j['extractions'], [{
            'source': {'path': 'a.m', 'start': 3, 'end': 7},
            'destination': {'path': 'a.m', 'start': 7, 'end': 11},
            'lines': 5, 'destination_lines': 5, 'mismatches': []}])
        self.assertEqual(j['declared_added'], [mline('a.m', 3, '    [self g];'), mline('a.m', 4, '}'),
                                               mline('a.m', 5, ''), mline('a.m', 6, '- (void)g {')])
        self.assertEqual(j['file_problems'], [])

    def test_same_file_extraction_text(self):
        self.two_commits({'a.m': B1_BEFORE}, {'a.m': B1_AFTER})
        code, out, err = self.repo.run('HEAD', *B1_DECL)
        self.assertEqual(code, 0)
        self.assertIn('Result: PURE MOVE (exit 0)', out)
        self.assertIn('Extracted blocks (1):\n  a.m:3-7 -> a.m:7-11 (5 lines)\n', out)
        self.assertIn('Declared added lines, not checked (4):\n  a.m:3:     [self g];\n', out)
        for rule in pm.EXTRACT_RULES:
            self.assertIn(rule, out)
        for item in pm.NOT_CHECKED_EXTRACT:
            self.assertIn(item, out)

    def test_two_line_swap_of_first_and_last_lines(self):
        after = B1_AFTER.replace('        a();\n        b();\n        c();\n',
                                 '        c();\n        b();\n        a();\n')
        code, j, err = self.extract({'a.m': B1_BEFORE}, {'a.m': after}, *B1_DECL)
        self.assertEqual(code, 1)
        self.assertEqual([(x['source']['line'], x['destination']['line'])
                          for x in j['extractions'][0]['mismatches']], [(4, 8), (6, 10)])

    def test_dropped_line(self):
        after = B1_AFTER.replace('        b();\n', '')
        code, j, err = self.extract({'a.m': B1_BEFORE}, {'a.m': after},
                                    '--extract', 'a.m:3-7=a.m:7-10', '--allow-added=a.m:3-6')
        self.assertEqual(code, 1)
        e = j['extractions'][0]
        self.assertEqual((e['lines'], e['destination_lines']), (5, 4))
        self.assertEqual(j['counts']['length_mismatches'], 1)

    def test_dropped_line_text(self):
        after = B1_AFTER.replace('        b();\n', '')
        self.two_commits({'a.m': B1_BEFORE}, {'a.m': after})
        code, out, err = self.repo.run('HEAD', '--extract', 'a.m:3-7=a.m:7-10',
                                       '--allow-added=a.m:3-6')
        self.assertEqual(code, 1)
        self.assertIn('  a.m:3-7 -> a.m:7-10 (5 lines; the destination has 4)\n', out)

    def test_duplicated_line(self):
        after = B1_AFTER.replace('        b();\n', '        b();\n        b();\n')
        code, j, err = self.extract({'a.m': B1_BEFORE}, {'a.m': after},
                                    '--extract', 'a.m:3-7=a.m:7-12', '--allow-added=a.m:3-6')
        self.assertEqual(code, 1)
        self.assertEqual(j['counts']['length_mismatches'], 1)
        # Declared with equal lengths instead, the extra line shows elsewhere.
        code, j, err = self.repo.run_json('HEAD', '--extract', 'a.m:3-7=a.m:7-11',
                                          '--allow-added=a.m:3-6')
        self.assertEqual(code, 1)
        self.assertEqual(j['unaccounted_added'], [mline('a.m', 12, '    }')])
        self.assertEqual(j['unaccounted_removed'], [])

    def test_edit_outside_block(self):
        after = B1_AFTER.replace('    pre();', '    pre(1);')
        code, j, err = self.extract({'a.m': B1_BEFORE}, {'a.m': after}, *B1_DECL)
        self.assertEqual(code, 1)
        self.assertEqual(j['unaccounted_removed'], [mline('a.m', 2, '    pre();')])
        self.assertEqual(j['unaccounted_added'], [mline('a.m', 2, '    pre(1);')])
        self.assertEqual(j['extractions'][0]['mismatches'], [])

    def test_edit_outside_block_text(self):
        after = B1_AFTER.replace('    pre();', '    pre(1);')
        self.two_commits({'a.m': B1_BEFORE}, {'a.m': after})
        code, out, err = self.repo.run('HEAD', *B1_DECL)
        self.assertEqual(code, 1)
        self.assertIn('Unaccounted removed lines (1):\n  a.m:2:     pre();\n', out)
        self.assertIn('Unaccounted added lines (1):\n  a.m:2:     pre(1);\n', out)

    def test_edit_inside_block(self):
        after = B1_AFTER.replace('        a();', '        a(1);')
        code, j, err = self.extract({'a.m': B1_BEFORE}, {'a.m': after}, *B1_DECL)
        self.assertEqual(code, 1)
        self.assertEqual(j['extractions'][0]['mismatches'], [
            {'source': mline('a.m', 4, '        a();'), 'destination': mline('a.m', 8, '        a(1);')}])

    def test_indentation_change_inside_block_passes(self):
        after = lines_of('- (void)f {', '    pre();', '    [self g];', '}', '', '- (void)g {',
                         'if (x) {', '\ta();', '    b();', '  c();', '}', '}')
        code, j, err = self.extract({'a.m': B1_BEFORE}, {'a.m': after}, *B1_DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_indentation_change_outside_block_fails(self):
        after = B1_AFTER.replace('    pre();', '\tpre();')
        code, j, err = self.extract({'a.m': B1_BEFORE}, {'a.m': after}, *B1_DECL)
        self.assertEqual(code, 1)
        self.assertEqual(j['unaccounted_removed'], [mline('a.m', 2, '    pre();')])
        self.assertEqual(j['unaccounted_added'], [mline('a.m', 2, '\tpre();')])

    TWO_BEFORE = lines_of('void f() {', '    p();', '    a1();', '    a2();', '    q();', '    b1();',
                          '    b2();', '}')
    TWO_AFTER = lines_of('void f() {', '    p();', '    A();', '    q();', '    B();', '}',
                         'void A() {', '    a1();', '    a2();', '}', 'void B() {', '    b1();',
                         '    b2();', '}')
    TWO_DECL = ['--extract', 'a.m:3-4=a.m:8-9', '--extract', 'a.m:6-7=a.m:12-13',
                '--allow-added=a.m:3', '--allow-added=a.m:5', '--allow-added=a.m:7',
                '--allow-added=a.m:10-11', '--allow-added=a.m:14']

    def test_two_extractions(self):
        code, j, err = self.extract({'a.m': self.TWO_BEFORE}, {'a.m': self.TWO_AFTER},
                                    *self.TWO_DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertEqual(j['counts']['extractions'], 2)
        self.assertEqual(j['counts']['extracted_lines'], 4)

    def test_two_extractions_with_lines_swapped_across_them(self):
        after = self.TWO_AFTER.replace('    a2();', 'X').replace('    b2();', '    a2();') \
            .replace('X', '    b2();')
        code, j, err = self.extract({'a.m': self.TWO_BEFORE}, {'a.m': after}, *self.TWO_DECL)
        self.assertEqual(code, 1)
        self.assertEqual([len(e['mismatches']) for e in j['extractions']], [1, 1])

    def test_extraction_to_other_file(self):
        before = {'a.m': B1_BEFORE, 'b.m': lines_of('// b')}
        after = {'a.m': lines_of('- (void)f {', '    pre();', '    [self g];', '}'),
                 'b.m': lines_of('// b', '- (void)g {', 'if (x) {', 'a();', 'b();', 'c();', '}', '}')}
        code, j, err = self.extract(before, after, '--extract', 'a.m:3-7=b.m:3-7',
                                    '--allow-added=a.m:3', '--allow-added=b.m:2',
                                    '--allow-added=b.m:8')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        # Swapped lines in the other file fail too.
        self.repo.write('b.m', lines_of('// b', '- (void)g {', 'if (x) {', 'a();', 'c();', 'b();',
                                        '}', '}'))
        self.repo.commit('swap')
        self.repo.git('reset', '-q', '--soft', 'HEAD~2')
        self.repo.commit('both')
        code, j, err = self.repo.run_json('HEAD', '--extract', 'a.m:3-7=b.m:3-7',
                                          '--allow-added=a.m:3', '--allow-added=b.m:2',
                                          '--allow-added=b.m:8')
        self.assertEqual(code, 1)
        self.assertEqual(len(j['extractions'][0]['mismatches']), 2)

    def test_extraction_to_new_file(self):
        after = {'a.m': lines_of('- (void)f {', '    pre();', '    [self g];', '}'),
                 'n.m': lines_of('- (void)g {', 'if (x) {', 'a();', 'b();', 'c();', '}', '}')}
        code, j, err = self.extract({'a.m': B1_BEFORE}, after, '--extract', 'a.m:3-7=n.m:2-6',
                                    '--allow-added=a.m:3', '--allow-added=n.m:1',
                                    '--allow-added=n.m:7')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertEqual([f['status'] for f in j['files']], ['M', 'A'])

    def test_extraction_out_of_deleted_file(self):
        before = {'a.m': lines_of('x'), 'old.m': lines_of('void g() {', 'a();', 'b();', '}')}
        after = {'a.m': lines_of('x', 'a();', 'b();'), 'old.m': None}
        code, j, err = self.extract(before, after, '--extract', 'old.m:2-3=a.m:2-3',
                                    '--allow-removed=old.m:1', '--allow-removed=old.m:4')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_decoy_identical_line_changes_nothing(self):
        decoy = lines_of('- (void)h {', '        b();', '        c();', '}')
        code, j, err = self.extract({'a.m': B1_BEFORE + decoy}, {'a.m': B1_SWAPPED + decoy},
                                    *B1_DECL)
        self.assertEqual(code, 1)
        self.assertEqual(len(j['extractions'][0]['mismatches']), 2)
        self.repo.write('a.m', B1_AFTER + decoy)
        self.repo.commit('fixed')
        self.repo.git('reset', '-q', '--soft', 'HEAD~2')
        self.repo.commit('both')
        code, j, err = self.repo.run_json('HEAD', *B1_DECL)
        self.assertEqual(code, 0)

    def bad(self, *args):
        self.two_commits({'a.m': B1_BEFORE, 'r.m': ''.join('line %d\n' % i for i in range(20))},
                         {'a.m': B1_AFTER, 'r.m': None,
                          'r2.m': ''.join('line %d\n' % i for i in range(20))})
        code, out, err = self.repo.run('HEAD', *args)
        self.assertEqual(code, 2, (args, out))
        self.assertEqual(out, '')
        return err

    def test_bad_ranges(self):
        self.assertIn('a.m:3-9', self.bad('--extract', 'a.m:3-9=a.m:7-13', '--allow-added=a.m:3-6'))

    def test_bad_ranges_each(self):
        for spec, message in [
                ('a.m:3-7=a.m:7-13', 'is outside the new content of a.m (12 lines)'),
                ('a.m:3-9=a.m:7-11', 'is outside the old content of a.m (8 lines)'),
                ('a.m:7-3=a.m:7-11', 'expects OLDPATH:A-B=NEWPATH:C-D'),
                ('a.m:0-3=a.m:7-9', 'expects OLDPATH:A-B=NEWPATH:C-D'),
                ('a.m:3-7', 'expects OLDPATH:A-B=NEWPATH:C-D'),
                ('a.m:3-7=', 'expects OLDPATH:A-B=NEWPATH:C-D'),
                ('zz.m:1-2=a.m:7-8', 'zz.m is not a file whose lines are compared'),
                ('r2.m:1-2=a.m:7-8', 'r2.m is not a file whose lines are compared'),
                ('a.m:3-7=zz.m:1-5', 'zz.m is not a file whose lines are compared')]:
            with self.subTest(spec=spec):
                self.assertIn(message, self.bad('--extract', spec))

    def test_source_in_added_file_is_bad(self):
        self.two_commits({'a.m': lines_of('x')}, {'a.m': lines_of('x', 'y'), 'n.m': lines_of('y')})
        code, out, err = self.repo.run('HEAD', '--extract', 'n.m:1=a.m:2')
        self.assertEqual(code, 2)
        self.assertIn('n.m:1 is outside the old content of n.m (0 lines)', err)

    def test_allow_added_out_of_range_is_bad(self):
        self.assertIn('--allow-added a.m:13 is outside the new content of a.m (12 lines)',
                      self.bad('--extract', 'a.m:3-7=a.m:7-11', '--allow-added=a.m:13'))

    def test_overlap(self):
        for args in [['--extract', 'a.m:3-5=a.m:7-9', '--extract', 'a.m:5-6=a.m:10-11'],
                     ['--extract', 'a.m:3-4=a.m:7-8', '--extract', 'a.m:5-6=a.m:8-9'],
                     ['--extract', 'a.m:3-7=a.m:7-11', '--allow-added=a.m:3-7'],
                     ['--extract', 'a.m:3-7=a.m:7-11', '--allow-removed=a.m:7-8']]:
            with self.subTest(args=args):
                self.assertIn('overlap', self.bad(*args))

    def test_extract_with_strict_runs_is_an_error(self):
        err = self.bad('--strict-runs', *B1_DECL)
        self.assertIn('--extract cannot be combined with --strict-runs', err)

    def test_extract_with_show_lines_is_an_error(self):
        self.assertIn('--show-lines takes no declarations', self.bad('--show-lines', *B1_DECL))

    def test_path_with_equals_and_colon(self):
        self.two_commits({'x=1:2.m': B1_BEFORE}, {'x=1:2.m': B1_AFTER})
        code, j, err = self.repo.run_json('HEAD', '--extract', 'x=1:2.m:3-7=x=1:2.m:7-11',
                                          '--allow-added=x=1:2.m:3-6')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_single_line_ranges(self):
        self.two_commits({'a.m': lines_of('void f() {', '    a();', '}')},
                         {'a.m': lines_of('void f() {', '    g();', '}', 'void g() {', '    a();', '}')})
        code, j, err = self.repo.run_json('HEAD', '--extract', 'a.m:2=a.m:5',
                                          '--allow-added=a.m:2', '--allow-added=a.m:4',
                                          '--allow-added=a.m:6')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_unchanged_other_file_is_not_compared(self):
        # Only changed files take part; an empty diff is still not a pure move.
        self.repo.write('a.m', B1_BEFORE)
        self.repo.commit()
        self.repo.commit('empty')
        code, out, err = self.repo.run('HEAD', '--extract', 'a.m:3-7=a.m:3-7')
        self.assertEqual(code, 2)
        self.assertIn('a.m is not a file whose lines are compared', err)

    def test_pairing_mode_rules_state_the_limit(self):
        text = ' '.join(pm.RULES)
        self.assertNotIn('closes the gap above for single-block extractions', text)
        self.assertIn('cannot judge an extraction whose destination is in the same file', text)
        self.assertIn('--extract', text)
        self.assertIn('large-code.md section 2.2', text)
        nc = ' '.join(pm.NOT_CHECKED)
        self.assertNotIn('--strict-runs closes that for single-block extractions', nc)
        self.assertIn('cannot judge an extraction whose destination is in the same file', nc)

    def test_extract_not_checked_list(self):
        nc = ' '.join(pm.NOT_CHECKED_EXTRACT)
        for phrase in ['means the same in its new place', 'Control flow that leaves', 'Locals read or written',
                       'order of evaluations', 'Manual reference counting', 'Declared lines',
                       'whatever the author declared']:
            self.assertIn(phrase, nc)


class ShowLinesTests(RepoTestCase):
    def test_round_trip_into_a_passing_extraction(self):
        self.two_commits({'a.m': B1_BEFORE}, {'a.m': B1_AFTER})
        code, j, err = self.repo.run_json('HEAD', '--show-lines')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertEqual(j['check'], 'show_lines')
        f = j['files'][0]
        self.assertEqual(f['path'], 'a.m')
        self.assertEqual(f['added'], ['a.m:3-6'])
        self.assertEqual(f['removed'], [])
        rows = f['lines']
        first = [r for r in rows if r['text'] == '    if (x) {'][0]
        last = [r for r in rows if r['text'] == '    }'][0]
        spec = 'a.m:%d-%d=a.m:%d-%d' % (first['old'], last['old'], first['new'], last['new'])
        self.assertEqual(spec, 'a.m:3-7=a.m:7-11')
        args = ['--extract', spec] + ['--allow-added=' + r for r in f['added']]
        code, j, err = self.repo.run_json('HEAD', *args)
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_text_listing(self):
        self.two_commits({'a.m': B1_BEFORE}, {'a.m': B1_SWAPPED})
        code, out, err = self.repo.run('HEAD', '--show-lines')
        self.assertEqual(code, 0)
        self.assertIn('M a.m\n  removed (old side): a.m:5\n  added (new side): a.m:3-6, a.m:10\n', out)
        self.assertIn('       2       2       pre();\n', out)
        self.assertIn('               3 +     [self g];\n', out)
        self.assertIn('       5         -         b();\n', out)

    def test_every_run_is_a_valid_declaration(self):
        self.two_commits({'Widget.m': fixture('widget_before.m')},
                         {'Widget.m': fixture('widget_extracted.m')})
        code, j, err = self.repo.run_json('HEAD', '--show-lines')
        self.assertEqual(code, 0)
        f = j['files'][0]
        self.assertTrue(f['added'])
        for r in f['added']:
            code, out, err = self.repo.run('HEAD', '--allow-added=' + r)
            self.assertIn(code, (0, 1), err)
        for r in f['removed']:
            code, out, err = self.repo.run('HEAD', '--allow-removed=' + r)
            self.assertIn(code, (0, 1), err)

    def test_added_and_deleted_files_and_problems(self):
        self.two_commits({'a.m': lines_of('x1', 'x2', 'x3'), 'b.bin': b'\0'},
                         {'a.m': None, 'c.m': lines_of('y'), 'b.bin': b'\0\1'})
        code, j, err = self.repo.run_json('HEAD', '--show-lines')
        self.assertEqual(code, 0)
        by_path = dict((f['path'], f) for f in j['files'])
        self.assertEqual(by_path['a.m']['removed'], ['a.m:1-3'])
        self.assertEqual(by_path['c.m']['added'], ['c.m:1'])
        self.assertEqual(j['file_problems'], [{'path': 'b.bin', 'problem': 'binary file; not compared'}])

    def test_show_lines_with_declarations_is_an_error(self):
        self.two_commits({'a.m': B1_BEFORE}, {'a.m': B1_AFTER})
        code, out, err = self.repo.run('HEAD', '--show-lines', '--allow-added=a.m:3')
        self.assertEqual(code, 2)
        self.assertIn('--show-lines takes no declarations', err)


class FinalNewlineTests(RepoTestCase):
    def test_moved_last_line_into_new_file_without_newline(self):
        self.two_commits({'a.m': 'x\nf();\n'}, {'a.m': 'x\n', 'b.m': 'f();'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [{'path': 'b.m', 'problem': 'no final newline in added file'}])

    def test_moved_last_line_into_new_file_without_newline_extract(self):
        self.two_commits({'a.m': 'x\nf();\n'}, {'a.m': 'x\n', 'b.m': 'f();'})
        code, j, err = self.repo.run_json('HEAD', '--extract', 'a.m:2=b.m:1')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [{'path': 'b.m', 'problem': 'no final newline in added file'}])

    def test_line_without_newline_moved_out_of_deleted_file(self):
        self.two_commits({'a.m': 'x\n', 'b.m': 'f();'}, {'a.m': 'x\nf();\n', 'b.m': None})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [{'path': 'b.m', 'problem': 'no final newline in deleted file'}])
        code, j, err = self.repo.run_json('HEAD', '--extract', 'b.m:1=a.m:2')
        self.assertEqual(code, 1)

    def test_last_line_without_newline_moved_within_file(self):
        self.two_commits({'a.m': 'a();\nb();'}, {'a.m': 'b();\na();'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [
            {'path': 'a.m', 'problem': 'last line has no final newline and is changed'}])
        code, j, err = self.repo.run_json('HEAD', '--extract', 'a.m:1=a.m:2')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [
            {'path': 'a.m', 'problem': 'last line has no final newline and is changed'}])

    def test_unchanged_last_line_without_newline_is_fine(self):
        self.two_commits({'a.m': 'x();\ny();\nz();'}, {'a.m': 'y();\nx();\nz();'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        self.assertEqual(j['file_problems'], [])
        code, j, err = self.repo.run_json('HEAD', '--extract', 'a.m:1=a.m:2')
        self.assertEqual(code, 0)

    def test_rule_text(self):
        for rules in (pm.RULES, pm.EXTRACT_RULES):
            text = ' '.join(rules)
            self.assertIn('an added or deleted file whose content does not end with a newline', text)


class LastLineRuleTests(unittest.TestCase):
    """Each side of the last-line rule, with a canned patch. With real git a changed last line
    without a final newline shows on both sides, so these cases need a fake."""
    S = '1' * 40
    T = '2' * 40

    def problems(self, old, new, patch):
        raw = (':100644 100644 %s %s M\0a.m\0' % (self.S, self.T)).encode()
        return collect4(FakeGit(raw, {self.S: old, self.T: new}, patch=patch), 'range', 'o', 'n')[3]

    def test_old_last_line_removed(self):
        self.assertEqual(self.problems(b'a\nb', b'a', b'@@ -2 +1,0 @@\n-b\n'),
                         [{'path': 'a.m', 'problem': 'last line has no final newline and is changed'}])

    def test_new_last_line_added(self):
        self.assertEqual(self.problems(b'a', b'a\nb', b'@@ -1,0 +2 @@\n+b\n'),
                         [{'path': 'a.m', 'problem': 'last line has no final newline and is changed'}])

    def test_other_line_changed(self):
        self.assertEqual(self.problems(b'a\nb', b'b', b'@@ -1 +0,0 @@\n-a\n'), [])

    def test_extract_old_side_only(self):
        # The old last line is declared removed and nothing at the end of the new content is.
        repo = Repo()
        try:
            repo.write('a.m', 'x();\ny();\nz();')
            repo.commit()
            repo.write('a.m', 'x();\nz();')
            repo.commit()
            code, j, err = repo.run_json('HEAD', '--extract', 'a.m:1=a.m:1', '--allow-removed=a.m:3')
            self.assertEqual(err, '')
            self.assertEqual(j['file_problems'],
                             [{'path': 'a.m', 'problem': 'last line has no final newline and is changed'}])
            code, j, err = repo.run_json('HEAD', '--extract', 'a.m:1=a.m:1', '--allow-removed=a.m:2')
            self.assertEqual(j['file_problems'], [])
            self.assertEqual(code, 0)
        finally:
            repo.cleanup()


class ExtractDetailTests(RepoTestCase):
    def test_overlapping_declared_lines_are_fine(self):
        self.two_commits({'a.m': B1_BEFORE}, {'a.m': B1_AFTER})
        code, j, err = self.repo.run_json('HEAD', '--extract', 'a.m:3-7=a.m:7-11',
                                          '--allow-added=a.m:3-5', '--allow-added=a.m:4-6')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)

    def test_shared_blob_in_two_files(self):
        # b.m's new content is a.m's old content, so one blob serves two files.
        self.two_commits({'a.m': B1_BEFORE, 'b.m': lines_of('x')},
                         {'a.m': B1_AFTER, 'b.m': B1_BEFORE})
        code, j, err = self.repo.run_json('HEAD', *B1_DECL)
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(len(j['unaccounted_added']), 8)
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(err, '')


class ProblemOrderTests(RepoTestCase):
    def test_problems_in_path_order_across_checks(self):
        # The mode change is found before any content is read and the binary file after, yet
        # the problems are listed in path order.
        self.two_commits({'a.bin': b'\0\1', 'b.sh': 'echo\n'}, {'a.bin': b'\0\2'})
        os.chmod(os.path.join(self.repo.root, 'b.sh'), 0o755)
        self.repo.commit()
        self.repo.git('reset', '-q', '--soft', 'HEAD~2')
        self.repo.commit()
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual([p['path'] for p in j['file_problems']], ['a.bin', 'b.sh', None])


class ExtractDeclaredRemovedTests(RepoTestCase):
    def test_declared_removed_lines_are_listed(self):
        before = {'a.m': lines_of('x'), 'old.m': lines_of('void g() {', 'a();', '}')}
        after = {'a.m': lines_of('x', 'a();'), 'old.m': None}
        self.two_commits(before, after)
        code, j, err = self.repo.run_json('HEAD', '--extract', 'old.m:2=a.m:2',
                                          '--allow-removed=old.m:1', '--allow-removed=old.m:3')
        self.assertEqual(code, 0)
        self.assertEqual(j['declared_removed'], [mline('old.m', 1, 'void g() {'),
                                                 mline('old.m', 3, '}')])
        self.assertEqual(j['counts']['declared_removed'], 2)


class DiffRemaindersTests(unittest.TestCase):
    def setUp(self):
        self.saved = pm.MAX_DIFF_PAIRS

    def tearDown(self):
        pm.MAX_DIFF_PAIRS = self.saved

    def test_line_diff(self):
        old = [b'a', b'b', b'c', b'd', b'e']
        new = [b'a', b'c', b'X', b'd', b'e']
        self.assertEqual(pm.diff_remainders(old, range(1, 6), new, range(1, 6)),
                         ([(2, b'b')], [(3, b'X')]))

    def test_whole_region_above_the_limit(self):
        pm.MAX_DIFF_PAIRS = 3
        old = [b'a', b'b', b'c', b'd', b'e']
        new = [b'a', b'c', b'X', b'd', b'e']
        self.assertEqual(tuple(list(x) for x in pm.diff_remainders(old, range(1, 6),
                                                                   new, range(1, 6))),
                         ([(2, b'b'), (3, b'c')], [(2, b'c'), (3, b'X')]))

    def test_kept_lines_only(self):
        self.assertEqual(pm.diff_remainders([b'a', b'z', b'b'], [1, 3], [b'a', b'b'], [1, 2]),
                         ([], []))

    def test_limit_is_stated(self):
        self.assertEqual(pm.MAX_DIFF_PAIRS, 1000000)
        self.assertIn('1,000,000', ' '.join(pm.EXTRACT_RULES))


class CountingGit(pm.Git):
    def __init__(self, repo):
        pm.Git.__init__(self, repo)
        self.calls = []

    def run(self, args, input=None, check=True):
        self.calls.append(args[0])
        return pm.Git.run(self, args, input=input, check=check)


class ManyFilesTests(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()
        self.saved = (pm.MAX_CHANGED_FILES, pm.MAX_TOTAL_BYTES)

    def tearDown(self):
        pm.MAX_CHANGED_FILES, pm.MAX_TOTAL_BYTES = self.saved
        self.repo.cleanup()

    def change(self, n):
        for k in range(n):
            self.repo.write('f%03d.m' % k, 'start\nf%d();\nend\n' % k)
        self.repo.commit()
        for k in range(n):
            self.repo.write('f%03d.m' % k, 'start\nend\nf%d();\n' % k)
        self.repo.commit()

    def test_git_processes_do_not_grow_with_files(self):
        self.change(3)
        few = CountingGit(self.repo.root)
        self.assertEqual(pm.check(few, 'commit', ['HEAD'], [], [])['exit_code'], 0)
        self.repo.cleanup()
        self.repo = Repo()
        self.change(40)
        many = CountingGit(self.repo.root)
        self.assertEqual(pm.check(many, 'commit', ['HEAD'], [], [])['exit_code'], 0)
        self.assertEqual(len(few.calls), len(many.calls))
        self.assertLessEqual(len(many.calls), 8)

    def test_file_budget(self):
        self.assertEqual(pm.MAX_CHANGED_FILES, 10000)
        self.assertIn('10,000', ' '.join(pm.RULES))
        self.change(3)
        pm.MAX_CHANGED_FILES = 3
        pm.check(pm.Git(self.repo.root), 'commit', ['HEAD'], [], [])
        pm.MAX_CHANGED_FILES = 2
        with self.assertRaises(pm.ToolError) as cm:
            pm.check(pm.Git(self.repo.root), 'commit', ['HEAD'], [], [])
        self.assertIn('more than 2 changed files', str(cm.exception))

    def test_byte_cap(self):
        self.assertEqual(pm.MAX_TOTAL_BYTES, 128 * 1024 * 1024)
        self.assertIn('128 MB', ' '.join(pm.RULES))
        self.assertIn('128 MB', ' '.join(pm.EXTRACT_RULES))
        self.change(3)
        # Each file is 16 bytes before and after: 96 bytes in all.
        pm.MAX_TOTAL_BYTES = 96
        pm.check(pm.Git(self.repo.root), 'commit', ['HEAD'], [], [])
        pm.MAX_TOTAL_BYTES = 95
        with self.assertRaises(pm.ToolError) as cm:
            pm.check(pm.Git(self.repo.root), 'commit', ['HEAD'], [], [])
        self.assertIn('more than 95 bytes', str(cm.exception))
        with self.assertRaises(pm.ToolError):
            pm.check(pm.Git(self.repo.root), 'commit', ['HEAD'], [], [],
                     extractions=[('f000.m', 2, 2, 'f000.m', 3, 3)])


class SplitBatchesTests(unittest.TestCase):
    def test_batches(self):
        out = (b'diff --git a/p0 b/p0\n@@ -1 +1 @@\n-a\x00b\n+c\n\x00\x00'
               b'diff --git a/p2 b/p2\n@@ -2,0 +3 @@\n+d\n\\ No newline at end of file\n\x00')
        self.assertEqual(pm.split_batches(out, 3), [
            ([(1, b'a\x00b')], [(1, b'c')]), ([], []), ([], [(3, b'd')])])

    def test_wrong_count(self):
        with self.assertRaises(pm.ToolError):
            pm.split_batches(b'\x00', 2)
        with self.assertRaises(pm.ToolError):
            pm.split_batches(b'\x00\x00x', 2)


class ParseExtractionTests(unittest.TestCase):
    def test_forms(self):
        self.assertEqual(pm.parse_extraction('a.m:3-7=b.m:9-13'), ('a.m', 3, 7, 'b.m', 9, 13))
        self.assertEqual(pm.parse_extraction('a.m:3=a.m:9'), ('a.m', 3, 3, 'a.m', 9, 9))
        self.assertEqual(pm.parse_extraction('x=1:2.m:3-4=x=1:2.m:5-6'),
                         ('x=1:2.m', 3, 4, 'x=1:2.m', 5, 6))
        # The first ":N=" ends OLDPATH.
        self.assertEqual(pm.parse_extraction('a.m:3=b:4=c.m:5'), ('a.m', 3, 3, 'b:4=c.m', 5, 5))

    def test_bad(self):
        for bad in ['a.m:3-7', 'a.m:3-7=', '=a.m:3', 'a.m:0-2=a.m:3-5', 'a.m:5-4=a.m:1-2',
                    'a.m:1-2=a.m:4-3', 'a.m=b.m', 'a.m:1-2=b.m']:
            with self.assertRaises(ValueError, msg=bad):
                pm.parse_extraction(bad)


# Tests added for the fifth review round.

class EmptySideNewlineTests(RepoTestCase):
    """A modified file that is emptied, or starts empty, is held to the rule for an added or
    deleted file: its non-empty side must end with a newline."""

    def test_emptied_file_without_final_newline_extract(self):
        self.two_commits({'X.m': b'a\nb', 'Y.m': b'y\n'}, {'X.m': b'', 'Y.m': b'y\na\nb\n'})
        code, j, err = self.repo.run_json('HEAD', '--extract=X.m:1-2=Y.m:2-3')
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [
            {'path': 'X.m', 'problem': 'no final newline in a file that is now empty'}])

    def test_emptied_file_without_final_newline_pairing(self):
        self.two_commits({'X.m': b'a\nb', 'Y.m': b'y\n'}, {'X.m': b'', 'Y.m': b'y\na\nb\n'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [
            {'path': 'X.m', 'problem': 'no final newline in a file that is now empty'}])

    def test_file_that_was_empty_without_final_newline_extract(self):
        self.two_commits({'X.m': b'a\nb\n', 'Y.m': b''}, {'X.m': b'', 'Y.m': b'a\nb'})
        code, j, err = self.repo.run_json('HEAD', '--extract=X.m:1-2=Y.m:1-2')
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [
            {'path': 'Y.m', 'problem': 'no final newline in a file that was empty'}])

    def test_file_that_was_empty_without_final_newline_pairing(self):
        self.two_commits({'X.m': b'a\nb\n', 'Y.m': b''}, {'X.m': b'', 'Y.m': b'a\nb'})
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['file_problems'], [
            {'path': 'Y.m', 'problem': 'no final newline in a file that was empty'}])

    def test_emptied_file_with_final_newline_passes(self):
        self.two_commits({'X.m': b'a\nb\n', 'Y.m': b''}, {'X.m': b'', 'Y.m': b'a\nb\n'})
        code, j, err = self.repo.run_json('HEAD', '--extract=X.m:1-2=Y.m:1-2')
        self.assertEqual(err, '')
        self.assertEqual(code, 0)
        code, j, err = self.repo.run_json('HEAD')
        self.assertEqual(code, 0)

    def test_rule_text(self):
        for rules in (pm.RULES, pm.EXTRACT_RULES):
            self.assertIn('a modified file whose old content is empty and whose new content does '
                          'not end with a newline, or whose new content is empty and whose old '
                          'content does not end with a newline', ' '.join(rules))


class SurvivingMutantTests(RepoTestCase):
    def test_block_one_line_short_with_balanced_remainder(self):
        # The destination has one line more than the block; the remainders are equal.
        self.two_commits({'X.m': lines_of('A', 'B', 'C', 'D', 'E')},
                         {'X.m': lines_of('A', 'B', 'X', 'C', 'D', 'E')})
        code, j, err = self.repo.run_json('HEAD', '--extract=X.m:1-2=X.m:1-3')
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['counts']['length_mismatches'], 1)
        self.assertEqual(j['counts']['mismatches'], 0)
        self.assertEqual(j['unaccounted_removed'], [])
        self.assertEqual(j['unaccounted_added'], [])

    def test_suffix_does_not_overlap_prefix(self):
        self.two_commits({'X.m': lines_of('m', 'a')}, {'X.m': lines_of('a', 'a', 'm')})
        code, j, err = self.repo.run_json('HEAD', '--extract=X.m:1=X.m:3')
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['unaccounted_removed'], [])
        self.assertEqual(j['unaccounted_added'], [mline('X.m', 2, 'a')])


class GitVersionTextTests(unittest.TestCase):
    def test_docstring_says_which_modes_need_git_2_50(self):
        self.assertNotIn('Python 3 standard library and git 2.50 or later (for git\ndiff-pairs)',
                         pm.__doc__)
        self.assertIn('The pairing mode and --show-lines need git 2.50 or later (for git\n'
                      'diff-pairs); the extraction mode (--extract) works with older git.',
                      pm.__doc__)

    def test_help_says_which_modes_need_git_2_50(self):
        proc = subprocess.run([sys.executable, '-B', TOOL, '--help'], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE)
        self.assertEqual(proc.returncode, 0)
        out = ' '.join(proc.stdout.decode('utf-8').split())
        self.assertIn('The pairing mode and --show-lines need git 2.50 or later (for git '
                      'diff-pairs); the extraction mode (--extract) works with older git.', out)


class FormatCharacterTests(RepoTestCase):
    def test_format_characters_are_escaped(self):
        self.assertEqual(pm.display('a‮b​c⁦d﻿e'.encode('utf-8')),
                         'a\\u202eb\\u200bc\\u2066d\\ufeffe')
        self.assertEqual(pm.display('x\U000e0001y'.encode('utf-8')), 'x\\U000e0001y')

    def test_declared_and_mismatched_lines_are_escaped(self):
        self.two_commits({'a.m': lines_of('x', 'f(1);')},
                         {'a.m': lines_of('x', 'g(‮);', 'f(​1);')})
        code, out, err = self.repo.run('HEAD', '--extract=a.m:2=a.m:3', '--allow-added=a.m:2')
        self.assertEqual(code, 1)
        self.assertIn('  a.m:2: g(\\u202e);\n', out)
        self.assertIn('    new: f(\\u200b1);\n', out)
        self.assertNotIn('‮', out)
        self.assertNotIn('​', out)

    def test_rule_text(self):
        for rules in (pm.RULES, pm.EXTRACT_RULES):
            self.assertIn('Unicode format characters (category Cf, such as bidirectional controls '
                          'and zero-width characters) as \\uNNNN', ' '.join(rules))


class ListedLineCapTests(RepoTestCase):
    def setUp(self):
        RepoTestCase.setUp(self)
        self.saved = pm.MAX_LISTED_LINES

    def tearDown(self):
        pm.MAX_LISTED_LINES = self.saved
        RepoTestCase.tearDown(self)

    def run_check(self):
        # Two mismatched lines in the block, then three removed and three added lines that
        # nothing accounts for.
        self.two_commits({'a.m': lines_of('b1', 'b2', 'r1', 'r2', 'r3', 'end')},
                         {'a.m': lines_of('c1', 'c2', 'a1', 'a2', 'a3', 'end')})
        return pm.check(pm.Git(self.repo.root), 'commit', ['HEAD'], [], [],
                        extractions=[('a.m', 1, 2, 'a.m', 1, 2)])

    def test_cap_value_and_rule(self):
        self.assertEqual(pm.MAX_LISTED_LINES, 2000)
        self.assertIn('At most 2,000 lines are listed', ' '.join(pm.EXTRACT_RULES))

    def test_uncapped(self):
        j = self.run_check()
        self.assertEqual(j['exit_code'], 1)
        self.assertEqual(len(j['extractions'][0]['mismatches']), 2)
        self.assertEqual(len(j['unaccounted_removed']), 3)
        self.assertEqual(len(j['unaccounted_added']), 3)
        self.assertEqual(j['not_listed'], {'mismatches': 0, 'unaccounted_removed': 0,
                                           'unaccounted_added': 0})

    def test_small_cap(self):
        pm.MAX_LISTED_LINES = 3
        j = self.run_check()
        self.assertEqual(j['exit_code'], 1)
        self.assertEqual(j['pure_move'], False)
        self.assertEqual(j['counts']['mismatches'], 2)
        self.assertEqual(j['counts']['unaccounted_removed'], 3)
        self.assertEqual(j['counts']['unaccounted_added'], 3)
        self.assertEqual(j['extractions'][0]['mismatches'], [
            {'source': mline('a.m', 1, 'b1'), 'destination': mline('a.m', 1, 'c1')},
            {'source': mline('a.m', 2, 'b2'), 'destination': mline('a.m', 2, 'c2')}])
        self.assertEqual(j['unaccounted_removed'], [mline('a.m', 3, 'r1')])
        self.assertEqual(j['unaccounted_added'], [])
        self.assertEqual(j['not_listed'], {'mismatches': 0, 'unaccounted_removed': 2,
                                           'unaccounted_added': 3})
        text = pm.format_text(j)
        self.assertIn('Unaccounted removed lines (3):\n  a.m:3: r1\n'
                      '  ... and 2 more, not listed\n', text)
        self.assertIn('Unaccounted added lines (3):\n  ... and 3 more, not listed\n', text)

    def test_zero_cap_keeps_the_verdict(self):
        pm.MAX_LISTED_LINES = 0
        j = self.run_check()
        self.assertEqual(j['exit_code'], 1)
        self.assertEqual(j['extractions'][0]['mismatches'], [])
        self.assertEqual(j['unaccounted_removed'], [])
        self.assertEqual(j['not_listed'], {'mismatches': 2, 'unaccounted_removed': 3,
                                           'unaccounted_added': 3})
        self.assertIn('Mismatched lines in extracted blocks (2):\n  ... and 2 more, not listed\n',
                      pm.format_text(j))


MEANING_PASS = ('a pass means that the lines covered by the check were moved unchanged, and the '
                'change is probably a pure move')
MEANING_FAIL = ('a failure does not mean that the change is wrong; it means that this tool cannot '
                'confirm it and more analysis is needed')
MEANING_EXAMPLE = ('an extraction that turns a local variable into a parameter rewrites every use '
                   'of it, and is reported as a failure')


class MeaningTests(RepoTestCase):
    def test_first_rule_of_each_mode(self):
        for rules in (pm.RULES, pm.EXTRACT_RULES):
            first = rules[0].lower()
            for phrase in (MEANING_PASS, MEANING_FAIL, MEANING_EXAMPLE):
                self.assertIn(phrase, first)

    def test_verdict_lines(self):
        self.two_commits({'a.m': B1_BEFORE}, {'a.m': B1_AFTER})
        code, out, err = self.repo.run('HEAD', *B1_DECL)
        self.assertEqual(code, 0)
        self.assertIn('Result: PURE MOVE (exit 0): the lines covered by the check were moved '
                      'unchanged, and the change is probably a pure move.\n', out)
        code, out, err = self.repo.run('HEAD')
        self.assertEqual(code, 1)
        self.assertIn('Result: NOT A PURE MOVE (exit 1): this does not mean that the change is '
                      'wrong; it means that this tool cannot confirm it and more analysis is '
                      'needed.\n', out)


def unescape(shown):
    """The inverse of the display rule, written from the rule: returns the raw bytes."""
    out = bytearray()
    i = 0
    while i < len(shown):
        ch = shown[i]
        if ch != '\\':
            out += ch.encode('utf-8')
            i += 1
            continue
        kind = shown[i + 1]
        if kind == '\\':
            out += b'\\'
            i += 2
        elif kind == 'r':
            out += b'\r'
            i += 2
        elif kind == 't':
            out += b'\t'
            i += 2
        elif kind == 'x':
            out.append(int(shown[i + 2:i + 4], 16))
            i += 4
        elif kind == 'u':
            out += chr(int(shown[i + 2:i + 6], 16)).encode('utf-8')
            i += 6
        elif kind == 'U':
            out += chr(int(shown[i + 2:i + 10], 16)).encode('utf-8')
            i += 10
        else:
            raise AssertionError('bad escape in %r' % shown)
    return bytes(out)


class ControlCharacterDisplayTests(unittest.TestCase):
    def test_c1_controls_are_escaped(self):
        self.assertEqual(pm.display(b'a\xc2\x85b\xc2\x9bc\xc2\x80d\xc2\x9fe'),
                         'a\\u0085b\\u009bc\\u0080d\\u009fe')

    def test_c0_controls_and_delete(self):
        self.assertEqual(pm.display(b'a\x00b\x1bc\x7fd\te'), 'a\\x00b\\x1bc\\x7fd\te')

    def test_rule_text(self):
        for rules in (pm.RULES, pm.EXTRACT_RULES):
            self.assertIn('every other control character (category Cc) except tab as \\xNN below '
                          'U+0080 and as \\uNNNN from U+0080 to U+009F', ' '.join(rules))


# Pairs of lines that differ but looked the same before backslashes were escaped: (old bytes,
# new bytes, old display, new display).
AMBIGUOUS_PAIRS = [
    (b'x = "\\r";', b'x = "\r";', 'x = "\\\\r";', 'x = "\\r";'),
    (b'@"\\u200b"', '@"\u200b"'.encode('utf-8'), '@"\\\\u200b"', '@"\\u200b"'),
    (b'bad\\xff', b'bad\xff', 'bad\\\\xff', 'bad\\xff'),
    (b't;', b't; ', 't;', 't;\\x20'),
    (b'a b', 'a\u00a0b'.encode('utf-8'), 'a b', 'a\\u00a0b'),
]


class UnambiguousDisplayTests(unittest.TestCase):
    def check_pair(self, old, new, old_shown, new_shown):
        repo = Repo()
        try:
            repo.write('a.m', b'x;\n' + old + b'\n')
            repo.commit('before')
            repo.write('a.m', b'x;\n' + new + b'\n')
            repo.commit('after')
            code, out, err = repo.run('HEAD', '--extract=a.m:2=a.m:2')
            self.assertEqual((code, err), (1, ''))
            self.assertIn('    old: %s\n    new: %s\n' % (old_shown, new_shown), out)
            code, j, err = repo.run_json('HEAD', '--extract=a.m:2=a.m:2')
            self.assertEqual((code, err), (1, ''))
            m = j['extractions'][0]['mismatches']
            self.assertEqual([(x['source']['text'], x['destination']['text']) for x in m],
                             [(old_shown, new_shown)])
        finally:
            repo.cleanup()

    def test_pairs_display_differently(self):
        for old, new, old_shown, new_shown in AMBIGUOUS_PAIRS:
            with self.subTest(old=old, new=new):
                self.assertNotEqual(old_shown, new_shown)
                self.check_pair(old, new, old_shown, new_shown)

    def test_backslash_round_trips(self):
        self.assertEqual(pm.display(b'a\\b'), 'a\\\\b')
        self.assertEqual(pm.display(b'\\x41\\'), '\\\\x41\\\\')
        lines = [b'a\\b', b'\\\\', b'\\xff\xff', b'\\r\r', b'\\t\t', b'\\u00a0\xc2\xa0',
                 b'x \t \t', b' \t', b'a\tb', b'\\', '\u200b\\u200b'.encode('utf-8'),
                 b'\xc2\x85\\u0085', '\U000e0001'.encode('utf-8')]
        for line in lines:
            self.assertEqual(unescape(pm.display(line)), line)
        shown = [pm.display(line) for line in lines]
        self.assertEqual(len(set(shown)), len(shown))

    def test_space_separators_and_trailing_whitespace(self):
        self.assertEqual(pm.display('a\u00a0b\u2003c\u3000d e'.encode('utf-8')),
                         'a\\u00a0b\\u2003c\\u3000d e')
        self.assertEqual(pm.display(b'a \tb \t'), 'a \tb\\x20\\t')
        self.assertEqual(pm.display(b' \t '), '\\x20\\t\\x20')

    def test_rule_text(self):
        for rules in (pm.RULES, pm.EXTRACT_RULES):
            text = ' '.join(rules)
            self.assertIn('a backslash as \\\\', text)
            self.assertIn('space separators other than U+0020 (category Zs, such as the no-break '
                          'space) as \\uNNNN', text)
            self.assertIn('each space at the end of a line as \\x20 and each tab at the end of a '
                          'line as \\t', text)
            self.assertIn('every text field of --json is escaped the same way', text)


FAKE_GIT = '''#!%s
import os, sys
mode = os.environ['FAKE_GIT_MODE']
args = sys.argv[1:]
while args and args[0] in ('--no-pager', '-C'):
    args = args[2:] if args[0] == '-C' else args[1:]
if args == ['cat-file', '--batch-check']:
    for sha in sys.stdin.read().split():
        sys.stdout.write('%%s blob %%s\\n' %% (sha, '12x' if mode == 'bad_size' else '2'))
elif args == ['cat-file', '--batch']:
    if mode == 'stderr_flood':
        sys.stderr.write('w' * (200 * 1024))
        sys.stderr.flush()
    for sha in sys.stdin.read().split():
        if mode == 'bad_size':
            sys.stdout.write('%%s blob x1\\n' %% sha)
        else:
            sys.stdout.write('%%s blob 2\\nx\\n\\n' %% sha)
else:
    sys.stderr.write('fake git: unexpected %%r\\n' %% (args,))
    sys.exit(3)
''' % sys.executable


class FakeGitExecutable(object):
    """A directory holding a fake git executable, for the git output that pm.Git parses."""

    def __init__(self, mode):
        self.dir = tempfile.mkdtemp(prefix='pure-move-fake-git-')
        path = os.path.join(self.dir, 'git')
        with open(path, 'w') as f:
            f.write(FAKE_GIT)
        os.chmod(path, 0o755)
        self.env = dict(os.environ, PATH=self.dir + os.pathsep + os.environ.get('PATH', ''),
                        FAKE_GIT_MODE=mode)

    def git(self):
        git = pm.Git(self.dir)
        git.env = dict(self.env)
        return git

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


class MalformedGitOutputTests(unittest.TestCase):
    Z = '0' * 40
    S = '1' * 40

    def test_non_integer_size_from_batch_check(self):
        fake = FakeGitExecutable('bad_size')
        try:
            with self.assertRaises(pm.ToolError) as cm:
                fake.git().sizes([self.S])
            self.assertIn('cannot read blob %s' % self.S, str(cm.exception))
        finally:
            fake.cleanup()

    def test_non_integer_size_from_batch(self):
        fake = FakeGitExecutable('bad_size')
        try:
            with self.assertRaises(pm.ToolError) as cm:
                fake.git().read_blobs([self.S])
            self.assertIn('cannot read blob %s' % self.S, str(cm.exception))
        finally:
            fake.cleanup()

    def collect_raw(self, raw):
        return collect4(FakeGit(raw, {self.S: b'x\n'}), 'range', 'o', 'n')

    def test_short_raw_meta_line(self):
        with self.assertRaises(pm.ToolError) as cm:
            self.collect_raw((':100644 100644 %s M\0a.m\0' % self.S).encode())
        self.assertIn('unexpected git diff --raw output', str(cm.exception))

    def test_raw_meta_line_without_status(self):
        with self.assertRaises(pm.ToolError) as cm:
            self.collect_raw((':100644 100644 %s %s \0a.m\0' % (self.Z, self.S)).encode())
        self.assertIn('unexpected git diff --raw output', str(cm.exception))

    def test_non_ascii_raw_meta_line(self):
        with self.assertRaises(pm.ToolError) as cm:
            self.collect_raw(b':100644 100644 \xff%s %s M\0a.m\0' % (self.Z.encode(),
                                                                     self.S.encode()))
        self.assertIn('unexpected git diff --raw output', str(cm.exception))

    def test_truncated_raw_output(self):
        meta = ':100644 100644 %s %s M' % (self.Z, self.S)
        for raw in (meta + '\0a.m', meta + '\0', meta,
                    ':100644 100644 %s %s R090\0old.m\0' % (self.Z, self.S),
                    ':100644 100644 %s %s R090\0old.m\0new.m' % (self.Z, self.S)):
            with self.subTest(raw=raw):
                with self.assertRaises(pm.ToolError) as cm:
                    self.collect_raw(raw.encode())
                self.assertIn('git diff --raw output is truncated', str(cm.exception))

    def test_whole_records_are_accepted(self):
        raw = (':000000 100644 %s %s A\0a.m\0' % (self.Z, self.S)).encode()
        files, removed, added, problems = self.collect_raw(raw)
        self.assertEqual(added, [pm.Line('a.m', 1, b'x')])


class StderrFloodTests(unittest.TestCase):
    def test_much_stderr_before_stdout_does_not_deadlock(self):
        fake = FakeGitExecutable('stderr_flood')
        code = ('import sys; sys.path.insert(0, %r); import pure_move as pm; '
                'g = pm.Git(%r); g.env = dict(g.env); '
                'print(repr(g.read_blobs([%r, %r])))' % (TOOL_DIR, fake.dir, '1' * 40, '2' * 40))
        proc = subprocess.Popen([sys.executable, '-B', '-c', code], env=fake.env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True)
        try:
            # A deadlock never ends; a working read takes well under a second.
            out, err = proc.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, 9)
            proc.communicate()
            self.fail('read_blobs deadlocked on a git that fills its stderr pipe')
        finally:
            fake.cleanup()
        self.assertEqual(err, b'')
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(out, (repr({'1' * 40: b'x\n', '2' * 40: b'x\n'}) + '\n').encode())


class UnexpectedExceptionTests(RepoTestCase):
    def test_unexpected_exception_exits_2_with_one_line(self):
        import contextlib
        import io
        self.two_commits({'a.m': 'f();\ng();\n'}, {'a.m': 'g();\nf();\n'})
        saved = pm.check

        def broken(*args, **kwargs):
            raise RuntimeError('first\nsecond')

        pm.check = broken
        err, out = io.StringIO(), io.StringIO()
        try:
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
                code = pm.main(['--repo', self.repo.root, 'HEAD'])
        finally:
            pm.check = saved
        self.assertEqual(code, 2)
        self.assertEqual(out.getvalue(), '')
        self.assertEqual(err.getvalue(),
                         'pure_move.py: error: unexpected RuntimeError: first second\n')


class BudgetCountsBinaryTests(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()
        self.saved = pm.MAX_TOTAL_BYTES

    def tearDown(self):
        pm.MAX_TOTAL_BYTES = self.saved
        self.repo.cleanup()

    def test_binary_blobs_count_toward_the_byte_budget(self):
        for rules in (pm.RULES, pm.EXTRACT_RULES):
            self.assertIn('reads at most 128 MB of file content (the distinct blobs of every changed '
                          'file whose content is read: binary files count, and files refused before '
                          'their content is read, such as renames and files over 20 MB, do not)',
                          ' '.join(rules))
        self.repo.write('a.m', 'f();\ng();\n')
        self.repo.write('b.bin', b'\0abc')
        self.repo.commit()
        self.repo.write('a.m', 'g();\nf();\n')
        self.repo.write('b.bin', b'\0abd')
        self.repo.commit()
        # a.m is 10 bytes before and after, b.bin 4: 28 bytes, 20 of them compared as lines.
        pm.MAX_TOTAL_BYTES = 28
        j = pm.check(pm.Git(self.repo.root), 'commit', ['HEAD'], [], [])
        self.assertEqual(j['file_problems'], [{'path': 'b.bin',
                                               'problem': 'binary file; not compared'}])
        pm.MAX_TOTAL_BYTES = 27
        with self.assertRaises(pm.ToolError):
            pm.check(pm.Git(self.repo.root), 'commit', ['HEAD'], [], [])


HELP_OPTION_TEXT = [
    'REV a commit, checked against its parent, or two commits OLD NEW, the first checked against '
    'the second',
    '--staged check HEAD against the index',
    '--extract OLDPATH:A-B=NEWPATH:C-D declare that old lines A-B of OLDPATH moved and are new '
    'lines C-D of NEWPATH; selects the extraction mode; may be repeated',
    '--allow-added PATH:N[-M] declare new-side lines as new code, listed and not checked; may be '
    'repeated',
    '--allow-removed PATH:N[-M] declare old-side lines as removed code, listed and not checked; '
    'may be repeated',
    '--strict-runs pairing mode only: run notices are failures',
    '--show-lines list every changed file with the old and new line number of each line, to '
    'write declarations from; checks nothing',
    '--repo REPO the repository (default: the current directory)',
    '--json machine-readable output',
]


class WordingTests(unittest.TestCase):
    def help_text(self):
        proc = subprocess.run([sys.executable, '-B', TOOL, '--help'], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE)
        self.assertEqual(proc.returncode, 0)
        return ' '.join(proc.stdout.decode('utf-8').split())

    def test_docstring(self):
        doc = ' '.join(pm.__doc__.split())
        self.assertNotIn('did nothing else', doc)
        self.assertNotIn('The diff is a pure move', doc)
        self.assertNotIn('0 the change is a pure move', doc)
        self.assertIn('(docs/swift-migration/large-code.md section 2.2,', doc)
        self.assertIn('Exit status: 0 the lines covered by the check were moved unchanged, and the '
                      'change is probably a pure move (or --show-lines listed it); 1 this tool '
                      'cannot confirm that the change is a pure move, and more analysis is needed',
                      doc)

    def test_help_describes_every_option(self):
        out = self.help_text()
        for text in HELP_OPTION_TEXT:
            self.assertIn(text, out)

    def test_help_states_exit_statuses_and_budgets_from_the_rules(self):
        out = self.help_text()
        self.assertIn('Exit status: 0 the lines covered by the check were moved unchanged, and the '
                      'change is probably a pure move (or --show-lines listed it). 1 this tool '
                      'cannot confirm that the change is a pure move, and more analysis is needed; '
                      'every unaccounted line and problem is listed (with --extract, at most 2,000 '
                      'lines are listed and the rest are counted). 2 a usage error, a bad '
                      'declaration, a merge commit, an unmerged index, a change over a budget, a '
                      'git failure, or an unexpected error.', out)
        self.assertIn('Budgets: The pairing mode checks at most 500,000 changed lines', out)
        for fragment in (pm._BUDGET_LINES, pm._BUDGET_FILES):
            self.assertIn(' '.join(fragment.split()), out)
            self.assertIn(fragment, ' '.join(pm.RULES))
        self.assertIn(pm._BUDGET_FILES, ' '.join(pm.EXTRACT_RULES))
        self.assertIn('Files over 20 MB are refused (not compared).', out)
        for rules in (pm.RULES, pm.EXTRACT_RULES):
            self.assertIn('files over 20 MB', ' '.join(rules))


class TrailingSpaceAboveBlockTests(RepoTestCase):
    def test_trailing_space_added_above_extracted_block(self):
        self.two_commits({'X.m': lines_of('a;', 'b;', 'c;', 'z;')},
                         {'X.m': lines_of('a; ', 'call();', 'z;', 'b;', 'c;')})
        code, j, err = self.repo.run_json('HEAD', '--extract=X.m:2-3=X.m:4-5',
                                          '--allow-added=X.m:2')
        self.assertEqual(err, '')
        self.assertEqual(code, 1)
        self.assertEqual(j['unaccounted_removed'], [mline('X.m', 1, 'a;')])
        self.assertEqual(j['unaccounted_added'], [mline('X.m', 1, 'a;\\x20')])


if __name__ == '__main__':
    unittest.main()
