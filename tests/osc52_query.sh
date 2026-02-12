#!/bin/bash
# Query clipboard using OSC 52
# The response will be: ESC ] 52 ; c ; <base64-data> ESC \

# Save terminal settings and set raw mode to capture response
old_settings=$(stty -g)
stty raw -echo

# Send OSC 52 query: ESC ] 52 ; c ; ? ST
printf '\e]52;c;?\e\\'

# Read the response with a timeout
response=""
echo "Reading response"
while IFS= read -r -n 1 char; do
    echo "Got a character"
    response+="$char"
    # Check for string terminator (ESC \)
    if [[ "$response" == *$'\e\\' ]]; then
        echo "Read ST"
        break
    fi
    # Also check for BEL terminator
    if [[ "$response" == *$'\a' ]]; then
        echo "Read BEL"
        break
    fi
done

# Restore terminal settings
stty "$old_settings"

# Parse the response - extract base64 data between ; and terminator
if [[ "$response" =~ \]52\;[a-z]\;([A-Za-z0-9+/=]*) ]]; then
    base64_data="${BASH_REMATCH[1]}"
    if [[ -n "$base64_data" ]]; then
        echo "Clipboard contents:"
        echo "$base64_data" | base64 -d
        echo
    else
        echo "Clipboard is empty"
    fi
else
    echo "No response or unsupported terminal"
    echo "Raw response: $response" | cat -v
fi
