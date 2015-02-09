import esccsi
import esclog
from escutil import AssertEQ, AssertTrue, GetCursorPosition, GetDisplaySize, GetIsIconified, GetScreenSize, GetWindowPosition, GetWindowSizePixels, knownBug
from esctypes import Point, Size
import time

# No tests for the following operations:
# 5 - Raise in stacking order
# 6 - Lower in stacking order
# 7 - Refresh

class XtermWinopsTests(object):
  def __init__(self, args):
    self._args = args

  def test_XtermWinops_IconifyDeiconfiy(self):
    needsSleep = self._args.expected_terminal in [ "xterm" ]
    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_ICONIFY)
    if needsSleep:
      time.sleep(1)
    AssertEQ(GetIsIconified(), True)

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_DEICONIFY)
    if needsSleep:
      time.sleep(1)
    AssertEQ(GetIsIconified(), False)

  def test_XtermWinops_MoveToXY(self):
    needsSleep = self._args.expected_terminal in [ "xterm" ]
    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_MOVE, 0, 0)
    if needsSleep:
      time.sleep(0.1)
    AssertEQ(GetWindowPosition(), Point(0, 0))
    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_MOVE, 1, 1)
    if needsSleep:
      time.sleep(0.1)
    AssertEQ(GetWindowPosition(), Point(1, 1))

  def test_XtermWinops_ResizePixels_BothParameters(self):
    """Resize the window to a pixel size, giving both parameters."""
    original_size = GetWindowSizePixels()
    desired_size = Size(400, 200)

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            desired_size.height(),
                            desired_size.width())
    # See if we're within 20px of the desired size on each dimension. It won't
    # be exact because most terminals snap to grid.
    actual_size = GetWindowSizePixels()
    error = Size(abs(actual_size.width() - desired_size.width()),
                 abs(actual_size.height() - desired_size.height()))
    max_error = 20
    AssertTrue(error.width() <= max_error)
    AssertTrue(error.height() <= max_error)

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            original_size.height(),
                            original_size.width())

  def test_XtermWinops_ResizePixels_OmittedHeight(self):
    """Resize the window to a pixel size, omitting one parameter. The size
    should not change in the direction of the omitted parameter."""
    original_size = GetWindowSizePixels()
    desired_size = Size(400, original_size.height())

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            None,
                            desired_size.width())
    # See if we're within 20px of the desired size. It won't be exact because
    # most terminals snap to grid.
    actual_size = GetWindowSizePixels()
    error = Size(abs(actual_size.width() - desired_size.width()),
                 abs(actual_size.height() - desired_size.height()))
    max_error = 20
    AssertTrue(error.width() <= max_error)
    AssertTrue(error.height() <= max_error)

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            original_size.height(),
                            original_size.width())

  def test_XtermWinops_ResizePixels_OmittedWidth(self):
    """Resize the window to a pixel size, omitting one parameter. The size
    should not change in the direction of the omitted parameter."""
    original_size = GetWindowSizePixels()
    desired_size = Size(original_size.width(), 200)

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            desired_size.height())
    # See if we're within 20px of the desired size. It won't be exact because
    # most terminals snap to grid.
    actual_size = GetWindowSizePixels()
    error = Size(abs(actual_size.width() - desired_size.width()),
                 abs(actual_size.height() - desired_size.height()))
    max_error = 20
    AssertTrue(error.width() <= max_error)
    AssertTrue(error.height() <= max_error)

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            original_size.height(),
                            original_size.width())

  @knownBug(terminal="xterm",
      reason="GetScreenSize reports an incorrect value, at least on Mac OS X")
  def test_XtermWinops_ResizePixels_ZeroWidth(self):
    """Resize the window to a pixel size, setting one parameter to 0. The
    window should maximize in the direction of the 0 parameter."""
    original_size = GetWindowSizePixels()

    # Set height and maximize width.
    desired_height = 200
    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            desired_height,
                            0)

    # Make sure the height changed as requested.
    max_error = 20
    actual_size = GetWindowSizePixels()
    AssertTrue(abs(actual_size.height() - desired_height) < max_error)

    # See if the width is about as big as the display (only measurable in
    # characters, not pixels).
    display_size = GetDisplaySize()  # In characters
    screen_size = GetScreenSize()  # In characters
    max_error = 5
    AssertTrue(abs(display_size.width() - screen_size.width()) < max_error)

    # Restore to original size.
    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            original_size.height(),
                            original_size.width())

  @knownBug(terminal="xterm",
      reason="GetScreenSize reports an incorrect value, at least on Mac OS X")
  def test_XtermWinops_ResizePixels_ZeroHeight(self):
    """Resize the window to a pixel size, setting one parameter to 0. The
    window should maximize in the direction of the 0 parameter."""
    original_size = GetWindowSizePixels()

    # Set height and maximize width.
    desired_width = 400
    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            0,
                            desired_width)

    # Make sure the height changed as requested.
    max_error = 20
    actual_size = GetWindowSizePixels()
    AssertTrue(abs(actual_size.width() - desired_width) < max_error)

    # See if the height is about as big as the display (only measurable in
    # characters, not pixels).
    display_size = GetDisplaySize()  # In characters
    screen_size = GetScreenSize()  # In characters
    max_error = 5
    AssertTrue(abs(display_size.height() - screen_size.height()) < max_error)

    # Restore to original size.
    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_PIXELS,
                            original_size.height(),
                            original_size.width())

  def test_XtermWinops_ResizeChars_BothParameters(self):
    """Resize the window to a character size, giving both parameters."""
    desired_size = Size(20, 21)

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_CHARS,
                            desired_size.height(),
                            desired_size.width())
    AssertEQ(GetScreenSize(), desired_size)

  @knownBug(terminal="iTerm2", reason="Doesn't interpret 0 param to mean max")
  def test_XtermWinops_ResizeChars_ZeroWidth(self):
    """Resize the window to a character size, setting one param to 0 (max size
    in that direction)."""
    max_size = GetDisplaySize()
    desired_size = Size(max_size.width(), 21)

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_CHARS,
                            desired_size.height(),
                            0)
    AssertEQ(GetScreenSize(), desired_size)

  @knownBug(terminal="iTerm2", reason="Doesn't interpret 0 param to mean max")
  def test_XtermWinops_ResizeChars_ZeroHeight(self):
    """Resize the window to a character size, setting one param to 0 (max size
    in that direction)."""
    max_size = GetDisplaySize()
    desired_size = Size(20, max_size.height())

    esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_RESIZE_CHARS,
                            0,
                            desired_size.width())
    AssertEQ(GetScreenSize(), desired_size)

