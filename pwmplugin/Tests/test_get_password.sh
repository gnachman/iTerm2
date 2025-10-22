#!/bin/bash

set -e

echo "Testing get-password command..."

# Create a test database
TEST_DB="test_db.kdbx"
TEST_PASSWORD="test123"
ENTRY_PASSWORD="mySecretPassword456"

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

# Add a test entry with a known password in iTerm2 folder
keepassxc-cli add -p -u testuser1 "$TEST_DB" iTerm2/TestEntry1 <<EOF
$TEST_PASSWORD
$ENTRY_PASSWORD
$ENTRY_PASSWORD
EOF

# Export the database path
export KEEPASSXC_DATABASE="$TEST_DB"

# First, login to get the token
LOGIN_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "masterPassword": "'"$TEST_PASSWORD"'"
}'
LOGIN_OUTPUT=$(echo "$LOGIN_INPUT" | ../iterm2-keepassxc-adapter login 2>/dev/null)

# Extract the token from login output
TOKEN=$(echo "$LOGIN_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('token', ''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get token from login"
    echo "Login output was: $LOGIN_OUTPUT"
    rm -f "$TEST_DB"
    exit 1
fi

# Now test get-password with the token
GET_PASSWORD_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "accountIdentifier": {
    "accountID": "iTerm2/TestEntry1"
  }
}'
OUTPUT=$(echo "$GET_PASSWORD_INPUT" | ../iterm2-keepassxc-adapter get-password 2>/dev/null)

# Check if output is valid JSON
echo "$OUTPUT" | python3 -m json.tool > /dev/null || {
    echo "ERROR: Output is not valid JSON"
    echo "Output was: $OUTPUT"
    rm -f "$TEST_DB"
    exit 1
}

# Check if output contains password field
echo "$OUTPUT" | grep -q '"password"' || {
    echo "ERROR: Missing password field"
    rm -f "$TEST_DB"
    exit 1
}

# Check if the password is correct
RETRIEVED_PASSWORD=$(echo "$OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('password', ''))" 2>/dev/null)

if [ "$RETRIEVED_PASSWORD" != "$ENTRY_PASSWORD" ]; then
    echo "ERROR: Password mismatch. Expected '$ENTRY_PASSWORD', got '$RETRIEVED_PASSWORD'"
    rm -f "$TEST_DB"
    exit 1
fi

echo "✓ Get-password test passed!"

# Clean up
rm -f "$TEST_DB"
