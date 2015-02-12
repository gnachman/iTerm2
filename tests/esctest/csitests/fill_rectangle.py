from esc import CR, LF
import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, Rect, knownBug, vtLevel
from esctypes import Point

class FillRectangleTests(object):
  def __init__(self, args):
    self._args = args

  def data(self):
    return [ "abcdefgh",
             "ijklmnop",
             "qrstuvwx",
             "yz012345",
             "ABCDEFGH",
             "IJKLMNOP",
             "QRSTUVWX",
             "YZ6789!@" ]

  def prepare(self):
    esccsi.CSI_CUP(Point(1, 1))
    for line in self.data():
      escio.Write(line + CR + LF)

  def fill(self, top=None, left=None, bottom=None, right=None):
    """Subclasses should override this to do the appropriate fill action."""
    pass

  def characters(self, point, count):
    """Returns the filled characters starting at point, and count of them."""
    return "!" * count

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def fillRectangle_basic(self):
    self.prepare()
    self.fill(top=5,
              left=5,
              bottom=7,
              right=7)
    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 8),
                                 [ "abcdefgh",
                                   "ijklmnop",
                                   "qrstuvwx",
                                   "yz012345",
                                   "ABCD" + self.characters(Point(5, 5), 3) + "H",
                                   "IJKL" + self.characters(Point(5, 6), 3) + "P",
                                   "QRST" + self.characters(Point(5, 7), 3) + "X",
                                   "YZ6789!@" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented", noop=True)
  def fillRectangle_invalidRectDoesNothing(self):
    self.prepare()
    self.fill(top=5,
              left=5,
              bottom=4,
              right=4)
    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 8),
                                 [ "abcdefgh",
                                   "ijklmnop",
                                   "qrstuvwx",
                                   "yz012345",
                                   "ABCDEFGH",
                                   "IJKLMNOP",
                                   "QRSTUVWX",
                                   "YZ6789!@" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def fillRectangle_defaultArgs(self):
    """Write a value at each corner, run fill with no args, and verify the
    corners have all been replaced with self.character."""
    size = GetScreenSize()
    points = [ Point(1, 1),
               Point(size.width(), 1),
               Point(size.width(), size.height()),
               Point(1, size.height()) ]
    n = 1
    for point in points:
      esccsi.CSI_CUP(point)
      escio.Write(str(n))
      n += 1

    self.fill()

    for point in points:
      AssertScreenCharsInRectEqual(
          Rect(point.x(), point.y(), point.x(), point.y()),
          [ self.characters(point, 1) ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def fillRectangle_respectsOriginMode(self):
    self.prepare()

    # Set margins starting at 2 and 2
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 9)
    esccsi.CSI_DECSTBM(2, 9)

    # Turn on origin mode
    esccsi.CSI_DECSET(esccsi.DECOM)

    # Fill from 1,1 to 3,3 - with origin mode, that's 2,2 to 4,4
    self.fill(top=1,
              left=1,
              bottom=3,
              right=3)

    # Turn off margins and origin mode
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()
    esccsi.CSI_DECRESET(esccsi.DECOM)

    # See what happened.
    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 8),
                                 [ "abcdefgh",
                                   "i" + self.characters(Point(2, 2), 3) + "mnop",
                                   "q" + self.characters(Point(2, 3), 3) + "uvwx",
                                   "y" + self.characters(Point(2, 4), 3) + "2345",
                                   "ABCDEFGH",
                                   "IJKLMNOP",
                                   "QRSTUVWX",
                                   "YZ6789!@" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def fillRectangle_overlyLargeSourceClippedToScreenSize(self):
    size = GetScreenSize()

    # Put ab, cX in the bottom right
    esccsi.CSI_CUP(Point(size.width() - 1, size.height() - 1))
    escio.Write("ab")
    esccsi.CSI_CUP(Point(size.width() - 1, size.height()))
    escio.Write("cd")

    # Fill a 2x2 block starting at the d.
    self.fill(top=size.height(),
              left=size.width(),
              bottom=size.height() + 10,
              right=size.width() + 10)
    AssertScreenCharsInRectEqual(Rect(size.width() - 1,
                                      size.height() - 1,
                                      size.width(),
                                      size.height()),
                                 [ "ab",
                                   "c" + self.characters(Point(size.width(), size.height()), 1) ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented", noop=True)
  def fillRectangle_cursorDoesNotMove(self):
    # Make sure something is on screen (so the test is more deterministic)
    self.prepare()

    # Place the cursor
    position = Point(3, 4)
    esccsi.CSI_CUP(position)

    # Fill a block
    self.fill(top=2,
              left=2,
              bottom=4,
              right=4)

    # Make sure the cursor is where we left it.
    AssertEQ(GetCursorPosition(), position)

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def fillRectangle_ignoresMargins(self):
    self.prepare()

    # Set margins
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(3, 6)
    esccsi.CSI_DECSTBM(3, 6)

    # Fill!
    self.fill(top=5,
              left=5,
              bottom=7,
              right=7)

    # Remove margins
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    # Did it ignore the margins?
    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 8),
                                 [ "abcdefgh",
                                   "ijklmnop",
                                   "qrstuvwx",
                                   "yz012345",
                                   "ABCD" + self.characters(Point(5, 5), 3) + "H",
                                   "IJKL" + self.characters(Point(5, 6), 3) + "P",
                                   "QRST" + self.characters(Point(5, 7), 3) + "X",
                                   "YZ6789!@" ])
