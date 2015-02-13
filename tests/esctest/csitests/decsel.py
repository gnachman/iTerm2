from esc import NUL
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, knownBug

class DECSELTests(object):
  def __init__(self, args):
    self._args = args

  def blank(self):
    if self._args.expected_terminal == "xterm":
      return ' '
    else:
      return NUL

  def prepare(self):
    """Initializes the screen to abcdefghij on the first line with the cursor
    on the 'e'."""
    esccsi.CUP(Point(1, 1))
    escio.Write("abcdefghij")
    esccsi.CUP(Point(5, 1))

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_Default(self):
    """Should erase to right of cursor."""
    self.prepare()
    esccsi.DECSEL()
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcd" + 6 * NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_0(self):
    """Should erase to right of cursor."""
    self.prepare()
    esccsi.DECSEL(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcd" + 6 * NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_1(self):
    """Should erase to left of cursor."""
    self.prepare()
    esccsi.DECSEL(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 5 * self.blank() + "fghij" ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_2(self):
    """Should erase whole line."""
    self.prepare()
    esccsi.DECSEL(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 10 * NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_IgnoresScrollRegion(self):
    """Should erase whole line."""
    self.prepare()
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.CUP(Point(5, 1))
    esccsi.DECSEL(2)
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 10 * NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_Default_Protection(self):
    """Should erase to right of cursor."""
    esccsi.DECSCA(1)
    self.prepare()

    # Write an X at 1,1 without protection
    esccsi.DECSCA(0)
    esccsi.CUP(Point(10, 1))
    escio.Write("X")
    esccsi.CUP(Point(5, 1))

    esccsi.DECSEL()
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcdefghi" + NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_0_Protection(self):
    """All letters are protected so nothing should happen."""
    esccsi.DECSCA(1)
    self.prepare()

    # Write an X at 1,1 without protection
    esccsi.DECSCA(0)
    esccsi.CUP(Point(10, 1))
    escio.Write("X")

    esccsi.CUP(Point(5, 1))
    esccsi.DECSEL(0)

    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcdefghi" + NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_1_Protection(self):
    """All letters are protected so nothing should happen."""
    esccsi.DECSCA(1)
    self.prepare()

    # Write an X at 1,1 without protection
    esccsi.DECSCA(0)
    esccsi.CUP(Point(1, 1))
    escio.Write("X")

    esccsi.CUP(Point(5, 1))
    esccsi.DECSEL(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ self.blank() + "bcdefghij" ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_2_Protection(self):
    """All letters are protected so nothing should happen."""
    esccsi.DECSCA(1)
    self.prepare()

    # Write an X at 1,1 without protection
    esccsi.DECSCA(0)
    esccsi.CUP(Point(1, 1))
    escio.Write("X")

    esccsi.DECSEL(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ self.blank() + "bcdefghij" ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_IgnoresScrollRegion_Protection(self):
    """All letters are protected so nothing should happen."""
    esccsi.DECSCA(1)
    self.prepare()

    # Write an X at 1,1 without protection
    esccsi.DECSCA(0)
    esccsi.CUP(Point(1, 1))
    escio.Write("X")

    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.CUP(Point(5, 1))
    esccsi.DECSEL(2)
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ self.blank() + "bcdefghij" ])

