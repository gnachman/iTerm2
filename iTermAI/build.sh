#!/bin/bash

set -x

function die {
  echo $1
  exit
}

echo Enter the notarization password
read -s NOTPASS

echo Enter the EdDSA private key for iTermAI
read -s PRIVKEY

echo Enter the version
read VERSION

pushd ../SignPlugin
xcodebuild || die "Failed to build SignPlugin"
popd

../SignPlugin/Build/Release/SignPlugin sign $PRIVKEY iTermAI/iTermAIPlugin.js > iTermAI/iTermAIPlugin.sig
xcodebuild -project iTermAI.xcodeproj -scheme iTermAI -configuration Release -destination 'generic/platform=macOS'

cd Build/Release

PRENOTARIZED_ZIP=iTermAI-${VERSION}-prenotarized.zip
zip -ry $PRENOTARIZED_ZIP iTermAI.app
xcrun notarytool submit --team-id H7V7XYVQ7D --apple-id "apple@georgester.com" --password "$NOTPASS" $PRENOTARIZED_ZIP > /tmp/upload.out 2>&1 || die "Notarization failed"
UUID=$(grep id: /tmp/upload.out | head -1 | sed -e 's/.*id: //')
echo "uuid is $UUID"
xcrun notarytool info --team-id H7V7XYVQ7D --apple-id "apple@georgester.com" --password "$NOTPASS" $UUID
sleep 1
while xcrun notarytool info --team-id H7V7XYVQ7D --apple-id "apple@georgester.com" --password "$NOTPASS" $UUID 2>&1 | egrep -i "in progress|Could not find the RequestUUID|Submission does not exist or does not belong to your team":
do
    echo "Trying again"
    sleep 1
done
NOTARIZED_ZIP=iTermAI-${VERSION}.zip
xcrun stapler staple iTermAI.app
zip -ry $NOTARIZED_ZIP iTermAI.app
echo `pwd`/${NOTARIZED_ZIP}
