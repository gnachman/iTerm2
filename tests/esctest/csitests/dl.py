from esc import NUL
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertScreenCharsInRectEqual, GetScreenSize, knownBug

class DLTests(object):
  def __init__(self, args):
    self._args = args

  def prepare(self):
    """Fills the screen with 4-char line numbers (0001, 0002, ...) down to the
    last line and puts the cursor on the start of the second line."""
    height = GetScreenSize().height()
    for i in xrange(height):
      y = i + 1
      esccsi.CSI_CUP(Point(1, y))
      escio.Write("%04d" % y)

    esccsi.CSI_CUP(Point(1, 2))

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
      esccsi.CSI_CUP(Point(1, y))
      escio.Write(line)
    esccsi.CSI_CUP(Point(3, 2))

  def test_DL_DefaultParam(self):
    """DL with no parameter should delete a single line."""
    # Set up the screen with 0001, 0002, ..., height
    self.prepare()

    # Delete the second line, moving subsequent lines up.
    esccsi.CSI_DL()

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
    esccsi.CSI_DL(2)

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
    esccsi.CSI_DL(height * 2)

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
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DL()
    esccsi.CSI_DECSTBM()

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
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(3, 1))
    esccsi.CSI_DL()
    esccsi.CSI_DECSTBM()

    expected_lines = [ "abcde",
                       "fghij",
                       "klmno",
                       "pqrst",
                       "uvwxy" ]

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_DL_InLeftRightScrollRegion(self):
    """Test that DL respects left-right margins."""
    self.prepareForRegion()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DL()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

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
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_CUP(Point(1, 2))
    esccsi.CSI_DL()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    expected_lines = [ "abcde",
                       "fghij",
                       "klmno",
                       "pqrst",
                       "uvwxy" ]

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_DL_InLeftRightAndTopBottomScrollRegion(self):
    """Test that DL respects left-right margins together with top-bottom."""
    self.prepareForRegion()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DL()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    expected_lines = [ "abcde",
                       "flmnj",
                       "kqrso",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_DL_ClearOutLeftRightAndTopBottomScrollRegion(self):
    """Erase the whole scroll region with both kinds of margins."""
    self.prepareForRegion()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DL(99)
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    expected_lines = [ "abcde",
                       "f" + NUL * 3 + "j",
                       "k" + NUL * 3 + "o",
                       "p" + NUL * 3 + "t",
                       "uvwxy" ]

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);

  def test_DL_OutsideLeftRightAndTopBottomScrollRegion(self):
    """Test that DL does nothing outside left-right margins together with top-bottom."""
    self.prepareForRegion()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 4)
    esccsi.CSI_CUP(Point(1, 1))
    esccsi.CSI_DL()
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    expected_lines = [ "abcde",
                       "fghij",
                       "klmno",
                       "pqrst",
                       "uvwxy" ]


    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 5), expected_lines);
