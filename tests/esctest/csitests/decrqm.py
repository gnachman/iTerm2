from esc import NUL
import escargs
import esccsi
import escio
import esclog
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetScreenSize, knownBug, vtLevel
from esctypes import Point, Rect

class DECRQMTests(object):
  """DECANM is not tested because there doesn't seem to be any way to
  exit VT52 mode and subsequent tests are broken."""
  def requestAnsiMode(self, mode):
    esccsi.DECRQM(mode, DEC=False)
    return escio.ReadCSI('$y')

  def requestDECMode(self, mode):
    esccsi.DECRQM(mode, DEC=True)
    return escio.ReadCSI('$y', '?')

  def doModifiableAnsiTest(self, mode):
      before = self.requestAnsiMode(mode)
      if before[1] == 2:
        esccsi.SM(mode)
        AssertEQ(self.requestAnsiMode(mode), [ mode, 1 ])

        esccsi.RM(mode)
        AssertEQ(self.requestAnsiMode(mode), [ mode, 2 ])
      else:
        esccsi.RM(mode)
        AssertEQ(self.requestAnsiMode(mode), [ mode, 2 ])

        esccsi.SM(mode)
        AssertEQ(self.requestAnsiMode(mode), [ mode, 1 ])

  def doPermanentlyResetAnsiTest(self, mode):
      AssertEQ(self.requestAnsiMode(mode), [ mode, 4 ])

  def doModifiableDecTest(self, mode):
      before = self.requestDECMode(mode)
      if before[1] == 2:
        esccsi.DECSET(mode)
        AssertEQ(self.requestDECMode(mode), [ mode, 1 ])
        esccsi.DECRESET(mode)
        AssertEQ(self.requestDECMode(mode), [ mode, 2 ])
      else:
        esccsi.DECRESET(mode)
        AssertEQ(self.requestDECMode(mode), [ mode, 2 ])
        esccsi.DECSET(mode)
        AssertEQ(self.requestDECMode(mode), [ mode, 1 ])

  def doPermanentlyResetDecTest(self, mode):
    AssertEQ(self.requestDECMode(mode), [ mode, 4 ])

  # Modifiable ANSI modes ----------------------------------------------------

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.")
  def test_DECRQM(self):
    """See if DECRQM works at all. Unlike all the other tests, this one should
    never have shouldTry=False set. That way if a terminal with a knownBug
    begins supporting DECRQM, this will cease to fail, which is your sign to
    remove the 'DECRQM not supported' knownBug from other tests for that
    terminal."""
    AssertEQ(len(self.requestAnsiMode(esccsi.IRM)), 2)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_KAM(self):
    self.doModifiableAnsiTest(esccsi.KAM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_IRM(self):
    self.doModifiableAnsiTest(esccsi.IRM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_SRM(self):
    self.doModifiableAnsiTest(esccsi.SRM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_LNM(self):
    self.doModifiableAnsiTest(esccsi.LNM)


  # Permanently reset ANSI modes ----------------------------------------------

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_GATM(self):
    self.doPermanentlyResetAnsiTest(esccsi.GATM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_SRTM(self):
    self.doPermanentlyResetAnsiTest(esccsi.SRTM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_VEM(self):
    self.doPermanentlyResetAnsiTest(esccsi.VEM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_HEM(self):
    self.doPermanentlyResetAnsiTest(esccsi.HEM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_PUM(self):
    self.doPermanentlyResetAnsiTest(esccsi.PUM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_FEAM(self):
    self.doPermanentlyResetAnsiTest(esccsi.FEAM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_FETM(self):
    self.doPermanentlyResetAnsiTest(esccsi.FETM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_MATM(self):
    self.doPermanentlyResetAnsiTest(esccsi.MATM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_TTM(self):
    self.doPermanentlyResetAnsiTest(esccsi.TTM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_SATM(self):
    self.doPermanentlyResetAnsiTest(esccsi.SATM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_TSM(self):
    self.doPermanentlyResetAnsiTest(esccsi.TSM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_ANSI_EBM(self):
    self.doPermanentlyResetAnsiTest(esccsi.EBM)


  # Modifiable DEC modes ------------------------------------------------------

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECCKM(self):
    self.doModifiableDecTest(esccsi.DECCKM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECCOLM(self):
    needsPermission = escargs.args.expected_terminal in [ "xterm", "iTerm2" ]
    if needsPermission:
      esccsi.DECSET(esccsi.Allow80To132)
    self.doModifiableDecTest(esccsi.DECCOLM)
    if needsPermission:
      esccsi.DECRESET(esccsi.Allow80To132)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECSCLM(self):
    self.doModifiableDecTest(esccsi.DECSCLM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECSCNM(self):
    self.doModifiableDecTest(esccsi.DECSCNM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECOM(self):
    self.doModifiableDecTest(esccsi.DECOM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECAWM(self):
    self.doModifiableDecTest(esccsi.DECAWM)

  @knownBug(terminal="xterm",
            reason="xterm always returns 4 (permanently reset)")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECARM(self):
    self.doModifiableDecTest(esccsi.DECARM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECPFF(self):
    self.doModifiableDecTest(esccsi.DECPFF)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECPEX(self):
    self.doModifiableDecTest(esccsi.DECPEX)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECTCEM(self):
    self.doModifiableDecTest(esccsi.DECTCEM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECRLM(self):
    self.doModifiableDecTest(esccsi.DECRLM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECHEBM(self):
    self.doModifiableDecTest(esccsi.DECHEBM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECHEM(self):
    """Hebrew encoding mode."""
    self.doModifiableDecTest(esccsi.DECHEM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECNRCM(self):
    self.doModifiableDecTest(esccsi.DECNRCM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECNAKB(self):
    self.doModifiableDecTest(esccsi.DECNAKB)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECVCCM(self):
    self.doModifiableDecTest(esccsi.DECVCCM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECPCCM(self):
    self.doModifiableDecTest(esccsi.DECPCCM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECNKM(self):
    self.doModifiableDecTest(esccsi.DECNKM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECBKM(self):
    self.doModifiableDecTest(esccsi.DECBKM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECKBUM(self):
    self.doModifiableDecTest(esccsi.DECKBUM)

  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECVSSM(self):
    self.doModifiableDecTest(esccsi.DECVSSM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECXRLM(self):
    self.doModifiableDecTest(esccsi.DECXRLM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECKPM(self):
    self.doModifiableDecTest(esccsi.DECKPM)

  @vtLevel(5)
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECNCSM(self):
    needsPermission = escargs.args.expected_terminal in [ "xterm", "iTerm2" ]
    if needsPermission:
      esccsi.DECSET(esccsi.Allow80To132)
    self.doModifiableDecTest(esccsi.DECNCSM)
    needsPermission = escargs.args.expected_terminal in [ "xterm", "iTerm2" ]
    if needsPermission:
      esccsi.DECRESET(esccsi.Allow80To132)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECRLCM(self):
    self.doModifiableDecTest(esccsi.DECRLCM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECCRTSM(self):
    self.doModifiableDecTest(esccsi.DECCRTSM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECARSM(self):
    self.doModifiableDecTest(esccsi.DECARSM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECMCM(self):
    self.doModifiableDecTest(esccsi.DECMCM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECAAM(self):
    self.doModifiableDecTest(esccsi.DECAAM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECCANSM(self):
    self.doModifiableDecTest(esccsi.DECCANSM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECNULM(self):
    self.doModifiableDecTest(esccsi.DECNULM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECHDPXM(self):
    """Set duplex."""
    self.doModifiableDecTest(esccsi.DECHDPXM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECESKM(self):
    self.doModifiableDecTest(esccsi.DECESKM)

  @knownBug(terminal="xterm", reason="Not supported")
  @knownBug(terminal="iTerm2", reason="DECRQM not supported.", shouldTry=False)
  def test_DECRQM_DEC_DECOSCNM(self):
    self.doModifiableDecTest(esccsi.DECOSCNM)

  # Permanently Reset DEC Modes -----------------------------------------------

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
    self.doPermanentlyResetDecTest(esccsi.DECHCCM)

