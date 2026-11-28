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


def test_async_setter_sends_enum_value(monkeypatch):
    sent = []

    async def set_property(connection, session_id, key, value, guids):
        sent.append((key, value))

    monkeypatch.setattr(iterm2.profile, "async_set_profile_property", set_property)
    profile = iterm2.WriteOnlyProfile("session-id", connection=None)

    asyncio.run(profile.async_set_cursor_type(iterm2.CursorType.CURSOR_TYPE_BOX))
    asyncio.run(profile.async_set_window_type(iterm2.WindowType.MAXIMIZED))
    asyncio.run(profile.async_set_columns(100))

    assert sent == [("Cursor Type", 2), ("Window Type", 15), ("Columns", 100)]


def test_local_setter_stores_enum_value():
    profile = iterm2.LocalWriteOnlyProfile()
    profile.set_logging_style(iterm2.LoggingStyle.ASCIICAST)
    profile.set_match_color_dark(iterm2.Color(255, 0, 0))

    assert profile.values["Plain Text Logging"] == "3"
    assert "Match Background Color (Dark)" in profile.values


def test_getter_returns_raw_enum_value():
    properties = [
        iterm2.api_pb2.ProfileProperty(key=key, json_value=value)
        for key, value in {"Timestamps Style": "3", "Tags": '["a", "b"]'}.items()
    ]
    profile = iterm2.Profile(None, None, properties)

    assert profile.timestamps_style == 3
    assert iterm2.TimestampsStyle(profile.timestamps_style) is (
        iterm2.TimestampsStyle.ADJACENT
    )
    assert profile.tags == ["a", "b"]
