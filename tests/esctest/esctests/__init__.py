import decaln
import decbi
import s8c1t

# No tests for:
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





tests = [ decaln.DECALNTests,
          decbi.DECBITests,
          s8c1t.S8C1TTests ]
