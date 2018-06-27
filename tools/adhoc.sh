#!/bin/bash
COMPACTDATE=$(date +"%Y%m%d_%H%M%S")
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
NAME=$(echo $VERSION | sed -e "s/\\./_/g")-adhoc
make clean
make Development
rm -rf build/Development/iTerm.app
mv build/Development/iTerm2.app build/Development/iTerm.app
pushd build/Development
zip -ry iTerm2-${NAME}.zip iTerm.app
chmod a+r iTerm2-${NAME}.zip
scp iTerm2-${NAME}.zip gnachman@iterm2.com:iterm2.com/adhocbuilds/ || \
  scp iTerm2-${NAME}.zip gnachman@iterm2.com:iterm2.com/adhocbuilds/
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git checkout -b adhoc_$VERSION
git commit -am "Adhoc build $VERSION"
git push origin adhoc_$VERSION
git checkout $BRANCH
echo ""
echo "Download linky:"
echo "http://iterm2.com/adhocbuilds/iTerm2-${NAME}.zip"
