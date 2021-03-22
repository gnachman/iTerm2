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

def supports_list_saved_arrangements(connection):
    """Can you get a list of saved arrangements?"""
    min_ver = (1, 6)
    return ge(connection.iterm2_protocol_version, min_ver)


def check_supports_list_saved_arrangements(connection):
    """Die if you can't get a list of saved arrangements."""
    if not supports_list_saved_arrangements(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to get the " +
            "default profile from a Python script. You should upgrade " +
            "to run this script.")

def supports_context_menu_providers(connection):
    """Can you register a context menu provider?"""
    min_ver = (1, 7)
    return ge(connection.iterm2_protocol_version, min_ver)

def check_supports_context_menu_provider(connection):
    """"Die if context menu providers are not supported."""
    if not supports_context_menu_providers(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to register a " +
            "context menu provider. You should upgrade to " +
            "run this script.")

def supports_add_annotation(connection):
    """Can you add an annotation?"""
    min_ver = (1, 8)
    return ge(connection.iterm2_protocol_version, min_ver)

def check_supports_add_annotation(connection):
    """Die if you can't add an annotation."""
    if not supports_add_annotation(connection):
        raise AppVersionTooOld(
            "This version of iTerm2 is too old to add an annotation. " +
            "You should upgrade to run this script.")

def supports_advanced_key_notifications(connection):
  """Can you get key-up and flags-changed notifs?"""
  min_ver = (1, 9)
  return ge(connection.iterm2_protocol_version, min_ver)

def check_supports_advanced_key_notifications(connection):
  """Die if you can't get key-up and flags-changed notifs."""
  if not supports_advanced_key_notifications(connection):
    raise AppVersionTooOld(
        "This version of iTerm2 is too old to get advanced keystroke " +
        "notifications. You should upgrade to run this script.")

