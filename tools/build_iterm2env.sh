#!/bin/bash
# Usage: build_iterm2env.sh path_to_virtualenv

set -x

SOURCE=$(pwd)/venv
DEST=iterm2env

rm -rf "$SOURCE"

VERSION=3.6.5

rm -rf /tmp/pyenv
git clone https://github.com/pyenv/pyenv.git /tmp/pyenv
export PYENV_ROOT=$SOURCE
# If this fails complaining about missing a library like zlib, do: xcode-select --install
/tmp/pyenv/bin/pyenv install $VERSION
export PATH=$PYENV_ROOT/versions/$VERSION/bin:$PATH
pip3 install websockets
pip3 install protobuf
pip3 install iterm2

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

rm -f $DEST/shims/2to3*
rm -f $DEST/shims/easy_install*
rm -f $DEST/shims/idle*
rm -f $DEST/shims/pip*
rm -f $DEST/shims/pydoc*
rm -f $DEST/shims/pyen

rm -f $DEST/versions/$VERSION/bin/2to3*
rm -f $DEST/versions/$VERSION/bin/easy_install*
rm -f $DEST/versions/$VERSION/bin/idle*
rm -f $DEST/versions/$VERSION/bin/pip*
rm -f $DEST/versions/$VERSION/bin/pydoc*
rm -f $DEST/versions/$VERSION/bin/pyen
rm -rf $DEST/versions/$VERSION/bin/pyen
rm -rf $DEST/versions/$VERSION/include
rm -rf $DEST/versions/$VERSION/share
rm -rf $DEST/versions/$VERSION/lib/pkgconfig
rm -rf $DEST/versions/$VERSION/lib/python3.6/test
rm -rf $DEST/versions/$VERSION/lib/python3.6/site-packages/easy_install.py
rm -rf $DEST/versions/$VERSION/lib/python3.6/site-packages/*dist-info
rm -rf $DEST/versions/$VERSION/lib/python3.6/site-packages/pip
rm -rf $DEST/versions/$VERSION/lib/python3.6/site-packages/pkg_resources
rm -rf $DEST/versions/$VERSION/lib/python3.6/site-packages/setuptools
rm -rf $DEST/versions/$VERSION/lib/python3.6/config-*
rm -rf $DEST/versions/$VERSION/lib/python3.6/distutils
rm -rf $DEST/versions/$VERSION/lib/python3.6/ensurepip
rm -rf $DEST/versions/$VERSION/lib/python3.6/idlelib
rm -rf $DEST/versions/$VERSION/lib/python3.6/lib2to3
rm -rf $DEST/versions/$VERSION/lib/python3.6/tkinter
rm -rf $DEST/versions/$VERSION/lib/python3.6/pydoc_data
rm -rf $DEST/versions/$VERSION/lib/python3.6/unittest
find $DEST | grep -E '(__pycache__|\.pyc|\.pyo$)' | xargs rm -rf
rm -rf "$SOURCE"
