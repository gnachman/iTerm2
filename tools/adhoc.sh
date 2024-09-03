#!/bin/bash
echo Enter the notarization password
read -s NOTPASS
COMPACTDATE=$(date +"%Y%m%d_%H%M%S")
VERSION="0.$COMPACTDATE-adhoc"
echo "$VERSION" > version.txt
NAME=$(echo $VERSION | sed -e "s/\\./_/g")
make clean
make release
rm -rf build/Deployment/iTerm.app
mv build/Deployment/iTerm2.app build/Deployment/iTerm.app
pushd build/Deployment


function die {
  echo $1
  exit
}

# - notarize -
PRENOTARIZED_ZIP=iTerm2-${NAME}-prenotarized.zip
zip -ry $PRENOTARIZED_ZIP iTerm.app
set -x
xcrun notarytool submit --team-id H7V7XYVQ7D --apple-id "apple@georgester.com" --password "$NOTPASS" $PRENOTARIZED_ZIP > /tmp/upload.out 2>&1 || die "Notarization failed"
cat /tmp/upload.out
UUID=$(grep RequestUUID /tmp/upload.out | sed -e 's/RequestUUID = //')
echo "uuid is $UUID"
xcrun notarytool info --team-id H7V7XYVQ7D --apple-id "apple@georgester.com" --password "$NOTPASS" $UUID
sleep 1
while xcrun notarytool info --team-id H7V7XYVQ7D --apple-id "apple@georgester.com" --password "$NOTPASS" $UUID 2>&1 | egrep -i "in progress|Could not find the RequestUUID|Submission does not exist or does not belong to your team":
do
    echo "Trying again"
    sleep 1
done
xcrun stapler staple iTerm.app
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
