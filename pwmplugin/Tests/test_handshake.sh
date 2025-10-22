#!/bin/bash

set -e

echo "Testing handshake command..."

# Create test input
INPUT='{"iTermVersion":"3.5.13","minProtocolVersion":0,"maxProtocolVersion":0}'

# Run the command
OUTPUT=$(echo "$INPUT" | ../iterm2-keepassxc-adapter handshake)

# Check if output is valid JSON
echo "$OUTPUT" | python3 -m json.tool > /dev/null || {
    echo "ERROR: Output is not valid JSON"
    echo "Output was: $OUTPUT"
    exit 1
}

# Check if output contains expected fields
echo "$OUTPUT" | grep -q '"protocolVersion"' || {
    echo "ERROR: Missing protocolVersion field"
    exit 1
}

echo "$OUTPUT" | grep -q '"name"' || {
    echo "ERROR: Missing name field"
    exit 1
}

echo "$OUTPUT" | grep -q '"requiresMasterPassword"' || {
    echo "ERROR: Missing requiresMasterPassword field"
    exit 1
}

echo "$OUTPUT" | grep -q '"canSetPasswords"' || {
    echo "ERROR: Missing canSetPasswords field"
    exit 1
}

# Check specific values
echo "$OUTPUT" | grep -q '"protocolVersion" : 0' || {
    echo "ERROR: protocolVersion should be 0"
    exit 1
}

echo "$OUTPUT" | grep -q '"name" : "KeePassXC"' || {
    echo "ERROR: name should be KeePassXC"
    exit 1
}

echo "$OUTPUT" | grep -q '"requiresMasterPassword" : true' || {
    echo "ERROR: requiresMasterPassword should be true"
    exit 1
}

echo "$OUTPUT" | grep -q '"canSetPasswords" : true' || {
    echo "ERROR: canSetPasswords should be true"
    exit 1
}

echo "✓ Handshake test passed!"
