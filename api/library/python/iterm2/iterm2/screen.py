"""Provides access to screen contents."""
import asyncio
import typing

import iterm2.api_pb2
import iterm2.notifications
import iterm2.rpc
import iterm2.util

from enum import Enum
from iterm2.api_pb2 import CellStyle as ProtoCellStyle, RGBColor as ProtoRGBColor, URL as ProtoURL, AlternateColor as ProtoAlternateColor, ImagePlaceholderType as ProtoImagePlaceholderType

class CellStyle:
    class RGBColor:
        def __init__(self, color: ProtoRGBColor):
            """
            Initialize RGBColor, which defines a color in sRGB with 8-bit
            integer components.

            :param color: A Protobuf RGBColor message.
            """
            self._color = color

        @property
        def red(self) -> int:
            """
            Returns the red component of the RGB color.

            :returns: An integer representing the red value (0-255).
            """
            return self._color.red

        @property
        def green(self) -> int:
            """
            Returns the green component of the RGB color.

            :returns: An integer representing the green value (0-255).
            """
            return self._color.green

        @property
        def blue(self) -> int:
            """
            Returns the blue component of the RGB color.

            :returns: An integer representing the blue value (0-255).
            """
            return self._color.blue

    class URL:
        def __init__(self, url: ProtoURL):
            """
            Initialize URL.

            :param url: A Protobuf URL message.
            """
            self._url = url

        @property
        def url(self) -> str:
            """
            Returns the URL string.

            :returns: A string representing the URL.
            """
            return self._url.url

        @property
        def identifier(self) -> str:
            """
            Returns the optional identifier associated with the URL, if present.

            :returns: A string representing the identifier, or None if not set.
            """
            return self._url.identifier if self._url.HasField("identifier") else None

    class AlternateColor(Enum):
        DEFAULT = ProtoAlternateColor.DEFAULT  #: Default text or background color
        REVERSED_DEFAULT = ProtoAlternateColor.REVERSED_DEFAULT  #: Default text or background color, but with roles reversed.
        SYSTEM_MESSAGE = ProtoAlternateColor.SYSTEM_MESSAGE  #: A message from the terminal emulator itself (e.g., a "session ended" message).

    class Color:
        def __init__(self,
                     standard: int = None,
                     alternate: 'CellStyle.AlternateColor' = None,
                     rgb: 'CellStyle.RGBColor' = None,
                     placement: int = None):
            """Represents a color that can be standard, alternate, or RGB.

            A standard color is part of the 256-color pallete with ANSI colors
            taking 0-16, then 16-231 as RGB values, and 232-255 as grayscale.

            See the `AlternateColor` class for the possible alternate colors.

            RGB colors are 24-bit colors in sRGB, like those set with SGR
            38;2;r;g;b and SGR 48;2;r;g;b.

            A placement gives the X or Y coordinate of an image in the Kitty
            graphics protocol, which overloads color to store coordinates.
            """
            self._standard = standard
            self._alternate = alternate
            self._rgb = rgb
            self._placement = placement

        @property
        def is_standard(self) -> bool:
            """Returns True if the color is a standard color."""
            return self._standard is not None

        @property
        def is_alternate(self) -> bool:
            """Returns True if the color is an alternate color."""
            return self._alternate is not None

        @property
        def is_rgb(self) -> bool:
            """Returns True if the color is an RGB color."""
            return self._rgb is not None

        @property
        def standard(self) -> int:
            """Returns the standard color if applicable, raises otherwise."""
            if self._standard is None:
                raise ValueError("Not a standard color")
            return self._standard

        @property
        def alternate(self) -> 'CellStyle.AlternateColor':
            """Returns the alternate color if applicable, raises otherwise."""
            if self._alternate is None:
                raise ValueError("Not an alternate color")
            return self._alternate

        @property
        def rgb(self) -> 'CellStyle.RGBColor':
            """Returns the RGB color if applicable, raises otherwise."""
            if self._rgb is None:
                raise ValueError("Not an RGB color")
            return self._rgb

        @property
        def placement(self) -> int:
            """Returns the alternate placement value if applicable, raises otherwise."""
            if self._placement is None:
                raise ValueError("Not an alternate placement")
            return self._placement

    class ImagePlaceholderType(Enum):
        """A cell that shows an image.

        Each of the two image protocols has a way of displaying part of an image
        in a cell with a special placeholder. This value identifies the image
        protocol for this cell, if any.
        """
        NONE = ProtoImagePlaceholderType.NONE
        ITERM2 = ProtoImagePlaceholderType.ITERM2
        KITTY = ProtoImagePlaceholderType.KITTY

    def __init__(self, protobuf: ProtoCellStyle):
        """
        CellStyle describes the appearance of a cell (such as its color or text properties).

        :param protobuf: A Protobuf CellStyle message.
        """
        self._proto = protobuf

    @property
    def repeats(self) -> int:
        """Returns the number of consecutive cells with the same style."""
        return self._proto.repeats

    @property
    def fg_color(self) -> 'CellStyle.Color':
        """
        Returns the foreground color as a CellStyle.Color object.

        :returns: A Color object representing the foreground color.
        """
        if self._proto.HasField('fgStandard'):
            return CellStyle.Color(standard=self._proto.fgStandard)
        elif self._proto.HasField('fgAlternate'):
            return CellStyle.Color(alternate=CellStyle.AlternateColor(self._proto.fgAlternate))
        elif self._proto.HasField('fgRgb'):
            return CellStyle.Color(rgb=CellStyle.RGBColor(self._proto.fgRgb))
        elif self._proto.HasField('fgAlternatePlacementX'):
            return CellStyle.Color(placement=self._proto.fgAlternatePlacementX)

    @property
    def bg_color(self) -> 'CellStyle.Color':
        """
        Returns the background color as a CellStyle.Color object.

        :returns: A Color object representing the background color.
        """
        if self._proto.HasField('bgStandard'):
            return CellStyle.Color(standard=self._proto.bgStandard)
        elif self._proto.HasField('bgAlternate'):
            return CellStyle.Color(alternate=CellStyle.AlternateColor(self._proto.bgAlternate))
        elif self._proto.HasField('bgRgb'):
            return CellStyle.Color(rgb=CellStyle.RGBColor(self._proto.bgRgb))
        elif self._proto.HasField('bgAlternatePlacementY'):
            return CellStyle.Color(placement=self._proto.bgAlternatePlacementY)

    @property
    def bold(self) -> bool:
        """
        Returns whether the text is bold.

        :returns: A boolean indicating if bold styling is applied.
        """
        return self._proto.bold

    @property
    def faint(self) -> bool:
        """
        Returns whether the text is faint.

        :returns: A boolean indicating if faint styling is applied.
        """
        return self._proto.faint

    @property
    def italic(self) -> bool:
        """
        Returns whether the text is italicized.

        :returns: A boolean indicating if italic styling is applied.
        """
        return self._proto.italic

    @property
    def blink(self) -> bool:
        """
        Returns whether the text is blinking.

        :returns: A boolean indicating if blink styling is applied.
        """
        return self._proto.blink

    @property
    def underline(self) -> bool:
        """
        Returns whether the text is underlined.

        :returns: A boolean indicating if underline styling is applied.
        """
        return self._proto.underline

    @property
    def strikethrough(self) -> bool:
        """
        Returns whether the text is strikethrough.

        :returns: A boolean indicating if strikethrough styling is applied.
        """
        return self._proto.strikethrough

    @property
    def invisible(self) -> bool:
        """
        Returns whether the text is invisible.

        :returns: A boolean indicating if invisible styling is applied.
        """
        return self._proto.invisible

    @property
    def inverse(self) -> bool:
        """
        Returns whether the text colors are inverted.

        :returns: A boolean indicating if inverse styling is applied.
        """
        return self._proto.inverse

    @property
    def guarded(self) -> bool:
        """
        Returns whether the text is guarded. Guarded cells can't be erased when
        screen is in protected mode. See DECSCA, SPA, and EPA.

        :returns: A boolean indicating if guarded styling is applied.
        """
        return self._proto.guarded

    @property
    def image(self) -> typing.Optional['CellStyle.ImagePlaceholderType']:
        """
        Returns the image placeholder type if set.

        :returns: An ImagePlaceholderType enum or None if not set.
        """
        return CellStyle.ImagePlaceholderType(self._proto.image) if self._proto.HasField("image") else None

    @property
    def underline_color(self) -> typing.Optional['CellStyle.RGBColor']:
        """
        Returns the underline color if set.

        :returns: An RGBColor object or None if not set.
        """
        return CellStyle.RGBColor(self._proto.underlineColor) if self._proto.HasField("underlineColor") else None

    @property
    def block_id(self) -> typing.Optional[str]:
        """
        Returns the block ID if set (as set by OSC 1337 ; Block).

        :returns: A string representing the block ID, or None if not set.
        """
        return self._proto.blockID if self._proto.HasField("blockID") else None

    @property
    def url(self) -> typing.Optional['CellStyle.URL']:
        """
        If this cell is hyperlinked by an OSC 8 URL, returns the URL.

        :returns: A URL object or None if not set.
        """
        return CellStyle.URL(self._proto.url) if self._proto.HasField("url") else None

class LineContents:
    """Describes the contents of a line."""
    def __init__(self, proto):
        self.__proto = proto
        self.__offset_of_cell = [0]
        self.__length_of_cell = []
        self.__styles = []
        offset = 0
        for cppc in proto.code_points_per_cell:
            for i in range(cppc.repeats):  # pylint: disable=unused-variable
                offset += cppc.num_code_points
                self.__offset_of_cell.append(offset)
                self.__length_of_cell.append(cppc.num_code_points)
        for style in proto.style:
            cs = CellStyle(style)
            for i in range(style.repeats):  # pylint: disable=unused-variable
                self.__styles.append(cs)

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

    def style_at(self, x: int) -> typing.Optional[CellStyle]:
        """Returns the style of the cell at index `x`.

        :param x: The index to look up.
        :returns: A `CellStyle` describing the style of the cell at that index or None if `x` is out of range. Note that `x` will be considered out-of-range for uninitialized cells (those that have not been modified since the screen was cleared).
        """
        if x >= 0 and x < len(self.__styles):
            return self.__styles[x]
        return None

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

    async def async_get(self, style=False) -> typing.Union[None, ScreenContents]:
        """
        Blocks until the screen contents change.

        If this `ScreenStreamer` has been configured to provide screen
        contents, then they will be returned.

        :param style: If `True`, include style information in the result.

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
            None,
            style)
        if (result.get_buffer_response.status == iterm2.
                api_pb2.GetBufferResponse.Status.Value("OK")):
            return ScreenContents(result.get_buffer_response)
        raise iterm2.rpc.RPCException(
            iterm2.api_pb2.GetBufferResponse.Status.Name(
                result.get_buffer_response.status))
