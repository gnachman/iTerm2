"""Enables showing modal alerts."""

import iterm2.connection
import json
import typing

class Alert:
    """A modal alert.

    :param title: The title, shown in bold at the top.
    :param subtitle: The informative text, which may be more than one line long.
    :param window_id: The window to attach the alert to. If None, it will be application modal.

    .. seealso:: Example ":ref:`oneshot_example`"
    """
    def __init__(self, title: str, subtitle: str, window_id: typing.Optional[str]=None):
        self.__title = title
        self.__subtitle = subtitle
        self.__buttons = []
        self.__window_id = window_id

    @property
    def title(self) -> str:
        return self.__title

    @property
    def subtitle(self) -> str:
        return self.__subtitle

    @property
    def window_id(self) -> str:
        return self.__window_id

    def add_button(self, title: str):
        """Adds a button to the end of the list of buttons."""
        self.__buttons.append(title)

    async def async_run(self, connection: iterm2.connection.Connection) -> int:
        """Shows the modal alert.

        :param connection: The connection to use.
        :returns: The index of the selected button. If no buttons were defined then a single button, "OK", is automatically added.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        title = json.dumps(self.title)
        subtitle = json.dumps(self.subtitle)
        buttons = json.dumps(self.__buttons)

        return await iterm2.async_invoke_function(
                connection,
                f'iterm2.alert(title: {title}, subtitle: {subtitle}, buttons: {buttons}, window_id: {json.dumps(self.window_id)})')

class TextInputAlert:
    """A modal alert with a text input accessory.

    :param title: The title, shown in bold at the top.
    :param subtitle: The informative text, which may be more than one line long.
    :param placeholder: Grayed-out text to show in the text field when it is empty.
    :param defaultValue: Default text to place in the text field.
    """
    def __init__(self, title: str, subtitle: str, placeholder: str, defaultValue: str, window_id: typing.Optional[str]=None):
        self.__title = title
        self.__subtitle = subtitle
        self.__placeholder = placeholder
        self.__defaultValue = defaultValue
        self.__window_id = window_id

    @property
    def title(self) -> str:
        return self.__title

    @property
    def subtitle(self) -> str:
        return self.__subtitle

    @property
    def placeholder(self) -> str:
        return self.__placeholder

    @property
    def defaultValue(self) -> str:
        return self.__defaultValue

    @property
    def window_id(self) -> str:
        return self.__window_id

    async def async_run(self, connection: iterm2.connection.Connection) -> typing.Optional[str]:
        """Shows the modal alert.

        :param connection: The connection to use.
        :returns: The string entered, or None if the alert was canceled.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        title = json.dumps(self.title)
        subtitle = json.dumps(self.subtitle)
        placeholder = json.dumps(self.placeholder)
        defaultValue = json.dumps(self.defaultValue)

        return await iterm2.async_invoke_function(
                connection,
                f'iterm2.get_string(title: {title}, subtitle: {subtitle}, placeholder: {placeholder}, defaultValue: {defaultValue}, window_id: {json.dumps(self.window_id)})')

