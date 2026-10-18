#!/usr/bin/env python3
"""Exercises framer.py's commands other than `file`, in-process: dispatch through handle(),
process lifecycle (run, login, send, kill, eval and the %terminate that reports each exit),
terminal-mode reports, sessions (register, deregister, poll, autopoll, reset, reset2, save,
recover, quit), getenv and runpy, and the small helpers under them (the stdout writer, grant
parsing, ps parsing, window-size propagation).

Flow control, pane, it2 and SIGWINCH have their own files; this one fills the gaps between
them. The login shell is pinned to /bin/sh so the user's shell startup files cannot slow a
test down or change its output. Process tests use `exec` so that killing the shell kills the
program and nothing else holds the pty open.

Run: python3 tests/framer_commands_test.py
"""
import ast
import asyncio
import base64
import contextlib
import errno
import fcntl
import io
import os
import pty
import signal
import struct
import sys
import termios
import threading
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import framer_harness as H  # noqa: E402


@contextlib.contextmanager
def env(**values):
    saved = {k: os.environ.get(k) for k in values}
    for k, v in values.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
    try:
        yield
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


@contextlib.contextmanager
def patched(obj, name, value):
    saved = getattr(obj, name)
    setattr(obj, name, value)
    try:
        yield
    finally:
        setattr(obj, name, saved)


@contextlib.contextmanager
def fake_stdin_size(rows, cols):
    """Points sys.stdin at a pty of the given size, as the framer's own terminal."""
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    saved = sys.stdin
    sys.stdin = os.fdopen(slave, "r")
    try:
        yield
    finally:
        sys.stdin.close()
        sys.stdin = saved
        os.close(master)


class CommandTestCase(H.FramerTestCase):
    def setUp(self):
        super().setUp()
        self._saved_shell = self.framer.guess_login_shell
        self.framer.guess_login_shell = lambda: "/bin/sh"

    def tearDown(self):
        self.framer.guess_login_shell = self._saved_shell
        super().tearDown()

    def output(self, pid):
        return self.h.parser.output_bytes(pid)


class DispatchTests(CommandTestCase):
    def test_a_blank_command_is_ignored(self):
        async def body():
            self.assertFalse(await self.framer.handle([]))
        self.run_async(body)
        self.assertEqual(self.h.raw, b"")

    def test_unknown_command_fails(self):
        async def body():
            reply = await self.h.command("frobnicate", "x")
            self.assertEqual((reply.status, reply.lines, reply.kind), (1, [], "r"))
        self.run_async(body)
        self.assertNoParseErrors()

    def run_with_handler(self, handler):
        replies = []

        async def body():
            before = len(self.h.parser.replies())
            await self.framer.handle(["boom"])
            replies.extend(self.h.parser.replies()[before:])
        saved = dict(self.framer.HANDLERS)
        self.framer.HANDLERS["boom"] = handler
        try:
            self.run_async(body)
        finally:
            self.framer.HANDLERS.clear()
            self.framer.HANDLERS.update(saved)
        self.assertNoParseErrors()
        return replies

    def test_a_handler_that_raises_before_replying_fails(self):
        async def handler(identifier, args):
            q = self.framer.begin(identifier)
            self.framer.send_esc(q, "lost")
            raise ValueError("bad argument")
        replies = self.run_with_handler(handler)
        self.assertEqual([(r.status, r.lines) for r in replies], [(1, [])])

    def test_a_handler_that_raises_after_replying_is_not_answered_twice(self):
        async def handler(identifier, args):
            self.framer.end(self.framer.begin(identifier), identifier, 0)
            raise ValueError("after the reply")
        replies = self.run_with_handler(handler)
        self.assertEqual([r.status for r in replies], [0])

    def test_every_handler_is_registered(self):
        self.assertEqual(sorted(self.framer.HANDLERS), sorted(
            "run login pane panesize send kill quit register deregister poll reset reset2 "
            "autopoll recover save file eval getenv runpy it2listen it2send it2close flow panes "
            "drain ping".split()))

    def test_identifiers_are_unique_and_alphanumeric(self):
        ids = [self.framer.makeid() for _ in range(500)]
        self.assertEqual(len(set(ids)), 500)
        self.assertTrue(all(i.isalnum() for i in ids))
        self.assertEqual(self.framer.squash(0), "0")
        self.assertEqual(self.framer.squash(62), "10")

    def test_reply_kind_says_whether_processes_are_running(self):
        async def body():
            self.assertEqual((await self.h.command("ping")).kind, "r")
            pid = await self.h.start("run", "exec cat")
            self.assertEqual((await self.h.command("ping")).kind, "f")
            await self.h.command("kill", str(pid))
            await self.h.wait_terminated(pid)
            self.assertEqual((await self.h.command("ping")).kind, "r")
        self.run_async(body)

    def test_guess_login_shell_is_executable(self):
        shell = self._saved_shell()
        self.assertTrue(os.access(shell, os.X_OK), shell)

    def test_guess_login_shell_falls_back_to_sh(self):
        with patched(self.framer.os, "access", lambda *_a, **_k: False):
            self.assertEqual(self._saved_shell(), "/bin/sh")


# Prints "ready" and then sleeps in the same process, so ^C after "ready" reaches the sleeper.
READY_THEN_SLEEP = "exec perl -e '$|=1; print \"ready\\n\"; sleep 60'"


class RunTests(CommandTestCase):
    def test_output_and_exit_status(self):
        async def body():
            pid = await self.h.start("run", "printf 'hello'; exit 3")
            self.assertEqual(await self.h.wait_terminated(pid), 3)
            self.assertEqual(self.output(pid), b"hello")
            outputs = self.h.parser.outputs(pid)
            self.assertTrue(all(o.channel == 1 and o.depth == 0 for o in outputs))
            self.assertNotIn(pid, self.framer.PROCESSES)
        self.run_async(body)
        self.assertNoParseErrors()

    def test_runs_with_lang_c(self):
        async def body():
            pid = await self.h.start("run", "echo lang=$LANG")
            await self.h.wait_terminated(pid)
            self.assertIn(b"lang=C", self.output(pid))
        self.run_async(body)

    def test_large_output_comes_in_bounded_frames(self):
        async def body():
            pid = await self.h.start("run", "head -c 100000 /dev/zero | tr '\\0' x")
            self.assertEqual(await self.h.wait_terminated(pid), 0)
            self.assertEqual(self.output(pid), b"x" * 100000)
            self.assertTrue(all(len(o.data) <= 4096 for o in self.h.parser.outputs(pid)))
        self.run_async(body)
        self.assertNoParseErrors()

    def test_binary_output_and_frame_lookalikes_survive(self):
        payload = bytes(range(256)) + b"\x1b]134;:end 1 0 r\x1b\\\x1b]134;:%end x\x1b\\\x1b"
        path = os.path.join(self.tmp, "payload")
        with open(path, "wb") as f:
            f.write(payload)

        async def body():
            pid = await self.h.start("run", "stty raw -echo; exec cat " + path)
            self.assertEqual(await self.h.wait_terminated(pid), 0)
            self.assertEqual(self.output(pid), payload)
        self.run_async(body)
        self.assertNoParseErrors()

    def test_failure_to_start_fails(self):
        async def boom(_command):
            raise OSError(errno.EAGAIN, "no processes left")

        async def body():
            with patched(self.framer.Process, "run_shell_tty", boom):
                reply = await self.h.command("run", "true")
            self.assertEqual(reply.status, 1)
            self.assertEqual(self.framer.PROCESSES, {})
        self.run_async(body)

    def test_send_writes_to_the_program(self):
        async def body():
            pid = await self.h.start("run", "exec head -n 1")
            reply = await self.h.command("send", str(pid), H.b64("line one\n"))
            self.assertEqual(reply.status, 0)
            self.assertEqual(await self.h.wait_terminated(pid), 0)
            self.assertIn(b"line one", self.output(pid))
        self.run_async(body)

    def test_send_errors(self):
        async def body():
            self.assertEqual((await self.h.command("send", "999999999", H.b64("x"))).status, 1)
            self.assertEqual((await self.h.command("send", "1")).status, 1)
            self.assertEqual((await self.h.command("send", "pid", H.b64("x"))).status, 1)
            self.assertEqual((await self.h.command("send", "1", "abc")).status, 1)
        self.run_async(body)

    def test_kill_sends_sigterm(self):
        async def body():
            pid = await self.h.start("run", "exec sleep 60")
            reply = await self.h.command("kill", str(pid))
            self.assertEqual(reply.status, 0)
            self.assertEqual(await self.h.wait_terminated(pid), -signal.SIGTERM)
        self.run_async(body)
        self.assertNoParseErrors()

    def test_kill_reaches_programs_the_shell_started(self):
        # The shell forks for a pipeline (and dash forks even for a lone command), so the pid
        # iTerm2 gets is the shell's. Killing only the shell would leave sleep running and
        # holding the pty open.
        pidfile = os.path.join(self.tmp, "sleeper")

        async def body():
            pid = await self.h.start("run", "sh -c 'echo $$ > %s; exec sleep 60' | cat" % pidfile)
            self.assertTrue(await self.h.wait_for(
                lambda: os.path.exists(pidfile) and open(pidfile).read().strip()))
            sleeper = int(open(pidfile).read())
            self.assertEqual((await self.h.command("kill", str(pid))).status, 0)
            self.assertIsNotNone(await self.h.wait_terminated(pid))

            def gone():
                try:
                    os.kill(sleeper, 0)
                    return False
                except ProcessLookupError:
                    return True
            self.assertTrue(await self.h.wait_for(gone), "sleep %d survived" % sleeper)
        self.run_async(body)

    def test_kill_errors(self):
        async def body():
            self.assertEqual((await self.h.command("kill", "999999999")).status, 1)
            self.assertEqual((await self.h.command("kill", "nope")).status, 1)
            self.assertEqual((await self.h.command("kill")).status, 1)
        self.run_async(body)

    def test_control_c_reaches_the_login_shell_through_its_pty(self):
        # Only login (and pane) programs have the pty as their controlling terminal; a `run`
        # program does not, so ^C sent to it is just a byte. The program that says it is ready
        # must be the one that gets the ^C: with "echo ready; exec sleep", a ^C that arrives
        # before the exec is handled by the shell, which can go on to run sleep.
        async def body():
            pid = await self.h.start("login", self.tmp, READY_THEN_SLEEP)
            self.assertTrue(await self.h.wait_for(lambda: b"ready" in self.output(pid)))
            await self.h.command("send", str(pid), H.b64("\x03"))
            self.assertEqual(await self.h.wait_terminated(pid), -signal.SIGINT)
        self.run_async(body)

    def test_terminal_mode_changes_are_reported(self):
        async def body():
            pid = await self.h.start("run", "stty -echo; echo ready; exec head -n 1")
            self.assertTrue(await self.h.wait_for(
                lambda: any(e.text == "tty -echo +icanon"
                            for e in self.h.parser.notifications("notif"))))
            await self.h.command("send", str(pid), H.b64("\n"))
            await self.h.wait_terminated(pid)
        self.run_async(body)

    def test_cleanup_of_a_process_that_already_exited(self):
        async def body():
            pid = await self.h.start("run", "exec sleep 60")
            proc = self.framer.PROCESSES[pid]
            os.kill(pid, signal.SIGKILL)
            await proc.wait()
            await proc.cleanup()
            self.assertEqual(proc.return_code, -signal.SIGKILL)
            self.framer.PROCESSES.pop(pid, None)
        self.run_async(body)


class LoginTests(CommandTestCase):
    def test_login_runs_the_shell_as_a_login_shell_in_the_directory(self):
        async def body():
            pid = await self.h.start("login", self.tmp, 'echo "argv0=$0 pwd=$(pwd -P)"')
            self.assertEqual(await self.h.wait_terminated(pid), 0)
            out = self.output(pid)
            self.assertIn(b"argv0=-sh", out)
            self.assertIn(("pwd=" + self.tmp).encode(), out)
            self.assertTrue(all(o.channel == -1 for o in self.h.parser.outputs(pid)),
                            "the login shell's output is on channel -1")
        self.run_async(body)
        self.assertNoParseErrors()

    def test_arguments_are_joined_into_one_command(self):
        async def body():
            pid = await self.h.start("login", self.tmp, "echo", "one", "two")
            await self.h.wait_terminated(pid)
            self.assertIn(b"one two", self.output(pid))
        self.run_async(body)

    def test_directory_expands_tilde_and_variables(self):
        async def body():
            with env(HOME=self.tmp, FRAMER_DIR="sub"):
                os.mkdir(os.path.join(self.tmp, "sub"))
                pid = await self.h.start("login", "~/$FRAMER_DIR", "pwd -P")
            await self.h.wait_terminated(pid)
            self.assertIn(os.path.join(self.tmp, "sub").encode(), self.output(pid))
        self.run_async(body)

    def test_missing_directory_fails(self):
        async def body():
            reply = await self.h.command("login", os.path.join(self.tmp, "nope"), "true")
            self.assertEqual(reply.status, 1)
            self.assertTrue(reply.lines[0].startswith("Command failed: "), reply)
        self.run_async(body)

    def test_login_shell_has_a_controlling_terminal_of_the_framers_size(self):
        async def body():
            with fake_stdin_size(33, 101):
                pid = await self.h.start("login", self.tmp, "stty size")
            await self.h.wait_terminated(pid)
            self.assertIn(b"33 101", self.output(pid))
        self.run_async(body)

    def test_window_size_changes_reach_programs(self):
        async def body():
            with fake_stdin_size(24, 80):
                pid = await self.h.start("login", self.tmp, "head -n 1 >/dev/null; stty size")
                await self.h.wait_for(lambda: self.framer.PROCESSES[pid].flow_source is not None)
            with fake_stdin_size(40, 132):
                await self.framer.update_pty_size()
            await self.h.command("send", str(pid), H.b64("\n"))
            await self.h.wait_terminated(pid)
            self.assertIn(b"40 132", self.output(pid))
        self.run_async(body)

    def test_window_size_change_skips_processes_without_a_pty(self):
        class NoPty:
            pane = False
            master = None

        async def body():
            self.framer.PROCESSES[1] = NoPty()
            try:
                with fake_stdin_size(40, 132):
                    await self.framer.update_pty_size()
            finally:
                del self.framer.PROCESSES[1]
        self.run_async(body)


class EvalTests(CommandTestCase):
    def test_runs_the_script_as_a_login_process(self):
        async def body():
            with env(HOME=self.tmp):
                pid = await self.h.start("eval", H.b64('echo "self=$SELF"; rm -f "$SELF"'))
            self.assertEqual(await self.h.wait_terminated(pid), 0)
            out = self.output(pid).decode()
            path = out.split("self=")[1].split()[0]
            self.assertEqual(os.path.dirname(path), os.path.join(self.tmp, ".iterm2"))
            self.assertFalse(os.path.exists(path), "the script removed itself")
            self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)
        self.run_async(body)

    def test_script_file_is_private_and_executable(self):
        with env(HOME=self.tmp):
            path = self.framer.write_exec_file("true\n")
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o700)
        with open(path) as f:
            self.assertEqual(f.read(), "true\n")

    def test_unwritable_home_fails(self):
        async def body():
            not_a_directory = os.path.join(self.tmp, "file")
            with open(not_a_directory, "w"):
                pass
            with env(HOME=not_a_directory):
                reply = await self.h.command("eval", H.b64("true"))
            self.assertEqual(reply.status, 1)
            self.assertTrue(reply.lines[0].startswith("Command failed: "), reply)
        self.run_async(body)

    # A jump script (Conductor.jumpScript) can mention a non-ASCII path or host name.
    def test_non_ascii_script_runs_unchanged(self):
        async def body():
            with env(HOME=self.tmp):
                pid = await self.h.start("eval", H.b64('printf "café"; rm -f "$SELF"'))
            await self.h.wait_terminated(pid)
            self.assertEqual(self.output(pid), "café".encode())
        self.run_async(body)


class GetenvTests(CommandTestCase):
    def getenv(self, name, **environment):
        result = []

        async def body():
            with env(**environment):
                result.append(await self.h.command("getenv", name))
        self.run_async(body)
        return result[0]

    def test_reads_the_variable_through_the_shell(self):
        reply = self.getenv("FRAMER_TEST_VAR", SHELL="/bin/sh", FRAMER_TEST_VAR="hello")
        self.assertEqual((reply.status, reply.lines), (0, ["hello"]))

    def test_unset_variable_is_empty(self):
        reply = self.getenv("FRAMER_TEST_UNSET", SHELL="/bin/sh", FRAMER_TEST_UNSET=None)
        self.assertEqual(reply.lines, [""])

    # When the shell cannot say, the framer's own environment, inherited from the login shell,
    # is the next best answer.
    def test_unknown_shell_falls_back_to_the_framers_environment(self):
        reply = self.getenv("FRAMER_TEST_VAR", SHELL="/opt/weird/shell", FRAMER_TEST_VAR="mine")
        self.assertEqual((reply.status, reply.lines), (0, ["mine"]))

    def test_failing_shell_falls_back_to_the_framers_environment(self):
        # XONSHRC says xonsh, and with an empty PATH there is no xonsh to run.
        reply = self.getenv("FRAMER_TEST_VAR", SHELL="/bin/sh", XONSHRC="/nonexistent",
                            PATH=self.tmp, FRAMER_TEST_VAR="mine")
        self.assertEqual((reply.status, reply.lines), (0, ["mine"]))

    def test_nothing_to_report_sends_no_value(self):
        # iTerm2 takes the first line as the value, so there must be none, not "None".
        reply = self.getenv("FRAMER_TEST_UNSET", SHELL="/opt/weird/shell", FRAMER_TEST_UNSET=None)
        self.assertEqual((reply.status, reply.lines), (1, []))

    def test_value_is_not_split_globbed_or_taken_as_an_option(self):
        for value in ["a  b *", "-n", "back\\slash \\n"]:
            reply = self.getenv("FRAMER_TEST_VAR", SHELL="/bin/sh", FRAMER_TEST_VAR=value)
            self.assertEqual(reply.lines, [value])

    def test_a_name_that_is_not_a_variable_is_not_run(self):
        marker = os.path.join(self.tmp, "ran")
        reply = self.getenv("X;touch %s" % marker, SHELL="/bin/sh")
        self.assertFalse(os.path.exists(marker))
        self.assertEqual(reply.status, 1)


class RunpyTests(CommandTestCase):
    def runpy(self, script):
        result = []

        async def body():
            result.append(await self.h.command("runpy", H.b64(script)))
        self.run_async(body)
        self.assertNoParseErrors()
        return result[0]

    def test_returns_a_string(self):
        reply = self.runpy("import os\nx = 6 * 7\nreturn str(x)")
        self.assertEqual((reply.status, reply.lines), (0, ["42"]))

    def test_none_is_empty(self):
        self.assertEqual(self.runpy("pass").lines, [""])

    def test_non_strings_are_converted(self):
        self.assertEqual(self.runpy("return [1, 2]").lines, ["[1, 2]"])

    def test_exception_returns_the_traceback(self):
        reply = self.runpy("raise ValueError('boom')")
        self.assertEqual(reply.status, 1)
        self.assertIn("ValueError: boom", reply.lines[0])

    def test_syntax_error(self):
        self.assertEqual(self.runpy("return (").status, 1)

    def test_bad_base64(self):
        async def body():
            reply = await self.h.command("runpy", "abc")
            self.assertEqual(reply.status, 1)
        self.run_async(body)


class RegistrationTests(CommandTestCase):
    def test_register_and_deregister(self):
        async def body():
            self.assertEqual((await self.h.command("register", "10")).status, 0)
            await self.h.command("register", "10")
            await self.h.command("register", "11")
            self.assertEqual(self.framer.REGISTERED, [10, 11])
            self.assertEqual((await self.h.command("deregister", "10")).status, 0)
            await self.h.command("deregister", "12")
            self.assertEqual(self.framer.REGISTERED, [11])
        self.run_async(body)

    def test_bad_arguments(self):
        async def body():
            for command in ("register", "deregister"):
                self.assertEqual((await self.h.command(command)).status, 1)
                self.assertEqual((await self.h.command(command, "x")).status, 1)
            self.assertEqual(self.framer.REGISTERED, [])
        self.run_async(body)

    def test_reset_forgets_registrations(self):
        async def body():
            await self.h.command("register", "10")
            self.framer.LASTPS = {"10": ()}
            self.framer.AUTOPOLL = 1
            self.assertEqual((await self.h.command("reset")).status, 0)
            self.assertEqual((self.framer.REGISTERED, self.framer.LASTPS, self.framer.AUTOPOLL),
                             ([], {}, 0))
            await self.h.command("register", "10")
            reply = await self.h.command("reset2", "CODE-123")
            self.assertEqual((reply.status, reply.lines), (0, ["CODE-123"]))
            self.assertEqual(self.framer.REGISTERED, [])
        self.run_async(body)


PS_OUTPUT = b"""  PID  PPID STAT STARTED                      COMMAND
    1     0 Ss   Mon Oct 12 09:00:00 2026     /sbin/launchd
  100     1 S    Mon Oct 12 09:00:01 2026     -zsh
  101   100 S+   Mon Oct 12 09:00:02 2026     vim notes.txt
  102   101 Z    Mon Oct 12 09:00:03 2026     (defunct)
  103   101 S    Mon Oct 12 09:00:04 2026     python3 helper.py --flag
  200     1 S    Mon Oct 12 09:00:05 2026     unrelated
garbage line
"""


class PollTests(CommandTestCase):
    def test_procmon_reports_registered_trees_as_a_diff(self):
        framer = self.framer
        framer.REGISTERED = [100]
        first = framer.procmon_parse(PS_OUTPUT)
        self.assertEqual(sorted(first), [
            "+100 1 S Mon Oct 12 09:00:01 2026 -zsh",
            "+101 100 S+ Mon Oct 12 09:00:02 2026 vim notes.txt",
            "+103 101 S Mon Oct 12 09:00:04 2026 python3 helper.py --flag"])
        self.assertEqual(framer.procmon_parse(PS_OUTPUT), [], "no change, no diff")
        changed = PS_OUTPUT.replace(b"101   100 S+", b"101   100 T+").replace(
            b"  103   101 S    Mon Oct 12 09:00:04 2026     python3 helper.py --flag\n", b"")
        self.assertEqual(sorted(framer.procmon_parse(changed)), [
            "-103", "~101 100 T+ Mon Oct 12 09:00:02 2026 vim notes.txt"])

    def test_procmon_ignores_unregistered_and_missing_pids(self):
        self.framer.REGISTERED = [999]
        self.assertEqual(self.framer.procmon_parse(PS_OUTPUT), [])

    def test_poll_reports_categories(self):
        async def fake_cpu():
            return ["=12.5%"]

        async def body():
            self.framer.REGISTERED = [os.getpid()]
            with patched(self.framer, "poll_cpu", fake_cpu):
                result = await self.framer.poll()
            self.assertEqual(result["cpu"], ["=12.5%"])
            self.assertTrue(any(line.startswith("+%d " % os.getpid()) for line in result["ps"]),
                            result["ps"])
        self.run_async(body)

    def test_poll_cpu_parses_top(self):
        fake_top = os.path.join(self.tmp, "top")
        with open(fake_top, "w") as f:
            f.write("#!/bin/sh\necho 'CPU usage: 7.5% user, 2.5% sys, 90.0% idle'\n")
        os.chmod(fake_top, 0o755)

        async def body():
            with patched(self.framer.platform, "system", lambda: "Darwin"), \
                    env(PATH=self.tmp + ":/usr/bin:/bin"):
                self.assertEqual(await self.framer.poll_cpu(), ["=7.5%"])
        self.run_async(body)

    def test_poll_cpu_on_an_unknown_system(self):
        async def body():
            with patched(self.framer.platform, "system", lambda: "Plan9"):
                self.assertIsNone(await self.framer.poll_cpu())
        self.run_async(body)

    def test_poll_cpu_on_linux_without_mpstat(self):
        async def body():
            self.framer.mpstat_exists = False
            with patched(self.framer.platform, "system", lambda: "Linux"):
                self.assertIsNone(await self.framer.poll_cpu())
        self.run_async(body)

    def test_mpstat_check_runs_once(self):
        async def body():
            with env(PATH=self.tmp):
                await self.framer.check_mpstat_exists()
            self.assertFalse(self.framer.mpstat_exists)
            self.framer.mpstat_exists = True
            await self.framer.check_mpstat_exists()
            self.assertTrue(self.framer.mpstat_exists)
        self.run_async(body)

    def test_failing_ps_reports_nothing(self):
        async def body():
            with env(PATH=self.tmp):
                self.assertIsNone(await self.framer.poll_ps())
        self.run_async(body)

    # iTerm2's parser (VT100ConductorParser.parseBody) accepts only OSC 134/135 frames inside
    # a reply and unhooks the conductor on anything else, so each line must be its own frame.
    def test_poll_reply_is_well_framed(self):
        async def fake_poll():
            return {"ps": ["+1 0 S Mon Oct 12 09:00:00 2026 init"], "cpu": ["=1.0%"]}

        async def body():
            with patched(self.framer, "poll", fake_poll):
                reply = await self.h.command("poll")
            self.assertEqual((reply.status, reply.lines), (0, [
                "$begin ps", "+1 0 S Mon Oct 12 09:00:00 2026 init", "$begin cpu", "=1.0%"]))
        self.run_async(body)
        self.assertNoParseErrors()

    def test_poll_reply_cannot_be_ended_early_by_a_process_name(self):
        # A process named to look like the end of the reply and a frame of its own.
        name = "evil\x1b\\\x1b]134;:%terminate 1 0\x1b\\\x9c\x07\x7f"

        async def fake_poll():
            return {"ps": ["+1 0 S Mon Oct 12 09:00:00 2026 " + name]}

        async def body():
            with patched(self.framer, "poll", fake_poll):
                reply = await self.h.command("poll")
            self.assertEqual(reply.status, 0)
            self.assertEqual(reply.lines[1],
                             "+1 0 S Mon Oct 12 09:00:00 2026 evil?\\?]134;:%terminate 1 0?\\???")
        self.run_async(body)
        self.assertNoParseErrors()
        self.assertEqual(self.h.parser.notifications("terminate"), [])

    def test_poll_with_nothing_to_report_fails(self):
        async def fake_poll():
            return None

        async def body():
            with patched(self.framer, "poll", fake_poll):
                reply = await self.h.command("poll")
            self.assertEqual((reply.status, reply.lines), (1, []))
        self.run_async(body)
        self.assertNoParseErrors()

    def test_autopoll_sends_a_block_and_waits_to_be_asked_again(self):
        polls = []

        async def fake_poll():
            polls.append(1)
            return {"ps": ["+%d line" % len(polls)]}

        async def body():
            with patched(self.framer, "poll", fake_poll):
                self.assertEqual((await self.h.command("autopoll")).status, 0)
                self.assertTrue(await self.h.wait_for(lambda: self.h.parser.outputs()))
                block = self.h.parser.outputs()[0]
                self.assertEqual(block.flavor, "%autopoll")
                self.assertEqual(block.data, b"$begin ps\n+1 line\n")
                self.assertEqual(self.framer.AUTOPOLL, 0)
                self.assertEqual(len(polls), 1)
                # A second autopoll re-arms the running task rather than starting another.
                task = self.framer.AUTOPOLL_TASK
                await self.h.command("autopoll")
                self.assertIs(self.framer.AUTOPOLL_TASK, task)
                self.assertTrue(await self.h.wait_for(lambda: len(self.h.parser.outputs()) == 2))
                self.assertEqual(self.h.parser.outputs()[1].data, b"$begin ps\n+2 line\n")
                # quit cancels it.
                await self.h.command("quit")
                self.assertIsNone(self.framer.AUTOPOLL_TASK)
                self.assertTrue(task.cancelled())
        self.run_async(body)
        self.assertNoParseErrors()

    def test_autopoll_survives_nothing_to_report_and_stops_on_error(self):
        results = [{}, RuntimeError("ps exploded")]

        async def fake_poll():
            r = results.pop(0)
            if isinstance(r, Exception):
                raise r
            return r

        async def body():
            with patched(self.framer, "poll", fake_poll):
                await self.h.command("autopoll")
                task = self.framer.AUTOPOLL_TASK
                # Still armed (nothing has been reported), so a second request is a no-op.
                self.assertEqual((await self.h.command("autopoll")).status, 0)
                self.assertIs(self.framer.AUTOPOLL_TASK, task)
                await asyncio.wait_for(task, H.TIMEOUT)
            self.assertEqual(results, [])
            self.assertEqual(self.h.parser.outputs(), [])
        self.run_async(body)


class SaveAndRecoverTests(CommandTestCase):
    def recovery_lines(self):
        return [e.text for e in self.h.parser.events
                if isinstance(e, H.Event) and e.kind == "recovery"]

    def test_save_and_recover(self):
        self.h.parser = H.FrameParser()

        async def body():
            pid = await self.h.start("login", self.tmp, "exec cat")
            other = await self.h.start("run", "exec cat")
            reply = await self.h.command("save", "dcsID=abc", "sshargs=-p 22 host=x")
            self.assertEqual(reply.status, 0)
            await self.h.command("register", "5")
            # A new iTerm2 attaches: its parser starts in recovery mode.
            self.h.parser = H.FrameParser(recovery_mode=True)
            self.assertIsNone(await self.h.command("recover"))
            lines = self.recovery_lines()
            self.assertEqual(lines[0], "begin-recovery")
            self.assertEqual(lines[1], "recovery: version 2")
            self.assertEqual(lines[-1], "end-recovery")
            self.assertIn("recovery: login %d" % pid, lines)
            self.assertIn("recovery: dcsID abc", lines)
            self.assertIn("recovery: sshargs -p 22 host=x", lines)
            self.assertIn("recovery: process %d" % other, lines)
            self.assertEqual(self.framer.REGISTERED, [], "recovery resets registrations")
            # The session carries on.
            await self.h.command("send", str(pid), H.b64("after\n"))
            self.assertTrue(await self.h.wait_for(lambda: b"after" in self.output(pid)))
        self.run_async(body)
        self.assertNoParseErrors()

    def test_save_rejects_a_pair_without_equals(self):
        async def body():
            await self.h.command("save", "a=1")
            reply = await self.h.command("save", "novalue")
            self.assertEqual(reply.status, 1)
            self.assertEqual(self.framer.RECOVERY_STATE, {"a": "1"}, "left as it was")
        self.run_async(body)

    def test_recover_aborts_it2_connections(self):
        class Transport:
            aborted = False

            def abort(self):
                Transport.aborted = True

        class Writer:
            transport = Transport()

        async def body():
            self.framer.IT2_CONNS["c1"] = Writer()
            await self.h.command("recover")
            self.assertEqual(self.framer.IT2_CONNS, {})
            self.assertTrue(Transport.aborted)
        self.run_async(body)


class QuitTests(CommandTestCase):
    def test_quit_replies_then_goes_quiet(self):
        async def body():
            reply = await self.h.command("quit")
            self.assertEqual(reply.status, 0)
            self.assertTrue(self.framer.QUITTING)
            before = bytes(self.h.raw)
            q = self.framer.lock()
            self.framer.send_esc(q, "%notif late")
            self.framer.send(q, b"late output")
            self.framer.unlock(q)
            self.assertEqual(bytes(self.h.raw), before)
        self.run_async(body)


class PingTests(H.FramerTestCase):
    def test_ping_is_squelched_before_anything_runs(self):
        self.framer.ping()
        self.assertEqual(bytes(self.h.raw), b"")
        self.framer.PROCESSES[1] = None
        try:
            self.framer.ping()
        finally:
            del self.framer.PROCESSES[1]
        self.assertEqual(bytes(self.h.raw), b"\x1b]134;:%ping\x1b\\")


class WriterTests(H.FramerTestCase):
    def test_write_all_retries_partial_and_interrupted_writes(self):
        written = []
        calls = []

        def fake_write(fd, data):
            calls.append(len(data))
            if len(calls) == 2:
                raise InterruptedError()
            n = min(3, len(data))
            written.append(bytes(data[:n]))
            return n

        with patched(self.framer.os, "write", fake_write):
            self.framer._write_all.__func__ if False else None
            write_all = H.load_framer("framer_writer_under_test")._write_all
            write_all(1, "hello world")
        self.assertEqual(b"".join(written), b"hello world")

    def test_write_all_gives_up_when_nothing_is_written(self):
        calls = []

        def fake_write(fd, data):
            calls.append(1)
            return 0

        write_all = H.load_framer("framer_writer_under_test2")._write_all
        with patched(os, "write", fake_write):
            write_all(1, b"abc")
        self.assertEqual(len(calls), 1)

    def test_unlock_writes_every_frame_to_stdout(self):
        self.framer.unlock(["\x1b]134;:%ping\x1b\\", b"raw"])
        self.assertEqual(bytes(self.h.raw), b"\x1b]134;:%ping\x1b\\raw")
        self.framer.unlock([])

    @unittest.skipIf(sys.version_info < (3, 8),
                     "sys.unraisablehook is new in 3.8; before that the framer never calls it")
    def test_shutdown_noise_is_silenced_and_other_errors_are_not(self):
        class Unraisable:
            def __init__(self, exc):
                self.exc_value = exc

        seen = []
        with patched(sys, "__unraisablehook__", seen.append):
            self.framer._silence_shutdown_unraisable(
                Unraisable(RuntimeError("Event loop is closed")))
            self.assertEqual(seen, [])
            other = Unraisable(ValueError("real"))
            self.framer._silence_shutdown_unraisable(other)
            self.assertEqual(seen, [other])


class CommandReaderTests(H.FramerTestCase):
    def test_parse_grant(self):
        parse = self.framer._parse_grant
        grant = H.b64("grant")
        self.assertEqual(parse([grant, H.b64("100"), ""]), ("leader", 100))
        self.assertEqual(parse([grant[:3] + "\\", grant[3:], H.b64("7"), ""]), ("leader", 7))
        self.assertEqual(parse([grant, H.b64("it2"), H.b64("9"), ""]), ("it2", 9))
        self.assertEqual(parse([grant, H.b64("leader"), H.b64("0"), ""]), ("leader", 0))
        self.assertEqual(parse([grant, H.b64("4321"), H.b64("50"), ""]), (4321, 50))
        self.assertIsNone(parse([grant, H.b64("-5"), H.b64("50"), ""]))
        self.assertIsNone(parse([grant, H.b64("nobody"), H.b64("50"), ""]))
        self.assertIsNone(parse([grant, H.b64("-1"), ""]))
        self.assertIsNone(parse([grant, H.b64("lots"), ""]))
        self.assertIsNone(parse([grant, ""]))
        self.assertIsNone(parse([H.b64("ping"), H.b64("1"), ""]))

    def test_end_of_input_and_read_errors_end_the_stream(self):
        class Broken:
            def readline(self):
                raise OSError("gone")

        async def body():
            for stream in (io.StringIO(H.b64("ping") + "\n"), Broken()):
                queue = asyncio.Queue()
                thread = threading.Thread(target=self.framer.command_reader,
                                          args=(stream, asyncio.get_event_loop(), queue),
                                          daemon=True)
                thread.start()
                lines = []
                while True:
                    line = await asyncio.wait_for(queue.get(), H.TIMEOUT)
                    if line is None:
                        break
                    lines.append(line)
                thread.join(H.TIMEOUT)
                self.assertIn(lines, ([H.b64("ping")], []))
        self.run_async(body)


class TtyWatchTests(CommandTestCase):
    def test_echo_icanon_of_a_closed_fd_raises(self):
        r, w = os.pipe()
        os.close(r)
        os.close(w)
        with self.assertRaises(Exception):
            self.framer.get_echo_icanon(r)

    def test_watch_tty_stops_when_the_pty_is_gone(self):
        class Gone:
            master = -1
            echo = True
            icanon = True

        async def body():
            await asyncio.wait_for(self.framer.watch_tty(Gone(), 0), H.TIMEOUT)
        self.run_async(body)

    def test_watch_tty_reports_changes_made_without_output(self):
        async def body():
            pid = await self.h.start("run", "exec cat")
            proc = self.framer.PROCESSES[pid]
            attrs = termios.tcgetattr(proc.master)
            attrs[3] &= ~termios.ICANON
            termios.tcsetattr(proc.master, termios.TCSANOW, attrs)
            self.assertTrue(await self.h.wait_for(
                lambda: any(e.text == "tty +echo -icanon"
                            for e in self.h.parser.notifications("notif"))))
        self.run_async(body)


class PaneArgumentTests(CommandTestCase):
    """framer_pane_test.py covers panes; these are its remaining error paths."""

    def test_sizes_out_of_range_fail(self):
        async def body():
            for rows, cols in (("0", "80"), ("24", "10001"), ("-1", "80")):
                reply = await self.h.command("pane", rows, cols, self.tmp, "true")
                self.assertEqual(reply.status, 1, (rows, cols))
            self.assertEqual((await self.h.command("pane", "24", "80", self.tmp)).status, 1,
                             "no command")
            self.assertEqual((await self.h.command("panesize", "1", "0", "80")).status, 1)
        self.run_async(body)

    def test_missing_directory_fails(self):
        async def body():
            reply = await self.h.command("pane", "24", "80", os.path.join(self.tmp, "no"), "true")
            self.assertEqual(reply.status, 1)
            self.assertTrue(reply.lines[0].startswith("Command failed: "), reply)
        self.run_async(body)


class FlowGapTests(H.FramerTestCase):
    """Corners of flow control that framer_flow_test.py leaves out."""

    def test_grant_and_drain_do_nothing_while_off(self):
        flow = self.framer.FlowControl(lambda: 0.0)
        flow.grant(100)
        flow.drain()
        self.assertEqual((flow.credit, flow.draining), (0, False))

    def test_echo_allowance_delay(self):
        clock = [0.0]
        flow = self.framer.FlowControl(lambda: clock[0])
        flow.enable()
        self.assertEqual(flow.echo_allowance_delay(10), 0.0)
        self.assertTrue(flow.take_echo_allowance(256))
        self.assertAlmostEqual(flow.echo_allowance_delay(256),
                               256 / self.framer.FLOW_ECHO_REFILL)

    def test_the_valve_is_announced(self):
        clock = [1000.0]
        framer = self.framer

        async def body():
            framer.FLOW = framer.FlowControl(lambda: clock[0])
            framer.FLOW.enable()
            framer.FLOW.spend(framer.FLOW_INITIAL_CREDIT)
            r, w = os.pipe()
            source = framer.FlowSource(r, lambda *a: None, 1, None)
            source.ready = True
            framer.SOURCES.append(source)
            try:
                framer._flow_tick()  # Output begins waiting.
                clock[0] += 6
                framer.FLOW.note_command()
                framer._flow_tick()
                self.assertIn("valve", [e.text for e in self.h.parser.notifications("notif")])
            finally:
                framer.remove_source(source)
                os.close(r)
                os.close(w)
                if framer.FLOW_TICK_HANDLE is not None:
                    framer.FLOW_TICK_HANDLE.cancel()
                framer.FLOW.disable()
        self.run_async(body)

    def test_it2_data_waits_out_a_drain(self):
        framer = self.framer

        async def body():
            framer.FLOW.enable()
            framer.FLOW.drain()
            gate = asyncio.ensure_future(framer.it2_gate())
            for _ in range(10):
                await asyncio.sleep(0)
            self.assertFalse(gate.done(), "held during the drain")
            framer.flow_grant(100)
            await asyncio.wait_for(gate, H.TIMEOUT)
            framer.FLOW.drain()
            framer.flow_changed()
            self.assertFalse(framer.IT2_GATE.is_set())
            framer.flow_grant(1)
            if framer.FLOW_TICK_HANDLE is not None:
                framer.FLOW_TICK_HANDLE.cancel()
            framer.FLOW.disable()
        self.run_async(body)


class It2ErrorTests(CommandTestCase):
    """framer_it2_test.py covers the socket proxy; these are its argument errors."""

    def test_errors(self):
        async def body():
            self.assertEqual((await self.h.command("it2listen")).status, 1)
            self.assertEqual((await self.h.command("it2send", "nope", H.b64("x"))).status, 1)
            self.assertEqual((await self.h.command("it2send", "nope")).status, 1)
            self.assertEqual((await self.h.command("it2close")).status, 0)
            self.assertEqual((await self.h.command("it2close", "nope")).status, 0)
            path = os.path.join(self.tmp, "s")
            self.assertEqual((await self.h.command("it2listen", path)).status, 0)
            self.assertEqual((await self.h.command("it2listen", path + "2")).status, 0,
                             "already listening")
            self.assertFalse(os.path.exists(path + "2"))
        self.run_async(body)

    def test_bad_base64_drops_the_frame_but_keeps_the_connection(self):
        class Transport:
            def get_write_buffer_size(self):
                return 0

        class Writer:
            transport = Transport()

            def write(self, data):
                raise AssertionError("nothing should be written")

        async def body():
            self.framer.IT2_CONNS["c1"] = Writer()
            # Bad padding; b64decode only skips characters outside the alphabet.
            self.assertEqual((await self.h.command("it2send", "c1", "abc")).status, 1)
            self.assertIn("c1", self.framer.IT2_CONNS)
            self.framer.IT2_CONNS = {}
        self.run_async(body)


class CleanupTests(H.FramerTestCase):
    def test_completed_pids_already_forgotten_are_skipped(self):
        async def body():
            self.framer.COMPLETED = [123456789]
            await self.framer.cleanup()
            self.assertEqual(self.framer.COMPLETED, [])
        self.run_async(body)
        self.assertEqual(bytes(self.h.raw), b"")


class PythonCompatibilityTests(unittest.TestCase):
    """The oldest Python iTerm2 accepts on a remote host is 3.7
    (Conductor.minimumPythonMinorVersion), so framer.py must not use anything newer. These
    are static checks: they run on the local python3, which is newer."""

    # Library APIs added after 3.7, by attribute name.
    NEWER_APIS = {
        "removeprefix": "str.removeprefix (3.9)",
        "removesuffix": "str.removesuffix (3.9)",
        "to_thread": "asyncio.to_thread (3.9)",
        "prod": "math.prod (3.8)",
        "isqrt": "math.isqrt (3.8)",
        "cache": "functools.cache (3.9)",
        "cached_property": "functools.cached_property (3.8)",
        "waitstatus_to_exitcode": "os.waitstatus_to_exitcode (3.9)",
        "TaskGroup": "asyncio.TaskGroup (3.11)",
        "timeout": "asyncio.timeout (3.11)",
        "pidfd_open": "os.pidfd_open (3.9)",
    }
    GENERIC_BUILTINS = {"list", "dict", "tuple", "set", "frozenset", "type"}

    @classmethod
    def setUpClass(cls):
        with open(H.FRAMER_PATH) as f:
            cls.source = f.read()
        cls.tree = ast.parse(cls.source)

    @unittest.skipIf(sys.version_info < (3, 8),
                     "feature_version needs 3.8; running under 3.7 checks this directly")
    def test_syntax_is_python_3_7(self):
        # Rejects the walrus operator, positional-only parameters, match, parenthesized
        # context managers and other syntax newer than 3.7.
        ast.parse(self.source, feature_version=(3, 7))

    def test_no_dict_union_or_runtime_builtin_generics(self):
        found = []
        for node in ast.walk(self.tree):
            annotations = []
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                args = node.args
                annotations += [a.annotation for a in args.args + args.kwonlyargs if a.annotation]
                annotations.append(node.returns)
            for annotation in annotations:
                for sub in ast.walk(annotation) if annotation is not None else ():
                    if (isinstance(sub, ast.Subscript) and isinstance(sub.value, ast.Name) and
                            sub.value.id in self.GENERIC_BUILTINS):
                        found.append("line %d: %s[...] annotation" % (sub.lineno, sub.value.id))
            if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitOr) and (
                    isinstance(node.left, (ast.Dict, ast.DictComp)) or
                    isinstance(node.right, (ast.Dict, ast.DictComp))):
                found.append("line %d: dict | dict (3.9)" % node.lineno)
        self.assertEqual(found, [])

    def test_no_library_apis_newer_than_3_7(self):
        found = ["line %d: %s" % (node.lineno, self.NEWER_APIS[node.attr])
                 for node in ast.walk(self.tree)
                 if isinstance(node, ast.Attribute) and node.attr in self.NEWER_APIS]
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()
