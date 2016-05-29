set -x
security unlock-keychain -p "$ITERM_KEYCHAIN_PASSWORD" "$ITERM_KEYCHAIN"
codesign --deep -s "Developer ID Application: GEORGE NACHMAN" -f build/Deployment/iTerm.app
codesign --keychain "$ITERM_KEYCHAIN" --deep -s "Developer ID Application: GEORGE NACHMAN" -f build/Nightly/iTerm2.app
