"""Enables showing modal alerts."""
import json
import typing

import iterm2.connection


class Alert:
    """A modal alert.

    :param title: The title, shown in bold at the top.
    :param subtitle: The informative text, which may be more than one line
        long.
    :param window_id: The window to attach the alert to. If None, it will be
        application modal.

    .. seealso:: Example ":ref:`oneshot_example`"
    """
    def __init__(
            self,
            title: str,
            subtitle: str,
            window_id: typing.Optional[str] = None):
        self.__title = title
        self.__subtitle = subtitle
        self.__buttons: typing.List[str] = []
        self.__window_id = window_id

    @property
    def title(self) -> str:
        """Returns the title string"""
        return self.__title

    @property
    def subtitle(self) -> str:
        """Returns the subtitle string"""
        return self.__subtitle

    @property
    def window_id(self) -> typing.Optional[str]:
        """Returns the window ID"""
        return self.__window_id

    def add_button(self, title: str):
        """Adds a button to the end of the list of buttons."""
        self.__buttons.append(title)

    async def async_run(self, connection: iterm2.connection.Connection) -> int:
        """Shows the modal alert.

        :param connection: The connection to use.
        :returns: The index of the selected button. If no buttons were defined
            then a single button, "OK", is automatically added.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        title = json.dumps(self.title)
        subtitle = json.dumps(self.subtitle)
        buttons = json.dumps(self.__buttons)

        return await iterm2.async_invoke_function(
            connection,
            (f'iterm2.alert(title: {title}, ' +
             f'subtitle: {subtitle}, ' +
             f'buttons: {buttons}, ' +
             f'window_id: {json.dumps(self.window_id)})'))


class TextInputAlert:
    """A modal alert with a text input accessory.

    :param title: The title, shown in bold at the top.
    :param subtitle: The informative text, which may be more than one line
        long.
    :param placeholder: Grayed-out text to show in the text field when it is
        empty.
    :param default_value: Default text to place in the text field.
    :param window_id: Window ID to attach to, or None to make app-modal.
    """
    # pylint: disable=too-many-arguments
    def __init__(
            self,
            title: str,
            subtitle: str,
            placeholder: str,
            default_value: str,
            window_id: typing.Optional[str] = None):
        self.__title = title
        self.__subtitle = subtitle
        self.__placeholder = placeholder
        self.__default_value = default_value
        self.__window_id = window_id
    # pylint: enable=too-many-arguments

    @property
    def title(self) -> str:
        """Returns the title string"""
        return self.__title

    @property
    def subtitle(self) -> str:
        """Returns the subtitle string"""
        return self.__subtitle

    @property
    def placeholder(self) -> str:
        """Returns the placeholder string"""
        return self.__placeholder

    @property
    def default_value(self) -> str:
        """Returns the default value."""
        return self.__default_value

    # pylint: disable=invalid-name
    @property
    def defaultValue(self) -> str:
        """Deprecated in favor of default_valuedefault_value"""
        return self.__default_value
    # pylint: enable=invalid-name

    @property
    def window_id(self) -> typing.Optional[str]:
        """Returns the window ID"""
        return self.__window_id

    async def async_run(
            self,
            connection: iterm2.connection.Connection) -> typing.Optional[str]:
        """Shows the modal alert.

        :param connection: The connection to use.
        :returns: The string entered, or None if the alert was canceled.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        title = json.dumps(self.title)
        subtitle = json.dumps(self.subtitle)
        placeholder = json.dumps(self.placeholder)
        default_value = json.dumps(self.default_value)

        return await iterm2.async_invoke_function(
            connection,
            (f'iterm2.get_string(title: {title}, ' +
             f'subtitle: {subtitle}, ' +
             f'placeholder: {placeholder}, ' +
             f'defaultValue: {default_value}, ' +
             f'window_id: {json.dumps(self.window_id)})'))
