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
# Set margin-bell volume (DECSMBV): CSI Ps SP u
# Enable Filter Rectangle (DECEFR): CSI Pt ; Pl ; Pb ; Pr ' w
# Request Terminal Parameters (DECREQTPARM): CSI Ps x
# Select Attribute Change Extent (DECSACE): CSI Ps * x
# Request Checksum of Rectangular Area (DECRQCRA): CSI Pi ; Pg ; Pt ; Pl ; Pb ; Pr * y
# Select Locator Events (DECSLE): CSI Pm ' {
# Request Locator Position (DECRQLP): CSI PS ' |
# ESC SP L  Set ANSI conformance level 1 (dpANS X3.134.1).
# ESC SP M  Set ANSI conformance level 2 (dpANS X3.134.1).
# ESC SP N  Set ANSI conformance level 3 (dpANS X3.134.1).
#   In xterm, all these do is fiddle with character sets, which are not testable.
# ESC # 3   DEC double-height line, top half (DECDHL).
# ESC # 4   DEC double-height line, bottom half (DECDHL).
# ESC # 5   DEC single-width line (DECSWL).
# ESC # 6   DEC double-width line (DECDWL).
#  Double-width affects display only and is generally not introspectable. Wrap
#  doesn't work so there's no way to tell where the cursor is visually.
# ESC % @   Select default character set.  That is ISO 8859-1 (ISO 2022).
# ESC % G   Select UTF-8 character set (ISO 2022).
# ESC ( C   Designate G0 Character Set (ISO 2022, VT100).
# ESC ) C   Designate G1 Character Set (ISO 2022, VT100).
# ESC * C   Designate G2 Character Set (ISO 2022, VT220).
# ESC + C   Designate G3 Character Set (ISO 2022, VT220).
# ESC - C   Designate G1 Character Set (VT300).
# ESC . C   Designate G2 Character Set (VT300).
# ESC / C   Designate G3 Character Set (VT300).
#  Character set stuff is not introspectable.
# Shift in (SI): ^O
# Shift out (SO): ^N
# Space (SP): 0x20
# Tab (TAB): 0x09 [tested in HTS]
# ESC =     Application Keypad (DECKPAM).
# ESC >     Normal Keypad (DECKPNM).
# ESC F     Cursor to lower left corner of screen.  This is enabled by the
#           hpLowerleftBugCompat resource. (Not worth testing as it's off by
#           default, and silly regardless)
# ESC l     Memory Lock (per HP terminals).  Locks memory above the cursor.
# ESC m     Memory Unlock (per HP terminals).
# ESC n     Invoke the G2 Character Set as GL (LS2).
# ESC o     Invoke the G3 Character Set as GL (LS3).
# ESC |     Invoke the G3 Character Set as GR (LS3R).
# ESC }     Invoke the G2 Character Set as GR (LS2R).
# ESC ~     Invoke the G1 Character Set as GR (LS1R).
# DCS + p Pt ST    Set Termcap/Terminfo Data
# DCS + q Pt ST    Request Termcap/Terminfo String
# The following OSC commands are tested in xterm_winops and don't have their own test:
#           Ps = 0  -> Change Icon Name and Window Title to Pt.
#           Ps = 1  -> Change Icon Name to Pt.
#           Ps = 2  -> Change Window Title to Pt.
# This test is too ill-defined and X-specific, and is not tested:
#           Ps = 3  -> Set X property on top-level window.  Pt should be
#         in the form "prop=value", or just "prop" to delete the prop-
#         erty
# No introspection for whether special color are enabled/disabled:
#           Ps = 6 ; c; f -> Enable/disable Special Color Number c.  The
#         second parameter tells xterm to enable the corresponding color
#         mode if nonzero, disable it if zero.
# Off by default, obvious security issues:
#           Ps = 4 6  -> Change Log File to Pt.  (This is normally dis-
#         abled by a compile-time option).
# No introspection for fonts:
#           Ps = 5 0  -> Set Font to Pt.
# No-op:
#           Ps = 5 1  -> reserved for Emacs shell.


import ansirc
import apc
import bs
import cbt
import cha
import change_color
import change_special_color
import change_dynamic_color
import cht
import cnl
import cpl
import cr
import cub
import cud
import cuf
import cup
import cuu
import da
import da2
import dch
import dcs
import decaln
import decbi
import deccra
import decdc
import decdsr
import decera
import decfra
import decfi
import decic
import decid
import decrc
import decrqm
import decrqss
import decscl
import decsed
import decsel
import decsera
import decset
import decset_tite_inhibit
import decstbm
import decstr
import dl
import ech
import ed
import el
import ff
import hpa
import hpr
import hts
import hvp
import ich
import il
import ind
import lf
import manipulate_selection_data
import nel
import pm
import rep
import reset_color
import reset_special_color
import ri
import ris
import rm
import s8c1t
import sd
import sm
import sm_title
import sos
import su
import tbc
import vpa
import vpr
import vt
import xterm_save
import xterm_winops

tests = [
    ansirc.ANSIRCTests,
    apc.APCTests,
    bs.BSTests,
    cbt.CBTTests,
    cha.CHATests,
    change_color.ChangeColorTests,
    change_special_color.ChangeSpecialColorTests,
    change_dynamic_color.ChangeDynamicColorTests,
    cht.CHTTests,
    cnl.CNLTests,
    cpl.CPLTests,
    cr.CRTests,
    cub.CUBTests,
    cud.CUDTests,
    cuf.CUFTests,
    cup.CUPTests,
    cuu.CUUTests,
    da.DATests,
    da2.DA2Tests,
    dch.DCHTests,
    dcs.DCSTests,
    decaln.DECALNTests,
    decbi.DECBITests,
    deccra.DECCRATests,
    decdc.DECDCTests,
    decdsr.DECDSRTests,
    decera.DECERATests,
    decfra.DECFRATests,
    decfi.DECFITests,
    decic.DECICTests,
    decid.DECIDTests,
    decrc.DECRCTests,
    decrqm.DECRQMTests,
    decrqss.DECRQSSTests,
    decscl.DECSCLTests,
    decsed.DECSEDTests,
    decsel.DECSELTests,
    decsera.DECSERATests,
    decset.DECSETTests,
    decset_tite_inhibit.DECSETTiteInhibitTests,
    decstbm.DECSTBMTests,
    decstr.DECSTRTests,
    dl.DLTests,
    ech.ECHTests,
    ed.EDTests,
    el.ELTests,
    ff.FFTests,
    hpa.HPATests,
    hpr.HPRTests,
    hts.HTSTests,
    hvp.HVPTests,
    ich.ICHTests,
    il.ILTests,
    ind.INDTests,
    lf.LFTests,
    manipulate_selection_data.ManipulateSelectionDataTests,
    nel.NELTests,
    pm.PMTests,
    rep.REPTests,
    reset_color.ResetColorTests,
    reset_special_color.ResetSpecialColorTests,
    ri.RITests,
    ris.RISTests,
    rm.RMTests,
    s8c1t.S8C1TTests,
    sd.SDTests,
    sm.SMTests,
    sm_title.SMTitleTests,
    sos.SOSTests,
    su.SUTests,
    tbc.TBCTests,
    vpa.VPATests,
    vpr.VPRTests,
    vt.VTTests,
    xterm_save.XtermSaveTests,
    xterm_winops.XtermWinopsTests,
  ]
