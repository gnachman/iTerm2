#!/bin/bash
function die {
    echo "$@"
    echo "$@" | mail -s "Nightly build failure" $MY_EMAIL_ADDR
    echo echo "$@" >> ~/.login
    exit 1
}
# Usage: SparkleSign testing.xml template.xml signingkey
function SparkleSign {
    LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')
    ../../tools/sign_update iTerm2-${NAME}.zip "$3" > /tmp/newsig.txt || die SparkleSignNew
    NEWSIG=$(cat /tmp/newsig.txt)
    DATE=$(date +"%a, %d %b %Y %H:%M:%S %z")
    XML=$1
    TEMPLATE=$2
    cp $SVNDIR/source/appcasts/${TEMPLATE} /tmp
    cat /tmp/${TEMPLATE} | \
    sed -e "s/%XML%/${XML}/" | \
    sed -e "s/%VER%/${VERSION}/" | \
    sed -e "s/%DATE%/${DATE}/" | \
    sed -e "s/%NAME%/${NAME}/" | \
    sed -e "s/%LENGTH%/$LENGTH/" | \
    sed -e "s,%NEWSIG%,${NEWSIG}," > $SVNDIR/source/appcasts/$1
    cp iTerm2-${NAME}.zip ~/iterm2-website/downloads/beta/
}


set -x
# todo: git pull origin master
rm -rf build/Nightly/iTerm2.app
make clean || die "Make clean failed"
#security unlock-keychain -p "$ITERM_KEYCHAIN_PASSWORD" "$ITERM_KEYCHAIN"
security unlock-keychain -p "$ITERM_KEYCHAIN_PASSWORD"
make Nightly || die "Nightly build failed"
COMPACTDATE=$(date +"%Y%m%d")-nightly
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
NAME=$(echo $VERSION | sed -e "s/\\./_/g")
SVNDIR=~/iterm2-website
(git log --after={`date -v-1m "+%Y-%m-01"`} --pretty=format:"%cd: %B" --date=short | fmt -w 60) > $SVNDIR/source/appcasts/nightly_changes.txt

CASK_DATE=$(echo -n $COMPACTDATE | sed -e 's/-nightly//')
CASK_VERSION=$(cat version.txt | sed -e "s/%(extra)s/$CASK_DATE/")
CASK_VERSION=$(echo $CASK_VERSION | sed -e "s/\\./_/g")

git tag "v$COMPACTDATE"
git push --tags
cd build/Nightly

# For the purposes of auto-update, the app's folder must be named iTerm.app since Sparkle won't accept a name change.
rm -rf iTerm.app
mv iTerm2.app iTerm.app

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
NOTARIZED_ZIP=iTerm2-${NAME}.zip
xcrun stapler staple iTerm.app
zip -ry $NOTARIZED_ZIP iTerm.app

# Modern
SparkleSign nightly_modern.xml nightly_modern_template.xml "$SIGNING_KEY"

#https://github.com/Homebrew/homebrew-cask-versions/pull/6965
#cask-repair --cask-url https://www.iterm2.com/nightly/latest -b --cask-version $CASK_VERSION iterm2-nightly < /dev/null

cp iTerm2-${NAME}.zip ~/Dropbox/NightlyBuilds/
scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no iTerm2-${NAME}.zip gnachman@bryan.dreamhost.com:iterm2.com/nightly/iTerm2-${NAME}.zip || die "scp zip"
ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no gnachman@bryan.dreamhost.com "./newnightly.sh iTerm2-${NAME}.zip" || die "ssh"
scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $SVNDIR/source/appcasts/nightly_changes.txt $SVNDIR/source/appcasts/nightly_modern.xml gnachman@bryan.dreamhost.com:iterm2.com/appcasts/ || die "scp appcasts"

curl -v -X POST "https://api.cloudflare.com/client/v4/zones/$CFZONE/purge_cache" \
     -H "X-Auth-Email: gnachman@gmail.com" \
     -H "X-Auth-Key: $CFKEY" \
     -H "Content-Type: application/json" \
     --data '{"files":["https://iterm2.com/nightly/latest"]}'

cd $SVNDIR
git add source/appcasts/nightly_changes.txt
# Modern
git add source/appcasts/nightly_modern.xml
# Transitional
git add source/appcasts/nightly_new.xml
# Legacy
git add source/appcasts/nightly.xml
git commit -m "${NAME}"

