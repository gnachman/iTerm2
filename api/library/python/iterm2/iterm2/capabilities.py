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
