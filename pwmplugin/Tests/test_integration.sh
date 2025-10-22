#!/bin/bash

set -e

echo "Testing all password manager commands..."

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

# Export the database path
export KEEPASSXC_DATABASE="$TEST_DB"

# Login to get the token
echo "1. Testing login..."
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
echo "✓ Login successful"

# Test add-account
echo "2. Testing add-account..."
ADD_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "userName": "testuser",
  "accountName": "TestAccount",
  "password": "initialPassword123"
}'
ADD_OUTPUT=$(echo "$ADD_INPUT" | ../iterm2-keepassxc-adapter add-account 2>/dev/null)
ACCOUNT_ID=$(echo "$ADD_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['accountIdentifier']['accountID'])" 2>/dev/null)

if [ -z "$ACCOUNT_ID" ]; then
    echo "ERROR: Failed to get account ID from add-account"
    rm -f "$TEST_DB"
    exit 1
fi
echo "✓ Add-account successful, account ID: $ACCOUNT_ID"

# Test list-accounts (should show the new account)
echo "3. Testing list-accounts..."
LIST_OUTPUT=$(echo '{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'"
}' | ../iterm2-keepassxc-adapter list-accounts 2>/dev/null)
ACCOUNT_COUNT=$(echo "$LIST_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data['accounts']))" 2>/dev/null)

if [ "$ACCOUNT_COUNT" -lt 1 ]; then
    echo "ERROR: Expected at least 1 account, got $ACCOUNT_COUNT"
    rm -f "$TEST_DB"
    exit 1
fi
echo "✓ List-accounts successful, found $ACCOUNT_COUNT account(s)"

# Test get-password (should return initialPassword123)
echo "4. Testing get-password..."
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
PASSWORD=$(echo "$GET_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('password', ''))" 2>/dev/null)

if [ "$PASSWORD" != "initialPassword123" ]; then
    echo "ERROR: Expected password 'initialPassword123', got '$PASSWORD'"
    rm -f "$TEST_DB"
    exit 1
fi
echo "✓ Get-password successful, password matches"

# Test set-password
echo "5. Testing set-password..."
SET_INPUT='{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "accountIdentifier": {
    "accountID": "'"$ACCOUNT_ID"'"
  },
  "newPassword": "updatedPassword456"
}'
SET_OUTPUT=$(echo "$SET_INPUT" | ../iterm2-keepassxc-adapter set-password 2>/dev/null)

if ! echo "$SET_OUTPUT" | python3 -m json.tool > /dev/null 2>&1; then
    echo "ERROR: set-password returned invalid JSON"
    rm -f "$TEST_DB"
    exit 1
fi
echo "✓ Set-password successful"

# Verify password was changed
echo "6. Verifying password change..."
GET_OUTPUT2=$(echo "$GET_INPUT" | ../iterm2-keepassxc-adapter get-password 2>/dev/null)
NEW_PASSWORD=$(echo "$GET_OUTPUT2" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('password', ''))" 2>/dev/null)

if [ "$NEW_PASSWORD" != "updatedPassword456" ]; then
    echo "ERROR: Expected updated password 'updatedPassword456', got '$NEW_PASSWORD'"
    rm -f "$TEST_DB"
    exit 1
fi
echo "✓ Password change verified"

# Test delete-account
echo "7. Testing delete-account..."
DELETE_INPUT='{
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
DELETE_OUTPUT=$(echo "$DELETE_INPUT" | ../iterm2-keepassxc-adapter delete-account 2>/dev/null)

if ! echo "$DELETE_OUTPUT" | python3 -m json.tool > /dev/null 2>&1; then
    echo "ERROR: delete-account returned invalid JSON"
    rm -f "$TEST_DB"
    exit 1
fi
echo "✓ Delete-account successful"

# Verify account was deleted (moved to recycle bin)
echo "8. Verifying account deletion..."
LIST_OUTPUT2=$(echo '{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'"
}' | ../iterm2-keepassxc-adapter list-accounts 2>/dev/null)

# Check that the original account ID is not in the root anymore
# It should be in the Recycle Bin now
if echo "$LIST_OUTPUT2" | grep -q '"accountID" : "'"$ACCOUNT_ID"'"'; then
    # The account is still there by exact ID match, but it might be in Recycle Bin
    # Check if it's in the recycle bin path
    if ! echo "$LIST_OUTPUT2" | grep -q "Recycle Bin/$ACCOUNT_ID"; then
        echo "ERROR: Account was not moved to recycle bin"
        rm -f "$TEST_DB"
        exit 1
    fi
fi
echo "✓ Account deletion verified (moved to recycle bin)"

echo ""
echo "✓✓✓ All tests passed! ✓✓✓"

# Clean up
rm -f "$TEST_DB"
