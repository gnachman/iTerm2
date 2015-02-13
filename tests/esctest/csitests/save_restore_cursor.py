# Restoring the cursor does the following things that are not testable:
# * Turn off character attributes
# * Maps the ASCII character set into GL, and the DEC Supplemental Graphic set into GR.
# * Status bar has a separate saved cursor.

# From the Xterm docs, there are several variants of DECRC with different names.

# * CSI u (ANSI RC)
#     ANSI version of DECRC.
# * ESC 8 (DECRC)
#     Restore cursor. Same as CSI u.
# * CSI ? 1048 l (DECRESET TITE INHIBIT)
#     XTerm extension, same as CSI u but can be disabled by a resource.

# Likewise, DECSC can be done with:
# * CSI s (ANSI SC)
#     ANSI version of DECSC, but is disabled in left-right mode (DECSLRM).
# * ESC 7 (DECSC)
#     Saves the cursor
# * CSI ? 1048 h (DECSET TITE INHIBIT)
#     XTerm extension, same as ESC 7 but can be disabled by a resource.
import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, Rect, knownBug
from esctypes import Point

class SaveRestoreCursorTests(object):
  """Base class for ANSI SC/RC, DECRC/DECSC, and DECSET/DECRESET TITE
  INHIBIT. Subclasses should implement saveCursor() and restoreCursor()."""
  def __init__(self, args):
    self._args = args

  def test_SaveRestoreCursor_Basic(self):
    esccsi.CUP(Point(5, 6))
    self.saveCursor()
    esccsi.CUP(Point(1, 1))
    self.restoreCursor()
    AssertEQ(GetCursorPosition(), Point(5, 6))

  def test_SaveRestoreCursor_MoveToHomeWhenNotSaved(self):
    esccsi.DECSTR()
    esccsi.CUP(Point(5, 6))
    self.restoreCursor()
    AssertEQ(GetCursorPosition(), Point(1, 1))

  def test_SaveRestoreCursor_ResetsOriginMode(self):
    esccsi.CUP(Point(5, 6))
    self.saveCursor()

    # Set up margins.
    esccsi.DECSTBM(5, 7)
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 7)

    # Enter origin mode.
    esccsi.DECSET(esccsi.DECOM)

    # Do DECRC, which should reset origin mode.
    self.restoreCursor()

    # Move home
    esccsi.CUP(Point(1, 1))

    # Place an X at cursor, which should be at (1, 1) if DECOM was reset.
    escio.Write("X")

    # Remove margins and ensure origin mode is off for valid test.
    esccsi.DECRESET(esccsi.DECLRMM)
    esccsi.DECSTBM()
    esccsi.DECRESET(esccsi.DECOM)

    # Ensure the X was placed at the true origin
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "X" ])

  def test_SaveRestoreCursor_WorksInLRM(self, shouldWork=True):
    """Subclasses may cause shouldWork to be set to false."""
    esccsi.CUP(Point(2, 3))
    self.saveCursor()
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(1, 10)
    esccsi.CUP(Point(5, 6))
    self.saveCursor()

    esccsi.CUP(Point(4, 5))
    self.restoreCursor()

    if shouldWork:
      AssertEQ(GetCursorPosition(), Point(5, 6))
    else:
      AssertEQ(GetCursorPosition(), Point(2, 3))
