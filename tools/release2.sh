#!/bin/bash
NAME=$1
export EDITOR=vi
svn copy -m $NAME trunk https://iterm2.googlecode.com/svn/tags/$NAME
cp trunk/appcasts/* fork/appcasts/
echo Run this:
echo cd trunk
echo svn commit -m \"$NAME trunk\"
echo cd ../fork
echo svn commit -m \"$NAME fork\"
