from esc import ESC, TAB, NUL, CR, LF, BS
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug, optionRequired, vtLevel, optionRejects
import escargs
import esccmd
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
    esccmd.DECSET(esccmd.Allow80To132)

    # Write something to verify that it gets erased
    esccmd.CUP(Point(5, 5))
    escio.Write("x")

    # Set left-right and top-bottom margins to ensure they're removed.
    esccmd.DECSTBM(1, 2)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(1, 2)

    # Enter 132-column mode.
    esccmd.DECSET(esccmd.DECCOLM)

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

    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 2, 5, 3), [ "Hello", "World" ])
    AssertScreenCharsInRectEqual(Rect(5, 5, 5, 5), [ NUL ])

  def test_DECSET_DECOM(self):
    """Set origin mode. Cursor positioning is relative to the scroll region's
    top left."""
    # Origin mode allows cursor addressing relative to a user-defined origin.
    # This mode resets when the terminal is powered up or reset. It does not
    # affect the erase in display (ED) function.
    esccmd.DECSTBM(5, 7)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 7)
    esccmd.DECSET(esccmd.DECOM)
    esccmd.CUP(Point(1, 1))
    escio.Write("X")

    esccmd.DECRESET(esccmd.DECLRMM)
    esccmd.DECSTBM()

    # Still in origin mode but origin at 1,1. DECRQCRA respects origin
    # mode, so this is an extra wrinkle in this test.
    AssertScreenCharsInRectEqual(Rect(5, 5, 5, 5), [ "X" ])

  def test_DECSET_DECOM_SoftReset(self):
    """Soft reset turns off DECOM."""
    esccmd.DECSTBM(5, 7)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 7)
    esccmd.DECSET(esccmd.DECOM)
    esccmd.DECSTR()
    esccmd.CHA(1)
    esccmd.VPA(1)
    escio.Write("X")

    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "X" ])

  def test_DECSET_DECOM_DECRQCRA(self):
    """DECRQCRA should be relative to the origin in origin mode. DECRQCRA
    doesn't have its own test so this is tested here instead."""
    esccmd.CUP(Point(5, 5))
    escio.Write("X")

    esccmd.DECSTBM(5, 7)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 7)
    esccmd.DECSET(esccmd.DECOM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "X" ])

  # This test is flaky so I turned off shouldTry to avoid false failures.
  @knownBug(terminal="xterm",
            reason="xterm produces incorrect output if ABC is written too quickly. A pause before writing the C produces correct output.",
            shouldTry=False)
  def test_DECSET_DECAWM(self):
    """Auto-wrap mode."""
    size = GetScreenSize()
    esccmd.CUP(Point(size.width() - 1, 1))
    esccmd.DECSET(esccmd.DECAWM)
    escio.Write("abc")

    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ "c" ])

    esccmd.CUP(Point(size.width() - 1, 1))
    esccmd.DECRESET(esccmd.DECAWM)
    escio.Write("ABC")

    AssertScreenCharsInRectEqual(Rect(size.width() - 1, 1, size.width(), 1), [ "AC" ])
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ "c" ])

  def test_DECSET_DECAWM_CursorAtRightMargin(self):
    """If you start at column 1 and write N+1 characters (where N is the width of
    the window) the cursor's position should go: 1, 2, ..., N, N, 2."""
    esccmd.DECSET(esccmd.DECAWM)
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
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 9)
    esccmd.DECSTBM(5, 9)
    esccmd.CUP(Point(8, 9))
    esccmd.DECSET(esccmd.DECAWM)
    escio.Write("abcdef")

    AssertScreenCharsInRectEqual(Rect(5, 8, 9, 9), [ NUL * 3 + "ab", "cdef" + NUL ])

  def test_DECSET_DECAWM_OffRespectsLeftRightMargin(self):
    """Auto-wrap mode off respects left-right margins."""
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 9)
    esccmd.DECSTBM(5, 9)
    esccmd.CUP(Point(8, 9))
    esccmd.DECRESET(esccmd.DECAWM)
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
    esccmd.DECSET(esccmd.Allow80To132)
    if (GetScreenSize().width() == 132):
      # Enter 80 columns so the test can proceed.
      esccmd.DECRESET(esccmd.DECCOLM)
      AssertEQ(GetScreenSize().width(), 80)

    # Enter 132
    esccmd.DECSET(esccmd.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

    # Test 2: 132->80, allowed
    esccmd.DECRESET(esccmd.DECCOLM)
    AssertEQ(GetScreenSize().width(), 80)

    # Test 3: 80->132
    # Disallow 80 to 132
    esccmd.DECRESET(esccmd.Allow80To132)
    # Try to enter 132 - should do nothing.
    esccmd.DECSET(esccmd.DECCOLM)
    AssertEQ(GetScreenSize().width(), 80)

    # Allow 80 to 132
    esccmd.DECSET(esccmd.Allow80To132)

    # Enter 132
    esccmd.DECSET(esccmd.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

    # Disallow 80 to 132
    esccmd.DECRESET(esccmd.Allow80To132)

    # Try to enter 80 - should do nothing.
    esccmd.DECRESET(esccmd.DECCOLM)
    AssertEQ(GetScreenSize().width(), 132)

  def fillLineAndWriteTab(self):
    escio.Write(CR + LF)
    size = GetScreenSize()
    for i in xrange(size.width()):
      escio.Write("x")
    escio.Write(TAB)

  def test_DECSET_DECAWM_TabDoesNotWrapAround(self):
    """In auto-wrap mode, tabs to not wrap to the next line."""
    esccmd.DECSET(esccmd.DECAWM)
    size = GetScreenSize()
    for i in xrange(size.width() / 8 + 2):
      escio.Write(TAB)
    AssertEQ(GetCursorPosition().x(), size.width())
    AssertEQ(GetCursorPosition().y(), 1)
    escio.Write("X")

  def test_DECSET_DECAWM_NoLineWrapOnTabWithLeftRightMargin(self):
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.XTERM_WINOPS(esccmd.WINOP_RESIZE_CHARS,
                            24,
                            80)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(10, 20)

    # Move to origin and tab thrice. Should stop at right margin.
    AssertEQ(GetCursorPosition(), Point(1, 1))
    escio.Write(TAB)
    AssertEQ(GetCursorPosition(), Point(9, 1))
    escio.Write(TAB)
    AssertEQ(GetCursorPosition(), Point(17, 1))
    escio.Write(TAB)
    AssertEQ(GetCursorPosition(), Point(20, 1))
    escio.Write(TAB)
    AssertEQ(GetCursorPosition(), Point(20, 1))

  def test_DECSET_MoreFix(self):
    """xterm supports DECSET 41 to enable a fix for a bug in curses where it
    would draw to the end of a row and then insert a tab. When 41 is set, the
    tab is drawn."""
    # With MoreFix on, test that writing N x'es followed by a tab leaves the
    # cursor at the first tab stop.
    esccmd.DECSET(esccmd.MoreFix)
    self.fillLineAndWriteTab()
    AssertEQ(GetCursorPosition().x(), 9)
    escio.Write("1")
    AssertScreenCharsInRectEqual(Rect(9, 3, 9, 3), [ "1" ])

    # With MoreFix off, test that writing N x'es followed by a tab leaves the cursor at
    # the right margin
    esccmd.DECRESET(esccmd.MoreFix)
    self.fillLineAndWriteTab()
    AssertEQ(GetCursorPosition().x(), GetScreenSize().width())
    escio.Write("2")
    AssertScreenCharsInRectEqual(Rect(1, 5, 1, 5), [ "2" ])

  def test_DECSET_ReverseWraparound_BS(self):
    """xerm supports DECSET 45 to toggle 'reverse wraparound'. Both DECAWM and
    45 must be set."""
    # iTerm2 turns reverse wraparound on by default, while xterm does not.
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.CUP(Point(1, 2))
    escio.Write(BS)
    AssertEQ(GetCursorPosition().x(), GetScreenSize().width())

  def test_DECSET_ReverseWraparoundLastCol_BS(self):
    """If the cursor is in the last column and a character was just output and
    reverse-wraparound is on then backspace by 1 has no effect."""
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECSET(esccmd.DECAWM)
    size = GetScreenSize()
    esccmd.CUP(Point(size.width() - 1, 1))
    escio.Write("a")
    AssertEQ(GetCursorPosition().x(), size.width())
    escio.Write("b")
    AssertEQ(GetCursorPosition().x(), size.width())
    escio.Write(BS)
    AssertEQ(GetCursorPosition().x(), size.width())

  def test_DECSET_ReverseWraparound_Multi(self):
    size = GetScreenSize()
    esccmd.CUP(Point(size.width() - 1, 1))
    escio.Write("abcd")
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.CUB(4)
    AssertEQ(GetCursorPosition().x(), size.width() - 1)

  def test_DECSET_ResetReverseWraparoundDisablesIt(self):
    """DECRESET of reverse wraparound prevents it from happening."""
    # Note that iTerm disregards the value of ReverseWraparound when there's a
    # soft EOL on the preceding line and always wraps.
    esccmd.DECRESET(esccmd.ReverseWraparound)
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.CUP(Point(1, 2))
    escio.Write(BS)
    AssertEQ(GetCursorPosition().x(), 1)

  def test_DECSET_ReverseWraparound_RequiresDECAWM(self):
    """Reverse wraparound only works if DECAWM is set."""
    # iTerm2 turns reverse wraparound on by default, while xterm does not.
    esccmd.CUP(Point(1, 2))
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECRESET(esccmd.DECAWM)
    escio.Write(BS)
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
    esccmd.DECSET(code)
    after = GetCursorPosition()
    AssertEQ(before.x(), after.x())
    AssertEQ(before.y(), after.y())

    # Scribble in alt screen, clearing it first since who knows what might have
    # been there.
    esccmd.ED(2)
    esccmd.CUP(Point(1, 2))
    escio.Write("def" + CR +LF + "def")

    # Make sure abc is gone
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 3), [ NUL * 3, "def", "def" ])

    # Switch to main. Cursor should not move.
    before = GetCursorPosition()
    esccmd.DECRESET(code)
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
    esccmd.DECSET(code)
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
    self.doAltBuftest(esccmd.OPT_ALTBUF, True, False)

  def test_DECSET_ALTBUF(self):
    """DECSET 47 and DECSET 1047 do the same thing: If not in alt screen,
    switch to it. Its contents are NOT erased.

    DECRESET 47 switches to the main screen (without first clearing the alt
    screen)."""
    self.doAltBuftest(esccmd.ALTBUF, False, False)

  def test_DECSET_OPT_ALTBUF_CURSOR(self):
    """DECSET 1049 is like 1047 but it also saves the cursor position before
    entering alt and restores it after returning to main."""
    self.doAltBuftest(esccmd.OPT_ALTBUF_CURSOR, True, True)

  # xterm doesn't implement auto-wrap mode when wide characters are disabled.
  @optionRejects(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  def test_DECSET_DECLRMM(self):
    """Left-right margin. This is tested extensively in many other places as well."""
    # Turn on margins and write.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 4)
    escio.Write("abcdefgh")
    esccmd.DECRESET(esccmd.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 3), [ "abcd", NUL + "efg", NUL + "h" + NUL * 2 ])

    # Turn off margins.
    esccmd.CUP(Point(1, 1))
    escio.Write("ABCDEFGH")
    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 1), [ "ABCDEFGH" ])

  def test_DECSET_DECLRMM_MarginsResetByDECSTR(self):
    esccmd.DECSLRM(2, 4)
    esccmd.DECSTR()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.CUP(Point(3, 3))
    escio.Write("abc")
    AssertEQ(GetCursorPosition().x(), 6)

  def test_DECSET_DECLRMM_ModeNotResetByDECSTR(self):
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSTR()
    esccmd.DECSLRM(2, 4)
    esccmd.CUP(Point(3, 3))
    escio.Write("abc")
    AssertEQ(GetCursorPosition().x(), 3)

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
    esccmd.DECRESET(esccmd.DECCOLM)
    esccmd.DECSET(esccmd.DECNCSM)
    esccmd.CUP(Point(1, 1))
    escio.Write("1")
    esccmd.DECSET(esccmd.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "1" ])

    # 2: Set DECNCSM, Reset column mode.
    esccmd.DECSET(esccmd.DECCOLM)
    esccmd.DECSET(esccmd.DECNCSM)
    esccmd.CUP(Point(1, 1))
    escio.Write("2")
    esccmd.DECRESET(esccmd.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ "2" ])

    # 3: Reset DECNCSM, Set column mode.
    esccmd.DECRESET(esccmd.DECCOLM)
    esccmd.DECRESET(esccmd.DECNCSM)
    esccmd.CUP(Point(1, 1))
    escio.Write("3")
    esccmd.DECSET(esccmd.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

    # 4: Reset DECNCSM, Reset column mode.
    esccmd.DECSET(esccmd.DECCOLM)
    esccmd.DECRESET(esccmd.DECNCSM)
    esccmd.CUP(Point(1, 1))
    escio.Write("4")
    esccmd.DECRESET(esccmd.DECCOLM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), [ NUL ])

  @knownBug(terminal="iTerm2", reason="Save/restore cursor not implemented")
  def test_DECSET_SaveRestoreCursor(self):
    """Set saves the cursor position. Reset restores it."""
    esccmd.CUP(Point(2, 3))
    esccmd.DECSET(esccmd.SaveRestoreCursor)
    esccmd.CUP(Point(5, 5))
    esccmd.DECRESET(esccmd.SaveRestoreCursor)
    cursor = GetCursorPosition()
    AssertEQ(cursor.x(), 2)
    AssertEQ(cursor.y(), 3)




