#!/usr/bin/env python3
import html
import sys
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
            name = " > ".join(this_path)
            if "identifier" not in item.attrib:
                print("Bogus item: {}".format(item.attrib))
            identifier = item.attrib["identifier"]
            f(".".join(this_path), name, identifier)

def prologue():
    print(
"""
Menu Item Identifiers
---------------------

To refer to a menu item you must use its unique identifier. This table shows the identifier for each menu item.

----------


^^^^^^^^^^^
Identifiers
^^^^^^^^^^^

""")

def epilogue():
    print("""
----

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
""")

def make_rst(items, idname):
    """
    Outputs a table formatted like this:

    ==== ==========
    Name Identifier
    ==== ==========
    N1   ID1
    N2   ID2
    ...
    Nn   IDn
    ==== ==========
    """
    longest_name = 0
    longest_identifier = 0
    def measure(_titlepath, name, identifier):
        nonlocal longest_name
        nonlocal longest_identifier
        longest_name = max(longest_name, len(name))
        longest_identifier = max(longest_identifier, len(identifier))
    search_container([], items, measure)

    divider = "{} {}".format("=" * longest_name, "=" * longest_identifier)
    print(divider)
    fmt = "%-{}s %-{}s".format(longest_name, longest_identifier)
    print(fmt % ("Menu Item", idname))
    print(divider)

    def escape(s):
        return s.replace("'", "\\'").replace("*", "\\*").replace("`", "\\`")

    def rst(_titlepath, name, identifier):
        ticked_identifier = "`{}`".format(escape(identifier))
        print(fmt % (escape(name), ticked_identifier))
    search_container([], items, rst)

    print(divider)

def items():
    tree = ET.parse(sys.argv[1])
    items = tree.getroot().find("objects").find("menu").find("items")
    return items

def main():
    prologue()
    make_rst(items(), "Identifier")
    epilogue()

if __name__ == "__main__":
    main()
