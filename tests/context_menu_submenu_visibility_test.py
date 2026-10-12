#!/usr/bin/env python3
"""
Manual test for the submenu and visible_when arguments of
ContextMenuProviderRPC (issue 13007).

The script opens a window with three tabs:
  - "BOUND": user.ezboot_bound is True (set from Python) and user.provider
    is "codex".
  - "SHELL": user.ezboot_bound is the string "1", set by the shell with the
    SetUserVar escape sequence, as iterm2_set_user_var would. This checks
    that `user.ezboot_bound == 1` matches a string as well as a boolean.
  - "UNBOUND": user.ezboot_bound is False and user.provider is unset, so
    "Codex Only" also checks that an undefined variable hides an item.

It then registers these context menu items:
  - "Always Visible" (top level, no visible_when). Shows in both tabs.
  - "Codex Only" (top level, visible_when user.provider == "codex").
  - Submenu "EzBoot" with "Restart Bridge", "Edit Config", and
    "Unbind This Session", all with visible_when user.ezboot_bound == 1.
  - Submenu "Mixed" with "Mixed: Always" and "Mixed: Bound Only". The
    submenu appears in every tab; the second item only when bound.
  - "Bind This Session" (top level, visible_when
    user.ezboot_bound != 1). Rebinds an unbound session.

It also checks that registration rejects a visible_when that calls a
function and one with a syntax error.

Clicking an item writes a line into the clicked session showing which item
ran, its session ID, and the selection. "Unbind" and "Bind" flip
user.ezboot_bound, so reopening the menu in the same session shows the
EzBoot submenu disappear or reappear. That confirms visible_when is
evaluated each time the menu opens.

The script runs until you press Return in the terminal that launched it.
Pass --close to close its window then.

Requirements:
  - An iTerm2 build that speaks protocol 1.23 or later, with the Python API
    enabled.
  - The in-tree iterm2 Python module (2.28 or later). Use
    tests/run_context_menu_submenu_visibility_test.sh to get it.
"""

import asyncio
import sys

import iterm2
import iterm2.capabilities

PREFIX = "com.iterm2.test.contextmenu."
BOUND_EXPR = "user.ezboot_bound == 1"


def banner(lines):
    body = "".join(f"\x1b[1m{line}\x1b[0m\r\n" for line in lines)
    return body.encode("utf-8")


async def report(app, session_id, item, selection):
    session = app.get_session_by_id(session_id)
    if not session:
        print(f"{item}: session {session_id} not found")
        return
    print(f"{item}: session={session_id} selection={selection!r}")
    text = f"\r\n\x1b[32m[{item}]\x1b[0m session={session_id} selection={selection!r}\r\n"
    await session.async_inject(text.encode("utf-8"))


async def expect_rejected(connection, display_name, unique_id, expression):
    @iterm2.ContextMenuProviderRPC
    async def rejected_handler():
        pass

    try:
        await rejected_handler.async_register(
            connection, display_name, PREFIX + unique_id,
            visible_when=expression)
    except iterm2.notifications.SubscriptionException as e:
        print(f"PASS: visible_when={expression!r} was rejected ({e}). "
              "The Script Console shows the reason.")
        return True
    print(f"FAIL: visible_when={expression!r} was accepted but should "
          "have been rejected.")
    return False


async def main(connection):
    if not iterm2.capabilities.supports_context_menu_submenus_and_visibility(connection):
        print(f"iTerm2 protocol {connection.iterm2_protocol_version} is too "
              "old. Run a build with protocol 1.23 or later.")
        return

    app = await iterm2.async_get_app(connection)
    close_at_end = "--close" in sys.argv[1:]

    window = await iterm2.Window.async_create(connection)
    bound_tab = window.current_tab
    shell_tab = await window.async_create_tab()
    unbound_tab = await window.async_create_tab()
    bound = bound_tab.current_session
    shell = shell_tab.current_session
    unbound = unbound_tab.current_session

    await bound_tab.async_set_title("BOUND")
    await shell_tab.async_set_title("SHELL")
    await unbound_tab.async_set_title("UNBOUND")
    await bound.async_set_variable("user.ezboot_bound", True)
    await bound.async_set_variable("user.provider", "codex")
    await unbound.async_set_variable("user.ezboot_bound", False)

    await bound.async_inject(banner([
        "BOUND session: user.ezboot_bound=true, user.provider=codex",
        "Right-click and expect, after a separator:",
        "  Always Visible, Codex Only, EzBoot >, Mixed >",
        "  EzBoot > Edit Config, Restart Bridge, Unbind This Session",
        "  Mixed > Mixed: Always, Mixed: Bound Only",
        "Choose Unbind, then right-click again: EzBoot and Mixed: Bound",
        "Only disappear, and Bind This Session appears.",
    ]))
    await shell.async_inject(banner([
        "SHELL session: the shell sets user.ezboot_bound to the string 1",
        "Right-click and expect, after a separator:",
        "  Always Visible, EzBoot >, Mixed >",
        "  EzBoot > Edit Config, Restart Bridge, Unbind This Session",
        "  Mixed > Mixed: Always, Mixed: Bound Only",
        "No Codex Only and no Bind This Session.",
    ]))
    # MQ== is base64 for "1". This is what iterm2_set_user_var sends.
    await shell.async_send_text(
        "printf '\\033]1337;SetUserVar=ezboot_bound=MQ==\\007'\n")
    await unbound.async_inject(banner([
        "UNBOUND session: user.ezboot_bound=false, user.provider unset",
        "Right-click and expect, after a separator:",
        "  Always Visible, Bind This Session, Mixed >",
        "  Mixed > Mixed: Always (only)",
        "No EzBoot submenu and no Codex Only.",
    ]))

    @iterm2.ContextMenuProviderRPC
    async def always_visible(session_id=iterm2.Reference("id"),
                             selection=iterm2.Reference("selection?")):
        await report(app, session_id, "Always Visible", selection)

    @iterm2.ContextMenuProviderRPC
    async def codex_only(session_id=iterm2.Reference("id"),
                         selection=iterm2.Reference("selection?")):
        await report(app, session_id, "Codex Only", selection)

    @iterm2.ContextMenuProviderRPC
    async def restart_bridge(session_id=iterm2.Reference("id"),
                             selection=iterm2.Reference("selection?")):
        await report(app, session_id, "EzBoot > Restart Bridge", selection)

    @iterm2.ContextMenuProviderRPC
    async def edit_config(session_id=iterm2.Reference("id"),
                          selection=iterm2.Reference("selection?")):
        await report(app, session_id, "EzBoot > Edit Config", selection)

    @iterm2.ContextMenuProviderRPC
    async def unbind(session_id=iterm2.Reference("id"),
                     selection=iterm2.Reference("selection?")):
        session = app.get_session_by_id(session_id)
        if session:
            await session.async_set_variable("user.ezboot_bound", False)
        await report(app, session_id, "EzBoot > Unbind This Session", selection)

    @iterm2.ContextMenuProviderRPC
    async def bind(session_id=iterm2.Reference("id"),
                   selection=iterm2.Reference("selection?")):
        session = app.get_session_by_id(session_id)
        if session:
            await session.async_set_variable("user.ezboot_bound", True)
        await report(app, session_id, "Bind This Session", selection)

    @iterm2.ContextMenuProviderRPC
    async def mixed_always(session_id=iterm2.Reference("id"),
                           selection=iterm2.Reference("selection?")):
        await report(app, session_id, "Mixed > Mixed: Always", selection)

    @iterm2.ContextMenuProviderRPC
    async def mixed_bound(session_id=iterm2.Reference("id"),
                          selection=iterm2.Reference("selection?")):
        await report(app, session_id, "Mixed > Mixed: Bound Only", selection)

    await always_visible.async_register(
        connection, "Always Visible", PREFIX + "always")
    await codex_only.async_register(
        connection, "Codex Only", PREFIX + "codex",
        visible_when='user.provider == "codex"')
    await restart_bridge.async_register(
        connection, "Restart Bridge", PREFIX + "restart",
        submenu="EzBoot", visible_when=BOUND_EXPR)
    await edit_config.async_register(
        connection, "Edit Config", PREFIX + "edit",
        submenu="EzBoot", visible_when=BOUND_EXPR)
    await unbind.async_register(
        connection, "Unbind This Session", PREFIX + "unbind",
        submenu="EzBoot", visible_when=BOUND_EXPR)
    await bind.async_register(
        connection, "Bind This Session", PREFIX + "bind",
        visible_when="user.ezboot_bound != 1")
    await mixed_always.async_register(
        connection, "Mixed: Always", PREFIX + "mixed-always",
        submenu="Mixed")
    await mixed_bound.async_register(
        connection, "Mixed: Bound Only", PREFIX + "mixed-bound",
        submenu="Mixed", visible_when=BOUND_EXPR)
    print("Registered context menu items.")

    ok = await expect_rejected(connection, "Bad Function", "bad-function",
                               "foo(x: 1)")
    ok = await expect_rejected(connection, "Bad Syntax", "bad-syntax",
                               "user.ezboot_bound ==") and ok
    if not ok:
        print("Registration checks FAILED.")

    print("Right-click in the BOUND, SHELL, and UNBOUND tabs and compare with the "
          "banners. Press Return here to exit.")
    await asyncio.get_running_loop().run_in_executor(None, sys.stdin.readline)
    if close_at_end:
        await window.async_close(force=True)


if __name__ == "__main__":
    iterm2.run_until_complete(main)
