set -x
security unlock-keychain -p "$ITERM_KEYCHAIN_PASSWORD" "$ITERM_KEYCHAIN"
codesign --deep -s "H7V7XYVQ7D" -f build/Deployment/iTerm.app
codesign --keychain "$ITERM_KEYCHAIN" --deep -s "H7V7XYVQ7D" -f build/Nightly/iTerm2.app
