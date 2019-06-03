def ge(a, b):
    """Is a >= b?"""
    if a[0] > b[0]:
        return True
    if a[0] < b[0]:
        return False
    return a[1] >= b[1]

def supports_multiple_set_profile_properties(connection):
    min_ver = (0, 69)
    print(f'Capabilities check between {min_ver} and {connection.iterm2_protocol_version} is {ge(min_ver, connection.iterm2_protocol_version)}')
    return ge(connection.iterm2_protocol_version, min_ver)

