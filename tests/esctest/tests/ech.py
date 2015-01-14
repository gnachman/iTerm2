from esc import NUL, blank
import escargs
import esccmd
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug

class ECHTests(object):
  def test_ECH_DefaultParam(self):
    """Should erase the character under the cursor."""
    escio.Write("abc")
    esccmd.CUP(Point(1, 1))
    esccmd.ECH()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1), [ blank() + "bc" ]);

  def test_ECH_ExplicitParam(self):
    """Should erase N characters starting at the cursor."""
    escio.Write("abc")
    esccmd.CUP(Point(1, 1))
    esccmd.ECH(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1), [ blank() * 2 + "c" ]);

  def test_ECH_IgnoresScrollRegion(self):
    """ECH ignores the scroll region when the cursor is inside it"""
    escio.Write("abcdefg")
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(3, 1))
    esccmd.ECH(4)
    esccmd.DECRESET(esccmd.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 1), [ "ab" + blank() * 4 + "g" ]);

  def test_ECH_OutsideScrollRegion(self):
    """ECH ignores the scroll region when the cursor is outside it"""
    escio.Write("abcdefg")
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(1, 1))
    esccmd.ECH(4)
    esccmd.DECRESET(esccmd.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 1), [ blank() * 4 + "efg" ]);

  @knownBug(terminal="xterm",
            reason="ECH respects DEC protection, which is questionable at best given the description of DECSCA 'The selective erase control functions (DECSED and DECSEL) can only erase characters defined as erasable'.")
  def test_ECH_doesNotRespectDECPRotection(self):
    """ECH should not respect DECSCA."""
    escio.Write("a")
    escio.Write("b")
    esccmd.DECSCA(1)
    escio.Write("c")
    esccmd.DECSCA(0)
    esccmd.CUP(Point(1, 1))
    esccmd.ECH(3)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ blank() * 3 ])

  @knownBug(terminal="iTerm2",
            reason="Protection not implemented.")
  def test_ECH_respectsISOProtection(self):
    """ECH respects SPA/EPA."""
    escio.Write("a")
    escio.Write("b")
    esccmd.SPA()
    escio.Write("c")
    esccmd.EPA()
    esccmd.CUP(Point(1, 1))
    esccmd.ECH(3)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ blank() * 2 + "c" ])

