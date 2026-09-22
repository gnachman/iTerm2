"""Tests for Session Note support in iterm2.session."""
import asyncio
import json
from types import SimpleNamespace

import pytest

import iterm2


def make_session():
    """Return a Session with a minimal real protobuf link."""
    connection = object()
    link = iterm2.api_pb2.SplitTreeNode.SplitTreeLink()
    link.session.unique_identifier = "session-id"
    return iterm2.Session(connection, link), connection


def test_session_note_is_exported_with_read_only_properties():
    """SessionNote exposes immutable text, visibility, and collapse state."""
    note = iterm2.SessionNote("remember this", True, False)

    assert note.text == "remember this"
    assert note.visible is True
    assert note.collapsed is False
    for name in ("text", "visible", "collapsed"):
        with pytest.raises(AttributeError):
            setattr(note, name, "changed")


def test_get_session_note_requests_and_parses_complete_state(monkeypatch):
    """The getter targets this session and returns every Session Note field."""
    session, connection = make_session()
    calls = []

    async def async_get_property(actual_connection, name, session_id):
        calls.append((actual_connection, name, session_id))
        return SimpleNamespace(
            get_property_response=SimpleNamespace(
                status=iterm2.api_pb2.GetPropertyResponse.Status.Value("OK"),
                json_value=json.dumps({
                    "text": "remember this",
                    "visible": True,
                    "collapsed": False,
                })))

    monkeypatch.setattr(iterm2.rpc, "async_get_property", async_get_property)

    note = asyncio.run(session.async_get_session_note())

    assert calls == [(connection, "session_note", "session-id")]
    assert isinstance(note, iterm2.SessionNote)
    assert (note.text, note.visible, note.collapsed) == (
        "remember this", True, False)


def test_set_session_note_sends_only_text_when_other_fields_are_omitted(
        monkeypatch):
    """A text-only update does not overwrite visibility or collapse state."""
    session, connection = make_session()
    calls = []

    async def async_set_property(
            actual_connection, name, json_value, session_id):
        calls.append((actual_connection, name, json_value, session_id))
        return SimpleNamespace(
            set_property_response=SimpleNamespace(
                status=iterm2.api_pb2.SetPropertyResponse.Status.Value("OK")))

    monkeypatch.setattr(iterm2.rpc, "async_set_property", async_set_property)

    asyncio.run(session.async_set_session_note(text="updated"))

    assert len(calls) == 1
    actual_connection, name, json_value, session_id = calls[0]
    assert actual_connection is connection
    assert name == "session_note"
    assert json.loads(json_value) == {"text": "updated"}
    assert session_id == "session-id"


def test_set_session_note_serializes_a_complete_patch(monkeypatch):
    """A complete update serializes both booleans as JSON booleans."""
    session, _ = make_session()
    values = []

    async def async_set_property(connection, name, json_value, session_id):
        del connection, name, session_id
        values.append(json_value)
        return SimpleNamespace(
            set_property_response=SimpleNamespace(
                status=iterm2.api_pb2.SetPropertyResponse.Status.Value("OK")))

    monkeypatch.setattr(iterm2.rpc, "async_set_property", async_set_property)

    asyncio.run(session.async_set_session_note(
        text="updated", visible=False, collapsed=True))

    assert json.loads(values[0]) == {
        "text": "updated",
        "visible": False,
        "collapsed": True,
    }
    assert '"visible": false' in values[0]
    assert '"collapsed": true' in values[0]


def test_set_session_note_rejects_an_empty_patch_before_rpc(monkeypatch):
    """An update with no supplied fields fails without contacting iTerm2."""
    session, _ = make_session()

    async def unexpected_rpc(*args, **kwargs):
        del args, kwargs
        raise AssertionError("RPC must not be called for an empty patch")

    monkeypatch.setattr(iterm2.rpc, "async_set_property", unexpected_rpc)

    with pytest.raises(ValueError, match="At least one Session Note field"):
        asyncio.run(session.async_set_session_note())


def test_get_session_note_raises_rpc_exception_for_non_ok_status(monkeypatch):
    """A rejected Session Note read surfaces the server status."""
    session, _ = make_session()

    async def async_get_property(connection, name, session_id):
        del connection, name, session_id
        return SimpleNamespace(
            get_property_response=SimpleNamespace(
                status=iterm2.api_pb2.GetPropertyResponse.Status.Value(
                    "INVALID_TARGET"),
                json_value=""))

    monkeypatch.setattr(iterm2.rpc, "async_get_property", async_get_property)

    with pytest.raises(iterm2.rpc.RPCException, match="INVALID_TARGET"):
        asyncio.run(session.async_get_session_note())


def test_set_session_note_raises_rpc_exception_for_non_ok_status(monkeypatch):
    """A rejected Session Note update surfaces the server status."""
    session, _ = make_session()

    async def async_set_property(connection, name, json_value, session_id):
        del connection, name, json_value, session_id
        return SimpleNamespace(
            set_property_response=SimpleNamespace(
                status=iterm2.api_pb2.SetPropertyResponse.Status.Value(
                    "INVALID_VALUE")))

    monkeypatch.setattr(iterm2.rpc, "async_set_property", async_set_property)

    with pytest.raises(iterm2.rpc.RPCException, match="INVALID_VALUE"):
        asyncio.run(session.async_set_session_note(text="updated"))
