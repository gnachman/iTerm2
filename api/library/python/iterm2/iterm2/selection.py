"""Provides interfaces for interacting with selected text regions."""
import enum
import iterm2.api_pb2
import iterm2.connection
import iterm2.screen
import iterm2.util
import itertools
from operator import itemgetter
import typing

class SelectionMode(enum.Enum):
    """Enumerated list of modes for selecting text."""
    CHARACTER = 0  #: character-by-character selection
    WORD = 1  #: word-by-word selection
    LINE = 2  #: row-by-row selection
    SMART = 3  #: smart selection
    BOX = 4  #: rectangular region
    WHOLE_LINE = 5  #: entire wrapped lines, which could occupy many rows

    @staticmethod
    def fromProtoValue(p):
        global MODE_MAP
        return MODE_MAP[p]

    @staticmethod
    def toProtoValue(p):
        global INVERSE_MODE_MAP
        return INVERSE_MODE_MAP[p]

class SubSelection:
    """Describes a continguous block of selected characters.

    :param windowedCoordRange: A :class:`~iterm2.util.WindowedCoordRange` describing the range.
    :param mode: A :class:`SelectionMode` describing how the selection is interpreted and extended.
    :param connected: If true, no newline exists between this and the next sub-selection.
    """
    def __init__(
            self,
            windowedCoordRange: iterm2.util.WindowedCoordRange,
            mode:SelectionMode,
            connected: bool):
        self.__windowedCoordRange = windowedCoordRange
        self.__mode = mode
        self.__connected = connected

    @property
    def windowedCoordRange(self) -> iterm2.util.WindowedCoordRange:
        return self.__windowedCoordRange

    @property
    def mode(self) -> SelectionMode:
        return self.__mode

    @property
    def proto(self):
        p = iterm2.api_pb2.SubSelection()
        p.windowed_coord_range.CopyFrom(self.__windowedCoordRange.proto)
        p.selection_mode = SelectionMode.toProtoValue(self.__mode)
        return p

    @property
    def connected(self) -> bool:
        return self.__connected

    async def async_get_string(self, connection: iterm2.connection.Connection, session_id: str) -> str:
        """Gets the text belonging to this subselection.

        :param connection: The connection to iTerm2.
        :param session_id: The ID of the session for which to look up the selected text.
        """
        result = await iterm2.rpc.async_get_screen_contents(
            connection,
            session_id,
            self.__windowedCoordRange)
        if result.get_buffer_response.status == iterm2.api_pb2.GetBufferResponse.Status.Value("OK"):
            screenContents = iterm2.screen.ScreenContents(result.get_buffer_response)
            s = ""
            wcr = screenContents.windowed_coord_range
            i = 0
            while i < screenContents.number_of_lines:
                line = screenContents.line(i)
                i += 1
                s += line.string
                if line.hard_eol:
                    s += "\n"
            return s
        else:
            raise iterm2.rpc.RPCException(iterm2.api_pb2.GetBufferResponse.Status.Name(result.get_buffer_response.status))

    def enumerateRanges(self, callback):
        if self.__windowedCoordRange.hasWindow:
            right = self.__windowedCoordRange.right
            startX = self.__windowedCoordRange.start.x
            y = self.__windowedCoordRange.coordRange.start.y
            while y < self.__windowedCoordRange.coordRange.end.y:
                callback(iterm2.util.CoordRange(
                    iterm2.util.Point(startX, y),
                    iterm2.util.Point(right, y)))
                startX = self.__windowedCoordRange.left

                y += 1

            callback(iterm2.util.CoordRange(
                iterm2.util.Point(
                    startX,
                    self.__windowedCoordRange.coordRange.end.y),
                iterm2.util.Point(
                    self.__windowedCoordRange.end.x,
                    self.__windowedCoordRange.coordRange.end.y)))
        else:
            callback(self.__windowedCoordRange.coordRange)

class Selection:
    """A collection of :class:`SubSelection` objects, describing all the selections in a session.

    :param subSelections: An array of :class:`SubSelection` objects.
    """
    def __init__(self, subSelections: typing.List[SubSelection]):
        self.__subSelections = subSelections

    @property
    def subSelections(self) -> typing.List[SubSelection]:
        return self.__subSelections

    async def _async_get_content_in_range(self, connection, session_id, coordRange):
        result = await iterm2.rpc.async_get_screen_contents(
            connection,
            session_id,
            coordRange)
        if result.get_buffer_response.status == iterm2.api_pb2.GetBufferResponse.Status.Value("OK"):
            screenContents = iterm2.screen.ScreenContents(result.get_buffer_response)
            s = ""
            wcr = screenContents.windowed_coord_range
            i = 0
            while i < screenContents.number_of_lines:
                line = screenContents.line(i)
                i += 1
                s += line.string
                if line.hard_eol:
                    s += "\n"
            return s

    async def async_get_string(self, connection: iterm2.connection.Connection, session_id: str, width: int) -> str:
        """Returns the selected text.

        :param connection: The connection to iTerm2.
        :param session_id: The ID of the session for which to look up the selected text.
        :param width: The width (number of columns) of the session.
        """
        if len(self.__subSelections) == 1:
            return await self.__subSelections[0].async_get_string(connection, session_id)

        result = ""
        async def handleRange(coordRange, eol):
            content = await self._async_get_content_in_range(connection, session_id, coordRange)
            nonlocal result
            result += content
            if eol and not content.endswith("\n"):
                result += "\n"
        await self.async_enumerate_ranges(connection, session_id, width, handleRange)
        return result

    async def async_enumerate_ranges(self, connection, session_id, width, cb):
        """Gets the text belonging to each subselection and concatenates them with newlines.

        :param connection: A :class:`~iterm2.connection.Connection`.
        :param session_id: A string session ID.
        :param width: The width of the session
        :param cb: A function to call for each range, taking a WindowedCoordRange and a boolean which is true if there's a hard EOL at the end of the range.

        :returns: A string with the selected text.
        """
        if len(self.__subSelections) == 0:
            return

        # Ranges ending at connectors don't get a newline following.
        connectors = set()
        indexes = set()
        for outer in self.__subSelections:
            if outer.connected:
                thePosition = outer.windowedCoordRange.coordRange.end.x + outer.windowedCoordRange.coordRange.end.y * width;
                connectors |= {thePosition}

            theRange = iterm2.util.Range(0, 0)
            def handleRange(outerRange):
                nonlocal indexes
                nonlocal theRange
                theRange = iterm2.util.Range(
                        outerRange.start.x + outerRange.start.y * width,
                        outerRange.length(width));

                indexesToAdd = theRange.toSet
                indexesToRemove = set()
                def f(values):
                    i,x=values
                    return i-x
                # Iterate contiguous ranges
                indexes_of_interest = indexes.intersection(indexesToAdd)
                for k, g in itertools.groupby(enumerate(sorted(indexes_of_interest)), f):
                    # range exists in both indexes and theRange
                    values_in_range=map(itemgetter(1), g)
                    indexesToRemove |= set(values_in_range)
                    indexesToAdd -= set(values_in_range)
                indexes -= indexesToRemove
                indexes |= indexesToAdd

                # In multipart windowed ranges, add connectors for the endpoint of all but the last
                # range. Each enumerated range is on its own line.
                if (outer.windowedCoordRange.hasWindow and
                    outerRange.end == outer.windowedCoordRange.coordRange.end and
                    theRange.length > 0):
                    connectors |= {theRange.max}

            outer.enumerateRanges(handleRange)

        # the ranges may be out of order so put them in an array and then sort it.
        allRanges = []
        def f(values):
            i,x=values
            return i-x
        # Iterate contiguous ranges
        for k, g in itertools.groupby(enumerate(sorted(indexes)), f):
            # range exists in both indexes and theRange
            values_in_range=list(map(itemgetter(1), g))
            coordRange = iterm2.util.CoordRange(
                    iterm2.util.Point(
                        min(values_in_range) % width,
                        min(values_in_range) // width),
                    iterm2.util.Point(
                        max(values_in_range) % width,
                        max(values_in_range) // width))
            allRanges.append(coordRange)

        def rangeKey(r):
            return r.start.y * width + r.start.x
        sortedRanges = sorted(allRanges, key=rangeKey)
        for idx, theRange in enumerate(sortedRanges):
            endIndex = theRange.start.x + theRange.start.y * width + theRange.length(width)
            eol = (endIndex not in connectors) and idx + 1 < len(sortedRanges)
            stop = await cb(iterm2.util.WindowedCoordRange(theRange), eol)
            if stop:
                break


MODE_MAP = {
        iterm2.api_pb2.SelectionMode.Value("CHARACTER"): SelectionMode.CHARACTER,
        iterm2.api_pb2.SelectionMode.Value("WORD"): SelectionMode.WORD,
        iterm2.api_pb2.SelectionMode.Value("LINE"): SelectionMode.LINE,
        iterm2.api_pb2.SelectionMode.Value("SMART"): SelectionMode.SMART,
        iterm2.api_pb2.SelectionMode.Value("BOX"): SelectionMode.BOX,
        iterm2.api_pb2.SelectionMode.Value("WHOLE_LINE"): SelectionMode.WHOLE_LINE }

INVERSE_MODE_MAP = {v: k for k, v in MODE_MAP.items()}

