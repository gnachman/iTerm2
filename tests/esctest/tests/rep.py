from esc import NUL
import escargs
import esccmd
import escio
from escutil import AssertScreenCharsInRectEqual, GetScreenSize, knownBug, optionRejects, vtLevel
from esctypes import Point, Rect

class REPTests(object):
  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_REP_DefaultParam(self):
    escio.Write("a")
    esccmd.REP()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1), [ "aa" + NUL ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_REP_ExplicitParam(self):
    escio.Write("a")
    esccmd.REP(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 1), [ "aaa" + NUL ])

  # Fixed in xterm #332 (didn't implement auto-wrap mode with margins when wide characters are disabled).
  @vtLevel(4)
  @optionRejects(terminal="notxterm", option=escargs.DISABLE_WIDE_CHARS)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_REP_RespectsLeftRightMargins(self):
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(2, 1))
    escio.Write("a")
    esccmd.REP(3)
    esccmd.DECRESET(esccmd.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 2),
        [ NUL + "aaa" + NUL ,
          NUL + "a" + NUL * 3 ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_REP_RespectsTopBottomMargins(self):
    width = GetScreenSize().width()
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(width - 2, 4))
    escio.Write("a")
    esccmd.REP(3)

    AssertScreenCharsInRectEqual(Rect(1, 3, width, 4),
        [ NUL * (width - 3) + "aaa",
          "a" + NUL * (width - 1) ])
