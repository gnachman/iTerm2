"""Defines interfaces for accessing menu items."""

class MenuItemState:
    """Describes the current state of a menu item.

    There are two properties:

    `checked`: Is there a check mark next to the menu item?
    `enabled`: Is the menu item selectable?
    """
    def __init__(self, checked, enabled):
        self.checked = checked
        self.enabled = enabled

class MainMenu:
    @staticmethod
    async def async_select_menu_item(connection, identifier):
        """Selects a menu item.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`

        :throws MenuItemException: if something goes wrong.
        """
        response = await iterm2.rpc.async_menu_item(connection, identifier, False)
        status = response.menu_item_response.status
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(iterm2.api_pb2.MenuItemResponse.Status.Name(status))

    @staticmethod
    async def async_get_menu_item_state(connection, identifier):
        """Queries a menu item for its state.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`
        :returns: :class:`App.MenuItemState`

        :throws MenuItemException: if something goes wrong.
        """
        response = await iterm2.rpc.async_menu_item(connection, identifier, True)
        status = response.menu_item_response.status
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(iterm2.api_pb2.MenuItemResponse.Status.Name(status))
        return iterm2.App.MenuItemState(response.menu_item_response.checked,
                                        response.menu_item_response.enabled)

