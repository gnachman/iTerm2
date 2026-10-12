"""Open and Save panels."""

from __future__ import annotations

import enum
import json
from typing import TYPE_CHECKING

from .app import async_invoke_function
from .capabilities import check_supports_file_panels

if TYPE_CHECKING:
    from .connection import Connection


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
        CAN_CREATE_DIRECTORIES = 1 << 0
        TREATS_FILE_PACKAGES_AS_DIRECTORIES = 1 << 1
        SHOWS_HIDDEN_FILES = 1 << 2
        RESOLVES_ALIASES = 1 << 32
        CAN_CHOOSE_DIRECTORIES = 1 << 33
        ALLOWS_MULTIPLE_SELECTION = 1 << 34
        CAN_CHOOSE_FILES = 1 << 35

    class Result:
        """Holds the results of a successful open panel."""

        def __init__(self, files: list[str]) -> None:
            self.__files = files

        @property
        def files(self) -> list[str]:
            return self.__files

    def __init__(self) -> None:
        self.__path: str | None = None
        self.__options = [OpenPanel.Options(OpenPanel.Options.CAN_CHOOSE_FILES)]
        self.__extensions: list[str] | None = None
        self.__prompt: str | None = None
        self.__message: str | None = None

    @property
    def path(self) -> str | None:
        """Initial directory for panel."""
        return self.__path

    @path.setter
    def path(self, value: str) -> None:
        self.__path = value

    @property
    def options(self) -> list[OpenPanel.Options]:
        """Flags controlling the panel.

        Defaults to [Options(CAN_CHOOSE_FILES)].
        """
        return self.__options

    @options.setter
    def options(self, value: list[OpenPanel.Options]) -> None:
        self.__options = value

    @property
    def extensions(self) -> list[str] | None:
        """List of file extensions that are allowed."""
        return self.__extensions

    @extensions.setter
    def extensions(self, value: list[str] | None) -> None:
        self.__extensions = value

    @property
    def prompt(self) -> str | None:
        """Text for OK button."""
        return self.__prompt

    @prompt.setter
    def prompt(self, value: str) -> None:
        self.__prompt = value

    @property
    def message(self) -> str | None:
        """Text for panel title."""
        return self.__message

    @message.setter
    def message(self, value: str) -> None:
        self.__message = value

    async def async_run(self, connection: Connection) -> OpenPanel.Result | None:
        """Show the panel.

        :returns: A :class:`~iterm2.OpenPanel.Result` if successful,
            or `None` if the user cancels.
        """
        check_supports_file_panels(connection)
        bitmap = sum(option.value for option in self.options)
        response = await async_invoke_function(
            connection,
            (
                f"iterm2.open_panel(path: {json.dumps(self.path)}, "
                f"options: {bitmap},"
                f"extensions: {json.dumps(self.extensions)},"
                f"prompt: {json.dumps(self.prompt)},"
                f"message: {json.dumps(self.message)})"
            ),
        )
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
        CAN_CREATE_DIRECTORIES = 1 << 0
        TREATS_FILE_PACKAGES_AS_DIRECTORIES = 1 << 1
        SHOWS_HIDDEN_FILES = 1 << 2
        ALLOWS_OTHER_FILE_TYPES = 1 << 3
        CAN_SELECT_HIDDEN_EXTENSION = 1 << 4
        EXTENSION_HIDDEN = 1 << 5

    class Result:
        """Holds the results of a successful save panel."""

        def __init__(self, file: str) -> None:
            self.__file = file

        @property
        def file(self) -> str:
            return self.__file

    def __init__(self) -> None:
        self.__path: str | None = None
        self.__options: list[SavePanel.Options] = []
        self.__extensions: list[str] | None = None
        self.__prompt: str | None = None
        self.__title: str | None = None
        self.__message: str | None = None
        self.__name_field_label: str | None = None
        self.__default_filename: str | None = None

    @property
    def path(self) -> str | None:
        """Initial directory."""
        return self.__path

    @path.setter
    def path(self, value: str) -> None:
        self.__path = value

    @property
    def options(self) -> list[SavePanel.Options]:
        """Flags controlling the panel.

        Defaults to [].
        """
        return self.__options

    @options.setter
    def options(self, value: list[SavePanel.Options]) -> None:
        self.__options = value

    @property
    def extensions(self) -> list[str] | None:
        """List of file extensions that are allowed."""
        return self.__extensions

    @extensions.setter
    def extensions(self, value: list[str] | None) -> None:
        self.__extensions = value

    @property
    def prompt(self) -> str | None:
        """Text for OK button."""
        return self.__prompt

    @prompt.setter
    def prompt(self, value: str | None) -> None:
        self.__prompt = value

    @property
    def title(self) -> str | None:
        """Text for panel title."""
        return self.__title

    @title.setter
    def title(self, value: str | None) -> None:
        self.__title = value

    @property
    def message(self) -> str | None:
        """Text for subtitle."""
        return self.__message

    @message.setter
    def message(self, value: str | None) -> None:
        self.__message = value

    @property
    def name_field_label(self) -> str | None:
        """Text before filename field."""
        return self.__name_field_label

    @name_field_label.setter
    def name_field_label(self, value: str | None) -> None:
        self.__name_field_label = value

    @property
    def default_filename(self) -> str | None:
        """Pre-fill filename field with this."""
        return self.__default_filename

    @default_filename.setter
    def default_filename(self, value: str | None) -> None:
        self.__default_filename = value

    async def async_run(self, connection: Connection) -> SavePanel.Result | None:
        """Show the panel.

        :returns: A :class:`~iterm2.SavePanel.Result` if successful,
            or `None` if the user cancels.
        """
        check_supports_file_panels(connection)
        bitmap = sum(option.value for option in self.options)
        response = await async_invoke_function(
            connection,
            (
                f"iterm2.save_panel(path: {json.dumps(self.path)}, "
                + f"options: {bitmap},"
                + f"extensions: {json.dumps(self.extensions)},"
                + f"prompt: {json.dumps(self.prompt)},"
                + f"title: {json.dumps(self.title)},"
                + f"message: {json.dumps(self.message)},"
                + f"name_field_label: {json.dumps(self.name_field_label)},"
                f"default_filename: {json.dumps(self.default_filename)})"
            ),
        )
        if response:
            return SavePanel.Result(response)
        return None
