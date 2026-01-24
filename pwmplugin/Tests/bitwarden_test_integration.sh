#!/bin/bash

set -e

echo "Testing all Bitwarden password manager commands..."

# BW_TEST_PASSWORD should be set by the runner script
if [ -z "$BW_TEST_PASSWORD" ]; then
    echo "ERROR: BW_TEST_PASSWORD not set"
    exit 1
fi

# Generate unique test account name to avoid conflicts
TEST_ACCOUNT_NAME="iTerm2-Test-$(date +%s)"

# Lock the vault first
bw lock > /dev/null 2>&1 || true

# Login to get the token
echo "1. Testing login..."
LOGIN_INPUT='{
  "header": {
    "mode": "terminal"
  },
  "masterPassword": "'"$BW_TEST_PASSWORD"'"
}'
LOGIN_OUTPUT=$(echo "$LOGIN_INPUT" | ../iterm2-bitwarden-adapter login 2>/dev/null)
TOKEN=$(echo "$LOGIN_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('token', ''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get token from login"
    echo "Output: $LOGIN_OUTPUT"
    exit 1
fi
echo "✓ Login successful"

# Test add-account
echo "2. Testing add-account..."
ADD_INPUT='{
  "header": {
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "userName": "testuser",
  "accountName": "'"$TEST_ACCOUNT_NAME"'",
  "password": "initialPassword123"
}'
ADD_OUTPUT=$(echo "$ADD_INPUT" | ../iterm2-bitwarden-adapter add-account 2>/dev/null)

# Check for errors
if echo "$ADD_OUTPUT" | grep -q '"error"'; then
    echo "ERROR: add-account failed"
    echo "Output: $ADD_OUTPUT"
    exit 1
fi

ACCOUNT_ID=$(echo "$ADD_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['accountIdentifier']['accountID'])" 2>/dev/null)

if [ -z "$ACCOUNT_ID" ]; then
    echo "ERROR: Failed to get account ID from add-account"
    echo "Output: $ADD_OUTPUT"
    exit 1
fi
echo "✓ Add-account successful, account ID: $ACCOUNT_ID"

# Test list-accounts (should show the new account)
echo "3. Testing list-accounts..."
LIST_OUTPUT=$(echo '{
  "header": {
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'"
}' | ../iterm2-bitwarden-adapter list-accounts 2>/dev/null)

# Check for errors
if echo "$LIST_OUTPUT" | grep -q '"error"'; then
    echo "ERROR: list-accounts failed"
    echo "Output: $LIST_OUTPUT"
    # Clean up the account we created
    echo '{"header":{"mode":"terminal"},"token":"'"$TOKEN"'","accountIdentifier":{"accountID":"'"$ACCOUNT_ID"'"}}' | ../iterm2-bitwarden-adapter delete-account > /dev/null 2>&1 || true
    exit 1
fi

ACCOUNT_COUNT=$(echo "$LIST_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data['accounts']))" 2>/dev/null)

if [ "$ACCOUNT_COUNT" -lt 1 ]; then
    echo "ERROR: Expected at least 1 account, got $ACCOUNT_COUNT"
    echo '{"header":{"mode":"terminal"},"token":"'"$TOKEN"'","accountIdentifier":{"accountID":"'"$ACCOUNT_ID"'"}}' | ../iterm2-bitwarden-adapter delete-account > /dev/null 2>&1 || true
    exit 1
fi
echo "✓ List-accounts successful, found $ACCOUNT_COUNT account(s)"

# Test get-password (should return initialPassword123)
echo "4. Testing get-password..."
GET_INPUT='{
  "header": {
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "accountIdentifier": {
    "accountID": "'"$ACCOUNT_ID"'"
  }
}'
GET_OUTPUT=$(echo "$GET_INPUT" | ../iterm2-bitwarden-adapter get-password 2>/dev/null)

# Check for errors
if echo "$GET_OUTPUT" | grep -q '"error"'; then
    echo "ERROR: get-password failed"
    echo "Output: $GET_OUTPUT"
    echo '{"header":{"mode":"terminal"},"token":"'"$TOKEN"'","accountIdentifier":{"accountID":"'"$ACCOUNT_ID"'"}}' | ../iterm2-bitwarden-adapter delete-account > /dev/null 2>&1 || true
    exit 1
fi

PASSWORD=$(echo "$GET_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('password', ''))" 2>/dev/null)

if [ "$PASSWORD" != "initialPassword123" ]; then
    echo "ERROR: Expected password 'initialPassword123', got '$PASSWORD'"
    echo '{"header":{"mode":"terminal"},"token":"'"$TOKEN"'","accountIdentifier":{"accountID":"'"$ACCOUNT_ID"'"}}' | ../iterm2-bitwarden-adapter delete-account > /dev/null 2>&1 || true
    exit 1
fi
echo "✓ Get-password successful, password matches"

# Test set-password
echo "5. Testing set-password..."
SET_INPUT='{
  "header": {
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "accountIdentifier": {
    "accountID": "'"$ACCOUNT_ID"'"
  },
  "newPassword": "updatedPassword456"
}'
SET_OUTPUT=$(echo "$SET_INPUT" | ../iterm2-bitwarden-adapter set-password 2>/dev/null)

# Check for errors
if echo "$SET_OUTPUT" | grep -q '"error"'; then
    echo "ERROR: set-password failed"
    echo "Output: $SET_OUTPUT"
    echo '{"header":{"mode":"terminal"},"token":"'"$TOKEN"'","accountIdentifier":{"accountID":"'"$ACCOUNT_ID"'"}}' | ../iterm2-bitwarden-adapter delete-account > /dev/null 2>&1 || true
    exit 1
fi

if ! echo "$SET_OUTPUT" | python3 -m json.tool > /dev/null 2>&1; then
    echo "ERROR: set-password returned invalid JSON"
    echo '{"header":{"mode":"terminal"},"token":"'"$TOKEN"'","accountIdentifier":{"accountID":"'"$ACCOUNT_ID"'"}}' | ../iterm2-bitwarden-adapter delete-account > /dev/null 2>&1 || true
    exit 1
fi
echo "✓ Set-password successful"

# Verify password was changed
echo "6. Verifying password change..."
GET_OUTPUT2=$(echo "$GET_INPUT" | ../iterm2-bitwarden-adapter get-password 2>/dev/null)
NEW_PASSWORD=$(echo "$GET_OUTPUT2" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('password', ''))" 2>/dev/null)

if [ "$NEW_PASSWORD" != "updatedPassword456" ]; then
    echo "ERROR: Expected updated password 'updatedPassword456', got '$NEW_PASSWORD'"
    echo '{"header":{"mode":"terminal"},"token":"'"$TOKEN"'","accountIdentifier":{"accountID":"'"$ACCOUNT_ID"'"}}' | ../iterm2-bitwarden-adapter delete-account > /dev/null 2>&1 || true
    exit 1
fi
echo "✓ Password change verified"

# Test TOTP retrieval
echo "6b. Testing TOTP retrieval..."

# Get session for direct bw commands (use env var to avoid password on command line)
export BW_MASTER_PASSWORD="$BW_TEST_PASSWORD"
BW_SESSION=$(bw unlock --passwordenv BW_MASTER_PASSWORD --raw --nointeraction 2>&1)
unset BW_MASTER_PASSWORD

# Check if we got a valid session (should be a long alphanumeric string)
if [ -z "$BW_SESSION" ] || ! echo "$BW_SESSION" | grep -qE '^[A-Za-z0-9+/=]{20,}$'; then
    echo "WARNING: Could not get bw session for TOTP test (session: '$BW_SESSION'), skipping"
    BW_SESSION=""
fi

if [ -n "$BW_SESSION" ]; then
# Create a test account with TOTP using bw directly
TOTP_ACCOUNT_NAME="iTerm2-TOTP-Test-$(date +%s)"
TOTP_SECRET="JBSWY3DPEHPK3PXP"  # Standard test TOTP secret

# Get or create iTerm2 folder
FOLDER_ID=$(bw list folders --session "$BW_SESSION" 2>/dev/null | python3 -c "import sys, json; folders=json.load(sys.stdin); print(next((f['id'] for f in folders if f['name']=='iTerm2'), ''))" 2>/dev/null)

# Create item with TOTP
TOTP_ITEM_JSON=$(cat <<EOF
{
  "type": 1,
  "name": "$TOTP_ACCOUNT_NAME",
  "folderId": "$FOLDER_ID",
  "login": {
    "username": "totpuser",
    "password": "totppass123",
    "totp": "$TOTP_SECRET"
  }
}
EOF
)
TOTP_ENCODED=$(echo "$TOTP_ITEM_JSON" | bw encode)
TOTP_CREATE_OUTPUT=$(echo "$TOTP_ENCODED" | bw create item --session "$BW_SESSION" 2>/dev/null)
TOTP_ACCOUNT_ID=$(echo "$TOTP_CREATE_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null)

if [ -z "$TOTP_ACCOUNT_ID" ]; then
    echo "WARNING: Could not create TOTP test account, skipping TOTP test"
else
    # Test get-password with TOTP
    TOTP_GET_INPUT='{
      "header": {
        "mode": "terminal"
      },
      "token": "'"$TOKEN"'",
      "accountIdentifier": {
        "accountID": "'"$TOTP_ACCOUNT_ID"'"
      }
    }'
    TOTP_GET_OUTPUT=$(echo "$TOTP_GET_INPUT" | ../iterm2-bitwarden-adapter get-password 2>/dev/null)

    # Check that OTP field exists and is not empty
    OTP_VALUE=$(echo "$TOTP_GET_OUTPUT" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('otp', ''))" 2>/dev/null)

    if [ -z "$OTP_VALUE" ]; then
        echo "ERROR: Expected OTP value but got empty"
        bw delete item "$TOTP_ACCOUNT_ID" --session "$BW_SESSION" > /dev/null 2>&1 || true
        echo '{"header":{"mode":"terminal"},"token":"'"$TOKEN"'","accountIdentifier":{"accountID":"'"$ACCOUNT_ID"'"}}' | ../iterm2-bitwarden-adapter delete-account > /dev/null 2>&1 || true
        exit 1
    fi

    # OTP should be 6 digits
    if ! echo "$OTP_VALUE" | grep -qE '^[0-9]{6}$'; then
        echo "ERROR: OTP value '$OTP_VALUE' is not a 6-digit code"
        bw delete item "$TOTP_ACCOUNT_ID" --session "$BW_SESSION" > /dev/null 2>&1 || true
        echo '{"header":{"mode":"terminal"},"token":"'"$TOKEN"'","accountIdentifier":{"accountID":"'"$ACCOUNT_ID"'"}}' | ../iterm2-bitwarden-adapter delete-account > /dev/null 2>&1 || true
        exit 1
    fi

    echo "✓ TOTP retrieval successful, got OTP: $OTP_VALUE"

    # Clean up TOTP test account
    bw delete item "$TOTP_ACCOUNT_ID" --session "$BW_SESSION" > /dev/null 2>&1 || true
fi
fi  # end of BW_SESSION check

# Test delete-account
echo "7. Testing delete-account..."
DELETE_INPUT='{
  "header": {
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'",
  "accountIdentifier": {
    "accountID": "'"$ACCOUNT_ID"'"
  }
}'
DELETE_OUTPUT=$(echo "$DELETE_INPUT" | ../iterm2-bitwarden-adapter delete-account 2>/dev/null)

# Check for errors
if echo "$DELETE_OUTPUT" | grep -q '"error"'; then
    echo "ERROR: delete-account failed"
    echo "Output: $DELETE_OUTPUT"
    exit 1
fi

if ! echo "$DELETE_OUTPUT" | python3 -m json.tool > /dev/null 2>&1; then
    echo "ERROR: delete-account returned invalid JSON"
    exit 1
fi
echo "✓ Delete-account successful"

# Verify account was deleted
echo "8. Verifying account deletion..."
LIST_OUTPUT2=$(echo '{
  "header": {
    "mode": "terminal"
  },
  "token": "'"$TOKEN"'"
}' | ../iterm2-bitwarden-adapter list-accounts 2>/dev/null)

# The account should not be in the list anymore
if echo "$LIST_OUTPUT2" | grep -q "$ACCOUNT_ID"; then
    echo "ERROR: Account should have been deleted but is still in list"
    exit 1
fi
echo "✓ Account deletion verified"

echo ""
echo "✓✓✓ All Bitwarden tests passed! ✓✓✓"
