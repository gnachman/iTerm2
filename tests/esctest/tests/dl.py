from esc import NUL
import esccmd
import escio
from esctypes import Point, Rect
from escutil import AssertScreenCharsInRectEqual, GetScreenSize, knownBug

class DLTests(object):
  def prepare(self):
    """Fills the screen with 4-char line numbers (0001, 0002, ...) down to the
    last line and puts the cursor on the start of the second line."""
    height = GetScreenSize().height()
    for i in xrange(height):
      y = i + 1
      esccmd.CUP(Point(1, y))
      escio.Write("%04d" % y)

    esccmd.CUP(Point(1, 2))

  def prepareForRegion(self):
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

  def test_DL_DefaultParam(self):
    """DL with no parameter should delete a single line."""
    # Set up the screen with 0001, 0002, ..., height
    self.prepare()

    # Delete the second line, moving subsequent lines up.
    esccmd.DL()

    # Build an array of 0001, 0003, 0004, ..., height
    height = GetScreenSize().height()
    y = 1
    expected_lines = []
    for i in xrange(height):
      if y != 2:
        expected_lines.append("%04d" % y)
      y += 1

    # The last line should be blank
    expected_lines.append(NUL * 4);
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, height), expected_lines);

  def test_DL_ExplicitParam(self):
    """DL should delete the given number of lines."""
    # Set up the screen with 0001, 0002, ..., height
    self.prepare()

    # Delete two lines starting at the second line, moving subsequent lines up.
    esccmd.DL(2)

    # Build an array of 0001, 0004, ..., height
    height = GetScreenSize().height()
    y = 1
    expected_lines = []
    for i in xrange(height):
      if y < 2 or y > 3:
        expected_lines.append("%04d" % y)
      y += 1

    # The last two lines should be blank
    expected_lines.append(NUL * 4);
    expected_lines.append(NUL * 4);

    AssertScreenCharsInRectEqual(Rect(1, 1, 4, height), expected_lines);

  def test_DL_DeleteMoreThanVisible(self):
    """Test passing a too-big parameter to DL."""
    # Set up the screen with 0001, 0002, ..., height
    self.prepare()

    # Delete more than the height of the screen.
    height = GetScreenSize().height()
    esccmd.DL(height * 2)

    # Build an array of 0001 followed by height-1 empty lines.
    y = 1
    expected_lines = [ "0001" ]
    for i in xrange(height - 1):
      expected_lines.append(NUL * 4);

    AssertScreenCharsInRectEqual(Rect(1, 1, 4, height), expected_lines);

  def test_DL_InScrollRegion(self):
    """Test that DL does the right thing when the cursor is inside the scroll
    region."""
    self.prepareForRegion()
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(3, 2))
    esccmd.DL()
    esccmd.DECSTBM()

    expected_lines = [ "abcde",
                       "klmno",
                       "pqrst",
                       NUL * 5,
                       "uvwxy" ]
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_DL_OutsideScrollRegion(self):
    """Test that DL does nothing when the cursor is outside the scroll
    region."""
    self.prepareForRegion()
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(3, 1))
    esccmd.DL()
    esccmd.DECSTBM()

    expected_lines = [ "abcde",
                       "fghij",
                       "klmno",
                       "pqrst",
                       "uvwxy" ]

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_DL_InLeftRightScrollRegion(self):
    """Test that DL respects left-right margins."""
    self.prepareForRegion()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(3, 2))
    esccmd.DL()
    esccmd.DECRESET(esccmd.DECLRMM)

    expected_lines = [ "abcde",
                       "flmnj",
                       "kqrso",
                       "pvwxt",
                       "u" + NUL * 3 + "y" ]

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  @knownBug(terminal="xterm",
            reason="xterm erases the area inside the scroll region incorrectly")
  def test_DL_OutsideLeftRightScrollRegion(self):
    """Test that DL does nothing outside a left-right margin."""
    self.prepareForRegion()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(1, 2))
    esccmd.DL()
    esccmd.DECRESET(esccmd.DECLRMM)

    expected_lines = [ "abcde",
                       "fghij",
                       "klmno",
                       "pqrst",
                       "uvwxy" ]

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_DL_InLeftRightAndTopBottomScrollRegion(self):
    """Test that DL respects left-right margins together with top-bottom."""
    self.prepareForRegion()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(3, 2))
    esccmd.DL()
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()

    expected_lines = [ "abcde",
                       "flmnj",
                       "kqrso",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_DL_ClearOutLeftRightAndTopBottomScrollRegion(self):
    """Erase the whole scroll region with both kinds of margins."""
    self.prepareForRegion()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(3, 2))
    esccmd.DL(99)
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()

    expected_lines = [ "abcde",
                       "f" + NUL * 3 + "j",
                       "k" + NUL * 3 + "o",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_DL_OutsideLeftRightAndTopBottomScrollRegion(self):
    """Test that DL does nothing outside left-right margins together with top-bottom."""
    self.prepareForRegion()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 4)
    esccmd.CUP(Point(1, 1))
    esccmd.DL()
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()

    expected_lines = [ "abcde",
                       "fghij",
                       "klmno",
                       "pqrst",
                       "uvwxy" ]


    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);
