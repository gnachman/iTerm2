#!/bin/bash
set -x
NAME=$1
export EDITOR=vi
svn copy -m $NAME trunk https://iterm2.googlecode.com/svn/tags/$NAME
cp trunk/appcasts/* fork/appcasts/
echo Run this:
svn commit -m $NAME
