"""Tests for iterm2.profile."""

import asyncio

import iterm2


def test_setting_none_stores_json_null():
    profile = iterm2.LocalWriteOnlyProfile()
    profile.set_custom_window_title(None)
    profile.set_badge_text("hi")

    assert profile.values == {"Custom Window Title": "null", "Badge Text": '"hi"'}


def test_session_sends_a_cleared_value_as_json_null(monkeypatch):
    connection = type("Connection", (), {"iterm2_protocol_version": (1, 20)})()
    link = iterm2.api_pb2.SplitTreeNode.SplitTreeLink()
    link.session.unique_identifier = "session-id"
    session = iterm2.Session(connection, link)
    sent = []

    async def set_properties(actual_connection, session_id, assignments):
        sent.extend(assignments)
        response = iterm2.api_pb2.ServerOriginatedMessage()
        response.set_profile_property_response.status = (
            iterm2.api_pb2.SetProfilePropertyResponse.Status.Value("OK")
        )
        return response

    monkeypatch.setattr(
        iterm2.session, "async_set_profile_properties_json", set_properties
    )
    monkeypatch.setattr(
        iterm2.session, "supports_multiple_set_profile_properties", lambda c: True
    )
    profile = iterm2.LocalWriteOnlyProfile()
    profile.set_custom_window_title(None)

    asyncio.run(session.async_set_profile_properties(profile))

    assert sent == [("Custom Window Title", "null")]
