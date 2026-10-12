"""
Helps determine which features are available for the currently connected app.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .connection import Connection


class AppVersionTooOld(Exception):
    """Raised when you need a newer version of iTerm2."""


# pylint: disable=invalid-name
def ge(a: Sequence[int], b: Sequence[int]) -> bool:
    """Is a >= b?"""
    if a[0] > b[0]:
        return True
    if a[0] < b[0]:
        return False
    return a[1] >= b[1]


# pylint: enable=invalid-name


def supports_multiple_set_profile_properties(connection: Connection) -> bool:
    """Can multiple profile properties be set in one call?"""
    min_ver = (0, 69)
    return ge(connection.iterm2_protocol_version, min_ver)


def supports_select_pane_in_direction(connection: Connection) -> bool:
    """Can you select pane left/right/up/down?"""
    min_ver = (1, 0)
    return ge(connection.iterm2_protocol_version, min_ver)


def supports_prompt_monitor_modes(connection: Connection) -> bool:
    """Can you monitor the prompt in different modes?"""
    min_ver = (1, 1)
    return ge(connection.iterm2_protocol_version, min_ver)


def supports_status_bar_unread_count(connection: Connection) -> bool:
    """Can the status bar show an unread count?"""
    min_ver = (1, 2)
    return ge(connection.iterm2_protocol_version, min_ver)


def supports_coprocesses(connection: Connection) -> bool:
    """Can you manipulate coprocesses?"""
    min_ver = (1, 3)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_coprocesses(connection: Connection) -> None:
    """Die if you can't manipulate coprocesses."""
    if not supports_coprocesses(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to control "
            + "coprocesses from a Python script. You should upgrade to "
            + "run this script."
        )


def supports_get_default_profile(connection: Connection) -> bool:
    """Can you get the default profile?"""
    min_ver = (1, 4)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_get_default_profile(connection: Connection) -> None:
    """Die if you can't get the default profile."""
    if not supports_get_default_profile(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to get the "
            + "default profile from a Python script. You should upgrade "
            + "to run this script."
        )


def supports_prompt_id(connection: Connection) -> bool:
    """Can you list prompts or get a prompt by ID?"""
    min_ver = (1, 5)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_prompt_id(connection: Connection) -> None:
    """Die if you can't list prompts."""
    if not supports_prompt_id(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to fetch a list of "
            + "prompts or get a prompt by ID from a Python script. "
            + "You should upgrade to run this script."
        )


def supports_list_saved_arrangements(connection: Connection) -> bool:
    """Can you get a list of saved arrangements?"""
    min_ver = (1, 6)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_list_saved_arrangements(connection: Connection) -> None:
    """Die if you can't get a list of saved arrangements."""
    if not supports_list_saved_arrangements(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to get the "
            + "default profile from a Python script. You should upgrade "
            + "to run this script."
        )


def supports_context_menu_providers(connection: Connection) -> bool:
    """Can you register a context menu provider?"""
    min_ver = (1, 7)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_context_menu_provider(connection: Connection) -> None:
    """ "Die if context menu providers are not supported."""
    if not supports_context_menu_providers(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to register a "
            + "context menu provider. You should upgrade to "
            + "run this script."
        )


def supports_add_annotation(connection: Connection) -> bool:
    """Can you add an annotation?"""
    min_ver = (1, 8)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_add_annotation(connection: Connection) -> None:
    """Die if you can't add an annotation."""
    if not supports_add_annotation(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to add an annotation. "
            + "You should upgrade to run this script."
        )


def supports_advanced_key_notifications(connection: Connection) -> bool:
    """Can you get key-up and flags-changed notifs?"""
    min_ver = (1, 9)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_advanced_key_notifications(connection: Connection) -> None:
    """Die if you can't get key-up and flags-changed notifs."""
    if not supports_advanced_key_notifications(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to get advanced keystroke "
            + "notifications. You should upgrade to run this script."
        )


def supports_file_panels(connection: Connection) -> bool:
    """ "Can you use open/save panels?"""
    min_ver = (1, 10)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_file_panels(connection: Connection) -> None:
    """ "Die if you can't use open/save panels."""
    if not supports_file_panels(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to use open/save panels. "
            + "You should upgrade to run this script."
        )


def supports_move_session(connection: Connection) -> bool:
    """ "Can you use move_session()?"""
    min_ver = (1, 11)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_move_session(connection: Connection) -> None:
    if not supports_move_session(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to move sessions to split panes. "
            + "You should upgrade to run this script."
        )


def supports_load_url(connection: Connection) -> bool:
    """Can you use load_url() in browser sessions?"""
    min_ver = (1, 12)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_load_url(connection: Connection) -> None:
    """Die if you can't use load_url()."""
    if not supports_load_url(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to load URLs in browser sessions. "
            + "You should upgrade to run this script."
        )


def supports_move_session_to_tab_or_window(connection: Connection) -> bool:
    """Can you use move_session_to_new_tab() or move_session_to_new_window()?"""
    min_ver = (1, 13)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_move_session_to_tab_or_window(connection: Connection) -> None:
    if not supports_move_session_to_tab_or_window(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to move sessions to new tabs or windows. "
            + "You should upgrade to run this script."
        )


def supports_apply_layout(connection: Connection) -> bool:
    """Can you use App.async_apply_layout()?"""
    min_ver = (1, 14)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_apply_layout(connection: Connection) -> None:
    if not supports_apply_layout(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to apply layouts via the Python API. "
            + "You should upgrade to run this script."
        )


def supports_apply_layout_new_session(connection: Connection) -> bool:
    """Can App.async_apply_layout() create new sessions inline via
    `new_session` leaves?"""
    min_ver = (1, 16)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_apply_layout_new_session(connection: Connection) -> None:
    if not supports_apply_layout_new_session(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to create new sessions via "
            "apply_layout (new_session leaves). You should upgrade to run "
            "this script."
        )


def supports_prompt_excluded_subranges(connection: Connection) -> bool:
    """Does GetPromptResponse populate excluded_subranges (PS2 prefixes,
    right-prompt cells inside the command range)?"""
    min_ver = (1, 15)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_prompt_excluded_subranges(connection: Connection) -> None:
    if not supports_prompt_excluded_subranges(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to report excluded subranges "
            + "(PS2 prefixes, right-prompt cells) on prompts. You should "
            + "upgrade to run this script."
        )


def supports_screenshot(connection: Connection) -> bool:
    """Can you use Session.async_screenshot()?"""
    min_ver = (1, 17)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_screenshot(connection: Connection) -> None:
    if not supports_screenshot(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to capture screenshots via "
            + "the Python API. You should upgrade to run this script."
        )


def supports_tab_groups(connection: Connection) -> bool:
    """Can you discover and modify tab groups?"""
    min_ver = (1, 19)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_tab_groups(connection: Connection) -> None:
    if not supports_tab_groups(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to control tab groups via "
            + "the Python API. You should upgrade to run this script."
        )


def supports_session_note(connection: Connection) -> bool:
    """Can you read and write a session's Session Note?"""
    min_ver = (1, 20)
    return ge(connection.iterm2_protocol_version, min_ver)


def supports_floating_panes(connection: Connection) -> bool:
    """Does iTerm2 report and arrange floating panes?"""
    min_ver = (1, 21)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_floating_panes(connection: Connection) -> None:
    if not supports_floating_panes(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to control floating panes "
            + "via the Python API. You should upgrade to run this script."
        )


def check_supports_session_note(connection: Connection) -> None:
    if not supports_session_note(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to read or write Session "
            + "Notes via the Python API. You should upgrade to run this "
            + "script."
        )
