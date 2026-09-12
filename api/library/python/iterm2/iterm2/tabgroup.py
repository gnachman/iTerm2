"""Provides a class for working with native tab groups.

A tab group is a named, colored, collapsible run of tabs in a window's tab bar.
All of a group's tabs live in one window and stay contiguous. A group is
identified by a stable id that rides its member tabs, so it keeps its identity
even as tabs are added or removed.
"""
import typing

import iterm2.api_pb2
import iterm2.color
import iterm2.connection
import iterm2.rpc

# Imported for type hints only; avoids a hard import cycle at module load.
if typing.TYPE_CHECKING:
    import iterm2.tab


class TabGroupException(Exception):
    """A problem occurred in a tab-group request."""


def _color_from_proto(
        proto_color: iterm2.api_pb2.RGBColor) -> iterm2.color.Color:
    return iterm2.color.Color(
        proto_color.red, proto_color.green, proto_color.blue)


def _raise_unless_ok(response: iterm2.api_pb2.ServerOriginatedMessage):
    status = response.tab_group_response.status
    if status != iterm2.api_pb2.TabGroupResponse.Status.Value("OK"):
        raise TabGroupException(
            iterm2.api_pb2.TabGroupResponse.Status.Name(status))


class TabGroup:
    """A native tab group.

    Do not construct this directly. Create one with :meth:`async_create` or
    enumerate existing groups with :meth:`async_list`.
    """
    @staticmethod
    async def async_create(
            connection: 'iterm2.connection.Connection',
            tabs: typing.List['iterm2.tab.Tab'],
            name: str,
            color: typing.Optional[iterm2.color.Color] = None
            ) -> 'TabGroup':
        """Creates a tab group from one or more existing tabs.

        The tabs must all belong to the same window. No modal prompt is shown;
        the name and color are supplied here.

        :param connection: A connection to iTerm2.
        :param tabs: The tabs to place in the group (all in one window).
        :param name: The group's name.
        :param color: An optional :class:`iterm2.color.Color` for the group. A
            palette color is chosen when omitted.

        :returns: The newly created :class:`TabGroup`.

        :raises: :class:`TabGroupException` if the request fails (for example,
            the tabs are in different windows).
        """
        tab_ids = [tab.tab_id for tab in tabs]
        response = await iterm2.rpc.async_create_tab_group(
            connection, tab_ids, name, color)
        _raise_unless_ok(response)
        groups = response.tab_group_response.groups
        if not groups:
            raise TabGroupException("Server returned no group")
        return TabGroup(connection, groups[0])

    @staticmethod
    async def async_list(
            connection: 'iterm2.connection.Connection'
            ) -> typing.List['TabGroup']:
        """Lists every tab group in every window.

        :param connection: A connection to iTerm2.

        :returns: A list of :class:`TabGroup`.
        """
        response = await iterm2.rpc.async_list_tab_groups(connection)
        _raise_unless_ok(response)
        return [TabGroup(connection, group)
                for group in response.tab_group_response.groups]

    def __init__(
            self,
            connection: 'iterm2.connection.Connection',
            proto_group: iterm2.api_pb2.TabGroupResponse.Group):
        self.connection = connection
        self.__update_from_proto(proto_group)

    def __update_from_proto(
            self, proto_group: iterm2.api_pb2.TabGroupResponse.Group):
        self.__group_id = proto_group.group_id
        self.__name = proto_group.name
        self.__window_id = proto_group.window_id
        self.__collapsed = proto_group.collapsed
        self.__tab_ids = list(proto_group.tab_ids)
        if proto_group.HasField("color"):
            self.__color: typing.Optional[iterm2.color.Color] = \
                _color_from_proto(proto_group.color)
        else:
            self.__color = None

    def __repr__(self):
        return "<TabGroup id={} name={} tabs={}>".format(
            self.__group_id, repr(self.__name), self.__tab_ids)

    @property
    def group_id(self) -> str:
        """The group's stable unique identifier."""
        return self.__group_id

    @property
    def name(self) -> str:
        """The group's name."""
        return self.__name

    @property
    def color(self) -> typing.Optional[iterm2.color.Color]:
        """The group's color, or None if it has none."""
        return self.__color

    @property
    def window_id(self) -> str:
        """The id of the window the group lives in."""
        return self.__window_id

    @property
    def collapsed(self) -> bool:
        """Whether the group is currently collapsed."""
        return self.__collapsed

    @property
    def tab_ids(self) -> typing.List[str]:
        """The ids of the group's member tabs, in tab-bar order."""
        return list(self.__tab_ids)

    def __sync_from_response(
            self, response: iterm2.api_pb2.ServerOriginatedMessage):
        _raise_unless_ok(response)
        groups = response.tab_group_response.groups
        if groups:
            self.__update_from_proto(groups[0])
        else:
            # The group dissolved (its last member left).
            self.__tab_ids = []

    async def async_add_tab(self, tab: 'iterm2.tab.Tab'):
        """Adds an existing tab to this group.

        The tab must be in the same window as the group.

        :param tab: The tab to add.

        :raises: :class:`TabGroupException` if the request fails.
        """
        response = await iterm2.rpc.async_assign_tab_to_group(
            self.connection, self.__group_id, tab.tab_id)
        self.__sync_from_response(response)

    async def async_remove_tab(self, tab: 'iterm2.tab.Tab'):
        """Removes a tab from this group.

        :param tab: The tab to remove.

        :raises: :class:`TabGroupException` if the request fails.
        """
        response = await iterm2.rpc.async_remove_tab_from_group(
            self.connection, tab.tab_id)
        self.__sync_from_response(response)

    async def async_set_name(self, name: str):
        """Renames the group.

        :param name: The new name.

        :raises: :class:`TabGroupException` if the request fails.
        """
        response = await iterm2.rpc.async_rename_tab_group(
            self.connection, self.__group_id, name)
        self.__sync_from_response(response)

    async def async_set_color(self, color: iterm2.color.Color):
        """Recolors the group.

        :param color: The new :class:`iterm2.color.Color`.

        :raises: :class:`TabGroupException` if the request fails.
        """
        response = await iterm2.rpc.async_set_tab_group_color(
            self.connection, self.__group_id, color)
        self.__sync_from_response(response)

    async def async_set_collapsed(self, collapsed: bool):
        """Collapses or expands the group.

        Collapsing a group that is the whole window is impossible and raises.

        :param collapsed: True to collapse, False to expand.

        :raises: :class:`TabGroupException` if the request fails.
        """
        response = await iterm2.rpc.async_set_tab_group_collapsed(
            self.connection, self.__group_id, collapsed)
        self.__sync_from_response(response)

    async def async_refresh(self):
        """Reloads this group's membership and definition from iTerm2.

        :raises: :class:`TabGroupException` if the group no longer exists.
        """
        response = await iterm2.rpc.async_get_tab_group_membership(
            self.connection, self.__group_id)
        self.__sync_from_response(response)
