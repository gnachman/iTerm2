from esc import NUL
import escargs
import esccmd
import escio
import esclog
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetScreenSize, knownBug, optionRequired, vtLevel
from esctypes import Point, Rect

class DECRQMTests(object):
  """DECANM is not tested because there doesn't seem to be any way to
  exit VT52 mode and subsequent tests are broken."""
  def requestAnsiMode(self, mode):
    esccmd.DECRQM(mode, DEC=False)
    return escio.ReadCSI('$y')

  def requestDECMode(self, mode):
    esccmd.DECRQM(mode, DEC=True)
    return escio.ReadCSI('$y', '?')

  def doModifiableAnsiTest(self, mode):
      before = self.requestAnsiMode(mode)
      if before[1] == 2:
        esccmd.SM(mode)
        AssertEQ(self.requestAnsiMode(mode), [ mode, 1 ])

        esccmd.RM(mode)
        AssertEQ(self.requestAnsiMode(mode), [ mode, 2 ])
      else:
        esccmd.RM(mode)
        AssertEQ(self.requestAnsiMode(mode), [ mode, 2 ])

        esccmd.SM(mode)
        AssertEQ(self.requestAnsiMode(mode), [ mode, 1 ])

  def doPermanentlyResetAnsiTest(self, mode):
      AssertEQ(self.requestAnsiMode(mode), [ mode, 4 ])

  def doModifiableDecTest(self, mode):
      before = self.requestDECMode(mode)
      if before[1] == 2:
        esccmd.DECSET(mode)
        AssertEQ(self.requestDECMode(mode), [ mode, 1 ])
        esccmd.DECRESET(mode)
        AssertEQ(self.requestDECMode(mode), [ mode, 2 ])
      else:
        esccmd.DECRESET(mode)
        AssertEQ(self.requestDECMode(mode), [ mode, 2 ])
        esccmd.DECSET(mode)
        AssertEQ(self.requestDECMode(mode), [ mode, 1 ])

  def doPermanentlyResetDecTest(self, mode):
    AssertEQ(self.requestDECMode(mode), [ mode, 4 ])

  # Modifiable ANSI modes ----------------------------------------------------

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.")
  def test_DECRQM(self):
    """See if DECRQM works at all. Unlike all the other tests, this one should
    never have shouldTry=False set. That way if a terminal with a knownBug
    begins supporting DECRQM, this will cease to fail, which is your sign to
    remove the 'DECRQM not supported' knownBug from other tests for that
    terminal."""
    AssertEQ(len(self.requestAnsiMode(esccmd.IRM)), 2)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_KAM(self):
    self.doModifiableAnsiTest(esccmd.KAM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_IRM(self):
    self.doModifiableAnsiTest(esccmd.IRM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_SRM(self):
    self.doModifiableAnsiTest(esccmd.SRM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_LNM(self):
    self.doModifiableAnsiTest(esccmd.LNM)


  # Permanently reset ANSI modes ----------------------------------------------

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_GATM(self):
    self.doPermanentlyResetAnsiTest(esccmd.GATM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_SRTM(self):
    self.doPermanentlyResetAnsiTest(esccmd.SRTM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_VEM(self):
    self.doPermanentlyResetAnsiTest(esccmd.VEM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_HEM(self):
    self.doPermanentlyResetAnsiTest(esccmd.HEM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_PUM(self):
    self.doPermanentlyResetAnsiTest(esccmd.PUM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_FEAM(self):
    self.doPermanentlyResetAnsiTest(esccmd.FEAM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_FETM(self):
    self.doPermanentlyResetAnsiTest(esccmd.FETM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_MATM(self):
    self.doPermanentlyResetAnsiTest(esccmd.MATM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_TTM(self):
    self.doPermanentlyResetAnsiTest(esccmd.TTM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_SATM(self):
    self.doPermanentlyResetAnsiTest(esccmd.SATM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_TSM(self):
    self.doPermanentlyResetAnsiTest(esccmd.TSM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_EBM(self):
    self.doPermanentlyResetAnsiTest(esccmd.EBM)


  # Modifiable DEC modes ------------------------------------------------------

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECCKM(self):
    self.doModifiableDecTest(esccmd.DECCKM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECCOLM(self):
    needsPermission = escargs.args.expected_terminal in [ "xterm", "iTerm2" ]
    if needsPermission:
      esccmd.DECSET(esccmd.Allow80To132)
    self.doModifiableDecTest(esccmd.DECCOLM)
    if needsPermission:
      esccmd.DECRESET(esccmd.Allow80To132)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECSCLM(self):
    self.doModifiableDecTest(esccmd.DECSCLM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECSCNM(self):
    self.doModifiableDecTest(esccmd.DECSCNM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECOM(self):
    self.doModifiableDecTest(esccmd.DECOM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECAWM(self):
    self.doModifiableDecTest(esccmd.DECAWM)

  @vtLevel(3)
  @knownBug(terminal="xterm",
            reason="xterm always returns 4 (permanently reset)")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECARM(self):
    self.doModifiableDecTest(esccmd.DECARM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECPFF(self):
    self.doModifiableDecTest(esccmd.DECPFF)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECPEX(self):
    self.doModifiableDecTest(esccmd.DECPEX)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECTCEM(self):
    self.doModifiableDecTest(esccmd.DECTCEM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECRLM(self):
    self.doModifiableDecTest(esccmd.DECRLM)

  @vtLevel(5)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECHEBM(self):
    self.doModifiableDecTest(esccmd.DECHEBM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECHEM(self):
    """Hebrew encoding mode."""
    self.doModifiableDecTest(esccmd.DECHEM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECNRCM(self):
    self.doModifiableDecTest(esccmd.DECNRCM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECNAKB(self):
    self.doModifiableDecTest(esccmd.DECNAKB)

  @vtLevel(3)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECVCCM(self):
    self.doModifiableDecTest(esccmd.DECVCCM)

  @vtLevel(3)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECPCCM(self):
    self.doModifiableDecTest(esccmd.DECPCCM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECNKM(self):
    self.doModifiableDecTest(esccmd.DECNKM)

  @vtLevel(3)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECBKM(self):
    self.doModifiableDecTest(esccmd.DECBKM)

  @vtLevel(3)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECKBUM(self):
    self.doModifiableDecTest(esccmd.DECKBUM)

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECLRMM(self):
    self.doModifiableDecTest(esccmd.DECLRMM)

  @vtLevel(4)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECXRLM(self):
    self.doModifiableDecTest(esccmd.DECXRLM)

  @vtLevel(4)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECKPM(self):
    self.doModifiableDecTest(esccmd.DECKPM)

  @vtLevel(5)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  @optionRequired(terminal="xterm",
                  option=escargs.XTERM_WINOPS_ENABLED)
  def test_DECRQM_DEC_DECNCSM(self):
    needsPermission = escargs.args.expected_terminal in [ "xterm", "iTerm2" ]
    if needsPermission:
      esccmd.DECSET(esccmd.Allow80To132)
    self.doModifiableDecTest(esccmd.DECNCSM)
    needsPermission = escargs.args.expected_terminal in [ "xterm", "iTerm2" ]
    if needsPermission:
      esccmd.DECRESET(esccmd.Allow80To132)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECRLCM(self):
    self.doModifiableDecTest(esccmd.DECRLCM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECCRTSM(self):
    self.doModifiableDecTest(esccmd.DECCRTSM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECARSM(self):
    self.doModifiableDecTest(esccmd.DECARSM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECMCM(self):
    self.doModifiableDecTest(esccmd.DECMCM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECAAM(self):
    self.doModifiableDecTest(esccmd.DECAAM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECCANSM(self):
    self.doModifiableDecTest(esccmd.DECCANSM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECNULM(self):
    self.doModifiableDecTest(esccmd.DECNULM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECHDPXM(self):
    """Set duplex."""
    self.doModifiableDecTest(esccmd.DECHDPXM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECESKM(self):
    self.doModifiableDecTest(esccmd.DECESKM)

  @vtLevel(5)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECOSCNM(self):
    self.doModifiableDecTest(esccmd.DECOSCNM)

  # Permanently Reset DEC Modes -----------------------------------------------

  @vtLevel(3)
  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECHCCM(self):
    """Here's what the official docs have to say:

      Normally, when you horizontally change the size of your window or
      terminal (for example, from 132 columns to 80 columns), the cursor is not
      visible.  You can change this default by clicking on the Horizontal
      Cursor Coupling option.

    I also found this on carleton.edu:

      Check the Horizontal Cursor Coupling check box if you want the horizontal
      scrollbar to be adjusted automatically when the cursor moves to always
      keep the column with the cursor on the visible portion of the display.

    I gather this is irrelevant if your terminal doesn't support horizontal
    scrolling."""
    self.doPermanentlyResetDecTest(esccmd.DECHCCM)

