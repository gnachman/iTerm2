"""Tests for the public interface declared in iterm2/__init__.py."""

import ast
from pathlib import Path

import iterm2


def _imported_names():
    """Returns the names __init__.py imports from the package's modules."""
    tree = ast.parse(Path(iterm2.__file__).read_text())
    return [
        alias.asname or alias.name
        for node in tree.body
        if isinstance(node, ast.ImportFrom) and node.module != "__future__"
        for alias in node.names
    ]


def test_all_lists_exactly_the_imported_names():
    """A name imported but missing from __all__ looks private to type
    checkers, and one listed but not imported breaks star imports."""
    imported = _imported_names()

    assert sorted(set(iterm2.__all__)) == sorted(set(imported))


def test_all_has_no_duplicates():
    assert len(iterm2.__all__) == len(set(iterm2.__all__))


def test_every_name_in_all_is_defined():
    missing = [name for name in iterm2.__all__ if not hasattr(iterm2, name)]

    assert missing == []
