import esccsi
import escio
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point

class XtermSaveTests(object):
  def __init__(self, args):
    self._args = args

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_XtermSave_SaveSetState(self):
    # Turn on auto-wrap
    esccsi.CSI_DECSET(esccsi.DECAWM)

    # Save the setting
    esccsi.CSI_XTERM_SAVE(esccsi.DECAWM)

    # Turn off auto-wrap
    esccsi.CSI_DECRESET(esccsi.DECAWM)

    # Restore the setting
    esccsi.CSI_XTERM_RESTORE(esccsi.DECAWM)

    # Verify that auto-wrap is on
    size = GetScreenSize()
    esccsi.CSI_CUP(Point(size.width() - 1, 1))
    escio.Write("xxx")
    AssertEQ(GetCursorPosition().x(), 2)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_XtermSave_SaveResetState(self):
    # Turn off auto-wrap
    esccsi.CSI_DECRESET(esccsi.DECAWM)

    # Save the setting
    esccsi.CSI_XTERM_SAVE(esccsi.DECAWM)

    # Turn on auto-wrap
    esccsi.CSI_DECSET(esccsi.DECAWM)

    # Restore the setting
    esccsi.CSI_XTERM_RESTORE(esccsi.DECAWM)

    # Verify that auto-wrap is of
    size = GetScreenSize()
    esccsi.CSI_CUP(Point(size.width() - 1, 1))
    escio.Write("xxx")
    AssertEQ(GetCursorPosition().x(), size.width())
