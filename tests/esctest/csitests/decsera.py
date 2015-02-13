import csitests.fill_rectangle
import esc
import esccsi
import escio
from escutil import Point, knownBug

class DECSERATests(csitests.fill_rectangle.FillRectangleTests):
  def __init__(self, args):
    csitests.fill_rectangle.FillRectangleTests.__init__(self, args)
    self._always_return_blank = False

  def prepare(self):
    esccsi.CUP(Point(1, 1))
    i = 1
    for line in self.data():
      # Protect odd-numbered rows
      esccsi.DECSCA(i)
      escio.Write(line + esc.CR + esc.LF)
      i = 1 - i
    esccsi.DECSCA(0)

  def fill(self, top=None, left=None, bottom=None, right=None):
    esccsi.DECSERA(top, left, bottom, right)

  def blank(self):
    if self._args.expected_terminal == "xterm":
      return ' '
    else:
      return esc.NUL

  def characters(self, point, count):
    if self._always_return_blank:
      return self.blank() * count
    s = ""
    data = self.data()
    for i in xrange(count):
      p = Point(point.x() + i, point.y())
      if p.y() >= len(data):
        s += self.blank()
        continue
      line = data[p.y() - 1]
      if p.x() >= len(line):
        s += self.blank()
        continue
      if point.y() % 2 == 1:
        s += line[p.x() - 1]
      else:
        s += self.blank()
    return s

  def test_DECSERA_basic(self):
    self.fillRectangle_basic()

  def test_DECSERA_invalidRectDoesNothing(self):
    self.fillRectangle_invalidRectDoesNothing()

  @knownBug(terminal="xterm",
            reason="xterm doesn't accept all default params for DECSERA, although it does work if there is a single semicolon")
  def test_DECSERA_defaultArgs(self):
    try:
      self._always_return_blank = True
      self.fillRectangle_defaultArgs()
    finally:
      self._always_return_blank = False

  def test_DECSERA_respectsOriginMode(self):
    self.fillRectangle_respectsOriginMode()

  def test_DECSERA_overlyLargeSourceClippedToScreenSize(self):
    self.fillRectangle_overlyLargeSourceClippedToScreenSize()

  def test_DECSERA_cursorDoesNotMove(self):
    self.fillRectangle_cursorDoesNotMove()

  def test_DECSERA_ignoresMargins(self):
    self.fillRectangle_ignoresMargins()


