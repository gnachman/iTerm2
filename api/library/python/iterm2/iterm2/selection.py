"""Provides interfaces for interacting with selected text regions."""

from __future__ import annotations

import enum
import itertools
from collections.abc import Awaitable, Callable
from operator import itemgetter
from typing import TYPE_CHECKING, Any

from . import api_pb2
from .rpc import RPCException, async_get_screen_contents
from .screen import ScreenContents
from .util import CoordRange, Point, Range, WindowedCoordRange

if TYPE_CHECKING:
    from typing_extensions import Self

    from .connection import Connection


class SelectionMode(enum.Enum):
    """Enumerated list of modes for selecting text."""

    CHARACTER = 0  #: character-by-character selection
    WORD = 1  #: word-by-word selection
    LINE = 2  #: row-by-row selection
    SMART = 3  #: smart selection
    BOX = 4  #: rectangular region
    WHOLE_LINE = 5  #: entire wrapped lines, which could occupy many rows

    @staticmethod
    def from_proto_value(value: api_pb2.SelectionMode.ValueType) -> SelectionMode:
        """Creates a SelectionMode from a protobuf enum value."""
        return MODE_MAP[value]

    @staticmethod
    def to_proto_value(value: SelectionMode) -> api_pb2.SelectionMode.ValueType:
        """Converts self into a protobuf enum value."""
        return INVERSE_MODE_MAP[value]


class SubSelection:
    """Describes a continguous block of selected characters.

    :param windowed_coord_range: A :class:`~iterm2.util.WindowedCoordRange`
        describing the range.
    :param mode: A :class:`SelectionMode` describing how the selection is
        interpreted and extended.
    :param connected: If true, no newline exists between this and the next
        sub-selection.
    """

    def __init__(
        self,
        windowed_coord_range: WindowedCoordRange,
        mode: SelectionMode,
        connected: bool,
    ) -> None:
        self.__windowed_coord_range = windowed_coord_range
        self.__mode = mode
        self.__connected = connected

    # pylint: disable=invalid-name
    @property
    def windowedCoordRange(self) -> WindowedCoordRange:
        """Deprecated in favor of windowed_coord_range"""
        return self.windowed_coord_range

    # pylint: enable=invalid-name

    @property
    def windowed_coord_range(self) -> WindowedCoordRange:
        """Returns the coordinate range spanned by this sub-selection."""
        return self.__windowed_coord_range

    @property
    def mode(self) -> SelectionMode:
        """Returns the mode of this sub-selection."""
        return self.__mode

    @property
    def proto(self) -> api_pb2.SubSelection:
        """Creates a protobuf for this sub-selection."""
        # pylint: disable=no-member
        sub_selection = api_pb2.SubSelection()
        sub_selection.windowed_coord_range.CopyFrom(self.__windowed_coord_range.proto)
        sub_selection.selection_mode = SelectionMode.to_proto_value(self.__mode)
        return sub_selection

    @property
    def connected(self) -> bool:
        """
        Returns whether the subselection is connected to the next
        subselection.
        """
        return self.__connected

    async def async_get_string(self, connection: Connection, session_id: str) -> str:
        """Gets the text belonging to this subselection.

        :param connection: The connection to iTerm2.
        :param session_id: The ID of the session for which to look up the
            selected text.
        """
        result = await async_get_screen_contents(
            connection, session_id, self.__windowed_coord_range
        )
        # pylint: disable=no-member
        if result.get_buffer_response.status == api_pb2.GetBufferResponse.Status.Value(
            "OK"
        ):
            screen_contents = ScreenContents(result.get_buffer_response)
            built_string = ""
            i = 0
            while i < screen_contents.number_of_lines:
                line = screen_contents.line(i)
                i += 1
                built_string += line.string
                if line.hard_eol:
                    built_string += "\n"
            return built_string
        raise RPCException(
            api_pb2.GetBufferResponse.Status.Name(result.get_buffer_response.status)
        )

    def enumerate_ranges(self, callback: Callable[[Self, CoordRange], Any]) -> None:
        """Invoke callback for each selected range."""
        if self.__windowed_coord_range.hasWindow:
            right = self.__windowed_coord_range.right
            start_x = self.__windowed_coord_range.start.x
            y = self.__windowed_coord_range.coordRange.start.y
            while y < self.__windowed_coord_range.coordRange.end.y:
                callback(self, CoordRange(Point(start_x, y), Point(right, y)))
                start_x = self.__windowed_coord_range.left

                y += 1

            callback(
                self,
                CoordRange(
                    Point(start_x, self.__windowed_coord_range.coordRange.end.y),
                    Point(
                        self.__windowed_coord_range.end.x,
                        self.__windowed_coord_range.coordRange.end.y,
                    ),
                ),
            )
        else:
            callback(self, self.__windowed_coord_range.coordRange)

    # pylint: enable=invalid-name


class Selection:
    """
    A collection of :class:`SubSelection` objects, describing all the
    selections in a session.

    :param sub_selections: An array of :class:`SubSelection` objects.
    """

    def __init__(self, sub_selections: list[SubSelection]) -> None:
        self.__sub_selections = sub_selections

    # pylint: disable=invalid-name
    @property
    def subSelections(self) -> list[SubSelection]:
        """Deprecated in favore of sub_selections."""
        return self.sub_selections

    # pylint: enable=invalid-name

    @property
    def sub_selections(self) -> list[SubSelection]:
        """Returns the set of subselections."""
        return self.__sub_selections

    async def _async_get_content_in_range(
        self, connection: Connection, session_id: str, coord_range: WindowedCoordRange
    ):
        """Returns the string in the given range."""
        result = await async_get_screen_contents(connection, session_id, coord_range)
        # pylint: disable=no-member
        if result.get_buffer_response.status == api_pb2.GetBufferResponse.Status.Value(
            "OK"
        ):
            screen_contents = ScreenContents(result.get_buffer_response)
            built_string = ""
            i = 0
            while i < screen_contents.number_of_lines:
                line = screen_contents.line(i)
                i += 1
                built_string += line.string
                if line.hard_eol:
                    built_string += "\n"
            return built_string

    async def async_get_string(
        self, connection: Connection, session_id: str, width: int
    ) -> str:
        """Returns the selected text.

        :param connection: The connection to iTerm2.
        :param session_id: The ID of the session for which to look up the
            selected text.
        :param width: The width (number of columns) of the session.
        """
        if len(self.__sub_selections) == 1:
            return await self.__sub_selections[0].async_get_string(
                connection, session_id
            )

        result: str = ""

        async def handle_range(coord_range: WindowedCoordRange, eol: bool):
            content = await self._async_get_content_in_range(
                connection, session_id, coord_range
            )
            assert content is not None
            nonlocal result
            result += content
            if eol and not content.endswith("\n"):
                result += "\n"

        await self.async_enumerate_ranges(width, handle_range)
        return result

    async def async_enumerate_ranges(
        self,
        width: int,
        callback: Callable[[WindowedCoordRange, bool], Awaitable[bool | None]],
    ) -> None:
        """
        Gets the text belonging to each subselection and concatenates them with
        newlines.

        :param width: The width of the session
        :param callback: A function to call for each range, taking a
            WindowedCoordRange and a boolean which is true if there's a hard
            EOL at the end of the range.

        :returns: A string with the selected text.
        """
        # pylint: disable=too-many-locals
        if len(self.__sub_selections) == 0:
            return

        # Ranges ending at connectors don't get a newline following.
        connectors: set[int] = set()
        indexes: set[int] = set()
        for outer in self.__sub_selections:
            if outer.connected:
                the_position = (
                    outer.windowed_coord_range.coordRange.end.x
                    + outer.windowed_coord_range.coordRange.end.y * width
                )
                connectors |= {the_position}

            the_range = Range(0, 0)

            def _handle_range(outer: SubSelection, outer_range: CoordRange):
                # pylint: disable=invalid-name
                nonlocal indexes
                nonlocal the_range
                nonlocal connectors
                the_range = Range(
                    outer_range.start.x + outer_range.start.y * width,
                    outer_range.length(width),
                )

                indexes_to_add = the_range.toSet
                indexes_to_remove: set[int] = set()

                def f(values: tuple[int, int]) -> int:
                    i, x = values
                    return i - x

                # Iterate contiguous ranges
                indexes_of_interest = indexes.intersection(indexes_to_add)
                # pylint: disable=unused-variable
                for _, g in itertools.groupby(
                    enumerate(sorted(indexes_of_interest)), f
                ):
                    # range exists in both indexes and the_range
                    values_in_range = set(map(itemgetter(1), g))
                    indexes_to_remove |= values_in_range
                    indexes_to_add -= values_in_range
                indexes -= indexes_to_remove
                indexes |= indexes_to_add

                # In multipart windowed ranges, add connectors for the endpoint
                # of all but the last # range. Each enumerated range is on its
                # own line.
                if (
                    outer.windowed_coord_range.hasWindow
                    and outer_range.end == outer.windowed_coord_range.coordRange.end
                    and the_range.length > 0
                ):
                    connectors |= {the_range.max}

            outer.enumerate_ranges(_handle_range)

        # The ranges may be out of order so put them in an array and then sort
        # it.
        all_ranges: list[CoordRange] = []

        # pylint: disable=invalid-name
        def f(values: tuple[int, int]) -> int:
            i, x = values
            return i - x

        # pylint: enable=invalid-name

        # Iterate contiguous ranges
        # pylint: disable=unused-variable
        for _, range_group in itertools.groupby(enumerate(sorted(indexes)), f):
            # range exists in both indexes and the_range
            values_in_range = list(map(itemgetter(1), range_group))
            coord_range = CoordRange(
                Point(min(values_in_range) % width, min(values_in_range) // width),
                Point(max(values_in_range) % width, max(values_in_range) // width),
            )
            all_ranges.append(coord_range)

        def range_key(a_range: CoordRange) -> int:
            return a_range.start.y * width + a_range.start.x

        sorted_ranges = sorted(all_ranges, key=range_key)
        for idx, sorted_range in enumerate(sorted_ranges):
            end_index = (
                sorted_range.start.x
                + sorted_range.start.y * width
                + sorted_range.length(width)
            )
            eol = (end_index not in connectors) and idx + 1 < len(sorted_ranges)
            sorted_range.end.x += 1
            stop = await callback(WindowedCoordRange(sorted_range), eol)
            if stop:
                break


MODE_MAP: dict[api_pb2.SelectionMode.ValueType, SelectionMode] = {
    api_pb2.SelectionMode.Value("CHARACTER"): SelectionMode.CHARACTER,
    api_pb2.SelectionMode.Value("WORD"): SelectionMode.WORD,
    api_pb2.SelectionMode.Value("LINE"): SelectionMode.LINE,
    api_pb2.SelectionMode.Value("SMART"): SelectionMode.SMART,
    api_pb2.SelectionMode.Value("BOX"): SelectionMode.BOX,
    api_pb2.SelectionMode.Value("WHOLE_LINE"): SelectionMode.WHOLE_LINE,
}

INVERSE_MODE_MAP: dict[SelectionMode, api_pb2.SelectionMode.ValueType] = {
    v: k for k, v in MODE_MAP.items()
}
