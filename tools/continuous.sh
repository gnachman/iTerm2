#!/bin/bash

set -x
cd ~/continuous/iTerm2/
echo Check for updates...
git pull origin master | grep "Already up-to-date." && exit
echo Check for build failure...
(make Nightly > /tmp/continuous.out 2>&1) && exit
echo "Build failed; send mail."
cat /tmp/continuous | mail -s "Continuous build failure" gnachman@gmail.com
