# TODO: Add support for 8-bit controls
from esc import ESC
import escio

def DCS():
  """Device control string. Prefixes various commands."""
  escio.Write(ESC + "P")

def DECRC():
  """Restore the cursor and resets various attributes."""
  escio.Write(ESC + "8")

def DECSC():
  """Saves the cursor."""
  escio.Write(ESC + "7")

def EPA():
  """End protected area."""
  escio.Write(ESC + "W")

def HTS():
  """Set a horizontal tab stop."""
  escio.Write(ESC + "H")

def IND():
  """Move cursor down one line."""
  escio.Write(ESC + "D")

def NEL():
  """Index plus carriage return."""
  escio.Write(ESC + "E")

def RI():
  """Move cursor up one line."""
  escio.Write(ESC + "M")

def SPA():
  """Start protected area."""
  escio.Write(ESC + "V")

def SOS():
  """Start of string."""
  escio.Write(ESC + "X")
