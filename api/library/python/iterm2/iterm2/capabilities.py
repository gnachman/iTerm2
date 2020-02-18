"""
Helps determine which features are available for the currently connected app.
"""

class AppVersionTooOld(Exception):
    """Raised when you need a newer version of iTerm2."""


# pylint: disable=invalid-name
def ge(a, b):
    """Is a >= b?"""
    if a[0] > b[0]:
        return True
    if a[0] < b[0]:
        return False
    return a[1] >= b[1]
# pylint: enable=invalid-name


def supports_multiple_set_profile_properties(connection):
    """Can multiple profile properties be set in one call?"""
    min_ver = (0, 69)
    return ge(connection.iterm2_protocol_version, min_ver)


def supports_select_pane_in_direction(connection):
    """Can you select pane left/right/up/down?"""
    min_ver = (1, 0)
    return ge(connection.iterm2_protocol_version, min_ver)


def supports_prompt_monitor_modes(connection):
    """Can you monitor the prompt in different modes?"""
    min_ver = (1, 1)
    return ge(connection.iterm2_protocol_version, min_ver)


def supports_status_bar_unread_count(connection):
    """Can the status bar show an unread count?"""
    min_ver = (1, 2)
    return ge(connection.iterm2_protocol_version, min_ver)


def supports_coprocesses(connection):
    """Can you manipulate coprocesses?"""
    min_ver = (1, 3)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_coprocesses(connection):
    """Die if you can't manipulate coprocesses."""
    if not supports_coprocesses(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to control " +
            "coprocesses from a Python script. You should upgrade to " +
            "run this script.")


def supports_get_default_profile(connection):
    """Can you get the default profile?"""
    min_ver = (1, 4)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_get_default_profile(connection):
    """Die if you can't get the default profile."""
    if not supports_get_default_profile(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to get the " +
            "default profile from a Python script. You should upgrade " +
            "to run this script.")

def supports_prompt_id(connection):
    """Can you list prompts or get a prompt by ID?"""
    min_ver = (1, 5)
    return ge(connection.iterm2_protocol_version, min_ver)

def check_supports_prompt_id(connection):
    """Die if you can't list prompts."""
    if not supports_prompt_id(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to fetch a list of " +
            "prompts or get a prompt by ID from a Python script. " +
            "You should upgrade to run this script.")
