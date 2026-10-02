import enum
from collections.abc import Iterable
from types import TracebackType
from typing_extensions import Self

from . import api_pb2
from .connection import Connection

class Modifier(enum.Enum):
    CONTROL = 1
    OPTION = 2
    COMMAND = 3
    SHIFT = 4
    FUNCTION = 5
    NUMPAD = 6
    @staticmethod
    def from_cocoa(value: int) -> list[Modifier]: ...
    def to_cocoa(self) -> int: ...

class Keycode(enum.Enum):
    ANSI_A = 0
    ANSI_S = 1
    ANSI_D = 2
    ANSI_F = 3
    ANSI_H = 4
    ANSI_G = 5
    ANSI_Z = 6
    ANSI_X = 7
    ANSI_C = 8
    ANSI_V = 9
    ANSI_B = 11
    ANSI_Q = 12
    ANSI_W = 13
    ANSI_E = 14
    ANSI_R = 15
    ANSI_Y = 16
    ANSI_T = 17
    ANSI_1 = 18
    ANSI_2 = 19
    ANSI_3 = 20
    ANSI_4 = 21
    ANSI_6 = 22
    ANSI_5 = 23
    ANSI_EQUAL = 24
    ANSI_9 = 25
    ANSI_7 = 26
    ANSI_MINUS = 27
    ANSI_8 = 28
    ANSI_0 = 29
    ANSI_RIGHT_BRACKET = 30
    ANSI_O = 31
    ANSI_U = 32
    ANSI_LEFT_BRACKET = 33
    ANSI_I = 34
    ANSI_P = 35
    ANSI_L = 37
    ANSI_J = 38
    ANSI_QUOTE = 39
    ANSI_K = 40
    ANSI_SEMICOLON = 41
    ANSI_BACKSLASH = 42
    ANSI_COMMA = 43
    ANSI_SLASH = 44
    ANSI_N = 45
    ANSI_M = 46
    ANSI_PERIOD = 47
    ANSI_GRAVE = 50
    ANSI_KEYPAD_DECIMAL = 65
    ANSI_KEYPAD_MULTIPLY = 67
    ANSI_KEYPAD_PLUS = 69
    ANSI_KEYPAD_CLEAR = 71
    ANSI_KEYPAD_DIVIDE = 75
    ANSI_KEYPAD_ENTER = 76
    ANSI_KEYPAD_MINUS = 78
    ANSI_KEYPAD_EQUALS = 81
    ANSI_KEYPAD0 = 82
    ANSI_KEYPAD1 = 83
    ANSI_KEYPAD2 = 84
    ANSI_KEYPAD3 = 85
    ANSI_KEYPAD4 = 86
    ANSI_KEYPAD5 = 87
    ANSI_KEYPAD6 = 88
    ANSI_KEYPAD7 = 89
    ANSI_KEYPAD8 = 91
    ANSI_KEYPAD9 = 92
    RETURN = 36
    TAB = 48
    SPACE = 49
    DELETE = 51
    ESCAPE = 53
    COMMAND = 55
    SHIFT = 56
    CAPS_LOCK = 57
    OPTION = 58
    CONTROL = 59
    RIGHT_COMMAND = 54
    RIGHT_SHIFT = 60
    RIGHT_OPTION = 61
    RIGHT_CONTROL = 62
    FUNCTION = 63
    F17 = 64
    VOLUME_UP = 72
    VOLUME_DOWN = 73
    MUTE = 74
    F18 = 79
    F19 = 80
    F20 = 90
    F5 = 96
    F6 = 97
    F7 = 98
    F3 = 99
    F8 = 100
    F9 = 101
    F11 = 103
    F13 = 105
    F16 = 106
    F14 = 107
    F10 = 109
    F12 = 111
    F15 = 113
    HELP = 114
    HOME = 115
    PAGE_UP = 116
    FORWARD_DELETE = 117
    F4 = 118
    END = 119
    F2 = 120
    PAGE_DOWN = 121
    F1 = 122
    LEFT_ARROW = 123
    RIGHT_ARROW = 124
    DOWN_ARROW = 125
    UP_ARROW = 126

class Keystroke:
    class Action(enum.Enum):
        NA = 0
        KEY_DOWN = 1
        KEY_UP = 2
        FLAGS_CHANGED = 3

    def __init__(self, notification: api_pb2.KeystrokeNotification) -> None: ...
    @property
    def characters(self) -> str: ...
    @property
    def characters_ignoring_modifiers(self) -> str: ...
    @property
    def modifiers(self) -> list[Modifier]: ...
    @property
    def keycode(self) -> Keycode: ...
    @property
    def action(self) -> Keystroke.Action: ...

class KeystrokePattern:
    def __init__(self) -> None: ...
    @property
    def required_modifiers(self) -> list[Modifier]: ...
    @required_modifiers.setter
    def required_modifiers(self, value: list[Modifier]) -> None: ...
    @property
    def forbidden_modifiers(self) -> list[Modifier]: ...
    @forbidden_modifiers.setter
    def forbidden_modifiers(self, value: list[Modifier]) -> None: ...
    @property
    def keycodes(self) -> list[Keycode]: ...
    @keycodes.setter
    def keycodes(self, value: list[Keycode]) -> None: ...
    @property
    def characters(self) -> list[str]: ...
    @characters.setter
    def characters(self, value: list[str]) -> None: ...
    @property
    def characters_ignoring_modifiers(self) -> list[str]: ...
    @characters_ignoring_modifiers.setter
    def characters_ignoring_modifiers(self, value: list[str]) -> None: ...
    def to_proto(self) -> api_pb2.KeystrokePattern: ...

class KeystrokeMonitor:
    def __init__(
        self,
        connection: Connection,
        session: str | None = None,
        advanced: bool | None = False,
    ) -> None: ...
    async def __aenter__(self) -> Self: ...
    async def async_get(self) -> Keystroke: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: TracebackType | None,
    ) -> None: ...

class KeystrokeFilter:
    def __init__(
        self,
        connection: Connection,
        patterns: Iterable[KeystrokePattern],
        session: str | None = None,
    ) -> None: ...
    async def __aenter__(self) -> Self: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: TracebackType | None,
    ) -> None: ...
