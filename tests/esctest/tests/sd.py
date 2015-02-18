from esc import NUL
import esccmd
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug

class SDTests(object):
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

  def test_SD_DefaultParam(self):
    """SD with no parameter should scroll the screen contents down one line."""
    self.prepare()
    esccmd.SD()
    expected_lines = [ NUL * 5,
                       "abcde",
                       "fghij",
                       "klmno",
                       "pqrst" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SD_ExplicitParam(self):
    """SD should scroll the screen down by the number of lines given in the parameter."""
    self.prepare()
    esccmd.SD(2)
    expected_lines = [ NUL * 5,
                       NUL * 5,
                       "abcde",
                       "fghij",
                       "klmno" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  @knownBug(terminal="xterm", reason="Asserts", shouldTry=False)
  def test_SD_CanClearScreen(self):
    """An SD equal to the height of the screen clears it."""
    # Fill the screen with 0001, 0002, ..., height. Fill expected_lines with empty rows.
    height = GetScreenSize().height()
    expected_lines = []
    for i in xrange(height):
      y = i + 1
      esccmd.CUP(Point(1, y))
      escio.Write("%04d" % y)
      expected_lines.append(NUL * 4)

    # Scroll by |height|
    esccmd.SD(height)

    # Ensure the screen is empty
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, height), expected_lines);

  def test_SD_RespectsTopBottomScrollRegion(self):
    """When the cursor is inside the scroll region, SD should scroll the
    contents of the scroll region only."""
    self.prepare()
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(3, 2))
    esccmd.SD(2)
    esccmd.DECSTBM()

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
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(1, 1))
    esccmd.SD(2)
    esccmd.DECSTBM()

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
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(3, 2))
    esccmd.SD(2)
    esccmd.DECRESET(esccmd.DECLRMM)

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
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(1, 2))
    esccmd.SD(2)
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)

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
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(1, 2))
    esccmd.SD(2)
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)

    expected_lines = [ "abcde",
                       "f" + NUL * 3 + "j",
                       "k" + NUL * 3 + "o",
                       "pghit",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_SD_BigScrollLeftRightAndTopBottomScrollRegion(self):
    """Scroll a lr and tb scroll region by more than its height."""
    self.prepare()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(1, 2))
    esccmd.SD(99)
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)

    expected_lines = [ "abcde",
                       "f" + NUL * 3 + "j",
                       "k" + NUL * 3 + "o",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);
