import AppKit
import Foundation
import __main__
import inspect
import os
import pathlib
import sys
import typing

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

def get_script_name():
    name = None
    if hasattr(__main__, "__file__"):
        fileName = __main__.__file__
        if os.path.basename(fileName) == "__main__.py":
            fileName = os.path.dirname(__main__.__file__)
        name = pathlib.Path(os.path.basename(fileName))
    elif len(sys.argv) > 0:
        name = os.path.basename(sys.argv[0])
    if not name:
        name = "Unknown"
    return name

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
        justName = get_script_name()
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

def applescript_auth_disabled():
    filename = os.path.expanduser("~/Library/Application Support/iTerm2/disable-automation-auth")
    try:
        magic = "61DF88DC-3423-4823-B725-22570E01C027"
        expected = filename.encode("utf-8").hex() + " " + magic
        stat = os.stat(filename, follow_symlinks=False)
        if stat.st_uid != 0:
            return False
        if stat.st_size != len(expected):
            return False
        with open(filename, "r") as f:
            return f.read() == expected
    except:
        return False

def authenticate(
        launch_if_needed: bool = False,
        myname: typing.Optional[str] = None) -> bool:
    """Attempts to authenticate before connecting to iTerm2 API.

    :param launch_if_needed: If iTerm2 is not running, try to launch it first.
    :param myname: Name of this script to show in the console.

    :returns: True if a cookie and key were fetched. False if an existing one
        was kept.

    Raises an :class:`~iterm2.AuthenticationException` exception if
    authentication fails.
    """
    if applescript_auth_disabled():
        return True
    if os.environ.get("ITERM2_COOKIE"):
        return False
    with LSBackgroundContextManager() as _:
        cookie_and_key = request_cookie_and_key(launch_if_needed, myname)
        cookie, key = cookie_and_key.split(" ")
        os.environ["ITERM2_COOKIE"] = cookie
        os.environ["ITERM2_KEY"] = key
        return True
