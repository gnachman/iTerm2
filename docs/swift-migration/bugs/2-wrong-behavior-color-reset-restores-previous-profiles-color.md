# Resetting a color after a profile change restores the old profile's color

**Where:** `sources/PTYSession/PTYSession.m`: the dictionary `_preEscapeSequenceColors`, filled by `-setEscapeSequenceProfileValues:` (near line 19321) and read by `-screenResetColorWithColorMapKey:profileKey:dark:` (near line 19205); `-storeProfile:` and `-setProfile:` (near line 8000) replace the profile without clearing it.

**What happens:** when a program sets a color with an escape sequence (OSC 10, 11 and the like), the session records the profile's color as a baseline so that a reset (OSC 110, 111 and the like) can put it back. If the session's profile changes in between, the reset writes the old profile's color instead of the new profile's. The same stale baseline is written when XTPOPCOLORS pops a saved slot that lacks that color. It takes a color set by a program, then a profile change, then a reset: uncommon, but nothing prevents it.

**Why:** entries leave `_preEscapeSequenceColors` only when the same key is written through `-setSessionSpecificProfileValues:` (near line 9404) or when the reset consumes them. A profile change replaces `_profile` wholesale and leaves the baselines in place.

**How to see it:** a session with profile P1 whose foreground is F1. Send `OSC 10 ; <some color> ST`. Change the session to profile P2 (Edit Session, or anything that calls `-setProfile:`). Send `OSC 110 ST`: the foreground becomes F1, not P2's foreground. Seen by reading the code; not run.

**Suggested fix:** clear `_preEscapeSequenceColors` when the session changes to a different profile (a different GUID), keeping the existing behavior for edits of the same profile.

**Found:** 2026-11-24, by reading, while reviewing a change to saved color slots.

**Checked against the tree:** 2026-11-27. `-storeProfile:` and `-setProfile:` still never touch `_preEscapeSequenceColors`.
