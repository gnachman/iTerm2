#!/bin/bash
read_bytes()
{
  numbytes=$1
  dd bs=1 count=$numbytes 2>/dev/null
}

ordinal_for_byte()
{
  echo -n $1 | od -t u1 -A n | sed -e 's/^ *//' | sed -e 's/  / /g' | sed -e 's/ *$//' | head -1
}

ordinal_for_next_byte_of_input()
{
  c=$(read_bytes 1)
  ordinal_for_byte "$c"
}

read_bytes()
{
  numbytes=$1
  dd bs=1 count=$numbytes 2>/dev/null
}

read_osc()
{
  # esc ] 1337 ;
  read_bytes 7
  data=""
  b=$(read_bytes 1)
  while [ $(ordinal_for_byte "$b") -ne 7 ]; do
    data="$data""$b"
    b=$(read_bytes 1)
  done
  echo "$data"
}

_STTY=$(stty -g)      ## Save current terminal setup
stty -echo -icanon raw    ## Turn off line buffering

echo -n ']1337;NativeView='
echo -n '{ "app": "Interactive", "arguments": { "url": "'"$1"'" } }' | base64
echo -n ''

while true; do
  data="$(read_osc)"
  identifier=$(echo -n "$data" | sed -Ee 's/1337;NativeViewHeightChange=([^;]+);.*/\1/')
  proposed=$(echo -n "$data" | sed -Ee 's/1337;NativeViewHeightChange=[^;]+;([0-9]+).*/\1/')

  echo -n "]1337;NativeViewHeightAccepted=${identifier};${proposed}"
done

stty "$_STTY"            ## Restore terminal settings

