from esc import BS, CR, ESC, LF, NUL
import esccmd
import escio
import esclog
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, intentionalDeviationFromSpec, knownBug
from esctypes import Point, Rect

class DECSTRTests(object):
  """The following settings are reset:

  DECTCEM                   Cursor enabled.
  IRM                       Replace mode.
  DECOM                     Absolute (cursor origin at upper-left of screen.)
  DECAWM                    No autowrap.
  DECNRCM                   Multinational set.
  KAM                       Unlocked.
  DECNKM                    Numeric characters.
  DECCKM                    Normal (arrow keys).
  DECSTBM                   Top margin = 1; bottom margin = page length.
  G0, G1, G2, G3, GL, GR    Default settings.
  SGR                       Normal rendition.
  DECSCA                    Normal (erasable by DECSEL and DECSED).
  DECSC                     Home position.
  DECAUPSS                  Set selected in Set-Up.
  DECSASD                   Main display.
  DECKPM                    Character codes.
  DECRLM                    Reset (Left-to-right), regardless of NVR setting.
  DECPCTERM                 Always reset."""

  def test_DECSTR_DECSC(self):
    # Save cursor position
    esccmd.CUP(Point(5, 6))
    esccmd.DECSC()

    # Perform soft reset
    esccmd.DECSTR()

    # Ensure saved cursor position is the origin
    esccmd.DECRC()
    AssertEQ(GetCursorPosition(), Point(1, 1))

  def test_DECSTR_IRM(self):
    # Turn on insert mode
    esccmd.SM(esccmd.IRM)

    # Perform soft reset
    esccmd.DECSTR()

    # Ensure replace mode is on
    esccmd.CUP(Point(1, 1))
    escio.Write("a")
    esccmd.CUP(Point(1, 1))
    escio.Write("b")
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "b" ])

  def test_DECSTR_DECOM(self):
    # Define a scroll region
    esccmd.DECSTBM(3, 4)

    # Turn on origin mode
    esccmd.DECSET(esccmd.DECOM)

    # Perform soft reset
    esccmd.DECSTR()

    # Define scroll region again
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(3, 4)
    esccmd.DECSTBM(4, 5)

    # Move to 1,1 (or 3,4 if origin mode is still on) and write an X
    esccmd.CUP(Point(1, 1))
    escio.Write("X")

    # Turn off origin mode
    esccmd.DECRESET(esccmd.DECOM)

    # Make sure the X was at 1, 1, implying origin mode was off.
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 4), [ "X" + NUL * 2,
                                                     NUL * 3,
                                                     NUL * 3,
                                                     NUL * 3 ])

  @intentionalDeviationFromSpec(terminal="iTerm2",
                                reason="For compatibility purposes, iTerm2 mimics xterm's behavior of turning on DECAWM by default.")
  @intentionalDeviationFromSpec(terminal="iTerm2",
                                reason="For compatibility purposes, xterm turns on DECAWM by default.")
  def test_DECSTR_DECAWM(self):
    # Turn on autowrap
    esccmd.DECSET(esccmd.DECAWM)

    # Perform soft reset
    esccmd.DECSTR()

    # Make sure autowrap is still on
    esccmd.CUP(Point(GetScreenSize().width() - 1, 1))
    escio.Write("xxx")
    position = GetCursorPosition()
    AssertEQ(position.x(), 2)

  def test_DECSTR_ReverseWraparound(self):
    # Turn on reverse wraparound
    esccmd.DECSET(esccmd.ReverseWraparound)

    # Perform soft reset
    esccmd.DECSTR()

    # Verify reverse wrap is off
    esccmd.CUP(Point(1, 2))
    escio.Write(BS)
    AssertEQ(GetCursorPosition().x(), 1)

  def test_DECSTR_STBM(self):
    # Set top and bottom margins
    esccmd.DECSTBM(3, 4)

    # Perform soft reset
    esccmd.DECSTR()

    # Ensure no margins
    esccmd.CUP(Point(1, 4))
    escio.Write(CR + LF)
    AssertEQ(GetCursorPosition().y(), 5)

  @knownBug(terminal="iTerm2", reason="DECSCA not implemented")
  def test_DECSTR_DECSCA(self):
    # Turn on character protection
    esccmd.DECSCA(1)

    # Perform soft reset
    esccmd.DECSTR()

    # Ensure character protection is off
    esccmd.CUP(Point(1, 1))
    escio.Write("X")
    esccmd.DECSED(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

  def test_DECSTR_DECSASD(self):
    # Direct output to status line
    esccmd.DECSASD(1)

    # Perform soft reset
    esccmd.DECSTR()

    # Ensure output goes to screen
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "X" ])

  def test_DECSTR_DECRLM(self):
    # Set right-to-left mode
    esccmd.DECSET(esccmd.DECRLM)

    # Perform soft reset
    esccmd.DECSTR()

    # Ensure text goes left to right
    esccmd.CUP(Point(2, 1))
    escio.Write("a")
    escio.Write("b")
    AssertScreenCharsInRectEqual(Rect(2, 1, 2, 1), [ "a" ])
    AssertScreenCharsInRectEqual(Rect(3, 1, 3, 1), [ "b" ])

  def test_DECSTR_DECLRMM(self):
    # This isn't in the vt 510 docs but xterm does it and it makes sense to do.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 6)

    # Perform soft reset
    esccmd.DECSTR()

    # Ensure margins are gone.
    esccmd.CUP(Point(5, 5))
    escio.Write("ab")
    AssertEQ(GetCursorPosition().x(), 7)

  def test_DECSTR_CursorStaysPut(self):
    esccmd.CUP(Point(5, 6))
    esccmd.DECSTR()
    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), 6)
