import escio

args = None

# DECSET/DECRESET
Allow80To132 = 40  # Allow 80->132 Mode
ALTBUF = 47  # Switch to alt buf
DECAAM = 100
DECANM = 2
DECARM = 8
DECARSM = 98
DECAWM = 7  # Autowrap
DECBKM = 67
DECCANSM = 101
DECCKM = 1
DECCOLM = 3  # 132-column mode
DECCRTSM = 97
DECESKM = 104
DECHCCM = 60
DECHDPXM = 103
DECHEBM = 35
DECHEM = 36
DECKBUM = 68
DECKPM = 81
DECLRMM = 69  # Left/right margin enabled
DECMCM = 99
DECNAKB = 57
DECNCSM = 95
DECNCSM = 95  # Clear screen on enabling column mode
DECNKM = 66
DECNRCM = 42
DECNULM = 102
DECOM = 6  # Origin mode
DECOSCNM = 106
DECPCCM = 64
DECPEX = 19
DECPFF = 18
DECRLCM = 96
DECRLM = 34  # Right-to-left mode
DECSCLM = 4
DECSCNM = 5
DECTCEM = 25
DECVCCM = 61
DECVSSM = 69
DECXRLM = 73
MoreFix = 41  # Work around bug in more(1) (see details in test_DECSET_MoreFix)
OPT_ALTBUF = 1047  # Switch to alt buf. DECRESET first clears the alt buf.
OPT_ALTBUF_CURSOR = 1049  # Like 1047 but saves/restores main screen's cursor position.
ReverseWraparound = 45  # Reverse-wraparound mode (only works on conjunction with DECAWM)
SaveRestoreCursor = 1048  # Save cursor as in DECSC.

# DECDSR
DECCKSR = 63
DECMSR = 62
DECXCPR = 6
DSRCPR = 6
DSRDECLocatorStatus = 55
DSRIntegrityReport = 75
DSRKeyboard = 26
DSRLocatorId = 56
DSRMultipleSessionStatus = 85
DSRPrinterPort = 15
DSRUDKLocked = 25
DSRXtermLocatorStatus = 55

# SM/RM
EBM = 19
FEAM = 13
FETM = 14
GATM = 1
HEM = 10
IRM = 4
KAM = 2
LNM = 20
MATM = 15
PUM = 11
SATM = 17
SRM = 12
SRTM = 5
TSM = 18
TTM = 16
VEM = 7

def CSI_CBT(Pn=None):
  """Move cursor back by Pn tab stops or to left margin. Default is 1."""
  if Pn is None:
    params = []
  else:
    params = [ Pn ]
  escio.WriteCSI(params=params, final="Z")

def CSI_CHA(Pn=None):
  """Move cursor to Pn column, or first column by default."""
  if Pn is None:
    params = []
  else:
    params = [ Pn ]
  escio.WriteCSI(params=params, final="G")

def CSI_CHT(Ps=None):
  """Move cursor forward by Ps tab stops (default is 1)."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="I")

def CSI_CNL(Ps=None):
  """Cursor down Ps times and to the left margin."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="E")

def CSI_CPL(Ps=None):
  """Cursor up Ps times and to the left margin."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="F")

def CSI_CUB(Ps=None):
  """Cursor left Ps times."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="D")

def CSI_CUD(Ps=None):
  """Cursor down Ps times."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="B")

def CSI_CUF(Ps=None):
  """Cursor right Ps times."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="C")

def CSI_CUP(point=None, row=None, col=None):
  """ Move cursor to |point| """
  if point is None and row is None and col is None:
    escio.WriteCSI(params=[ ], final="H")
  elif point is None:
    if row is None:
      row = ""
    if col is None:
      escio.WriteCSI(params=[ row ], final="H")
    else:
      escio.WriteCSI(params=[ row, col ], final="H")
  else:
    escio.WriteCSI(params=[ point.y(), point.x() ], final="H")

def CSI_CUU(Ps=None):
  """Cursor up Ps times."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="A")

def CSI_DA(Ps=None):
  """Request primary device attributes."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="c")

def CSI_DA2(Ps=None):
  """Request secondary device attributes."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, prefix='>', final="c")

def CSI_DCH(Ps=None):
  """Delete Ps characters at cursor."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="P")

def CSI_DECDSR(Ps, Pid=None, suppressSideChannel=False):
  """Send device status request. Does not read response."""
  if Ps is None:
    params = []
  else:
    if Pid is None:
      params = [ Ps ]
    else:
      params = [ Ps, Pid ]
  escio.WriteCSI(params=params, prefix='?', requestsReport=suppressSideChannel, final='n')

def CSI_DECRQCRA(Pid, Pp=None, rect=None):
  """Compute the checksum (16-bit sum of ordinals) in a rectangle."""
  # xterm versions 314 and earlier incorrectly expect the Pid in the second
  # argument and ignore Pp.
  # For the time being, iTerm2 is compatible with the bug.
  if not args.disable_xterm_checksum_bug:
    Pid, Pp = Pp, Pid

  params = [ Pid ]

  if Pp is not None:
    params += [ Pp ]
  elif Pp is None and rect is not None:
    params += [ "" ]

  if rect is not None:
    params.extend(rect.params())

  escio.WriteCSI(params=params, intermediate='*', final='y', requestsReport=True)

def CSI_DECRQM(mode, DEC):
  """Requests if a mode is set or not."""
  if DEC:
    escio.WriteCSI(params=[ mode ], intermediate='$', prefix='?', final='p')
  else:
    escio.WriteCSI(params=[ mode ], intermediate='$', final='p')

def CSI_DECRESET(Pm):
  """Reset the parameter |Pm|."""
  escio.WriteCSI(params=[ Pm ], prefix='?', final='l')

def CSI_DECSASD(Ps=None):
  """Direct output to status line if Ps is 1, to main display if 0."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, intermediate='$', final="}")

def CSI_DECSCA(Ps=None):
  """Turn on character protection if Ps is 1, off if 0."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, intermediate='"', final="q")

def CSI_DECSCL(level, sevenBit=None):
  """Level should be one of 61, 62, 63, or 64. sevenBit can be 0 or 1, or not
  specified."""
  if sevenBit is None:
    params = [ level ]
  else:
    params = [ level, sevenBit ]
  escio.WriteCSI(params=params, intermediate='"', final="p")

def CSI_DECSED(Ps=None):
  """Like ED but respects character protection."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, prefix='?', final="J")

def CSI_DECSEL(Ps=None):
  """Like EL but respects character protection."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, prefix='?', final="K")

def CSI_DECSET(Pm):
  """Set the parameter |Pm|."""
  escio.WriteCSI(params=[ Pm ], prefix='?', final='h')

def CSI_DECSLRM(Pl, Pr):
  """Set the left and right margins."""
  escio.WriteCSI(params=[ Pl, Pr ], final='s')

def CSI_DECSTBM(top=None, bottom=None):
  """Set Scrolling Region [top;bottom] (default = full size of window)."""
  params = []
  if top is not None:
    params.append(top)
  if bottom is not None:
    params.append(bottom)

  escio.WriteCSI(params=params, final="r")

def CSI_DECSTR():
  """Soft reset."""
  escio.WriteCSI(prefix='!', final='p')

def CSI_DL(Pn=None):
  """Delete |Pn| lines at the cursor. Default value is 1."""
  if Pn is None:
    params = []
  else:
    params = [ Pn ]
  escio.WriteCSI(params=params, final="M")

def CSI_DSR(Ps, suppressSideChannel=False):
  """Send device status request. Does not read response."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, requestsReport=suppressSideChannel, final='n')

def CSI_ECH(Pn=None):
  """Erase |Pn| characters starting at the cursor. Default value is 1."""
  if Pn is None:
    params = []
  else:
    params = [ Pn ]
  escio.WriteCSI(params=params, final="X")

def CSI_ED(Ps=None):
  """Erase characters, clearing display attributes. Works in or out of scrolling regions.

  Ps = 0 (default): From the cursor through the end of the display
  Ps = 1: From the beginning of the display through the cursor
  Ps = 2: The complete display
  """
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="J")

def CSI_EL(Ps=None):
  """Erase in the active line.

  Ps = 0 (default): Erase to right of cursor
  Ps = 1: Erase to left of cursor
  Ps = 2: Erase whole line
  """
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="K")

def CSI_HPA(Pn=None):
  """Position the cursor at the Pn'th column. Default value is 1."""
  if Pn is None:
    params = []
  else:
    params = [ Pn ]
  escio.WriteCSI(params=params, final="`")

def CSI_HPR(Pn=None):
  """Position the cursor at the Pn'th column relative to its current position.
  Default value is 1."""
  if Pn is None:
    params = []
  else:
    params = [ Pn ]
  escio.WriteCSI(params=params, final="a")

def CSI_HVP(point=None, row=None, col=None):
  """ Move cursor to |point| """
  if point is None and row is None and col is None:
    escio.WriteCSI(params=[ ], final="H")
  elif point is None:
    if row is None:
      row = ""
    if col is None:
      escio.WriteCSI(params=[ row ], final="H")
    else:
      escio.WriteCSI(params=[ row, col ], final="H")
  else:
    escio.WriteCSI(params=[ point.y(), point.x() ], final="f")

def CSI_ICH(Pn=None):
  """ Insert |Pn| blanks at cursor. Cursor does not move. """
  if Pn is None:
    params = []
  else:
    params = [ Pn ]
  escio.WriteCSI(params=params, final="@")

def CSI_IL(Pn=None):
  """Insert |Pn| blank lines after the cursor. Default value is 1."""
  if Pn is None:
    params = []
  else:
    params = [ Pn ]
  escio.WriteCSI(params=params, final="L")

def CSI_REP(Ps=None):
  """Repeat the preceding character |Ps| times. Undocumented default is 1."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="b")

def CSI_RM(Pm=None):
  """Reset mode."""
  if Pm is None:
    params = []
  else:
    params = [ Pm ]
  escio.WriteCSI(params=params, final="l")

def CSI_SD(Ps=None):
  """Scroll down by |Ps| lines. Default value is 1."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="T")

def CSI_SM(Pm=None):
  """Set mode."""
  if Pm is None:
    params = []
  else:
    params = [ Pm ]
  escio.WriteCSI(params=params, final="h")

def CSI_SU(Ps=None):
  """Scroll up by |Ps| lines. Default value is 1."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="S")

def CSI_TBC(Ps=None):
  """Clear tab stop. Default arg is 0 (clear tabstop at cursor)."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="g")

def CSI_VPA(Ps=None):
  """Move to line |Ps|. Default value is 1."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="d")

def CSI_VPR(Ps=None):
  """Move down by |Ps| rows. Default value is 1."""
  if Ps is None:
    params = []
  else:
    params = [ Ps ]
  escio.WriteCSI(params=params, final="e")



