#!/bin/bash

# Usage: set_profile_property.sh key1 json1 [key2 json2 ...]
# Example: ./set_profile_property.sh "Cursor Type" '2' "Blinking Cursor" 'true'

if [[ $# -lt 2 ]] || [[ $(($# % 2)) -ne 0 ]]; then
    echo "Usage: $0 key1 json1 [key2 json2 ...]" >&2
    exit 1
fi

props=""
while [[ $# -gt 0 ]]; do
    key="$1"
    json="$2"
    encoded=$(echo -n "$json" | base64)
    if [[ -n "$props" ]]; then
        props="${props};"
    fi
    props="${props}${key}=${encoded}"
    shift 2
done

printf '\033]1337;SetProfileProperty=%s\a' "$props"
