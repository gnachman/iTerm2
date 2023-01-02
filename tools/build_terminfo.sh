#!/bin/bash

# To update terminfo, download xterm's source, copy terminfo into
# Resources/terminfo, remove syntax errors (like duplicate definitions) and add
# back undercurl.

rm -rf Resources/terminfo
mkdir Resources/terminfo

/usr/bin/tic -x -o Resources/terminfo Resources/xterm-terminfo
/usr/bin/tic -x -o Resources/terminfo Resources/tmux-terminfo

export TERMINFO_DIRS=$(pwd)/Resources/terminfo
infocmp xterm
infocmp xterm-new
infocmp xterm-256color
infocmp tmux-256color
