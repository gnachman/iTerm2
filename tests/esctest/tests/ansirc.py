import esccsi
from escutil import knownBug
from tests.save_restore_cursor import SaveRestoreCursorTests

class ANSIRCTests(SaveRestoreCursorTests):
  def __init__(self):
    SaveRestoreCursorTests.__init__(self)

  def saveCursor(self):
    esccsi.ANSISC()

  def restoreCursor(self):
    esccsi.ANSIRC()

  @knownBug(terminal="iTerm2", reason="Does not reset origin mode.")
  def test_SaveRestoreCursor_ResetsOriginMode(self):
    SaveRestoreCursorTests.test_SaveRestoreCursor_ResetsOriginMode(self)

  def test_SaveRestoreCursor_WorksInLRM(self, shouldWork=True):
    SaveRestoreCursorTests.test_SaveRestoreCursor_WorksInLRM(self, False)

