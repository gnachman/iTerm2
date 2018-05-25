#!/bin/bash
set -x
rm -rf _build
mkdir _build

./generate_menu_ids.py "$PWD"/../../../../../Interfaces/MainMenu.xib > menu_ids.rst
make html

cp _static/css/custom.css _build/html/_static/alabaster.css
cp -R _build/html/* ~/iterm2-website/source/python-api/
