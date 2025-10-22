#!/bin/bash

set -e

echo "Testing set-password command..."

# Create a test database
TEST_DB="test_db.kdbx"
TEST_PASSWORD="test123"
INITIAL_PASSWORD="initialPass123"
NEW_PASSWORD="updatedPass456"

# Clean up any existing test database
rm -f "$TEST_DB"

# Create a new database
keepassxc-cli db-create "$TEST_DB" --set-password <<EOF
$TEST_PASSWORD
$TEST_PASSWORD
EOF

# Create iTerm2 folder
keepassxc-cli mkdir "$TEST_DB" iTerm2 <<EOF
$TEST_PASSWORD
EOF

# Add a test entry with initial password in iTerm2 folder
keepassxc-cli add -p -u testuser "$TEST_DB" iTerm2/TestEntry <<EOF
$TEST_PASSWORD
$INITIAL_PASSWORD
$INITIAL_PASSWORD
EOF

# Export the database path
export KEEPASSXC_DATABASE="$TEST_DB"

# Login to get the token
LOGIN_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "masterPassword": "'"$TEST_PASSWORD"'"
}'
LOGIN_OUTPUT=$(echo "$LOGIN_INPUT" | ../iterm2-keepassxc-adapter login 2>/dev/null)
TOKEN=$(echo "$LOGIN_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('token', ''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get token from login"
    rm -f "$TEST_DB"
    exit 1
fi

# Test set-password
SET_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "accountIdentifier": {
    "accountID": "iTerm2/TestEntry"
  },
  "newPassword": "'"$NEW_PASSWORD"'"
}'
OUTPUT=$(echo "$SET_INPUT" | ../iterm2-keepassxc-adapter set-password 2>/dev/null)

# Check if output is valid JSON
echo "$OUTPUT" | python3 -m json.tool > /dev/null || {
    echo "ERROR: Output is not valid JSON"
    echo "Output was: $OUTPUT"
    rm -f "$TEST_DB"
    exit 1
}

# Verify the password was actually changed
GET_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "accountIdentifier": {
    "accountID": "iTerm2/TestEntry"
  }
}'
GET_OUTPUT=$(echo "$GET_INPUT" | ../iterm2-keepassxc-adapter get-password 2>/dev/null)
RETRIEVED_PASSWORD=$(echo "$GET_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('password', ''))" 2>/dev/null)

if [ "$RETRIEVED_PASSWORD" != "$NEW_PASSWORD" ]; then
    echo "ERROR: Password was not updated. Expected '$NEW_PASSWORD', got '$RETRIEVED_PASSWORD'"
    rm -f "$TEST_DB"
    exit 1
fi

echo "✓ Set-password test passed!"

# Clean up
rm -f "$TEST_DB"
