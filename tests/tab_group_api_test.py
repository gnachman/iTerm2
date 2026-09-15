#!/usr/bin/env python3
"""Live smoke test for the tab-group Python API.

Creates a named + colored tab group, moves three existing tabs into it,
collapses it, renames it, and reads the membership back — with no modal
prompt and no UI clicking. Run against a running iTerm2 build that has the
tab-group API compiled in and "Enable Python API" turned on:

    ITERM2_COOKIE=... ITERM2_KEY=... \
      PYTHONPATH=api/library/python/iterm2 python3 tests/tab_group_api_test.py

Prints PASS on success; raises AssertionError otherwise.
"""
import iterm2


async def main(connection):
    app = await iterm2.async_get_app(connection)

    # A fresh window with four tabs, so a collapse has a visible tab to move the
    # active selection onto (the group will hold three of the four).
    window = await iterm2.Window.async_create(connection)
    tabs = [window.current_tab]
    for _ in range(3):
        tabs.append(await window.async_create_tab())
    tab_ids = [t.tab_id for t in tabs]
    print("created window %s with tabs %s" % (window.window_id, tab_ids))

    # Create the group from the first tab, no modal prompt: name + color here.
    color = iterm2.Color(0x50, 0xAF, 0xBC)  # #50afbc
    group = await iterm2.TabGroup.async_create(
        connection, [tabs[0]], "phpvms", color)
    print("created group id=%s name=%r color=%s members=%s" % (
        group.group_id, group.name, group.color, group.tab_ids))
    assert group.name == "phpvms", group.name
    assert group.tab_ids == [tab_ids[0]], group.tab_ids

    # Move two more existing tabs into it (exercises assign-to-existing-group).
    await group.async_add_tab(tabs[1])
    await group.async_add_tab(tabs[2])
    print("after moving three tabs in: members=%s" % (group.tab_ids,))
    assert set(group.tab_ids) == set(tab_ids[:3]), group.tab_ids

    # Collapse it.
    await group.async_set_collapsed(True)
    print("collapsed=%s" % group.collapsed)
    assert group.collapsed is True

    # Rename it.
    await group.async_set_name("phpvms-prod")
    print("renamed to %r" % group.name)
    assert group.name == "phpvms-prod"

    # Read the membership back from a fresh enumeration (not the cached handle).
    listed = await iterm2.TabGroup.async_list(connection)
    match = [g for g in listed if g.group_id == group.group_id]
    assert match, "group %s not found in async_list" % group.group_id
    g = match[0]
    print("read back: id=%s name=%r color=%s collapsed=%s members=%s" % (
        g.group_id, g.name, g.color, g.collapsed, g.tab_ids))
    assert g.name == "phpvms-prod", g.name
    assert g.collapsed is True, g.collapsed
    assert set(g.tab_ids) == set(tab_ids[:3]), g.tab_ids

    print("PASS: create + assign(x3) + collapse + rename + read-membership, "
          "no modal prompt, no UI clicking")


iterm2.run_until_complete(main)
