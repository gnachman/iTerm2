"""Provides information about the shell prompt."""
import asyncio
import enum
import typing

import iterm2.api_pb2
import iterm2.capabilities
import iterm2.connection
import iterm2.notifications
import iterm2.rpc

class PromptState(enum.Enum):
    """Describes the states that a command prompt can take."""
    UNKNOWN = -1  #: This version of iTerm2 does not report prompt state (you should upgrade)
    EDITING = 0  #: User is editing the command at the prompt
    RUNNING = 1  #: The last entered command is still executing, and has not finished yet.
    FINISHED = 3  #: The last entered command has finished but there hasn't been a new prompt yet (rare).


class Prompt:
    """Describes a command prompt.

    Shell Integration must be installed for this to work properly.  Do not
    construct this object yourself. Use :func:`~async_get_last_prompt` to get
    an instance.
    """
    def __init__(self, proto):
        self.__proto = proto

    @property
    def prompt_range(self) -> iterm2.util.CoordRange:
        """Gives the :class:`~iterm2.util.CoordRange` of a shell prompt."""
        return iterm2.util.CoordRange.from_proto(self.__proto.prompt_range)

    @property
    def command_range(self) -> iterm2.util.CoordRange:
        """
        Gives the :class:`~iterm2.util.CoordRange` of the command following the
        shell prompt.
        """
        return iterm2.util.CoordRange.from_proto(self.__proto.command_range)

    @property
    def output_range(self) -> iterm2.util.CoordRange:
        """
        Gives the :class:`~iterm2.util.CoordRange` of the output of a command
        following a shell prompt.
        """
        return iterm2.util.CoordRange.from_proto(self.__proto.output_range)

    @property
    def working_directory(self) -> typing.Union[None, str]:
        """Returns the working directory at the time the prompt was printed."""
        return self.__proto.working_directory

    @property
    def command(self) -> typing.Union[None, str]:
        """Returns the command entered at the prompt."""
        return self.__proto.command

    @property
    def state(self) -> PromptState:
        """Returns the state of this command prompt."""
        if not self.__proto.HasField("prompt_state"):
            return PromptState.UNKNOWN
        return PromptState(self.__proto.prompt_state)

    @property
    def unique_id(self) -> typing.Optional[str]:
        """Returns the unique ID of this command prompt.

        Will be None if not available because the version of iTerm2 is too
        old to report it."""
        if self.__proto.HasField("unique_prompt_id"):
            return self.__proto.unique_prompt_id
        return None

async def async_get_last_prompt(
        connection: iterm2.connection.Connection,
        session_id: str) -> typing.Union[None, Prompt]:
    """
    Fetches info about the last prompt in a session.

    :param connection: The connection to iTerm2.
    :param session_id: The session ID for which to fetch the most recent
        prompt.

    :returns: The prompt if one exists, or else `None`.

    :throws: :class:`RPCException` if something goes wrong.
    """
    response = await iterm2.rpc.async_get_prompt(connection, session_id)
    status = response.get_prompt_response.status
    # pylint: disable=no-member
    if status == iterm2.api_pb2.GetPromptResponse.Status.Value("OK"):
        return Prompt(response.get_prompt_response)
    if status == iterm2.api_pb2.GetPromptResponse.Status.Value(
            "PROMPT_UNAVAILABLE"):
        return None
    raise iterm2.rpc.RPCException(
        iterm2.api_pb2.GetPromptResponse.Status.Name(status))

async def async_get_prompt_by_id(
        connection: iterm2.connection.Connection,
        session_id: str,
        prompt_unique_id: str) -> typing.Optional[Prompt]:
    """
    Fetches a Prompt by its unique ID.

    :param connection: The connection to iTerm2.
    :param session_id: The Session ID the prompt belongs to.
    :param prompt_unique_id: The unique ID of the prompt.

    :returns: The prompt if one exists or else `None`.

    :throws: :class:`RPCException` if something goes wrong.
    """
    iterm2.capabilities.check_supports_prompt_id(connection)
    response = await iterm2.rpc.async_get_prompt(
        connection, session_id, prompt_unique_id)
    status = response.get_prompt_response.status
    # pylint: disable=no-member
    if status == iterm2.api_pb2.GetPromptResponse.Status.Value("OK"):
        return Prompt(response.get_prompt_response)
    if status == iterm2.api_pb2.GetPromptResponse.Status.Value(
            "PROMPT_UNAVAILABLE"):
        return None
    raise iterm2.rpc.RPCException(
        iterm2.api_pb2.GetPromptResponse.Status.Name(status))

async def async_list_prompts(
    connection: iterm2.connection.Connection,
    session_id: str,
    first: typing.Optional[str] = None,
    last: typing.Optional[str] = None) -> typing.Optional[Prompt]:
    """
    Fetches a list of prompt unique IDs in a session.

    :param connection: The connection to iTerm2.
    :param session_id: The Session ID the prompt belongs to.
    :param first: If not None, list no prompts before the one with
         this unique ID.
    :param last: If not None, list no prompts after the one with
         this unique ID.
    :returns: List of prompt IDs.

    :throws: :class:`RPCException` if something goes wrong.
    """
    iterm2.capabilities.check_supports_prompt_id(connection)
    response = await iterm2.rpc.async_list_prompts(
        connection, session_id, first, last)
    status = response.list_prompts_response.status
    # pylint: disable=no-member
    if status == iterm2.api_pb2.ListPromptsResponse.Status.Value("OK"):
        return response.list_prompts_response.unique_prompt_id

    raise iterm2.rpc.RPCException(
        iterm2.api_pb2.GetPromptResponse.Status.Name(status))

class PromptMonitor:
    """
    An asyncio context manager to watch for changes to the prompt.

    This requires shell integration or prompt-detecting triggers to be
    installed for prompt detection.

    Note: Older versions of the runtime do not support modes other than PROMPT.
    Attempting to use a mode other than PROMPT when connected to a too-old
    version of iTerm2 will result in an exception telling the user to upgrade.

    :param connection: The :class:`~iterm2.connection.Connection` to use.
    :param session_id: The string session ID to monitor.

    Example:

      .. code-block:: python

          async with iterm2.PromptMonitor(
              connection, my_session.session_id) as mon:
                  while True:
                      await mon.async_get()
                      DoSomething()
    """
    class Mode(enum.Enum):
        """The mode for a prompt monitor."""

        # pylint: disable=line-too-long
        PROMPT = iterm2.api_pb2.PromptMonitorMode.Value("PROMPT")  #: Notify when prompt detected
        COMMAND_START = iterm2.api_pb2.PromptMonitorMode.Value("COMMAND_START")  #: Notify when a command begins execution
        COMMAND_END = iterm2.api_pb2.PromptMonitorMode.Value("COMMAND_END")  #: Notify when a command finishes execution
        # pylint: enable=line-too-long

    def __init__(
            self,
            connection: iterm2.connection.Connection,
            session_id: str,
            modes: typing.Optional[typing.List[Mode]] = None):
        if modes is None:
            modes = [PromptMonitor.Mode.PROMPT]
        self.connection = connection
        self.session_id = session_id
        self.__modes = modes
        self.__token = None
        self.__queue: asyncio.Queue = asyncio.Queue(
            loop=asyncio.get_event_loop())
        if (modes != [PromptMonitor.Mode.PROMPT] and
                not iterm2.capabilities.supports_prompt_monitor_modes(
                    connection)):
            raise iterm2.capabilities.AppVersionTooOld(
                "This version of iTerm2 is too old to handle the " +
                "requested prompt monitor modes (only PROMPT is " +
                "supported in this version). You should upgrade to " +
                "run this script.")

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a new prompt is shown."""
            await self.__queue.put(message)

        self.__token = (
            await iterm2.notifications.async_subscribe_to_prompt_notification(
                self.connection,
                callback,
                self.session_id,
                list(map(lambda x: x.value, self.__modes))))
        return self

    async def async_get(
            self,
            include_id: bool = False) -> typing.Union[
                typing.Tuple['PromptMonitor.Mode', typing.Any],
                typing.Tuple['PromptMonitor.Mode', typing.Any, typing.Optional[str]]]:
        """Blocks until a new shell prompt is received.

        Note: Older versions of the runtime that do not support modes other
        than PROMPT always return None.

        :param include_id: If True, return a triple where the last value is the
            prompt's unique ID if available or None otherwise.

        :returns: A tuple of (PROMPT,Optional[Prompt]), (COMMAND_START,Str), or
            (COMMAND_END,Int) where the Str gives the command being run and the
            Int gives the exit status of the command. Older versions of iTerm2 will
            not provide a Prompt object when the first value is PROMPT."""
        triple = await self._async_get()
        if include_id:
            return triple
        return (triple[0], triple[1])

    async def _async_get(self) -> typing.Tuple['PromptMonitor.Mode', typing.Any]:
        message = await self.__queue.get()
        if not iterm2.capabilities.supports_prompt_monitor_modes(
                self.connection):
            return (PromptMonitor.Mode.PROMPT, None, None)
        which = message.WhichOneof('event')
        if which == 'prompt' or which is None:
            if message.prompt.HasField('prompt'):
                prompt = Prompt(message.prompt.prompt)
                return (PromptMonitor.Mode.PROMPT, prompt, message.unique_prompt_id)
            else:
                return (PromptMonitor.Mode.PROMPT, None, message.unique_prompt_id)
        if which == 'command_start':
            return (PromptMonitor.Mode.COMMAND_START,
                    message.command_start.command, message.unique_prompt_id)
        if which == 'command_end':
            return (PromptMonitor.Mode.COMMAND_END, message.command_end.status,
                message.unique_prompt_id)
        raise iterm2.rpc.RPCException(
            f'Unexpected oneof in prompt notification: {message}')

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.connection, self.__token)
        except iterm2.notifications.SubscriptionException:
            pass
