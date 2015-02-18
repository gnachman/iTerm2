import decaln
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


tests = [ decaln.DECALNTests,
          s8c1t.S8C1TTests ]
