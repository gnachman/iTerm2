#!/bin/bash

set -e

echo "Testing Bitwarden login command..."

# BW_TEST_PASSWORD should be set by the runner script
if [ -z "$BW_TEST_PASSWORD" ]; then
    echo "ERROR: BW_TEST_PASSWORD not set"
    exit 1
fi

# Lock the vault first to ensure we're testing unlock
bw lock > /dev/null 2>&1 || true

# Test login with correct password
echo '{
  "header": {
    "mode": "terminal"
  },
  "masterPassword": "'"$BW_TEST_PASSWORD"'"
}' | ../iterm2-bitwarden-adapter login 2>/dev/null > /tmp/bw_login_output.json || {
    echo "ERROR: login command failed"
    cat /tmp/bw_login_output.json
    rm -f /tmp/bw_login_output.json
    exit 1
}

# Check if output is valid JSON
python3 -m json.tool < /tmp/bw_login_output.json > /dev/null || {
    echo "ERROR: Output is not valid JSON"
    cat /tmp/bw_login_output.json
    rm -f /tmp/bw_login_output.json
    exit 1
}

# Check if output contains token field
if ! grep -q '"token"' /tmp/bw_login_output.json; then
    echo "ERROR: Missing token field"
    cat /tmp/bw_login_output.json
    rm -f /tmp/bw_login_output.json
    exit 1
fi

# Check token is not empty
TOKEN=$(python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('token', ''))" < /tmp/bw_login_output.json 2>/dev/null)
if [ -z "$TOKEN" ]; then
    echo "ERROR: token should not be empty"
    rm -f /tmp/bw_login_output.json
    exit 1
fi

# Lock vault again before testing wrong password
bw lock > /dev/null 2>&1 || true

# Test login with incorrect password (should return error)
echo '{
  "header": {
    "mode": "terminal"
  },
  "masterPassword": "wrong-password-12345"
}' | ../iterm2-bitwarden-adapter login 2>/dev/null > /tmp/bw_login_error.json || true

if ! grep -q '"error"' /tmp/bw_login_error.json; then
    echo "ERROR: Login with wrong password should return an error"
    cat /tmp/bw_login_error.json
    rm -f /tmp/bw_login_output.json /tmp/bw_login_error.json
    exit 1
fi

echo "✓ Login test passed!"

# Clean up
rm -f /tmp/bw_login_output.json /tmp/bw_login_error.json
