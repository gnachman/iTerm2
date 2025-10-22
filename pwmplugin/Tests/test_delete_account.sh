#!/bin/bash

set -e

echo "Testing delete-account command..."

# Create a test database
TEST_DB="test_db.kdbx"
TEST_PASSWORD="test123"

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

# Add a test entry in iTerm2 folder
keepassxc-cli add -p -u testuser "$TEST_DB" iTerm2/TestEntry <<EOF
$TEST_PASSWORD
testpass
testpass
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

# Verify the account exists before deletion
LIST_OUTPUT=$(echo '{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'"
}' | ../iterm2-keepassxc-adapter list-accounts 2>/dev/null)
ACCOUNT_COUNT_BEFORE=$(echo "$LIST_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data['accounts']))" 2>/dev/null)

if [ "$ACCOUNT_COUNT_BEFORE" -lt 1 ]; then
    echo "ERROR: Expected at least 1 account before deletion, got $ACCOUNT_COUNT_BEFORE"
    rm -f "$TEST_DB"
    exit 1
fi

# Test delete-account
DELETE_INPUT='{
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
OUTPUT=$(echo "$DELETE_INPUT" | ../iterm2-keepassxc-adapter delete-account 2>/dev/null)

# Check if output is valid JSON
echo "$OUTPUT" | python3 -m json.tool > /dev/null || {
    echo "ERROR: Output is not valid JSON"
    echo "Output was: $OUTPUT"
    rm -f "$TEST_DB"
    exit 1
}

# Verify the account was deleted (moved to recycle bin)
LIST_OUTPUT_AFTER=$(echo '{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'"
}' | ../iterm2-keepassxc-adapter list-accounts 2>/dev/null)

# Since list-accounts filters out Recycle Bin entries, the account should not appear in the list
# Check that iTerm2/TestEntry is no longer in the accounts list
if echo "$LIST_OUTPUT_AFTER" | grep -q '"accountID" : "iTerm2/TestEntry"'; then
    echo "ERROR: Account still appears in list, was not deleted"
    rm -f "$TEST_DB"
    exit 1
fi

# Verify the account count decreased
ACCOUNT_COUNT_AFTER=$(echo "$LIST_OUTPUT_AFTER" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data['accounts']))" 2>/dev/null)

if [ "$ACCOUNT_COUNT_AFTER" -ge "$ACCOUNT_COUNT_BEFORE" ]; then
    echo "ERROR: Account count did not decrease after deletion (before: $ACCOUNT_COUNT_BEFORE, after: $ACCOUNT_COUNT_AFTER)"
    rm -f "$TEST_DB"
    exit 1
fi

echo "✓ Delete-account test passed!"

# Clean up
rm -f "$TEST_DB"
