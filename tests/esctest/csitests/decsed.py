from esc import NUL
import esccsi
import escio
from escutil import AssertScreenCharsInRectEqual, knownBug
from esctypes import Point, Rect

class DECSEDTests(object):
  def __init__(self, args):
    self._args = args

  def blank(self):
    if self._args.expected_terminal == "xterm":
      return ' '
    else:
      return NUL

  def prepare(self):
    """Sets up the display as:
    a

    bcd

    e

    With the cursor on the 'c'.
    """
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("a")
    esccsi.CSI_CUP(Point(1, 3))
    escio.Write("bcd")
    esccsi.CSI_CUP(Point(1, 5))
    escio.Write("e")

    esccsi.CSI_CUP(Point(2, 3))

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

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_Default(self):
    """Should be the same as DECSED_0."""
    self.prepare()
    esccsi.CSI_DECSED()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "b" + NUL * 2,
                                   NUL * 3,
                                   NUL * 3 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_0(self):
    """Erase after cursor."""
    self.prepare()
    esccsi.CSI_DECSED(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "b" + NUL * 2,
                                   NUL * 3,
                                   NUL * 3 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  @knownBug(terminal="xterm", reason="DECSED clears whole screen with mode 1")
  def test_DECSED_1(self):
    """Erase before cursor."""
    self.prepare()
    esccsi.CSI_DECSED(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ NUL * 3,
                                   NUL * 3,
                                   self.blank() * 2 + "d",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_2(self):
    """Erase whole screen."""
    self.prepare()
    esccsi.CSI_DECSED(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ NUL * 3,
                                   NUL * 3,
                                   NUL * 3,
                                   NUL * 3,
                                   NUL * 3 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented", noop=True)
  def test_DECSED_3(self):
    """xterm supports a "3" parameter, which also erases scrollback history. There
    is no way to test if it's working, though. We can at least test that it doesn't
    touch the screen."""
    self.prepare()
    esccsi.CSI_DECSED(3)

    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_0_WithScrollRegion(self):
    """Erase after cursor with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 3)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DECSED(0)
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ "abcde",
                                   "fg" + NUL * 3,
                                   NUL * 5 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  @knownBug(terminal="xterm", reason="DECSED clears whole screen with mode 1")
  def test_DECSED_1_WithScrollRegion(self):
    """Erase before cursor with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 3)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DECSED(1)
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ NUL * 5,
                                   self.blank() * 3 + "ij",
                                   "klmno" ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_2_WithScrollRegion(self):
    """Erase whole screen with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 3)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DECSED(2)
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ NUL * 5,
                                   NUL * 5,
                                   NUL * 5 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_Default_Protection(self):
    """Should be the same as DECSED_0."""
    esccsi.CSI_DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccsi.CSI_DECSCA(0)
    esccsi.CSI_CUP(Point(2, 5))
    escio.Write("X")
    esccsi.CSI_CUP(Point(2, 3))

    esccsi.CSI_DECSED()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_DECSCA_2(self):
    """DECSCA 2 should be the same as DECSCA 0."""
    esccsi.CSI_DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccsi.CSI_DECSCA(2)
    esccsi.CSI_CUP(Point(2, 5))
    escio.Write("X")
    esccsi.CSI_CUP(Point(2, 3))

    esccsi.CSI_DECSED()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_0_Protection(self):
    """Erase after cursor."""
    esccsi.CSI_DECSCA(1)
    self.prepare()

    # Write this to verify that DECSED is actually doing something.
    esccsi.CSI_DECSCA(0)
    esccsi.CSI_CUP(Point(2, 5))
    escio.Write("X")

    esccsi.CSI_CUP(Point(2, 3))
    esccsi.CSI_DECSED(0)

    # X should be erased, other characters not.
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_1_Protection(self):
    """Erase before cursor."""
    esccsi.CSI_DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccsi.CSI_DECSCA(0)
    esccsi.CSI_CUP(Point(2, 1))
    escio.Write("X")

    esccsi.CSI_CUP(Point(2, 3))
    esccsi.CSI_DECSED(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_2_Protection(self):
    """Erase whole screen."""
    esccsi.CSI_DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccsi.CSI_DECSCA(0)
    esccsi.CSI_CUP(Point(2, 1))
    escio.Write("X")

    # Erase the screen
    esccsi.CSI_DECSED(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented", noop=True)
  def test_DECSED_3_Protection(self):
    """xterm supports a "3" parameter, which also erases scrollback history. There
    is no way to test if it's working, though. We can at least test that it doesn't
    touch the screen."""
    esccsi.CSI_DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccsi.CSI_DECSCA(0)
    esccsi.CSI_CUP(Point(2, 1))
    escio.Write("X")

    esccsi.CSI_DECSED(3)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "aX" + NUL,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_0_WithScrollRegion_Protection(self):
    """Erase after cursor with a scroll region present. The scroll region is ignored."""
    esccsi.CSI_DECSCA(1)
    self.prepare_wide()

    # Write an X at 1,3 without protection
    esccsi.CSI_DECSCA(0)
    esccsi.CSI_CUP(Point(1, 3))
    escio.Write("X")

    # Set up margins
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 3)

    # Position cursor in margins and do DECSED 0
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DECSED(0)

    # Remove margins to compute checksum
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ "abcde",
                                   "fghij",
                                   self.blank() + "lmno" ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_1_WithScrollRegion_Protection(self):
    """Erase after cursor with a scroll region present. The scroll region is ignored."""
    esccsi.CSI_DECSCA(1)
    self.prepare_wide()

    # Write an X at 1,1 without protection
    esccsi.CSI_DECSCA(0)
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("X")

    # Set margins
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 3)

    # Position cursor and do DECSED 1
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DECSED(1)

    # Remove margins
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ self.blank() + "bcde",
                                   "fghij",
                                   "klmno" ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_2_WithScrollRegion_Protection(self):
    """Erase whole screen with a scroll region present. The scroll region is ignored."""
    esccsi.CSI_DECSCA(1)
    self.prepare_wide()

    # Write an X at 1,1 without protection
    esccsi.CSI_DECSCA(0)
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("X")

    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    esccsi.CSI_DECSTBM(2, 3)
    esccsi.CSI_CUP(Point(3, 2))
    esccsi.CSI_DECSED(2)
    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ self.blank() + "bcde",
                                   "fghij",
                                   "klmno" ])
