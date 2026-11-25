#!/usr/bin/env python3
"""Tests for dossier_cap.py, the lint for the dossier's length
(docs/swift-migration/lifecycle.md section 4).

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_dossier_cap.py'
"""

import io
import os
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import dossier_cap  # noqa: E402


class CapTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='dossier-cap-test-')
        self.units = os.path.join(self.dir, 'units')
        os.makedirs(self.units)

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def write(self, name, lines, first=()):
        path = os.path.join(self.units, name)
        with open(path, 'w') as f:
            f.write(''.join(x + '\n' for x in first))
            f.write(''.join('line %d\n' % i for i in range(lines - len(first))))
        return path

    def source(self, lines):
        path = os.path.join(self.dir, 'Foo.m')
        with open(path, 'w') as f:
            f.write('x\n' * lines)
        return path

    def run_cap(self, *argv):
        out = io.StringIO()
        return dossier_cap.main(list(argv), out=out), out.getvalue()

    def test_the_caps(self):
        self.assertEqual(dossier_cap.cap('trivial', 10), 0)
        self.assertEqual(dossier_cap.cap('light', 400), 60)
        self.assertEqual(dossier_cap.cap('full', 30), 100)
        self.assertEqual(dossier_cap.cap('full', 250), 250)
        self.assertEqual(dossier_cap.cap('full', 5000), 600)

    def test_light_within_and_over(self):
        d = self.write('Foo.md', 60)
        status, text = self.run_cap(d, '--path', 'light')
        self.assertEqual(status, 0, text)
        self.assertIn('60 of 60', text)
        d = self.write('Foo.md', 61)
        status, text = self.run_cap(d, '--path', 'light')
        self.assertEqual(status, 1, text)
        self.assertIn('over the cap', text)

    def test_full_scales_with_the_implementation(self):
        src = self.source(250)
        d = self.write('Foo.md', 200)
        self.assertEqual(self.run_cap(d, '--path', 'full', '--implementation', src)[0], 0)
        self.write('Foo.evidence.md', 51)
        status, text = self.run_cap(d, '--path', 'full', '--implementation', src)
        self.assertEqual(status, 1, 'the evidence file counts toward the cap')
        self.assertIn('Foo.evidence.md', text)

    def test_a_stated_reason_allows_more(self):
        d = self.write('Foo.md', 90, first=('# Foo', 'Over the cap: the class has 40 xib actions, each listed.'))
        status, text = self.run_cap(d, '--path', 'light')
        self.assertEqual(status, 0, text)
        self.assertIn('the class has 40 xib actions', text)
        d = self.write('Foo.md', 90, first=('# Foo', 'Over the cap:'))
        self.assertEqual(self.run_cap(d, '--path', 'light')[0], 1, 'an empty reason is no reason')
        d = self.write('Foo.md', 90, first=('# Foo',) + ('text',) * 10 + ('Over the cap: late',))
        self.assertEqual(self.run_cap(d, '--path', 'light')[0], 1, 'the reason must be in the first lines')

    def test_trivial_has_no_dossier(self):
        d = self.write('Foo.md', 5)
        status, text = self.run_cap(d, '--path', 'trivial')
        self.assertEqual(status, 1)
        self.assertIn('no dossier', text)

    def test_full_needs_the_implementation(self):
        d = self.write('Foo.md', 5)
        status, text = self.run_cap(d, '--path', 'full')
        self.assertEqual(status, 2)


if __name__ == '__main__':
    unittest.main()
