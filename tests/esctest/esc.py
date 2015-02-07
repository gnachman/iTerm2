import escio

ESC = "%c" % 27
ST = ESC + "\\"
NUL = "%c" % 0
TAB = "%c" % 9
CR = "%c" % 13
LF = "%c" % 10
BS = "%c" % 8

# VT x00 level. vtLevel may be 1, 2, 3, 4, or 5.
vtLevel = 1

def DECRC():
  """Restore the cursor and resets various attributes."""
  escio.Write(ESC + "8")

def DECSC():
  """Saves the cursor."""
  escio.Write(ESC + "7")
