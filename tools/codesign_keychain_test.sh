#!/bin/bash
#
# Re-sign a locally-built iTerm2.app with the keychain-access-groups entitlement so
# `make run-keychain` can exercise the data-protection-keychain migration without an
# Xcode-driven signed build (which would need a device-registered Mac App Development
# profile). keychain-access-groups is a RESTRICTED entitlement: launchd refuses to
# spawn the app (RBSRequestErrorDomain "Launch failed", errno 163) unless an embedded
# provisioning profile authorizes it AND the signing certificate is inside that
# profile. So this finds an installed "iTerm2 Dev ID App Prov Prof" whose embedded
# Developer ID cert you actually hold, embeds it, and signs with that exact cert.
#
# codesign does NOT expand Xcode build-setting variables, so the team prefix is
# resolved by hand. app-groups (also restricted, and not authorized by this profile)
# is intentionally dropped; it is not needed to test the keychain.
#
set -euo pipefail

APP="${1:?usage: codesign_keychain_test.sh <path-to-iTerm2.app>}"
TEAM=H7V7XYVQ7D
PROFILE_NAME="iTerm2 Dev ID App Prov Prof"
[ -d "$APP" ] || { echo "error: app not found: $APP" >&2; exit 1; }

# Find a profile named $PROFILE_NAME that (a) authorizes keychain-access-groups and
# (b) embeds a Developer ID cert present in your keychain. Use that profile + cert.
# Iterate in SORTED order so the same profile/cert is picked every run (a differing
# access-group context between launches is the suspected migration-loss cause).
prof=""; cert=""
while IFS= read -r f; do
  [ -e "$f" ] || continue
  x=$(security cms -D -i "$f" 2>/dev/null) || continue
  [ "$(printf '%s' "$x" | plutil -extract Name raw - 2>/dev/null)" = "$PROFILE_NAME" ] || continue
  printf '%s' "$x" | plutil -extract Entitlements.keychain-access-groups raw - >/dev/null 2>&1 || continue
  n=$(printf '%s' "$x" | plutil -extract DeveloperCertificates raw - 2>/dev/null) || continue
  i=0
  while [ "$i" -lt "$n" ]; do
    sha=$(printf '%s' "$x" | plutil -extract "DeveloperCertificates.$i" raw - 2>/dev/null \
          | base64 -D 2>/dev/null | openssl x509 -inform DER -noout -fingerprint -sha1 2>/dev/null \
          | sed 's/.*=//; s/://g')
    if [ -n "$sha" ] && security find-identity -v -p codesigning | grep -q "$sha"; then
      prof="$f"; cert="$sha"; break
    fi
    i=$((i + 1))
  done
  [ -n "$prof" ] && break
done < <(find "$HOME/Library/MobileDevice/Provisioning Profiles" -name '*.provisionprofile' 2>/dev/null | sort)

if [ -z "$prof" ]; then
  echo "error: no installed '$PROFILE_NAME' profile embeds a Developer ID cert you hold." >&2
  echo "       Regenerate that profile in the developer portal to include your current" >&2
  echo "       Developer ID Application certificate, then retry." >&2
  exit 1
fi
echo "Using provisioning profile: $prof"
echo "Signing certificate SHA1:   $cert"

ent=$(mktemp -t iterm2-keychain-test.XXXXXX)
cat > "$ent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>keychain-access-groups</key><array><string>${TEAM}.com.googlecode.iterm2</string></array>
	<key>com.apple.security.get-task-allow</key><true/>
	<key>com.apple.security.cs.allow-jit</key><true/>
	<key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
EOF

cp "$prof" "$APP/Contents/embedded.provisionprofile"
# Remove any *.cstemp left behind by a previously interrupted codesign; an incremental
# rebuild reuses the app dir, and a stale temp makes the next --deep sign fail with
# "<name>.cstemp: No such file or directory".
find "$APP" -name '*.cstemp' -delete 2>/dev/null || true
codesign --force --deep --entitlements "$ent" --sign "$cert" "$APP"
rm -f "$ent"

if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "${TEAM}.com.googlecode.iterm2"; then
  echo "keychain-access-group '${TEAM}.com.googlecode.iterm2' embedded OK"
else
  echo "error: keychain-access-groups entitlement missing after signing" >&2
  exit 1
fi
