import iterm2.rpc

async def register_web_view_tool(connection, display_name, identifier, reveal_if_already_registered, url):
  """
  Registers a toolbelt tool that shows a webview.

  connection: A connected iterm2.Connection.
  display_name: The name of the tool. User-visible.
  identifier: A unique ID that prevents duplicate registration.
  reveal_if_already_registered: Bool. If true, shows the tool on a duplicate registration attempt.
  url: The URL to show in the webview.

  Returns: iterm2.api_pb2.RegisterToolResponse on success

  Raises: iterm2.rpc.RPCException if something goes wrong
  """
  print("Sending rpc..")
  result = await iterm2.rpc.register_web_view_tool(connection, display_name, identifier, reveal_if_already_registered, url)
  print("Processing result")
  status = result.register_tool_response.status
  if status == iterm2.api_pb2.RegisterToolResponse.Status.Value("OK"):
    return result
  else:
    raise iterm2.rpc.RPCException(result.register_tool_response)

