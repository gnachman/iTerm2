#!/usr/bin/env python3
"""
Integration tests for App.async_apply_layout.

Connects to a running iTerm2 (debug build), creates real windows / tabs /
split panes for each test case, exercises the apply_layout API against
them, and asserts that the resulting layout matches what was requested.

Each test isolates: it creates the windows it needs and closes them in
teardown so other tests (and the user's pre-existing windows) are
unaffected.

Usage:
    1. Start a debug iTerm2 build (e.g. `make run`).
    2. Run this script:
        python3 tests/apply_layout_integration_test.py
        python3 tests/apply_layout_integration_test.py test_swap_two_panes
        python3 tests/apply_layout_integration_test.py -v
"""

import asyncio
import inspect
import os
import sys
import traceback
import typing

import iterm2


# ---------------------------------------------------------------------------
# Tree-shape helpers
#
# A "shape" is a hashable representation of a tab.root tree where session
# identities are indirected through a caller-supplied label map. This lets
# tests write assertions like ('V', [('S', 'a'), ('S', 'b')]) instead of
# raw GUIDs, which keeps the failure messages readable.
# ---------------------------------------------------------------------------

Shape = typing.Tuple[str, typing.Any]


def tree_shape(node, label_for: typing.Callable[[str], str]) -> Shape:
    """Convert a Splitter / Session tree into a (kind, payload) tuple.

    Leaves: ('S', label). Splitters: ('V'|'H', [child_shape, ...]).
    `label_for(session_id)` returns the test-supplied short label for
    that session, or the raw session_id if unmapped (so unexpected
    sessions still surface in failure messages).

    Note on single-leaf wrapping: `iTermSplitTreeRebuilder` always wraps
    a single-leaf layout in a vertical splitter so `tab.root` is always
    an NSSplitView (see `iTermSplitTreeRebuilder.swift`). Tests that
    assert against `('V', [('S', x)])` are encoding that snapshot. If
    the rebuilder ever changes (e.g., to use H-wrap or to pass the leaf
    through unwrapped), several tests here will break in a coordinated
    way — that's intentional, so the rebuilder change is forced through
    a deliberate test update.
    """
    if isinstance(node, iterm2.Session):
        return ('S', label_for(node.session_id))
    children = [tree_shape(c, label_for) for c in node.children]
    return ('V' if node.vertical else 'H', children)


def labeler(mapping: typing.Dict[str, str]) -> typing.Callable[[str], str]:
    """Return a label_for function from a session_id → label mapping.

    Unknown session IDs come back as `'?<short-id>'` so failures point
    at the unexpected session.
    """
    def fn(session_id: str) -> str:
        return mapping.get(session_id, '?' + session_id[:8])
    return fn


# ---------------------------------------------------------------------------
# Spec constructors
#
# Convenience helpers so tests read more like layout descriptions and
# less like JSON construction.
# ---------------------------------------------------------------------------

def leaf(session_id: str) -> dict:
    return {"session_id": session_id}


def vsplit(*children: dict) -> dict:
    return {"vertical": True, "children": list(children)}


def hsplit(*children: dict) -> dict:
    return {"vertical": False, "children": list(children)}


def reshape(tab_id: str, root: dict) -> dict:
    return {"tab_id": tab_id, "root": root}


# ---------------------------------------------------------------------------
# Live-state helpers
# ---------------------------------------------------------------------------

async def refresh(connection) -> 'iterm2.App':
    """Re-fetch the app so cached tab/session/window pointers are live."""
    return await iterm2.async_get_app(connection)


def find_window(app, window_id: str) -> typing.Optional['iterm2.Window']:
    for window in app.windows:
        if window.window_id == window_id:
            return window
    return None


def find_tab(app, tab_id: str) -> typing.Optional['iterm2.Tab']:
    for window in app.windows:
        for tab in window.tabs:
            if tab.tab_id == tab_id:
                return tab
    return None


def find_session(app, session_id: str) -> typing.Optional['iterm2.Session']:
    for window in app.windows:
        for tab in window.tabs:
            for session in tab.sessions:
                if session.session_id == session_id:
                    return session
    return None


async def screen_contains(session, needle: str) -> bool:
    """True if `needle` appears anywhere in the session's onscreen
    contents."""
    contents = await session.async_get_screen_contents()
    for i in range(contents.number_of_lines):
        if needle in contents.line(i).string:
            return True
    return False


async def write_marker(session, marker: str, timeout_seconds: float = 3.0) -> None:
    """Send `echo MARKER` to the session and wait until it appears on
    screen (shell startup + echo can take a moment). Raises TestFailure
    if it never shows up."""
    await session.async_send_text(f"echo {marker}\n")
    deadline = asyncio.get_event_loop().time() + timeout_seconds
    while asyncio.get_event_loop().time() < deadline:
        if await screen_contains(session, marker):
            return
        await asyncio.sleep(0.1)
    raise TestFailure(
        f"marker {marker!r} never appeared on session {session.session_id[:8]} "
        f"(timeout {timeout_seconds}s)")


async def split_n_times(session, count: int, vertical: bool) -> typing.List['iterm2.Session']:
    """Split `count` times in series and return all resulting sessions
    in the order they appear in the tree (left-to-right or top-to-bottom).
    """
    sessions = [session]
    current = session
    for _ in range(count):
        new = await current.async_split_pane(vertical=vertical)
        sessions.append(new)
        current = new
    return sessions


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

class TestFailure(AssertionError):
    """Raised by harness helpers on assertion failure."""


def assert_equal(actual, expected, message: str = "") -> None:
    if actual != expected:
        prefix = (message + ": ") if message else ""
        raise TestFailure(
            f"{prefix}expected {expected!r}, got {actual!r}")


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise TestFailure(message)


def assert_raises(exc_type, message_substring: typing.Optional[str] = None):
    """Returns an async context manager that asserts the body raises exc_type
    (and optionally that the message contains a substring)."""
    class _CM:
        async def __aenter__(self):
            return self

        async def __aexit__(self, et, ev, tb):
            if et is None:
                raise TestFailure(
                    f"expected {exc_type.__name__} but no exception was raised")
            if not issubclass(et, exc_type):
                return False  # propagate unexpected exception
            if message_substring is not None and message_substring not in str(ev):
                raise TestFailure(
                    f"expected {exc_type.__name__} containing "
                    f"{message_substring!r}, got {ev!r}")
            return True
    return _CM()


class Harness:
    """Per-test context. Tracks windows created during the test so they
    can be closed in teardown without disturbing the user's other
    windows.
    """

    def __init__(self, connection, app):
        self.connection = connection
        self.app = app
        self._initial_window_ids: typing.Set[str] = {
            w.window_id for w in app.windows}

    async def make_window(self) -> 'iterm2.Window':
        """Create a fresh window. Caller takes ownership; teardown will
        close it."""
        window = await iterm2.Window.async_create(self.connection)
        if window is None:
            raise TestFailure("could not create window")
        # Refresh app so the new window is reachable via app.windows.
        self.app = await refresh(self.connection)
        # Re-resolve to the fresh Window object.
        new_window = find_window(self.app, window.window_id)
        if new_window is None:
            raise TestFailure(
                f"new window {window.window_id} not in app after refresh")
        return new_window

    async def refresh(self) -> 'iterm2.App':
        self.app = await refresh(self.connection)
        return self.app

    async def teardown(self) -> None:
        self.app = await refresh(self.connection)
        for window in list(self.app.windows):
            if window.window_id not in self._initial_window_ids:
                try:
                    await window.async_close(force=True)
                except Exception:
                    # Swallow teardown errors so a failing test doesn't
                    # mask its own assertion in noise.
                    pass


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# --- In-tab reshape -------------------------------------------------------

async def test_swap_two_panes_in_tab(h: Harness) -> None:
    """Swap two horizontally-split panes; tree should flip child order."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()

    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})
    assert_equal(tree_shape(tab.root, label),
                 ('V', [('S', 'a'), ('S', 'b')]),
                 "pre-condition")

    spec = {"tabs": [reshape(tab.tab_id,
                             vsplit(leaf(b.session_id), leaf(a.session_id)))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab.root, label),
                 ('V', [('S', 'b'), ('S', 'a')]),
                 "after swap")


async def test_swap_three_panes_in_tab(h: Harness) -> None:
    """Reverse the order of a 3-pane row."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    c = await b.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b', c.session_id: 'c'})

    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(c.session_id), leaf(b.session_id), leaf(a.session_id)))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab.root, label),
                 ('V', [('S', 'c'), ('S', 'b'), ('S', 'a')]))


async def test_change_orientation_v_to_h(h: Harness) -> None:
    """Two vertically-split panes become horizontally split, same order."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})

    spec = {"tabs": [reshape(tab.tab_id,
                             hsplit(leaf(a.session_id), leaf(b.session_id)))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab.root, label),
                 ('H', [('S', 'a'), ('S', 'b')]))


async def test_restructure_flat_to_nested(h: Harness) -> None:
    """Three panes in a flat horizontal row become a nested layout:
    a on the left, (b stacked above c) on the right."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    c = await b.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b', c.session_id: 'c'})

    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(a.session_id),
        hsplit(leaf(b.session_id), leaf(c.session_id))))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab.root, label),
                 ('V', [('S', 'a'),
                        ('H', [('S', 'b'), ('S', 'c')])]))


async def test_no_op_reshape_preserves_shape(h: Harness) -> None:
    """Submitting the existing layout shape should preserve tree shape
    and the active session, and the original GUIDs must still resolve
    (GUIDs are assigned at session creation and never re-used, so a
    surviving GUID proves the session itself survived).
    """
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    await a.async_activate()
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})
    before = tree_shape(tab.root, label)
    active_before = tab.active_session_id

    spec = {"tabs": [reshape(tab.tab_id,
                             vsplit(leaf(a.session_id), leaf(b.session_id)))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab.root, label), before, "tree shape preserved")
    assert_equal(tab.active_session_id, active_before, "active session preserved")
    assert_true(find_session(h.app, a.session_id) is not None,
                "a's session_id should still resolve after no-op reshape")
    assert_true(find_session(h.app, b.session_id) is not None,
                "b's session_id should still resolve after no-op reshape")


# --- Cross-tab moves ------------------------------------------------------

async def test_cross_tab_move_single_session(h: Harness) -> None:
    """Move one pane from tab A to tab B; A and B must both list the
    correct sessions afterward."""
    window = await h.make_window()
    tab_a = window.current_tab
    a1 = tab_a.sessions[0]
    a2 = await a1.async_split_pane(vertical=True)
    tab_b = await window.async_create_tab()
    h.app = await h.refresh()
    window = find_window(h.app, window.window_id)
    tab_b = window.tabs[-1]
    b1 = tab_b.sessions[0]
    label = labeler({a1.session_id: 'a1', a2.session_id: 'a2',
                     b1.session_id: 'b1'})

    # Move a2 from tab A into tab B as a vertical split with b1.
    spec = {"tabs": [
        reshape(tab_a.tab_id, leaf(a1.session_id)),
        reshape(tab_b.tab_id, vsplit(leaf(b1.session_id), leaf(a2.session_id))),
    ]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_a = find_tab(h.app, tab_a.tab_id)
    tab_b = find_tab(h.app, tab_b.tab_id)
    assert_true(tab_a is not None, "tab A should still exist")
    assert_true(tab_b is not None, "tab B should still exist")
    # The rebuilder wraps a single-leaf layout in a vertical splitter so
    # tab.root is always an NSSplitView. Pin the exact shape.
    assert_equal(tree_shape(tab_a.root, label),
                 ('V', [('S', 'a1')]),
                 "tab A layout (single-leaf wrapped in V)")
    assert_equal(tree_shape(tab_b.root, label),
                 ('V', [('S', 'b1'), ('S', 'a2')]),
                 "tab B layout")


async def test_cross_tab_move_emptying_source_implicitly_closes_it(h: Harness) -> None:
    """Move all sessions out of tab A into tab B WITHOUT listing tab A in
    close_tabs. emptyTabsToClose in endTransaction should close A.

    Exercises the implicit-close path that endTransaction's
    `emptyTabsToClose` handling provides.
    """
    window = await h.make_window()
    tab_a = window.current_tab
    a1 = tab_a.sessions[0]
    a2 = await a1.async_split_pane(vertical=True)
    tab_b = await window.async_create_tab()
    h.app = await h.refresh()
    window = find_window(h.app, window.window_id)
    tab_b = window.tabs[-1]
    b1 = tab_b.sessions[0]

    # NOTE: no close_tabs entry. Tab A's sessions all migrate to B; the
    # auto-close path must catch this.
    spec = {"tabs": [
        reshape(tab_b.tab_id, vsplit(
            leaf(b1.session_id), leaf(a1.session_id), leaf(a2.session_id))),
    ]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    assert_true(find_tab(h.app, tab_a.tab_id) is None,
                "tab A should be auto-closed via emptyTabsToClose")
    tab_b_after = find_tab(h.app, tab_b.tab_id)
    assert_true(tab_b_after is not None, "tab B should still exist")
    assert_equal(len(tab_b_after.sessions), 3,
                 "tab B should now have 3 sessions")


async def test_cross_tab_move_emptying_single_session_tab_implicitly_closes(h: Harness) -> None:
    """Even narrower implicit-close test: tab A has exactly one session
    that moves to B. WITHOUT close_tabs, A must auto-close.
    """
    window = await h.make_window()
    tab_a = window.current_tab
    a1 = tab_a.sessions[0]  # a1 is the only session in A
    tab_b = await window.async_create_tab()
    h.app = await h.refresh()
    window = find_window(h.app, window.window_id)
    tab_b = window.tabs[-1]
    b1 = tab_b.sessions[0]

    # No close_tabs. Tab A has only a1, which is moving to B.
    spec = {"tabs": [
        reshape(tab_b.tab_id, vsplit(leaf(b1.session_id), leaf(a1.session_id))),
    ]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    assert_true(find_tab(h.app, tab_a.tab_id) is None,
                "empty tab A should have been auto-closed by endTransaction")


async def test_cross_window_move(h: Harness) -> None:
    """Move a session from a tab in window 1 to a tab in window 2."""
    window1 = await h.make_window()
    tab1 = window1.current_tab
    a = tab1.sessions[0]
    b = await a.async_split_pane(vertical=True)
    window2 = await h.make_window()
    tab2 = window2.current_tab
    c = tab2.sessions[0]
    h.app = await h.refresh()
    label = labeler({a.session_id: 'a', b.session_id: 'b', c.session_id: 'c'})

    spec = {"tabs": [
        reshape(tab1.tab_id, leaf(a.session_id)),
        reshape(tab2.tab_id, vsplit(leaf(c.session_id), leaf(b.session_id))),
    ]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab1_after = find_tab(h.app, tab1.tab_id)
    tab2_after = find_tab(h.app, tab2.tab_id)
    assert_equal(tree_shape(tab1_after.root, label),
                 ('V', [('S', 'a')]),
                 "window1.tab layout (single-leaf wrapped in V)")
    assert_equal(tree_shape(tab2_after.root, label),
                 ('V', [('S', 'c'), ('S', 'b')]),
                 "window2.tab layout")


# --- Closes ---------------------------------------------------------------

async def test_close_session_only(h: Harness) -> None:
    """close_sessions terminates the named session and the tab is reshaped
    around the survivors."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})

    spec = {"tabs": [reshape(tab.tab_id, leaf(a.session_id))],
            "close_sessions": [b.session_id]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_true(tab_after is not None, "tab should still exist")
    assert_true(find_session(h.app, b.session_id) is None,
                "b should be terminated")
    assert_equal(tree_shape(tab_after.root, label),
                 ('V', [('S', 'a')]),
                 "tab should contain only a (wrapped in V)")


async def test_close_tab_only(h: Harness) -> None:
    """close_tabs removes a tab without affecting other tabs."""
    window = await h.make_window()
    tab1 = window.current_tab
    a = tab1.sessions[0]
    tab2 = await window.async_create_tab()
    h.app = await h.refresh()
    window = find_window(h.app, window.window_id)
    tab2 = window.tabs[-1]
    b = tab2.sessions[0]

    spec = {"tabs": [reshape(tab1.tab_id, leaf(a.session_id))],
            "close_tabs": [tab2.tab_id]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    assert_true(find_tab(h.app, tab1.tab_id) is not None,
                "tab1 should still exist")
    assert_true(find_tab(h.app, tab2.tab_id) is None,
                "tab2 should be closed")
    assert_true(find_session(h.app, b.session_id) is None,
                "b should be gone")


async def test_close_window_only(h: Harness) -> None:
    """close_windows removes a window outright AND terminates its
    sessions."""
    window1 = await h.make_window()
    window2 = await h.make_window()
    tab2 = window2.current_tab
    b = tab2.sessions[0]

    spec = {"close_windows": [window2.window_id]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    assert_true(find_window(h.app, window1.window_id) is not None,
                "window1 should still exist")
    assert_true(find_window(h.app, window2.window_id) is None,
                "window2 should be closed")
    assert_true(find_session(h.app, b.session_id) is None,
                "window2's session should be terminated")


# --- Active session promotion ---------------------------------------------

async def test_active_session_survives_reshape(h: Harness) -> None:
    """Reshaping a tab whose active session survives keeps that session
    active."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    # Make `a` the active session.
    await a.async_activate()
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)

    spec = {"tabs": [reshape(tab.tab_id,
                             vsplit(leaf(b.session_id), leaf(a.session_id)))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_equal(tab_after.active_session_id, a.session_id,
                 "active session should be preserved after reshape")


async def test_active_session_promoted_when_terminated(h: Harness) -> None:
    """When the active session is closed, a survivor is promoted to active."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    # Make `b` the active session, then close it.
    await b.async_activate()
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    assert_equal(tab.active_session_id, b.session_id, "pre-condition")

    spec = {"tabs": [reshape(tab.tab_id, leaf(a.session_id))],
            "close_sessions": [b.session_id]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_equal(tab_after.active_session_id, a.session_id,
                 "a should be the new active session")


async def test_active_session_set_after_cross_tab_move(h: Harness) -> None:
    """Regression test for the adoptSession-ran-after-activeSession-
    promotion bug.

    Setup:
      - tab A has [a1, a2]
      - tab B has only [b1]; b1 is the active session (single-session
        tab => it's active)

    Spec moves a1 and a2 into tab B and closes b1. Tab A is then empty
    and auto-closes. Tab B's post-state is [a1, a2] only.

    To exercise the active-promotion path, the previous active (b1) is
    terminated, so `replaceViewHierarchy` must pick a NEW active from
    `tab.sessions()`. If adoption ran AFTER promotion, surviving sessions
    would be empty (b1 gone, a1/a2 not yet in viewToSessionMap) and no
    active session would be assigned. With the fix in place, surviving
    is [a1, a2] and the first leaf in the tree (a1) becomes active.

    The test passes only if a1 ends up active — proving adoption ran
    BEFORE active-session promotion.
    """
    window = await h.make_window()
    tab_a = window.current_tab
    a1 = tab_a.sessions[0]
    a2 = await a1.async_split_pane(vertical=True)
    tab_b = await window.async_create_tab()
    h.app = await h.refresh()
    window = find_window(h.app, window.window_id)
    tab_b = window.tabs[-1]
    b1 = tab_b.sessions[0]

    spec = {"tabs": [
        reshape(tab_b.tab_id, vsplit(leaf(a1.session_id), leaf(a2.session_id))),
    ], "close_sessions": [b1.session_id]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_a_after = find_tab(h.app, tab_a.tab_id)
    tab_b_after = find_tab(h.app, tab_b.tab_id)
    assert_true(tab_a_after is None,
                "tab A should auto-close (both sessions moved to B)")
    assert_true(tab_b_after is not None, "tab B should still exist")
    assert_equal(len(tab_b_after.sessions), 2, "tab B should have 2 sessions")
    # CRITICAL: a1 (first leaf in the new tree) must be active. With the
    # bug present, surviving = [] when promotion runs and active stays
    # b1 (now-dead) or nil — never a1.
    assert_equal(tab_b_after.active_session_id, a1.session_id,
                 "a1 should be active in B (proves adopt ran before "
                 "active-session promotion)")


async def test_active_session_preserved_when_other_session_moves_in(h: Harness) -> None:
    """When a session moves INTO a tab, the destination tab's existing
    active session should remain active (no spurious promotion)."""
    window = await h.make_window()
    tab_a = window.current_tab
    a1 = tab_a.sessions[0]
    a2 = await a1.async_split_pane(vertical=True)
    tab_b = await window.async_create_tab()
    h.app = await h.refresh()
    window = find_window(h.app, window.window_id)
    tab_b = window.tabs[-1]
    b1 = tab_b.sessions[0]
    # b1 is the only (and active) session in tab B.

    # Move a2 from tab A into tab B (placed first in vsplit).
    spec = {"tabs": [
        reshape(tab_a.tab_id, leaf(a1.session_id)),
        reshape(tab_b.tab_id, vsplit(leaf(a2.session_id), leaf(b1.session_id))),
    ]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_b_after = find_tab(h.app, tab_b.tab_id)
    assert_equal(len(tab_b_after.sessions), 2, "tab B should have 2 sessions")
    # b1 was active before; it survived; it should still be active even
    # though a2 is structurally first in the new tree.
    assert_equal(tab_b_after.active_session_id, b1.session_id,
                 "b1 should still be active in B (existing active "
                 "preserved when survivor)")


# --- Combined ops ---------------------------------------------------------

async def test_combined_reshape_and_close(h: Harness) -> None:
    """Reshape one tab while closing a session in another."""
    window = await h.make_window()
    tab1 = window.current_tab
    a = tab1.sessions[0]
    b = await a.async_split_pane(vertical=True)
    tab2 = await window.async_create_tab()
    h.app = await h.refresh()
    window = find_window(h.app, window.window_id)
    tab2 = window.tabs[-1]
    c = tab2.sessions[0]
    d = await c.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab1 = find_tab(h.app, tab1.tab_id)
    tab2 = find_tab(h.app, tab2.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b',
                     c.session_id: 'c', d.session_id: 'd'})

    # Swap a/b in tab1, close d in tab2.
    spec = {"tabs": [
        reshape(tab1.tab_id, vsplit(leaf(b.session_id), leaf(a.session_id))),
        reshape(tab2.tab_id, leaf(c.session_id)),
    ], "close_sessions": [d.session_id]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab1_after = find_tab(h.app, tab1.tab_id)
    tab2_after = find_tab(h.app, tab2.tab_id)
    assert_equal(tree_shape(tab1_after.root, label),
                 ('V', [('S', 'b'), ('S', 'a')]), "tab1 reshape")
    assert_true(find_session(h.app, d.session_id) is None,
                "d should be closed")
    assert_equal(tree_shape(tab2_after.root, label),
                 ('V', [('S', 'c')]),
                 "tab2 should contain only c (wrapped in V)")


# --- Validation rejections ------------------------------------------------

async def test_unknown_tab_id_rejected(h: Harness) -> None:
    """Use both a fake tab_id AND a fake session_id so the unknown-tab
    error fires from the tab lookup (not the orphan check or session
    lookup of a real session). The error message must contain the
    offending tab_id verbatim."""
    await h.make_window()  # ensure there is at least one window
    spec = {"tabs": [reshape("not-a-real-tab-id",
                             leaf("ghost-session-id"))]}
    async with assert_raises(iterm2.rpc.RPCException, "not-a-real-tab-id"):
        await h.app.async_apply_layout(spec)


async def test_unknown_session_id_rejected(h: Harness) -> None:
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]

    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(a.session_id), leaf("ghost-session-id")))]}
    async with assert_raises(iterm2.rpc.RPCException, "ghost-session-id"):
        await h.app.async_apply_layout(spec)


async def test_duplicate_session_id_rejected(h: Harness) -> None:
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]

    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(a.session_id), leaf(a.session_id)))]}
    async with assert_raises(iterm2.rpc.RPCException, "more than once"):
        await h.app.async_apply_layout(spec)


async def test_same_orientation_nesting_rejected(h: Harness) -> None:
    """V-inside-V (or H-inside-H) is rejected by the validator. The
    inner splitter must use the opposite orientation or be flattened
    into the outer.

    Use three distinct sessions so the duplicate-GUID check can't fire
    first and mask which rule actually triggered.
    """
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    c = await b.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)

    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(a.session_id),
        vsplit(leaf(b.session_id), leaf(c.session_id))))]}
    async with assert_raises(iterm2.rpc.RPCException, "orientation"):
        await h.app.async_apply_layout(spec)


async def test_splitter_with_one_child_rejected(h: Harness) -> None:
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]

    spec = {"tabs": [reshape(tab.tab_id, vsplit(leaf(a.session_id)))]}
    async with assert_raises(iterm2.rpc.RPCException, "at least 2"):
        await h.app.async_apply_layout(spec)


async def test_orphan_session_rejected(h: Harness) -> None:
    """Reshaping a tab without listing all its current sessions in
    either the new layout or close_sessions/close_tabs is a hard error."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)

    # Spec only mentions `a`; `b` is silently dropped.
    spec = {"tabs": [reshape(tab.tab_id, leaf(a.session_id))]}
    async with assert_raises(iterm2.rpc.RPCException, "unaccounted"):
        await h.app.async_apply_layout(spec)


async def test_new_tabs_field_rejected(h: Harness) -> None:
    window = await h.make_window()
    a = window.current_tab.sessions[0]

    spec = {"new_tabs": [{
        "window_id": window.window_id, "root": leaf(a.session_id)}]}
    async with assert_raises(iterm2.rpc.RPCException, "new_tabs"):
        await h.app.async_apply_layout(spec)


async def test_new_windows_field_rejected(h: Harness) -> None:
    window = await h.make_window()
    a = window.current_tab.sessions[0]

    spec = {"new_windows": [{"profile": "Default", "root": leaf(a.session_id)}]}
    async with assert_raises(iterm2.rpc.RPCException, "new_windows"):
        await h.app.async_apply_layout(spec)


def new_leaf(profile_guid: str, command: typing.Optional[str] = None) -> dict:
    info: typing.Dict[str, typing.Any] = {"profile": profile_guid}
    if command is not None:
        info["command"] = command
    return {"new_session": info}


async def test_new_session_leaf_creates_session(h: Harness) -> None:
    """A new_session leaf creates a brand-new live session in place, next
    to an existing one, in a single apply_layout call."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    guid = (await a.async_get_profile()).guid

    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(a.session_id),
        new_leaf(guid)))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    assert_equal(len(tab.sessions), 2, "tab should have two panes")
    ids = [s.session_id for s in tab.sessions]
    assert_true(a.session_id in ids, "original session should survive")
    new_ids = [sid for sid in ids if sid != a.session_id]
    assert_equal(len(new_ids), 1, "exactly one new session created")
    # New pane is the second child (right of the original).
    label = labeler({a.session_id: 'a', new_ids[0]: 'new'})
    assert_equal(tree_shape(tab.root, label),
                 ('V', [('S', 'a'), ('S', 'new')]))
    # Confirm the new session has a live shell.
    new_session = find_session(h.app, new_ids[0])
    await write_marker(new_session, "NEWPANE_OK")


async def test_new_session_unknown_profile_rejected(h: Harness) -> None:
    """A new_session leaf naming a profile GUID that doesn't exist is
    rejected up front, before any mutation."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]

    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(a.session_id),
        new_leaf("not-a-real-profile-guid")))]}
    async with assert_raises(iterm2.rpc.RPCException, "profile"):
        await h.app.async_apply_layout(spec)


async def test_new_session_honors_profile_home_directory(h: Harness) -> None:
    """A new_session honors its profile's working-directory mode rather than
    always inheriting the neighbor's directory.

    Set the profile to Home, move the neighbor pane to a distinctive
    directory, then create a new_session next to it. The new pane must
    start in the home directory. (The earlier behavior forced the
    neighbor's directory regardless of the profile, which this guards
    against.)
    """
    window = await h.make_window()
    tab = window.current_tab
    anchor = tab.sessions[0]
    profile = await anchor.async_get_profile()
    guid = profile.guid
    home = os.path.expanduser("~")

    # Move the neighbor somewhere distinctive so "inherit the neighbor"
    # would be both possible and obviously wrong.
    await anchor.async_send_text("cd /tmp\n")
    await asyncio.sleep(1.5)  # let iTerm2 observe the new cwd

    # The getter returns the raw stored value (a string like "No"); the
    # setter wants an InitialWorkingDirectory enum. Normalize so the
    # restore in `finally` round-trips correctly.
    raw_mode = profile.initial_directory_mode
    original_mode = (raw_mode if isinstance(raw_mode, iterm2.InitialWorkingDirectory)
                     else iterm2.InitialWorkingDirectory(raw_mode))
    try:
        await profile.async_set_initial_directory_mode(
            iterm2.InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_HOME)

        spec = {"tabs": [reshape(tab.tab_id, vsplit(
            leaf(anchor.session_id), new_leaf(guid)))]}
        await h.app.async_apply_layout(spec)
        await asyncio.sleep(1.5)

        h.app = await h.refresh()
        tab = find_tab(h.app, tab.tab_id)
        new_ids = [s.session_id for s in tab.sessions
                   if s.session_id != anchor.session_id]
        assert_equal(len(new_ids), 1, "exactly one new session")
        new_session = find_session(h.app, new_ids[0])

        # Print $PWD with a unique, shell-safe marker (no <,>,= ambiguity).
        marker = "CWDMARK_" + new_ids[0][:8].replace("-", "")
        await new_session.async_send_text(f"echo {marker}=$PWD\n")

        needle = f"{marker}={home}"
        deadline = asyncio.get_event_loop().time() + 5.0
        seen = False
        while asyncio.get_event_loop().time() < deadline:
            if await screen_contains(new_session, needle):
                seen = True
                break
            await asyncio.sleep(0.1)
        assert_true(
            seen,
            f"new pane should start in home ({home}); never saw {needle!r}. "
            "If it landed in /tmp it wrongly inherited the neighbor.")
    finally:
        await profile.async_set_initial_directory_mode(original_mode)


async def test_validation_failure_does_not_mutate(h: Harness) -> None:
    """If the spec fails validation, no tab in the spec should be touched."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})
    before = tree_shape(tab.root, label)

    # Spec is well-formed for the first tab (a swap), but references a
    # non-existent session in a fake second tab. Resolver must reject the
    # whole spec before any mutation runs.
    spec = {"tabs": [
        reshape(tab.tab_id, vsplit(leaf(b.session_id), leaf(a.session_id))),
        reshape("not-a-real-tab-id", leaf("ghost-session")),
    ]}
    async with assert_raises(iterm2.rpc.RPCException):
        await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab_after.root, label), before,
                 "tab should be unchanged after validation rejection")


async def test_empty_spec_is_no_op(h: Harness) -> None:
    """Empty spec succeeds and changes nothing."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})
    before = tree_shape(tab.root, label)

    await h.app.async_apply_layout({})

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab_after.root, label), before)


async def test_unknown_session_in_close_sessions_rejected(h: Harness) -> None:
    """A bogus GUID in close_sessions must be rejected before any
    mutation runs."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})
    before = tree_shape(tab.root, label)

    spec = {"tabs": [reshape(tab.tab_id,
                             vsplit(leaf(a.session_id), leaf(b.session_id)))],
            "close_sessions": ["bogus-session-guid"]}
    async with assert_raises(iterm2.rpc.RPCException, "bogus-session-guid"):
        await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab_after.root, label), before,
                 "tab should be unchanged after close_sessions rejection")


async def test_unknown_tab_in_close_tabs_rejected(h: Harness) -> None:
    spec = {"close_tabs": ["not-a-real-tab-id"]}
    async with assert_raises(iterm2.rpc.RPCException, "not-a-real-tab-id"):
        await h.app.async_apply_layout(spec)


async def test_unknown_window_in_close_windows_rejected(h: Harness) -> None:
    spec = {"close_windows": ["not-a-real-window-guid"]}
    async with assert_raises(iterm2.rpc.RPCException, "not-a-real-window-guid"):
        await h.app.async_apply_layout(spec)


# --- Atomicity for resolver-stage errors ---------------------------------

async def test_orphan_failure_does_not_mutate(h: Harness) -> None:
    """Resolver-stage errors (orphaned session) must not perform any
    mutation. Companion to test_validation_failure_does_not_mutate which
    covers parse-stage errors via unknown-tab."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})
    before = tree_shape(tab.root, label)

    # Spec only mentions a; b is silently dropped → resolver throws
    # orphanedSession.
    spec = {"tabs": [reshape(tab.tab_id, leaf(a.session_id))]}
    async with assert_raises(iterm2.rpc.RPCException, "unaccounted"):
        await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab_after.root, label), before,
                 "tab should be unchanged after orphan rejection")


async def test_unknown_session_in_layout_does_not_mutate(h: Harness) -> None:
    """A spec referencing a bogus session in the new layout must be
    rejected before any mutation runs."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})
    before = tree_shape(tab.root, label)

    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(a.session_id), leaf(b.session_id), leaf("ghost-session-id")))]}
    async with assert_raises(iterm2.rpc.RPCException, "ghost-session-id"):
        await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab_after.root, label), before,
                 "tab should be unchanged after unknown-session rejection")


# --- Deep / wide layouts --------------------------------------------------

async def test_deep_nesting_three_levels(h: Harness) -> None:
    """Build a layout three splitter levels deep, alternating
    orientation. The rebuilder must produce the exact tree shape."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    c = await b.async_split_pane(vertical=True)
    d = await c.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b',
                     c.session_id: 'c', d.session_id: 'd'})

    # Outer V → middle H → inner V. Same-orientation nesting is rejected
    # so we must alternate at each level.
    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(a.session_id),
        hsplit(
            leaf(b.session_id),
            vsplit(leaf(c.session_id), leaf(d.session_id)))))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab.root, label),
                 ('V', [('S', 'a'),
                        ('H', [('S', 'b'),
                               ('V', [('S', 'c'), ('S', 'd')])])]))


async def test_wide_splitter_four_siblings(h: Harness) -> None:
    """A single splitter with four sibling leaves."""
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    c = await b.async_split_pane(vertical=True)
    d = await c.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b',
                     c.session_id: 'c', d.session_id: 'd'})

    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(d.session_id), leaf(c.session_id),
        leaf(b.session_id), leaf(a.session_id)))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab.root, label),
                 ('V', [('S', 'd'), ('S', 'c'),
                        ('S', 'b'), ('S', 'a')]))


# --- close_windows with non-trivial state --------------------------------

async def test_close_window_with_multiple_tabs_and_panes_terminates_all(
        h: Harness) -> None:
    """Closing a window with multiple tabs and split panes must
    terminate every session in that window (and not affect sessions in
    a sibling window)."""
    window1 = await h.make_window()
    keep = window1.current_tab.sessions[0]

    window2 = await h.make_window()
    tab2a = window2.current_tab
    s1 = tab2a.sessions[0]
    s2 = await s1.async_split_pane(vertical=True)
    tab2b = await window2.async_create_tab()
    h.app = await h.refresh()
    window2 = find_window(h.app, window2.window_id)
    tab2b = window2.tabs[-1]
    s3 = tab2b.sessions[0]
    s4 = await s3.async_split_pane(vertical=False)
    doomed_session_ids = [s.session_id for s in (s1, s2, s3, s4)]

    spec = {"close_windows": [window2.window_id]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    assert_true(find_window(h.app, window1.window_id) is not None,
                "sibling window 1 should still exist")
    assert_true(find_window(h.app, window2.window_id) is None,
                "doomed window 2 should be gone")
    assert_true(find_session(h.app, keep.session_id) is not None,
                "sibling window's session should still exist")
    for sid in doomed_session_ids:
        assert_true(find_session(h.app, sid) is None,
                    f"session {sid[:8]} in doomed window should be gone")


async def test_cross_window_move_emptying_source_window(h: Harness) -> None:
    """Move the last session out of window 1's only tab into window 2.
    Window 1's tab auto-closes via emptyTabsToClose; the window itself
    should follow when its last tab goes away.

    Caveat: the "window auto-closes when its last tab goes away"
    invariant is iTerm2's general behavior — not specifically a contract
    of `apply_layout`. If this test ever fails, check whether iTerm2's
    window-close-on-empty behavior changed (independent of this API)
    before assuming a layout-API regression.
    """
    window1 = await h.make_window()
    tab1 = window1.current_tab
    a = tab1.sessions[0]
    window2 = await h.make_window()
    tab2 = window2.current_tab
    b = tab2.sessions[0]
    h.app = await h.refresh()

    spec = {"tabs": [
        reshape(tab2.tab_id, vsplit(leaf(b.session_id), leaf(a.session_id))),
    ]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    assert_true(find_window(h.app, window2.window_id) is not None,
                "window 2 should still exist with both sessions")
    tab2_after = find_tab(h.app, tab2.tab_id)
    assert_equal(len(tab2_after.sessions), 2,
                 "window 2's tab should have 2 sessions")
    # If iTerm2 auto-closes a window whose last tab went away, this
    # assertion holds. If it doesn't, this test will fail and document
    # that gap.
    assert_true(find_window(h.app, window1.window_id) is None,
                "window 1 should auto-close after its only tab emptied")


# --- Scrollback survival --------------------------------------------------

async def test_session_scrollback_survives_in_tab_swap(h: Harness) -> None:
    """The most user-visible promise of the API: reshaping a tab must
    NOT destroy the underlying sessions. A marker written before the
    reshape must still appear afterward.
    """
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    a_live = find_session(h.app, a.session_id)
    assert_true(a_live is not None, "should have found a in refreshed app")

    marker = "APPLY_LAYOUT_MARKER_INTAB_4F2A"
    await write_marker(a_live, marker)

    spec = {"tabs": [reshape(tab.tab_id,
                             vsplit(leaf(b.session_id), leaf(a.session_id)))]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    a_after = find_session(h.app, a.session_id)
    assert_true(a_after is not None,
                "a's session_id must still resolve after reshape")
    assert_true(await screen_contains(a_after, marker),
                "marker must still be on a's screen after in-tab reshape — "
                "proves the session was reused, not destroyed and recreated")


async def test_session_scrollback_survives_cross_tab_move(h: Harness) -> None:
    """Cross-tab moves are the most complex path in the mutator
    (detachSession → attachTree → tab.adoptSession). A session moved
    from tab A to tab B must keep its scrollback contents.
    """
    window = await h.make_window()
    tab_a = window.current_tab
    a1 = tab_a.sessions[0]
    a2 = await a1.async_split_pane(vertical=True)
    tab_b = await window.async_create_tab()
    h.app = await h.refresh()
    window = find_window(h.app, window.window_id)
    tab_b = window.tabs[-1]
    b1 = tab_b.sessions[0]
    a2_live = find_session(h.app, a2.session_id)

    marker = "APPLY_LAYOUT_MARKER_XTAB_8C19"
    await write_marker(a2_live, marker)

    # Move a2 from tab A to tab B.
    spec = {"tabs": [
        reshape(tab_a.tab_id, leaf(a1.session_id)),
        reshape(tab_b.tab_id, vsplit(leaf(b1.session_id), leaf(a2.session_id))),
    ]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    a2_after = find_session(h.app, a2.session_id)
    assert_true(a2_after is not None,
                "a2's session_id must still resolve after cross-tab move")
    # The session should now belong to tab B.
    tab_b_after = find_tab(h.app, tab_b.tab_id)
    a2_in_tab_b = any(s.session_id == a2.session_id
                      for s in tab_b_after.sessions)
    assert_true(a2_in_tab_b, "a2 should now be in tab B")
    # And the marker should survive the move.
    assert_true(await screen_contains(a2_after, marker),
                "marker must still be on a2's screen after cross-tab move — "
                "proves detach/attach reused the SessionView, didn't recreate")


# --- Maximize / parser-error / cross-list rejections --------------------

async def test_maximized_tab_rejected(h: Harness) -> None:
    """Maximized tabs must be rejected by the rebuilder; the user has
    to unmaximize before reshaping. Drives the
    `SplitTreeRebuilderError.maximizedTab` path which is otherwise
    unreachable from tests.
    """
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    await a.async_activate()
    await window.async_activate()
    # Toggle "Maximize Active Pane" via the main menu.
    await iterm2.MainMenu.async_select_menu_item(
        h.connection, "Maximize Active Pane")
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)

    spec = {"tabs": [reshape(tab.tab_id,
                             vsplit(leaf(b.session_id), leaf(a.session_id)))]}
    # Error type may surface as a generic Swift Error rather than a
    # well-formatted string (it's not a LocalizedError). Just check for
    # the substring "maximized" / "maximizedTab" — whichever fires.
    async with assert_raises(iterm2.rpc.RPCException, "aximized"):
        await h.app.async_apply_layout(spec)

    # Cleanup: unmaximize so teardown can close the window cleanly.
    try:
        await iterm2.MainMenu.async_select_menu_item(
            h.connection, "Maximize Active Pane")
    except Exception:
        pass


async def test_missing_field_rejected(h: Harness) -> None:
    """A tab spec without `tab_id` is rejected at parse time."""
    spec = {"tabs": [{"root": {"session_id": "anything"}}]}
    async with assert_raises(iterm2.rpc.RPCException, "tab_id"):
        await h.app.async_apply_layout(spec)


async def test_wrong_type_rejected(h: Harness) -> None:
    """Passing a string where the parser expects an array is rejected."""
    spec = {"tabs": "should-be-a-list"}
    async with assert_raises(iterm2.rpc.RPCException, "tabs"):
        await h.app.async_apply_layout(spec)


async def test_unknown_leaf_kind_rejected(h: Harness) -> None:
    """A node that's neither a session_id nor a splitter nor a
    new_session is rejected at parse time."""
    spec = {"tabs": [{"tab_id": "anything",
                      "root": {"unknown_leaf_kind": "x"}}]}
    async with assert_raises(iterm2.rpc.RPCException):
        await h.app.async_apply_layout(spec)


async def test_tree_too_deep_rejected(h: Harness) -> None:
    """Trees deeper than `LayoutSpecValidator.maxDepth` (32) are
    rejected at validation time. Use a unique session_id at every
    level so the duplicate-GUID check can't fire first."""
    # Build 40 levels deep, alternating orientation so the
    # same-orientation-nesting check doesn't fire first either. The
    # leaf session_ids don't need to exist — depth check runs before
    # existence checks.
    node = {"session_id": "leaf-bottom"}
    for i in range(40):
        node = {"vertical": (i % 2 == 0), "children": [
            {"session_id": f"filler-{i}"},
            node,
        ]}
    spec = {"tabs": [{"tab_id": "anything", "root": node}]}
    async with assert_raises(iterm2.rpc.RPCException, "deep"):
        await h.app.async_apply_layout(spec)


async def test_bidirectional_cross_tab_swap(h: Harness) -> None:
    """In a single spec, swap a session from A→B and another from B→A.
    Exercises the detach-everything-first ordering: both sessions must
    be detached before either tab's attach phase runs, so neither tab
    sees a partially-detached intermediate state.
    """
    window = await h.make_window()
    tab_a = window.current_tab
    a1 = tab_a.sessions[0]
    a2 = await a1.async_split_pane(vertical=True)
    tab_b = await window.async_create_tab()
    h.app = await h.refresh()
    window = find_window(h.app, window.window_id)
    tab_b = window.tabs[-1]
    b1 = tab_b.sessions[0]
    b2 = await b1.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab_a = find_tab(h.app, tab_a.tab_id)
    tab_b = find_tab(h.app, tab_b.tab_id)
    label = labeler({a1.session_id: 'a1', a2.session_id: 'a2',
                     b1.session_id: 'b1', b2.session_id: 'b2'})

    # Swap: a2 goes to B, b2 comes to A.
    spec = {"tabs": [
        reshape(tab_a.tab_id, vsplit(leaf(a1.session_id), leaf(b2.session_id))),
        reshape(tab_b.tab_id, vsplit(leaf(b1.session_id), leaf(a2.session_id))),
    ]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_a_after = find_tab(h.app, tab_a.tab_id)
    tab_b_after = find_tab(h.app, tab_b.tab_id)
    assert_equal(tree_shape(tab_a_after.root, label),
                 ('V', [('S', 'a1'), ('S', 'b2')]),
                 "tab A after swap")
    assert_equal(tree_shape(tab_b_after.root, label),
                 ('V', [('S', 'b1'), ('S', 'a2')]),
                 "tab B after swap")


async def test_close_sessions_runs_after_attach(h: Harness) -> None:
    """close_sessions runs AFTER the attach phase, so a session may
    appear in a new layout AND be terminated in the same call.

    Setup: tab has [a, b, c]. Spec is `reshape(tab → vsplit(a, c))`
    plus `close_sessions=[b]`. b is dropped from the new layout AND
    explicitly listed for close. The transaction:
      1. Attaches the new tree (containing only a and c). b is no
         longer in the visible tree but remains alive — the rebuilder
         deliberately does NOT auto-terminate.
      2. close_sessions terminates b.

    End state: tab=[a, c], b dead. apply_layout returns success.
    """
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    c = await b.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b', c.session_id: 'c'})

    spec = {"tabs": [reshape(tab.tab_id,
                             vsplit(leaf(a.session_id), leaf(c.session_id)))],
            "close_sessions": [b.session_id]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_equal(tree_shape(tab_after.root, label),
                 ('V', [('S', 'a'), ('S', 'c')]),
                 "tab should reshape to [a, c]")
    assert_true(find_session(h.app, b.session_id) is None,
                "b should be terminated")


async def test_session_in_both_layout_and_close_sessions(h: Harness) -> None:
    """A session may appear in BOTH `tabs[].root` and `close_sessions`.
    The semantics are "apply layout, then close": after attach, the
    session is in the new tree; then close_sessions terminates it,
    and PTYTab.removeSession cleans it out of viewToSessionMap and
    the tree.

    End state: tab contains only `a`. b is dead.
    """
    window = await h.make_window()
    tab = window.current_tab
    a = tab.sessions[0]
    b = await a.async_split_pane(vertical=True)
    h.app = await h.refresh()
    tab = find_tab(h.app, tab.tab_id)
    label = labeler({a.session_id: 'a', b.session_id: 'b'})

    spec = {"tabs": [reshape(tab.tab_id,
                             vsplit(leaf(a.session_id), leaf(b.session_id)))],
            "close_sessions": [b.session_id]}
    await h.app.async_apply_layout(spec)

    h.app = await h.refresh()
    tab_after = find_tab(h.app, tab.tab_id)
    assert_true(tab_after is not None, "tab should still exist")
    assert_true(find_session(h.app, b.session_id) is None, "b is dead")
    assert_equal(tree_shape(tab_after.root, label),
                 ('V', [('S', 'a')]),
                 "tab should contain only a after b is closed")


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

async def discover_tests(filter_substring: typing.Optional[str]) -> typing.List[
        typing.Tuple[str, typing.Callable]]:
    tests = []
    for name, obj in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        if not inspect.iscoroutinefunction(obj):
            continue
        if filter_substring and filter_substring not in name:
            continue
        tests.append((name, obj))
    return tests


async def run(connection):
    args = sys.argv[1:]
    verbose = False
    filter_substring: typing.Optional[str] = None
    for arg in args:
        if arg in ("-v", "--verbose"):
            verbose = True
        elif arg.startswith("-"):
            print(f"Unknown option: {arg}")
            sys.exit(2)
        else:
            filter_substring = arg

    app = await iterm2.async_get_app(connection)
    if app is None:
        print("Could not get app handle. Is iTerm2 running?")
        sys.exit(1)

    tests = await discover_tests(filter_substring)
    if not tests:
        print("No tests matched.")
        sys.exit(1)

    passes = 0
    failures: typing.List[typing.Tuple[str, str]] = []

    for name, fn in tests:
        # Refresh before each test so the harness sees the current set of
        # windows as the "do not touch" baseline.
        app = await refresh(connection)
        h = Harness(connection, app)
        print(f"  {name} ... ", end="", flush=True)
        try:
            await fn(h)
            print("PASS")
            passes += 1
        except TestFailure as e:
            print("FAIL")
            failures.append((name, str(e)))
            if verbose:
                traceback.print_exc()
        except Exception as e:
            print("ERROR")
            failures.append((name, f"{type(e).__name__}: {e}"))
            if verbose:
                traceback.print_exc()
        finally:
            await h.teardown()

    total = passes + len(failures)
    print()
    print(f"Ran {total} tests: {passes} passed, {len(failures)} failed")
    for name, message in failures:
        print(f"  FAIL: {name}")
        for line in message.splitlines():
            print(f"    {line}")
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    iterm2.run_until_complete(run)
