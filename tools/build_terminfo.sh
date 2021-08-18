#!/bin/bash

# To update terminfo, download xterm's source, copy terminfo into
# Resources/terminfo, remove syntax errors (like duplicate definitions) and add
# back undercurl.

rm -rf Resources/terminfo
mkdir Resources/terminfo
tic -x -o Resources/terminfo Resources/xterm-terminfo
