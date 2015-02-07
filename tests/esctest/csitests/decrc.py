import csitests.save_restore_cursor
import esc
import esccsi

class DECRCTests(csitests.save_restore_cursor.SaveRestoreCursorTests):
  def saveCursor(self):
    esc.DECSC()

  def restoreCursor(self):
    esc.DECRC()

