"""Shared classes for representing color and related concepts."""

import AppKit
import base64
import enum
import json
import typing


class ColorSpace(enum.Enum):
    """Describes the color space of a :class:`Color`."""
    SRGB = "sRGB"  #: SRGB color space
    CALIBRATED = "Calibrated"  #: Device color space


# pylint: disable=too-many-instance-attributes
class Color:
    """Describes a color.

      :param r: Red, in 0-255
      :param g: Green, in 0-255
      :param b: Blue, in 0-255
      :param a: Alpha, in 0-255
      :param color_space: The color space. Only sRGB is supported currently.
      """
    # pylint: disable=too-many-arguments
    def __init__(
            self,
            r: int = 0,
            g: int = 0,
            b: int = 0,
            a: int = 255,
            color_space: ColorSpace = ColorSpace.SRGB):
        """Create a color."""
        self.__red = r
        self.__green = g
        self.__blue = b
        self.__alpha = a
        self.__color_space = color_space

    @staticmethod
    def from_trigger(s: str) -> typing.Optional['Color']:
        """Decodes a color as encoded in a trigger."""
        color = Color.from_hex(s)
        if color is not None:
            return color
        return Color.from_cocoa(s)

    @staticmethod
    def from_hex(s: str) -> typing.Optional['Color']:
        """Decodes a hex-encoded color like #aabbcc"""
        if s[0] != '#' or len(s) != 7:
            return None
        red = int(s[1:3], 16)
        green = int(s[3:5], 16)
        blue = int(s[5:7], 16)
        return Color(red, green, blue, 255)

    @staticmethod
    def from_cocoa(b: str) -> typing.Optional['Color']:
        """Decodes a NSKeyedArchiver-encoded color."""
        data = base64.b64decode(b)
        nscolor = AppKit.NSColor.alloc().initWithCoder_(AppKit.NSKeyedUnarchiver.alloc().initForReadingWithData_(data))
        return Color(
             round(nscolor.redComponent() * 255),
             round(nscolor.greenComponent() * 255),
             round(nscolor.blueComponent() * 255),
             round(nscolor.alphaComponent() * 255))

    @staticmethod
    def from_legacy_trigger(s: str) -> ('Color', 'Color'):
        i = int(str)

        black = AppKit.NSColor.blackColor
        blue = AppKit.NSColor.blueColor
        brown = AppKit.NSColor.brownColor
        cyan = AppKit.NSColor.cyanColor
        darkgray = AppKit.NSColor.darkGrayColor
        gray = AppKit.NSColor.grayColor
        green = AppKit.NSColor.greenColor
        lightgray = AppKit.NSColor.lightGrayColor
        magenta = AppKit.NSColor.magentaColor
        none = lambda: None
        orange = AppKit.NSColor.orangeColor
        purple = AppKit.NSColor.purpleColor
        red = AppKit.NSColor.redColor
        white = AppKit.NSColor.whiteColor
        yellow = AppKit.NSColor.yellowColor

        table = {
            0: (yellow, black),
            1: (black, yellow),
            2: (white, red),
            3: (red, white),
            4: (black, orange),
            5: (orange, black),
            6: (black, purple),
            7: (purple, black),

            1000: (black, none),
            1001: (darkgray, none),
            1002: (lightgray, none),
            1003: (white, none),
            1004: (gray, none),
            1005: (red, none),
            1006: (green, none),
            1007: (blue, none),
            1008: (cyan, none),
            1009: (yellow, none),
            1010: (magenta, none),
            1011: (orange, none),
            1012: (purple, none),
            1013: (brown, none),

            2000: (none, black),
            2001: (none, darkgray),
            2002: (none, lightgray),
            2003: (none, white),
            2004: (none, gray),
            2005: (none, red),
            2006: (none, green),
            2007: (none, blue),
            2008: (none, cyan),
            2009: (none, yellow),
            2010: (none, magenta),
            2011: (none, orange),
            2012: (none, purple),
            2013: (none, brown),
        }

        (text, background) = table[i]
        return (text(), background())


    def __repr__(self):
        return "({},{},{},{} {})".format(
            round(self.red),
            round(self.green),
            round(self.blue),
            round(self.alpha),
            self.color_space)

    @property
    def red(self) -> int:
        """The color's red component."""
        return self.__red

    @red.setter
    def red(self, value: int):
        """Sets the color's red component."""
        self.__red = value

    @property
    def green(self) -> int:
        """The color's green component."""
        return self.__green

    @green.setter
    def green(self, value: int):
        """Sets the color's green component."""
        self.__green = value

    @property
    def blue(self) -> int:
        """The color's blue component."""
        return self.__blue

    @blue.setter
    def blue(self, value: int):
        """Sets the color's blue component."""
        self.__blue = value

    @property
    def alpha(self) -> int:
        """The color's alpha component."""
        return self.__alpha

    @alpha.setter
    def alpha(self, value: int):
        """Sets the color's alpha component."""
        self.__alpha = value

    @property
    def color_space(self) -> ColorSpace:
        """The color's color space."""
        return self.__color_space

    @color_space.setter
    def color_space(self, value: ColorSpace):
        """Sets the color's scolor space."""
        self.__color_space = value

    def get_dict(self):
        """Returns a dictionary representation of this color.

        Suitable for conversion to a JSON object to pass to iTerm2."""
        return {
            "Red Component": self.red / 255.0,
            "Green Component": self.green / 255.0,
            "Blue Component": self.blue / 255.0,
            "Alpha Component": self.alpha / 255.0,
            "Color Space": self.color_space.value
            }

    def from_dict(self, input_dict):
        """Updates the color from the dictionary's contents."""
        self.red = float(input_dict["Red Component"]) * 255
        self.green = float(input_dict["Green Component"]) * 255
        self.blue = float(input_dict["Blue Component"]) * 255
        if "Alpha Component" in input_dict:
            self.alpha = float(input_dict["Alpha Component"]) * 255
        else:
            self.alpha = 255
        if "Color Space" in input_dict:
            self.color_space = ColorSpace(input_dict["Color Space"])
        else:
            # This is the default because it is what profiles use by default.
            self.color_space = ColorSpace.CALIBRATED

    @property
    def json(self):
        """Returns a JSON representation of this color."""
        return json.dumps(self.get_dict())

    @property
    def hex(self):
        """Returns a #rrggbb representation of this color. Assumes srgb colorspace."""
        two_digit_hex = '02x'
        return "#" + format(self.red, two_digit_hex) + format(self.green, two_digit_hex) + format(self.blue, two_digit_hex)
