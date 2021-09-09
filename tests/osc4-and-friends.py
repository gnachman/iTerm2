#!/usr/bin/env python3
import enum

esc = chr(27)
st = esc + "\\"

def osc(cmd, args=[""]):
  print(esc + "]" + ";".join(map(str, ([cmd] + args))), end=st)

def hex2(n):
  assert(n >= 0 and n < 256)
  return "{:02x}".format(n)

def rgb(r,g,b):
  return "#" + hex2(r) + hex2(g) + hex2(b)
  #return "rgb:" + "/".join([hex2(r), hex2(g), hex2(b)])

class DynamicColor(enum.Enum):
  # Values are (reset OSC, set OSC)
  DEFAULT_FG    = (110, 10)
  DEFAULT_BG    = (111, 11)
  CURSOR_TEXT   = (112, 12)
  SELECTION_BG  = (117, 17)
  SELECTION_FG  = (119, 19)

  def reset(self):
    print(f'Reset DynamicColor.{self.name}')
    osc(self.value[0])

  def set(self, color):
    print(f'Set DynamicColor.{self.name} = {color}')
    osc(self.value[1], [color])

  @classmethod
  def reset_all(self):
    print("Reset all dynamic colors")
    for c in self:
      print("  ", end="")
      c.reset()


class ANSIColor:
  def __init__(self, number):
    self.number = number

  def set(self, color):
    print(f'Set ANSI color {self.number} to {color}')
    osc(4, [self.number, color])

  def reset(self):
    print(f'Reset ANSI color {self.number}')
    osc(104, [self.value[1]])

  @classmethod
  def reset_all(self):
    print("Reset all ANSI colors")
    osc(104)

def sgr(code):
  print(esc + "[" + str(code) + "m", end="")

def print_colored(fg, bg):
  assert(fg >= 0 and bg >= 0)

  if fg == 0:
    sgr(39)
  elif fg < 8:
    sgr(30 + fg)
  elif fg < 16:
    sgr(90 + fg - 8)
  elif fg < 256:
    sgr("38:5:" + str(fg))
  else:
    assert(False)

  if bg == 0:
    sgr(49)
  elif bg < 8:
    sgr(40 + bg)
  elif bg < 16:
    sgr(100 + bg - 8)
  elif bg < 256:
    sgr("48:5:" + str(bg))
  else:
    assert(False)

  print("X", end="")

def print_flag():
  print("Default/Default")
  print("")

  for bg in range(256):
    print("{:02x}".format(bg), end=" ")
    for fg in range(256):
      print_colored(fg, bg)
    sgr("")
    print("")
  print("")

def wait():
  bs = chr(8)
  input("Hit return to continue" + bs)


DynamicColor.reset_all()
ANSIColor.reset_all()

print_flag()
wait()

DynamicColor.DEFAULT_BG.set(rgb(255,0,0))
DynamicColor.DEFAULT_FG.set(rgb(0,255,0))
DynamicColor.CURSOR_TEXT.set(rgb(0,0,255))
DynamicColor.SELECTION_BG.set(rgb(255,0,255))
DynamicColor.SELECTION_FG.set(rgb(255,255,255))

for x in range(255):
  ANSIColor(x).set(rgb(x,x,x))

print_flag()
wait()

DynamicColor.reset_all()
ANSIColor.reset_all()

print_flag()
wait()
