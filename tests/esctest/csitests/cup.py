import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class CUPTests(object):
  def __init__(self, args):
    self._args = args

  def test_CUP_DefaultParams(self):
    """With no params, CUP moves to 1,1."""
    esccsi.CSI_CUP(Point(6, 3))

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 3)

    esccsi.CSI_CUP()

    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 1)

  def test_CUP_OutOfBoundsParams(self):
    """With overly large parameters, CUP moves as far as possible down and right."""
    size = GetScreenSize()
    esccsi.CSI_CUP(Point(size.width() + 10, size.height() + 10))

    position = GetCursorPosition()
    AssertEQ(position.x(), size.width())
    AssertEQ(position.y(), size.height())

  @knownBug(terminal="iTerm2",
            reason="iTerm2 has an off-by-one bug in origin mode. 1;1 should go to the origin, but instead it goes one right and one down of the origin.")
  def test_CUP_RespectsOriginMode(self):
    """CUP is relative to margins in origin mode."""
    # Set a scroll region.
    esccsi.CSI_DECSTBM(6, 11)
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 10)

    # Move to center of region
    esccsi.CSI_CUP(Point(7, 9))
    position = GetCursorPosition()
    AssertEQ(position.x(), 7)
    AssertEQ(position.y(), 9)

    # Turn on origin mode.
    esccsi.CSI_DECSET(esccsi.DECOM)

    # Move to top-left
    esccsi.CSI_CUP(Point(1, 1))

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
