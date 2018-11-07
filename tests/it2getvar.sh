#!/bin/bash

function ctrl_c() {
  stty "$saved_stty"
  exit 1
}

# tmux requires unrecognized OSC sequences to be wrapped with DCS tmux;
# <sequence> ST, and for all ESCs in <sequence> to be replaced with ESC ESC. It
# only accepts ESC backslash for ST.
function print_osc() {
    if [[ $TERM == screen* ]] ; then printf "\033Ptmux;\033\033]"
    else
        printf "\033]" >& 2
    fi
}

# More of the tmux workaround described above.
function print_st() {
    if [[ $TERM == screen* ]] ; then
        printf "\a\033\\" >& 2
    else
        printf "\a" >& 2
    fi
}

function show_help() {
    echo "Usage:" 1>& 2
    echo "   $(basename $0) name" 1>& 2
}

# Read some bytes from stdin. Pass the number of bytes to read as the first argument.
function read_bytes() {
  numbytes=$1
  dd bs=1 count=$numbytes 2>/dev/null
}

# read_until c
# Returns bytes read from stdin up to but not including the fist one equal to c
function read_until() {
  result=""
  while :
  do
    b=$(read_bytes 1)
    if [[ $b == $1 ]]
    then
      echo "$result"
      return
    fi
    result="$result$b"
  done
}

## Main
if [[ $# != 1 ]]
then
  show_help
  exit 1
fi

if ! test -t 1
then
  echo "Standard error not a terminal"
  exit 1
fi

# Save the tty's state.
saved_stty=$(stty -g)

# Trap ^C to fix the tty.
trap ctrl_c INT

# Enter raw mode and turn off echo so the terminal and I can chat quietly.
stty -echo -icanon raw

print_osc
printf "1337;ReportVariable=%s" "$(printf "%s" "$1" | base64)" >& 2
print_st

VERSION=$(base64 --version 2>&1)
if [[ "$VERSION" =~ fourmilab ]]; then
  BASE64ARG=-d
elif [[ "$VERSION" =~ GNU ]]; then
  BASE64ARG=-di
else
  BASE64ARG=-D
fi

ignore=$(read_bytes 1)
name=$(read_until )
re='^]1337;ReportVariable=(.*)'
if [[ $name =~ $re ]]
then
  printf "%s" $(base64 $BASE64ARG <<< ${BASH_REMATCH[1]})
  exit 0
else
  exit 1
fi

