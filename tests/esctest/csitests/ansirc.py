import csitests.save_restore_cursor
import esccsi

class ANSIRCTests(csitests.save_restore_cursor.SaveRestoreCursorTests):
  def saveCursor(self):
    esccsi.CSI_ANSISC()

  def restoreCursor(self):
    esccsi.CSI_ANSIRC()


