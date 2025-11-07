"""Enables showing modal alerts."""
import json
import typing
from dataclasses import dataclass
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
        :returns: The index of the selected button, plus 1000. If no buttons
        were defined
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
    # pylint: disable=too-many-positional-arguments
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


@dataclass
class PolyModalResult:
    """Dedicated object to return for PolyModalAlert """
    button: typing.Optional[str] = None
    tf_text: typing.Optional[str] = None
    combo: typing.Optional[str] = None
    checks: typing.Optional[typing.List[str]] = None


class PolyModalAlert:
    """A modal alert with various UI options

    :param title: The title, shown in bold at the top.
    :param subtitle: The informative text, which may be more than one line
        long.
    :param window_id: The window to attach the alert to. If None, it will be
        application modal."
    """

    # pylint: disable=too-many-instance-attributes

    def __init__(
            self,
            title: str,
            subtitle: str,
            window_id: typing.Optional[str] = None):
        self.__title: str = title
        self.__subtitle: str = subtitle
        self.__buttons: typing.List[str] = []
        self.__checkboxes: typing.List[str] = []
        self.__checkbox_defaults: typing.List[int] = []
        self.__combobox_items: typing.List[str] = []
        self.__combobox_default: str = ""
        self.__text_field: typing.List[str] = []
        self.__width: int = 300
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
    def text_field(self) -> typing.List[str]:
        """Returns the text field list [placeholder, default] """
        return self.__text_field

    @property
    def checkboxes(self) -> typing.List[str]:
        """Returns a list of checkbox strings """
        return self.__checkboxes

    @property
    def checkbox_defaults(self) -> typing.List[int]:
        """Returns a list of whether checkboxes are checked by default """
        return self.__checkbox_defaults

    @property
    def combobox_items(self) -> typing.List[str]:
        """Returns the list of strings that will populate the combobox."""
        return self.__combobox_items

    @property
    def combobox_default(self) -> str:
        """Returns the combox item that is initially chosen."""
        return self.__combobox_default

    @property
    def window_id(self) -> typing.Optional[str]:
        """Returns the window ID."""
        return self.__window_id

    @property
    def width(self) -> int:
        """The width of the alert modal."""
        return self.__width

    @width.setter
    def width(self, value: int):
        """Set the width of the model."""
        self.__width = value

    def add_button(self, title: str):
        """Adds a button to the end of the list of buttons."""
        self.__buttons.append(title)

    def add_checkboxes(self, items: typing.List[str],
                       defaults: typing.List[int]):
        """Adds an array of checkbox items to the end of the list of
        checkboxes.
        Parameters
        ----------
        items : List[str]
            A list of labels for the checkboxes to add.
        defaults : List[int]
            A list of default values (e.g., 0 or 1) indicating whether each
            checkbox is initially checked.
            Must have the same length as `items`.

        Raises
        ------
        AssertionError
            If `items` and `defaults` do not have the same length.
        """
        assert len(items) == len(
            defaults), "items and defaults must have the same length."
        for item_text, default in zip(items, defaults):
            self.__checkbox_defaults.append(default)
            self.__checkboxes.append(item_text)

    def add_checkbox_item(self, item_text: str, item_default: int = 0):
        """
        Adds a single checkbox item to the end of the list of checkboxes.

        Parameters
        ----------
        item_text : str
            The label for the checkbox.
        item_default : int, optional
            The default value of the checkbox (0 for unchecked,
            1 for checked). Default is 0.
        """
        self.__checkbox_defaults.append(item_default)
        self.__checkboxes.append(item_text)

    def add_combobox(self, items: typing.List[str], default: str = None):
        """
        Adds multiple items to the combobox list and sets the default value.

        Parameters
        ----------
        items : List[str]
            A list of strings to add to the combobox.
        default : str, optional
            The default value for the combobox. If empty, no default is set.

        Raises
        ------
        AssertionError
            If `default ` is not present in items.
        """
        if default is not None:
            assert default in items, "default must be present in items"
            self.__combobox_default = default
        for item_text in items:
            self.__combobox_items.append(item_text)

    def set_combobox_items(self, items: typing.List[str], default_index: int):
        """
        Sets (or replaces) the combobox items with a list and sets the
        default by index.

        Parameters
        ----------
        items : List[str]
            A list of strings to set as the combobox items.
        default_index : int
            The index of the item in `items` to set as the default. Must be
            within the list range.

        Raises
        ------
        AssertionError
            If `default_index` is out of range of the items list.
        """
        assert default_index < len(
            items), (f"default_index {default_index} is out of range for items "
                     f"list of length {len(items)}")
        self.__combobox_default = items[default_index]
        self.__combobox_items = items

    def add_combobox_item(self, item_text: str, is_default: bool = False):
        """
        Adds a single item to the combobox list and optionally sets it as
        default.

        Parameters
        ----------
        item_text : str
            The text of the combobox item to add.
        is_default : bool, optional
            If True, this item becomes the default selection.
        """
        self.__combobox_items.append(item_text)
        if is_default:
            self.__combobox_default = item_text

    def add_text_field(self, placeholder: str, default: str):
        """
        Adds a text field to the alert.

        Parameters
        ----------
        placeholder : str
            The placeholder text to show in the text field.
        default : str
            The default text value of the text field.
        """
        self.__text_field.append(placeholder)
        self.__text_field.append(default)

    async def async_run(self,
                        connection: iterm2.connection.Connection) -> (
            PolyModalResult):
        """Shows the poly modal alert.

        :param connection: The connection to use.
        :returns: A PolyModalResult object containing values corresponding to
        the UI elements that were added
         - the label of clicked button
         - text entered into the field input
         - selected combobox text ('' if combobox was present but nothing
         selected)
         - array of checked checkbox labels.
        If no buttons were defined
            then a single button, "OK", is automatically added
                and "button" will be absent from PolyModalResult.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        # pylint: disable=too-many-locals
        title = json.dumps(self.title)
        subtitle = json.dumps(self.subtitle)
        buttons = json.dumps(self.__buttons)
        checkboxes_list = json.dumps(self.checkboxes)
        checkbox_defaults = json.dumps(self.checkbox_defaults)
        combobox_items = json.dumps(self.combobox_items)
        combobox_default = json.dumps(self.combobox_default)
        text_field = json.dumps(self.text_field)
        width = json.dumps(self.__width)

        result = await iterm2.async_invoke_function(
            connection,
            (f'iterm2.get_poly_modal_alert(title: {title}, ' +
             f'subtitle: {subtitle}, ' +
             f'buttons: {buttons}, ' +
             f'checkboxes: {checkboxes_list}, ' +
             f'checkboxDefaults: {checkbox_defaults}, ' +
             f'comboboxItems: {combobox_items}, ' +
             f'comboboxDefault: {combobox_default}, ' +
             f'textFieldParams: {text_field}, ' +
             f'width: {width}, ' +
             f'window_id: {json.dumps(self.window_id)})'))
        return PolyModalResult(**result)
