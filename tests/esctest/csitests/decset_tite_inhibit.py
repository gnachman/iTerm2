from csitests.save_restore_cursor import SaveRestoreCursorTests
import esccsi
from escutil import knownBug

class DECSETTiteInhibitTests(SaveRestoreCursorTests):
  def __init__(self):
    SaveRestoreCursorTests.__init__(self)

  def saveCursor(self):
    esccsi.DECSET(esccsi.SaveRestoreCursor)

  def restoreCursor(self):
    esccsi.DECRESET(esccsi.SaveRestoreCursor)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_SaveRestoreCursor_Basic(self):
    SaveRestoreCursorTests.test_SaveRestoreCursor_Basic(self)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_SaveRestoreCursor_MoveToHomeWhenNotSaved(self):
    SaveRestoreCursorTests.test_SaveRestoreCursor_MoveToHomeWhenNotSaved(self)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_SaveRestoreCursor_ResetsOriginMode(self):
    SaveRestoreCursorTests.test_SaveRestoreCursor_ResetsOriginMode(self)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_SaveRestoreCursor_WorksInLRM(self, shouldWork=True):
    SaveRestoreCursorTests.test_SaveRestoreCursor_WorksInLRM(self)
