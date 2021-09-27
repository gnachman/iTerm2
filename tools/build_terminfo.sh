#!/bin/bash

# To update terminfo, download xterm's source, copy terminfo into
# Resources/terminfo, remove syntax errors (like duplicate definitions) and add
# back undercurl.

rm -rf Resources/terminfo
mkdir Resources/terminfo

currentver="$(tic -V | cut -d' ' -f2)"
minver="6.1"
if [ "$(printf '%s\n' "$minver" "$currentver" | sort -V | tail -n1)" = "$minver" ]; then
    # Older versions of tic suffer from integer overflow for values at least
    # 2^16 which is a problem for xterm-256color's pairs#65536.
    echo "tic 6.1 or later is needed. You have " $(tic -V) at $(which tic) with PATH $PATH
    echo "You probably want to do this:"
    echo 'set path=(/usr/local/Cellar/ncurses/6.2/bin $path)'
    exit 1
fi

tic -x -o Resources/terminfo Resources/xterm-terminfo
export TERMINFO_DIRS=$(pwd)/Resources/terminfo
infocmp xterm
infocmp xterm-new
infocmp xterm-256color
