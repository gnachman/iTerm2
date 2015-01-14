from tests.save_restore_cursor import SaveRestoreCursorTests
import esccmd
from escutil import knownBug

class DECSETTiteInhibitTests(SaveRestoreCursorTests):
  def __init__(self):
    SaveRestoreCursorTests.__init__(self)

  def saveCursor(self):
    esccmd.DECSET(esccmd.SaveRestoreCursor)

  def restoreCursor(self):
    esccmd.DECRESET(esccmd.SaveRestoreCursor)

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
