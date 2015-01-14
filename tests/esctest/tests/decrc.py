import tests.save_restore_cursor
import esccmd

class DECRCTests(tests.save_restore_cursor.SaveRestoreCursorTests):
  def saveCursor(self):
    esccmd.DECSC()

  def restoreCursor(self):
    esccmd.DECRC()

