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
