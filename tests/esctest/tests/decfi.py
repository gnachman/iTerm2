from esc import blank, NUL
import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, Point, Rect, intentionalDeviationFromSpec, knownBug, optionRequired, vtLevel

class DECFITests(object):
  """Move cursor forward or scroll data within margins right."""
  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented.")
  def test_DECFI_Basic(self):
    esccmd.CUP(Point(5, 6))
    esccmd.DECFI()
    AssertEQ(GetCursorPosition(), Point(6, 6))

  @knownBug(terminal="iTerm2", reason="Not implemented.", noop=True)
  @vtLevel(4)
  def test_DECFI_NoWrapOnRightEdge(self):
    size = GetScreenSize()
    esccmd.CUP(Point(size.width(), 2))
    esccmd.DECFI()
    AssertEQ(GetCursorPosition(), Point(size.width(), 2))

  @knownBug(terminal="iTerm2", reason="Not implemented.")
  @vtLevel(4)
  def test_DECFI_Scrolls(self):
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

    esccmd.CUP(Point(5, 5))
    esccmd.DECFI()

    # It is out of character for xterm to use NUL in the middle of the line,
    # but not terribly important, and not worth marking as a bug. I mentioned
    # it to TED.
    AssertScreenCharsInRectEqual(Rect(2, 3, 6, 7),
                                 [ "abcde",
                                   "fhi" + NUL + "j",
                                   "kmn" + NUL + "o",
                                   "prs" + NUL + "t",
                                   "uvwxy" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented.")
  @knownBug(terminal="xterm",
            reason="While the docs for DECFI are self-contradictory, I believe the cursor should move in this case. xterm does not move it.")
  def test_DECFI_RightOfMargin(self):
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(3, 5)
    esccmd.CUP(Point(6, 1))
    esccmd.DECFI()
    AssertEQ(GetCursorPosition(), Point(7, 1))

  @knownBug(terminal="iTerm2", reason="Not implemented.")
  @vtLevel(4)
  @intentionalDeviationFromSpec(terminal="xterm",
                                reason="The spec says 'If the cursor is at the right border of the page when the terminal receives DECFI, then the terminal ignores DECFI', but that only makes sense when the right margin is not at the right edge of the screen.")
  def test_DECFI_WholeScreenScrolls(self):
    """The spec is confusing and contradictory. It first says "If the cursor is
    at the right margin, then all screen data within the margin moves one column
    to the left" and then says "DECFI is not affected by the margins." I don't
    know what they could mean by the second part."""
    size = GetScreenSize()
    esccmd.CUP(Point(size.width(), 1))
    escio.Write("x")
    esccmd.DECFI()
    AssertScreenCharsInRectEqual(Rect(size.width() - 1, 1, size.width(), 1), [ "x" + NUL ])


