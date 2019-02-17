#!/bin/bash
function die {
    echo "$@"
    echo "$@" | mail -s "Nightly build failure" $MY_EMAIL_ADDR
    exit 1
}
# Usage: SparkleSign testing.xml template.xml signingkey
function SparkleSign {
    LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')
    ruby "../../ThirdParty/SparkleSigningTools/sign_update.rb" iTerm2-${NAME}.zip $PRIVKEY > /tmp/sig.txt || die "Signing failed"
    ../../tools/sign_update iTerm2-${NAME}.zip "$3" > /tmp/newsig.txt || die SparkleSignNew
    SIG=$(cat /tmp/sig.txt)
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
    sed -e "s,%SIG%,${SIG}," | \
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
tools/sign.sh
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
zip -ry iTerm2-${NAME}.zip iTerm.app

# Modern
SparkleSign nightly_modern.xml nightly_modern_template.xml "$SIGNING_KEY"
# Transitional
SparkleSign nightly_new.xml nightly_new_template.xml "$SIGNING_KEY"
# Legacy
SparkleSign nightly.xml nightly_template.xml "$SIGNING_KEY"

#https://github.com/Homebrew/homebrew-cask-versions/pull/6965
#cask-repair --cask-url https://www.iterm2.com/nightly/latest -b --cask-version $CASK_VERSION iterm2-nightly < /dev/null

scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no iTerm2-${NAME}.zip gnachman@iterm2.com:iterm2.com/nightly/iTerm2-${NAME}.zip || die "scp zip"
ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no gnachman@iterm2.com "./newnightly.sh iTerm2-${NAME}.zip" || die "ssh"
scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $SVNDIR/source/appcasts/nightly_changes.txt $SVNDIR/source/appcasts/nightly.xml $SVNDIR/source/appcasts/nightly_new.xml $SVNDIR/source/appcasts/nightly_modern.xml gnachman@iterm2.com:iterm2.com/appcasts/ || die "scp appcasts"

cd $SVNDIR
git add source/appcasts/nightly_changes.txt
# Modern
git add source/appcasts/nightly_modern.xml
# Transitional
git add source/appcasts/nightly_new.xml
# Legacy
git add source/appcasts/nightly.xml
git commit -m "${NAME}"

