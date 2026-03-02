"""Tests for iterm2.triggers module."""
from iterm2.triggers import Trigger, decode_trigger


class TestTriggerBaseName:
    """Tests for the Trigger base class _name method."""

    def test_trigger_base_has_name(self):
        """Test that Trigger base class defines _name."""
        assert hasattr(Trigger, '_name')

    def test_trigger_base_name_returns_trigger(self):
        """Test that Trigger._name() returns 'Trigger'."""
        assert Trigger._name() == "Trigger"

    def test_trigger_instance_encode_does_not_crash(self):
        """Test that encode works on a bare Trigger instance.

        decode_trigger returns a bare Trigger for unrecognized trigger
        types, and calling .encode on it should not raise AttributeError.
        """
        trigger = Trigger(regex="test", param="", instant=False, enabled=True)
        encoded = trigger.encode
        assert encoded["action"] == "Trigger"
        assert encoded["regex"] == "test"
        assert encoded["parameter"] == ""
        assert encoded["partial"] is False
        assert encoded["disabled"] is False

    def test_unrecognized_trigger_roundtrip(self):
        """Test that an unrecognized trigger type can round-trip through
        decode_trigger and encode without crashing."""
        encoded = {
            "action": "SomeFutureTrigger",
            "regex": "pattern",
            "parameter": "param_value",
            "partial": True,
            "disabled": False,
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, Trigger)

        result = trigger.encode
        assert result["regex"] == "pattern"
        assert result["partial"] is True
        assert result["disabled"] is False
from iterm2.triggers import (
    Trigger,
    AlertTrigger,
    BellTrigger,
    HighlightTrigger,
    decode_trigger,
)


class TestTriggerDeserialize:
    """Tests for the Trigger base class deserialize method."""

    def test_returns_trigger_instance(self):
        """Test that Trigger.deserialize returns a Trigger instance."""
        trigger = Trigger.deserialize("regex", "param", True, False)
        assert isinstance(trigger, Trigger)

    def test_fields_are_set(self):
        """Test that deserialize sets all fields correctly."""
        trigger = Trigger.deserialize("pattern", "value", False, True)
        assert trigger.regex == "pattern"
        assert trigger.param == "value"
        assert trigger.instant is False
        assert trigger.enabled is True


class TestDecodeTrigger:
    """Tests for decode_trigger using the classes dict and deserialize."""

    def test_decode_known_trigger(self):
        """Test decoding a known trigger type calls its deserialize."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "error",
            "parameter": "Alert!",
            "partial": False,
            "disabled": False,
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, AlertTrigger)
        assert trigger.regex == "error"
        assert trigger.instant is False
        assert trigger.enabled is True

    def test_decode_unknown_trigger_falls_back_to_base(self):
        """Test that an unknown action falls back to Trigger.deserialize."""
        encoded = {
            "action": "SomeFutureTrigger",
            "regex": "test",
            "parameter": "param_value",
        }
        trigger = decode_trigger(encoded)
        assert type(trigger) is Trigger
        assert trigger.regex == "test"
        assert trigger.param == "param_value"

    def test_decode_defaults(self):
        """Test that missing optional fields get default values."""
        encoded = {
            "action": "BellTrigger",
            "regex": "bell",
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, BellTrigger)
        assert trigger.instant is False
        assert trigger.enabled is True

    def test_decode_disabled(self):
        """Test that disabled flag is correctly inverted."""
        encoded = {
            "action": "BellTrigger",
            "regex": "bell",
            "disabled": True,
        }
        trigger = decode_trigger(encoded)
        assert trigger.enabled is False
