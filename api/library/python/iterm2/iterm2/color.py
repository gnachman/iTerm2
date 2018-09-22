class Color:
    """Describes a color."""

    COLOR_SPACE_NAME_SRGB="sRGB"
    COLOR_SPACE_NAME_CALIBRATED="Calibrated"

    def __init__(self, r=0, g=0, b=0, a=255, color_space="sRGB"):
        """Create a color.

          r: Red, in 0-255
          g: Green, in 0-255
          b: Blue, in 0-255
          a: Alpha, in 0-255
          color_space: The color space. Only sRGB is supported currently."""
        self.__red = r
        self.__green = g
        self.__blue = b
        self.__alpha = a
        self.__color_space = color_space

    def __repr__(self):
        return "({},{},{},{} {})".format(
            round(self.red),
            round(self.green),
            round(self.blue),
            round(self.alpha),
            self.color_space)

    @property
    def red(self):
        """The color's red component."""
        return self.__red

    @red.setter
    def red(self, value):
        """Sets the color's red component."""
        self.__red = value

    @property
    def green(self):
        """The color's green component."""
        return self.__green

    @green.setter
    def green(self, value):
        """Sets the color's green component."""
        self.__green = value

    @property
    def blue(self):
        """The color's blue component."""
        return self.__blue

    @blue.setter
    def blue(self, value):
        """Sets the color's blue component."""
        self.__blue = value

    @property
    def alpha(self):
        """The color's alpha component."""
        return self.__alpha

    @alpha.setter
    def alpha(self, value):
        """Sets the color's alpha component."""
        self.__alpha = value

    @property
    def color_space(self):
        """The color's color space.

        Recognized values are: `iterm2.Color.COLOR_SPACE_NAME_SRGB` and `iterm2.Color.COLOR_SPACE_NAME_CALIBRATED`."""
        return self.__color_space

    @color_space.setter
    def color_space(self, value):
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
            "Color Space": self.color_space
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
            self.color_space = input_dict["Color Space"]
        else:
            self.color_space = "sRGB"

    @property
    def json(self):
        return json.dumps(self.get_dict())

