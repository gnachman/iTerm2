from csitests.save_restore_cursor import SaveRestoreCursorTests
import esccsi
from escutil import knownBug

class DECSETTiteInhibitTests(SaveRestoreCursorTests):
  def saveCursor(self):
    esccsi.CSI_DECSET(esccsi.SaveRestoreCursor)

  def restoreCursor(self):
    esccsi.CSI_DECRESET(esccsi.SaveRestoreCursor)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_SaveRestoreCursor_Basic(self):
    SaveRestoreCursorTests.test_SaveRestoreCursor_Basic(self)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_SaveRestoreCursor_MoveToHomeWhenNotSaved(self):
    SaveRestoreCursorTests.test_SaveRestoreCursor_MoveToHomeWhenNotSaved(self)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_SaveRestoreCursor_ResetsOriginMode(self):
    SaveRestoreCursorTests.test_SaveRestoreCursor_ResetsOriginMode(self)
