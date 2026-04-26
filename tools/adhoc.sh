#!/bin/bash
echo Enter the notarization password
read -s NOTPASS
COMPACTDATE=$(date +"%Y%m%d_%H%M%S")
VERSION="0.$COMPACTDATE-adhoc"
echo "$VERSION" > version.txt
NAME=$(echo $VERSION | sed -e "s/\\./_/g")
make clean
make SIGNED=1 UNIVERSAL=1 release
rm -rf build/Deployment/iTerm.app
mv build/Deployment/iTerm2.app build/Deployment/iTerm.app
pushd build/Deployment


function die {
  echo "$1"
  exit 1
}

# - notarize -
PRENOTARIZED_ZIP=iTerm2-${NAME}-prenotarized.zip
zip -ry $PRENOTARIZED_ZIP iTerm.app

# Retry notarytool submit on transient upload failures (e.g.
# HTTPClientError.deadlineExceeded, abortedUpload, connection
# reset). After the first transient failure, fall back to
# --no-s3-acceleration: Apple's S3 Transfer Acceleration (the
# default) routes through CloudFront edges and can be slower
# than the direct S3 path when an edge is congested or
# mis-routed, which is the usual cause of deadlineExceeded
# during the multipart upload. Real rejections (Invalid status,
# bad credentials) are not retried.
function notarize_with_retry {
  local zip="$1"
  local max_attempts=6
  local attempt=1
  local out=/tmp/upload.out
  local accel_args=()
  while [ $attempt -le $max_attempts ]; do
    echo "Notarization attempt $attempt of $max_attempts (${accel_args[*]:-default acceleration})..."
    xcrun notarytool submit \
      --team-id H7V7XYVQ7D \
      --apple-id "apple@georgester.com" \
      --password "$NOTPASS" \
      --wait \
      "${accel_args[@]}" \
      "$zip" > "$out" 2>&1
    local rc=$?
    cat "$out"
    if [ $rc -eq 0 ] && grep -q "status: Accepted" "$out"; then
      return 0
    fi
    if grep -qE "abortedUpload|deadlineExceeded|connection reset|connectionReset|timed out|Connection refused|networkConnectionLost" "$out"; then
      accel_args=(--no-s3-acceleration)
      local backoff=$((attempt * 10))
      echo "Transient upload failure (attempt $attempt). Retrying in ${backoff}s with --no-s3-acceleration..."
      sleep $backoff
      attempt=$((attempt + 1))
      continue
    fi
    echo "Notarization failed with non-retryable error (rc=$rc)."
    return 1
  done
  echo "Notarization failed after $max_attempts attempts."
  return 1
}

set -x
notarize_with_retry "$PRENOTARIZED_ZIP" || die "Notarization failed"
xcrun stapler staple iTerm.app || die "Stapling failed"
set +x
# - end notarize -

zip -ry iTerm2-${NAME}.zip iTerm.app
chmod a+r iTerm2-${NAME}.zip
scp iTerm2-${NAME}.zip gnachman@bryan:iterm2.com/adhocbuilds/ || \
  scp iTerm2-${NAME}.zip gnachman@bryan:iterm2.com/adhocbuilds/
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git checkout -b adhoc_$VERSION
git commit -am "Adhoc build $VERSION"
git push origin adhoc_$VERSION
git checkout $BRANCH
echo ""
echo "Download linky:"
echo "https://iterm2.com/adhocbuilds/iTerm2-${NAME}.zip"
