"""Tests for registering context menu providers."""
import asyncio
import warnings
from types import SimpleNamespace

import iterm2
import iterm2.notifications


def register(monkeypatch, protocol_version=(1, 23), **kwargs):
    """Registers a provider and returns the RPCRegistrationRequest it sent."""
    captured = {}

    async def fake_subscribe(connection, subscribe, notification_type, callback, **kw):
        captured.update(kw)
        return "token"

    monkeypatch.setattr(iterm2.notifications, "_async_subscribe", fake_subscribe)

    @iterm2.ContextMenuProviderRPC
    async def handler(session_id=iterm2.Reference("id")):
        pass

    connection = SimpleNamespace(iterm2_protocol_version=protocol_version)
    asyncio.run(handler.async_register(connection, "Unbind", "com.example.unbind", **kwargs))
    return captured["rpc_registration_request"]


def test_submenu_and_visible_when_are_sent(monkeypatch):
    request = register(monkeypatch, submenu="EzBoot", visible_when="user.ezboot_bound")
    attributes = request.context_menu_attributes
    assert attributes.display_name == "Unbind"
    assert attributes.unique_identifier == "com.example.unbind"
    assert attributes.submenu == "EzBoot"
    assert attributes.visible_when == "user.ezboot_bound"


def test_omitted_arguments_leave_fields_unset(monkeypatch):
    attributes = register(monkeypatch).context_menu_attributes
    assert not attributes.HasField("submenu")
    assert not attributes.HasField("visible_when")


def test_old_app_warns_when_new_arguments_are_passed(monkeypatch):
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        register(monkeypatch, protocol_version=(1, 22), visible_when="user.x")
    assert any("3.7.6" in str(w.message) for w in caught)


def test_old_app_does_not_warn_without_new_arguments(monkeypatch):
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        register(monkeypatch, protocol_version=(1, 22))
    assert not caught


def test_new_app_does_not_warn(monkeypatch):
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        register(monkeypatch, submenu="EzBoot", visible_when="user.x")
    assert not caught
