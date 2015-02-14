import escargs

ESC = "%c" % 27
ST = ESC + "\\"
NUL = "%c" % 0
TAB = "%c" % 9
CR = "%c" % 13
LF = "%c" % 10
BS = "%c" % 8

# VT x00 level. vtLevel may be 1, 2, 3, 4, or 5.
vtLevel = 1

def blank():
    if escargs.args.expected_terminal == "xterm":
      return ' '
    else:
      return NUL

