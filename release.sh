#!/bin/bash
set -x
function PrintUsageAndDie {
  echo Usage:
  echo release.sh 'normal|legacy'
  exit
}

function die {
  echo $1
  exit
}

# Usage: SparkleSign testing.xml template.xml
function SparkleSign {
    LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')
    test -f "$PRIVKEY" || die "Set PRIVKEY environment variable to point at a valid private key (not set or nonexistent)"
    ruby "../../SparkleSigningTools/sign_update.rb" iTerm2-${NAME}.zip $PRIVKEY > /tmp/sig.txt
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
  codesign --verbose --force --sign 'Developer ID Application: GEORGE NACHMAN' "build/$BUILDTYPE/iTerm.app/Contents/Frameworks/Sparkle.framework" || die Signing
  codesign --verbose --force --sign 'Developer ID Application: GEORGE NACHMAN' "build/$BUILDTYPE/iTerm.app/Contents/Frameworks/Growl.framework" || die Signing
  codesign --verbose --force --sign 'Developer ID Application: GEORGE NACHMAN' "build/$BUILDTYPE/iTerm.app" || die Signing
  # Commented out because it crashes on 10.10
  #codesign --verify --verbose "build/$BUILDTYPE/iTerm.app" || die "Signature not verified"
  pushd "build/$BUILDTYPE"

  # Create the zip file
  zip -ry iTerm2-${NAME}.zip iTerm.app

  # Update the list of changes
  vi $SVNDIR/source/appcasts/testing_changes.txt

  # Place files in website git.
  cp iTerm2-${NAME}.zip $SVNDIR/downloads/beta/

  test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.summary || (echo "iTerm2 "$VERSION" beta ($SUMMARY)" > $SVNDIR/downloads/beta/iTerm2-${NAME}.summary)
  test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.description || (echo "$DESCRIPTION" > $SVNDIR/downloads/beta/iTerm2-${NAME}.description)
  vi $SVNDIR/downloads/beta/iTerm2-${NAME}.description
  vi $SVNDIR/downloads/beta/iTerm2-${NAME}.changelog
  echo cd $SVNDIR
  echo git add "downloads/beta/iTerm2-${NAME}.summary downloads/beta/iTerm2-${NAME}.description downloads/beta/iTerm2-${NAME}.changelog downloads/beta/iTerm2-${NAME}.zip source/appcasts/testing.xml source/appcasts/testing_changes.txt"

  # Prepare the sparkle xml file
  SparkleSign ${SPARKLE_PREFIX}testing.xml ${SPARKLE_PREFIX}template.xml

  popd
}

COMPACTDATE=$(date +"%Y%m%d")
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
SVNDIR=~/iterm2-website
ORIG_DIR=`pwd`
NEWFILES=""

[ $# -gt 0 ] || PrintUsageAndDie
if [ "$1" = normal ]; then
    echo "Build deployment release"
    make release
    Build Deployment "" "OS 10.7+, Intel-only" "This is the recommended beta build for most users. It contains a bunch of bug fixes, including fixes for some crashers, plus some minor performance improvements." "" "--deep"
fi

if [ "$1" = legacy ]; then
    echo "Build legacy release"
    make legacy
    Build "Leopard Deployment" "-LeopardPPC" "OS 10.6, Intel, PPC" "This build has a limited set of features but supports OS 10.6 and PowerPC. If you have an Intel Mac that runs OS 10.7 or newer, you don't want this." "legacy_" ""
fi

#set -x

echo "git tag v${VERSION}"
echo "git commit -am ${VERSION}"
echo "git push origin v2"
echo "git push --tags"
echo "cd "$SVNDIR
echo "git add "$NEWFILES
echo "git commit -am v${VERSION}"
echo "git push origin master"
