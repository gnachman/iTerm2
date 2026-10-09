from collections.abc import Iterable, Mapping, Sequence
from typing import Any

from . import api_pb2
from .connection import Connection
from .selection import Selection
from .util import Size, WindowedCoordRange

ACTIVATE_RAISE_ALL_WINDOWS: int
ACTIVATE_IGNORING_OTHER_APPS: int

class RPCException(Exception): ...

async def async_list_sessions(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_notification_request(
    connection: Connection,
    subscribe: bool,
    notification_type: api_pb2.NotificationType.ValueType,
    session: str | None = None,
    rpc_registration_request: api_pb2.RPCRegistrationRequest | None = None,
    keystroke_monitor_request: api_pb2.KeystrokeMonitorRequest | None = None,
    variable_monitor_request: api_pb2.VariableMonitorRequest | None = None,
    profile_change_request: api_pb2.ProfileChangeRequest | None = None,
    prompt_monitor_modes: Iterable[api_pb2.PromptMonitorMode.ValueType] | None = None,
    keystroke_filter_request: api_pb2.KeystrokeFilterRequest | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_send_text(
    connection: Connection, session: str, text: str, suppress_broadcast: bool
) -> api_pb2.ServerOriginatedMessage: ...
async def async_screenshot(
    connection: Connection, session: str
) -> api_pb2.ServerOriginatedMessage: ...
async def async_split_pane(
    connection: Connection,
    session: str | None,
    vertical: bool,
    before: bool,
    profile: str | None = None,
    profile_customizations: Mapping[str, str] | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_create_tab(
    connection: Connection,
    profile: str | None = None,
    window: str | None = None,
    index: int | None = None,
    command: str | None = None,
    profile_customizations: Mapping[str, str] | None = None,
    select: bool = True,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_screen_contents(
    connection: Connection,
    session: str | None,
    windowed_coord_range: WindowedCoordRange | None = None,
    style: bool = False,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_prompt(
    connection: Connection, session: str | None = None, prompt_id: str | None = None
) -> api_pb2.ServerOriginatedMessage: ...
async def async_list_prompts(
    connection: Connection, session: str, first: str | None, last: str | None
) -> api_pb2.ServerOriginatedMessage: ...
async def async_start_transaction(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_end_transaction(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_register_web_view_tool(
    connection: Connection,
    display_name: str,
    identifier: str,
    reveal_if_already_registered: bool,
    url: str,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_set_profile_property(
    connection: Connection,
    session_id: str | None,
    key: str,
    value: Any,
    guids: Iterable[str] | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_set_profile_property_json(
    connection: Connection,
    session_id: str | None,
    key: str,
    json_value: str,
    guids: Iterable[str] | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_set_profile_properties_json(
    connection: Connection,
    session_id: str | None,
    assignments: Iterable[Sequence[str]],
    guids: Iterable[str] | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_profile(
    connection: Connection, session: str | None = None, keys: Iterable[str] | None = None
) -> api_pb2.ServerOriginatedMessage: ...
async def async_set_property(
    connection: Connection,
    name: str,
    json_value: str,
    window_id: str | None = None,
    session_id: str | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_property(
    connection: Connection,
    name: str,
    window_id: str | None = None,
    session_id: str | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_inject(
    connection: Connection, data: bytes, sessions: Iterable[str]
) -> api_pb2.ServerOriginatedMessage: ...
async def async_activate(
    connection: Connection,
    select_session: bool,
    select_tab: bool,
    order_window_front: bool,
    session_id: str | None = None,
    tab_id: str | None = None,
    window_id: str | None = None,
    activate_app_opts: Sequence[int] | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_variable(
    connection: Connection,
    session_id: str | None = None,
    sets: Iterable[tuple[str, str]] | None = None,
    gets: Iterable[str] | None = None,
    tab_id: str | None = None,
    window_id: str | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_save_arrangement(
    connection: Connection, name: str, window_id: str | None = None
) -> api_pb2.ServerOriginatedMessage: ...
async def async_restore_arrangement(
    connection: Connection, name: str, window_id: str | None = None
) -> api_pb2.ServerOriginatedMessage: ...
async def async_list_arrangements(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_focus_info(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_list_profiles(
    connection: Connection,
    guids: Iterable[str] | None,
    properties: Iterable[str] | None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_send_rpc_result(
    connection: Connection, request_id: str, is_exception: bool, value: Any
) -> api_pb2.ServerOriginatedMessage: ...
async def async_restart_session(
    connection: Connection, session_id: str, only_if_exited: bool
) -> api_pb2.ServerOriginatedMessage: ...
async def async_menu_item(
    connection: Connection, identifier: str, query_only: bool
) -> api_pb2.ServerOriginatedMessage: ...
async def async_set_tab_layout(
    connection: Connection, tab_id: str, tree: api_pb2.SplitTreeNode
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_broadcast_domains(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_rpc_list_tmux_connections(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_rpc_send_tmux_command(
    connection: Connection, tmux_connection_id: str, command: str
) -> api_pb2.ServerOriginatedMessage: ...
async def async_rpc_set_tmux_window_visible(
    connection: Connection, tmux_connection_id: str, window_id: str, visible: bool
) -> api_pb2.ServerOriginatedMessage: ...
async def async_rpc_create_tmux_window(
    connection: Connection, tmux_connection_id: str, affinity: str | None = None
) -> api_pb2.ServerOriginatedMessage: ...
async def async_reorder_tabs(
    connection: Connection, assignments: Iterable[tuple[str, Iterable[str]]]
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_default_profile(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_set_default_profile(
    connection: Connection, guid: str
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_preference(
    connection: Connection, key: str
) -> api_pb2.ServerOriginatedMessage: ...
async def async_set_preference(
    connection: Connection, key: str, value: str
) -> api_pb2.ServerOriginatedMessage: ...
async def async_list_color_presets(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_color_preset(
    connection: Connection, name: str
) -> api_pb2.ServerOriginatedMessage: ...
async def async_get_selection(
    connection: Connection, session_id: str
) -> api_pb2.ServerOriginatedMessage: ...
async def async_set_selection(
    connection: Connection, session_id: str, selection: Selection
) -> api_pb2.ServerOriginatedMessage: ...
async def async_open_status_bar_component_popover(
    connection: Connection, identifier: str, session_id: str, html: str, size: Size
) -> api_pb2.ServerOriginatedMessage: ...
async def async_set_broadcast_domains(
    connection: Connection, list_of_list_of_session_ids: Iterable[Iterable[str]]
) -> api_pb2.ServerOriginatedMessage: ...
async def async_close(
    connection: Connection,
    sessions: Iterable[str] | None = None,
    tabs: Iterable[str] | None = None,
    windows: Iterable[str] | None = None,
    force: bool = False,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_invoke_function(
    connection: Connection,
    invocation: str,
    session_id: str | None = None,
    tab_id: str | None = None,
    window_id: str | None = None,
    timeout: float = -1,
    receiver: str | None = None,
) -> api_pb2.ServerOriginatedMessage: ...
async def async_invoke_method(
    connection: Connection, receiver: str, invocation: str, timeout: float
) -> Any: ...
async def async_invoke_app_function(
    connection: Connection, invocation: str, timeout: float = -1
) -> Any: ...
