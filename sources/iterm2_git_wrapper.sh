#!/bin/bash

echo "$ cd $PWD"
echo "$ git" "$@"
echo ""
echo -n $'\e[m'
echo -n $'\e]0;git '"$@"$'\e\\'
echo ""

git "$@" && exit 0

echo $'\e]1337;Disinter\e\\'
echo -n $'\e[7m'
echo -n "An error occurred while running 'git " "$@" "'."
echo $'\e[m'
echo "You may safely close this window."

while true
do
    read
done
