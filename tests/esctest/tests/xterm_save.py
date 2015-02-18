import esccmd
import escio
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point

class XtermSaveTests(object):
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_XtermSave_SaveSetState(self):
    # Turn on auto-wrap
    esccmd.DECSET(esccmd.DECAWM)

    # Save the setting
    esccmd.XTERM_SAVE(esccmd.DECAWM)

    # Turn off auto-wrap
    esccmd.DECRESET(esccmd.DECAWM)

    # Restore the setting
    esccmd.XTERM_RESTORE(esccmd.DECAWM)

    # Verify that auto-wrap is on
    size = GetScreenSize()
    esccmd.CUP(Point(size.width() - 1, 1))
    escio.Write("xxx")
    AssertEQ(GetCursorPosition().x(), 2)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_XtermSave_SaveResetState(self):
    # Turn off auto-wrap
    esccmd.DECRESET(esccmd.DECAWM)

    # Save the setting
    esccmd.XTERM_SAVE(esccmd.DECAWM)

    # Turn on auto-wrap
    esccmd.DECSET(esccmd.DECAWM)

    # Restore the setting
    esccmd.XTERM_RESTORE(esccmd.DECAWM)

    # Verify that auto-wrap is of
    size = GetScreenSize()
    esccmd.CUP(Point(size.width() - 1, 1))
    escio.Write("xxx")
    AssertEQ(GetCursorPosition().x(), size.width())
