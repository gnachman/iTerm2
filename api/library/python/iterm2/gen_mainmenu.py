#!/usr/bin/env python3

import string
import xml.etree.ElementTree as ET

def search_container(path, container, f):
    if container is None:
        return
    for item in container.findall("menuItem"):
        if "isSeparatorItem" in item.attrib:
            continue
        menu = item.find("menu")
        title = item.attrib["title"]
        this_path = path + [title]
        if menu is not None:
            search_container(this_path, menu.find("items"), f)
        else:
            try:
                identifier = item.attrib["identifier"]
                f(this_path, identifier)
            except:
                print("Bogus item: {}".format(item.attrib), file=sys.stderr)
                raise


class RemoveNonAlphanumeric:
  def __init__(self, keep=string.digits + string.ascii_letters + "_"):
    self.comp = dict((ord(c),c) for c in keep)
  def __getitem__(self, k):
    return self.comp.get(k)


def gen_menu_items_impl(items):
    tree = {}
    def build_tree(titlepath, identifier):
        current = tree
        for child in titlepath[:-1]:
            if child not in current:
                current[child] = {}
            current = current[child]
        current[titlepath[-1]] = (titlepath[-1], identifier)
    search_container([], items, build_tree)

    def emit(node, depth=1):
        needsNewline = False
        for k in node:
            v = node[k]
            if isinstance(v, dict):
                if needsNewline:
                    yield ""
                yield f'{"    " * depth}class {k.translate(RemoveNonAlphanumeric())}(enum.Enum):'
                for line in emit(v, depth+1):
                    yield line
                yield ""
            else:
                needsNewline = True
                yield f'{"    " * depth}{k.upper().replace(" ", "_").translate(RemoveNonAlphanumeric())} = MenuItemIdentifier("{v[0]}", "{v[1]}")'

    result = []
    for line in emit(tree):
        result.append(line)
    return "\n".join(result)

def items():
    tree = ET.parse("../../../../Interfaces/MainMenu.xib")
    items = tree.getroot().find("objects").find("menu").find("items")
    return items

def gen_menu_items():
    return gen_menu_items_impl(items())

print(
"""\"\"\"Defines interfaces for accessing menu items.\"\"\"
import enum
import iterm2.api_pb2
import iterm2.rpc
import typing

class MenuItemException(Exception):
    \"\"\"A problem was encountered while selecting a menu item.\"\"\"


class MenuItemState:
    \"\"\"Describes the current state of a menu item.\"\"\"
    def __init__(self, checked: bool, enabled: bool):
        self.__checked = checked
        self.__enabled = enabled

    @property
    def checked(self):
        \"\"\"Is the menu item checked? A `bool` property.\"\"\"
        return self.__checked

    @property
    def enabled(self):
        \"\"\"
        Is the menu item enabled (i.e., it can be selected)? A `bool`
        property.
        \"\"\"
        return self.__enabled

class MenuItemIdentifier:
    def __init__(self, title, identifier):
        self.__title = title
        self.__identifier = identifier

    def __repr__(self):
        return f'[MenuItemIdentifier title={self.title} id={self.identifier}]'

    @property
    def title(self) -> str:
        return self.__title

    @property
    def identifier(self) -> typing.Optional[str]:
        return self.__identifier

    def _encode(self):
        # Encodes to a key binding parameter.
        if self.__identifier is None:
            return self.__title
        return self.__title + "\\n" + self.__identifier

class MainMenu:
    \"\"\"Represents the app's main menu.\"\"\"

    @staticmethod
    async def async_select_menu_item(connection, identifier: str):
        \"\"\"Selects a menu item.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`

        :throws MenuItemException: if something goes wrong.

        .. seealso:: Example ":ref:`zoom_on_screen_example`"
        \"\"\"
        response = await iterm2.rpc.async_menu_item(
            connection, identifier, False)
        status = response.menu_item_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(
                iterm2.api_pb2.MenuItemResponse.Status.Name(status))

    @staticmethod
    async def async_get_menu_item_state(
            connection, identifier: str) -> MenuItemState:
        \"\"\"Queries a menu item for its state.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`

        :throws MenuItemException: if something goes wrong.
        \"\"\"
        response = await iterm2.rpc.async_menu_item(
            connection, identifier, True)
        status = response.menu_item_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(
                iterm2.api_pb2.MenuItemResponse.Status.Name(status))
        return iterm2.MenuItemState(
            response.menu_item_response.checked,
            response.menu_item_response.enabled)

""" + gen_menu_items())
