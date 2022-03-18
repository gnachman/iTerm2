try:
    import AppKit
    import Foundation
    gAppKitAvailable = True
except:
    gAppKitAvailable = False
import __main__
import inspect
import os
import pathlib
import re
import subprocess
import sys
import typing

class AuthenticationException(Exception):
    pass

class AppKitApplescriptRunner:
    def __init__(self, script):
        assert(gAppKitAvailable)
        self._script = script

    def execute(self):
        s = Foundation.NSAppleScript.alloc().initWithSource_(self._script)
        self._value = s.executeAndReturnError_(None)

    def get_string(self):
        return self._value[0].stringValue()

    def has_error(self):
        return self._value[0] is None

    def get_error(self):
        return self._value[1]["NSAppleScriptErrorNumber"]

    def get_error_reason(self):
        return self._value[1]["NSAppleScriptErrorBriefMessage"]

class CommandLineApplescriptRunner:
    def __init__(self, script):
        self._script = script.encode("utf-8")

    def execute(self):
        p = subprocess.Popen(['/usr/bin/osascript', '-'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = p.communicate(self._script)
        self._returncode = p.returncode
        self._output = stdout.decode("utf-8").rstrip()
        self._error = stderr.decode("utf-8").rstrip()

    def get_string(self):
        return self._output

    def has_error(self):
        return self._returncode != 0

    def get_error(self):
        result = re.search(r" \(((?:-?)[0-9]+)\)$", self._error)
        return result.group(1)

    def get_error_reason(self):
        result = re.search(r"^[0-9]+:[0-9]+: (.*) \((?:-)?[0-9]+\)$", self._error)
        return result.group(1)

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
        launch_if_needed: bool, myname: typing.Optional[str], runner_class):
    if not launch_if_needed:
        runner = runner_class(
            """
            set appName to "iTerm2"

            if application appName is running then
                return "yes"
            else
                return "no"
            end if
            """)
        runner.execute()
        is_running = runner.get_string()
        if is_running == "no":
            raise AuthenticationException("iTerm2 not running")
    justName = myname
    if justName is None:
        justName = get_script_name()
    runner = runner_class(
            'tell application "iTerm2" to request cookie and key ' +
            f'for app named "{justName}"')
    runner.execute()
    if runner.has_error():
        if runner.get_error() == -2740 or runner.get_error() == -2741:
            raise AuthenticationException("iTerm2 version too old")

        reason = runner.get_error_reason()
        raise AuthenticationException(reason)
    return runner.get_string()

class LSBackgroundContextManager():
    def __init__(self):
        assert(gAppKitAvailable)
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
    if gAppKitAvailable:
        with LSBackgroundContextManager() as _:
            cookie_and_key = request_cookie_and_key(launch_if_needed, myname, AppKitApplescriptRunner)
    else:
        cookie_and_key = request_cookie_and_key(launch_if_needed, myname, CommandLineApplescriptRunner)
    cookie, key = cookie_and_key.split(" ")
    os.environ["ITERM2_COOKIE"] = cookie
    os.environ["ITERM2_KEY"] = key
    return True
