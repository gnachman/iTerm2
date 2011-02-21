#!/bin/bash
# Run this before uploading.
NAME=$1
cd build/Deployment
NAME=`date +'iTerm2-nightly-%Y-%m-%d.zip'`
zip -r $NAME iTerm.app
echo `pwd`/$NAME
