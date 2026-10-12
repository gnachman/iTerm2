"""Tests for iterm2.auth."""

from types import SimpleNamespace

import iterm2.auth


def fake_appkit(info):
    bundle = SimpleNamespace(infoDictionary=lambda: info)
    return SimpleNamespace(NSBundle=SimpleNamespace(mainBundle=lambda: bundle))


def test_background_context_restores_an_existing_value(monkeypatch):
    info = {"LSBackgroundOnly": "0"}
    monkeypatch.setattr(iterm2.auth, "gAppKitAvailable", True)
    monkeypatch.setattr(iterm2.auth, "AppKit", fake_appkit(info), raising=False)

    with iterm2.auth.LSBackgroundContextManager():
        assert info["LSBackgroundOnly"] == "1"

    assert info == {"LSBackgroundOnly": "0"}


def test_background_context_removes_a_value_it_added(monkeypatch):
    info = {}
    monkeypatch.setattr(iterm2.auth, "gAppKitAvailable", True)
    monkeypatch.setattr(iterm2.auth, "AppKit", fake_appkit(info), raising=False)

    with iterm2.auth.LSBackgroundContextManager():
        assert info["LSBackgroundOnly"] == "1"

    assert info == {}
