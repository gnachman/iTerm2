#!/bin/bash

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

function show_help() {
    echo "Usage:" 1>& 2
    echo "   it2setkeylabel.sh set Fn Label" 1>& 2
    echo "     Where n is a value from 1 to 20" 1>& 2
    echo "   it2setkeylabel.sh push" 1>& 2
    echo "   it2setkeylabel.sh pop" 1>& 2
}

## Main
if [[ $# == 0 ]]
then
  show_help
  exit 1
fi

if [[ $1 == set ]]
then
  if [[ $# != 3 ]]
  then
    show_help
    exit 1
  fi
  print_osc
  printf "1337;SetKeyLabel=%s=%s" "$2" "$3"
  print_st
elif [[ $1 == push ]]
then
  if [[ $# != 1 ]]
  then
    show_help
    exit 1
  fi
  print_osc
  printf "1337;PushKeyLabels"
  print_st
elif [[ $1 == pop ]]
then
  if [[ $# != 1 ]]
  then
    show_help
    exit 1
  fi
  print_osc
  printf "1337;PopKeyLabels"
  print_st
else
  show_help
  exit 1
fi
