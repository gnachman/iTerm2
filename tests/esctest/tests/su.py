from esc import NUL
import esccmd
import escio
from esctypes import Point, Rect
from escutil import AssertScreenCharsInRectEqual, GetScreenSize

class SUTests(object):
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
      esccmd.CUP(Point(1, y))
      escio.Write(line)
    esccmd.CUP(Point(3, 2))

  def test_SU_DefaultParam(self):
    """SU with no parameter should scroll the screen contents up one line."""
    self.prepare()
    esccmd.SU()
    expected_lines = [ "fghij",
                       "klmno",
                       "pqrst",
                       "uvwxy",
                       NUL * 5 ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SU_ExplicitParam(self):
    """SU should scroll the screen up by the number of lines given in the parameter."""
    self.prepare()
    esccmd.SU(2)
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
      esccmd.CUP(Point(1, y))
      escio.Write("%04d" % y)
      expected_lines.append(NUL * 4)

    # Scroll by |height|
    esccmd.SU(height)

    # Ensure the screen is empty
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, height), expected_lines);

  def test_SU_RespectsTopBottomScrollRegion(self):
    """When the cursor is inside the scroll region, SU should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(3, 2))
    esccmd.SU(2)
    esccmd.DECSTBM()

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
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(1, 1))
    esccmd.SU(2)
    esccmd.DECSTBM()

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
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(3, 2))
    esccmd.SU(2)
    esccmd.DECRESET(esccmd.DECLRMM)

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
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(1, 2))
    esccmd.SU(2)
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)

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
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(1, 2))
    esccmd.SU(2)
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)

    expected_lines = [ "abcde",
                       "fqrsj",
                       "k" + NUL * 3 + "o",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SU_BigScrollLeftRightAndTopBottomScrollRegion(self):
    """Scroll a lr and tb scroll region by more than its height."""
    self.prepare()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(1, 2))
    esccmd.SU(99)
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)

    expected_lines = [ "abcde",
                       "f" + NUL * 3 + "j",
                       "k" + NUL * 3 + "o",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);
