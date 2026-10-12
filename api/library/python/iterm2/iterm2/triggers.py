"Abstractions for iTerm2 triggers."

from __future__ import annotations

import enum
import json
from collections.abc import Mapping
from typing import TYPE_CHECKING, Any, TypeVar

from .color import Color

if TYPE_CHECKING:
    _T = TypeVar("_T", bound="Trigger")


class MatchType(enum.Enum):
    """Match type for triggers.

    Regex-based triggers (0-99) fire when output matches a pattern.
    Event-based triggers (100+) fire when specific events occur.
    """

    # Regex-based (0-99)
    REGEX = 0
    URL_REGEX = 1
    PAGE_CONTENT_REGEX = 2

    # Event-based (100+)
    EVENT_PROMPT_DETECTED = 100
    EVENT_COMMAND_FINISHED = 101
    EVENT_DIRECTORY_CHANGED = 102
    EVENT_HOST_CHANGED = 103
    EVENT_USER_CHANGED = 104
    EVENT_IDLE = 105
    EVENT_ACTIVITY_AFTER_IDLE = 106
    EVENT_SESSION_ENDED = 107
    EVENT_BELL_RECEIVED = 108
    EVENT_LONG_RUNNING_COMMAND = 109
    EVENT_CUSTOM_ESCAPE_SEQUENCE = 110
    EVENT_NOTIFICATION_POSTED = 111
    EVENT_PROGRESS_BAR_CHANGED = 112

    @staticmethod
    def is_event(match_type: MatchType) -> bool:
        """Returns True if this is an event-based match type."""
        return match_type.value >= 100


def _hex(color: Color | None):
    if not color:
        return ""
    return color.hex


def _futureproof(param: Any, obj: _T) -> _T:
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


def decode_trigger(encoded: dict[str, Any]) -> Trigger | EventTrigger:
    """Create a trigger.

    Use this to convert the dictionary representation of a trigger gotten from
    :class:`~iterm2.Profile` and friends into a :class:`~Trigger` object.

    NOTE: This may raise an assertion on iTerm2 prior to 3.5.0beta6 if pyobjc
    is not installed.

    :param encoded: The encoded trigger.

    :returns: A :class:`~Trigger`.
    """

    classes: dict[str, type[Trigger]] = {
        AlertTrigger._name(): AlertTrigger,  # pyright: ignore[reportPrivateUsage]
        AnnotateTrigger._name(): AnnotateTrigger,  # pyright: ignore[reportPrivateUsage]
        BellTrigger._name(): BellTrigger,  # pyright: ignore[reportPrivateUsage]
        BounceTrigger._name(): BounceTrigger,  # pyright: ignore[reportPrivateUsage]
        CaptureTrigger._name(): CaptureTrigger,  # pyright: ignore[reportPrivateUsage]
        CoprocessTrigger._name(): CoprocessTrigger,  # pyright: ignore[reportPrivateUsage]
        HighlightLineTrigger._name(): HighlightLineTrigger,  # pyright: ignore[reportPrivateUsage]
        HighlightTrigger._name(): HighlightTrigger,  # pyright: ignore[reportPrivateUsage]
        HyperlinkTrigger._name(): HyperlinkTrigger,  # pyright: ignore[reportPrivateUsage]
        InjectTrigger._name(): InjectTrigger,  # pyright: ignore[reportPrivateUsage]
        MarkTrigger._name(): MarkTrigger,  # pyright: ignore[reportPrivateUsage]
        MuteCoprocessTrigger._name(): MuteCoprocessTrigger,  # pyright: ignore[reportPrivateUsage]
        PasswordTrigger._name(): PasswordTrigger,  # pyright: ignore[reportPrivateUsage]
        RPCTrigger._name(): RPCTrigger,  # pyright: ignore[reportPrivateUsage]
        RunCommandTrigger._name(): RunCommandTrigger,  # pyright: ignore[reportPrivateUsage]
        SendTextTrigger._name(): SendTextTrigger,  # pyright: ignore[reportPrivateUsage]
        SetDirectoryTrigger._name(): SetDirectoryTrigger,  # pyright: ignore[reportPrivateUsage]
        SetHostnameTrigger._name(): SetHostnameTrigger,  # pyright: ignore[reportPrivateUsage]
        SetTitleTrigger._name(): SetTitleTrigger,  # pyright: ignore[reportPrivateUsage]
        SetUserVariableTrigger._name(): SetUserVariableTrigger,  # pyright: ignore[reportPrivateUsage]
        ShellPromptTrigger._name(): ShellPromptTrigger,  # pyright: ignore[reportPrivateUsage]
        StopTrigger._name(): StopTrigger,  # pyright: ignore[reportPrivateUsage]
        UserNotificationTrigger._name(): UserNotificationTrigger,  # pyright: ignore[reportPrivateUsage]
        SetNamedMarkTrigger._name(): SetNamedMarkTrigger,  # pyright: ignore[reportPrivateUsage]
        FoldTrigger._name(): FoldTrigger,  # pyright: ignore[reportPrivateUsage]
        SGRTrigger._name(): SGRTrigger,  # pyright: ignore[reportPrivateUsage]
        BufferInputTrigger._name(): BufferInputTrigger,  # pyright: ignore[reportPrivateUsage]
    }

    name = encoded["action"]
    regex = encoded.get("regex", "")
    param = encoded.get("parameter", "")
    instant = encoded.get("partial", False)
    enabled = not encoded.get("disabled", False)
    match_type_value = encoded.get("matchType", 0)
    event_params = encoded.get("eventParams", None)

    # Check if this is an event-based trigger (matchType >= 100)
    if match_type_value >= 100:
        try:
            match_type = MatchType(match_type_value)
        except ValueError:
            # Unknown event type - return generic EventTrigger
            match_type = None
        return _decode_event_trigger(
            name, match_type, match_type_value, param, enabled, event_params, classes
        )

    if name not in classes:
        # Futureproof unrecognized trigger types. This allows a round-trip
        # through the Trigger representation.
        return Trigger(regex, param, instant, enabled)

    return classes[name].deserialize(regex, param, instant, enabled)


def _decode_event_trigger(
    action_name: str,
    match_type: MatchType | None,
    match_type_value: int,
    param: Any,
    enabled: bool,
    event_params: dict[str, Any] | None,
    action_classes: dict[str, type[Trigger]],
) -> EventTrigger:
    """Decode an event-based trigger."""
    # Map match types to their specific event trigger classes
    event_classes: dict[MatchType, type[EventTrigger]] = {
        MatchType.EVENT_PROMPT_DETECTED: PromptDetectedEventTrigger,
        MatchType.EVENT_COMMAND_FINISHED: CommandFinishedEventTrigger,
        MatchType.EVENT_DIRECTORY_CHANGED: DirectoryChangedEventTrigger,
        MatchType.EVENT_HOST_CHANGED: HostChangedEventTrigger,
        MatchType.EVENT_USER_CHANGED: UserChangedEventTrigger,
        MatchType.EVENT_IDLE: IdleEventTrigger,
        MatchType.EVENT_ACTIVITY_AFTER_IDLE: ActivityAfterIdleEventTrigger,
        MatchType.EVENT_SESSION_ENDED: SessionEndedEventTrigger,
        MatchType.EVENT_BELL_RECEIVED: BellReceivedEventTrigger,
        MatchType.EVENT_LONG_RUNNING_COMMAND: LongRunningCommandEventTrigger,
        MatchType.EVENT_CUSTOM_ESCAPE_SEQUENCE: CustomEscapeSequenceEventTrigger,
        MatchType.EVENT_NOTIFICATION_POSTED: NotificationPostedEventTrigger,
        MatchType.EVENT_PROGRESS_BAR_CHANGED: ProgressBarChangedEventTrigger,
    }

    if match_type is not None and match_type in event_classes:
        event_class = event_classes[match_type]
        return event_class.deserialize(
            action_name, param, enabled, event_params, action_classes
        )

    # Unknown event type - return generic EventTrigger
    return EventTrigger(
        match_type=match_type if match_type else MatchType.EVENT_PROMPT_DETECTED,
        action_name=action_name,
        param=param,
        enabled=enabled,
        event_params=event_params,
        _raw_match_type=match_type_value if match_type is None else None,
    )


class Trigger:
    """Base class for triggers.

    Do not create this yourself. Instead, create a subclass directly.

    You may get an instance of this object for unrecognized trigger types that
    are defined in future versions of iTerm2.
    """

    def __init__(
        self,
        regex: str,
        param: Any,
        instant: bool,
        enabled: bool,
        match_type: MatchType = MatchType.REGEX,
    ) -> None:
        self.__regex = regex
        self.__param = param
        self.__instant = instant
        self.__enabled = enabled
        self.__match_type = match_type

    def __repr__(self):
        return f"<{self.__class__.__name__}: regex={self.__regex} instant={self.__instant} enabled={self.__enabled} param={self._param}>"

    def __eq__(self, other: Trigger) -> bool:  # type: ignore[override]
        return (
            self.__regex == other.__regex
            and self.__param == other.__param
            and self.__instant == other.__instant
            and self.__enabled == other.__enabled
            and self.__match_type == other.__match_type
        )

    @property
    def param(self) -> Any:
        return self.__param

    @param.setter
    def param(self, value: Any) -> None:
        self.__param = value

    @property
    def regex(self) -> str:
        return self.__regex

    @regex.setter
    def regex(self, value: str) -> None:
        self.__regex = value

    @property
    def instant(self) -> bool:
        return self.__instant

    @instant.setter
    def instant(self, value: bool) -> None:
        self.__instant = value

    @property
    def enabled(self) -> bool:
        return self.__enabled

    @enabled.setter
    def enabled(self, value: bool) -> None:
        self.__enabled = value

    @property
    def match_type(self) -> MatchType:
        """The match type for this trigger."""
        return self.__match_type

    @staticmethod
    def _name() -> str:
        return "Trigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool) -> Trigger:
        return Trigger(regex, param, instant, enabled)

    @property
    def encode(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "regex": self.regex,
            "action": self._name(),
            "parameter": self.param,
            "partial": self.instant,
            "disabled": not self.enabled,
            "matchType": self.__match_type.value,
        }
        return result

    def toJSON(self) -> str:
        return json.dumps(self.encode)

    @property
    def _param(self) -> str | int:
        return ""


class AlertTrigger(Trigger):
    def __init__(self, regex: str, message: str, instant: bool, enabled: bool) -> None:
        self.__message = message
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "AlertTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> AlertTrigger:
        return _futureproof(param, AlertTrigger(regex, param, instant, enabled))

    @property
    def message(self) -> str:
        return self.__message

    @message.setter
    def message(self, value: str) -> None:
        self.__message = value
        self.param = self._param

    @property
    def _param(self):
        return self.__message


class AnnotateTrigger(Trigger):
    def __init__(
        self, regex: str, annotation: str, instant: bool, enabled: bool
    ) -> None:
        self.__annotation = annotation
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "AnnotateTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> AnnotateTrigger:
        return _futureproof(param, AnnotateTrigger(regex, param, instant, enabled))

    @property
    def annotation(self) -> str:
        return self.__annotation

    @annotation.setter
    def annotation(self, value: str) -> None:
        self.__annotation = value
        self.param = self._param

    @property
    def _param(self):
        return self.__annotation


class BellTrigger(Trigger):
    def __init__(self, regex: str, instant: bool, enabled: bool) -> None:
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "BellTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> BellTrigger:
        return _futureproof(param, BellTrigger(regex, instant, enabled))

    @property
    def _param(self) -> str:
        return ""


class BounceTrigger(Trigger):
    class Action(enum.Enum):
        BOUNCE_UNTIL_ACTIVATED = 0
        BOUNCE_ONCE = 1

    def __init__(
        self, regex: str, action: BounceTrigger.Action, instant: bool, enabled: bool
    ) -> None:
        self.__action = action
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "BounceTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: Any, instant: bool, enabled: bool
    ) -> BounceTrigger:
        return _futureproof(
            param, BounceTrigger(regex, BounceTrigger.Action(param), instant, enabled)
        )

    @property
    def action(self) -> BounceTrigger.Action:
        return self.__action

    @action.setter
    def action(self, value: BounceTrigger.Action) -> None:
        self.__action = value
        self.param = self._param

    @property
    def _param(self):
        return self.__action.value


class BufferInputTrigger(Trigger):
    class Action(enum.Enum):
        START = 0
        STOP = 1

    def __init__(
        self,
        regex: str,
        action: BufferInputTrigger.Action,
        instant: bool,
        enabled: bool,
    ) -> None:
        self.__action = action
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermBufferInputTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: Any, instant: bool, enabled: bool
    ) -> BufferInputTrigger:
        return _futureproof(
            param,
            BufferInputTrigger(
                regex, BufferInputTrigger.Action(param), instant, enabled
            ),
        )

    @property
    def action(self) -> BufferInputTrigger.Action:
        return self.__action

    @action.setter
    def action(self, value: BufferInputTrigger.Action) -> None:
        self.__action = value
        self.param = self._param

    @property
    def _param(self):
        return self.__action.value


class RPCTrigger(Trigger):
    def __init__(
        self, regex: str, invocation: str, instant: bool, enabled: bool
    ) -> None:
        self.__invocation = invocation
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermRPCTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool) -> RPCTrigger:
        return _futureproof(param, RPCTrigger(regex, param, instant, enabled))

    @property
    def invocation(self) -> str:
        return self.__invocation

    @invocation.setter
    def invocation(self, value: str) -> None:
        self.__invocation = value
        self.param = self._param

    @property
    def _param(self):
        return self.__invocation


class CaptureTrigger(Trigger):
    def __init__(self, regex: str, command: str, instant: bool, enabled: bool) -> None:
        self.__command = command
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "CaptureTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> CaptureTrigger:
        return _futureproof(param, CaptureTrigger(regex, param, instant, enabled))

    @property
    def command(self) -> str:
        return self.__command

    @command.setter
    def command(self, value: str) -> None:
        self.__command = value
        self.param = self._param

    @property
    def _param(self):
        return self.__command


class SetNamedMarkTrigger(Trigger):
    def __init__(self, regex: str, markname: str, instant: bool, enabled: bool) -> None:
        self.__markname = markname
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermSetNamedMarkTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> SetNamedMarkTrigger:
        return _futureproof(param, SetNamedMarkTrigger(regex, param, instant, enabled))

    @property
    def markname(self) -> str:
        return self.__markname

    @markname.setter
    def markname(self, value: str) -> None:
        self.__markname = value
        self.param = self._param

    @property
    def _param(self):
        return self.__markname


class SGRTrigger(Trigger):
    def __init__(self, regex: str, sgr: str, instant: bool, enabled: bool) -> None:
        self.__sgr = sgr
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermSGRTrigger"

    @staticmethod
    def deserialize(regex: str, param: str, instant: bool, enabled: bool) -> SGRTrigger:
        return _futureproof(param, SGRTrigger(regex, param, instant, enabled))

    @property
    def sgr(self) -> str:
        return self.__sgr

    @sgr.setter
    def sgr(self, value: str) -> None:
        self.__sgr = value
        self.param = self._param

    @property
    def _param(self):
        return self.__sgr


class FoldTrigger(Trigger):
    def __init__(self, regex: str, markname: str, instant: bool, enabled: bool) -> None:
        self.__markname = markname
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermFoldTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> FoldTrigger:
        return _futureproof(param, FoldTrigger(regex, param, instant, enabled))

    @property
    def markname(self) -> str:
        return self.__markname

    @markname.setter
    def markname(self, value: str) -> None:
        self.__markname = value
        self.param = self._param

    @property
    def _param(self):
        return self.__markname


class InjectTrigger(Trigger):
    def __init__(
        self, regex: str, injection: str, instant: bool, enabled: bool
    ) -> None:
        self.__injection = injection
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermInjectTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> InjectTrigger:
        return _futureproof(param, InjectTrigger(regex, param, instant, enabled))

    @property
    def injection(self) -> str:
        return self.__injection

    @injection.setter
    def injection(self, value: str) -> None:
        self.__injection = value
        self.param = self._param

    @property
    def _param(self):
        return self.__injection


class HighlightLineTrigger(Trigger):
    def __init__(
        self,
        regex: str,
        text_color: Color | None,
        background_color: Color | None,
        instant: bool,
        enabled: bool,
    ) -> None:
        self.__text_color = text_color
        self.__background_color = background_color
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermHighlightLineTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> HighlightTrigger:
        parts = param[1:-1].split(",")
        text_color = Color.from_trigger(parts[0])
        background_color = Color.from_trigger(parts[1])
        return _futureproof(
            param,
            HighlightTrigger(regex, text_color, background_color, instant, enabled),
        )

    @property
    def text_color(self) -> Color | None:
        return self.__text_color

    @text_color.setter
    def text_color(self, value: Color | None) -> None:
        self.__text_color = value
        self.param = self._param

    @property
    def background_color(self) -> Color | None:
        return self.__background_color

    @background_color.setter
    def background_color(self, value: Color | None) -> None:
        self.__background_color = value
        self.param = self._param

    @property
    def _param(self):
        return "{" + _hex(self.__text_color) + "," + _hex(self.__background_color) + "}"


class UserNotificationTrigger(Trigger):
    def __init__(self, regex: str, message: str, instant: bool, enabled: bool) -> None:
        self.__message = message
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermUserNotificationTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> UserNotificationTrigger:
        return _futureproof(
            param, UserNotificationTrigger(regex, param, instant, enabled)
        )

    @property
    def message(self) -> str:
        return self.__message

    @message.setter
    def message(self, value: str) -> None:
        self.__message = value
        self.param = self._param

    @property
    def _param(self):
        return self.__message


class SetUserVariableTrigger(Trigger):
    def __init__(
        self, regex: str, name: str, json_value: str, instant: bool, enabled: bool
    ) -> None:
        self.__name = name
        self.__json_value = json_value
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermSetUserVariableTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> SetUserVariableTrigger:
        parts = param.split(chr(1))
        return _futureproof(
            param, SetUserVariableTrigger(regex, parts[0], parts[1], instant, enabled)
        )

    @property
    def name(self) -> str:
        return self.__name

    @name.setter
    def name(self, value: str) -> None:
        self.__name = value
        self.param = self._param

    @property
    def json_value(self) -> str:
        return self.__json_value

    @json_value.setter
    def json_value(self, value: str) -> None:
        self.__json_value = value
        self.param = self._param

    @property
    def _param(self):
        return self.__name + chr(1) + self.__json_value


class ShellPromptTrigger(Trigger):
    def __init__(self, regex: str, instant: bool, enabled: bool) -> None:
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermShellPromptTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> ShellPromptTrigger:
        return _futureproof(param, ShellPromptTrigger(regex, instant, enabled))

    @property
    def _param(self):
        return ""


class SetTitleTrigger(Trigger):
    def __init__(self, regex: str, title: str, instant: bool, enabled: bool) -> None:
        self.__title = title
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermSetTitleTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> SetTitleTrigger:
        return _futureproof(param, SetTitleTrigger(regex, param, instant, enabled))

    @property
    def title(self) -> str:
        return self.__title

    @title.setter
    def title(self, value: str) -> None:
        self.__title = value
        self.param = self._param

    @property
    def _param(self):
        return self.__title


class SendTextTrigger(Trigger):
    def __init__(self, regex: str, text: str, instant: bool, enabled: bool) -> None:
        self.__text = text
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "SendTextTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> SendTextTrigger:
        return _futureproof(param, SendTextTrigger(regex, param, instant, enabled))

    @property
    def text(self) -> str:
        return self.__text

    @text.setter
    def text(self, value: str) -> None:
        self.__text = value
        self.param = self._param

    @property
    def _param(self):
        return self.__text


class RunCommandTrigger(Trigger):
    def __init__(self, regex: str, command: str, instant: bool, enabled: bool) -> None:
        self.__command = command
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "ScriptTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> RunCommandTrigger:
        return _futureproof(param, RunCommandTrigger(regex, param, instant, enabled))

    @property
    def command(self) -> str:
        return self.__command

    @command.setter
    def command(self, value: str) -> None:
        self.__command = value
        self.param = self._param

    @property
    def _param(self):
        return self.__command


class CoprocessTrigger(Trigger):
    def __init__(self, regex: str, command: str, instant: bool, enabled: bool) -> None:
        self.__command = command
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "CoprocessTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> CoprocessTrigger:
        return _futureproof(param, CoprocessTrigger(regex, param, instant, enabled))

    @property
    def command(self) -> str:
        return self.__command

    @command.setter
    def command(self, value: str) -> None:
        self.__command = value
        self.param = self._param

    @property
    def _param(self):
        return self.__command


class MuteCoprocessTrigger(Trigger):
    def __init__(self, regex: str, command: str, instant: bool, enabled: bool) -> None:
        self.__command = command
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "MuteCoprocessTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> MuteCoprocessTrigger:
        return _futureproof(param, MuteCoprocessTrigger(regex, param, instant, enabled))

    @property
    def command(self) -> str:
        return self.__command

    @command.setter
    def command(self, value: str) -> None:
        self.__command = value
        self.param = self._param

    @property
    def _param(self):
        return self.__command


class HighlightTrigger(Trigger):
    def __init__(
        self,
        regex: str,
        text_color: Color | None,
        background_color: Color | None,
        instant: bool,
        enabled: bool,
    ) -> None:
        self.__text_color = text_color
        self.__background_color = background_color
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "HighlightTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> HighlightTrigger:
        parts = param[1:-1].split(",")
        text_color = Color.from_trigger(parts[0])
        background_color = Color.from_trigger(parts[1])
        return _futureproof(
            param,
            HighlightTrigger(regex, text_color, background_color, instant, enabled),
        )

    @property
    def text_color(self) -> Color | None:
        return self.__text_color

    @text_color.setter
    def text_color(self, value: Color | None) -> None:
        self.__text_color = value
        self.param = self._param

    @property
    def background_color(self) -> Color | None:
        return self.__background_color

    @background_color.setter
    def background_color(self, value: Color | None) -> None:
        self.__background_color = value
        self.param = self._param

    @property
    def _param(self):
        return "{" + _hex(self.__text_color) + "," + _hex(self.__background_color) + "}"


class MarkTrigger(Trigger):
    def __init__(
        self, regex: str, stop_scrolling: bool, instant: bool, enabled: bool
    ) -> None:
        self.__stop_scrolling = stop_scrolling
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "MarkTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: Any, instant: bool, enabled: bool
    ) -> MarkTrigger:
        return _futureproof(param, MarkTrigger(regex, param == 1, instant, enabled))

    @property
    def stop_scrolling(self) -> bool:
        return self.__stop_scrolling

    @stop_scrolling.setter
    def stop_scrolling(self, value: bool) -> None:
        self.__stop_scrolling = value
        self.param = self._param

    @property
    def _param(self):
        return 1 if self.__stop_scrolling else 0


class PasswordTrigger(Trigger):
    SEPARATOR: str = "\u2002\u2014\u2002"

    def __init__(
        self,
        regex: str,
        account_name: str,
        user_name: str | None,
        instant: bool,
        enabled: bool,
    ) -> None:
        self.__account_name = account_name
        self.__user_name = user_name
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "PasswordTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> PasswordTrigger:
        if PasswordTrigger.SEPARATOR in param:
            parts = param.split(PasswordTrigger.SEPARATOR)
            account_name = parts[0]
            user_name = parts[1]
        else:
            account_name = param
            user_name = ""
        return _futureproof(
            param, PasswordTrigger(regex, account_name, user_name, instant, enabled)
        )

    @property
    def account_name(self) -> str:
        return self.__account_name

    @account_name.setter
    def account_name(self, value: str) -> None:
        self.__account_name = value
        self.param = self._param

    @property
    def user_name(self) -> str | None:
        return self.__user_name

    @user_name.setter
    def user_name(self, value: str) -> None:
        self.__user_name = value
        self.param = self._param

    @property
    def _param(self) -> str:
        if len(self.__user_name) > 0:  # type: ignore[arg-type]
            return self.__account_name + PasswordTrigger.SEPARATOR + self.__user_name  # type: ignore[operator]
        return self.__account_name


class HyperlinkTrigger(Trigger):
    def __init__(self, regex: str, url: str, instant: bool, enabled: bool) -> None:
        self.__url = url
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "iTermHyperlinkTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> HyperlinkTrigger:
        return _futureproof(param, HyperlinkTrigger(regex, param, instant, enabled))

    @property
    def url(self) -> str:
        return self.__url

    @url.setter
    def url(self, value: str) -> None:
        self.__url = value
        self.param = self._param

    @property
    def _param(self):
        return self.__url


class SetDirectoryTrigger(Trigger):
    def __init__(
        self, regex: str, directory: str, instant: bool, enabled: bool
    ) -> None:
        self.__directory = directory
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "SetDirectoryTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> SetDirectoryTrigger:
        return _futureproof(param, SetDirectoryTrigger(regex, param, instant, enabled))

    @property
    def directory(self) -> str:
        return self.__directory

    @directory.setter
    def directory(self, value: str) -> None:
        self.__directory = value
        self.param = self._param

    @property
    def _param(self):
        return self.__directory


class SetHostnameTrigger(Trigger):
    def __init__(self, regex: str, hostname: str, instant: bool, enabled: bool) -> None:
        self.__hostname = hostname
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "SetHostnameTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> SetHostnameTrigger:
        return _futureproof(param, SetHostnameTrigger(regex, param, instant, enabled))

    @property
    def hostname(self) -> str:
        return self.__hostname

    @hostname.setter
    def hostname(self, value: str) -> None:
        self.__hostname = value
        self.param = self._param

    @property
    def _param(self):
        return self.__hostname


class StopTrigger(Trigger):
    def __init__(self, regex: str, instant: bool, enabled: bool) -> None:
        super().__init__(regex, self._param, instant, enabled)

    @staticmethod
    def _name():
        return "StopTrigger"

    @staticmethod
    def deserialize(
        regex: str, param: str, instant: bool, enabled: bool
    ) -> StopTrigger:
        return _futureproof(param, StopTrigger(regex, instant, enabled))

    @property
    def _param(self):
        return ""


# Event-based triggers (match type >= 100)


class EventTrigger:
    """Base class for event-based triggers.

    Event triggers fire when specific events occur (like command finished,
    directory changed, etc.) rather than when text matches a regex pattern.

    Do not create this directly. Instead, use one of the specific event trigger
    subclasses like :class:`~CommandFinishedEventTrigger`.
    """

    def __init__(
        self,
        match_type: MatchType,
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None = None,
        _raw_match_type: int | None = None,
    ) -> None:
        self.__match_type = match_type
        self.__action_name = action_name
        self.__param = param
        self.__enabled = enabled
        self.__event_params = event_params or {}
        # For future-proofing unknown match types
        self.__raw_match_type = _raw_match_type

    def __repr__(self):
        return (
            f"<{self.__class__.__name__}: match_type={self.__match_type} "
            f"action={self.__action_name} enabled={self.__enabled} "
            f"event_params={self.__event_params}>"
        )

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, EventTrigger):
            return False
        return (
            self.__match_type == other.__match_type
            and self.__action_name == other.__action_name
            and self.__param == other.__param
            and self.__enabled == other.__enabled
            and self.__event_params == other.__event_params
        )

    @property
    def match_type(self) -> MatchType:
        """The event type this trigger responds to."""
        return self.__match_type

    @property
    def action_name(self) -> str:
        """The name of the action to perform when triggered."""
        return self.__action_name

    @action_name.setter
    def action_name(self, value: str) -> None:
        self.__action_name = value

    @property
    def param(self) -> Any:
        """The parameter for the trigger action."""
        return self.__param

    @param.setter
    def param(self, value: Any) -> None:
        self.__param = value

    @property
    def enabled(self) -> bool:
        """Whether this trigger is enabled."""
        return self.__enabled

    @enabled.setter
    def enabled(self, value: bool) -> None:
        self.__enabled = value

    @property
    def event_params(self) -> dict[str, Any]:
        """Event-specific parameters (e.g., exit_code_filter, timeout)."""
        return self.__event_params

    @event_params.setter
    def event_params(self, value: dict[str, Any]) -> None:
        self.__event_params = value

    @property
    def encode(self) -> dict[str, Any]:
        """Encode this trigger for sending to iTerm2."""
        match_type_value = (
            self.__raw_match_type
            if self.__raw_match_type is not None
            else self.__match_type.value
        )
        result: dict[str, Any] = {
            "regex": "",
            "action": self.__action_name,
            "parameter": self.__param if self.__param else "",
            "partial": False,
            "disabled": not self.__enabled,
            "matchType": match_type_value,
        }
        if self.__event_params:
            result["eventParams"] = self.__event_params
        return result

    def toJSON(self) -> str:
        return json.dumps(self.encode)

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> EventTrigger:
        return EventTrigger(
            match_type=MatchType.EVENT_PROMPT_DETECTED,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,  # type: ignore[arg-type]
        )


class PromptDetectedEventTrigger(EventTrigger):
    """Trigger that fires when a shell prompt is detected.

    Requires shell integration.
    """

    def __init__(self, action_name: str, param: Any, enabled: bool) -> None:
        super().__init__(
            match_type=MatchType.EVENT_PROMPT_DETECTED,
            action_name=action_name,
            param=param,
            enabled=enabled,
        )

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> PromptDetectedEventTrigger:
        return PromptDetectedEventTrigger(action_name, param, enabled)


class ExitCodeFilter(enum.Enum):
    """Filter for command exit codes."""

    ANY = "*"
    ZERO = "0"
    NON_ZERO = "!0"


class CommandFinishedEventTrigger(EventTrigger):
    """Trigger that fires when a command finishes.

    Can filter by exit code. Requires shell integration.

    :param action_name: The action to perform (e.g., "AlertTrigger").
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param exit_code_filter: Filter for exit codes. Can be:
        - ExitCodeFilter.ANY: Match any exit code
        - ExitCodeFilter.ZERO: Match only exit code 0
        - ExitCodeFilter.NON_ZERO: Match non-zero exit codes
        - A specific integer exit code
    """

    def __init__(
        self,
        action_name: str,
        param: Any,
        enabled: bool,
        exit_code_filter: ExitCodeFilter | int = ExitCodeFilter.ANY,
    ) -> None:
        event_params: dict[str, Any] = {}
        if isinstance(exit_code_filter, ExitCodeFilter):
            event_params["exitCodeFilter"] = exit_code_filter.value
        else:
            event_params["exitCodeFilter"] = str(exit_code_filter)
        super().__init__(
            match_type=MatchType.EVENT_COMMAND_FINISHED,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__exit_code_filter = exit_code_filter

    @property
    def exit_code_filter(self) -> ExitCodeFilter | int:
        """The exit code filter for this trigger."""
        return self.__exit_code_filter

    @exit_code_filter.setter
    def exit_code_filter(self, value: ExitCodeFilter | int) -> None:
        self.__exit_code_filter = value
        if isinstance(value, ExitCodeFilter):
            self.event_params["exitCodeFilter"] = value.value
        else:
            self.event_params["exitCodeFilter"] = str(value)

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> CommandFinishedEventTrigger:
        exit_code_filter: ExitCodeFilter | int = ExitCodeFilter.ANY
        if event_params:
            filter_str = event_params.get("exitCodeFilter", "*")
            if filter_str == "*" or filter_str == "":
                exit_code_filter = ExitCodeFilter.ANY
            elif filter_str == "0":
                exit_code_filter = ExitCodeFilter.ZERO
            elif filter_str == "!0":
                exit_code_filter = ExitCodeFilter.NON_ZERO
            else:
                try:
                    exit_code_filter = int(filter_str)
                except ValueError:
                    exit_code_filter = ExitCodeFilter.ANY
        return CommandFinishedEventTrigger(
            action_name, param, enabled, exit_code_filter
        )


class DirectoryChangedEventTrigger(EventTrigger):
    """Trigger that fires when the working directory changes.

    Can optionally filter by a regex pattern. Requires shell integration.

    :param action_name: The action to perform.
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param directory_regex: Optional regex pattern to match against the new directory.
    """

    def __init__(
        self,
        action_name: str,
        param: Any,
        enabled: bool,
        directory_regex: str | None = None,
    ) -> None:
        event_params: dict[str, Any] = {}
        if directory_regex:
            event_params["directoryRegex"] = directory_regex
        super().__init__(
            match_type=MatchType.EVENT_DIRECTORY_CHANGED,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__directory_regex = directory_regex

    @property
    def directory_regex(self) -> str | None:
        """Regex pattern to match against the new directory."""
        return self.__directory_regex

    @directory_regex.setter
    def directory_regex(self, value: str | None) -> None:
        self.__directory_regex = value
        if value:
            self.event_params["directoryRegex"] = value
        elif "directoryRegex" in self.event_params:
            del self.event_params["directoryRegex"]

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> DirectoryChangedEventTrigger:
        directory_regex = event_params.get("directoryRegex") if event_params else None
        return DirectoryChangedEventTrigger(
            action_name, param, enabled, directory_regex
        )


class HostChangedEventTrigger(EventTrigger):
    """Trigger that fires when the remote host changes.

    Can optionally filter by a regex pattern. Requires shell integration.

    :param action_name: The action to perform.
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param host_regex: Optional regex pattern to match against the new host.
    """

    def __init__(
        self, action_name: str, param: Any, enabled: bool, host_regex: str | None = None
    ) -> None:
        event_params: dict[str, Any] = {}
        if host_regex:
            event_params["hostRegex"] = host_regex
        super().__init__(
            match_type=MatchType.EVENT_HOST_CHANGED,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__host_regex = host_regex

    @property
    def host_regex(self) -> str | None:
        """Regex pattern to match against the new host."""
        return self.__host_regex

    @host_regex.setter
    def host_regex(self, value: str | None) -> None:
        self.__host_regex = value
        if value:
            self.event_params["hostRegex"] = value
        elif "hostRegex" in self.event_params:
            del self.event_params["hostRegex"]

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> HostChangedEventTrigger:
        host_regex = event_params.get("hostRegex") if event_params else None
        return HostChangedEventTrigger(action_name, param, enabled, host_regex)


class UserChangedEventTrigger(EventTrigger):
    """Trigger that fires when the current user changes.

    Can optionally filter by a regex pattern. Requires shell integration.

    :param action_name: The action to perform.
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param user_regex: Optional regex pattern to match against the new username.
    """

    def __init__(
        self, action_name: str, param: Any, enabled: bool, user_regex: str | None = None
    ) -> None:
        event_params: dict[str, Any] = {}
        if user_regex:
            event_params["userRegex"] = user_regex
        super().__init__(
            match_type=MatchType.EVENT_USER_CHANGED,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__user_regex = user_regex

    @property
    def user_regex(self) -> str | None:
        """Regex pattern to match against the new username."""
        return self.__user_regex

    @user_regex.setter
    def user_regex(self, value: str | None) -> None:
        self.__user_regex = value
        if value:
            self.event_params["userRegex"] = value
        elif "userRegex" in self.event_params:
            del self.event_params["userRegex"]

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> UserChangedEventTrigger:
        user_regex = event_params.get("userRegex") if event_params else None
        return UserChangedEventTrigger(action_name, param, enabled, user_regex)


class IdleEventTrigger(EventTrigger):
    """Trigger that fires when the session becomes idle.

    :param action_name: The action to perform.
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param timeout: Number of seconds of inactivity before firing. Default is 30.
    """

    def __init__(
        self, action_name: str, param: Any, enabled: bool, timeout: float = 30.0
    ) -> None:
        event_params = {"timeout": timeout}
        super().__init__(
            match_type=MatchType.EVENT_IDLE,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__timeout = timeout

    @property
    def timeout(self) -> float:
        """Number of seconds of inactivity before firing."""
        return self.__timeout

    @timeout.setter
    def timeout(self, value: float) -> None:
        self.__timeout = value
        self.event_params["timeout"] = value

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> IdleEventTrigger:
        timeout = 30.0
        if event_params and "timeout" in event_params:
            timeout = float(event_params["timeout"])
        return IdleEventTrigger(action_name, param, enabled, timeout)


class ActivityAfterIdleEventTrigger(EventTrigger):
    """Trigger that fires when activity resumes after the session was idle.

    :param action_name: The action to perform.
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param timeout: Number of seconds of inactivity required before activity
        will trigger. Default is 30.
    """

    def __init__(
        self, action_name: str, param: Any, enabled: bool, timeout: float = 30.0
    ) -> None:
        event_params = {"timeout": timeout}
        super().__init__(
            match_type=MatchType.EVENT_ACTIVITY_AFTER_IDLE,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__timeout = timeout

    @property
    def timeout(self) -> float:
        """Number of seconds of inactivity required before activity will trigger."""
        return self.__timeout

    @timeout.setter
    def timeout(self, value: float) -> None:
        self.__timeout = value
        self.event_params["timeout"] = value

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> ActivityAfterIdleEventTrigger:
        timeout = 30.0
        if event_params and "timeout" in event_params:
            timeout = float(event_params["timeout"])
        return ActivityAfterIdleEventTrigger(action_name, param, enabled, timeout)


class SessionEndedEventTrigger(EventTrigger):
    """Trigger that fires when the session ends."""

    def __init__(self, action_name: str, param: Any, enabled: bool) -> None:
        super().__init__(
            match_type=MatchType.EVENT_SESSION_ENDED,
            action_name=action_name,
            param=param,
            enabled=enabled,
        )

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> SessionEndedEventTrigger:
        return SessionEndedEventTrigger(action_name, param, enabled)


class BellReceivedEventTrigger(EventTrigger):
    """Trigger that fires when a bell character is received."""

    def __init__(self, action_name: str, param: Any, enabled: bool) -> None:
        super().__init__(
            match_type=MatchType.EVENT_BELL_RECEIVED,
            action_name=action_name,
            param=param,
            enabled=enabled,
        )

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> BellReceivedEventTrigger:
        return BellReceivedEventTrigger(action_name, param, enabled)


class LongRunningCommandEventTrigger(EventTrigger):
    """Trigger that fires when a command runs longer than a threshold.

    Requires shell integration.

    :param action_name: The action to perform.
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param threshold: Number of seconds a command must run before triggering.
        Default is 60.
    :param command_regex: Optional regex pattern to match against the command.
    """

    def __init__(
        self,
        action_name: str,
        param: Any,
        enabled: bool,
        threshold: float = 60.0,
        command_regex: str | None = None,
    ) -> None:
        event_params: dict[str, Any] = {"threshold": threshold}
        if command_regex:
            event_params["commandRegex"] = command_regex
        super().__init__(
            match_type=MatchType.EVENT_LONG_RUNNING_COMMAND,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__threshold = threshold
        self.__command_regex = command_regex

    @property
    def threshold(self) -> float:
        """Number of seconds a command must run before triggering."""
        return self.__threshold

    @threshold.setter
    def threshold(self, value: float) -> None:
        self.__threshold = value
        self.event_params["threshold"] = value

    @property
    def command_regex(self) -> str | None:
        """Regex pattern to match against the command."""
        return self.__command_regex

    @command_regex.setter
    def command_regex(self, value: str | None) -> None:
        self.__command_regex = value
        if value:
            self.event_params["commandRegex"] = value
        elif "commandRegex" in self.event_params:
            del self.event_params["commandRegex"]

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> LongRunningCommandEventTrigger:
        threshold = 60.0
        command_regex = None
        if event_params:
            if "threshold" in event_params:
                threshold = float(event_params["threshold"])
            command_regex = event_params.get("commandRegex")
        return LongRunningCommandEventTrigger(
            action_name, param, enabled, threshold, command_regex
        )


class CustomEscapeSequenceEventTrigger(EventTrigger):
    """Trigger that fires when a custom escape sequence is received.

    Custom escape sequences are sent with OSC 1337 ; Custom=id=<id>:<payload> ST.

    :param action_name: The action to perform.
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param sequence_id: The identifier of the escape sequence to match.
        Can be a regex pattern.
    """

    def __init__(
        self,
        action_name: str,
        param: Any,
        enabled: bool,
        sequence_id: str | None = None,
    ) -> None:
        event_params: dict[str, Any] = {}
        if sequence_id:
            event_params["sequenceId"] = sequence_id
        super().__init__(
            match_type=MatchType.EVENT_CUSTOM_ESCAPE_SEQUENCE,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__sequence_id = sequence_id

    @property
    def sequence_id(self) -> str | None:
        """The identifier of the escape sequence to match."""
        return self.__sequence_id

    @sequence_id.setter
    def sequence_id(self, value: str | None) -> None:
        self.__sequence_id = value
        if value:
            self.event_params["sequenceId"] = value
        elif "sequenceId" in self.event_params:
            del self.event_params["sequenceId"]

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> CustomEscapeSequenceEventTrigger:
        sequence_id = event_params.get("sequenceId") if event_params else None
        return CustomEscapeSequenceEventTrigger(
            action_name, param, enabled, sequence_id
        )


class NotificationPostedEventTrigger(EventTrigger):
    """Trigger that fires when a notification is posted by a control sequence (OSC 9).

    :param action_name: The action to perform.
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param message_regex: Optional regex pattern to match against the notification
        message.
    """

    def __init__(
        self,
        action_name: str,
        param: Any,
        enabled: bool,
        message_regex: str | None = None,
    ) -> None:
        event_params: dict[str, Any] = {}
        if message_regex:
            event_params["messageRegex"] = message_regex
        super().__init__(
            match_type=MatchType.EVENT_NOTIFICATION_POSTED,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__message_regex = message_regex

    @property
    def message_regex(self) -> str | None:
        """Regex pattern to match against the notification message."""
        return self.__message_regex

    @message_regex.setter
    def message_regex(self, value: str | None) -> None:
        self.__message_regex = value
        if value:
            self.event_params["messageRegex"] = value
        elif "messageRegex" in self.event_params:
            del self.event_params["messageRegex"]

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> NotificationPostedEventTrigger:
        message_regex = event_params.get("messageRegex") if event_params else None
        return NotificationPostedEventTrigger(
            action_name, param, enabled, message_regex
        )


class ProgressBarChangedEventTrigger(EventTrigger):
    """Trigger that fires when a progress bar appears or disappears.

    :param action_name: The action to perform.
    :param param: The parameter for the action.
    :param enabled: Whether the trigger is enabled.
    :param progress_bar_filter: Filter for when to fire. One of ``"*"``
        (appears or disappears), ``"appeared"``, or ``"disappeared"``.
        Defaults to ``"*"``.
    """

    def __init__(
        self,
        action_name: str,
        param: Any,
        enabled: bool,
        progress_bar_filter: str = "*",
    ) -> None:
        event_params: dict[str, Any] = {}
        if progress_bar_filter and progress_bar_filter != "*":
            event_params["progressBarFilter"] = progress_bar_filter
        super().__init__(
            match_type=MatchType.EVENT_PROGRESS_BAR_CHANGED,
            action_name=action_name,
            param=param,
            enabled=enabled,
            event_params=event_params,
        )
        self.__progress_bar_filter = progress_bar_filter

    @property
    def progress_bar_filter(self) -> str:
        """Filter for when to fire: ``"*"``, ``"appeared"``, or ``"disappeared"``."""
        return self.__progress_bar_filter

    @progress_bar_filter.setter
    def progress_bar_filter(self, value: str) -> None:
        self.__progress_bar_filter = value
        if value and value != "*":
            self.event_params["progressBarFilter"] = value
        elif "progressBarFilter" in self.event_params:
            del self.event_params["progressBarFilter"]

    @staticmethod
    def deserialize(
        action_name: str,
        param: Any,
        enabled: bool,
        event_params: dict[str, Any] | None,
        action_classes: Mapping[str, type[Trigger]],
    ) -> ProgressBarChangedEventTrigger:
        progress_bar_filter = (
            event_params.get("progressBarFilter", "*") if event_params else "*"
        )
        return ProgressBarChangedEventTrigger(
            action_name, param, enabled, progress_bar_filter
        )
