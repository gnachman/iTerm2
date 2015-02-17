import escargs

NUL = chr(0)
BS = chr(8)
TAB = chr(9)
LF = chr(10)
VT = chr(11)
CR = chr(13)
FF = chr(12)
ESC = chr(27)

S7C1T = ESC + " F"
S8C1T = ESC + " G"

ST = ESC + "\\"

# VT x00 level. vtLevel may be 1, 2, 3, 4, or 5.
vtLevel = 1

def blank():
    if escargs.args.expected_terminal == "xterm":
      return ' '
    else:
      return NUL

