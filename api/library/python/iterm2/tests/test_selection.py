"""Tests for iterm2.selection."""

import asyncio

from iterm2.selection import Selection, SelectionMode, SubSelection
from iterm2.util import CoordRange, Point, Range, WindowedCoordRange


def test_windowed_lines_are_joined_but_end_with_a_newline():
    """Like iTerm2, each line of a windowed selection but the last is connected."""
    windowed = SubSelection(
        WindowedCoordRange(CoordRange(Point(12, 0), Point(15, 2)), Range(10, 10)),
        SelectionMode.CHARACTER,
        False,
    )
    later = SubSelection(
        WindowedCoordRange(CoordRange(Point(0, 5), Point(4, 5))),
        SelectionMode.CHARACTER,
        False,
    )
    eols = []

    async def callback(_coord_range, eol):
        eols.append(eol)
        return False

    asyncio.run(Selection([windowed, later]).async_enumerate_ranges(80, callback))

    assert eols == [False, False, True, False]


def test_connected_sub_selection_is_joined_to_the_next():
    """A connected sub-selection gets no newline after it."""
    first = SubSelection(
        WindowedCoordRange(CoordRange(Point(0, 0), Point(5, 0))),
        SelectionMode.CHARACTER,
        True,
    )
    second = SubSelection(
        WindowedCoordRange(CoordRange(Point(0, 1), Point(5, 1))),
        SelectionMode.CHARACTER,
        False,
    )
    eols = []

    async def callback(_coord_range, eol):
        eols.append(eol)
        return False

    asyncio.run(Selection([first, second]).async_enumerate_ranges(80, callback))

    assert eols == [False, False]
