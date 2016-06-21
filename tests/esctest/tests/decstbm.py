from esc import CR, LF, NUL
import esccmd
import escio
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, AssertScreenCharsInRectEqual, knownBug
from esctypes import Point, Rect

class DECSTBMTests(object):
  """DECSTBM is tested pretty well in various other tests; this is meant to
  cover the basics."""
  def test_DECSTBM_ScrollsOnNewline(self):
    """Define a top-bottom margin, put text in it, and have newline scroll it."""
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(1, 2))
    escio.Write("1" + CR + LF)
    escio.Write("2")
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ "1", "2" ])
    escio.Write(CR + LF)
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ "2", NUL ])
    AssertEQ(GetCursorPosition().y(), 3)

  def test_DECSTBM_NewlineBelowRegion(self):
    """A newline below the region has no effect on the region."""
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(1, 2))
    escio.Write("1" + CR + LF)
    escio.Write("2")
    esccmd.CUP(Point(1, 4))
    escio.Write(CR + LF)
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ "1", "2" ])

  def test_DECSTBM_MovsCursorToOrigin(self):
    """DECSTBM moves the cursor to column 1, line 1 of the page."""
    esccmd.CUP(Point(3, 2))
    esccmd.DECSTBM(2, 3)
    AssertEQ(GetCursorPosition(), Point(1, 1))

  def test_DECSTBM_TopBelowBottom(self):
    """The value of the top margin (Pt) must be less than the bottom margin (Pb)."""
    size = GetScreenSize()
    esccmd.DECSTBM(3, 3)
    for i in xrange(size.height()):
      escio.Write("%04d" % i)
      y = i + 1
      if y != size.height():
        escio.Write(CR + LF)
    for i in xrange(size.height()):
      y = i + 1
      AssertScreenCharsInRectEqual(Rect(1, y, 4, y), [ "%04d" % i ])
    esccmd.CUP(Point(1, size.height()))
    escio.Write(LF)
    for i in xrange(size.height() - 1):
      y = i + 1
      AssertScreenCharsInRectEqual(Rect(1, y, 4, y), [ "%04d" % (i + 1) ])

    y = size.height()
    AssertScreenCharsInRectEqual(Rect(1, y, 4, y), [ NUL * 4 ])

  def test_DECSTBM_DefaultRestores(self):
    """Default args restore to full screen scrolling."""
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(1, 2))
    escio.Write("1" + CR + LF)
    escio.Write("2")
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ "1", "2" ])
    position = GetCursorPosition()
    esccmd.DECSTBM()
    esccmd.CUP(position)
    escio.Write(CR + LF)
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ "1", "2" ])
    AssertEQ(GetCursorPosition().y(), 4)

  def test_DECSTBM_CursorBelowRegionAtBottomTriesToScroll(self):
    """You cannot perform scrolling outside the margins."""
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(1, 2))
    escio.Write("1" + CR + LF)
    escio.Write("2")
    size = GetScreenSize()
    esccmd.CUP(Point(1, size.height()))
    escio.Write("3" + CR + LF)

    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ "1", "2" ])
    AssertScreenCharsInRectEqual(Rect(1, size.height(), 1, size.height()), [ "3" ])
    AssertEQ(GetCursorPosition().y(), size.height())

  def test_DECSTBM_MaxSizeOfRegionIsPageSize(self):
    """The maximum size of the scrolling region is the page size."""
    # Write "x" at line 2
    esccmd.CUP(Point(1, 2))
    escio.Write("x")

    # Set the scroll bottom to below the screen.
    size = GetScreenSize()
    esccmd.DECSTBM(1, GetScreenSize().height() + 10)

    # Move the cursor to the last line and write a newline.
    esccmd.CUP(Point(1, size.height()))
    escio.Write(CR + LF)

    # Verify that line 2 scrolled up to line 1.
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 2), [ "x", NUL ])

    # Verify the cursor is at the last line on the page.
    AssertEQ(GetCursorPosition().y(), size.height())

  def test_DECSTBM_TopOfZeroIsTopOfScreen(self):
    """A zero value for the top arg gives the top of the screen."""
    esccmd.DECSTBM(0, 3)
    esccmd.CUP(Point(1, 2))
    escio.Write("1" + CR + LF)
    escio.Write("2" + CR + LF)
    escio.Write("3" + CR + LF)
    escio.Write("4")
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 3), [ "2", "3", "4" ])

  def test_DECSTBM_BottomOfZeroIsBottomOfScreen(self):
    """A zero value for the bottom arg gives the bottom of the screen."""
    # Write "x" at line 3
    esccmd.CUP(Point(1, 3))
    escio.Write("x")

    # Set the scroll bottom to below the screen.
    size = GetScreenSize()
    esccmd.DECSTBM(2, 0)

    # Move the cursor to the last line and write a newline.
    esccmd.CUP(Point(1, size.height()))
    escio.Write(CR + LF)

    # Verify that line 3 scrolled up to line 2.
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ "x", NUL ])

    # Verify the cursor is at the last line on the page.
    AssertEQ(GetCursorPosition().y(), size.height())
