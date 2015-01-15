import esccsi
import escio
from esclog import LogDebug, LogInfo, LogError, Print
import esctypes
from esctypes import Point, Size, Rect
import functools
import traceback

gNextId = 1
gHaveAsserted = False


def AssertEQ(actual, expected):
  global gHaveAsserted
  gHaveAsserted = True
  if actual != expected:
    raise esctypes.TestFailure(actual, expected)

def AssertTrue(value):
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

  expected_checksum = expected_checksum & 0xffff
  actual_checksum = GetChecksumOfRect(rect)
  if expected_checksum != actual_checksum:
    LogError("Checksums did not match for rect %s. Expected=%s, actual=%s" %
        (str(rect), str(expected_checksum), str(actual_checksum)))
    for point in rect.points():
      y = point.y() - rect.top()
      x = point.x() - rect.left()
      expected_checksum = ord(expected_lines[y][x])
      actual_checksum = GetChecksumOfRect(Rect(left=point.x(),
                                               top=point.y(),
                                               right=point.x(),
                                               bottom=point.y()))
      LogError("  At %s: expected=%d actual=%d" % (str(point), expected_checksum, actual_checksum))
      if expected_checksum != actual_checksum:
        raise esctypes.ChecksumException(point, actual_checksum, expected_checksum)

    # Shouldn't get here: if the rectangles' checksum don't match then some
    # character should differ.
    LogError("** Somehow, all individual characters matched but checksums did not.")
    assert False

def GetChecksumOfRect(rect):
  global gNextId
  Pid = gNextId
  gNextId += 1
  esccsi.CSI_DECRQCRA(Pid, 0, rect)
  params = escio.ReadDCS()

  str_pid = str(Pid)
  if not params.startswith(str_pid):
    raise esctypes.BadResponse(params, "Prefix of " + str_pid)

  i = len(str_pid)

  assert params[i:].startswith("!~")
  i += 2

  hex_checksum = params[i:]
  return int(hex_checksum, 16)

def knownBug(terminal, reason):
  def decorator(func):
    @functools.wraps(func)
    def func_wrapper(self, *args, **kwargs):
      if self._args.expected_terminal == terminal:
        try:
          func(self, *args, **kwargs)
          raise esctypes.InternalError("Should have failed")
        except:
          raise esctypes.KnownBug(reason)
      else:
        func(self, *args, **kwargs)
    return func_wrapper
  return decorator

def AssertAssertionAsserted():
  global gHaveAsserted
  ok = gHaveAsserted
  gHaveAsserted = False
  if not ok:
    raise esctypes.BrokenTest("No assertion attempted.")
