import tests.save_restore_cursor
import esccsi

class DECRCTests(tests.save_restore_cursor.SaveRestoreCursorTests):
  def saveCursor(self):
    esccsi.DECSC()

  def restoreCursor(self):
    esccsi.DECRC()

