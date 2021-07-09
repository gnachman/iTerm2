"Abstractions for iTerm2 key bindings."

import enum
import json
import iterm2.keyboard
import iterm2.mainmenu
import iterm2.rpc
import typing

def NoParamConstructor(param):
    return ""


def MenuItemIdentifierConstructor(param):
    lines = param.split("\n")
    title = lines[0]
    if len(lines) > 1:
        identifier = lines[1]
    else:
        identifier = None
    return iterm2.MenuItemIdentifier(title, identifier)

def PasteConfigurationConstructor(param):
    if param is None:
        base64 = False
        wait_for_prompts = False
        tab_transform = PasteConfiguration.TabTransform.NONE
        tab_stop_size = False
        delay = 0.01
        chunk_size = 1024
        convert_newlines = False
        remove_newlines = False
        convert_unicode_punctuation = False
        escape_for_shell = False
        remove_controls = False
        bracket_allowed = True
        use_regex_substitution = False
        regex = ""
        substitution = ""
    else:
        root = json.loads(param)
        base64 = root['Base64']
        wait_for_prompts = root['WaitForPrompts']
        tab_transform = PasteConfiguration.TabTransform(root['TabTransform'])
        tab_stop_size = root['TabStopSize']
        delay = root['Delay']
        chunk_size = root['ChunkSize']
        convert_newlines = root['ConvertNewlines']
        remove_newlines = root['RemoveNewlines']
        convert_unicode_punctuation = root['ConvertUnicodePunctuation']
        escape_for_shell = root['EscapeForShell']
        remove_controls = root['RemoveControls']
        bracket_allowed = root['BracketAllowed']
        use_regex_substitution = root['UseRegexSubstitution']
        regex = root['Regex']
        substitution = root['Substitution']

    return PasteConfiguration(
        base64,
        wait_for_prompts,
        tab_transform,
        tab_stop_size,
        delay,
        chunk_size,
        convert_newlines,
        remove_newlines,
        convert_unicode_punctuation,
        escape_for_shell,
        remove_controls,
        bracket_allowed,
        use_regex_substitution,
        regex,
        substitution)

class PasteConfiguration:
    """Configuration parameters for pasting."""

    class TabTransform(enum.Enum):
        "How to transform tabs."
        NONE = 0
        CONVERT_TO_SPACES = 1
        ESCAPE_WITH_CONTROL_V = 2

    def __init__(
         self,
         base64: bool,
         wait_for_prompts: bool,
         tab_transform: 'TabTransform',
         tab_stop_size: bool,
         delay: float,
         chunk_size: int,
         convert_newlines: bool,
         remove_newlines: bool,
         convert_unicode_punctuation: bool,
         escape_for_shell: bool,
         remove_controls: bool,
         bracket_allowed: bool,
         use_regex_substitution: bool,
         regex: str,
         substitution: str):
        self.__base64 = base64
        self.__wait_for_prompts = wait_for_prompts
        self.__tab_transform = tab_transform
        self.__tab_stop_size = tab_stop_size
        self.__delay = delay
        self.__chunk_size = chunk_size
        self.__convert_newlines = convert_newlines
        self.__remove_newlines = remove_newlines
        self.__convert_unicode_punctuation = convert_unicode_punctuation
        self.__escape_for_shell = escape_for_shell
        self.__remove_controls = remove_controls
        self.__bracket_allowed = bracket_allowed
        self.__use_regex_substitution = use_regex_substitution
        self.__regex = regex
        self.__substitution = substitution


    def _encode(self) -> str:
        param = {
            'Base64': self.__base64,
            'WaitForPrompts': self.__wait_for_prompts,
            'TabTransform': self.__tab_transform.value,
            'TabStopSize': self.__tab_stop_size,
            'Delay': self.__delay,
            'ChunkSize': self.__chunk_size,
            'ConvertNewlines': self.__convert_newlines,
            'RemoveNewlines': self.__remove_newlines,
            'ConvertUnicodePunctuation': self.__convert_unicode_punctuation,
            'EscapeForShell': self.__escape_for_shell,
            'RemoveControls': self.__remove_controls,
            'BracketAllowed': self.__bracket_allowed,
            'UseRegexSubstitution': self.__use_regex_substitution,
            'Regex': self.__regex,
            'Substitution': self.__substitution
        }
        return json.dumps(param)

    @property
    def base64(self) -> bool:
        "Returns whether to base64-encode when pasting."
        return __base64

    @base64.setter
    def base64(self, value: bool):
        "Sets whether to base64-encode when pasting."
        self.__base64 = value

    @property
    def wait_for_prompts(self) -> bool:
        "Returns whether to wait for a shell prompt before pasting."
        return __wait_for_prompts

    @wait_for_prompts.setter
    def wait_for_prompts(self, value: bool):
        "Sets whether to wait for a shell prompt before pasting."
        self.__wait_for_prompts = value

    @property
    def tab_transform(self) -> 'TabTransform':
        "Returns how to convert tabs to strings when pasting."
        return __tab_transform

    @tab_transform.setter
    def tab_transform(self, value: 'TabTransform'):
        "Sets how to convert tabs to strings when pasting."
        self.__tab_transform = value

    @property
    def tab_stop_size(self) -> int:
        "When converting tabs to spaces, this gives the number of spaces per tab."
        return __tab_stop_size

    @tab_stop_size.setter
    def tab_stop_size(self, value: int):
        "When converting tabs to spaces, this gives the number of spaces per tab."
        self.__tab_stop_size = value

    @property
    def delay(self) -> float:
        "How long to wait between chunks (seconds)."
        return __delay

    @delay.setter
    def delay(self, value: float):
        "How long to wait between chunks (seconds)."
        self.__delay = value

    @property
    def chunk_size(self) -> bool:
        "Chunk size to send."
        return __chunk_size

    @chunk_size.setter
    def chunk_size(self, value: bool):
        "Chunk size to send."
        self.__chunk_size = value

    @property
    def convert_newlines(self) -> bool:
        "Convert CRLF and LF to CR?"
        return __convert_newlines

    @convert_newlines.setter
    def convert_newlines(self, value: bool):
        "Convert CRLF and LF to CR?"
        self.__convert_newlines = value

    @property
    def remove_newlines(self) -> bool:
        "Remove all newlines?"
        return __remove_newlines

    @remove_newlines.setter
    def remove_newlines(self, value: bool):
        "Remove all newlines?"
        self.__remove_newlines = value

    @property
    def convert_unicode_punctuation(self) -> bool:
        "Returns whether to convert non-ASCII puncutation to ASCII equivalents when pasting."
        return __convert_unicode_punctuation

    @convert_unicode_punctuation.setter
    def convert_unicode_punctuation(self, value: bool):
        "Sets whether to convert non-ASCII puncutation to ASCII equivalents when pasting."
        self.__convert_unicode_punctuation = value

    @property
    def escape_for_shell(self) -> bool:
        "Returns whether to escape control characters for input to a shell when pasting."
        return __escape_for_shell

    @escape_for_shell.setter
    def escape_for_shell(self, value: bool):
        "Sets whether to escape control characters for input to a shell when pasting."
        self.__escape_for_shell = value

    @property
    def remove_controls(self) -> bool:
        "Returns whether to remove control characters when pasting."
        return __remove_controls

    @remove_controls.setter
    def remove_controls(self, value: bool):
        "Sets whether to remove control characters when pasting."
        self.__remove_controls = value

    @property
    def bracket_allowed(self) -> bool:
        "Returns whether to allow bracketed paste."
        return __bracket_allowed

    @bracket_allowed.setter
    def bracket_allowed(self, value: bool):
        "Sets whether to allow bracketed paste."
        self.__bracket_allowed = value

    @property
    def use_regex_substitution(self) -> bool:
        "Returns whether to perform regular expression substitution. See regex and substitution."
        return __use_regex_substitution

    @use_regex_substitution.setter
    def use_regex_substitution(self, value: bool):
        "Sets whether to perform regular expression substitution. See regex and substitution."
        self.__use_regex_substitution = value

    @property
    def regex(self) -> bool:
        "The regular expression pattern to match. See use_regex_substitution."
        return __regex

    @regex.setter
    def regex(self, value: bool):
        "The regular expression pattern to match. See use_regex_substitution."
        self.__regex = value

    @property
    def substitution(self) -> bool:
        "Replaces matches found by regex. See use_regex_substitution."
        return __substitution

    @substitution.setter
    def substitution(self, value: bool):
        "Replaces matches found by regex. See use_regex_substitution."
        self.__substitution = value


class MoveSelectionUnit(enum.Enum):
    "Units by which the cursor can move when modifying a selection."
    CHAR = 0  #: One cell, or two if a double-width character is present.
    WORD = 1  #: Jump over alphanumerics.
    LINE = 2
    MARK = 3  #: Marks can be set manually or (more often) by shell integration.
    BIG_WORD = 4  #: Like WORD but includes punctuation characters.

    def _encode(self) -> int:
        return self.value


def MoveSelectionUnitConstructor(value: str) -> 'MoveSelectionUnit':
    return MoveSelectionUnit(int(value))

class SnippetIdentifier:
    def __init__(self, value: typing.Union[str, dict]):
        """Creates a SnippetIdentifier.

        :param value: Legacy prefs have a snippet title here. New identifiers
            have a dictionary of {'guid': 'unique identifier'}.
        """
        if isinstance(value, str):
            self.__title = value
            self.__guid = None
        else:
            self.__title = None
            self.__guid = value['guid']

    def _encode(self) -> typing.Union[str,dict]:
        if self.__title is None:
            return { 'guid': self.__guid }
        return self.__title


def parse_binding_param(action: 'BindingAction', param) -> typing.Union[None, iterm2.mainmenu.MenuItemIdentifier, PasteConfiguration, MoveSelectionUnit, SnippetIdentifier]:
    constructor = get_constructor(action)
    return constructor(param)


def get_constructor(action: 'BindingAction'):
    if action == BindingAction.NEXT_SESSION:
        return NoParamConstructor

    if action == BindingAction.NEXT_WINDOW:
        return NoParamConstructor

    if action == BindingAction.PREVIOUS_SESSION:
        return NoParamConstructor

    if action == BindingAction.PREVIOUS_WINDOW:
        return NoParamConstructor

    if action == BindingAction.SCROLL_END:
        return NoParamConstructor

    if action == BindingAction.SCROLL_HOME:
        return NoParamConstructor

    if action == BindingAction.SCROLL_LINE_DOWN:
        return NoParamConstructor

    if action == BindingAction.SCROLL_LINE_UP:
        return NoParamConstructor

    if action == BindingAction.SCROLL_PAGE_DOWN:
        return NoParamConstructor

    if action == BindingAction.SCROLL_PAGE_UP:
        return NoParamConstructor

    if action == BindingAction.ESCAPE_SEQUENCE:
        return str

    if action == BindingAction.HEX_CODE:
        return str

    if action == BindingAction.TEXT:
        return str

    if action == BindingAction.IGNORE:
        return NoParamConstructor

    if action == BindingAction.IR_BACKWARD:
        return NoParamConstructor

    if action == BindingAction.SEND_C_H_BACKSPACE:
        return NoParamConstructor

    if action == BindingAction.SEND_C_QM_BACKSPACE:
        return NoParamConstructor

    if action == BindingAction.SELECT_PANE_LEFT:
        return NoParamConstructor

    if action == BindingAction.SELECT_PANE_RIGHT:
        return NoParamConstructor

    if action == BindingAction.SELECT_PANE_ABOVE:
        return NoParamConstructor

    if action == BindingAction.SELECT_PANE_BELOW:
        return NoParamConstructor

    if action == BindingAction.DO_NOT_REMAP_MODIFIERS:
        return NoParamConstructor

    if action == BindingAction.TOGGLE_FULLSCREEN:
        return NoParamConstructor

    if action == BindingAction.REMAP_LOCALLY:
        return NoParamConstructor

    if action == BindingAction.SELECT_MENU_ITEM:
        return MenuItemIdentifierConstructor

    if action == BindingAction.NEW_WINDOW_WITH_PROFILE:
        return str

    if action == BindingAction.NEW_TAB_WITH_PROFILE:
        return str

    if action == BindingAction.SPLIT_HORIZONTALLY_WITH_PROFILE:
        return str

    if action == BindingAction.SPLIT_VERTICALLY_WITH_PROFILE:
        return str

    if action == BindingAction.NEXT_PANE:
        return NoParamConstructor

    if action == BindingAction.PREVIOUS_PANE:
        return NoParamConstructor

    if action == BindingAction.NEXT_MRU_TAB:
        return NoParamConstructor

    if action == BindingAction.MOVE_TAB_LEFT:
        return NoParamConstructor

    if action == BindingAction.MOVE_TAB_RIGHT:
        return NoParamConstructor

    if action == BindingAction.RUN_COPROCESS:
        return str

    if action == BindingAction.FIND_REGEX:
        return str

    if action == BindingAction.SET_PROFILE:
        return str

    if action == BindingAction.VIM_TEXT:
        return str

    if action == BindingAction.PREVIOUS_MRU_TAB:
        return NoParamConstructor

    if action == BindingAction.LOAD_COLOR_PRESET:
        return str

    if action == BindingAction.PASTE_SPECIAL:
        return PasteConfigurationConstructor

    if action == BindingAction.PASTE_SPECIAL_FROM_SELECTION:
        return PasteConfigurationConstructor

    if action == BindingAction.TOGGLE_HOTKEY_WINDOW_PINNING:
        return NoParamConstructor

    if action == BindingAction.UNDO:
        return NoParamConstructor

    if action == BindingAction.MOVE_END_OF_SELECTION_LEFT:
        return MoveSelectionUnitConstructor

    if action == BindingAction.MOVE_END_OF_SELECTION_RIGHT:
        return MoveSelectionUnitConstructor

    if action == BindingAction.MOVE_START_OF_SELECTION_LEFT:
        return MoveSelectionUnitConstructor

    if action == BindingAction.MOVE_START_OF_SELECTION_RIGHT:
        return MoveSelectionUnitConstructor

    if action == BindingAction.DECREASE_HEIGHT:
        return NoParamConstructor

    if action == BindingAction.INCREASE_HEIGHT:
        return NoParamConstructor

    if action == BindingAction.DECREASE_WIDTH:
        return NoParamConstructor

    if action == BindingAction.INCREASE_WIDTH:
        return NoParamConstructor

    if action == BindingAction.SWAP_PANE_LEFT:
        return NoParamConstructor

    if action == BindingAction.SWAP_PANE_RIGHT:
        return NoParamConstructor

    if action == BindingAction.SWAP_PANE_ABOVE:
        return NoParamConstructor

    if action == BindingAction.SWAP_PANE_BELOW:
        return NoParamConstructor

    if action == BindingAction.FIND_AGAIN_DOWN:
        return NoParamConstructor

    if action == BindingAction.FIND_AGAIN_UP:
        return NoParamConstructor

    if action == BindingAction.TOGGLE_MOUSE_REPORTING:
        return NoParamConstructor

    if action == BindingAction.INVOKE_SCRIPT_FUNCTION:
        return str

    if action == BindingAction.DUPLICATE_TAB:
        return NoParamConstructor

    if action == BindingAction.MOVE_TO_SPLIT_PANE:
        return NoParamConstructor

    if action == BindingAction.SEND_SNIPPET:
        return SnippetIdentifier

    return None

class BindingAction(enum.Enum):
    NEXT_SESSION = 0
    NEXT_WINDOW = 1
    PREVIOUS_SESSION = 2
    PREVIOUS_WINDOW = 3
    SCROLL_END = 4
    SCROLL_HOME = 5
    SCROLL_LINE_DOWN = 6
    SCROLL_LINE_UP = 7
    SCROLL_PAGE_DOWN = 8
    SCROLL_PAGE_UP = 9
    ESCAPE_SEQUENCE = 10
    HEX_CODE = 11
    TEXT = 12
    IGNORE = 13
    IR_BACKWARD = 15
    SEND_C_H_BACKSPACE = 16
    SEND_C_QM_BACKSPACE = 17
    SELECT_PANE_LEFT = 18
    SELECT_PANE_RIGHT = 19
    SELECT_PANE_ABOVE = 20
    SELECT_PANE_BELOW = 21
    DO_NOT_REMAP_MODIFIERS = 22
    TOGGLE_FULLSCREEN = 23
    REMAP_LOCALLY = 24
    SELECT_MENU_ITEM = 25
    NEW_WINDOW_WITH_PROFILE = 26
    NEW_TAB_WITH_PROFILE = 27
    SPLIT_HORIZONTALLY_WITH_PROFILE = 28
    SPLIT_VERTICALLY_WITH_PROFILE = 29
    NEXT_PANE = 30
    PREVIOUS_PANE = 31
    NEXT_MRU_TAB = 32
    MOVE_TAB_LEFT = 33
    MOVE_TAB_RIGHT = 34
    RUN_COPROCESS = 35
    FIND_REGEX = 36
    SET_PROFILE = 37
    VIM_TEXT = 38
    PREVIOUS_MRU_TAB = 39
    LOAD_COLOR_PRESET = 40
    PASTE_SPECIAL = 41
    PASTE_SPECIAL_FROM_SELECTION = 42
    TOGGLE_HOTKEY_WINDOW_PINNING = 43
    UNDO = 44
    MOVE_END_OF_SELECTION_LEFT = 45
    MOVE_END_OF_SELECTION_RIGHT = 46
    MOVE_START_OF_SELECTION_LEFT = 47
    MOVE_START_OF_SELECTION_RIGHT = 48
    DECREASE_HEIGHT = 49
    INCREASE_HEIGHT = 50
    DECREASE_WIDTH = 51
    INCREASE_WIDTH = 52
    SWAP_PANE_LEFT = 53
    SWAP_PANE_RIGHT = 54
    SWAP_PANE_ABOVE = 55
    SWAP_PANE_BELOW = 56
    FIND_AGAIN_DOWN = 57
    FIND_AGAIN_UP = 58
    TOGGLE_MOUSE_REPORTING = 59
    INVOKE_SCRIPT_FUNCTION = 60
    DUPLICATE_TAB = 61
    MOVE_TO_SPLIT_PANE = 62
    SEND_SNIPPET = 63

class KeyBinding:
    """A keyboard shortcut along with an action to perform and any extra
    info that configures the action.

    :param character: The code point of the character associated with the keypress.
    :param modifiers: List of modifier keys that must be pressed to activate the binding
    :param keycode: None or the keycode associated with the key.
    :param action: The action to perform.
    :param param: Action-specific data that configures the behavior.
    :param version: Generally this should be None. For actions that send text, use 1 to get newer escaping semantics (use vim-style escaping instead of only backslash + one of 'n', 'e', 'a', or 't').
    :param label: Label for touch bar actions. Set to None for non-touchbar bindings.
    """
    def __init__(
          self,
          character: int,
          modifiers: [iterm2.keyboard.Modifier],
          keycode: typing.Optional[iterm2.keyboard.Keycode],
          action: 'BindingAction',
          param,
          version: typing.Optional[int],
          label: typing.Optional[str]):
        self.__keycode = keycode
        self.__character = character
        self.__modifiers = 0
        for mod in modifiers:
            self.__modifiers = self.__modifiers | mod.to_cocoa()
        self.__action = action
        self.__parsed_param = param
        if isinstance(param, str):
            self.__encoded_param = param
        else:
            self.__encoded_param = param._encode()
        self.__version = version
        self.__label = label

    def __eq__(self, other):
        return (
             self.__keycode == other.__keycode and
             self.__character == other.__character and
             self.__modifiers == other.__modifiers and
             self.__action == other.__action and
             self.__encoded_param == other.__encoded_param and
             self.__version == other.__version and
             self.__label == other.__label)

    def __repr__(self):
        return f'[KeyBinding keycode={self.keycode} character={self.character} modifiers={self.modifiers} action={self.action} param={self.__parsed_param}] version={self.__version} label={self.__label}]'

    @staticmethod
    def _make(key: str, entry: dict):
        # Key can be one of:
        # 0xcharacter-0xmodifiers
        # 0xcharacter-0xmodifiers-0xkeycode
        keyParts = key.split("-")
        action = BindingAction(entry['Action'])
        if len(keyParts) < 3:
            keycode = None
        else:
            keycode = iterm2.keyboard.Keycode(int(keyParts[2], 16))
        character = int(keyParts[0], 16)
        modifiers = iterm2.keyboard.Modifier.from_cocoa(int(keyParts[1], 16))
        param = parse_binding_param(
                action,
                entry['Text'])
        return KeyBinding(character, modifiers, keycode, action, param, entry.get('Version', None), entry.get('Label', None))

    @property
    def keycode(self) -> typing.Optional[iterm2.keyboard.Keycode]:
        "None, or the keycode associated with the key."
        return self.__keycode

    @property
    def character(self) -> int:
        return self.__character

    @property
    def modifiers(self) -> typing.List['iterm2.keyboard.Modifier']:
        "List of modifier keys that must be pressed to activate the binding."
        return iterm2.keyboard.Modifier.from_cocoa(self.__modifiers)

    @property
    def action(self) -> 'BindingAction':
        "The action to perform."
        return self.__action

    @property
    def param(self) -> typing.Union[None, iterm2.mainmenu.MenuItemIdentifier, PasteConfiguration, MoveSelectionUnit, SnippetIdentifier]:
        "Action-specific data that configures the behavior."
        return self.__parsed_param

    @property
    def _key(self):
        base = hex(self.__character) + "-" + hex(self.__modifiers)
        if self.__keycode is None:
            return base
        return base + "-" + hex(self.__keycode.value)

    @property
    def _value(self) -> dict:
        result = { 'Action': self.action.value,
                   'Text': self.__encoded_param }
        if self.__version is not None:
            result['Version'] = self.__version
        if self.__label is not None:
            result['Label'] = self.__label
        return result

GLOBAL_KEY_MAP_USER_DEFAULTS_KEY = 'GlobalKeyMap'

async def async_get_global_key_bindings(connection: iterm2.connection.Connection) -> [KeyBinding]:
    """Fetches the global key binding.

    :param connection: The :class:`~iterm2.Connection` to use.

    :returns: A list of key bindings from Preferences > Keys.
    """
    proto = await iterm2.rpc.async_get_preference(connection, GLOBAL_KEY_MAP_USER_DEFAULTS_KEY)
    j = proto.preferences_response.results[0].get_preference_result.json_value
    raw = json.loads(j)
    result = []
    for k in raw:
        entry = raw[k]
        binding = KeyBinding._make(k, entry)
        result.append(binding)
    return result

async def async_set_global_key_bindings(connection: iterm2.connection.Connection, bindings: [KeyBinding]):
    """Sets the global key bindings.

    :param connection: The :class:`~iterm2.Connection` to use.
    :param bindings: The new bindings to use.
    """
    replacement = {}
    for binding in bindings:
        replacement[binding._key] = binding._value
    proto = await iterm2.rpc.async_set_preference(connection, GLOBAL_KEY_MAP_USER_DEFAULTS_KEY, json.dumps(replacement))
    status = proto.preferences_response.results[0].set_preference_result.status
    if status == iterm2.api_pb2.PreferencesResponse.Result.SetPreferenceResult.Status.Value("OK"):
        return
    raise iterm2.rpc.RPCException(
        iterm2.api_pb2.PreferencesResponse.Result.SetPreferenceResult.Status.Name(status))

