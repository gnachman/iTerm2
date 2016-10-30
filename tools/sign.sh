set -x
security unlock-keychain -p "$ITERM_KEYCHAIN_PASSWORD" "$ITERM_KEYCHAIN"
/usr/bin/codesign --keychain "$ITERM_KEYCHAIN" --deep --force --sign 3E1298F974EB540E3D1D905AA99612231919845E --requirements '=designated => anchor apple generic  and identifier "$self.identifier" and ((cert leaf[field.1.2.840.113635.100.6.1.9] exists) or ( certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists  and certificate leaf[subject.OU] = "H7V7XYVQ7D" ))' --timestamp=none "build/Nightly/iTerm2.app"
