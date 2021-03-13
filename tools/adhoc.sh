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

# - notarize -
PRENOTARIZED_ZIP=iTerm2-${NAME}-prenotarized.zip
zip -ry $PRENOTARIZED_ZIP iTerm.app
xcrun altool --notarize-app --primary-bundle-id "com.googlecode.iterm2" --username "apple@georgester.com" --password "$NOTPASS" --file $PRENOTARIZED_ZIP > /tmp/upload.out 2>&1 || die "Notarization failed"
UUID=$(grep RequestUUID /tmp/upload.out | sed -e 's/RequestUUID = //')
echo "uuid is $UUID"
xcrun altool --notarization-info $UUID -u "apple@georgester.com" -p "$NOTPASS"
sleep 1
while xcrun altool --notarization-info $UUID -u "apple@georgester.com" -p "$NOTPASS" 2>&1 | egrep -i "in progress|Could not find the RequestUUID":
do
    echo "Trying again"
    sleep 1
done
xcrun stapler staple iTerm.app
# - end notarize - 

zip -ry iTerm2-${NAME}.zip iTerm.app
chmod a+r iTerm2-${NAME}.zip
scp iTerm2-${NAME}.zip gnachman@bryan.dreamhost.com:iterm2.com/adhocbuilds/ || \
  scp iTerm2-${NAME}.zip gnachman@bryan.dreamhost.com:iterm2.com/adhocbuilds/
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git checkout -b adhoc_$VERSION
git commit -am "Adhoc build $VERSION"
git push origin adhoc_$VERSION
git checkout $BRANCH
echo ""
echo "Download linky:"
echo "https://iterm2.com/adhocbuilds/iTerm2-${NAME}.zip"
