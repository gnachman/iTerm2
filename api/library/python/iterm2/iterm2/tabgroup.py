"""Provides a class that represents an iTerm2 tab group."""
import typing

import iterm2.capabilities
import iterm2.color
import iterm2.rpc
import iterm2.util


class TabGroup:
    """Represents a tab group.

    A tab group is a named, colored collection of adjacent tabs in a window.
    Its members are always kept consecutive in the tab bar: iTerm2 reorders
    tabs as needed to maintain that invariant when membership changes.

    A group may be nested in another group (one level deep): its
    :attr:`parent_group_id` names the parent, and its tabs are kept consecutive
    inside the parent's tabs. A parent group's members include its sub-groups'
    tabs, so collapsing, renaming, or recoloring applies per level.

    Don't create this yourself. Instead, get one from :attr:`iterm2.Tab.tab_group`
    or :attr:`iterm2.Window.tab_groups`, or create one with
    :meth:`iterm2.Window.async_create_tab_group`.

    The `name`, `color`, and `collapsed` values reflect the state at the time
    this object was fetched. After a mutation, re-fetch the app to observe the
    updated state.
    """

    def __init__(
            self,
            connection,
            group_id: str,
            name: str,
            color: typing.Optional[iterm2.color.Color],
            collapsed: bool,
            parent_group_id: typing.Optional[str] = None):
        self.connection = connection
        self.__group_id = group_id
        self.__name = name
        self.__color = color
        self.__collapsed = collapsed
        self.__parent_group_id = parent_group_id

    def __repr__(self):
        return "<TabGroup id=%s name=%s>" % (self.__group_id, repr(self.__name))

    def __eq__(self, other):
        if not isinstance(other, TabGroup):
            return NotImplemented
        return self.__group_id == other.group_id

    def __hash__(self):
        return hash(self.__group_id)

    @property
    def group_id(self) -> str:
        """
        A tab group's unique identifier.

        The identity is stable: it travels with the group's tabs, even if they
        are dragged to another window.

        :returns: The group's identifier, a string.
        """
        return self.__group_id

    @property
    def name(self) -> str:
        """
        :returns: The group's name, as shown in its tab-bar chip.
        """
        return self.__name

    @property
    def color(self) -> typing.Optional[iterm2.color.Color]:
        """
        :returns: The group's color, or `None` if it has none.
        """
        return self.__color

    @property
    def collapsed(self) -> bool:
        """
        :returns: Whether the group is collapsed (its members hidden in the tab
            bar).
        """
        return self.__collapsed

    @property
    def parent_group_id(self) -> typing.Optional[str]:
        """
        The identifier of the group this one is nested in, or `None` for a
        top-level group.

        Tab groups nest one level deep, so a parent never has a parent. Create
        a sub-group with :meth:`iterm2.Window.async_create_tab_group` and its
        `parent` argument.

        :returns: The parent group's identifier, or `None`.
        """
        return self.__parent_group_id

    async def async_set_name(self, name: str) -> None:
        """
        Renames the group. The new name applies to every member tab.

        :param name: The new name.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        iterm2.capabilities.check_supports_tab_groups(self.connection)
        invocation = iterm2.util.invocation_string(
            "iterm2.set_tab_group_name",
            {"group_id": self.__group_id, "name": name})
        await iterm2.rpc.async_invoke_app_function(self.connection, invocation)

    async def async_set_color(self, color: iterm2.color.Color) -> None:
        """
        Changes the group's color. The new color applies to every member tab.

        :param color: The new color.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        iterm2.capabilities.check_supports_tab_groups(self.connection)
        invocation = iterm2.util.invocation_string(
            "iterm2.set_tab_group_color",
            {"group_id": self.__group_id, "color": color.hex})
        await iterm2.rpc.async_invoke_app_function(self.connection, invocation)

    async def async_set_collapsed(self, collapsed: bool) -> bool:
        """
        Collapses or expands the group.

        Collapsing hides the group's members in the tab bar. It can be refused
        when the group comprises the entire window (there would be no tab left
        to select), in which case this returns `False`.

        :param collapsed: `True` to collapse, `False` to expand.

        :returns: The group's collapsed state after the change.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        iterm2.capabilities.check_supports_tab_groups(self.connection)
        invocation = iterm2.util.invocation_string(
            "iterm2.set_tab_group_collapsed",
            {"group_id": self.__group_id, "collapsed": 1 if collapsed else 0})
        return await iterm2.rpc.async_invoke_app_function(
            self.connection, invocation)
