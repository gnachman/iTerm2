"""Tests for iterm2.binding module."""
import json
import pytest
from iterm2.binding import PasteConfiguration


class TestPasteConfiguration:
    """Tests for the PasteConfiguration class."""

    def make_config(self, **kwargs):
        """Helper to create a PasteConfiguration with defaults."""
        defaults = {
            'base64': False,
            'wait_for_prompts': False,
            'tab_transform': PasteConfiguration.TabTransform.NONE,
            'tab_stop_size': 4,
            'delay': 0.01,
            'chunk_size': 1024,
            'convert_newlines': True,
            'remove_newlines': False,
            'convert_unicode_punctuation': False,
            'escape_for_shell': False,
            'remove_controls': False,
            'bracket_allowed': True,
            'use_regex_substitution': False,
            'regex': '',
            'substitution': ''
        }
        defaults.update(kwargs)
        return PasteConfiguration(**defaults)

    def test_base64_property(self):
        """Test base64 property getter."""
        config = self.make_config(base64=True)
        assert config.base64 is True

        config = self.make_config(base64=False)
        assert config.base64 is False

    def test_wait_for_prompts_property(self):
        """Test wait_for_prompts property getter."""
        config = self.make_config(wait_for_prompts=True)
        assert config.wait_for_prompts is True

    def test_tab_transform_property(self):
        """Test tab_transform property getter."""
        config = self.make_config(tab_transform=PasteConfiguration.TabTransform.CONVERT_TO_SPACES)
        assert config.tab_transform == PasteConfiguration.TabTransform.CONVERT_TO_SPACES

    def test_tab_stop_size_property(self):
        """Test tab_stop_size property getter."""
        config = self.make_config(tab_stop_size=8)
        assert config.tab_stop_size == 8

    def test_delay_property(self):
        """Test delay property getter."""
        config = self.make_config(delay=0.5)
        assert config.delay == 0.5

    def test_chunk_size_property(self):
        """Test chunk_size property getter."""
        config = self.make_config(chunk_size=2048)
        assert config.chunk_size == 2048

    def test_convert_newlines_property(self):
        """Test convert_newlines property getter."""
        config = self.make_config(convert_newlines=True)
        assert config.convert_newlines is True

    def test_remove_newlines_property(self):
        """Test remove_newlines property getter."""
        config = self.make_config(remove_newlines=True)
        assert config.remove_newlines is True

    def test_convert_unicode_punctuation_property(self):
        """Test convert_unicode_punctuation property getter."""
        config = self.make_config(convert_unicode_punctuation=True)
        assert config.convert_unicode_punctuation is True

    def test_escape_for_shell_property(self):
        """Test escape_for_shell property getter."""
        config = self.make_config(escape_for_shell=True)
        assert config.escape_for_shell is True

    def test_remove_controls_property(self):
        """Test remove_controls property getter."""
        config = self.make_config(remove_controls=True)
        assert config.remove_controls is True

    def test_bracket_allowed_property(self):
        """Test bracket_allowed property getter."""
        config = self.make_config(bracket_allowed=False)
        assert config.bracket_allowed is False

    def test_use_regex_substitution_property(self):
        """Test use_regex_substitution property getter."""
        config = self.make_config(use_regex_substitution=True)
        assert config.use_regex_substitution is True

    def test_regex_property(self):
        """Test regex property getter."""
        config = self.make_config(regex=r'\d+')
        assert config.regex == r'\d+'

    def test_substitution_property(self):
        """Test substitution property getter."""
        config = self.make_config(substitution='replacement')
        assert config.substitution == 'replacement'

    def test_base64_setter(self):
        """Test base64 property setter."""
        config = self.make_config(base64=False)
        config.base64 = True
        assert config.base64 is True

    def test_tab_transform_setter(self):
        """Test tab_transform property setter."""
        config = self.make_config()
        config.tab_transform = PasteConfiguration.TabTransform.ESCAPE_WITH_CONTROL_V
        assert config.tab_transform == PasteConfiguration.TabTransform.ESCAPE_WITH_CONTROL_V


class TestPasteConfigurationEncode:
    """Tests for PasteConfiguration._encode() method."""

    def test_encode_produces_valid_json(self):
        """Test that _encode produces valid JSON."""
        config = PasteConfiguration(
            base64=True,
            wait_for_prompts=False,
            tab_transform=PasteConfiguration.TabTransform.NONE,
            tab_stop_size=4,
            delay=0.01,
            chunk_size=1024,
            convert_newlines=True,
            remove_newlines=False,
            convert_unicode_punctuation=False,
            escape_for_shell=False,
            remove_controls=False,
            bracket_allowed=True,
            use_regex_substitution=False,
            regex='',
            substitution=''
        )
        encoded = config._encode()
        parsed = json.loads(encoded)

        assert parsed['Base64'] is True
        assert parsed['WaitForPrompts'] is False
        assert parsed['TabTransform'] == 0
        assert parsed['TabStopSize'] == 4
        assert parsed['Delay'] == 0.01
        assert parsed['ChunkSize'] == 1024
        assert parsed['ConvertNewlines'] is True
        assert parsed['RemoveNewlines'] is False
        assert parsed['ConvertUnicodePunctuation'] is False
        assert parsed['EscapeForShell'] is False
        assert parsed['RemoveControls'] is False
        assert parsed['BracketAllowed'] is True
        assert parsed['UseRegexSubstitution'] is False
        assert parsed['Regex'] == ''
        assert parsed['Substitution'] == ''

    def test_encode_tab_transform_values(self):
        """Test that tab_transform enum values are encoded correctly."""
        for transform in PasteConfiguration.TabTransform:
            config = PasteConfiguration(
                base64=False,
                wait_for_prompts=False,
                tab_transform=transform,
                tab_stop_size=4,
                delay=0.0,
                chunk_size=1024,
                convert_newlines=False,
                remove_newlines=False,
                convert_unicode_punctuation=False,
                escape_for_shell=False,
                remove_controls=False,
                bracket_allowed=True,
                use_regex_substitution=False,
                regex='',
                substitution=''
            )
            parsed = json.loads(config._encode())
            assert parsed['TabTransform'] == transform.value


class TestTabTransform:
    """Tests for PasteConfiguration.TabTransform enum."""

    def test_enum_values(self):
        """Test TabTransform enum has expected values."""
        assert PasteConfiguration.TabTransform.NONE.value == 0
        assert PasteConfiguration.TabTransform.CONVERT_TO_SPACES.value == 1
        assert PasteConfiguration.TabTransform.ESCAPE_WITH_CONTROL_V.value == 2
