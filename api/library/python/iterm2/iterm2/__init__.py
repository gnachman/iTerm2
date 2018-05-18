"""
The iTerm2 module provides a Python interface for controlling iTerm2.
"""
from iterm2.app import async_get_app, CreateWindowException, SavedArrangementException, App
from iterm2.notifications import async_unsubscribe, async_subscribe_to_new_session_notification, async_subscribe_to_keystroke_notification, async_subscribe_to_screen_update_notification, async_subscribe_to_prompt_notification, async_subscribe_to_location_change_notification, async_subscribe_to_custom_escape_sequence_notification, async_subscribe_to_terminate_session_notification, async_subscribe_to_layout_change_notification, async_subscribe_to_focus_change_notification
from iterm2.profile import Profile, Color, PartialProfile, BadGUIDException
from iterm2.session import SplitPaneException, Splitter, Session, InvalidSessionId
from iterm2.transaction import Transaction
from iterm2.tab import Tab
from iterm2.tool import async_register_web_view_tool
from iterm2.util import frame_str, size_str
from iterm2.window import CreateTabException, SetPropertyException, GetPropertyException, SavedArrangementException, Window
from iterm2._version import __version__
from iterm2.connection import Connection
