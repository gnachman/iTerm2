from esc import NUL, blank
import escargs
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition

class ELTests(object):
  def prepare(self):
    """Initializes the screen to abcdefghij on the first line with the cursor
    on the 'e'."""
    esccsi.CUP(Point(1, 1))
    escio.Write("abcdefghij")
    esccsi.CUP(Point(5, 1))

  def test_EL_Default(self):
    """Should erase to right of cursor."""
    self.prepare()
    esccsi.EL()
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcd" + 6 * NUL ])

  def test_EL_0(self):
    """Should erase to right of cursor."""
    self.prepare()
    esccsi.EL(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcd" + 6 * NUL ])

  def test_EL_1(self):
    """Should erase to left of cursor."""
    self.prepare()
    esccsi.EL(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 5 * blank() + "fghij" ])

  def test_EL_2(self):
    """Should erase whole line."""
    self.prepare()
    esccsi.EL(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 10 * NUL ])

  def test_EL_IgnoresScrollRegion(self):
    """Should erase whole line."""
    self.prepare()
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.CUP(Point(5, 1))
    esccsi.EL(2)
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 10 * NUL ])


