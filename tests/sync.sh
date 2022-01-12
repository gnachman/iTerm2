#!/bin/bash

echo ']4;-1;rgb:ff/ff/ff'
echo Hello world should appear at once.

sleep 1

# Hide cursor - implicit sync if feature enabled
echo '[?25l'
echo hello
sleep .05
echo world
echo '[?25h'

sleep 1
echo Hello world should appear and turn red at once.

# begin sync
echo P=1s\\
echo ']4;-1;rgb:ff/00/00'
echo hello
sleep .5
echo world
echo P=2s\\
#end sync

sleep .5

echo ']4;-1;rgb:ff/ff/ff'
