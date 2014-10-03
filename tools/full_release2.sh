#!/bin/bash
NAME=$1
export EDITOR=vi
svn copy -m $NAME trunk https://iterm2.googlecode.com/svn/tags/$NAME
echo Run this:
echo cd trunk
echo svn commit -m \"$NAME trunk\"
