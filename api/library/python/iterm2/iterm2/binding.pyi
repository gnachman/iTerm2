from collections.abc import Callable, Iterable, Mapping
from enum import Enum
from typing import Any, TypeAlias

from .connection import Connection
from .keyboard import Keycode, Modifier
from .mainmenu import MenuItemIdentifier

_BindingParam: TypeAlias = (
    str
    | MenuItemIdentifier
    | PasteConfiguration
    | MoveSelectionUnit
    | SnippetIdentifier
)

def NoParamConstructor(param: object) -> str: ...
def MenuItemIdentifierConstructor(param: str) -> MenuItemIdentifier: ...
def PasteConfigurationConstructor(param: str | None) -> PasteConfiguration: ...

class PasteConfiguration:
    class TabTransform(Enum):
        NONE = 0
        CONVERT_TO_SPACES = 1
        ESCAPE_WITH_CONTROL_V = 2

    def __init__(
        self,
        base64: bool,
        wait_for_prompts: bool,
        tab_transform: TabTransform,
        tab_stop_size: int,
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
        substitution: str,
    ) -> None: ...
    @property
    def base64(self) -> bool: ...
    @base64.setter
    def base64(self, value: bool) -> None: ...
    @property
    def wait_for_prompts(self) -> bool: ...
    @wait_for_prompts.setter
    def wait_for_prompts(self, value: bool) -> None: ...
    @property
    def tab_transform(self) -> TabTransform: ...
    @tab_transform.setter
    def tab_transform(self, value: TabTransform) -> None: ...
    @property
    def tab_stop_size(self) -> int: ...
    @tab_stop_size.setter
    def tab_stop_size(self, value: int) -> None: ...
    @property
    def delay(self) -> float: ...
    @delay.setter
    def delay(self, value: float) -> None: ...
    @property
    def chunk_size(self) -> int: ...
    @chunk_size.setter
    def chunk_size(self, value: int) -> None: ...
    @property
    def convert_newlines(self) -> bool: ...
    @convert_newlines.setter
    def convert_newlines(self, value: bool) -> None: ...
    @property
    def remove_newlines(self) -> bool: ...
    @remove_newlines.setter
    def remove_newlines(self, value: bool) -> None: ...
    @property
    def convert_unicode_punctuation(self) -> bool: ...
    @convert_unicode_punctuation.setter
    def convert_unicode_punctuation(self, value: bool) -> None: ...
    @property
    def escape_for_shell(self) -> bool: ...
    @escape_for_shell.setter
    def escape_for_shell(self, value: bool) -> None: ...
    @property
    def remove_controls(self) -> bool: ...
    @remove_controls.setter
    def remove_controls(self, value: bool) -> None: ...
    @property
    def bracket_allowed(self) -> bool: ...
    @bracket_allowed.setter
    def bracket_allowed(self, value: bool) -> None: ...
    @property
    def use_regex_substitution(self) -> bool: ...
    @use_regex_substitution.setter
    def use_regex_substitution(self, value: bool) -> None: ...
    @property
    def regex(self) -> str: ...
    @regex.setter
    def regex(self, value: str) -> None: ...
    @property
    def substitution(self) -> str: ...
    @substitution.setter
    def substitution(self, value: str) -> None: ...

class MoveSelectionUnit(Enum):
    CHAR = 0
    WORD = 1
    LINE = 2
    MARK = 3
    BIG_WORD = 4

def MoveSelectionUnitConstructor(value: str) -> MoveSelectionUnit: ...

class SnippetIdentifier:
    def __init__(self, value: str | dict[str, Any]) -> None: ...

def parse_binding_param(action: BindingAction, param: Any) -> _BindingParam: ...
def get_constructor(
    action: BindingAction,
) -> Callable[[Any], _BindingParam] | None: ...

class BindingAction(Enum):
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

def decode_key_binding(key: str, obj: Mapping[str, Any]) -> KeyBinding: ...

class KeyBinding:
    def __init__(
        self,
        character: int,
        modifiers: Iterable[Modifier],
        keycode: Keycode | None,
        action: BindingAction,
        param: _BindingParam,
        version: int | None,
        label: str | None,
    ) -> None: ...
    def __eq__(self, other: object) -> bool: ...
    @property
    def encode(self) -> dict[str, Any]: ...
    @property
    def keycode(self) -> Keycode | None: ...
    @property
    def character(self) -> int: ...
    @property
    def modifiers(self) -> list[Modifier]: ...
    @property
    def action(self) -> BindingAction: ...
    @property
    def param(self) -> _BindingParam: ...
    @property
    def key(self) -> str: ...

GLOBAL_KEY_MAP_USER_DEFAULTS_KEY: str

async def async_get_global_key_bindings(
    connection: Connection,
) -> list[KeyBinding]: ...
async def async_set_global_key_bindings(
    connection: Connection, bindings: Iterable[KeyBinding]
) -> None: ...
