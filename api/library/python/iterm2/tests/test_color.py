"""Tests for iterm2.color module."""
import pytest
from iterm2.color import Color, ColorSpace, MissingDependency


class TestColor:
    """Tests for the Color class."""

    def test_default_color(self):
        """Test that default color is black with full opacity."""
        color = Color()
        assert color.red == 0
        assert color.green == 0
        assert color.blue == 0
        assert color.alpha == 255
        assert color.color_space == ColorSpace.SRGB

    def test_color_with_values(self):
        """Test creating a color with specific values."""
        color = Color(r=100, g=150, b=200, a=128)
        assert color.red == 100
        assert color.green == 150
        assert color.blue == 200
        assert color.alpha == 128

    def test_color_setters(self):
        """Test color property setters."""
        color = Color()
        color.red = 50
        color.green = 100
        color.blue = 150
        color.alpha = 200
        color.color_space = ColorSpace.P3

        assert color.red == 50
        assert color.green == 100
        assert color.blue == 150
        assert color.alpha == 200
        assert color.color_space == ColorSpace.P3


class TestColorFromHex:
    """Tests for Color.from_hex() method."""

    def test_from_hex_6_digit(self):
        """Test parsing a 6-digit hex color."""
        color = Color.from_hex("#aabbcc")
        assert color is not None
        assert color.red == 0xaa
        assert color.green == 0xbb
        assert color.blue == 0xcc
        assert color.alpha == 255

    def test_from_hex_12_digit(self):
        """Test parsing a 12-digit hex color."""
        # 12-digit hex: #rrrrggggbbbb
        # Each component is divided by 257 to convert from 16-bit to 8-bit
        color = Color.from_hex("#ffff00000000")
        assert color is not None
        assert color.red == 255
        assert color.green == 0
        assert color.blue == 0

    def test_from_hex_p3_prefix(self):
        """Test parsing a P3 color space hex color."""
        color = Color.from_hex("p3#ff0000")
        assert color is not None
        assert color.red == 255
        assert color.green == 0
        assert color.blue == 0
        assert color.color_space == ColorSpace.P3

    def test_from_hex_invalid_no_hash(self):
        """Test that hex without # returns None."""
        color = Color.from_hex("aabbcc")
        assert color is None

    def test_from_hex_invalid_length(self):
        """Test that invalid length returns None."""
        color = Color.from_hex("#aabb")
        assert color is None


class TestColorDict:
    """Tests for Color dict/JSON methods."""

    def test_get_dict(self):
        """Test converting color to dictionary."""
        color = Color(r=255, g=128, b=64, a=255)
        d = color.get_dict()

        assert d["Red Component"] == 1.0
        assert d["Green Component"] == pytest.approx(128 / 255.0)
        assert d["Blue Component"] == pytest.approx(64 / 255.0)
        assert d["Alpha Component"] == 1.0
        assert d["Color Space"] == "sRGB"

    def test_from_dict(self):
        """Test loading color from dictionary."""
        color = Color()
        color.from_dict({
            "Red Component": 1.0,
            "Green Component": 0.5,
            "Blue Component": 0.25,
            "Alpha Component": 0.75,
            "Color Space": "P3"
        })

        assert color.red == 255
        assert color.green == pytest.approx(127.5)
        assert color.blue == pytest.approx(63.75)
        assert color.alpha == pytest.approx(191.25)
        assert color.color_space == ColorSpace.P3

    def test_from_dict_defaults(self):
        """Test loading color from dict with missing optional fields."""
        color = Color()
        color.from_dict({
            "Red Component": 0.5,
            "Green Component": 0.5,
            "Blue Component": 0.5
        })

        assert color.alpha == 255
        assert color.color_space == ColorSpace.CALIBRATED


class TestColorHex:
    """Tests for Color.hex property."""

    def test_hex_srgb(self):
        """Test hex representation for sRGB color."""
        color = Color(r=255, g=128, b=0)
        assert color.hex == "#ff8000"

    def test_hex_p3(self):
        """Test hex representation for P3 color."""
        color = Color(r=255, g=128, b=0, color_space=ColorSpace.P3)
        assert color.hex == "p3#ff8000"

    def test_hex_black(self):
        """Test hex representation for black."""
        color = Color(r=0, g=0, b=0)
        assert color.hex == "#000000"

    def test_hex_white(self):
        """Test hex representation for white."""
        color = Color(r=255, g=255, b=255)
        assert color.hex == "#ffffff"


class TestMissingDependency:
    """Tests for MissingDependency exception."""

    def test_is_subclass_of_import_error(self):
        """Test that MissingDependency is a subclass of ImportError."""
        assert issubclass(MissingDependency, ImportError)

    def test_from_cocoa_without_pyobjc(self):
        """Test that from_cocoa raises MissingDependency without pyobjc."""
        with pytest.raises(MissingDependency):
            Color.from_cocoa("dGVzdA==")

    def test_from_legacy_trigger_without_pyobjc(self):
        """Test that from_legacy_trigger raises MissingDependency without pyobjc."""
        with pytest.raises(MissingDependency):
            Color.from_legacy_trigger("0")


class TestColorRepr:
    """Tests for Color.__repr__() method."""

    def test_repr(self):
        """Test string representation of color."""
        color = Color(r=100, g=150, b=200, a=255)
        repr_str = repr(color)
        assert "100" in repr_str
        assert "150" in repr_str
        assert "200" in repr_str
