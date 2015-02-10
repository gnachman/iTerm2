import esc
import esccsi
import escio
from esclog import LogDebug, LogInfo, LogError, Print
import esctypes
from esctypes import Point, Size, Rect
import functools
import traceback

gNextId = 1
gHaveAsserted = False
force = False

def Raise(e):
  if not force:
    raise e

def AssertGE(actual, minimum):
  global gHaveAsserted
  gHaveAsserted = True
  if actual < minimum:
    Raise(esctypes.TestFailure(actual, expected))

def AssertEQ(actual, expected):
  global gHaveAsserted
  gHaveAsserted = True
  if actual != expected:
    Raise(esctypes.TestFailure(actual, expected))

def AssertTrue(value, details=None):
  if force:
    return
  global gHaveAsserted
  gHaveAsserted = True
  if value != True:
    Raise(esctypes.TestFailure(value, True, details))

def GetIconTitle():
  esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_REPORT_ICON_LABEL)
  return escio.ReadOSC("L")

def GetWindowTitle():
  if args.expected_terminal == "iTerm2":
    raise esctypes.InternalError(
        "iTerm2 uses L instead of l as initial char for window title reports.")
  esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_REPORT_WINDOW_TITLE)
  return escio.ReadOSC("l")

def GetWindowSizePixels():
  """Returns a Size giving the window's size in pixels."""
  esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_REPORT_WINDOW_SIZE_PIXELS)
  params = escio.ReadCSI("t")
  AssertTrue(params[0] == 4)
  AssertTrue(len(params) >= 3)
  return Size(params[2], params[1])

def GetWindowPosition():
  """Returns a Point giving the window's origin in screen pixels."""
  esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_REPORT_WINDOW_POSITION)
  params = escio.ReadCSI("t")
  AssertTrue(params[0] == 3)
  AssertTrue(len(params) >= 3)
  return Point(params[1], params[2])

def GetIsIconified():
  esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_REPORT_WINDOW_STATE)
  params = escio.ReadCSI("t")
  AssertTrue(params[0] in [ 1, 2 ], "Params are " + str(params))
  return params[0] == 2

def GetCursorPosition():
  esccsi.CSI_DSR(esccsi.DSRCPR, suppressSideChannel=True)
  params = escio.ReadCSI("R")
  return Point(int(params[1]), int(params[0]))

def GetScreenSize():
  esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_REPORT_TEXT_AREA_CHARS)
  params = escio.ReadCSI("t")
  return Size(params[2], params[1])

def GetDisplaySize():
  esccsi.CSI_XTERM_WINOPS(esccsi.WINOP_REPORT_SCREEN_SIZE_CHARS)
  params = escio.ReadCSI("t")
  return Size(params[2], params[1])

def AssertScreenCharsInRectEqual(rect, expected_lines):
  global gHaveAsserted
  gHaveAsserted = True

  if rect.height() != len(expected_lines):
    raise esctypes.InternalError(
        "Height of rect (%d) does not match number of expected lines (%d)" % (
          rect.height(),
          len(expected_lines)))

  # Check each point individually. The dumb checksum algorithm can't distinguish
  # "ab" from "ba", so equivalence of two multiple-character rects means nothing.

  # |actual| and |expected| will form human-readable arrays of lines
  actual = []
  expected = []
  # Additional information about mismatches.
  errorLocations = []
  for point in rect.points():
    y = point.y() - rect.top()
    x = point.x() - rect.left()
    expected_line = expected_lines[y]
    if rect.width() != len(expected_line):
      fmt = ("Width of rect (%d) does not match number of characters in expected line " +
          "index %d, coordinate %d (its length is %d)")
      raise esctypes.InternalError(
          fmt % (rect.width(),
                 y,
                 point.y(),
                 len(expected_lines[y])))

    expected_checksum = ord(expected_line[x])

    actual_checksum = GetChecksumOfRect(Rect(left=point.x(),
                                             top=point.y(),
                                             right=point.x(),
                                             bottom=point.y()))
    if len(actual) <= y:
      actual.append("")
    if actual_checksum == 0:
      actual[y] += '.'
    else:
      actual[y] += chr(actual_checksum)

    if len(expected) <= y:
      expected.append("")
    if expected_checksum == 0:
      expected[y] += '.'
    else:
      expected[y] += chr(expected_checksum)

    if expected_checksum != actual_checksum:
      errorLocations.append("At %s expected '%c' (0x%02x) but got '%c' (0x%02x)" % (
        str(point),
        chr(expected_checksum),
        expected_checksum,
        chr(actual_checksum),
        actual_checksum))

  if len(errorLocations) > 0:
    Raise(esctypes.ChecksumException(errorLocations, actual, expected))

def GetChecksumOfRect(rect):
  global gNextId
  Pid = gNextId
  gNextId += 1
  esccsi.CSI_DECRQCRA(Pid, 0, rect)
  params = escio.ReadDCS()

  str_pid = str(Pid)
  if not params.startswith(str_pid):
    Raise(esctypes.BadResponse(params, "Prefix of " + str_pid))

  i = len(str_pid)

  assert params[i:].startswith("!~")
  i += 2

  hex_checksum = params[i:]
  return int(hex_checksum, 16)

def vtLevel(minimum):
  """Defines the minimum VT level the terminal must be capable of to succeed."""
  def decorator(func):
    @functools.wraps(func)
    def func_wrapper(self, *args, **kwargs):
      if esc.vtLevel >= minimum:
        func(self, *args, **kwargs)
      else:
        raise esctypes.InsufficientVTLevel(esc.vtLevel, minimum)
    return func_wrapper
  return decorator

def intentionalDeviationFromSpec(terminal, reason):
  """Decorator for a method indicating that what it tests deviates from the
  sepc and why."""
  def decorator(func):
    @functools.wraps(func)
    def func_wrapper(self, *args, **kwargs):
      func(self, *args, **kwargs)
    return func_wrapper
  return decorator

def optionRequired(terminal, option):
  """Decorator for a method indicating that it should fail unless an option is
  present."""
  reason = "Terminal \"" + terminal + "\" requires option \"" + option + "\" for this test to pass."
  def decorator(func):
    @functools.wraps(func)
    def func_wrapper(self, *args, **kwargs):
      hasOption = (self._args.options is not None and
                   option in self._args.options)
      if self._args.expected_terminal == terminal:
        try:
          func(self, *args, **kwargs)
        except Exception, e:
          if hasOption:
            # Failed despite option being set. Re-raise.
            raise
          tb = traceback.format_exc()
          lines = tb.split("\n")
          lines = map(lambda x: "EXPECTED FAILURE (MISSING OPTION): " + x, lines)
          raise esctypes.KnownBug(reason + "\n\n" + "\n".join(lines))

        # Got here because test passed. If the option isn't set, that's
        # unexpected so we raise an error.
        if not force and not hasOption:
          raise esctypes.InternalError("Should have failed: " + reason)
      else:
        func(self, *args, **kwargs)
    return func_wrapper
  return decorator

def knownBug(terminal, reason, noop=False, shouldTry=True):
  """Decorator for a method indicating that it should fail and explaining why.
  If the method is intended to succeed when nothing happens (that is, the
  sequence being tested is a no-op) then the caller should set noop=True.
  Otherwise, successes will raise an InternalError exception. If shouldTry is
  true then the test will be run to make sure it really does fail."""
  def decorator(func):
    @functools.wraps(func)
    def func_wrapper(self, *args, **kwargs):
      if self._args.expected_terminal == terminal:
        if not shouldTry:
          raise esctypes.KnownBug(reason + " (not trying)")
        try:
          func(self, *args, **kwargs)
        except Exception, e:
          tb = traceback.format_exc()
          lines = tb.split("\n")
          lines = map(lambda x: "KNOWN BUG: " + x, lines)
          raise esctypes.KnownBug(reason + "\n" + "\n".join(lines))

        # Shouldn't get here because the test should have failed. If 'force' is on then
        # tests always pass, though.
        if not force and not noop:
          raise esctypes.InternalError("Should have failed")
      else:
        func(self, *args, **kwargs)
    return func_wrapper
  return decorator

def AssertAssertionAsserted():
  if force:
    return
  global gHaveAsserted
  ok = gHaveAsserted
  gHaveAsserted = False
  if not ok and not force:
    raise esctypes.BrokenTest("No assertion attempted.")
