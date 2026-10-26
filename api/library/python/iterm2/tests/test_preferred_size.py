"""Tests for Session.preferred_size and Tab.async_update_layout."""

import asyncio
from types import SimpleNamespace

import iterm2


def set_summary(message, session_id, width, height=40):
    message.unique_identifier = session_id
    message.grid_size.width = width
    message.grid_size.height = height
    message.title = session_id


def list_sessions_response(widths):
    """A layout with one window and one tab split into sessions of the given
    widths."""
    response = iterm2.api_pb2.ListSessionsResponse()
    window = response.windows.add()
    window.window_id = "w"
    tab = window.tabs.add()
    tab.tab_id = "1"
    tab.root.vertical = True
    for i, width in enumerate(widths):
        link = tab.root.links.add()
        set_summary(link.session, f"s{i}", width)
    return response


def make_app(widths):
    connection = SimpleNamespace(iterm2_protocol_version=(1, 21))
    windows = iterm2.App._windows_from_list_sessions_response(
        connection, list_sessions_response(widths)
    )
    app = iterm2.App(connection, windows, [])

    async def async_refresh_focus():
        return None

    app.async_refresh_focus = async_refresh_focus
    return app


def change_layout(app, widths):
    layout = SimpleNamespace(list_sessions_response=list_sessions_response(widths))
    asyncio.run(app._async_handle_layout_change(None, layout))


def capture_set_tab_layout(monkeypatch):
    sent = []

    async def async_set_tab_layout(_connection, tab_id, root):
        sent.append((tab_id, [link.session.grid_size.width for link in root.links]))
        return SimpleNamespace(
            set_tab_layout_response=SimpleNamespace(
                status=iterm2.api_pb2.SetTabLayoutResponse.Status.Value("OK")
            )
        )

    monkeypatch.setattr(iterm2.tab, "async_set_tab_layout", async_set_tab_layout)
    return sent


def test_layout_change_refreshes_preferred_size():
    """After a split, the original session's preferred size is its new size,
    so a no-op layout update doesn't grow it back to its old width."""
    app = make_app([196])
    original = app.get_session_by_id("s0")
    assert original.preferred_size.width == 196

    change_layout(app, [95, 96])

    assert app.get_session_by_id("s0") is original
    assert original.preferred_size.width == 95


def test_noop_update_layout_after_split_sends_current_sizes(monkeypatch):
    app = make_app([196])
    change_layout(app, [95, 96])
    sent = capture_set_tab_layout(monkeypatch)

    asyncio.run(app.get_tab_by_id("1").async_update_layout())

    assert sent == [("1", [95, 96])]


def test_layout_change_keeps_a_preferred_size_the_script_set():
    """A size the script asked for survives a layout change until it is
    applied."""
    app = make_app([196])
    original = app.get_session_by_id("s0")
    original.preferred_size = iterm2.util.Size(50, 40)

    change_layout(app, [95, 96])

    assert original.preferred_size.width == 50


def test_preferred_size_follows_layout_again_once_applied(monkeypatch):
    app = make_app([95, 96])
    original = app.get_session_by_id("s0")
    original.preferred_size = iterm2.util.Size(50, 40)
    sent = capture_set_tab_layout(monkeypatch)

    asyncio.run(app.get_tab_by_id("1").async_update_layout())
    assert sent == [("1", [50, 96])]

    # The server applied it, then a later split changed it again.
    change_layout(app, [50, 141])
    change_layout(app, [25, 24, 141])

    assert original.preferred_size.width == 25


def test_preferred_size_is_not_the_grid_size_object():
    """Changing preferred_size in place must not change grid_size."""
    app = make_app([95, 96])
    original = app.get_session_by_id("s0")
    original.preferred_size.width = 80
    assert original.grid_size.width == 95

    change_layout(app, [90, 101])
    original.preferred_size.width = 70
    assert original.grid_size.width == 90
