"""Tests for iterm2.selection module — SelectionMode, SubSelection, Selection."""
import pytest
from iterm2.selection import SelectionMode, SubSelection, Selection
import iterm2.util


class TestSelectionMode:
    """Tests for the SelectionMode enum."""

    def test_all_modes_exist(self):
        expected = {"CHARACTER", "WORD", "LINE", "SMART", "BOX", "WHOLE_LINE"}
        actual = {m.name for m in SelectionMode}
        assert expected == actual

    def test_character_value(self):
        assert SelectionMode.CHARACTER.value == 0

    def test_word_value(self):
        assert SelectionMode.WORD.value == 1

    def test_line_value(self):
        assert SelectionMode.LINE.value == 2

    def test_smart_value(self):
        assert SelectionMode.SMART.value == 3

    def test_box_value(self):
        assert SelectionMode.BOX.value == 4

    def test_whole_line_value(self):
        assert SelectionMode.WHOLE_LINE.value == 5

    def test_roundtrip_via_proto(self):
        """to_proto_value(from_proto_value(x)) == x for all modes."""
        for mode in SelectionMode:
            proto_val = SelectionMode.to_proto_value(mode)
            recovered = SelectionMode.from_proto_value(proto_val)
            assert recovered == mode

    def test_from_proto_value_character(self):
        proto_val = SelectionMode.to_proto_value(SelectionMode.CHARACTER)
        assert SelectionMode.from_proto_value(proto_val) == SelectionMode.CHARACTER

    def test_from_proto_value_box(self):
        proto_val = SelectionMode.to_proto_value(SelectionMode.BOX)
        assert SelectionMode.from_proto_value(proto_val) == SelectionMode.BOX


class TestSubSelection:
    """Tests for SubSelection — properties accessible without network."""

    def _make_range(self, x1=0, y1=0, x2=5, y2=0):
        start = iterm2.util.Point(x1, y1)
        end = iterm2.util.Point(x2, y2)
        coord_range = iterm2.util.CoordRange(start, end)
        return iterm2.util.WindowedCoordRange(coord_range)

    def test_windowed_coord_range_property(self):
        wcr = self._make_range()
        sub = SubSelection(wcr, SelectionMode.CHARACTER, False)
        assert sub.windowed_coord_range is wcr

    def test_deprecated_windowed_coord_range_alias(self):
        """windowedCoordRange is a deprecated alias for windowed_coord_range."""
        wcr = self._make_range()
        sub = SubSelection(wcr, SelectionMode.WORD, False)
        assert sub.windowedCoordRange is sub.windowed_coord_range

    def test_mode_property(self):
        wcr = self._make_range()
        sub = SubSelection(wcr, SelectionMode.LINE, False)
        assert sub.mode == SelectionMode.LINE

    def test_connected_false(self):
        wcr = self._make_range()
        sub = SubSelection(wcr, SelectionMode.CHARACTER, False)
        assert sub.connected is False

    def test_connected_true(self):
        wcr = self._make_range()
        sub = SubSelection(wcr, SelectionMode.CHARACTER, True)
        assert sub.connected is True

    def test_all_modes(self):
        wcr = self._make_range()
        for mode in SelectionMode:
            sub = SubSelection(wcr, mode, False)
            assert sub.mode == mode


class TestSelection:
    """Tests for the Selection container class."""

    def _make_sub(self, x1=0, y1=0, x2=5, y2=0, mode=SelectionMode.CHARACTER, connected=False):
        start = iterm2.util.Point(x1, y1)
        end = iterm2.util.Point(x2, y2)
        coord_range = iterm2.util.CoordRange(start, end)
        wcr = iterm2.util.WindowedCoordRange(coord_range)
        return SubSelection(wcr, mode, connected)

    def test_empty_selection(self):
        sel = Selection([])
        assert sel.sub_selections == []

    def test_single_sub_selection(self):
        sub = self._make_sub()
        sel = Selection([sub])
        assert len(sel.sub_selections) == 1
        assert sel.sub_selections[0] is sub

    def test_multiple_sub_selections(self):
        subs = [self._make_sub(i, 0, i + 3, 0) for i in range(3)]
        sel = Selection(subs)
        assert len(sel.sub_selections) == 3

    def test_deprecated_alias(self):
        """subSelections is a deprecated alias for sub_selections."""
        sub = self._make_sub()
        sel = Selection([sub])
        assert sel.subSelections is sel.sub_selections

    def test_sub_selections_preserves_order(self):
        subs = [
            self._make_sub(0, 0, 5, 0, SelectionMode.CHARACTER),
            self._make_sub(0, 1, 5, 1, SelectionMode.WORD),
            self._make_sub(0, 2, 5, 2, SelectionMode.LINE),
        ]
        sel = Selection(subs)
        for i, sub in enumerate(sel.sub_selections):
            assert sub is subs[i]
