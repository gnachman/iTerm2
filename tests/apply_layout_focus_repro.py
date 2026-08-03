#!/usr/bin/env python3
"""
Manual repro for the apply_layout keyboard-focus bug.

Symptom (reported on iterm2-discuss, 3.7.0beta5): after
App.async_apply_layout reshapes a tab whose active pane survives the
reshape (e.g. a fresh one-session tab turning into a multi-pane layout
with new_session leaves), NO pane in that tab holds keyboard focus.
Typing goes nowhere until you click a pane.

Why the API can't check this for you: keyboard focus is the window's
AppKit first responder, which is a UI-level concept not exposed through
the Python API. So this script can only set up the exact repro and ask
you to confirm by typing. It deliberately does NOT click or send text
into any pane, because doing so would either mask the bug (a click sets
first responder) or bypass it (async_send_text writes to the pty
directly, independent of focus).

Everything happens in a window this script creates, so your existing
windows are left alone.

Requirements:
  - A nightly/debug iTerm2 with the apply_layout new_session capability.
  - iterm2 Python module 2.20+.

Usage:
    python3 tests/apply_layout_focus_repro.py
    python3 tests/apply_layout_focus_repro.py --close   # close the window
                                                        # when you press Return
"""

import asyncio
import sys

import iterm2


# --------------------------------------------------------------------------
# Spec helpers - read like layout descriptions rather than JSON.
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


def banner(text):
    print()
    print("=" * 72)
    print(text)
    print("=" * 72)


async def main(connection):
    close_at_end = "--close" in sys.argv[1:]

    app = await iterm2.async_get_app(connection)

    # A brand-new window's tab starts with exactly one session, which is
    # the reporter's "fresh tab" starting point.
    window = await iterm2.Window.async_create(connection)
    await app.async_activate()
    await window.async_activate()

    tab = window.current_tab
    original = tab.sessions[0]
    guid = (await original.async_get_profile()).guid

    banner("Reshaping the fresh 1-session tab into 3 panes in one call")
    print(f"  original session {original.session_id[:8]} (profile {guid[:8]})")
    print("  layout: existing session on the left, two NEW sessions stacked")
    print("          on the right. The existing (active) pane survives, so")
    print("          this is exactly the case that loses first responder.")

    spec = {
        "tabs": [
            reshape(
                tab.tab_id,
                vsplit(
                    leaf(original),
                    hsplit(
                        new_leaf(guid),
                        new_leaf(guid),
                    ),
                ),
            )
        ]
    }
    await app.async_apply_layout(spec)

    # Give the app a moment to finish the reshape and settle.
    await asyncio.sleep(0.5)

    banner("NOW TEST FOCUS - do not click anything first")
    print()
    print("  The 3-pane layout is up in the new window. Bring that window")
    print("  to the front if it is not already, then WITHOUT clicking any")
    print("  pane, start typing.")
    print()
    print("  PASS (bug fixed): characters appear in one of the panes")
    print("                    immediately - a pane already has keyboard")
    print("                    focus.")
    print()
    print("  FAIL (bug present): nothing appears no matter what you type,")
    print("                      until you click a pane. Focus was lost by")
    print("                      the reshape.")
    print()
    print("  Bonus check (the reporter's second symptom): click a pane,")
    print("  then close it with Ctrl-D. Without clicking again, type. If")
    print("  nothing lands until you click, focus was lost on close too.")
    print()
    input("  Press Return when done to finish"
          + (" and close the window." if close_at_end else "."))

    if close_at_end:
        await window.async_close(force=True)


iterm2.run_until_complete(main)
