import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class CHATests(object):
  def __init__(self, args):
    self._args = args

  def test_CHA_DefaultParam(self):
    """CHA moves to first column of active line by default."""
    esccsi.CSI_CUP(Point(5, 3))
    esccsi.CSI_CHA()
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 3)

  def test_CHA_ExplicitParam(self):
    """CHA moves to specified column of active line."""
    esccsi.CSI_CUP(Point(5, 3))
    esccsi.CSI_CHA(10)
    position = GetCursorPosition()
    AssertEQ(position.x(), 10)
    AssertEQ(position.y(), 3)

  def test_CHA_OutOfBoundsLarge(self):
    """CHA moves as far as possible when given a too-large parameter."""
    esccsi.CSI_CUP(Point(5, 3))
    esccsi.CSI_CHA(9999)
    position = GetCursorPosition()
    width = GetScreenSize().width()
    AssertEQ(position.x(), width)
    AssertEQ(position.y(), 3)

  def test_CHA_ZeroParam(self):
    """CHA moves as far left as possible when given a zero parameter."""
    esccsi.CSI_CUP(Point(5, 3))
    esccsi.CSI_CHA(0)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 3)

  def test_CHA_IgnoresScrollRegion(self):
    """CHA ignores scroll regions."""
    # Set a scroll region.
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 10)
    esccsi.CSI_CUP(Point(5, 3))
    esccsi.CSI_CHA(1)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 3)

  @knownBug(terminal="iTerm2",
            reason="iTerm2 has an off-by-one bug in origin mode. 1;1 should go to the origin, but instead it goes one right and one down of the origin.")
  def test_CHA_RespectsOriginMode(self):
    """CHA is relative to left margin in origin mode."""
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

    # Move to top but not the left, so CHA has something to do.
    esccsi.CSI_CUP(Point(2, 1))

    # Move to leftmost column in the scroll region.
    esccsi.CSI_CHA(1)

    # Check relative position while still in origin mode.
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)

    escio.Write("X")

    # Turn off origin mode. This moves the cursor.
    esccsi.CSI_DECSET(esccsi.DECOM)

    # Turn off scroll regions so checksum can work.
    esccsi.CSI_DECSTBM()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    # Make sure there's an X at 5,6
    AssertScreenCharsInRectEqual(Rect(5, 6, 5, 6),
                                 [ "X" ])

