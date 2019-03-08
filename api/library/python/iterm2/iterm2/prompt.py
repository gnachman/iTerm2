"""Provides information about the shell prompt."""
import asyncio
import iterm2.api_pb2
import iterm2.connection
import iterm2.notifications
import iterm2.rpc
import typing

class Prompt:
    """Describes a command prompt.

    Shell Integration must be installed for this to work properly.
    """
    def __init__(self, proto):
        self.__proto = proto

    @property
    def prompt_range(self) -> iterm2.util.CoordRange:
        """Gives the :class:`~iterm2.util.CoordRange` of a shell prompt."""
        return iterm2.util.CoordRange.from_proto(self.__proto.prompt_range)

    @property
    def command_range(self) -> iterm2.util.CoordRange:
        """Gives the :class:`~iterm2.util.CoordRange` of the command following the shell prompt."""
        return iterm2.util.CoordRange.from_proto(self.__proto.command_range)

    @property
    def output_range(self) -> iterm2.util.CoordRange:
        """Gives the :class:`~iterm2.util.CoordRange` of the output of a command following a shell prompt."""
        return iterm2.util.CoordRange.from_proto(self.__proto.output_range)

    @property
    def working_directory(self) -> typing.Union[None, str]:
      """Returns the working directory at the time the prompt was printed."""
      return self.__proto.working_directory

    @property
    def command(self) -> typing.Union[None, str]:
      """Returns the command entered at the prompt."""
      return self.__proto.command

async def async_get_last_prompt(connection: iterm2.connection.Connection, session_id: str) -> typing.Union[None, Prompt]:
    """
    Fetches info about the last prompt in a session.

    :param connection: The connection to iTerm2.
    :param session_id: The session ID for which to fetch the most recent prompt.

    :returns: The prompt if one exists, or else `None`.

    :throws: :class:`RPCException` if something goes wrong.
    """
    response = await iterm2.rpc.async_get_prompt(connection, session_id)
    status = response.get_prompt_response.status
    if status == iterm2.api_pb2.GetPromptResponse.Status.Value("OK"):
        return Prompt(response.get_prompt_response)
    elif status == iterm2.api_pb2.GetPromptResponse.Status.Value("PROMPT_UNAVAILABLE"):
        return None
    else:
        raise iterm2.rpc.RPCException(iterm2.api_pb2.GetPromptResponse.Status.Name(status))

class PromptMonitor:
    """An asyncio context manager to watch for changes to the prompt.

    This requires shell integration or prompt-detecting triggers to be installed for prompt detection.

    :param connection: The :class:`~iterm2.connection.Connection` to use.
    :param session_id: The string session ID to monitor.

    Example:

      .. code-block:: python

          async with iterm2.PromptMonitor(connection, my_session.session_id) as mon:
              while True:
                  await mon.async_get()
                  DoSomething()
    """
    def __init__(self, connection: iterm2.connection.Connection, session_id: str):
        self.connection = connection
        self.session_id = session_id
        self.__queue: asyncio.Queue = asyncio.Queue(loop=asyncio.get_event_loop())

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a new prompt is shown."""
            await self.__queue.put(message)

        self.__token = await iterm2.notifications.async_subscribe_to_prompt_notification(
                self.connection,
                callback,
                self.session_id)
        return self

    async def async_get(self) -> None:
        """Blocks until a new shell prompt is received."""
        await self.__queue.get()

    async def __aexit__(self, exc_type, exc, _tb):
        await iterm2.notifications.async_unsubscribe(self.__connection, self.__token)
