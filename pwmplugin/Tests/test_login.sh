#!/bin/bash

set -e

echo "Testing login command..."

# Create a test database
TEST_DB="test_db.kdbx"
TEST_PASSWORD="test-password-123"

# Clean up any existing test database
rm -f "$TEST_DB"

# Create a new database
keepassxc-cli db-create "$TEST_DB" --set-password <<EOF
$TEST_PASSWORD
$TEST_PASSWORD
EOF

# Export the database path
export KEEPASSXC_DATABASE="$TEST_DB"

# Test login with correct password
echo '{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "masterPassword": "'"$TEST_PASSWORD"'"
}' | ../iterm2-keepassxc-adapter login 2>/dev/null > /tmp/login_output.json || {
    echo "ERROR: login command failed"
    rm -f "$TEST_DB" /tmp/login_output.json
    exit 1
}

# Check if output is valid JSON
python3 -m json.tool < /tmp/login_output.json > /dev/null || {
    echo "ERROR: Output is not valid JSON"
    cat /tmp/login_output.json
    rm -f "$TEST_DB" /tmp/login_output.json
    exit 1
}

# Check if output contains token field
if ! grep -q '"token"' /tmp/login_output.json; then
    echo "ERROR: Missing token field"
    rm -f "$TEST_DB" /tmp/login_output.json
    exit 1
fi

# Check token is not empty
TOKEN=$(python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('token', ''))" < /tmp/login_output.json 2>/dev/null)
if [ -z "$TOKEN" ]; then
    echo "ERROR: token should not be empty"
    rm -f "$TEST_DB" /tmp/login_output.json
    exit 1
fi

# Test login with incorrect password (should return error)
echo '{
  "header": {
    "pathToDatabase": "'"$TEST_DB"'",
    "pathToExecutable": "/opt/homebrew/bin/keepassxc-cli",
    "mode": "terminal"
  },
  "masterPassword": "wrong-password"
}' | ../iterm2-keepassxc-adapter login 2>/dev/null > /tmp/login_error.json || true

if ! grep -q '"error"' /tmp/login_error.json; then
    echo "ERROR: Login with wrong password should return an error"
    cat /tmp/login_error.json
    rm -f "$TEST_DB" /tmp/login_output.json /tmp/login_error.json
    exit 1
fi

echo "✓ Login test passed!"

# Clean up
rm -f "$TEST_DB" /tmp/login_output.json /tmp/login_error.json
