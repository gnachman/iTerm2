import bs
import cr
import ff
import lf
import vt

# No test for:
# Shift in (SI): ^O
# Shift out (SO): ^N
# Space (SP): 0x20
# Tab (TAB): 0x09 [tested in HTS]

tests = [ bs.BSTests,
          cr.CRTests,
          ff.FFTests,
          lf.LFTests,
          vt.VTTests ]
