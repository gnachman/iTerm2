import esccsi
import escio
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point

class XtermSaveTests(object):
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_XtermSave_SaveSetState(self):
    # Turn on auto-wrap
    esccsi.DECSET(esccsi.DECAWM)

    # Save the setting
    esccsi.XTERM_SAVE(esccsi.DECAWM)

    # Turn off auto-wrap
    esccsi.DECRESET(esccsi.DECAWM)

    # Restore the setting
    esccsi.XTERM_RESTORE(esccsi.DECAWM)

    # Verify that auto-wrap is on
    size = GetScreenSize()
    esccsi.CUP(Point(size.width() - 1, 1))
    escio.Write("xxx")
    AssertEQ(GetCursorPosition().x(), 2)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_XtermSave_SaveResetState(self):
    # Turn off auto-wrap
    esccsi.DECRESET(esccsi.DECAWM)

    # Save the setting
    esccsi.XTERM_SAVE(esccsi.DECAWM)

    # Turn on auto-wrap
    esccsi.DECSET(esccsi.DECAWM)

    # Restore the setting
    esccsi.XTERM_RESTORE(esccsi.DECAWM)

    # Verify that auto-wrap is of
    size = GetScreenSize()
    esccsi.CUP(Point(size.width() - 1, 1))
    escio.Write("xxx")
    AssertEQ(GetCursorPosition().x(), size.width())
