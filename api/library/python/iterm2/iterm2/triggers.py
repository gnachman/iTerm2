"Abstractions for iTerm2 triggers."

import enum
import iterm2
import typing

def _hex(color):
    if not color:
        return ""
    return color.hex

def _futureproof(param, obj):
    """Sets the unparsed parameter in a trigger.

    Subclasses of Trigger will initialize __param with a computed param. This
    limits it to features that are parseable. If new values are added to a param
    in the future (e.g., color changes from {text,background} to
    {text,background,colorspace}) then those future features would be able to
    round trip through HighlightTrigger.deserialize().param. This function is a
    convenience to replace __param with the raw value so that as long as you
    don't modify a trigger it will produce the same param it was initialized
    with.
    """
    obj.param = param
    return obj

def decode_trigger(encoded: dict) -> 'Trigger':
    """Create a trigger.

    Use this to convert the dictionary representation of a trigger gotten from
    :class:`~iterm2.Profile` and friends into a :class:`~Trigger` object.

    :param encoded: The encoded trigger.

    :returns: A :class:`~Trigger`.
    """
    classes = {
        AlertTrigger._name(): AlertTrigger,
        AnnotateTrigger._name(): AnnotateTrigger,
        BellTrigger._name(): BellTrigger,
        BounceTrigger._name(): BounceTrigger,
        CaptureTrigger._name(): CaptureTrigger,
        CoprocessTrigger._name(): CoprocessTrigger,
        HighlightLineTrigger._name(): HighlightLineTrigger,
        HighlightTrigger._name(): HighlightTrigger,
        HyperlinkTrigger._name(): HyperlinkTrigger,
        InjectTrigger._name(): InjectTrigger,
        MarkTrigger._name(): MarkTrigger,
        MuteCoprocessTrigger._name(): MuteCoprocessTrigger,
        PasswordTrigger._name(): PasswordTrigger,
        RPCTrigger._name(): RPCTrigger,
        RunCommandTrigger._name(): RunCommandTrigger,
        SendTextTrigger._name(): SendTextTrigger,
        SetDirectoryTrigger._name(): SetDirectoryTrigger,
        SetHostnameTrigger._name(): SetHostnameTrigger,
        SetTitleTrigger._name(): SetTitleTrigger,
        SetUserVariableTrigger._name(): SetUserVariableTrigger,
        ShellPromptTrigger._name(): ShellPromptTrigger,
        StopTrigger._name(): StopTrigger,
        UserNotificationTrigger._name(): UserNotificationTrigger,
    }

    name = encoded["action"]
    regex = encoded["regex"]
    param = encoded.get("parameter", "")
    instant = encoded.get("partial", False)
    enabled = not encoded.get("disabled", False)

    if name not in classes:
        # Futureproof unrecognized trigger types. This allows a round-trip
        # through the Trigger representation.
        return Trigger(regex, param, instant, enabled)

    return classes[name].deserialize(regex, param, instant, enabled)

class Trigger:
    """Base class for triggers.

    Do not create this yourself. Instead, create a subclass directly.

    You may get an instance of this object for unrecognized trigger types that
    are defined in future versions of iTerm2.
    """
    def __init__(self, regex: str, param, instant: bool, enabled: bool):
        self.__regex = regex
        self.__param = param
        self.__instant = instant
        self.__enabled = enabled

    def __repr__(self):
        return f'<{self.__class__.__name__}: regex={self.__regex} instant={self.__instant} enabled={self.__enabled} param={self._param}>'

    def __eq__(self, other):
        return (
             self.__regex == other.__regex and
             self.__param == other.__param and
             self.__instant == other.__instant and
             self.__enabled == other.__enabled)

    @property
    def param(self):
        return self.__param

    @param.setter
    def param(self, value):
        self.__param = value

    @property
    def regex(self) -> str:
        return self.__regex

    @regex.setter
    def regex(self, value: str):
        self.__regex = value

    @property
    def instant(self) -> bool:
        return self.__instant

    @instant.setter
    def instant(self, value: bool):
        self.__instant = value

    @property
    def enabled(self) -> bool:
        return self.__enabled

    @enabled.setter
    def enabled(self, value: bool):
        self.__enabled = value

    @property
    def encode(self) -> dict:
        return { "regex":  self.regex,
                 "action":  self._name(),
                 "parameter": self.param,
                 "partial": self.instant,
                 "disabled": not self.enabled }

    def toJSON(self):
        return json.dumps(self.encode)

    @property
    def _param(self):
        return ""


class AlertTrigger(Trigger):
    def __init__(self, regex: str, message: str, instant: bool, enabled: bool):
        self.__message = message
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "AlertTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, AlertTrigger(regex, param, instant, enabled))

    @property
    def message(self) -> str:
        return self.__message

    @message.setter
    def message(self, value: str):
        self.__message = value
        self.param = self._param

    @property
    def _param(self):
        return self.__message

class AnnotateTrigger(Trigger):
    def __init__(self, regex: str, annotation: str, instant: bool, enabled: bool):
        self.__annotation = annotation
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "AnnotateTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, AnnotateTrigger(regex, param, instant, enabled))

    @property
    def annotation(self) -> str:
        return self.__annotation

    @annotation.setter
    def annotation(self, value: str):
        self.__annotation = value
        self.param = self._param

    @property
    def _param(self):
        return self.__annotation

class BellTrigger(Trigger):
    def __init__(self, regex: str, instant: bool, enabled: bool):
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "BellTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, BellTrigger(regex, instant, enabled))

    @property
    def _param(self) -> None:
        return ""

class BounceTrigger(Trigger):
    class Action(enum.Enum):
        BOUNCE_UNTIL_ACTIVATED = 0
        BOUNCE_ONCE = 1

    def __init__(self, regex: str, action: 'iterm2.Trigger.BounceTrigger.Action', instant: bool, enabled: bool):
        self.__action = action
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "BounceTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, BounceTrigger(regex, BounceTrigger.Action(param), instant, enabled))

    @property
    def action(self) -> 'iterm2.Trigger.BounceTrigger.Action':
        return self.__action

    @action.setter
    def action(self, value: 'iterm2.Trigger.BounceTrigger.Action'):
        self.__action = value
        self.param = self._param

    @property
    def _param(self):
        return self.__action.value

class RPCTrigger(Trigger):
    def __init__(self, regex: str, invocation: str, instant: bool, enabled: bool):
        self.__invocation = invocation
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermRPCTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, RPCTrigger(regex, param, instant, enabled))

    @property
    def invocation(self) -> str:
        return self.__invocation

    @invocation.setter
    def invocation(self, value: str):
        self.__invocation = value
        self.param = self._param

    @property
    def _param(self):
        return self.__invocation

class CaptureTrigger(Trigger):
    def __init__(self, regex: str, command: str, instant: bool, enabled: bool):
        self.__command = command
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "CaptureTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, CaptureTrigger(regex, param, instant, enabled))

    @property
    def command(self) -> str:
        return self.__command

    @command.setter
    def command(self, value: str):
        self.__command = value
        self.param = self._param

    @property
    def _param(self):
        return self.__command

class InjectTrigger(Trigger):
    def __init__(self, regex: str, injection: str, instant: bool, enabled: bool):
        self.__injection = injection
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermInjectTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, InjectTrigger(regex, param, instant, enabled))

    @property
    def injection(self) -> str:
        return self.__injection

    @injection.setter
    def injection(self, value: str):
        self.__injection = value
        self.param = self._param

    @property
    def _param(self):
        return self.__injection

class HighlightLineTrigger(Trigger):
    def __init__(self, regex: str, text_color: typing.Optional[iterm2.Color], background_color: typing.Optional[iterm2.Color], instant: bool, enabled: bool):
        self.__text_color = text_color
        self.__background_color = background_color
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermHighlightLineTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        parts = param[1:-1].split(",")
        text_color = iterm2.Color.from_trigger(parts[0])
        background_color = iterm2.Color.from_trigger(parts[1])
        return _futureproof(param, HighlightTrigger(regex, text_color, background_color, instant, enabled))

    @property
    def text_color(self) -> typing.Optional[iterm2.Color]:
        return self.__text_color

    @text_color.setter
    def text_color(self, value: typing.Optional[iterm2.Color]):
        self.__text_color = value
        self.param = self._param

    @property
    def background_color(self) -> typing.Optional[iterm2.Color]:
        return self.__background_color

    @background_color.setter
    def background_color(self, value: typing.Optional[iterm2.Color]):
        self.__background_color = value
        self.param = self._param

    @property
    def _param(self):
        return "{" + _hex(self.__text_color) + "," + _hex(self.__background_color) + "}"

class UserNotificationTrigger(Trigger):
    def __init__(self, regex: str, message: str, instant: bool, enabled: bool):
        self.__message = message
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermUserNotificationTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, UserNotificationTrigger(regex, param, instant, enabled))

    @property
    def message(self) -> str:
        return self.__message

    @message.setter
    def message(self, value: str):
        self.__message = value
        self.param = self._param

    @property
    def _param(self):
        return self.__message

class SetUserVariableTrigger(Trigger):
    def __init__(self, regex: str, name: str, json_value: str, instant: bool, enabled: bool):
        self.__name = name
        self.__json_value = json_value
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermSetUserVariableTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        parts = param.split(chr(1))
        return _futureproof(param, SetUserVariableTrigger(regex, parts[0], parts[1], instant, enabled))

    @property
    def name(self) -> str:
        return self.__name

    @name.setter
    def name(self, value: str):
        self.__name = value
        self.param = self._param

    @property
    def json_value(self) -> str:
        return self.__json_value

    @json_value.setter
    def json_value(self, value: str):
        self.__json_value = value
        self.param = self._param

    @property
    def _param(self):
        return self.__name + chr(1) + self.__json_value

class ShellPromptTrigger(Trigger):
    def __init__(self, regex: str, instant: bool, enabled: bool):
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermShellPromptTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, ShellPromptTrigger(regex, instant, enabled))

    @property
    def _param(self):
        return ""

class SetTitleTrigger(Trigger):
    def __init__(self, regex: str, title: str, instant: bool, enabled: bool):
        self.__title = title
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermSetTitleTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, SetTitleTrigger(regex, param, instant, enabled))

    @property
    def title(self) -> str:
        return self.__title

    @title.setter
    def title(self, value: str):
        self.__title = value
        self.param = self._param

    @property
    def _param(self):
        return self.__title

class SendTextTrigger(Trigger):
    def __init__(self, regex: str, text: str, instant: bool, enabled: bool):
        self.__text = text
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "SendTextTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, SendTextTrigger(regex, param, instant, enabled))

    @property
    def text(self) -> str:
        return self.__text

    @text.setter
    def text(self, value: str):
        self.__text = value
        self.param = self._param

    @property
    def _param(self):
        return self.__text

class RunCommandTrigger(Trigger):
    def __init__(self, regex: str, command: str, instant: bool, enabled: bool):
        self.__command = command
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "ScriptTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, RunCommandTrigger(regex, param, instant, enabled))

    @property
    def command(self) -> str:
        return self.__command

    @command.setter
    def command(self, value: str):
        self.__command = value
        self.param = self._param

    @property
    def _param(self):
        return self.__command

class CoprocessTrigger(Trigger):
    def __init__(self, regex: str, command: str, instant: bool, enabled: bool):
        self.__command = command
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "CoprocessTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, CoprocessTrigger(regex, param, instant, enabled))

    @property
    def command(self) -> str:
        return self.__command

    @command.setter
    def command(self, value: str):
        self.__command = value
        self.param = self._param

    @property
    def _param(self):
        return self.__command

class MuteCoprocessTrigger(Trigger):
    def __init__(self, regex: str, command: str, instant: bool, enabled: bool):
        self.__command = command
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "MuteCoprocessTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, MuteCoprocessTrigger(regex, param, instant, enabled))

    @property
    def command(self) -> str:
        return self.__command

    @command.setter
    def command(self, value: str):
        self.__command = value
        self.param = self._param

    @property
    def _param(self):
        return self.__command

class HighlightTrigger(Trigger):
    def __init__(self, regex: str, text_color: typing.Optional[iterm2.Color], background_color: typing.Optional[iterm2.Color], instant: bool, enabled: bool):
        self.__text_color = text_color
        self.__background_color = background_color
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "HighlightTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        parts = param[1:-1].split(",")
        text_color = iterm2.Color.from_trigger(parts[0])
        background_color = iterm2.Color.from_trigger(parts[1])
        return _futureproof(param, HighlightTrigger(regex, text_color, background_color, instant, enabled))

    @property
    def text_color(self) -> typing.Optional[iterm2.Color]:
        return self.__text_color

    @text_color.setter
    def text_color(self, value: typing.Optional[iterm2.Color]):
        self.__text_color = value
        self.param = self._param

    @property
    def background_color(self, value: typing.Optional[iterm2.Color]):
        return self.__background_color

    @background_color.setter
    def background_color(self, value: typing.Optional[iterm2.Color]):
        self.__background_color = value
        self.param = self._param

    @property
    def _param(self):
        return "{" + _hex(self.__text_color) + "," + _hex(self.__background_color) + "}"

class MarkTrigger(Trigger):
    def __init__(self, regex: str, stop_scrolling: bool, instant: bool, enabled: bool):
        self.__stop_scrolling = stop_scrolling
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "MarkTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, MarkTrigger(regex, param == 1, instant, enabled))

    @property
    def stop_scrolling(self) -> bool:
        return self.__stop_scrolling

    @stop_scrolling.setter
    def stop_scrolling(self, value: bool):
        self.__stop_scrolling = value
        self.param = self._param

    @property
    def _param(self):
        return 1 if self.__stop_scrolling else 0

class PasswordTrigger(Trigger):
    SEPARATOR = "\u2002\u2014\u2002"

    def __init__(self, regex: str, account_name: str, user_name: typing.Optional[str], instant: bool, enabled: bool):
        self.__account_name = account_name
        self.__user_name = user_name
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "PasswordTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        if PasswordTrigger.SEPARATOR in param:
            parts = param.split(PasswordTrigger.SEPARATOR)
            account_name = parts[0]
            user_name = parts[1]
        else:
            account_name = param
            user_name = ""
        return _futureproof(param, PasswordTrigger(regex, account_name, user_name, instant, enabled))

    @property
    def account_name(self) -> str:
        return self.__account_name

    @account_name.setter
    def account_name(self, value: str):
        self.__account_name = value
        self.param = self._param

    @property
    def user_name(self) -> str:
        return self.__user_name

    @user_name.setter
    def user_name(self, value: str):
        self.__user_name = value
        self.param = self._param

    @property
    def _param(self):
        if len(self.__user_name) > 0:
            return self.__account_name + PasswordTrigger.SEPARATOR + self.__user_name
        return self.__account_name

class HyperlinkTrigger(Trigger):
    def __init__(self, regex: str, url: str, instant: bool, enabled: bool):
        self.__url = url
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermHyperlinkTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, HyperlinkTrigger(regex, param, instant, enabled))

    @property
    def url(self) -> str:
        return self.__url

    @url.setter
    def url(self, value: str):
        self.__url = value
        self.param = self._param

    @property
    def _param(self):
        return self.__url

class SetDirectoryTrigger(Trigger):
    def __init__(self, regex: str, directory: str, instant: bool, enabled: bool):
        self.__directory = directory
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "SetDirectoryTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, SetDirectoryTrigger(regex, param, instant, enabled))

    @property
    def directory(self) -> str:
        return self.__directory

    @directory.setter
    def directory(self, value: str):
        self.__directory = value
        self.param = self._param

    @property
    def _param(self):
        return self.__directory

class SetHostnameTrigger(Trigger):
    def __init__(self, regex: str, hostname: str, instant: bool, enabled: bool):
        self.__hostname = hostname
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "SetHostnameTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, SetHostnameTrigger(regex, param, instant, enabled))

    @property
    def hostname(self) -> str:
        return self.__hostname

    @hostname.setter
    def hostname(self, value: str):
        self.__hostname = value
        self.param = self._param

    @property
    def _param(self):
        return self.__hostname

class StopTrigger(Trigger):
    def __init__(self, regex: str, instant: bool, enabled: bool):
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "StopTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool):
        return _futureproof(param, StopTrigger(regex, instant, enabled))

    @property
    def _param(self):
        return ""

