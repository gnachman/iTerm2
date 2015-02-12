import csitests.fill_rectangle
import esc
import esccsi

class DECFRATests(csitests.fill_rectangle.FillRectangleTests):
  def fill(self, top=None, left=None, bottom=None, right=None):
    esccsi.CSI_DECFRA(str(ord(self.character())), top, left, bottom, right)

  def character(self):
    return "%"

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

