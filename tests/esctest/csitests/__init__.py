# The following CSI codes supported by xcode are not tested.
# Query ReGIS/Sixel attributes:  CSI ? Pi ; Pa ; P vS
# Initiate highlight mouse tracking: CSI Ps ; Ps ; Ps ; Ps ; Ps T
# Media Copy (MC): CSI Pm i
# Media Copy (MC, DEC-specific): CSI ? Pm i
# Character Attributes (SGR): CSI Pm m
# Disable modifiers: CSI > Ps n
# Set pointer mode: CSI > Ps p

# Notes for future tests:
# CSI 21 t
#   Test the title modes settable and resttable by CSI > Ps ; Ps t and CSI > Ps ; Ps T

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
import decrqm
import decscl
import decsed
import decsel
import decset
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
import su
import tbc
import vpa
import vpr

tests = [ cbt.CBTTests,
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
          decrqm.DECRQMTests,
          decscl.DECSCLTests,
          decsed.DECSEDTests,
          decsel.DECSELTests,
          decset.DECSETTests,
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
          su.SUTests,
          tbc.TBCTests,
          vpa.VPATests,
          vpr.VPRTests ]
