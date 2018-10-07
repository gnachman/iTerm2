"""Provides interfaces for interacting with selected text regions."""
import enum
import iterm2.api_pb2
import iterm2.util

class SelectionMode(enum.Enum):
    """Enumerated list of selection modes.

    `CHARACTER`, `WORD`, `LINE`, `WHOLE_LINE`, or `BOX`.

    These determine how the selection is extended, and how to interpret its coordinate range.

    `CHARACTER` means character-by-character selection.

    `WORD` means word-by-word selection.

    `LINE` means row-by-row selection.

    `WHOLE_LINE` means entire wrapped lines, which could occupy many rows.

    `BOX` is a rectangular region."""
    CHARACTER = 0
    WORD = 1
    LINE = 2
    SMART = 3
    BOX = 4
    WHOLE_LINE = 5

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

    :param windowedCoordRange: A :class:`iterm2.util.WindowedCoordRange` describing the range.
    :param mode: A :class:`SelectionMode` describing how the selection is interpreted and extended.
    """
    def __init__(self, windowedCoordRange, mode):
        self.__windowedCoordRange = windowedCoordRange
        self.__mode = mode

    @property
    def windowedCoordRange(self):
        return self.__windowedCoordRange

    @property
    def mode(self):
        return self.__mode

    @property
    def proto(self):
        p = iterm2.api_pb2.SubSelection()
        p.windowed_coord_range.CopyFrom(self.__windowedCoordRange.proto)
        p.selection_mode = SelectionMode.toProtoValue(self.__mode)
        return p

class Selection:
    """A collection of :class:`SubSelection` objects, describing all the selections in a session.

    :param subSelections: An array of :class:`SubSelection` objects.
    """
    def __init__(self, subSelections):
        self.__subSelections = subSelections

    @property
    def subSelections(self):
        return self.__subSelections

MODE_MAP = {
        iterm2.api_pb2.SelectionMode.Value("CHARACTER"): SelectionMode.CHARACTER,
        iterm2.api_pb2.SelectionMode.Value("WORD"): SelectionMode.WORD,
        iterm2.api_pb2.SelectionMode.Value("LINE"): SelectionMode.LINE,
        iterm2.api_pb2.SelectionMode.Value("SMART"): SelectionMode.SMART,
        iterm2.api_pb2.SelectionMode.Value("BOX"): SelectionMode.BOX,
        iterm2.api_pb2.SelectionMode.Value("WHOLE_LINE"): SelectionMode.WHOLE_LINE }

INVERSE_MODE_MAP = {v: k for k, v in MODE_MAP.items()}

