#!/bin/bash
function die {
    echo "$@"
    echo "$@" | mail -s "Nightly build failure" $MY_EMAIL_ADDR
    exit 1
}
# Usage: SparkleSign testing.xml template.xml
function SparkleSign {
    LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')
    ruby "../../ThirdParty/SparkleSigningTools/sign_update.rb" iTerm2-${NAME}.zip $PRIVKEY > /tmp/sig.txt || die "Signing failed"
    SIG=$(cat /tmp/sig.txt)
    DATE=$(date +"%a, %d %b %Y %H:%M:%S %z")
    XML=$1
    TEMPLATE=$2
    cp $SVNDIR/source/appcasts/${TEMPLATE} /tmp
    cat /tmp/${TEMPLATE} | \
    sed -e "s/%XML%/${XML}/" | \
    sed -e "s/%VER%/${VERSION}/" | \
    sed -e "s/%DATE%/${DATE}/" | \
    sed -e "s/%NAME%/${NAME}/" | \
    sed -e "s/%LENGTH%/$LENGTH/" |
    sed -e "s,%SIG%,${SIG}," > $SVNDIR/source/appcasts/$1
    cp iTerm2-${NAME}.zip ~/iterm2-website/downloads/beta/
}


set -x
# todo: git pull origin master
rm -rf build/Nightly/iTerm2.app
make clean || die "Make clean failed"
make Nightly || die "Nightly build failed"
tools/sign.sh
COMPACTDATE=$(date +"%Y%m%d")-nightly
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
NAME=$(echo $VERSION | sed -e "s/\\./_/g")
SVNDIR=~/iterm2-website
git log > $SVNDIR/source/appcasts/nightly_changes.txt

cd build/Nightly

# For the purposes of auto-update, the app's folder must be named iTerm.app since Sparkle won't accept a name change.
rm -rf iTerm.app
mv iTerm2.app iTerm.app
zip -ry iTerm2-${NAME}.zip iTerm.app

SparkleSign nightly.xml nightly_template.xml

scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no iTerm2-${NAME}.zip gnachman@iterm2.com:iterm2.com/nightly/iTerm2-${NAME}.zip || die "scp zip"
ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no gnachman@iterm2.com "./newnightly.sh iTerm2-${NAME}.zip" || die "ssh"
scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $SVNDIR/source/appcasts/nightly_changes.txt $SVNDIR/source/appcasts/nightly.xml gnachman@iterm2.com:iterm2.com/appcasts/ || die "scp appcasts"
