#!/usr/bin/env python3
"""Exercises framer.py's SIGWINCH handling: the handler must not write, because a signal can
arrive in the middle of writing a command's reply and a %ping there would become a line of
that reply. The ping is sent from the event loop instead, after the reply is complete.

Run: python3 tests/framer_sigwinch_test.py
"""
import asyncio
import importlib.util
import os
import signal
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMER_PATH = os.path.join(HERE, "..", "OtherResources", "framer.py")

_spec = importlib.util.spec_from_file_location("framer_sigwinch_under_test", FRAMER_PATH)
framer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(framer)
framer.DEPTH = 0

OSC = "\033]134;:"
ST = "\033\\"


class SigwinchTests(unittest.TestCase):
    def setUp(self):
        self.written = []
        self.resizes = 0
        self.saved = (framer._write_all, framer.update_pty_size, framer.PROCESSES, framer.RUNLOOP)

        async def update_pty_size():
            self.resizes += 1
        framer.update_pty_size = update_pty_size
        # ping() is squelched until a program is running.
        framer.PROCESSES = {1: None}

    def tearDown(self):
        (framer._write_all, framer.update_pty_size, framer.PROCESSES, framer.RUNLOOP) = self.saved

    def run_loop(self, body):
        async def wrapper():
            framer.RUNLOOP = asyncio.get_running_loop()
            await body()
        asyncio.run(wrapper())

    async def until(self, predicate):
        # Yields to the loop; the ping is queued with call_soon_threadsafe, so it runs within
        # a few iterations regardless of how fast the machine is.
        for _ in range(1000):
            if predicate():
                return
            await asyncio.sleep(0)
        self.fail("condition never became true")

    def stream(self):
        return "".join(self.written)

    def test_signal_during_a_reply_pings_after_the_reply(self):
        def write_all(_fd, data):
            self.written.append(data)
            if len(self.written) == 1:
                # The signal arrives after "begin" is out and before the rest of the reply.
                framer.on_sigwinch(signal.SIGWINCH, None)
        framer._write_all = write_all

        async def body():
            q = framer.begin("7")
            framer.send_esc(q, "reply line")
            framer.end(q, "7", 0)
            await self.until(lambda: "%ping" in self.stream())

        self.run_loop(body)
        stream = self.stream()
        end = stream.index(OSC + "end 7 0 f" + ST)
        self.assertNotIn("%ping", stream[:end], "no ping inside the begin/end block")
        self.assertIn(OSC + "%ping" + ST, stream[end:])
        self.assertEqual(self.resizes, 1)

    def test_handler_itself_writes_nothing(self):
        framer._write_all = lambda _fd, data: self.written.append(data)

        async def body():
            framer.on_sigwinch(signal.SIGWINCH, None)
            self.assertEqual(self.written, [], "the handler deferred its write to the loop")
            await self.until(lambda: "%ping" in self.stream())

        self.run_loop(body)
        self.assertEqual(self.stream(), OSC + "%ping" + ST)

    def test_signal_before_the_loop_starts_is_ignored(self):
        framer._write_all = lambda _fd, data: self.written.append(data)
        framer.RUNLOOP = None
        framer.on_sigwinch(signal.SIGWINCH, None)
        self.assertEqual(self.written, [])
        self.assertEqual(self.resizes, 0)


if __name__ == "__main__":
    unittest.main()
