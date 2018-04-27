#!/bin/bash
# Usage: it2_api_wrapper.sh path_to_pyenv script.py
set -x
unset PYTHONPATH
export PYTHONUNBUFFERED=1
"$1" "$2"
