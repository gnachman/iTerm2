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
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("abcdefghij")
    esccsi.CSI_CUP(Point(5, 1))

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_Default(self):
    """Should erase to right of cursor."""
    self.prepare()
    esccsi.CSI_DECSEL()
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcd" + 6 * NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_0(self):
    """Should erase to right of cursor."""
    self.prepare()
    esccsi.CSI_DECSEL(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcd" + 6 * NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_1(self):
    """Should erase to left of cursor."""
    self.prepare()
    esccsi.CSI_DECSEL(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 5 * self.blank() + "fghij" ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_2(self):
    """Should erase whole line."""
    self.prepare()
    esccsi.CSI_DECSEL(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 10 * NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_IgnoresScrollRegion(self):
    """Should erase whole line."""
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_CUP(Point(5, 1))
    esccsi.CSI_DECSEL(2)
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 10 * NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_Default_Protection(self):
    """Should erase to right of cursor."""
    esccsi.CSI_DECSCA(1)
    self.prepare()
    esccsi.CSI_DECSEL()
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcdefghij" ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_0_Protection(self):
    """All letters are protected so nothing should happen."""
    esccsi.CSI_DECSCA(1)
    self.prepare()
    esccsi.CSI_DECSEL(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcdefghij" ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_1_Protection(self):
    """All letters are protected so nothing should happen."""
    esccsi.CSI_DECSCA(1)
    self.prepare()
    esccsi.CSI_DECSEL(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcdefghij" ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_2_Protection(self):
    """All letters are protected so nothing should happen."""
    esccsi.CSI_DECSCA(1)
    self.prepare()
    esccsi.CSI_DECSEL(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcdefghij" ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECSEL_IgnoresScrollRegion_Protection(self):
    """All letters are protected so nothing should happen."""
    esccsi.CSI_DECSCA(1)
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_CUP(Point(5, 1))
    esccsi.CSI_DECSEL(2)
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcdefghij" ])

