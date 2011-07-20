#!/bin/bash
# Run this before uploading.
MINORVERSION=$1
BUGVERSION=$2
NAME=1.$MINORVERSION.$BUGVERSION
cd build/Deployment
zip -r iTerm2-${NAME}.zip iTerm.app
vi ../../appcasts/full_changes.html
LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')
ruby "/Users/georgen/Downloads/Sparkle 1.5b6/Extras/Signing Tools/sign_update.rb" iTerm2-${NAME}.zip $PRIVKEY > /tmp/sig.txt
SIG=$(cat /tmp/sig.txt)
DATE=$(date +"%a, %d %b %Y %H:%M:%S %z")
cp ../../appcasts/full_template.xml /tmp/template.xml
cat /tmp/template.xml | \
sed -e "s/%MINORVER%/${MINORVERSION}/" | \
sed -e "s/%BUGVER%/${BUGVERSION}/" | \
sed -e "s/%DATE%/${DATE}/" | \
sed -e "s/%NAME%/${NAME}/" | \
sed -e "s/%LENGTH%/$LENGTH/" |
sed -e "s,%SIG%,${SIG}," > ../../appcasts/final.xml
echo "Go upload the iTerm2-${NAME}.zip, then run:"
echo "svn commit -m $NAME"
echo "cd .. && trunk/release2.sh $NAME"
