#!/bin/bash
#@ Copyright: © 2011 Chris F.A. Johnson
#@ Released under the terms of the GNU General Public License V2
#@ See the file COPYING for the full license

clean_up()
{
  printf "${ESC}[?${mv}l"  ## Turn off mouse reporting
  stty "$_STTY"            ## Restore terminal settings
  printf "${ESC}[?12l${ESC}[?25h" ## Turn cursor back on
  printf "\n${ESC}[0J\n"   ## Clear from cursor to bottom of screen
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

ESC="" ##  A literal escape character
but_row=1

clear
normal_tracking=1000  # Just button presses
# iterm2 doesn't support 1001, highlight tracking
button_tracking=1002 # clicks and drags are reported
any_event_tracking=1003 # clicks, drags, and motion

mv=$normal_tracking  ## I hacked this to use 1003 so everything is reported.
#printf "[?1006h"  ## SGR

trap clean_up EXIT

_STTY=$(stty -g)      ## Save current terminal setup
stty -echo -icanon    ## Turn off line buffering
printf "${ESC}[?${mv}h        "   ## Turn on mouse reporting
printf "${ESC}[?25l"  ## Turn off cursor

while :
do
  [ $mv -eq $normal_tracking ] && mv_str="Normal Tracking"
  [ $mv -eq $button_tracking ] && mv_str="Button Tracking"
  [ $mv -eq $any_event_tracking ] && mv_str="Any Event Tracking"

  print_buttons "$mv_str" "Exit"

  x=$(dd bs=1 count=6 2>/dev/null) ## Read six characters

  m1=${x#???}    ## Remove the first 3 characters
  m2=${x#????}   ## Remove the first 4 characters
  m3=${x#?????}  ## Remove the first 5 characters

  ## Convert to characters to decimal values
  eval "$(printf "mb=%d mx=%d my=%d" "'$m1" "'$m2" "'$m3")"

  ## Values > 127 are signed
  [ $mx -lt 0 ] && MOUSEX=$(( 223 + $mx )) || MOUSEX=$(( $mx - 32 ))
  [ $my -lt 0 ] && MOUSEY=$(( 223 + $my )) || MOUSEY=$(( $my - 32 ))

  ## Button pressed is in first 2 bytes; use bitwise AND
  BUTTON=$(( ($mb & 3) + 1 ))

  case $MOUSEY in
       $but_row) ## Calculate which on-screen button has been pressed
                 button=$(( ($MOUSEX - $gutter) / $but_width + 1 ))
                 case $button in
                      1) printf "${ESC}[?${mv}l"
                         [ $mv -eq $normal_tracking ] && next_mode=$button_tracking
                         [ $mv -eq $button_tracking ] && next_mode=$any_event_tracking
                         [ $mv -eq $any_event_tracking ] && next_mode=$normal_tracking
                         mv=$next_mode
                         printf "${ESC}[?${mv}h"
                         x=$(dd bs=1 count=6 2>/dev/null)
                         ;;
                      2) break ;;
                 esac
                 ;;
       *) printat $MOUSEY $MOUSEX
          printf "X=%d Y=%d [%d]  " $MOUSEX $MOUSEY $BUTTON
          ;;
  esac

done
