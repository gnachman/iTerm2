
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
mv=9  ## mv=1000 for press and release reporting; mv=9 for press only

trap clean_up EXIT

_STTY=$(stty -g)      ## Save current terminal setup
stty -echo -icanon    ## Turn off line buffering
printf "${ESC}[?${mv}h        "   ## Turn on mouse reporting
printf "${ESC}[?25l"  ## Turn off cursor

while :
do
  [ $mv -eq 9 ] && mv_str="Show Press & Release" || mv_str="Show Press Only"
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
                         [ $mv -eq 9 ] && mv=1000 || mv=9
                         printf "${ESC}[?${mv}h"
                         [ $mv -eq 1000 ] && x=$(dd bs=1 count=6 2>/dev/null)
                         ;;
                      2) break ;;
                 esac
                 ;;
       *) printat $MOUSEY $MOUSEX
          printf "X=%d Y=%d [%d]  " $MOUSEX $MOUSEY $BUTTON
          ;;
  esac

done

