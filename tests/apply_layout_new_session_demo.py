#!/usr/bin/env python3
"""
Manual demo of inline session creation in App.async_apply_layout.

Exercises the new `new_session` leaf: apply_layout can now create brand-new
sessions in place while reshaping a tab, instead of only rearranging
existing ones. This is the thing that lets a script turn a fresh tab into a
multi-pane layout in a single call, with the panes born in their final
positions (no create-then-rearrange reflow), and with each new pane
inheriting a neighbor's working directory like a split.

What it shows:
  1. A fresh tab's single session becomes a 3-pane layout in one call,
     mixing the existing session with two new ones (one running a command).
  2. A new pane created next to a session that has cd'd elsewhere inherits
     that directory (split-like cwd), if the profile reuses the previous
     directory.
  3. A new full-width pane is added on top of an existing split.
  4. A bad profile GUID is rejected up front with no side effects.

Everything happens in a window this script creates, so your existing
windows are left alone.

Requirements:
  - A nightly/debug iTerm2 that advertises the capability (protocol >= 1.16).
  - iterm2 Python module 2.20+.

Usage:
    python3 tests/apply_layout_new_session_demo.py
    python3 tests/apply_layout_new_session_demo.py --close   # close the
                                                             # window at the end
"""

import asyncio
import sys

import iterm2


# --------------------------------------------------------------------------
# Spec helpers — read like layout descriptions rather than JSON.
# --------------------------------------------------------------------------

def leaf(session):
    return {"session_id": session.session_id}


def new_leaf(profile_guid, command=None):
    info = {"profile": profile_guid}
    if command is not None:
        info["command"] = command
    return {"new_session": info}


def vsplit(*children):
    """Vertical divider: children laid out left-to-right."""
    return {"vertical": True, "children": list(children)}


def hsplit(*children):
    """Horizontal divider: children laid out top-to-bottom."""
    return {"vertical": False, "children": list(children)}


def reshape(tab_id, root):
    return {"tab_id": tab_id, "root": root}


# --------------------------------------------------------------------------
# Live-state helpers
# --------------------------------------------------------------------------

async def refresh(connection):
    return await iterm2.async_get_app(connection)


def find_tab(app, tab_id):
    for window in app.windows:
        for tab in window.tabs:
            if tab.tab_id == tab_id:
                return tab
    return None


def find_session(app, session_id):
    for window in app.windows:
        for tab in window.tabs:
            for session in tab.sessions:
                if session.session_id == session_id:
                    return session
    return None


def banner(text):
    print()
    print("=" * 72)
    print(text)
    print("=" * 72)


async def settle(seconds=1.2):
    """Pause so the layout change is watchable and the app's cached state
    catches up to the mutation."""
    await asyncio.sleep(seconds)


# --------------------------------------------------------------------------
# Demos
# --------------------------------------------------------------------------

async def demo_three_pane_from_one(connection, app, window):
    banner("1. Fresh tab -> 3 panes in one apply_layout call")
    tab = window.current_tab
    original = tab.sessions[0]
    guid = (await original.async_get_profile()).guid
    print(f"  original session {original.session_id[:8]} (profile {guid[:8]})")

    # Existing session on the left; a vertical stack of two NEW sessions on
    # the right. The bottom-right one runs `top` to show the command field.
    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(original),
        hsplit(
            new_leaf(guid),
            new_leaf(guid, command="top"),
        ),
    ))]}
    print("  applying layout: V[ original , H[ new , new(top) ] ]")
    await app.async_apply_layout(spec)
    await settle()

    app = await refresh(connection)
    tab = find_tab(app, tab.tab_id)
    ids = [s.session_id for s in tab.sessions]
    new_ids = [sid for sid in ids if sid != original.session_id]
    print(f"  tab now has {len(tab.sessions)} panes; "
          f"{len(new_ids)} created by apply_layout")
    assert len(tab.sessions) == 3, "expected 3 panes"
    assert original.session_id in ids, "original should survive"
    return app


async def demo_cwd_inheritance(connection, app, window):
    banner("2. New pane inherits a neighbor's working directory")
    tab = window.current_tab
    # Use the top-left pane as the anchor and cd it somewhere distinctive.
    anchor = tab.sessions[0]
    target_dir = "/tmp"
    print(f"  cd anchor pane {anchor.session_id[:8]} to {target_dir}")
    await anchor.async_send_text(f"cd {target_dir}\n")
    await settle()

    guid = (await anchor.async_get_profile()).guid
    # Add a new pane directly below the anchor. It should start in the
    # anchor's directory IF the profile reuses the previous directory.
    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        hsplit(leaf(anchor), new_leaf(guid)),
        *[leaf(s) for s in tab.sessions[1:]],
    ))]}
    print("  adding a new pane below the anchor")
    await app.async_apply_layout(spec)
    await settle()

    app = await refresh(connection)
    tab = find_tab(app, tab.tab_id)
    known = {anchor.session_id} | {s.session_id for s in tab.sessions
                                   if s.session_id != anchor.session_id}
    # Identify the brand-new pane: not present before this call.
    new_session = None
    for s in tab.sessions:
        path = await s.async_get_variable("path")
        if s.session_id != anchor.session_id and path == target_dir:
            new_session = s
            break
    if new_session is None:
        new_session = tab.sessions[-1]
    path = await new_session.async_get_variable("path")
    print(f"  new pane {new_session.session_id[:8]} path = {path!r} "
          f"(want {target_dir!r} if the profile reuses the directory)")
    print("  sending `pwd` to the new pane so you can see it on screen:")
    await new_session.async_send_text("pwd\n")
    await settle()
    return app


async def demo_new_pane_on_top(connection, app, window):
    banner("3. Add a new full-width pane on top of the existing layout")
    tab = window.current_tab
    guid = (await tab.sessions[0].async_get_profile()).guid
    # New pane spans the full width above everything that's there now.
    existing = [leaf(s) for s in tab.sessions]
    spec = {"tabs": [reshape(tab.tab_id, hsplit(
        new_leaf(guid),
        vsplit(*existing) if len(existing) > 1 else existing[0],
    ))]}
    print("  applying layout: H[ NEW , <everything that was there> ]")
    await app.async_apply_layout(spec)
    await settle()
    app = await refresh(connection)
    tab = find_tab(app, tab.tab_id)
    print(f"  tab now has {len(tab.sessions)} panes")
    return app


async def demo_bad_profile_rejected(connection, app, window):
    banner("4. A bad profile GUID is rejected up front (no side effects)")
    tab = window.current_tab
    before = len(tab.sessions)
    spec = {"tabs": [reshape(tab.tab_id, vsplit(
        leaf(tab.sessions[0]),
        new_leaf("this-is-not-a-real-profile-guid"),
    ))]}
    try:
        await app.async_apply_layout(spec)
        print("  ERROR: expected a rejection but none happened")
    except iterm2.rpc.RPCException as exc:
        print(f"  rejected as expected: {exc}")
    await settle(0.3)
    app = await refresh(connection)
    tab = find_tab(app, tab.tab_id)
    print(f"  pane count unchanged: {before} -> {len(tab.sessions)}")
    return app


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

async def main(connection):
    app = await iterm2.async_get_app(connection)

    if not iterm2.capabilities.supports_apply_layout_new_session(connection):
        print("This iTerm2 is too old: it does not support new_session leaves "
              "in apply_layout. Use a nightly/debug build (protocol >= 1.16).")
        return

    banner("Creating a dedicated window for the demo")
    window = await iterm2.Window.async_create(connection)
    if window is None:
        print("Could not create a window.")
        return
    app = await refresh(connection)
    window = next(w for w in app.windows if w.window_id == window.window_id)
    await window.async_activate()
    print(f"  window {window.window_id}")

    try:
        app = await demo_three_pane_from_one(connection, app, window)
        window = next(w for w in app.windows
                      if w.window_id == window.window_id)
        app = await demo_cwd_inheritance(connection, app, window)
        window = next(w for w in app.windows
                      if w.window_id == window.window_id)
        app = await demo_new_pane_on_top(connection, app, window)
        window = next(w for w in app.windows
                      if w.window_id == window.window_id)
        app = await demo_bad_profile_rejected(connection, app, window)
    finally:
        banner("Done")
        if "--close" in sys.argv:
            window = next((w for w in (await refresh(connection)).windows
                           if w.window_id == window.window_id), None)
            if window is not None:
                await window.async_close(force=True)
            print("  closed the demo window")
        else:
            print("  leaving the demo window open for inspection "
                  "(pass --close to auto-close)")


if __name__ == "__main__":
    iterm2.run_until_complete(main)
