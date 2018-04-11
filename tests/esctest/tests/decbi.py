from esc import blank
import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, Point, Rect, intentionalDeviationFromSpec, knownBug, optionRequired, vtLevel

class DECBITests(object):
  """Move cursor back or scroll data within margins right."""
  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented.")
  def test_DECBI_Basic(self):
    esccmd.CUP(Point(5, 6))
    esccmd.DECBI()
    AssertEQ(GetCursorPosition(), Point(4, 6))

  @knownBug(terminal="iTerm2", reason="Not implemented.", noop=True)
  @vtLevel(4)
  def test_DECBI_NoWrapOnLeftEdge(self):
    esccmd.CUP(Point(1, 2))
    esccmd.DECBI()
    AssertEQ(GetCursorPosition(), Point(1, 2))

  @knownBug(terminal="iTerm2", reason="Not implemented.")
  @vtLevel(4)
  def test_DECBI_Scrolls(self):
    strings = [ "abcde",
                "fghij",
                "klmno",
                "pqrst",
                "uvwxy" ]
    y = 3
    for s in strings:
      esccmd.CUP(Point(2, y))
      escio.Write(s)
      y += 1

    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(3, 5)
    esccmd.DECSTBM(4, 6)

    esccmd.CUP(Point(3, 5))
    esccmd.DECBI()

    AssertScreenCharsInRectEqual(Rect(2, 3, 6, 7),
                                 [ "abcde",
                                   "f" + blank() + "ghj",
                                   "k" + blank() + "lmo",
                                   "p" + blank() + "qrt",
                                   "uvwxy" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented.")
  # DEC STD 070 says DECBI can move when outside the margins.
  def test_DECBI_LeftOfMargin(self):
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(3, 5)
    esccmd.CUP(Point(2, 1))
    esccmd.DECBI()
    AssertEQ(GetCursorPosition(), Point(1, 1))

  @knownBug(terminal="iTerm2", reason="Not implemented.")
  @vtLevel(4)
  # Refer to DEC STD 070, which says if the cursor is outside the margins, at
  # the left edge of the page, the command is ignored.
  def test_DECBI_WholeScreenScrolls(self):
    escio.Write("x")
    esccmd.CUP(Point(1, 1))
    esccmd.DECBI()
    AssertScreenCharsInRectEqual(Rect(1, 1, 2, 1), [ blank() + "x" ])


