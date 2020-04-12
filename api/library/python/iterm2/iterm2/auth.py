import AppKit
import Foundation
import __main__
import keyring
import os
import typing

MODE_APPLESCRIPT = "Applescript"
MODE_KEYRING = "Keyring"

class AuthenticationException(Exception):
    pass

def run_applescript(script):
    s = Foundation.NSAppleScript.alloc().initWithSource_(script)
    return s.executeAndReturnError_(None)

def get_string(result):
    return result[0].stringValue()

def get_error(result):
    return result[1]["NSAppleScriptErrorNumber"]

def has_error(result):
    return result[0] is None

def get_error_reason(result):
    return result[1]["NSAppleScriptErrorBriefMessage"]

def request_cookie_and_key(
        launch_if_needed: bool, myname: typing.Optional[str]):
    script = """
    set appName to "iTerm2"

    if application appName is running then
        return "yes"
    else
        return "no"
    end if
    """
    if not launch_if_needed:
        is_running = get_string(run_applescript(script))
        if is_running == "no":
            raise AuthenticationException("iTerm2 not running")
    justName = myname
    if justName is None:
        justName = os.path.basename(__main__.__file__)
    s = Foundation.NSAppleScript.alloc().initWithSource_(
            'tell application "iTerm2" to request cookie and key ' +
            f'for app named "{justName}"')
    result = s.executeAndReturnError_(None)
    if has_error(result):
        if get_error(result) == -2740:
            raise AuthenticationException("iTerm2 version too old")

        reason = get_error_reason(result)
        raise AuthenticationException(reason)
    return get_string(result)

class LSBackgroundContextManager():
    def __init__(self):
        self.__value = AppKit.NSBundle.mainBundle().infoDictionary().get(
                "LSBackgroundOnly")

    def __enter__(self):
        info = AppKit.NSBundle.mainBundle().infoDictionary()
        info["LSBackgroundOnly"] = "1"

    def __exit__(self, exc_type, exc_value, exc_traceback):
        info = AppKit.NSBundle.mainBundle().infoDictionary()
        if self.__value:
            info["LSBackgroundOnly"] = __value
        else:
            del info["LSBackgroundOnly"]

def authenticate(
        launch_if_needed: bool = False,
        myname: typing.Optional[str] = None,
        mode: str = MODE_APPLESCRIPT) -> bool:
    """Attempts to authenticate before connecting to iTerm2 API.

    :param launch_if_needed: If iTerm2 is not running, try to launch it first.
    :param myname: Name of this script to show in the console.

    :returns: True if a cookie and key were fetched. False if an existing one
        was kept.

    Raises an :class:`~iterm2.AuthenticationException` exception if
    authentication fails.
    """
    if mode == MODE_APPLESCRIPT:
        authenticate_applescript(launch_if_needed, myname)
    elif mode == MODE_KEYRING:
        authenticate_keyring(launch_if_needed)
    raise AuthenticationException(f'Invalid auth mode {str}')

def authenticate_keyring(
        launch_if_needed: bool = False,
        myname: typing.Optional[str] = None):
    if os.environ.get("ITERM2_COOKIE"):
        return False
    secret = keyring.get_password("iTerm2 API Token", "n/a")
    os.environ["ITERM2_COOKIE"] = cookie
    del os.environ["ITERM2_KEY"]
    return True

def authenticate_applescript(
        launch_if_needed: bool = False,
        myname: typing.Optional[str] = None):
    if os.environ.get("ITERM2_COOKIE"):
        return False

    with LSBackgroundContextManager() as _:
        cookie_and_key = request_cookie_and_key(launch_if_needed, myname)
        cookie, key = cookie_and_key.split(" ")
        os.environ["ITERM2_COOKIE"] = cookie
        os.environ["ITERM2_KEY"] = key
        return True
