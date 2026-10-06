"""Tests for floating panes in iterm2.tab and iterm2.window."""
from types import SimpleNamespace

import iterm2


def summary(message, session_id, x=0, y=0, width=100, height=50):
    message.unique_identifier = session_id
    message.frame.origin.x = x
    message.frame.origin.y = y
    message.frame.size.width = width
    message.frame.size.height = height
    message.grid_size.width = width // 10
    message.grid_size.height = height // 10
    message.title = session_id


def make_window(active_session_id="float-front", hidden=False):
    """A window whose tab has one tiled session and two floats."""
    window = iterm2.api_pb2.ListSessionsResponse.Window()
    window.window_id = "w"
    tab = window.tabs.add()
    tab.tab_id = "1"
    link = tab.root.links.add()
    summary(link.session, "tiled")
    for i, session_id in enumerate(("float-back", "float-front")):
        floating_pane = tab.floating_panes.add()
        summary(floating_pane.session, session_id, x=10 * i, y=20 * i, width=300, height=200)
    tab.floating_panes_hidden = hidden
    tab.active_session_id = active_session_id
    connection = SimpleNamespace(iterm2_protocol_version=(1, 21))
    return iterm2.Window.create_from_proto(connection, window)


def test_floats_are_listed_apart_from_the_tree():
    tab = make_window().tabs[0]
    assert [s.session_id for s in tab.sessions] == ["tiled"]
    assert [s.session_id for s in tab.floating_sessions] == ["float-back", "float-front"]
    assert [s.session_id for s in tab.all_sessions] == ["tiled", "float-back", "float-front"]
    assert tab.floating_panes_hidden is False


def test_a_float_has_a_frame_and_grid_and_is_not_buried():
    float_session = make_window().tabs[0].floating_sessions[1]
    assert float_session.floating is True
    assert float_session.buried is False
    assert float_session.frame.origin.x == 10
    assert float_session.frame.origin.y == 20
    assert float_session.grid_size.width == 30
    assert float_session.grid_size.height == 20
    tiled = make_window().tabs[0].sessions[0]
    assert tiled.floating is False


def test_current_session_can_be_a_float():
    tab = make_window(active_session_id="float-front").tabs[0]
    assert tab.current_session is not None
    assert tab.current_session.session_id == "float-front"


def test_hidden_state_is_reported():
    assert make_window(hidden=True).tabs[0].floating_panes_hidden is True


def test_update_from_carries_floats():
    old = make_window().tabs[0]
    new_window = iterm2.api_pb2.ListSessionsResponse.Window()
    new_tab = new_window.tabs.add()
    new_tab.tab_id = "1"
    summary(new_tab.root.links.add().session, "tiled")
    connection = SimpleNamespace(iterm2_protocol_version=(1, 21))
    new = iterm2.Window.create_from_proto(connection, new_window).tabs[0]
    old.update_from(new)
    assert old.floating_sessions == []


def test_update_session_replaces_a_float():
    tab = make_window().tabs[0]
    replacement = tab.floating_sessions[0]
    replacement.name = "renamed"
    tab.update_session(replacement)
    assert tab.floating_sessions[0].name == "renamed"


def test_older_servers_report_no_floats():
    window = iterm2.api_pb2.ListSessionsResponse.Window()
    tab = window.tabs.add()
    tab.tab_id = "1"
    summary(tab.root.links.add().session, "tiled")
    connection = SimpleNamespace(iterm2_protocol_version=(1, 20))
    parsed = iterm2.Window.create_from_proto(connection, window).tabs[0]
    assert parsed.floating_sessions == []
    assert parsed.floating_panes_hidden is False
