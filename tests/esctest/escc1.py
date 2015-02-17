# TODO: Add support for 8-bit controls
from esc import ESC
import escio

def APC():
  """Application Program Command."""
  if escio.use8BitControls:
    escio.Write(chr(0x9f))
  else:
    escio.Write(ESC + "_")

def DCS():
  """Device control string. Prefixes various commands."""
  if escio.use8BitControls:
    escio.Write(chr(0x90))
  else:
    escio.Write(ESC + "P")

def DECID():
  """Obsolete form of DA."""
  if escio.use8BitControls:
    escio.Write(chr(0x9a))
  else:
    escio.Write(ESC + "Z")

def DECRC():
  """Restore the cursor and resets various attributes."""
  escio.Write(ESC + "8")

def DECSC():
  """Saves the cursor."""
  escio.Write(ESC + "7")

def EPA():
  """End protected area."""
  if escio.use8BitControls:
    escio.Write(chr(0x97))
  else:
    escio.Write(ESC + "W")

def HTS():
  """Set a horizontal tab stop."""
  if escio.use8BitControls:
    escio.Write(chr(0x88))
  else:
    escio.Write(ESC + "H")

def IND():
  """Move cursor down one line."""
  if escio.use8BitControls:
    escio.Write(chr(0x84))
  else:
    escio.Write(ESC + "D")

def NEL():
  """Index plus carriage return."""
  if escio.use8BitControls:
    escio.Write(chr(0x85))
  else:
    escio.Write(ESC + "E")

def PM():
  """Privacy message."""
  if escio.use8BitControls:
    escio.Write(chr(0x9e))
  else:
    escio.Write(ESC + "^")

def RI():
  """Move cursor up one line."""
  if escio.use8BitControls:
    escio.Write(chr(0x8d))
  else:
    escio.Write(ESC + "M")

def SPA():
  """Start protected area."""
  if escio.use8BitControls:
    escio.Write(chr(0x96))
  else:
    escio.Write(ESC + "V")

def SOS():
  """Start of string."""
  if escio.use8BitControls:
    escio.Write(chr(0x98))
  else:
    escio.Write(ESC + "X")
