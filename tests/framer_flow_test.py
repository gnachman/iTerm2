#!/usr/bin/env python3
"""Exercises framer.py's flow control: iTerm2 grants the framer credit, and the framer reads its
programs' output only while it has credit, so a backlog stays in the remote pty where Ctrl-C
discards it. Credit is counted in bytes read from the source. A drain zeroes credit; a safety
valve trickles output if the controller looks dead; the login shell gets a small allowance
outside credit so echo is not held behind a flooding side command. In version 1 there is one
flow. In version 2 the leader (login shell and side commands), each pane and it2 have credit of
their own, so a peer whose session reads slowly holds back only itself.

The first group drives FlowControl directly on a fake clock. The second runs real programs on
ptys through the framer's handlers and its read pump.

Run: python3 tests/framer_flow_test.py
"""
import asyncio
import base64
import importlib.util
import io
import os
import sys
import threading
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMER_PATH = os.path.join(HERE, "..", "OtherResources", "framer.py")

_spec = importlib.util.spec_from_file_location("framer_under_test", FRAMER_PATH)
framer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(framer)
framer.DEPTH = 0

_frames = []
framer.unlock = lambda writes: _frames.extend(
    w if isinstance(w, str) else w.decode("latin-1") for w in writes
)

OSC = "\033]134;:"
ST = "\033\\"


class FakeClock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t

    def advance(self, seconds):
        self.t += seconds


class FlowControlTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.flow = framer.FlowControl(self.clock)

    def test_off_by_default_reads_as_today(self):
        self.assertFalse(self.flow.enabled)
        self.assertEqual(self.flow.budget(), 4096)
        self.flow.spend(4096)
        self.assertEqual(self.flow.budget(), 4096)
        self.assertEqual(self.flow.take_flags(), 0)

    def test_enabling_grants_the_initial_credit(self):
        self.flow.enable()
        self.assertEqual(self.flow.credit, 8192)
        self.assertEqual(self.flow.budget(), 4096)
        self.flow.spend(4096)
        self.flow.spend(4000)
        self.assertEqual(self.flow.budget(), 96)

    def test_running_out_of_credit_marks_the_next_frame_limited(self):
        self.flow.enable()
        self.flow.spend(8000)
        self.assertEqual(self.flow.take_flags(), 0)
        self.flow.spend(192)
        self.assertEqual(self.flow.budget(), 0)
        self.assertEqual(self.flow.take_flags(), framer.FLOW_FLAG_LIMITED)
        self.assertEqual(self.flow.take_flags(), 0, "reported once")

    def test_grants_add_up(self):
        self.flow.enable()
        self.flow.spend(8192)
        self.flow.grant(100)
        self.flow.grant(50)
        self.assertEqual(self.flow.credit, 150)

    def test_a_drain_zeroes_credit_until_the_next_grant(self):
        self.flow.enable()
        self.flow.drain()
        self.assertTrue(self.flow.draining)
        self.assertEqual(self.flow.budget(), 0)
        self.flow.grant(1000)
        self.assertFalse(self.flow.draining)
        self.assertEqual(self.flow.credit, 1000)

    def test_a_drain_with_no_grant_ends_itself_after_ten_seconds(self):
        self.flow.enable()
        self.flow.drain()
        self.clock.advance(9.9)
        self.flow.tick(waiting=True)
        self.assertTrue(self.flow.draining)
        self.clock.advance(0.2)
        self.flow.tick(waiting=True)
        self.assertFalse(self.flow.draining)
        self.assertEqual(self.flow.credit, framer.FLOW_DRAIN_FLOOR)

    def test_the_valve_fires_when_grants_stop_but_commands_continue(self):
        self.flow.enable()
        self.flow.spend(8192)
        for _ in range(12):
            self.clock.advance(0.5)
            self.flow.note_command()
            fired = self.flow.tick(waiting=True)
            # Output began waiting at the first tick, half a second in.
            if self.clock.t - 1000.5 < framer.FLOW_VALVE_SILENCE:
                self.assertFalse(fired)
        self.assertTrue(self.flow.valve_open)
        self.assertGreater(self.flow.credit, 0)

    def test_the_valve_trickles_four_kilobytes_a_second(self):
        self.flow.enable()
        self.flow.spend(8192)
        fired = []
        for _ in range(40):
            self.clock.advance(0.25)
            self.flow.note_command()
            fired.append(self.flow.tick(waiting=True))
        self.assertEqual(fired.count(True), 1, "reported once")
        # Open from t=5 s to t=10 s: about 5 seconds at 4 KB/s.
        self.assertAlmostEqual(self.flow.credit, 5 * framer.FLOW_VALVE_RATE, delta=framer.FLOW_VALVE_RATE)

    def test_a_flood_after_a_quiet_spell_gets_time_for_a_grant(self):
        # An idle iTerm2 sends no grants, so the last one can be minutes old when a program
        # starts flooding. The silence that matters starts when output begins to wait.
        self.flow.enable()
        self.clock.advance(120)
        self.flow.spend(8192)
        self.flow.note_command()
        self.clock.advance(0.25)
        self.assertFalse(self.flow.tick(waiting=True))
        self.clock.advance(4.5)
        self.flow.note_command()
        self.assertFalse(self.flow.tick(waiting=True))
        self.assertFalse(self.flow.valve_open)
        self.clock.advance(0.5)
        self.assertTrue(self.flow.tick(waiting=True))

    def test_waiting_that_stops_restarts_the_count(self):
        self.flow.enable()
        self.flow.spend(8192)
        for _ in range(4):
            self.clock.advance(1)
            self.flow.note_command()
            self.assertFalse(self.flow.tick(waiting=True))
        self.flow.tick(waiting=False)
        for _ in range(4):
            self.clock.advance(1)
            self.flow.note_command()
            self.assertFalse(self.flow.tick(waiting=True))
        self.assertFalse(self.flow.valve_open)

    def test_the_valve_stays_shut_when_nothing_is_waiting(self):
        self.flow.enable()
        self.clock.advance(6)
        self.flow.note_command()
        self.assertFalse(self.flow.tick(waiting=False))
        self.assertFalse(self.flow.valve_open)

    def test_the_valve_stays_shut_when_no_commands_arrive(self):
        # iTerm2 is gone or frozen: nothing is reading, so keep holding.
        self.flow.enable()
        self.flow.spend(8192)
        self.clock.advance(6)
        self.assertFalse(self.flow.tick(waiting=True))

    def test_the_valve_stays_shut_during_a_drain(self):
        self.flow.enable()
        self.flow.drain()
        self.clock.advance(6)
        self.flow.note_command()
        self.assertFalse(self.flow.tick(waiting=True))

    def test_a_heartbeat_keeps_the_valve_shut(self):
        self.flow.enable()
        self.flow.spend(8192)
        for _ in range(40):
            self.clock.advance(0.25)
            self.flow.note_command()
            if int(self.clock.t * 4) % 4 == 0:
                self.flow.grant(0)
            self.assertFalse(self.flow.tick(waiting=True))
        self.assertEqual(self.flow.credit, 0)

    def test_a_drain_stops_the_valve(self):
        self.flow.enable()
        self.flow.spend(8192)
        self.flow.tick(waiting=True)  # Output begins waiting.
        self.clock.advance(6)
        self.flow.note_command()
        self.assertTrue(self.flow.tick(waiting=True))
        self.flow.drain()
        self.assertFalse(self.flow.valve_open)
        self.assertEqual(self.flow.credit, 0)

    def test_recovery_keeps_flow_control_on_with_no_credit(self):
        self.flow.enable()
        self.flow.recover()
        self.assertTrue(self.flow.enabled)
        self.assertEqual(self.flow.budget(), 0)
        self.assertTrue(self.flow.draining)

    def test_recovery_leaves_flow_control_off_if_it_was_off(self):
        self.flow.recover()
        self.assertFalse(self.flow.enabled)
        self.assertEqual(self.flow.budget(), 4096)

    def test_the_echo_allowance_is_for_small_writes_only(self):
        self.flow.enable()
        self.flow.spend(8192)
        self.assertFalse(self.flow.take_echo_allowance(257))
        self.assertTrue(self.flow.take_echo_allowance(3))
        self.assertEqual(self.flow.credit, 0, "the allowance is not credit")

    def test_the_echo_allowance_refills_at_its_rate(self):
        self.flow.enable()
        self.flow.spend(8192)
        self.assertTrue(self.flow.take_echo_allowance(256))
        self.assertFalse(self.flow.take_echo_allowance(1))
        self.clock.advance(0.1)  # 256 bytes at 2.5 KB/s
        self.assertTrue(self.flow.take_echo_allowance(250))
        self.assertFalse(self.flow.take_echo_allowance(10))

    def test_the_echo_allowance_is_off_without_flow_control(self):
        self.assertFalse(self.flow.take_echo_allowance(3))

    # Version 2: a flow per source.

    def test_version_one_has_a_single_flow_and_leaves_it2_alone(self):
        self.flow.enable(1)
        self.flow.spend(4096, 77)
        self.assertEqual(self.flow.credit, 4096, "a pane spends the leader's credit")
        self.assertFalse(self.flow.controls(framer.FLOW_IT2))
        self.assertEqual(self.flow.budget(framer.FLOW_IT2), 4096)
        self.flow.grant(10, 77)
        self.assertEqual(self.flow.credit, 4106)

    def test_each_flow_has_its_own_credit(self):
        self.flow.enable(2)
        self.assertEqual(self.flow.budget(77), 0, "a pane waits for a grant of its own")
        self.assertEqual(self.flow.budget(framer.FLOW_IT2), 0)
        self.flow.grant(5000, 77)
        self.flow.spend(5000, 77)
        self.assertEqual(self.flow.credit, 8192, "the leader's credit is untouched")
        self.assertEqual(self.flow.budget(77), 0)
        self.assertEqual(self.flow.take_flags(flow=77), framer.FLOW_FLAG_LIMITED)
        self.assertEqual(self.flow.take_flags(), 0, "only the pane ran out")

    def test_a_drain_zeroes_every_flow(self):
        self.flow.enable(2)
        self.flow.grant(100, 77)
        self.flow.grant(100, framer.FLOW_IT2)
        self.flow.drain()
        self.assertEqual([self.flow.budget(f) for f in (framer.FLOW_LEADER, 77, framer.FLOW_IT2)],
                         [0, 0, 0])
        self.flow.grant(50, 77)
        self.assertFalse(self.flow.draining, "a grant to any flow ends the drain")

    def test_the_valve_trickles_to_the_flows_that_wait(self):
        self.flow.enable(2)
        self.flow.spend(8192)
        for _ in range(40):
            self.clock.advance(0.25)
            self.flow.note_command()
            self.flow.tick(waiting={77, framer.FLOW_LEADER})
        self.assertTrue(self.flow.valve_open)
        self.assertGreater(self.flow.credit_of(77), 0)
        self.assertGreater(self.flow.credit, 0)
        self.assertEqual(self.flow.credit_of(framer.FLOW_IT2), 0, "it2 was not waiting")

    def test_an_ended_pane_is_forgotten(self):
        self.flow.enable(2)
        self.flow.grant(100, 77)
        self.flow.forget(77)
        self.assertEqual(self.flow.credit_of(77), 0)
        self.assertNotIn(77, self.flow.credits)


# Integration: real programs on ptys.

def payloads():
    result = []
    current = None
    for f in _frames:
        if f.startswith(OSC) and f.endswith(ST):
            p = f[len(OSC):-len(ST)]
            if current is not None and p == "%end " + current[0].split()[1]:
                result.append(tuple(current))
                current = None
            elif p.startswith("%output "):
                current = [p, ""]
            else:
                result.append((p, None))
        elif current is not None:
            current[1] += f
    return result


def outputs(pid):
    return [(p.split(), data) for p, data in payloads()
            if p.startswith("%output ") and p.split()[2] == str(pid)]


def output_bytes(pid):
    return sum(len(data) for _, data in outputs(pid))


def reply_lines(identifier):
    """Lines between begin and end for identifier, and the status."""
    lines = []
    inside = False
    for p, _ in payloads():
        if p == "begin " + identifier:
            inside = True
        elif inside and p.startswith("end " + identifier + " "):
            return lines, int(p.split()[2])
        elif inside:
            lines.append(p)
    return lines, None


def terminated(pid):
    for p, _ in payloads():
        parts = p.split()
        if parts[0] == "%terminate" and parts[1] == str(pid):
            return True
    return False


async def wait_for(predicate, timeout=10.0):
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        if predicate():
            return True
        await asyncio.sleep(0.01)
    return predicate()


async def start(identifier, handler, args):
    await handler(identifier, args)
    lines, status = reply_lines(identifier)
    assert status == 0, (identifier, lines, status)
    return int(lines[0])


def blocked(pid):
    """The framer is holding pid's output for lack of credit."""
    source = framer.PROCESSES[pid].flow_source
    return source is not None and source.blocked and framer.FLOW.budget(source.flow) == 0


def reset_framer():
    """Each test runs its own event loop, so forget timers and pending callbacks that belonged
    to the last one."""
    _frames.clear()
    framer.FLOW = framer.FlowControl(framer.flow_now)
    framer.PROCESSES.clear()
    framer.SOURCES.clear()
    framer.PUMP_SCHEDULED = False
    framer.FLOW_TICK_HANDLE = None
    framer.ECHO_TIMER = None
    framer.IT2_GATE = None


class FlowIntegrationTests(unittest.TestCase):
    def setUp(self):
        reset_framer()

    def run_async(self, coro):
        asyncio.run(coro)

    async def finish(self, *pids):
        for pid in pids:
            if pid in framer.PROCESSES:
                framer.PROCESSES[pid].send_signal(9)
        framer.FLOW.disable()
        framer.pump_sources()

        async def done():
            await framer.cleanup()
            while framer.TASKS:
                await framer.TASKS.pop(0)
            return all(terminated(pid) for pid in pids)
        deadline = asyncio.get_event_loop().time() + 10
        while asyncio.get_event_loop().time() < deadline:
            if await done():
                return
            await asyncio.sleep(0.01)
        self.fail("processes did not exit")

    def test_without_flow_control_frames_keep_the_old_format(self):
        async def body():
            pid = await start("r1", framer.handle_run, ["printf hello"])
            self.assertTrue(await wait_for(lambda: terminated(pid) or "hello" in "".join(
                d for _, d in outputs(pid))))
            for header, _ in outputs(pid):
                self.assertEqual(len(header), 5, header)
            await self.finish(pid)
        self.run_async(body())

    def test_flow_on_reports_the_version_and_clock(self):
        async def body():
            await framer.handle_flow("f1", ["on"])
            lines, status = reply_lines("f1")
            self.assertEqual(status, 0)
            self.assertEqual(lines, ["1 " + framer.flow_clock_name()])
            self.assertIn(framer.flow_clock_name(), ("boottime", "monotonic", "uptime"))
            self.assertTrue(framer.FLOW.enabled)
        self.run_async(body())

    def test_unknown_flow_arguments_fail(self):
        async def body():
            await framer.handle_flow("f1", ["sideways"])
            self.assertEqual(reply_lines("f1")[1], 1)
            self.assertFalse(framer.FLOW.enabled)
        self.run_async(body())

    def test_output_stops_at_the_credit_and_resumes_with_a_grant(self):
        async def body():
            await framer.handle_flow("f1", ["on"])
            pid = await start("r1", framer.handle_run, ["yes"])
            self.assertTrue(await wait_for(lambda: blocked(pid)))
            self.assertEqual(output_bytes(pid), 8192)
            framer.FLOW.grant(5000)
            framer.pump_sources()
            self.assertTrue(await wait_for(lambda: blocked(pid) and output_bytes(pid) == 13192))
            await self.finish(pid)
        self.run_async(body())

    def test_output_written_before_exit_survives_until_there_is_credit(self):
        # macOS discards unread pty output when the last copy of the slave closes, so the
        # framer must hold its own copy until it has read everything. The output must fit in
        # the pty's buffer (1 KB on macOS) for the program to exit without being read, and
        # exceed the 257 bytes the framer peeks at without credit.
        async def body():
            await framer.handle_flow("f1", ["on"])
            framer.FLOW.spend(framer.FLOW.credit)
            pid = await start("r1", framer.handle_run, ["head -c 1000 /dev/zero | tr '\\0' x"])
            self.assertTrue(await wait_for(lambda: framer.PROCESSES[pid].exited))
            self.assertFalse(terminated(pid))
            framer.flow_grant(1 << 20)
            self.assertTrue(await wait_for(lambda: terminated(pid)))
            self.assertEqual(output_bytes(pid), 1000)
            await self.finish()
        self.run_async(body())

    def test_killing_a_program_that_exited_but_is_not_reported_yet(self):
        # Its output is still unread for lack of credit, so it is listed but already reaped.
        async def body():
            await framer.handle_flow("f1", ["on"])
            framer.FLOW.spend(framer.FLOW.credit)
            pid = await start("r1", framer.handle_run, ["head -c 1000 /dev/zero | tr '\\0' x"])
            self.assertTrue(await wait_for(lambda: framer.PROCESSES[pid].exited))
            await framer.handle_kill("k1", [str(pid)])
            self.assertEqual(reply_lines("k1"), ([], 0))
            framer.flow_grant(1 << 20)
            self.assertTrue(await wait_for(lambda: terminated(pid)))
            await self.finish()
        self.run_async(body())

    def test_controlled_frames_carry_a_timestamp_and_flags(self):
        async def body():
            await framer.handle_flow("f1", ["on"])
            before = framer.flow_send_ms()
            pid = await start("r1", framer.handle_run, ["yes"])
            self.assertTrue(await wait_for(lambda: blocked(pid)))
            after = framer.flow_send_ms()
            headers = [h for h, _ in outputs(pid)]
            for h in headers:
                self.assertEqual(len(h), 7, h)
                self.assertTrue(before <= int(h[5]) <= after, (before, h, after))
            flags = [int(h[6]) & framer.FLOW_FLAG_LIMITED for h in headers]
            self.assertEqual(flags, [0] * (len(flags) - 1) + [framer.FLOW_FLAG_LIMITED],
                             "only the frame that used up the credit is marked")
            framer.FLOW.grant(100)
            framer.pump_sources()
            self.assertTrue(await wait_for(lambda: output_bytes(pid) == 8292))
            last = outputs(pid)[-1][0]
            self.assertEqual(int(last[6]) & framer.FLOW_FLAG_LIMITED, framer.FLOW_FLAG_LIMITED)
            await self.finish(pid)
        self.run_async(body())

    def test_sources_share_credit_round_robin(self):
        async def body():
            await framer.handle_flow("f1", ["on"])
            a = await start("r1", framer.handle_run, ["yes a"])
            b = await start("r2", framer.handle_run, ["yes b"])
            self.assertTrue(await wait_for(lambda: blocked(a) and blocked(b)))
            for _ in range(20):
                framer.FLOW.grant(4096 * 2)
                framer.pump_sources()
                await wait_for(lambda: blocked(a) and blocked(b))
            self.assertGreater(output_bytes(a), 40000)
            self.assertGreater(output_bytes(b), 40000)
            await self.finish(a, b)
        self.run_async(body())

    def test_a_drain_zeroes_credit_and_replies(self):
        async def body():
            await framer.handle_flow("f1", ["on"])
            pid = await start("r1", framer.handle_run, ["yes"])
            await framer.handle_drain("d1", [])
            self.assertEqual(reply_lines("d1")[1], 0)
            sent = output_bytes(pid)
            self.assertTrue(await wait_for(lambda: blocked(pid)))
            self.assertEqual(output_bytes(pid), sent, "nothing after the drain")
            await self.finish(pid)
        self.run_async(body())

    def test_ping_replies_at_once(self):
        async def body():
            await framer.handle_ping("p1", [])
            self.assertEqual(reply_lines("p1"), ([], 0))
        self.run_async(body())

    def test_a_program_that_exits_is_reported_even_without_credit(self):
        async def body():
            await framer.handle_flow("f1", ["on"])
            filler = await start("r1", framer.handle_run, ["yes"])
            self.assertTrue(await wait_for(lambda: blocked(filler)))
            quiet = await start("r2", framer.handle_run, ["exit 3"])
            async def reported():
                await framer.cleanup()
                while framer.TASKS:
                    await framer.TASKS.pop(0)
                return terminated(quiet)
            deadline = asyncio.get_event_loop().time() + 10
            while not await reported():
                self.assertLess(asyncio.get_event_loop().time(), deadline)
                await asyncio.sleep(0.01)
            await self.finish(filler)
        self.run_async(body())

    def test_echo_gets_through_while_a_side_command_holds_the_credit(self):
        async def body():
            await framer.handle_flow("f1", ["on"])
            login = await start("l1", framer.handle_login, [os.getcwd(), "exec cat"])
            filler = await start("r1", framer.handle_run, ["yes"])
            self.assertTrue(await wait_for(lambda: blocked(filler)))
            await framer.PROCESSES[login].write(b"hi\n")
            self.assertTrue(await wait_for(lambda: "hi" in "".join(d for _, d in outputs(login))))
            exempt = [h for h, _ in outputs(login) if int(h[6]) & framer.FLOW_FLAG_EXEMPT]
            self.assertTrue(exempt, outputs(login))
            self.assertEqual(framer.FLOW.credit, 0)
            await self.finish(login, filler)
        self.run_async(body())

    def test_a_flooding_login_shell_gets_no_more_than_the_allowance(self):
        # A peek that finds a few bytes looks like echo whether or not it is, as can happen
        # while yes starts up, so a flood may get some exempt bytes, but only as many as the
        # allowance's bucket holds.
        async def body():
            loop = asyncio.get_event_loop()
            started = loop.time()
            await framer.handle_flow("f1", ["on"])
            login = await start("l1", framer.handle_login, [os.getcwd(), "exec yes"])
            self.assertTrue(await wait_for(lambda: blocked(login)))
            elapsed = loop.time() - started
            frames = outputs(login)
            exempt = sum(len(d) for h, d in frames if int(h[6]) & framer.FLOW_FLAG_EXEMPT)
            self.assertEqual(output_bytes(login) - exempt, 8192)
            self.assertLessEqual(
                exempt, framer.FLOW_ECHO_ALLOWANCE + framer.FLOW_ECHO_REFILL * elapsed)
            await self.finish(login)
        self.run_async(body())

    def test_recovery_reports_flow_control_and_holds_output(self):
        async def body():
            await framer.handle_flow("f1", ["on"])
            pid = await start("r1", framer.handle_run, ["yes"])
            self.assertTrue(await wait_for(lambda: blocked(pid)))
            await framer.handle_recover("v1", [])
            texts = [p for p, _ in payloads()]
            start_index = texts.index("begin-recovery")
            block = texts[start_index:texts.index("end-recovery")]
            self.assertIn("recovery: flow 1 " + framer.flow_clock_name(), block)
            self.assertEqual(framer.FLOW.budget(), 0)
            await self.finish(pid)
        self.run_async(body())

    def test_recovery_without_flow_control_says_nothing_about_it(self):
        async def body():
            await framer.handle_recover("v1", [])
            self.assertFalse([p for p, _ in payloads() if p.startswith("recovery: flow")])
        self.run_async(body())

    # Version 2

    def test_flow_on_two_speaks_version_two(self):
        async def body():
            await framer.handle_flow("f1", ["on", "2"])
            self.assertEqual(reply_lines("f1"), (["2 " + framer.flow_clock_name()], 0))
            self.assertEqual(framer.FLOW.version, 2)
        self.run_async(body())

    def test_a_version_this_framer_does_not_speak_fails(self):
        async def body():
            await framer.handle_flow("f1", ["on", str(framer.FLOW_VERSION + 1)])
            self.assertEqual(reply_lines("f1")[1], 1)
            self.assertFalse(framer.FLOW.enabled)
        self.run_async(body())

    async def start_pane(self, identifier, command):
        return await start(identifier, framer.handle_pane, ["24", "80", os.getcwd(), command])

    def test_a_pane_waits_for_credit_of_its_own(self):
        async def body():
            await framer.handle_flow("f1", ["on", "2"])
            pane = await self.start_pane("p1", "yes pane")
            leader = await start("r1", framer.handle_run, ["yes leader"])
            self.assertTrue(await wait_for(lambda: blocked(leader) and blocked(pane)))
            self.assertEqual(output_bytes(leader), 8192)
            self.assertEqual(output_bytes(pane), 0, "no grant yet")
            framer.flow_grant(3000, pane)
            self.assertTrue(await wait_for(lambda: output_bytes(pane) == 3000 and blocked(pane)))
            self.assertEqual(output_bytes(leader), 8192, "the pane's credit is its own")
            headers = [h for h, _ in outputs(pane)]
            self.assertTrue(all(len(h) == 7 for h in headers), headers)
            self.assertEqual(int(headers[-1][6]) & framer.FLOW_FLAG_LIMITED, framer.FLOW_FLAG_LIMITED)
            await self.finish(pane, leader)
        self.run_async(body())

    def test_a_stalled_pane_does_not_hold_back_the_leader(self):
        async def body():
            await framer.handle_flow("f1", ["on", "2"])
            pane = await self.start_pane("p1", "yes pane")
            framer.flow_grant(4096, pane)
            leader = await start("r1", framer.handle_run, ["yes leader"])
            self.assertTrue(await wait_for(lambda: blocked(pane) and blocked(leader)))
            for _ in range(10):
                framer.flow_grant(8192)
                await wait_for(lambda: blocked(leader))
            self.assertEqual(output_bytes(leader), 8192 * 11)
            self.assertEqual(output_bytes(pane), 4096)
            await self.finish(pane, leader)
        self.run_async(body())

    def test_grants_to_a_process_that_is_not_a_pane_are_ignored(self):
        async def body():
            await framer.handle_flow("f1", ["on", "2"])
            pid = await start("r1", framer.handle_run, ["yes"])
            framer.flow_grant(1000, pid)
            framer.flow_grant(1000, 999999)
            self.assertEqual(framer.FLOW.credits, {framer.FLOW_LEADER: 8192})
            await self.finish(pid)
        self.run_async(body())

    def test_recovery_reports_the_version_in_use(self):
        async def body():
            await framer.handle_flow("f1", ["on", "2"])
            await framer.handle_recover("v1", [])
            texts = [p for p, _ in payloads()]
            self.assertIn("recovery: flow 2 " + framer.flow_clock_name(), texts)
        self.run_async(body())

    async def it2_frames(self, data, grants):
        """Runs an it2 connection that sends `data`, granting it2 each of `grants` in turn once
        the framer holds the rest. Returns the data frames' headers and the bytes they carried."""
        reader = asyncio.StreamReader()
        reader.feed_data(data)
        reader.feed_eof()

        class Writer:
            def close(self):
                pass
        task = asyncio.ensure_future(framer.handle_it2_connection(reader, Writer()))

        def frames():
            result = []
            for p, _ in payloads():
                parts = p.split()
                if parts[:1] == ["%it2"] and parts[2] == "data":
                    result.append((parts, base64.b64decode(parts[3])))
            return result

        def received():
            return sum(len(d) for _, d in frames())
        for n in grants:
            before = received()
            framer.flow_grant(n, framer.FLOW_IT2)
            await wait_for(lambda: received() >= before + min(n, len(data) - before))
        await asyncio.wait_for(task, 10)
        return frames()

    def test_it2_data_is_under_credit_in_version_two(self):
        async def body():
            await framer.handle_flow("f1", ["on", "2"])
            frames = await self.it2_frames(b"x" * 10000, [0, 3000, 7000])
            self.assertEqual(sum(len(d) for _, d in frames), 10000)
            first = [h for h, _ in frames]
            self.assertTrue(all(len(h) == 6 for h in first), first)
            sent = 0
            for header, payload in frames:
                sent += len(payload)
                if sent == 3000:
                    self.assertEqual(int(header[5]) & framer.FLOW_FLAG_LIMITED, framer.FLOW_FLAG_LIMITED)
        self.run_async(body())

    def test_it2_data_is_not_under_credit_in_version_one(self):
        async def body():
            await framer.handle_flow("f1", ["on"])
            frames = await self.it2_frames(b"y" * 10000, [])
            self.assertEqual(sum(len(d) for _, d in frames), 10000)
            self.assertTrue(all(len(h) == 4 for h, _ in frames), "the old format")
        self.run_async(body())


class CommandReaderTests(unittest.TestCase):
    """Grants are applied by the stdin reader as they arrive, not queued behind a command
    handler that is still running."""

    def encode(self, *args):
        return "".join(base64.b64encode(a.encode()).decode() + "\n" for a in args) + "\n"

    def test_a_grant_names_its_flow(self):
        async def body():
            reset_framer()
            framer.FLOW.enable(2)
            queue = asyncio.Queue()
            stream = io.StringIO(self.encode("grant", "it2", "700"))
            loop = asyncio.get_event_loop()
            thread = threading.Thread(target=framer.command_reader, args=(stream, loop, queue),
                                      daemon=True)
            thread.start()
            while await queue.get() is not None:
                pass
            await asyncio.sleep(0)
            self.assertEqual(framer.FLOW.credit_of(framer.FLOW_IT2), 700)
            self.assertEqual(framer.FLOW.credit, 8192)
        asyncio.run(body())

    def test_grants_are_applied_and_other_commands_are_queued(self):
        async def body():
            reset_framer()
            framer.FLOW.enable()
            framer.FLOW.spend(8192)
            queue = asyncio.Queue()
            stream = io.StringIO(self.encode("grant", "700") + self.encode("ping") +
                                 self.encode("grant", "300"))
            loop = asyncio.get_event_loop()
            thread = threading.Thread(target=framer.command_reader, args=(stream, loop, queue),
                                      daemon=True)
            thread.start()
            lines = []
            while True:
                line = await queue.get()
                if line is None:
                    break
                lines.append(line)
            self.assertEqual(framer.FLOW.credit, 1000)
            self.assertEqual(lines, [base64.b64encode(b"ping").decode(), ""])
        asyncio.run(body())

    def test_a_long_argument_split_across_lines_is_passed_through(self):
        async def body():
            queue = asyncio.Queue()
            encoded = base64.b64encode(b"send").decode()
            stream = io.StringIO(encoded[:3] + "\\\n" + encoded[3:] + "\n\n")
            thread = threading.Thread(target=framer.command_reader,
                                      args=(stream, asyncio.get_event_loop(), queue), daemon=True)
            thread.start()
            lines = []
            while True:
                line = await queue.get()
                if line is None:
                    break
                lines.append(line)
            self.assertEqual(lines, [encoded[:3] + "\\", encoded[3:], ""])
        asyncio.run(body())


if __name__ == "__main__":
    unittest.main()
