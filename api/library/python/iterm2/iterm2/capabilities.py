class AppVersionTooOld(Exception):
    """Raised when you need a newer version of iTerm2."""
    pass

def ge(a, b):
    """Is a >= b?"""
    if a[0] > b[0]:
        return True
    if a[0] < b[0]:
        return False
    return a[1] >= b[1]

def supports_multiple_set_profile_properties(connection):
    min_ver = (0, 69)
    return ge(connection.iterm2_protocol_version, min_ver)

def supports_select_pane_in_direction(connection):
    min_ver = (1, 0)
    return ge(connection.iterm2_protocol_version, min_ver)

def supports_prompt_monitor_modes(connection):
    min_ver = (1, 1)
    return ge(connection.iterm2_protocol_version, min_ver)

def supports_status_bar_unread_count(connection):
    min_ver = (1, 2)
    return ge(connection.iterm2_protocol_version, min_ver)

def supports_coprocesses(connection):
    min_ver = (1, 3)
    return ge(connection.iterm2_protocol_version, min_ver)

def check_supports_coprocesses(connection):
    if not supports_coprocesses(connection):
        raise AppVersionTooOld("This version of iTerm2 is too old to control coprocesses from a Python script. You should upgrade to run this script.")

def supports_get_default_profile(connection):
    min_ver = (1, 4)
    return ge(connection.iterm2_protocol_version, min_ver)

def check_supports_get_default_profile(connection):
    if not supports_get_default_profile(connection):
        raise AppVersionTooOld("This version of iTerm2 is too old to get the default profile from a Python script. You should upgrade to run this script.")
