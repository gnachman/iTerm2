"""
Provides classes for monitoring keyboard activity and modifying how iTerm2
handles keystrokes.
"""
import asyncio
import enum
import typing

import iterm2.api_pb2
import iterm2.capabilities
import iterm2.connection
import iterm2.notifications


# pylint: disable=line-too-long
class Modifier(enum.Enum):
    """Enumerated list of modifier keys."""
    CONTROL = iterm2.api_pb2.Modifiers.Value("CONTROL")  #: The control key modifier
    OPTION = iterm2.api_pb2.Modifiers.Value("OPTION")  #: The option (or Alt) key modifier
    COMMAND = iterm2.api_pb2.Modifiers.Value("COMMAND")  #: The command key modifier
    SHIFT = iterm2.api_pb2.Modifiers.Value("SHIFT")  #: The shift key modifier
    FUNCTION = iterm2.api_pb2.Modifiers.Value("FUNCTION")  #: Indicates the key is a function key.
    NUMPAD = iterm2.api_pb2.Modifiers.Value("NUMPAD")  #: Indicates the key is on the numeric keypad.

    @staticmethod
    def from_cocoa(value: int) -> ['Modifier']:
        result = []
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


class Keycode(enum.Enum):
    """Enumerated list of virtual keycodes. These repesent physical keys on a
    keyboard regardless of its actual layout."""
    ANSI_A = 0X00
    ANSI_S = 0X01
    ANSI_D = 0X02
    ANSI_F = 0X03
    ANSI_H = 0X04
    ANSI_G = 0X05
    ANSI_Z = 0X06
    ANSI_X = 0X07
    ANSI_C = 0X08
    ANSI_V = 0X09
    ANSI_B = 0X0B
    ANSI_Q = 0X0C
    ANSI_W = 0X0D
    ANSI_E = 0X0E
    ANSI_R = 0X0F
    ANSI_Y = 0X10
    ANSI_T = 0X11
    ANSI_1 = 0X12
    ANSI_2 = 0X13
    ANSI_3 = 0X14
    ANSI_4 = 0X15
    ANSI_6 = 0X16
    ANSI_5 = 0X17
    ANSI_EQUAL = 0X18
    ANSI_9 = 0X19
    ANSI_7 = 0X1A
    ANSI_MINUS = 0X1B
    ANSI_8 = 0X1C
    ANSI_0 = 0X1D
    ANSI_RIGHT_BRACKET = 0X1E
    ANSI_O = 0X1F
    ANSI_U = 0X20
    ANSI_LEFT_BRACKET = 0X21
    ANSI_I = 0X22
    ANSI_P = 0X23
    ANSI_L = 0X25
    ANSI_J = 0X26
    ANSI_QUOTE = 0X27
    ANSI_K = 0X28
    ANSI_SEMICOLON = 0X29
    ANSI_BACKSLASH = 0X2A
    ANSI_COMMA = 0X2B
    ANSI_SLASH = 0X2C
    ANSI_N = 0X2D
    ANSI_M = 0X2E
    ANSI_PERIOD = 0X2F
    ANSI_GRAVE = 0X32
    ANSI_KEYPAD_DECIMAL = 0X41
    ANSI_KEYPAD_MULTIPLY = 0X43
    ANSI_KEYPAD_PLUS = 0X45
    ANSI_KEYPAD_CLEAR = 0X47
    ANSI_KEYPAD_DIVIDE = 0X4B
    ANSI_KEYPAD_ENTER = 0X4C
    ANSI_KEYPAD_MINUS = 0X4E
    ANSI_KEYPAD_EQUALS = 0X51
    ANSI_KEYPAD0 = 0X52
    ANSI_KEYPAD1 = 0X53
    ANSI_KEYPAD2 = 0X54
    ANSI_KEYPAD3 = 0X55
    ANSI_KEYPAD4 = 0X56
    ANSI_KEYPAD5 = 0X57
    ANSI_KEYPAD6 = 0X58
    ANSI_KEYPAD7 = 0X59
    ANSI_KEYPAD8 = 0X5B
    ANSI_KEYPAD9 = 0X5C
    RETURN = 0X24
    TAB = 0X30
    SPACE = 0X31
    DELETE = 0X33
    ESCAPE = 0X35
    COMMAND = 0X37
    SHIFT = 0X38
    CAPS_LOCK = 0X39
    OPTION = 0X3A
    CONTROL = 0X3B
    RIGHT_COMMAND = 0x36
    RIGHT_SHIFT = 0X3C
    RIGHT_OPTION = 0X3D
    RIGHT_CONTROL = 0X3E
    FUNCTION = 0X3F
    F17 = 0X40
    VOLUME_UP = 0X48
    VOLUME_DOWN = 0X49
    MUTE = 0X4A
    F18 = 0X4F
    F19 = 0X50
    F20 = 0X5A
    F5 = 0X60
    F6 = 0X61
    F7 = 0X62
    F3 = 0X63
    F8 = 0X64
    F9 = 0X65
    F11 = 0X67
    F13 = 0X69
    F16 = 0X6A
    F14 = 0X6B
    F10 = 0X6D
    F12 = 0X6F
    F15 = 0X71
    HELP = 0X72
    HOME = 0X73
    PAGE_UP = 0X74
    FORWARD_DELETE = 0X75
    F4 = 0X76
    END = 0X77
    F2 = 0X78
    PAGE_DOWN = 0X79
    F1 = 0X7A
    LEFT_ARROW = 0X7B
    RIGHT_ARROW = 0X7C
    DOWN_ARROW = 0X7D
    UP_ARROW = 0X7E


class Keystroke:
    """Describes a keystroke.

    Do not create instances of this class. They will be passed to you when you
    use a :class:`KeystrokeMonitor`.
    """

    class Action(enum.Enum):
        """Type of keyboard event."""
        NA = 0  #: Advanced keyboard monitoring is not enabled. Otherwise, this is the same as KEY_DOWN.
        KEY_DOWN = 1  #: A non-modifier was pressed.
        KEY_UP = 2  #: A non-modifier was released.
        FLAGS_CHANGED = 3  #: Only modifiers changed

    def __init__(self, notification):
        self.__characters = notification.characters
        self.__characters_ignoring_modifiers = (
            notification.charactersIgnoringModifiers)
        self.__modifiers = notification.modifiers
        self.__key_code = notification.keyCode
        self.__action = Keystroke.Action.NA
        if notification.HasField("action"):
            if notification.action == iterm2.api_pb2.KeystrokeNotification.Action.Value("KEY_DOWN"):
                self.__action = Keystroke.Action.KEY_DOWN
            elif notification.action == iterm2.api_pb2.KeystrokeNotification.Action.Value("KEY_UP"):
                self.__action = Keystroke.Action.KEY_UP
            elif notification.action == iterm2.api_pb2.KeystrokeNotification.Action.Value("FLAGS_CHANGED"):
                self.__action = Keystroke.Action.FLAGS_CHANGED

    def __repr__(self):
        info = (
            "chars={}, charsIgnoringModifiers={}, " +
            "modifiers={}, keyCode={}").format(
                self.characters,
                self.characters_ignoring_modifiers,
                self.modifiers,
                self.keycode)
        if self.__action == Keystroke.Action.KEY_DOWN:
            info = info + ", action=key-down"
        elif self.__action == Keystroke.Action.KEY_UP:
            info = info + ", action=key-up"
        elif self.__action == Keystroke.Action.FLAGS_CHANGED:
            info = info + ", action=flags-changed"
        return f'Keystroke({info})'

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
    def modifiers(self) -> typing.List[Modifier]:
        """The modifiers that were pressed.

        :returns: A list of :class:`Modifier` objects."""
        return list(map(Modifier, self.__modifiers))

    @property
    def keycode(self) -> Keycode:
        """The ANSI keycode that was pressed.

        :returns: A :class:`Keycode` object."""
        return Keycode(self.__key_code)

    @property
    def action(self) -> Action:
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
    def __init__(self):
        self.__required_modifiers = []
        self.__forbidden_modifiers = []
        self.__keycodes = []
        self.__characters = []
        self.__characters_ignoring_modifiers = []

    @property
    def required_modifiers(self) -> typing.List[Modifier]:
        """List of modifiers that are required to match the pattern.

        A list of type :class:`Modifier`.
        """
        return self.__required_modifiers

    @required_modifiers.setter
    def required_modifiers(self, value: typing.List[Modifier]):
        self.__required_modifiers = value

    @property
    def forbidden_modifiers(self) -> typing.List[Modifier]:
        """
        List of modifiers whose presence prevents the pattern from being
        matched.

        A list of type :class:`Modifier`.
        """
        return self.__forbidden_modifiers

    @forbidden_modifiers.setter
    def forbidden_modifiers(self, value: typing.List[Modifier]):
        self.__forbidden_modifiers = value

    @property
    def keycodes(self) -> typing.List[Keycode]:
        """List of keycodes that match the pattern.

        The pattern matches if the modifier constraints are satisfied and a
        keystroke has any of these keycodes.

        A list of type :class:`Keycode`."""
        return self.__keycodes

    @keycodes.setter
    def keycodes(self, value: typing.List[Keycode]):
        self.__keycodes = value

    @property
    def characters(self) -> typing.List[str]:
        """List of strings. Each string has a character.

        The pattern matches if the modifier constraints are satisfied and a
        keystroke has any of these characters.
        """
        return self.__characters

    @characters.setter
    def characters(self, value: typing.List[str]):
        self.__characters = value

    @property
    def characters_ignoring_modifiers(self) -> typing.List[str]:
        """List of strings. Each string has a character.

        The pattern matches if the modifier constraints are satisfied and a
        keystroke has any of these characters, ignoring modifiers.

        "Ignoring modifiers" mostly means ignoring modifiers other than Shift.
        It has a lot of surprising edge cases which Apple did not document, so
        experiment to find how it works.
        """
        return self.__characters_ignoring_modifiers

    @characters_ignoring_modifiers.setter
    def characters_ignoring_modifiers(self, value: typing.List[str]):
        self.__characters_ignoring_modifiers = value

    def to_proto(self):
        """Creates a protobuf for this pattern."""
        # pylint: disable=no-member
        proto = iterm2.api_pb2.KeystrokePattern()
        proto.required_modifiers.extend(
            list(
                map(lambda x: x.value, self.__required_modifiers)))
        proto.forbidden_modifiers.extend(
            list(
                map(lambda x: x.value, self.__forbidden_modifiers)))
        proto.keycodes.extend(list(map(lambda x: x.value, self.__keycodes)))
        proto.characters.extend(self.__characters)
        proto.characters_ignoring_modifiers.extend(
            self.__characters_ignoring_modifiers)
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
            connection: iterm2.connection.Connection,
            session: typing.Union[None, str] = None,
            advanced: typing.Optional[bool] = False):
        self.__connection = connection
        self.__session = session
        if advanced:
            iterm2.capabilities.check_supports_advanced_key_notifications(connection)
        self.__advanced = advanced
        self.__token = None
        self.__queue: asyncio.Queue = asyncio.Queue()

    async def __aenter__(self):
        # pylint: disable=unused-argument
        async def callback(connection, notification):
            await self.__queue.put(notification)
        # pylint: enable=unused-argument
        self.__token = (
            await iterm2.notifications.
            async_subscribe_to_keystroke_notification(
                self.__connection,
                callback,
                self.__session,
                self.__advanced))
        return self

    async def async_get(self) -> Keystroke:
        """Wait for and return the next keystroke."""
        notification = await self.__queue.get()
        return Keystroke(notification)

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.__connection, self.__token)
        except iterm2.notifications.SubscriptionException:
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
            connection: iterm2.connection.Connection,
            patterns: typing.List[KeystrokePattern],
            session: typing.Union[None, str] = None):
        self.__connection = connection
        self.__session = session
        self.__patterns = patterns
        self.__token = None

    async def __aenter__(self):
        self.__token = await iterm2.notifications.async_filter_keystrokes(
            self.__connection,
            self.__patterns,
            self.__session)
        return self

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.__connection, self.__token)
        except iterm2.notifications.SubscriptionException:
            pass
