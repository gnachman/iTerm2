from esc import NUL
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize

class ILTests(object):
  def __init__(self, args):
    self._args = args

  def prepare_wide(self):
    """Sets up the display as:
    abcde
    fghij
    klmno

    With the cursor on the 'h'.
    """
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("abcde")
    esccsi.CSI_CUP(Point(1, 2))
    escio.Write("fghij")
    esccsi.CSI_CUP(Point(1, 3))
    escio.Write("klmno")

    esccsi.CSI_CUP(Point(2, 3))

  def prepare_region(self):
    # The capital letters are in the scroll region
    lines = [ "abcde",
              "fGHIj",
              "kLMNo",
              "pQRSt",
              "uvwxy" ]
    for i in xrange(len(lines)):
      esccsi.CSI_CUP(Point(1, i + 1))
      escio.Write(lines[i])

    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 4)

    # Place cursor on the 'H'
    esccsi.CSI_CUP(Point(3, 2))

  def test_IL_DefaultParam(self):
    """Should insert a single line below the cursor."""
    self.prepare_wide();
    esccsi.CSI_IL()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 4),
                                 [ "abcde",
                                   "fghij",
                                   NUL * 5,
                                   "klmno" ])

  def test_IL_ExplicitParam(self):
    """Should insert two lines below the cursor."""
    self.prepare_wide();
    esccsi.CSI_IL(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5),
                                 [ "abcde",
                                   "fghij",
                                   NUL * 5,
                                   NUL * 5,
                                   "klmno" ])

  def test_IL_ScrollsOffBottom(self):
    """Lines should be scrolled off the bottom of the screen."""
    height = GetScreenSize().height()
    for i in xrange(height):
      esccsi.CSI_CUP(Point(1, i + 1))
      escio.Write("%04d" % (i + 1))
    esccsi.CSI_CUP(Point(1, 2))
    esccsi.CSI_IL()

    expected = 1
    for i in xrange(height):
      y = i + 1
      if y == 2:
        AssertScreenCharsInRectEqual(Rect(1, y, 4, y), [ NUL * 4 ])
      else:
        AssertScreenCharsInRectEqual(Rect(1, y, 4, y), [ "%04d" % expected ])
        expected += 1

  def test_IL_RespectsScrollRegion(self):
    """When IL is invoked while the cursor is within the scroll region, lines
    within the scroll regions hould be scrolled down; lines within should
    remain unaffected."""
    self.prepare_region()
    esccsi.CSI_IL()

    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5),
                                 [ "abcde",
                                   "f" + NUL * 3 + "j",
                                   "kGHIo",
                                   "pLMNt",
                                   "uvwxy" ])

  def test_IL_RespectsScrollRegion_Over(self):
    """Scroll by more than the available space in a region."""
    self.prepare_region()
    esccsi.CSI_IL(99)

    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5),
                                 [ "abcde",
                                   "f" + NUL * 3 + "j",
                                   "k" + NUL * 3 + "o",
                                   "p" + NUL * 3 + "t",
                                   "uvwxy" ])

  def test_IL_AboveScrollRegion(self):
    """IL is a no-op outside the scroll region."""
    self.prepare_region()
    esccsi.CSI_CUP(Point(1, 1))
    esccsi.CSI_IL()

    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5),
                                 [ "abcde",
                                   "fGHIj",
                                   "kLMNo",
                                   "pQRSt",
                                   "uvwxy" ])
