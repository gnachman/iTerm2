#!/bin/bash

function ctrl_c() {
  stty "$saved_stty"
  exit 1
}

# Read some bytes from stdin. Pass the number of bytes to read as the first argument.
function read_bytes() {
  numbytes=$1
  dd bs=1 count=$numbytes 2>/dev/null
}

function init() {
  # Make sure stdin and stdout are a tty.
  if [ ! -t 0 ] ; then
    exit 1
  fi
  if [ ! -t 1 ] ; then
    exit 1
  fi

  # Save the tty's state.
  saved_stty=$(stty -g)

  # Trap ^C to fix the tty.
  trap ctrl_c INT

  # Enter raw mode and turn off echo so the terminal and I can chat quietly.
  stty -echo -icanon raw
}

# Request the profile name
function send_title_request() {
  printf '\e[20t'
}

function read_osc() {
  boilerplate=$(read_bytes 2)
  result=''
  b=""
  tab=$(printf "\e")
  while :
  do
    last="$b"
    b=$(read_bytes 1)
    if [[ $last == $tab && $b == "\\" ]]
    then
      break
    elif [[ $last == $tab ]]
    then
      result="$result$last$b"
    elif [[ $b != $tab ]]
    then
      result="$result$b"
    fi
  done
  echo -n "$result"
}

function read_title_report() {
  body=$(read_osc)
  echo -n ${body:1}
}

init

# Request a report with the profile name
send_title_request

# Read teh response
value=$(read_title_report)

# Restore the terminal to cooked mode.
stty "$saved_stty"

# Print the profile name
echo "$value"
