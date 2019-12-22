#!/bin/bash

function die {
  echo $1
  exit
}

branch() {
  local output=$(git symbolic-ref -q --short HEAD)
    if [ $? -eq 0 ]; then
        echo "${output}"
    fi
}

set -x

WEBSITE=~/iterm2-website
test -d $WEBSITE || die No $WEBSITE directory
pushd $WEBSITE
if [ $(branch) != master ]; then
  die "Not on master"
fi
popd

cp $WEBSITE/source/shell_integration/bash Resources/shell_integration/iterm2_shell_integration.bash
cp $WEBSITE/source/shell_integration/fish Resources/shell_integration/iterm2_shell_integration.fish
cp $WEBSITE/source/shell_integration/tcsh Resources/shell_integration/iterm2_shell_integration.tcsh
cp $WEBSITE/source/shell_integration/zsh  Resources/shell_integration/iterm2_shell_integration.zsh
DEST=$PWD/Resources/utilities

pushd $WEBSITE/source/utilities
files=$(find . -type f)
tar cvfz $DEST/utilities.tgz *
echo * > $DEST/utilities-manifest.txt
popd

