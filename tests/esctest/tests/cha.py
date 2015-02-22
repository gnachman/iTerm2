import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class CHATests(object):
  def test_CHA_DefaultParam(self):
    """CHA moves to first column of active line by default."""
    esccmd.CUP(Point(5, 3))
    esccmd.CHA()
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 3)

  def test_CHA_ExplicitParam(self):
    """CHA moves to specified column of active line."""
    esccmd.CUP(Point(5, 3))
    esccmd.CHA(10)
    position = GetCursorPosition()
    AssertEQ(position.x(), 10)
    AssertEQ(position.y(), 3)

  def test_CHA_OutOfBoundsLarge(self):
    """CHA moves as far as possible when given a too-large parameter."""
    esccmd.CUP(Point(5, 3))
    esccmd.CHA(9999)
    position = GetCursorPosition()
    width = GetScreenSize().width()
    AssertEQ(position.x(), width)
    AssertEQ(position.y(), 3)

  def test_CHA_ZeroParam(self):
    """CHA moves as far left as possible when given a zero parameter."""
    esccmd.CUP(Point(5, 3))
    esccmd.CHA(0)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 3)

  def test_CHA_IgnoresScrollRegion(self):
    """CHA ignores scroll regions."""
    # Set a scroll region.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(5, 3))
    esccmd.CHA(1)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 3)

  def test_CHA_RespectsOriginMode(self):
    """CHA is relative to left margin in origin mode."""
    # Set a scroll region.
    esccmd.DECSTBM(6, 11)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    # Move to center of region
    esccmd.CUP(Point(7, 9))
    position = GetCursorPosition()
    AssertEQ(position.x(), 7)
    AssertEQ(position.y(), 9)

    # Turn on origin mode.
    esccmd.DECSET(esccmd.DECOM)

    # Move to top but not the left, so CHA has something to do.
    esccmd.CUP(Point(2, 1))

    # Move to leftmost column in the scroll region.
    esccmd.CHA(1)

    # Check relative position while still in origin mode.
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)

    escio.Write("X")

    # Turn off origin mode. This moves the cursor.
    esccmd.DECRESET(esccmd.DECOM)

    # Turn off scroll regions so checksum can work.
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)

    # Make sure there's an X at 5,6
    AssertScreenCharsInRectEqual(Rect(5, 6, 5, 6),
                                 [ "X" ])

