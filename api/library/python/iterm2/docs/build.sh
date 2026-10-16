#!/bin/bash
set -x
set -e

# Build in a private venv so the result doesn't depend on whichever
# sphinx-build happens to be on the PATH. Autodoc imports the iterm2 package,
# so its runtime dependencies must be installed too.
VENV="$PWD/.venv"
if [ ! -x "$VENV/bin/sphinx-build" ]; then
    rm -rf "$VENV"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install sphinx sphinx-autodoc-annotation protobuf websockets
fi

rm -rf _build
mkdir _build

./generate_menu_ids.py "$PWD"/../../../../../sources/MainMenu/Base.lproj/MainMenu.xib > menu_ids.rst
make html SPHINXBUILD="$VENV/bin/sphinx-build"

cp _static/css/custom.css _build/html/_static/alabaster.css
cp -R _build/html/* ~/iterm2-website/source/python-api/
