"""Tests for tab pinning support in iterm2.tab."""
import asyncio
from types import SimpleNamespace

import pytest

import iterm2


def make_tab(protocol_version=(1, 21), pinned=False):
    """Return a Tab with a minimal connection that reports a protocol version.

    The protocol version matters because pinning checks that the attached
    iTerm2 supports it.
    """
    connection = SimpleNamespace(iterm2_protocol_version=protocol_version)
    return iterm2.Tab(connection, "42", None, pinned=pinned), connection


def make_window_proto(pinned=None):
    """A ListSessionsResponse.Window holding one tab with one session."""
    window = iterm2.api_pb2.ListSessionsResponse.Window()
    window.window_id = "window-id"
    tab = window.tabs.add()
    tab.tab_id = "42"
    tab.root.vertical = True
    link = tab.root.links.add()
    link.session.unique_identifier = "session-id"
    if pinned is not None:
        tab.pinned = pinned
    return window


def test_pinned_defaults_to_false():
    """A tab is unpinned unless the server says otherwise."""
    tab, _ = make_tab()
    assert tab.pinned is False


def test_pinned_is_read_from_list_sessions():
    """Window.create_from_proto carries the pinned flag onto the Tab."""
    connection = SimpleNamespace(iterm2_protocol_version=(1, 21))
    window = iterm2.Window.create_from_proto(
        connection, make_window_proto(pinned=True))
    assert window.tabs[0].pinned is True


def test_pinned_is_false_when_server_omits_it():
    """Older servers do not send the field; the tab reads as unpinned."""
    connection = SimpleNamespace(iterm2_protocol_version=(1, 20))
    window = iterm2.Window.create_from_proto(connection, make_window_proto())
    assert window.tabs[0].pinned is False


def test_update_from_copies_pinned():
    """A refresh replaces the pinned flag with the server's current value."""
    tab, _ = make_tab(pinned=False)
    refreshed, _ = make_tab(pinned=True)
    tab.update_from(SimpleNamespace(
        root=None,
        minimized_sessions=[],
        _Tab__tab_group_id=None,
        _Tab__tab_group_name=None,
        _Tab__tab_group_color=None,
        _Tab__tab_group_collapsed=False,
        _Tab__pinned=refreshed.pinned))
    assert tab.pinned is True


@pytest.mark.parametrize("pinned,expected", [
    (True, "iterm2.set_pinned(pinned: 1)"),
    (False, "iterm2.set_pinned(pinned: 0)"),
])
def test_set_pinned_invokes_tab_method(monkeypatch, pinned, expected):
    """async_set_pinned invokes iterm2.set_pinned on this tab."""
    tab, connection = make_tab()
    calls = []

    async def async_invoke_method(actual_connection, receiver, invocation,
                                  timeout):
        calls.append((actual_connection, receiver, invocation, timeout))

    monkeypatch.setattr(iterm2.rpc, "async_invoke_method", async_invoke_method)

    asyncio.run(tab.async_set_pinned(pinned))

    assert calls == [(connection, "42", expected, -1)]


def test_set_pinned_requires_protocol_1_21(monkeypatch):
    """Against an older iTerm2 the call fails before any RPC is sent."""
    tab, _ = make_tab(protocol_version=(1, 20))

    async def unexpected_rpc(*args, **kwargs):
        del args, kwargs
        raise AssertionError("RPC must not be called on an old iTerm2")

    monkeypatch.setattr(iterm2.rpc, "async_invoke_method", unexpected_rpc)

    with pytest.raises(iterm2.capabilities.AppVersionTooOld):
        asyncio.run(tab.async_set_pinned(True))
