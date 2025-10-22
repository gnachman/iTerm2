#!/bin/bash

set -e

echo "Testing list-accounts command..."

# Create a test database
TEST_DB="test_db.kdbx"
TEST_PASSWORD="test123"

# Clean up any existing test database
rm -f "$TEST_DB"

# Create a new database (password needs to be entered twice)
keepassxc-cli db-create "$TEST_DB" --set-password <<EOF
$TEST_PASSWORD
$TEST_PASSWORD
EOF

# Create iTerm2 folder
keepassxc-cli mkdir "$TEST_DB" iTerm2 <<EOF
$TEST_PASSWORD
EOF

# Add some test entries in iTerm2 folder
keepassxc-cli add -p -u testuser1 "$TEST_DB" iTerm2/TestEntry1 <<EOF
$TEST_PASSWORD
user1pass
user1pass
EOF

keepassxc-cli add -p -u testuser2 "$TEST_DB" iTerm2/TestEntry2 <<EOF
$TEST_PASSWORD
user2pass
user2pass
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

# Now test list-accounts with the token
LIST_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'"
}'
OUTPUT=$(echo "$LIST_INPUT" | ../iterm2-keepassxc-adapter list-accounts 2>/dev/null)

# Check if output is valid JSON
echo "$OUTPUT" | python3 -m json.tool > /dev/null || {
    echo "ERROR: Output is not valid JSON"
    echo "Output was: $OUTPUT"
    rm -f "$TEST_DB"
    exit 1
}

# Check if output contains accounts array
echo "$OUTPUT" | grep -q '"accounts"' || {
    echo "ERROR: Missing accounts field"
    rm -f "$TEST_DB"
    exit 1
}

# Check if we have at least one account
ACCOUNT_COUNT=$(echo "$OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data['accounts']))")

if [ "$ACCOUNT_COUNT" -lt 1 ]; then
    echo "ERROR: Expected at least 1 account, got $ACCOUNT_COUNT"
    rm -f "$TEST_DB"
    exit 1
fi

echo "✓ List-accounts test passed! Found $ACCOUNT_COUNT accounts."

# Clean up
rm -f "$TEST_DB"
