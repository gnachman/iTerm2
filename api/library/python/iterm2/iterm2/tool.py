"""Provides functions to register toolbelt webivew tools."""
import iterm2.api_pb2
import iterm2.connection
import iterm2.rpc


async def async_register_web_view_tool(
        connection: iterm2.connection.Connection,
        display_name: str,
        identifier: str,
        reveal_if_already_registered: bool,
        url: str) -> None:
    """
    Registers a toolbelt tool that shows a webview.

    :param connection: The connection to iTerm2.
    :param display_name: The name of the tool. User-visible.
    :param identifier: A unique ID for this tool. Only one tool with a given
        identifier may be registered at a time.
    :param reveal_if_already_registered: If `True`, shows the tool on a
        duplicate registration attempt.
    :param url: The URL to show in the webview.

    :throws: :class:`~iterm2.RPCException` if something goes wrong

    .. seealso:: Example ":ref:`targeted_input_example`"
    """
    result = await iterm2.rpc.async_register_web_view_tool(
        connection,
        display_name,
        identifier,
        reveal_if_already_registered,
        url)
    status = result.register_tool_response.status
    # pylint: disable=no-member
    if status == iterm2.api_pb2.RegisterToolResponse.Status.Value("OK"):
        return None
    raise iterm2.rpc.RPCException(result.register_tool_response)
