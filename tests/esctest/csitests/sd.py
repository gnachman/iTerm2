from esc import NUL
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug

class SDTests(object):
  def __init__(self, args):
    self._args = args

  def prepare(self):
    """Sets the screen up as
    abcde
    fghij
    klmno
    pqrst
    uvwxy

    With the cursor on the 'h'."""
    lines = [ "abcde",
              "fghij",
              "klmno",
              "pqrst",
              "uvwxy" ]
    for i in xrange(len(lines)):
      y = i + 1
      line = lines[i]
      esccsi.CSI_CUP(Point(1, y))
      escio.Write(line)
    esccsi.CSI_CUP(Point(3, 2))

  def test_SD_DefaultParam(self):
    """SD with no parameter should scroll the screen contents down one line."""
    self.prepare()
    esccsi.CSI_SD()
    expected_lines = [ NUL * 5,
                       "abcde",
                       "fghij",
                       "klmno",
                       "pqrst" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SD_ExplicitParam(self):
    """SD should scroll the screen down by the number of lines given in the parameter."""
    self.prepare()
    esccsi.CSI_SD(2)
    expected_lines = [ NUL * 5,
                       NUL * 5,
                       "abcde",
                       "fghij",
                       "klmno" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SD_CanClearScreen(self):
    """An SD equal to the height of the screen clears it."""
    # Fill the screen with 0001, 0002, ..., height. Fill expected_lines with empty rows.
    height = GetScreenSize().height()
    expected_lines = []
    for i in xrange(height):
      y = i + 1
      esccsi.CSI_CUP(Point(1, y))
      escio.Write("%04d" % y)
      expected_lines.append(NUL * 4)

    # Scroll by |height|
    esccsi.CSI_SD(height)

    # Ensure the screen is empty
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, height), expected_lines);

  def test_SD_RespectsTopBottomScrollRegion(self):
    """When the cursor is inside the scroll region, SD should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_SD(2)
    esccsi.CSI_DECSTBM()

    expected_lines = [ "abcde",
                       NUL * 5,
                       NUL * 5,
                       "fghij",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SD_OutsideTopBottomScrollRegion(self):
    """When the cursor is outside the scroll region, SD should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(1, 1))
    esccsi.CSI_SD(2)
    esccsi.CSI_DECSTBM()

    expected_lines = [ "abcde",
                       NUL * 5,
                       NUL * 5,
                       "fghij",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SD_RespectsLeftRightScrollRegion(self):
    """When the cursor is inside the scroll region, SD should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_SD(2)
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    expected_lines = [ "a" + NUL * 3 + "e",
                       "f" + NUL * 3 + "j",
                       "kbcdo",
                       "pghit",
                       "ulmny" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SD_OutsideLeftRightScrollRegion(self):
    """When the cursor is outside the scroll region, SD should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_CUP(Point(1, 2))
    esccsi.CSI_SD(2)
    esccsi.CSI_DECSTBM()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    expected_lines = [ "a" + NUL * 3 + "e",
                       "f" + NUL * 3 + "j",
                       "kbcdo",
                       "pghit",
                       "ulmny",
                       NUL + "qrs" + NUL,
                       NUL + "vwx" + NUL ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 7), expected_lines);

  def test_SD_LeftRightAndTopBottomScrollRegion(self):
    """When the cursor is outside the scroll region, SD should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(1, 2))
    esccsi.CSI_SD(2)
    esccsi.CSI_DECSTBM()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    expected_lines = [ "abcde",
                       "f" + NUL * 3 + "j",
                       "k" + NUL * 3 + "o",
                       "pghit",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SD_BigScrollLeftRightAndTopBottomScrollRegion(self):
    """Scroll a lr and tb scroll region by more than its height."""
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(1, 2))
    esccsi.CSI_SD(99)
    esccsi.CSI_DECSTBM()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    expected_lines = [ "abcde",
                       "f" + NUL * 3 + "j",
                       "k" + NUL * 3 + "o",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);
