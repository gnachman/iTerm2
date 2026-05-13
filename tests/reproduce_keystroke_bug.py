"""
1:1 reproduction of iTermKeystroke.keyInBindingDictionary: matching logic.

This script mirrors the exact serialization and matching algorithm from
iTermKeystroke.m (lines 286-372), demonstrating the bug and the fix.
"""

# --- Serialization (from iTermKeystroke.m) ---

def serialized(char, mods, keycode):
    """0x<char>-0x<mods>-0x<keycode> — the primary key format."""
    return f"0x{char:x}-0x{mods:x}-0x{keycode:x}"

def legacy_serialized(char, mods):
    """0x<char>-0x<mods> — without virtual keycode."""
    return f"0x{char:x}-0x{mods:x}"

def portable_serialized(mods, keycode):
    """*-0x<mods>-0x<keycode> — language-agnostic, keycode only."""
    return f"*-0x{mods:x}-0x{keycode:x}"


# --- Matching BEFORE fix (from iTermKeystroke.m lines 351-372) ---

def key_in_binding_dict_before(char, mods, keycode, binding_dict):
    """Simulates the original matching logic without portable fallback."""
    s = serialized(char, mods, keycode)
    ls = legacy_serialized(char, mods)

    # 1. Exact match
    if s in binding_dict:
        return s

    # 2. Legacy match (no keycode)
    if ls in binding_dict:
        return ls

    # 3. Slow fallback: iterate keys looking for legacy match
    for key in binding_dict:
        # Try to parse key as char-mods-keycode and compare legacy form
        parts = key.split("-")
        if len(parts) == 3:
            cand_char = int(parts[0], 16)
            cand_mods = int(parts[1], 16)
            if legacy_serialized(cand_char, cand_mods) == ls:
                return key
        elif len(parts) == 2:
            if key == ls:
                return key

    return None


# --- Matching AFTER fix (with portable fallback) ---

def key_in_binding_dict_after(char, mods, keycode, binding_dict):
    """Simulates the fixed matching logic WITH portable fallback."""
    s = serialized(char, mods, keycode)
    ls = legacy_serialized(char, mods)

    # 1. Exact match
    if s in binding_dict:
        return s

    # 2. Legacy match (no keycode)
    if ls in binding_dict:
        return ls

    # 3. Slow fallback: iterate keys looking for legacy match
    for key in binding_dict:
        parts = key.split("-")
        if len(parts) == 3:
            cand_char = int(parts[0], 16)
            cand_mods = int(parts[1], 16)
            if legacy_serialized(cand_char, cand_mods) == ls:
                return key
        elif len(parts) == 2:
            if key == ls:
                return key

    # 4. NEW: Language-agnostic fallback on virtual key code
    if True:  # hasVirtualKeyCode
        my_portable = portable_serialized(mods, keycode)
        for key in binding_dict:
            parts = key.split("-")
            if len(parts) == 3:
                cand_mods = int(parts[1], 16)
                cand_keycode = int(parts[2], 16)
                if portable_serialized(cand_mods, cand_keycode) == my_portable:
                    return key

    return None


# --- Test scenario ---

CMD = 0x100000          # NSEventModifierFlagCommand
GRAVE_KEY = 0x32        # kVK_ANSI_Grave (physical backtick key)
CHINESE_CHAR = 0xb7     # charactersIgnoringModifiers on Chinese layout (·)
US_CHAR = 0x60          # charactersIgnoringModifiers on US layout (`)

# The binding stored in GlobalKeyMap — created when keyboard reported 0xb7
binding_key = serialized(CHINESE_CHAR, CMD, GRAVE_KEY)
binding_dict = {binding_key: {"Action": 30, "Version": 2}}

print("=" * 60)
print("Binding stored in plist:", binding_key)
print("=" * 60)

# Simulate pressing Cmd+` when charactersIgnoringModifiers returns 0x60
# (e.g. after typing text changed input method state)
print(f"\nPressing Cmd+` — charactersIgnoringModifiers = 0x{US_CHAR:x}")
print(f"  serialized:           {serialized(US_CHAR, CMD, GRAVE_KEY)}")
print(f"  legacy_serialized:    {legacy_serialized(US_CHAR, CMD)}")
print(f"  portable_serialized:  {portable_serialized(CMD, GRAVE_KEY)}")

result_before = key_in_binding_dict_before(US_CHAR, CMD, GRAVE_KEY, binding_dict)
result_after = key_in_binding_dict_after(US_CHAR, CMD, GRAVE_KEY, binding_dict)

print(f"\n  BEFORE fix: {'MATCH' if result_before else 'NO MATCH — BUG REPRODUCED'}")
print(f"  AFTER  fix: {'MATCH' if result_after else 'NO MATCH'}")

# Also test: same character as stored (should always work)
print(f"\nPressing Cmd+` — charactersIgnoringModifiers = 0x{CHINESE_CHAR:x} (same as stored)")
result_same_before = key_in_binding_dict_before(CHINESE_CHAR, CMD, GRAVE_KEY, binding_dict)
result_same_after = key_in_binding_dict_after(CHINESE_CHAR, CMD, GRAVE_KEY, binding_dict)
print(f"  BEFORE fix: {'MATCH' if result_same_before else 'NO MATCH'}")
print(f"  AFTER  fix: {'MATCH' if result_same_after else 'NO MATCH'}")

# Test: different key code should NOT match
print(f"\nPressing Cmd+1 (keycode=0x12) — should NEVER match")
result_wrong_key = key_in_binding_dict_after(0x31, CMD, 0x12, binding_dict)
print(f"  AFTER  fix: {'MATCH (BUG!)' if result_wrong_key else 'NO MATCH (correct)'}")

# Summary
print("\n" + "=" * 60)
if result_before is None and result_after is not None:
    print("BUG CONFIRMED & FIX VERIFIED")
    print("Without fix: key press with different character not recognized.")
    print("With fix:    portableSerialized fallback matches on keycode + modifiers.")
elif result_before is not None:
    print("UNEXPECTED: bug not reproduced, check assumptions.")
else:
    print("UNEXPECTED: fix did not resolve the issue.")
print("=" * 60)
