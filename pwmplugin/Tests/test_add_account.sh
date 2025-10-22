#!/bin/bash

set -e

echo "Testing add-account command..."

# Create a test database
TEST_DB="test_db.kdbx"
TEST_PASSWORD="test123"
ENTRY_PASSWORD="newEntryPass789"

# Clean up any existing test database
rm -f "$TEST_DB"

# Create a new database
keepassxc-cli db-create "$TEST_DB" --set-password <<EOF
$TEST_PASSWORD
$TEST_PASSWORD
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

# Test add-account
ADD_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "userName": "newuser",
  "accountName": "NewTestAccount",
  "password": "'"$ENTRY_PASSWORD"'"
}'
OUTPUT=$(echo "$ADD_INPUT" | ../iterm2-keepassxc-adapter add-account 2>/dev/null)

# Check if output is valid JSON
echo "$OUTPUT" | python3 -m json.tool > /dev/null || {
    echo "ERROR: Output is not valid JSON"
    echo "Output was: $OUTPUT"
    rm -f "$TEST_DB"
    exit 1
}

# Check if output contains accountIdentifier
echo "$OUTPUT" | grep -q '"accountIdentifier"' || {
    echo "ERROR: Missing accountIdentifier field"
    rm -f "$TEST_DB"
    exit 1
}

# Extract the account ID
ACCOUNT_ID=$(echo "$OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['accountIdentifier']['accountID'])" 2>/dev/null)

if [ -z "$ACCOUNT_ID" ]; then
    echo "ERROR: Account ID is empty"
    rm -f "$TEST_DB"
    exit 1
fi

# Verify the account was actually added by trying to retrieve its password
GET_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "accountIdentifier": {
    "accountID": "'"$ACCOUNT_ID"'"
  }
}'
GET_OUTPUT=$(echo "$GET_INPUT" | ../iterm2-keepassxc-adapter get-password 2>/dev/null)
RETRIEVED_PASSWORD=$(echo "$GET_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('password', ''))" 2>/dev/null)

if [ "$RETRIEVED_PASSWORD" != "$ENTRY_PASSWORD" ]; then
    echo "ERROR: Retrieved password doesn't match. Expected '$ENTRY_PASSWORD', got '$RETRIEVED_PASSWORD'"
    rm -f "$TEST_DB"
    exit 1
fi

echo "✓ Add-account test passed!"

# Clean up
rm -f "$TEST_DB"
