"""Enables showing modal alerts."""

import iterm2.connection
import json
import typing

class Alert:
    """A modal alert.

    :param title: The title, shown in bold at the top.
    :param subtitle: The informative text, which may be more than one line long.

    .. seealso:: Example ":ref:`oneshot_example`"
    """
    def __init__(self, title, subtitle):
        self.__title = title
        self.__subtitle = subtitle
        self.__buttons = []

    @property
    def title(self) -> str:
        return self.__title

    @property
    def subtitle(self) -> str:
        return self.__subtitle

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
                'iterm2.alert(title: {}, subtitle: {}, buttons: {})'.format(
                    title, subtitle, buttons))

class TextInputAlert:
    """A modal alert with a text input accessory.

    :param title: The title, shown in bold at the top.
    :param subtitle: The informative text, which may be more than one line long.
    :param placeholder: Grayed-out text to show in the text field when it is empty.
    :param defaultValue: Default text to place in the text field.
    """
    def __init__(self, title: str, subtitle: str, placeholder: str, defaultValue: str):
        self.__title = title
        self.__subtitle = subtitle
        self.__placeholder = placeholder
        self.__defaultValue = defaultValue

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
                f'iterm2.get_string(title: {title}, subtitle: {subtitle}, placeholder: {placeholder}, defaultValue: {defaultValue})')

