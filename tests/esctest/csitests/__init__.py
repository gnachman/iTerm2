# The following CSI codes supported by xcode are not tested.
# Query ReGIS/Sixel attributes:  CSI ? Pi ; Pa ; P vS
# Initiate highlight mouse tracking: CSI Ps ; Ps ; Ps ; Ps ; Ps T

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
import decsed
import decsel
import decset
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
          decsed.DECSEDTests,
          decsel.DECSELTests,
          decset.DECSETTests,
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
          sd.SDTests,
          sm.SMTests,
          su.SUTests,
          tbc.TBCTests,
          vpa.VPATests,
          vpr.VPRTests ]
