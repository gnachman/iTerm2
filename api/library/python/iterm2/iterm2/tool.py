"""Provides functions to register toolbelt webivew tools."""

import iterm2.rpc

async def async_register_web_view_tool(connection,
                                       display_name,
                                       identifier,
                                       reveal_if_already_registered,
                                       url):
    """
    Registers a toolbelt tool that shows a webview.

    :param connection: A connected iterm2.connection.Connection.
    :param display_name: The name of the tool. User-visible.
    :param identifier: A unique ID that prevents duplicate registration.
    :param reveal_if_already_registered: Bool. If True, shows the tool on a duplicate registration
        attempt.
    :param url: The URL to show in the webview.

    :returns: iterm2.api_pb2.RegisterToolResponse on success

    :raises: iterm2.rpc.RPCException if something goes wrong
    """
    result = await iterm2.rpc.async_register_web_view_tool(
        connection,
        display_name,
        identifier,
        reveal_if_already_registered,
        url)
    status = result.register_tool_response.status
    if status == iterm2.api_pb2.RegisterToolResponse.Status.Value("OK"):
        return result
    else:
        raise iterm2.rpc.RPCException(result.register_tool_response)
