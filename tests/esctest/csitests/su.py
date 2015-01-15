from esc import NUL
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertScreenCharsInRectEqual, GetScreenSize

class SUTests(object):
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

  def test_SU_DefaultParam(self):
    """SU with no parameter should scroll the screen contents up one line."""
    self.prepare()
    esccsi.CSI_SU()
    expected_lines = [ "fghij",
                       "klmno",
                       "pqrst",
                       "uvwxy",
                       NUL * 5 ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SU_ExplicitParam(self):
    """SU should scroll the screen up by the number of lines given in the parameter."""
    self.prepare()
    esccsi.CSI_SU(2)
    expected_lines = [ "klmno",
                       "pqrst",
                       "uvwxy",
                       NUL * 5,
                       NUL * 5 ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SU_CanClearScreen(self):
    """An SU equal to the height of the screen clears it."""
    # Fill the screen with 0001, 0002, ..., height. Fill expected_lines with empty rows.
    height = GetScreenSize().height()
    expected_lines = []
    for i in xrange(height):
      y = i + 1
      esccsi.CSI_CUP(Point(1, y))
      escio.Write("%04d" % y)
      expected_lines.append(NUL * 4)

    # Scroll by |height|
    esccsi.CSI_SU(height)

    # Ensure the screen is empty
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, height), expected_lines);

  def test_SU_RespectsTopBottomScrollRegion(self):
    """When the cursor is inside the scroll region, SU should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_SU(2)
    esccsi.CSI_DECSTBM()

    expected_lines = [ "abcde",
                       "pqrst",
                       NUL * 5,
                       NUL * 5,
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SU_OutsideTopBottomScrollRegion(self):
    """When the cursor is outside the scroll region, SU should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(1, 1))
    esccsi.CSI_SU(2)
    esccsi.CSI_DECSTBM()

    expected_lines = [ "abcde",
                       "pqrst",
                       NUL * 5,
                       NUL * 5,
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SU_RespectsLeftRightScrollRegion(self):
    """When the cursor is inside the scroll region, SU should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_SU(2)
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    expected_lines = [ "almne",
                       "fqrsj",
                       "kvwxo",
                       "p" + NUL * 3 + "t",
                       "u" + NUL * 3 + "y" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SU_OutsideLeftRightScrollRegion(self):
    """When the cursor is outside the scroll region, SU should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_CUP(Point(1, 2))
    esccsi.CSI_SU(2)
    esccsi.CSI_DECSTBM()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    expected_lines = [ "almne",
                       "fqrsj",
                       "kvwxo",
                       "p" + NUL * 3 + "t",
                       "u" + NUL * 3 + "y" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SU_LeftRightAndTopBottomScrollRegion(self):
    """When the cursor is outside the scroll region, SU should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(1, 2))
    esccsi.CSI_SU(2)
    esccsi.CSI_DECSTBM()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    expected_lines = [ "abcde",
                       "fqrsj",
                       "k" + NUL * 3 + "o",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SU_BigScrollLeftRightAndTopBottomScrollRegion(self):
    """Scroll a lr and tb scroll region by more than its height."""
    self.prepare()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(1, 2))
    esccsi.CSI_SU(99)
    esccsi.CSI_DECSTBM()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    expected_lines = [ "abcde",
                       "f" + NUL * 3 + "j",
                       "k" + NUL * 3 + "o",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);
