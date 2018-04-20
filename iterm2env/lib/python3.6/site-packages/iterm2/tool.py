import iterm2.rpc

async def register_web_view_tool(connection, display_name, identifier, reveal_if_already_registered, url):
  print("Sending rpc..")
  result = await iterm2.rpc.register_web_view_tool(connection, display_name, identifier, reveal_if_already_registered, url)
  print("Processing result")
  status = result.register_tool_response.status
  if status == iterm2.api_pb2.RegisterToolResponse.Status.Value("OK"):
    return result
  else:
    raise iterm2.rpc.RPCException(result.register_tool_response)

