"""Tests for iterm2.window."""

from types import SimpleNamespace

import pytest

import iterm2


@pytest.mark.parametrize("collapsed", [False, True])
def test_tab_group_collapsed_state_comes_from_the_proto(collapsed):
    window = iterm2.api_pb2.ListSessionsResponse.Window()
    window.window_id = "w"
    tab = window.tabs.add()
    tab.tab_id = "1"
    tab.root.links.add().session.unique_identifier = "s"
    tab.tab_group_id = "group"
    tab.tab_group_collapsed = collapsed
    connection = SimpleNamespace(iterm2_protocol_version=(1, 21))

    group = iterm2.Window.create_from_proto(connection, window).tabs[0].tab_group

    assert group.collapsed is collapsed
