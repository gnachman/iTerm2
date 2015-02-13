from esc import BS, CR, ESC, LF, NUL
import esccsi
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
  DECPCTERM                 Always reset. """
  @knownBug(terminal="iTerm2", reason="iTerm2 fails to reset saved cursor position.")
  def test_DECSTR_DECSC(self):
    # Save cursor position
    esccsi.CUP(Point(5, 6))
    escio.Write(ESC + "7")  # DECSC

    # Perform soft reset
    esccsi.DECSTR()

    # Ensure saved cursor position is the origin
    escio.Write(ESC + "8")  # DECRC
    AssertEQ(GetCursorPosition(), Point(1, 1))

  def test_DECSTR_IRM(self):
    # Turn on insert mode
    esccsi.SM(esccsi.IRM)

    # Perform soft reset
    esccsi.DECSTR()

    # Ensure replace mode is on
    esccsi.CUP(Point(1, 1))
    escio.Write("a")
    esccsi.CUP(Point(1, 1))
    escio.Write("b")
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "b" ])

  def test_DECSTR_DECOM(self):
    # Define a scroll region
    esccsi.DECSTBM(3, 4)

    # Turn on origin mode
    esccsi.DECSET(esccsi.DECOM)

    # Perform soft reset
    esccsi.DECSTR()

    # Define scroll region again
    esccsi.DECSTBM(3, 4)

    # Move to 1,1 (or 3,4 if origin mode is still on) and write an X
    esccsi.CUP(Point(1, 1))
    escio.Write("X")

    # Turn off origin mode
    esccsi.DECRESET(esccsi.DECOM)

    # Make sure the X was at 1, 1, implying origin mode was off.
    esccsi.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "X" ])

  @intentionalDeviationFromSpec(terminal="iTerm2",
                                reason="For compatibility purposes, iTerm2 mimics xterm's behavior of turning on DECAWM by default.")
  @intentionalDeviationFromSpec(terminal="iTerm2",
                                reason="For compatibility purposes, xterm turns on DECAWM by default.")
  def test_DECSTR_DECAWM(self):
    # Turn on autowrap
    esccsi.DECSET(esccsi.DECAWM)

    # Perform soft reset
    esccsi.DECSTR()

    # Make sure autowrap is still on
    esccsi.CUP(Point(GetScreenSize().width() - 1, 1))
    escio.Write("xxx")
    position = GetCursorPosition()
    AssertEQ(position.x(), 2)

  @knownBug(terminal="iTerm2", reason="Reverse wrap is always on in iTerm2")
  def test_DECSTR_ReverseWraparound(self):
    # Turn on reverse wraparound
    esccsi.DECSET(esccsi.ReverseWraparound)

    # Perform soft reset
    esccsi.DECSTR()

    # Verify reverse wrap is off
    esccsi.CUP(Point(GetScreenSize().width() - 1, 2))
    escio.Write("abc" + BS * 3)
    AssertEQ(GetCursorPosition().x(), 1)

  def test_DECSTR_STBM(self):
    # Set top and bottom margins
    esccsi.DECSTBM(3, 4)

    # Perform soft reset
    esccsi.DECSTR()

    # Ensure no margins
    esccsi.CUP(Point(1, 4))
    escio.Write(CR + LF)
    AssertEQ(GetCursorPosition().y(), 5)

  @knownBug(terminal="iTerm2", reason="DECSCA not implemented")
  def test_DECSTR_DECSCA(self):
    # Turn on character protection
    esccsi.DECSCA(1)

    # Perform soft reset
    esccsi.DECSTR()

    # Ensure character protection is off
    esccsi.CUP(Point(1, 1))
    escio.Write("X")
    esccsi.DECSED(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

  def test_DECSTR_DECSASD(self):
    # Direct output to status line
    esccsi.DECSASD(1)

    # Perform soft reset
    esccsi.DECSTR()

    # Ensure output goes to screen
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "X" ])

  def test_DECSTR_DECRLM(self):
    # Set right-to-left mode
    esccsi.DECSET(esccsi.DECRLM)

    # Perform soft reset
    esccsi.DECSTR()

    # Ensure text goes left to right
    esccsi.CUP(Point(2, 1))
    escio.Write("a")
    escio.Write("b")
    AssertScreenCharsInRectEqual(Rect(2, 1, 2, 1), [ "a" ])
    AssertScreenCharsInRectEqual(Rect(3, 1, 3, 1), [ "b" ])

  def test_DECSTR_DECLRMM(self):
    # This isn't in the vt 510 docs but xterm does it and it makes sense to do.
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 6)

    # Perform soft reset
    esccsi.DECSTR()

    # Ensure margins are gone.
    esccsi.CUP(Point(5, 5))
    escio.Write("ab")
    AssertEQ(GetCursorPosition().x(), 7)

  def test_DECSTR_CursorStaysPut(self):
    esccsi.CUP(Point(5, 6))
    esccsi.DECSTR()
    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), 6)
