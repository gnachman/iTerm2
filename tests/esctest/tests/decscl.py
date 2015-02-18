from esc import ESC, NUL
import esccmd
import escio
import esclog
from escutil import AssertEQ, AssertScreenCharsInRectEqual, AssertTrue, GetCursorPosition, GetScreenSize, knownBug, vtLevel
from esctypes import InternalError, Point, Rect

""" level 1, 2, 3, 4
RIS on change
7 vs 8 bit
"""

class DECSCLTests(object):
  """VT Level 1 doesn't have any distinguishing features that are testable that
  aren't also in level 2."""
  @vtLevel(2)
  @knownBug(terminal="xterm", reason="xterm always turns on 8-bit controls.", shouldTry=False)
  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't implement DECSCL")
  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't implement DECRQM", shouldTry=False)
  def test_DECSCL_Level2DoesntSupportDECRQM(self):
    """VT level 2 does not support DECRQM."""
    escio.Write("Hello world.")
    GetScreenSize()
    esccmd.DECSCL(62, 1)
    GetScreenSize()
    # Make sure DECRQM fails.
    try:
      esccmd.DECRQM(esccmd.IRM, DEC=False)
      escio.ReadCSI('$y')
      # Should not get here.
      AssertTrue(False)
    except InternalError, e:
      # Assert something so the test infrastructure is happy.
      AssertTrue(True)

  @vtLevel(2)
  @knownBug(terminal="xterm", reason="xterm always turns on 8-bit controls.", shouldTry=False)
  def test_DSCSCL_Level2Supports7BitControls(self):
    esccmd.DECSCL(62, 1)
    esccmd.CUP(Point(2, 2))
    AssertEQ(GetCursorPosition(), Point(2, 2))

  @vtLevel(3)
  @knownBug(terminal="xterm", reason="xterm always turns on 8-bit controls.", shouldTry=False)
  @knownBug(terminal="iTerm2", reason="Not implemented", shouldTry=False)
  def test_DSCSCL_Level3_SupportsDECRQMDoesntSupportDECSLRM(self):
    # Set level 3 conformance
    esccmd.DECSCL(63, 1)

    # Make sure DECRQM is ok.
    esccmd.DECRQM(esccmd.IRM, DEC=False)
    escio.ReadCSI('$y')

    # Make sure DECSLRM fails.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 6)
    esccmd.CUP(Point(5, 1))
    escio.Write("abc")
    AssertEQ(GetCursorPosition().x(), 8)

  @vtLevel(4)
  @knownBug(terminal="xterm", reason="xterm always turns on 8-bit controls.", shouldTry=False)
  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't implement DECSCL")
  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't implement DECNCSM", shouldTry=False)
  def test_DECSCL_Level4_SupportsDECSLRMDoesntSupportDECNCSM(self):
    # Set level 4 conformance
    esccmd.DECSCL(64, 1)

    # Enable DECCOLM.
    esccmd.DECSET(esccmd.Allow80To132)

    # Set DECNCSM, Set column mode. Screen should be cleared anyway.
    esccmd.DECRESET(esccmd.DECCOLM)
    esccmd.DECSET(esccmd.DECNCSM)
    esccmd.CUP(Point(1, 1))
    escio.Write("1")
    esccmd.DECSET(esccmd.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

    # Make sure DECSLRM succeeds.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 6)
    esccmd.CUP(Point(5, 1))
    escio.Write("abc")
    AssertEQ(GetCursorPosition().x(), 6)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="xterm always turns on 8-bit controls.", shouldTry=False)
  @knownBug(terminal="iTerm2", reason="Not implemented", shouldTry=False)
  def test_DECSCL_Level5_SupportsDECNCSM(self):
    # Set level 5 conformance
    esccmd.DECSCL(65, 1)

    # Set DECNCSM, Set column mode. Screen should not be cleared.
    esccmd.DECRESET(esccmd.DECCOLM)
    esccmd.DECSET(esccmd.DECNCSM)
    esccmd.CUP(Point(1, 1))
    escio.Write("1")
    esccmd.DECSET(esccmd.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "1" ])

  @vtLevel(3)
  @knownBug(terminal="xterm", reason="xterm always turns on 8-bit controls.", shouldTry=False)
  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't implement DECSCL")
  def test_DECSCL_RISOnChange(self):
    """DECSCL should do an RIS. RIS does a lot, so we'll just test a few
    things. This may not be true for VT220's, though, to quote the xterm code:

      VT300, VT420, VT520 manuals claim that DECSCL does a
      hard reset (RIS).  VT220 manual states that it is a soft
      reset.  Perhaps both are right (unlikely).  Kermit says
      it's soft.

    So that's why this test is for vt level 3 and up."""
    escio.Write("x")

    # Set saved cursor position
    esccmd.CUP(Point(5, 6))
    esccmd.DECSC()

    # Turn on insert mode
    esccmd.SM(esccmd.IRM)

    esccmd.DECSCL(61)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

    # Ensure saved cursor position is the origin
    esccmd.DECRC()
    AssertEQ(GetCursorPosition(), Point(1, 1))

    # Ensure replace mode is on
    esccmd.CUP(Point(1, 1))
    escio.Write("a")
    esccmd.CUP(Point(1, 1))
    escio.Write("b")
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "b" ])
