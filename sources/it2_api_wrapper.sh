#!/bin/bash
# Usage: it2_api_wrapper.sh path_to_pyenv script.py
set -x
unset PYTHONPATH
"$1"/versions/*/bin/python "$2"
