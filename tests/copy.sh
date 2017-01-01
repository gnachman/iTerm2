#!/bin/bash

trap clean_up EXIT
_STTY=$(stty -g)      ## Save current terminal setup
stty -echo            ## Turn off echo

function clean_up() {
  stty "$_STTY"            ## Restore terminal settings
}

function show_help() {
  echo "Usage: $(basename $0)" 1>& 2
}

# tmux requires unrecognized OSC sequences to be wrapped with DCS tmux;
# <sequence> ST, and for all ESCs in <sequence> to be replaced with ESC ESC. It
# only accepts ESC backslash for ST.
function print_osc() {
    if [[ $TERM == screen* ]] ; then
        printf "\033Ptmux;\033\033]"
    else
        printf "\033]"
    fi
}

# More of the tmux workaround described above.
function print_st() {
    if [[ $TERM == screen* ]] ; then
        printf "\a\033\\"
    else
        printf "\a"
    fi
}

print_osc
printf '1337;Copy=:'
base64
print_st
