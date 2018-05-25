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
            identifier = item.attrib["identifier"]
            f(".".join(this_path), name, identifier)

def prologue():
    print(
"""
Menu Item Identifiers
---------------------

To refer to a menu item you must use its unique identifier. The kind of identifier you use depends on the version of macOS you have.

For macOS 10.12 and newer, identifiers are stable and do not change over time.

On older versions of macOS, you use `Title Paths`_. A title path is a concatenation of menu item titles. This is because of a limitation imposed by the OS.

----------


^^^^^^^^^^^
Identifiers
^^^^^^^^^^^

Use these identifiers for macOS 10.12 and newer:

""")

def titlepath_prologue():
    print("""

----------

^^^^^^^^^^^
Title Paths
^^^^^^^^^^^

Use these title paths for macOS 10.11 and earlier:

""")

def epilogue():
    print("""
----

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
""")

def make_rst(items, mapper, idname):
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
    def measure(_titlepath, _name, _identifier):
        t = mapper(_titlepath, _name, _identifier) 
        name, identifier = t
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

    def rst(_titlepath, _name, _identifier):
        t = mapper(_titlepath, _name, _identifier) 
        name, identifier = t
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
    make_rst(items(), lambda t, n, i: (n, i), "Identifier")
    titlepath_prologue()
    make_rst(items(), lambda t, n, i: (n, t), "Title Path")
    epilogue()

if __name__ == "__main__":
    main()
