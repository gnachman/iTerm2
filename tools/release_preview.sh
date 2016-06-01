#!/bin/bash
function die {
  echo $1
  exit
}

test -f "$PRIVKEY" || die "Set PRIVKEY environment variable to point at a valid private key (not set or nonexistent)"
# Usage: SparkleSign testing.xml template.xml
function SparkleSign {
    LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')
    ruby "../../ThirdParty/SparkleSigningTools/sign_update.rb" iTerm2-${NAME}.zip $PRIVKEY > /tmp/sig.txt || die SparkleSign
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

# First arg is build directory name (e.g., Deployment)
# Second arg is suffix for name that goes before .zip.
# Third arg describes system requirements
# Fourth arg is the default description for the build and can be longer.
# Fifth arg is a prefix for sparkle files.
# Sixth arg is extra args for codesign
function Build {
  BUILDTYPE=$1
  NAME=$(echo $VERSION | sed -e "s/\\./_/g")$2
  SUMMARY=$3
  DESCRIPTION=$4
  SPARKLE_PREFIX=$5
  codesign -s "Developer ID Application: GEORGE NACHMAN" -f "build/$BUILDTYPE/iTerm2.app/Contents/Frameworks/Growl.framework"
  codesign -s "Developer ID Application: GEORGE NACHMAN" -f "build/$BUILDTYPE/iTerm2.app/Contents/Frameworks/NMSSH.framework"
  codesign -s "Developer ID Application: GEORGE NACHMAN" -f "build/$BUILDTYPE/iTerm2.app/Contents/Frameworks/Sparkle.framework"
  codesign -s "Developer ID Application: GEORGE NACHMAN" -f "build/$BUILDTYPE/iTerm2.app/Contents/Frameworks/ColorPicker.framework"
  codesign -s "Developer ID Application: GEORGE NACHMAN" -f "build/$BUILDTYPE/iTerm2.app"
  codesign --verify --verbose "build/$BUILDTYPE/iTerm2.app" || die "Signature not verified"
  pushd "build/$BUILDTYPE"
 
  # Create the zip file
  # For the purposes of auto-update, the app's folder must be named iTerm.app
  # since Sparkle won't accept a name change.
  rm -rf iTerm.app
  mv iTerm2.app iTerm.app
  zip -ry iTerm2-${NAME}.zip iTerm.app
 
  # Update the list of changes
  vi $SVNDIR/source/appcasts/testing_changes3.txt
 
  # Place files in website git.
  cp iTerm2-${NAME}.zip $SVNDIR/downloads/beta/
 
  test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.summary || (echo "iTerm2 "$VERSION" beta ($SUMMARY)" > $SVNDIR/downloads/beta/iTerm2-${NAME}.summary)
  test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.description || (echo "$DESCRIPTION" > $SVNDIR/downloads/beta/iTerm2-${NAME}.description)
  vi $SVNDIR/downloads/beta/iTerm2-${NAME}.description
  echo 'SHA-256 of the zip file is' > $SVNDIR/downloads/beta/iTerm2-${NAME}.changelog
  shasum -a256 iTerm2-${NAME}.zip | awk '{print $1}' >> $SVNDIR/downloads/beta/iTerm2-${NAME}.changelog
  vi $SVNDIR/downloads/beta/iTerm2-${NAME}.changelog
  pushd $SVNDIR
  git add downloads/beta/iTerm2-${NAME}.summary downloads/beta/iTerm2-${NAME}.description downloads/beta/iTerm2-${NAME}.changelog downloads/beta/iTerm2-${NAME}.zip source/appcasts/testing3.xml source/appcasts/testing_changes3.txt
  popd

  # Prepare the sparkle xml file
  SparkleSign ${SPARKLE_PREFIX}testing3.xml ${SPARKLE_PREFIX}template3.xml

  popd
}

COMPACTDATE=$(date +"%Y%m%d")
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
SVNDIR=~/iterm2-website
ORIG_DIR=`pwd`

echo "Build deployment release"
make clean
make preview
Build Deployment "-preview" "OS 10.8+" "This is the recommended beta build for most users. It contains a bunch of bug fixes, including fixes for some crashers." "" "--deep"

#set -x

git tag v${VERSION}-preview
git commit -am ${VERSION}-preview
git push origin master
git push --tags
cd $SVNDIR
git commit -am v${VERSION}-preview
git push origin master

