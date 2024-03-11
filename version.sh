#!/bin/sh
PB=/usr/libexec/PlistBuddy

getVersion() {
	cat version.txt
}

setBundleVersion() {
	VERSION="$1"
	APPPATH="$2"
	$PB -c "Set :CFBundleVersion ${VERSION}" "${APPPATH}/Contents/Info.plist"
	$PB -c "Set :CFBundleShortVersionString ${VERSION}" "${APPPATH}/Contents/Info.plist"
}

setVersion() {
	VERSION="$1"
	echo $VERSION > version.txt
	echo "#define THERM_VERSION \"$VERSION\"" > config.h
	setBundleVersion $VERSION 'build/Deployment/Therm.app'
	setBundleVersion $VERSION 'build/Development/Therm.app'
}

if [ -z "$1" ]; then
	getVersion
else
	setVersion "$1"
fi
