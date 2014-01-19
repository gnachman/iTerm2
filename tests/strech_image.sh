#!/bin/bash
if [ $# -ne 3 ]; then
  echo "Usage: strech_image.sh filename width height"
  exit 1
fi
if [ -a "$1" ]; then
  printf '\033]1337;BeginFile='"$1"'\n'
  wc -c "$1" | awk '{print $1}'
  echo $2
  echo $3
  echo 1
  printf '\a'
  base64 < "$1"
  printf '\033]1337;EndFile\a'
  exit 0
fi

echo File $1 does not exist.
exit 1
