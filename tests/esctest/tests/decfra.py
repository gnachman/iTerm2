import tests.fill_rectangle
import esc
import esccmd

CHARACTER = "%"

class DECFRATests(tests.fill_rectangle.FillRectangleTests):
  def fill(self, top=None, left=None, bottom=None, right=None):
    esccmd.DECFRA(str(ord(CHARACTER)), top, left, bottom, right)

  def characters(self, point, count):
    return CHARACTER * count

  def test_DECFRA_basic(self):
    self.fillRectangle_basic()

  def test_DECFRA_invalidRectDoesNothing(self):
    self.fillRectangle_invalidRectDoesNothing()

  def test_DECFRA_defaultArgs(self):
    self.fillRectangle_defaultArgs()

  def test_DECFRA_respectsOriginMode(self):
    self.fillRectangle_respectsOriginMode()

  def test_DECFRA_overlyLargeSourceClippedToScreenSize(self):
    self.fillRectangle_overlyLargeSourceClippedToScreenSize()

  def test_DECFRA_cursorDoesNotMove(self):
    self.fillRectangle_cursorDoesNotMove()

  def test_DECFRA_ignoresMargins(self):
    self.fillRectangle_ignoresMargins()

