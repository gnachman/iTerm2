#!/bin/bash

set -x

function die {
  echo $1
  exit
}

if [ $# -ne 1 ]; then
   echo "Usage: release_beta.sh version"
   exit 1
fi

echo Enter the EdDSA private key
read -s EDPRIVKEY

echo Enter the notarization password
read -s NOTPASS

# Usage: SparkleSign testing.xml template.xml
function SparkleSign {
    LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')

    ../../tools/sign_update iTerm2-${NAME}.zip "$EDPRIVKEY" > /tmp/newsig.txt || die SparkleSignNew
    echo "New signature is"
    cat /tmp/newsig.txt

    NEWSIG=$(cat /tmp/newsig.txt)
    DATE=$(date +"%a, %d %b %Y %H:%M:%S %z")
    XML=$1
    TEMPLATE=$2
    cp $SVNDIR/source/appcasts/${TEMPLATE} /tmp
    cat /tmp/${TEMPLATE} | \
    sed -e "s/%XML%/${XML}/" | \
    sed -e "s/%VER%/${VERSION}/" | \
    sed -e "s/%DATE%/${DATE}/" | \
    sed -e "s/%NAME%/${NAME}/" | \
    sed -e "s/%LENGTH%/$LENGTH/" | \
    sed -e "s,%NEWSIG%,${NEWSIG}," > $SVNDIR/source/appcasts/$1

    echo "Updated appcasts file $SVNDIR/source/appcasts/$1"
    cat $SVNDIR/source/appcasts/$1
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

  # Zip it, notarize it, staple it, and re-zip it.
  PRENOTARIZED_ZIP=iTerm2-${NAME}-prenotarized.zip
  zip -ry $PRENOTARIZED_ZIP iTerm.app
  xcrun altool --notarize-app --primary-bundle-id "com.googlecode.iterm2" --username "apple@georgester.com" --password "$NOTPASS" --file $PRENOTARIZED_ZIP > /tmp/upload.out 2>&1 || die "Notarization failed"
  UUID=$(grep RequestUUID /tmp/upload.out | sed -e 's/RequestUUID = //')
  echo "uuid is $UUID"
  xcrun altool --notarization-info $UUID -u "apple@georgester.com" -p "$NOTPASS"
  sleep 1
  while xcrun altool --notarization-info $UUID -u "apple@georgester.com" -p "$NOTPASS" 2>&1 | egrep -i "in progress|Could not find the RequestUUID":
  do
      echo "Trying again"
      sleep 1
  done
  NOTARIZED_ZIP=iTerm2-${NAME}.zip
  xcrun stapler staple iTerm.app
  zip -ry $NOTARIZED_ZIP iTerm.app

  # Update the list of changes
  vi $SVNDIR/source/appcasts/testing_changes3.txt
 
  # Place files in website git.
  cp iTerm2-${NAME}.zip $SVNDIR/downloads/beta/
 
  test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.summary || (echo "iTerm2 "$VERSION" ($SUMMARY)" > $SVNDIR/downloads/beta/iTerm2-${NAME}.summary)
  test -f $SVNDIR/downloads/beta/iTerm2-${NAME}.description || (echo "$DESCRIPTION" > $SVNDIR/downloads/beta/iTerm2-${NAME}.description)
  vi $SVNDIR/downloads/beta/iTerm2-${NAME}.description
  rm -f /tmp/sum /tmp/sum.asc
  shasum -a256 iTerm2-${NAME}.zip | awk '{print $1}' > /tmp/sum
  gpg --clearsign /tmp/sum
  echo "You can use the following to verify the zip file on https://keybase.io/verify:" > $SVNDIR/downloads/beta/iTerm2-${NAME}.changelog
  echo "" >> $SVNDIR/downloads/beta/iTerm2-${NAME}.changelog
  cat /tmp/sum.asc >> $SVNDIR/downloads/beta/iTerm2-${NAME}.changelog
  vi $SVNDIR/downloads/beta/iTerm2-${NAME}.changelog
  pushd $SVNDIR
  git add downloads/beta/iTerm2-${NAME}.summary downloads/beta/iTerm2-${NAME}.description downloads/beta/iTerm2-${NAME}.changelog downloads/beta/iTerm2-${NAME}.zip source/appcasts/testing3_new.xml source/appcasts/testing3_modern.xml source/appcasts/testing_changes3.txt
  popd

  # Transitional
  SparkleSign ${SPARKLE_PREFIX}testing3_new.xml ${SPARKLE_PREFIX}template3_new.xml
  # Modern
  SparkleSign ${SPARKLE_PREFIX}testing3_modern.xml ${SPARKLE_PREFIX}template3_modern.xml

  # Copy experiment to control
  cp $SVNDIR/source/appcasts/${SPARKLE_PREFIX}testing3_new.xml    $SVNDIR/source/appcasts/${SPARKLE_PREFIX}testing_new.xml
  cp $SVNDIR/source/appcasts/${SPARKLE_PREFIX}testing3_modern.xml $SVNDIR/source/appcasts/${SPARKLE_PREFIX}testing_modern.xml

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
make -j8 Beta

BUILDTYPE=Beta

Build $BUILDTYPE "" "OS 10.15+" "This is the recommended beta build for most users." "" "--deep"

git checkout -- version.txt
#set -x

git tag v${VERSION}
git commit -am ${VERSION}
git push origin master
git push --tags
cd $SVNDIR
git commit -am v${VERSION}
git push origin master
