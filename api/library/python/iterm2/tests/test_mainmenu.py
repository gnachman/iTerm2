"""Tests for the menu item enums in iterm2.mainmenu."""
import warnings

import iterm2
from iterm2.mainmenu import MainMenu


def test_nested_submenu_items_are_reachable():
    """A submenu nested in a menu is reached as an attribute of that menu."""
    item = MainMenu.Shell.Archives.SAVE_ARCHIVE_OF_CURRENT_SESSION

    assert isinstance(item, MainMenu.Shell.Archives)
    assert item.value.identifier == "Save Archive of Current Session"


def test_submenus_are_not_members_of_their_parent_menu():
    """Iterating a menu yields only its own items, never a nested submenu."""
    members = list(MainMenu.Shell)

    assert members
    assert all(isinstance(m.value, iterm2.MenuItemIdentifier) for m in members)
    assert "Archives" not in MainMenu.Shell.__members__


def test_nested_submenus_do_not_warn():
    """Defining the menus doesn't trigger Python's nested-enum deprecation."""
    import importlib

    import iterm2.mainmenu

    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        importlib.reload(iterm2.mainmenu)

    assert not [w for w in caught if "inside an enum" in str(w.message)]
