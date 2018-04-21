#!/bin/bash
# Usage: build_iterm2env.sh path_to_virtualenv

set -x

SOURCE=venv
DEST=iterm2env

rm -rf "$SOURCE"
virtualenv -p python3.6 $SOURCE
source venv/bin/activate
pip3.6 install websockets
pip3.6 install protobuf
pip3.6 install iterm2

rsync $SOURCE/ $DEST/ -a --copy-links -v

fdupes -r -1 $DEST | while read line
do
  master=""
  for file in ${line[*]}
  do
    if [ "x${master}" == "x" ]
    then
      master=$file
    else
      ln -f "${master}" "${file}"
    fi
  done
done

find $DEST | grep -E '(__pycache__|\.pyc|\.pyo$)' | xargs rm -rf
rm -rf $DEST/lib/python3.6/site-packages/pip
rm -rf $DEST/lib/python3.6/site-packages/setuptools
rm -rf $DEST/lib/python3.6/site-packages/wheel
rm -rf $DEST/lib/python3.6/site-packages/pip-7.1.2.dist-info/
rm -rf $DEST/lib/python3.6/site-packages/setuptools-18.2.dist-info/
rm -rf $DEST/lib/python3.6/site-packages/wheel-0.24.0.dist-info/
rm -rf $DEST/lib/python3.6/distutils
rm -rf "$SOURCE"
