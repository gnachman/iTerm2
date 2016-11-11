set -x
#security unlock-keychain -p "$ITERM_KEYCHAIN_PASSWORD" "$ITERM_KEYCHAIN"
security unlock-keychain -p "$ITERM_KEYCHAIN_PASSWORD" 
codesign --deep -s "H7V7XYVQ7D" -f build/Deployment/iTerm.app
codesign --keychain "$ITERM_KEYCHAIN" --deep -s "H7V7XYVQ7D" -f build/Nightly/iTerm2.app
