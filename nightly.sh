#!/bin/bash

set -x
cd ~/nightly/iTerm2/
# todo: git pull origin master
make Nightly
./sign.sh
cd build/Deployment
COMPACTDATE=$(date +"%Y%m%d")-nightly
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
NAME=$(echo $VERSION | sed -e "s/\\./_/g")
zip -r iTerm2-${NAME}.zip iTerm.app
scp  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no iTerm2-${NAME}.zip gnachman@themcnachmans.com:iterm2.com/nightly/iTerm2-${NAME}.zip
ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no iTerm2-${NAME}.zip gnachman@themcnachmans.com newnightly.sh iTerm2-${NAME}.zip
