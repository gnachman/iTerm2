#!/bin/bash
function die {
    echo "$@"
    echo "$@" | mail -s "Nightly build failure" $MY_EMAIL_ADDR
    exit 1
}

set -x
cd ~/nightly/iTerm2/
# todo: git pull origin master
make Nightly || die "Nightly build failed"
./sign.sh
COMPACTDATE=$(date +"%Y%m%d")-nightly
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
NAME=$(echo $VERSION | sed -e "s/\\./_/g")
cd build/Nightly
zip -ry iTerm2-${NAME}.zip iTerm.app
scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no iTerm2-${NAME}.zip gnachman@themcnachmans.com:iterm2.com/nightly/iTerm2-${NAME}.zip
ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no gnachman@themcnachmans.com "./newnightly.sh iTerm2-${NAME}.zip"

