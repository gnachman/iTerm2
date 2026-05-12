"""Tests for iterm2.keyboard module — Modifier, Keycode, KeystrokePattern."""
import pytest
from iterm2.keyboard import Modifier, Keycode, KeystrokePattern


class TestModifierFromCocoa:
    """Tests for Modifier.from_cocoa() — bit-flag parsing."""

    def test_control(self):
        result = Modifier.from_cocoa(1 << 18)
        assert Modifier.CONTROL in result

    def test_option(self):
        result = Modifier.from_cocoa(1 << 19)
        assert Modifier.OPTION in result

    def test_command(self):
        result = Modifier.from_cocoa(1 << 20)
        assert Modifier.COMMAND in result

    def test_shift(self):
        result = Modifier.from_cocoa(1 << 17)
        assert Modifier.SHIFT in result

    def test_function(self):
        result = Modifier.from_cocoa(1 << 23)
        assert Modifier.FUNCTION in result

    def test_numpad(self):
        result = Modifier.from_cocoa(1 << 21)
        assert Modifier.NUMPAD in result

    def test_no_modifiers(self):
        result = Modifier.from_cocoa(0)
        assert result == []

    def test_multiple_modifiers(self):
        flags = (1 << 18) | (1 << 20)  # CONTROL + COMMAND
        result = Modifier.from_cocoa(flags)
        assert Modifier.CONTROL in result
        assert Modifier.COMMAND in result
        assert len(result) == 2

    def test_all_modifiers(self):
        flags = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 21) | (1 << 23)
        result = Modifier.from_cocoa(flags)
        assert len(result) == 6


class TestModifierToCocoa:
    """Tests for Modifier.to_cocoa() — enum → bit-flag conversion."""

    def test_control(self):
        assert Modifier.CONTROL.to_cocoa() == 1 << 18

    def test_option(self):
        assert Modifier.OPTION.to_cocoa() == 1 << 19

    def test_command(self):
        assert Modifier.COMMAND.to_cocoa() == 1 << 20

    def test_shift(self):
        assert Modifier.SHIFT.to_cocoa() == 1 << 17

    def test_function(self):
        assert Modifier.FUNCTION.to_cocoa() == 1 << 23

    def test_numpad(self):
        assert Modifier.NUMPAD.to_cocoa() == 1 << 21

    def test_roundtrip_control(self):
        """from_cocoa(to_cocoa()) should return the same modifier."""
        flag = Modifier.CONTROL.to_cocoa()
        result = Modifier.from_cocoa(flag)
        assert Modifier.CONTROL in result

    def test_roundtrip_shift(self):
        flag = Modifier.SHIFT.to_cocoa()
        result = Modifier.from_cocoa(flag)
        assert Modifier.SHIFT in result


class TestModifierEnum:
    """Tests for Modifier enum values."""

    def test_all_members_exist(self):
        expected = {"CONTROL", "OPTION", "COMMAND", "SHIFT", "FUNCTION", "NUMPAD"}
        actual = {m.name for m in Modifier}
        assert expected == actual

    def test_no_duplicate_values(self):
        values = [m.value for m in Modifier]
        assert len(values) == len(set(values))


class TestKeycodeEnum:
    """Tests for Keycode enum."""

    def test_return_key(self):
        assert Keycode.RETURN.value == 0x24

    def test_escape_key(self):
        assert Keycode.ESCAPE.value == 0x35

    def test_space_key(self):
        assert Keycode.SPACE.value == 0x31

    def test_ansi_a(self):
        assert Keycode.ANSI_A.value == 0x00

    def test_arrow_keys_exist(self):
        assert hasattr(Keycode, "LEFT_ARROW")
        assert hasattr(Keycode, "RIGHT_ARROW")
        assert hasattr(Keycode, "UP_ARROW")
        assert hasattr(Keycode, "DOWN_ARROW")

    def test_function_keys_exist(self):
        for i in range(1, 13):
            assert hasattr(Keycode, f"F{i}"), f"F{i} missing"

    def test_keypad_keys_exist(self):
        for i in range(10):
            assert hasattr(Keycode, f"ANSI_KEYPAD{i}")


class TestKeystrokePattern:
    """Tests for KeystrokePattern — no iTerm2 connection required."""

    def test_default_empty_lists(self):
        pattern = KeystrokePattern()
        assert pattern.required_modifiers == []
        assert pattern.forbidden_modifiers == []
        assert pattern.keycodes == []
        assert pattern.characters == []
        assert pattern.characters_ignoring_modifiers == []

    def test_set_required_modifiers(self):
        pattern = KeystrokePattern()
        pattern.required_modifiers = [Modifier.COMMAND, Modifier.SHIFT]
        assert Modifier.COMMAND in pattern.required_modifiers
        assert Modifier.SHIFT in pattern.required_modifiers

    def test_set_forbidden_modifiers(self):
        pattern = KeystrokePattern()
        pattern.forbidden_modifiers = [Modifier.CONTROL]
        assert Modifier.CONTROL in pattern.forbidden_modifiers

    def test_set_keycodes(self):
        pattern = KeystrokePattern()
        pattern.keycodes = [Keycode.RETURN, Keycode.ESCAPE]
        assert Keycode.RETURN in pattern.keycodes
        assert Keycode.ESCAPE in pattern.keycodes

    def test_set_characters(self):
        pattern = KeystrokePattern()
        pattern.characters = ["a", "b"]
        assert "a" in pattern.characters
        assert "b" in pattern.characters

    def test_set_characters_ignoring_modifiers(self):
        pattern = KeystrokePattern()
        pattern.characters_ignoring_modifiers = ["x"]
        assert "x" in pattern.characters_ignoring_modifiers

    def test_to_proto_empty_pattern(self):
        """to_proto() on empty pattern should return a valid proto."""
        pattern = KeystrokePattern()
        proto = pattern.to_proto()
        assert proto is not None
        assert list(proto.required_modifiers) == []
        assert list(proto.forbidden_modifiers) == []
        assert list(proto.keycodes) == []

    def test_to_proto_with_modifiers(self):
        pattern = KeystrokePattern()
        pattern.required_modifiers = [Modifier.COMMAND]
        pattern.keycodes = [Keycode.ANSI_A]
        proto = pattern.to_proto()
        assert len(list(proto.required_modifiers)) == 1
        assert len(list(proto.keycodes)) == 1

    def test_to_proto_with_characters(self):
        pattern = KeystrokePattern()
        pattern.characters = ["q"]
        proto = pattern.to_proto()
        assert "q" in list(proto.characters)
