from esc import NUL
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition

class EDTests(object):
  def __init__(self, args):
    self._args = args

  def blank(self):
    if self._args.expected_terminal == "xterm":
      return ' '
    else:
      return NUL

  def prepare(self):
    """Sets up the display as:
    a

    bcd

    e

    With the cursor on the 'c'.
    """
    esccsi.CUP(Point(1, 1))
    escio.Write("a")
    esccsi.CUP(Point(1, 3))
    escio.Write("bcd")
    esccsi.CUP(Point(1, 5))
    escio.Write("e")

    esccsi.CUP(Point(2, 3))

  def prepare_wide(self):
    """Sets up the display as:
    abcde
    fghij
    klmno

    With the cursor on the 'h'.
    """
    esccsi.CUP(Point(1, 1))
    escio.Write("abcde")
    esccsi.CUP(Point(1, 2))
    escio.Write("fghij")
    esccsi.CUP(Point(1, 3))
    escio.Write("klmno")

    esccsi.CUP(Point(2, 3))

  def test_ED_Default(self):
    """Should be the same as ED_0."""
    self.prepare()
    esccsi.ED()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "b" + NUL * 2,
                                   NUL * 3,
                                   NUL * 3 ])

  def test_ED_0(self):
    """Erase after cursor."""
    self.prepare()
    esccsi.ED(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "b" + NUL * 2,
                                   NUL * 3,
                                   NUL * 3 ])

  def test_ED_1(self):
    """Erase before cursor."""
    self.prepare()
    esccsi.ED(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ NUL * 3,
                                   NUL * 3,
                                   self.blank() * 2 + "d",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  def test_ED_2(self):
    """Erase whole screen."""
    self.prepare()
    esccsi.ED(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ NUL * 3,
                                   NUL * 3,
                                   NUL * 3,
                                   NUL * 3,
                                   NUL * 3 ])

  def test_ED_3(self):
    """xterm supports a "3" parameter, which also erases scrollback history. There
    is no way to test if it's working, though. We can at least test that it doesn't
    touch the screen."""
    self.prepare()
    esccsi.ED(3)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  def test_ED_0_WithScrollRegion(self):
    """Erase after cursor with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.DECSTBM(2, 3)
    esccsi.CUP(Point(3, 2))
    esccsi.ED(0)
    esccsi.DECRESET(esccsi.DECLRMM)
    esccsi.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ "abcde",
                                   "fg" + NUL * 3,
                                   NUL * 5 ])

  def test_ED_1_WithScrollRegion(self):
    """Erase before cursor with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.DECSTBM(2, 3)
    esccsi.CUP(Point(3, 2))
    esccsi.ED(1)
    esccsi.DECRESET(esccsi.DECLRMM)
    esccsi.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ NUL * 5,
                                   self.blank() * 3 + "ij",
                                   "klmno" ])

  def test_ED_2_WithScrollRegion(self):
    """Erase whole screen with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.DECSTBM(2, 3)
    esccsi.CUP(Point(3, 2))
    esccsi.ED(2)
    esccsi.DECRESET(esccsi.DECLRMM)
    esccsi.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ NUL * 5,
                                   NUL * 5,
                                   NUL * 5 ])

