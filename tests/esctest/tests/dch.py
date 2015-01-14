from esc import NUL
import esccmd
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug

class DCHTests(object):
  def test_DCH_DefaultParam(self):
    """DCH with no parameter should delete one character at the cursor."""
    escio.Write("abcd")
    esccmd.CUP(Point(2, 1))
    esccmd.DCH()
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 1), [ "acd" + NUL ]);

  def test_DCH_ExplicitParam(self):
    """DCH deletes the specified number of parameters."""
    escio.Write("abcd")
    esccmd.CUP(Point(2, 1))
    esccmd.DCH(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 1), [ "ad" + NUL * 2 ]);

  def test_DCH_RespectsMargins(self):
    """DCH respects left-right margins."""
    escio.Write("abcde")
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(3, 1))
    esccmd.DCH()
    esccmd.DECRESET(esccmd.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 1), [ "abd" + NUL + "e" ]);

  def test_DCH_DeleteAllWithMargins(self):
    """Delete all characters up to right margin."""
    escio.Write("abcde")
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(3, 1))
    esccmd.DCH(99)
    esccmd.DECRESET(esccmd.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 1), [ "ab" + NUL * 2 + "e" ]);

  def test_DCH_DoesNothingOutsideLeftRightMargin(self):
    """DCH should do nothing outside left-right margins."""
    escio.Write("abcde")
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(1, 1))
    esccmd.DCH(99)
    esccmd.DECRESET(esccmd.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 1), [ "abcde" ])

  @knownBug(terminal="xterm", reason="DCH operates on the current line when outside the scroll region in xterm.")
  @knownBug(terminal="xterm", reason="Assertion fires", shouldTry=False)
  @knownBug(terminal="iTerm2", reason="DCH operates on the current line when outside the scroll region in iTerm2.")
  @knownBug(terminal="Terminal.app", reason="DCH operates on the current line when outside the scroll region in Terminal.app.")
  def test_DCH_DoesNothingOutsideTopBottomMargin(self):
    """DCH should do nothing outside top-bottom margins."""
    escio.Write("abcde")
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(1, 1))
    esccmd.DCH(99)
    esccmd.DECSTBM()

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 1), [ "abcde" ])
