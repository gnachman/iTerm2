import tests.fill_rectangle
import esc
import escargs
import esccmd
from escutil import knownBug

class DECERATests(tests.fill_rectangle.FillRectangleTests):
  def fill(self, top=None, left=None, bottom=None, right=None):
    esccmd.DECERA(top, left, bottom, right)

  def characters(self, point, count):
    return esc.blank() * count

  def test_DECERA_basic(self):
    self.fillRectangle_basic()

  def test_DECERA_invalidRectDoesNothing(self):
    self.fillRectangle_invalidRectDoesNothing()

  @knownBug(terminal="xterm",
            reason="xterm doesn't accept all default params for DECERA, although it does work if there is a single semicolon")
  def test_DECERA_defaultArgs(self):
    self.fillRectangle_defaultArgs()

  def test_DECERA_respectsOriginMode(self):
    self.fillRectangle_respectsOriginMode()

  def test_DECERA_overlyLargeSourceClippedToScreenSize(self):
    self.fillRectangle_overlyLargeSourceClippedToScreenSize()

  def test_DECERA_cursorDoesNotMove(self):
    self.fillRectangle_cursorDoesNotMove()

  def test_DECERA_ignoresMargins(self):
    self.fillRectangle_ignoresMargins()

