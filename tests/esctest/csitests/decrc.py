import csitests.save_restore_cursor
import escc1
import esccsi

class DECRCTests(csitests.save_restore_cursor.SaveRestoreCursorTests):
  def saveCursor(self):
    escc1.DECSC()

  def restoreCursor(self):
    escc1.DECRC()

