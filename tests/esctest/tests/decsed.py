from esc import NUL, blank
import escargs
import esccmd
import escio
from escutil import AssertScreenCharsInRectEqual, knownBug
from esctypes import Point, Rect

class DECSEDTests(object):

  def prepare(self):
    """Sets up the display as:
    a

    bcd

    e

    With the cursor on the 'c'.
    """
    esccmd.CUP(Point(1, 1))
    escio.Write("a")
    esccmd.CUP(Point(1, 3))
    escio.Write("bcd")
    esccmd.CUP(Point(1, 5))
    escio.Write("e")

    esccmd.CUP(Point(2, 3))

  def prepare_wide(self):
    """Sets up the display as:
    abcde
    fghij
    klmno

    With the cursor on the 'h'.
    """
    esccmd.CUP(Point(1, 1))
    escio.Write("abcde")
    esccmd.CUP(Point(1, 2))
    escio.Write("fghij")
    esccmd.CUP(Point(1, 3))
    escio.Write("klmno")

    esccmd.CUP(Point(2, 3))

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_Default(self):
    """Should be the same as DECSED_0."""
    self.prepare()
    esccmd.DECSED()
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
    esccmd.DECSED(0)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "b" + NUL * 2,
                                   NUL * 3,
                                   NUL * 3 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_1(self):
    """Erase before cursor."""
    self.prepare()
    esccmd.DECSED(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ NUL * 3,
                                   NUL * 3,
                                   blank() * 2 + "d",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_2(self):
    """Erase whole screen."""
    self.prepare()
    esccmd.DECSED(2)
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
    esccmd.DECSED(3)

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
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(3, 2))
    esccmd.DECSED(0)
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ "abcde",
                                   "fg" + NUL * 3,
                                   NUL * 5 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_1_WithScrollRegion(self):
    """Erase before cursor with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(3, 2))
    esccmd.DECSED(1)
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ NUL * 5,
                                   blank() * 3 + "ij",
                                   "klmno" ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_2_WithScrollRegion(self):
    """Erase whole screen with a scroll region present. The scroll region is ignored."""
    self.prepare_wide()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(3, 2))
    esccmd.DECSED(2)
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ NUL * 5,
                                   NUL * 5,
                                   NUL * 5 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_Default_Protection(self):
    """Should be the same as DECSED_0."""
    esccmd.DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccmd.DECSCA(0)
    esccmd.CUP(Point(2, 5))
    escio.Write("X")
    esccmd.CUP(Point(2, 3))

    esccmd.DECSED()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_DECSCA_2(self):
    """DECSCA 2 should be the same as DECSCA 0."""
    esccmd.DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccmd.DECSCA(2)
    esccmd.CUP(Point(2, 5))
    escio.Write("X")
    esccmd.CUP(Point(2, 3))

    esccmd.DECSED()
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_0_Protection(self):
    """Erase after cursor."""
    esccmd.DECSCA(1)
    self.prepare()

    # Write this to verify that DECSED is actually doing something.
    esccmd.DECSCA(0)
    esccmd.CUP(Point(2, 5))
    escio.Write("X")

    esccmd.CUP(Point(2, 3))
    esccmd.DECSED(0)

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
    esccmd.DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccmd.DECSCA(0)
    esccmd.CUP(Point(2, 1))
    escio.Write("X")

    esccmd.CUP(Point(2, 3))
    esccmd.DECSED(1)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "a" + NUL * 2,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_2_Protection(self):
    """Erase whole screen."""
    esccmd.DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccmd.DECSCA(0)
    esccmd.CUP(Point(2, 1))
    escio.Write("X")

    # Erase the screen
    esccmd.DECSED(2)
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
    esccmd.DECSCA(1)
    self.prepare()

    # Write an X at 2,1 without protection
    esccmd.DECSCA(0)
    esccmd.CUP(Point(2, 1))
    escio.Write("X")

    esccmd.DECSED(3)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 5),
                                 [ "aX" + NUL,
                                   NUL * 3,
                                   "bcd",
                                   NUL * 3,
                                   "e" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_0_WithScrollRegion_Protection(self):
    """Erase after cursor with a scroll region present. The scroll region is ignored."""
    esccmd.DECSCA(1)
    self.prepare_wide()

    # Write an X at 1,3 without protection
    esccmd.DECSCA(0)
    esccmd.CUP(Point(1, 3))
    escio.Write("X")

    # Set up margins
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 3)

    # Position cursor in margins and do DECSED 0
    esccmd.CUP(Point(3, 2))
    esccmd.DECSED(0)

    # Remove margins to compute checksum
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ "abcde",
                                   "fghij",
                                   blank() + "lmno" ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_1_WithScrollRegion_Protection(self):
    """Erase after cursor with a scroll region present. The scroll region is ignored."""
    esccmd.DECSCA(1)
    self.prepare_wide()

    # Write an X at 1,1 without protection
    esccmd.DECSCA(0)
    esccmd.CUP(Point(1, 1))
    escio.Write("X")

    # Set margins
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 3)

    # Position cursor and do DECSED 1
    esccmd.CUP(Point(3, 2))
    esccmd.DECSED(1)

    # Remove margins
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()

    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ blank() + "bcde",
                                   "fghij",
                                   "klmno" ])

  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_2_WithScrollRegion_Protection(self):
    """Erase whole screen with a scroll region present. The scroll region is ignored."""
    esccmd.DECSCA(1)
    self.prepare_wide()

    # Write an X at 1,1 without protection
    esccmd.DECSCA(0)
    esccmd.CUP(Point(1, 1))
    escio.Write("X")

    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(3, 2))
    esccmd.DECSED(2)
    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()
    AssertScreenCharsInRectEqual(Rect(1, 1, 5, 3),
                                 [ blank() + "bcde",
                                   "fghij",
                                   "klmno" ])

  @knownBug(terminal="xterm",
            reason="DECSED respects ISO protection for backward compatibility reasons, per email from Thomas")
  @knownBug(terminal="iTerm2", reason="DECSED not implemented")
  def test_DECSED_doesNotRespectISOProtect(self):
    """DECSED does not respect ISO protection."""
    escio.Write("a")
    esccmd.SPA()
    escio.Write("b")
    esccmd.EPA()
    esccmd.DECSED(2)
    AssertScreenCharsInRectEqual(Rect(1, 1, 2, 1), [ blank() * 2 ])

