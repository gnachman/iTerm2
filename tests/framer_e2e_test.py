#!/usr/bin/env python3
"""End-to-end tests: `python3 framer.py` runs as a child on a pty set up the way
conductor.sh leaves the remote terminal (no echo, no output processing, canonical input),
and the test speaks the real wire protocol to it. Commands are encoded exactly as
Conductor.swift encodes them (base64 arguments, 128-character lines continued with a
backslash, a blank line to finish) and everything the framer writes goes through the
harness's port of iTerm2's VT100ConductorParser, so a frame iTerm2 would reject fails the
test.

Covers framing (continuation lines, blank lines, malformed input, unknown commands, end of
input), output that looks like frames or is binary, process lifecycle and exit statuses,
quit with programs still running, SIGWINCH, flow control grants on the wire, it2 sockets,
and save/recover across a simulated reconnect.

Run: python3 tests/framer_e2e_test.py
"""
import base64
import json
import os
import shutil
import signal
import socket
import struct
import sys
import fcntl
import termios
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import framer_harness as H  # noqa: E402


class E2ETestCase(unittest.TestCase):
    def setUp(self):
        self.p = H.FramerProcess()
        self.pids = []

    def tearDown(self):
        self.p.close(self.pids)

    def mkdtemp(self, prefix="framer-test-"):
        path = H.scratch_dir(prefix)
        self.addCleanup(shutil.rmtree, path, True)
        return path

    def command(self, *args, **kwargs):
        reply = self.p.command(*args, **kwargs)
        self.assertIsNotNone(reply, self.p.diagnostics())
        return reply

    def start(self, *args):
        reply = self.command(*args)
        self.assertEqual(reply.status, 0, reply)
        pid = int(reply.lines[0])
        self.pids.append(pid)
        return pid

    def terminated(self, pid):
        self.assertTrue(self.p.wait(lambda: self.p.parser.terminate_status(pid) is not None),
                        self.p.diagnostics())
        return self.p.parser.terminate_status(pid)

    def assertClean(self):
        self.assertEqual(self.p.parser.errors, [], self.p.diagnostics())
        self.assertNotIn("Traceback", self.p.stderr())


class FramingTests(E2ETestCase):
    def test_ping(self):
        reply = self.command("ping")
        self.assertEqual((reply.status, reply.lines, reply.kind), (0, [], "r"))
        self.assertClean()

    def test_replies_come_in_command_order(self):
        for i in range(20):
            self.p.send("reset2", "code%d" % i)
        for i in range(20):
            self.assertEqual(self.p.next_reply().lines, ["code%d" % i])
        self.assertClean()

    def test_arguments_continue_across_lines(self):
        # Each argument is cut into pieces of its own, so no cut falls on the newline between
        # arguments (see test_iterm2_encoding_never_splits_a_command for that case).
        text = "x" * 50 + "y" * 50
        for size in (1, 3, 7, 128):
            lines = []
            for arg in ("runpy", H.b64("return %r" % text)):
                encoded = H.b64(arg)
                lines.extend(H.chunk(encoded, size, "\\"))
            self.p.write(("\n".join(lines) + "\n\n").encode())
            reply = self.p.next_reply()
            self.assertIsNotNone(reply, self.p.diagnostics())
            self.assertEqual(reply.lines, [text], size)
        self.assertClean()

    # The framer writes reply text as UTF-8 and iTerm2 reads it as UTF-8, so non-ASCII text
    # in a reply line (a runpy result, a getenv value, a path in an error) arrives intact.
    def test_non_ascii_reply_text_reaches_iterm2_intact(self):
        reply = self.command("runpy", H.b64("return 'caf\u00e9'"))
        self.assertEqual(reply.lines, ["caf\u00e9"])

    def test_an_argument_longer_than_a_canonical_line(self):
        # A pty in canonical mode holds at most MAX_CANON (1024 on macOS) bytes per line,
        # which is why iTerm2 sends 128-character lines.
        target = os.path.join(self.p.workdir, "big")
        content = os.urandom(20000)
        reply = self.command("file", "create", H.b64(target), H.b64(content))
        self.assertEqual(reply.status, 0, reply)
        with open(target, "rb") as f:
            self.assertEqual(f.read(), content)
        self.assertClean()

    def test_extra_blank_lines_are_ignored(self):
        # Conductor writes a blank line before `recover`; recovery may send others.
        self.p.write(b"\n\n\n")
        self.assertEqual(self.command("reset2", "after").lines, ["after"])
        self.assertClean()

    def test_unknown_command_fails_and_the_framer_carries_on(self):
        self.assertEqual(self.command("frobnicate").status, 1)
        self.assertEqual(self.command("ping").status, 0)
        self.assertClean()

    # A command that does not decode gets a failure reply, and the framer carries on. Exiting
    # would take the login shell with it.
    def test_malformed_base64_does_not_kill_the_framer(self):
        self.p.write(b"!!!notbase64\n\n")
        reply = self.p.next_reply()
        self.assertIsNotNone(reply, "no reply; framer exited with %r" % self.p.proc.poll())
        self.assertEqual(reply.status, 1)
        self.assertEqual(self.command("ping").status, 0)

    def test_non_utf8_argument_does_not_kill_the_framer(self):
        # Valid base64 whose bytes are not UTF-8.
        self.p.write(H.b64(b"\xff\xfe").encode() + b"\n\n")
        reply = self.p.next_reply()
        self.assertIsNotNone(reply, "framer exited with %r" % self.p.proc.poll())
        self.assertEqual(reply.status, 1)
        self.assertEqual(self.command("ping").status, 0)

    def test_end_of_input_exits(self):
        self.command("ping")
        self.p.send_eof()
        self.assertEqual(self.p.exited(), 0)
        self.assertClean()

    def test_end_of_input_mid_command_exits(self):
        self.p.write(H.b64("ping").encode() + b"\n")
        self.p.send_eof()
        self.assertEqual(self.p.exited(), 0)

    # Conductor.encode used to cut the joined arguments every 128 characters, so a cut just
    # before a separating newline left a blank line and ran the command early. `file suggest`
    # hit it with ordinary paths. The harness's encoder is a copy of Conductor.encode's; this
    # checks the framer accepts what it sends at every cut position.
    def test_iterm2_encoding_never_splits_a_command(self):
        for n in range(1, 400):
            args = ["file", "suggest", H.b64("a"), H.b64("/"), H.b64("/" + "p" * n), "r", "10"]
            self.assertNotIn(b"\n\n", H.encode_command(args)[:-2], n)
            if n % 50 == 0:
                reply = self.command(*args)
                self.assertEqual(reply.status, 0, reply)
                self.assertIsInstance(json.loads("".join(reply.lines)), list)


class OutputTests(E2ETestCase):
    def test_frame_lookalikes_and_binary_output_arrive_intact(self):
        payload = (bytes(range(256)) +
                   b"\x1b]134;:end 1 0 r\x1b\\\x1b]134;:%end 1\x1b\\\x1b]135;:unhook\x1b\\" +
                   b"\x1b]134;:begin 9\x1b\\\x1b]13\x1b]134;\x1b" + bytes(range(255, -1, -1)))
        path = os.path.join(self.p.workdir, "payload")
        with open(path, "wb") as f:
            f.write(payload)
        pid = self.start("run", "stty raw -echo; exec cat " + path)
        self.assertEqual(self.terminated(pid), 0)
        self.assertEqual(self.p.parser.output_bytes(pid), payload)
        self.assertClean()

    def test_a_megabyte_of_output(self):
        pid = self.start("login", self.p.workdir,
                         "head -c 1000000 /dev/zero | tr '\\0' 'y'")
        self.assertEqual(self.terminated(pid), 0)
        out = self.p.parser.output_bytes(pid)
        self.assertEqual(out.count(b"y"), 1000000)
        self.assertClean()


class LifecycleTests(E2ETestCase):
    def test_exit_statuses(self):
        ok = self.start("run", "exit 0")
        three = self.start("run", "exit 3")
        killed = self.start("run", "exec sleep 60")
        self.assertEqual(self.command("kill", str(killed)).status, 0)
        self.assertEqual(self.terminated(ok), 0)
        self.assertEqual(self.terminated(three), 3)
        self.assertEqual(self.terminated(killed), -signal.SIGTERM)
        self.assertEqual(self.command("ping").kind, "r", "nothing left running")
        self.assertClean()

    def test_login_send_and_echo(self):
        pid = self.start("login", self.p.workdir, "exec cat")
        self.assertEqual(self.command("send", str(pid), H.b64("hello\n")).status, 0)
        self.assertTrue(self.p.wait(lambda: b"hello" in self.p.parser.output_bytes(pid)))
        self.assertEqual(self.command("send", str(pid), H.b64("\x04")).status, 0)
        self.assertEqual(self.terminated(pid), 0)
        self.assertEqual(self.command("send", str(pid), H.b64("x")).status, 1, "gone")
        self.assertClean()

    def test_eval(self):
        home = self.mkdtemp()
        self.p.close()
        self.p = H.FramerProcess(env={"HOME": home})
        pid = self.start("eval", H.b64('echo "evaluated"; rm -f "$SELF"'))
        self.assertEqual(self.terminated(pid), 0)
        self.assertIn(b"evaluated", self.p.parser.output_bytes(pid))
        self.assertEqual(os.listdir(os.path.join(home, ".iterm2")), [])
        self.assertClean()

    def test_quit_with_programs_still_running(self):
        login = self.start("login", self.p.workdir, "exec sleep 300")
        self.start("run", "exec sleep 300")
        reply = self.command("quit")
        self.assertEqual((reply.status, reply.kind), (0, "f"))
        self.assertEqual(self.p.exited(), 0)
        # The login shell's terminal hangs up when the framer exits.
        self.assertTrue(H.wait_until(lambda: not H.pid_alive(login)))
        self.assertClean()

    def test_end_of_input_with_a_login_shell(self):
        login = self.start("login", self.p.workdir, "exec sleep 300")
        self.p.send_eof()
        self.assertEqual(self.p.exited(), 0)
        self.assertTrue(H.wait_until(lambda: not H.pid_alive(login)))

    # A search blocks once 16 matches are unacknowledged. Its thread must not keep the
    # framer from exiting, or the framer lingers on the remote host.
    def start_blocked_search(self):
        base = self.mkdtemp()
        for i in range(20):
            with open(os.path.join(base, "match%02d" % i), "w"):
                pass
        reply = self.command("file", "search", "start", H.b64("match"), H.b64(base))
        self.assertEqual(reply.status, 0)
        self.assertTrue(self.p.wait(lambda: len(self.p.parser.notifications("notif")) >= 16))

    def test_quit_during_a_search_exits(self):
        self.start_blocked_search()
        self.assertEqual(self.command("quit").status, 0)
        self.assertEqual(self.p.exited(), 0)

    def test_end_of_input_during_a_search_exits(self):
        self.start_blocked_search()
        self.p.send_eof()
        self.assertEqual(self.p.exited(), 0)


class SigwinchTests(E2ETestCase):
    def test_resize_pings_and_resizes_programs(self):
        pid = self.start("login", self.p.workdir, "head -n 1 >/dev/null; stty size")
        fcntl.ioctl(self.p.master, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 150, 0, 0))
        self.assertTrue(self.p.wait(lambda: self.p.parser.notifications("ignored")),
                        self.p.diagnostics())
        self.assertEqual(self.p.parser.notifications("ignored")[0].text, "%ping")
        # The resize happens on the loop with the ping; a command round trip after the
        # ping is seen means it is done.
        self.command("ping")
        self.command("send", str(pid), H.b64("\n"))
        self.assertEqual(self.terminated(pid), 0)
        self.assertIn(b"50 150", self.p.parser.output_bytes(pid))
        self.assertClean()


class FlowTests(E2ETestCase):
    def test_grants_on_the_wire(self):
        reply = self.command("flow", "on")
        self.assertEqual(reply.lines[0].split()[0], "1")
        pid = self.start("run", "head -c 30000 /dev/zero")
        self.assertTrue(self.p.wait(lambda: len(self.p.parser.output_bytes(pid)) == 8192))
        # Grants get no reply, so a ping after one tells us it has been read.
        self.command("ping")
        self.assertEqual(len(self.p.parser.output_bytes(pid)), 8192, "held at the credit")
        self.p.send("grant", str(30000 - 8192))
        self.assertEqual(self.terminated(pid), 0)
        self.assertEqual(len(self.p.parser.output_bytes(pid)), 30000)
        for o in self.p.parser.outputs(pid):
            self.assertEqual(len(o.header), 7, o.header)
        self.assertClean()


class It2Tests(E2ETestCase):
    def test_socket_round_trip(self):
        path = os.path.join(self.mkdtemp("it2-"), "s")
        self.assertEqual(self.command("it2listen", path).status, 0)
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(H.TIMEOUT)
        try:
            client.connect(path)
            client.sendall(b"hello framer")
            self.assertTrue(self.p.wait(lambda: any(
                e.parts[1] == "data" for e in self.p.parser.notifications("it2"))))
            events = self.p.parser.notifications("it2")
            connid = events[0].parts[0]
            self.assertEqual(events[0].parts[1], "open")
            data = b"".join(base64.b64decode(e.parts[2]) for e in events
                            if e.parts[1] == "data")
            self.assertEqual(data, b"hello framer")
            self.assertEqual(self.command("it2send", connid, H.b64("hi back")).status, 0)
            self.assertEqual(client.recv(100), b"hi back")
            self.assertEqual(self.command("it2close", connid).status, 0)
            self.assertEqual(client.recv(100), b"")
        finally:
            client.close()
        self.assertEqual(self.command("quit").status, 0)
        self.assertEqual(self.p.exited(), 0)
        self.assertFalse(os.path.exists(path), "quit removes the socket")
        self.assertClean()


class ReconnectTests(E2ETestCase):
    def test_save_and_recover_after_a_reconnect(self):
        login = self.start("login", self.p.workdir, "exec cat")
        job = self.start("run", "exec cat")
        self.assertEqual(self.command("save", "dcsID=d1", "sshargs=-t host",
                                      "boolArgs=", "clientUniqueID=u1").status, 0)
        self.command("register", str(login))

        # iTerm2 restarts and reattaches: a new parser in recovery mode, then what
        # Conductor.childDidBeginJumping writes.
        self.p.reattach()
        self.p.write(b"\n" + H.b64("recover").encode() + b"\n\n")
        self.assertTrue(self.p.wait(lambda: any(
            e.text == "end-recovery" for e in self.p.parser.notifications("recovery"))),
            self.p.diagnostics())
        lines = [e.text for e in self.p.parser.notifications("recovery")]
        self.assertEqual(lines[:2], ["begin-recovery", "recovery: version 2"])
        self.assertIn("recovery: login %d" % login, lines)
        self.assertIn("recovery: process %d" % job, lines)
        for expected in ("dcsID d1", "sshargs -t host", "boolArgs ", "clientUniqueID u1"):
            self.assertIn("recovery: " + expected, lines)

        # The recovered session works: the login shell is still there and answers.
        self.assertEqual(self.command("send", str(login), H.b64("still here\n")).status, 0)
        self.assertTrue(self.p.wait(lambda: b"still here" in self.p.parser.output_bytes(login)))
        self.assertEqual(self.command("ping").kind, "f")
        self.assertClean()


if __name__ == "__main__":
    unittest.main()
