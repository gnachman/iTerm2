import esc
import escio

def DECRQSS(Pt):
  escio.WriteDCS("$q", Pt)
