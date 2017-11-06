#!/bin/bash
function die {
  echo $1
  exit
}

if [ $# -ne 1 ]; then
   echo "Usage: release_beta.sh version"
   exit 1
fi

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

# First arg is build directory name (e.g., Beta)
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
  codesign --verify --verbose "build/$BUILDTYPE/iTerm2.app" || die "Signature not verified"
  codesign -dv --verbose=4 "build/$BUILDTYPE/iTerm2.app" > /tmp/signature 2>&1
  cat /tmp/signature | fgrep 'Authority=Developer ID Application: GEORGE NACHMAN (H7V7XYVQ7D)' || die "Not signed with the right certificate"
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
 
  test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.summary || (echo "iTerm2 "$VERSION" ($SUMMARY)" > $SVNDIR/downloads/beta/iTerm2-${NAME}.summary)
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

echo "$1" > version.txt
echo Set version to
cat version.txt

COMPACTDATE=$(date +"%Y%m%d")
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
SVNDIR=~/iterm2-website
ORIG_DIR=`pwd`


echo "Build beta release"
make clean
make Beta

BUILDTYPE=Beta

Build $BUILDTYPE "" "OS 10.10+" "This is the recommended beta build for most users." "" "--deep"

git checkout -- version.txt
#set -x

git tag v${VERSION}
git commit -am ${VERSION}
git push origin master
git push --tags
cd $SVNDIR
git commit -am v${VERSION}
git push origin master

