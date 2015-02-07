import escio

def ChangeWindowTitle(title, bel=False, suppressSideChannel=False):
  """Change the window title."""
  escio.WriteOSC(params=[ "2", title ], bel=bel, requestsReport=suppressSideChannel)

def ChangeIconTitle(title, bel=False, suppressSideChannel=False):
  """Change the icon (tab) title."""
  escio.WriteOSC(params=[ "1", title ], bel=bel, requestsReport=suppressSideChannel)
