#!/bin/bash

set -x

function die {
  echo $1
  exit
}

if [ $# -ne 1 ]; then
   echo "Usage: release_stable.sh version"
   exit 1
fi

test -f "$PRIVKEY" || die "Set PRIVKEY environment variable to point at a valid private key (not set or nonexistent)"
echo Enter the EdDSA private key
read -s EDPRIVKEY

echo Enter the notarization password
read -s NOTPASS

# Usage: SparkleSign final.xml final_template.xml
function SparkleSign {
    LENGTH=$(ls -l iTerm2-${NAME}.zip | awk '{print $5}')
    ruby "../../ThirdParty/SparkleSigningTools/sign_update.rb" iTerm2-${NAME}.zip $PRIVKEY > /tmp/sig.txt || die SparkleSign
    echo "Signature is "
    cat /tmp/sig.txt
    actualsize=$(wc -c < /tmp/sig.txt)
    if (( $actualsize < 60)); then
        die "signature file too small"
    fi

    ../../tools/sign_update iTerm2-${NAME}.zip "$EDPRIVKEY" > /tmp/newsig.txt || die SparkleSignNew
    echo "New signature is"
    cat /tmp/newsig.txt

    SIG=$(cat /tmp/sig.txt)
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
    sed -e "s,%SIG%,${SIG}," | \
    sed -e "s,%NEWSIG%,${NEWSIG}," > $SVNDIR/source/appcasts/$1

    echo "Updated appcasts file $SVNDIR/source/appcasts/$1"
    cat $SVNDIR/source/appcasts/$1
    cp iTerm2-${NAME}.zip ~/iterm2-website/downloads/stable/
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
  xcrun altool --notarize-app --primary-bundle-id "com.googlecode.iterm2" --username "apple@georgester.com" --password "$NOTPASS" --file $PRENOTARIZED_ZIP > /tmp/upload.out 2>&1
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
  vi $SVNDIR/source/appcasts/full_changes.txt
 
  # Place files in website git.
  cp iTerm2-${NAME}.zip $SVNDIR/downloads/stable/
 
  test -f $SVNDIR/downloads/stable/iTerm2-${NAME}.summary || (echo "iTerm2 "$VERSION" ($SUMMARY)" > $SVNDIR/downloads/stable/iTerm2-${NAME}.summary)
  test -f $SVNDIR/downloads/stable/iTerm2-${NAME}.description || (echo "$DESCRIPTION" > $SVNDIR/downloads/stable/iTerm2-${NAME}.description)
  vi $SVNDIR/downloads/stable/iTerm2-${NAME}.description
  echo 'SHA-256 of the zip file is' > $SVNDIR/downloads/stable/iTerm2-${NAME}.changelog
  shasum -a256 iTerm2-${NAME}.zip | awk '{print $1}' >> $SVNDIR/downloads/stable/iTerm2-${NAME}.changelog
  vi $SVNDIR/downloads/stable/iTerm2-${NAME}.changelog
  pushd $SVNDIR

  echo 'Options +FollowSymlinks' > ~/iterm2-website/downloads/stable/.htaccess
  echo 'Redirect 302 /downloads/stable/latest https://iterm2.com/downloads/stable/iTerm2-'${NAME}'.zip' >> ~/iterm2-website/downloads/stable/.htaccess

  git add downloads/stable/iTerm2-${NAME}.summary downloads/stable/iTerm2-${NAME}.description downloads/stable/iTerm2-${NAME}.changelog downloads/stable/iTerm2-${NAME}.zip source/appcasts/final.xml source/appcasts/final_new.xml source/appcasts/final_modern.xml source/appcasts/full_changes.txt downloads/stable/.htaccess
  popd

  # Legacy
  SparkleSign ${SPARKLE_PREFIX}final.xml ${SPARKLE_PREFIX}final_template.xml
  # Transitional
  SparkleSign ${SPARKLE_PREFIX}final_new.xml ${SPARKLE_PREFIX}final_template_new.xml
  # Modern
  SparkleSign ${SPARKLE_PREFIX}final_modern.xml ${SPARKLE_PREFIX}final_template_modern.xml

  popd
}

echo "$1" > version.txt
echo Set version to
cat version.txt

COMPACTDATE=$(date +"%Y%m%d")
VERSION=$(cat version.txt | sed -e "s/%(extra)s/$COMPACTDATE/")
SVNDIR=~/iterm2-website
ORIG_DIR=`pwd`


echo "Build deployment release"
make clean
make release

BUILDTYPE=Deployment

Build $BUILDTYPE "" "OS 10.12+" "This is the recommended build for most users." "" "--deep"

git checkout -- version.txt
#set -x

git tag v${VERSION}
git commit -am ${VERSION}
#git push origin HEAD
#git push --tags
cd $SVNDIR
git commit -am v${VERSION}
#git push origin HEAD

