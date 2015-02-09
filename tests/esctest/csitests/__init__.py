# The following CSI codes supported by xcode are not tested.
# Query ReGIS/Sixel attributes:  CSI ? Pi ; Pa ; P vS
# Initiate highlight mouse tracking: CSI Ps ; Ps ; Ps ; Ps ; Ps T
# Media Copy (MC): CSI Pm i
# Media Copy (MC, DEC-specific): CSI ? Pm i
# Character Attributes (SGR): CSI Pm m
# Disable modifiers: CSI > Ps n
# Set pointer mode: CSI > Ps p
# Load LEDs (DECLL): CSI Ps q
# Set cursor style (DECSCUSR): CIS Ps SP q
# Select character protection attribute (DECSCA): CSI Ps " q   [This is already tested by DECSED and DECSEL]
# Window manipulation: CSI Ps; Ps; Ps t
# Reverse Attributes in Rectangular Area (DECRARA): CSI Pt ; Pl ; Pb ; Pr ; Ps $ t
# Set warning bell volume (DECSWBV): CSI Ps SP t

# Notes for future tests:
# CSI 21 t
#   Test the title modes settable and resttable by CSI > Ps ; Ps t and CSI > Ps ; Ps T

import ansirc
import cbt
import cha
import cht
import cnl
import cpl
import cub
import cud
import cup
import cuf
import cuu
import da
import da2
import dch
import decdsr
import decrc
import decrqm
import decscl
import decsed
import decsel
import decset
import decset_tite_inhibit
import decstbm
import decstr
import dl
import ech
import ed
import el
import hpa
import hpr
import hvp
import ich
import il
import rep
import rm
import sd
import sm
import sm_title
import su
import tbc
import vpa
import vpr
import xterm_save
import xterm_winops

tests = [ ansirc.ANSIRCTests,
          cbt.CBTTests,
          cha.CHATests,
          cht.CHTTests,
          cnl.CNLTests,
          cpl.CPLTests,
          cub.CUBTests,
          cud.CUDTests,
          cuf.CUFTests,
          cup.CUPTests,
          cuu.CUUTests,
          da.DATests,
          da2.DA2Tests,
          dch.DCHTests,
          decdsr.DECDSRTests,
          decrc.DECRCTests,
          decrqm.DECRQMTests,
          decscl.DECSCLTests,
          decsed.DECSEDTests,
          decsel.DECSELTests,
          decset.DECSETTests,
          decset_tite_inhibit.DECSETTiteInhibitTests,
          decstbm.DECSTBMTests,
          decstr.DECSTRTests,
          ech.ECHTests,
          ed.EDTests,
          el.ELTests,
          dl.DLTests,
          hpa.HPATests,
          hpr.HPRTests,
          hvp.HVPTests,
          ich.ICHTests,
          il.ILTests,
          rep.REPTests,
          rm.RMTests,
          sd.SDTests,
          sm.SMTests,
          sm_title.SMTitleTests,
          su.SUTests,
          tbc.TBCTests,
          vpa.VPATests,
          vpr.VPRTests,
          xterm_save.XtermSaveTests,
          xterm_winops.XtermWinopsTests ]
