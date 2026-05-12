"""Tests for iterm2.capabilities module."""
import pytest
from iterm2.capabilities import (
    AppVersionTooOld,
    ge,
    supports_multiple_set_profile_properties,
    supports_select_pane_in_direction,
    supports_prompt_monitor_modes,
    supports_status_bar_unread_count,
    supports_coprocesses,
    check_supports_coprocesses,
    supports_get_default_profile,
    check_supports_get_default_profile,
    supports_prompt_id,
    check_supports_prompt_id,
    supports_list_saved_arrangements,
    check_supports_list_saved_arrangements,
    supports_context_menu_providers,
    check_supports_context_menu_provider,
    supports_add_annotation,
    check_supports_add_annotation,
    supports_advanced_key_notifications,
    check_supports_advanced_key_notifications,
    supports_file_panels,
    check_supports_file_panels,
    supports_move_session,
    check_supports_move_session,
    supports_load_url,
    check_supports_load_url,
    supports_move_session_to_tab_or_window,
    check_supports_move_session_to_tab_or_window,
)


class MockConnection:
    """Mock connection for testing capability checks."""

    def __init__(self, major: int, minor: int):
        self.iterm2_protocol_version = (major, minor)


class TestGe:
    """Tests for the ge() version comparison helper."""

    def test_major_greater(self):
        assert ge((2, 0), (1, 99)) is True

    def test_major_less(self):
        assert ge((1, 0), (2, 0)) is False

    def test_equal_versions(self):
        assert ge((1, 5), (1, 5)) is True

    def test_same_major_minor_greater(self):
        assert ge((1, 10), (1, 5)) is True

    def test_same_major_minor_less(self):
        assert ge((1, 4), (1, 5)) is False

    def test_zero_versions(self):
        assert ge((0, 0), (0, 0)) is True

    def test_large_minor(self):
        assert ge((0, 100), (0, 99)) is True


class TestSupportsMultipleSetProfileProperties:
    """Tests for supports_multiple_set_profile_properties (min: 0.69)."""

    def test_supported(self):
        conn = MockConnection(0, 69)
        assert supports_multiple_set_profile_properties(conn) is True

    def test_above_minimum(self):
        conn = MockConnection(1, 0)
        assert supports_multiple_set_profile_properties(conn) is True

    def test_not_supported(self):
        conn = MockConnection(0, 68)
        assert supports_multiple_set_profile_properties(conn) is False


class TestSupportsSelectPaneInDirection:
    """Tests for supports_select_pane_in_direction (min: 1.0)."""

    def test_supported(self):
        assert supports_select_pane_in_direction(MockConnection(1, 0)) is True

    def test_not_supported(self):
        assert supports_select_pane_in_direction(MockConnection(0, 99)) is False

    def test_newer_version(self):
        assert supports_select_pane_in_direction(MockConnection(2, 0)) is True


class TestSupportsPromptMonitorModes:
    """Tests for supports_prompt_monitor_modes (min: 1.1)."""

    def test_supported(self):
        assert supports_prompt_monitor_modes(MockConnection(1, 1)) is True

    def test_not_supported(self):
        assert supports_prompt_monitor_modes(MockConnection(1, 0)) is False


class TestSupportsStatusBarUnreadCount:
    """Tests for supports_status_bar_unread_count (min: 1.2)."""

    def test_supported(self):
        assert supports_status_bar_unread_count(MockConnection(1, 2)) is True

    def test_not_supported(self):
        assert supports_status_bar_unread_count(MockConnection(1, 1)) is False


class TestSupportsCoprocesses:
    """Tests for supports_coprocesses (min: 1.3)."""

    def test_supported(self):
        assert supports_coprocesses(MockConnection(1, 3)) is True

    def test_not_supported(self):
        assert supports_coprocesses(MockConnection(1, 2)) is False

    def test_check_raises_when_not_supported(self):
        conn = MockConnection(0, 0)
        with pytest.raises(AppVersionTooOld):
            check_supports_coprocesses(conn)

    def test_check_passes_when_supported(self):
        conn = MockConnection(1, 3)
        check_supports_coprocesses(conn)  # should not raise


class TestSupportsGetDefaultProfile:
    """Tests for supports_get_default_profile (min: 1.4)."""

    def test_supported(self):
        assert supports_get_default_profile(MockConnection(1, 4)) is True

    def test_not_supported(self):
        assert supports_get_default_profile(MockConnection(1, 3)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_get_default_profile(MockConnection(0, 0))

    def test_check_passes_when_supported(self):
        check_supports_get_default_profile(MockConnection(1, 4))


class TestSupportsPromptId:
    """Tests for supports_prompt_id (min: 1.5)."""

    def test_supported(self):
        assert supports_prompt_id(MockConnection(1, 5)) is True

    def test_not_supported(self):
        assert supports_prompt_id(MockConnection(1, 4)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_prompt_id(MockConnection(0, 0))


class TestSupportsListSavedArrangements:
    """Tests for supports_list_saved_arrangements (min: 1.6)."""

    def test_supported(self):
        assert supports_list_saved_arrangements(MockConnection(1, 6)) is True

    def test_not_supported(self):
        assert supports_list_saved_arrangements(MockConnection(1, 5)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_list_saved_arrangements(MockConnection(0, 0))


class TestSupportsContextMenuProviders:
    """Tests for supports_context_menu_providers (min: 1.7)."""

    def test_supported(self):
        assert supports_context_menu_providers(MockConnection(1, 7)) is True

    def test_not_supported(self):
        assert supports_context_menu_providers(MockConnection(1, 6)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_context_menu_provider(MockConnection(0, 0))


class TestSupportsAddAnnotation:
    """Tests for supports_add_annotation (min: 1.8)."""

    def test_supported(self):
        assert supports_add_annotation(MockConnection(1, 8)) is True

    def test_not_supported(self):
        assert supports_add_annotation(MockConnection(1, 7)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_add_annotation(MockConnection(0, 0))


class TestSupportsAdvancedKeyNotifications:
    """Tests for supports_advanced_key_notifications (min: 1.9)."""

    def test_supported(self):
        assert supports_advanced_key_notifications(MockConnection(1, 9)) is True

    def test_not_supported(self):
        assert supports_advanced_key_notifications(MockConnection(1, 8)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_advanced_key_notifications(MockConnection(0, 0))


class TestSupportsFilePanels:
    """Tests for supports_file_panels (min: 1.10)."""

    def test_supported(self):
        assert supports_file_panels(MockConnection(1, 10)) is True

    def test_not_supported(self):
        assert supports_file_panels(MockConnection(1, 9)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_file_panels(MockConnection(0, 0))


class TestSupportsMoveSession:
    """Tests for supports_move_session (min: 1.11)."""

    def test_supported(self):
        assert supports_move_session(MockConnection(1, 11)) is True

    def test_not_supported(self):
        assert supports_move_session(MockConnection(1, 10)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_move_session(MockConnection(0, 0))


class TestSupportsLoadUrl:
    """Tests for supports_load_url (min: 1.12)."""

    def test_supported(self):
        assert supports_load_url(MockConnection(1, 12)) is True

    def test_not_supported(self):
        assert supports_load_url(MockConnection(1, 11)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_load_url(MockConnection(0, 0))


class TestSupportsMoveSessionToTabOrWindow:
    """Tests for supports_move_session_to_tab_or_window (min: 1.13)."""

    def test_supported(self):
        assert supports_move_session_to_tab_or_window(MockConnection(1, 13)) is True

    def test_not_supported(self):
        assert supports_move_session_to_tab_or_window(MockConnection(1, 12)) is False

    def test_check_raises_when_not_supported(self):
        with pytest.raises(AppVersionTooOld):
            check_supports_move_session_to_tab_or_window(MockConnection(0, 0))

    def test_major_version_override(self):
        """Major version 2+ supports everything."""
        assert supports_move_session_to_tab_or_window(MockConnection(2, 0)) is True


class TestAppVersionTooOld:
    """Tests for AppVersionTooOld exception."""

    def test_is_exception(self):
        assert issubclass(AppVersionTooOld, Exception)

    def test_message(self):
        exc = AppVersionTooOld("test message")
        assert "test message" in str(exc)
