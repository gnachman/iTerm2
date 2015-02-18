from esc import NUL, blank
import escargs
import esccmd
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, knownBug

class ELTests(object):
  def prepare(self):
    """Initializes the screen to abcdefghij on the first line with the cursor
    on the 'e'."""
    esccmd.CUP(Point(1, 1))
    escio.Write("abcdefghij")
    esccmd.CUP(Point(5, 1))

  def test_EL_Default(self):
    """Should erase to right of cursor."""
    self.prepare()
    esccmd.EL()
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcd" + 6 * NUL ])

  def test_EL_0(self):
    """Should erase to right of cursor."""
    self.prepare()
    esccmd.EL(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ "abcd" + 6 * NUL ])

  def test_EL_1(self):
    """Should erase to left of cursor."""
    self.prepare()
    esccmd.EL(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 5 * blank() + "fghij" ])

  def test_EL_2(self):
    """Should erase whole line."""
    self.prepare()
    esccmd.EL(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 10 * NUL ])

  def test_EL_IgnoresScrollRegion(self):
    """Should erase whole line."""
    self.prepare()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(5, 1))
    esccmd.EL(2)
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 10, 1),
                                 [ 10 * NUL ])

  def test_EL_doesNotRespectDECProtection(self):
    """EL respects DECSCA."""
    escio.Write("a")
    escio.Write("b")
    esccmd.DECSCA(1)
    escio.Write("c")
    esccmd.DECSCA(0)
    esccmd.CUP(Point(1, 1))
    esccmd.EL(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ NUL * 3 ])

  @knownBug(terminal="iTerm2",
            reason="Protection not implemented.")
  def test_EL_respectsISOProtection(self):
    """EL respects SPA/EPA."""
    escio.Write("a")
    escio.Write("b")
    esccmd.SPA()
    escio.Write("c")
    esccmd.EPA()
    esccmd.CUP(Point(1, 1))
    esccmd.EL(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ blank() * 2 + "c" ])

