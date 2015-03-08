from esc import ESC, ST, NUL
import escargs
from esclog import LogDebug, LogInfo, LogError, Print
import esctypes
import os
import select
import sys
import tty

stdin_fd = None
stdout_fd = None
gSideChannel = None
use8BitControls = False

def Init():
  global stdout_fd
  global stdin_fd

  stdout_fd = os.fdopen(sys.stdout.fileno(), 'w', 0)
  stdin_fd = os.fdopen(sys.stdin.fileno(), 'r', 0)
  tty.setraw(stdin_fd)

def Shutdown():
  tty.setcbreak(stdin_fd)

def Write(s, sideChannelOk=True):
  global gSideChannel
  if sideChannelOk and gSideChannel is not None:
    gSideChannel.write(s)
  stdout_fd.write(s)

def SetSideChannel(filename):
  global gSideChannel
  if filename is None:
    if gSideChannel:
      gSideChannel.close()
      gSideChannel = None
  else:
    gSideChannel = open(filename, "w")

def OSC():
  if use8BitControls:
    return chr(0x9d)
  else:
    return ESC + "]"

def CSI():
  if use8BitControls:
    return chr(0x9b)
  else:
    return ESC + "["

def DCS():
  if use8BitControls:
    return chr(0x90)
  else:
    return ESC + "P"

def WriteOSC(params, bel=False, requestsReport=False):
  str_params = map(str, params)
  joined_params = ";".join(str_params)
  ST = ESC + "\\"
  BEL = chr(7)
  if bel:
    terminator = BEL
  else:
    terminator = ST
  sequence = OSC() + joined_params + terminator
  LogDebug("Send sequence: " + sequence.replace(ESC, "<ESC>"))
  Write(sequence, sideChannelOk=not requestsReport)

def WriteDCS(introducer, params):
  Write(DCS() + introducer + params + ST)

def WriteCSI(prefix="", params=[], intermediate="", final="", requestsReport=False):
  if len(final) == 0:
    raise esctypes.InternalError("final must not be empty")
  def StringifyCSIParam(p):
    if p is None:
      return ""
    else:
      return str(p)
  str_params = map(StringifyCSIParam, params)

  # Remove trailing empty args
  while len(str_params) > 0 and str_params[-1] == "":
    str_params = str_params[:-1]

  joined_params = ";".join(str_params)
  sequence = CSI() + prefix + joined_params + intermediate + final
  LogDebug("Send sequence: " + sequence.replace(ESC, "<ESC>"))
  Write(sequence, sideChannelOk=not requestsReport)

def ReadOrDie(e):
  c = read(1)
  AssertCharsEqual(c, e)

def AssertCharsEqual(c, e):
  if c != e:
    raise esctypes.InternalError("Read %c (0x%02x), expected %c (0x%02x)" % (c, ord(c), e, ord(e)))

def ReadOSC(expected_prefix):
  """Read an OSC code starting with |expected_prefix|."""
  ReadOrDie(ESC)
  ReadOrDie(']')
  for c in expected_prefix:
    ReadOrDie(c)
  s = ""
  while not s.endswith(ST):
    c = read(1)
    s += c
  return s[:-2]

def ReadCSI(expected_final, expected_prefix=None):
  """Read a CSI code ending with |expected_final| and returns an array of parameters. """

  c = read(1)
  if c == ESC:
    ReadOrDie('[')
  elif ord(c) != 0x9b:
    raise esctypes.InternalError("Read %c (0x%02x), expected CSI" % (c, ord(c)))

  params = []
  current_param = ""

  c = read(1)
  if not c.isdigit() and c != ';':
    if c == expected_prefix:
      c = read(1)
    else:
      raise esctypes.InternalError("Unexpected character 0x%02x" % ord(c))

  while True:
    if c == ";":
      params.append(int(current_param))
      current_param = ""
    elif c >= '0' and c <= '9':
      current_param += c
    else:
      # Read all the final characters, asserting they match.
      while True:
        AssertCharsEqual(c, expected_final[0])
        expected_final = expected_final[1:]
        if len(expected_final) > 0:
          c = read(1)
        else:
          break

      if current_param == "":
        params.append(None)
      else:
        params.append(int(current_param))
      break
    c = read(1)
  return params

def ReadDCS():
  """ Read a DCS code. Returns the characters between DCS and ST. """
  c = read(1)
  if c == ESC:
    ReadOrDie("P")
  elif ord(c) != 0x90:
    raise esctypes.InternalError("Read %c (0x%02x), expected DCS" % (c, ord(c)))

  result = ""
  while not result.endswith(ST) and not result.endswith(chr(0x9c)):
    c = read(1)
    result += c
  if result.endswith(ST):
    return result[:-2]
  else:
    return result[:-1]

def read(n):
  """Try to read n bytes. Times out if it takes more than 1
  second to read any given byte."""
  s = ""
  f = sys.stdin.fileno()
  for i in xrange(n):
    r, w, e = select.select([ f ], [], [], escargs.args.timeout)
    if f not in r:
      raise esctypes.InternalError("Timeout waiting to read.")
    s += os.read(f, 1)
  return s


