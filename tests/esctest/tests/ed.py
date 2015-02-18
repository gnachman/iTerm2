from esc import NUL, blank
import escargs
import esccmd
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, knownBug

class EDTests(object):
  def prepare(self):
    """Sets up the display as:
    a

    bcd

    e

    With the cursor on the 'c'.
    """
    esccmd.CUP(Point(1, 1))
    escio.Write("a")
    esccmd.CUP(Point(1, 3))
    escio.Write("bcd")
    esccmd.CUP(Point(1, 5))
    escio.Write("e")

    esccmd.CUP(Point(2, 3))

  def prepare_wide(self):
    """Sets up the display as:
    abcde
    fghij
    klmno

    With the cursor on the 'h'.
    """
    esccmd.CUP(Point(1, 1))
    escio.Write("abcde")
    esccmd.CUP(Point(1, 2))
    escio.Write("fghij")
    esccmd.CUP(Point(1, 3))
    escio.Write("klmno")

    esccmd.CUP(Point(2, 3))

  def test_ED_Default(self):
    """Should be the same as ED_0."""
    self.prepare()
    esccmd.ED()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "b" + NUL * 2,
                                   NUL * 3,
                                   NUL * 3 ])

  def test_ED_0(self):
    """Erase after cursor."""
    self.prepare()
    esccmd.ED(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "b" + NUL * 2,
                                   NUL * 3,
                                   NUL * 3 ])

  def test_ED_1(self):
    """Erase before cursor."""
    self.prepare()
    esccmd.ED(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ NUL * 3,
                                   NUL * 3,
                                   blank() * 2 + "d",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  def test_ED_2(self):
    """Erase whole screen."""
    self.prepare()
    esccmd.ED(2)
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
    esccmd.ED(3)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  def test_ED_0_WithScrollRegion(self):
    """Erase after cursor with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(3, 2))
    esccmd.ED(0)
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ "abcde",
                                   "fg" + NUL * 3,
                                   NUL * 5 ])

  def test_ED_1_WithScrollRegion(self):
    """Erase before cursor with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(3, 2))
    esccmd.ED(1)
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ NUL * 5,
                                   blank() * 3 + "ij",
                                   "klmno" ])

  def test_ED_2_WithScrollRegion(self):
    """Erase whole screen with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(3, 2))
    esccmd.ED(2)
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ NUL * 5,
                                   NUL * 5,
                                   NUL * 5 ])

  def test_ED_doesNotRespectDECProtection(self):
    """ED should not respect DECSCA"""
    escio.Write("a")
    escio.Write("b")
    esccmd.DECSCA(1)
    escio.Write("c")
    esccmd.DECSCA(0)
    esccmd.CUP(Point(1, 1))
    esccmd.ED(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                               [ NUL * 3 ])

  @knownBug(terminal="iTerm2",
            reason="Protection not implemented.")
  def test_ED_respectsISOProtection(self):
    """ED respects SPA/EPA."""
    escio.Write("a")
    escio.Write("b")
    esccmd.SPA()
    escio.Write("c")
    esccmd.EPA()
    esccmd.CUP(Point(1, 1))
    esccmd.ED(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ blank() * 2 + "c" ])

