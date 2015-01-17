import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class HVPTests(object):
  def __init__(self, args):
    self._args = args

  def test_HVP_DefaultParams(self):
    """With no params, HVP moves to 1,1."""
    esccsi.CSI_HVP(Point(6, 3))

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 3)

    esccsi.CSI_HVP()

    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 1)

  def test_HVP_RowOnly(self):
    """Default column is 1."""
    esccsi.CSI_HVP(Point(6, 3))

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 3)

    esccsi.CSI_HVP(row=2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 2)

  def test_HVP_ColumnOnly(self):
    """Default row is 1."""
    esccsi.CSI_HVP(Point(6, 3))

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 3)

    esccsi.CSI_HVP(col=2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 2)
    AssertEQ(position.y(), 1)

  def test_HVP_ZeroIsTreatedAsOne(self):
    """Zero args are treated as 1."""
    esccsi.CSI_HVP(Point(6, 3))
    esccsi.CSI_HVP(col=0, row=0)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 1)

  def test_HVP_OutOfBoundsParams(self):
    """With overly large parameters, HVP moves as far as possible down and right."""
    size = GetScreenSize()
    esccsi.CSI_HVP(Point(size.width() + 10, size.height() + 10))

    position = GetCursorPosition()
    AssertEQ(position.x(), size.width())
    AssertEQ(position.y(), size.height())

  @knownBug(terminal="iTerm2",
            reason="iTerm2 has an off-by-one bug in origin mode. 1;1 should go to the origin, but instead it goes one right and one down of the origin.")
  def test_HVP_RespectsOriginMode(self):
    """HVP is relative to margins in origin mode."""
    # Set a scroll region.
    esccsi.CSI_DECSTBM(6, 11)
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 10)

    # Move to center of region
    esccsi.CSI_HVP(Point(7, 9))
    position = GetCursorPosition()
    AssertEQ(position.x(), 7)
    AssertEQ(position.y(), 9)

    # Turn on origin mode.
    esccsi.CSI_DECSET(esccsi.DECOM)

    # Move to top-left
    esccsi.CSI_HVP(Point(1, 1))

    # Check relative position while still in origin mode.
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 1)

    escio.Write("X")

    # Turn off origin mode. This moves the cursor.
    esccsi.CSI_DECSET(esccsi.DECOM)

    # Turn off scroll regions so checksum can work.
    esccsi.CSI_DECSTBM()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    # Make sure there's an X at 5,6
    AssertScreenCharsInRectEqual(Rect(5, 6, 5, 6),
                                 [ "X" ])
