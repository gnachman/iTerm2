#!/bin/sh
PB=/usr/libexec/PlistBuddy

getVersion() {
	cat version.txt
}

setBundleVersion() {
	VERSION="$1"
	APPDIR="$2"
	PLISTFILE="$APPDIR/Contents/Info.plist"
	if [ -f "${PLISTFILE}" ]; then
		$PB -c "Set :CFBundleVersion ${VERSION}" ${PLISTFILE}
		$PB -c "Set :CFBundleShortVersionString ${VERSION}" "${PLISTFILE}"
		codesign --force --options runtime --sign - --entitlements Therm.entitlements "$APPDIR"
	else
		echo "Ignore $APPDIR"
	fi
}

setVersion() {
	VERSION="$1"
	echo $VERSION > version.txt
	echo "#define THERM_VERSION \"$VERSION\"" > config.h
	[ -d 'build/Deployment/Therm.app' ] && \
		setBundleVersion $VERSION 'build/Deployment/Therm.app'
	[ -d 'build/Development/Therm.app' ] && \
		setBundleVersion $VERSION 'build/Development/Therm.app'
}

if [ -z "$1" ]; then
	getVersion
elif [ "$1" = "-f" ]; then
	setVersion `getVersion`
else
	setVersion "$1"
fi
