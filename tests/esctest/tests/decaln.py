import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, Point, Rect, knownBug, optionRequired

class DECALNTests(object):
  def test_DECALN_FillsScreen(self):
    """Makes sure DECALN fills the screen with the letter E (could be anything,
    but xterm uses E). Testing the whole screen would be slow so we just check
    the corners and center."""
    esccmd.DECALN()
    size = GetScreenSize()
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "E" ])
    AssertScreenCharsInRectEqual(Rect(size.width(), 1, size.width(), 1), [ "E" ])
    AssertScreenCharsInRectEqual(Rect(1, size.height(), 1, size.height()), [ "E" ])
    AssertScreenCharsInRectEqual(Rect(size.width(), size.height(), size.width(), size.height()),
                                 [ "E" ])
    AssertScreenCharsInRectEqual(Rect(size.width() / 2,
                                     size.height() / 2,
                                     size.width() / 2,
                                     size.height() / 2),
                                 [ "E" ])

  def test_DECALN_MovesCursorHome(self):
    esccmd.CUP(Point(5, 5))
    esccmd.DECALN()
    AssertEQ(GetCursorPosition(), Point(1, 1))

  def test_DECALN_ClearsMargins(self):
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 3)
    esccmd.DECSTBM(4, 5)
    esccmd.DECALN()

    # Verify we can pass the top margin
    esccmd.CUP(Point(2, 4))
    esccmd.CUU()
    AssertEQ(GetCursorPosition(), Point(2, 3))

    # Verify we can pass the bottom margin
    esccmd.CUP(Point(2, 5))
    esccmd.CUD()
    AssertEQ(GetCursorPosition(), Point(2, 6))

    # Verify we can pass the left margin
    esccmd.CUP(Point(2, 4))
    esccmd.CUB()
    AssertEQ(GetCursorPosition(), Point(1, 4))

    # Verify we can pass the right margin
    esccmd.CUP(Point(3, 4))
    esccmd.CUF()
    AssertEQ(GetCursorPosition(), Point(4, 4))
