"""Tests for iterm2.triggers module."""
from iterm2.triggers import (
    Trigger,
    AlertTrigger,
    BellTrigger,
    HighlightTrigger,
    decode_trigger,
    MatchType,
    EventTrigger,
    ExitCodeFilter,
    PromptDetectedEventTrigger,
    CommandFinishedEventTrigger,
    DirectoryChangedEventTrigger,
    HostChangedEventTrigger,
    UserChangedEventTrigger,
    IdleEventTrigger,
    ActivityAfterIdleEventTrigger,
    SessionEndedEventTrigger,
    BellReceivedEventTrigger,
    LongRunningCommandEventTrigger,
    CustomEscapeSequenceEventTrigger,
    NotificationPostedEventTrigger,
)


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


# Event-based trigger tests


class TestMatchType:
    """Tests for the MatchType enum."""

    def test_regex_match_types(self):
        """Test that regex match types have correct values."""
        assert MatchType.REGEX.value == 0
        assert MatchType.URL_REGEX.value == 1
        assert MatchType.PAGE_CONTENT_REGEX.value == 2

    def test_event_match_types(self):
        """Test that event match types have correct values >= 100."""
        assert MatchType.EVENT_PROMPT_DETECTED.value == 100
        assert MatchType.EVENT_COMMAND_FINISHED.value == 101
        assert MatchType.EVENT_DIRECTORY_CHANGED.value == 102
        assert MatchType.EVENT_HOST_CHANGED.value == 103
        assert MatchType.EVENT_USER_CHANGED.value == 104
        assert MatchType.EVENT_IDLE.value == 105
        assert MatchType.EVENT_ACTIVITY_AFTER_IDLE.value == 106
        assert MatchType.EVENT_SESSION_ENDED.value == 107
        assert MatchType.EVENT_BELL_RECEIVED.value == 108
        assert MatchType.EVENT_LONG_RUNNING_COMMAND.value == 109
        assert MatchType.EVENT_CUSTOM_ESCAPE_SEQUENCE.value == 110

    def test_is_event(self):
        """Test the is_event helper method."""
        assert not MatchType.is_event(MatchType.REGEX)
        assert not MatchType.is_event(MatchType.URL_REGEX)
        assert MatchType.is_event(MatchType.EVENT_PROMPT_DETECTED)
        assert MatchType.is_event(MatchType.EVENT_COMMAND_FINISHED)


class TestEventTrigger:
    """Tests for the EventTrigger base class."""

    def test_create_event_trigger(self):
        """Test creating an EventTrigger instance."""
        trigger = EventTrigger(
            match_type=MatchType.EVENT_PROMPT_DETECTED,
            action_name="AlertTrigger",
            param="Hello",
            enabled=True,
            event_params={"key": "value"}
        )
        assert trigger.match_type == MatchType.EVENT_PROMPT_DETECTED
        assert trigger.action_name == "AlertTrigger"
        assert trigger.param == "Hello"
        assert trigger.enabled is True
        assert trigger.event_params == {"key": "value"}

    def test_encode_event_trigger(self):
        """Test encoding an EventTrigger."""
        trigger = EventTrigger(
            match_type=MatchType.EVENT_SESSION_ENDED,
            action_name="AlertTrigger",
            param="Session ended!",
            enabled=True
        )
        encoded = trigger.encode
        assert encoded["regex"] == ""
        assert encoded["action"] == "AlertTrigger"
        assert encoded["parameter"] == "Session ended!"
        assert encoded["partial"] is False
        assert encoded["disabled"] is False
        assert encoded["matchType"] == 107

    def test_event_trigger_equality(self):
        """Test EventTrigger equality comparison."""
        trigger1 = EventTrigger(
            match_type=MatchType.EVENT_BELL_RECEIVED,
            action_name="AlertTrigger",
            param="Bell!",
            enabled=True
        )
        trigger2 = EventTrigger(
            match_type=MatchType.EVENT_BELL_RECEIVED,
            action_name="AlertTrigger",
            param="Bell!",
            enabled=True
        )
        trigger3 = EventTrigger(
            match_type=MatchType.EVENT_BELL_RECEIVED,
            action_name="AlertTrigger",
            param="Different",
            enabled=True
        )
        assert trigger1 == trigger2
        assert trigger1 != trigger3

    def test_to_json(self):
        """Test EventTrigger toJSON method."""
        import json
        trigger = EventTrigger(
            match_type=MatchType.EVENT_SESSION_ENDED,
            action_name="AlertTrigger",
            param="Ended",
            enabled=True
        )
        json_str = trigger.toJSON()
        parsed = json.loads(json_str)
        assert parsed["action"] == "AlertTrigger"
        assert parsed["matchType"] == 107


class TestCommandFinishedEventTrigger:
    """Tests for CommandFinishedEventTrigger."""

    def test_create_with_exit_code_filter_enum(self):
        """Test creating with ExitCodeFilter enum values."""
        trigger = CommandFinishedEventTrigger(
            action_name="AlertTrigger",
            param="Failed!",
            enabled=True,
            exit_code_filter=ExitCodeFilter.NON_ZERO
        )
        assert trigger.exit_code_filter == ExitCodeFilter.NON_ZERO
        assert trigger.event_params["exitCodeFilter"] == "!0"

    def test_create_with_specific_exit_code(self):
        """Test creating with a specific exit code integer."""
        trigger = CommandFinishedEventTrigger(
            action_name="AlertTrigger",
            param="Exit 42!",
            enabled=True,
            exit_code_filter=42
        )
        assert trigger.exit_code_filter == 42
        assert trigger.event_params["exitCodeFilter"] == "42"

    def test_encode(self):
        """Test encoding a CommandFinishedEventTrigger."""
        trigger = CommandFinishedEventTrigger(
            action_name="AlertTrigger",
            param="Success!",
            enabled=True,
            exit_code_filter=ExitCodeFilter.ZERO
        )
        encoded = trigger.encode
        assert encoded["matchType"] == 101
        assert encoded["eventParams"]["exitCodeFilter"] == "0"

    def test_decode(self):
        """Test decoding a CommandFinishedEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Command done",
            "disabled": False,
            "matchType": 101,
            "eventParams": {"exitCodeFilter": "!0"}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, CommandFinishedEventTrigger)
        assert trigger.exit_code_filter == ExitCodeFilter.NON_ZERO

    def test_decode_specific_code(self):
        """Test decoding with a specific exit code."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Exit 1",
            "matchType": 101,
            "eventParams": {"exitCodeFilter": "1"}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, CommandFinishedEventTrigger)
        assert trigger.exit_code_filter == 1


class TestDirectoryChangedEventTrigger:
    """Tests for DirectoryChangedEventTrigger."""

    def test_create_without_regex(self):
        """Test creating without a directory regex."""
        trigger = DirectoryChangedEventTrigger(
            action_name="AlertTrigger",
            param="Dir changed",
            enabled=True
        )
        assert trigger.directory_regex is None
        assert "directoryRegex" not in trigger.event_params

    def test_create_with_regex(self):
        """Test creating with a directory regex."""
        trigger = DirectoryChangedEventTrigger(
            action_name="AlertTrigger",
            param="In project",
            enabled=True,
            directory_regex="/Users/.*/projects"
        )
        assert trigger.directory_regex == "/Users/.*/projects"
        assert trigger.event_params["directoryRegex"] == "/Users/.*/projects"

    def test_decode(self):
        """Test decoding a DirectoryChangedEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Dir",
            "matchType": 102,
            "eventParams": {"directoryRegex": "^/home"}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, DirectoryChangedEventTrigger)
        assert trigger.directory_regex == "^/home"


class TestIdleEventTrigger:
    """Tests for IdleEventTrigger."""

    def test_create_with_default_timeout(self):
        """Test creating with default timeout."""
        trigger = IdleEventTrigger(
            action_name="AlertTrigger",
            param="Idle",
            enabled=True
        )
        assert trigger.timeout == 30.0

    def test_create_with_custom_timeout(self):
        """Test creating with custom timeout."""
        trigger = IdleEventTrigger(
            action_name="AlertTrigger",
            param="Idle",
            enabled=True,
            timeout=120.0
        )
        assert trigger.timeout == 120.0
        assert trigger.event_params["timeout"] == 120.0

    def test_encode(self):
        """Test encoding an IdleEventTrigger."""
        trigger = IdleEventTrigger(
            action_name="AlertTrigger",
            param="Idle",
            enabled=True,
            timeout=60.0
        )
        encoded = trigger.encode
        assert encoded["matchType"] == 105
        assert encoded["eventParams"]["timeout"] == 60.0

    def test_decode(self):
        """Test decoding an IdleEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Idle",
            "matchType": 105,
            "eventParams": {"timeout": 45.0}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, IdleEventTrigger)
        assert trigger.timeout == 45.0


class TestLongRunningCommandEventTrigger:
    """Tests for LongRunningCommandEventTrigger."""

    def test_create_with_defaults(self):
        """Test creating with default values."""
        trigger = LongRunningCommandEventTrigger(
            action_name="AlertTrigger",
            param="Still running",
            enabled=True
        )
        assert trigger.threshold == 60.0
        assert trigger.command_regex is None

    def test_create_with_command_regex(self):
        """Test creating with command regex filter."""
        trigger = LongRunningCommandEventTrigger(
            action_name="AlertTrigger",
            param="Make is slow",
            enabled=True,
            threshold=120.0,
            command_regex="^make "
        )
        assert trigger.threshold == 120.0
        assert trigger.command_regex == "^make "
        assert trigger.event_params["commandRegex"] == "^make "

    def test_decode(self):
        """Test decoding a LongRunningCommandEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Slow",
            "matchType": 109,
            "eventParams": {"threshold": 300.0, "commandRegex": "npm"}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, LongRunningCommandEventTrigger)
        assert trigger.threshold == 300.0
        assert trigger.command_regex == "npm"


class TestCustomEscapeSequenceEventTrigger:
    """Tests for CustomEscapeSequenceEventTrigger."""

    def test_create_with_sequence_id(self):
        """Test creating with a sequence ID."""
        trigger = CustomEscapeSequenceEventTrigger(
            action_name="AlertTrigger",
            param="Custom!",
            enabled=True,
            sequence_id="my-event"
        )
        assert trigger.sequence_id == "my-event"
        assert trigger.event_params["sequenceId"] == "my-event"

    def test_decode(self):
        """Test decoding a CustomEscapeSequenceEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Custom",
            "matchType": 110,
            "eventParams": {"sequenceId": "notify"}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, CustomEscapeSequenceEventTrigger)
        assert trigger.sequence_id == "notify"


class TestHostChangedEventTrigger:
    """Tests for HostChangedEventTrigger."""

    def test_create_without_regex(self):
        """Test creating without a host regex."""
        trigger = HostChangedEventTrigger(
            action_name="AlertTrigger",
            param="Host changed",
            enabled=True
        )
        assert trigger.host_regex is None
        assert "hostRegex" not in trigger.event_params

    def test_create_with_regex(self):
        """Test creating with a host regex."""
        trigger = HostChangedEventTrigger(
            action_name="AlertTrigger",
            param="Production!",
            enabled=True,
            host_regex="prod-.*\\.example\\.com"
        )
        assert trigger.host_regex == "prod-.*\\.example\\.com"
        assert trigger.event_params["hostRegex"] == "prod-.*\\.example\\.com"

    def test_encode(self):
        """Test encoding a HostChangedEventTrigger."""
        trigger = HostChangedEventTrigger(
            action_name="AlertTrigger",
            param="Host",
            enabled=True,
            host_regex="server"
        )
        encoded = trigger.encode
        assert encoded["matchType"] == 103
        assert encoded["eventParams"]["hostRegex"] == "server"

    def test_decode(self):
        """Test decoding a HostChangedEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Host",
            "matchType": 103,
            "eventParams": {"hostRegex": "^web"}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, HostChangedEventTrigger)
        assert trigger.host_regex == "^web"


class TestUserChangedEventTrigger:
    """Tests for UserChangedEventTrigger."""

    def test_create_without_regex(self):
        """Test creating without a user regex."""
        trigger = UserChangedEventTrigger(
            action_name="AlertTrigger",
            param="User changed",
            enabled=True
        )
        assert trigger.user_regex is None
        assert "userRegex" not in trigger.event_params

    def test_create_with_regex(self):
        """Test creating with a user regex."""
        trigger = UserChangedEventTrigger(
            action_name="AlertTrigger",
            param="Root!",
            enabled=True,
            user_regex="^root$"
        )
        assert trigger.user_regex == "^root$"
        assert trigger.event_params["userRegex"] == "^root$"

    def test_encode(self):
        """Test encoding a UserChangedEventTrigger."""
        trigger = UserChangedEventTrigger(
            action_name="AlertTrigger",
            param="User",
            enabled=True,
            user_regex="admin"
        )
        encoded = trigger.encode
        assert encoded["matchType"] == 104
        assert encoded["eventParams"]["userRegex"] == "admin"

    def test_decode(self):
        """Test decoding a UserChangedEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "User",
            "matchType": 104,
            "eventParams": {"userRegex": "sudo"}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, UserChangedEventTrigger)
        assert trigger.user_regex == "sudo"


class TestActivityAfterIdleEventTrigger:
    """Tests for ActivityAfterIdleEventTrigger."""

    def test_create_with_default_timeout(self):
        """Test creating with default timeout."""
        trigger = ActivityAfterIdleEventTrigger(
            action_name="AlertTrigger",
            param="Activity!",
            enabled=True
        )
        assert trigger.timeout == 30.0

    def test_create_with_custom_timeout(self):
        """Test creating with custom timeout."""
        trigger = ActivityAfterIdleEventTrigger(
            action_name="AlertTrigger",
            param="Activity!",
            enabled=True,
            timeout=60.0
        )
        assert trigger.timeout == 60.0
        assert trigger.event_params["timeout"] == 60.0

    def test_encode(self):
        """Test encoding an ActivityAfterIdleEventTrigger."""
        trigger = ActivityAfterIdleEventTrigger(
            action_name="AlertTrigger",
            param="Activity",
            enabled=True,
            timeout=45.0
        )
        encoded = trigger.encode
        assert encoded["matchType"] == 106
        assert encoded["eventParams"]["timeout"] == 45.0

    def test_decode(self):
        """Test decoding an ActivityAfterIdleEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Activity",
            "matchType": 106,
            "eventParams": {"timeout": 120.0}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, ActivityAfterIdleEventTrigger)
        assert trigger.timeout == 120.0


class TestSimpleEventTriggers:
    """Tests for simple event triggers without parameters."""

    def test_prompt_detected(self):
        """Test PromptDetectedEventTrigger."""
        trigger = PromptDetectedEventTrigger(
            action_name="AlertTrigger",
            param="Prompt!",
            enabled=True
        )
        assert trigger.match_type == MatchType.EVENT_PROMPT_DETECTED
        encoded = trigger.encode
        assert encoded["matchType"] == 100

    def test_session_ended(self):
        """Test SessionEndedEventTrigger."""
        trigger = SessionEndedEventTrigger(
            action_name="AlertTrigger",
            param="Goodbye",
            enabled=True
        )
        assert trigger.match_type == MatchType.EVENT_SESSION_ENDED
        encoded = trigger.encode
        assert encoded["matchType"] == 107

    def test_bell_received(self):
        """Test BellReceivedEventTrigger."""
        trigger = BellReceivedEventTrigger(
            action_name="AlertTrigger",
            param="Bell!",
            enabled=True
        )
        assert trigger.match_type == MatchType.EVENT_BELL_RECEIVED
        encoded = trigger.encode
        assert encoded["matchType"] == 108

    def test_decode_prompt_detected(self):
        """Test decoding a PromptDetectedEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Prompt",
            "matchType": 100
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, PromptDetectedEventTrigger)

    def test_decode_session_ended(self):
        """Test decoding a SessionEndedEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Goodbye",
            "matchType": 107
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, SessionEndedEventTrigger)

    def test_decode_bell_received(self):
        """Test decoding a BellReceivedEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Bell",
            "matchType": 108
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, BellReceivedEventTrigger)


class TestNotificationPostedEventTrigger:
    """Tests for NotificationPostedEventTrigger."""

    def test_create_with_message_regex(self):
        """Test creating with a message regex."""
        trigger = NotificationPostedEventTrigger(
            action_name="AlertTrigger",
            param="Got notification!",
            enabled=True,
            message_regex="error.*"
        )
        assert trigger.message_regex == "error.*"
        assert trigger.event_params["messageRegex"] == "error.*"

    def test_create_without_message_regex(self):
        """Test creating without a message regex."""
        trigger = NotificationPostedEventTrigger(
            action_name="AlertTrigger",
            param="Got notification!",
            enabled=True
        )
        assert trigger.message_regex is None
        assert "messageRegex" not in trigger.event_params

    def test_decode(self):
        """Test decoding a NotificationPostedEventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Notified",
            "matchType": 111,
            "eventParams": {"messageRegex": "build.*"}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, NotificationPostedEventTrigger)
        assert trigger.message_regex == "build.*"

    def test_decode_without_params(self):
        """Test decoding without event params."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Notified",
            "matchType": 111
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, NotificationPostedEventTrigger)
        assert trigger.message_regex is None

    def test_roundtrip(self):
        """Test round-trip for NotificationPostedEventTrigger."""
        original = NotificationPostedEventTrigger(
            action_name="AlertTrigger",
            param="Notified!",
            enabled=True,
            message_regex="deploy"
        )
        encoded = original.encode
        decoded = decode_trigger(encoded)
        assert isinstance(decoded, NotificationPostedEventTrigger)
        assert decoded.message_regex == "deploy"
        assert decoded.action_name == original.action_name
        assert decoded.param == original.param
        assert decoded.enabled == original.enabled


class TestEventTriggerRoundTrip:
    """Tests for encoding and decoding event triggers."""

    def test_command_finished_roundtrip(self):
        """Test round-trip for CommandFinishedEventTrigger."""
        original = CommandFinishedEventTrigger(
            action_name="AlertTrigger",
            param="Done!",
            enabled=True,
            exit_code_filter=ExitCodeFilter.NON_ZERO
        )
        encoded = original.encode
        decoded = decode_trigger(encoded)
        assert isinstance(decoded, CommandFinishedEventTrigger)
        assert decoded.action_name == original.action_name
        assert decoded.param == original.param
        assert decoded.enabled == original.enabled
        assert decoded.exit_code_filter == original.exit_code_filter

    def test_idle_roundtrip(self):
        """Test round-trip for IdleEventTrigger."""
        original = IdleEventTrigger(
            action_name="UserNotificationTrigger",
            param="Idle!",
            enabled=False,
            timeout=90.0
        )
        encoded = original.encode
        decoded = decode_trigger(encoded)
        assert isinstance(decoded, IdleEventTrigger)
        assert decoded.timeout == 90.0
        assert decoded.enabled is False

    def test_long_running_roundtrip(self):
        """Test round-trip for LongRunningCommandEventTrigger."""
        original = LongRunningCommandEventTrigger(
            action_name="AlertTrigger",
            param="Slow!",
            enabled=True,
            threshold=180.0,
            command_regex="^rsync"
        )
        encoded = original.encode
        decoded = decode_trigger(encoded)
        assert isinstance(decoded, LongRunningCommandEventTrigger)
        assert decoded.threshold == 180.0
        assert decoded.command_regex == "^rsync"


class TestUnknownEventTrigger:
    """Tests for handling unknown event trigger types."""

    def test_decode_unknown_event_type(self):
        """Test decoding an unknown event type returns EventTrigger."""
        encoded = {
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "Unknown",
            "matchType": 999,  # Unknown future event type
            "eventParams": {"someKey": "someValue"}
        }
        trigger = decode_trigger(encoded)
        assert isinstance(trigger, EventTrigger)
        # Should preserve the raw match type for re-encoding
        assert trigger.encode["matchType"] == 999
