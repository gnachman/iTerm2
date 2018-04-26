#!/bin/bash
# Usage: it2_api_wrapper.sh path_to_virtualenv script.py
set -x
unset PYTHONPATH
"$1"/bin/python "$2"

