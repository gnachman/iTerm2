import csitests.fill_rectangle
import esc
import esccsi
from escutil import knownBug

class DECERATests(csitests.fill_rectangle.FillRectangleTests):
  def fill(self, top=None, left=None, bottom=None, right=None):
    esccsi.CSI_DECERA(top, left, bottom, right)

  def blank(self):
    if self._args.expected_terminal == "xterm":
      return ' '
    else:
      return esc.NUL

  def characters(self, point, count):
    return self.blank() * count

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

