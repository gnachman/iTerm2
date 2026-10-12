"""
Provides classes for monitoring keyboard activity and modifying how iTerm2
handles keystrokes.
"""

from __future__ import annotations

from asyncio import Queue
from enum import Enum
from typing import TYPE_CHECKING

from . import api_pb2
from .capabilities import check_supports_advanced_key_notifications
from .notifications import (
    SubscriptionException,
    async_filter_keystrokes,
    async_subscribe_to_keystroke_notification,
    async_unsubscribe,
)

if TYPE_CHECKING:
    from collections.abc import Iterable
    from types import TracebackType
    from typing import Self

    from .connection import Connection
    from .notifications import NotificationToken


# pylint: disable=line-too-long
class Modifier(Enum):
    """Enumerated list of modifier keys."""

    CONTROL = api_pb2.Modifiers.Value("CONTROL")  #: The control key modifier
    OPTION = api_pb2.Modifiers.Value("OPTION")  #: The option (or Alt) key modifier
    COMMAND = api_pb2.Modifiers.Value("COMMAND")  #: The command key modifier
    SHIFT = api_pb2.Modifiers.Value("SHIFT")  #: The shift key modifier
    FUNCTION = api_pb2.Modifiers.Value(
        "FUNCTION"
    )  #: Indicates the key is a function key.
    NUMPAD = api_pb2.Modifiers.Value(
        "NUMPAD"
    )  #: Indicates the key is on the numeric keypad.

    @staticmethod
    def from_cocoa(value: int) -> list[Modifier]:
        result: list[Modifier] = []
        if value & (1 << 18):
            result.append(Modifier.CONTROL)
        if value & (1 << 19):
            result.append(Modifier.OPTION)
        if value & (1 << 20):
            result.append(Modifier.COMMAND)
        if value & (1 << 17):
            result.append(Modifier.SHIFT)
        if value & (1 << 23):
            result.append(Modifier.FUNCTION)
        if value & (1 << 21):
            result.append(Modifier.NUMPAD)
        return result

    def to_cocoa(self) -> int:
        if self == Modifier.CONTROL:
            return 1 << 18

        if self == Modifier.OPTION:
            return 1 << 19

        if self == Modifier.COMMAND:
            return 1 << 20

        if self == Modifier.SHIFT:
            return 1 << 17

        if self == Modifier.FUNCTION:
            return 1 << 23

        if self == Modifier.NUMPAD:
            return 1 << 21

        return 0


# pylint: enable=line-too-long


class Keycode(Enum):
    """Enumerated list of virtual keycodes. These repesent physical keys on a
    keyboard regardless of its actual layout."""

    ANSI_A = 0x00
    ANSI_S = 0x01
    ANSI_D = 0x02
    ANSI_F = 0x03
    ANSI_H = 0x04
    ANSI_G = 0x05
    ANSI_Z = 0x06
    ANSI_X = 0x07
    ANSI_C = 0x08
    ANSI_V = 0x09
    ANSI_B = 0x0B
    ANSI_Q = 0x0C
    ANSI_W = 0x0D
    ANSI_E = 0x0E
    ANSI_R = 0x0F
    ANSI_Y = 0x10
    ANSI_T = 0x11
    ANSI_1 = 0x12
    ANSI_2 = 0x13
    ANSI_3 = 0x14
    ANSI_4 = 0x15
    ANSI_6 = 0x16
    ANSI_5 = 0x17
    ANSI_EQUAL = 0x18
    ANSI_9 = 0x19
    ANSI_7 = 0x1A
    ANSI_MINUS = 0x1B
    ANSI_8 = 0x1C
    ANSI_0 = 0x1D
    ANSI_RIGHT_BRACKET = 0x1E
    ANSI_O = 0x1F
    ANSI_U = 0x20
    ANSI_LEFT_BRACKET = 0x21
    ANSI_I = 0x22
    ANSI_P = 0x23
    ANSI_L = 0x25
    ANSI_J = 0x26
    ANSI_QUOTE = 0x27
    ANSI_K = 0x28
    ANSI_SEMICOLON = 0x29
    ANSI_BACKSLASH = 0x2A
    ANSI_COMMA = 0x2B
    ANSI_SLASH = 0x2C
    ANSI_N = 0x2D
    ANSI_M = 0x2E
    ANSI_PERIOD = 0x2F
    ANSI_GRAVE = 0x32
    ANSI_KEYPAD_DECIMAL = 0x41
    ANSI_KEYPAD_MULTIPLY = 0x43
    ANSI_KEYPAD_PLUS = 0x45
    ANSI_KEYPAD_CLEAR = 0x47
    ANSI_KEYPAD_DIVIDE = 0x4B
    ANSI_KEYPAD_ENTER = 0x4C
    ANSI_KEYPAD_MINUS = 0x4E
    ANSI_KEYPAD_EQUALS = 0x51
    ANSI_KEYPAD0 = 0x52
    ANSI_KEYPAD1 = 0x53
    ANSI_KEYPAD2 = 0x54
    ANSI_KEYPAD3 = 0x55
    ANSI_KEYPAD4 = 0x56
    ANSI_KEYPAD5 = 0x57
    ANSI_KEYPAD6 = 0x58
    ANSI_KEYPAD7 = 0x59
    ANSI_KEYPAD8 = 0x5B
    ANSI_KEYPAD9 = 0x5C
    RETURN = 0x24
    TAB = 0x30
    SPACE = 0x31
    DELETE = 0x33
    ESCAPE = 0x35
    COMMAND = 0x37
    SHIFT = 0x38
    CAPS_LOCK = 0x39
    OPTION = 0x3A
    CONTROL = 0x3B
    RIGHT_COMMAND = 0x36
    RIGHT_SHIFT = 0x3C
    RIGHT_OPTION = 0x3D
    RIGHT_CONTROL = 0x3E
    FUNCTION = 0x3F
    F17 = 0x40
    VOLUME_UP = 0x48
    VOLUME_DOWN = 0x49
    MUTE = 0x4A
    F18 = 0x4F
    F19 = 0x50
    F20 = 0x5A
    F5 = 0x60
    F6 = 0x61
    F7 = 0x62
    F3 = 0x63
    F8 = 0x64
    F9 = 0x65
    F11 = 0x67
    F13 = 0x69
    F16 = 0x6A
    F14 = 0x6B
    F10 = 0x6D
    F12 = 0x6F
    F15 = 0x71
    HELP = 0x72
    HOME = 0x73
    PAGE_UP = 0x74
    FORWARD_DELETE = 0x75
    F4 = 0x76
    END = 0x77
    F2 = 0x78
    PAGE_DOWN = 0x79
    F1 = 0x7A
    LEFT_ARROW = 0x7B
    RIGHT_ARROW = 0x7C
    DOWN_ARROW = 0x7D
    UP_ARROW = 0x7E


class Keystroke:
    """Describes a keystroke.

    Do not create instances of this class. They will be passed to you when you
    use a :class:`KeystrokeMonitor`.
    """

    class Action(Enum):
        """Type of keyboard event."""

        NA = 0  #: Advanced keyboard monitoring is not enabled. Otherwise, this is the same as KEY_DOWN.
        KEY_DOWN = 1  #: A non-modifier was pressed.
        KEY_UP = 2  #: A non-modifier was released.
        FLAGS_CHANGED = 3  #: Only modifiers changed

    def __init__(self, notification: api_pb2.KeystrokeNotification) -> None:
        self.__characters = notification.characters
        self.__characters_ignoring_modifiers = notification.charactersIgnoringModifiers
        self.__modifiers = notification.modifiers
        self.__key_code = notification.keyCode
        self.__action = Keystroke.Action.NA
        if notification.HasField("action"):
            if notification.action == api_pb2.KeystrokeNotification.Action.Value(
                "KEY_DOWN"
            ):
                self.__action = Keystroke.Action.KEY_DOWN
            elif notification.action == api_pb2.KeystrokeNotification.Action.Value(
                "KEY_UP"
            ):
                self.__action = Keystroke.Action.KEY_UP
            elif notification.action == api_pb2.KeystrokeNotification.Action.Value(
                "FLAGS_CHANGED"
            ):
                self.__action = Keystroke.Action.FLAGS_CHANGED

    def __repr__(self):
        info = (
            "chars={}, charsIgnoringModifiers={}, " + "modifiers={}, keyCode={}"
        ).format(
            self.characters,
            self.characters_ignoring_modifiers,
            self.modifiers,
            self.keycode,
        )
        if self.__action == Keystroke.Action.KEY_DOWN:
            info = info + ", action=key-down"
        elif self.__action == Keystroke.Action.KEY_UP:
            info = info + ", action=key-up"
        elif self.__action == Keystroke.Action.FLAGS_CHANGED:
            info = info + ", action=flags-changed"
        return f"Keystroke({info})"

    @property
    def characters(self) -> str:
        """A string giving the characters that would be generated by the
        keystroke ordinarily.

        :returns: A string."""
        return self.__characters

    @property
    def characters_ignoring_modifiers(self) -> str:
        """A string giving the characters that would be generated by the
        keystroke as if no modifiers besides shift were pressed.

        :returns: A string."""
        return self.__characters_ignoring_modifiers

    @property
    def modifiers(self) -> list[Modifier]:
        """The modifiers that were pressed.

        :returns: A list of :class:`Modifier` objects."""
        return list(map(Modifier, self.__modifiers))

    @property
    def keycode(self) -> Keycode:
        """The ANSI keycode that was pressed.

        :returns: A :class:`Keycode` object."""
        return Keycode(self.__key_code)

    @property
    def action(self) -> Keystroke.Action:
        """The kind of keystroke.

        :returns: A :class:`Keystroke.Action` object."""
        return self.__action


class KeystrokePattern:
    """Describes attributes that select keystrokes.

    Keystrokes contain modifiers (e.g., command or option), characters (what
    characters are generated by the keypress), and characters ignoring
    modifiers (what characters would be generated if no modifiers were pressed,
    excepting the shift key).
    """

    def __init__(self) -> None:
        self.__required_modifiers: list[Modifier] = []
        self.__forbidden_modifiers: list[Modifier] = []
        self.__keycodes: list[Keycode] = []
        self.__characters: list[str] = []
        self.__characters_ignoring_modifiers: list[str] = []

    @property
    def required_modifiers(self) -> list[Modifier]:
        """List of modifiers that are required to match the pattern.

        A list of type :class:`Modifier`.
        """
        return self.__required_modifiers

    @required_modifiers.setter
    def required_modifiers(self, value: list[Modifier]) -> None:
        self.__required_modifiers = value

    @property
    def forbidden_modifiers(self) -> list[Modifier]:
        """
        List of modifiers whose presence prevents the pattern from being
        matched.

        A list of type :class:`Modifier`.
        """
        return self.__forbidden_modifiers

    @forbidden_modifiers.setter
    def forbidden_modifiers(self, value: list[Modifier]) -> None:
        self.__forbidden_modifiers = value

    @property
    def keycodes(self) -> list[Keycode]:
        """List of keycodes that match the pattern.

        The pattern matches if the modifier constraints are satisfied and a
        keystroke has any of these keycodes.

        A list of type :class:`Keycode`."""
        return self.__keycodes

    @keycodes.setter
    def keycodes(self, value: list[Keycode]) -> None:
        self.__keycodes = value

    @property
    def characters(self) -> list[str]:
        """List of strings. Each string has a character.

        The pattern matches if the modifier constraints are satisfied and a
        keystroke has any of these characters.
        """
        return self.__characters

    @characters.setter
    def characters(self, value: list[str]) -> None:
        self.__characters = value

    @property
    def characters_ignoring_modifiers(self) -> list[str]:
        """List of strings. Each string has a character.

        The pattern matches if the modifier constraints are satisfied and a
        keystroke has any of these characters, ignoring modifiers.

        "Ignoring modifiers" mostly means ignoring modifiers other than Shift.
        It has a lot of surprising edge cases which Apple did not document, so
        experiment to find how it works.
        """
        return self.__characters_ignoring_modifiers

    @characters_ignoring_modifiers.setter
    def characters_ignoring_modifiers(self, value: list[str]) -> None:
        self.__characters_ignoring_modifiers = value

    def to_proto(self) -> api_pb2.KeystrokePattern:
        """Creates a protobuf for this pattern."""
        # pylint: disable=no-member
        proto = api_pb2.KeystrokePattern()
        proto.required_modifiers.extend([x.value for x in self.__required_modifiers])
        proto.forbidden_modifiers.extend([x.value for x in self.__forbidden_modifiers])
        proto.keycodes.extend([x.value for x in self.__keycodes])
        proto.characters.extend(self.__characters)
        proto.characters_ignoring_modifiers.extend(self.__characters_ignoring_modifiers)
        return proto


class KeystrokeMonitor:
    """Monitors keystrokes in one or all sessions.

    :param connection: The :class:`~iterm2.Connection` to use.
    :param session: The session ID to affect, or `None` meaning all sessions.
    :param advanced: If false only key-down events are reported. If true,
        key-up and flags-changed events are also reported.
    .. seealso::
        * Example ":ref:`broadcast_example`"
        * Example ":ref:`escindicator_example`"
        * Example ":ref:`function_key_tabs_example`"

    Example:

      .. code-block:: python

          async with iterm2.KeystrokeMonitor(connection) as mon:
              while True:
                  keystroke = await mon.async_get()
                  DoSomething(keystroke)
    """

    def __init__(
        self,
        connection: Connection,
        session: str | None = None,
        advanced: bool | None = False,
    ) -> None:
        self.__connection = connection
        self.__session = session
        if advanced:
            check_supports_advanced_key_notifications(connection)
        # The protobuf field is a bool and rejects None.
        self.__advanced = bool(advanced)
        self.__token: NotificationToken | None = None
        self.__queue: Queue[api_pb2.KeystrokeNotification] = Queue()

    async def __aenter__(self) -> Self:
        # pylint: disable=unused-argument
        async def callback(
            connection: Connection, notification: api_pb2.KeystrokeNotification
        ):
            await self.__queue.put(notification)

        # pylint: enable=unused-argument
        self.__token = await async_subscribe_to_keystroke_notification(
            self.__connection, callback, self.__session, self.__advanced
        )
        return self

    async def async_get(self) -> Keystroke:
        """Wait for and return the next keystroke."""
        notification = await self.__queue.get()
        return Keystroke(notification)

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: TracebackType | None,
    ) -> None:
        if self.__token is None:
            return
        try:
            await async_unsubscribe(self.__connection, self.__token)
        except SubscriptionException:
            pass


class KeystrokeFilter:
    """
    An async context manager that disables the regular handling of keystrokes
    matching patterns during its lifetime.

    :param connection: The :class:`~iterm2.Connection` to use.
    :param patterns: A list of :class:`KeystrokePattern` objects specifying
        keystrokes whose regular handling should be disabled.
    :param session: The session ID to affect, or None meaning all.

    .. seealso::
        * Example ":ref:`broadcast_example`"
        * Example ":ref:`function_key_tabs_example`"

    Example:

    .. code-block:: python

        # Prevent iTerm2 from handling all control-key combinations.
        ctrl = iterm2.KeystrokePattern()
        ctrl.required_modifiers = [iterm2.Modifier.CONTROL]
        ctrl.keycodes = [keycode for keycode in iterm2.Keycode]

        filter = iterm2.KeystrokeFilter(connection, [ctrl])
        async with filter as mon:
            await iterm2.async_wait_forever()
    """

    def __init__(
        self,
        connection: Connection,
        patterns: Iterable[KeystrokePattern],
        session: str | None = None,
    ) -> None:
        self.__connection = connection
        self.__session = session
        self.__patterns = patterns
        self.__token: NotificationToken | None = None

    async def __aenter__(self) -> Self:
        self.__token = await async_filter_keystrokes(
            self.__connection, self.__patterns, self.__session
        )
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: TracebackType | None,
    ) -> None:
        if self.__token is None:
            return
        try:
            await async_unsubscribe(self.__connection, self.__token)
        except SubscriptionException:
            pass
