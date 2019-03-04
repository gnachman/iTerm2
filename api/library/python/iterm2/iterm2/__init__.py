"""
The iTerm2 module provides a Python interface for controlling iTerm2.
"""
from iterm2.alert import Alert

from iterm2.app import async_get_app, CreateWindowException, App, async_invoke_function, async_get_variable

from iterm2.arrangement import SavedArrangementException, Arrangement

from iterm2.broadcast import BroadcastDomain, async_set_broadcast_domains

from iterm2.color import Color, ColorSpace

from iterm2.colorpresets import ColorPreset, ListPresetsException, GetPresetException

from iterm2.connection import Connection, run_until_complete, run_forever

from iterm2.customcontrol import CustomControlSequenceMonitor

from iterm2.focus import FocusMonitor, FocusUpdateApplicationActive, FocusUpdateWindowChanged, FocusUpdateSelectedTabChanged, FocusUpdateActiveSessionChanged, FocusUpdate, FocusMonitor

from iterm2.lifecycle import SessionTerminationMonitor, LayoutChangeMonitor, NewSessionMonitor

from iterm2.mainmenu import MenuItemState, MainMenu, MenuItemException

from iterm2.keyboard import Modifier, Keycode, Keystroke, KeystrokePattern, KeystrokeMonitor, KeystrokeFilter

from iterm2.preferences import PreferenceKey, async_get_preference

from iterm2.profile import Profile, PartialProfile, BadGUIDException, LocalWriteOnlyProfile, BackgroundImageMode, CursorType, ThinStrokes, UnicodeNormalization, CharacterEncoding, OptionKeySends, InitialWorkingDirectory, IconMode, TitleComponents

from iterm2.prompt import PromptMonitor, async_get_last_prompt

from iterm2.registration import RPC, TitleProviderRPC, StatusBarRPC, Reference

from iterm2.screen import ScreenStreamer, LineContents, ScreenContents

from iterm2.selection import SelectionMode, SubSelection, Selection

from iterm2.session import SplitPaneException, Splitter, Session, InvalidSessionId

from iterm2.statusbar import StatusBarComponent, CheckboxKnob, StringKnob, PositiveFloatingPointKnob, ColorKnob

from iterm2.transaction import Transaction

from iterm2.tab import Tab

from iterm2.tmux import TmuxException, TmuxConnection, async_get_tmux_connections, async_get_tmux_connection_by_connection_id

from iterm2.tool import async_register_web_view_tool

from iterm2.util import frame_str, size_str, Size, Point, Frame, CoordRange, Range, WindowedCoordRange, async_wait_forever

from iterm2.window import CreateTabException, SetPropertyException, GetPropertyException, Window

from iterm2._version import __version__

from iterm2.rpc import RPCException

from iterm2.variables import VariableMonitor, VariableScopes

