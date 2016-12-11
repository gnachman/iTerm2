#!/bin/bash
#@ Copyright: © 2011 Chris F.A. Johnson
#@ Released under the terms of the GNU General Public License V2
#@ See the file COPYING for the full license
# Originally from http://cfajohnson.com/shell/listing1.txt
# Hacked to be completley different by George Nachman

read_bytes()
{
  numbytes=$1
  dd bs=1 count=$numbytes 2>/dev/null
}

is_decimal_digit()
{
  c="$1"
  n=$(printf "%d" "'$c'")
  printf "%s" $(( $n >= 48 && $n < 58 ))
}

# Decimals plus .
is_float_digit()
{
  c="$1"
  n=$(printf "%d" "'$c'")
  printf "%s" $(( $n >= 48 && $n < 58 || $n == 46 ))
}

read_decimal()
{
  c=$(read_bytes 1)
  while [ $(is_decimal_digit "$c") -eq 1 ]; do
    printf "%s" "$c"
    c=$(read_bytes 1)
  done
}

# Ignores part after the decimal point
read_float()
{
  c=$(read_bytes 1)
  while [ $(is_decimal_digit "$c") -eq 1 ]; do
    printf "%s" "$c"
    c=$(read_bytes 1)
  done
  # Ignore anything after the decimal point
  while [ $(is_float_digit "$c") -eq 1 ]; do
    c=$(read_bytes 1)
  done
}

clean_up()
{
  stty "$_STTY"            ## Restore terminal settings
}

trap clean_up EXIT

_STTY=$(stty -g)      ## Save current terminal setup
stty -echo -icanon    ## Turn off line buffering

# Get window size
echo -n '[14t'

# CSI 4 ; height ; width t
spam=$(read_bytes 4)
pixel_height=$(read_decimal)
pixel_width=$(read_decimal)

# Get session size
echo -n '[18t'

# CSI 8 ; height ; width t
spam=$(read_bytes 4)
char_height=$(read_decimal)
char_width=$(read_decimal)

# Get cell size
echo -n ']1337;ReportCellSize'

# OSC 1337;ReportCellSize= height ; width ST
spam=$(read_bytes 22)
cell_height=$(read_float)
cell_width=$(read_float)
spam=$(read_bytes 1)

echo Window pixel size: $pixel_width x $pixel_height
echo Session size: $char_width x $char_height
echo Cell size: $cell_width x $cell_height

echo ""
echo Fullscreen window stats:
echo Extra space below: $(($pixel_height - 4 - $char_height * $cell_height))
echo Extra space on right: $(($pixel_width - 10 - $char_width * $cell_width))

