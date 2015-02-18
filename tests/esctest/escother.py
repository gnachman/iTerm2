import esc
import escio

def DECDHL(x):
  """Double-width, double-height line.
     x = 3: top half
     x = 4: bottom half"""
  escio.Write(esc.ESC + "#" + str(x))

def DECALN():
  """Write test pattern."""
  escio.Write(esc.ESC + "#8")
