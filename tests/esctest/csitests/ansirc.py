import csitests.save_restore_cursor
import esccsi
from escutil import knownBug

class ANSIRCTests(csitests.save_restore_cursor.SaveRestoreCursorTests):
  def saveCursor(self):
    esccsi.CSI_ANSISC()

  def restoreCursor(self):
    esccsi.CSI_ANSIRC()

  @knownBug(terminal="iTerm2", reason="Does not reset origin mode.")
  def test_SaveRestoreCursor_ResetsOriginMode(self):
    super(self)

