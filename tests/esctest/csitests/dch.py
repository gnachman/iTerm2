from esc import NUL
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug

class DCHTests(object):
  def test_DCH_DefaultParam(self):
    """DCH with no parameter should delete one character at the cursor."""
    escio.Write("abcd")
    esccsi.CUP(Point(2, 1))
    esccsi.DCH()
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 1), [ "acd" + NUL ]);

  def test_DCH_ExplicitParam(self):
    """DCH deletes the specified number of parameters."""
    escio.Write("abcd")
    esccsi.CUP(Point(2, 1))
    esccsi.DCH(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 1), [ "ad" + NUL * 2 ]);

  def test_DCH_RespectsMargins(self):
    """DCH respects left-right margins."""
    escio.Write("abcde")
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.CUP(Point(3, 1))
    esccsi.DCH()
    esccsi.DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 1), [ "abd" + NUL + "e" ]);

  def test_DCH_DeleteAllWithMargins(self):
    """Delete all characters up to right margin."""
    escio.Write("abcde")
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.CUP(Point(3, 1))
    esccsi.DCH(99)
    esccsi.DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 1), [ "ab" + NUL * 2 + "e" ]);

  def test_DCH_DoesNothingOutsideLeftRightMargin(self):
    """DCH should do nothing outside left-right margins."""
    escio.Write("abcde")
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    esccsi.CUP(Point(1, 1))
    esccsi.DCH(99)
    esccsi.DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 1), [ "abcde" ])

  @knownBug(terminal="xterm", reason="DCH operates on the current line when outside the scroll region in xterm.")
  @knownBug(terminal="iTerm2", reason="DCH operates on the current line when outside the scroll region in iTerm2.")
  @knownBug(terminal="Terminal.app", reason="DCH operates on the current line when outside the scroll region in Terminal.app.")
  def test_DCH_DoesNothingOutsideTopBottomMargin(self):
    """DCH should do nothing outside top-bottom margins."""
    escio.Write("abcde")
    esccsi.DECSTBM(2, 3)
    esccsi.CUP(Point(1, 1))
    esccsi.DCH(99)
    esccsi.DECSTBM()

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 1), [ "abcde" ])
