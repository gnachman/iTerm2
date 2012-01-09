#!/bin/bash
# Run this before uploading.
COMPACTDATE=$(date +"%Y%m%d")
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
NAME=$(echo $VERSION | sed -e "s/\\./_/g")
cd build/Deployment
zip -r iTerm2-${NAME}.zip iTerm.app
vi ../../appcasts/testing_changes.html
LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')
ruby "/Users/georgen/Downloads/Sparkle 1.5b6/Extras/Signing Tools/sign_update.rb" iTerm2-${NAME}.zip $PRIVKEY > /tmp/sig.txt
SIG=$(cat /tmp/sig.txt)
DATE=$(date +"%a, %d %b %Y %H:%M:%S %z")
cp ../../appcasts/template.xml /tmp
cat /tmp/template.xml | \
sed -e "s/%VER%/${VERSION}/" | \
sed -e "s/%DATE%/${DATE}/" | \
sed -e "s/%NAME%/${NAME}/" | \
sed -e "s/%LENGTH%/$LENGTH/" |
sed -e "s,%SIG%,${SIG}," > ../../appcasts/canary.xml
echo "Go upload the iTerm2-${NAME}.zip, then run:"
echo "git tag v${VERSION}"
echo "git push --tags"
echo "svn commit -m ${VERSION} appcasts/canary.xml appcasts/testing_changes.html"
echo "git commit -am ${VERSION}"
echo "git push origin master"
