from esc import ESC, TAB, NUL, CR, LF, BS
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug, optionRequired, vtLevel, optionRejects
import escargs
import esccsi
import escio
import esclog
import time
# Note: There is no test for DECRESET; that is handled here.

# Can't test the following:
# DECCKM - requires user action at the keyboard
# DECSCLM - affects visual presentation of scrolling only
# DECSCNM - changes color palette
# DECARM - requires user action at the keyboard
# Mouse Tracking (9) - requires user action at mouse
# Show Toolbar (10) - no way to introspect toolbar
# Start Blinking Cursor (12) - no way to introspect cursor status
# DECPFF - no way to examine output to printer
# DECPEX - no way to examine output to printer
# DECTCEM - no way to tell if the cursor is visible
# Show Scrollbar (30) - no way to tell if scroll bar is visible
# Enable font-shifting (35) - I think this enables/disables a keyboard shortcut to grow or shrink the font. Not testable because user interaction is required.
# DECTEK - Tektronix is out of scope for now (and probably not introspectable, I guess).
# DECNRCM - Can't introspect character sets
# Margin Bell (44) - Can't tell if bell is ringing
# Allow Logging (46) - Not on by default
# DECNKM - Requires user interaction to detect app keypad
# DECBKM - Requires user interaction to see what back arrow key sends
# Mouse tracking (1000, 1001, 1002, 1003, 1005, 1006, 1007, 1015) - Requires user interaction with mouse
# Focus In/Out (1004) - Requires user interaction
# Scroll to bottom on tty output (1010) - Can't introspect scroll position
# Scroll to bottom on tty output (1011) - Can't introspect scroll position and requires user interaction with keyboard
# Interpret meta key sets 8th bit - Requires user interaction with keyboard
# Enable special modifiers for Alt and NumLock keys - Requires user interaction with keyboard
# Send ESC when Meta modifies a key - Requires user interaction with keyboard
# Send DEL from the editing-keypad Delete key - Requires user interaction with keyboard
# Send ESC when Alt modifies a key - Requires user interaction with keyboard
# Keep selection even if not highlighted - Can't set selection
# Use the CLIPBOARD selection - Can't set selection
# Enable Urgency window manager hint when Control-G is received - Can't introspect window manager
# Enable raising of the window when Control-G is received - Can't introspect window raised status
# Set terminfo/termcap function-key mode - Requires user interaction.
# Set Sun function-key mode - Requires user interaction.
# Set HP function-key mode - Requires user interaction.
# Set SCO function-key mode - Requires user interaction.
# Set legacy keyboard emulation (X11R6) - Requires user interaction.
# Set VT220 keyboard emulation - Requires user interaction.
# Set bracketed paste mode - Requires user interaction.

# TODO: test DECANM. It sets the font to USASCII and sets VT100 mode
class DECSETTests(object):
  def test_DECSET_DECCOLM(self):
    """Set 132 column mode."""
    # From the docs:
    # When the terminal receives the sequence, the screen is erased and the
    # cursor moves to the home position. This also sets the scrolling region
    # for full screen

    # Enable DECCOLM.
    esccsi.DECSET(esccsi.Allow80To132)

    # Write something to verify that it gets erased
    esccsi.CUP(Point(5, 5))
    escio.Write("x")

    # Set left-right and top-bottom margins to ensure they're removed.
    esccsi.DECSTBM(1, 2)
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(1, 2)

    # Enter 132-column mode.
    esccsi.DECSET(esccsi.DECCOLM)

    # Check that the screen got resized
    AssertEQ(GetScreenSize().width(), 132)

    # Make sure the cursor is at the origin
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 1)

    # Write to make sure the scroll regions are gone
    escio.Write(CR + LF)
    escio.Write("Hello")
    escio.Write(CR + LF)
    escio.Write("World")

    esccsi.DECSTBM()
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 2, 5, 3), [ "Hello", "World" ])
    AssertScreenCharsInRectEqual(Rect(5, 5, 5, 5), [ NUL ])

  @knownBug(terminal="iTerm2", reason="iTerm2 has an off-by-one bug with origin mode.")
  def test_DECSET_DECOM(self):
    """Set origin mode. Cursor positioning is relative to the scroll region's
    top left."""
    # Origin mode allows cursor addressing relative to a user-defined origin.
    # This mode resets when the terminal is powered up or reset. It does not
    # affect the erase in display (ED) function.
    esccsi.DECSTBM(5, 7)
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 7)
    esccsi.DECSET(esccsi.DECOM)
    esccsi.CUP(Point(1, 1))
    escio.Write("X")

    esccsi.DECRESET(esccsi.DECLRMM)
    esccsi.DECSTBM()

    AssertScreenCharsInRectEqual(Rect(5, 5, 5, 5), [ "X" ])

  def test_DECSET_DECOM_SoftReset(self):
    """Soft reset turns off DECOM."""
    esccsi.DECSTBM(5, 7)
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 7)
    esccsi.DECSET(esccsi.DECOM)
    esccsi.DECSTR()
    esccsi.CHA(1)
    esccsi.VPA(1)
    escio.Write("X")

    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "X" ])

  # This test is flaky so I turned off shouldTry to avoid false failures.
  @knownBug(terminal="xterm",
            reason="xterm produces incorrect output if ABC is written too quickly. A pause before writing the C produces correct output.",
            shouldTry=False)
  def test_DECSET_DECAWM(self):
    """Auto-wrap mode."""
    size = GetScreenSize()
    esccsi.CUP(Point(size.width() - 1, 1))
    esccsi.DECSET(esccsi.DECAWM)
    escio.Write("abc")

    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ "c" ])

    esccsi.CUP(Point(size.width() - 1, 1))
    esccsi.DECRESET(esccsi.DECAWM)
    escio.Write("ABC")

    AssertScreenCharsInRectEqual(Rect(size.width() - 1, 1, size.width(), 1), [ "AC" ])
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ "c" ])

  def test_DECSET_DECAWM_CursorAtRightMargin(self):
    """If you start at column 1 and write N+1 characters (where N is the width of
    the window) the cursor's position should go: 1, 2, ..., N, N, 2."""
    esccsi.DECSET(esccsi.DECAWM)
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

  # xterm doesn't implement auto-wrap mode when wide characters are disabled.
  @optionRejects(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  def test_DECSET_DECAWM_OnRespectsLeftRightMargin(self):
    """Auto-wrap mode on respects left-right margins."""
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 9)
    esccsi.DECSTBM(5, 9)
    esccsi.CUP(Point(8, 9))
    esccsi.DECSET(esccsi.DECAWM)
    escio.Write("abcdef")

    AssertScreenCharsInRectEqual(Rect(5, 8, 9, 9), [ NUL * 3 + "ab", "cdef" + NUL ])

  @knownBug(terminal="iTerm2",
            reason="Upon reaching the right margin, iTerm2 incorrectly moves the cursor to the right edge of the screen.")
  def test_DECSET_DECAWM_OffRespectsLeftRightMargin(self):
    """Auto-wrap mode off respects left-right margins."""
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 9)
    esccsi.DECSTBM(5, 9)
    esccsi.CUP(Point(8, 9))
    esccsi.DECRESET(esccsi.DECAWM)
    escio.Write("abcdef")

    AssertEQ(GetCursorPosition().x(), 9)
    AssertScreenCharsInRectEqual(Rect(5, 8, 9, 9), [ NUL * 5, NUL * 3 + "af" ])

  def test_DECSET_Allow80To132(self):
    """DECCOLM only has an effect if Allow80To132 is on."""
    # There are four tests:
    #          Allowed   Not allowed
    # 80->132  1         3
    # 132->80  2         4

    # Test 1: 80->132, allowed
    # Allow 80 to 132.
    esccsi.DECSET(esccsi.Allow80To132)
    if (GetScreenSize().width() == 132):
      # Enter 80 columns so the test can proceed.
      esccsi.DECRESET(esccsi.DECCOLM)
      AssertEQ(GetScreenSize().width(), 80)

    # Enter 132
    esccsi.DECSET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

    # Test 2: 132->80, allowed
    esccsi.DECRESET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 80)

    # Test 3: 80->132
    # Disallow 80 to 132
    esccsi.DECRESET(esccsi.Allow80To132)
    # Try to enter 132 - should do nothing.
    esccsi.DECSET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 80)

    # Allow 80 to 132
    esccsi.DECSET(esccsi.Allow80To132)

    # Enter 132
    esccsi.DECSET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

    # Disallow 80 to 132
    esccsi.DECRESET(esccsi.Allow80To132)

    # Try to enter 80 - should do nothing.
    esccsi.DECRESET(esccsi.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

  def fillLineAndWriteTab(self):
    escio.Write(CR + LF)
    size = GetScreenSize()
    for i in xrange(size.width()):
      escio.Write("x")
    escio.Write(TAB)

  @knownBug(terminal="iTerm2", reason="iTerm2 wraps tabs")
  def test_DECSET_DECAWM_TabDoesNotWrapAround(self):
    """In auto-wrap mode, tabs to not wrap to the next line."""
    esccsi.DECSET(esccsi.DECAWM)
    size = GetScreenSize()
    for i in xrange(size.width() / 8 + 2):
      escio.Write(TAB)
    AssertEQ(GetCursorPosition().x(), size.width())
    AssertEQ(GetCursorPosition().y(), 1)

  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't implement DECSET 41 (MoreFix).")
  def test_DECSET_MoreFix(self):
    """xterm supports DECSET 41 to enable a fix for a bug in curses where it
    would draw to the end of a row and then insert a tab. When 41 is set, the
    tab is drawn."""
    # With MoreFix on, test that writing N x'es followed by a tab leaves the
    # cursor at the first tab stop.
    esccsi.DECSET(esccsi.MoreFix)
    self.fillLineAndWriteTab()
    AssertEQ(GetCursorPosition().x(), 9)
    escio.Write("1")
    AssertScreenCharsInRectEqual(Rect(9, 3, 9, 3), [ "1" ])

    # With MoreFix off, test that writing N x'es followed by a tab leaves the cursor at
    # the right margin
    esccsi.DECRESET(esccsi.MoreFix)
    self.fillLineAndWriteTab()
    AssertEQ(GetCursorPosition().x(), GetScreenSize().width())
    escio.Write("2")
    AssertScreenCharsInRectEqual(Rect(1, 5, 1, 5), [ "2" ])

  @knownBug(terminal="iTerm2",
            reason="iTerm2 only reverse wraps-around if there's a soft newline at the preceding line.")
  def test_DECSET_ReverseWraparound_BS(self):
    """xerm supports DECSET 45 to toggle 'reverse wraparound'. Both DECAWM and
    45 must be set."""
    # iTerm2 turns reverse wraparound on by default, while xterm does not.
    esccsi.DECSET(esccsi.ReverseWraparound)
    esccsi.DECSET(esccsi.DECAWM)
    esccsi.CUP(Point(1, 2))
    escio.Write(BS)
    AssertEQ(GetCursorPosition().x(), GetScreenSize().width())

  @knownBug(terminal="iTerm2", reason="iTerm2 moves the cursor back an extra space.")
  def test_DECSET_ReverseWraparoundLastCol_BS(self):
    """If the cursor is in the last column and a character was just output and
    reverse-wraparound is on then backspace by 1 has no effect."""
    esccsi.DECSET(esccsi.ReverseWraparound)
    esccsi.DECSET(esccsi.DECAWM)
    size = GetScreenSize()
    esccsi.CUP(Point(size.width() - 1, 1))
    escio.Write("a")
    AssertEQ(GetCursorPosition().x(), size.width())
    escio.Write("b")
    AssertEQ(GetCursorPosition().x(), size.width())
    escio.Write(BS)
    AssertEQ(GetCursorPosition().x(), size.width())

  def test_DECSET_ReverseWraparound_Multi(self):
    size = GetScreenSize()
    esccsi.CUP(Point(size.width() - 1, 1))
    escio.Write("abcd")
    esccsi.DECSET(esccsi.ReverseWraparound)
    esccsi.DECSET(esccsi.DECAWM)
    esccsi.CUB(4)
    AssertEQ(GetCursorPosition().x(), size.width() - 1)

  @knownBug(terminal="iTerm2",
            reason="iTerm2 doesn't implement DECRESET ReverseWraparound.")
  def test_DECSET_ResetReverseWraparoundDisablesIt(self):
    """DECRESET of reverse wraparound prevents it from happening."""
    # iTerm2 turns reverse wraparound on by default, while xterm does not.
    esccsi.DECRESET(esccsi.ReverseWraparound)
    esccsi.DECSET(esccsi.DECAWM)
    esccsi.CUP(Point(GetScreenSize().width() - 1, 1))
    escio.Write("abc")
    escio.Write(BS * 5)
    AssertEQ(GetCursorPosition().x(), 1)

  @knownBug(terminal="iTerm2",
             reason="iTerm2 does not require DECAWM for reverse wrap.")
  def test_DECSET_ReverseWraparound_RequiresDECAWM(self):
    """Reverse wraparound only works if DECAWM is set."""
    # iTerm2 turns reverse wraparound on by default, while xterm does not.
    esccsi.CUP(Point(GetScreenSize().width() - 1, 1))
    escio.Write("abc")
    esccsi.DECSET(esccsi.ReverseWraparound)
    esccsi.DECRESET(esccsi.DECAWM)
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
    esccsi.DECSET(code)
    after = GetCursorPosition()
    AssertEQ(before.x(), after.x())
    AssertEQ(before.y(), after.y())

    # Scribble in alt screen, clearing it first since who knows what might have
    # been there.
    esccsi.ED(2)
    esccsi.CUP(Point(1, 2))
    escio.Write("def" + CR +LF + "def")

    # Make sure abc is gone
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 3), [ NUL * 3, "def", "def" ])

    # Switch to main. Cursor should not move.
    before = GetCursorPosition()
    esccsi.DECRESET(code)
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
    esccsi.DECSET(code)
    after = GetCursorPosition()
    AssertEQ(before.x(), after.x())
    AssertEQ(before.y(), after.y())

    if altGetsClearedBeforeToMain:
      AssertScreenCharsInRectEqual(Rect(1, 1, 3, 3), [ NUL * 3, NUL * 3, NUL * 3 ])
    else:
      AssertScreenCharsInRectEqual(Rect(1, 1, 3, 3), [ NUL * 3, "def", "def" ])

  @knownBug(terminal="iTerm2", reason="DECSET 1047 (OPT_ALTBUF) not implemented.")
  def test_DECSET_OPT_ALTBUF(self):
    """DECSET 47 and DECSET 1047 do the same thing: If not in alt screen,
    switch to it. Its contents are NOT erased.

    DECRESET 1047 If on alt screen, clear the alt screen and then switch to the
    main screen."""
    self.doAltBuftest(esccsi.OPT_ALTBUF, True, False)

  def test_DECSET_ALTBUF(self):
    """DECSET 47 and DECSET 1047 do the same thing: If not in alt screen,
    switch to it. Its contents are NOT erased.

    DECRESET 47 switches to the main screen (without first clearing the alt
    screen)."""
    self.doAltBuftest(esccsi.ALTBUF, False, False)

  def test_DECSET_OPT_ALTBUF_CURSOR(self):
    """DECSET 1049 is like 1047 but it also saves the cursor position before
    entering alt and restores it after returning to main."""
    self.doAltBuftest(esccsi.OPT_ALTBUF_CURSOR, True, True)

  # xterm doesn't implement auto-wrap mode when wide characters are disabled.
  @optionRejects(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  def test_DECSET_DECLRMM(self):
    """Left-right margin. This is tested extensively in many other places as well."""
    # Turn on margins and write.
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 4)
    escio.Write("abcdefgh")
    esccsi.DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 3), [ "abcd", NUL + "efg", NUL + "h" + NUL * 2 ])

    # Turn off margins.
    esccsi.CUP(Point(1, 1))
    escio.Write("ABCDEFGH")
    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 1), [ "ABCDEFGH" ])

  @knownBug(terminal="iTerm2",
            reason="iTerm2 fails to reset DECLRMM (it just sets the margins to the screen edges)")
  def test_DECSET_DECLRMM_ResetByDECSTR(self):
    """DECSTR should turn off DECLRMM."""
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSTR()
    esccsi.DECSET(esccsi.DECAWM)
    esccsi.DECSET(esccsi.ReverseWraparound)
    esccsi.CUP(Point(GetScreenSize().width() - 1, 1))
    escio.Write("abc")
    # Reverse wraparound is disabled (at least in iTerm2) when a scroll region is present.
    escio.Write(BS * 3)
    AssertEQ(GetCursorPosition().y(), 1)

  @vtLevel(5)
  @knownBug(terminal="iTerm2", reason="DECNCSM not implemented")
  @optionRequired(terminal="xterm",
                  option=escargs.XTERM_WINOPS_ENABLED)
  def test_DECSET_DECNCSM(self):
    """From the manual: When enabled, a column mode change (either through
    Set-Up or by the escape sequence DECCOLM) does not clear the screen. When
    disabled, the column mode change clears the screen as a side effect."""
    # There are four tests:
    #                    DECNCSM Set   DECNCSM Reset
    # Column Mode Set    1             3
    # Column Mode Reset  2             4

    # 1: Set DECNCSM, Set column mode.
    esccsi.DECRESET(esccsi.DECCOLM)
    esccsi.DECSET(esccsi.DECNCSM)
    esccsi.CUP(Point(1, 1))
    escio.Write("1")
    esccsi.DECSET(esccsi.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "1" ])

    # 2: Set DECNCSM, Reset column mode.
    esccsi.DECSET(esccsi.DECCOLM)
    esccsi.DECSET(esccsi.DECNCSM)
    esccsi.CUP(Point(1, 1))
    escio.Write("2")
    esccsi.DECRESET(esccsi.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "2" ])

    # 3: Reset DECNCSM, Set column mode.
    esccsi.DECRESET(esccsi.DECCOLM)
    esccsi.DECRESET(esccsi.DECNCSM)
    esccsi.CUP(Point(1, 1))
    escio.Write("3")
    esccsi.DECSET(esccsi.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

    # 4: Reset DECNCSM, Reset column mode.
    esccsi.DECSET(esccsi.DECCOLM)
    esccsi.DECRESET(esccsi.DECNCSM)
    esccsi.CUP(Point(1, 1))
    escio.Write("4")
    esccsi.DECRESET(esccsi.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

  @knownBug(terminal="iTerm2", reason="Save/restore cursor not implemented")
  def test_DECSET_SaveRestoreCursor(self):
    """Set saves the cursor position. Reset restores it."""
    esccsi.CUP(Point(2, 3))
    esccsi.DECSET(esccsi.SaveRestoreCursor)
    esccsi.CUP(Point(5, 5))
    esccsi.DECRESET(esccsi.SaveRestoreCursor)
    cursor = GetCursorPosition()
    AssertEQ(cursor.x(), 2)
    AssertEQ(cursor.y(), 3)




