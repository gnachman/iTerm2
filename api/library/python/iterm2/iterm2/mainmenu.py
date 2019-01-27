"""Defines interfaces for accessing menu items."""
import iterm2.api_pb2
import iterm2.rpc

class MenuItemException(Exception):
    """A problem was encountered while selecting a menu item."""
    pass

class MenuItemState:
    """Describes the current state of a menu item."""
    def __init__(self, checked: bool, enabled: bool):
        self.__checked = checked
        self.__enabled = enabled

    @property
    def checked(self):
        """Is the menu item checked? A `bool` property."""
        return self.__checked

    @property
    def enabled(self):
        """Is the menu item enabled (i.e., it can be selected)? A `bool` property."""
        return self.__enabled

class MainMenu:
    @staticmethod
    async def async_select_menu_item(connection, identifier: str):
        """Selects a menu item.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`

        :throws MenuItemException: if something goes wrong.

        .. seealso:: Example ":ref:`zoom_on_screen_example`"
        """
        response = await iterm2.rpc.async_menu_item(connection, identifier, False)
        status = response.menu_item_response.status
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(iterm2.api_pb2.MenuItemResponse.Status.Name(status))

    @staticmethod
    async def async_get_menu_item_state(connection, identifier: str) -> MenuItemState:
        """Queries a menu item for its state.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`

        :throws MenuItemException: if something goes wrong.
        """
        response = await iterm2.rpc.async_menu_item(connection, identifier, True)
        status = response.menu_item_response.status
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(iterm2.api_pb2.MenuItemResponse.Status.Name(status))
        return iterm2.MenuItemState(
                response.menu_item_response.checked,
                response.menu_item_response.enabled)

