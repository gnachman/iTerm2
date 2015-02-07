from esc import ESC, TAB, NUL, CR, LF, BS
import time
import esccsi
import escio
import esclog
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class XTERM_SAVE_RESTOREests(object):
  """This is based on the DECSET test."""
  def __init__(self, args):
    self._args = args

  def test_XTERM_SAVE_RESTORE_DECCOLM(self):
    """Set 132 column mode."""
    # Enable DECCOLM. Required for saving to work.
    esccsi.CSI_DECSET(esccsi.Allow80To132)

    # Enter 80 column mode and save it.
    esccsi.CSI_DECRESET(esccsi.DECCOLM)
    esccsi.CSI_XTERM_SAVE(esccsi.DECCOLM)

    # Enter 132 column mode
    esccsi.CSI_DECSET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

    # Restore and make sure it is now 80.
    esccsi.CSI_XTERM_RESTORE(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 80)

    # Enter 132 column mode and save it
    esccsi.CSI_DECSET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)
    esccsi.CSI_XTERM_SAVE(esccsi.DECCOLM)

    # Enter 80 column mode
    esccsi.CSI_DECRESET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 80)

    # Restore and make sure it now 132.
    esccsi.CSI_XTERM_RESTORE(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)


  def test_XTERM_SAVE_RESTORE_DECOM(self):
    """Set origin mode. Cursor positioning is relative to the scroll region's
    top left."""
    # Origin mode allows cursor addressing relative to a user-defined origin.
    # This mode resets when the terminal is powered up or reset. It does not
    # affect the erase in display (ED) function.
    esccsi.CSI_DECSTBM(5, 7)
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 7)
    esccsi.CSI_DECSET(esccsi.DECOM)
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("X")

    esccsi.CSI_DECRESET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    esccsi.CSI_XTERM_SAVE(esccsi.DECOM)
    esccsi.CSI_DECRESET(esccsi.DECOM)
    esccsi.CSI_XTERM_RESTORE(esccsi.DECOM)

    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("Y")

    AssertScreenCharsInRectEqual(Rect(5, 5, 5, 5), [ "Y" ])

  def test_XTERM_SAVE_RESTORE_DECOM_SoftReset(self):
    """Soft reset turns off DECOM."""
    esccsi.CSI_DECSTBM(5, 7)
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 7)
    esccsi.CSI_DECSET(esccsi.DECOM)
    esccsi.CSI_DECSTR()
    esccsi.CSI_CHA(1)
    esccsi.CSI_VPA(1)
    escio.Write("X")

    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "X" ])

  @knownBug(terminal="xterm",
            reason="xterm produces incorrect output if ABC is written too quickly. A pause before writing the C produces correct output.")
  def test_XTERM_SAVE_RESTORE_DECAWM(self):
    """Auto-wrap mode."""
    size = GetScreenSize()
    esccsi.CSI_CUP(Point(size.width() - 1, 1))
    esccsi.CSI_DECSET(esccsi.DECAWM)
    escio.Write("abc")

    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ "c" ])

    esccsi.CSI_CUP(Point(size.width() - 1, 1))
    esccsi.CSI_DECRESET(esccsi.DECAWM)
    escio.Write("ABC")

    AssertScreenCharsInRectEqual(Rect(size.width() - 1, 1, size.width(), 1), [ "AC" ])
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ "c" ])

  def test_XTERM_SAVE_RESTORE_DECAWM_CursorAtRightMargin(self):
    """If you start at column 1 and write N+1 characters (where N is the width of
    the window) the cursor's position should go: 1, 2, ..., N, N, 2."""
    esccsi.CSI_DECSET(esccsi.DECAWM)
    size = GetScreenSize()

    # 1, 2, ... N - 2
    AssertEQ(GetCursorPosition().x(), 1)
    for i in xrange(size.width() - 2):
      escio.Write("x")
    AssertEQ(GetCursorPosition().x(), size.width() - 1)

    # Write the N-1th character, cursor enters the right margin.
    escio.Write("x")
    AssertEQ(GetCursorPosition().x(), size.width())

    # Nth: cursor still at right margin!
    escio.Write("x")
    AssertEQ(GetCursorPosition().x(), size.width())

    # N+1th: cursor wraps around to second position.
    escio.Write("x")
    AssertEQ(GetCursorPosition().x(), 2)

  def test_XTERM_SAVE_RESTORE_DECAWM_OnRespectsLeftRightMargin(self):
    """Auto-wrap mode on respects left-right margins."""
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 9)
    esccsi.CSI_DECSTBM(5, 9)
    esccsi.CSI_CUP(Point(8, 9))
    esccsi.CSI_DECSET(esccsi.DECAWM)
    escio.Write("abcdef")

    AssertScreenCharsInRectEqual(Rect(5, 8, 9, 9), [ NUL * 3 + "ab", "cdef" + NUL ])

  @knownBug(terminal="iTerm2",
            reason="Upon reaching the right margin, iTerm2 incorrectly moves the cursor to the right edge of the screen.")
  def test_XTERM_SAVE_RESTORE_DECAWM_OffRespectsLeftRightMargin(self):
    """Auto-wrap mode off respects left-right margins."""
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 9)
    esccsi.CSI_DECSTBM(5, 9)
    esccsi.CSI_CUP(Point(8, 9))
    esccsi.CSI_DECRESET(esccsi.DECAWM)
    escio.Write("abcdef")

    AssertEQ(GetCursorPosition().x(), 9)
    AssertScreenCharsInRectEqual(Rect(5, 8, 9, 9), [ NUL * 5, NUL * 3 + "af" ])

  def test_XTERM_SAVE_RESTORE_Allow80To132(self):
    """DECCOLM only has an effect if Allow80To132 is on."""
    # There are four tests:
    #          Allowed   Not allowed
    # 80->132  1         3
    # 132->80  2         4

    # Test 1: 80->132, allowed
    # Allow 80 to 132.
    esccsi.CSI_DECSET(esccsi.Allow80To132)
    if (GetScreenSize().width() == 132):
      # Enter 80 columns so the test can proceed.
      esccsi.CSI_DECRESET(esccsi.DECCOLM)
      AssertEQ(GetScreenSize().width(), 80)

    # Enter 132
    esccsi.CSI_DECSET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

    # Test 2: 132->80, allowed
    esccsi.CSI_DECRESET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 80)

    # Test 3: 80->132
    # Disallow 80 to 132
    esccsi.CSI_DECRESET(esccsi.Allow80To132)
    # Try to enter 132 - should do nothing.
    esccsi.CSI_DECSET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 80)

    # Allow 80 to 132
    esccsi.CSI_DECSET(esccsi.Allow80To132)

    # Enter 132
    esccsi.CSI_DECSET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

    # Disallow 80 to 132
    esccsi.CSI_DECRESET(esccsi.Allow80To132)

    # Try to enter 80 - should do nothing.
    esccsi.CSI_DECRESET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

  def fillLineAndWriteTab(self):
    escio.Write(CR + LF)
    size = GetScreenSize()
    for i in xrange(size.width()):
      escio.Write("x")
    escio.Write(TAB)

  @knownBug(terminal="iTerm2", reason="iTerm2 wraps tabs")
  def test_XTERM_SAVE_RESTORE_DECAWM_TabDoesNotWrapAround(self):
    """In auto-wrap mode, tabs to not wrap to the next line."""
    esccsi.CSI_DECSET(esccsi.DECAWM)
    size = GetScreenSize()
    for i in xrange(size.width() / 8 + 2):
      escio.Write(TAB)
    AssertEQ(GetCursorPosition().x(), size.width())
    AssertEQ(GetCursorPosition().y(), 1)

  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't implement DECSET 41 (MoreFix).")
  def test_XTERM_SAVE_RESTORE_MoreFix(self):
    """xterm supports DECSET 41 to enable a fix for a bug in curses where it
    would draw to the end of a row and then insert a tab. When 41 is set, the
    tab is drawn."""
    # With MoreFix on, test that writing N x'es followed by a tab leaves the
    # cursor at the first tab stop.
    esccsi.CSI_DECSET(esccsi.MoreFix)
    self.fillLineAndWriteTab()
    AssertEQ(GetCursorPosition().x(), 9)
    escio.Write("1")
    AssertScreenCharsInRectEqual(Rect(9, 3, 9, 3), [ "1" ])

    # With MoreFix off, test that writing N x'es followed by a tab leaves the cursor at
    # the right margin
    esccsi.CSI_DECRESET(esccsi.MoreFix)
    self.fillLineAndWriteTab()
    AssertEQ(GetCursorPosition().x(), GetScreenSize().width())
    escio.Write("2")
    AssertScreenCharsInRectEqual(Rect(1, 5, 1, 5), [ "2" ])

  @knownBug(terminal="iTerm2",
            reason="iTerm2 only reverse wraps-around if there's a soft newline at the preceding line.")
  def test_XTERM_SAVE_RESTORE_ReverseWraparound_BS(self):
    """xerm supports DECSET 45 to toggle 'reverse wraparound'. Both DECAWM and
    45 must be set."""
    # iTerm2 turns reverse wraparound on by default, while xterm does not.
    esccsi.CSI_DECSET(esccsi.ReverseWraparound)
    esccsi.CSI_DECSET(esccsi.DECAWM)
    esccsi.CSI_CUP(Point(1, 2))
    escio.Write(BS)
    AssertEQ(GetCursorPosition().x(), GetScreenSize().width())

  @knownBug(terminal="iTerm2", reason="iTerm2 moves the cursor back an extra space.")
  def test_XTERM_SAVE_RESTORE_ReverseWraparoundLastCol_BS(self):
    """If the cursor is in the last column and a character was just output and
    reverse-wraparound is on then backspace by 1 has no effect."""
    esccsi.CSI_DECSET(esccsi.ReverseWraparound)
    esccsi.CSI_DECSET(esccsi.DECAWM)
    size = GetScreenSize()
    esccsi.CSI_CUP(Point(size.width() - 1, 1))
    escio.Write("a")
    AssertEQ(GetCursorPosition().x(), size.width())
    escio.Write("b")
    AssertEQ(GetCursorPosition().x(), size.width())
    escio.Write(BS)
    AssertEQ(GetCursorPosition().x(), size.width())

  def test_XTERM_SAVE_RESTORE_ReverseWraparound_Multi(self):
    size = GetScreenSize()
    esccsi.CSI_CUP(Point(size.width() - 1, 1))
    escio.Write("abcd")
    esccsi.CSI_DECSET(esccsi.ReverseWraparound)
    esccsi.CSI_DECSET(esccsi.DECAWM)
    esccsi.CSI_CUB(4)
    AssertEQ(GetCursorPosition().x(), size.width() - 1)

  @knownBug(terminal="iTerm2",
            reason="iTerm2 doesn't implement DECRESET ReverseWraparound.")
  def test_XTERM_SAVE_RESTORE_ResetReverseWraparoundDisablesIt(self):
    """DECRESET of reverse wraparound prevents it from happening."""
    # iTerm2 turns reverse wraparound on by default, while xterm does not.
    esccsi.CSI_DECRESET(esccsi.ReverseWraparound)
    esccsi.CSI_DECSET(esccsi.DECAWM)
    esccsi.CSI_CUP(Point(GetScreenSize().width() - 1, 1))
    escio.Write("abc")
    escio.Write(BS * 5)
    AssertEQ(GetCursorPosition().x(), 1)

  @knownBug(terminal="iTerm2",
             reason="iTerm2 does not require DECAWM for reverse wrap.")
  def test_XTERM_SAVE_RESTORE_ReverseWraparound_RequiresDECAWM(self):
    """Reverse wraparound only works if DECAWM is set."""
    # iTerm2 turns reverse wraparound on by default, while xterm does not.
    esccsi.CSI_CUP(Point(GetScreenSize().width() - 1, 1))
    escio.Write("abc")
    esccsi.CSI_DECSET(esccsi.ReverseWraparound)
    esccsi.CSI_DECRESET(esccsi.DECAWM)
    escio.Write(BS * 5)
    AssertEQ(GetCursorPosition().x(), 1)

  def doAltBuftest(self, code, altGetsClearedBeforeToMain, cursorSaved):
    """|code| is the code to test with, either 47 or 1047."""
    # Scribble in main screen
    escio.Write("abc" + CR + LF + "abc")

    # Switch from main to alt. Cursor should not move. If |cursorSaved| is set,
    # record the position first to verify that it's restored after DECRESET.
    if cursorSaved:
      mainCursorPosition = GetCursorPosition()

    before = GetCursorPosition()
    esccsi.CSI_DECSET(code)
    after = GetCursorPosition()
    AssertEQ(before.x(), after.x())
    AssertEQ(before.y(), after.y())

    # Scribble in alt screen, clearing it first since who knows what might have
    # been there.
    esccsi.CSI_ED(2)
    esccsi.CSI_CUP(Point(1, 2))
    escio.Write("def" + CR +LF + "def")

    # Make sure abc is gone
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 3), [ NUL * 3, "def", "def" ])

    # Switch to main. Cursor should not move.
    before = GetCursorPosition()
    esccsi.CSI_DECRESET(code)
    after = GetCursorPosition()
    if cursorSaved:
      AssertEQ(mainCursorPosition.x(), after.x())
      AssertEQ(mainCursorPosition.y(), after.y())
    else:
      AssertEQ(before.x(), after.x())
      AssertEQ(before.y(), after.y())

    # def should be gone, abc should be back.
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 3), [ "abc", "abc", NUL * 3 ])

    # Switch to alt
    before = GetCursorPosition()
    esccsi.CSI_DECSET(code)
    after = GetCursorPosition()
    AssertEQ(before.x(), after.x())
    AssertEQ(before.y(), after.y())

    if altGetsClearedBeforeToMain:
      AssertScreenCharsInRectEqual(Rect(1, 1, 3, 3), [ NUL * 3, NUL * 3, NUL * 3 ])
    else:
      AssertScreenCharsInRectEqual(Rect(1, 1, 3, 3), [ NUL * 3, "def", "def" ])

  @knownBug(terminal="iTerm2", reason="DECSET 1047 (OPT_ALTBUF) not implemented.")
  def test_XTERM_SAVE_RESTORE_OPT_ALTBUF(self):
    """DECSET 47 and DECSET 1047 do the same thing: If not in alt screen,
    switch to it. Its contents are NOT erased.

    DECRESET 1047 If on alt screen, clear the alt screen and then switch to the
    main screen."""
    self.doAltBuftest(esccsi.OPT_ALTBUF, True, False)

  def test_XTERM_SAVE_RESTORE_ALTBUF(self):
    """DECSET 47 and DECSET 1047 do the same thing: If not in alt screen,
    switch to it. Its contents are NOT erased.

    DECRESET 47 switches to the main screen (without first clearing the alt
    screen)."""
    self.doAltBuftest(esccsi.ALTBUF, False, False)

  def test_XTERM_SAVE_RESTORE_OPT_ALTBUF_CURSOR(self):
    """DECSET 1049 is like 1047 but it also saves the cursor position before
    entering alt and restores it after returning to main."""
    self.doAltBuftest(esccsi.OPT_ALTBUF_CURSOR, True, True)

  def test_XTERM_SAVE_RESTORE_DECLRMM(self):
    """Left-right margin. This is tested extensively in many other places as well."""
    # Turn on margins and write.
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(2, 4)
    escio.Write("abcdefgh")
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 3), [ "abcd", NUL + "efg", NUL + "h" + NUL * 2 ])

    # Turn off margins.
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("ABCDEFGH")
    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 1), [ "ABCDEFGH" ])

  @knownBug(terminal="iTerm2",
            reason="iTerm2 fails to reset DECLRMM (it just sets the margins to the screen edges)")
  def test_XTERM_SAVE_RESTORE_DECLRMM_ResetByDECSTR(self):
    """DECSTR should turn off DECLRMM."""
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSTR()
    esccsi.CSI_DECSET(esccsi.DECAWM)
    esccsi.CSI_DECSET(esccsi.ReverseWraparound)
    esccsi.CSI_CUP(Point(GetScreenSize().width() - 1, 1))
    escio.Write("abc")
    # Reverse wraparound is disabled (at least in iTerm2) when a scroll region is present.
    escio.Write(BS * 3)
    AssertEQ(GetCursorPosition().y(), 1)

  @knownBug(terminal="xterm", reason="By default, xterm emulates a vt420 and this is a vt500 code.")
  @knownBug(terminal="iTerm2", reason="DECNCSM not implemented")
  def test_XTERM_SAVE_RESTORE_DECNCSM(self):
    """From the manual: When enabled, a column mode change (either through
    Set-Up or by the escape sequence DECCOLM) does not clear the screen. When
    disabled, the column mode change clears the screen as a side effect."""
    # There are four tests:
    #                    DECNCSM Set   DECNCSM Reset
    # Column Mode Set    1             3
    # Column Mode Reset  2             4

    # 1: Set DECNCSM, Set column mode.
    esccsi.CSI_DECRESET(esccsi.DECCOLM)
    esccsi.CSI_DECSET(esccsi.DECNCSM)
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("1")
    esccsi.CSI_DECSET(esccsi.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "1" ])

    # 2: Set DECNCSM, Reset column mode.
    esccsi.CSI_DECSET(esccsi.DECCOLM)
    esccsi.CSI_DECSET(esccsi.DECNCSM)
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("2")
    esccsi.CSI_DECRESET(esccsi.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "2" ])

    # 3: Reset DECNCSM, Set column mode.
    esccsi.CSI_DECRESET(esccsi.DECCOLM)
    esccsi.CSI_DECRESET(esccsi.DECNCSM)
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("3")
    esccsi.CSI_DECSET(esccsi.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

    # 4: Reset DECNCSM, Reset column mode.
    esccsi.CSI_DECSET(esccsi.DECCOLM)
    esccsi.CSI_DECRESET(esccsi.DECNCSM)
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("4")
    esccsi.CSI_DECRESET(esccsi.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

  @knownBug(terminal="iTerm2", reason="Save/restore cursor not implemented")
  def test_XTERM_SAVE_RESTORE_SaveRestoreCursor(self):
    """Set saves the cursor position. Reset restores it."""
    esccsi.CSI_CUP(Point(2, 3))
    esccsi.CSI_DECSET(esccsi.SaveRestoreCursor)
    esccsi.CSI_CUP(Point(5, 5))
    esccsi.CSI_DECRESET(esccsi.SaveRestoreCursor)
    cursor = GetCursorPosition()
    AssertEQ(cursor.x(), 2)
    AssertEQ(cursor.y(), 3)




