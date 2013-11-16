#!/bin/bash
function die {
    echo "$@"
    echo "$@" | mail -s "Nightly build failure" $MY_EMAIL_ADDR
    exit 1
}
# Usage: SparkleSign testing.xml template.xml
function SparkleSign {
    LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')
    ruby "../../SparkleSigningTools/sign_update.rb" iTerm2-${NAME}.zip $PRIVKEY > /tmp/sig.txt
    SIG=$(cat /tmp/sig.txt)
    DATE=$(date +"%a, %d %b %Y %H:%M:%S %z")
    XML=$1
    TEMPLATE=$2
    cp $SVNDIR/appcasts/${TEMPLATE} /tmp
    cat /tmp/${TEMPLATE} | \
    sed -e "s/%XML%/${XML}/" | \
    sed -e "s/%VER%/${VERSION}/" | \
    sed -e "s/%DATE%/${DATE}/" | \
    sed -e "s/%NAME%/${NAME}/" | \
    sed -e "s/%LENGTH%/$LENGTH/" |
    sed -e "s,%SIG%,${SIG}," > $SVNDIR/appcasts/$1
    cp iTerm2-${NAME}.zip ~/iterm2-website/downloads/beta/
}


set -x
cd ~/server/nightly/iTerm2/
# todo: git pull origin master
make Nightly || die "Nightly build failed"
./sign.sh
COMPACTDATE=$(date +"%Y%m%d")-nightly
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
NAME=$(echo $VERSION | sed -e "s/\\./_/g")
SVNDIR=~/iterm2-website
git log > $SVNDIR/appcasts/nightly_changes.txt

cd build/Nightly
zip -ry iTerm2-${NAME}.zip iTerm.app

SparkleSign nightly.xml nightly_template.xml

scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no iTerm2-${NAME}.zip gnachman@iterm2.com:iterm2.com/nightly/iTerm2-${NAME}.zip
ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no gnachman@iterm2.com "./newnightly.sh iTerm2-${NAME}.zip"

scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $SVNDIR/appcasts/nightly_changes.txt $SVNDIR/appcasts/nightly.xml gnachman@iterm2.com:iterm2.com/appcasts/
