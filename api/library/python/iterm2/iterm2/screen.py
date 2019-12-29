"""Provides access to screen contents."""
import asyncio
import typing

import iterm2.api_pb2
import iterm2.notifications
import iterm2.rpc
import iterm2.util


class LineContents:
    """Describes the contents of a line."""
    def __init__(self, proto):
        self.__proto = proto
        self.__offset_of_cell = [0]
        self.__length_of_cell = []
        offset = 0
        for cppc in proto.code_points_per_cell:
            for i in range(cppc.repeats):  # pylint: disable=unused-variable
                offset += cppc.num_code_points
                self.__offset_of_cell.append(offset)
                self.__length_of_cell.append(cppc.num_code_points)

    @property
    def string(self) -> str:
        """
        :returns: The line's contents as a string.
        """
        return self.__proto.text

    def string_at(self, x: int) -> str:  # pylint: disable=invalid-name
        """Returns the string of the cell at index `x`.

        :param x: The index to look up.
        :returns: A string giving the contents of the cell at that index, or
            empty string if none.
        """
        offset = self.__offset_of_cell[x]
        limit = offset + self.__length_of_cell[x]
        return self.__proto.text[offset:limit]

    @property
    def hard_eol(self) -> bool:
        """
        :returns: True if the line has a hard newline. If False, the text of a
            longer line wraps onto the next line."""
        return (
            # pylint: disable=no-member
            self.__proto.continuation ==
            iterm2.api_pb2.LineContents.Continuation.Value(
                "CONTINUATION_HARD_EOL"))


class ScreenContents:
    """Describes screen contents."""
    def __init__(self, proto):
        self.__proto = proto

    @property
    def windowed_coord_range(self) -> iterm2.util.WindowedCoordRange:
        """The line number of the first line in this object."""
        return iterm2.util.WindowedCoordRange(
            iterm2.util.CoordRange(
                iterm2.util.Point(
                    self.__proto.windowed_coord_range.coord_range.start.x,
                    self.__proto.windowed_coord_range.coord_range.start.y),
                iterm2.util.Point(
                    self.__proto.windowed_coord_range.coord_range.end.x,
                    self.__proto.windowed_coord_range.coord_range.end.y)),
            iterm2.util.Range(
                self.__proto.windowed_coord_range.columns.location,
                self.__proto.windowed_coord_range.columns.length))

    @property
    def number_of_lines(self) -> int:
        """The number of lines in this object."""
        return len(self.__proto.contents)

    def line(self, index: int) -> LineContents:
        """Returns the LineContents at the given index.

        :param index: should be at least 0 and less than `number_of_lines`.

        :returns: A :class:`LineContents` object.
        """
        return LineContents(self.__proto.contents[index])

    @property
    def cursor_coord(self) -> iterm2.util.Point:
        """Returns the location of the cursor.

        :returns: A :class:`~iterm2.Point`"""
        return iterm2.util.Point(self.__proto.cursor.x, self.__proto.cursor.y)

    @property
    def number_of_lines_above_screen(self) -> int:
        """
        Returns the number of lines before the screen including scrollback
        history and lines lost from the head of scrollback history.

        :returns: The number of lines ever received before the top line of the
            screen.
        """
        return self.__proto.num_lines_above_screen


class ScreenStreamer:
    """An asyncio context manager for monitoring the screen contents.

    You can use this to be notified when screen contents change. Optionally,
    you can receive the actual contents of the screen.

    Don't create this yourself. Use Session.get_screen_streamer() instead. See
    its docstring for more info."""
    def __init__(self, connection, session_id, want_contents=True):
        assert session_id != "all"
        self.connection = connection
        self.session_id = session_id
        self.want_contents = want_contents
        self.future = None
        self.token = None

    async def __aenter__(self):
        async def async_on_update(_connection, message):
            """Called on screen update. Saves the update message."""
            future = self.future
            if future is None:
                # Ignore reentrant calls
                return

            self.future = None
            if future is not None and not future.done():
                future.set_result(message)

        self.token = (
            await iterm2.notifications.
            async_subscribe_to_screen_update_notification(
                self.connection,
                async_on_update,
                self.session_id))
        return self

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.connection, self.token)
        except iterm2.notifications.SubscriptionException:
            pass

    async def async_get(self) -> typing.Union[None, ScreenContents]:
        """
        Blocks until the screen contents change.

        If this `ScreenStreamer` has been configured to provide screen
        contents, then they will be returned.

        :returns: A :class:`ScreenContents` (if so configured), otherwise
            `None`.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        future: asyncio.Future = asyncio.Future()
        self.future = future
        await self.future
        self.future = None

        if not self.want_contents:
            return None
        # pylint: disable=no-member
        result = await iterm2.rpc.async_get_screen_contents(
            self.connection,
            self.session_id,
            None)
        if (result.get_buffer_response.status == iterm2.
                api_pb2.GetBufferResponse.Status.Value("OK")):
            return ScreenContents(result.get_buffer_response)
        raise iterm2.rpc.RPCException(
            iterm2.api_pb2.GetBufferResponse.Status.Name(
                result.get_buffer_response.status))
