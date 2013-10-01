#!/bin/bash
function RunFromMakefile {
  echo You\'re supposed to use "make release", not run this directly. I\'ll just do it for you.
  sleep 1
  make release
  exit
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

echo Num args is $#
[ $# -gt 0 ] || RunFromMakefile
[ "$1" = RanFromMakefile ] || RunFromMakefile

COMPACTDATE=$(date +"%Y%m%d")
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
NAME=$(echo $VERSION | sed -e "s/\\./_/g")
SVNDIR=~/iterm2-website
ORIG_DIR=`pwd`

set -x
./sign.sh

cd build/Deployment

# Create the zip file
zip -ry iTerm2-${NAME}.zip iTerm.app

# Update the list of changes
vi $SVNDIR/appcasts/testing_changes.txt

# Place files in website git.
cp iTerm2-${NAME}.zip $SVNDIR/downloads/beta/
NEWFILES=""
test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.summary || (echo "iTerm2 "$VERSION" beta (OS 10.6+, Intel-only)" > $SVNDIR/downloads/beta/iTerm2-${NAME}.summary)
test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.description || (echo "This is the recommended beta build for most users. **ENTER CHANGES HERE**" > $SVNDIR/downloads/beta/iTerm2-${NAME}.description)
vi $SVNDIR/downloads/beta/iTerm2-${NAME}.description
vi $SVNDIR/downloads/beta/iTerm2-${NAME}.changelog
NEWFILES=${NEWFILES}" downloads/beta/iTerm2-${NAME}.summary downloads/beta/iTerm2-${NAME}.description downloads/beta/iTerm2-${NAME}.changelog downloads/beta/iTerm2-${NAME}.zip appcasts/testing.xml appcasts/testing_changes.txt"

# Prepare the sparkle xml file
SparkleSign testing.xml template.xml

############################################################################################
# Begin legacy build
cd "../Leopard Deployment"

MODERN_NAME=$NAME
NAME=$(echo $VERSION | sed -e "s/\\./_/g")-LeopardPPC

# Create the zip file
zip -ry iTerm2-${NAME}.zip iTerm.app

# Place files in website git.
cp iTerm2-${NAME}.zip $SVNDIR/downloads/beta/
test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.summary || (echo "iTerm2 "$VERSION" beta (OS 10.6+, Intel-only)" > $SVNDIR/downloads/beta/iTerm2-${NAME}.summary)
test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.description || (echo "This build has a limited set of features but supports OS 10.5 and PowerPC. If you have an Intel Mac that runs OS 10.6 or newer, you don't want this." > $SVNDIR/downloads/beta/iTerm2-${NAME}.description)
vi $SVNDIR/downloads/beta/iTerm2-${NAME}.description
NEWFILES="${NEWFILES}downloads/beta/iTerm2-${NAME}.summary downloads/beta/iTerm2-${NAME}.description downloads/beta/iTerm2-${NAME}.description downloads/beta/iTerm2-${NAME}.zip appcasts/legacy_testing.xml"

# Prepare the sparkle xml file
SparkleSign legacy_testing.xml legacy_template.xml
# End legacy build
############################################################################################

echo "git tag v${VERSION}"
echo "git commit -am ${VERSION}"
echo "git push origin v2"
echo "git push --tags"
echo "cd "$SVNDIR
echo "git add "$NEWFILES
echo "git commit -am v${VERSION}"
echo "git push origin master"
