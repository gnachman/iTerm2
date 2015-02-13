from esc import NUL, blank
import escargs
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug

class ECHTests(object):
  def test_ECH_DefaultParam(self):
    """Should erase the character under the cursor."""
    escio.Write("abc")
    esccsi.CUP(Point(1, 1))
    esccsi.ECH()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1), [ blank() + "bc" ]);

  def test_ECH_ExplicitParam(self):
    """Should erase N characters starting at the cursor."""
    escio.Write("abc")
    esccsi.CUP(Point(1, 1))
    esccsi.ECH(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1), [ blank() * 2 + "c" ]);

  def test_ECH_IgnoresScrollRegion(self):
    """ECH ignores the scroll region when the cursor is inside it"""
    escio.Write("abcdefg")
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.CUP(Point(3, 1))
    esccsi.ECH(4)
    esccsi.DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 1), [ "ab" + blank() * 4 + "g" ]);

  def test_ECH_OutsideScrollRegion(self):
    """ECH ignores the scroll region when the cursor is outside it"""
    escio.Write("abcdefg")
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.CUP(Point(1, 1))
    esccsi.ECH(4)
    esccsi.DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 1), [ blank() * 4 + "efg" ]);

