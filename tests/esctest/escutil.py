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

def AssertEQ(actual, expected):
  global gHaveAsserted
  gHaveAsserted = True
  if actual != expected:
    Raise(esctypes.TestFailure(actual, expected))

def AssertTrue(value):
  if force:
    return
  global gHaveAsserted
  gHaveAsserted = True
  assert value == True

def GetCursorPosition():
  escio.WriteCSI(params = [ 6 ], final="n", requestsReport=True)
  params = escio.ReadCSI("R")
  return Point(int(params[1]), int(params[0]))

def GetScreenSize():
  escio.WriteCSI(params = [ 18 ], final="t", requestsReport=True)
  params = escio.ReadCSI("t")
  return Size(params[2], params[1])

def Checksum(s):
  checksum = 0
  for c in s:
    checksum += ord(c)
  return checksum

def AssertScreenCharsInRectEqual(rect, expected_lines):
  global gHaveAsserted
  gHaveAsserted = True
  expected_checksum = 0
  area = 0
  if rect.height() != len(expected_lines):
    raise esctypes.InternalError("Height of rect (%d) does not match number of expected lines (%d)" % (rect.height(), len(expected_lines)))
  if rect.width() != len(expected_lines[0]):
    raise esctypes.InternalError("Width of rect (%d) does not match number of characters in first of expected lines (%d)" % (rect.width(), len(expected_lines[0])))
  for line in expected_lines:
    expected_checksum += Checksum(line)

  # Check each point individually. The dumb checksum algorithm can't distinguish
  # "ab" from "ba", so equivalence of multiple characters means nothing.
  actual = list(expected_lines)
  errorLocations = []
  for point in rect.points():
    y = point.y() - rect.top()
    x = point.x() - rect.left()
    expected_checksum = ord(expected_lines[y][x])
    actual_checksum = GetChecksumOfRect(Rect(left=point.x(),
                                             top=point.y(),
                                             right=point.x(),
                                             bottom=point.y()))
    s = actual[y]
    c = chr(actual_checksum)
    s = s[:x] + c + s[x + 1:]
    actual[y] = s
    if expected_checksum != actual_checksum:
      errorLocations.append(point)
  if len(errorLocations) > 0:
    Raise(esctypes.ChecksumException(errorLocations, actual, expected_lines))

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

def knownBug(terminal, reason, noop=False):
  """Decorator for a method indicating that it should fail and explaining why.
  If the method is intended to succeed when nothing happens (that is, the
  sequence being tested is a no-op) then the caller should set noop=True.
  Otherwise, successes will raise an InternalError exception."""
  def decorator(func):
    @functools.wraps(func)
    def func_wrapper(self, *args, **kwargs):
      if self._args.expected_terminal == terminal:
        try:
          func(self, *args, **kwargs)
        except Exception, e:
          raise esctypes.KnownBug(reason)

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
