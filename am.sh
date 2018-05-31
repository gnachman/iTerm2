#!/bin/sh

(
cd ../it2
rm -f /tmp/00*
git format-patch $1^..$1
mv 00* /tmp
)

git am --abort
F=`ls /tmp/00*`
git am < $F
