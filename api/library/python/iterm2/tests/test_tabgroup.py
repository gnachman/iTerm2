"""Tests for nested tab group support in iterm2.tab, iterm2.window, and iterm2.tabgroup."""
import asyncio
from types import SimpleNamespace

import pytest

import iterm2


def make_tab(connection, tab_id, group=None, parent=None):
    """A Tab in `group` (id, name), nested in `parent` (id, name) when given."""
    kwargs = {}
    if group:
        kwargs.update(tab_group_id=group[0], tab_group_name=group[1],
                      tab_group_color="#00ff00", tab_group_collapsed=False)
    if parent:
        kwargs.update(tab_group_parent_id=parent[0], tab_group_parent_name=parent[1],
                      tab_group_parent_color="#0000ff", tab_group_parent_collapsed=True)
    return iterm2.Tab(connection, tab_id, iterm2.session.Splitter(), **kwargs)


def make_window(protocol_version=(1, 21)):
    connection = SimpleNamespace(iterm2_protocol_version=protocol_version)
    tabs = [
        make_tab(connection, "1"),
        make_tab(connection, "2", group=("C", "Parakeet"), parent=("P", "Idle")),
        make_tab(connection, "3", group=("P", "Idle")),
        make_tab(connection, "4", group=("D", "Other"), parent=("P", "Idle")),
    ]
    return iterm2.Window(connection, "w1", tabs, None, 0), connection


def test_tab_reports_its_group_and_parent():
    window, _ = make_window()
    tab = window.tabs[1]
    assert tab.tab_group.group_id == "C"
    assert tab.tab_group.parent_group_id == "P"
    assert tab.tab_group_parent.group_id == "P"
    assert tab.tab_group_parent.name == "Idle"
    assert tab.tab_group_parent.collapsed is True
    assert tab.tab_group_parent.parent_group_id is None


def test_top_level_tab_has_no_parent():
    window, _ = make_window()
    assert window.tabs[2].tab_group.parent_group_id is None
    assert window.tabs[2].tab_group_parent is None
    assert window.tabs[0].tab_group_parent is None


def test_window_lists_parent_before_its_subgroups_once():
    """A parent appears once, ahead of its sub-groups, even if its first tab is in a sub-group."""
    window, _ = make_window()
    assert [group.group_id for group in window.tab_groups] == ["P", "C", "D"]


def test_create_tab_group_with_parent_sends_parent_id(monkeypatch):
    window, connection = make_window()
    calls = []

    async def async_invoke_method(actual_connection, receiver, invocation, timeout):
        calls.append(invocation)
        return "NEW"

    monkeypatch.setattr(iterm2.rpc, "async_invoke_method", async_invoke_method)
    parent = window.tabs[2].tab_group
    group = asyncio.run(window.async_create_tab_group("Sub", [window.tabs[0]], parent=parent))

    assert group.group_id == "NEW"
    assert group.parent_group_id == "P"
    assert 'parent_group_id: "P"' in calls[0]


def test_create_tab_group_without_parent_omits_it(monkeypatch):
    window, _ = make_window(protocol_version=(1, 19))
    calls = []

    async def async_invoke_method(actual_connection, receiver, invocation, timeout):
        calls.append(invocation)
        return "NEW"

    monkeypatch.setattr(iterm2.rpc, "async_invoke_method", async_invoke_method)
    group = asyncio.run(window.async_create_tab_group("Top", [window.tabs[0]]))

    assert group.parent_group_id is None
    assert "parent_group_id" not in calls[0]


def test_create_tab_group_with_parent_needs_protocol_1_21(monkeypatch):
    window, _ = make_window(protocol_version=(1, 20))

    async def async_invoke_method(*args):
        raise AssertionError("must not be called")

    monkeypatch.setattr(iterm2.rpc, "async_invoke_method", async_invoke_method)
    with pytest.raises(iterm2.capabilities.AppVersionTooOld):
        asyncio.run(window.async_create_tab_group(
            "Sub", [window.tabs[0]], parent=window.tabs[2].tab_group))
