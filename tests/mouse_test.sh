#!/bin/bash
#@ Copyright: © 2011 Chris F.A. Johnson
#@ Released under the terms of the GNU General Public License V2
#@ See the file COPYING for the full license
# Originally from http://cfajohnson.com/shell/listing1.txt

ESC="" ##  A literal escape character
x10_format="${ESC}[?1005l"  # Turn off extended xterm to get x10
utf8_format="${ESC}[?1005h"  # Extended format (UTF-8 encoding)
sgr_format="${ESC}[?1006h"  # CSI < button; Cx; Cy {M,m}
urxvt_format="${ESC}[?1015h"  # CSI decimal-button; Cx; Cy; M

output_mouse()
{
  printf "MOUSEX=%s MOUSEY=%s BUTTON=%s LAST=%s" "$1" "$2" "$3" "$4"
}

read_bytes()
{
  numbytes=$1
  dd bs=1 count=$numbytes 2>/dev/null
}

## Reads in a utf8 character and outputs its code point in decimal.
## e.g., é -> 233
is_decimal_digit()
{
  c="$1"
  n=$(printf "%d" "'$c'")
  printf "%s" $(( $n >= 48 && $n < 58 ))
}

read_sgr()
{
  prefix=$(read_bytes 3)   ## CSI <
  if [[ $prefix != "${ESC}[<" ]]; then
      printf "MOUSEX=- MOUSEY=- BUTTON=- LAST=-"
      return
  fi

  button=""
  cx=""
  cy=""

  c=$(read_bytes 1)
  while [ $(is_decimal_digit "$c") -eq 1 ]; do
    button="$button$c"
    c=$(read_bytes 1)
  done
  c=$(read_bytes 1)
  while [ $(is_decimal_digit "$c") -eq 1 ]; do
    cx="$cx$c"
    c=$(read_bytes 1)
  done
  c=$(read_bytes 1)
  while [ $(is_decimal_digit "$c") -eq 1 ]; do
    cy="$cy$c"
    c=$(read_bytes 1)
  done
  mode=$c

  output_mouse $cx $cy $button $mode
}

clean_up()
{
  printf "${ESC}[?1000;1001;1002;1003;1004;1005l"  ## Turn off mouse reporting
  stty "$_STTY"            ## Restore terminal settings
}

printat() ## USAGE: printat ROW COLUMN
{
    printf "${ESC}[${1};${2}H"
}

print_buttons()
{
   num_but=$#
   COLUMNS=${COLUMNS:-$(tput cols)}
   gutter=2
   gutters=$(( $num_but + 1 ))
   but_width=$(( ($COLUMNS - $gutters) / $num_but ))
   n=0
   for but_str
   do
     col=$(( $gutter + $n * ($but_width + $gutter) ))
     printat $but_row $col
     printf "${ESC}[7m%${but_width}s" " "
     printat $but_row $(( $col + ($but_width - ${#but_str}) / 2 ))
     printf "%.${but_width}s${ESC}[0m" "$but_str"
     n=$(( $n + 1 ))
   done
}

erase_line()
{
    printf "${ESC}[G${ESC}[K"
}

cursor_up()
{
    printf "${ESC}[A"
}

# $1 mode
# $2 name
tracking()
{
    erase_line
    echo "$2"
    printf "${ESC}[?$1h"
}

# $1 y
# $2 x
goto()
{
    printf "${ESC}[$1;$2H"
}

erase_below()
{
    printf "${ESC}[J"
}

cls()
{
    printf "${ESC}[2J"
    goto 1 1
}

# $1: description
# $2, $3, $4: expected params
# $5 M for down or m for up
do_test()
{
    X=$3
    Y=$4
    L=$5
    B=$2
    goto 4 1
    erase_below
    echo "$STATUS"
    echo $1

    while :
    do
        eval $(read_sgr)
        if [[ $MOUSEX == $X && $MOUSEY == $Y && $BUTTON == $B && $LAST == $L ]]; then
            export STATUS=$STATUS"P"
            export PASSES=$PASSES$1";"
            return
        elif [[ $MOUSEX > 13 && $MOUSEX < 23 && $MOUSEY == 2 && $BUTTON == 0 ]]; then
            if [[ $LAST == M ]]; then
                export STATUS=$STATUS"F"
                export FAILS=$FAILS$1";"
                return
            fi
        else
            erase_line
            printf "Wrong. Expected: button = $2 ; x = $3 ; y = $4 $L     Actual: button = $BUTTON ; x = $MOUSEX ; y = $MOUSEY $LAST"
        fi
    done
}

clear
echo ""
echo "  X          Skip test"

printf "[?1006h"  ## SGR
_STTY=$(stty -g)      ## Save current terminal setup
trap clean_up EXIT
stty -echo -icanon    ## Turn off line buffering

echo "Place the mouse cursor on the X and click as directed"
echo "Status:"
STATUS="Status: "
PASSES=""
FAILS=""

tracking 1000 "Normal tracking mode"
# Buttons
do_test "Left Mouse Down" 0 3 2 M
do_test "Left Mouse Up" 0 3 2 m
do_test "Right Mouse Down" 1 3 2 M
do_test "Right Mouse Up" 1 3 2 m
do_test "Middle Mouse Down" 2 3 2 M
do_test "Middle Mouse Up" 2 3 2 m
do_test "Scroll up" 64 3 2 M
do_test "Scroll down" 65 3 2 M

do_test "Shift + Left Mouse Down" 4 3 2 M
do_test "Meta + Left Mouse Down" 8 3 2 M
do_test "Shift + Meta + Left Mouse Down" 12 3 2 M
do_test "Control + Left Mouse Down" 16 3 2 M
do_test "Shift + Control + Left Mouse Down" 20 3 2 M
do_test "Meta + Control + Left Mouse Down" 24 3 2 M
do_test "Shift + Meta + Control + Left Mouse Down" 28 3 2 M

tracking 1002 "Button event tracking"
do_test "Drag mouse over X while left button is down" 32 3 2 M
do_test "Drag mouse over X while right button is down" 33 3 2 M
do_test "Drag mouse over X while middle button is down" 34 3 2 M

tracking 1003 "Any event tracking"
do_test "Move mouse over X with no button down" 35 3 2 M
do_test "Shift + Move mouse over X with no button down" 39 3 2 M

cls
echo Passed:
echo $PASSES | tr ";" "\n"

echo Failed:
echo $FAILS | tr ";" "\n"
