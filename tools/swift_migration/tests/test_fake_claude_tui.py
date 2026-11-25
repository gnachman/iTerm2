"""Tests for tools/swift_migration/tests/fake_claude_tui.py, the stand-in
for Claude Code's input line used by test_deadline_run.py and
test_nightly_start.py: that it models what was observed of Claude Code
2.1.331 (its docstring lists it).

Run from the repository root:
    python3 -B -m unittest tools/swift_migration/tests/test_fake_claude_tui.py

The stand-in runs on a pseudo-terminal; the tests type into it and read
the files it writes. Waits poll with a generous bound.
"""

import os
import pty
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FAKE = os.path.join(HERE, 'fake_claude_tui.py')


def wait_until(predicate, bound=30.0):
    end = time.monotonic() + bound
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


class FakeClaudeTests(unittest.TestCase):
    def start(self, **env):
        self.dir = tempfile.mkdtemp(prefix='fake_claude_test.')
        self.addCleanup(shutil.rmtree, self.dir, True)
        e = dict(os.environ)
        e.update(env)
        master, slave = pty.openpty()
        p = subprocess.Popen([sys.executable, '-B', FAKE, self.dir], stdin=slave, stdout=slave, stderr=slave,
                             env=e, start_new_session=True)
        os.close(slave)
        self.addCleanup(os.close, master)

        def stop():
            if p.poll() is None:
                p.kill()
                p.wait()
        self.addCleanup(stop)
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.dir, 'ready'))))
        self.master = master
        return p

    def type(self, data):
        os.write(self.master, data)
        # Separate bursts, as separate tmux calls are.
        time.sleep(0.3)

    def lines(self):
        try:
            with open(os.path.join(self.dir, 'lines')) as f:
                return f.read().splitlines()
        except OSError:
            return []

    LONG = b'x' * 150

    def test_long_text_with_enter_in_one_burst_is_a_paste(self):
        self.start()
        self.type(self.LONG + b'\r')
        self.assertEqual(self.lines(), [])
        # Enter on its own then submits it, the pasted newline included.
        self.type(b'\r')
        self.assertTrue(wait_until(lambda: self.lines() == ['x' * 150 + '\\n']), self.lines())

    def test_text_then_enter_apart_is_submitted(self):
        self.start()
        self.type(self.LONG)
        self.type(b'\r')
        self.assertTrue(wait_until(lambda: self.lines() == ['x' * 150]), self.lines())

    def test_ctrl_c_clears_the_line_and_exit_ends_it(self):
        p = self.start()
        self.type(self.LONG + b'\r')
        self.type(b'\x03')
        self.type(b'/exit')
        self.type(b'\r')
        self.assertEqual(p.wait(timeout=30), 0)
        self.assertTrue(os.path.exists(os.path.join(self.dir, 'got_exit')))
        self.assertEqual(self.lines(), [])

    def test_two_ctrl_c_on_an_empty_line_exit(self):
        p = self.start()
        self.type(b'\x03')
        self.assertIsNone(p.poll())
        self.type(b'\x03')
        self.assertEqual(p.wait(timeout=30), 0)
        self.assertTrue(os.path.exists(os.path.join(self.dir, 'ctrl_c_exit')))

    def test_a_line_typed_during_a_turn_is_queued_and_escape_submits_it(self):
        # A turn that would last ten minutes: only Escape can deliver the
        # queued line in this test.
        self.start(FAKE_TURN_SECONDS='600')
        self.type(b'first')
        self.type(b'\r')
        self.assertTrue(wait_until(lambda: self.lines() == ['first']))
        self.type(b'queued')
        self.type(b'\r')
        self.assertEqual(self.lines(), ['first'])
        self.type(b'\x1b')
        self.assertTrue(wait_until(lambda: self.lines() == ['first', 'queued']), self.lines())

    def test_the_queue_is_delivered_when_the_turn_ends(self):
        self.start(FAKE_TURN_SECONDS='1')
        self.type(b'first')
        self.type(b'\r')
        self.type(b'queued')
        self.type(b'\r')
        self.assertTrue(wait_until(lambda: self.lines() == ['first', 'queued']), self.lines())

    def test_an_open_dialog_takes_the_line_as_its_answer(self):
        self.start(FAKE_DIALOG='1')
        self.type(b'It is the clean stop time.')
        self.type(b'\r')
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.dir, 'dialog_answer'))))
        with open(os.path.join(self.dir, 'dialog_answer')) as f:
            self.assertEqual(f.read(), 'It is the clean stop time.\n')
        self.assertEqual(self.lines(), [])
        # Closed: the next line is delivered.
        self.type(b'next')
        self.type(b'\r')
        self.assertTrue(wait_until(lambda: self.lines() == ['next']), self.lines())


if __name__ == '__main__':
    unittest.main()
