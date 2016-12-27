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

function read_terminfo_string_response() {
  # Reading response to request termcap/terminfo string.
  # DCS 11 + r Key = Value St

  boilerplate=$(read_bytes 5)

  key=$(read_until =)
  value=$(read_until )

  # Read the backslash
  boilerplate=$(read_bytes 1)
  echo $(hex_to_string $value)
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

# hex_to_string aabbcc...
# Converts hex digits to a string.
function hex_to_string() {
  result=""
  hex=$1
  while [[ $hex != "" ]]
  do
    b=$(hex_to_dec ${hex:0:2})
    result=$result$(printf $(printf '\%o' $b))
    hex=${hex:2}
  done
  echo -n "$result"
}

# hex_to_dec [0-9a-f]*
function hex_to_dec() {
  echo $((16#$1))
}

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

# Request the profile name
function send_terminfo_string_request() {
  printf '\eP+q%s\e\\' $(string_to_hex $1)
}

function string_to_hex() {
  echo -n "$1" | xxd -pu
}

# Request a report with the profile name
send_terminfo_string_request iTerm2Profile

# Read teh response
value=$(read_terminfo_string_response)

# Restore the terminal to cooked mode.
stty "$saved_stty"

# Print the profile name
echo "$value"
