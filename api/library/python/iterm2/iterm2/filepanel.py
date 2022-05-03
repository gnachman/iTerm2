"""Open and Save panels."""
import enum
import json
import typing

import iterm2.capabilities
import iterm2.connection

class OpenPanel:
    """
    Requires iTerm2 3.5.0beta6 or later.

    :param path: Initial directory.
    :param options: Collection of flags. See Options enum.
    :param extensions: List of extensions, like ["txt", "rtf"].
    :param prompt: Text for OK button.
    :param message: Panel title text.
    """

    class Options(enum.Enum):
        CAN_CREATE_DIRECTORIES = (1 << 0)
        TREATS_FILE_PACKAGES_AS_DIRECTORIES = (1 << 1)
        SHOWS_HIDDEN_FILES = (1 << 2)
        RESOLVES_ALIASES = (1 << 32)
        CAN_CHOOSE_DIRECTORIES = (1 << 33)
        ALLOWS_MULTIPLE_SELECTION = (1 << 34)
        CAN_CHOOSE_FILES = (1 << 35)

    class Result:
        """Holds the results of a successful open panel."""
        def __init__(self, files):
            self.__files = files

        @property
        def files(self) -> typing.List[str]:
            return self.__files

    def __init__(self):
        self.__path = None
        self.__options = [OpenPanel.Options(OpenPanel.Options.CAN_CHOOSE_FILES)]
        self.__extensions = None
        self.__prompt = None
        self.__message = None

    @property
    def path(self) -> typing.Optional[str]:
        """Initial directory for panel."""
        return self.__path

    @path.setter
    def path(self, value: str):
        self.__path = value

    @property
    def options(self) -> typing.List['iterm2.OpenPanel.Options']:
        """Flags controlling the panel.

        Defaults to [Options(CAN_CHOOSE_FILES)].
        """
        return self.__options

    @options.setter
    def options(self, value: typing.List['iterm2.OpenPanel.Options']):
        self.__options = value

    @property
    def extensions(self) -> typing.Optional[typing.List[str]]:
        """List of file extensions that are allowed."""
        return self.__extensions

    @extensions.setter
    def extensions(self, value: typing.Optional[typing.List[str]]):
        self.__extensions = value

    @property
    def prompt(self) -> typing.Optional[str]:
        """Text for OK button."""
        return self.__prompt

    @prompt.setter
    def prompt(self, value: str):
        self.__prompt = value

    @property
    def message(self) -> typing.Optional[str]:
        """Text for panel title."""
        return self.__message

    @message.setter
    def message(self, value: str):
        self.__message = value

    async def async_run(self, connection) -> typing.Optional['iterm2.OpenPanel.Result']:
        """Show the panel.

        :returns: A :class:`~iterm2.OpenPanel.Result` if successful,
            or `None` if the user cancels.
        """
        iterm2.capabilities.check_supports_file_panels(connection)
        bitmap = sum(map(lambda option: option.value, self.options))
        response = await iterm2.async_invoke_function(
            connection,
            (f'iterm2.open_panel(path: {json.dumps(self.path)}, ' +
             f'options: {bitmap},' +
             f'extensions: {json.dumps(self.extensions)},' +
             f'prompt: {json.dumps(self.prompt)},' +
             f'message: {json.dumps(self.message)})'))
        if response:
            return OpenPanel.Result(response)
        return None


class SavePanel:
    """
    Requires iTerm2 3.5.0beta6 or later.

    :param path: Undocumented.
    :param options: Undocumented.
    :param extensions: Undocumented.
    :param prompt: Undocumented.
    :param title: Undocumented.
    :param message: Undocumented.
    :param name_field_label: Undocumented.
    :param default_filename: Undocumented.
    """

    class Options(enum.Enum):
        CAN_CREATE_DIRECTORIES = (1 << 0)
        TREATS_FILE_PACKAGES_AS_DIRECTORIES = (1 << 1)
        SHOWS_HIDDEN_FILES = (1 << 2)
        ALLOWS_OTHER_FILE_TYPES = (1 << 3)
        CAN_SELECT_HIDDEN_EXTENSION = (1 << 4)
        EXTENSION_HIDDEN = (1 << 5)

    class Result:
        """Holds the results of a successful save panel."""
        def __init__(self, file):
            self.__file = file

        @property
        def file(self) -> str:
            return self.__file

    def __init__(self):
        self.__path = None
        self.__options = []
        self.__extensions = None
        self.__prompt = None
        self.__title = None
        self.__message = None
        self.__name_field_label = None
        self.__default_filename = None

    @property
    def path(self) -> str:
        """Initial directory."""
        return self.__path

    @path.setter
    def path(self, value: str):
        self.__path = value

    @property
    def options(self) -> typing.List['iterm2.SavePanel.Options']:
        """Flags controlling the panel.

        Defaults to [].
        """
        return self.__options

    @options.setter
    def options(self, value: typing.List['iterm2.SavePanel.Options']):
        self.__options = value

    @property
    def extensions(self) -> typing.Optional[typing.List[str]]:
        """List of file extensions that are allowed."""
        return self.__extensions

    @extensions.setter
    def extensions(self, value: typing.Optional[typing.List[str]]):
        self.__extensions = value

    @property
    def prompt(self) -> typing.Optional[str]:
        """Text for OK button."""
        return self.__prompt

    @prompt.setter
    def prompt(self, value: typing.Optional[str]):
        self.__prompt = value

    @property
    def title(self) -> typing.Optional[str]:
        """Text for panel title."""
        return self.__title

    @title.setter
    def title(self, value: typing.Optional[str]):
        self.__title = value

    @property
    def message(self) -> typing.Optional[str]:
        """Text for subtitle."""
        return self.__message

    @message.setter
    def message(self, value: typing.Optional[str]):
        self.__message = value

    @property
    def name_field_label(self) -> typing.Optional[str]:
        """Text before filename field."""
        return self.__name_field_label

    @name_field_label.setter
    def name_field_label(self, value: typing.Optional[str]):
        self.__name_field_label = value

    @property
    def default_filename(self) -> typing.Optional[str]:
        """Pre-fill filename field with this."""
        return self.__default_filename

    @default_filename.setter
    def default_filename(self, value: typing.Optional[str]):
        self.__default_filename = value

    async def async_run(self, connection) -> typing.Optional['iterm2.SavePanel.Result']:
        """Show the panel.

        :returns: A :class:`~iterm2.SavePanel.Result` if successful,
            or `None` if the user cancels.
        """
        iterm2.capabilities.check_supports_file_panels(connection)
        bitmap = sum(map(lambda option: option.value, self.options))
        response = await iterm2.async_invoke_function(
                connection,
                (f'iterm2.save_panel(path: {json.dumps(self.path)}, ' +
                f'options: {bitmap},' +
                f'extensions: {json.dumps(self.extensions)},' +
                f'prompt: {json.dumps(self.prompt)},' +
                f'title: {json.dumps(self.title)},' +
                f'message: {json.dumps(self.message)},' +
                f'name_field_label: {json.dumps(self.name_field_label)},'
                f'default_filename: {json.dumps(self.default_filename)})'))
        if response:
            return SavePanel.Result(response)
        return None
