from esc import NUL
import esccsi
import escio
from escutil import AssertScreenCharsInRectEqual, GetScreenSize, knownBug
from esctypes import Point, Rect

class REPTests(object):
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_REP_DefaultParam(self):
    escio.Write("a")
    esccsi.REP()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1), [ "aa" + NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_REP_ExplicitParam(self):
    escio.Write("a")
    esccsi.REP(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 1), [ "aaa" + NUL ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_REP_RespectsLeftRightMargins(self):
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.CUP(Point(2, 1))
    escio.Write("a")
    esccsi.REP(3)
    esccsi.DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 2),
        [ NUL + "aaa" + NUL ,
          NUL + "a" + NUL * 3 ])

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_REP_RespectsTopBottomMargins(self):
    width = GetScreenSize().width()
    esccsi.DECSTBM(2, 4)
    esccsi.CUP(Point(width - 2, 4))
    escio.Write("a")
    esccsi.REP(3)

    AssertScreenCharsInRectEqual(Rect(1, 3, width, 4),
        [ NUL * (width - 3) + "aaa",
          "a" + NUL * (width - 1) ])
